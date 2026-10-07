extends "res://scripts/tests/ObjectExplorerTest.gd"

const TABLE := "base:furniture:wooden_table"
const CHAIR := "base:furniture:wooden_chair"
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
	_expect(catalog._empty.visible and catalog._place.disabled and not catalog._paper.visible
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
	_expect(catalog._tiles.size() == furniture.get_defs().size(), "all 18 furniture definitions represented")
	for tile: Dictionary in catalog._tiles.values():
		_expect(tile.image.texture != null, "real model thumbnail exists")
	_click(catalog._tabs.storage.get_global_rect().get_center())
	await _settle()
	_expect(catalog._count.text == "3 designs", "Storage filter shows its three furniture designs")
	_expect(catalog._paper.visible and catalog._tiles[catalog.selected_key].button.visible, "details follow a visible design in the selected category")
	_click(catalog._all_toggle.get_global_rect().get_center())
	await _settle()
	_expect(catalog._empty.visible and not catalog._paper.visible and catalog.selected_key.is_empty(), "returning to empty owned stock clears previous design details")
	_click(catalog._tabs.all.get_global_rect().get_center())
	await _settle()
	var item_key: String = furniture.get_defs()[TABLE].item_key
	items.spawn_drop(item_key, 3, Vector3i(33,21,33))
	items.spawn_drop(furniture.get_defs()[CHAIR].item_key, 2, Vector3i(34,21,33))
	await _settle()
	_expect(catalog._paper.visible and catalog.selected_key == TABLE, "arriving furniture restores the matching details")
	await _test_stable_browsing()
	_expect(not furniture.is_active(), "opening the catalog alone does not start placement")
	_click(catalog._tiles[TABLE].button.get_global_rect().get_center())
	_expect(catalog._values.Available.text == "3", "loose items update open UI")
	_expect(furniture.active_furniture_key() == TABLE and furniture._preview != null
		and manager.is_open("place"), "one tile click starts the blueprint preview and keeps catalog open")
	_expect(furniture._ghosts.is_empty(), "tile click starts preview without placing behind UI")
	_key(KEY_R)
	_click(catalog._tiles[TABLE].button.get_global_rect().get_center())
	_expect(furniture._yaw == 1, "re-clicking the active tile preserves rotation")
	_click(catalog._tiles["base:furniture:communal_table"].button.get_global_rect().get_center())
	_expect(not furniture.is_active() and furniture._preview == null and catalog._place.disabled,
		"unavailable design shows details and clears the old preview")
	_click(catalog._tiles[TABLE].button.get_global_rect().get_center())
	_expect(furniture.active_furniture_key() == TABLE, "available tile restarts placement directly")
	var tile_count: int = furniture._ghosts.size()
	_click(catalog._place.get_global_rect().get_center())
	_expect(furniture._ghosts.size() == tile_count, "UI click never places into world")
	var cell := Vector3i(37,20,38)
	_click(camera.unproject_position(Vector3(cell) + Vector3(.5,1,.5)))
	await _settle()
	_expect(furniture._ghosts.size() == 1, "real world click creates a placement")
	_expect(catalog._values.Available.text == "2" and catalog._values.Reserved.text == "1", "available becomes reserved")
	_expect(furniture.is_active(), "repeat placement stays armed")
	_click(catalog._tiles[CHAIR].button.get_global_rect().get_center())
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
	_click(catalog._undo.get_global_rect().get_center())
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
	# Containers, restored requests and installation share the same live accounting.
	var barrel := "base:furniture:barrel"
	var barrel_item: String = furniture.get_defs()[barrel].item_key
	var container = load("res://scripts/components/ContainerStorageComponent.gd").new()
	container.setup_container({"storage": {"capacity": 8}}, cells)
	container.source_id = root.get_node("TaskManager").allocate_source_id()
	root.get_node("StockpileManager").register_container(container)
	container.restore_inventory({barrel_item: 2}, items)
	root.get_node("StockpileManager").rebuild_totals()
	_expect(int(furniture.get_catalog_stock()[barrel].available) == 2, "container inventory is available")
	furniture.activate_for(barrel, true)
	_place_at(Vector3i(45,20,43))
	var saved: Dictionary = furniture.serialize_state()
	furniture.deactivate()
	for id in furniture._ghosts.keys(): furniture.cancel_ghost(id)
	furniture.restore_state(saved)
	_expect(int(furniture.get_catalog_stock()[barrel].available) == 1
		and int(furniture.get_catalog_stock()[barrel].reserved) == 1, "restored plans reserve existing stock")
	var barrel_plan = furniture._ghosts.values()[0]
	var barrel_fetch: Dictionary = barrel_plan.reserve_fetch(779, cells[0])
	_expect(not barrel_fetch.is_empty() and container.stored_count() == 1, "fetch withdraws real container item")
	items.take(barrel_fetch.item)
	scene.add_child(barrel_fetch.item)
	barrel_plan.notify_picked_up(779)
	barrel_fetch.item.free()
	barrel_plan.complete_build(779)
	await _settle()
	_expect(furniture._installed.size() == 1 and furniture._ghosts.is_empty(), "delivery installs the requested furniture")
	_expect(int(furniture.get_catalog_stock()[barrel].available) == 1
		and int(furniture.get_catalog_stock()[barrel].reserved) == 0, "installation consumes one unit and clears its reservation")
	# Window/keyboard lifecycle; camera wheel isolation is in NavigationPreview.
	_click(catalog._tiles[TABLE].button.get_global_rect().get_center())
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
			"catalog leaves the dock accessible at " + str(viewport_size))
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
	var extras := ["bench", "barrel", "storage_chest", "storage_shelf", "wall_torch", "brazier", "door", "dwarf_bunk"]
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
		catalog._tiles[CHAIR].button.grab_focus()
		await _settle()
		var rectangles := {}
		var click_key := ""
		for key: String in catalog._tiles:
			var button: Button = catalog._tiles[key].button
			if button.visible:
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
			items.spawn_drop(furniture.get_defs()["base:furniture:communal_table"].item_key, 1, Vector3i(32,21,32))
			await _settle()
			_assert_browse_stable(rectangles, window_rect, scroll, "new design arrives")
		_expect(root.gui_get_focus_owner() == catalog._tiles[CHAIR].button, "stock changes retain keyboard focus")
		_expect(catalog.selected_key == CHAIR, "stock changes retain selection")
		_expect(not click_key.is_empty(), "scrolled catalog has a clickable tile")
		_click(rectangles[click_key].get_center())
		_expect(catalog.selected_key == click_key, "same screen point selects the same item after hauling")
		stockpiles.deregister_zone(zone)
	# Return the fixture to its original stock for the placement checks.
	for node in items._loose.keys():
		if items.item_key_of(node) not in [chair_item, furniture.get_defs()[TABLE].item_key]:
			items.take(node); node.free()
	manager.close("place"); manager.open("place")
	await _settle()
	_expect(catalog._count.text == "2 designs", "reopening refreshes the owned-design list")
	root.size = Vector2i(1280,720)
	catalog._all_toggle.button_pressed = true
	catalog._scroll.scroll_vertical = 0
	await _settle()


func _assert_browse_stable(rectangles: Dictionary, window_rect: Rect2, scroll: int, stage: String) -> void:
	_expect(dock._place_window.get_global_rect().is_equal_approx(window_rect), "window stays put: " + stage)
	_expect(catalog._scroll.scroll_vertical == scroll, "scroll stays put: " + stage)
	for key: String in rectangles:
		var button: Button = catalog._tiles[key].button
		_expect(button.visible and button.get_global_rect().is_equal_approx(rectangles[key]), "tile stays put: " + key + " / " + stage)


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
