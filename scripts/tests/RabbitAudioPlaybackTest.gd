extends SceneTree
## Native audio device test. Records only this game's Work bus, never a mic.
class RabbitSource extends Node3D:
	var activity := "Grazing"

var failures: Array[String] = []
var feedback
var camera: Camera3D
var source: Node3D
var recorder := AudioEffectRecord.new()
var clock_node
var species := "rabbit"

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	if "--deer" in OS.get_cmdline_user_args(): species = "deer"
	if "--wolf" in OS.get_cmdline_user_args(): species = "wolf"
	if "--duck" in OS.get_cmdline_user_args(): species = "duck"
	for service in ["SaveManager","RoomManager","StockpileManager","TaskManager","WorldClock"]: root.get_node(service).set_process(false)
	clock_node = root.get_node("WorldClock")
	clock_node.set_paused(false)
	clock_node.set_speed(1)
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	camera = Camera3D.new()
	scene.add_child(camera)
	camera.position = Vector3(0,8,10)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	camera.set_meta("work_focus",Vector3.ZERO)
	camera.set_meta("work_zoom",12.0)
	source = RabbitSource.new()
	if species == "wolf": source.activity = "Eating"
	scene.add_child(source)
	feedback = root.get_node("WorkFeedback")
	recorder.format = AudioStreamWAV.FORMAT_16_BITS
	var bus := AudioServer.get_bus_index("Work")
	AudioServer.add_bus_effect(bus,recorder)
	await create_timer(.1).timeout
	var samples := {}
	for label in ["select","select_paused","graze","far","zoom_out","left","right","pause_tail"]:
		samples[label] = await _record(label)
	if species=="duck":
		samples.splash = await _record("splash")
		_check(samples.splash.peak>.01 and samples.splash.peak<.5,"duck landing splash outputs quiet PCM")
	_check(samples.select.peak > .01 and samples.select_paused.peak > .01,"selection outputs PCM while running and paused")
	_check(samples.graze.peak > .01,"nearby grazing outputs audible PCM")
	_check(samples.far.peak < .001 and samples.zoom_out.peak < .001,"far and overview grazing produce silence")
	_check(samples.left.energy.x > samples.left.energy.y and samples.right.energy.y > samples.right.energy.x,"rabbit PCM pans left/right")
	_check(samples.pause_tail.peak < .001,"pausing silences a running graze tail")
	for label in samples: _check(samples[label].peak < .5,"quiet rabbit headroom: " + label)
	print(species.to_upper()+"_AUDIO_PCM: ",samples)
	feedback.clear_transients()
	AudioServer.remove_bus_effect(bus,AudioServer.get_bus_effect_count(bus)-1)
	recorder = null
	scene.queue_free()
	await process_frame
	await process_frame
	for failure in failures: push_error(failure)
	if failures.is_empty(): print(species.to_upper()+"_AUDIO_PLAYBACK_OK")
	quit(0 if failures.is_empty() else 1)

func _record(label: String) -> Dictionary:
	feedback.clear_transients()
	feedback._rng.seed = 293
	clock_node.set_paused(label == "select_paused")
	camera.set_meta("work_focus",Vector3(30,0,0) if label == "far" else Vector3.ZERO)
	camera.set_meta("work_zoom",80.0 if label == "zoom_out" else 12.0)
	source.position.x = -6 if label == "left" else 6 if label == "right" else 0
	var kind := species+"_select" if label.begins_with("select") else species+"_eat" if species == "wolf" else species+"_graze"
	if species=="duck" and not label.begins_with("select"): kind = "duck_splash" if label=="splash" else "duck_quack"
	if label == "pause_tail":
		feedback.play_animal(kind,source)
		await create_timer(.10).timeout
		clock_node.set_paused(true)
		await create_timer(.10).timeout # Drain the mixer's already submitted buffer.
	recorder.set_recording_active(true)
	await create_timer(.04).timeout
	if label != "pause_tail": feedback.play_animal(kind,source)
	await create_timer(.95).timeout
	recorder.set_recording_active(false)
	var wav := recorder.get_recording()
	var energy := Vector2.ZERO
	var peak := 0.0
	for i in range(wav.data.size()/4):
		var l := float(wav.data.decode_s16(i*4))/32768.0
		var r := float(wav.data.decode_s16(i*4+2))/32768.0
		energy += Vector2(l*l,r*r)
		peak = maxf(peak,maxf(absf(l),absf(r)))
	var directory := "res://tmp/deer_review/native_pcm" if species == "deer" else "res://tmp/rabbit_audio_review/native_pcm"
	if species == "wolf": directory = "res://tmp/wolf_review/native_pcm"
	if species == "duck": directory = "res://tmp/duck_review/native_pcm"
	DirAccess.make_dir_recursive_absolute(directory)
	wav.save_to_wav(directory+"/"+label+".wav")
	return {"energy":energy,"peak":peak}

func _check(ok: bool, label: String) -> void:
	if not ok: failures.append(label)
