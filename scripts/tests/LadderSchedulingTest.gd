extends "res://scripts/tests/LadderTest.gd"

func _run() -> void:
	create_timer(90).timeout.connect(func(): push_error("Ladder scheduling timed out"); quit(1))
	await _setup_crafting_fixture()
	ladders = furniture._ladders
	ladders.set_process(false)
	nav = root.get_node("NavGrid")
	_build_cliff()
	await process_frame
	# The save had one paid section and two more in storage, with mining
	# designated above it. Mining outranks construction but needs this ladder.
	for cell: Vector3i in [Vector3i(40,20,44), Vector3i(41,20,44)]:
		zone.cell_stacks[cell] = {"item":SECTION,"count":1,"material_id":"base:material:pine"}
		drops.restore_stored_item(SECTION,cell,1,"",false,"base:material:pine")
	stockpiles.rebuild_totals()
	ladders.restore_state({"next_id":2,"routes":[{"id":1,"key":LADDER,
		"base":[48,20,48],"yaw":0,"height":12,"built":4,"mode":"build","progress":0.0,
		"materials":["base:material:pine"],"required_material_id":""}]})
	var mining = load("res://scripts/systems/MiningDesignationController.gd").new()
	scene.add_child(mining)
	mining.set_process(false)
	var selected: Array[Vector3i] = [Vector3i(50,32,45)]
	var mine_id: int = mining._create_zone(selected)
	var mine_source = tasks.get_work_source(mine_id)
	var build_lease: int = ladders.routes[1].source._lease_id
	_expect(not nav.find_path(worker.current_cell(),base+Vector3i.UP*4).is_empty(),"next section is reachable on the paid rungs")
	_expect(nav.find_path(worker.current_cell(),upper).is_empty(),"mining still needs the unfinished upper sections")
	# Force continuation independent of machine speed. Construction must get
	# a turn before the much larger failed mining search finishes.
	tasks._probe_node_cap = 1
	for i in range(180):
		tasks._run_scheduler()
		if worker.current_task_id >= 0: break
		await process_frame
	_expect(worker.current_task_id == build_lease,"unfinished mining searches yield to reachable ladder construction")
	_expect(tasks._tasks.values().filter(func(task): return task.type == Task.Type.MINE).all(func(task): return task.blocked_count == 0),"yielding does not pretend that unfinished mining probes failed")
	if worker.current_task_id != build_lease:
		_finish_scheduling(); return
	_expect(int(tasks._work_probes.get(Task.Type.MINE,{}).get("route_query",{}).get("expanded",0)) > 1,"mining keeps its search progress while construction is considered")
	tasks._probe_node_cap = 1200
	# This fixture supplies real chunks, not a generated world's noise maps.
	root.get_node("WorldGenerator")._maps_ready = false
	_expect(await _until_condition(func(): return ladders.routes[1].built == 12),"worker fetches both stored sections and finishes the ladder")
	_expect(_count(SECTION) == 0 and ladders.routes[1].materials.size() == 3,"extension consumes exactly the two remaining physical sections")
	_expect(await _until_condition(func(): return mine_source.remaining_count() == 0),"finished ladder wakes mining and worker actually removes the upper block")
	mining._remove_zone(mine_id)
	_finish_scheduling()

func _finish_scheduling() -> void:
	for failure: String in failures: push_error(failure)
	print("LADDER_SCHEDULING_OK" if failures.is_empty() else "LADDER_SCHEDULING_FAIL")
	quit(0 if failures.is_empty() else 1)
