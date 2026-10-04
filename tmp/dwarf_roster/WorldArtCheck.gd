extends SceneTree

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	create_timer(60.0).timeout.connect(func(): push_error('Art check timed out'); quit(1))
	root.get_node("SaveManager").set_process(false)
	assert(change_scene_to_file("res://scenes/main/debug_world.tscn") == OK)
	await process_frame
	var world: Node = root.get_node("WorldGenerator")
	var deadline := Time.get_ticks_msec() + 90000
	while Time.get_ticks_msec() < deadline:
		if bool(world.call("get_streaming_stats").get("maps_ready", false)) and not world.call("is_generating"):
			break
		await process_frame
	assert(Time.get_ticks_msec() < deadline)
	root.get_node("WorldClock").call("restore_state", {"year":1,"season":"summer","day":1,"hour":12.0,"speed":1.0,"paused":true})
	root.get_node("SkyController").call("rebind_to_current_scene")
	for node in current_scene.find_children("*", "CanvasLayer", true, false):
		node.hide()
	var flora := current_scene.get_node_or_null('SurfaceFloraSpawner')
	if flora is Node3D: flora.hide()
	var height: float = 0.0
	for x in range(505,520):
		height = maxf(height,float(world.call("get_surface_y",x,491))+1.0)
	var centre := Vector3(512,height,491)
	var platform := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(17,.15,5)
	platform.mesh = mesh
	platform.position = centre-Vector3(0,.08,0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(.40,.43,.41)
	material.roughness = 1.0
	platform.material_override = material
	current_scene.add_child(platform)
	var specs := [["male","short_back",""],["male","short_back","short_trimmed"],["female","braid_side",""],["male","braided_back","full_braided"]]
	for i in range(4):
		var ap := DwarfAppearanceData.new()
		ap.gender = specs[i][0]
		ap.hair_style = specs[i][1]
		ap.beard_style = specs[i][2]
		ap.eyebrow_style = "thin_arched" if i==2 else "arched"
		ap.eye_color = "blue"
		ap.skin_tone = ["medium","medium","pale","dark"][i]
		ap.hair_color = ["brown","brown","red","white"][i]
		var actor: Node3D = load("res://scripts/entities/DwarfAgent.gd").new()
		actor.setup(i, {"gender":ap.gender,"appearance":ap})
		actor.set_process(false)
		actor.position = centre+Vector3((i-1.5)*3.7,0,0)
		actor.rotation_degrees.y = 25
		current_scene.add_child(actor)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 10
	camera.far = 200
	camera.position = centre + Vector3(0,13,23)
	current_scene.add_child(camera)
	camera.look_at(centre+Vector3(0,1.6,0))
	camera.current = true
	for i in range(30):
		await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png("res://tmp/dwarf_roster/renders/live_world.png") == OK)
	print("DWARF_WORLD_ART_OK")
	quit(0)


