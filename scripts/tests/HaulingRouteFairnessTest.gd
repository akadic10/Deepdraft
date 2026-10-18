extends "res://scripts/tests/HaulingSelectionTest.gd"

## A lower-level pickup must not monopolize every lease while another worker
## has a reachable load. Mirrors the player's multilevel settlement stall.
func _run() -> void:
	create_timer(90).timeout.connect(func(): push_error("Haul route fairness timed out"); quit(1))
	await _setup_fixture()
	await _fresh()
	for node in drops._loose.keys():
		drops.take(node); node.free()
	var lower := Vector3i(42,14,40)
	# Two large disconnected walkable levels defeat the small reverse-pocket
	# rejection. The nearer pickup needs a genuinely prolonged route search.
	world.begin_edit_batch()
	for x in range(30,55):
		for z in range(28,53):
			for y in range(15,20): world.set_block(x,y,z,blocks.AIR_ID)
	world.end_edit_batch()
	worker.position = Vector3(42.5,21,40.5)
	var helper = _other(220,Vector3i(64,20,60))
	_zone_at([Vector3i(65,20,61),Vector3i(66,20,61),Vector3i(67,20,61),Vector3i(68,20,61)])
	drops.restore_loose_item(LOG,Vector3(lower)+Vector3(.5,1,.5),0,1)
	drops.restore_loose_item(LOG,Vector3(75.5,21,60.5),0,1)
	await process_frame; await process_frame
	tasks._probe_node_cap=4
	tasks._max_probes_per_wake=1
	tasks._budget_usec=10000
	for wake in 180:
		# Personal needs repeatedly alter the available pool without changing
		# either worker's position. Searches must still make forward progress.
		if wake % 3 == 0:
			tasks.notify_dwarf_unavailable(worker.dwarf_id)
			tasks.notify_dwarf_idle(worker.dwarf_id)
		stockpiles._process(.25)
		var before: int=tasks._probes_total
		tasks._run_scheduler()
		_expect(tasks._probes_total-before<=1,"candidate rotation preserves per-wake probe cap")
		if helper.current_task_id>=0: break
		await process_frame
	_expect(helper.current_task_id>=0,"reachable worker receives a load while nearer cross-level search is unfinished")
	_expect(worker.current_task_id<0,"unproven route never assigns the stranded pickup")
	if zone._pulls.has(helper.dwarf_id):
		_expect(drops.item_floor_cell(zone._pulls[helper.dwarf_id].items[0])==Vector3i(75,20,60),"executor reserves the reachable load")
	var slow_progress := 0
	for ctx: Dictionary in tasks._family_frontiers.values():
		for route: Dictionary in ctx.get("routes",{}).values():
			slow_progress=maxi(slow_progress,int(route.get("route_query",{}).get("expanded",0)))
	_expect(slow_progress>0,"yielded searches retain their frontier for a later turn")
	for tick in 1200:
		if zone.stored_count()==1: break
		helper._process(.04)
		await process_frame
	_expect(zone.stored_count()==1 and _loose_units()==1,"real delivery preserves the uncollected lower-level item")
	_expect(tasks.lifecycle_errors().is_empty(),"candidate rotation leaves valid task ownership")
	await _single_worker_alternative()
	await _only_long_route()
	for failure: String in failures: push_error(failure)
	print("HAULING_ROUTE_FAIRNESS_OK" if failures.is_empty() else "HAULING_ROUTE_FAIRNESS_FAIL")
	quit(0 if failures.is_empty() else 1)


func _single_worker_alternative() -> void:
	await _fresh()
	for node in drops._loose.keys():
		drops.take(node); node.free()
	worker.position = Vector3(42.5,21,40.5)
	_zone_at([Vector3i(64,20,44),Vector3i(65,20,44)])
	drops.restore_loose_item(LOG,Vector3(42.5,15,40.5),0,1)
	drops.restore_loose_item(LOG,Vector3(63.5,21,40.5),0,1)
	tasks._probe_node_cap=4
	tasks._max_probes_per_wake=1
	tasks._budget_usec=10000
	for wake in 240:
		stockpiles._process(.25)
		tasks._run_scheduler()
		if worker.current_task_id>=0: break
		await process_frame
	_expect(worker.current_task_id>=0,"one available dwarf tries another pickup while the nearest route is unfinished")
	if zone._pulls.has(worker.dwarf_id):
		_expect(drops.item_floor_cell(zone._pulls[worker.dwarf_id].items[0])==Vector3i(63,20,40),"softly deferred pickup stays excluded when the executor claims its load")
	for tick in 1200:
		if zone.stored_count()==1: break
		worker._process(.04)
		await process_frame
	_expect(zone.stored_count()==1 and _loose_units()==1,"single worker delivers the alternate load without losing the deferred item")
	_expect(tasks.lifecycle_errors().is_empty(),"alternate pickup retains valid task ownership")


func _only_long_route() -> void:
	await _fresh()
	for node in drops._loose.keys():
		drops.take(node); node.free()
	worker.position = Vector3(42.5,21,40.5)
	_zone_at([Vector3i(101,20,101),Vector3i(102,20,101)])
	drops.restore_loose_item(LOG,Vector3(100.5,21,100.5),0,1)
	tasks._probe_node_cap=1
	tasks._max_probes_per_wake=1
	tasks._budget_usec=10000
	var saw_deferred := false
	for wake in 600:
		stockpiles._process(.25)
		tasks._run_scheduler()
		for context: Dictionary in tasks._family_frontiers.values():
			if not context.get("deferred",{}).is_empty(): saw_deferred=true
		if worker.current_task_id>=0: break
		await process_frame
	_expect(saw_deferred,"long reachable route exceeds the planning quantum")
	_expect(worker.current_task_id>=0 and drops._reserved.size()==1,"exhausting alternatives resumes a long reachable route instead of rejecting it")
	_expect(tasks.lifecycle_errors().is_empty(),"resumed route retains valid task ownership")
