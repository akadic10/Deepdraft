extends "res://scripts/tests/WorkFeedbackTest.gd"

## Native frames from the real work/completion path, with immediate log drops.
func _run() -> void:
	await _setup_feedback_fixture()
	feedback.set_muted(true) # Offline frame capture; the WAV sampler is separate.
	root.size = Vector2i(1050,780)
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(.16,.21,.18)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = .8
	environment.environment = env
	scene.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48,-35,0)
	sun.light_energy = 1.3
	scene.add_child(sun)
	var ground := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(28,.1,28)
	ground.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(.43,.5,.34)
	ground.material_override = mat
	ground.position = Vector3(41,20.94,41)
	scene.add_child(ground)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 13.5
	var center := Vector3(41.5,23,41.5)
	camera.position = center+Vector3(-14,12,-16)
	camera.look_at(center)
	var layer := CanvasLayer.new()
	scene.add_child(layer)
	var title := Label.new()
	title.text = "TREE FELLING / COMPLETION DUST"
	title.position = Vector2(25,20)
	title.add_theme_font_size_override("font_size",24)
	layer.add_child(title)
	var caption := Label.new()
	caption.text = "Last axe swing → brief dust and bark burst → logs ready to haul"
	caption.position = Vector2(25,732)
	caption.add_theme_font_size_override("font_size",18)
	layer.add_child(caption)
	for i in range(8):
		await process_frame
	root.get_node("SkyController").set_process(false)
	env.ambient_light_energy = .8
	sun.light_energy = 1.3
	var source: RefCounted = flora._felling_sources[Vector2i(40,40)]
	source.state.work_seconds = float(source.duration)-1.15
	feedback._rng.seed = 1874
	var directory := "res://tmp/chopping_feedback_review"
	DirAccess.make_dir_recursive_absolute(directory)
	for i in range(96):
		feedback._process(1.0/30)
		worker._process(1.0/30)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(directory+"/frame_%03d.png" % i)
	_expect(burst_events.size() == 1,"preview shows one real completion")
	_expect(_item_count("base:resources:wood:oak_log") == 4,"preview includes real log drops")
	feedback.clear_transients()
	feedback.set_muted(false)
	for i in range(8):
		await process_frame
	print("CHOPPING_FEEDBACK_PREVIEW_OK: real last swing, completion poof, immediate logs, cleanup")
	quit(0 if failures.is_empty() else 1)
