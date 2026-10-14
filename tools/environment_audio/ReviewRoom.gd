extends "res://scripts/tests/SaveManagerRoundTripTest.gd"

## Review a copied player save in isolated APPDATA. Never writes to the source.
const OUT := "res://tmp/room_audio_20261013/"
class Listener extends Node3D:
	var context := {}
	func get_work_audio_context() -> Dictionary: return context

func _run() -> void:
	if not "/room_audio_20261013/" in OS.get_user_data_dir().replace("\\", "/"):
		push_error("Room review needs its isolated copied-save profile"); quit(2); return
	create_timer(240).timeout.connect(func(): push_error("Room audio review timed out"); quit(1))
	root.size = Vector2i(1600, 900)
	_save_manager = root.get_node("SaveManager")
	_world_generator = root.get_node("WorldGenerator")
	_world_clock = root.get_node("WorldClock")
	_save_manager.configure_storage_for_testing("user://save_copy")
	_save_manager.set_process(false)
	var read: Dictionary = _save_manager._read_snapshot("user://save_copy/quicksave.json")
	if not read.get("ok", false): push_error("Copied save invalid"); quit(1); return
	_world_generator.world_seed = int(read.snapshot.world_seed)
	_world_clock.set_paused(true)
	node_added.connect(func(node: Node):
		if node.name == "Renderer" and node.get_script() != null: node.world_seed = int(read.snapshot.world_seed))
	change_scene_to_file("res://scenes/main/debug_world.tscn")
	await process_frame
	await process_frame
	if not await _wait_for_world_ready(WORLD_TIMEOUT_MSEC): push_error("World timeout"); quit(1); return
	_save_manager.set_process(true)
	_save_manager.load_finished.connect(_on_load_finished, CONNECT_ONE_SHOT)
	if not _load_through_dock("load_game") or not await _wait_for_load(LOAD_TIMEOUT_MSEC) or not _load_succeeded:
		push_error("Copied save load failed"); quit(1); return
	_save_manager.set_process(false)
	_world_clock.set_process(false)
	_world_clock.set_paused(false)
	var rig = current_scene.get_node("CameraRig")
	rig.set_process(false)
	# Let restored lighting and the visible slice finish, without moving view.
	for i in 90: await process_frame
	var feedback = root.get_node("WorkFeedback")
	var ambience = root.get_node("AmbientAudio")
	ambience.set_volume("effects", 1.0)
	ambience.set_volume("ambience", .5)
	ambience.set_muted("effects", false)
	ambience.set_muted("ambience", false)
	var listener := Listener.new()
	current_scene.add_child(listener)
	var contexts := {
		"pivot": {"focus": rig.global_position, "zoom": rig.global_position.distance_to(rig.camera_node.global_position)},
		"screen": rig.get_work_audio_context()
	}
	var furniture = _owner("furniture")
	var fire = furniture.get_node("FireSound")
	var sleepers: Array[Node3D] = []
	for agent in root.get_node("TaskManager")._agents.values():
		if agent is Node3D and agent.is_resting():
			sleepers.append(agent)
			agent.set_process(false)
	var results := {"contexts": contexts, "sleepers": [], "recordings": {}}
	for agent: Node3D in sleepers:
		results.sleepers.append({"id": agent.dwarf_id, "position": agent.global_position,
			"pivot_gain": feedback.spatial_gain(agent.global_position, contexts.pivot.focus, contexts.pivot.zoom, feedback._profile("snore")),
			"screen_gain": feedback.spatial_gain(agent.global_position, contexts.screen.focus, contexts.screen.zoom, feedback._profile("snore"))})
	var record := AudioEffectRecord.new()
	record.format = AudioStreamWAV.FORMAT_16_BITS
	AudioServer.add_bus_effect(0, record)
	# Capture local sounds separately and together with the new ambience.
	for label: String in ["pivot_torch", "screen_torch", "pivot_snore", "screen_snore", "room_mix"]:
		var old := label.begins_with("pivot")
		listener.context = contexts.pivot if old else contexts.screen
		feedback.clear_transients()
		feedback._sync_scene()
		feedback._view = listener
		ambience._view = listener
		ambience.set_muted("ambience", label != "room_mix")
		fire.set_process("snore" not in label)
		fire._silence()
		if "snore" not in label:
			fire._until_scan = 0
			fire._scan(listener.context)
			for i in 20: fire._process(.25)
		var fire_gain := 0.0
		for voice: Dictionary in fire.voices: fire_gain += voice.gain
		await create_timer(.2).timeout
		record.set_recording_active(true)
		var emitted := 0
		if "snore" in label or label == "room_mix":
			for agent: Node3D in sleepers:
				feedback._last_sound_msec.erase("snore")
				if feedback.play_snore(agent): emitted += 1
		await create_timer(3.2 if label != "room_mix" else 9.0).timeout
		record.set_recording_active(false)
		var wav := record.get_recording()
		wav.save_to_wav(OUT + label + ".wav")
		var pcm := wav.data
		var energy := 0.0
		var peak := 0.0
		for i in range(0, pcm.size(), 2):
			var sample := float(pcm.decode_s16(i)) / 32768.0
			energy += sample * sample
			peak = maxf(peak, absf(sample))
		results.recordings[label] = {"rms": sqrt(energy / maxi(1, pcm.size() / 2)), "peak": peak, "snore_emissions": emitted, "fire_gain": fire_gain}
	feedback._view = rig
	ambience._view = rig
	ambience.set_muted("ambience", false)
	AudioServer.remove_bus_effect(0, AudioServer.get_bus_effect_count(0) - 1)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + "room.png")
	var file := FileAccess.open(OUT + "review.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(results, "\t"))
	print("ROOM_AUDIO_REVIEW ", results)
	quit()
