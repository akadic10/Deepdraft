extends "res://scripts/tests/WorkerCraftingTest.gd"

const CAMP := "base:furniture:campfire"
const CAMP_ITEM := "base:resources:furniture:campfire"

func _run() -> void:
	create_timer(60).timeout.connect(func(): push_error("Furniture assignment timed out"); quit(1))
	await _setup_crafting_fixture()
	tasks._max_probes_per_wake = 1 # Failed pairs must survive between wakes.
	var factory = load("res://scripts/entities/DwarfFactory.gd").new()
	extra_worker = factory.spawn(factory.generate(142, {}),142)
	scene.add_child(extra_worker)
	extra_worker.position = Vector3(45.5,21,40.5)
	extra_worker.set_process(false)
	extra_worker.sleep = 1.0
	tasks.register_dwarf(extra_worker)
	# The first idle dwarf is on an isolated patch, while the next dwarf can
	# reach both the packed fire and the installation site.
	var rock: int = blocks.get_id("base:terrain:rock:rock01")
	for offset in [Vector3i.LEFT,Vector3i.RIGHT,Vector3i.FORWARD,Vector3i.BACK]:
		for y in range(21,25):
			var cell: Vector3i = worker.current_cell()+offset
			world.set_block(cell.x,y,cell.z,rock)
	await _frames(2)
	drops.restore_loose_item(CAMP_ITEM,Vector3(46.5,21,40.5),0,1)
	furniture.activate_for(CAMP,true)
	furniture._hover_cell = Vector3i(49,20,40)
	furniture._confirm_ghost()
	furniture.deactivate()
	var ghost = furniture._ghosts.values()[0]
	var lease: int = ghost._lease_id
	for i in range(80):
		tasks._run_scheduler()
		if extra_worker.current_task_id == lease or tasks.get_task(lease).blocked_count > 0: break
		await process_frame
	_expect(extra_worker.current_task_id == lease and worker.current_task_id < 0,
		"reachable idle dwarf installs when the first idle dwarf is isolated")
	_expect(tasks.get_task(lease).blocked_count == 0,"one worker's failed route must not back off the whole furniture order")
	if extra_worker.current_task_id == lease:
		_expect(await _installed(CAMP),"reachable worker collects and installs the actual packed campfire")
		_expect(_count(CAMP_ITEM)==0 and extra_worker._carried_entries.is_empty(),"installation consumes one item without leaving cargo")
		await _all_workers_blocked()
	for failure: String in failures: push_error(failure)
	print("FURNITURE_ASSIGNMENT_OK" if failures.is_empty() else "FURNITURE_ASSIGNMENT_FAIL")
	quit(0 if failures.is_empty() else 1)


func _all_workers_blocked() -> void:
	extra_worker.stop_walking()
	extra_worker._idle_behavior.cancel()
	extra_worker.position = Vector3(45.5,21,40.5)
	var rock: int = blocks.get_id("base:terrain:rock:rock01")
	for offset in [Vector3i.LEFT,Vector3i.RIGHT,Vector3i.FORWARD,Vector3i.BACK]:
		for y in range(21,25):
			var cell: Vector3i = extra_worker.current_cell()+offset
			world.set_block(cell.x,y,cell.z,rock)
	await _frames(2)
	drops.restore_loose_item(CAMP_ITEM,Vector3(46.5,21,46.5),0,1)
	furniture.activate_for(CAMP,true)
	furniture._hover_cell = Vector3i(46,20,47)
	furniture._confirm_ghost()
	furniture.deactivate()
	var ghost = furniture._ghosts.values()[0]
	var lease: int = ghost._lease_id
	for i in range(100):
		tasks._run_scheduler()
		if tasks.get_task(lease).blocked_count > 0: break
		await process_frame
	var task: Task = tasks.get_task(lease)
	_expect(task.blocked_count==1 and task.assigned_to<0,"back off once when every eligible worker is unreachable")
	_expect(ghost._claim_valid() and _count(CAMP_ITEM)==1,"unreachable order retains its packed item")
	var before: int = tasks._probes_total
	for i in range(5): tasks._run_scheduler()
	_expect(tasks._probes_total==before,"fully blocked order respects its retry delay")
	for y in range(21,25): world.set_block(45,y,41,blocks.AIR_ID)
	await _frames(2)
	for i in range(800):
		if furniture._ghosts.is_empty(): break
		await _tick()
	_expect(furniture._ghosts.is_empty() and _count(CAMP_ITEM)==0,"opening a route rearms the existing order and completes installation")
	_expect(tasks._worker_rejections.is_empty(),"completed leases discard failed-worker records")
