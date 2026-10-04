extends "res://scripts/tests/MiningAnimationTest.gd"

func _run() -> void:
	await _setup_mining_fixture()
	var view := "wall"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--case="):
			view = argument.trim_prefix("--case=")
	var target := Vector3i(42,22,40)
	if view == "high": target.y = 25
	if view == "low": target.y = 19
	if view == "underfoot": target = Vector3i(41,20,40)
	if view == "low": world.set_block(42,20,40,blocks.AIR_ID)
	await _begin_block(target)
	mining._zones_root.hide()
	root.size = Vector2i(780,720)
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(.14,.18,.2)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = .8
	environment.environment = env
	scene.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48,-35,0)
	sun.light_energy = 1.4
	scene.add_child(sun)
	var ground := MeshInstance3D.new()
	var ground_box := BoxMesh.new()
	ground_box.size = Vector3(7,.3,7)
	ground.mesh = ground_box
	var ground_mat := StandardMaterial3D.new()
	ground_mat.albedo_color = Color(.34,.39,.4)
	ground.material_override = ground_mat
	ground.position = Vector3(38.5,20.82,40.5)
	scene.add_child(ground)
	var rock := MeshInstance3D.new()
	var rock_box := BoxMesh.new()
	rock_box.size = Vector3.ONE
	rock.mesh = rock_box
	var rock_mat := StandardMaterial3D.new()
	rock_mat.albedo_color = Color(.57,.6,.62)
	rock.material_override = rock_mat
	rock.position = Vector3(target)+Vector3.ONE*.5
	scene.add_child(rock)
	camera = Camera3D.new()
	scene.add_child(camera)
	camera.current = true
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 7.6
	var center := Vector3(41.5,22.65,40.5)
	camera.position = center+Vector3(-3,4,7)
	camera.look_at(center)
	var layer := CanvasLayer.new()
	scene.add_child(layer)
	var title := Label.new()
	title.text = "MINING / " + view.to_upper()
	title.position = Vector2(22,18)
	title.add_theme_font_size_override("font_size",23)
	layer.add_child(title)
	var caption := Label.new()
	caption.text = "Visible pick · Two-handed grip · Targeted strike"
	caption.position = Vector2(22,670)
	caption.add_theme_font_size_override("font_size",17)
	layer.add_child(caption)
	for i in range(8): await process_frame
	root.get_node("SkyController").set_process(false)
	env.ambient_light_energy = .8
	sun.light_energy = 1.4
	var directory := "res://tmp/mining_animation_review/"+view
	DirAccess.make_dir_recursive_absolute(directory)
	for i in range(36):
		worker._mining_pose.apply(float(i)/35,worker._mine_contact)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(directory+"/frame_%02d.png" % i)
	print("DWARF_MINING_PREVIEW_OK: ",view,"; native grip and point, actual assigned mining job")
	quit(0 if failures.is_empty() else 1)
