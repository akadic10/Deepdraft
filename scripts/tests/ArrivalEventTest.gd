extends SceneTree
## Real seeded boundary routes, scheduling invariants, interrupted groups,
## pressure, save replay and live terrain changes. Uses isolated user storage.
var failures: Array[String] = []
var wildlife
var events
var clock_node
var generator
var world
var navigation
var planner
var event: Dictionary
var route: Array
var checkpoint: Dictionary

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	for service in ["SaveManager", "WorldClock", "TaskManager"]: root.get_node(service).set_process(false)
	clock_node = root.get_node("WorldClock")
	clock_node.set_paused(false)
	clock_node.set_speed(1)
	generator = root.get_node("WorldGenerator")
	world = root.get_node("WorldData")
	navigation = load("res://scripts/components/AnimalNavigation.gd")
	planner = load("res://scripts/components/EdgeArrivalPlanner.gd")
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	wildlife = load("res://scripts/systems/WildlifeManager.gd").new()
	scene.add_child(wildlife)
	wildlife.set_process(false)
	wildlife.initialized = true
	wildlife.deer_initialized = true
	wildlife.wolf_initialized = true
	events = load("res://scripts/systems/WorldEventDirector.gd").new()
	scene.add_child(events)
	events.set_process(false)
	event = events.config.events[0]
	# Check actual generated edges on four seeds, including route determinism.
	for seed_value in [0, 42, 1234, 20261009]:
		_generate(seed_value)
		var result := _find_route()
		_check(not result.is_empty(), "valid inland corridor on seed %d" % seed_value)
		if result.is_empty(): continue
		route = result.route
		_check(result == _find_route(), "seeded route is repeatable")
		var entry: Vector3i = root.get_node("SaveManager").unpack_v3i(route[0])
		var home: Vector3i = root.get_node("SaveManager").unpack_v3i(route.back())
		_check(entry.x in [0, 1023] or entry.z in [0, 1023], "entry is an actual boundary cell")
		_check(planner._depth(home, 1) >= 32, "destination is at least 32 blocks inland")
		for i in range(1, route.size()):
			_check(navigation.can_hop(_cell(i-1), _cell(i)), "complete connected route with legal steps")
		print("ARRIVAL_ROUTE_SEED: ", seed_value, " edge=", result.edge, " steps=", route.size())
	if route.is_empty(): quit(1); return
	# Decided calendar draws never depend on animal population or removals.
	events.initialize_schedule()
	checkpoint = events.serialize_state()
	_check(float(events.schedules.rabbit_arrival.next.due)-clock_node.elapsed_days() >= 2, "first opportunity is delayed")
	events.restore_state({})
	events.initialize_schedule()
	_check(events.serialize_state() == checkpoint, "same world and date give same schedule")
	var plan: Dictionary = events.schedules.rabbit_arrival.next
	plan.due = clock_node.elapsed_days()
	plan.roll = 0.0
	plan.count = 3
	checkpoint = events.serialize_state()
	events.advance(.01)
	var next: Dictionary = events.schedules.rabbit_arrival.next.duplicate(true)
	_clear_animals()
	events.restore_state(checkpoint)
	var reserve_cell := _cell(route.size()-1)
	for i in range(48): wildlife.add_rabbit("reserve:%d" % i, reserve_cell, i)
	events.advance(.01)
	_check(events.schedules.rabbit_arrival.active.is_empty() and events.history.back().result == "population cap", "full population consumes rather than queues opportunity")
	_check(events.schedules.rabbit_arrival.next == next, "population cannot change future date, size, seed or roll")
	for animal in wildlife.animals.duplicate(): wildlife.remove_animal(animal, "player_hunt")
	_check(events.schedules.rabbit_arrival.next == next, "wiping out rabbits never accelerates or enlarges arrivals")
	events.advance(1)
	_check(wildlife.animals.is_empty(), "no immediate replacement after extinction")
	events.pressure.clear()
	# Limited space reduces this group only; unused members never form a queue.
	events.restore_state(checkpoint)
	for i in range(46): wildlife.add_rabbit("reserve:%d" % i, Vector3i(512, 40, 512), i)
	for attempt in range(64):
		events.advance(.01)
		if wildlife.animals.size() > 46: break
	_check(not events.schedules.rabbit_arrival.active.is_empty() and events.schedules.rabbit_arrival.active.count == 2, "limited capacity accepts only available places")
	_clear_animals()
	events.restore_state(checkpoint)
	events.schedules.rabbit_arrival.next.roll = 1.0
	events.advance(.1)
	_check(events.history.back().result == "season" and wildlife.animals.is_empty(), "seasonal chance can skip an otherwise eligible arrival")
	# A zero population can still receive the next ordinary opportunity.
	events.restore_state(checkpoint)
	for attempt in range(64):
		events.advance(.01)
		if not wildlife.animals.is_empty(): break
	_check(wildlife.animals.size() == 1, "ordinary opportunity begins one member at the boundary")
	if wildlife.animals.is_empty(): quit(1); return
	var rabbit: Node3D = wildlife.animals[0]
	route = events.schedules.rabbit_arrival.active.route.duplicate(true)
	wildlife.advance(.1, [])
	wildlife.advance(.1, [])
	_check(rabbit.activity == "Arriving" and rabbit.hop_progress > 0 and rabbit.hop_progress < 1, "arrival walks inland with partial movement")
	var animal_save: Dictionary = _json(wildlife.serialize_state())
	var event_save: Dictionary = _json(events.serialize_state())
	clock_node.set_paused(true)
	wildlife.advance(20, [])
	events.advance(20)
	_check(_json(wildlife.serialize_state()) == animal_save and _json(events.serialize_state()) == event_save, "pause freezes batch and travelling members")
	clock_node.set_paused(false)
	for i in range(120):
		wildlife.advance(.1, [])
		events.advance(.1)
	var expected_animals: Dictionary = _json(wildlife.serialize_state())
	var expected_events: Dictionary = _json(events.serialize_state())
	wildlife.restore_state(animal_save)
	events.restore_state(event_save)
	for i in range(120):
		wildlife.advance(.1, [])
		events.advance(.1)
	_check(_json(wildlife.serialize_state()) == expected_animals and _json(events.serialize_state()) == expected_events, "JSON restore mid-stride and mid-group replays exactly")
	_check(wildlife.animals.size() == 3 and events.schedules.rabbit_arrival.active.is_empty(), "three members enter once, spaced over time")
	for i in range(400): wildlife.advance(.1, [])
	for animal in wildlife.animals:
		_check(animal.arrival.status == "Settled" and animal.home == _cell(route.size()-1), "arrival reaches inland home and resumes ordinary behavior")
	# A consumed first member stays gone while the rest of a saved group enters.
	wildlife.restore_state(animal_save)
	events.restore_state(event_save)
	var consumed_id: String = wildlife.animals[0].animal_id
	wildlife.remove_animal(wildlife.animals[0], "predation")
	_check(events.pressure.is_empty(), "predation does not add player hunting pressure")
	wildlife.restore_state(_json(wildlife.serialize_state()))
	events.restore_state(_json(events.serialize_state()))
	for i in range(100):
		wildlife.advance(.1, [])
		events.advance(.1)
	_check(wildlife.animals.size() == 2, "consumed member is not replaced on load")
	for animal in wildlife.animals: _check(animal.animal_id != consumed_id, "issued ordinal is never reused")
	# Pressure is local, saved and decaying; schedule stays untouched.
	var schedule_before: Dictionary = events.schedules.duplicate(true)
	var kill_at: Vector3i = wildlife.animals[0].cell
	_check(wildlife.remove_animal(wildlife.animals[0], "player_hunt"), "successful hunt records danger")
	_check(not events.safe_arrival_cell(kill_at) and events.safe_arrival_cell(Vector3i(512, 40, 512)), "local hunting pressure discourages settlement")
	events.restore_state(_json(events.serialize_state()))
	_check(not events.safe_arrival_cell(kill_at) and _json(events.schedules) == _json(schedule_before), "saved pressure does not alter schedule")
	clock_node.advance_hours(.1)
	_check(not events.safe_arrival_cell(kill_at), "one hunt remains discouraging after time starts advancing")
	clock_node.advance_hours(49)
	_check(events.safe_arrival_cell(kill_at), "pressure fades with game days")
	# Late opportunities expire, including partially entered groups.
	_clear_animals()
	events.restore_state(checkpoint)
	clock_node.advance_hours(24*20)
	events.advance(.1)
	_check(wildlife.animals.is_empty() and events.history.back().result == "missed", "large clock jump creates no backlog")
	_check(float(events.schedules.rabbit_arrival.next.due) > clock_node.elapsed_days()+1.99, "next opportunity starts at the new calendar time")
	# Real blocks inserted after planning cancel the remaining members.
	events.restore_state(event_save)
	wildlife.restore_state(animal_save)
	var blocker := _cell(2)
	var old_block: int = navigation.block_at(blocker)
	_materialize(blocker)
	world.set_block(blocker.x, blocker.y, blocker.z, root.get_node("BlockRegistry").get_id("base:terrain:stone:granite"))
	# Clock must be within the stored opportunity for this route check.
	clock_node.restore_state({"year": 1, "season": "summer", "day": 1, "hour": 8.0, "speed": 1.0, "paused": false})
	events.schedules.rabbit_arrival.active.due = clock_node.elapsed_days()
	events.schedules.rabbit_arrival.next.due = clock_node.elapsed_days()+3
	events.advance(2)
	_check(events.schedules.rabbit_arrival.active.is_empty() and wildlife.animals.size() == 1 and events.history.back().result == "blocked", "changed corridor cancels remaining group without teleporting")
	world.set_block(blocker.x, blocker.y, blocker.z, old_block)
	_test_blocked_edges()
	# Older saves schedule only after the restored clock is available.
	events.restore_state({})
	root.get_node("SaveManager")._loading = true
	events.advance(1)
	_check(not events.initialized, "load defers fresh scheduling until calendar restore")
	clock_node.year = 4
	root.get_node("SaveManager")._loading = false
	events.advance(0)
	_check(float(events.schedules.rabbit_arrival.next.due) >= clock_node.elapsed_days()+2, "old save gets a delayed opportunity in its restored year")
	var existing: Dictionary = events.schedules.rabbit_arrival.duplicate(true)
	var future: Dictionary = event.duplicate(true)
	future.id = "future_arrival_test"
	events.config.events.append(future)
	events.initialize_schedule()
	_check(events.schedules.rabbit_arrival == existing and events.schedules.has("future_arrival_test"), "new event definition preserves existing saved decisions")
	print("ARRIVAL_EVENTS_OK" if failures.is_empty() else "ARRIVAL_EVENTS_FAILED: %d" % failures.size())
	quit(0 if failures.is_empty() else 1)

func _test_blocked_edges() -> void:
	# A narrow flat edge strip surrounded by void. A wall, water or missing
	# support across the strip must prevent entry, without unrelated detours.
	var grass: int = root.get_node("BlockRegistry").get_id("base:terrain:surface:grass_01")
	var stone: int = root.get_node("BlockRegistry").get_id("base:terrain:stone:granite")
	for x in range(0, 64):
		for z in range(400, 416):
			for y in range(16, 32): world.set_block(x, y, z, 0)
			if z in range(404, 412): world.set_block(x, 20, z, grass)
	var origin := Vector3i(0, 21, 408)
	var allowed := func(at): return at.y == 21 and at.z >= 404 and at.z < 412
	_check(not planner.from_entry(origin, 0, event, wildlife.definition, allowed).is_empty(), "fixture edge has connected habitat")
	for z in range(404, 412):
		world.set_block(12, 21, z, stone)
		world.set_block(12, 22, z, stone)
	_check(planner.from_entry(origin, 0, event, wildlife.definition, allowed).is_empty(), "sealed wall prevents inland route")
	for z in range(404, 412):
		world.set_block(12, 21, z, 0)
		world.set_block(12, 22, z, 0)
		world.set_block(12, 20, z, 0)
	_check(planner.from_entry(origin, 0, event, wildlife.definition, allowed).is_empty(), "unsupported gap prevents inland route")
	var water: int = root.get_node("BlockRegistry").get_id("base:terrain:water:source")
	_check(water != 0, "water fixture uses registered water")
	for z in range(404, 412): world.set_block(12, 20, z, water)
	_check(planner.from_entry(origin, 0, event, wildlife.definition, allowed).is_empty(), "water prevents inland route")
	world.set_block(origin.x, origin.y, origin.z, stone)
	_check(planner.from_entry(origin, 0, event, wildlife.definition, allowed).is_empty(), "blocked boundary never spawns inside a structure")

func _find_route() -> Dictionary:
	for attempt in range(int(event.entry_attempts)):
		var result: Dictionary = planner.probe(event, {"seed": "875323", "attempt": attempt}, wildlife.definition, func(_at): return true)
		if not result.is_empty(): return result
	return {}

func _cell(index: int) -> Vector3i:
	return root.get_node("SaveManager").unpack_v3i(route[index])

func _clear_animals() -> void:
	for animal in wildlife.animals.duplicate(): wildlife.remove_animal(animal, "test")

func _json(data: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(data))

func _materialize(at: Vector3i) -> void:
	var base := Vector3i(at.x >> 4, at.y >> 4, at.z >> 4)*16
	if world.chunk_exists(at.x >> 4, at.y >> 4, at.z >> 4): return
	for x in range(base.x, base.x+16):
		for y in range(base.y, base.y+16):
			for z in range(base.z, base.z+16): world.set_block(x, y, z, generator.get_generated_block_id(x, y, z))

func _generate(seed_value: int) -> void:
	world.clear_world()
	generator._reset_generation_state()
	generator.world_seed = seed_value
	generator._cache_block_ids()
	generator._layout_profile = generator.load_macro_layout_profile()
	generator._build_noise_instances()
	generator._build_seeded_maps()
	generator._apply_edge_detail()
	generator._maps_ready = true

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)
