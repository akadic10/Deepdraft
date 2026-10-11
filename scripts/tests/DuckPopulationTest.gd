extends SceneTree
var failures: Array[String] = []
func _init() -> void: _run.call_deferred()
func check(ok: bool,message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)
func _run() -> void:
	for service in ["SaveManager","WorldClock","TaskManager","WaterManager"]: root.get_node(service).set_process(false)
	root.get_node("WorldClock").paused = true
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var wildlife = load("res://scripts/systems/WildlifeManager.gd").new()
	scene.add_child(wildlife)
	wildlife.set_process(false)
	wildlife.duck_initialized = true
	var events = load("res://scripts/systems/WorldEventDirector.gd").new()
	scene.add_child(events)
	events.set_process(false)
	var generator = root.get_node("WorldGenerator")
	var water = root.get_node("WaterManager")
	for seed_value in [42,1234,1675083273,20261010]:
		root.get_node("WorldData").clear_world()
		water.reset()
		generator._reset_generation_state()
		generator.world_seed = seed_value
		generator._cache_block_ids()
		generator._layout_profile = generator.load_macro_layout_profile()
		generator.water_profile = generator.load_water_profile()
		generator._build_noise_instances()
		generator._build_seeded_maps()
		generator._apply_edge_detail()
		generator._build_river()
		generator._build_cave_maps()
		generator._maps_ready = true
		water.initialize()
		var started := Time.get_ticks_msec()
		var groups: Array = wildlife.duck_population.groups(seed_value)
		check(groups.size()==3,"three flocks seed %d" % seed_value)
		check(groups==wildlife.duck_population.groups(seed_value),"deterministic duck habitats")
		var river_groups := 0
		for group: Dictionary in groups:
			check(group.cells.size()>=2 and group.cells.size()<=4,"small flock")
			if generator.river_layout.columns.has(Vector2i(group.home.x,group.home.z)): river_groups += 1
			for cell: Vector3i in group.cells:
				var sample: Dictionary = wildlife.duck_navigation.surface(Vector2i(cell.x,cell.z))
				check(not sample.is_empty() and sample.water,"safe open water spawn")
		print("DUCK_GROUPS ",seed_value," flocks=",groups.size()," river=",river_groups," planning_ms=",Time.get_ticks_msec()-started)
		var settings: Dictionary = events.config.events[-1]
		var batch := {"id":"duck:test-arrival","count":3,"seed":"875323","attempt":0,"issued":0,"due":0.0,"wait":0.0}
		var plan: Dictionary = {}
		for attempt in 16:
			batch.attempt = attempt
			plan = wildlife.prepare_arrival(settings,batch,events)
			if plan.get("status")=="ready": break
		check(plan.get("status")=="ready","aerial arrivals find safe landings seed %d" % seed_value)
		if plan.get("status")!="ready": continue
		batch.merge(plan,true)
		check(wildlife.spawn_arrival_member(settings,batch,events)=="spawned","duck enters from an edge")
		var duck = wildlife.animals.back()
		check(duck.mode=="air" and (duck.position.x<2 or duck.position.x>1022 or duck.position.z<2 or duck.position.z>1022),"arrival starts airborne at map edge")
		for i in 3000:
			duck.advance(.05,0,[])
			if duck.mode!="air": break
		check(duck.mode=="water" and duck.arrival.status=="Settled","arrival flies continuously to water")
		wildlife.remove_animal(duck,"test")
	if failures.is_empty(): print("DUCK_POPULATION_OK")
	quit(0 if failures.is_empty() else 1)
