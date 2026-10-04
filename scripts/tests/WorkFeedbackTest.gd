extends "res://scripts/tests/TreeFellingTest.gd"

class SliceStub extends Node:
	var height := 127
	func get_slice_y() -> int:
		return height

var feedback
var sound_events: Array = []
var burst_events: Array = []
var slice_stub: Node


func _setup_feedback_fixture() -> void:
	for name in ["SaveManager","RoomManager","StockpileManager"]:
		root.get_node(name).set_process(false)
	clock_node = root.get_node("WorldClock")
	clock_node.set_process(false)
	clock_node.set_paused(false)
	clock_node.set_speed(1)
	tasks = root.get_node("TaskManager")
	tasks.set_process(false)
	root.get_node("WorldGenerator").world_seed = 1234
	world = root.get_node("WorldData")
	blocks = root.get_node("BlockRegistry")
	_build_floor()
	scene = Node3D.new()
	root.add_child(scene)
	current_scene = scene
	camera = Camera3D.new()
	scene.add_child(camera)
	camera.position = Vector3(32,33,29)
	camera.look_at(Vector3(41.5,22,41.5))
	camera.current = true
	camera.set_meta("work_focus",Vector3(41.5,21,41.5))
	camera.set_meta("work_zoom",24.0)
	slice_stub = SliceStub.new()
	slice_stub.add_to_group("work_feedback_slice")
	scene.add_child(slice_stub)
	drops = load("res://scripts/systems/ItemDropManager.gd").new()
	scene.add_child(drops)
	flora = load("res://scripts/systems/SurfaceFloraSpawner.gd").new()
	scene.add_child(flora)
	flora.set_process(false)
	flora._season = "summer"
	_spawn_tree("oak","mature",Vector2i(40,40))
	flora.designate_felling(Vector2i(40,40))
	var factory = load("res://scripts/entities/DwarfFactory.gd").new()
	worker = factory.spawn(factory.generate(101,{}),101)
	scene.add_child(worker)
	worker.position = Vector3(41.5,21,39.5)
	worker.set_process(false)
	tasks.register_dwarf(worker)
	feedback = root.get_node("WorkFeedback")
	feedback.set_process(false)
	feedback._sync_scene()
	feedback.sound_started.connect(func(kind,position,variant): sound_events.append([kind,position,variant]))
	feedback.burst_started.connect(func(position,stage): burst_events.append([position,stage]))
	_expect(await _until_working(),"fixture has real assigned work")


func _run() -> void:
	await _setup_feedback_fixture()
	var focus := Vector3(41.5,21,41.5)
	var near_gain: float = feedback.spatial_gain(focus,focus,24)
	var mid_gain: float = feedback.spatial_gain(focus+Vector3(30,0,0),focus,24)
	_expect(near_gain > mid_gain and mid_gain > 0,"camera focus distance attenuates monotonically")
	_expect(feedback.spatial_gain(focus+Vector3(80,0,0),focus,24) == 0,"far work becomes silent")
	_expect(feedback.spatial_gain(focus,focus,120) < near_gain*.3,"zoomed-out impacts are quieter")
	_expect(feedback.spatial_gain(focus,focus+Vector3(0,100,0),24) == near_gain,"elevated RTS pivot does not silence nearby work")
	worker._process(.60)
	_expect(sound_events.is_empty(),"no sound during wind-up")
	worker._process(.03)
	_expect(sound_events.size() == 1 and sound_events[0][0] == "chop","sound at first contact crossing")
	worker._process(.02)
	_expect(sound_events.size() == 1,"contact hold does not repeat sound")
	feedback._process(.5)
	worker._process(1.15)
	_expect(sound_events.size() == 2,"one hit across cycle wrap")
	feedback._process(.5)
	worker._process(2.4)
	_expect(sound_events.size() == 3,"long frame coalesces skipped impacts without backlog")
	clock_node.set_paused(true)
	worker._process(2)
	_expect(sound_events.size() == 3,"pause emits no impacts")
	clock_node.set_paused(false)
	worker.dev_force_interrupt()
	_expect(await _until_working(),"interruption resumes job")
	clock_node.set_speed(3)
	worker._process(.20)
	_expect(sound_events.size() == 3,"3x wind-up waits for contact")
	worker._process(.01)
	_expect(sound_events.size() == 4,"3x contact has one impact")
	var pitch: float = feedback._voices.back().player.pitch_scale
	_expect(pitch > .96 and pitch < 1.04,"speed changes cadence, not audio pitch")
	clock_node.set_speed(1)
	worker.dev_force_interrupt()
	_expect(await _until_working(),"second interruption resumes")
	worker._process(.2)
	flora.cancel_felling(Vector2i(40,40))
	worker._process(.5)
	_expect(sound_events.size() == 4,"cancel before contact emits nothing")
	flora.designate_felling(Vector2i(40,40))
	_expect(await _until_working(),"cancelled work restarts")
	flora._on_slice_changed(19)
	worker._process(.7)
	_expect(sound_events.size() == 4,"slice-hidden tree produces no hit")
	flora._on_slice_changed(127)
	worker._process(.01)
	_expect(sound_events.size() == 4,"revealing tree does not replay missed hit")
	var count_before := sound_events.size()
	camera.set_meta("work_focus",focus+Vector3(100,0,0))
	worker._process(1.15)
	_expect(sound_events.size() == count_before,"panning away suppresses further hits")
	camera.set_meta("work_focus",focus)
	feedback.clear_transients()
	_expect(await _until_felled(Vector2i(40,40)),"actual felling commits")
	_expect(burst_events.size() == 1 and feedback._bursts.size() == 1,"completion emits exactly one independent poof")
	_expect(_item_count("base:resources:wood:oak_log") == 4,"loot remains immediately available")
	var snapshot: Dictionary = flora.serialize_state()
	flora.restore_state(snapshot)
	_expect(burst_events.size() == 1,"loading completed tree never replays effect")
	var burst: Node3D = feedback._bursts[0]
	feedback._process(.1)
	var age: float = burst.age
	clock_node.set_paused(true)
	feedback._process(.4)
	_expect(is_equal_approx(burst.age,age),"pause freezes dust")
	slice_stub.height = 19
	feedback._process(.01)
	_expect(not burst.visible,"active poof hides with slice")
	slice_stub.height = 127
	feedback._process(.01)
	_expect(burst.visible,"active poof follows slice reveal")
	clock_node.set_paused(false)
	clock_node.set_speed(2)
	feedback._process(.1)
	_expect(is_equal_approx(burst.age,age+.2),"dust follows simulation speed")
	clock_node.set_speed(1)
	feedback._process(1)
	_expect(feedback._bursts.is_empty(),"dust expires and frees its nodes")
	# Pool bounds, near-over-far voice priority and per-hit variation.
	feedback.clear_transients()
	for i in range(int(feedback.config.audio.max_voices)):
		_expect(feedback.play_chop(focus+Vector3(35,0,0),20),"fill bounded voice pool")
	_expect(feedback._voices.size() == 8,"voice pool capped at eight")
	_expect(not feedback.play_chop(focus+Vector3(45,0,0),20),"quieter overflow is discarded")
	_expect(feedback.play_chop(focus,20),"near impact replaces distant tail")
	var previous := -1
	for i in range(20):
		feedback._process(1)
		feedback.play_chop(focus,20)
		var variant: int = sound_events.back()[2]
		_expect(variant != previous,"no immediate sample repeats")
		previous = variant
	var voice: Dictionary = feedback._voices[0]
	var close_volume: float = voice.player.volume_db
	camera.set_meta("work_focus",focus+Vector3(30,0,0))
	feedback._process(.01)
	_expect(voice.player.volume_db < close_volume,"an active sound attenuates while camera pans")
	camera.set_meta("work_focus",focus+Vector3(100,0,0))
	feedback._process(.01)
	_expect(voice.remaining == 0,"inaudible tail stops without queued replay")
	camera.set_meta("work_focus",focus)
	for i in range(20):
		feedback.tree_felled(focus,"ancient",20)
	_expect(feedback._bursts.size() == 12,"simultaneous poofs bounded")
	feedback.set_muted(true)
	_expect(AudioServer.is_bus_mute(AudioServer.get_bus_index("Work")),"shared work mute route")
	feedback.set_muted(false)
	scene.free()
	current_scene = null
	_expect(feedback._voices.is_empty() and feedback._bursts.is_empty(),"scene exit clears all transient feedback")
	for i in range(3):
		await process_frame
	for failure in failures:
		push_error(failure)
	if failures.is_empty():
		print("WORK_FEEDBACK_OK: real contacts, wrap/stall, pause/speed, cancellation, camera attenuation, variation/pool bounds, completion, slice, restore, cleanup")
	quit(0 if failures.is_empty() else 1)
