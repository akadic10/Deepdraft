extends SceneTree

const OUTPUT := "res://tmp/log_furniture_20261011/audio"
class FurnitureFixture extends Node3D:
	var _installed: Dictionary = {}
var failures: Array[String] = []
var sound
var furniture := FurnitureFixture.new()
var camera := Camera3D.new()
var feedback
var clock_node
var source := Node3D.new()

func _init() -> void: _run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func _run() -> void:
	create_timer(100).timeout.connect(func(): push_error("Fire audio timeout"); quit(1))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	for name in ["SaveManager","RoomManager","StockpileManager","TaskManager","WorldClock","WaterManager"]: root.get_node(name).set_process(false)
	feedback = root.get_node("WorkFeedback")
	clock_node = root.get_node("WorldClock")
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	scene.add_child(furniture)
	furniture.add_child(source)
	scene.add_child(camera)
	camera.position = Vector3(0,10,16)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	_fixture("campfire")
	sound = load("res://scripts/components/FurnitureFireSound.gd").new()
	sound.furniture = furniture
	furniture.add_child(sound)
	sound.set_process(false)
	for kind in sound._streams:
		var wav: AudioStreamWAV = sound._streams[kind]
		check(wav.loop_mode==AudioStreamWAV.LOOP_FORWARD and wav.get_length()>10, "long looping fire bank: "+kind)
		# The importer may store QOA. Inspect authored PCM, then record actual
		# imported playback below to cover the engine's decoded output too.
		var data := FileAccess.get_file_as_bytes(String(feedback.config.fire_ambience[kind].stream)).slice(44)
		var count := data.size()>>1
		var energy := 0.0
		var peak := 0.0
		var difference := 0.0
		var previous := float(data.decode_s16((count-1)*2))/32768.0
		var seam := absf(float(data.decode_s16(0))/32768.0-previous)
		for i in count:
			var sample := float(data.decode_s16(i*2))/32768.0
			energy += sample*sample
			peak = maxf(peak,absf(sample))
			difference += (sample-previous)*(sample-previous)
			previous = sample
		check(peak<.75 and sqrt(energy/count)>.04, "audible, unclipped PCM: "+kind)
		check(seam<sqrt(difference/count)*5, "no discontinuous loop seam: "+kind)
	for label in ["campfire","torch","hidden","sliced","far","overview","paused","zero_speed","loading","no_camera","removed"]:
		_fixture(label)
		for i in 50: sound._process(.2)
		var audible := false
		for voice in sound.voices: audible = audible or voice.gain>.001
		check(audible==(label in ["campfire","torch"]), "source gating: "+label)
	_fixture("campfire")
	for id in range(2,42):
		furniture._installed[id] = {"installed_id":id,"node":source,"def":{"fire_sound":"campfire"}}
	sound._process(5)
	check(sound.voices.size()==4 and sound.get_child_count()==4, "forty fires have only four voices")
	var power := 0.0
	for voice in sound.voices: power += voice.target_gain*voice.target_gain
	check(power<=pow(db_to_linear(-10),2)+.0001, "many fires retain single-fire power budget")
	_fixture("campfire")
	sound._process(5)
	source.visible = false
	sound._process(.001)
	check(sound.voices.all(func(v): return is_zero_approx(v.gain)), "hidden source silences immediately")
	source.visible = true
	sound._until_scan = 0
	sound._process(.01)
	check(sound.voices[0].gain<.02, "resume fades in")
	clock_node.speed = 2
	sound._process(.3)
	check(sound.voices[0].player.pitch_scale==1, "speed keeps natural fire pitch")
	if DisplayServer.get_name()!="headless":
		sound.set_process(true)
		var recorder := AudioEffectRecord.new()
		recorder.format = AudioStreamWAV.FORMAT_16_BITS
		AudioServer.add_bus_effect(0,recorder)
		var samples := {}
		for label in ["campfire","torch","quiet","muted","far","paused","hidden","removed"]:
			_fixture(label)
			await create_timer(3.3 if label=="far" else 1.5).timeout
			recorder.set_recording_active(true)
			await create_timer(13.0 if label=="campfire" else .9).timeout
			recorder.set_recording_active(false)
			var wav := recorder.get_recording()
			wav.save_to_wav(OUTPUT+"/"+label+".wav")
			var data := wav.data
			var count := data.size()>>1
			var energy := 0.0
			var peak := 0.0
			for i in count:
				var sample := float(data.decode_s16(i*2))/32768.0
				energy += sample*sample
				peak = maxf(peak,absf(sample))
			samples[label] = {"rms":sqrt(energy/maxi(1,count)),"peak":peak}
		check(samples.campfire.rms>.002 and samples.torch.rms>.001, "real audible fire output")
		check(samples.torch.rms<samples.campfire.rms*.85, "torch quieter than campfire")
		check(samples.quiet.rms<samples.campfire.rms*.2, "Work volume controls fire")
		for label in ["muted","far","paused","hidden","removed"]: check(samples[label].peak<.001, "silent actual output: "+label)
		for label in samples: check(samples[label].peak<.4, "output headroom: "+label)
		print("Fire PCM: ",samples)
		AudioServer.remove_bus_effect(0,AudioServer.get_bus_effect_count(0)-1)
	_fixture("campfire")
	sound._process(1)
	source.free()
	sound._process(.1) # Previously freed references must be checked before typing.
	check(sound.voices.all(func(v): return is_zero_approx(v.gain)), "freed source is safely silent")
	var players: Array = sound.voices.map(func(v): return weakref(v.player))
	scene.queue_free()
	await process_frame
	await process_frame
	check(players.all(func(p): return p.get_ref()==null), "scene exit frees all voices")
	print("FireAudioTest: ","PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)

func _fixture(label: String) -> void:
	clock_node.paused = label=="paused"
	clock_node.speed = 0 if label=="zero_speed" else 1
	root.get_node("SaveManager")._loading = label=="loading"
	feedback.set_muted(label=="muted")
	feedback.set_volume_db(-27 if label=="quiet" else -7)
	camera.set_meta("work_focus",Vector3(100,0,0) if label=="far" else Vector3.ZERO)
	camera.set_meta("work_zoom",200.0 if label=="overview" else 18.0)
	camera.current = label!="no_camera"
	source.visible = label!="hidden"
	source.position.y = 130 if label=="sliced" else 0
	furniture._installed = {} if label=="removed" else {1:{"installed_id":1,"node":source,"def":{"fire_sound":"torch" if label=="torch" else "campfire"}}}
	if is_instance_valid(sound):
		sound._silence()
