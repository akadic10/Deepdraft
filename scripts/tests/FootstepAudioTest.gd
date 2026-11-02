extends "res://scripts/tests/HaulingAnimationTest.gd"

class StepSlice extends Node:
	var height := 127
	func get_slice_y() -> int: return height

var feedback
var sounds: Array = []
var slice := StepSlice.new()


func _run() -> void:
	create_timer(80).timeout.connect(func(): push_error("Footstep audio timeout"); quit(1))
	await _setup_fixture()
	tasks.reset_runtime_state()
	worker.abort_task()
	feedback = root.get_node("WorkFeedback")
	feedback.set_process(false)
	camera = Camera3D.new()
	scene.add_child(camera)
	camera.position = Vector3(42,35,55)
	camera.look_at(Vector3(42,21,40))
	camera.current = true
	camera.set_meta("work_focus",Vector3(42,21,40))
	camera.set_meta("work_zoom",18.0)
	slice.add_to_group("work_feedback_slice")
	scene.add_child(slice)
	feedback.sound_started.connect(func(kind,position,variant):
		if kind.begins_with("footstep_"): sounds.append([kind,position,variant]))
	for bank in ["stone","earth","grass","wood"]:
		var streams: Array = feedback._streams["footstep_"+bank]
		_expect(streams.size()>=4,"multiple recorded variants: "+bank)
		for stream: AudioStreamWAV in streams:
			_expect(stream.loop_mode==AudioStreamWAV.LOOP_DISABLED and stream.get_length()>.1 and stream.get_length()<.5,"short one-shot import: "+bank)

	# Drive a real route in fractions of a stride, including the wrap contact.
	worker.walk_nearby(Vector3i(52,20,39))
	var step_seconds: float = worker.stride_length/worker.walk_speed
	worker._follow_path(step_seconds*.49)
	_expect(sounds.is_empty(),"less than one stride has no landing sound")
	worker._follow_path(step_seconds*.49)
	_expect(sounds.is_empty(),"swing stays silent before ground contact")
	worker._follow_path(step_seconds*.03)
	_expect(sounds.size()==1 and sounds[0][0]=="footstep_stone","first foot landing emits stone step")
	feedback._process(1)
	worker._follow_path(step_seconds)
	_expect(sounds.size()==2,"other foot lands at cycle wrap")
	_expect(sounds[0][2]!=sounds[1][2],"successive steps avoid the same recording")
	feedback._process(1)
	worker._follow_path(step_seconds*3.1)
	_expect(sounds.size()==3,"stalled frame coalesces skipped footfalls")
	worker._rig.climbing = true
	worker._movement.walk_bob(worker.stride_length)
	_expect(sounds.size()==3,"climbing does not emit walking footsteps")
	worker._rig.climbing = false
	worker.stop_walking()
	worker._movement.walk_bob(worker.stride_length)
	_expect(sounds.size()==3,"stationary posing cannot create footsteps")

	# Reaching a waypoint still counts the travelled distance before resetting.
	worker.position = Vector3(40.5,21,39.5)
	worker.walk_nearby(Vector3i(41,20,39))
	worker._movement.walk_cycle = .45
	feedback.clear_transients()
	sounds.clear()
	worker._follow_path(1)
	_expect(sounds.size()==1 and not worker.is_walking(),"arrival includes the final landing without replay")
	worker._process(.001)
	_expect(sounds.size()==1,"arrival and idle do not replay the landing")

	worker.position = Vector3(40.5,21,39.5)
	worker.walk_nearby(Vector3i(52,20,39))
	var cell: Vector3i = worker.current_cell()
	var surfaces := {"stone":"base:terrain:rock:rock01","wood":"base:construction:log:oak:x","earth":"base:terrain:surface:dirt","grass":"base:terrain:surface:grass"}
	for surface: String in surfaces:
		feedback.clear_transients()
		sounds.clear()
		world.set_block(cell.x,cell.y,cell.z,blocks.get_id(surfaces[surface]))
		_expect(feedback.play_footstep(worker),"eligible walker plays on "+surface)
		_expect(sounds.size()==1 and sounds[0][0]=="footstep_"+surface,"actual floor selects "+surface)

	feedback.clear_transients()
	for surface in ["stone","wood","earth"]:
		world.set_block(cell.x,cell.y,cell.z,blocks.get_id(surfaces[surface]))
		_expect(feedback.play_footstep(worker),"mixed-surface voice admitted")
	world.set_block(cell.x,cell.y,cell.z,blocks.get_id(surfaces.grass))
	_expect(not feedback.play_footstep(worker) and feedback._voices.size()==3,"all surfaces share three voices")
	_expect(feedback.play_chop(worker.position,cell.y),"footstep cap leaves capacity for work sounds")
	feedback.clear_transients()
	_expect(feedback.play_footstep(worker),"start tail for pause check")
	var voice: Dictionary = feedback._voices[0]
	var remaining: float = voice.remaining
	clock_node.set_paused(true)
	feedback._process(1)
	_expect(not feedback.play_footstep(worker) and voice.remaining==remaining,"pause freezes tails and starts no step")
	clock_node.set_paused(false)
	clock_node.set_speed(3)
	feedback._process(.01)
	_expect(absf(voice.player.pitch_scale-1)<.04,"simulation speed never raises recording pitch")
	clock_node.set_speed(1)
	feedback.clear_transients()
	for label in ["hidden","slice","far","overview","loading","no_camera","air","zero_speed"]:
		worker.visible = label!="hidden"
		slice.height = 19 if label=="slice" else 127
		camera.set_meta("work_focus",Vector3(140,21,140) if label=="far" else Vector3(42,21,40))
		camera.set_meta("work_zoom",100.0 if label=="overview" else 18.0)
		root.get_node("SaveManager")._loading = label=="loading"
		if label=="no_camera": camera.clear_current()
		else: camera.make_current()
		world.set_block(cell.x,cell.y,cell.z,blocks.AIR_ID if label=="air" else blocks.get_id(surfaces.stone))
		clock_node.set_speed(0 if label=="zero_speed" else 1)
		_expect(not feedback.play_footstep(worker),"silent source: "+label)
	root.get_node("SaveManager")._loading = false
	clock_node.set_speed(1)
	feedback.clear_transients()
	_expect(feedback.play_footstep(worker),"restored listener plays a fresh step")
	worker.hide()
	feedback._process(.001)
	_expect(feedback._voices[0].remaining==0,"hidden source cuts its active tail")
	worker.show()
	feedback.play_footstep(worker)
	worker.free()
	feedback._process(.001)
	_expect(feedback._voices.all(func(v): return v.remaining==0),"deleted walker leaves no sound")
	feedback.clear_transients()
	for failure in failures: push_error(failure)
	print("FOOTSTEP_AUDIO_OK" if failures.is_empty() else "FOOTSTEP_AUDIO_FAIL")
	quit(0 if failures.is_empty() else 1)
