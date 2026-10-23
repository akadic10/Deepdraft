extends Node

## Owns environmental audio and player audio preferences. All playback is
## cosmetic and scene-bound: no simulation RNG, wildlife or save mutations.
const CONFIG_PATH := "res://data/audio/environment.json"
var config: Dictionary = {}
var loops: Dictionary = {}
var calls: Array[Dictionary] = []
var targets: Dictionary = {}
var _streams: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _scene: Node
var _view: Node3D
var _lighting: Node
var _flora: Node
var _slice: Node
var _scan_left := 0.0
var _call_left := {"birds": 6.0, "owls": 50.0}
var _last_variant := {}
var _context: Dictionary = {}
var _exposure := 1.0
var _forest := 0.0
var _wildlife: Node
var _habitat: Dictionary = {}
var _sources := preload("res://scripts/components/EnvironmentSoundSources.gd").new()
var last_scan_usec := 0
var _preferences_path := "user://audio.cfg"
var _save_left := -1.0
var _volumes := {}
var _muted := {}
signal preferences_changed


func _ready() -> void:
	process_priority = 56
	config = preload("res://scripts/registries/JsonData.gd").read_dict(CONFIG_PATH)
	_rng.randomize()
	if AudioServer.get_bus_index(config.bus) < 0:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, config.bus)
		AudioServer.set_bus_send(AudioServer.bus_count - 1, &"Master")
	for kind: String in config.loops:
		var stream := (load(config.loops[kind].stream) as AudioStreamWAV).duplicate() as AudioStreamWAV
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = roundi(stream.get_length() * stream.mix_rate)
		_streams[kind] = stream
	for kind: String in config.calls:
		_call_left[kind] = _interval(kind, 0)
		var bank: Array[AudioStream] = []
		for file: String in config.calls[kind].streams:
			bank.append(load("res://assets/audio/ambience/environment/" + file + ".wav"))
		_streams[kind] = bank
	reload_preferences()


func _bus(channel: String) -> int:
	return AudioServer.get_bus_index(config.bus if channel == "ambience" else WorkFeedback.config.audio.bus)


func volume(channel: String) -> float:
	return float(_volumes.get(channel, 0.0))


func muted(channel: String) -> bool:
	return bool(_muted.get(channel, false))


func set_volume(channel: String, value: float) -> void:
	if channel not in ["ambience", "effects"]: return
	_volumes[channel] = clampf(value, 0, 1)
	_apply_preference(channel)
	_save_left = .4
	preferences_changed.emit()


func set_muted(channel: String, value: bool) -> void:
	if channel not in ["ambience", "effects"]: return
	_muted[channel] = value
	_apply_preference(channel)
	_save_left = .4
	preferences_changed.emit()


func _apply_preference(channel: String) -> void:
	AudioServer.set_bus_volume_db(_bus(channel), linear_to_db(maxf(volume(channel), .0001)))
	AudioServer.set_bus_mute(_bus(channel), muted(channel) or volume(channel) <= 0)


func reload_preferences() -> void:
	var prefs := ConfigFile.new()
	prefs.load(_preferences_path)
	for channel: String in ["ambience", "effects"]:
		var fallback: float = config.default_volume if channel == "ambience" else config.default_effects_volume
		var stored: Variant = prefs.get_value(channel, "volume", fallback)
		_volumes[channel] = clampf(float(stored), 0, 1) if (stored is float or stored is int) and is_finite(float(stored)) else fallback
		_muted[channel] = prefs.get_value(channel, "muted", false) == true
		_apply_preference(channel)
	preferences_changed.emit()


func save_preferences() -> void:
	var prefs := ConfigFile.new()
	for channel: String in ["ambience", "effects"]:
		prefs.set_value(channel, "volume", volume(channel))
		prefs.set_value(channel, "muted", muted(channel))
	var error := prefs.save(_preferences_path)
	if error != OK: push_warning("Could not save audio preferences: " + error_string(error))
	_save_left = -1.0


func _sync_scene() -> bool:
	var scene := get_tree().current_scene
	if not is_instance_valid(scene) or not scene.is_inside_tree() or SaveManager.is_loading():
		clear_scene()
		return false
	if scene != _scene:
		clear_scene()
		var view := get_tree().get_first_node_in_group("work_audio_view") as Node3D
		# Only a live world camera opts in; asset viewers and unrelated fixtures
		# must not acquire sound or new node children merely by loading the project.
		if view == null or not scene.is_ancestor_of(view): return false
		_scene = scene
		_view = view
		_lighting = get_tree().get_first_node_in_group("underground_lighting")
		_flora = get_tree().get_first_node_in_group("surface_flora")
		_slice = get_tree().get_first_node_in_group("work_feedback_slice")
		_wildlife = get_tree().get_first_node_in_group("wildlife")
		_scene.tree_exiting.connect(clear_scene)
		for kind: String in config.loops:
			var player: Node
			if config.loops[kind].get("positional", false):
				player = AudioStreamPlayer3D.new()
			else:
				player = AudioStreamPlayer.new()
			if player is AudioStreamPlayer3D:
				player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
				player.attenuation_filter_cutoff_hz = 20500
				player.panning_strength = .4
			player.bus = config.bus
			player.stream = _streams[kind]
			player.volume_db = -80
			add_child(player)
			loops[kind] = {"player": player, "gain": 0.0}
		for i in int(config.call_voices):
			var player := AudioStreamPlayer3D.new()
			player.bus = config.bus
			player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
			player.attenuation_filter_cutoff_hz = 20500
			player.panning_strength = .4
			add_child(player)
			calls.append({"player": player, "kind": "", "left": 0.0, "gain": 0.0})
	if not is_instance_valid(_view) or not _view.is_inside_tree():
		clear_scene()
		return false
	return true


func clear_scene() -> void:
	if is_instance_valid(_scene) and _scene.tree_exiting.is_connected(clear_scene):
		_scene.tree_exiting.disconnect(clear_scene)
	for voice: Dictionary in loops.values(): voice.player.free()
	for voice: Dictionary in calls: voice.player.free()
	loops.clear()
	calls.clear()
	targets.clear()
	_scene = null
	_view = null
	_lighting = null
	_flora = null
	_slice = null
	_wildlife = null
	_habitat.clear()
	_context.clear()
	_scan_left = 0
	for kind: String in _call_left: _call_left[kind] = _interval(kind, 0)


func _exit_tree() -> void:
	clear_scene()
	if _save_left >= 0: save_preferences()


func _process(delta: float) -> void:
	if _save_left >= 0:
		_save_left -= delta
		if _save_left < 0: save_preferences()
	if config.is_empty() or not _sync_scene(): return
	if not WorldGenerator.is_maps_ready() or get_viewport().get_camera_3d() == null:
		for voice: Dictionary in loops.values():
			voice.player.stop()
			voice.gain = 0.0
		for voice: Dictionary in calls:
			voice.player.stop()
			voice.left = 0.0
		return
	_scan_left -= delta
	if _scan_left <= 0:
		_scan_environment()
		_scan_left = float(config.scan_seconds)
	if _context.is_empty():
		for voice: Dictionary in loops.values(): voice.player.stop(); voice.gain = 0.0
		for voice: Dictionary in calls: voice.player.stop(); voice.left = 0.0
		return
	targets = mix_for(WorldClock.hour, WorldClock.season, WeatherManager.current_weather_id(), _exposure, _forest, float(_context.zoom), _habitat)
	var paused := WorldClock.paused or WorldClock.speed <= 0
	var blend := 1.0 - exp(-delta / float(config.fade_seconds))
	for kind: String in loops:
		var voice: Dictionary = loops[kind]
		if voice.player is AudioStreamPlayer3D and _habitat.has(kind): voice.player.global_position = _habitat[kind].point
		var gain: float = targets[kind] * db_to_linear(float(config.loops[kind].level_db))
		if paused: gain *= float(config.pause_gain)
		voice.gain = lerpf(voice.gain, gain, blend)
		voice.player.volume_db = linear_to_db(maxf(voice.gain, .0001))
		if voice.gain > .0002 and not voice.player.playing and DisplayServer.get_name() != "headless":
			voice.player.play(_rng.randf_range(0, voice.player.stream.get_length()))
		elif voice.gain <= .0002: voice.player.stop()
	for voice: Dictionary in calls:
		voice.left = maxf(0, voice.left - delta)
		if voice.left <= 0: continue
		if paused or float(targets.get(voice.kind, 0)) < .01 or not _voice_source_valid(voice):
			voice.player.stop()
			voice.left = 0.0
			continue
		if voice.has("source"):
			var source: Node3D = voice.source.get_ref()
			voice.player.global_position = source.global_position + Vector3.UP
		voice.gain = lerpf(voice.gain, float(targets[voice.kind]), blend)
		voice.player.volume_db = linear_to_db(maxf(voice.gain, .0001)) + float(config.calls[voice.kind].level_db)
	if paused: return
	for kind: String in _call_left:
		if float(targets[kind]) < .01:
			_call_left[kind] = _interval(kind, float(targets.dawn))
			continue
		# Less activity in cold/murky weather as well as lower call volume.
		_call_left[kind] -= delta * clampf(float(targets[kind]), .2, 1.0)
		if _call_left[kind] <= 0:
			_start_call(kind)
			_call_left[kind] = _interval(kind, float(targets.dawn))


func _scan_environment() -> void:
	var started := Time.get_ticks_usec()
	_context = _view.get_work_audio_context()
	if _context.is_empty(): return
	var focus: Vector3 = _context.focus
	var x := clampi(floori(focus.x), 0, WorldData.WORLD_SIZE_X - 1)
	var z := clampi(floori(focus.z), 0, WorldData.WORLD_SIZE_Z - 1)
	var surface := WorldGenerator.get_overview_surface_height(x, z)
	var slice_y := int(_slice.get_slice_y()) if is_instance_valid(_slice) else SliceController.MAX_SLICE_Y
	# Sample air at the viewed column, not the elevated camera. Slicing away
	# a mountain roof does not turn its interior into an outdoor sound source.
	var point := focus + Vector3.UP * .35
	_exposure = 1.0
	if is_instance_valid(_lighting): _exposure = _lighting.actor_sky_at(point)
	elif point.y <= surface: _exposure = 0.0
	_forest = 0.0
	if is_instance_valid(_flora) and _flora.has_method("ambient_tree_density"):
		_forest = _flora.ambient_tree_density(point, float(config.forest_radius), float(config.forest_full_count))
	_habitat = _sources.scan(focus, slice_y, int(config.source_radius), _flora, _wildlife)
	_habitat.roof_gain = 0.0
	if is_instance_valid(_lighting) and _lighting.has_method("roof_height"):
		var roof: int = _lighting.roof_height(Vector2i(x, z))
		_habitat.roof_gain = 1.0 - smoothstep(5, 14, maxf(0, roof - focus.y))
	last_scan_usec = Time.get_ticks_usec() - started


func mix_for(hour: float, season: String, weather: String, exposure: float, forest: float, zoom: float, habitat: Dictionary = {}) -> Dictionary:
	var events := SkyController.current_event_hours()
	var day := smoothstep(float(events.sunrise_start), float(events.sunrise_end), hour) * (1.0 - smoothstep(float(events.sunset_start), float(events.sunset_end), hour))
	var dawn := exp(-pow((hour - float(events.sunrise)) / 1.15, 2))
	var s: Dictionary = config.seasons.get(season, config.seasons.summer)
	var w: Dictionary = config.weather.get(weather, config.weather["base:weather:clear"])
	var outside := smoothstep(.015, .6, clampf(exposure, 0, 1))
	var detail := lerpf(1.0, .45, smoothstep(35, 240, zoom))
	var night := 1.0 - day
	var rain := float(w.rain)
	var roof := float(habitat.get("roof_gain", 0)) * (1.0 - outside)
	return {
		"wind": float(s.wind) * float(w.wind) * outside * lerpf(.75, 1.0, day),
		"foliage": float(s.foliage) * float(w.foliage) * outside * clampf(forest, 0, 1) * detail * (1.0 - .65 * float(s.dry_leaves)),
		"crickets": float(s.insects) * float(w.insects) * outside * (1.0 - day) * detail,
		"shelter": 1.0 - outside,
		"birds": float(s.birds) * float(w.birds) * outside * maxf(day, dawn * .8) * detail,
		"owls": float(s.owls) * float(w.owls) * outside * (1.0 - day) * detail * lerpf(.3, 1.0, forest),
		"dry_leaves": float(s.dry_leaves) * float(w.foliage) * outside * forest * detail,
		"winter_wind": float(s.winter_wind) * float(w.wind) * outside,
		"day_insects": float(s.insects) * float(w.insects) * day * outside * detail,
		"chirps": float(s.insects) * float(w.insects) * night * outside * detail,
		"shoreline": _local_gain(habitat, "shoreline", zoom) * outside,
		"frogs": _local_gain(habitat, "frogs", zoom) * outside * float(s.insects) * float(w.insects) * night,
		"drips": _local_gain(habitat, "drips", zoom) * (1.0 - outside),
		"creaks": _local_gain(habitat, "creaks", zoom) * outside * float(w.wind) * (.35 + .65 * float(s.winter_wind)),
		"wolves": _local_gain(habitat, "wolves", zoom, float(config.source_radius) * 3) * outside * night,
		"rain": rain * outside,
		"rain_roof": rain * roof,
		"thunder": float(w.thunder) * (outside + .2 * roof),
		"dawn": dawn
	}


func _local_gain(habitat: Dictionary, kind: String, zoom: float, radius := -1.0) -> float:
	if not habitat.has(kind): return 0.0
	if radius < 0: radius = float(config.source_radius)
	return pow(1.0 - smoothstep(3, radius, float(habitat[kind].distance)), 2) * pow(minf(1, 24.0 / maxf(1, zoom)), 1.3)


func _voice_source_valid(voice: Dictionary) -> bool:
	if not voice.has("source"): return true
	var node: Node3D = voice.source.get_ref()
	if not is_instance_valid(node) or not node.is_inside_tree() or node.is_queued_for_deletion() or not node.is_visible_in_tree(): return false
	var slice_y := int(_slice.get_slice_y()) if is_instance_valid(_slice) else SliceController.MAX_SLICE_Y
	if node.global_position.y > slice_y: return false
	if _context.is_empty() or node.global_position.distance_to(_context.focus) > float(config.source_radius) * (3 if voice.kind == "wolves" else 1): return false
	if voice.kind == "wolves": return _sources.eligible_wolf(node, slice_y)
	return true


func _interval(kind: String, dawn: float) -> float:
	var profile: Dictionary = config.calls[kind]
	return _rng.randf_range(profile.interval[0], profile.interval[1]) * lerpf(1.0, float(profile.dawn_interval_multiplier), dawn)


func _start_call(kind: String) -> bool:
	if float(targets.get(kind, 0)) < .01: return false
	if kind in ["wolves", "creaks"] and not _habitat.get(kind, {}).has("node"): return false
	if kind in ["frogs", "drips"] and not _habitat.has(kind): return false
	# One phrase per family, with a shared budget for all local details.
	for voice: Dictionary in calls:
		if voice.left > 0 and voice.kind == kind: return false
	for voice: Dictionary in calls:
		if voice.left > 0: continue
		voice.erase("source")
		voice.kind = kind
		if _habitat.get(kind, {}).has("node"): voice.source = _habitat[kind].node
		if not _voice_source_valid(voice): return false
		var bank: Array = _streams[kind]
		var variant := _rng.randi_range(0, bank.size() - 1)
		if variant == int(_last_variant.get(kind, -1)): variant = (variant + 1) % bank.size()
		_last_variant[kind] = variant
		var player: AudioStreamPlayer3D = voice.player
		player.bus = config.calls[kind].get("bus", config.bus)
		player.stream = bank[variant]
		player.pitch_scale = _rng.randf_range(.97, 1.03)
		var angle := _rng.randf_range(-PI, PI)
		player.global_position = _context.focus + Vector3(cos(angle) * 22, 5, sin(angle) * 22)
		if _habitat.has(kind): player.global_position = _habitat[kind].point
		voice.kind = kind
		voice.gain = float(targets[kind])
		voice.left = player.stream.get_length() / player.pitch_scale
		player.volume_db = linear_to_db(maxf(voice.gain, .0001)) + float(config.calls[kind].level_db)
		if DisplayServer.get_name() != "headless": player.play()
		return true
	return false
