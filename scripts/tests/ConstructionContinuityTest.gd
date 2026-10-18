extends "res://scripts/tests/ConstructionTest.gd"

const OUT := "res://tmp/construction_continuity_20261017/"
var transitions: Array = []

func _run() -> void:
	create_timer(100).timeout.connect(func(): push_error("Construction continuity timeout"); quit(1))
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
	_terrain_before = world.terrain_overrides()
	construction.set_process_unhandled_input(false)
	await _four_block_column()
	await _blocked_next_block()
	await _interrupt_after_transition()
	_expect(tasks.lifecycle_errors().is_empty(),"continuation leaves no orphan leases or reservations")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var file := FileAccess.open(OUT+"transitions.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(transitions,"\t"))
	for failure in failures: push_error(failure)
	print("CONSTRUCTION_CONTINUITY_OK" if failures.is_empty() else "CONSTRUCTION_CONTINUITY_FAIL")
	quit(0 if failures.is_empty() else 1)

func _four_block_column() -> void:
	var cells: Array[Vector3i] = []
	for y in range(21,25): cells.append(Vector3i(44,y,40))
	var id: int = construction.create_order(cells)
	_expect(await _wait_phase(worker.TaskPhase.FETCH_WORKING),"supplied four-block column reaches a real builder")
	if worker._task_phase != worker.TaskPhase.FETCH_WORKING: return
	var order = construction.orders[id]
	var task_id: int = worker.current_task_id
	var generation: int = worker._work_execution.generation
	var position: Vector3 = worker.global_position
	var left: Vector3 = worker._foot_l.global_position
	var right: Vector3 = worker._foot_r.global_position
	var body_horizontal := Vector2(worker._body.global_position.x,worker._body.global_position.z)
	var completed := 0
	for frame in range(500):
		await _tick()
		tasks.advance_supervision(.04)
		if not construction.orders.has(id): break
		_expect(worker.current_task_id==task_id and worker._work_execution.generation==generation,"reachable blocks keep the same builder and attempt")
		_expect(worker._task_phase==worker.TaskPhase.FETCH_WORKING,"block boundaries never enter idle or route planning")
		_expect(worker._move_path.is_empty() and worker.global_position.is_equal_approx(position),"root never walks or snaps inward")
		_expect(worker._foot_l.global_position.is_equal_approx(left) and worker._foot_r.global_position.is_equal_approx(right),"both visible feet remain planted across all four heights")
		_expect(Vector2(worker._body.global_position.x,worker._body.global_position.z).is_equal_approx(body_horizontal),"body stance does not reset inward between stones")
		_expect(worker._construction_pose.tool.visible,"hammer stays equipped between blocks")
		if _completed_cells().size()!=completed:
			completed = _completed_cells().size()
			var sample: Dictionary = worker._work_execution.sample(worker)
			_expect(sample.unit==str(order.target),"supervision tracks the new block rather than the previous timer")
			transitions.append({"completed":completed,"next_block":str(order.target),"task":worker.current_task_id,
				"root":str(worker.global_position),"left_foot":str(worker._foot_l.global_position),"right_foot":str(worker._foot_r.global_position)})
	_expect(cells.all(func(cell): return _completed_cells().has(cell)),"all four blocks finish from the same spot")
	_expect(transitions.size()==3,"observed every internal block transition")
	_expect(worker.global_position.is_equal_approx(position),"last block also completes without walking")
	_expect(not worker._construction_pose.tool.visible and not worker._construction_pose._stance_ready,"final completion releases the pose anchor")
	_expect(_snapshot_units()==8,"column consumes exactly four stones")

func _blocked_next_block() -> void:
	var lower := Vector3i(47,21,44)
	var upper := lower+Vector3i.UP
	var id: int = construction.create_order(_cells([lower,upper]))
	_expect(await _wait_phase(worker.TaskPhase.FETCH_WORKING),"blocked-next fixture starts the lower block")
	var order = construction.orders[id]
	var handle: int = root.get_node("PlacedEntityRegistry").register_box(upper,Vector3i.ONE)
	worker._process(3.1)
	_expect(_completed_cells().has(lower) and not _completed_cells().has(upper),"continuation rechecks late occupancy")
	_expect(worker.current_task_id<0 and order.builder_id<0,"blocked continuation releases the assignment normally")
	_expect(order.materials.count()==1,"blocked next block does not consume its stone")
	root.get_node("PlacedEntityRegistry").unregister(handle)
	_expect(await _wait_phase(worker.TaskPhase.FETCH_WORKING),"unblocking allows normal replanning")
	worker._process(3.1)
	_expect(_completed_cells().has(upper) and not construction.orders.has(id),"unblocked project finishes")

func _interrupt_after_transition() -> void:
	var lower := Vector3i(49,21,47)
	var upper := lower+Vector3i.UP
	var id: int = construction.create_order(_cells([lower,upper]))
	_expect(await _wait_phase(worker.TaskPhase.FETCH_WORKING),"interruption fixture begins")
	var order = construction.orders[id]
	worker._process(3.1)
	_expect(order.target==upper and worker._task_phase==worker.TaskPhase.FETCH_WORKING,"second block starts without releasing")
	worker._process(.4)
	var partial: float = order.progress
	clock_node.set_paused(true)
	worker._process(5)
	_expect(is_equal_approx(order.progress,partial),"pause freezes continued construction")
	clock_node.set_paused(false)
	worker.dev_force_interrupt()
	_expect(order.builder_id<0 and order.materials.count()==1 and is_equal_approx(order.work_progress[upper],partial),"interrupt after a chained commit preserves stock and partial work")
	_expect(not worker._construction_pose.tool.visible and not worker._construction_pose._stance_ready,"interruption releases the pose anchor")
	_expect(await _wait_phase(worker.TaskPhase.FETCH_WORKING),"partial chained work can resume")
	_expect(order.target==upper and order.progress>=partial and order.progress<=partial+.041,"resumed block keeps partial work plus at most the scheduler's first tick")
	construction.cancel_order(id)
	_expect(worker.current_task_id<0 and not worker._construction_pose.tool.visible,"cancelling continued work clears worker state")
	_expect(_snapshot_units()==5,"completed stones and refunded unused stock remain conserved")
