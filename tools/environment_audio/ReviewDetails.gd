extends "res://tools/terrain_art/CaptureTerrain.gd"

## Isolated generated-world listening and weather review, never player saves.
func _run() -> void:
	if not "/environment_details_20261013/" in OS.get_user_data_dir().replace("\\","/"):
		push_error("Details review requires isolated APPDATA"); quit(2); return
	output = "res://tmp/environment_details_20261013/world/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	create_timer(240).timeout.connect(func(): push_error("Details world review timed out"); quit(1))
	root.size = Vector2i(1440,900)
	var saves = root.get_node("SaveManager")
	saves.configure_storage_for_testing("user://details_review")
	saves.set_process(false)
	var clock = root.get_node("WorldClock")
	clock.set_process(false)
	clock.set_paused(true)
	root.get_node("WorldGenerator").world_seed = 1234
	node_added.connect(func(node: Node):
		if node.name == "Renderer" and node.get_script() != null: node.world_seed = 1234)
	change_scene_to_file("res://scenes/main/debug_world.tscn")
	await process_frame
	generator = root.get_node("WorldGenerator")
	while not generator._maps_ready or generator.is_generating(): await process_frame
	var water = root.get_node("WaterManager")
	while not water.initialized: await process_frame
	water.set_process(false)
	renderer = current_scene.get_node("Renderer")
	var rig = current_scene.get_node("CameraRig")
	rig.set_process(false)
	camera = rig.camera_node
	camera.reparent(current_scene)
	camera.current = true
	var ambience = root.get_node("AmbientAudio")
	var centre := Vector3.ZERO
	for key: Vector3i in water.flow.mass:
		if key.y > 50: continue
		var point := Vector3(key.x+.5,water.flow.level(key)+.05,key.z+.5)
		if point.y <= generator.get_surface_y(key.x,key.z): continue
		var sources: Dictionary = ambience._sources.scan(point,127,18,null,null)
		if sources.has("shoreline"):
			centre = sources.shoreline.point
			break
	if centre == Vector3.ZERO: push_error("No shore for review"); quit(1); return
	rig.global_position = centre
	camera.position = centre + Vector3(16,23,23)
	camera.look_at(centre)
	ambience.set_volume("ambience", .72)
	ambience.set_muted("ambience", false)
	root.get_node("WorkFeedback").set_muted(true)
	var sky = root.get_node("SkyController")
	sky.rebind_to_current_scene()
	var weather = root.get_node("WeatherManager")
	var record := AudioEffectRecord.new()
	record.format = AudioStreamWAV.FORMAT_16_BITS
	AudioServer.add_bus_effect(0,record)
	var result := {}
	for label: String in ["shore_night","autumn","winter","rain","storm"]:
		clock.season = label if label in ["autumn","winter"] else "summer"
		clock.hour = 1 if label == "shore_night" else 14
		clock.set_paused(false)
		sky._refresh_event_hours()
		weather.set_weather("base:weather:" + label if label in ["rain","storm"] else "base:weather:snow" if label == "winter" else "base:weather:clear")
		for i in 120: await process_frame
		ambience._scan_left = 0
		for i in 35: ambience._process(1)
		for voice: Dictionary in ambience.calls: voice.player.stop(); voice.left = 0
		if label == "shore_night": ambience._start_call("frogs")
		if label == "storm": ambience._start_call("thunder")
		var samples: Array[int] = []
		for i in 12:
			ambience._scan_environment()
			samples.append(ambience.last_scan_usec)
		samples.sort()
		var mass_before: Dictionary = water.flow.mass.duplicate()
		record.set_recording_active(true)
		await create_timer(9).timeout
		record.set_recording_active(false)
		record.get_recording().save_to_wav(output+label+".wav")
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output+label+".png")
		var rain = current_scene.get_node_or_null("WeatherPrecipitation")
		result[label] = {"targets":ambience.targets.duplicate(),"scan_median_usec":samples[6],"scan_max_usec":samples.back(),"visible_rain_streaks":rain.visible_streaks if rain != null else 0,"water_mass_unchanged":mass_before == water.flow.mass}
		result[label].context = rig.get_work_audio_context()
		if label == "shore_night" and (ambience.targets.shoreline <= 0 or ambience.targets.frogs <= 0): push_error("Viewed shoreline did not produce local sound")
		if label in ["rain","storm"] and (rain == null or rain.visible_streaks == 0): push_error("Missing visible rain: "+label)
	# Detached precipitation must not survive scene replacement.
	var old_rain = current_scene.get_node_or_null("WeatherPrecipitation")
	var rain_ref: WeakRef = weakref(old_rain)
	var old_scene := current_scene
	root.remove_child(old_scene)
	old_scene.free()
	weather._process(0)
	result["scene_exit_clears_rain"] = rain_ref.get_ref() == null
	AudioServer.remove_bus_effect(0,AudioServer.get_bus_effect_count(0)-1)
	var file := FileAccess.open(output+"report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"\t"))
	print("ENVIRONMENT_DETAILS_REVIEW ",result)
	quit()
