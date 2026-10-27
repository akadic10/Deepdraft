extends "res://scripts/tests/ObjectExplorerTest.gd"

const TABLE := "base:furniture:log_table"
const CHAIR := "base:furniture:log_chair"
var items
var dock
var catalog

func _run() -> void:
	create_timer(60).timeout.connect(func(): push_error("Place test timed out"); quit(1))
	root.get_node("SaveManager").set_process(false)
	root.get_node("WorldClock").set_paused(true)
	root.get_node("TaskManager").set_process(false)
	root.get_node("RoomManager").set_process(false)
	world = root.get_node("WorldData")
	blocks = root.get_node("BlockRegistry")
	_build_floor()
	root.get_node("WorldGenerator")._maps_ready = true
	root.get_node("WorldGenerator").world_seed = 1234
	root.get_node("WorldGenerator").heightmap.resize(1024 * 1024)
	root.get_node("WorldGenerator").heightmap.fill(20)
	# Cursor rays can reach unloaded columns outside the fixture's floor chunks.
	root.get_node("WorldGenerator").waterline_map.resize(1024 * 1024)
	root.get_node("WorldGenerator").waterline_map.fill(-1)
	scene = Node3D.new()
	root.add_child(scene)
	current_scene = scene
	manager = load("res://scripts/ui/UIWindowManager.gd").new()
	manager.name = "Windows"
	scene.add_child(manager)
	manager._layout_loaded = false
	manager._layout.clear()
	items = load("res://scripts/systems/ItemDropManager.gd").new()
	scene.add_child(items)
	dock = load("res://scripts/ui/DockUI.gd").new()
	dock.name = "Dock"
	dock.window_manager_path = NodePath("../Windows")
	scene.add_child(dock)
	furniture = load("res://scripts/systems/FurniturePlacementController.gd").new()
	furniture.dock_ui_path = NodePath("../Dock")
	scene.add_child(furniture)
	furniture.set_process(false)
	furniture._process(0)
	catalog = dock._place_catalog
	root.size = Vector2i(1280, 720)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 22
	scene.add_child(camera)
	camera.current = true
	camera.position = Vector3(49, 41, 55)
	camera.look_at(Vector3(38,21,38))
	_build_review_world()
	await _settle()
	_click(dock._button_by_target.place.get_global_rect().get_center())
	await _settle()
	_expect(manager.is_open("place") and dock._button_by_target.place.button_pressed, "Place opens a managed catalog")
	_expect(catalog._empty.visible and catalog._place.disabled and not catalog._card.is_visible_in_tree()
		and catalog.selected_key.is_empty(), "no stock shows empty state without unrelated furniture details")
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tmp/place_catalog_review/empty_place.png")
	_expect(catalog._values.Crafting.text == "—", "no fabricated crafting count")
	root.size = Vector2i(960,540)
	await _settle()
	_expect(dock._place_window.get_global_rect().end.y <= dock._dock_panel.position.y - 8,
		"compact empty state leaves the dock accessible")
	root.size = Vector2i(1280,720)
	await _settle()
	_click(catalog._all_toggle.get_global_rect().get_center())
	await _settle()
	_expect(catalog.shown_designs().size() == furniture.get_defs().size(), "all furniture definitions represented")
	for key: String in catalog.shown_designs():
		_expect(catalog.tile(key).icon != null, "real model thumbnail exists")
	var lighting: Array = catalog._entries.filter(func(entry): return entry.category == "lighting").map(func(entry): return entry.key)
	_expect(lighting.size() > 0 and _heading_shown("Lighting") and lighting.all(func(key): return catalog.tile(key) != null),
		"every category is open at once: Lighting shows as a group with its designs")
	_expect(not _heading_shown("All"), "there is no All group")
	_expect(catalog._card.is_visible_in_tree() and catalog.tile(catalog.selected_key).visible, "details follow a shown design")
	_click(catalog._all_toggle.get_global_rect().get_center())
	await _settle()
	_expect(catalog._empty.visible and not catalog._card.is_visible_in_tree() and catalog.selected_key.is_empty(), "returning to empty owned stock clears previous design details")
	var item_key: String = furniture.get_defs()[TABLE].item_key
	items.spawn_drop(item_key, 3, Vector3i(33,21,33))
	items.spawn_drop(furniture.get_defs()[CHAIR].item_key, 2, Vector3i(34,21,33))
	await _settle()
	_expect(catalog._card.is_visible_in_tree() and catalog.selected_key == TABLE, "arriving furniture restores the matching details")
	await _test_stable_browsing()
	_expect(not furniture.is_active(), "opening the catalog alone does not start placement")
	_click(catalog.tile(TABLE).get_global_rect().get_center())
	await process_frame   # a tile press arrives once the click is over
	_expect(catalog._values.Available.text == "3", "loose items update open UI")
	_expect(furniture.active_furniture_key() == TABLE and furniture._visuals.preview != null
		and manager.is_open("place"), "one tile click starts the blueprint preview and keeps catalog open")
	_expect(furniture._ghosts.is_empty(), "tile click starts preview without placing behind UI")
	_key(KEY_R)
	_click(catalog.tile(TABLE).get_global_rect().get_center())
	await process_frame   # a tile press arrives once the click is over
	_expect(furniture._yaw == 1, "re-clicking the active tile preserves rotation")
	catalog._scroll.ensure_control_visible(catalog.tile("base:furniture:board_game_table"))
	await _settle()
	_click(catalog.tile("base:furniture:board_game_table").get_global_rect().get_center())
	await process_frame   # a tile press arrives once the click is over
	_expect(not furniture.is_active() and furniture._visuals.preview == null and catalog._place.disabled,
		"unavailable design shows details and clears the old preview")
	catalog._scroll.ensure_control_visible(catalog.tile(TABLE))
	await _settle()
	_click(catalog.tile(TABLE).get_global_rect().get_center())
	await process_frame   # a tile press arrives once the click is over
	_expect(furniture.active_furniture_key() == TABLE, "available tile restarts placement directly")
	var tile_count: int = furniture._ghosts.size()
	_click(catalog._place.get_global_rect().get_center())
	_expect(furniture._ghosts.size() == tile_count, "UI click never places into world")
	var cell := Vector3i(37,20,38)
	# The window spans most of a 1280-wide screen, so look from further left for this click:
	# the cell then sits on the right of the screen, clear of the window.
	var shift: Vector3 = camera.global_transform.basis.x * -14.0
	camera.position += shift
	await _settle()
	var spot := camera.unproject_position(Vector3(cell) + Vector3(.5,1,.5))
	_expect(not dock._place_window.get_global_rect().has_point(spot), "the world click lands clear of the window")
	_click(spot)
	await _settle()
	camera.position -= shift
	_expect(furniture._ghosts.size() == 1, "real world click creates a placement")
	_expect(catalog._values.Available.text == "2" and catalog._values.Reserved.text == "1", "available becomes reserved")
	_expect(furniture.is_active(), "repeat placement stays armed")
	_click(catalog.tile(CHAIR).get_global_rect().get_center())
	await process_frame   # a tile press arrives once the click is over
	_expect(furniture.active_furniture_key() == CHAIR, "switching item continues placement")
	_expect(furniture._ghosts.size() == 1, "item tile click does not place behind the catalog")
	catalog._select(TABLE)
	# Atomic guard: successive confirmations without waiting for the UI wake.
	_place_at(Vector3i(41,20,38))
	_place_at(Vector3i(45,20,38))
	_place_at(Vector3i(49,20,38))
	await _settle()
	_expect(furniture._ghosts.size() == 3, "cannot overbook the final unit with rapid clicks")
	_expect(not furniture.is_active() and manager.is_open("place"), "exhaustion ends tool, retains catalog")
	_expect(catalog._values.Available.text == "0" and catalog._values.Reserved.text == "3", "exhausted count remains visible")
	# The tool ended with the stock; Ctrl + Z still takes back the newest placement.
	var undo := InputEventKey.new()
	undo.pressed = true; undo.keycode = KEY_Z; undo.physical_keycode = KEY_Z; undo.ctrl_pressed = true
	root.push_input(undo, true)
	await _settle()
	_expect(furniture._ghosts.size() == 2 and catalog._values.Available.text == "1", "Undo returns inventory")
	var first = furniture._ghosts.values()[0]
	first.update_lease()
	_expect(int(furniture.get_catalog_stock()[TABLE].available) == 1, "claim does not subtract the same request twice")
	var fetched: Dictionary = first.reserve_fetch(777, Vector3i(33,20,33))
	_expect(not fetched.is_empty(), "reserved plan uses existing fetch pipeline")
	items.take(fetched.item)
	first.notify_picked_up(777)
	scene.add_child(fetched.item)
	first.update_lease()
	_expect(not first._claim_valid(), "carrying plan never claims a second item")
	_expect(int(furniture.get_catalog_stock()[TABLE].available) == 1, "carried item is not subtracted twice")
	first.cancel_fetch(777)
	items.drop_loose(fetched.item, Vector3i(33,20,33))
	first.update_lease()
	_expect(int(furniture.get_catalog_stock()[TABLE].available) == 1, "interrupted fetch conserves availability")
	for id in furniture._ghosts.keys(): furniture.cancel_ghost(id)
	await _settle()
	_expect(catalog._values.Available.text == "3" and catalog._values.Reserved.text == "0", "cancelling all plans releases all stock")
	# Place counts what is ready to place, in moss (doc 23, "Counts").
	dock._counts.refresh()
	var place_tile: Control = dock._button_by_target.place
	_expect(place_tile.count_text == str(dock._counts.ready_to_place()) and dock._counts.ready_to_place() >= 3 and place_tile.count_tone == "fine"
		and place_tile.count_note.ends_with("items are ready to place"), "Place counts what is ready to place, in moss: " + place_tile.count_text)
	# Stored units are counted once; a fetched stored item moves to the claimed pool.
	for node in items._loose.keys():
		if items.item_key_of(node) == item_key: items.take(node); node.free()
	var zone = load("res://scripts/components/StockpileZoneComponent.gd").new()
	var cells: Array[Vector3i] = [Vector3i(30,20,30), Vector3i(31,20,30)]
	zone.setup(901, cells)
	for stored_cell in cells:
		zone.cell_stacks[stored_cell] = {"item": item_key, "count": 1}
		items.restore_stored_item(item_key, stored_cell)
	root.get_node("StockpileManager").register_zone(zone)
	root.get_node("StockpileManager").rebuild_totals()
	await _settle()
	_expect(int(furniture.get_catalog_stock()[TABLE].available) == 2, "ground stockpile counts once")
	furniture.activate_for(TABLE, true)
	_place_at(Vector3i(37,20,38))
	var stored_plan = furniture._ghosts.values()[0]
	var stored_fetch: Dictionary = stored_plan.reserve_fetch(778, cells[0])
	_expect(not stored_fetch.is_empty(), "stored furniture can be fetched")
	_expect(int(furniture.get_catalog_stock()[TABLE].available) == 1, "withdraw preserves remaining available count")
	stored_plan.cancel_fetch(778)
	furniture.cancel_ghost(stored_plan.ghost_id)
	await _settle()
	_expect(int(furniture.get_catalog_stock()[TABLE].available) == 2, "cancel after withdraw conserves stock")
	# Stockpiled stock, restored requests and installation share the same live accounting.
	var stored_key := "base:furniture:bench"
	var stored_item_key: String = furniture.get_defs()[stored_key].item_key
	var bench_zone = load("res://scripts/components/StockpileZoneComponent.gd").new()
	var bench_cells: Array[Vector3i] = [Vector3i(30,20,32), Vector3i(31,20,32)]
	bench_zone.setup(903, bench_cells)
	for stored_cell in bench_cells:
		bench_zone.cell_stacks[stored_cell] = {"item": stored_item_key, "count": 1}
		items.restore_stored_item(stored_item_key, stored_cell)
	root.get_node("StockpileManager").register_zone(bench_zone)
	root.get_node("StockpileManager").rebuild_totals()
	_expect(int(furniture.get_catalog_stock()[stored_key].available) == 2, "stockpiled furniture is available")
	furniture.activate_for(stored_key, true)
	_place_at(Vector3i(45,20,43))
	var saved: Dictionary = furniture.serialize_state()
	furniture.deactivate()
	for id in furniture._ghosts.keys(): furniture.cancel_ghost(id)
	furniture.restore_state(saved)
	_expect(int(furniture.get_catalog_stock()[stored_key].available) == 1
		and int(furniture.get_catalog_stock()[stored_key].reserved) == 1, "restored plans reserve existing stock")
	var stored_bench_plan = furniture._ghosts.values()[0]
	var stored_bench_fetch: Dictionary = stored_bench_plan.reserve_fetch(779, bench_cells[0])
	_expect(not stored_bench_fetch.is_empty() and bench_zone.stored_count() == 1, "fetch withdraws real stockpiled item")
	items.take(stored_bench_fetch.item)
	scene.add_child(stored_bench_fetch.item)
	stored_bench_plan.notify_picked_up(779)
	stored_bench_fetch.item.free()
	stored_bench_plan.complete_build(779)
	await _settle()
	_expect(furniture._installed.size() == 1 and furniture._ghosts.is_empty(), "delivery installs the requested furniture")
	_expect(int(furniture.get_catalog_stock()[stored_key].available) == 1
		and int(furniture.get_catalog_stock()[stored_key].reserved) == 0, "installation consumes one unit and clears its reservation")
	# Window/keyboard lifecycle; camera wheel isolation is in NavigationPreview.
	_click(catalog.tile(TABLE).get_global_rect().get_center())
	await process_frame   # a tile press arrives once the click is over
	_key(KEY_R)
	_expect(furniture._yaw == 1, "R rotates while catalog open")
	_key(KEY_ESCAPE)
	_expect(not furniture.is_active() and manager.is_open("place"), "first Escape finishes placement")
	_key(KEY_ESCAPE)
	_expect(not manager.is_open("place") and not dock._button_by_target.place.button_pressed, "second Escape closes catalog")
	_click(dock._button_by_target.place.get_global_rect().get_center())
	await _settle()
	var start: Vector2 = dock._place_window.position
	var title_point: Vector2 = start + Vector2(130,18)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT; press.pressed = true; press.position = title_point
	root.push_input(press, true)
	var motion := InputEventMouseMotion.new()
	motion.position = title_point + Vector2(40,10); motion.relative = Vector2(40,10)
	root.push_input(motion, true)
	press = press.duplicate(); press.pressed = false; press.position = motion.position
	root.push_input(press, true)
	_expect(dock._place_window.position != start, "title bar dragging works")
	manager.close("place"); manager.open("place")
	_expect(dock._place_window.position != start, "reopening preserves moved position")
	for viewport_size in [Vector2i(960,540), Vector2i(1280,720), Vector2i(2560,1440)]:
		root.size = viewport_size
		dock._place_window.position = Vector2(24,76)
		await _settle()
		catalog.refresh()
		await _settle()
		var bounds := Rect2(Vector2.ZERO, Vector2(viewport_size))
		_expect(bounds.encloses(dock._place_window.get_global_rect()), "catalog fits " + str(viewport_size))
		_expect(dock._place_window.get_global_rect().encloses(catalog._place.get_global_rect()), "primary action fits " + str(viewport_size))
		_expect(catalog._scroll.size.y >= 112, "catalog shows at least one complete compact row")
		_expect(dock._place_window.get_global_rect().end.y <= dock._dock_panel.position.y - 8,
			"catalog leaves the dock accessible at %s (window %s, dock top %.0f, list %.0f)" % [viewport_size, dock._place_window.get_global_rect(), dock._dock_panel.position.y, catalog._scroll.size.y])
		if "--capture" in OS.get_cmdline_user_args():
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://tmp/place_catalog_review/place_%d.png" % viewport_size.x)
	_click(dock._button_by_target.orders.get_global_rect().get_center())
	_expect(not manager.is_open("place") and dock._orders.is_open(), "opening Orders closes Place")
	if failures.is_empty(): print("FURNITURE_PLACE_OK: live loose/stored counts, stable browsing through hauling/new stock, claims/pickup/release, rapid-click guard, continuous placement, undo, real thumbnails, drag, keyboard, responsive native UI")
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)


func _place_at(cell: Vector3i) -> void:
	furniture._hover_cell = cell
	furniture._confirm_ghost()


func _test_stable_browsing() -> void:
	# The user's default view must not compact/re-sort while a hauler owns the
	# last unit. Use the real reserve -> pickup -> ground-stockpile deposit flow.
	var extras := ["bench", "crude_workbench", "wooden_torch", "campfire", "door", "log_bed"]
	for suffix in extras:
		items.spawn_drop(furniture.get_defs()["base:furniture:" + suffix].item_key, 1, Vector3i(32,21,32))
	catalog._all_toggle.button_pressed = false
	var chair_item: String = furniture.get_defs()[CHAIR].item_key
	var stockpiles = root.get_node("StockpileManager")
	stockpiles._process(0)
	for viewport_size in [Vector2i(960,540), Vector2i(1280,720), Vector2i(2560,1440)]:
		root.size = viewport_size
		manager.close("place"); manager.open("place")
		catalog._select(CHAIR)
		await _settle()
		catalog._scroll.scroll_vertical = 60
		catalog.tile(CHAIR).grab_focus()
		await _settle()
		var rectangles := {}
		var click_key := ""
		for key: String in catalog.shown_designs():
			var button: Button = catalog.tile(key)
			if button.is_visible_in_tree():
				rectangles[key] = button.get_global_rect()
				if catalog._scroll.get_global_rect().has_point(button.get_global_rect().get_center()): click_key = key
		var window_rect: Rect2 = dock._place_window.get_global_rect()
		var scroll: int = catalog._scroll.scroll_vertical
		var zone = load("res://scripts/components/StockpileZoneComponent.gd").new()
		var cells: Array[Vector3i] = [Vector3i(28,20,30), Vector3i(29,20,30)]
		zone.setup(902, cells)
		stockpiles.register_zone(zone)
		var exclude := {}
		for node in items._loose:
			if items.item_key_of(node) != chair_item: exclude[node] = true
		for id in [881,882]:
			var haul: Dictionary = zone.reserve_haul(id, Vector3i(34,20,33), exclude)
			_expect(haul.get("items", []).size() == 1, "reserve one actual furniture item per hauler")
		await _settle()
		_expect(catalog._values.Available.text == "0" and catalog._place.disabled, "hauling still updates honest availability")
		_assert_browse_stable(rectangles, window_rect, scroll, "reserve " + str(viewport_size))
		var carried := []
		for id in [881,882]:
			var node: Node3D = zone.take_item(id, 0)
			scene.add_child(node)
			carried.append(node)
		await _settle()
		_assert_browse_stable(rectangles, window_rect, scroll, "pickup " + str(viewport_size))
		for index in range(2):
			_expect(zone.commit_haul(881 + index, [[carried[index], chair_item]]), "deposit furniture into ground stockpile")
		await _settle()
		_expect(catalog._values.Available.text == "2" and not catalog._place.disabled, "stockpile deposit restores availability")
		_assert_browse_stable(rectangles, window_rect, scroll, "deposit " + str(viewport_size))
		if viewport_size.x == 960:
			items.spawn_drop(furniture.get_defs()["base:furniture:board_game_table"].item_key, 1, Vector3i(32,21,32))
			await _settle()
			_assert_browse_stable(rectangles, window_rect, scroll, "new design arrives")
			_expect(_heading_shown("New") and catalog.shown_designs().back() == "base:furniture:board_game_table",
				"a design that arrives while Place is open waits in the New group at the end")
		_expect(root.gui_get_focus_owner() == catalog.tile(CHAIR), "stock changes retain keyboard focus")
		_expect(catalog.selected_key == CHAIR, "stock changes retain selection")
		_expect(not click_key.is_empty(), "scrolled catalog has a clickable tile")
		_click(rectangles[click_key].get_center())
		await process_frame   # a tile press arrives once the click is over
		_expect(catalog.selected_key == click_key, "same screen point selects the same item after hauling")
		stockpiles.deregister_zone(zone)
	# Return the fixture to its original stock for the placement checks.
	for node in items._loose.keys():
		if items.item_key_of(node) not in [chair_item, furniture.get_defs()[TABLE].item_key]:
			items.take(node); node.free()
	manager.close("place"); manager.open("place")
	await _settle()
	_expect(catalog.shown_designs().size() == 2 and not _heading_shown("New"), "reopening refreshes the owned-design list and sorts arrivals into their groups")
	root.size = Vector2i(1280,720)
	catalog._all_toggle.button_pressed = true
	catalog._scroll.scroll_vertical = 0
	await _settle()


func _assert_browse_stable(rectangles: Dictionary, window_rect: Rect2, scroll: int, stage: String) -> void:
	_expect(dock._place_window.get_global_rect().is_equal_approx(window_rect), "window stays put: " + stage)
	_expect(catalog._scroll.scroll_vertical == scroll, "scroll stays put: " + stage)
	for key: String in rectangles:
		var button: Button = catalog.tile(key)
		_expect(button != null and button.is_visible_in_tree() and button.get_global_rect().is_equal_approx(rectangles[key]), "tile stays put: " + key + " / " + stage)


## Whether the designs show a group headed with this title.
func _heading_shown(title: String) -> bool:
	return catalog._grid.find_children("*", "Label", true, false).any(func(label: Label): return label.text == title and label.is_visible_in_tree())


func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.pressed = true; event.keycode = code
	root.push_input(event, true)


func _settle() -> void:
	for frame in range(6): await process_frame


func _build_review_world() -> void:
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	mesh.mesh.size = Vector3(55,1,55)
	mesh.position = Vector3(40,20.5,40)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("748475")
	mesh.material_override = material
	scene.add_child(mesh)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50,-25,0)
	scene.add_child(light)
	var environment := WorldEnvironment.new()
	environment.name = "WorldEnvironment"
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("34403e")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("ced9c7")
	environment.environment.ambient_light_energy = .7
	scene.add_child(environment)
