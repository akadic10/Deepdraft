extends "res://tools/terrain_art/CaptureTerrain.gd"

## Run with an isolated APPDATA containing /ambience_20261013/.
## Captures native game mixer output only, never a microphone.
func _run() -> void:
	if not "/ambience_20261013/" in OS.get_user_data_dir().replace("\\", "/"):
		push_error("Ambience review requires an isolated APPDATA"); quit(2); return
	output = "res://tmp/ambience_20261013/world/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	create_timer(240).timeout.connect(func(): push_error("World ambience review timed out"); quit(1))
	root.size = Vector2i(1280, 800)
	var saves = root.get_node("SaveManager")
	saves.configure_storage_for_testing("user://ambience_review")
	saves.set_process(false)
	var clock = root.get_node("WorldClock")
	clock.set_process(false)
	clock.set_paused(true)
	node_added.connect(func(node: Node):
		if node.name == "Renderer" and node.get_script() != null: node.set("world_seed", 1234))
	change_scene_to_file("res://scenes/main/debug_world.tscn")
	await process_frame
	generator = root.get_node("WorldGenerator")
	while not generator._maps_ready or generator.is_generating(): await process_frame
	renderer = current_scene.get_node("Renderer")
	await _settle()
	var flora = current_scene.get_node("SurfaceFloraSpawner")
	while not flora._pending.is_empty(): await process_frame
	var rig = current_scene.get_node("CameraRig")
	rig.set_process(false)
	camera = rig.camera_node
	var centre := Vector3(512, 50, 512)
	for tree: Dictionary in flora._trees.values():
		if not is_instance_valid(tree.node): continue
		var point := Vector3(tree.cell) + Vector3(5, 1, 5)
		if point.distance_to(centre) < 120 and flora.ambient_tree_density(point, 38, 12) > .45:
			centre = point
			break
	rig.global_position = centre
	camera.reparent(current_scene)
	camera.position = centre + Vector3(34, 40, 40)
	camera.look_at(centre)
	camera.current = true
	var ambience = root.get_node("AmbientAudio")
	ambience.set_process(false)
	ambience.set_volume("ambience", .72)
	ambience.set_muted("ambience", false)
	var sky = root.get_node("SkyController")
	sky.rebind_to_current_scene()
	var weather = root.get_node("WeatherManager")
	weather.set_weather("base:weather:clear")
	clock.season = "summer"
	clock.day = 2
	clock.set_paused(false)
	clock.set_process(false)
	var record := AudioEffectRecord.new()
	record.format = AudioStreamWAV.FORMAT_16_BITS
	# On Master, these previews include the actual player-volume setting.
	root.get_node("WorkFeedback").set_muted(true)
	AudioServer.add_bus_effect(0, record)
	var result := {"checks": [], "position": [centre.x, centre.y, centre.z]}
	for label: String in ["day", "night"]:
		clock.hour = 14 if label == "day" else 1
		sky._refresh_event_hours()
		sky._update(clock.hour)
		ambience._scan_left = 0
		for i in 40: ambience._process(1)
		for voice: Dictionary in ambience.calls:
			voice.player.stop()
			voice.left = 0
		ambience._start_call("birds" if label == "day" else "owls")
		var samples: Array[int] = []
		for i in 40:
			var start := Time.get_ticks_usec()
			ambience._scan_environment()
			samples.append(Time.get_ticks_usec() - start)
		samples.sort()
		result[label] = {"targets": ambience.targets.duplicate(), "forest": ambience._forest, "exposure": ambience._exposure, "scan_max_usec": samples.back(), "scan_median_usec": samples[20]}
		ambience.set_process(true)
		await create_timer(.25).timeout
		record.set_recording_active(true)
		await create_timer(14).timeout
		record.set_recording_active(false)
		record.get_recording().save_to_wav(output + label + ".wav")
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output + label + ".png")
		ambience.set_process(false)
		if ambience._exposure > .9 and ambience._forest > 0 and ambience.loops.wind.gain > .01:
			result.checks.append(label + " production environment is audible")
		else: push_error("World ambience failed: " + label)
	AudioServer.remove_bus_effect(0, AudioServer.get_bus_effect_count(0) - 1)
	root.get_node("WorkFeedback").set_muted(false)
	# A cut through intact rock must not sound like an open-air clearing.
	current_scene.get_node("SliceController").activate()
	current_scene.get_node("SliceController")._set_slice_y(floori(centre.y) - 8)
	ambience._scan_environment()
	result["cut_exposure"] = ambience._exposure
	if ambience._exposure == 0: result.checks.append("rock slice suppresses exterior audio")
	else: push_error("Rock slice leaked exterior ambience")
	var file := FileAccess.open(output + "report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	print("AMBIENCE_WORLD_", "OK" if result.checks.size() == 3 else "FAIL", " ", result)
	quit(0 if result.checks.size() == 3 else 1)
