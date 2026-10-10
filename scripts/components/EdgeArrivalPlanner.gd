extends RefCounted
## Wildlife adapter for shared arrival events. Each probe is a deterministic,
## bounded search from an actual boundary cell into connected inland habitat.
const Navigation = preload("res://scripts/components/AnimalNavigation.gd")

static func probe(event: Dictionary, plan: Dictionary, animal: Dictionary, allowed: Callable) -> Dictionary:
	var random := RandomNumberGenerator.new()
	random.seed = int(String(plan.seed)) + int(plan.attempt)*104729
	var side := random.randi_range(0, 3)
	var width := int(animal.navigation.get("footprint", 1))
	var along := random.randi_range(int(event.inland_depth), WorldData.WORLD_SIZE_X-int(event.inland_depth)-width)
	var start := Vector3i(0, 0, along)
	if side == 1: start.x = WorldData.WORLD_SIZE_X-width
	elif side == 2: start = Vector3i(along, 0, 0)
	elif side == 3: start = Vector3i(along, 0, WorldData.WORLD_SIZE_Z-width)
	start.y = WorldGenerator.get_surface_y(start.x, start.z)+1
	return from_entry(start, side, event, animal, allowed)

static func from_entry(start: Vector3i, side: int, event: Dictionary, animal: Dictionary, allowed: Callable) -> Dictionary:
	var height := int(animal.navigation.clearance)
	var width := int(animal.navigation.get("footprint", 1))
	if not habitat(start, animal) or not allowed.call(start): return {}
	var inward: Vector3i = [Vector3i.RIGHT, Vector3i.LEFT, Vector3i.BACK, Vector3i.FORWARD][side]
	var goal := start+inward*int(event.inland_depth)
	var open: Array[Vector3i] = [start]
	var parents := {start: start}
	var costs := {start: 0.0}
	for iteration in range(int(event.route_nodes)):
		if open.is_empty(): break
		var best := 0
		var score := INF
		for i in range(open.size()):
			var candidate := open[i]
			var value := Vector2(candidate.x-goal.x, candidate.z-goal.z).length()+float(costs[candidate])*.2
			if value < score:
				score = value
				best = i
		var at := open[best]
		open.remove_at(best)
		if _depth(at, width) >= int(event.inland_depth) and _patch(at, event, animal, allowed):
			var route: Array = [SaveManager.pack_v3i(at)]
			while at != start:
				at = parents[at]
				route.push_front(SaveManager.pack_v3i(at))
			return {"status": "ready", "route": route, "edge": ["west", "east", "north", "south"][side]}
		for next in Navigation.neighbors(at, height, width):
			if parents.has(next) or not allowed.call(next): continue
			if Vector2(next.x-start.x, next.z-start.z).length() > float(event.inland_depth)+float(event.corridor_radius): continue
			parents[next] = at
			costs[next] = float(costs[at])+width
			open.append(next)
	return {}

static func _depth(at: Vector3i, width: int) -> int:
	return mini(mini(at.x, at.z), mini(WorldData.WORLD_SIZE_X-width-at.x, WorldData.WORLD_SIZE_Z-width-at.z))

static func habitat(at: Vector3i, animal: Dictionary) -> bool:
	var width := int(animal.navigation.get("footprint", 1))
	if at.y-1 > int(animal.population.max_ground_y) or not Navigation.standable(at, int(animal.navigation.clearance), width): return false
	for x in range(width):
		for z in range(width):
			var key := BlockRegistry.get_key(Navigation.block_at(at+Vector3i(x, -1, z)))
			if BlockRegistry.get_def(key).get("kind", "") != "grass": return false
	return true

static func group_routes(route: Array, count: int, event: Dictionary, animal: Dictionary, allowed: Callable) -> Array:
	# Connected, separated destinations prevent large arrivals piling onto one
	# home cell. BFS ordering is reversed so the furthest member settles first;
	# no later member's path runs through an earlier member's destination.
	var home := SaveManager.unpack_v3i(route.back())
	var queue: Array[Vector3i] = [home]
	var parents := {home: home}
	var homes: Array[Vector3i] = [home]
	var incoming := {}
	for packed: Array in route: incoming[SaveManager.unpack_v3i(packed)] = true
	var cursor := 0
	while cursor < queue.size() and homes.size() < count:
		var at := queue[cursor]
		cursor += 1
		for next in Navigation.neighbors(at, int(animal.navigation.clearance), int(animal.navigation.get("footprint", 1))):
			if parents.has(next) or incoming.has(next) or Vector3(next-home).length() > float(event.habitat_radius): continue
			if not habitat(next, animal) or not allowed.call(next): continue
			parents[next] = at
			queue.append(next)
			var spaced := _depth(next, int(animal.navigation.get("footprint", 1))) >= int(event.inland_depth)
			for other in homes:
				if Vector3(next-other).length() < float(event.member_spacing): spaced = false
			if spaced:
				homes.append(next)
				if homes.size() >= count: break
	if homes.size() < count: return []
	var routes: Array = []
	homes.reverse()
	for destination in homes:
		var tail: Array = []
		var at := destination
		while at != home:
			tail.push_front(SaveManager.pack_v3i(at))
			at = parents[at]
		var member_route := route.duplicate(true)
		member_route.append_array(tail)
		routes.append(member_route)
	return routes

static func _patch(start: Vector3i, event: Dictionary, animal: Dictionary, allowed: Callable) -> bool:
	if not habitat(start, animal): return false
	var cells: Array[Vector3i] = [start]
	var seen := {start: true}
	var cursor := 0
	while cursor < cells.size() and cells.size() < int(event.habitat_cells):
		var at := cells[cursor]
		cursor += 1
		for next in Navigation.neighbors(at, int(animal.navigation.clearance), int(animal.navigation.get("footprint", 1))):
			if seen.has(next) or Vector3(next-start).length() > float(event.habitat_radius): continue
			seen[next] = true
			if habitat(next, animal) and allowed.call(next): cells.append(next)
	return cells.size() >= int(event.habitat_cells)
