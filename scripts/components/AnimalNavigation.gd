extends RefCounted
## Small terrestrial animals deliberately do not change dwarf NavGrid clearance
## or inherit its ladder links. Every hop checks live support and swept space.
## Main-thread cache only: edits invalidate overlapping footprints immediately.

const DIRECTIONS := [Vector3i(1,0,0), Vector3i(-1,0,0), Vector3i(0,0,1), Vector3i(0,0,-1)]
const MAX_TILES := 128
const MAX_TILE_ENTRIES := 1024
static var _tiles: Dictionary = {}
static var _connected := false
static var _water_revision := -1
static var _occupancy_revision := -1
static var _seed := -1
static var _maps_ready := false
static var _max_width := 1
static var _access := 0
static var _hits := 0
static var _misses := 0
static var _evictions := 0

static func clear_cache() -> void:
	_tiles.clear()

static func get_cache_stats() -> Dictionary:
	var entries := 0
	for tile: Dictionary in _tiles.values(): entries += int(tile.entries)
	return {"tiles":_tiles.size(),"entries":entries,"hits":_hits,"misses":_misses,"evictions":_evictions}

static func _check_epoch() -> void:
	if not _connected:
		WorldData.block_changed.connect(_block_changed)
		# Streamed chunks have the same generated identity. Deferred notifications
		# also discard any earlier query against a newly materialized chunk.
		WorldData.chunk_dirtied.connect(_chunk_changed, CONNECT_DEFERRED)
		PlacedEntityRegistry.occupancy_changed.connect(_invalidate_box)
		WaterManager.levels_changed.connect(_water_changed)
		_connected = true
	if _water_revision != WaterManager.revision or _occupancy_revision != PlacedEntityRegistry.reset_revision or _seed != WorldGenerator.world_seed or _maps_ready != WorldGenerator._maps_ready:
		clear_cache()
		_water_revision = WaterManager.revision
		_occupancy_revision = PlacedEntityRegistry.reset_revision
		_seed = WorldGenerator.world_seed
		_maps_ready = WorldGenerator._maps_ready

static func _tile(cell: Vector3i) -> Dictionary:
	_check_epoch()
	var key := Vector2i(cell.x >> 4,cell.z >> 4)
	_access += 1
	if not _tiles.has(key):
		if _tiles.size() >= MAX_TILES:
			var oldest: Vector2i = _tiles.keys()[0]
			for other: Vector2i in _tiles:
				if int(_tiles[other].used) < int(_tiles[oldest].used): oldest = other
			_tiles.erase(oldest)
			_evictions += 1
		_tiles[key] = {"terrain":{},"clear":{},"standable":{},"solid_bounds":{},"entries":0,"used":0}
	var tile: Dictionary = _tiles[key]
	tile.used = _access
	return tile

static func _store(tile: Dictionary, kind: String, key: Variant, value: Variant) -> void:
	# Nested queries can fill the same tile, so enforce the bound at insertion.
	if int(tile.entries) >= MAX_TILE_ENTRIES:
		tile.terrain.clear()
		tile["clear"].clear()
		tile.standable.clear()
		tile.solid_bounds.clear()
		tile.entries = 0
		_evictions += 1
	tile[kind][key] = value
	tile.entries += 1

static func _invalidate_box(at: Vector3i, size: Vector3i) -> void:
	# A result is stored by its origin, but may depend on a neighbouring tile.
	# Include every possible origin whose footprint overlaps the changed box.
	var low := Vector2i((at.x-_max_width+1) >> 4,(at.z-_max_width+1) >> 4)
	var high := Vector2i((at.x+size.x-1) >> 4,(at.z+size.z-1) >> 4)
	for x in range(low.x,high.x+1):
		for z in range(low.y,high.y+1): _tiles.erase(Vector2i(x,z))

static func _block_changed(at: Vector3i, _old: int, _new: int) -> void:
	_invalidate_box(at,Vector3i.ONE)

static func _chunk_changed(x: int, _y: int, z: int) -> void:
	_invalidate_box(Vector3i(x*16,0,z*16),Vector3i(16,128,16))

static func _water_changed(cells: Array) -> void:
	for cell: Vector3i in cells: _invalidate_box(cell,Vector3i.ONE)

static func terrain_at(cell: Vector3i) -> int:
	if cell.x < 0 or cell.z < 0 or cell.x >= WorldData.WORLD_SIZE_X or cell.z >= WorldData.WORLD_SIZE_Z or cell.y < 0 or cell.y >= WorldData.WORLD_SIZE_Y: return BlockRegistry.AIR_ID
	var tile := _tile(cell)
	if tile.terrain.has(cell):
		_hits += 1
		return tile.terrain[cell]
	_misses += 1
	var id := WorldData.get_terrain_block(cell.x,cell.y,cell.z)
	_store(tile,"terrain",cell,id)
	return id

static func block_at(cell: Vector3i) -> int:
	# Reading support includes immutable bedrock; only feet positions exclude it.
	if cell.x < 0 or cell.z < 0 or cell.x >= WorldData.WORLD_SIZE_X or cell.z >= WorldData.WORLD_SIZE_Z or cell.y < 0 or cell.y >= WorldData.WORLD_SIZE_Y: return BlockRegistry.AIR_ID
	# Keep fractional live water separate from cached terrain identity.
	return WaterManager.live_block(cell,terrain_at(cell))

static func solid_bounds_clear(low: Vector3i, high: Vector3i) -> bool:
	# Inclusive duck body bounds: water remains traversable, and flight may
	# extend above terrain height. Cache only raw solids and placed occupancy.
	# The shared edit/reset invalidation also covers footprints crossing tiles.
	_max_width = maxi(_max_width,maxi(high.x-low.x+1,high.z-low.z+1))
	var tile := _tile(low)
	var key := AABB(Vector3(low),Vector3(high-low))
	if tile.solid_bounds.has(key):
		_hits += 1
		return tile.solid_bounds[key]
	_misses += 1
	var result := _solid_bounds_uncached(low,high)
	_store(tile,"solid_bounds",key,result)
	return result

static func _solid_bounds_uncached(low: Vector3i, high: Vector3i) -> bool:
	for x in range(low.x,high.x+1):
		for y in range(low.y,high.y+1):
			for z in range(low.z,high.z+1):
				var cell := Vector3i(x,y,z)
				if y<WorldData.WORLD_SIZE_Y and BlockRegistry.is_solid(terrain_at(cell)): return false
				if PlacedEntityRegistry.occupies(cell): return false
	return true

static func inside(cell: Vector3i) -> bool:
	return cell.x >= 0 and cell.z >= 0 and cell.x < WorldData.WORLD_SIZE_X and cell.z < WorldData.WORLD_SIZE_Z and cell.y > WorldGenerator.BEDROCK_MAX_Y and cell.y < WorldData.WORLD_SIZE_Y - 1

static func clear(cell: Vector3i, height: int, width: int = 1) -> bool:
	if not inside(cell) or height < 1 or width < 1 or cell.y + height > WorldData.WORLD_SIZE_Y or cell.x + width > WorldData.WORLD_SIZE_X or cell.z + width > WorldData.WORLD_SIZE_Z: return false
	_max_width = maxi(_max_width,width)
	var tile := _tile(cell)
	var key := Vector4i(cell.x,cell.y,cell.z,(width << 16)+height)
	if tile["clear"].has(key):
		_hits += 1
		return tile["clear"][key]
	_misses += 1
	var result := _clear_uncached(cell,height,width)
	_store(tile,"clear",key,result)
	return result

static func _clear_uncached(cell: Vector3i, height: int, width: int) -> bool:
	for x in range(width):
		for z in range(width):
			for y in range(height):
				var part := cell + Vector3i(x,y,z)
				if block_at(part) != BlockRegistry.AIR_ID or PlacedEntityRegistry.occupies(part): return false
	return true

static func standable(cell: Vector3i, height: int = 2, width: int = 1) -> bool:
	if not clear(cell, height, width): return false
	var tile := _tile(cell)
	var key := Vector4i(cell.x,cell.y,cell.z,(width << 16)+height)
	if tile.standable.has(key):
		_hits += 1
		return tile.standable[key]
	_misses += 1
	var result := _supported_uncached(cell,width)
	_store(tile,"standable",key,result)
	return result

static func _supported_uncached(cell: Vector3i, width: int) -> bool:
	for x in range(width):
		for z in range(width):
			if not BlockRegistry.is_solid(block_at(cell + Vector3i(x,-1,z))): return false
	return true

static func can_hop(from: Vector3i, to: Vector3i, height: int = 2, width: int = 1) -> bool:
	# Overlapping/adjacent endpoint footprints cover the complete cardinal sweep.
	# Larger visual bodies retain two-cell strides and the existing speed/reach.
	if (from.x != to.x and from.z != to.z) or absi(from.x-to.x) + absi(from.z-to.z) != stride(width,from.y!=to.y) or absi(from.y-to.y) > 1: return false
	if not standable(from, height, width) or not standable(to, height, width): return false
	var top_y := maxi(from.y, to.y)
	return clear(Vector3i(from.x, top_y, from.z), height, width) and clear(Vector3i(to.x, top_y, to.z), height, width)

static func stride(width: int, stepping := false) -> int:
	# A height transition needs disjoint support footprints: an overlapping
	# column cannot be both clear at the lower level and solid at the upper one.
	return width if stepping else mini(width,2)

static func neighbors(cell: Vector3i, height: int = 2, width: int = 1) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	for direction: Vector3i in DIRECTIONS:
		for dy in [0, 1, -1]:
			var target := cell + direction * stride(width,dy!=0) + Vector3i(0,dy,0)
			if can_hop(cell, target, height, width):
				result.append(target)
				break
	return result

static func centre(cell: Vector3i, width: int = 1) -> Vector3:
	return Vector3(cell) + Vector3(width * 0.5, 0, width * 0.5)

static func sight_clear(from: Vector3, to: Vector3) -> bool:
	var count := maxi(1,ceili(from.distance_to(to)*4))
	for i in range(count+1):
		var cell := Vector3i((from.lerp(to,float(i)/count)+Vector3.UP*.5).floor())
		if not inside(cell) or block_at(cell) != BlockRegistry.AIR_ID or PlacedEntityRegistry.occupies(cell): return false
	return true

static func contact_clear(from: Vector3, to: Vector3, reach: float) -> bool:
	if from.distance_to(to) > reach or absf(from.y-to.y) > .35 or not sight_clear(from,to): return false
	# The contact segment is short: check every intersected voxel, including
	# a tiny corner intersection that a regularly sampled ray could miss.
	var a := from+Vector3.UP*.5
	var b := to+Vector3.UP*.5
	var low := Vector3i(a.min(b).floor())
	var high := Vector3i(a.max(b).floor())
	for x in range(low.x,high.x+1):
		for y in range(low.y,high.y+1):
			for z in range(low.z,high.z+1):
				var cell := Vector3i(x,y,z)
				if AABB(Vector3(cell),Vector3.ONE).intersects_segment(a,b) == null: continue
				if block_at(cell) != BlockRegistry.AIR_ID or PlacedEntityRegistry.occupies(cell) or not BlockRegistry.is_solid(block_at(cell+Vector3i.DOWN)): return false
	return true

static func approach(start: Vector3i, goal: Vector3, height: int, width: int, budget: int, reach: float) -> Vector3i:
	# Bounded best-first local routing: route around nearby obstacles without
	# borrowing dwarf NavGrid, scanning the world or keeping unsaved route state.
	var open: Array[Vector3i] = [start]
	var first := {start:start}
	var costs := {start:0.0}
	var best := start
	var best_distance := centre(start,width).distance_to(goal)
	for iteration in range(budget):
		if open.is_empty(): break
		var index := 0
		var score := INF
		for i in range(open.size()):
			var candidate := open[i]
			var priority := centre(candidate,width).distance_to(goal)+float(costs[candidate])*.2
			if priority < score:
				score = priority
				index = i
		var at := open[index]
		open.remove_at(index)
		var point := centre(at,width)
		var distance := point.distance_to(goal)
		if contact_clear(point,goal,reach): return first[at]
		if distance < best_distance:
			best_distance = distance
			best = at
		for next in neighbors(at,height,width):
			if first.has(next): continue
			first[next] = next if at == start else first[at]
			costs[next] = float(costs[at])+stride(width,next.y!=at.y)
			open.append(next)
	return first[best]
