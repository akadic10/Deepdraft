extends Node

## Owns short world-work audio and disposable effects. All state is cosmetic;
## changing/reloading the scene clears it. No simulation RNG or save fields.
const CONFIG_PATH := "res://data/audio/work_feedback.json"
const DustBurst = preload("res://scripts/components/WorkDustBurst.gd")
var config: Dictionary = {}
var _streams: Dictionary = {}
var _last_variant: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _voices: Array[Dictionary] = []
var _bursts: Array[Node3D] = []
var _scene_id := 0
var _view: Node
var _slice: Node
signal sound_started(kind: String, position: Vector3, variant: int)
signal burst_started(position: Vector3, stage: String)


func _ready() -> void:
	process_priority = 50 # Camera smoothing runs before spatial volume updates.
	_rng.randomize()
	var file := FileAccess.open(CONFIG_PATH,FileAccess.READ)
	if file == null:
		push_error("WorkFeedback: cannot load settings")
		return
	config = JSON.parse_string(file.get_as_text())
	for kind in ["chop","completion","mining_stone","mining_soil"]:
		var bank: Array[AudioStream] = []
		for path in config.audio[kind]:
			var stream := load(path) as AudioStream
			if stream != null:
				bank.append(stream)
		_streams[kind] = bank
	var bus := StringName(config.audio.bus)
	if AudioServer.get_bus_index(bus) < 0:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count-1,bus)
		AudioServer.set_bus_send(AudioServer.bus_count-1,&"Master")
	set_volume_db(float(config.audio.volume_db))


func set_volume_db(value: float) -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(config.audio.bus),clampf(value,-80,0))


func set_muted(value: bool) -> void:
	AudioServer.set_bus_mute(AudioServer.get_bus_index(config.audio.bus),value)


func _sync_scene() -> bool:
	var scene := get_tree().current_scene
	var id := scene.get_instance_id() if is_instance_valid(scene) else 0
	if id != _scene_id:
		clear_transients()
		_scene_id = id
		_view = null
		_slice = null
		if scene != null:
			scene.tree_exiting.connect(clear_transients,CONNECT_ONE_SHOT)
	return id != 0


func clear_transients() -> void:
	for voice in _voices:
		voice.player.stop()
		voice.player.free()
	_voices.clear()
	for burst in _bursts:
		burst.free()
	_bursts.clear()
	_last_variant.clear()


func _exit_tree() -> void:
	clear_transients()
	_streams.clear()


func _context() -> Dictionary:
	if not is_instance_valid(_view):
		_view = get_tree().get_first_node_in_group("work_audio_view")
	if is_instance_valid(_view):
		return _view.call("get_work_audio_context")
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return {}
	# Standalone render/test scenes can supply a focus without a full RTS rig.
	return {"focus": camera.get_meta("work_focus",camera.global_position-camera.global_basis.z*24),
		"zoom": camera.get_meta("work_zoom",24.0)}


func _slice_y() -> int:
	if not is_instance_valid(_slice):
		_slice = get_tree().get_first_node_in_group("work_feedback_slice")
	return int(_slice.call("get_slice_y")) if is_instance_valid(_slice) else 127


## Horizontal distance to the looked-at area, independent of camera altitude.
func spatial_gain(position: Vector3, focus: Vector3, zoom: float) -> float:
	var distance := Vector2(position.x-focus.x,position.z-focus.z).length()
	var proximity := 1.0-smoothstep(float(config.audio.near_radius),float(config.audio.far_radius),distance)
	var zoom_gain := pow(minf(1.0,float(config.audio.zoom_reference)/maxf(zoom,1)),float(config.audio.zoom_exponent))
	return proximity*proximity*zoom_gain


func play_chop(position: Vector3, floor_y: int) -> bool:
	return _play("chop",position,floor_y)


func _play(kind: String, position: Vector3, floor_y: int) -> bool:
	if config.is_empty() or not _sync_scene() or WorldClock.paused or WorldClock.speed <= 0:
		return false
	var context := _context()
	if context.is_empty() or floor_y > _slice_y():
		return false
	var gain := spatial_gain(position,context.focus,context.zoom)
	if gain < float(config.audio.minimum_gain) or _streams[kind].is_empty():
		return false
	var selected := -1
	var quietest := INF
	var quiet_index := -1
	for i in range(_voices.size()):
		var voice := _voices[i]
		if float(voice.remaining) <= 0:
			selected = i
			break
		var current_gain := spatial_gain(voice.player.global_position,context.focus,context.zoom)
		if current_gain < quietest:
			quietest = current_gain
			quiet_index = i
	if selected < 0 and _voices.size() < int(config.audio.max_voices):
		var player := AudioStreamPlayer3D.new()
		player.bus = config.audio.bus
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
		player.attenuation_filter_cutoff_hz = 20500
		player.panning_strength = float(config.audio.panning_strength)
		add_child(player)
		_voices.append({"player":player,"remaining":0.0,"floor":floor_y,"level":0.0})
		selected = _voices.size()-1
	if selected < 0:
		if gain <= quietest:
			return false
		selected = quiet_index # A near hit may replace a distant, quieter tail.
	var bank: Array = _streams[kind]
	var variant := _rng.randi_range(0,bank.size()-1)
	if bank.size() > 1 and variant == int(_last_variant.get(kind,-1)):
		variant = (variant + _rng.randi_range(1,bank.size()-1)) % bank.size()
	_last_variant[kind] = variant
	var voice := _voices[selected]
	var player: AudioStreamPlayer3D = voice.player
	player.stop()
	player.global_position = position
	player.stream = bank[variant]
	var variation := float(config.audio.pitch_variation)
	player.pitch_scale = _rng.randf_range(1.0-variation,1.0+variation)
	voice.remaining = player.stream.get_length()/player.pitch_scale
	voice.floor = floor_y
	voice.level = _rng.randf_range(-float(config.audio.volume_variation_db),float(config.audio.volume_variation_db))
	_update_voices(0,context)
	# Headless simulation has no audio mixer to retire playback handles.
	if DisplayServer.get_name() != "headless":
		player.play()
	sound_started.emit(kind,position,variant)
	return true


func tree_felled(position: Vector3, stage: String, floor_y: int) -> void:
	if not _can_emit(position,floor_y):
		return
	_play("completion",position,floor_y)
	_spawn_burst(position,floor_y,config.poof,float(config.poof.stage_scale.get(stage,1.0)),stage)


func mining_impact(position: Vector3, block: Vector3i, visible_id: int, normal: Vector3) -> void:
	if not _can_emit(position,block.y):
		return
	# Match the renderer's neutral rock fallback if strata is unavailable.
	if not BlockRegistry.is_solid(visible_id):
		visible_id = BlockRegistry.get_id(config.mining.fallback_block)
	var kind: String = BlockRegistry.get_def(BlockRegistry.get_key(visible_id)).get("kind","")
	var family := "soil" if kind in config.mining.soil_kinds else "stone"
	_play("mining_"+family,position,block.y)
	var settings := _mining_colors(config.mining.impact,visible_id)
	_spawn_burst(position,block.y,settings,float(settings.scale),"mining_impact",normal)


## Called only by the successful mining commit, never by restore/world writes.
func block_mined(block: Vector3i, removed_id: int) -> void:
	var position := Vector3(block)+Vector3.ONE*.5
	if not _can_emit(position,block.y):
		return
	var settings := _mining_colors(config.mining.completion,removed_id)
	_spawn_burst(position,block.y,settings,float(settings.scale),"mining_completion")


func _mining_colors(profile: Dictionary, block_id: int) -> Dictionary:
	var settings := profile.duplicate()
	var color := BlockRegistry.get_color(block_id,WorldClock.season)
	settings.dust_colors = [color.lightened(.18),color.lightened(.32),color]
	settings.chip_colors = [color,color.darkened(.18)]
	return settings


func _can_emit(position: Vector3, floor_y: int) -> bool:
	if config.is_empty() or not _sync_scene() or WorldClock.paused or WorldClock.speed <= 0:
		return false
	var context := _context()
	if context.is_empty() or floor_y > _slice_y():
		return false
	# Offscreen work never queues effects to replay on return.
	return spatial_gain(position,context.focus,context.zoom) >= float(config.audio.minimum_gain)


func _spawn_burst(position: Vector3, floor_y: int, settings: Dictionary, size: float, stage: String, direction := Vector3.ZERO) -> void:
	if _bursts.size() >= int(config.poof.max_bursts):
		_bursts.pop_front().free()
	var burst := DustBurst.new()
	add_child(burst)
	burst.global_position = position
	burst.setup(settings,size,_rng.randi(),floor_y,direction)
	_bursts.append(burst)
	burst_started.emit(position,stage)


func _process(delta: float) -> void:
	if config.is_empty() or not _sync_scene():
		return
	_update_voices(delta,_context())
	var step := 0.0 if WorldClock.paused else delta*WorldClock.speed
	var slice_y := _slice_y()
	for i in range(_bursts.size()-1,-1,-1):
		var burst := _bursts[i]
		burst.visible = burst.floor_y <= slice_y
		if burst.advance(step):
			_bursts.remove_at(i)
			burst.free()


func _update_voices(delta: float, context: Dictionary) -> void:
	var active := 0
	for voice in _voices:
		voice.remaining = maxf(0,float(voice.remaining)-delta)
		var gain := 0.0
		if not context.is_empty() and voice.floor <= _slice_y():
			gain = spatial_gain(voice.player.global_position,context.focus,context.zoom)
		voice.gain = gain
		if gain < float(config.audio.minimum_gain) or float(voice.remaining) <= 0:
			voice.player.stop()
			voice.remaining = 0.0
		else:
			active += 1
	# Leave headroom for simultaneous hits instead of simply summing full volume.
	var crowd_db := linear_to_db(1.0/sqrt(maxi(1,active)))
	for voice in _voices:
		if float(voice.remaining) > 0:
			voice.player.volume_db = linear_to_db(float(voice.gain)) + float(voice.level) + crowd_db
