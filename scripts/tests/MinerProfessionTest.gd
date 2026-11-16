extends "res://scripts/tests/MiningAnimationTest.gd"

const MINER := "base:profession:miner"
const WORKER := "base:profession:worker"
const PICK := "base:item:copper_pick"


func _run() -> void:
	create_timer(60).timeout.connect(func(): push_error("Miner test timed out"); quit(1))
	await _setup_mining_fixture()
	var assets := root.get_node("DwarfAssets")
	var block := Vector3i(42,22,40)
	worker.stats["base:stat:strength"] = 3   # Average, so the times below are the plain ones (doc 41 "Stats")
	var id: int = await _begin_block(block)
	var normal_time: float = worker._work_execution._swing_time
	_work_for(100)
	_expect(int(worker.profession_experience.get(MINER, 0)) == 0, "Worker mining does not earn specialist experience")
	_expect(not worker.change_profession("base:profession:brewer"), "a role the game does not have yet cannot be assigned via API")
	_expect(not worker.change_profession(MINER) and worker.profession == WORKER, "without a copper pick there is no Miner (doc 306)")
	_make_miner(worker)
	id = await _begin_block(block)
	_expect(is_equal_approx(worker._work_execution._swing_time, normal_time * .8), "a level-one Miner's copper pick takes a fifth off the digging time")
	_work_for(100)
	_expect(int(worker.profession_experience[MINER]) == 1, "final block of a zone earns exactly one experience")
	_work_for(100)
	_expect(int(worker.profession_experience[MINER]) == 1, "ended lease does not award again")
	for pair in [[9, 1], [10, 2], [99, 2], [100, 3], [500, 4], [2500, 5], [10000, 5]]:
		worker.profession_experience[MINER] = pair[0]
		_expect(assets.profession_level(MINER, worker.profession_experience) == pair[1], "cumulative experience thresholds and level five cap")
	worker.profession_experience[MINER] = 2500
	id = await _begin_block(block)
	_expect(is_equal_approx(worker._work_execution._swing_time, normal_time * .8 * .8), "a master Miner takes twenty percent off that again")
	worker._process(.1)
	worker.set_work_permission("mine", false)
	_expect(worker.current_task_id < 0 and not worker.is_walking(), "disabling active work releases its lease")
	_expect(int(worker.profession_experience[MINER]) == 2500 and world.get_block(block.x,block.y,block.z) != blocks.AIR_ID, "interruption grants neither terrain nor experience")
	for i in range(5): tasks._run_scheduler()
	_expect(worker.current_task_id < 0, "disabled mining cannot be reassigned")
	worker.stats["base:stat:strength"] = 5   # the resumed block starts a fresh swing with it
	worker.set_work_permission("mine", true)
	_expect(await _until_mining(), "reenabling mining resumes pending work")
	_expect(is_equal_approx(worker._work_execution._swing_time, normal_time * .8 * .8 / 1.12), "Excellent Strength swings 12% faster, on top of the pick and the Miner's levels (doc 41, Stats)")
	worker.stats["base:stat:strength"] = 3
	_make_worker(worker)
	_expect(await _until_mining(), "returning to Worker keeps mining available")
	_expect(is_equal_approx(worker._work_execution._swing_time, normal_time), "returning Worker has normal time despite retained Miner experience")
	_make_miner(worker)
	_expect(int(worker.profession_experience[MINER]) == 2500, "career switching preserves experience")
	mining._remove_zone(id)
	worker._begin_sleep()
	_make_worker(worker)
	_expect(worker.is_sleeping() and not worker.dwarf_id in tasks._idle_dwarves, "promotion never interrupts sleep or registers a sleeping worker")
	worker._wake_up()
	_make_miner(worker)
	worker.set_work_permission("haul", false)
	worker.set_work_permission("gather", false)
	_expect(not worker.allows_task(Task.Type.UPROOT_SHRUB) and worker.allows_task(Task.Type.FETCH_BUILD), "gather permission covers uprooting without blocking placement supplies")
	var state: Dictionary = worker.serialize_state()
	_expect(state.profession == MINER and state.profession_experience[MINER] == 2500 and state.work_permissions.haul == false, "save snapshot includes profession, experience and permissions")
	# A later idle Miner gets first refusal before an earlier generalist; the
	# same priority and reachability machinery still owns actual allocation.
	_make_worker(worker)
	var factory = load("res://scripts/entities/DwarfFactory.gd").new()
	var miner = factory.spawn(factory.generate(142, {}), 142)
	scene.add_child(miner)
	miner.position = worker.position
	miner.set_process(false)
	tasks.register_dwarf(miner)
	_make_miner(miner)
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
	if failures.is_empty(): print("MINER_PROFESSION_OK: copper pick, real commits, thresholds, timers, safe interruption, work permissions, retained experience, sleep, snapshots and scheduler preference")
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)


## A Miner with its copper pick in hand, as a finished promotion leaves one (ToolPromotionTest walks
## the real pickup).
func _make_miner(dwarf) -> void:
	dwarf._equipment.restore({"tool": PICK})
	dwarf._complete_profession_change(MINER)
	if not dwarf.is_sleeping(): tasks.notify_dwarf_idle(dwarf.dwarf_id)


## Back to Worker; the pick it sets down is taken out of the world, so the next Miner starts clean.
func _make_worker(dwarf) -> void:
	dwarf.change_profession(WORKER)
	var pick: Node3D = drops.nearest_loose_of_key(PICK, dwarf.current_cell())
	if pick != null:
		drops.take(pick)
		pick.free()
