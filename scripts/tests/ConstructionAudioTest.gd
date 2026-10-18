extends "res://scripts/tests/ConstructionTest.gd"

class HammerSliceStub extends Node:
	var height := 127
	func get_slice_y() -> int: return height

var feedback
var sound_events: Array = []

func _step(delta: float) -> void:
	feedback._process(delta)
	worker._process(delta)

func _run() -> void:
	create_timer(80).timeout.connect(func(): push_error("Construction audio timeout"); quit(1))
	await _setup_fixture()
	await _new_trip(STONE,2)
	stockpiles.reset_runtime_state()
	stockpiles._process(0)
	nav = root.get_node("NavGrid")
	root.get_node("WorldGenerator")._cache_block_ids()
	mine = load("res://scripts/systems/MiningDesignationController.gd").new()
	scene.add_child(mine)
	mine.set_process(false)
	construction = load("res://scripts/systems/ConstructionController.gd").new()
	construction.mining = mine
	scene.add_child(construction)
	construction.set_process(false)
	_terrain_before = world.terrain_overrides()
	camera = Camera3D.new()
	scene.add_child(camera)
	camera.position = Vector3(44,35,55)
	camera.look_at(Vector3(44,21,40))
	camera.current = true
	camera.set_meta("work_focus",Vector3(44,21,40))
	camera.set_meta("work_zoom",24.0)
	var slice := HammerSliceStub.new()
	slice.add_to_group("work_feedback_slice")
	scene.add_child(slice)
	feedback = root.get_node("WorkFeedback")
	feedback.set_process(false)
	feedback._sync_scene()
	feedback.sound_started.connect(func(kind,position,variant): sound_events.append([kind,position,variant]))
	var id: int = construction.create_order(_cells([Vector3i(44,21,40)]))
	var order = construction.orders[id]
	# Longer fixture work exercises wrap, skipped cycles and a fractional ending.
	order.def = order.def.duplicate()
	order.def.work_seconds = 8.2
	_expect(await _wait_phase(worker.TaskPhase.FETCH_WORKING),"real supplied construction reaches hammer work")
	_expect(sound_events.is_empty(),"deliveries and beginning work stay quiet")
	_step(.70)
	_expect(sound_events.is_empty(),"wind-up stays quiet")
	_step(.03)
	_expect(sound_events.size()==1 and sound_events[0][0]=="hammer","head contact plays hammer impact")
	if not sound_events.is_empty():
		var actual: Vector3 = worker._construction_pose.tool.global_transform*worker.ConstructionPose.MODEL_POINT
		_expect(actual.distance_to(sound_events[0][1])<.001,"sound originates at the striking face")
	_step(.02)
	_expect(sound_events.size()==1,"contact hold does not retrigger")
	clock_node.set_paused(true)
	_step(2)
	_expect(sound_events.size()==1 and is_equal_approx(order.progress,.75),"pause freezes strikes and work")
	clock_node.set_paused(false)
	clock_node.set_speed(3)
	_step(.30)
	_expect(sound_events.size()==1,"accelerated wind-up still waits for contact")
	_step(.03)
	_expect(sound_events.size()==2,"3x changes the strike cadence")
	_expect(absf(feedback._voices.back().player.pitch_scale-1)<.04,"game speed never pitch-shifts hammer audio")
	clock_node.set_speed(1)
	_step(2.2)
	_expect(sound_events.size()==3,"stalled frames coalesce skipped contacts")
	slice.height = 19
	_step(1)
	_expect(sound_events.size()==3,"slice-hidden work stays quiet")
	slice.height = 127
	worker.hide()
	_step(1)
	worker.show()
	_expect(sound_events.size()==3,"hidden dwarf stays quiet")
	camera.set_meta("work_focus",Vector3(140,21,140))
	_step(1)
	_expect(sound_events.size()==3,"distant work stays quiet")
	camera.set_meta("work_focus",Vector3(44,21,40))
	worker.dev_force_interrupt()
	_expect(await _wait_phase(worker.TaskPhase.FETCH_WORKING),"partial work resumes")
	_step(.01)
	_expect(sound_events.size()==3,"resume never replays a previous impact")
	_step(.78)
	_expect(sound_events.size()==4,"next genuine strike after resume is audible")
	_step(5)
	_expect(sound_events.size()==4 and _completed_cells().has(Vector3i(44,21,40)),"completion clamps progress before nonexistent later strikes")
	id = construction.create_order(_cells([Vector3i(46,21,40)]))
	_expect(await _wait_phase(worker.TaskPhase.FETCH_WORKING),"second project starts")
	_step(.2)
	construction.cancel_order(id)
	_step(2)
	_expect(sound_events.size()==4,"cancellation before contact stays quiet")
	feedback.clear_transients()
	for failure in failures: push_error(failure)
	print("CONSTRUCTION_AUDIO_OK" if failures.is_empty() else "CONSTRUCTION_AUDIO_FAIL")
	quit(0 if failures.is_empty() else 1)
