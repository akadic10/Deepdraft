extends SceneTree

## Focused runtime fixture: real flora/furniture models, screen-space picking,
## terrain occlusion, slice/tool exclusion, season replacement and fixed UI rows.
## godot --headless --path . --script res://scripts/tests/ObjectExplorerTest.gd
var failures: Array[String] = []
var flora
var furniture
var explorer
var manager
var camera: Camera3D
var world
var blocks
var scene: Node3D
var tree_ids: Array[Vector2i] = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	create_timer(60).timeout.connect(func(): push_error("Object explorer test timed out"); quit(1))
	root.get_node("SaveManager").set_process(false)
	root.get_node("WorldClock").set_paused(true)
	root.get_node("TaskManager").set_process(false)
	root.get_node("RoomManager").set_process(false)
	root.get_node("WorldGenerator").world_seed = 1234
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
	var items = load("res://scripts/systems/ItemDropManager.gd").new()
	scene.add_child(items)
	flora = load("res://scripts/systems/SurfaceFloraSpawner.gd").new()
	scene.add_child(flora)
	flora.set_process(false)
	flora._season = "spring"
	furniture = load("res://scripts/systems/FurniturePlacementController.gd").new()
	furniture.name = "Furniture"
	scene.add_child(furniture)
	furniture.set_process(false)
	furniture._process(0)
	explorer = load("res://scripts/ui/ObjectExplorerController.gd").new()
	explorer.window_manager_path = NodePath("../Windows")
	explorer.click_tool_paths.append(NodePath("../Furniture"))
	scene.add_child(explorer)
	explorer._window.position = Vector2(24, 150)
	camera = Camera3D.new()
	scene.add_child(camera)
	camera.current = true
	root.get_node("WorldGenerator")._maps_ready = true
	root.size = Vector2i(1280, 800)
	var row_positions: Array[float] = []
	for species_index in range(flora._species.size()):
		var species: Dictionary = flora._species[species_index]
		for stage_index in range(3):
			var stage_name: String = ["sapling", "mature", "ancient"][stage_index]
			var cell := Vector3i(24 + species_index * 24, 20, 24 + stage_index * 24)
			var stage: Dictionary = species.stages[stage_name]
			var path: String = flora.resolve_tree_model_for_season(stage, "spring", cell)
			var node: Node3D = flora._instance_tree(species.name, path, stage_name, stage,
				cell.x, cell.z, cell.y, flora._footprint_for(species.placement, stage_name))
			var id := Vector2i(cell.x, cell.z)
			tree_ids.append(id)
			var column := Vector2i(cell.x >> 4, cell.z >> 4)
			flora._loaded_columns[column] = [node]
			_aim_above(node.position)
			await process_frame
			_expect(explorer.select_at_screen(camera.unproject_position(node.position + Vector3.UP)), "click %s %s" % [species.name, stage_name])
			_expect(explorer._object_id == id, "selected the correct tree")
			await process_frame
			await process_frame
			var data: Dictionary = flora.get_explorer_data(id)
			_expect(data.rows[0] == ["Growth stage", stage_name.capitalize()], "growth stage value")
			var expected_fruit := "Too young" if stage_name == "sapling" else "Out of season"
			_expect(data.rows[1][1] == (expected_fruit if species.name == "apple" else "N/A"), "fruit applicability")
			var positions: Array[float] = []
			for label: Label in explorer._row_values:
				positions.append(label.global_position.y - explorer._window.position.y)
			if row_positions.is_empty():
				row_positions = positions
			_expect(row_positions == positions, "all species/stages use identical row positions")

	# Exact triangles reject empty space within an object's outer bounds.
	var picking = load("res://scripts/components/ObjectPicking.gd").new()
	var sparse := Node3D.new()
	scene.add_child(sparse)
	for x in [-2.0, 2.0]:
		var mesh := MeshInstance3D.new()
		mesh.mesh = BoxMesh.new()
		mesh.position = Vector3(50 + x, 25, 50)
		sparse.add_child(mesh)
	_expect(is_inf(picking.hit_distance(sparse, Vector3(50, 30, 50), Vector3(50, 20, 50))), "empty silhouette space is not selectable")
	sparse.free()

	# Terrain blocks selection even when the object itself is visible.
	var tree_id := tree_ids[0]
	var tree: Dictionary = flora._trees[tree_id]
	var node: Node3D = tree.node
	_aim_above(node.position)
	await process_frame
	var screen := camera.unproject_position(node.position + Vector3.UP)
	for x in range(tree_id.x - 3, tree_id.x + 5):
		for z in range(tree_id.y - 3, tree_id.y + 5):
			world.set_block(x, 40, z, blocks.get_id("base:terrain:rock:rock01"))
	_expect(not explorer.select_at_screen(screen), "terrain occludes trees")
	for x in range(tree_id.x - 3, tree_id.x + 5):
		for z in range(tree_id.y - 3, tree_id.y + 5):
			world.set_block(x, 40, z, blocks.AIR_ID)
	_expect(explorer.select_at_screen(screen), "tree selectable after terrain removal")
	explorer.clear_selection()
	_click(screen)
	await process_frame
	_expect(explorer._object_id == tree_id, "viewport input reaches the shared explorer")
	_click(explorer._window.position + Vector2(100, 16))
	await process_frame
	_expect(explorer._object_id == tree_id, "window input does not select through the UI")
	furniture._active = true
	_expect(not explorer.select_at_screen(screen), "active placement tool owns clicks")
	furniture._active = false
	flora._on_slice_changed(19)
	explorer._on_slice_changed(19)
	_expect(not manager.is_open("object_explorer"), "slice-hidden selection closes")
	_expect(not explorer.select_at_screen(screen), "hidden trees cannot be picked")
	flora._on_slice_changed(127)
	explorer._on_slice_changed(127)

	# Furniture uses the same window and its existing authoritative actions.
	var key := "base:furniture:barrel"
	furniture._install(key, furniture.get_defs()[key], Vector3i(14,20,14), 0)
	var piece = furniture._installed.values()[0]
	_aim_above(piece.node.position)
	await process_frame
	_expect(explorer.select_at_screen(camera.unproject_position(piece.node.position + Vector3.UP * .5)), "click furniture model")
	_expect(explorer._provider == furniture, "furniture provider selected")
	var furniture_id: String = explorer._object_id
	piece.storage.restore_inventory({"base:resources:wood:oak_log":3,
		"base:resources:seed:oak_acorn":27}, items)
	explorer._refresh_selected()
	explorer._storage_panel.refresh()
	_expect("5 / 8 slots" in explorer._storage_panel.info_label.text, "live physical capacity includes two produce crates")
	_expect(explorer._storage_panel.storage == piece.storage and piece.storage.inventory.get("base:resources:seed:oak_acorn", 0) == 27,
		"container inspection uses its authoritative contents")
	explorer._perform_action("uninstall")
	_expect(piece.flagged_uninstall, "uninstall action preserved")
	explorer._perform_action("uninstall")
	_expect(not piece.flagged_uninstall, "cancel uninstall action preserved")
	furniture._teardown_installed(piece.installed_id, true)
	explorer._refresh_selected()
	_expect(furniture.get_explorer_data(furniture_id).is_empty() and not manager.is_open("object_explorer"), "removed object closes explorer")

	items.restore_stored_item("base:resources:seed:oak_acorn",Vector3i(10,20,30),17)
	var crate: Node3D = items.stored_node_at(Vector3i(10,20,30))
	_aim_above(crate.position)
	await process_frame
	_click(camera.unproject_position(crate.position + Vector3(0,.4,0)))
	_expect(explorer._provider == items and explorer._row_values[1].text == "17 / 24", "viewport click inspects crate contents")
	items.set_quantity(crate,3)
	explorer._refresh_selected()
	_expect(explorer._row_values[1].text == "3 / 24" and explorer._outline.visible, "selected crate survives fill-model change")
	items.withdraw_stored(crate,100)
	items.take(crate)
	explorer._refresh_selected()
	_expect(not manager.is_open("object_explorer"), "picked-up crate closes its ground inspector")
	crate.free()

	# Seasonal recreation must preserve the selected logical tree and row layout.
	var apple_id := tree_ids[7] # species order: pine, oak, apple, juniper; mature.
	_expect(explorer.select_object(flora, apple_id), "select apple for season transition")
	flora._ready_to_spawn = true
	flora._on_season_changed("autumn")
	explorer._refresh_selected()
	_expect(manager.is_open("object_explorer") and explorer._object_id == apple_id, "selection survives visual despawn")
	_expect(explorer._row_values[1].text == "In season", "season updates the fruit row")
	await process_frame
	var apple: Dictionary = flora._species[2]
	var autumn_path: String = flora.resolve_tree_model_for_season(apple.stages.mature, "autumn", Vector3i(apple_id.x,20,apple_id.y))
	var replacement: Node3D = flora._instance_tree("apple", autumn_path, "mature", apple.stages.mature, apple_id.x, apple_id.y, 20, 3)
	explorer._refresh_selected()
	_expect(explorer._outline.visible, "outline follows replacement model")
	if "--capture" in OS.get_cmdline_user_args():
		await _capture(replacement, "res://tmp/object_explorer_review/cabinet_fix/apple_explorer.png")
	await _check_cabinet(items, replacement)
	manager.close("object_explorer")
	_expect(explorer._provider == null and not explorer._outline.visible, "close clears selection")
	if failures.is_empty():
		print("OBJECT_EXPLORER_OK: 12 tree stages, exact picking, terrain/slice/tool guards, furniture actions, season continuity, fixed rows")
	else:
		for failure in failures:
			push_error(failure)
	quit(0 if failures.is_empty() else 1)


func _build_floor() -> void:
	var chunk_script = load("res://scripts/systems/Chunk.gd")
	var stone: int = blocks.get_id("base:terrain:rock:rock01")
	for cx in range(8):
		for cz in range(8):
			for cy in range(8):
				var chunk = chunk_script.new()
				for ly in range(16):
					if cy * 16 + ly <= 20:
						for lz in range(16):
							for lx in range(16):
								chunk.blocks[lx + 16 * lz + 256 * ly] = stone
				world.submit_chunk(cx, cy, cz, chunk)


func _check_cabinet(items: Node3D, tree: Node3D) -> void:
	var panel: StyleBoxFlat = explorer._window.get_theme_stylebox("panel")
	_expect(panel.border_color == UITheme.CATALOG_GOLD, "all explorer subjects share cabinet chrome")
	var stone := "base:resources:stone:rough_stone"
	items.spawn_drop(stone, 1, Vector3i(20, 21, 30))
	var item: Node3D = items._loose.keys()[-1]
	for viewport: Vector2i in [Vector2i(960,540), Vector2i(1280,720), Vector2i(2560,1440)]:
		root.size = viewport
		_expect(explorer.select_object(items, item), "resource selection uses cabinet")
		for i in range(6): await process_frame
		# Refresh after text wrapping has resolved its minimum height.
		explorer._refresh_selected()
		for i in range(3): await process_frame
		var window: UIWindow = explorer._window
		_expect(window.get_global_rect().end.x <= viewport.x and window.get_global_rect().end.y <= viewport.y,
			"resource cabinet fits %s" % viewport)
		_expect(explorer._name_label.text == "Rough Stone" and explorer._row_values[1].text == "1", "live resource facts remain")
		_expect(explorer._details.is_visible_in_tree(), "resource description remains visible")
		if "--capture" in OS.get_cmdline_user_args():
			camera.position = item.position + Vector3(12,14,16)
			camera.look_at(item.position)
			await _save_cabinet_capture("rough_stone_%dx%d" % [viewport.x,viewport.y])
		_expect(explorer.select_object(flora, tree.get_meta("tree_id")), "tree selection uses the same cabinet")
		for i in range(6): await process_frame
		explorer._refresh_selected()
		for i in range(3): await process_frame
		_expect(window.get_global_rect().end.y <= viewport.y, "tree facts and actions fit %s" % viewport)
		_expect(explorer._actions.is_visible_in_tree(), "tree actions remain outside the scroll body")
		if "--capture" in OS.get_cmdline_user_args():
			var center: Vector3 = flora.get_explorer_bounds(tree.get_meta("tree_id")).get_center()
			camera.position = center + Vector3(18,13,23)
			camera.look_at(center)
			await _save_cabinet_capture("tree_%dx%d" % [viewport.x,viewport.y])


func _save_cabinet_capture(label: String) -> void:
	for i in range(4): await process_frame
	await RenderingServer.frame_post_draw
	var folder := "res://tmp/object_explorer_review/cabinet_fix"
	DirAccess.make_dir_recursive_absolute(folder)
	root.get_texture().get_image().save_png(folder.path_join(label + ".png"))


func _aim_above(position: Vector3) -> void:
	camera.position = position + Vector3(.1, 65, .1)
	camera.look_at(position + Vector3.UP, Vector3.FORWARD)


func _expect(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)


func _click(position: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = position
		root.push_input(event, true)


func _capture(tree: Node3D, output_path: String = "res://tmp/object_explorer_review/apple_explorer.png") -> void:
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(.12, .16, .19)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = .65
	environment.environment = env
	scene.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	scene.add_child(sun)
	var center: Vector3 = flora.get_explorer_bounds(tree.get_meta("tree_id")).get_center()
	camera.position = center + Vector3(18, 13, 23)
	camera.look_at(center - Vector3(5, 0, 0))
	flora._update_felling_marker_positions()
	for i in range(8):
		await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
	root.get_texture().get_image().save_png(output_path)
