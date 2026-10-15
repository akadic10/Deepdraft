extends "res://scripts/tests/DuckWildlifeTest.gd"

var original_navigation: GDScript
var original_manager: GDScript
var reference: Node3D
var compared_ticks := 0
var checks := 0
var timings := {"reference_usec":0,"optimized_usec":0}
var modes := {}

func _run() -> void:
	create_timer(180).timeout.connect(func(): push_error("Duck query reuse timeout"); quit(1))
	for service in ["SaveManager","TaskManager","RoomManager","WorldClock","WaterManager"]: root.get_node(service).set_process(false)
	clock_node = root.get_node("WorldClock")
	clock_node.paused = false
	clock_node.speed = 1
	world = root.get_node("WorldData")
	blocks = root.get_node("BlockRegistry")
	_build_floor()
	for x in range(32,75):
		for z in range(32,65):
			world.set_block(x,20,z,blocks.AIR_ID)
			geometry[Vector2i(x,z)] = [Vector2i(20,128)]
	water = root.get_node("WaterManager")
	water.flow = load("res://scripts/components/WaterFlow.gd").new()
	water.flow.spans_at = func(col: Vector2i): return geometry.get(col,[Vector2i(21,128)])
	water.initialized = true
	for col: Vector2i in geometry: water.flow.seed_column(Vector3i(col.x,20,col.y),.75)
	scene = Node3D.new()
	root.add_child(scene)
	current_scene = scene
	original_navigation = GDScript.new()
	original_navigation.source_code = FileAccess.get_file_as_string("res://docs/00_dev_roadmap/concepts/duck_performance_20261014/DuckNavigation.before.txt") + "\nfunc begin_update() -> void:\n\tpass\nfunc end_update() -> void:\n\tpass\n"
	_expect(original_navigation.reload() == OK,"frozen navigation compiles")
	original_manager = GDScript.new()
	original_manager.source_code = FileAccess.get_file_as_string("res://docs/00_dev_roadmap/concepts/duck_performance_20261014/WildlifeManager.before.txt").replace('var duck_navigation := preload("res://scripts/components/DuckNavigation.gd").new()', 'var duck_navigation: RefCounted')
	_expect(original_manager.reload() == OK,"frozen manager compiles")
	wildlife = _new_manager(false)
	reference = _new_manager(true)
	for owner in [wildlife,reference]:
		for i in 8:
			var bird = owner.add_duck("duck:compare:%d" % i,Vector3i(40+i*3,20,40+i%3*4),421+i*127,"flock:%d" % (i%2))
			bird.flight_left = 2+i*3
	_check_queries()
	var obstacle := -1
	for tick in 1200:
		if tick==150:
			for key: Vector3i in water.flow.mass: water.flow.mass[key] = 950000
		if tick==250:
			for key: Vector3i in water.flow.mass: water.flow.mass[key] = 750000
		if tick==300: obstacle = root.get_node("PlacedEntityRegistry").register_box(Vector3i(50,20,45),Vector3i(3,12,3))
		if tick==400: root.get_node("PlacedEntityRegistry").unregister(obstacle)
		if tick==450:
			geometry[Vector2i(75,50)] = [Vector2i(15,128)]
			water.flow.terrain_changed(Vector2i(75,50))
		if tick==550:
			geometry.erase(Vector2i(75,50))
			water.flow.terrain_changed(Vector2i(75,50))
		if tick==600:
			for owner in [wildlife,reference]:
				var saved: Dictionary = JSON.parse_string(JSON.stringify(owner.serialize_state(),"",false,true))
				owner.restore_state(saved)
		if tick==750:
			for x in range(38,47):
				for z in range(38,47): water.flow.mass.erase(Vector3i(x,20,z))
		if tick==850:
			for x in range(38,47):
				for z in range(38,47): water.flow.seed_column(Vector3i(x,20,z),.75)
		clock_node.speed = 2 if tick>=900 else 1
		clock_node.paused = tick>=1000 and tick<1020
		var threats: Array = [Vector3(44,21,42)] if tick>=80 and tick<120 else []
		var delta: float = [.02,.05,.1][tick%3]
		for owner in ([reference,wildlife] if tick%2==0 else [wildlife,reference]):
			var start := Time.get_ticks_usec()
			owner.advance(delta,threats)
			timings["reference_usec" if owner==reference else "optimized_usec"] += Time.get_ticks_usec()-start
		_expect(reference.serialize_state()==wildlife.serialize_state(),"exact duck positions, needs, routes, timers and RNG tick %d" % tick)
		for bird in wildlife.animals: modes[bird.mode] = int(modes.get(bird.mode,0))+1
		_expect(not wildlife.duck_navigation.get_query_stats().active and wildlife.duck_navigation.get_query_stats().entries==0,"no cached query outlives wildlife update")
		compared_ticks += 1
		if not failures.is_empty(): break
		if tick%60==0: await process_frame
	_expect(modes.has("water") and modes.has("air"),"comparison exercises swimming and flight")
	var result := {"failures":failures,"compared_ticks":compared_ticks,"query_checks":checks,"modes":modes,
		"timings":timings,"cache":wildlife.duck_navigation.get_query_stats()}
	DirAccess.make_dir_recursive_absolute("res://tmp/duck_performance_20261014")
	FileAccess.open("res://tmp/duck_performance_20261014/query_reuse.json",FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	for failure: String in failures: push_error(failure)
	print("DUCK_QUERY_REUSE_PASS " if failures.is_empty() else "DUCK_QUERY_REUSE_FAIL ",JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)

func _new_manager(old: bool) -> Node3D:
	var owner: Node3D = original_manager.new() if old else load("res://scripts/systems/WildlifeManager.gd").new()
	if old: owner.duck_navigation = original_navigation.new()
	scene.add_child(owner)
	owner.set_process(false)
	owner.initialized = true
	owner.deer_initialized = true
	owner.wolf_initialized = true
	owner.duck_initialized = true
	return owner

func _check_queries() -> void:
	var nav = wildlife.duck_navigation
	var old = reference.duck_navigation
	nav.begin_update()
	for x in range(29,78):
		for z in range(38,44):
			var col := Vector2i(x,z)
			for safe in [true,false]:
				_expect(nav.surface(col,safe)==old.surface(col,safe),"surface query matches original")
				checks += 1
			var point := Vector3(x+.5,20.47,z+.5)
			_expect(nav.segment_clear(point,point+Vector3(2,.5,1),.5)==old.segment_clear(point,point+Vector3(2,.5,1),.5),"swept body footprint matches")
			checks += 1
	# The combined storage bound applies even during a large failed search.
	for x in range(100,300):
		for z in range(100,125): nav.water_at(Vector2i(x,z))
	_expect(nav.get_query_stats().entries<=nav.MAX_QUERY_ENTRIES and nav.get_query_stats().peak<=nav.MAX_QUERY_ENTRIES,"query storage remains bounded")
	nav.end_update()
	_expect(nav.get_query_stats().entries==0,"scope end releases all query data")
	var at := Vector3(40.5,20.47,40.5)
	var occupancy := root.get_node("PlacedEntityRegistry")
	nav.begin_update()
	_expect(nav.clear_body(at,.5),"initial body is clear")
	nav.end_update()
	var handle: int = occupancy.register_box(Vector3i(40,20,40),Vector3i(1,3,1))
	nav.begin_update()
	_expect(not nav.clear_body(at,.5),"next update observes newly placed obstruction")
	nav.end_update()
	occupancy.unregister(handle)
	_expect(nav.clear_body(at,.5),"standalone query immediately observes removal")
	var before: Dictionary = nav.surface(Vector2i(40,40))
	water.flow.mass[Vector3i(40,20,40)] = 800000
	_expect(nav.surface(Vector2i(40,40))!=before,"standalone query observes fractional water changes")
	water.flow.mass[Vector3i(40,20,40)] = 750000
	var stone: int = blocks.get_id("base:terrain:rock:rock01")
	var terrain_cell := Vector3i(40,21,40)
	var previous: int = world.get_block(terrain_cell.x,terrain_cell.y,terrain_cell.z)
	water.initialized = false # This fixture owns fixed water spans, as in DuckWildlifeTest.
	world.set_block(terrain_cell.x,terrain_cell.y,terrain_cell.z,stone)
	water.initialized = true
	nav.begin_update()
	_expect(not nav.clear_body(at,.5),"next update observes terrain placed in body footprint")
	nav.end_update()
	water.initialized = false
	world.set_block(terrain_cell.x,terrain_cell.y,terrain_cell.z,previous)
	water.initialized = true
	nav.begin_update()
	_expect(nav.clear_body(at,.5),"next update observes mined terrain")
	nav.end_update()
