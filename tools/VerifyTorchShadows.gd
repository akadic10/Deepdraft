extends SceneTree

## GPU check in the isolated torch project. Uses the same TerrainLighting helper
## as all four live terrain mesh paths; compares a receiver behind a rock wall.
func _init() -> void:
	_run.call_deferred()

func _box(parent: Node3D, at: Vector3, size: Vector3) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var shape := BoxMesh.new()
	shape.size = size
	mesh.mesh = shape
	mesh.position = at
	var material := StandardMaterial3D.new()
	material.albedo_color = Color.WHITE
	material.roughness = 1
	mesh.material_override = material
	parent.add_child(mesh)
	return mesh

func _sample() -> float:
	for frame in range(5):
		await process_frame
	await RenderingServer.frame_post_draw
	var capture := root.get_texture().get_image()
	var center := capture.get_size()/2
	var value := 0.0
	for x in range(center.x-3,center.x+4):
		for y in range(center.y-3,center.y+4):
			value += capture.get_pixel(x,y).get_luminance()
	return value/49.0

func _run() -> void:
	root.size = Vector2i(640,480)
	var helper = load("res://TerrainLighting.gd")
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	environment.environment = env
	scene.add_child(environment)
	var floor_mesh := _box(scene,Vector3(0,-.1,0),Vector3(12,.2,12))
	floor_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var wall := _box(scene,Vector3(0,2,-1),Vector3(6,4,.25))
	helper.configure_mesh(wall)
	var light := OmniLight3D.new()
	light.position = Vector3(0,2,0)
	light.omni_range = 8
	light.light_energy = 2
	light.shadow_enabled = true
	scene.add_child(light)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3
	camera.position = Vector3(0,5,-6)
	camera.current = true
	scene.add_child(camera)
	camera.look_at(Vector3(0,0,-3))
	assert((camera.cull_mask & helper.TERRAIN_LAYER)!=0)
	assert((light.light_cull_mask & helper.TERRAIN_LAYER)!=0)
	var occluded: float = await _sample()
	wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var leaking: float = await _sample()
	helper.configure_mesh(wall)
	light.shadow_caster_mask &= ~helper.TERRAIN_LAYER
	var excluded: float = await _sample()
	var sun := DirectionalLight3D.new()
	var original_mask := sun.light_cull_mask
	helper.configure_sun(sun)
	assert((sun.shadow_caster_mask & helper.TERRAIN_LAYER)==0 and sun.light_cull_mask==original_mask)
	sun.free()
	var passed := leaking>.05 and occluded<leaking*.1 and is_equal_approx(leaking,excluded)
	var report := {"renderer":RenderingServer.get_video_adapter_name(),"behind_wall_luminance":occluded,
		"terrain_shadows_off_luminance":leaking,"terrain_excluded_luminance":excluded,
		"wall_blocks_local_light":passed,"sun_light_mask_preserved":true,"sun_omits_terrain_shadows":true}
	var file := FileAccess.open("res://shadow_checks.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  ")+"\n")
	file.close()
	print("TORCH_GPU_SHADOW_CHECK: ",JSON.stringify(report))
	quit(0 if passed else 1)
