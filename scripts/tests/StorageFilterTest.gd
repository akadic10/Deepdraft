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
		print("STORAGE_FILTERS_OK: exact/category/mixed rules, live cancellation, stockpile relocation, claims, partial crates, filter save/restore, native inspector controls and responsive layout")
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
	zone.restore_filter({"tags": ["stockpile_stone"], "items": [], "excluded_items": []})
	_expect(zone.accepts_key(STONE) and not zone.accepts_key(LOG), "restored category subset remains a subset")
	zone.restore_filter({"tags": [], "items": [], "excluded_items": []})
	_expect(not zone.accepts_key(STONE) and not zone.accepts_key(ACORN), "explicit empty rules accept nothing")
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


func _other_zone(count := 2, at := Vector3i(47,20,44)):
	_next_source += 1
	var result = load("res://scripts/components/StockpileZoneComponent.gd").new()
	var cells: Array[Vector3i] = []
	for x in range(count): cells.append(at + Vector3i(x, 0, 0))
	result.setup(_next_source, cells)
	stockpiles.register_zone(result)
	return result


## Seeds one stored crate per count, starting at the zone's first cell.
func _seed(owner, key: String, count: int, more: Array = []) -> void:
	var counts: Array = [count] + more
	for i in range(counts.size()):
		var cell: Vector3i = owner.tile_cells[i]
		owner.cell_stacks[cell] = {"item": key, "count": int(counts[i])}
		drops.restore_stored_item(key, cell, int(counts[i]))
	stockpiles.rebuild_totals()


func _relocation_transactions() -> void:
	await _clean_trip()
	_seed(zone, ACORN, 12)
	zone.set_all_accepted(false)
	_expect(zone.stored_count() == 12 and _loose_units() == 0, "no destination leaves rejected goods physically stored")
	var target = _other_zone(3, Vector3i(47,20,46))
	_seed(target, ACORN, 24, [24, 23]) # Three crates: 24 + 24 + 23, room for one.
	var pull: Dictionary = target.reserve_haul(201, Vector3i(40,20,40), {})
	_expect(not pull.is_empty() and zone.stored_count() == 12, "destination reserves before source loses ownership")
	_expect(target._pulls[201].transfer.token.count == 1, "relocation reserves only the remaining crate space")
	_expect(target.reserve_haul(202, Vector3i.ZERO, {}).is_empty(), "concurrent hauler cannot overbook destination")
	var spare = _other_zone(2, Vector3i(47,20,48))
	_expect(spare.reserve_haul(203, Vector3i.ZERO, {}).is_empty(), "another destination cannot claim same outgoing stack")
	_expect(drops.serialize_state().loose.is_empty() and drops.get_inventory_items().carried.is_empty(), "handoff marker never appears in physical inventory or save")
	var cargo: Node3D = target.take_item(201, 0)
	_expect(cargo != null and drops.quantity_of(cargo) == 1 and zone.stored_count() == 11, "source crate splits at pickup contact")
	_expect(target.commit_haul(201, [[cargo, ACORN]]) and target.stored_count() == 72, "partial crate refill conserves goods")
	_expect(target.cell_stacks.size() == 3 and stockpiles.get_total(ACORN) == 83, "totals remain 83 goods across four stacks")
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
	zone = _other_zone(2, Vector3i(51,20,46))
	_seed(zone, ACORN, 3)
	zone.set_all_accepted(false)
	var disappearing = _other_zone(2, Vector3i(51,20,48))
	disappearing.reserve_haul(299, Vector3i.ZERO, {})
	# The earlier removal left loose goods: consume those first, then reserve
	# directly from stored goods once that pull has been released.
	disappearing.cancel_haul(299)
	for item in drops._loose.keys():
		drops.take(item)
		item.free()
	disappearing.reserve_haul(299, Vector3i.ZERO, {})
	_expect(not zone._outgoing.is_empty(), "destination owns an outgoing source claim")
	stockpiles.deregister_zone(disappearing)
	_expect(zone._outgoing.is_empty() and disappearing._pulls.is_empty() and zone.stored_count() == 3, "destination removal releases orphaned claims")
	await _clean_trip()
	var origin = _other_zone(2, Vector3i(47,20,46))
	_seed(origin, ACORN, 17)
	origin.set_all_accepted(false)
	zone.reserve_haul(207, Vector3i.ZERO, {})
	cargo = zone.take_item(207, 0)
	_expect(cargo != null and origin.stored_count() == 0, "stockpile source withdraws real cargo at contact")
	_expect(zone.commit_haul(207, [[cargo, ACORN]]) and zone.stored_count() == 17, "stockpile-to-stockpile delivery preserves quantity")
	zone.set_all_accepted(false)
	origin.set_all_accepted(true)
	origin.reserve_haul(208, Vector3i.ZERO, {})
	cargo = origin.take_item(208, 0)
	_expect(origin.commit_haul(208, [[cargo, ACORN]]) and origin.stored_count() == 17 and zone.stored_count() == 0, "reverse relocation preserves quantity")
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
	var target = _other_zone(2, Vector3i(47,20,46))
	_expect(await _advance_to(worker.TaskPhase.HAUL_PICKUP), "real scheduler sends worker to rejected stored goods")
	_expect(zone.stored_count() == 12 and worker._carried_entries.is_empty(), "source owns goods through reach animation")
	_expect(await _advance_to(worker.TaskPhase.HAUL_TO_ZONE), "relocation picks up at contact and walks to the accepting stockpile")
	_expect(zone.stored_count() == 0 and _snapshot_units() == 12, "carried snapshot owns all goods after source withdrawal")
	_expect(await _advance_to(worker.TaskPhase.HAUL_DEPOSIT), "relocation reaches a valid delivery stand")
	worker._process(1.0)
	await process_frame
	_expect(target.stored_count() == 12 and _snapshot_units() == 0, "real worker completes relocation without duplication")
	zone.set_all_accepted(true)
	target.set_all_accepted(false)
	_expect(await _advance_to(worker.TaskPhase.HAUL_TO_ZONE), "worker picks up from the other stockpile for reverse relocation")
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
	# The picture filter (doc 261): the band names the zone; groups of category pictures.
	_expect(storage._window_panel.get_title_label().text == "Storage Zone 501", "the window's band names the zone")
	_expect(panel._rows.size() == 3 and panel.get_category_tile("stockpile_wood") != null and panel.get_category_tile("stockpile_misc") != null,
		"the categories show as pictures in three groups")
	_expect(panel.get_category_tile("stockpile_stone").get_node("Mark").get_global_rect().position.y >= panel._scroll.get_global_rect().position.y,
		"the top row's marks show whole inside the filter")
	_click(panel._none.get_global_rect().get_center())
	await _settle()
	_expect(_state_of(panel._rows.materials) == "None" and panel.get_category_tile("stockpile_wood").get_node_or_null("Mark") == null,
		"None leaves every group and picture unmarked")
	_click(_caption_of(panel._rows.materials, "stockpile_wood").get_global_rect().get_center())
	await _settle()
	_expect(panel.category == "stockpile_wood" and panel._exact.visible and panel._exact.get_index() == panel._rows.materials.get_index() + 1,
		"a category's name opens its exact goods under its group")
	_click(panel._exact_grid.get_tile(LOG).get_global_rect().get_center())
	await _settle()
	_expect(subject.accepts_key(LOG) and not subject.accepts_key(PINE), "native item click immediately writes exact acceptance")
	_expect(panel.category_state("stockpile_wood") == "some" and panel.get_category_tile("stockpile_wood").get_node("Mark").get_child(0).text == "−"
		and _state_of(panel._rows.materials) == "Some", "the partial category is marked − and its group says Some")
	_expect(panel._waiting.visible and subject.stored_count() == 1, "filter change displays waiting goods without ejecting them")
	_expect(probe.clicks == 0, "filter clicks do not reach world input")
	_click(panel.get_category_tile("stockpile_wood").get_global_rect().get_center())
	await _settle()
	_expect(subject.accepts_key(PINE) and subject.accepts_key(STAVE), "a click on the category's picture replaces individual exceptions")
	_click(_state_button(panel._rows.materials).get_global_rect().get_center())
	await _settle()
	_expect(subject.accepts_key(STONE) and subject.accepts_key(PINE) and not subject.accepts_key(ACORN)
		and _state_of(panel._rows.materials) == "All", "a group's state stores every category in the group")
	_click(panel._all.get_global_rect().get_center())
	await _settle()
	_expect(subject.accepts_key(STONE) and subject.accepts_key(ACORN), "native All restores every category")
	_click(panel._none.get_global_rect().get_center())
	await _settle()
	_click(panel._exact_grid.get_tile(LOG).get_global_rect().get_center())
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
	_expect(panel._tab_row.get_global_rect().position.y >= window.get_global_rect().end.y - 8.0, "Filter and Contents hang under the window")
	_click(panel._tabs[1].get_global_rect().get_center())
	await _settle()
	_expect(panel._contents_page.visible and not panel._filter.visible and "Used 1 / 3 cells" in panel.info_label.text, "contents tab keeps capacity visible")
	var stored: Button = panel._contents.find_children("Tile_*", "Button", true, false)[0]
	_expect(stored.has_node("Count") and stored.get_node("Count").text == "1" and stored.has_node("Mark"), "Contents shows the pine log with its count, marked as awaiting relocation")
	_click(stored.get_global_rect().get_center())
	await _settle()
	_expect(panel._filter.visible and panel.category == "stockpile_wood", "a stored good's picture opens its category in the filter")
	_click(panel._tabs[1].get_global_rect().get_center())
	await _settle()
	if "--capture" in OS.get_cmdline_user_args(): await _capture_storage("storage-contents")
	_click(panel._tabs[0].get_global_rect().get_center())
	await _settle()
	if "--capture" in OS.get_cmdline_user_args(): await _capture_storage("storage-filters")
	for viewport in [Vector2i(960,540), Vector2i(1280,720), Vector2i(2560,1440)]:
		root.size = viewport
		await _settle()
		_expect(window.position.y + window.size.y <= viewport.y and window.position.x + window.size.x <= viewport.x, "storage window fits %s (window %s)" % [viewport, window.get_global_rect()])
		_expect(panel._scroll.size.y >= 68 and panel._actions.get_global_rect().end.y < viewport.y, "scrolling item grid preserves footer at %s" % str(viewport))
		_expect(panel._tab_row.get_global_rect().end.y <= viewport.y, "the hanging tabs stay on screen at %s" % str(viewport))
		if "--capture" in OS.get_cmdline_user_args(): await _capture_storage("storage-%dx%d" % [viewport.x,viewport.y])
	root.size = Vector2i(1280,720)
	manager.close(storage.ZONE_WINDOW_ID)
	await _settle()
	await _storage_keeps_its_window(cells[2])
	_completed_stages += 1


## Bare terrain under the zone, as TerrainExplorerProvider reports it in the game.
class TerrainStub extends Node:
	var picking = load("res://scripts/components/ObjectPicking.gd")
	func developer_inspection_active() -> bool: return false
	func terrain_hit(start: Vector3, direction: Vector3, slice_y: int, limit: float) -> Dictionary:
		return picking.terrain_hit(start, direction, slice_y, limit)


## Doc 260 phase 6: every world object shows in the compact panel, but a click on a
## storage zone still opens the storage window, through the explorer as in the game.
func _storage_keeps_its_window(cell: Vector3i) -> void:
	storage.name = "Storage"
	var terrain := TerrainStub.new()
	terrain.name = "Terrain"
	scene.add_child(terrain)
	explorer = load("res://scripts/ui/ObjectExplorerController.gd").new()
	explorer.window_manager_path = NodePath("../Windows")
	explorer.terrain_provider_path = NodePath("../Terrain")
	explorer.click_tool_paths.append(NodePath("../Storage"))
	scene.add_child(explorer)
	camera = Camera3D.new()
	scene.add_child(camera)
	camera.current = true
	var generator = root.get_node("WorldGenerator")
	generator._maps_ready = true
	var target := Vector3(cell) + Vector3(.5, 1, .5)
	_aim_above(target)
	await _settle()
	_click(camera.unproject_position(target))
	await _settle()
	_expect(manager.is_open(storage.ZONE_WINDOW_ID) and storage._window_zone_id == 501, "a click on the zone opens the storage window")
	_expect(not explorer.get_compact_panel().visible and not manager.is_open(explorer.WINDOW_ID), "storage never opens the compact panel or the character sheet")
	_expect(storage._window_panel.get_theme_stylebox("panel", "TooltipPanel") == UITheme.cell_style("card", UITheme.CARD_CELL),
		"the storage window's tooltips are the hover card's hearth slab")
	manager.close(storage.ZONE_WINDOW_ID)
	generator._maps_ready = false
	for node: Node in [camera, explorer, terrain]: node.free()
	await _settle()


## A group's All, Some or None, as its row shows it.
func _state_of(row: Node) -> String:
	var button := _state_button(row)
	return button.text if button != null else ""


func _state_button(row: Node) -> Button:
	for button: Button in row.find_children("*", "Button", true, false):
		if button.text in ["All", "Some", "None"]: return button
	return null


## The name under a category's picture, which opens its exact goods.
func _caption_of(row: Node, tag: String) -> Button:
	return row.get_tile(tag).get_parent().get_child(1)


func _capture_storage(file: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tmp/storage_filter_review/%s.png" % file)
