extends "res://scripts/tests/WorkerCraftingTest.gd"

func _run() -> void:
	create_timer(60).timeout.connect(func(): push_error("Craft permission timed out"); quit(1))
	await _setup_crafting_fixture()
	drops.spawn_drop(PINE,1,Vector3i(46,21,40))
	var log_item: Node3D = drops._loose.keys()[0]
	drops.set_disallowed(log_item,true)
	var id: int = crafting.queue_order(BENCH_RECIPE,1)
	for i in 10: await _tick()
	_expect(worker.current_task_id<0 and crafting.get_order(id).progress==0,"forbidden timber does not enter crafting")
	drops.set_disallowed(log_item,false)
	_expect(await _phase(worker.TaskPhase.FETCH_PICKUP),"allowed timber wakes crafting")
	drops.set_disallowed(log_item,true)
	_expect(worker.current_task_id<0 and drops._reserved.is_empty() and _count(PINE)==1,"forbidding approach releases crafting claim")
	drops.set_disallowed(log_item,false)
	_expect(await _phase(worker.TaskPhase.FETCH_WORKING),"allowed material reaches crafting work")
	drops.set_disallowed(log_item,true)
	_expect(worker._carried_entries.is_empty() and drops._loose.has(log_item) and _count(BENCH_ITEM)==0,"forbidding during work returns unconsumed material")
	drops.set_disallowed(log_item,false)
	_expect(await _completed(id) and _count(BENCH_ITEM)==1,"craft resumes with preserved material and makes exactly one output")
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("CRAFTING_PERMISSIONS_OK: blocked selection, approach/work cancellation, conserved input and resumed output")
	quit(0 if failures.is_empty() else 1)
