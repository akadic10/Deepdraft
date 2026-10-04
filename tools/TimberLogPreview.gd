extends "res://scripts/tests/ObjectExplorerTest.gd"

## Real item material and native-scale drops; no player saves or layout writes.
func _run() -> void:
	root.get_node("SaveManager").set_process(false)
	root.get_node("TaskManager").set_process(false)
	root.get_node("WorldClock").set_process(false)
	root.get_node("RoomManager").set_process(false)
	world = root.get_node("WorldData")
	blocks = root.get_node("BlockRegistry")
	_build_floor()
	scene = Node3D.new()
	root.add_child(scene)
	current_scene = scene
	root.size = Vector2i(1600, 1000)
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(.105, .13, .14)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = .65
	environment.environment = env
	scene.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50,-30,0)
	sun.light_energy = 1.1
	scene.add_child(sun)
	var items = load("res://scripts/systems/ItemDropManager.gd").new()
	scene.add_child(items)
	var layer := CanvasLayer.new()
	scene.add_child(layer)
	var title := Label.new()
	title.text = "RAW TIMBER   /   ONE TILE PER LOG"
	title.position = Vector2(36,28)
	title.add_theme_font_size_override("font_size", 27)
	layer.add_child(title)
	var caption := Label.new()
	caption.text = "Oak · Pine · Apple · Juniper     |     Bark, cut ends and species colors     |     1 × 1 stockpile cells"
	caption.position = Vector2(36,70)
	caption.add_theme_font_size_override("font_size", 19)
	layer.add_child(caption)
	var labels: Array[Label] = []
	var positions: Array[Vector3] = []
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(.3,.34,.31)
	var ground := MeshInstance3D.new()
	var ground_mesh := BoxMesh.new()
	ground_mesh.size = Vector3(12,.12,7)
	ground.mesh = ground_mesh
	ground.material_override = material
	ground.position = Vector3(26,20.93,25)
	scene.add_child(ground)
	var index := 0
	for item in ["oak_log", "pine_log", "apple_wood", "juniper_log"]:
		var cell := Vector3i(23+index*2,20,25)
		var key: String = "base:resources:wood:" + item
		items.spawn_drop(key, 1, cell + Vector3i.UP)
		var node: Node3D = items.get_children().back()
		items.place_stored(node, cell)
		var bounds: AABB = load("res://scripts/components/ObjectPicking.gd").world_bounds(node)
		_expect(bounds.size.x <= 1.0 and bounds.size.z <= 1.0 and is_equal_approx(bounds.position.y,21.0), "%s fits its tile and rests on ground" % item)
		_expect(not items._missing_models.has(items.get_item_def(key).model), "%s uses an imported model" % item)
		var grid := MeshInstance3D.new()
		grid.mesh = load("res://scripts/components/ObjectPicking.gd").outline_mesh(
			AABB(Vector3(cell.x,21.005,cell.z),Vector3(1,.008,1)), Color(.65,.72,.61))
		scene.add_child(grid)
		positions.append(Vector3(cell.x+.5,21,cell.z+.5))
		var label := Label.new()
		label.text = items.get_item_def(key).display_name
		label.add_theme_font_size_override("font_size",22)
		layer.add_child(label)
		labels.append(label)
		index += 1
	camera = Camera3D.new()
	scene.add_child(camera)
	camera.current = true
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 8.6
	var center := Vector3(26.5,21.2,25.5)
	camera.position = center + Vector3(1.4,5.3,8)
	camera.look_at(center)
	for i in range(labels.size()):
		labels[i].position = camera.unproject_position(positions[i] + Vector3(0,0,1)) - Vector2(50,0)
	for i in range(8):
		await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://tmp/tree_felling_review")
	root.get_texture().get_image().save_png("res://tmp/tree_felling_review/timber.png")
	for failure in failures:
		push_error(failure)
	if failures.is_empty():
		print("TIMBER_MODELS_OK: four imported items, native material, 1x1 cells, ground contact")
	quit(0 if failures.is_empty() else 1)
