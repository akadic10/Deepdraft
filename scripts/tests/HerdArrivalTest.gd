extends "res://scripts/tests/ArrivalEventTest.gd"
## Wide-footprint arrivals, loose herds, predator food gates and mixed saves.

func _run() -> void:
	for service in ["SaveManager", "WorldClock", "TaskManager"]: root.get_node(service).set_process(false)
	clock_node = root.get_node("WorldClock")
	clock_node.set_paused(false)
	clock_node.set_speed(1)
	clock_node.hour = 8
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
	events = load("res://scripts/systems/WorldEventDirector.gd").new()
	scene.add_child(events)
	events.set_process(false)
	for seed_value in [0, 42, 1234, 20261009]:
		_clear_animals()
		_generate(seed_value)
		wildlife.initialized = false
		wildlife.deer_initialized = false
		wildlife.wolf_initialized = false
		wildlife.initialize_population()
		var population: Dictionary = wildlife.serialize_state()
		for species in ["deer", "wolf"]:
			wildlife.restore_state(population)
			var count := 4 if species == "deer" else 2
			for i in range(count): wildlife.remove_animal(wildlife.animals_of_species(species).back(), "test")
			var batch := _eligible_batch(species, count)
			_check(not batch.is_empty(), "%s has suitable natural arrival habitat on seed %d" % [species, seed_value])
			if batch.is_empty(): continue
			_check(batch == _eligible_batch(species, count), "wide arrival planning is deterministic")
			var data: Dictionary = wildlife.arrival_definition(species)
			_check(batch.member_routes.size() == count, "each member has its own saved destination")
			var homes: Array[Vector3i] = []
			for member_route: Array in batch.member_routes:
				var home: Vector3i = _unpack(member_route.back())
				for other in homes: _check(Vector3(home-other).length() >= 4, "group homes are separated")
				homes.append(home)
				for i in range(1, member_route.size()):
					_check(navigation.can_hop(_unpack(member_route[i-1]), _unpack(member_route[i]), int(data.navigation.clearance), 2), "every wide stride is fully supported")
				_check(planner.habitat(home, data), "whole destination footprint is grassy habitat")
			print("HERD_ARRIVAL_SEED: ", seed_value, " species=", species, " count=", count, " edge=", batch.edge)
	# A migrating deer group must enter, keep one herd identity, and settle
	# without blocking one another on the common approach or at the destination.
	_clear_animals()
	events.restore_state({})
	events.initialize_schedule()
	_make_due("deer", 4)
	_check(_enter_first("deer"), "first deer enters its scheduled group")
	if wildlife.animals_of_species("deer").is_empty(): quit(1); return
	wildlife.advance(.1, [])
	wildlife.advance(.1, [])
	var deer_save: Dictionary = _json(wildlife.serialize_state())
	var deer_events: Dictionary = _json(events.serialize_state())
	_check(wildlife.animals[0].hop_progress > 0 and wildlife.animals[0].hop_progress < 1, "save fixture has a partial deer stride")
	clock_node.set_paused(true)
	_tick(20)
	_check(_json(wildlife.serialize_state()) == deer_save and _json(events.serialize_state()) == deer_events, "pause freezes wide animals and pending herd")
	clock_node.set_paused(false)
	_tick(220)
	var replay: Dictionary = _json(wildlife.serialize_state())
	var replay_events: Dictionary = _json(events.serialize_state())
	wildlife.restore_state(deer_save)
	events.restore_state(deer_events)
	_tick(220)
	_check(_json(wildlife.serialize_state()) == replay and _json(events.serialize_state()) == replay_events, "partial herd and stride replay exactly after JSON restore")
	_tick(700)
	_check(wildlife.animals_of_species("deer").size() == 4, "four deer enter exactly once")
	var herd: String = wildlife.animals[0].herd_id
	for animal in wildlife.animals:
		_check(animal.herd_id == herd and animal.herd_members == 4, "all arrivals stay in one loose herd")
		_check(animal.arrival.status == "Settled", "each deer reaches its own inland destination")
	# Kills only add local pressure: no schedule accelerates or enlarges.
	var before: Dictionary = _json(events.schedules)
	for animal in wildlife.animals.duplicate(): wildlife.remove_animal(animal, "player_hunt")
	_check(_json(events.schedules) == before, "deer extinction leaves all species' future decisions intact")
	events.advance(1)
	_check(wildlife.animals.is_empty(), "deer extinction causes no immediate replacements")
	events.pressure.clear()
	_test_wide_obstructions()
	_test_wolves()
	_test_migration()
	print("HERD_ARRIVALS_OK" if failures.is_empty() else "HERD_ARRIVALS_FAILED: %d" % failures.size())
	quit(0 if failures.is_empty() else 1)

func _event_for(species: String) -> Dictionary:
	for entry: Dictionary in events.config.events:
		if entry.species == species: return entry
	return {}

func _eligible_batch(species: String, count: int) -> Dictionary:
	var settings := _event_for(species)
	var batch := {"id": species+"_arrival:test", "seed": "875323", "count": count,
		"issued": 0, "wait": 0.0, "due": clock_node.elapsed_days(), "attempt": 0}
	for attempt in range(int(settings.entry_attempts)):
		batch.attempt = attempt
		var result: Dictionary = wildlife.prepare_arrival(settings, batch, events)
		if result.get("status", "") == "ready":
			batch.merge(result, true)
			return batch
	return {}

func _make_due(species: String, count: int) -> void:
	events.schedules[species+"_arrival"].next.merge({"due": clock_node.elapsed_days(), "roll": 0.0, "count": count, "seed": "875323"}, true)

func _enter_first(species: String) -> bool:
	for i in range(64):
		events.advance(.01)
		if not wildlife.animals_of_species(species).is_empty(): return true
	return false

func _tick(steps: int) -> void:
	for i in range(steps):
		wildlife.advance(.1, [])
		events.advance(.1)

func _unpack(value: Array) -> Vector3i:
	return root.get_node("SaveManager").unpack_v3i(value)

func _test_wide_obstructions() -> void:
	var batch := _eligible_batch("deer", 2)
	_check(not batch.is_empty(), "wide obstruction fixture has a proven route")
	if batch.is_empty(): return
	var settings := _event_for("deer")
	var at := _unpack(batch.member_routes[0][2])+Vector3i(1, 2, 1)
	_materialize(at)
	var old: int = navigation.block_at(at)
	world.set_block(at.x, at.y, at.z, root.get_node("BlockRegistry").get_id("base:terrain:stone:granite"))
	_check(wildlife.spawn_arrival_member(settings, batch, events) == "blocked", "deer checks upper clearance in its second footprint column")
	world.set_block(at.x, at.y, at.z, old)
	at = _unpack(batch.member_routes[0][2])+Vector3i(1, -1, 1)
	_materialize(at)
	old = navigation.block_at(at)
	world.set_block(at.x, at.y, at.z, 0)
	_check(wildlife.spawn_arrival_member(settings, batch, events) == "blocked", "partial support cannot carry a wide arrival across a pit")
	world.set_block(at.x, at.y, at.z, old)
	var entry := _unpack(batch.route[0])
	var peer: Node3D = wildlife.add_deer("deer:crossing", entry, 55)
	peer.position = Vector3(entry)+Vector3(2.8, 0, 2.8)
	_check(wildlife.spawn_arrival_member(settings, batch, events) == "wait", "entry waits for a partially overlapping wide body")
	wildlife.remove_animal(peer, "test")
	events.record_player_hunt(entry)
	_check(wildlife.spawn_arrival_member(settings, batch, events) == "unsafe", "hunting pressure suppresses deer entry")
	events.pressure.clear()

func _test_wolves() -> void:
	_clear_animals()
	events.restore_state({})
	events.initialize_schedule()
	_make_due("wolf", 2)
	events.advance(.1)
	_check(events.schedules.wolf_arrival.active.is_empty() and events.history.back().result == "scarce prey", "no prey means no wolf arrival")
	# Restore ordinary seed-derived prey habitats, without existing wolves.
	wildlife.initialized = false
	wildlife.deer_initialized = false
	wildlife.wolf_initialized = true
	wildlife.initialize_population()
	var natural_prey: Dictionary = wildlife.serialize_state()
	for species in ["rabbit", "deer"]:
		var minimum: int = wildlife.wolf_definition.hunting.prey["base:animal:"+species].minimum_population
		while wildlife.animals_of_species(species).size() > minimum:
			wildlife.remove_animal(wildlife.animals_of_species(species).back(), "predation")
	var settings := _event_for("wolf")
	_check(wildlife._wolf_arrival_capacity(settings) == 0, "protected prey reserves never support additional predators")
	wildlife.restore_state(natural_prey)
	_make_due("wolf", 2)
	_check(_enter_first("wolf"), "ordinary opportunity admits wolf with plentiful nearby prey")
	if wildlife.animals_of_species("wolf").is_empty(): return
	var wolf: Node3D = wildlife.animals_of_species("wolf")[0]
	_check(wolf.hunger == float(settings.initial_hunger), "wolf enters content")
	wolf.hunger = .95
	wolf.fatigue = 0
	_check(not wolf.wants_hunt(), "even hungry arriving wolf finishes its journey before hunting")
	wolf.hunger = float(settings.initial_hunger)
	_tick(2)
	var animal_save: Dictionary = _json(wildlife.serialize_state())
	var event_save: Dictionary = _json(events.serialize_state())
	_tick(150)
	var expected: Dictionary = _json(wildlife.serialize_state())
	var expected_events: Dictionary = _json(events.serialize_state())
	wildlife.restore_state(animal_save)
	events.restore_state(event_save)
	_tick(150)
	_check(_equivalent(_json(wildlife.serialize_state()), expected) and _json(events.serialize_state()) == expected_events, "saved wolf pair and prey resume deterministically")
	_check(wildlife.animals_of_species("wolf").size() == 2, "two wolves enter once, within food and population limits")
	_tick(700)
	for member in wildlife.animals_of_species("wolf"):
		_check(member.arrival.status == "Settled", "wolf reaches its inland home")
		member.hunger = .95
		member.fatigue = 0
		member.activity = "Idle"
		_check(member.wants_hunt(), "settled wolf returns to normal hunger-gated hunting")
	# Pending members must recheck food instead of relying on an old decision.
	wildlife.restore_state(animal_save)
	events.restore_state(event_save)
	var next_before: Dictionary = _json(events.schedules.wolf_arrival.next)
	for species in ["rabbit", "deer"]:
		var minimum: int = wildlife.wolf_definition.hunting.prey["base:animal:"+species].minimum_population
		while wildlife.animals_of_species(species).size() > minimum:
			wildlife.remove_animal(wildlife.animals_of_species(species).back(), "predation")
	events.advance(4)
	_check(wildlife.animals_of_species("wolf").size() == 1 and events.history.back().result == "scarce prey", "prey depletion cancels remaining wolf without removing entered member")
	_check(_json(events.schedules.wolf_arrival.next) == next_before, "prey depletion does not reschedule wolves")
	wildlife.restore_state(animal_save)
	events.restore_state(event_save)
	for animal in wildlife.animals:
		if animal.definition.id != "base:animal:wolf": animal.position = Vector3(512, 40, 512)
	events.advance(4)
	_check(events.history.back().result == "prey moved away", "global food abundance alone cannot admit wolves into an empty local habitat")
	wildlife.restore_state(animal_save)
	events.restore_state(event_save)
	var due: Dictionary = _json(events.schedules)
	for animal in wildlife.animals_of_species("wolf"): wildlife.remove_animal(animal, "player_hunt")
	_check(_json(events.schedules) == due, "wolf kills cannot accelerate or enlarge events")
	events.advance(4)
	_check(wildlife.animals_of_species("wolf").is_empty() and events.history.back().result == "unsafe", "fresh pressure prevents the remaining wolf entering a hunted corridor")
	events.pressure.clear()
	# Capacity is checked again for an in-flight batch if other wolves appear.
	wildlife.restore_state(animal_save)
	events.restore_state(event_save)
	for i in range(3): wildlife.add_wolf("wolf:reserve:%d" % i, Vector3i(512, 40, 512), i)
	events.advance(4)
	_check(wildlife.animals_of_species("wolf").size() == 4 and events.history.back().result == "population cap", "saved batch cannot exceed four wolves")

func _test_migration() -> void:
	events.restore_state({})
	events.initialize_schedule()
	var old: Dictionary = _json(events.serialize_state())
	old.schedules.erase("deer_arrival")
	old.schedules.erase("wolf_arrival")
	events.restore_state(old)
	root.get_node("SaveManager")._loading = true
	events.advance(.1)
	_check(not events.schedules.has("deer_arrival"), "new species wait for the restored calendar")
	clock_node.year = 5
	root.get_node("SaveManager")._loading = false
	events.initialize_schedule()
	_check(_json(events.schedules.rabbit_arrival) == old.schedules.rabbit_arrival, "rabbit-only save preserves pending rabbit decision")
	for species in ["deer", "wolf"]:
		var delay: float = events.schedules[species+"_arrival"].next.due-clock_node.elapsed_days()
		var bounds: Array = _event_for(species).interval_days
		_check(delay >= float(bounds[0]) and delay <= float(bounds[1]), "migrated species gets a normal delayed first opportunity")
	var once: Dictionary = _json(events.serialize_state())
	events.initialize_schedule()
	_check(_json(events.serialize_state()) == once, "new schedules are added exactly once")

func _equivalent(a: Variant, b: Variant) -> bool:
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size(): return false
		for key in a:
			if not b.has(key) or not _equivalent(a[key], b[key]): return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size(): return false
		for i in range(a.size()):
			if not _equivalent(a[i], b[i]): return false
		return true
	# JSON decimal round-trips introduce ~1e-14 noise in accumulated needs.
	# Identity, RNG, route, activity and other discrete state remain exact.
	if a is float and b is float: return absf(a-b) < 1e-9
	return a == b
