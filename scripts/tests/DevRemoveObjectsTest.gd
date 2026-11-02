extends "res://scripts/tests/ObjectExplorerTest.gd"

## Development › Remove objects (DEV Remove): the menu entry starts the tool, and real clicks
## and a drag through the viewport delete trees, stones, bushes and flowers at once. Nothing
## drops, a marked tree's job is cancelled, the object explorer leaves the clicks to the tool,
## the tool bar shows it on the DEV tile without Undo, and a save keeps the removals. Without
## DEV tools it never starts.
const BOULDER := "boulder:1234:dev:1"
const FAR_BOULDER := "boulder:1234:dev:2"
const SCREE := "scree:1234:dev:1"
const BUSH := "blueberry:1234:dev:1"
const FLOWER := "flowers:1234:dev:1"
const FAR_FLOWER := "flowers:1234:dev:2"
var tasks
var drops
var dock
var chop
var details


func _run() -> void:
	create_timer(90).timeout.connect(func(): push_error("DEV remove objects test timed out"); quit(1))
	_setup()
	var oak_id := Vector2i(40, 40)
	var sapling_id := Vector2i(44, 52)
	var pine_id := Vector2i(64, 40)
	var oak := _spawn_tree("oak", "mature", oak_id)
	_spawn_tree("pine", "sapling", sapling_id)
	_spawn_tree("pine", "mature", pine_id)
	for spec: Array in [[BOULDER, "base:detail:boulder", Vector3i(52, 20, 40)], [FAR_BOULDER, "base:detail:boulder", Vector3i(62, 20, 62)],
			[SCREE, "base:detail:scree", Vector3i(48, 20, 52)], [BUSH, "base:flora:blueberry_bush", Vector3i(52, 20, 55)],
			[FLOWER, "base:detail:flowers", Vector3i(46, 20, 56)], [FAR_FLOWER, "base:detail:flowers", Vector3i(60, 20, 58)]]:
		details.register_record({"id": spec[0], "definition": spec[1], "origin": spec[2], "variant": 0, "yaw": 0})
		details._spawn_visual(spec[0])
	_expect(details.get_explorer_bounds(BUSH).size != Vector3.ZERO and details.get_explorer_bounds(FLOWER).size != Vector3.ZERO,
		"fixture: the bush and the flower stand")
	_expect(flora.designate_felling(oak_id), "fixture: the oak is marked for chopping")
	var lease: int = flora.work.sources[oak_id].lease_id
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 65
	_aim_above(Vector3(50, 21, 50))
	await _frames(5)

	# The Development menu's entry starts the tool, as a player opens it.
	_click(dock._button_by_target.development.get_global_rect().get_center())
	await _frames(5)
	var tile: Control = dock._panel_body.get_node_or_null("RemoveObjects")
	_expect(tile != null and tile.is_visible_in_tree(), "Development lists Remove objects")
	if tile == null:
		_finish()
		return
	_click(tile.get_global_rect().get_center())
	await _frames(3)
	_expect(chop.is_active() and chop.get_order_tool_id() == "dev_remove" and not dock._panel_container.visible,
		"Remove objects starts DEV Remove and closes the menu")
	var bar = dock._tool_bar
	bar.refresh()
	_expect(bar.active_tool() == chop and bar._name.text == "Remove objects" and not bar._undo.visible
		and bar._family == root.get_node("UIRegistry").get_icon_family_color("dev"), "the tool bar shows Remove objects on the DEV tile, without Undo")
	_expect(dock._orders.group_for_tool(dock._orders.active_tool_id()).is_empty() and not dock._button_by_target.orders.button_pressed,
		"the Orders button stays dark")

	# A click removes what it points at, at once and without drops.
	var oak_point := camera.unproject_position(oak.position + Vector3.UP * 3)
	_move(oak_point)
	_click(oak_point)
	_expect(bool(flora.get_tree_change(oak_id).get("felled", false)) and flora.get_explorer_bounds(oak_id).size == Vector3.ZERO,
		"a click removes the tree")
	_expect(tasks.get_task(lease) == null and not flora.work.has(oak_id) and not flora._felling_markers.has(oak_id),
		"the tree's chopping job and marker go with it")
	_expect(not explorer.is_object_selected(flora, oak_id) and explorer._provider == null, "the object explorer leaves the click to the tool")
	_click(camera.unproject_position(Vector3(53, 21.6, 41)))
	_expect(bool(details.get_change(BOULDER).get("removed", false)) and String(details.get_change(BOULDER).get("reason", "")) == "dev_removed",
		"a click removes the boulder")
	_expect(int(details.get_record(BOULDER).occupancy) < 0 and not root.get_node("PlacedEntityRegistry").occupies(Vector3i(52, 21, 40)),
		"the boulder's ground is free again")
	_expect(_dropped() == 0, "nothing drops from the tree or the boulder")
	bar.refresh()
	_expect(bar._status_text.text == "Removed 1 stone or plant", "the tool bar says what the last click removed: " + bar._status_text.text)

	# A drag removes every tree, stone and plant in the area, and nothing outside it.
	var a := camera.unproject_position(Vector3(43.2, 21, 50.2))
	var b := camera.unproject_position(Vector3(56.8, 21, 58.8))
	_move(a)
	_mouse_button(a, true)
	_move(b)
	_expect(chop._box_select and chop._preview_trees == [sapling_id] and chop._preview_stones.size() == 3,
		"the area previews the sapling, the scree, the bush and the flower: %s %s" % [chop._preview_trees, chop._preview_stones])
	_expect(String(chop.tool_bar_state().get("selection", {}).get("count", "")) == "4 to remove", "the tool bar counts what the area would remove")
	_mouse_button(b, false)
	_expect(bool(flora.get_tree_change(sapling_id).get("felled", false)), "the drag removes the sapling")
	for id: String in [SCREE, BUSH, FLOWER]:
		_expect(bool(details.get_change(id).get("removed", false)), "the drag removes " + id)
	_expect(details.get_explorer_bounds(FAR_FLOWER).size != Vector3.ZERO and details.get_explorer_bounds(FAR_BOULDER).size != Vector3.ZERO
		and flora.get_explorer_bounds(pine_id).size != Vector3.ZERO, "what lies outside the area stays")
	_expect(_dropped() == 0, "nothing drops: no logs, seeds, stone, berries or cuttings")

	# The slice hides what it hides: a tree above the cut is left alone.
	flora._on_slice_changed(19)
	_expect(not flora.dev_remove_tree(pine_id), "a tree the slice hides cannot be removed")
	flora._on_slice_changed(127)

	# A save keeps every removal; a removed wild tree never comes back with its column.
	var flora_saved: Dictionary = JSON.parse_string(JSON.stringify(flora.serialize_state()))
	var details_saved: Dictionary = JSON.parse_string(JSON.stringify(details.serialize_state()))
	flora.restore_state(flora_saved)
	details.restore_state(details_saved)
	_expect(JSON.parse_string(JSON.stringify(flora.serialize_state())) == flora_saved
		and JSON.parse_string(JSON.stringify(details.serialize_state())) == details_saved, "removals round trip through a save")
	_expect(bool(flora.get_tree_change(oak_id).get("felled", false)) and _spawn_tree("oak", "mature", oak_id) == null,
		"a removed tree stays gone when its column streams in again")
	for id: String in [BOULDER, SCREE, BUSH, FLOWER]:
		_expect(bool(details.get_change(id).get("removed", false)) and details.get_explorer_bounds(id).size == Vector3.ZERO, id + " stays removed after loading")
	_expect(not bool(details.get_change(FAR_FLOWER).get("removed", false)) and not bool(details.get_change(FAR_BOULDER).get("removed", false)),
		"what stood outside the area still stands after loading")

	# Another tool ends DEV Remove; Esc does too; without DEV tools it never starts.
	dock.tool_requested.emit("chop")
	bar.refresh()
	_expect(chop.is_active() and chop.get_order_tool_id() == "chop" and bar._undo.visible, "Chop trees takes over as an order tool, with Undo")
	dock.tool_requested.emit("dev_remove")
	_key(KEY_ESCAPE)
	_expect(not chop.is_active(), "Esc ends DEV Remove")
	var registry := root.get_node("UIRegistry")
	registry.dev_tools_enabled = false
	dock.tool_requested.emit("dev_remove")
	registry.dev_tools_enabled = true
	_expect(not chop.is_active(), "without DEV tools the tool never starts")
	_finish()


func _setup() -> void:
	for name: String in ["SaveManager", "RoomManager", "TaskManager"]:
		root.get_node(name).set_process(false)
	root.get_node("WorldClock").set_paused(true)
	tasks = root.get_node("TaskManager")
	var generator = root.get_node("WorldGenerator")
	generator.world_seed = 1234
	# Synthetic terrain still needs valid baseline maps for set_block queries.
	generator._cache_block_ids()
	generator.heightmap.resize(1024 * 1024)
	generator.heightmap.fill(20)
	generator.waterline_map.resize(1024 * 1024)
	generator.waterline_map.fill(-1)
	world = root.get_node("WorldData")
	blocks = root.get_node("BlockRegistry")
	_build_floor()
	scene = Node3D.new()
	root.add_child(scene)
	current_scene = scene
	manager = load("res://scripts/ui/UIWindowManager.gd").new()
	manager.name = "Windows"
	scene.add_child(manager)
	manager._layout_loaded = false # Do not write the player's window preferences.
	drops = load("res://scripts/systems/ItemDropManager.gd").new()
	scene.add_child(drops)
	flora = load("res://scripts/systems/SurfaceFloraSpawner.gd").new()
	flora.name = "Flora"
	scene.add_child(flora)
	flora.set_process(false)
	details = load("res://scripts/systems/SurfaceDetailManager.gd").new()
	details.name = "Details"
	scene.add_child(details)
	details.set_process(false)
	details._initialized = true
	dock = load("res://scripts/ui/DockUI.gd").new()
	dock.name = "Dock"
	dock.window_manager_path = NodePath("../Windows")
	scene.add_child(dock)
	explorer = load("res://scripts/ui/ObjectExplorerController.gd").new()
	explorer.name = "Explorer"
	explorer.window_manager_path = NodePath("../Windows")
	scene.add_child(explorer)
	chop = load("res://scripts/systems/TreeFellingController.gd").new()
	chop.dock_ui_path = NodePath("../Dock")
	chop.flora_path = NodePath("../Flora")
	chop.details_path = NodePath("../Details")
	chop.explorer_path = NodePath("../Explorer")
	scene.add_child(chop)
	explorer._tools.append(chop) # The main scene lists it in click_tool_paths.
	camera = Camera3D.new()
	scene.add_child(camera)
	camera.current = true
	root.size = Vector2i(1280, 800)
	generator._maps_ready = true


func _spawn_tree(species_name: String, stage_name: String, id: Vector2i) -> Node3D:
	var species: Dictionary = flora._species_for_key("base:flora:%s_tree" % species_name)
	var stage: Dictionary = species.stages[stage_name]
	var cell := Vector3i(id.x, 20, id.y)
	var node: Node3D = flora._instance_tree(species_name, flora.resolve_tree_model_for_season(stage, flora._season, cell),
		stage_name, stage, id.x, id.y, 20, flora._footprint_for(species.placement, stage_name))
	if node != null:
		var column := Vector2i(id.x >> 4, id.y >> 4)
		if not flora._loaded_columns.has(column): flora._loaded_columns[column] = []
		flora._loaded_columns[column].append(node)
	return node


## Loose goods on the ground: whatever a removal dropped.
func _dropped() -> int:
	return drops._loose.size()


func _frames(count: int) -> void:
	for i in range(count): await process_frame


func _move(position: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position
	root.push_input(event, true)


func _mouse_button(position: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = position
	root.push_input(event, true)


func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	root.push_input(event, true)


func _finish() -> void:
	for failure: String in failures: push_error(failure)
	print("DEV_REMOVE_OBJECTS_OK" if failures.is_empty() else "DEV_REMOVE_OBJECTS_FAIL")
	quit(0 if failures.is_empty() else 1)
