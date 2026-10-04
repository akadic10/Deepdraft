extends "res://scripts/tests/MiningAnimationTest.gd"

class SliceStub extends Node:
	var height := 127
	func get_slice_y() -> int:
		return height

var feedback
var sound_events: Array = []
var burst_events: Array = []
var slice_stub: Node


func _setup_mining_feedback() -> void:
	await _setup_mining_fixture()
	camera = Camera3D.new()
	scene.add_child(camera)
	camera.position = Vector3(35,30,46)
	camera.look_at(Vector3(42,22,40))
	camera.current = true
	camera.set_meta("work_focus",Vector3(42,21,40))
	camera.set_meta("work_zoom",24.0)
	slice_stub = SliceStub.new()
	slice_stub.add_to_group("work_feedback_slice")
	scene.add_child(slice_stub)
	feedback = root.get_node("WorkFeedback")
	feedback._sync_scene()
	feedback.sound_started.connect(func(kind,position,variant): sound_events.append([kind,position,variant]))
	feedback.burst_started.connect(func(position,stage): burst_events.append([position,stage]))


func _run() -> void:
	create_timer(45).timeout.connect(func(): push_error("Mining feedback test timed out"); quit(1))
	await _setup_mining_feedback()
	var block := Vector3i(42,22,40)
	# This wall faces a mined-open tunnel, so its actual material is visible.
	mining._mined_blocks[Vector3i(41,22,40)] = true
	var id: int = await _begin_block(block)
	var swing: float = worker._swing_time
	var elapsed: float = swing-worker._swing_timer
	worker._process(swing*.91-elapsed)
	_expect(sound_events.is_empty() and burst_events.is_empty(),"wind-up emits no feedback")
	worker._process(swing*.02)
	_expect(sound_events.size() == 1 and sound_events[0][0] == "mining_stone","stone contact emits once")
	_expect(burst_events.size() == 1 and burst_events[0][1] == "mining_impact","chips coincide with contact")
	_expect(sound_events[0][1].distance_to(worker.to_global(worker._mine_contact)) < .001,"sound originates at pick point")
	var chip = feedback._bursts.back()
	_expect(chip._particles.size() == 6,"small contact chip count")
	var chip_age: float = chip.age
	clock_node.set_paused(true)
	worker._process(10)
	feedback._process(.1)
	_expect(sound_events.size() == 1 and chip.age == chip_age,"pause freezes work and particles")
	clock_node.set_paused(false)
	worker._process(swing*.02)
	_expect(sound_events.size() == 1,"contact hold is silent")
	feedback._process(.5)
	worker._process(swing)
	_expect(sound_events.size() == 2,"cycle wrap emits one new strike")
	feedback._process(.5)
	worker._process(swing*1.2)
	_expect(sound_events.size() == 3,"long update coalesces crossed strikes")
	# Resume starts a fresh wind-up. Pitch remains natural at faster speed.
	id = await _begin_block(block)
	worker.dev_force_interrupt()
	_expect(await _until_mining(),"interrupted mining resumes")
	feedback._process(.5)
	clock_node.set_speed(3)
	elapsed = swing-worker._swing_timer
	worker._process((swing*.93-elapsed)/3)
	_expect(sound_events.size() == 4,"3x contact emits once")
	_expect(feedback._voices[0].player.pitch_scale > .96 and feedback._voices[0].player.pitch_scale < 1.04,"3x speed does not raise pitch")
	clock_node.set_speed(1)
	worker.dev_force_interrupt()
	_expect(await _until_mining(),"second resume")
	slice_stub.height = 21
	worker._process(swing*.95)
	_expect(sound_events.size() == 4,"target above slice emits no feedback even with visible dwarf")
	slice_stub.height = 127
	worker._process(swing*.02)
	_expect(sound_events.size() == 4,"revealing target never replays missed strike")
	mining._remove_zone(id)
	worker._process(5)
	_expect(sound_events.size() == 4 and world.get_block(block.x,block.y,block.z) != blocks.AIR_ID,"cancel neither strikes nor removes block")
	id = await _begin_block(block)
	camera.set_meta("work_focus",Vector3(200,21,200))
	var before: int = burst_events.size()
	worker._process(100)
	_expect(sound_events.size() == 4 and burst_events.size() == before,"distant mining completes silently without effect backlog")
	_expect(world.get_block(block.x,block.y,block.z) == blocks.AIR_ID,"camera distance does not stop real work")
	camera.set_meta("work_focus",Vector3(42,21,40))
	feedback._process(.5)
	_expect(sound_events.size() == 4,"camera return does not replay")
	# Real soil job completes once, retaining its normal drops.
	id = await _begin_block(block,"base:terrain:soil:cave")
	sound_events.clear()
	burst_events.clear()
	worker._process(100)
	_expect(sound_events.size() == 1 and sound_events[0][0] == "mining_soil","soil has softer bank, one event even across all swings")
	_expect(burst_events.size() == 2 and burst_events[1][1] == "mining_completion","successful removal emits exactly one completion puff")
	_expect(world.get_block(block.x,block.y,block.z) == blocks.AIR_ID,"feedback preserves removal")
	var dust = feedback._bursts.back()
	for particle in dust._particles:
		var color: Color = particle.color
		_expect(color.r > color.b,"soil puff stays earthy")
	_expect(dust.lifetime < .6 and dust._particles.size() == 23,"completion puff is brief and bounded")
	# Hidden resources use host strata until the struck face is mined open.
	feedback.clear_transients()
	world.set_block(block.x,block.y,block.z,blocks.get_id("base:terrain:ore:gold"))
	mining._mined_blocks.erase(Vector3i(41,22,40))
	var point := Vector3(42.025,22.4,40.5)
	mining.play_zone_mining_impact(block,point,Vector3.LEFT)
	var strata: int = root.get_node("WorldGenerator").get_overview_strata_block_id(block.x,block.y,block.z)
	if not blocks.is_solid(strata): strata = blocks.get_id(feedback.config.mining.fallback_block)
	var host_color: Color = blocks.get_color(strata,clock_node.season)
	for particle in feedback._bursts.back()._particles:
		_expect(particle.color.is_equal_approx(host_color) or particle.color.is_equal_approx(host_color.darkened(.18)),"hidden ore chips match visible host strata")
	feedback.clear_transients()
	mining._mined_blocks[Vector3i(41,22,40)] = true
	mining.play_zone_mining_impact(block,point,Vector3.LEFT)
	var gold: Color = blocks.get_color(blocks.get_id("base:terrain:ore:gold"),clock_node.season)
	for particle in feedback._bursts.back()._particles:
		_expect(particle.color.is_equal_approx(gold) or particle.color.is_equal_approx(gold.darkened(.18)),"revealed ore chips match exposed resource")
	# Generic world edits/restoration must never imitate a successful strike.
	before = burst_events.size()
	mining._mine_block_world(block)
	_expect(burst_events.size() == before,"generic world removal is silent")
	for i in range(40):
		feedback.mining_impact(point,block,blocks.get_id("base:terrain:rock:rock01"),Vector3.LEFT)
	_expect(feedback._voices.size() <= 8 and feedback._bursts.size() <= 12,"many workers share bounded audio/effects")
	feedback._process(1)
	_expect(feedback._bursts.is_empty(),"all chip and completion effects expire")
	feedback.block_mined(block,blocks.get_id("base:terrain:soil:cave"))
	scene.free()
	_expect(feedback._bursts.is_empty() and feedback._voices.is_empty(),"scene exit clears transient feedback")
	for failure in failures: push_error(failure)
	if failures.is_empty():
		print("MINING_FEEDBACK_OK: contact timing, wrap/stall, pause/speed, slice/camera/cancel, soil/stone, concealment, completion, pool bounds and cleanup")
	quit(0 if failures.is_empty() else 1)
