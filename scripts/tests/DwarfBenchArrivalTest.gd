extends "res://scripts/tests/WorkerCraftingTest.gd"

## Doc 298: a crafter walks to where it will swing, with the goods in hand, sets them down and works,
## with no slide back. The real job on a real order.
const STEP := 1.0/60.0


func _run() -> void:
	create_timer(60).timeout.connect(func(): push_error("Bench arrival test timed out"); quit(1))
	await _setup_crafting_fixture()
	furniture._install(BENCH,furniture.get_defs()[BENCH],Vector3i(46,20,40),0)   # the log bed is a Worker's again (doc 306)
	drops.spawn_drop(PINE,2,Vector3i(38,21,39))
	drops.spawn_drop(PINE,2,Vector3i(38,21,43))
	var id: int = crafting.queue_order("base:recipe:log_bed",1)
	var order = crafting.get_order(id)
	var closest := INF
	var retreat := 0.0
	var worked := 0.0
	var fastest_goods := 0.0
	var goods_before := Vector3.INF
	var goods_ever := false
	var phases := {}
	for tick in range(6000):
		worker._food.value = 1.0
		worker.sleep = 1.0
		crafting._refresh()
		tasks._run_scheduler()
		worker._process(STEP)
		var phase: int = worker._task_phase
		phases[worker.TaskPhase.keys()[phase]] = true
		var drawn: Vector3 = worker._body.global_position
		if phase in [worker.TaskPhase.FETCH_TO_GHOST,worker.TaskPhase.FETCH_DEPOSIT,worker.TaskPhase.FETCH_WORKING]:
			var surface: Vector3 = order.work_surface_from(worker.global_position)
			var gap := Vector2(drawn.x,drawn.z).distance_to(Vector2(surface.x,surface.z))
			closest = minf(closest,gap)
			retreat = maxf(retreat,gap-closest)
		if phase == worker.TaskPhase.FETCH_TO_GHOST and not worker._carried_entries.is_empty():
			goods_ever = true
			goods_before = worker._carried_entries[0][0].global_position
		elif phase == worker.TaskPhase.FETCH_DEPOSIT and goods_before != Vector3.INF and not worker._carried_entries.is_empty():
			# The frame the walk ends: the goods stay where they were carried.
			var goods: Vector3 = worker._carried_entries[0][0].global_position
			fastest_goods = maxf(fastest_goods,Vector2(goods.x-goods_before.x,goods.z-goods_before.z).length()/STEP)
			goods_before = Vector3.INF
		if phase == worker.TaskPhase.FETCH_WORKING:
			worked += STEP
			if worked > .8: break
		if tick%120 == 0: await process_frame
	print("BENCH_ARRIVAL worked %.2f, retreat %.3f, goods fastest %.2f, carried %s, phases %s" % [worked,retreat,fastest_goods,goods_ever,phases.keys()])
	_expect(worked > .5,"the crafter reaches its bench")
	_expect(retreat < .15,"no slide back at the bench (%.2f)" % retreat)
	_expect(goods_ever,"the check saw goods carried to the bench")
	_expect(fastest_goods < 5.0,"the goods never jump as the walk ends (%.2f blocks/s)" % fastest_goods)
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("DWARF_BENCH_ARRIVAL_OK")
	quit(0 if failures.is_empty() else 1)
