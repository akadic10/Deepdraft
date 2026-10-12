extends "res://scripts/tests/HaulingAnimationTest.gd"

var cover_meshes: Array[Node3D] = []

func _run() -> void:
	create_timer(90).timeout.connect(func(): push_error("Readability timeout"); quit(1))
	await _setup_fixture()
	tasks.reset_runtime_state()
	stockpiles.reset_runtime_state()
	worker._idle_behavior.cancel()
	worker.position = Vector3(49.5,21,50.5)
	worker.rotation.y = .3
	var helper = worker.get_node("Readability")
	helper.set_process(false)
	helper.refresh()
	_expect(helper.material.get_shader_parameter("cover_count")==0,"open ground has no silhouette cover")
	var before: Vector3 = worker.position
	var stone: int = blocks.get_id("base:terrain:rock:rock01")
	for x in range(46,51):
		for y in range(21,25): world.set_block(x,y,51,stone)
	helper.refresh()
	_expect(helper.material.get_shader_parameter("cover_count")>0,"nearby wall supplied to bounded silhouette")
	_expect(worker.position==before and root.get_node("NavGrid").is_walkable(worker.current_cell()),"readability does not move dwarf or change navigation")
	worker.apply_slice(19)
	for mesh in worker.find_children("OccludedSilhouette","MeshInstance3D",true,false):
		_expect(not mesh.is_visible_in_tree(),"slice hides silhouette with actor")
	worker.apply_slice(127)
	if "--capture" in OS.get_cmdline_user_args():
		_setup_view()
		_box(Vector3(48.5,23,51.5),Vector3(5,4,1),Color("62666c"))
		await _capture_pair("wall")
		for mesh in cover_meshes: mesh.free()
		cover_meshes.clear()
		for x in range(46,51):
			for y in range(21,25): world.set_block(x,y,51,blocks.AIR_ID)
		helper.refresh()
		await _capture_pair("open")
		root.get_node("NavGrid").set_ladder(7,Vector3i(49,20,51),8,Vector3i.FORWARD,1.0)
		for x in [49.1,49.85]: _box(Vector3(x,23,51.5),Vector3(.15,4,.15),Color("745735"))
		for y in range(21,25): _box(Vector3(49.5,y+.5,51.5),Vector3(.85,.13,.15),Color("a08356"))
		helper.refresh()
		await _capture_pair("ladder")
		root.get_node("NavGrid").remove_ladder(7)
		# A thick wall hides dwarves entirely once the actual cover exceeds 2.5 blocks.
		for mesh in cover_meshes: mesh.free()
		cover_meshes.clear()
		for x in range(46,54):
			for z in range(51,56):
				for y in range(21,27): world.set_block(x,y,z,stone)
		_box(Vector3(50,24,53.5),Vector3(8,6,5),Color("62666c"))
		helper.refresh()
		await _capture_pair("deep")
	for failure: String in failures: push_error(failure)
	print("DWARF_READABILITY_OK: nearby cover only, navigation unchanged, slice hidden, native wall/ladder/open/deep checks" if failures.is_empty() else "DWARF_READABILITY_FAIL")
	quit(0 if failures.is_empty() else 1)

func _setup_view() -> void:
	root.size = Vector2i(1000,760)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("333c3f")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = .65
	scene.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50,-35,0)
	sun.shadow_enabled = true
	scene.add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.mesh = BoxMesh.new()
	floor_mesh.mesh.size = Vector3(22,1,22)
	floor_mesh.position = Vector3(50,20.5,50)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("789068")
	floor_mesh.material_override = mat
	scene.add_child(floor_mesh)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 9
	scene.add_child(camera)
	camera.position = Vector3(60,29,63)
	camera.look_at(worker.position+Vector3(0,1.5,0))
	camera.current = true

func _capture_pair(label: String) -> void:
	var pictures: Array[Image] = []
	for enabled in [false,true]:
		for mesh in worker.find_children("OccludedSilhouette","MeshInstance3D",true,false): mesh.visible = enabled
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var picture := root.get_texture().get_image()
		picture.save_png("res://tmp/bedroom_20261011/%s_%s.png" % [label,"on" if enabled else "off"])
		pictures.append(picture)
	var changed := 0
	for y in pictures[0].get_height():
		for x in pictures[0].get_width():
			var delta := pictures[0].get_pixel(x,y)-pictures[1].get_pixel(x,y)
			if absf(delta.r)+absf(delta.g)+absf(delta.b)>.03: changed += 1
	_expect(changed>100 if label in ["wall","ladder"] else changed<10,"pixel difference for %s: %d" % [label,changed])
	print("Readability pixels ",label,": ",changed)

func _box(at: Vector3, size: Vector3, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	mesh.mesh.size = size
	mesh.position = at
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mesh.material_override = mat
	scene.add_child(mesh)
	cover_meshes.append(mesh)
