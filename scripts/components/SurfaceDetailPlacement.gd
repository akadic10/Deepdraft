extends RefCounted

## Seeded base layout only. Never consult loaded visuals or mutable occupancy.
## Cell insets leave >=10 blocks between 2-block stones across cell borders;
## the complete flat clearance ring protects narrow shelves and work access.
var tree_candidates: Dictionary = {}
var rejection_counts: Dictionary = {}
var _seed := -9223372036854775807
var _patches: Dictionary = {}


func reset() -> void:
	tree_candidates.clear()
	rejection_counts.clear()
	_patches.clear()
	_seed = WorldGenerator.world_seed


static func hash_cell(seed_value: int, x: int, z: int, salt: int) -> int:
	var h: int = seed_value * 2654435761 + 0x9E3779B9
	h ^= x * 73856093
	h ^= z * 19349663
	h ^= salt * 83492791
	h ^= h >> 13
	h *= 1274126177
	h ^= h >> 16
	return h & 0x7FFFFFFF


func _reject(reason: String) -> Dictionary:
	rejection_counts[reason] = int(rejection_counts.get(reason, 0)) + 1
	return {}


func candidate(key: String, definition: Dictionary, cell: Vector2i, flora: Node) -> Dictionary:
	if _seed != WorldGenerator.world_seed:
		reset()
	var pl: Dictionary = definition.placement
	var size := int(pl.cell_size)
	var inset := int(pl.cell_inset)
	var width := int(definition.footprint)
	var h := hash_cell(_seed, cell.x, cell.y, int(definition.salt))
	var span := size - inset * 2 - width + 1
	var x := cell.x * size + inset + h % span
	var z := cell.y * size + inset + (h / span) % span
	var ring := int(pl.clear_ring)
	if x - ring < 0 or z - ring < 0 or x + width + ring >= WorldData.WORLD_SIZE_X or z + width + ring >= WorldData.WORLD_SIZE_Z:
		return _reject("edge")
	var y := WorldGenerator.get_surface_y(x, z)
	if y < int(pl.min_y) or y > int(pl.max_y):
		return _reject("height")
	var shore: Dictionary = {}
	if pl.has("shore_radius"):
		shore = shore_info(Vector3i(x,y,z),pl)
		if shore.is_empty(): return _reject("shore")
	if pl.has("ground_kinds"):
		var moisture := WorldGenerator.get_moisture(x, z)
		if moisture < float(pl.min_moisture) or moisture > float(pl.max_moisture): return _reject("moisture")
		var block_key := BlockRegistry.get_key(WorldGenerator.get_generated_block_id(x, y, z))
		if String(BlockRegistry.get_def(block_key).get("kind", "")) not in pl.ground_kinds: return _reject("ground")
	if not _patches.has(key):
		var noise := FastNoiseLite.new()
		noise.seed = _seed + int(definition.salt)
		noise.frequency = float(pl.patch_frequency)
		_patches[key] = noise
	var patch := float(pl.patch_floor) + (1.0 - float(pl.patch_floor)) * clampf(_patches[key].get_noise_2d(x, z) * 1.5 + .5, 0, 1)
	var rocky := y >= int(pl.rock_min_y)
	var density := float(pl.rock_density if rocky else pl.lowland_density) * patch
	if float(hash_cell(_seed, cell.x, cell.y, int(definition.salt) + 1)) / 2147483647.0 >= density:
		return _reject("density")
	# Flat footprint AND ring: no smoothing, floating corners or blocked ledges.
	for px in range(x - ring, x + width + ring):
		for pz in range(z - ring, z + width + ring):
			var col := Vector2i(px, pz)
			if WorldGenerator.get_waterline(col.x,col.y)>=0:
				return _reject("water")
			if WorldGenerator.get_surface_y(px, pz) != y:
				return _reject("shelf")
	var cliff_distance := -1
	if String(pl.get("habitat", "")) == "cliff_foot":
		cliff_distance = _cliff_distance(Vector3i(x, y, z), width, pl)
		if cliff_distance < 0: return _reject("cliff_foot")
		# The broad patch field supplies broken clusters; this second independent
		# sample thins them as they spread away from the wall.
		var proximity := lerpf(1.0, float(pl.outer_density), float(cliff_distance - 1) / maxf(1, float(pl.cliff_radius) - 1))
		if float(hash_cell(_seed, cell.x, cell.y, int(definition.salt) + 4)) / 2147483647.0 >= proximity:
			return _reject("cliff_falloff")
	# Preserve the original trees, even if their columns have not streamed yet.
	var tree_size := int(flora.get("scatter_cell_size"))
	var margin := int(pl.tree_margin) + ring
	var area := Rect2i(x - margin, z - margin, width + margin * 2, width + margin * 2)
	for tx in range(floori(float(area.position.x - 4) / tree_size), floori(float(area.end.x) / tree_size) + 1):
		for tz in range(floori(float(area.position.y - 4) / tree_size), floori(float(area.end.y) / tree_size) + 1):
			var tree_cell := Vector2i(tx, tz)
			if not tree_candidates.has(tree_cell):
				tree_candidates[tree_cell] = flora.call("generated_tree_candidate", tx, tz, tree_size)
			var tree: Dictionary = tree_candidates[tree_cell]
			if not tree.is_empty() and area.intersects(Rect2i(tree.origin.x, tree.origin.z, tree.footprint, tree.footprint)):
				return _reject("tree")
	var result := {"id": "%s:%d:%d:%d" % [definition.category, _seed, cell.x, cell.y], "definition": key,
		"origin": Vector3i(x, y, z), "variant": hash_cell(_seed, cell.x, cell.y, int(definition.salt) + 2) % definition.models.size(),
		"yaw": hash_cell(_seed, cell.x, cell.y, int(definition.salt) + 3) % 4,
		"habitat": String(pl.habitat) if pl.has("ground_kinds") else "cliff_foot" if cliff_distance >= 0 else "upland" if rocky else "lowland",
		"cliff_distance": cliff_distance}
	result.merge(shore)
	return result


## Immutable water geometry only. The bank mask is a cheap rejection filter,
## never proof of suitable elevation or actual exposed water.
func shore_info(origin: Vector3i, pl: Dictionary) -> Dictionary:
	var radius := int(pl.shore_radius)
	var column := Vector2i(origin.x,origin.z)
	if WorldGenerator.get_waterline(origin.x,origin.z) >= 0: return {}
	if radius <= WorldGenerator.WATER_BANK_RADIUS and not WorldGenerator.water_bank_columns.has(column): return {}
	var result: Dictionary = {}
	var nearest := radius + 1
	for dx in range(-radius,radius+1):
		for dz in range(-radius,radius+1):
			var distance := absi(dx)+absi(dz)
			if distance == 0 or distance > radius or distance >= nearest: continue
			var water := column + Vector2i(dx,dz)
			var level := WorldGenerator.get_waterline(water.x,water.y)
			if level < 0: continue
			var rise := origin.y-level
			if rise < int(pl.min_bank_height) or rise > int(pl.max_bank_height): continue
			# Require an actual water cell; a mask/height alone must not suffice.
			var block := WorldGenerator.get_generated_block_id(water.x,level,water.y)
			if String(BlockRegistry.get_def(BlockRegistry.get_key(block)).get("kind","")) != "water": continue
			nearest = distance
			result = {"shore_water":water, "shore_waterline":level, "shore_distance":distance,
				"water_body":"tarn" if WorldGenerator.tarn_columns.has(water) else "lake"}
	return result


func _cliff_distance(origin: Vector3i, width: int, pl: Dictionary) -> int:
	var nearest := -1
	var center := Vector2i(origin.x + width / 2, origin.z + width / 2)
	for direction: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN,
			Vector2i(-1,-1), Vector2i(-1,1), Vector2i(1,-1), Vector2i(1,1)]:
		for distance in range(1, int(pl.cliff_radius) + 1):
			var col := center + direction * (width / 2 + distance)
			if col.x < 0 or col.y < 0 or col.x >= WorldData.WORLD_SIZE_X or col.y >= WorldData.WORLD_SIZE_Z: break
			if WorldGenerator.get_waterline(col.x,col.y)>=0: break
			var rise := WorldGenerator.get_surface_y(col.x, col.y) - origin.y
			if rise >= int(pl.cliff_min_rise):
				nearest = distance if nearest < 0 else mini(nearest, distance)
				break
			# Do not place rubble across a ravine or beyond an intervening step.
			if rise != 0: break
	return nearest


## A visual planting reservation, never navigation occupancy. Half-open bounds
## allow neighbouring 3x3 patches to touch, including on separate terrain levels.
static func planting_area(definition: Dictionary, origin: Vector3i) -> AABB:
	var radius := int(definition.get("planting_radius", 0))
	return AABB(Vector3(origin) + Vector3(-radius, 1, -radius),
		Vector3(int(definition.footprint) + radius * 2, maxi(3, int(definition.height)), int(definition.footprint) + radius * 2))
