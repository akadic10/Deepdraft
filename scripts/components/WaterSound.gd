extends Node3D

## Two bounded ambience beds, positioned around nearby visible moving water.
## Uses the same camera-focus attenuation and Work bus as work/wildlife audio.
const Synth := preload("res://scripts/components/WaterAudioSynth.gd")
var water_view: Node3D
var voices: Dictionary = {}
var last_scan_usec := 0
var _settings: Dictionary
var _until_scan := 0.0
var _revision := -1
var _synthesis := Thread.new()
var _streams_ready := false

func _ready() -> void:
	process_priority = 55 # After camera and water presentation updates.
	_settings = WorldGenerator.water_profile.audio
	_synthesis.start(_prepare_streams)
	for kind: String in ["waterfall","river"]:
		var player := AudioStreamPlayer3D.new()
		player.name = kind.capitalize()
		player.bus = StringName(WorkFeedback.config.audio.bus)
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
		player.attenuation_filter_cutoff_hz = 20500
		player.panning_strength = 0.45
		player.volume_db = -80
		add_child(player)
		voices[kind] = {"player":player,"gain":0.0,"target_gain":0.0,"point":Vector3.ZERO}

func _process(delta: float) -> void:
	if not _streams_ready:
		if _synthesis.is_alive(): return
		var streams: Dictionary = _synthesis.wait_to_finish()
		for kind: String in voices: voices[kind].player.stream = streams[kind]
		_streams_ready = true
	if not WaterManager.initialized or not is_instance_valid(water_view) or not water_view.is_visible_in_tree() or WorldClock.paused or WorldClock.speed<=0 or SaveManager.is_loading() or get_viewport().get_camera_3d()==null:
		_silence()
		return
	if _revision != WaterManager.revision:
		_silence()
		_revision = WaterManager.revision
	var context := WorkFeedback._context()
	if context.is_empty():
		_silence()
		return
	_until_scan -= delta
	if _until_scan <= 0:
		_scan(context)
		_until_scan = float(_settings.scan_seconds)
	var blend := 1.0-exp(-delta/float(_settings.fade_seconds))
	for kind: String in voices:
		var voice: Dictionary = voices[kind]
		var player: AudioStreamPlayer3D = voice.player
		if voice.gain<0.0001: player.global_position = voice.point
		else: player.global_position = player.global_position.lerp(voice.point,blend)
		voice.gain = lerpf(voice.gain,voice.target_gain,blend)
		player.volume_db = linear_to_db(maxf(voice.gain,0.0001))
		player.stream_paused = voice.gain<0.0001
		if not player.stream_paused and not player.playing and DisplayServer.get_name()!="headless": player.play()

func _prepare_streams() -> Dictionary:
	return {"waterfall":Synth.stream("waterfall"),"river":Synth.stream("river")}

func _exit_tree() -> void:
	if _synthesis.is_started(): _synthesis.wait_to_finish()

func _silence() -> void:
	_until_scan = 0.0
	for voice: Dictionary in voices.values():
		voice.gain = 0.0
		voice.target_gain = 0.0
		voice.player.volume_db = -80
		voice.player.stream_paused = true

func _scan(context: Dictionary) -> void:
	var started := Time.get_ticks_usec()
	var focus: Vector3 = context.focus
	var zoom: float = context.zoom
	var river_radius_squared := pow(float(_settings.river.far_radius),2)
	var fall := {"gain":0.0,"weight":0.0,"point":Vector3.ZERO}
	var river := {"gain":0.0,"weight":0.0,"point":Vector3.ZERO}
	# Several faces of one waterfall contribute a location, never extra volume.
	for sites: Array in water_view._splash_sites.values():
		for site: Dictionary in sites:
			var gain := WorkFeedback.spatial_gain(site.point,focus,zoom,_settings.waterfall)
			if gain<=0 or not _exposed(site.key): continue
			if minf(WaterManager.flow.level(site.key),water_view.terrain.slice_y+1.0)-site.point.y<=1.0: continue
			_add(fall,site.point,gain*_current_strength(site.key))
	# Only sparse measured currents, not every lake voxel or a node per cell.
	for key: Vector3i in water_view.motion.velocities:
		if zoom>float(_settings.river.max_zoom): break
		if Vector2(key.x+0.5-focus.x,key.z+0.5-focus.z).length_squared()>=river_radius_squared: continue
		var point := Vector3(key.x+0.5,key.y,key.z+0.5)
		var gain := WorkFeedback.spatial_gain(point,focus,zoom,_settings.river)
		if gain<=0 or not water_view.motion.slots.has(key) or not _exposed(key): continue
		point.y = minf(WaterManager.flow.level(key),water_view.terrain.slice_y+1.0)
		_add(river,point,gain*_current_strength(key))
	# The gentler bed recedes naturally beneath a nearby waterfall.
	river.gain *= 1.0-0.55*clampf(fall.gain/db_to_linear(float(_settings.waterfall.level_db)),0.0,1.0)
	for kind: String in voices:
		var sample: Dictionary = fall if kind=="waterfall" else river
		voices[kind].target_gain = sample.gain
		if sample.weight>0: voices[kind].point = sample.point/sample.weight
	last_scan_usec = Time.get_ticks_usec()-started

func _add(sample: Dictionary, point: Vector3, gain: float) -> void:
	var weight := gain*gain
	sample.point += point*weight
	sample.weight += weight
	sample.gain = maxf(sample.gain,gain)

func _current_strength(key: Vector3i) -> float:
	var speed := Vector2(water_view.motion.velocities.get(key,Vector2.ZERO)).length()
	return minf(1.0,sqrt(speed/0.03))*smoothstep(0.0001,0.001,speed)

func _exposed(key: Vector3i) -> bool:
	if key.y>water_view.terrain.slice_y or WaterManager.flow.volume(key)<WaterManager.standing_depth: return false
	var top := minf(WaterManager.flow.level(key),water_view.terrain.slice_y+1.0)
	return key.y>WorldGenerator.get_surface_y(key.x,key.z) or water_view.terrain.is_revealed_air(Vector3i(key.x,ceili(top)-1,key.z))
