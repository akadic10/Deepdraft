extends "res://scripts/tests/DuckPopulationTest.gd"
## Frozen synchronous planner is an independent oracle on real generated water.
class OracleOwner extends Node:
	var wildlife: Node
	var duck_definition: Dictionary
	var duck_navigation: RefCounted
	var duck_initialized:=true
	func animals_of_species(species: String) -> Array: return wildlife.animals_of_species(species)
	func _arrival_cell_allowed(at: Vector3i,event: Dictionary,events: Node) -> bool: return wildlife._arrival_cell_allowed(at,event,events)

var comparisons:=0
var slices:=0
var max_slice_usec:=0

func _run() -> void:
	create_timer(180).timeout.connect(func(): push_error("Arrival preparation timeout"); quit(1))
	for service in ["SaveManager","WorldClock","TaskManager","WaterManager"]: root.get_node(service).set_process(false)
	var clock_node=root.get_node("WorldClock")
	clock_node.paused=true
	var scene:=Node3D.new()
	root.add_child(scene); current_scene=scene
	var wildlife=load("res://scripts/systems/WildlifeManager.gd").new()
	scene.add_child(wildlife); wildlife.set_process(false)
	wildlife.duck_initialized=true
	wildlife.initialized=true; wildlife.deer_initialized=true; wildlife.wolf_initialized=true
	var events=load("res://scripts/systems/WorldEventDirector.gd").new()
	scene.add_child(events); events.set_process(false)
	var old_population: RefCounted=_old_script("DuckPopulation.gd").new()
	var oracle:=OracleOwner.new()
	oracle.wildlife=wildlife; oracle.duck_definition=wildlife.duck_definition
	old_population.owner=oracle
	var old_nav: RefCounted=_old_script("DuckNavigation.gd").new()
	old_nav.config=wildlife.duck_definition.navigation
	oracle.duck_navigation=old_nav
	var nav=wildlife.duck_navigation
	var generator=root.get_node("WorldGenerator")
	var water=root.get_node("WaterManager")
	var settings: Dictionary=events.config.events[-1]
	var last_ready: Dictionary={}
	for seed_value in [42,1234,1675083273,20261010]:
		root.get_node("WorldData").clear_world(); water.reset(); generator._reset_generation_state()
		generator.world_seed=seed_value
		generator._cache_block_ids()
		generator._layout_profile=generator.load_macro_layout_profile()
		generator.water_profile=generator.load_water_profile()
		generator._build_noise_instances(); generator._build_seeded_maps(); generator._apply_edge_detail()
		generator._build_river(); generator._build_cave_maps(); generator._maps_ready=true
		water.initialize()
		for attempt in 3:
			var batch: Dictionary={"id":"duck:test-arrival","count":3,"seed":"875323","attempt":attempt,"issued":0,"due":clock_node.elapsed_days(),"wait":0.0,"route":[],"edge":""}
			var expected: Dictionary=old_population.prepare_arrival(settings,batch,events)
			var actual:=_finish(wildlife,settings,batch,events)
			check(actual==expected,"exact budgeted result seed %d attempt %d" % [seed_value,attempt])
			comparisons+=1
			if actual.get("status")!="ready": continue
			last_ready=batch.duplicate(true); last_ready.merge(actual,true)
			for route: Array in actual.member_routes:
				var landing: Vector3i=root.get_node("SaveManager").unpack_v3i(route[-1])
				var entry: Vector3i=root.get_node("SaveManager").unpack_v3i(route[0])
				var dest: Dictionary=nav.surface(Vector2i(landing.x,landing.z))
				var from:=Vector3(entry)+Vector3(.5,0,.5)
				var expected_flight: PackedVector3Array=old_nav.flight_path(from,dest.position)
				var query: Dictionary=nav.begin_flight_path(from,dest.position)
				while not nav.advance_flight_path(query,Time.get_ticks_usec()+100): pass
				check(query.result==expected_flight,"all sampled flight points match former planner")
				comparisons+=1
	check(not last_ready.is_empty(),"oracle exercise includes successful arrivals")
	# A partial attempt remains the same saved decision until it completes.
	events.initialize_schedule()
	for definition in events.config.events: events.schedules[definition.id].next.due=clock_node.elapsed_days()+100
	var state: Dictionary=events.schedules.duck_arrival
	state.active={"id":"duck:pending-fixture","count":3,"seed":"875323","attempt":0,"issued":0,"due":clock_node.elapsed_days(),"wait":0.0,"route":[],"edge":""}
	clock_node.paused=false
	events.advance(.01,Time.get_ticks_usec()+1000)
	check(wildlife.duck_population._arrival_search!=null and state.active.attempt==0,"pending slice does not consume an attempt")
	var saved: Dictionary=events.serialize_state()
	var phase: String=wildlife.duck_population._arrival_search.phase
	clock_node.paused=true
	events.advance(100)
	check(events.serialize_state()==saved and wildlife.duck_population._arrival_search.phase==phase,"pause freezes partial work and decisions")
	events.restore_state(JSON.parse_string(JSON.stringify(saved)))
	check(wildlife.duck_population._arrival_search==null,"restore discards transient search")
	clock_node.paused=false
	events.advance(.01,Time.get_ticks_usec()+1000)
	check(wildlife.duck_population._arrival_search!=null,"restored attempt resumes by rebuilding")
	events.schedules.duck_arrival.active.due=clock_node.elapsed_days()-1
	events.advance(.01)
	check(wildlife.duck_population._arrival_search==null and events.schedules.duck_arrival.active.is_empty(),"expiry cancels unfinished work")
	# Recheck actual landing conditions at entry, even after a completed plan.
	if not last_ready.is_empty():
		var landing: Vector3i=root.get_node("SaveManager").unpack_v3i(last_ready.member_routes[0][-1])
		var placed=root.get_node("PlacedEntityRegistry")
		var handle: int=placed.register_box(landing,Vector3i(2,4,2))
		check(wildlife.spawn_arrival_member(settings,last_ready,events)!="spawned" and wildlife.animals.is_empty(),"changed landing rejects entry")
		placed.unregister(handle)
	print("ARRIVAL_PREPARATION_PASS " if failures.is_empty() else "ARRIVAL_PREPARATION_FAIL ",JSON.stringify({"comparisons":comparisons,"slices":slices,"max_slice_ms":max_slice_usec/1000.0,"failures":failures}))
	oracle.free()
	quit(0 if failures.is_empty() else 1)

func _finish(wildlife: Node,event: Dictionary,plan: Dictionary,events: Node) -> Dictionary:
	for iteration in 20000:
		var start:=Time.get_ticks_usec()
		var result: Dictionary=wildlife.prepare_arrival(event,plan,events,start+200)
		max_slice_usec=maxi(max_slice_usec,Time.get_ticks_usec()-start)
		slices+=1
		check(not wildlife.duck_navigation.get_query_stats().active and wildlife.duck_navigation.get_query_stats().entries==0,"query cache never crosses a slice")
		if result.get("status")!="pending": return result
	check(false,"bounded search eventually completes")
	return {}

func _old_script(name: String) -> GDScript:
	var script:=GDScript.new()
	script.source_code=FileAccess.get_file_as_string("res://docs/00_dev_roadmap/concepts/arrivals_20261015/"+name+".before.txt")
	check(script.reload()==OK,"frozen oracle compiles")
	return script
