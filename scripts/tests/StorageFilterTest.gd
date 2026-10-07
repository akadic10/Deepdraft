extends "res://scripts/tests/ZoneWindowTest.gd"

const PINE := "base:resources:wood:pine_log"
const STAVE := "base:resources:wood:oak_stave"
var _next_source := 30
var _completed_stages := 0


func _run() -> void:
	if not "/storage_filter_review/" in OS.get_user_data_dir().replace("\\", "/"):
		push_error("StorageFilterTest requires isolated APPDATA under tmp/storage_filter_review.")
		quit(1)
		return
	create_timer(90).timeout.connect(func(): push_error("Storage filter test timed out"); quit(1))
	await _setup_fixture()
	await _rules_and_incoming()
	await _relocation_transactions()
	await _real_relocation()
	await _ui_and_persistence()
	_expect(_completed_stages == 4, "all test stages reached their final assertion")
	if failures.is_empty():
		print("STORAGE_FILTERS_OK: exact/category/mixed rules, live cancellation, ground/container relocation, claims, partial crates, save migration, native inspector controls and responsive layout")
	else:
		for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)


func _rules_and_incoming() -> void:
	zone.set_all_accepted(false)
	zone.set_item_accepted(LOG, true)
	_expect(zone.accepts_key(LOG) and not zone.accepts_key(PINE) and not zone.accepts_key(STAVE) and not zone.accepts_key(ACORN), "oak-only means exact log identity")
	zone.set_category_accepted("stockpile_stone", true)
	_expect(zone.accepts_key(STONE) and zone.accepts_key(LOG) and not zone.accepts_key(PINE), "category and individual rules combine")
	zone.set_category_accepted("stockpile_wood", true)
	zone.set_item_accepted(PINE, false)
	var roundtrip: Dictionary = JSON.parse_string(JSON.stringify(zone.serialize_filter()))
	zone.restore_filter(roundtrip)
	_expect(zone.accepts_key(LOG) and not zone.accepts_key(PINE), "category exclusion survives JSON roundtrip")
	zone.restore_filter({})
	_expect(zone.accepts_key(PINE) and zone.accepts_key(ACORN), "legacy missing rules accept all")
	zone.restore_filter({"tags": ["stockpile_stone"]})
	_expect(zone.accepts_key(STONE) and not zone.accepts_key(LOG), "legacy category subset remains a subset")
	zone.set_all_accepted(false)
	_expect(zone.reserve_haul(101, Vector3i.ZERO, {}).is_empty(), "no filters means no hauling")
	await _new_trip(LOG, 1)
	_expect(await _until(worker.TaskPhase.HAUL_PICKUP), "worker reaches item before filter edit")
	zone.set_all_accepted(false)
	_expect(zone._pulls.is_empty() and zone.reserved_cells.is_empty() and _loose_units() == 1, "edit before contact frees reservations without moving item")
	zone.set_item_accepted(LOG, true)
	_expect(await _until(worker.TaskPhase.HAUL_TO_ZONE), "worker picks accepted log up")
	zone.set_category_accepted("stockpile_stone", true)
	_expect(worker._carried_entries.size() == 1 and _loose_units() == 0, "compatible delivery continues through an unrelated filter edit")
	zone.set_all_accepted(false)
	_expect(worker._carried_entries.is_empty() and _loose_units() == 1 and zone.stored_count() == 0, "edit during delivery safely drops carried goods")
	_expect(zone._reserve_deposit(LOG, Vector3i.ZERO, 101) == null, "direct incoming reservation also enforces filter")
	_completed_stages += 1


func _clean_trip() -> void:
	await _new_trip()
	for node: Node3D in drops._loose.keys():
		drops.take(node)
		node.free()
	await process_frame


func _other_zone(count := 2):
	_next_source += 1
	var result = load("res://scripts/components/StockpileZoneComponent.gd").new()
	var cells: Array[Vector3i] = []
	for x in range(count): cells.append(Vector3i(47 + x, 20, 44))
	result.setup(_next_source, cells)
	stockpiles.register_zone(result)
	return result


func _container(shelf := false, at := Vector3i(45,20,42)):
	var definition := {"storage": {"capacity": 3, "render_contents": shelf,
		"anchors": [[0,1,0],[0,2,0],[0,3,0]]}}
	var result = load("res://scripts/components/ContainerStorageComponent.gd").new()
	var cells: Array[Vector3i] = [at]
	result.setup_container(definition, cells)
	result.source_id = tasks.allocate_source_id()
	result.display_parent = Node3D.new()
	scene.add_child(result.display_parent)
	result.display_parent.position = Vector3(at) + Vector3(.5,1,.5)
	stockpiles.register_container(result)
	return result


func _seed(owner, key: String, count: int) -> void:
	if owner.get_script().resource_path.ends_with("StockpileZoneComponent.gd"):
		owner.cell_stacks[owner.tile_cells[0]] = {"item": key, "count": count}
		drops.restore_stored_item(key, owner.tile_cells[0], count)
	else:
		owner.restore_inventory({key: count}, drops)
	stockpiles.rebuild_totals()


func _relocation_transactions() -> void:
	await _clean_trip()
	_seed(zone, ACORN, 12)
	zone.set_all_accepted(false)
	_expect(zone.stored_count() == 12 and _loose_units() == 0, "no destination leaves rejected goods physically stored")
	var target = _container(true)
	_seed(target, ACORN, 71) # Three slots: 24 + 24 + 23, room for one.
	var pull: Dictionary = target.reserve_haul(201, Vector3i(40,20,40), {})
	_expect(not pull.is_empty() and zone.stored_count() == 12, "destination reserves before source loses ownership")
	_expect(target._pulls[201].transfer.token.count == 1, "relocation reserves only the remaining crate space")
	_expect(target.reserve_haul(202, Vector3i.ZERO, {}).is_empty(), "concurrent hauler cannot overbook destination")
	var spare = _other_zone()
	_expect(spare.reserve_haul(203, Vector3i.ZERO, {}).is_empty(), "another destination cannot claim same outgoing stack")
	_expect(drops.serialize_state().loose.is_empty() and drops.get_inventory_items().carried.is_empty(), "handoff marker never appears in physical inventory or save")
	var cargo: Node3D = target.take_item(201, 0)
	_expect(cargo != null and drops.quantity_of(cargo) == 1 and zone.stored_count() == 11, "source crate splits at pickup contact")
	_expect(target.commit_haul(201, [[cargo, ACORN]]) and target.stored_count() == 72, "shelf refill conserves goods and physical slots")
	_expect(target.occupied_slots() == 3 and stockpiles.get_total(ACORN) == 83, "totals remain 83 goods across four stacks")
	await process_frame
	var token_pull: Dictionary = spare.reserve_haul(204, Vector3i.ZERO, {})
	_expect(not token_pull.is_empty() and zone.withdraw_nearest(ACORN, Vector3i.ZERO, 299) == null, "fetch cannot steal a fully claimed stack")
	spare.cancel_haul(204)
	spare.cancel_haul(204)
	_expect(zone._outgoing.is_empty() and zone.stored_count() == 11, "cancelling an outgoing claim is idempotent and preserves source")
	spare.reserve_haul(205, Vector3i.ZERO, {})
	zone.set_all_accepted(true)
	_expect(spare.take_item(205, 0) == null and zone.stored_count() == 11, "source rule reversal invalidates an unpicked relocation")
	spare.cancel_haul(205)
	zone.set_all_accepted(false)
	spare.reserve_haul(206, Vector3i.ZERO, {})
	stockpiles.deregister_zone(zone)
	_expect(spare.take_item(206, 0) == null and _loose_units() == 11, "source removal releases actual goods exactly once")
	spare.cancel_haul(206)
	# A removed destination releases its source even when no live worker can
	# run abort_task (the same case as a worker removed from the scene).
	zone = _other_zone()
	_seed(zone, ACORN, 3)
	zone.set_all_accepted(false)
	var disappearing = _container(false, Vector3i(53,20,44))
	disappearing.reserve_haul(299, Vector3i.ZERO, {})
	# The earlier removal left loose goods: consume those first, then reserve
	# directly from stored goods once that pull has been released.
	disappearing.cancel_haul(299)
	for item in drops._loose.keys():
		drops.take(item)
		item.free()
	disappearing.reserve_haul(299, Vector3i.ZERO, {})
	_expect(not zone._outgoing.is_empty(), "destination owns an outgoing source claim")
	stockpiles.deregister_container(disappearing)
	_expect(zone._outgoing.is_empty() and disappearing._pulls.is_empty() and zone.stored_count() == 3, "destination removal releases orphaned claims")
	await _clean_trip()
	var origin = _container(true)
	_seed(origin, ACORN, 17)
	origin.set_all_accepted(false)
	zone.reserve_haul(207, Vector3i.ZERO, {})
	cargo = zone.take_item(207, 0)
	_expect(cargo != null and origin.stored_count() == 0, "shelf source withdraws real cargo at contact")
	_expect(zone.commit_haul(207, [[cargo, ACORN]]) and zone.stored_count() == 17, "shelf-to-ground delivery preserves quantity")
	await process_frame
	_expect(origin.display_parent.get_child_count() == 0, "empty shelf removes its anchored visual")
	var chest = _container(false, Vector3i(51,20,42))
	zone.set_all_accepted(false)
	chest.reserve_haul(208, Vector3i.ZERO, {})
	cargo = chest.take_item(208, 0)
	_expect(chest.commit_haul(208, [[cargo, ACORN]]) and chest.stored_count() == 17, "ground-to-closed-container delivery preserves quantity")
	chest.set_all_accepted(false)
	origin.set_all_accepted(true)
	origin.reserve_haul(209, Vector3i.ZERO, {})
	cargo = origin.take_item(209, 0)
	_expect(origin.commit_haul(209, [[cargo, ACORN]]) and origin.stored_count() == 17 and chest.stored_count() == 0, "closed-container-to-shelf relocation preserves quantity")
	await process_frame
	_completed_stages += 1


func _advance_to(phase: int, limit := 800) -> bool:
	for i in range(limit):
		if worker._task_phase == phase: return true
		stockpiles._process(.25)
		tasks._run_scheduler()
		worker._process(.04)
		await process_frame
	return false


func _real_relocation() -> void:
	await _clean_trip()
	_seed(zone, ACORN, 12)
	zone.set_all_accepted(false)
	var target = _container(true)
	_expect(await _advance_to(worker.TaskPhase.HAUL_PICKUP), "real scheduler sends worker to rejected stored goods")
	_expect(zone.stored_count() == 12 and worker._carried_entries.is_empty(), "source owns goods through reach animation")
	_expect(await _advance_to(worker.TaskPhase.HAUL_TO_ZONE), "relocation picks up at contact and walks to container")
	_expect(zone.stored_count() == 0 and _snapshot_units() == 12, "carried snapshot owns all goods after source withdrawal")
	_expect(await _advance_to(worker.TaskPhase.HAUL_DEPOSIT), "relocation reaches a valid container handoff stand")
	worker._process(1.0)
	await process_frame
	_expect(target.stored_count() == 12 and _snapshot_units() == 0, "real worker completes relocation without duplication")
	zone.set_all_accepted(true)
	target.set_all_accepted(false)
	_expect(await _advance_to(worker.TaskPhase.HAUL_TO_ZONE), "worker picks up from a container for reverse relocation")
	zone.set_all_accepted(false)
	_expect(worker._carried_entries.is_empty() and _loose_units() == 12, "interrupting a real relocation releases and drops the whole crate")
	_completed_stages += 1


func _ui_and_persistence() -> void:
	await _clean_trip()
	root.size = Vector2i(1280, 720)
	_build_windows(true)
	var cells: Array[Vector3i] = [Vector3i(56,20,44), Vector3i(57,20,44), Vector3i(58,20,44)]
	storage._create_zone(cells, 501)
	var subject = storage._zones[501]
	_seed(subject, PINE, 1)
	storage._open_zone_window(501)
	await _settle()
	var panel = storage._storage_panel
	var probe := InputProbe.new()
	scene.add_child(probe)
	_click(panel._none.get_global_rect().get_center())
	panel.set_category("stockpile_wood")
	await _settle()
	_click(panel._tiles[LOG].button.get_global_rect().get_center())
	await _settle()
	_expect(subject.accepts_key(LOG) and not subject.accepts_key(PINE), "native item click immediately writes exact acceptance")
	_expect("some selected" in panel._group.text and "Oak Log" in panel._summary.text, "category partial state and summary reflect selected log")
	_expect(panel._waiting.visible and subject.stored_count() == 1, "filter change displays waiting goods without ejecting them")
	_expect(probe.clicks == 0, "filter clicks do not reach world input")
	_click(panel._group.get_global_rect().get_center())
	await _settle()
	_expect(subject.accepts_key(PINE) and subject.accepts_key(STAVE), "native category click replaces individual exceptions")
	_click(panel._all.get_global_rect().get_center())
	await _settle()
	_expect(subject.accepts_key(STONE) and subject.accepts_key(ACORN), "native Accept all button restores every category")
	_click(panel._none.get_global_rect().get_center())
	await _settle()
	_click(panel._tiles[LOG].button.get_global_rect().get_center())
	await _settle()
	var saved: Dictionary = JSON.parse_string(JSON.stringify(storage.serialize_state()))
	storage.remove_zone(501)
	storage.restore_state(saved)
	subject = storage._zones[501]
	_expect(subject.accepts_key(LOG) and not subject.accepts_key(PINE) and subject.stored_count() == 1, "zone rules and rejected contents survive controller save/load")
	storage._open_zone_window(501)
	await _settle()
	var window: UIWindow = storage._window_panel
	var before := window.position
	_drag_title(window, Vector2(50, 10))
	_expect(window.position.x == before.x + 50, "storage inspector keeps native dragging")
	_click(panel._tabs[1].get_global_rect().get_center())
	await _settle()
	_expect(panel._contents.visible and not panel._grid.visible and "1 / 3 cells" in panel.info_label.text, "contents tab keeps capacity visible")
	if "--capture" in OS.get_cmdline_user_args(): await _capture_storage("storage-contents")
	_click(panel._tabs[0].get_global_rect().get_center())
	await _settle()
	if "--capture" in OS.get_cmdline_user_args(): await _capture_storage("storage-filters")
	for viewport in [Vector2i(960,540), Vector2i(1280,720), Vector2i(2560,1440)]:
		root.size = viewport
		await _settle()
		_expect(window.position.y + window.size.y <= viewport.y and window.position.x + window.size.x <= viewport.x, "storage window fits %s" % str(viewport))
		_expect(panel._scroll.size.y >= 68 and panel._actions.get_global_rect().end.y < viewport.y, "scrolling item grid preserves footer at %s" % str(viewport))
		if "--capture" in OS.get_cmdline_user_args(): await _capture_storage("storage-%dx%d" % [viewport.x,viewport.y])
	root.size = Vector2i(1280,720)
	manager.close(storage.ZONE_WINDOW_ID)
	furniture = load("res://scripts/systems/FurniturePlacementController.gd").new()
	furniture.name = "Furniture"
	scene.add_child(furniture)
	furniture.set_process(false)
	furniture._process(0)
	explorer = load("res://scripts/ui/ObjectExplorerController.gd").new()
	explorer.window_manager_path = NodePath("../Windows")
	scene.add_child(explorer)
	for key in ["base:furniture:storage_chest", "base:furniture:barrel", "base:furniture:storage_shelf"]:
		var id: int = furniture._next_installed_id
		furniture._install(key, furniture.get_defs()[key], Vector3i(65 + id*3,20,48), 0)
		var piece = furniture._installed[id]
		piece.storage.set_all_accepted(false)
		piece.storage.set_category_accepted("stockpile_stone", true)
		piece.storage.set_item_accepted(LOG, true)
		_expect(explorer.select_object(furniture, "installed:%d" % id), "installed storage is selectable: " + key)
		await _settle()
		_expect(explorer._storage_panel.visible and explorer._storage_panel.storage == piece.storage, "same inspector binds container: " + key)
	var furniture_save: Dictionary = JSON.parse_string(JSON.stringify(furniture.serialize_state()))
	for entry: Dictionary in furniture_save.installed:
		_expect(entry.storage_filter.tags == ["stockpile_stone"] and entry.storage_filter.items == [LOG], "each installed container saves mixed rules")
	var restored = load("res://scripts/systems/FurniturePlacementController.gd").new()
	scene.add_child(restored)
	restored.set_process(false)
	restored.restore_state(furniture_save)
	for piece in restored._installed.values():
		_expect(piece.storage.accepts_key(LOG) and piece.storage.accepts_key(STONE) and not piece.storage.accepts_key(PINE), "container rules restore through owner")
	if "--capture" in OS.get_cmdline_user_args(): await _capture_storage("storage-container")
	await _settle()
	_completed_stages += 1


func _capture_storage(file: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tmp/storage_filter_review/%s.png" % file)
