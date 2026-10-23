extends SceneTree

## Diagnostic: times each part of AmbientAudio._scan_environment in a loaded
## save while the game is paused and the camera pans (where 50-110 ms stalls
## were seen 2026-10-22). Run with an isolated APPDATA holding quicksave.json.
var output := ""

func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	_run.call_deferred()

func _run() -> void:
	var clock = root.get_node("WorldClock")
	var saves = root.get_node("SaveManager")
	var audio = root.get_node("AmbientAudio")
	clock.set_paused(true)
	saves.set_process(false)
	var placeholder := Node3D.new()
	placeholder.scene_file_path = "res://scenes/main/debug_world.tscn"
	root.add_child(placeholder)
	current_scene = placeholder
	saves.set_process(true)
	if not saves.request_load(): quit(2); return
	while saves.is_loading(): await process_frame
	saves.set_process(false)
	clock.set_paused(true)
	var view = current_scene.get_node("Renderer").get_node("Water")
	var settle := Time.get_ticks_msec()
	while not view.is_loading_complete() and Time.get_ticks_msec()-settle < 120000: await process_frame
	for _i in 30: await process_frame
	var rig = current_scene.get_node("CameraRig")
	rig.stop_following()
	var origin: Vector3 = rig._target_pos
	var parts := {}
	for i in 24:
		rig._target_pos = origin+Vector3(sin(i*.6)*18,0,cos(i*.6)*18)
		for _f in 20: await process_frame
		_time(parts, "context", func(): return audio._view.get_work_audio_context())
		var context: Dictionary = audio._view.get_work_audio_context()
		if context.is_empty(): continue
		var focus: Vector3 = context.focus
		var point := focus+Vector3.UP*.35
		var slice_y := int(audio._slice.get_slice_y()) if is_instance_valid(audio._slice) else 127
		if is_instance_valid(audio._lighting): _time(parts, "actor_sky_at", func(): return audio._lighting.actor_sky_at(point))
		if is_instance_valid(audio._flora): _time(parts, "tree_density", func(): return audio._flora.ambient_tree_density(point, float(audio.config.forest_radius), float(audio.config.forest_full_count)))
		_time(parts, "sources_scan", func(): return audio._sources.scan(focus, slice_y, int(audio.config.source_radius), audio._flora, audio._wildlife))
		if is_instance_valid(audio._lighting): _time(parts, "roof_height", func(): return audio._lighting.roof_height(Vector2i(floori(focus.x), floori(focus.z))))
		_time(parts, "whole_scan", func(): return audio._scan_environment())
	var report := {}
	for key: String in parts:
		var values: Array = parts[key]
		values.sort()
		report[key] = {"n":values.size(),"median_ms":values[values.size()/2],"max_ms":values.back()}
	print(JSON.stringify(report, "  "))
	if not output.is_empty(): FileAccess.open(output, FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	root.get_node("WorldGenerator").prepare_for_world_reload()
	quit(0)

func _time(parts: Dictionary, key: String, work: Callable) -> void:
	# The view caches its context per frame; a new frame id forces real work.
	var started := Time.get_ticks_usec()
	work.call()
	if not parts.has(key): parts[key] = []
	parts[key].append((Time.get_ticks_usec()-started)/1000.0)
