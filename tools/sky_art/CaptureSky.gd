extends "res://tools/terrain_art/CaptureTerrain.gd"

## Native production-scene sky review. Never uses the player's save directory.
func _run() -> void:
	if not "/sky_art_20261013/" in OS.get_user_data_dir().replace("\\", "/"):
		push_error("Sky review requires isolated APPDATA"); quit(2); return
	create_timer(300).timeout.connect(func(): push_error("Sky review timed out"); quit(1))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.size = Vector2i(1600, 1000)
	root.get_node("SaveManager").configure_storage_for_testing("user://sky_review")
	root.get_node("SaveManager").set_process(false)
	var clock = root.get_node("WorldClock")
	clock.set_paused(true)
	clock.season = "summer"
	clock.day = 2
	clock.hour = 0.7667
	node_added.connect(func(node: Node):
		if node.name == "Renderer" and node.get_script() != null: node.set("world_seed", 1234))
	change_scene_to_file("res://scenes/main/debug_world.tscn")
	await process_frame
	generator = root.get_node("WorldGenerator")
	while not generator._maps_ready or generator.is_generating(): await process_frame
	renderer = current_scene.get_node("Renderer")
	await _settle()
	while not current_scene.get_node("SurfaceFloraSpawner")._pending.is_empty(): await process_frame
	var rig = current_scene.get_node("CameraRig")
	rig.set_process(false)
	camera = rig.camera_node
	camera.reparent(current_scene)
	camera.current = true
	var sky = root.get_node("SkyController")
	sky.rebind_to_current_scene()
	sky._refresh_event_hours()
	sky._build_curves()
	sky.set_process(false)
	root.get_node("WeatherManager").set_process(false)
	var target := Vector3(512, 55, 512)
	var peak: Array = generator._macro_layout.metrics.summit_center
	target = Vector3((float(peak[0]) + .5) * 32, 60, (float(peak[1]) + .5) * 32)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = 70
	for sample in [["night", 0.7667], ["dawn", 6.0], ["day", 14.0], ["dusk", 22.0]]:
		_set_sky(float(sample[1]), "clear")
		camera.position = target + Vector3(-180, 55, 210)
		camera.look_at(target + Vector3(0, 50, 0))
		await _capture(String(sample[0]) + "_landscape")
	_set_sky(0.7667, "clear")
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	for i in range(4):
		var angle := float(i) * PI / 2.0
		_view(target, 500, Vector3(sin(angle), .85, cos(angle)))
		await _capture("night_orbit_" + str(i))
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.position = target + Vector3(0, 350, 0)
	for direction in [Vector3(0, .3, -1), Vector3(0, -.6, -1), Vector3(.01, 1, .01), Vector3(.01, -1, .01)]:
		camera.look_at(camera.position + direction)
		await _capture("sphere_" + str(report.captures.size()))
	for weather in ["overcast", "foggy", "snow"]:
		_set_sky(0.7667, weather)
		camera.position = target + Vector3(-180, 55, 210)
		camera.look_at(target + Vector3(0, 50, 0))
		await _capture(weather + "_night")
		_set_sky(14.0, weather)
		await _capture(weather + "_day")
	report["events"] = sky.current_event_hours()
	report["adapter"] = RenderingServer.get_video_adapter_name()
	FileAccess.open(output + "report.json", FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print("SKY_CAPTURE_PASS ", output)
	generator.prepare_for_world_reload()
	quit()

func _set_sky(hour: float, weather: String) -> void:
	root.get_node("WorldClock").hour = hour
	root.get_node("WeatherManager").set_weather("base:weather:" + weather)
	var sky = root.get_node("SkyController")
	for i in range(220): sky._update(hour)
	renderer.underground_lighting._sync_fog()

func _capture(label: String) -> void:
	# This harness freezes SkyController between samples, including projection changes.
	root.get_node("SkyController")._update(root.get_node("WorldClock").hour)
	await super._capture(label)
