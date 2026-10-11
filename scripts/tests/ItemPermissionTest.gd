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
	zone.set_disallowed(slot,true)
	_expect(stockpiles.get_total(ACORN)==12 and stockpiles.get_available_total(ACORN)==0, "blocked stored goods stay in total inventory")
	_expect(zone.withdraw_stack(slot,12,999)==null, "ground storage rejects forbidden withdrawal")
	_expect(zone._slots.room(ACORN,slot)==0, "no topping up forbidden crate")
	zone.set_disallowed(slot,false)
	_expect(stockpiles.get_available_total(ACORN)==12, "allow restores stored availability")
	# Separate permission for two crates of the same resource; shelf and chest.
	for shelf in [false,true]:
		var container = _container(shelf,Vector3i(50,20,42))
		container.restore_inventory({ACORN:15},drops,[{"item":ACORN,"count":7,"disallowed":true},{"item":ACORN,"count":8,"disallowed":false}])
		_expect(container.occupied_slots()==2, "restore does not merge differently permitted stacks")
		var blocked_slot = -1
		for s in container.stored_entries():
			if not container.slot_allowed(s): blocked_slot=s
		_expect(blocked_slot>=0 and container.withdraw_stack(blocked_slot,1,999)==null, "container blocks exact forbidden stack")
		var returned = container.withdraw_nearest(ACORN,Vector3i.ZERO,999)
		_expect(returned!=null and drops.quantity_of(returned)==1 and drops.Permission.allowed(returned), "container selects allowed unit of same type")
		drops.unreserve(returned,999)
		container.dump_contents(Vector3i(50,20,42))
		var forbidden := 0
		for node in drops._loose:
			if not drops.Permission.allowed(node): forbidden+=drops.quantity_of(node)
		_expect(forbidden==7 if not shelf else forbidden==14, "removing storage preserves blocked goods")
		stockpiles.deregister_container(container)
	if "--capture" in OS.get_cmdline_user_args(): await _review_permission_ui()
	if failures.is_empty(): print("ITEM_PERMISSIONS_OK: quotes, pickup/contact cancellation, carried release, ground/chest/shelf flags and ownership")
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _review_permission_ui() -> void:
	_build_windows(true)
	var cells: Array[Vector3i] = [Vector3i(56,20,44),Vector3i(57,20,44)]
	storage._create_zone(cells,501)
	var subject = storage._zones[501]
	_seed(subject,ACORN,7)
	storage._open_zone_window(501)
	var panel = storage._storage_panel
	panel._show_tab(1)
	await _settle()
	_click(_button_named(panel._contents,"Disallow").get_global_rect().get_center())
	await _settle()
	_expect(not subject.slot_allowed(cells[0]),"storage Contents click changes permission")
	for size in [Vector2i(960,540),Vector2i(2560,1440)]:
		root.size=size
		await _settle()
		_expect(storage._window_panel.get_global_rect().end.y<=size.y,"per-stack controls fit viewport")
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tmp/water_review/storage_disallow_%dx%d.png" % [size.x,size.y])
	_click(_button_named(panel._contents,"Allow").get_global_rect().get_center())
	await _settle()
	_expect(subject.slot_allowed(cells[0]),"Contents Allow releases stored goods")
