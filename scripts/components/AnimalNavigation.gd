extends RefCounted
## Small terrestrial animals deliberately do not change dwarf NavGrid clearance
## or inherit its ladder links. Every hop checks live support and swept space.

const DIRECTIONS := [Vector3i(1,0,0), Vector3i(-1,0,0), Vector3i(0,0,1), Vector3i(0,0,-1)]

static func block_at(cell: Vector3i) -> int:
	# Reading support includes immutable bedrock; only feet positions exclude it.
	if cell.x < 0 or cell.z < 0 or cell.x >= WorldData.WORLD_SIZE_X or cell.z >= WorldData.WORLD_SIZE_Z or cell.y < 0 or cell.y >= WorldData.WORLD_SIZE_Y: return BlockRegistry.AIR_ID
	if WorldData.chunk_exists(cell.x >> 4, cell.y >> 4, cell.z >> 4):
		return WorldData.get_block(cell.x, cell.y, cell.z)
	return WorldGenerator.get_generated_block_id(cell.x, cell.y, cell.z)

static func inside(cell: Vector3i) -> bool:
	return cell.x >= 0 and cell.z >= 0 and cell.x < WorldData.WORLD_SIZE_X and cell.z < WorldData.WORLD_SIZE_Z and cell.y > WorldGenerator.BEDROCK_MAX_Y and cell.y < WorldData.WORLD_SIZE_Y - 1

static func clear(cell: Vector3i, height: int, width: int = 1) -> bool:
	if not inside(cell) or cell.y + height > WorldData.WORLD_SIZE_Y or cell.x + width > WorldData.WORLD_SIZE_X or cell.z + width > WorldData.WORLD_SIZE_Z: return false
	for x in range(width):
		for z in range(width):
			for y in range(height):
				var part := cell + Vector3i(x,y,z)
				if block_at(part) != BlockRegistry.AIR_ID or PlacedEntityRegistry.occupies(part): return false
	return true

static func standable(cell: Vector3i, height: int = 2, width: int = 1) -> bool:
	if not clear(cell, height, width): return false
	for x in range(width):
		for z in range(width):
			if not BlockRegistry.is_solid(block_at(cell + Vector3i(x,-1,z))): return false
	return true

static func can_hop(from: Vector3i, to: Vector3i, height: int = 2, width: int = 1) -> bool:
	# A wide animal strides one footprint. Adjacent start/end squares cover the
	# entire sweep, without skipping an unchecked column, pit or obstacle.
	if (from.x != to.x and from.z != to.z) or absi(from.x-to.x) + absi(from.z-to.z) != width or absi(from.y-to.y) > 1: return false
	if not standable(from, height, width) or not standable(to, height, width): return false
	var top_y := maxi(from.y, to.y)
	return clear(Vector3i(from.x, top_y, from.z), height, width) and clear(Vector3i(to.x, top_y, to.z), height, width)

static func neighbors(cell: Vector3i, height: int = 2, width: int = 1) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	for direction: Vector3i in DIRECTIONS:
		for dy in [0, 1, -1]:
			var target := cell + direction * width + Vector3i(0,dy,0)
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
			costs[next] = float(costs[at])+width
			open.append(next)
	return first[best]
