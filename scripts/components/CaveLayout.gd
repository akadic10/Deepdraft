extends RefCounted

## Finite, dry, connected systems. One level per system keeps the first caves
## usable with the current three-block dwarf clearance and navigation rules.
## Immutable after build; column spans are shared by generation and discovery.
const SIZE := 1024
const CARDINALS := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]


static func build(world_seed: int, heights: PackedInt32Array, water: PackedInt32Array, profile: Dictionary) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed ^ 0x43415645
	var roughness := FastNoiseLite.new()
	roughness.seed = world_seed ^ 0x524f434b
	roughness.frequency = 0.18
	var systems: Array[Dictionary] = []
	var columns: Dictionary = {} # x * SIZE + z -> Vector3i(floor, ceiling, system)
	var soil: Dictionary = {}
	var candidates: Array[Vector2i] = []
	for x in range(48, SIZE - 48, 32):
		for z in range(48, SIZE - 48, 32):
			if heights[x * SIZE + z] >= 55: candidates.append(Vector2i(x, z))
	if candidates.is_empty(): return {"systems": systems, "columns": columns, "soil": soil}
	for attempt in range(int(profile["attempts"])):
		if systems.size() >= int(profile["target_systems"]): break
		var anchor: Vector2i = candidates[rng.randi_range(0, candidates.size() - 1)] + Vector2i(rng.randi_range(-8, 8), rng.randi_range(-8, 8))
		var rooms: Array[Vector2i] = [anchor]
		var footprint: Dictionary = {}
		var headroom := rng.randi_range(profile["min_headroom"], profile["max_headroom"])
		var count := rng.randi_range(profile["rooms_min"], profile["rooms_max"])
		for room in range(count):
			if room > 0:
				var angle := rng.randf_range(0.0, TAU)
				var distance := rng.randi_range(profile["room_spacing_min"], profile["room_spacing_max"])
				rooms.append(rooms[-1] + Vector2i(roundi(cos(angle) * distance), roundi(sin(angle) * distance)))
			var radius := rng.randi_range(profile["radius_min"], profile["radius_max"])
			_add_room(footprint, rooms[-1], radius, headroom, int(profile["min_headroom"]), roughness)
			if room > 0: _add_passage(footprint, rooms[-2], rooms[-1], int(profile["passage_radius"]), int(profile["min_headroom"]))
		# Keep only the component containing the first room (rough perimeter
		# noise must never leave isolated one-column pockets).
		footprint = _connected_footprint(footprint, anchor)
		var bounds := Rect2i(anchor, Vector2i.ONE)
		for point: Vector2i in footprint: bounds = bounds.merge(Rect2i(point, Vector2i.ONE))
		var safe_bounds := bounds.grow(maxi(profile["side_thickness"], profile["water_margin"]))
		if not Rect2i(8, 8, SIZE - 16, SIZE - 16).encloses(safe_bounds): continue
		var overlaps := false
		for system: Dictionary in systems:
			if (system["bounds"] as Rect2i).grow(profile["system_spacing"]).intersects(bounds):
				overlaps = true
				break
		if overlaps: continue
		var lowest := 127
		var wet := false
		for x in range(safe_bounds.position.x, safe_bounds.end.x):
			for z in range(safe_bounds.position.y, safe_bounds.end.y):
				lowest = mini(lowest, heights[x * SIZE + z])
				if water[x * SIZE + z] >= 0: wet = true
		var max_floor := mini(profile["max_floor_y"], lowest - headroom - int(profile["roof_thickness"]))
		if wet or max_floor < int(profile["min_floor_y"]): continue
		var floor_y := rng.randi_range(profile["min_floor_y"], max_floor)
		var fertile := rng.randf() < float(profile["soil_chance"])
		var soil_center: Vector2i = rooms[rng.randi_range(0, rooms.size() - 1)]
		var indices := PackedInt32Array()
		var volume := 0
		var soil_count := 0
		for point: Vector2i in footprint:
			var index := point.x * SIZE + point.y
			var ceiling := floor_y + int(footprint[point])
			columns[index] = Vector3i(floor_y, ceiling, systems.size())
			indices.append(index)
			volume += ceiling - floor_y
			if fertile and Vector2(point - soil_center).length() < float(profile["soil_radius"]) + roughness.get_noise_2d(point.x, point.y) * 2.0:
				soil[index] = true
				soil_count += 1
		indices.sort()
		systems.append({"id": systems.size(), "center": Vector3i(anchor.x, floor_y, anchor.y),
			"floor_y": floor_y, "ceiling_y": floor_y + headroom, "bounds": bounds,
			"columns": indices, "floor_area": indices.size(), "air_blocks": volume,
			"rooms": rooms.size(), "soil_candidates": soil_count})
	return {"systems": systems, "columns": columns, "soil": soil}


static func _add_room(footprint: Dictionary, center: Vector2i, radius: int, height: int, minimum: int, noise: FastNoiseLite) -> void:
	for x in range(center.x - radius - 2, center.x + radius + 3):
		for z in range(center.y - radius - 2, center.y + radius + 3):
			var point := Vector2i(x, z)
			var distance := Vector2(point - center).length()
			var edge := radius + noise.get_noise_2d(x, z) * 2.5
			if distance > edge: continue
			var top := minimum + roundi((height - minimum) * sqrt(maxf(0.0, 1.0 - pow(distance / maxf(edge, 1.0), 2.0))))
			footprint[point] = maxi(footprint.get(point, 0), top)


static func _add_passage(footprint: Dictionary, start: Vector2i, end: Vector2i, radius: int, height: int) -> void:
	var steps := maxi(absi(end.x - start.x), absi(end.y - start.y))
	for step in range(steps + 1):
		var center := Vector2i(Vector2(start).lerp(Vector2(end), float(step) / maxi(steps, 1)).round())
		for dx in range(-radius, radius + 1):
			for dz in range(-radius, radius + 1):
				if dx * dx + dz * dz > radius * radius: continue
				var point := center + Vector2i(dx, dz)
				footprint[point] = maxi(footprint.get(point, 0), height)


static func _connected_footprint(footprint: Dictionary, start: Vector2i) -> Dictionary:
	var connected := {start: footprint[start]}
	var queue: Array[Vector2i] = [start]
	var cursor := 0
	while cursor < queue.size():
		var point := queue[cursor]
		cursor += 1
		for direction: Vector2i in CARDINALS:
			var next := point + direction
			if footprint.has(next) and not connected.has(next):
				connected[next] = footprint[next]
				queue.append(next)
	return connected
