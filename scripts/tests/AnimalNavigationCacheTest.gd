extends "res://scripts/tests/ObjectExplorerTest.gd"
## Live invalidation, footprint seams and bounded memory. No scene rendering.
var nav
var occupancy
var water

func _run() -> void:
	for service in ["SaveManager","TaskManager","RoomManager","WorldClock","WaterManager"]: root.get_node(service).set_process(false)
	world = root.get_node("WorldData")
	blocks = root.get_node("BlockRegistry")
	occupancy = root.get_node("PlacedEntityRegistry")
	water = root.get_node("WaterManager")
	nav = load("res://scripts/components/AnimalNavigation.gd")
	_build_floor()
	var stone: int = blocks.get_id("base:terrain:surface:grass_01")
	for x in range(24,54):
		for z in range(24,54): world.set_block(x,20,z,stone)
	await process_frame # Drain setup chunk notifications before measuring reuse.
	var at := Vector3i(30,21,30) # Four-wide wolf spans four cache tiles.
	_expect(nav.standable(at,3,4),"initial supported footprint")
	var misses: int = nav.get_cache_stats().misses
	for i in 100: _expect(nav.can_hop(at,at+Vector3i(2,0,0),3,4),"cached hop stays legal")
	var warmed: int = nav.get_cache_stats().misses
	for i in 100: nav.can_hop(at,at+Vector3i(2,0,0),3,4)
	_expect(warmed >= misses and nav.get_cache_stats().misses == warmed,"repeated hop performs no new terrain or footprint queries")
	world.set_block(33,20,33,0)
	_expect(not nav.standable(at,3,4),"mined support invalidates diagonal tile seam immediately")
	world.set_block(33,20,33,stone)
	_expect(nav.standable(at,3,4),"restored support invalidates cached rejection")
	world.set_block(33,23,33,stone)
	_expect(not nav.clear(at,3,4) and nav.clear(at,2,4),"ceiling edit invalidates tall body without conflating sizes")
	world.set_block(33,23,33,0)
	_expect(nav.standable(at,3,4),"ceiling removal reopens footprint")
	var handle: int = occupancy.register_box(Vector3i(33,21,33),Vector3i.ONE)
	_expect(not nav.can_hop(at,at+Vector3i(2,0,0),3,4),"new furniture interrupts active hop")
	occupancy.unregister(handle)
	_expect(nav.can_hop(at,at+Vector3i(2,0,0),3,4),"furniture removal reopens hop")
	occupancy.register_box(at,Vector3i.ONE)
	_expect(not nav.standable(at,3,4),"occupied origin cached")
	occupancy.clear_runtime_state()
	_expect(nav.standable(at,3,4),"bulk occupancy reset clears negative cache")
	_water_checks(at)
	# Compare to authoritative reads while edits and occupancy change. All species
	# widths/heights, valid and invalid cells, are included without cached oracles.
	var random := RandomNumberGenerator.new()
	random.seed = 7214
	for i in 180:
		var cell := Vector3i(random.randi_range(27,38),random.randi_range(20,23),random.randi_range(27,38))
		var width: int = [1,2,4][i%3]
		var height: int = [2,4,3][i%3]
		world.set_block(cell.x,cell.y,cell.z,stone if i%4==0 else 0)
		_expect(nav.clear(cell,height,width) == _reference_clear(cell,height,width),"clearance matches live voxel/occupancy reads")
		_expect(nav.standable(cell,height,width) == _reference_standable(cell,height,width),"support matches live voxel reads")
	# Flood the cache with empty-space reads. Bounds are independent of travel time.
	for x in range(0,1024,16):
		for z in range(0,1024,16): nav.terrain_at(Vector3i(x,100,z))
	_expect(nav.get_cache_stats().tiles <= nav.MAX_TILES,"travelling across map evicts old tiles")
	for x in range(16):
		for z in range(16):
			for y in range(95,105): nav.terrain_at(Vector3i(x,y,z))
	_expect(nav.get_cache_stats().entries <= nav.MAX_TILES*nav.MAX_TILE_ENTRIES,"dense reads have bounded storage")
	world.clear_world()
	_expect(nav.terrain_at(at) == world.get_terrain_block(at.x,at.y,at.z),"world reset discards previous terrain")
	print("ANIMAL_NAVIGATION_CACHE_PASS" if failures.is_empty() else "ANIMAL_NAVIGATION_CACHE_FAIL "+str(failures))
	quit(0 if failures.is_empty() else 1)

func _water_checks(at: Vector3i) -> void:
	water._config = root.get_node("WorldGenerator").load_water_profile()
	water.moisture = load("res://scripts/components/SoilMoisture.gd").new()
	water._water_id = blocks.get_id("base:terrain:water:source")
	water.flow = load("res://scripts/components/WaterFlow.gd").new()
	water.flow.spans_at = func(_col: Vector2i): return [Vector2i(21,128)]
	water.initialized = true
	water.revision += 1
	_expect(nav.standable(at,3,4),"dry footprint before water rise")
	var key := Vector3i(33,21,33)
	water.flow.add_at(key,1.0,22.0)
	water._flush_changes()
	_expect(not nav.standable(at,3,4),"water occupancy invalidates footprint across seam")
	water.extract(key,1.0)
	_expect(nav.standable(at,3,4),"water withdrawal reopens footprint")
	water.flow.add_at(key,1.0,22.0)
	water._flush_changes()
	_expect(not nav.standable(at,3,4),"water rejection cached before reset")
	water.reset()
	_expect(nav.standable(at,3,4),"water reset clears cached occupancy")

func _reference_clear(at: Vector3i, height: int, width: int) -> bool:
	for x in width:
		for z in width:
			for y in height:
				var p := at+Vector3i(x,y,z)
				if world.get_live_block(p.x,p.y,p.z)!=0 or occupancy.occupies(p): return false
	return true

func _reference_standable(at: Vector3i, height: int, width: int) -> bool:
	if not _reference_clear(at,height,width): return false
	for x in width:
		for z in width:
			var p := at+Vector3i(x,-1,z)
			if not blocks.is_solid(world.get_live_block(p.x,p.y,p.z)): return false
	return true
