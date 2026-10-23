extends "res://scripts/tests/HaulingSelectionTest.gd"

## Multiple storage leases must not duplicate or erase the same expensive
## route search whenever another dwarf reserves, collects or deposits goods.
func _run() -> void:
	create_timer(90).timeout.connect(func(): push_error("Shared haul routes timed out"); quit(1))
	await _setup_fixture()
	await _shared_search_invalidation()
	await _busy_colony()
	for failure: String in failures: push_error(failure)
	print("HAULING_SHARED_ROUTES_OK" if failures.is_empty() else "HAULING_SHARED_ROUTES_FAIL")
	quit(0 if failures.is_empty() else 1)

func _shared_search_invalidation() -> void:
	await _fresh()
	var nav=root.get_node("NavGrid")
	var from:=Vector3i(34,20,34)
	var goal:=Vector3i(96,20,96)
	var goals:={goal:true}
	var first:={}
	var second:={}
	tasks._budget_usec=100000
	tasks._probe_node_cap=1
	var status: int=tasks._scheduler._advance_haul_probe(first,worker,from,goal,Time.get_ticks_usec(),goals)
	_expect(status==nav.ProbeResult.SEARCHING,"fixture starts an unfinished route")
	var expanded: int=first.route_query.expanded
	drops.restore_loose_item(LOG,Vector3(80.5,21,80.5))
	tasks._scheduler._advance_haul_probe(second,worker,from,goal,Time.get_ticks_usec(),goals)
	_expect(second.route_query.expanded>expanded and first.route_query==second.route_query,"another lease resumes the same search after an inventory change")
	for wake in 400:
		status=tasks._scheduler._advance_haul_probe(second,worker,from,goal,Time.get_ticks_usec(),goals)
		if status!=nav.ProbeResult.SEARCHING: break
	_expect(status==nav.ProbeResult.REACHABLE,"shared frontier eventually proves the long route")
	var third:={}
	status=tasks._scheduler._advance_haul_probe(third,worker,from,goal,Time.get_ticks_usec(),goals)
	_expect(status==nav.ProbeResult.REACHABLE and third.last_route==second.last_route,"a completed proof serves another lease without another search")
	var rock: int=blocks.get_id("base:terrain:rock:rock01")
	world.set_block(goal.x,goal.y+1,goal.z,rock)
	await process_frame; await process_frame
	status=tasks._scheduler._advance_haul_probe(third,worker,from,goal,Time.get_ticks_usec(),goals)
	_expect(status==nav.ProbeResult.UNREACHABLE,"blocking the approach invalidates a cached successful proof")
	world.set_block(goal.x,goal.y+1,goal.z,blocks.AIR_ID)
	await process_frame; await process_frame
	for wake in 400:
		status=tasks._scheduler._advance_haul_probe(third,worker,from,goal,Time.get_ticks_usec(),goals)
		if status!=nav.ProbeResult.SEARCHING: break
	_expect(status==nav.ProbeResult.REACHABLE,"opening the approach invalidates the failed proof too")
	var capacity: int=tasks.get_config_section("hauling").get("route_cache_entries",64)
	var retained:={}
	var long_goal:=Vector3i(110,20,110)
	tasks._scheduler._advance_haul_probe(retained,worker,from,long_goal,Time.get_ticks_usec(),{long_goal:true})
	var retained_expanded: int=retained.route_query.expanded
	for i in capacity+8:
		var other:=Vector3i(30+i%70,20,105)
		tasks._scheduler._advance_haul_probe({},worker,from,other,Time.get_ticks_usec(),{other:true})
	_expect(tasks._scheduler._haul_route_cache.size()<=capacity,"shared frontiers have a bounded memory footprint")
	tasks._scheduler._advance_haul_probe(retained,worker,from,long_goal,Time.get_ticks_usec(),{long_goal:true})
	_expect(retained.route_query.expanded>retained_expanded,"cache eviction does not discard a lease's unfinished route")
	_expect(drops._reserved.is_empty(),"sharing geometry never claims inventory during planning")

func _busy_colony() -> void:
	await _fresh()
	_expect(tasks._scheduler._haul_route_cache.is_empty(),"loading a new world clears all shared route state")
	for item in drops._loose.keys(): drops.take(item); item.free()
	world.begin_edit_batch()
	for x in range(30,55):
		for z in range(28,53):
			for y in range(15,20): world.set_block(x,y,z,blocks.AIR_ID)
	world.end_edit_batch()
	worker.position=Vector3(42.5,21,40.5)
	_other(220,Vector3i(42,20,40))
	_other(221,Vector3i(43,20,40))
	_other(222,Vector3i(43,20,40))
	for id in range(2,5):
		var destination=load("res://scripts/components/StockpileZoneComponent.gd").new()
		var cells: Array[Vector3i]=[]
		for x in range(8): cells.append(Vector3i(56+x,20,42+id*3))
		destination.setup(id,cells)
		stockpiles.register_zone(destination)
	drops.restore_loose_item(LOG,Vector3(42.5,15,40.5))
	drops.restore_loose_item(LOG,Vector3(43.5,15,41.5))
	for i in 8: drops.restore_loose_item(LOG,Vector3(65.5+i*2,21,40.5))
	for actor in tasks._agents.values(): actor._food.value=1.0
	await process_frame; await process_frame
	tasks._probe_node_cap=8
	tasks._max_probes_per_wake=1
	tasks._budget_usec=10000
	var assigned:={}
	var first_assignment:=-1
	var delivered:=0
	for tick in 1800:
		tasks.advance_supervision(.05)
		stockpiles._process(.05)
		var before: int=tasks._scheduler._probes_total
		tasks._run_scheduler()
		_expect(tasks._scheduler._probes_total-before<=1,"shared geometry retains the per-wake probe cap")
		for actor in tasks._agents.values():
			if actor.current_task_id>=0:
				assigned[actor.dwarf_id]=true
				if first_assignment<0: first_assignment=tick
			actor._process(.05) # Includes normal idle movement and real cargo handling.
		delivered=int(stockpiles.get_stats().stored)
		if delivered==8: break
		await process_frame
	_expect(first_assignment>=0 and first_assignment<256,"16 leases find reachable work promptly beside two difficult pickups")
	_expect(assigned.size()==4,"all four available dwarves receive useful work")
	_expect(delivered==8 and _loose_units()==2,"all reachable logs reach storage and lower-level items remain intact")
	_expect(tasks.lifecycle_errors().is_empty(),"ongoing inventory changes preserve task and claim ownership")
	print("SHARED_HAUL_COLONY first_wake=",first_assignment," workers=",assigned.size()," delivered=",delivered)
