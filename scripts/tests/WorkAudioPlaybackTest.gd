extends SceneTree

## Run with an audio device (not --headless). Records ONLY the game's Work
## bus, never microphone input, and checks real stereo/attenuated PCM output.
var failures: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var kind := "chop"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--kind="):
			kind = argument.trim_prefix("--kind=")
	for name in ["SaveManager","RoomManager","StockpileManager","TaskManager","WorldClock"]:
		root.get_node(name).set_process(false)
	root.get_node("WorldClock").set_paused(false)
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.position = Vector3(0,20,20)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	camera.set_meta("work_focus",Vector3.ZERO)
	camera.set_meta("work_zoom",24.0)
	var feedback := root.get_node("WorkFeedback")
	var recorder := AudioEffectRecord.new()
	recorder.format = AudioStreamWAV.FORMAT_16_BITS
	var bus := AudioServer.get_bus_index("Work")
	AudioServer.add_bus_effect(bus,recorder)
	await create_timer(.1).timeout
	var samples := {}
	for name in ["near","pan_away","zoom_out","left","right","crowd"]:
		camera.set_meta("work_focus",Vector3(35,0,0) if name == "pan_away" else Vector3.ZERO)
		camera.set_meta("work_zoom",120.0 if name == "zoom_out" else 24.0)
		feedback.clear_transients()
		feedback._rng.seed = 293
		recorder.set_recording_active(true)
		await create_timer(.04).timeout
		var position := Vector3.ZERO
		if name in ["left","right"]:
			position.x = -20 if name == "left" else 20
		for i in range(8 if name == "crowd" else 1):
			feedback._play(kind,position,0)
		await create_timer(.5).timeout
		recorder.set_recording_active(false)
		var wav := recorder.get_recording()
		var energy := Vector2.ZERO
		var peak := 0.0
		var count := wav.data.size()/4
		for i in range(count):
			var l := float(wav.data.decode_s16(i*4))/32768.0
			var r := float(wav.data.decode_s16(i*4+2))/32768.0
			energy += Vector2(l*l,r*r)
			peak = maxf(peak,maxf(absf(l),absf(r)))
		samples[name] = {"energy":energy,"peak":peak}
		var directory := "res://tmp/work_audio_review/"+kind
		DirAccess.make_dir_recursive_absolute(directory)
		wav.save_to_wav(directory+"/%s.wav" % name)
	if samples.near.peak < .01:
		failures.append("No audible PCM output from Work bus")
	if samples.pan_away.energy.length() >= samples.near.energy.length()*.3:
		failures.append("Panning away did not reduce actual recorded output")
	if samples.zoom_out.energy.length() >= samples.near.energy.length()*.15:
		failures.append("Zooming out did not reduce actual recorded output")
	if samples.left.energy.x <= samples.left.energy.y or samples.right.energy.y <= samples.right.energy.x:
		failures.append("Stereo output does not follow left/right sources")
	if samples.crowd.peak >= .95:
		failures.append("Eight simultaneous hits have insufficient audio headroom")
	feedback.clear_transients()
	AudioServer.remove_bus_effect(bus,0)
	await create_timer(.1).timeout
	for failure in failures:
		push_error(failure)
	print("WORK_AUDIO_PCM: ",samples)
	if failures.is_empty():
		print("WORK_AUDIO_PLAYBACK_OK: real PCM, focus distance, zoom, stereo, eight-voice headroom")
	quit(0 if failures.is_empty() else 1)
