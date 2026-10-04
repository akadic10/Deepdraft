extends "res://scripts/tests/ObjectExplorerTest.gd"

## Native Godot render, real item materials, one-tile bounds and all fill levels.
func _run() -> void:
	for name in ["SaveManager","TaskManager","WorldClock","RoomManager","StockpileManager"]:
		root.get_node(name).set_process(false)
	world = root.get_node("WorldData")
	blocks = root.get_node("BlockRegistry")
	_build_floor()
	scene = Node3D.new()
	root.add_child(scene)
	current_scene = scene
	root.size = Vector2i(1600,1000)
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(.10,.125,.14)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = .7
	environment.environment = env
	scene.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50,-30,0)
	sun.light_energy = 1.1
	scene.add_child(sun)
	var drops = load("res://scripts/systems/ItemDropManager.gd").new()
	scene.add_child(drops)
	var layer := CanvasLayer.new()
	scene.add_child(layer)
	_label(layer,"PRODUCE CRATES",Vector2(38,25),29)
	_label(layer,"One storage tile · Up to 24 goods of one type · Same crate for loose and stored goods",Vector2(38,69),20)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(.27,.32,.30)
	var ground := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(14,.08,12)
	ground.mesh = box
	ground.material_override = material
	ground.position = Vector3(27,20.95,25)
	scene.add_child(ground)
	camera = Camera3D.new()
	scene.add_child(camera)
	camera.current = true
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 13.2
	var center := Vector3(27,21.2,25.7)
	camera.position = center + Vector3(.7,13,12)
	camera.look_at(center)
	drops.get_item_def("base:resources:seed:oak_acorn")
	var index := 0
	for key: String in drops._defs:
		if drops.item_capacity(key) <= 1:
			continue
		# Inspect every authored fill level, not only the full variant shown here.
		for count in [1,12,24]:
			var test_node: Node3D = drops.create_item_visual(key,count)
			scene.add_child(test_node)
			var bounds: AABB = load("res://scripts/components/ObjectPicking.gd").world_bounds(test_node)
			_expect(bounds.size.x <= 1 and bounds.size.z <= 1 and is_zero_approx(bounds.position.y), "%s/%d fits a single tile" % [key,count])
			test_node.free()
		var position := Vector3(22.2 + float(index % 5)*2.4,21,21 + float(index / 5)*2.4)
		_show_crate(drops,layer,key,24,position,String(drops.get_item_def(key).display_name))
		index += 1
	for i in range(3):
		_show_crate(drops,layer,"base:resources:flora:apple",[1,12,24][i],Vector3(24.6+i*2.4,21,29),["1 / 24","12 / 24","24 / 24"][i])
	_expect(drops._missing_models.is_empty(), "every crate model is imported")
	_label(layer,"16 voxels per block · Chunky wood frame, distinct contents · Three fill levels; explorer shows the exact count",Vector2(38,942),18)
	for i in range(8):
		await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://tmp/produce_crate_review")
	root.get_texture().get_image().save_png("res://tmp/produce_crate_review/crates.png")
	for failure in failures:
		push_error(failure)
	if failures.is_empty():
		print("PRODUCE_CRATE_ART_OK: 45 imported models, shared silhouette, all contents/fill levels, native material, one-tile bounds")
	quit(0 if failures.is_empty() else 1)


func _show_crate(drops,layer,key: String,count: int,position: Vector3,title: String) -> void:
	var node: Node3D = drops.create_item_visual(key,count)
	scene.add_child(node)
	node.position = position
	var grid := MeshInstance3D.new()
	grid.mesh = load("res://scripts/components/ObjectPicking.gd").outline_mesh(
		AABB(Vector3(position.x-.5,21.002,position.z-.5),Vector3(1,.008,1)),Color(.54,.65,.60))
	scene.add_child(grid)
	var label := _label(layer,title,Vector2.ZERO,17)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = camera.unproject_position(position+Vector3(0,0,.75))-Vector2(label.get_minimum_size().x/2,0)


func _label(layer,text: String,position: Vector2,size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.position = position
	label.add_theme_font_size_override("font_size",size)
	layer.add_child(label)
	return label
