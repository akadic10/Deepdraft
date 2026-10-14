extends SceneTree

## Real generated shoreline, fixed camera/light, advancing only the water clock.
var output := "res://tmp/shoreline_art_20261013/before/"
var before_fix := false
var report := {"seed":1234,"samples":[],"failures":[]}

func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=").trim_suffix("/")+"/"
		if arg == "--before": before_fix = true
	_run.call_deferred()

func _run() -> void:
	if not "/shoreline_art_20261013/" in OS.get_user_data_dir().replace("\\","/"):
		quit(2)
		return
	create_timer(180).timeout.connect(func(): push_error("Shoreline capture timeout"); quit(1))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.size = Vector2i(1600,1000)
	root.get_node("SaveManager").configure_storage_for_testing("user://shoreline_capture")
	root.get_node("SaveManager").set_process(false)
	root.get_node("WorldClock").set_paused(true)
	var scene = load("res://scenes/main/debug_world.tscn").instantiate()
	scene.get_node("Renderer").world_seed = 1234
	var publish = func(node: Node):
		if node == scene: current_scene = scene
	node_added.connect(publish)
	root.add_child(scene)
	node_added.disconnect(publish)
	var gen = root.get_node("WorldGenerator")
	var renderer = scene.get_node("Renderer")
	var water = root.get_node("WaterManager")
	while not gen._maps_ready or not renderer._overview_built or not water.initialized: await process_frame
	while not scene.get_node("SurfaceFloraSpawner")._pending.is_empty(): await process_frame
	if before_fix:
		for node in renderer.get_children():
			if node.get_script() != null and node.get_script().resource_path == "res://scripts/components/MoistureRenderer.gd":
				node.free()
		var old_overlay = load("res://tmp/shoreline_art_20261013/MoistureRendererBefore.gd").new()
		old_overlay.terrain = renderer
		renderer.add_child(old_overlay)
	report["before_fix"] = before_fix
	root.get_node("WeatherManager").set_weather("base:weather:clear")
	var sky = root.get_node("SkyController")
	sky.rebind_to_current_scene()
	sky.set_process(false)
	sky._update(12.0)
	var registry = root.get_node("BlockRegistry")
	var focus := Vector3i(-1,-1,-1)
	var direction := Vector3.FORWARD
	var best := INF
	for cell: Vector3i in water.moisture.soils:
		if cell.y != gen.get_surface_y(cell.x,cell.z): continue
		var id: int = gen.get_generated_block_id(cell.x,cell.y,cell.z)
		if registry.get_def(registry.get_key(id)).get("kind","") != "grass": continue
		for offset: Vector3i in [Vector3i.LEFT,Vector3i.RIGHT,Vector3i.FORWARD,Vector3i.BACK]:
			if water.depth_at(cell+offset-Vector3i.UP) < 0.25: continue
			var distance := Vector3(cell).distance_squared_to(Vector3(gen.river_layout.outlet))
			if distance < best:
				best = distance
				focus = cell
				direction = Vector3(offset)
	if focus.x < 0:
		push_error("No moist grass shoreline found")
		quit(1)
		return
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 22
	scene.add_child(camera)
	camera.position = Vector3(focus)+direction*25+Vector3(direction.z*12,23,-direction.x*12)
	camera.look_at(Vector3(focus)+direction*2)
	camera.make_current()
	scene.get_node("SurfaceFloraSpawner").visible = false
	for layer in scene.find_children("*","CanvasLayer",true,false): layer.visible = false
	report["focus"] = str(focus)
	report["camera"] = str(camera.transform)
	report["trees_hidden_for_diagnostic"] = true
	for seconds in [0,30,90]:
		while water.elapsed < seconds:
			water.step(0.1)
			if water.elapsed_usec%1000000 == 0: await process_frame
		for i in range(20): await process_frame
		var before: Dictionary = water.serialize_state()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output+"shore_%03d.png"%seconds)
		if before != water.serialize_state(): report.failures.append("Capture mutated simulation")
		report.samples.append({"seconds":seconds,"moisture":water.soil_moisture_at(focus),
			"water_state":var_to_bytes(water.serialize_state()).hex_encode().sha256_text()})
	water.show_moisture = true
	for i in range(5): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output+"moisture_debug.png")
	FileAccess.open(output+"report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("SHORELINE_CAPTURE_PASS" if report.failures.is_empty() else "SHORELINE_CAPTURE_FAIL")
	gen.prepare_for_world_reload()
	quit(0 if report.failures.is_empty() else 1)
