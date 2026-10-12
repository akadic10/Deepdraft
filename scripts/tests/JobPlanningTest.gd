extends "res://scripts/tests/FurnitureAssignmentTest.gd"

func _run() -> void:
	create_timer(90).timeout.connect(func(): push_error("Job planning timed out"); quit(1))
	await _setup_crafting_fixture()
	var nav = root.get_node("NavGrid")
	var rock: int = blocks.get_id("base:terrain:rock:rock01")
	# The closest soft-claimed kit is enclosed; a farther real kit is usable.
	var sealed := Vector3i(48,20,43)
	for dx in range(-1,2):
		for dz in range(-1,2):
			if dx==0 and dz==0: continue
			for y in range(21,25): world.set_block(sealed.x+dx,y,sealed.z+dz,rock)
	drops.restore_loose_item(CAMP_ITEM,Vector3(sealed)+Vector3(.5,1,.5),0,1)
	drops.restore_loose_item(CAMP_ITEM,Vector3(36.5,21,40.5),0,1)
	furniture.activate_for(CAMP,true)
	furniture._hover_cell = Vector3i(50,20,42)
	furniture._confirm_ghost()
	furniture.deactivate()
	var ghost = furniture._ghosts.values()[0]
	_expect(drops.item_floor_cell(ghost._claim)==sealed,"fixture claims the nearer inaccessible supply")
	tasks._probe_node_cap = 3
	_expect(await _installed(CAMP),"planning skips the enclosed kit and installs from accessible stock")
	_expect(_count(CAMP_ITEM)==1 and ghost._claim==null,"unused soft claim is released after replacement")
	# Searching may run out of allowance without proving a route impossible.
	var from := Vector3i(33,20,33)
	var goal := Vector3i(60,20,60)
	var query := {}
	nav.advance_reachability(query,from,goal,1,Time.get_ticks_usec()+100000,false)
	query.erase("approach_query")
	query["search_limit"] = 1
	var result: int = nav.advance_reachability(query,from,goal,10,Time.get_ticks_usec()+100000,false)
	_expect(result==nav.ProbeResult.BUDGET_EXHAUSTED,"a finite search cap reports unknown, not unreachable")
	var frontier: int = query.expanded
	var probe = load("res://scripts/components/WorkRouteProbe.gd")
	for wake in range(100):
		result = probe.advance(query,from,goal,4,Time.get_ticks_usec()+100000,false)
		if result==nav.ProbeResult.REACHABLE: break
	_expect(result==nav.ProbeResult.REACHABLE and int(query.expanded)>frontier,"escalation retains the frontier and finds the feasible route")
	# Terrain changes outside examined chunks leave the frontier intact.
	var task_id: int = tasks.add_task(Task.Type.PATROL,goal)
	var task = tasks.get_task(task_id)
	var context := {"route_query":query,"slices":7}
	task.planning_context[worker.dwarf_id] = context
	tasks._on_chunk_dirtied(60,1,60)
	_expect(context.get("slices",0)==7,"unrelated edits preserve pending route progress")
	var touched: Vector3i = query.chunks.keys()[0]
	tasks._on_chunk_dirtied(touched.x,touched.y,touched.z)
	_expect(context.is_empty(),"relevant edits invalidate the stale proof")
	tasks.cancel_task(task_id)
	# One far request cannot monopolize the family while a nearby one is ready.
	worker._idle_behavior.cancel()
	worker.position = Vector3(35.5,21,36.5)
	var far_id: int = tasks.add_task(Task.Type.BUILD,Vector3i(61,20,61))
	var near_id: int = tasks.add_task(Task.Type.BUILD,Vector3i(36,20,36))
	tasks._probe_node_cap = 1
	tasks._max_probes_per_wake = 1
	for wake in range(100):
		tasks._run_scheduler()
		if worker.current_task_id>=0: break
		await process_frame
	_expect(worker.current_task_id==near_id,"same-family quantum schedules nearby work before the long search finishes")
	tasks.cancel_task(far_id)
	tasks.cancel_task(near_id)
	# The second ingredient has an inaccessible nearest match. Proving only
	# the first pickup used to trap a whole batch in repeated release/retry.
	furniture._install(BENCH,furniture.get_defs()[BENCH],Vector3i(41,20,42),0)
	drops.restore_loose_item(PINE,Vector3(sealed)+Vector3(.5,1,.5),0,1)
	drops.restore_loose_item(PINE,Vector3(36.5,21,58.5),0,1)
	drops.restore_loose_item(STONE,Vector3(40.5,21,40.5),0,1)
	var craft_id: int = crafting.queue_order("base:recipe:worker:stone_hoe",1)
	tasks._probe_node_cap = 32
	tasks._max_probes_per_wake = 2
	_expect(await _completed(craft_id),"later ingredient planning skips a disconnected supply without abandoning the batch")
	_expect(_count(PINE)==1 and _count(STONE)==0 and _count("base:resources:tools:stone_hoe")==1,"two-leg continuation preserves unused material and produces exactly one tool")
	for failure: String in failures: push_error(failure)
	print("JOB_PLANNING_OK" if failures.is_empty() else "JOB_PLANNING_FAIL")
	quit(0 if failures.is_empty() else 1)

func _tick() -> void:
	tasks.advance_supervision(.05*clock_node.speed)
	await super._tick()
