extends SceneTree

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(256,256)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var stage := Node3D.new()
	viewport.add_child(stage)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = .7
	stage.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55,-35,0)
	light.light_energy = .9
	stage.add_child(light)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 1.8
	stage.add_child(camera)
	camera.position = Vector3(2,2.6,3)
	camera.look_at(Vector3(.5,.5,.5))
	camera.current = true
	DirAccess.make_dir_recursive_absolute("res://assets/ui/construction")
	for name in ["plank_floor","stone_floor"]:
		var model: Node3D = load("res://assets/models/construction/%s.glb" % name).instantiate()
		# Only the visual meshes: the coarse shadow proxy would otherwise draw over them.
		preload("res://scripts/components/VoxelShadowSetup.gd").set_casting(model,false)
		var material := StandardMaterial3D.new()
		material.vertex_color_use_as_albedo = true
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		for mesh: MeshInstance3D in preload("res://scripts/components/VoxelShadowSetup.gd").visual_meshes(model): mesh.material_override = material
		stage.add_child(model)
		for frame in range(6): await process_frame
		await RenderingServer.frame_post_draw
		viewport.get_texture().get_image().save_png("res://assets/ui/construction/%s.png" % name)
		model.free()
	print("FLOOR_ICONS_OK")
	quit()
