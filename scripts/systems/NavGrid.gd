extends Node

## Custom 3D A* navigation (doc 32, doc 16 step 3b). Autoload, loaded after
## PlacedEntityRegistry (walkability reads it), before the future TaskManager
## (reachability probes need it).
##
## WALKABILITY (doc 32, Hard Rule 3): a floor cell (x, y, z) is walkable iff
##   1. the block at y is SOLID (water is not solid — no walking on lakes),
##   2. the blocks at y+1, y+2, y+3 are air (the 3-block clearance envelope),
##   3. none of those three clearance cells is occupied by a placed entity
##      (tree trunks, the Settlement Flag — PlacedEntityRegistry.occupies).
## Logical dwarf height is 3 blocks — NEVER the 3.3 visual mesh (doc 41).
##
## TERRAIN SOURCE: WorldData where the chunk exists (real, mined-aware once
## mining execution writes void); otherwise the deterministic generated block
## (`WorldGenerator.get_generated_block_id`) so dwarves can walk the whole map
## without waiting for render streaming.
##   KNOWN DEV WART: DEV-instant-mined blocks in UNgenerated chunks live only
##   in the renderer's mined set, not WorldData — nav sees authored rock there.
##   Real mining execution (step 6) writes through WorldData.set_block (which
##   lazily creates chunks), closing the gap. Recorded in doc 16 build log.
##
## CACHING (doc 32): walkability memoised per CHUNK (lazy, invalidated by
## WorldData.chunk_dirtied and PlacedEntityRegistry.occupancy_changed);
## completed paths cached by (start, goal) with a 5 s TTL, dropped when an
## invalidation touches any chunk the path crosses.
##
## STEP RULES: cardinal moves with floor delta -1/0/+1 per step, PLUS flat
## diagonals (enabled 2026-06-10, Alen — L-shaped routes read wrong in play;
## doc 32 updated). Diagonal rules: same-level only (vertical steps stay
## cardinal), and NO corner cutting — both cardinal in-between cells must be
## walkable, so dwarves never clip tree trunks or wall corners.
## Costs: lateral 1.0, diagonal 1.414, up 1.2, down 0.9. Heuristic: octile XZ
## + |dy| (admissible with diagonals; Manhattan would overestimate).

const CLEARANCE := 3                  # air blocks above every floor cell
const PATH_CACHE_TTL_MSEC := 5000     # doc 32
const DEFAULT_MAX_NODES := 6000      # full-path expansion cap (never hangs)
const PROBE_NODE_CAP := 200           # scheduler reachability probes (doc 32)

const COST_LATERAL := 1.0
const COST_DIAGONAL := 1.414
const COST_UP := 1.2
const COST_DOWN := 0.9

var _walkable_cache: Dictionary = {}   # Vector3i chunk -> Dictionary[Vector3i cell -> bool]
var _path_cache: Dictionary = {}       # [start, goal] key -> { path, expires, chunks }
var _paths_served: int = 0
var _path_cache_hits: int = 0
var _probes_run: int = 0
var _nodes_expanded_total: int = 0


func _ready() -> void:
	WorldData.chunk_dirtied.connect(_on_chunk_dirtied, CONNECT_DEFERRED)
	PlacedEntityRegistry.occupancy_changed.connect(_on_occupancy_changed)
	print("NavGrid: ready.")


# ── Public API ────────────────────────────────────────────────────────────────

## Full pathfind between two FLOOR cells. Returns the ordered floor-cell path
## INCLUDING start and goal, or an empty array if unreachable within the node
## cap. Results are cached for PATH_CACHE_TTL_MSEC.
func find_path(start: Vector3i, goal: Vector3i, max_nodes: int = DEFAULT_MAX_NODES) -> Array[Vector3i]:
	var now := Time.get_ticks_msec()
	var key := [start, goal]
	if _path_cache.has(key):
		var entry: Dictionary = _path_cache[key]
		if now < int(entry["expires"]):
			_path_cache_hits += 1
			var cached: Array[Vector3i] = entry["path"]
			return cached
		_path_cache.erase(key)

	var result := _astar(start, goal, max_nodes, false)
	if not result.is_empty():
		_path_cache[key] = {
			"path": result,
			"expires": now + PATH_CACHE_TTL_MSEC,
			"chunks": _path_chunk_set(result),
		}
		_paths_served += 1
	return result


## Capped reachability probe (doc 16 §2.6 — the scheduler's question). True if
## `goal` or any cell laterally adjacent to it is reached within the node cap.
## A capped failure counts as unreachable (caller applies backoff). The caller
## may pass its configured cap (task_config.json probe_node_cap); the default
## is the doc-32 value.
func probe_reachable(start: Vector3i, goal: Vector3i, node_cap: int = PROBE_NODE_CAP) -> bool:
	_probes_run += 1
	return not _astar(start, goal, node_cap, true).is_empty()


## The doc-32 walkability test for one floor cell (cached).
func is_walkable(cell: Vector3i) -> bool:
	if cell.y < 1 or cell.y + CLEARANCE >= WorldData.WORLD_SIZE_Y \
			or cell.x < 0 or cell.x >= WorldData.WORLD_SIZE_X \
			or cell.z < 0 or cell.z >= WorldData.WORLD_SIZE_Z:
		return false
	var chunk_key := Vector3i(cell.x >> 4, cell.y >> 4, cell.z >> 4)
	var chunk_cache: Dictionary = _walkable_cache.get(chunk_key, {})
	if chunk_cache.has(cell):
		return chunk_cache[cell]
	var walkable := _compute_walkable(cell)
	if chunk_cache.is_empty():
		_walkable_cache[chunk_key] = chunk_cache
	chunk_cache[cell] = walkable
	return walkable


## Finds the walkable floor cell of a column near an expected Y (snap helper
## for click targets and spawn points). Returns cell or Vector3i(-1,-1,-1).
func walkable_floor_at(wx: int, wz: int, near_y: int, scan: int = 4) -> Vector3i:
	var offsets: Array[int] = [0]
	for dy in range(1, scan + 1):
		offsets.append(dy)
		offsets.append(-dy)
	for dy in offsets:
		var cell := Vector3i(wx, near_y + dy, wz)
		if is_walkable(cell):
			return cell
	return Vector3i(-1, -1, -1)


## String-pulling support (agent movement smoothing): true if an agent can walk
## a straight FLAT line between two same-level floor-cell centres without
## crossing an unwalkable cell. Samples the segment with a small agent radius —
## the corner-safety margin. Grid paths stay the correctness authority; this
## only lets agents cut the staircase zigzag between waypoints.
func line_walkable_flat(a: Vector3i, b: Vector3i, radius: float = 0.3) -> bool:
	if a.y != b.y:
		return false
	var from := Vector2(float(a.x) + 0.5, float(a.z) + 0.5)
	var to := Vector2(float(b.x) + 0.5, float(b.z) + 0.5)
	var length := from.distance_to(to)
	if length < 0.001:
		return true
	var dir := (to - from) / length
	var side := Vector2(-dir.y, dir.x) * radius
	var t := 0.0
	while t <= length:
		var p := from + dir * t
		for offset in [Vector2.ZERO, side, -side]:
			var q: Vector2 = p + offset
			if not is_walkable(Vector3i(floori(q.x), a.y, floori(q.y))):
				return false
		t += 0.25
	return true


func get_stats() -> Dictionary:
	return {
		"paths_served": _paths_served,
		"path_cache_hits": _path_cache_hits,
		"path_cache_size": _path_cache.size(),
		"probes_run": _probes_run,
		"walkable_chunks_cached": _walkable_cache.size(),
		"nodes_expanded_total": _nodes_expanded_total,
	}


# ── Walkability ───────────────────────────────────────────────────────────────

func _compute_walkable(cell: Vector3i) -> bool:
	if not BlockRegistry.is_solid(_block_id(cell.x, cell.y, cell.z)):
		return false
	for k in range(1, CLEARANCE + 1):
		var above := Vector3i(cell.x, cell.y + k, cell.z)
		if BlockRegistry.is_solid(_block_id(above.x, above.y, above.z)):
			return false
		if PlacedEntityRegistry.occupies(above):
			return false
	return true


## Real block where a chunk exists; deterministic generated block elsewhere.
func _block_id(wx: int, wy: int, wz: int) -> int:
	@warning_ignore("integer_division")
	if WorldData.chunk_exists(wx / 16, wy / 16, wz / 16):
		return WorldData.get_block(wx, wy, wz)
	return WorldGenerator.get_generated_block_id(wx, wy, wz)


# ── A* core ───────────────────────────────────────────────────────────────────

const _DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const _DIAGS: Array[Vector2i] = [Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]

func _astar(start: Vector3i, goal: Vector3i, max_nodes: int, adjacent_ok: bool) -> Array[Vector3i]:
	var empty: Array[Vector3i] = []
	if not is_walkable(start):
		return empty
	if not adjacent_ok and not is_walkable(goal):
		return empty
	if start == goal:
		var trivial: Array[Vector3i] = [start]
		return trivial

	# Binary min-heap of [f, tie, cell]; g + came-from maps.
	var heap: Array = []
	var g: Dictionary = { start: 0.0 }
	var came: Dictionary = {}
	var closed: Dictionary = {}
	var tie := 0
	_heap_push(heap, [_heuristic(start, goal), tie, start])

	var expanded := 0
	while not heap.is_empty():
		var top: Array = _heap_pop(heap)
		var current: Vector3i = top[2]
		if closed.has(current):
			continue
		closed[current] = true
		expanded += 1
		_nodes_expanded_total += 1

		if current == goal or (adjacent_ok and _lateral_adjacent(current, goal)):
			return _reconstruct(came, current)
		if expanded >= max_nodes:
			return empty

		var g_cur: float = g[current]
		for dir: Vector2i in _DIRS:
			var nx := current.x + dir.x
			var nz := current.z + dir.y
			# At most one walkable floor exists among y-1/y/y+1 in a column
			# (a walkable floor's clearance forbids another directly above).
			for dy: int in [0, 1, -1]:
				var neighbor := Vector3i(nx, current.y + dy, nz)
				if closed.has(neighbor) or not is_walkable(neighbor):
					continue
				var step_cost := COST_LATERAL
				if dy > 0:
					step_cost = COST_UP
				elif dy < 0:
					step_cost = COST_DOWN
				var g_new := g_cur + step_cost
				if g.has(neighbor) and g_new >= float(g[neighbor]):
					break
				g[neighbor] = g_new
				came[neighbor] = current
				tie += 1
				_heap_push(heap, [g_new + _heuristic(neighbor, goal), tie, neighbor])
				break   # one floor per column — stop scanning dy

		# Flat diagonals (no corner cutting): destination at the SAME level,
		# and both cardinal in-between cells walkable.
		for dir: Vector2i in _DIAGS:
			var neighbor := Vector3i(current.x + dir.x, current.y, current.z + dir.y)
			if closed.has(neighbor) or not is_walkable(neighbor):
				continue
			if not is_walkable(Vector3i(current.x + dir.x, current.y, current.z)):
				continue
			if not is_walkable(Vector3i(current.x, current.y, current.z + dir.y)):
				continue
			var g_new := g_cur + COST_DIAGONAL
			if g.has(neighbor) and g_new >= float(g[neighbor]):
				continue
			g[neighbor] = g_new
			came[neighbor] = current
			tie += 1
			_heap_push(heap, [g_new + _heuristic(neighbor, goal), tie, neighbor])
	return empty


## Octile distance in XZ (diagonals allowed) + vertical Manhattan. Admissible:
## never overestimates the true cost under the step rules above.
func _heuristic(a: Vector3i, b: Vector3i) -> float:
	var dx := absi(a.x - b.x)
	var dz := absi(a.z - b.z)
	var dy := absi(a.y - b.y)
	return float(maxi(dx, dz)) + 0.414 * float(mini(dx, dz)) + 0.9 * float(dy)


func _lateral_adjacent(a: Vector3i, b: Vector3i) -> bool:
	return absi(a.x - b.x) + absi(a.z - b.z) == 1 and absi(a.y - b.y) <= 1


func _reconstruct(came: Dictionary, current: Vector3i) -> Array[Vector3i]:
	var path: Array[Vector3i] = [current]
	while came.has(current):
		current = came[current]
		path.push_front(current)
	return path


# ── Binary heap (min on element[0], tie-break element[1]) ─────────────────────

func _heap_push(heap: Array, item: Array) -> void:
	heap.append(item)
	var i := heap.size() - 1
	while i > 0:
		@warning_ignore("integer_division")
		var parent := (i - 1) / 2
		if _heap_less(heap[i], heap[parent]):
			var tmp = heap[i]
			heap[i] = heap[parent]
			heap[parent] = tmp
			i = parent
		else:
			break


func _heap_pop(heap: Array) -> Array:
	var top: Array = heap[0]
	var last = heap.pop_back()
	if not heap.is_empty():
		heap[0] = last
		var i := 0
		var n := heap.size()
		while true:
			var smallest := i
			var l := i * 2 + 1
			var r := i * 2 + 2
			if l < n and _heap_less(heap[l], heap[smallest]):
				smallest = l
			if r < n and _heap_less(heap[r], heap[smallest]):
				smallest = r
			if smallest == i:
				break
			var tmp = heap[i]
			heap[i] = heap[smallest]
			heap[smallest] = tmp
			i = smallest
	return top


func _heap_less(a: Array, b: Array) -> bool:
	if float(a[0]) != float(b[0]):
		return float(a[0]) < float(b[0])
	return int(a[1]) < int(b[1])


# ── Invalidation (doc 32: rebuild lazily on change) ──────────────────────────

func _on_chunk_dirtied(cx: int, cy: int, cz: int) -> void:
	_invalidate_chunk(Vector3i(cx, cy, cz))


func _on_occupancy_changed(box_min: Vector3i, box_size: Vector3i) -> void:
	# Occupancy affects walkability of cells whose CLEARANCE intersects the box,
	# so extend down by the clearance height before mapping to chunks.
	var lo := Vector3i(box_min.x, maxi(box_min.y - CLEARANCE, 0), box_min.z)
	var hi := box_min + box_size - Vector3i.ONE
	for cx in range(lo.x >> 4, (hi.x >> 4) + 1):
		for cy in range(lo.y >> 4, (hi.y >> 4) + 1):
			for cz in range(lo.z >> 4, (hi.z >> 4) + 1):
				_invalidate_chunk(Vector3i(cx, cy, cz))


func _invalidate_chunk(chunk_key: Vector3i) -> void:
	_walkable_cache.erase(chunk_key)
	if _path_cache.is_empty():
		return
	var stale: Array = []
	for key in _path_cache:
		var chunks: Dictionary = (_path_cache[key] as Dictionary)["chunks"]
		if chunks.has(chunk_key):
			stale.append(key)
	for key in stale:
		_path_cache.erase(key)


func _path_chunk_set(path: Array[Vector3i]) -> Dictionary:
	var chunks: Dictionary = {}
	for cell in path:
		chunks[Vector3i(cell.x >> 4, cell.y >> 4, cell.z >> 4)] = true
	return chunks
