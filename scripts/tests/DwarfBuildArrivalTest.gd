extends "res://scripts/tests/ConstructionTest.gd"

## Doc 298: a builder walks to where it will hammer, rather than to its cell centre and then sliding
## back. The real job on a real order: a 1x1 pillar, three blocks tall, from four sides.
const STEP := 1.0/60.0
const PILLARS := [Vector3i(44,21,40)]


func _build_at(base: Vector3i) -> void:
	var cells: Array[Vector3i] = [base,base+Vector3i.UP,base+Vector3i.UP*2]
	var id: int = construction.create_order(cells)
	var trunk := Vector2(base.x+.5,base.z+.5)
	var closest := INF
	var retreat := 0.0
	var fastest := 0.0
	var hammered := 0.0
	var previous: Vector3 = worker._body.global_position
	for tick in range(6000):
		worker._food.value = 1.0
		worker.sleep = 1.0
		construction._process(STEP)
		tasks._run_scheduler()
		worker._process(STEP)
		tasks.advance_supervision(STEP)
		var hammering: bool = is_instance_valid(worker._construction_pose.tool) and worker._construction_pose.tool.visible
		var drawn: Vector3 = worker._body.global_position
		if tick > 1: fastest = maxf(fastest,Vector2(drawn.x-previous.x,drawn.z-previous.z).length()/STEP)
		previous = drawn
		var gap := Vector2(drawn.x,drawn.z).distance_to(trunk)
		if worker._task_phase in [worker.TaskPhase.FETCH_TO_GHOST,worker.TaskPhase.FETCH_WORKING]:
			closest = minf(closest,gap)
			retreat = maxf(retreat,gap-closest)
		if hammering:
			hammered += STEP
			if hammered > .6: break
		if tick%120 == 0: await process_frame
	print("BUILD_ARRIVAL %s: hammered %.2f, retreat %.3f, fastest %.2f" % [base,hammered,retreat,fastest])
	_expect(hammered > .5,"the builder reaches the pillar at %s" % base)
	_expect(retreat < .15,"no slide back arriving at %s (%.2f)" % [base,retreat])


func _run() -> void:
	create_timer(60).timeout.connect(func(): push_error("Build arrival test timed out"); quit(1))
	await _setup_fixture()
	await _new_trip(STONE,12)
	stockpiles.reset_runtime_state()
	stockpiles._process(0)
	nav = root.get_node("NavGrid")
	root.get_node("WorldGenerator")._cache_block_ids()
	mine = load("res://scripts/systems/MiningDesignationController.gd").new()
	scene.add_child(mine)
	mine.set_process(false)
	mine.set_process_unhandled_input(false)
	construction = load("res://scripts/systems/ConstructionController.gd").new()
	construction.mining = mine
	scene.add_child(construction)
	construction.set_process(false)
	construction.set_process_unhandled_input(false)
	await _build_at(PILLARS[0])
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("DWARF_BUILD_ARRIVAL_OK")
	quit(0 if failures.is_empty() else 1)
