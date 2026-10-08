extends "res://scripts/tests/WorkerCraftingTest.gd"

## Contact timing uses real crafting jobs. --record additionally captures only
## the game's Work bus through the native mixer, with no microphone input.
class CraftSliceStub extends Node:
	var height := 127
	func get_slice_y() -> int: return height

var feedback
var sound_events: Array = []
var slice_stub
const AUDIO_OUT := "res://tmp/worker_crafting_review/audio"

func _run() -> void:
	create_timer(80).timeout.connect(func(): push_error("Crafting audio test timed out"); quit(1))
	await _setup_crafting_fixture()
	feedback = root.get_node("WorkFeedback")
	feedback.set_process(false)
	feedback._sync_scene()
	feedback.sound_started.connect(func(kind,position,variant): sound_events.append([kind,position,variant]))
	camera.set_meta("work_focus",Vector3(42,21,41))
	camera.set_meta("work_zoom",24.0)
	slice_stub = CraftSliceStub.new()
	slice_stub.add_to_group("work_feedback_slice")
	scene.add_child(slice_stub)
	drops.spawn_drop(PINE,5,Vector3i(40,21,41))
	var id: int = crafting.queue_order(BENCH_RECIPE,1)
	_expect(await _phase(worker.TaskPhase.FETCH_WORKING),"bench fixture reaches real crafting")
	_step(.60)
	_expect(sound_events.is_empty(),"bench wind-up stays quiet")
	_step(.03)
	_expect(sound_events.size()==1 and sound_events[0][0]=="chop","bench axe contact plays wood impact")
	_check_contact()
	_step(.02)
	_expect(sound_events.size()==1,"contact hold does not retrigger")
	clock_node.set_paused(true)
	_step(2)
	_expect(sound_events.size()==1,"paused crafting starts no sounds")
	clock_node.set_paused(false)
	_step(.50)
	clock_node.set_speed(3)
	_step(.20)
	_expect(sound_events.size()==1,"faster wind-up still waits for contact")
	_step(.01)
	_expect(sound_events.size()==2,"3x speed changes strike cadence")
	_expect(feedback._voices.back().player.pitch_scale>.96 and feedback._voices.back().player.pitch_scale<1.04,"speed does not pitch-shift the axe sample")
	clock_node.set_speed(1)
	_step(2.4)
	_expect(sound_events.size()==3,"stalled frame coalesces skipped contacts into one hit")
	slice_stub.height = 19
	_step(1.15)
	_expect(sound_events.size()==3,"slice-hidden crafting stays quiet")
	slice_stub.height = 127
	_step(.01)
	_expect(sound_events.size()==3,"slice reveal never replays missed hits")
	worker.hide()
	_step(1.15)
	worker.show()
	_expect(sound_events.size()==3,"hidden Worker starts no impact")
	camera.set_meta("work_focus",Vector3(140,21,140))
	_step(1.15)
	_expect(sound_events.size()==3,"distant crafting stays quiet")
	camera.set_meta("work_focus",Vector3(42,21,41))
	_step(5)
	_expect(sound_events.size()==3,"completion clamps overshoot before any nonexistent strike")
	_expect(await _completed(id),"bench still completes normally")
	_expect(sound_events.size()==3,"set-down and idle do not play chopping sounds")
	furniture.activate_for(BENCH,true)
	furniture._hover_cell = Vector3i(45,20,42)
	furniture._confirm_ghost()
	furniture.deactivate()
	_expect(await _installed(BENCH),"finished bench installs")
	id = crafting.queue_order(TORCH_RECIPE,1)
	_expect(await _phase(worker.TaskPhase.FETCH_WORKING),"torch fixture reaches placed bench")
	sound_events.clear()
	feedback.clear_transients()
	_step(.60)
	_expect(sound_events.is_empty(),"torch wind-up stays quiet")
	_step(.03)
	_expect(sound_events.size()==1,"torch contact uses same wood impact")
	_check_contact()
	crafting.set_paused(id,true)
	_step(2)
	_expect(sound_events.size()==1,"pausing the order prevents further strikes")
	crafting.set_paused(id,false)
	_expect(await _phase(worker.TaskPhase.FETCH_WORKING),"paused work resumes")
	_step(.01)
	_expect(sound_events.size()==1,"resume after contact does not replay it")
	crafting.remove_order(id)
	id = crafting.queue_order(TORCH_RECIPE,1)
	_expect(await _phase(worker.TaskPhase.FETCH_WORKING),"next torch order begins")
	_step(.2)
	crafting.remove_order(id)
	_step(1)
	_expect(sound_events.size()==1,"cancellation before contact remains silent")
	if "--record" in OS.get_cmdline_user_args():
		await _record_recipe(BENCH_RECIPE,"crude_workbench")
		await _record_recipe(TORCH_RECIPE,"wooden_torch")
	feedback.clear_transients()
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("CRAFTING_AUDIO_OK: both recipes, actual contacts, hold/wrap/stall, pause/speed, cancellation/resume, slice/distance, completion clamp and sound position")
	quit(0 if failures.is_empty() else 1)

func _step(delta: float) -> void:
	feedback._process(delta)
	worker._process(delta)

func _check_contact() -> void:
	if sound_events.is_empty(): return
	var item: Node3D = worker._fetch_item
	var bounds: AABB = worker._carry_pose.item_bounds(item)
	var expected := item.global_position+Vector3.UP*bounds.end.y
	_expect(sound_events.back()[1].is_equal_approx(expected),"sound originates at the axe contact on the log")

func _record_recipe(recipe: String, label: String) -> void:
	feedback.clear_transients()
	var id: int = crafting.queue_order(recipe,1)
	_expect(await _phase(worker.TaskPhase.FETCH_WORKING),"recording reaches "+label)
	var recorder := AudioEffectRecord.new()
	recorder.format = AudioStreamWAV.FORMAT_16_BITS
	var bus := AudioServer.get_bus_index("Work")
	var effect_index := AudioServer.get_bus_effect_count(bus)
	AudioServer.add_bus_effect(bus,recorder)
	recorder.set_recording_active(true)
	for i in range(100):
		_step(.02)
		await create_timer(.02).timeout
	recorder.set_recording_active(false)
	var wav := recorder.get_recording()
	var peak := 0.0
	for i in range(wav.data.size()/2): peak = maxf(peak,absf(float(wav.data.decode_s16(i*2))/32768.0))
	_expect(peak>.01 and peak<.95,"native "+label+" produces audible unclipped PCM")
	DirAccess.make_dir_recursive_absolute(AUDIO_OUT)
	wav.save_to_wav(AUDIO_OUT+"/"+label+".wav")
	print("CRAFTING_AUDIO_PCM: ",label," peak=",peak)
	AudioServer.remove_bus_effect(bus,effect_index)
	crafting.remove_order(id)
