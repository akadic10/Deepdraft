extends "res://scripts/tests/HaulingAnimationTest.gd"

## Live route invalidation and A* costs, using isolated flat/terraced terrain.
## godot --headless --path . --script res://scripts/tests/NavigationRegressionTest.gd
var nav
var occupancy
var walk_results: Array[bool] = []

func _run() -> void:
	create_timer(90).timeout.connect(func(): push_error("Navigation regression timed out"); quit(1))
	await _setup_fixture()
	nav = root.get_node("NavGrid")
	occupancy = root.get_node("PlacedEntityRegistry")
	worker.walk_finished.connect(func(success: bool): walk_results.append(success))
	_check_live_obstacles()
	_check_cache_corners()
	_check_live_water()
	await _check_later_segment()
	await _check_costs()
	for failure: String in failures: push_error(failure)
	print("NAVIGATION_REGRESSION_OK" if failures.is_empty() else "NAVIGATION_REGRESSION_FAIL")
	quit(0 if failures.is_empty() else 1)

func _start_walk(goal := Vector3i(50,20,40)) -> void:
	worker.stop_walking()
	worker._idle_behavior.cancel()
	worker.position = Vector3(40.5,21,40.5)
	walk_results.clear()
	_expect(worker.walk_to(goal), "fixture starts a reachable walk")
	worker._process(.05) # Let string-pulling choose its long segment first.

func _finish_walk(blocked: Vector3i) -> void:
	var crossed := false
	for i in range(300):
		if not worker.is_walking(): break
		worker._process(.04)
		crossed = crossed or worker.current_cell() == blocked
	_expect(not crossed, "active route never enters newly blocked cell %s" % blocked)
	_expect(walk_results == [true], "detour finishes once and succeeds")

func _check_live_obstacles() -> void:
	_start_walk()
	var handle: int = occupancy.register_box(Vector3i(44,21,40),Vector3i(1,3,1))
	_expect(not nav.is_walkable(Vector3i(44,20,40)), "placed obstacle invalidates walkability")
	_finish_walk(Vector3i(44,20,40))
	occupancy.unregister(handle)

	_start_walk()
	var before: int = nav._paths_served
	handle = occupancy.register_box(Vector3i(100,21,100),Vector3i(1,3,1))
	_finish_walk(Vector3i(100,20,100))
	_expect(nav._paths_served == before, "unrelated occupancy never triggers another path search")
	occupancy.unregister(handle)

	_start_walk()
	handle = occupancy.register_box(Vector3i(50,21,40),Vector3i(1,3,1))
	worker._process(.04)
	_expect(not worker.is_walking() and walk_results == [false], "blocked destination stops and reports failure once")
	occupancy.unregister(handle)

	# Failure handlers may synchronously assign another route. The failed walk
	# must already be cleared and must not erase that replacement afterwards.
	_start_walk()
	var replacement := func(success: bool):
		if not success: worker.walk_to(Vector3i(40,20,44))
	worker.walk_finished.connect(replacement)
	handle = occupancy.register_box(Vector3i(50,21,40),Vector3i(1,3,1))
	worker._process(.04)
	_expect(worker.is_walking() and worker._move_path.back() == Vector3i(40,20,44), "failure callback preserves replacement route")
	worker.walk_finished.disconnect(replacement)
	worker.stop_walking()
	occupancy.unregister(handle)

	_start_walk()
	world.set_block(44,21,40,blocks.get_id("base:terrain:rock:rock01"))
	world.set_block(44,22,40,blocks.get_id("base:terrain:rock:rock01"))
	nav.refresh_mined_block(Vector3i(44,21,40))
	_finish_walk(Vector3i(44,20,40))
	world.set_block(44,21,40,blocks.AIR_ID)
	world.set_block(44,22,40,blocks.AIR_ID)
	nav.refresh_mined_block(Vector3i(44,21,40))

func _check_cache_corners() -> void:
	# Both path nodes are in diagonal chunks; the required corner floor is in
	# neither. Editing that corner must still evict the completed path cache.
	var a := Vector3i(31,20,31)
	var b := Vector3i(32,20,32)
	_expect(nav.find_path(a,b).size() == 2, "flat diagonal is initially legal")
	var handle: int = occupancy.register_box(Vector3i(31,21,32),Vector3i(1,3,1))
	var route: Array[Vector3i] = nav.find_path(a,b)
	_expect(route.size() == 3, "adjacent-chunk corner change invalidates cached diagonal")
	_expect(not nav.line_walkable_flat(Vector3i(31,20,32),Vector3i(31,20,32)), "zero-length segment still checks clearance")
	occupancy.unregister(handle)

func _check_live_water() -> void:
	var water = root.get_node("WaterManager")
	water.set_process(false)
	water._config = root.get_node("WorldGenerator").load_water_profile()
	water.flow = load("res://scripts/components/WaterFlow.gd").new()
	water.flow.spans_at = func(_col: Vector2i): return [Vector2i(21,128)]
	water.moisture = load("res://scripts/components/SoilMoisture.gd").new()
	water._water_id = blocks.get_id("base:terrain:water:source")
	water._last_flood_warning = 0.0
	water.initialized = true
	_start_walk()
	water.flow.add_at(Vector3i(44,21,40),1.0,22.0)
	water._flush_changes()
	_expect(not nav.is_walkable(Vector3i(44,20,40)), "rising live water invalidates the route")
	_finish_walk(Vector3i(44,20,40))
	water.reset()
	water.levels_changed.emit([Vector3i(44,21,40)])

func _check_later_segment() -> void:
	var rock: int = blocks.get_id("base:terrain:rock:rock01")
	for x in range(46,52):
		for z in range(38,43): world.set_block(x,21,z,rock)
	await process_frame
	_start_walk(Vector3i(50,21,40))
	var handle: int = occupancy.register_box(Vector3i(46,22,40),Vector3i(1,3,1))
	_finish_walk(Vector3i(46,21,40))
	occupancy.unregister(handle)
	for x in range(46,52):
		for z in range(38,43): world.set_block(x,21,z,blocks.AIR_ID)
	await process_frame

func _check_costs() -> void:
	# Independent zero-heuristic search is the cost oracle, with the same legal
	# movement graph. Asymmetric up/down costs are checked in both directions.
	var oracle = load("res://scripts/tests/fixtures/DijkstraGrid.gd").new()
	var rock: int = blocks.get_id("base:terrain:rock:rock01")
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261011
	for layout in range(8):
		var peak := Vector2i(rng.randi_range(61,67),rng.randi_range(61,67))
		for x in range(60,69):
			for z in range(60,69):
				var height := 23-mini(3,(absi(x-peak.x)+absi(z-peak.y)) >> 1)
				for y in range(21,24): world.set_block(x,y,z,rock if y <= height else blocks.AIR_ID)
		await process_frame
		oracle.clear_runtime_state()
		for pair in range(8):
			var a: Vector3i = nav.walkable_floor_at(rng.randi_range(60,68),rng.randi_range(60,68),21)
			var b: Vector3i = nav.walkable_floor_at(rng.randi_range(60,68),rng.randi_range(60,68),21)
			_compare_route_costs(oracle,a,b)
			_compare_route_costs(oracle,b,a)
	# Adding a higher work position must not hide the downhill discount to a
	# lower one. Build a real ten-step descent; its cost is exactly 9.
	for x in range(80,91):
		for y in range(21,111-x): world.set_block(x,y,90,rock)
	await process_frame
	oracle.clear_runtime_state()
	var start := Vector3i(80,30,90)
	var lower := Vector3i(90,20,90)
	var query: Dictionary = nav._new_search(start,lower,false)
	query.goal_min = lower
	query.goal_max = Vector3i(90,30,93)
	var descent: Array[Vector3i] = oracle.find_path(start,lower)
	_expect(not descent.is_empty(), "multi-goal fixture has a reachable downhill stand")
	_expect(nav._search_heuristic(query,start) <= _path_cost(descent)+.00001, "goal-box bound includes the cheaper downhill destination")
	# Ladder costs must remain lower bounds even for a future faster ladder.
	for speed in [.45,2.0,20.0]:
		nav.set_ladder(900,Vector3i(80,20,80),8,Vector3i.RIGHT,speed)
		oracle.set_ladder(900,Vector3i(80,20,80),8,Vector3i.RIGHT,speed)
		_compare_route_costs(oracle,Vector3i(78,20,80),Vector3i(80,28,80))
		_compare_route_costs(oracle,Vector3i(80,28,80),Vector3i(78,20,80))
		_compare_route_costs(oracle,Vector3i(80,20,80),Vector3i(81,20,80))
		_compare_route_costs(oracle,Vector3i(81,20,80),Vector3i(80,20,80))
	nav.remove_ladder(900)
	oracle.free()
	print("NAVIGATION_COST_CASES=140 plus mixed-height goal box")

func _compare_route_costs(oracle, a: Vector3i, b: Vector3i) -> void:
	var expected: Array[Vector3i] = oracle.find_path(a,b)
	var actual: Array[Vector3i] = nav.find_path(a,b)
	_expect(not expected.is_empty() and not actual.is_empty(), "cost fixture remains reachable")
	if expected.is_empty() or actual.is_empty(): return
	var optimal := _path_cost(expected)
	_expect(nav._heuristic(a,b) <= optimal+.00001, "heuristic is a lower bound from %s to %s" % [a,b])
	_expect(absf(_path_cost(actual)-optimal) < .00001, "A* matches Dijkstra from %s to %s" % [a,b])

func _path_cost(path: Array[Vector3i]) -> float:
	var cost := 0.0
	for i in range(1,path.size()):
		var a := path[i-1]
		var b := path[i]
		if b in nav._ladder_neighbors(a,path.front(),path.back()):
			var route: Dictionary = nav.ladder_at(a) if nav._rungs.has(a) else nav.ladder_at(b)
			cost += 1.0/maxf(.1,float(route.speed)) if a.y != b.y else nav.COST_LATERAL
		elif b.y > a.y: cost += nav.COST_UP
		elif b.y < a.y: cost += nav.COST_DOWN
		elif a.x != b.x and a.z != b.z: cost += nav.COST_DIAGONAL
		else: cost += nav.COST_LATERAL
	return cost
