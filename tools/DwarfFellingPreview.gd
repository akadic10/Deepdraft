extends "res://scripts/tests/TreeFellingTest.gd"

## Native in-engine work animation capture. All world/save state is isolated.
func _run() -> void:
	for name in ["SaveManager","RoomManager","StockpileManager"]:
		root.get_node(name).set_process(false)
	clock_node = root.get_node("WorldClock")
	clock_node.set_process(false)
	clock_node.set_paused(false)
	clock_node.set_speed(1)
	tasks = root.get_node("TaskManager")
	tasks.set_process(false)
	root.get_node("WorldGenerator").world_seed = 1234
	world = root.get_node("WorldData")
	blocks = root.get_node("BlockRegistry")
	_build_floor()
	scene = Node3D.new()
	root.add_child(scene)
	current_scene = scene
	root.size = Vector2i(1100,850)
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(.13,.18,.17)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = .75
	environment.environment = env
	scene.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45,-30,0)
	sun.light_energy = 1.4
	scene.add_child(sun)
	var ground := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(24,.1,24)
	ground.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(.37,.43,.31)
	ground.material_override = material
	ground.position = Vector3(41,20.94,41)
	scene.add_child(ground)
	flora = load("res://scripts/systems/SurfaceFloraSpawner.gd").new()
	scene.add_child(flora)
	flora.set_process(false)
	flora._season = "summer"
	_spawn_tree("oak","mature",Vector2i(40,40))
	flora.designate_felling(Vector2i(40,40))
	var factory = load("res://scripts/entities/DwarfFactory.gd").new()
	var data: Dictionary = factory.generate(101,{})
	data.appearance.beard_style = "full_braided"
	data.appearance.gender = "male"
	data.appearance.hair_color = "brown"
	data.appearance.hair_style = "short_back"
	data.gender = "male"
	worker = factory.spawn(data,101)
	scene.add_child(worker)
	worker.position = Vector3(41.5,21,39.5)
	worker.set_process(false)
	tasks.register_dwarf(worker)
	_expect(await _until_working(),"preview uses a real assigned felling job")
	camera = Camera3D.new()
	scene.add_child(camera)
	camera.current = true
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 6.6
	var center: Vector3 = worker.position + Vector3(0,1.45,.1)
	camera.position = center + Vector3(-6,4,-7)
	if "--side" in OS.get_cmdline_user_args():
		camera.position = center + Vector3(-7,3,1)
	camera.look_at(center)
	var layer := CanvasLayer.new()
	scene.add_child(layer)
	var title := Label.new()
	title.text = "TREE FELLING  /  WORK AXE"
	title.position = Vector2(28,22)
	title.add_theme_font_size_override("font_size",25)
	layer.add_child(title)
	var caption := Label.new()
	caption.text = "Two-handed grip · Wind-up, strike, recovery · No tool inventory required"
	caption.position = Vector2(28,805)
	caption.add_theme_font_size_override("font_size",18)
	layer.add_child(caption)
	# Wait for autoload binding, then keep the review lighting fixed.
	for i in range(8):
		await process_frame
	root.get_node("SkyController").set_process(false)
	env.ambient_light_energy = .75
	sun.light_energy = 1.4
	var directory := "res://tmp/dwarf_felling_review"
	if "--side" in OS.get_cmdline_user_args():
		directory += "/side"
	DirAccess.make_dir_recursive_absolute(directory)
	for i in range(36):
		worker._felling_pose.apply(float(i)/36.0,worker._fell_contact)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(directory+"/frame_%02d.png" % i)
	print("DWARF_FELLING_PREVIEW_OK: native render, actual tree contact, 36-frame cycle")
	quit(0 if failures.is_empty() else 1)
