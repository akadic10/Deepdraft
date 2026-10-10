extends "res://scripts/tests/MiningAnimationTest.gd"

const MINER := "base:profession:miner"
const WORKER := "base:profession:worker"


func _run() -> void:
	create_timer(60).timeout.connect(func(): push_error("Miner test timed out"); quit(1))
	await _setup_mining_fixture()
	var assets := root.get_node("DwarfAssets")
	var block := Vector3i(42,22,40)
	var id: int = await _begin_block(block)
	var normal_time: float = worker._swing_time
	worker._process(100)
	_expect(int(worker.profession_experience.get(MINER, 0)) == 0, "Worker mining does not earn specialist experience")
	_expect(not worker.change_profession("base:profession:farmer"), "planned role cannot be assigned via API")
	_expect(worker.change_profession(MINER), "Worker can become Miner without a tool or level")
	id = await _begin_block(block)
	_expect(is_equal_approx(worker._swing_time, normal_time), "level one and Worker have equal digging times")
	worker._process(100)
	_expect(int(worker.profession_experience[MINER]) == 1, "final block of a zone earns exactly one experience")
	worker._process(100)
	_expect(int(worker.profession_experience[MINER]) == 1, "ended lease does not award again")
	for pair in [[9, 1], [10, 2], [99, 2], [100, 3], [500, 4], [2500, 5], [10000, 5]]:
		worker.profession_experience[MINER] = pair[0]
		_expect(assets.profession_level(MINER, worker.profession_experience) == pair[1], "cumulative experience thresholds and level five cap")
	worker.profession_experience[MINER] = 2500
	id = await _begin_block(block)
	_expect(is_equal_approx(worker._swing_time, normal_time * .8), "master Miner uses twenty percent less digging time")
	worker._process(.1)
	worker.set_work_permission("mine", false)
	_expect(worker.current_task_id < 0 and not worker.is_walking(), "disabling active work releases its lease")
	_expect(int(worker.profession_experience[MINER]) == 2500 and world.get_block(block.x,block.y,block.z) != blocks.AIR_ID, "interruption grants neither terrain nor experience")
	for i in range(5): tasks._run_scheduler()
	_expect(worker.current_task_id < 0, "disabled mining cannot be reassigned")
	worker.set_work_permission("mine", true)
	_expect(await _until_mining(), "reenabling mining resumes pending work")
	worker.change_profession(WORKER)
	_expect(await _until_mining(), "returning to Worker keeps mining available")
	_expect(is_equal_approx(worker._swing_time, normal_time), "returning Worker has normal time despite retained Miner experience")
	worker.change_profession(MINER)
	_expect(int(worker.profession_experience[MINER]) == 2500, "career switching preserves experience")
	mining._remove_zone(id)
	worker._begin_sleep()
	worker.change_profession(WORKER)
	_expect(worker.is_sleeping() and not worker.dwarf_id in tasks._idle_dwarves, "promotion never interrupts sleep or registers a sleeping worker")
	worker._wake_up()
	worker.change_profession(MINER)
	worker.set_work_permission("haul", false)
	worker.set_work_permission("gather", false)
	_expect(not worker.allows_task(Task.Type.UPROOT_SHRUB) and worker.allows_task(Task.Type.FETCH_BUILD), "gather permission covers uprooting without blocking placement supplies")
	var state: Dictionary = worker.serialize_state()
	_expect(state.profession == MINER and state.profession_experience[MINER] == 2500 and state.work_permissions.haul == false, "save snapshot includes profession, experience and permissions")
	# A later idle Miner gets first refusal before an earlier generalist; the
	# same priority and reachability machinery still owns actual allocation.
	worker.change_profession(WORKER)
	var factory = load("res://scripts/entities/DwarfFactory.gd").new()
	var miner = factory.spawn(factory.generate(142, {}), 142)
	scene.add_child(miner)
	miner.position = worker.position
	miner.set_process(false)
	tasks.register_dwarf(miner)
	miner.change_profession(MINER)
	world.set_block(block.x,block.y,block.z,blocks.get_id("base:terrain:rock:rock01"))
	var selected: Array[Vector3i] = [block]
	var zone: int = mining._create_zone(selected)
	for i in range(120):
		tasks._run_scheduler()
		if miner.current_task_id >= 0: break
		await process_frame
	_expect(miner.current_task_id >= 0, "later idle Miner is offered mining before the generalist")
	mining._remove_zone(zone)
	# Preferred does not mean mandatory: isolate the Miner on another ledge.
	for x in range(78, 83):
		for z in range(78, 83):
			for y in range(18, 26): world.set_block(x,y,z,blocks.AIR_ID)
	world.set_block(80,20,80,blocks.get_id("base:terrain:rock:rock01"))
	miner.position = Vector3(80.5,21,80.5)
	tasks._max_probes_per_wake = 1
	zone = mining._create_zone(selected)
	for i in range(120):
		tasks._run_scheduler()
		if worker.current_task_id >= 0: break
		await process_frame
	_expect(worker.current_task_id >= 0 and miner.current_task_id < 0, "unreachable preferred Miner yields to reachable Worker across capped wakes")
	mining._remove_zone(zone)
	# An explicitly higher-priority bucket must still win over profession focus.
	var previous: int = tasks._static_priorities.BUILD
	tasks._static_priorities.BUILD = 70
	tasks.notify_dwarf_unavailable(worker.dwarf_id)
	var build_id: int = tasks.add_task(Task.Type.BUILD, miner.current_cell())
	zone = mining._create_zone(selected)
	for i in range(120):
		tasks._run_scheduler()
		if miner.current_task_id >= 0: break
		await process_frame
	_expect(miner.current_task_id == build_id, "higher priority work outranks mining focus")
	tasks._static_priorities.BUILD = previous
	if failures.is_empty(): print("MINER_PROFESSION_OK: real commits, thresholds, timers, safe interruption, work permissions, retained experience, sleep, snapshots and scheduler preference")
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
