extends "res://scripts/tests/AmbientAudioTest.gd"

const DETAILS_OUT := "res://tmp/environment_details_20261013/"
class Wildlife extends Node:
	var animals: Array[Node3D] = []

func _run() -> void:
	create_timer(120).timeout.connect(func(): push_error("Environment details timed out"); quit(1))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DETAILS_OUT))
	await _setup_crafting_fixture()
	var water = root.get_node("WaterManager")
	water.set_process(false)
	ambience = root.get_node("AmbientAudio")
	ambience.set_process(false)
	ambience._preferences_path = DETAILS_OUT + "test_audio.cfg"
	ambience.set_volume("ambience", .72)
	ambience.set_volume("effects", 1)
	ambience.set_muted("ambience", false)
	ambience.set_muted("effects", false)
	view.add_to_group("work_audio_view")
	exposure.add_to_group("underground_lighting")
	forest.add_to_group("surface_flora")
	scene.add_child(view)
	scene.add_child(exposure)
	scene.add_child(forest)
	view.position = Vector3(49, 21, 42)
	var weather = root.get_node("WeatherManager")
	weather.set_process(false)
	var random_before: int = weather._rng.state
	var generator = root.get_node("WorldGenerator")
	var seed_before: int = generator.world_seed
	clock_node.season = "summer"
	clock_node.hour = 1
	root.get_node("SkyController")._refresh_event_hours()
	var wet := {"shoreline": {"point": view.position, "distance": 2.0}, "frogs": {"point": view.position, "distance": 2.0}, "drips": {"point": view.position, "distance": 2.0}, "creaks": {"point": view.position, "distance": 2.0}, "wolves": {"point": view.position, "distance": 2.0}, "roof_gain": 1.0}
	var night: Dictionary = ambience.mix_for(1,"summer","base:weather:clear",1,1,24,wet)
	_expect(night.frogs > .9 and night.chirps > .9 and night.wolves > .9, "warm wet night supplies frogs, chirps and real wolf source")
	var day: Dictionary = ambience.mix_for(14,"summer","base:weather:clear",1,1,24,wet)
	_expect(day.day_insects > .9 and day.frogs == 0 and day.wolves == 0, "daytime insects replace nocturnal calls")
	var winter: Dictionary = ambience.mix_for(1,"winter","base:weather:snow",1,1,24,wet)
	_expect(winter.frogs == 0 and winter.day_insects == 0 and winter.chirps == 0 and winter.winter_wind > 0, "cold weather removes insects and frogs")
	var autumn: Dictionary = ambience.mix_for(14,"autumn","base:weather:clear",1,1,24,wet)
	_expect(autumn.dry_leaves > day.dry_leaves, "autumn has dry leaf texture")
	var room: Dictionary = ambience.mix_for(1,"summer","base:weather:storm",0,1,24,{})
	_expect(room.drips == 0 and room.frogs == 0 and room.rain == 0 and room.rain_roof == 0, "dry deep room stays free of wildlife, drips and rain")
	var shelter: Dictionary = ambience.mix_for(1,"summer","base:weather:rain",0,1,24,wet)
	_expect(shelter.rain_roof > 0 and shelter.rain == 0 and shelter.thunder == 0, "roof patter uses indoor rain without thunder in ordinary rain")
	_expect(ambience.mix_for(1,"summer","base:weather:storm",1,1,24,wet).thunder == 1, "thunder belongs to storms")
	_expect(ambience.mix_for(1,"summer","base:weather:clear",1,1,24,{}).shoreline == 0, "no shoreline source means no lapping")
	# Shore, frog and cave-drip sources come from WaterManager's real water (its water_columns
	# index); this fixture has none, so they are not checked here.
	var source_scan = ambience._sources
	# Live tree and wolf sources are removed or invalidated immediately.
	var actual_flora = load("res://scripts/systems/SurfaceFloraSpawner.gd").new()
	var tree := Node3D.new()
	scene.add_child(tree)
	tree.position = view.position
	tree.set_meta("tree_id", Vector2i(3,2))
	actual_flora._loaded_columns[Vector2i(3,2)] = [tree]
	_expect(source_scan.scan(view.position,127,18,actual_flora,null).has("creaks"), "creak originates at live visible tree")
	actual_flora._tree_changes[Vector2i(3,2)] = {"felled":true}
	_expect(not source_scan.scan(view.position,127,18,actual_flora,null).has("creaks"), "felled tree cannot creak")
	actual_flora.free()
	var wildlife := Wildlife.new()
	scene.add_child(wildlife)
	var wolf = load("res://scripts/entities/WolfAgent.gd").new()
	scene.add_child(wolf)
	wolf.position = view.position
	wildlife.animals.append(wolf)
	var found: Dictionary = source_scan.scan(view.position,127,18,null,wildlife)
	_expect(found.has("wolves"), "howl requires actual nearby wolf")
	wolf.activity = "Sleeping"
	_expect(not source_scan.scan(view.position,127,18,null,wildlife).has("wolves"), "sleeping wolves do not howl")
	wolf.activity = "Idle"
	# Exercise real voice allocation, source lifetime and each new audio asset.
	ambience._process(.1)
	ambience._habitat = wet.duplicate(true)
	ambience._habitat.wolves = found.wolves
	ambience.targets = night
	for voice: Dictionary in ambience.calls: voice.left = 0
	_expect(ambience._start_call("wolves"), "wolf emits through real pool")
	_expect(ambience.calls.any(func(v): return v.kind == "wolves" and v.player.bus == &"Work"), "actual wolves obey Effects slider")
	wolf.hide()
	ambience._scan_left = 99
	ambience._process(.1)
	_expect(ambience.calls.all(func(v): return v.kind != "wolves" or v.left == 0), "hidden source stops existing howl")
	wolf.show()
	wet.wolves = found.wolves
	wet.creaks.node = weakref(tree)
	if DisplayServer.get_name() != "headless": await _details_pcm(wet)
	# Weather registry, deterministic schedule and saved-ID round trip.
	for id: String in ["base:weather:rain","base:weather:storm"]:
		weather.set_weather(id)
		var saved: Dictionary = weather.serialize_state()
		weather.set_weather("base:weather:clear")
		weather.restore_state(saved)
		_expect(weather.current_weather_id() == id and weather.current_definition().precipitation.intensity > 0, "new weather ID survives restoration: " + id)
	for season: String in ["spring","summer","autumn"]:
		_expect(weather._schedule[season].any(func(e): return e.weather == "base:weather:rain") and weather._schedule[season].any(func(e): return e.weather == "base:weather:storm"), "rain and storm scheduled: " + season)
	_expect(weather._rng.state == random_before and generator.world_seed == seed_before, "cosmetic additions leave simulation RNG untouched")
	# Rain geometry respects a physical roof even when that roof is sliced off.
	var rain = load("res://scripts/components/WeatherPrecipitation.gd").new()
	scene.add_child(rain)
	rain.set_process(false)
	var profile: Dictionary = weather.current_definition().precipitation
	rain.drops.append({"point":Vector3(49,21.05,42),"phase":.5,"strength":.25})
	rain._slice = null
	rain._draw_rain(profile)
	_expect(rain.visible_streaks == 1, "storm draws precipitation in open space")
	var slice_stub = load("res://scripts/tests/AudioListeningPointTest.gd").Slice.new()
	slice_stub.height = 15
	scene.add_child(slice_stub)
	rain._slice = slice_stub
	rain._draw_rain(profile)
	_expect(rain.visible_streaks == 0, "cutting below physical roof suppresses rain")
	weather.set_weather("base:weather:clear")
	rain._process(.1)
	_expect(not rain.visual.visible, "clear weather removes precipitation")
	ambience.clear_scene()
	for failure in failures: push_error(failure)
	var report := FileAccess.open(DETAILS_OUT + ("checks.json" if DisplayServer.get_name() == "headless" else "native_pcm.json"),FileAccess.WRITE)
	report.store_string(JSON.stringify({"failures":failures,"pcm":measurements},"\t"))
	print("EnvironmentDetailsTest: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)

func _details_pcm(habitat: Dictionary) -> void:
	var capture := AudioEffectRecord.new()
	capture.format = AudioStreamWAV.FORMAT_16_BITS
	AudioServer.add_bus_effect(0,capture)
	for kind: String in ["day_insects","dry_leaves","winter_wind","shoreline","rain","rain_roof","frogs","drips","creaks","wolves","thunder","chirps"]:
		for voice: Dictionary in ambience.loops.values(): voice.player.stop()
		for voice: Dictionary in ambience.calls: voice.player.stop(); voice.left = 0
		ambience._habitat = habitat.duplicate(true)
		ambience.targets[kind] = 1.0
		await create_timer(.1).timeout
		capture.set_recording_active(true)
		if ambience.loops.has(kind):
			var voice: Dictionary = ambience.loops[kind]
			voice.player.volume_db = ambience.config.loops[kind].level_db
			if voice.player is AudioStreamPlayer3D: voice.player.global_position = view.position
			voice.player.play()
		else:
			_expect(ambience._start_call(kind), "native emission: " + kind)
		await create_timer(3 if kind != "thunder" else 8).timeout
		capture.set_recording_active(false)
		var wav := capture.get_recording()
		wav.save_to_wav(DETAILS_OUT + kind + ".wav")
		var pcm := wav.data
		var energy := 0.0
		var peak := 0.0
		for i in range(0,pcm.size(),2):
			var sample := float(pcm.decode_s16(i))/32768.0
			energy += sample*sample
			peak = maxf(peak,absf(sample))
		var rms := sqrt(energy/maxi(1,pcm.size()/2))
		measurements[kind] = {"rms":rms,"peak":peak}
		_expect(rms > .0004 and peak < .65, "audible native PCM with headroom: " + kind)
	AudioServer.remove_bus_effect(0,AudioServer.get_bus_effect_count(0)-1)
