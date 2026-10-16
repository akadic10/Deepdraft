extends "res://scripts/tests/AnimalNavigationCacheTest.gd"
## Cross-update raw clearance reuse must agree with authoritative world reads.
var checks := 0

func _run() -> void:
	for service in ["SaveManager","TaskManager","RoomManager","WorldClock","WaterManager"]: root.get_node(service).set_process(false)
	world = root.get_node("WorldData")
	blocks = root.get_node("BlockRegistry")
	occupancy = root.get_node("PlacedEntityRegistry")
	water = root.get_node("WaterManager")
	nav = load("res://scripts/components/AnimalNavigation.gd")
	_build_floor()
	await process_frame
	var stone: int = blocks.get_id("base:terrain:rock:rock01")
	var low := Vector3i(30,30,30)
	var high := Vector3i(33,32,33)
	_expect(nav.solid_bounds_clear(low,high),"empty body crosses four tiles")
	var misses: int = nav.get_cache_stats().misses
	for i in 100: _expect(nav.solid_bounds_clear(low,high),"reuse across updates")
	_expect(nav.get_cache_stats().misses==misses,"unchanged body needs no new voxel/occupancy scan")
	world.set_block(high.x,high.y,high.z,stone)
	_expect(not nav.solid_bounds_clear(low,high),"terrain placement invalidates diagonal seam")
	_expect(nav.solid_bounds_clear(low,high-Vector3i.ONE),"different inclusive bounds stay distinct")
	world.set_block(high.x,high.y,high.z,0)
	_expect(nav.solid_bounds_clear(low,high),"mining invalidates cached rejection")
	var handle: int = occupancy.register_box(high,Vector3i.ONE)
	_expect(not nav.solid_bounds_clear(low,high),"placed obstacle invalidates seam")
	occupancy.unregister(handle)
	_expect(nav.solid_bounds_clear(low,high),"removed obstacle invalidates rejection")
	occupancy.register_box(low,Vector3i.ONE)
	_expect(not nav.solid_bounds_clear(low,high),"bulk-reset setup")
	occupancy.clear_runtime_state()
	_expect(nav.solid_bounds_clear(low,high),"bulk occupancy reset invalidates rejection")
	await process_frame
	nav.solid_bounds_clear(low,high)
	misses = nav.get_cache_stats().misses
	world.chunk_dirtied.emit(2,1,2)
	await process_frame
	nav.solid_bounds_clear(low,high)
	_expect(nav.get_cache_stats().misses>misses,"streamed chunk discards overlapping body result")
	var air := Vector3i(30,135,30)
	_expect(nav.solid_bounds_clear(air,air+Vector3i(3,2,3)),"flight above terrain height remains legal")
	handle = occupancy.register_box(air+Vector3i(3,2,3),Vector3i.ONE)
	_expect(not nav.solid_bounds_clear(air,air+Vector3i(3,2,3)),"high-altitude placed bounds are still checked")
	occupancy.unregister(handle)
	# Exercise irregular footprints and immediate positive/negative invalidation
	# against raw world reads, rather than using a second cached implementation.
	var random := RandomNumberGenerator.new()
	random.seed = 197
	for i in 400:
		low = Vector3i(random.randi_range(28,34),random.randi_range(28,32),random.randi_range(28,34))
		high = low+Vector3i(random.randi_range(0,5),random.randi_range(0,3),random.randi_range(0,5))
		world.set_block(high.x,high.y,high.z,stone if i%3==0 else 0)
		if i%5==0: handle = occupancy.register_box(high,Vector3i.ONE)
		_expect(nav.solid_bounds_clear(low,high)==_reference_bounds(low,high),"body matches live terrain/occupancy %d" % i)
		if i%5==0: occupancy.unregister(handle)
		_expect(nav.solid_bounds_clear(low,high)==_reference_bounds(low,high),"body matches after removal %d" % i)
	var timings := _compare_previous_navigation()
	# Shared bounds cover both tile travel and dense, differently sized bodies.
	for x in range(0,1024,16):
		for z in range(0,1024,16): nav.solid_bounds_clear(Vector3i(x,135,z),Vector3i(x,136,z))
	for y in range(130,145):
		for x in 16:
			for z in 16: nav.solid_bounds_clear(Vector3i(x,y,z),Vector3i(x,y+1,z))
	_expect(nav.get_cache_stats().tiles<=nav.MAX_TILES,"tile count stays bounded")
	_expect(nav.get_cache_stats().entries<=nav.MAX_TILES*nav.MAX_TILE_ENTRIES,"body and terrain entries share the memory limit")
	low = Vector3i(30,30,30)
	world.set_block(low.x,low.y,low.z,stone)
	_expect(not nav.solid_bounds_clear(low,low),"world-reset setup")
	world.clear_world()
	_expect(nav.solid_bounds_clear(low,low)==_reference_bounds(low,low),"world reset discards body cache")
	var result := {"checks":checks,"failures":failures,"timings":timings,"cache":nav.get_cache_stats()}
	DirAccess.make_dir_recursive_absolute("res://tmp/duck_updates_20261015")
	FileAccess.open("res://tmp/duck_updates_20261015/solid_bounds.json",FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	print("DUCK_SOLID_BOUNDS_PASS " if failures.is_empty() else "DUCK_SOLID_BOUNDS_FAIL ",JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)

func _reference_bounds(low: Vector3i, high: Vector3i) -> bool:
	for x in range(low.x,high.x+1):
		for y in range(low.y,high.y+1):
			for z in range(low.z,high.z+1):
				if y<128 and blocks.is_solid(world.get_terrain_block(x,y,z)): return false
				if occupancy.occupies(Vector3i(x,y,z)): return false
	return true

func _compare_previous_navigation() -> Dictionary:
	var script := GDScript.new()
	script.source_code = FileAccess.get_file_as_string("res://docs/00_dev_roadmap/concepts/duck_updates_20261015/DuckNavigation.before.txt")
	_expect(script.reload()==OK,"previous navigation compiles")
	var old = script.new()
	var current = load("res://scripts/components/DuckNavigation.gd").new()
	old.config = {"body_height":1.0,"flight_max_y":160}
	current.config = old.config.duplicate()
	var points: Array[Vector3] = []
	for x in range(28,38):
		for z in range(28,38): points.append(Vector3(x+.1,40.3,z+.7))
	for point in points:
		_expect(current.clear_body(point,.5)==old.clear_body(point,.5),"same previous body result")
	var times := {"before_usec":0,"after_usec":0,"queries_each":12000}
	for round_index in 12:
		for query in ([old,current] if round_index%2==0 else [current,old]):
			var start := Time.get_ticks_usec()
			for repeat_index in 10:
				for point in points: query.clear_body(point,.5)
			times["before_usec" if query==old else "after_usec"] += Time.get_ticks_usec()-start
	return times

func _expect(value: bool, message: String) -> void:
	checks += 1
	super._expect(value,message)
