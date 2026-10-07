extends "res://scripts/tests/FurniturePlaceTest.gd"

var Inventory
const STONE := "base:resources:stone:rough_stone"
const IRON := "base:resources:ore:iron"
const ACORN := "base:resources:seed:oak_acorn"
var inventory
var rig
var stock_controller

func _run() -> void:
	Inventory = load("res://scripts/components/ColonyInventory.gd")
	create_timer(60).timeout.connect(func(): push_error("Inventory test timed out"); quit(1))
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
	inventory = dock._inventory_panel
	rig = load("res://scripts/systems/Camera.gd").new()
	scene.add_child(rig)
	rig.set_process(false)
	camera.reparent(rig, true)
	camera.current = true
	stock_controller = load("res://scripts/systems/StockpileDesignationController.gd").new()
	stock_controller.dock_ui_path = NodePath("../Dock")
	stock_controller.window_manager_path = NodePath("../Windows")
	scene.add_child(stock_controller)
	stock_controller.set_process(false)
	explorer = load("res://scripts/ui/ObjectExplorerController.gd").new()
	explorer.window_manager_path = NodePath("../Windows")
	scene.add_child(explorer)
	await _settle()
	_click(dock._button_by_target.stocks.get_global_rect().get_center())
	await _settle()
	_expect(manager.is_open("inventory") and not dock._panel_container.visible, "Inventory opens directly from dock")
	_expect(dock._button_by_target.stocks.text == "Inventory", "dock uses Inventory name")
	_expect(inventory._empty.visible and inventory._locate.disabled, "empty colony has honest empty state")
	items.restore_loose_item(STONE, Vector3(33.5,21,33.5), 0)
	items.restore_loose_item(STONE, Vector3(34.5,21,33.5), 0)
	items.restore_loose_item(IRON, Vector3(35.5,21,33.5), 0)
	await _settle()
	_expect(inventory._stock[STONE].total == 2 and inventory._stock[STONE].loose == 2, "loose units wake open window")
	var stone: Node3D = items.nearest_loose_of_key(STONE, Vector3i(33,20,33))
	var rect: Rect2 = inventory._tiles[IRON].button.get_global_rect()
	var window_rect: Rect2 = dock._inventory_window.get_global_rect()
	items.reserve(stone, 17)
	await _settle()
	_expect(inventory._stock[STONE].reserved == 1 and inventory._stock[STONE].total == 2, "reservation is subset of physical total")
	items.take(stone)
	scene.add_child(stone)
	stone.position = Vector3(33.5,21,33.5)
	await _settle()
	_expect(inventory._stock[STONE].carried == 1 and inventory._stock[STONE].total == 2, "pickup conserves total")
	_expect(inventory._tiles[IRON].button.get_global_rect() == rect and dock._inventory_window.get_global_rect() == window_rect, "pickup leaves browsing targets and window unchanged")
	items.drop_loose(stone, Vector3i(33,20,33))
	await _settle()
	_expect(inventory._stock[STONE].carried == 0 and inventory._stock[STONE].available == 2, "interrupted hauling returns available goods")
	var cells: Array[Vector3i] = [Vector3i(30,20,30), Vector3i(31,20,30)]
	var zone = stock_controller._create_zone(cells)
	zone.carry_capacity = 1
	var pull: Dictionary = zone.reserve_haul(18, Vector3i(33,20,33), {})
	_expect(not pull.is_empty(), "real stockpile reserves haul")
	var cargo: Node3D = zone.take_item(18, 0)
	scene.add_child(cargo)
	var cargo_key: String = items.item_key_of(cargo)
	var previous_total: int = Inventory.snapshot(items, furniture)[cargo_key].total
	_expect(zone.commit_haul(18, [[cargo,cargo_key]]), "real stockpile deposit succeeds")
	await _settle()
	_expect(inventory._stock[cargo_key].total == previous_total and inventory._stock[cargo_key].stored == 1, "deposit counts storage once and clears transit")
	inventory.selected_key = cargo_key; inventory.refresh()
	_click(inventory._inspect.get_global_rect().get_center())
	await _settle()
	_expect(not manager.is_open("inventory") and stock_controller._window_zone_id == zone.zone_id, "Inspect storage opens the current stockpile")
	manager.close("storage_zone_info")
	_click(dock._button_by_target.stocks.get_global_rect().get_center())
	await _settle()
	inventory.selected_key = IRON; inventory.refresh()
	var zoom: float = rig._target_zoom
	var position_before: Vector3 = rig._target_pos
	items._on_slice_changed(19)
	_click(inventory._locate.get_global_rect().get_center())
	_expect(manager.is_open("inventory") and rig._target_pos == position_before, "Locate never jumps to slice-hidden goods")
	items._on_slice_changed(127)
	_click(inventory._locate.get_global_rect().get_center())
	_expect(not manager.is_open("inventory") and rig._target_zoom == zoom, "Locate moves camera without changing zoom")
	_expect(rig._target_pos.is_equal_approx(Vector3(35.5,22.5,33.5)), "Locate resolves live loose item position")
	dock._open_inventory()
	await _settle()
	# Containers count their contents; their display nodes never add inventory.
	furniture._install("base:furniture:storage_shelf", furniture.get_defs()["base:furniture:storage_shelf"], Vector3i(44,20,44), 0)
	var installed = furniture._installed.values()[0]
	var container = installed.storage
	container.restore_inventory({ACORN: 20}, items)
	root.get_node("StockpileManager").rebuild_totals()
	items.restore_loose_item(ACORN, Vector3(36.5,21,33.5), 0, 10)
	await _settle()
	_expect(inventory._stock[ACORN].total == 30, "crate contents count as units, not visuals or packages")
	inventory.selected_key = ACORN; inventory.refresh()
	_click(inventory._inspect.get_global_rect().get_center())
	await _settle()
	_expect(not manager.is_open("inventory") and explorer._object_id == "installed:%d" % installed.installed_id, "Inspect storage selects real installed shelf")
	explorer.clear_selection()
	dock._open_inventory()
	await _settle()
	container.filter_tags.assign(["stockpile_seed"])
	pull = container.reserve_haul(20, Vector3i(36,20,33), {})
	_expect(not pull.is_empty(), "shelf reserves crate")
	cargo = container.take_item(20, 0)
	scene.add_child(cargo)
	_expect(container.commit_haul(20, [[cargo,ACORN]]), "shelf deposits crate")
	await _settle()
	_expect(inventory._stock[ACORN].total == 30 and inventory._stock[ACORN].carried == 0, "merged shelf visuals do not duplicate goods")
	# Split-crate pickup retains remaining units on the ground.
	items.restore_loose_item(ACORN, Vector3(38.5,21,33.5), 0, 12)
	var crate: Node3D = items.nearest_loose_of_key(ACORN, Vector3i(38,20,33))
	items.reserve(crate, 21)
	cargo = items.take_quantity(crate, 5, 21)
	scene.add_child(cargo)
	await _settle()
	_expect(inventory._stock[ACORN].total == 42 and inventory._stock[ACORN].carried == 5, "partial crate pickup conserves every unit")
	items.drop_loose(cargo, Vector3i(38,20,34))
	# Existing model thumbnails; no invented replacements.
	for key in [STONE, IRON, ACORN]:
		_expect(inventory._tiles[key].image.texture.resource_path == Inventory.thumbnail_path(key), "real model thumbnail for " + key)
	var item_key: String = furniture.get_defs()[TABLE].item_key
	items.restore_loose_item(item_key, Vector3(37.5,21,33.5), 0)
	await _settle()
	_click(inventory._tiles[item_key].button.get_global_rect().get_center())
	await _settle()
	_expect(inventory.selected_key == item_key and manager.is_open("inventory") and not furniture.is_active(), "Inventory furniture selection inspects supplies without starting placement")
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tmp/inventory_review/inventory_furniture.png")
	_click(dock._button_by_target.place.get_global_rect().get_center())
	await _settle()
	_click(catalog._tiles[TABLE].button.get_global_rect().get_center())
	_expect(manager.is_open("place") and not manager.is_open("inventory") and furniture.active_furniture_key() == TABLE, "Place dock remains the entry to furniture placement")
	_expect(furniture._ghosts.is_empty(), "Place selection never places behind UI")
	_place_at(Vector3i(42,20,40))
	dock._open_inventory()
	await _settle()
	inventory.selected_key = item_key; inventory.refresh()
	_expect(inventory._stock[item_key].total == 1 and inventory._stock[item_key].reserved == 1 and inventory._stock[item_key].available == 0, "Inventory reports placement reservations without inventing total")
	for id in furniture._ghosts.keys(): furniture.cancel_ghost(id)
	# Scroll, focus and depleted tiles stay fixed as other goods come and go.
	for def: Dictionary in furniture.get_defs().values():
		items.restore_loose_item(def.item_key, Vector3(37.5,21,35.5), 0)
	await _settle()
	inventory._scroll.scroll_vertical = 120
	await _settle()
	var scroll: int = inventory._scroll.scroll_vertical
	var old_keys: Array = inventory._browse_keys.duplicate()
	var iron: Node3D = items.nearest_loose_of_key(IRON, Vector3i.ZERO)
	inventory._tiles[IRON].button.grab_focus()
	items.take(iron); iron.free()
	await _settle()
	_expect(inventory._tiles[IRON].button.visible and inventory._tiles[IRON].count.text == "0", "depletion retains zero-count tile until reopening")
	_expect(inventory._browse_keys == old_keys and inventory._scroll.scroll_vertical == scroll, "depletion preserves order and scroll")
	_expect(inventory._tiles[IRON].button.has_focus(), "count wake preserves keyboard focus")
	items.restore_loose_item("base:resources:wood:oak_log", Vector3(39.5,21,33.5), 0)
	await _settle()
	_expect(inventory._browse_keys.slice(0, old_keys.size()) == old_keys, "new goods append without reshuffling")
	inventory._set_category("materials")
	_expect(inventory._tiles[STONE].button.visible and not inventory._tiles[item_key].button.visible, "Materials filter uses JSON resource tags")
	inventory._set_category("all")
	# Title drag, close/reopen and native responsive captures.
	var start: Vector2 = dock._inventory_window.position
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT; press.pressed = true; press.position = start + Vector2(130,18)
	root.push_input(press, true)
	var motion := InputEventMouseMotion.new()
	motion.position = press.position + Vector2(40,-10); motion.relative = Vector2(40,-10)
	root.push_input(motion, true)
	press = press.duplicate(); press.pressed = false; press.position = motion.position
	root.push_input(press, true)
	_expect(dock._inventory_window.position != start, "Inventory title bar drags")
	var moved: Vector2 = dock._inventory_window.position
	_key(KEY_ESCAPE)
	_expect(not manager.is_open("inventory"), "Escape closes Inventory")
	dock._open_inventory()
	await _settle()
	_expect(dock._inventory_window.position == moved, "reopening remembers window position")
	stock_controller.remove_zone(zone.zone_id)
	await _settle()
	_expect(not stock_controller.inspect_storage(zone), "removed storage owner cannot be inspected")
	_expect(inventory._stock[STONE].total == 2 and inventory._stock[STONE].stored == 0, "removing stockpile returns goods without changing total")
	items.restore_loose_item(IRON, Vector3(35.5,21,33.5), 0)
	inventory.begin_browsing()
	await _settle()
	for viewport_size in [Vector2i(960,540), Vector2i(1280,720), Vector2i(2560,1440)]:
		root.size = viewport_size
		dock._inventory_window.position = Vector2(24,76)
		inventory.selected_key = STONE
		inventory._scroll.scroll_vertical = 0
		inventory.refresh()
		await _settle()
		var bounds := Rect2(Vector2.ZERO, Vector2(viewport_size))
		_expect(bounds.encloses(dock._inventory_window.get_global_rect()), "Inventory fits " + str(viewport_size))
		_expect(dock._inventory_window.get_global_rect().encloses(inventory._inspect.get_global_rect()), "actions remain inside window " + str(viewport_size))
		_expect(dock._inventory_window.get_global_rect().end.y <= dock._dock_panel.position.y - 8, "dock remains accessible " + str(viewport_size))
		if "--capture" in OS.get_cmdline_user_args():
			camera.global_position = Vector3(49,41,55)
			camera.look_at(Vector3(38,21,38))
			await _settle()
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://tmp/inventory_review/inventory_%d.png" % viewport_size.x)
	if failures.is_empty(): print("COLONY_INVENTORY_OK: direct navigation, physical totals, reservations, hauling, crate contents, stockpile/container storage, Locate/Inspect, separate Place workflow, stable browsing, drag, Escape, 960/1280/2560 layouts")
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
