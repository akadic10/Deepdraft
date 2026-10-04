extends "res://scripts/tests/MiningFeedbackTest.gd"

## Native frames: real assigned work, contact events and committed block removal.
func _run() -> void:
	create_timer(90).timeout.connect(func(): quit(1))
	await _setup_mining_feedback()
	feedback.set_muted(true)
	var family := "stone"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--family="):
			family = argument.trim_prefix("--family=")
	var key := "base:terrain:soil:cave" if family == "soil" else "base:terrain:rock:rock01"
	var target := Vector3i(42,22,40)
	mining._mined_blocks[Vector3i(41,22,40)] = true
	await _begin_block(target,key)
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
	rock.mesh = BoxMesh.new()
	var rock_mat := StandardMaterial3D.new()
	rock_mat.albedo_color = blocks.get_color(blocks.get_id(key),clock_node.season)
	rock.material_override = rock_mat
	rock.position = Vector3(target)+Vector3.ONE*.5
	scene.add_child(rock)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 7.6
	var center := Vector3(41.5,22.65,40.5)
	camera.position = center+Vector3(-3,4,7)
	camera.look_at(center)
	var layer := CanvasLayer.new()
	scene.add_child(layer)
	var title := Label.new()
	title.text = "MINING / " + family.to_upper()
	title.position = Vector2(22,18)
	title.add_theme_font_size_override("font_size",23)
	layer.add_child(title)
	var caption := Label.new()
	caption.text = "Contact chips → Block removed → Brief dust puff"
	caption.position = Vector2(22,670)
	caption.add_theme_font_size_override("font_size",17)
	layer.add_child(caption)
	for i in range(8): await process_frame
	root.get_node("SkyController").set_process(false)
	env.ambient_light_energy = .8
	sun.light_energy = 1.4
	# Show the last two authored swings at their real cadence.
	worker._swings_left = mini(worker._swings_left,2)
	var duration: float = worker._swing_timer+(worker._swings_left-1)*worker._swing_time+1.0
	var directory := "res://tmp/mining_feedback_review/"+family
	DirAccess.make_dir_recursive_absolute(directory)
	feedback._rng.seed = 753
	for i in range(ceili(duration*30)):
		feedback._process(1.0/30)
		worker._process(1.0/30)
		rock.visible = world.get_block(target.x,target.y,target.z) != blocks.AIR_ID
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(directory+"/frame_%03d.png" % i)
	var completions := 0
	for event in burst_events:
		if event[1] == "mining_completion": completions += 1
	_expect(completions == 1 and not rock.visible,"preview includes one successful removal puff")
	feedback.clear_transients()
	feedback.set_muted(false)
	print("MINING_FEEDBACK_PREVIEW_OK: ",family,"; actual strike and removal events")
	quit(0 if failures.is_empty() else 1)
