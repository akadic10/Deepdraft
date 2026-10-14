extends "res://scripts/tests/MiningAnimationTest.gd"

const BED := "base:furniture:log_bed"
const STAND := Vector3i(41,20,40)

func _frames(count: int) -> void:
	for i in count: await process_frame

func _run() -> void:
	create_timer(60).timeout.connect(func(): push_error("Mining furniture access timed out"); quit(1))
	await _setup_mining_fixture()
	furniture = load("res://scripts/systems/FurniturePlacementController.gd").new()
	scene.add_child(furniture)
	furniture.set_process(false)
	var nav = root.get_node("NavGrid")
	var stone: int = blocks.get_id("base:terrain:rock:rock01")
	# A tall wall leaves only the room-side floor within mining reach.
	for x in range(42,46):
		for z in range(35,46):
			for y in range(21,30): world.set_block(x,y,z,stone)
	var bed_id: int = furniture._next_installed_id
	furniture._install(BED,furniture.get_defs()[BED],Vector3i(38,20,39),0)
	worker.position = Vector3(37.5,21,40.5)
	await _frames(3) # Drain terrain notifications before testing furniture alone.
	var selected: Array[Vector3i] = [Vector3i(42,24,40),Vector3i(42,24,41)]
	var zone_id: int = mining._create_zone(selected)
	var source = mining._zones[zone_id].component
	_expect(not nav.is_walkable(STAND) and source.destination_count()==0,"bed blocks both mining faces")
	for i in 3:
		for task_id in source.lease_ids:
			tasks.get_task(task_id).retry_at = 0
		tasks._run_scheduler()
	_expect(worker.current_task_id<0 and source.destination_count()==0,"three retries cannot mine through a bed")
	var distant: Array[Vector3i] = [Vector3i(100,20,100)]
	var distant_id: int = mining._create_zone(distant)
	var distant_source = mining._zones[distant_id].component
	var distant_task = tasks.get_task(distant_source.lease_ids.keys()[0])
	distant_task.retry_at = Time.get_ticks_msec()+60000
	distant_task.recovery_paused = true
	var distant_retry: int = distant_task.retry_at
	# Also cover the attention state: a real access change should re-arm it.
	for task_id in source.lease_ids:
		var task = tasks.get_task(task_id)
		task.recovery_paused = true
		task.retry_at = Time.get_ticks_msec()+60000
	# Same-frame occupancy events must observe the final arrangement.
	furniture._teardown_installed(bed_id,false)
	bed_id = furniture._next_installed_id
	furniture._install(BED,furniture.get_defs()[BED],Vector3i(33,20,45),1)
	await _frames(3)
	_expect(nav.is_walkable(STAND),"moving bed clears navigation without changing terrain")
	_expect(source.destination_count()==2,"moving bed refreshes cached zero mining faces")
	for task_id in source.lease_ids:
		var task = tasks.get_task(task_id)
		_expect(not task.recovery_paused and task.retry_at==0 and task.planning_context.is_empty(),"access change clears stale route and retry state")
	_expect(distant_task.retry_at==distant_retry and distant_task.recovery_paused,"local furniture move does not restart a distant order")
	mining._remove_zone(distant_id)
	# A second obstruction in the same time window must also refresh faces.
	bed_id = furniture._next_installed_id
	furniture._install(BED,furniture.get_defs()[BED],Vector3i(38,20,39),0)
	await _frames(2)
	_expect(source.destination_count()==0,"new furniture removes previously available mining faces")
	furniture._teardown_installed(bed_id,false)
	await _frames(2)
	_expect(source.destination_count()==2,"rapid removal is not lost to terrain refresh throttling")
	for i in 800:
		tasks._process(.04)
		worker._process(.04)
		if not mining._zones.has(zone_id): break
		await process_frame
	_expect(not mining._zones.has(zone_id),"original zone finishes both remaining blocks without redesignation")
	_expect(world.get_block(42,24,40)==blocks.AIR_ID and world.get_block(42,24,41)==blocks.AIR_ID,"worker actually removes both selected blocks")
	_expect(tasks.lifecycle_errors().is_empty(),"mining retains valid work ownership")
	for failure in failures: push_error(failure)
	print("MINING_FURNITURE_ACCESS_OK" if failures.is_empty() else "MINING_FURNITURE_ACCESS_FAIL")
	quit(0 if failures.is_empty() else 1)
