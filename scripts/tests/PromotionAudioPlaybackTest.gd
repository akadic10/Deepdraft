extends SceneTree
## Native PCM output test; records only game audio, never the microphone.
var feedback
var recorder := AudioEffectRecord.new()

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	for service in ["SaveManager", "RoomManager", "StockpileManager", "TaskManager", "WorldClock"]:
		root.get_node(service).set_process(false)
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	feedback = root.get_node("WorkFeedback")
	recorder.format = AudioStreamWAV.FORMAT_16_BITS
	# Record Master so the Work bus volume/mute controls are included in PCM.
	AudioServer.add_bus_effect(0, recorder)
	await create_timer(.1).timeout
	var samples := {}
	for label in ["normal", "paused", "quiet", "muted", "cleared"]:
		samples[label] = await _record(label)
	var ok: bool = samples.normal.peak > .02 and samples.normal.peak < .5 \
		and samples.paused.peak > .02 and samples.quiet.peak < samples.normal.peak*.4 \
		and samples.muted.peak < .001 and samples.cleared.peak < .001
	feedback.clear_transients()
	feedback.set_muted(false)
	feedback.set_volume_db(float(feedback.config.audio.volume_db))
	AudioServer.remove_bus_effect(0, AudioServer.get_bus_effect_count(0)-1)
	print("PROMOTION_AUDIO_PCM: ", samples)
	if ok: print("PROMOTION_AUDIO_PLAYBACK_OK: audible notification without camera, paused, volume, mute, cleanup and headroom")
	else: push_error("Promotion PCM checks failed")
	quit(0 if ok else 1)

func _record(label: String) -> Dictionary:
	feedback.clear_transients()
	root.get_node("WorldClock").set_paused(label == "paused")
	feedback.set_volume_db(-24 if label == "quiet" else float(feedback.config.audio.volume_db))
	feedback.set_muted(label == "muted")
	if label == "cleared":
		feedback.play_promotion(Vector3(900,90,900))
		await create_timer(.1).timeout
		feedback.clear_transients()
		await create_timer(.12).timeout
	recorder.set_recording_active(true)
	await create_timer(.04).timeout
	if label != "cleared": feedback.play_promotion(Vector3(900,90,900))
	await create_timer(1.4).timeout
	recorder.set_recording_active(false)
	var wav := recorder.get_recording()
	var peak := 0.0
	var energy := 0.0
	for i in range(wav.data.size()/2):
		var sample := float(wav.data.decode_s16(i*2))/32768.0
		peak = maxf(peak, absf(sample))
		energy += sample * sample
	wav.save_to_wav("res://tmp/equipment_ui_review/promotion_%s.wav" % label)
	return {"peak":peak, "energy":energy}
