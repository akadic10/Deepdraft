extends "res://scripts/tests/ObjectExplorerTest.gd"
## Actual inspector selection and rabbit meal progress through the shared pool.
## Uses isolated user storage, no sound-driven simulation or saved audio timers.
class SliceStub extends Node:
	var height := 127
	func get_slice_y() -> int: return height

var wildlife
var rabbit
var feedback
var clock_node
var slice_stub
var events: Array = []

func _run() -> void:
	create_timer(45).timeout.connect(func(): push_error("Rabbit audio timed out"); quit(1))
	for service in ["SaveManager","RoomManager","StockpileManager","TaskManager","WorldClock"]: root.get_node(service).set_process(false)
	clock_node = root.get_node("WorldClock")
	clock_node.set_paused(true)
	clock_node.set_speed(1)
	world = root.get_node("WorldData")
	blocks = root.get_node("BlockRegistry")
	_build_floor()
	world.set_block(40,20,40,blocks.get_id("base:terrain:surface:grass_01"))
	scene = Node3D.new()
	root.add_child(scene)
	current_scene = scene
	wildlife = load("res://scripts/systems/WildlifeManager.gd").new()
	scene.add_child(wildlife)
	wildlife.set_process(false)
	wildlife.initialized = true
	rabbit = wildlife.add_rabbit("rabbit:audio:40:40",Vector3i(40,21,40),1234)
	manager = load("res://scripts/ui/UIWindowManager.gd").new()
	manager.name = "Windows"
	scene.add_child(manager)
	manager._layout_loaded = false
	explorer = load("res://scripts/ui/ObjectExplorerController.gd").new()
	explorer.window_manager_path = NodePath("../Windows")
	scene.add_child(explorer)
	camera = Camera3D.new()
	scene.add_child(camera)
	camera.current = true
	_aim_above(rabbit.position)
	camera.set_meta("work_focus",rabbit.position)
	camera.set_meta("work_zoom",12.0)
	slice_stub = SliceStub.new()
	slice_stub.add_to_group("work_feedback_slice")
	scene.add_child(slice_stub)
	feedback = root.get_node("WorkFeedback")
	feedback.set_process(false)
	feedback._sync_scene()
	feedback.sound_started.connect(func(kind,position,variant): events.append([kind,position,variant]))
	await process_frame
	var original: Dictionary = wildlife.serialize_state()
	_expect(explorer.select_object(wildlife,rabbit),"paused rabbit selection succeeds")
	_expect(events.size() == 1 and events[0][0] == "rabbit_select","selection emits quiet feedback while paused")
	for i in range(12): explorer.select_object(wildlife,rabbit)
	for i in range(12): explorer._refresh_selected()
	_expect(events.size() == 1,"rapid clicks and inspector refreshes do not stack sounds")
	_expect(wildlife.serialize_state() == original,"selection audio never changes wildlife state or RNG")
	feedback._process(1)
	await _wait_real(.8)
	explorer.select_object(wildlife,rabbit)
	_expect(events.size() == 2 and events[0][2] != events[1][2],"cooldown expires in real time and immediate variants differ")
	feedback.clear_transients()
	events.clear()
	clock_node.set_paused(false)
	rabbit.hunger = .7
	rabbit.fatigue = 0
	rabbit.timer = 0
	wildlife.advance(.01,[])
	_expect(rabbit.activity == "Grazing" and events.is_empty(),"starting a graze waits for its first nibble")
	wildlife.advance(.4,[])
	_expect(events.is_empty(),"no premature grazing cue")
	wildlife.advance(.1,[])
	_expect(events.size() == 1 and events[0][0] == "rabbit_graze","meal progress triggers its first nibble")
	var voice: Dictionary = feedback._voices[0]
	var remaining: float = voice.remaining
	clock_node.set_paused(true)
	feedback._process(.3)
	wildlife.advance(3,[])
	_expect(voice.remaining == remaining and events.size() == 1,"pause freezes active grazing audio and its cue progress")
	clock_node.set_paused(false)
	feedback._process(.05)
	_expect(not voice.player.stream_paused and voice.remaining < remaining,"unpause resumes the same short nibble")
	feedback._process(1)
	await _wait_real(.22)
	wildlife.advance(2.7,[])
	_expect(events.size() == 2,"second phrase occurs during the same six-second meal")
	var saved: Dictionary = wildlife.serialize_state()
	wildlife.restore_state(saved)
	rabbit = wildlife.animals[0]
	feedback._process(0)
	_expect(voice.remaining == 0 and events.size() == 2,"restoring retires stale source playback and emits nothing")
	wildlife.advance(.05,[])
	_expect(events.size() == 2,"restore does not replay an already crossed cue")
	feedback.clear_transients()
	_expect(feedback.play_animal("rabbit_graze",rabbit),"visible active grazer can play")
	wildlife.advance(.01,[rabbit.position + Vector3(2,0,0)])
	feedback._process(.01)
	_expect(rabbit.activity == "Fleeing" and feedback._voices[0].remaining == 0,"flight immediately stops a nibble")
	rabbit.activity = "Sleeping"
	_expect(not feedback.play_animal("rabbit_graze",rabbit),"sleeping rabbit cannot make eating sounds")
	rabbit.activity = "Grazing"
	feedback.clear_transients()
	feedback.play_animal("rabbit_graze",rabbit)
	wildlife.apply_slice(20)
	feedback._process(.01)
	_expect(feedback._voices[0].remaining == 0 and not feedback.play_animal("rabbit_select",rabbit),"hidden source stops tails and rejects selection audio")
	wildlife.apply_slice(127)
	feedback.clear_transients()
	camera.set_meta("work_focus",rabbit.position+Vector3(30,0,0))
	_expect(not feedback.play_animal("rabbit_graze",rabbit),"distant grazing is silent")
	camera.set_meta("work_focus",rabbit.position)
	camera.set_meta("work_zoom",80.0)
	_expect(not feedback.play_animal("rabbit_graze",rabbit),"overview zoom suppresses grazing")
	camera.set_meta("work_zoom",12.0)
	# Skip both cues while away, then return: missed phrases must stay missed.
	rabbit.restore_state(original.rabbits[0])
	rabbit.hunger = .7
	rabbit.fatigue = 0
	rabbit.timer = 0
	camera.set_meta("work_focus",rabbit.position+Vector3(100,0,0))
	wildlife.advance(.01,[])
	wildlife.advance(3.3,[])
	var before := events.size()
	camera.set_meta("work_focus",rabbit.position)
	wildlife.advance(.05,[])
	_expect(events.size() == before,"returning to the camera never replays missed grazing")
	feedback.clear_transients()
	rabbit.timer = 6
	clock_node.set_speed(2)
	wildlife.advance(.25,[])
	_expect(events.size() == before+1,"2x speed advances nibble cadence")
	_expect(feedback._voices[0].player.pitch_scale > .96 and feedback._voices[0].player.pitch_scale < 1.04,"game speed does not raise audio pitch")
	clock_node.set_speed(1)
	feedback.clear_transients()
	var previous := -1
	for i in range(6):
		feedback._process(1)
		await _wait_real(.22)
		_expect(feedback.play_animal("rabbit_graze",rabbit),"variant playback accepted")
		_expect(events.back()[2] != previous,"grazing variants never immediately repeat")
		previous = events.back()[2]
	feedback.clear_transients()
	for i in range(3):
		var other = wildlife.add_rabbit("rabbit:audio:%d" % i,Vector3i(41+i,21,40),200+i)
		other.activity = "Grazing"
		var accepted: bool = feedback.play_animal("rabbit_graze",other)
		_expect(accepted == (i < 2),"grazing pool is capped at two voices")
		await _wait_real(.22)
	_expect(feedback._voices.size() <= 2,"rabbit feedback stays inside the shared voice budget")
	scene.free()
	current_scene = null
	_expect(feedback._voices.is_empty() and feedback._last_sound_msec.is_empty(),"scene exit clears sources, voices and click cooldowns")
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("RABBIT_AUDIO_OK")
	quit(0 if failures.is_empty() else 1)

func _wait_real(seconds: float) -> void:
	# SceneTree timers can include an expensive setup frame; cooldowns use wall
	# time, so wait against the same monotonic clock without altering production.
	var deadline := Time.get_ticks_msec() + ceili(seconds * 1000)
	while Time.get_ticks_msec() < deadline: await create_timer(.02).timeout
