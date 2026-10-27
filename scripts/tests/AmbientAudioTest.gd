extends "res://scripts/tests/WorkerCraftingTest.gd"

const OUT := "res://tmp/ambience_20261013/"
class View extends Node3D:
	var zoom := 24.0
	func get_work_audio_context() -> Dictionary:
		return {"focus": global_position, "zoom": zoom}
class Exposure extends Node:
	var amount := 1.0
	func actor_sky_at(_point: Vector3) -> float: return amount
class Forest extends Node:
	var amount := 1.0
	func ambient_tree_density(_point: Vector3, _radius: float, _full: float) -> float: return amount

var ambience
var view := View.new()
var exposure := Exposure.new()
var forest := Forest.new()
var recorder := AudioEffectRecord.new()
var measurements := {}


func _run() -> void:
	create_timer(120).timeout.connect(func(): push_error("Ambience fixture timed out"); quit(1))
	await _setup_crafting_fixture()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	ambience = root.get_node("AmbientAudio")
	ambience.set_process(false)
	ambience._preferences_path = OUT + "test_preferences.cfg"
	ambience.set_volume("ambience", .72)
	ambience.set_volume("effects", .4466836)
	ambience.set_muted("ambience", false)
	ambience.set_muted("effects", false)
	view.add_to_group("work_audio_view")
	exposure.add_to_group("underground_lighting")
	forest.add_to_group("surface_flora")
	scene.add_child(view)
	scene.add_child(exposure)
	scene.add_child(forest)
	view.position = Vector3(45, 21, 42)
	var weather = root.get_node("WeatherManager")
	var rng_state: int = weather._rng.state
	var world_seed: int = root.get_node("WorldGenerator").world_seed
	var sky = root.get_node("SkyController")
	clock_node.season = "summer"
	sky._refresh_event_hours()
	var day: Dictionary = ambience.mix_for(14, "summer", "base:weather:clear", 1, 1, 24)
	var night: Dictionary = ambience.mix_for(1, "summer", "base:weather:clear", 1, 1, 24)
	_expect(day.birds > .5 and day.crickets == 0 and day.owls == 0, "day has birds, no night insects or owls")
	_expect(night.crickets > .9 and night.owls > .9 and night.birds < .001, "warm night changes its sound palette")
	for season: String in ["spring", "summer", "autumn", "winter"]:
		clock_node.season = season
		clock_node.day = 1
		sky._refresh_event_hours()
		var events: Dictionary = sky.current_event_hours()
		for anchor: String in ["sunrise_start", "sunrise", "sunrise_end", "sunset_start", "sunset", "sunset_end"]:
			var a: Dictionary = ambience.mix_for(float(events[anchor]) - .001, season, "base:weather:clear", 1, 1, 24)
			var b: Dictionary = ambience.mix_for(float(events[anchor]) + .001, season, "base:weather:clear", 1, 1, 24)
			_expect(absf(a.birds - b.birds) < .01 and absf(a.crickets - b.crickets) < .01, "continuous seasonal transition: " + season + anchor)
	_expect(ambience.mix_for(1, "winter", "base:weather:clear", 1, 1, 24).crickets == 0, "no winter insects")
	_expect(ambience.mix_for(1, "summer", "base:weather:snow", 1, 1, 24).crickets == 0, "snow suppresses insects independently of season")
	_expect(ambience.mix_for(14, "summer", "base:weather:overcast", 1, 1, 24).wind > day.wind, "overcast wind increases")
	_expect(ambience.mix_for(14, "summer", "base:weather:foggy", 1, 1, 24).birds < day.birds, "fog reduces bird activity")
	_expect(ambience.mix_for(14, "summer", "base:weather:clear", 0, 1, 24).birds == 0, "enclosed space removes exterior calls")
	_expect(ambience.mix_for(14, "summer", "base:weather:clear", 1, 0, 24).foliage == 0, "no foliage bed in clearing")
	_expect(ambience.mix_for(14, "summer", "base:weather:clear", 1, 1, 300).wind == day.wind, "overview retains broad wind")
	clock_node.season = "summer"
	sky._refresh_event_hours()
	clock_node.hour = 14
	weather.set_weather("base:weather:clear")
	ambience._process(.1)
	_expect(ambience.loops.size() == ambience.config.loops.size() and ambience.calls.size() == ambience.config.call_voices, "bounded soundscape pool")
	for i in 20: ambience._process(1)
	var full: float = ambience.loops.wind.gain
	clock_node.paused = true
	for i in 40: ambience._process(1)
	_expect(ambience.loops.wind.gain > 0 and ambience.loops.wind.gain < full * .3, "pause softens continuous ambience")
	for voice: Dictionary in ambience.calls: _expect(voice.left == 0, "pause stops discrete wildlife phrases")
	clock_node.paused = false
	clock_node.speed = 2
	ambience._process(.1)
	for voice: Dictionary in ambience.loops.values(): _expect(voice.player.pitch_scale == 1, "fast simulation retains loop pitch")
	clock_node.speed = 1
	for voice: Dictionary in ambience.calls: voice.left = 0
	_expect(ambience._start_call("birds") and not ambience._start_call("birds"), "one concurrent phrase per family")
	for voice: Dictionary in ambience.calls: voice.left = 1
	_expect(not ambience._start_call("birds"), "call allocation cannot exceed pool")
	var first: int = ambience._last_variant.birds
	ambience.calls[0].left = 0
	ambience._start_call("birds")
	_expect(first != ambience._last_variant.birds, "successive bird phrases vary")
	# Preferences are independent of saves and affect only their own channel.
	ambience.set_volume("effects", .2)
	ambience.set_volume("ambience", .6)
	ambience.set_muted("ambience", true)
	_expect(not AudioServer.is_bus_mute(ambience._bus("effects")), "ambience mute preserves effects")
	_expect(is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(ambience._bus("effects"))), .2), "effects has independent volume")
	ambience.save_preferences()
	ambience.set_volume("effects", .8)
	ambience.reload_preferences()
	_expect(is_equal_approx(ambience.volume("effects"), .2) and ambience.muted("ambience"), "preferences survive reload")
	ambience.set_volume("ambience", 0)
	ambience.set_muted("ambience", false)
	_expect(AudioServer.is_bus_mute(ambience._bus("ambience")), "zero slider is a true mute")
	ambience.set_volume("ambience", .72)
	ambience.set_volume("effects", .4466836)
	# The game menu's Settings page (doc 23), its Audio tab and real controls, at small and normal sizes.
	var menu = root.get_node("GameMenu")
	for size: Vector2i in [Vector2i(960, 540), Vector2i(1920, 1080)]:
		root.size = size
		await _frames(4)
		menu.open()
		menu._choose("settings")
		menu._settings.show_section("audio")
		await _frames(8)
		_expect(menu._settings.visible and menu._title.text == "Settings" and Rect2(Vector2.ZERO, Vector2(size)).encloses(menu._frame.get_global_rect()),
			"the Settings page opens in the menu and fits: " + str(size))
		var parts: Dictionary = menu._settings.controls.ambience
		parts.slider.value = 61
		_expect(is_equal_approx(ambience.volume("ambience"), .61) and parts.value.text == "61%", "the visible slider changes the live mix and its percentage")
		_click(parts.mute.get_global_rect().get_center())
		await _frames(2)
		_expect(ambience.muted("ambience") and parts.mute.button_pressed, "the actual Mute button mutes the bus")
		_click(parts.mute.get_global_rect().get_center())
		await _frames(2)
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(OUT + "settings_%d.png" % size.x)
		_click(menu._settings.restore_button.get_global_rect().get_center())
		await _frames(2)
		_expect(is_equal_approx(ambience.volume("ambience"), .72) and not ambience.muted("ambience") and parts.slider.value == 72,
			"Restore defaults puts the mix and the slider back")
		menu.close()
	ambience.set_volume("ambience", .72)
	if DisplayServer.get_name() != "headless": await _native_audio()
	_expect(weather._rng.state == rng_state and root.get_node("WorldGenerator").world_seed == world_seed, "audio leaves world/weather random state unchanged")
	var players: Array = []
	for voice: Dictionary in ambience.loops.values(): players.append(weakref(voice.player))
	root.remove_child(scene)
	_expect(ambience.loops.is_empty() and ambience.calls.is_empty(), "detach immediately clears sound even before old scene frees")
	ambience._process(.2)
	for ref: WeakRef in players: _expect(ref.get_ref() == null, "old player freed")
	root.add_child(scene)
	current_scene = scene
	ambience._process(.1)
	_expect(ambience.loops.size() == ambience.config.loops.size(), "same world rebinds after scene transition")
	root.get_node("SaveManager")._loading = true
	ambience._process(.1)
	_expect(ambience.loops.is_empty(), "loading blocks playback and clears voices")
	root.get_node("SaveManager")._loading = false
	ambience._process(.1)
	_expect(ambience.loops.size() == ambience.config.loops.size(), "restored world rebuilds one pool")
	scene.remove_child(view)
	ambience._process(.1)
	_expect(ambience.loops.is_empty() and ambience.calls.is_empty(), "removing the listening view silences the old world")
	view.free()
	ambience.clear_scene()
	for failure in failures: push_error(failure)
	print("AmbientAudioTest: ", "PASS" if failures.is_empty() else "FAIL", " (", measurements, ")")
	quit(0 if failures.is_empty() else 1)


func _native_audio() -> void:
	# Record only game mixer output; no microphone or external device capture.
	recorder.format = AudioStreamWAV.FORMAT_16_BITS
	AudioServer.add_bus_effect(ambience._bus("ambience"), recorder)
	ambience.set_process(true)
	for label: String in ["day", "night", "shelter", "overview", "paused", "muted"]:
		clock_node.hour = 1 if label == "night" else 14
		exposure.amount = 0 if label == "shelter" else 1
		view.zoom = 300 if label == "overview" else 24
		clock_node.paused = label == "paused"
		ambience.set_muted("ambience", label == "muted")
		ambience._scan_left = 0
		# Settle a long fade without changing playback pitch or the game clock.
		for i in 40: ambience._process(1)
		await create_timer(.2).timeout
		if label == "day":
			for voice: Dictionary in ambience.calls: voice.left = 0
			ambience._start_call("birds")
		if label == "night":
			for voice: Dictionary in ambience.calls: voice.left = 0
			ambience._start_call("owls")
		recorder.set_recording_active(true)
		await create_timer(10 if label in ["day", "night"] else 1.2).timeout
		recorder.set_recording_active(false)
		var wav := recorder.get_recording()
		wav.save_to_wav(OUT + label + ".wav")
		var pcm := wav.data
		var energy := 0.0
		var peak := 0.0
		for i in range(0, pcm.size(), 2):
			var sample := float(pcm.decode_s16(i)) / 32768.0
			energy += sample * sample
			peak = maxf(peak, absf(sample))
		measurements[label] = {"rms": sqrt(energy / maxi(1, pcm.size() / 2)), "peak": peak}
	# A bus effect precedes bus mute/volume. Master capture is used below to
	# verify the actual mute reaching the speakers.
	var bus: int = ambience._bus("ambience")
	AudioServer.remove_bus_effect(bus, AudioServer.get_bus_effect_count(bus) - 1)
	AudioServer.add_bus_effect(0, recorder)
	root.get_node("WorkFeedback").set_muted(true)
	recorder.set_recording_active(true)
	await create_timer(.8).timeout
	recorder.set_recording_active(false)
	var silent := recorder.get_recording()
	var silent_pcm := silent.data
	var mute_peak := 0
	for i in range(0, silent_pcm.size(), 2): mute_peak = maxi(mute_peak, absi(silent_pcm.decode_s16(i)))
	_expect(mute_peak < 4, "muted Master output is silent")
	AudioServer.remove_bus_effect(0, AudioServer.get_bus_effect_count(0) - 1)
	for label: String in ["day", "night", "shelter", "overview"]:
		_expect(measurements[label].rms > .0005 and measurements[label].peak < .5, "audible PCM with headroom: " + label)
	_expect(measurements.paused.rms < measurements.day.rms * .5, "pause attenuation reaches mixer")
	var report := FileAccess.open(OUT + "pcm.json", FileAccess.WRITE)
	report.store_string(JSON.stringify(measurements, "\t"))
	clock_node.paused = false
	ambience.set_muted("ambience", false)
	root.get_node("WorkFeedback").set_muted(false)
	ambience.set_process(false)
