extends Node3D

## One bounded pool per world, fed only by visible installed fires. Uses Work
## volume/mute and camera-focus attenuation; no per-furniture audio allocation.
var furniture: Node
var voices: Array[Dictionary] = []
var _settings: Dictionary
var _streams: Dictionary = {}
var _until_scan := 0.0

func _ready() -> void:
	process_priority = 55
	_settings = WorkFeedback.config.fire_ambience
	for kind: String in ["campfire", "torch"]:
		var stream := (load(String(_settings[kind].stream)) as AudioStreamWAV).duplicate() as AudioStreamWAV
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = roundi(stream.get_length()*stream.mix_rate)
		_streams[kind] = stream
	for i in int(_settings.max_voices):
		var player := AudioStreamPlayer3D.new()
		player.name = "Fire%d" % i
		player.bus = StringName(WorkFeedback.config.audio.bus)
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
		player.attenuation_filter_cutoff_hz = 20500
		player.panning_strength = .45
		player.volume_db = -80
		add_child(player)
		voices.append({"player":player, "source":null, "id":-1, "gain":0.0, "target_gain":0.0})

func _process(delta: float) -> void:
	if WorldClock.paused or WorldClock.speed<=0 or SaveManager.is_loading() or not is_instance_valid(furniture) or get_viewport().get_camera_3d()==null:
		_silence()
		return
	var context := WorkFeedback._context()
	if context.is_empty():
		_silence()
		return
	_until_scan -= delta
	if _until_scan<=0:
		_scan(context)
		_until_scan = float(_settings.scan_seconds)
	var blend := 1.0-exp(-delta/float(_settings.fade_seconds))
	for voice: Dictionary in voices:
		var player: AudioStreamPlayer3D = voice.player
		# Validate before assigning a typed Node: uninstall may already free it.
		if not _audible_source(voice.source):
			_clear(voice)
			continue
		voice.gain = lerpf(voice.gain, voice.target_gain, blend)
		player.volume_db = linear_to_db(maxf(voice.gain,.0001))
		player.stream_paused = voice.gain<.001
		if not player.stream_paused and not player.playing and DisplayServer.get_name()!="headless":
			player.play(fmod(float(voice.id)*2.317,player.stream.get_length()))

func _audible_source(source: Variant) -> bool:
	return is_instance_valid(source) and source.is_inside_tree() and not source.is_queued_for_deletion() and source.is_visible_in_tree() and floori(source.global_position.y)<=WorkFeedback._slice_y()

func _scan(context: Dictionary) -> void:
	var candidates: Array[Dictionary] = []
	for piece in furniture._installed.values():
		var kind := String(piece.def.get("fire_sound", ""))
		if kind.is_empty() or not _audible_source(piece.node): continue
		var point: Vector3 = piece.node.global_position
		var profile: Dictionary = _settings[kind]
		var gain := WorkFeedback.spatial_gain(point, context.focus, context.zoom, profile)
		gain *= 1.0-smoothstep(3.0,float(profile.far_radius),absf(point.y-context.focus.y))
		if gain<.001: continue
		candidates.append({"id":piece.installed_id, "source":piece.node, "kind":kind, "gain":gain})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary): return a.gain>b.gain if not is_equal_approx(a.gain,b.gain) else a.id<b.id)
	if candidates.size()>voices.size(): candidates.resize(voices.size())
	var selected: Dictionary = {}
	for candidate: Dictionary in candidates: selected[candidate.id] = candidate
	# Existing sources retain their playback phase; quiet outgoing voices fade.
	var normalization := 1.0/sqrt(float(maxi(1,candidates.size())))
	for voice: Dictionary in voices:
		voice.target_gain = 0.0
		if selected.has(voice.id):
			voice.target_gain = selected[voice.id].gain*normalization
			selected.erase(voice.id)
	for candidate: Dictionary in selected.values():
		for voice: Dictionary in voices:
			if voice.target_gain>0 or voice.gain>=.001: continue
			_clear(voice)
			voice.id = candidate.id
			voice.source = candidate.source
			voice.target_gain = candidate.gain*normalization
			voice.player.stream = _streams[candidate.kind]
			voice.player.global_position = candidate.source.global_position+Vector3.UP
			break

func _clear(voice: Dictionary) -> void:
	voice.player.stop()
	voice.player.volume_db = -80
	voice.source = null
	voice.id = -1
	voice.gain = 0.0
	voice.target_gain = 0.0

func _silence() -> void:
	_until_scan = 0.0
	for voice: Dictionary in voices: _clear(voice)
