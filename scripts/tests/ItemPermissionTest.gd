extends "res://scripts/tests/StorageFilterTest.gd"

func _run() -> void:
	create_timer(90).timeout.connect(func(): push_error("Item permissions timed out"); quit(1))
	await _setup_fixture()
	var item: Node3D = drops._loose.keys()[0]
	drops.set_disallowed(item,true)
	_expect(drops.count_loose(["stockpile_seed"],100)==0 and not drops.reserve(item,999), "blocked goods excluded from stock and claims")
	_expect(drops.take(item).is_empty() and drops.take_quantity(item,1,999)==null, "blocked goods rejected at pickup contact")
	var quote := {}
	var keys: Array[String] = [ACORN]
	drops.advance_material_quote(keys,worker.current_cell(),quote,Time.get_ticks_usec()+100000,{})
	_expect(quote.best.is_empty(), "crafting and promotion quotes exclude blocked items")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(drops.serialize_state()))
	_expect(saved.loose[0].disallowed, "loose save keeps flag")
	drops.set_disallowed(item,false)
	_expect(await _until(worker.TaskPhase.HAUL_PICKUP), "allow wakes a real haul")
	drops.set_disallowed(item,true)
	_expect(worker.current_task_id<0 and zone._pulls.is_empty() and zone.reserved_cells.is_empty(), "disallow at pickup cancels haul and reservations")
	_expect(_loose_units()==12, "uncollected crate stays intact")
	drops.set_disallowed(item,false)
	_expect(await _until(worker.TaskPhase.HAUL_TO_ZONE), "allowed goods collected")
	drops.set_disallowed(item,true)
	_expect(worker._carried_entries.is_empty() and _loose_units()==12, "disallow carried goods drops them safely")
	_expect(not drops.Permission.allowed(item), "drop retains flag")
	drops.set_disallowed(item,false)
	_expect(await _until(worker.TaskPhase.HAUL_DEPOSIT), "allowed cargo reaches storage")
	worker._process(1)
	var slot = zone.cell_stacks.keys()[0]
	var stored_item: Node3D = drops.stored_node_at(slot)
	drops.set_disallowed(stored_item,true)
	_expect(drops.Permission.allowed(stored_item) and zone.slot_allowed(slot), "stored goods cannot be disallowed through a stale action")
	_expect(stockpiles.get_total(ACORN)==12 and stockpiles.get_available_total(ACORN)==12, "stored goods remain available colony stock")
	_expect(zone._slots.room(ACORN,slot)==12, "stored crates accept matching top-ups")
	_expect(not _has_permission_action(drops.get_explorer_data(stored_item)), "stored object inspector has no permission action")
	var withdrawn: Node3D = zone.withdraw_stack(slot,12,999)
	_expect(withdrawn==stored_item and drops.Permission.allowed(withdrawn), "ground storage withdraws the physical crate")
	_expect(_has_permission_action(drops.get_explorer_data(withdrawn)), "permission action returns outside storage")
	drops.unreserve(withdrawn,999)
	# Stored ownership clears permissions in both hidden and visible containers.
	for shelf in [false,true]:
		var container = _container(shelf,Vector3i(50,20,42))
		container.restore_inventory({ACORN:15},drops,[{"item":ACORN,"count":7,"disallowed":true},{"item":ACORN,"count":8,"disallowed":false}])
		_expect(container.occupied_slots()==2, "restore preserves physical crates")
		for s in container.stored_entries():
			_expect(container.slot_allowed(s) and not container.stored_entries()[s].disallowed, "restored storage has no hidden disallowed stock")
			if shelf: _expect(drops.Permission.allowed(container._anchor_slots[s][0]), "shelf visual agrees with stored ownership")
		var returned = container.withdraw_nearest(ACORN,Vector3i.ZERO,999)
		_expect(returned!=null and drops.quantity_of(returned)==1 and drops.Permission.allowed(returned), "container selects available stock")
		drops.unreserve(returned,999)
		_expect(container.dump_contents(Vector3i(50,20,42))==14, "removing storage returns every remaining unit")
		var forbidden := 0
		for node in drops._loose:
			if not drops.Permission.allowed(node): forbidden+=drops.quantity_of(node)
		_expect(forbidden==0, "storage removal releases allowed goods")
		stockpiles.deregister_container(container)
	await _review_storage_contents()
	if failures.is_empty(): print("ITEM_PERMISSIONS_OK: outside-storage controls, pickup/contact cancellation, carried release, grouped material-aware contents, live counts and ground/chest/shelf ownership")
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _has_permission_action(data: Dictionary) -> bool:
	for action: Dictionary in data.get("actions", []):
		if action.id == "permission": return true
	return false


func _review_storage_contents() -> void:
	_build_windows(true)
	var cells: Array[Vector3i] = []
	for x in range(12): cells.append(Vector3i(56+x,20,44))
	storage._create_zone(cells,501)
	var subject = storage._zones[501]
	var chair := "base:resources:furniture:log_chair"
	var pine := "base:material:pine"
	var oak := "base:material:oak"
	for entry in [[PINE,1,""],[ACORN,7,""],[chair,1,pine],[PINE,1,""],
			[chair,1,oak],[ACORN,8,""],[chair,1,pine],[PINE,1,""]]:
		var token: Dictionary = subject._slots.reserve(entry[0],entry[1],-1,Vector3i.ZERO,true,entry[2])
		subject._commit_one(token,entry[0])
		var visual: Node3D = drops.create_item_visual(entry[0],entry[1],"",entry[2])
		subject._place_visual(visual,token)
	stockpiles.rebuild_totals()
	subject.set_item_accepted(PINE,false)
	storage._open_zone_window(501)
	var panel = storage._storage_panel
	panel._show_tab(1)
	await _settle()
	var expected := [["Oak Acorn","× 15"],["Oak log stool (packed)","× 1"],["Pine Log","× 3"],["Pine log stool (packed)","× 2"]]
	_expect(_content_rows(panel)==expected, "Contents groups counts by item and material, sorted by name: " + str(_content_rows(panel)))
	_expect("8 / 12 cells used" in panel.info_label.text and "Goods stored: 21" in panel.info_label.text, "grouping preserves physical capacity and logical goods totals")
	_expect(_button_named(panel._contents,"Disallow")==null and _button_named(panel._contents,"Allow")==null, "Contents has no permission buttons")
	var relocation_labels := 0
	for child in panel._contents.get_children():
		if child is Label and child.text=="Awaiting relocation": relocation_labels+=1
	_expect(relocation_labels==1, "rejected item group has one relocation note")
	for size in [Vector2i(960,540),Vector2i(2560,1440)]:
		root.size=size
		await _settle()
		_expect(storage._window_panel.get_global_rect().end.y<=size.y,"grouped Contents fits viewport")
		if "--capture" in OS.get_cmdline_user_args():
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://tmp/storage_contents_20261011/contents_%dx%d.png" % [size.x,size.y])
	# Withdrawing one of several identical objects updates the existing group.
	var removed: Node3D = subject.withdraw_stack(cells[0],1,999)
	drops.unreserve(removed,999)
	await _settle()
	expected[2][1] = "× 2"
	_expect(_content_rows(panel)==expected and "Goods stored: 20" in panel.info_label.text, "live withdrawal updates grouped totals")
	# The same panel is reused for both container representations.
	for shelf in [false,true]:
		var container = _container(shelf,Vector3i(50,20,42))
		container.restore_inventory({ACORN:15,PINE:1},drops,[{"item":PINE,"count":1},{"item":ACORN,"count":7},{"item":ACORN,"count":8}])
		panel.show_storage(container,[])
		await _settle()
		_expect(_content_rows(panel)==[["Oak Acorn","× 15"],["Pine Log","× 1"]], "container Contents groups separate crates")
		_expect("3 / 3 slots used" in panel.info_label.text, "container capacity still counts occupied slots")
		stockpiles.deregister_container(container)
	# Ground restore also applies current storage access rules to flags in input.
	var saved: Dictionary = storage.serialize_state()
	for entry: Dictionary in saved.zones:
		for stack: Dictionary in entry.stacks: stack["disallowed"] = true
	storage.restore_state(saved)
	for restored in storage._zones.values():
		for cell in restored.cell_stacks:
			_expect(not restored.cell_stacks[cell].disallowed and drops.Permission.allowed(drops.stored_node_at(cell)), "restored ground stock and its visual remain available")


func _content_rows(panel: Control) -> Array:
	var result := []
	for child in panel._contents.get_children():
		if child is HBoxContainer: result.append([child.get_child(0).text,child.get_child(1).text])
	return result
