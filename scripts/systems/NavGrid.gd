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
const APPROACH_PROBE_NODES := 64     # cheaply reject a sealed destination pocket

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
signal ladder_routes_changed
var ladder_revision := 0
var _ladders: Dictionary = {}
var _rungs: Dictionary = {}
var navigation_revision := 0
var _chunk_revisions: Dictionary = {}
enum ProbeResult { SEARCHING, REACHABLE, UNREACHABLE }


## Rungs are explicit traversal supports, never solid terrain/walkable floors.
func set_ladder(id: int, base: Vector3i, height: int, facing: Vector3i, speed: float, closing := false) -> void:
	_ladders[id] = {"base":base, "height":height, "facing":facing, "speed":speed, "closing":closing}
	_rebuild_ladders()


func remove_ladder(id: int) -> void:
	_ladders.erase(id)
	_rebuild_ladders()


func _rebuild_ladders() -> void:
	navigation_revision += 1
	_rungs.clear()
	for id: int in _ladders:
		var ladder: Dictionary = _ladders[id]
		for y in range(ladder.base.y, ladder.base.y + ladder.height + 1):
			_rungs[Vector3i(ladder.base.x, y, ladder.base.z)] = id
	_path_cache.clear()
	ladder_revision += 1
	ladder_routes_changed.emit()


func ladder_at(cell: Vector3i) -> Dictionary:
	return _ladders.get(_rungs.get(cell, -1), {})


func clear_for_climbing(cell: Vector3i) -> bool:
	if cell.x < 0 or cell.z < 0 or cell.x >= WorldData.WORLD_SIZE_X or cell.z >= WorldData.WORLD_SIZE_Z \
			or cell.y < 1 or cell.y + CLEARANCE >= WorldData.WORLD_SIZE_Y: return false
	for k in range(1, CLEARANCE + 1):
		var above := cell + Vector3i(0, k, 0)
		if _block_id(above.x, above.y, above.z) != BlockRegistry.AIR_ID or PlacedEntityRegistry.occupies(above): return false
	return true


func is_navigable(cell: Vector3i) -> bool:
	return is_walkable(cell) or (_rungs.has(cell) and clear_for_climbing(cell))


func _ladder_neighbors(cell: Vector3i, start: Vector3i, goal: Vector3i) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	if _rungs.is_empty(): return result
	for offset: Vector3i in [Vector3i.UP, Vector3i.DOWN, Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK]:
		var next := cell + offset
		var id: int = _rungs.get(cell, _rungs.get(next, -1))
		if id < 0: continue
		var route: Dictionary = _ladders[id]
		# Closing routes allow evacuation and explicit maintenance destinations.
		if route.closing and _rungs.get(start, -1) != id and _rungs.get(goal, -1) != id: continue
		if offset.y != 0:
			if _rungs.get(cell, -1) != id or _rungs.get(next, -1) != id: continue
		elif not (is_walkable(cell) or is_walkable(next)): continue
		if is_navigable(next): result.append(next)
	return result


func _ready() -> void:
	WorldData.chunk_dirtied.connect(_on_chunk_dirtied, CONNECT_DEFERRED)
	WaterManager.levels_changed.connect(_on_water_changed)
	PlacedEntityRegistry.occupancy_changed.connect(_on_occupancy_changed)
	print("NavGrid: ready.")

func _on_water_changed(cells: Array) -> void:
	var chunks: Dictionary = {}
	for cell: Vector3i in cells:
		# A reservoir can rise through several vertical chunks.
		for y in 8: chunks[Vector3i(cell.x >> 4,y,cell.z >> 4)] = true
	for key: Vector3i in chunks: _on_chunk_dirtied(key.x,key.y,key.z)


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


## Synchronous diagnostic probe. Gameplay scheduling uses advance_reachability
## so exhausting a single wake never becomes a false unreachable result. True if
## `goal` or any cell laterally adjacent to it is reached within the node cap.
## A capped failure returns false. The caller
## may pass its configured cap (task_config.json probe_node_cap); the default
## is the doc-32 value.
func probe_reachable(start: Vector3i, goal: Vector3i, node_cap: int = PROBE_NODE_CAP) -> bool:
	_probes_run += 1
	return not _astar(start, goal, node_cap, true).is_empty()


## Scheduler searches retain their frontier when a wake runs out of time or
## nodes. SEARCHING is not an unreachable result. The overall limit matches
## ordinary walking; changed terrain, occupancy, ladders or endpoints restart.
## exact_goals optionally supplies alternative working positions for one search.
func advance_reachability(query: Dictionary, start: Vector3i, goal: Vector3i,
		node_budget: int, deadline_usec: int, adjacent_ok := true, exact_goals: Dictionary = {}) -> int:
	adjacent_ok = adjacent_ok and exact_goals.is_empty()
	if query.is_empty() or query.start != start or query.goal != goal or query.adjacent_ok != adjacent_ok \
			or query.get("goals", {}) != exact_goals or not search_is_current(query):
		query.clear()
		query.merge(_new_search(start, goal, adjacent_ok, true))
		if not exact_goals.is_empty():
			query["goals"] = exact_goals
			var lo := goal
			var hi := goal
			for cell: Vector3i in exact_goals:
				lo = Vector3i(mini(lo.x,cell.x),mini(lo.y,cell.y),mini(lo.z,cell.z))
				hi = Vector3i(maxi(hi.x,cell.x),maxi(hi.y,cell.y),maxi(hi.z,cell.z))
				_remember_search_area(query,cell)
			query["goal_min"] = lo
			query["goal_max"] = hi
			if not query.heap.is_empty(): query.heap[0][0] = _search_heuristic(query,start)
		query["approach_query"] = _new_approach_probe(start, goal, adjacent_ok, exact_goals)
		query["approach_nodes"] = 0
		_probes_run += 1
	if int(query.status) != ProbeResult.SEARCHING: return int(query.status)
	# A small reverse search catches enclosed pickup/work areas before the
	# forward search explores a large open plateau. Only open (symmetric) ladder
	# graphs use it; closing routes retain the ordinary forward permission check.
	var approach: Dictionary = query.get("approach_query", {})
	if not approach.is_empty():
		var before: int = approach.expanded
		_advance_search(approach, mini(maxi(node_budget, 1), APPROACH_PROBE_NODES-before), deadline_usec)
		var used: int = int(approach.expanded)-before
		query.chunks.merge(approach.chunks)
		query.expanded += used
		query.approach_nodes += used
		node_budget -= used
		if int(approach.status) != ProbeResult.SEARCHING:
			query.status = approach.status
			query.path = approach.path
			query.path.reverse()
			query.erase("approach_query")
			return int(query.status)
		if int(approach.expanded) >= APPROACH_PROBE_NODES:
			query.erase("approach_query")
		else:
			return ProbeResult.SEARCHING
	var remaining := DEFAULT_MAX_NODES - (int(query.expanded) - int(query.approach_nodes))
	_advance_search(query, mini(maxi(node_budget, 0), remaining), deadline_usec)
	if int(query.status) == ProbeResult.SEARCHING and int(query.expanded) - int(query.approach_nodes) >= DEFAULT_MAX_NODES:
		query.status = ProbeResult.UNREACHABLE
	return int(query.status)


## Cache only a current exact proof for immediate worker execution.
func remember_reachable_path(query: Dictionary) -> void:
	if int(query.get("status", ProbeResult.SEARCHING)) != ProbeResult.REACHABLE \
			or bool(query.adjacent_ok) or not search_is_current(query): return
	var path: Array[Vector3i] = query.path
	if path.is_empty() or path.front() != query.start: return
	var endpoint: Vector3i = path.back()
	if endpoint != query.goal and not query.get("goals", {}).has(endpoint): return
	_path_cache[[query.start, endpoint]] = {"path":path,
		"expires":Time.get_ticks_msec()+PATH_CACHE_TTL_MSEC, "chunks":query.chunks.duplicate()}


## Streaming/mining elsewhere must not repeatedly restart a long route.
## Record every examined cell's clearance/neighbour chunks, including walls
## that were rejected, so opening a previously closed approach still restarts.
func search_is_current(query: Dictionary) -> bool:
	if query.is_empty() or int(query.ladder_revision) != ladder_revision: return false
	if int(query.revision) == navigation_revision: return true
	for chunk: Vector3i in query.chunks:
		if int(query.chunks[chunk]) != int(_chunk_revisions.get(chunk, 0)): return false
	query.revision = navigation_revision
	return true


func _remember_search_area(query: Dictionary, cell: Vector3i) -> void:
	if not bool(query.track_changes): return
	var lo := cell - Vector3i.ONE
	var hi := cell + Vector3i(1, CLEARANCE+1, 1)
	for cx in range(lo.x >> 4, (hi.x >> 4)+1):
		for cy in range(lo.y >> 4, (hi.y >> 4)+1):
			for cz in range(lo.z >> 4, (hi.z >> 4)+1):
				var key := Vector3i(cx,cy,cz)
				if not query.chunks.has(key): query.chunks[key] = int(_chunk_revisions.get(key,0))


func _new_approach_probe(start: Vector3i, goal: Vector3i, adjacent_ok := true, exact_goals: Dictionary = {}) -> Dictionary:
	for route: Dictionary in _ladders.values():
		if bool(route.closing): return {}
	var query := _new_search(goal, start, false, true)
	query.heap.clear()
	query.g.clear()
	query.status = ProbeResult.SEARCHING
	# Every cell that satisfies the forward probe is a reverse-search root.
	var roots: Array[Vector3i] = [goal]
	if not exact_goals.is_empty():
		roots.assign(exact_goals.keys())
	elif adjacent_ok:
		for offset: Vector2i in _DIRS:
			for dy in [-1,0,1]: roots.append(goal + Vector3i(offset.x,dy,offset.y))
	for cell: Vector3i in roots:
		if not is_navigable(cell): continue
		query.g[cell] = 0.0
		query.tie += 1
		_heap_push(query.heap, [_heuristic(cell,start), query.tie, cell])
	query["route_start"] = start
	query["route_goal"] = goal
	if query.heap.is_empty(): query.status = ProbeResult.UNREACHABLE
	return query


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


func clear_runtime_state() -> void:
	_chunk_revisions.clear()
	_ladders.clear()
	_rebuild_ladders()
	_walkable_cache.clear()
	_path_cache.clear()
	_paths_served = 0
	_path_cache_hits = 0
	_probes_run = 0
	_nodes_expanded_total = 0


# ── Walkability ───────────────────────────────────────────────────────────────

func _compute_walkable(cell: Vector3i) -> bool:
	if not BlockRegistry.is_solid(_block_id(cell.x, cell.y, cell.z)):
		return false
	for k in range(1, CLEARANCE + 1):
		var above := Vector3i(cell.x, cell.y + k, cell.z)
		if _block_id(above.x, above.y, above.z) != BlockRegistry.AIR_ID:
			return false
		if PlacedEntityRegistry.occupies(above):
			return false
	return true


## Real block where a chunk exists; deterministic generated block elsewhere.
func _block_id(wx: int, wy: int, wz: int) -> int:
	return WorldData.get_live_block(wx,wy,wz)


# ── A* core ───────────────────────────────────────────────────────────────────

const _DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const _DIAGS: Array[Vector2i] = [Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]

func _astar(start: Vector3i, goal: Vector3i, max_nodes: int, adjacent_ok: bool) -> Array[Vector3i]:
	var query := _new_search(start, goal, adjacent_ok)
	_advance_search(query, max_nodes, 0)
	var result: Array[Vector3i] = query.path
	return result


func _new_search(start: Vector3i, goal: Vector3i, adjacent_ok: bool, track_changes := false) -> Dictionary:
	# Binary min-heap of [f, tie, cell]; g + came-from maps.
	var heap: Array = []
	var path: Array[Vector3i] = []
	var status := ProbeResult.SEARCHING
	if not is_navigable(start) or (not adjacent_ok and not is_navigable(goal)):
		status = ProbeResult.UNREACHABLE
	else:
		_heap_push(heap, [_heuristic(start, goal), 0, start])
	var query := {"start":start, "goal":goal, "adjacent_ok":adjacent_ok, "heap":heap,
		"g":{start:0.0}, "came":{}, "closed":{}, "tie":0, "expanded":0,
		"status":status, "path":path, "revision":navigation_revision,
		"chunks":{}, "ladder_revision":ladder_revision, "track_changes":track_changes}
	_remember_search_area(query,start)
	_remember_search_area(query,goal)
	return query


func _advance_search(query: Dictionary, node_budget: int, deadline_usec: int) -> void:
	if int(query.status) != ProbeResult.SEARCHING: return
	var start: Vector3i = query.start
	var goal: Vector3i = query.goal
	var heap: Array = query.heap
	var g: Dictionary = query.g
	var came: Dictionary = query.came
	var closed: Dictionary = query.closed
	var goals: Dictionary = query.get("goals", {})
	var slice_nodes := 0
	while not heap.is_empty():
		if slice_nodes >= node_budget or (deadline_usec > 0 and Time.get_ticks_usec() >= deadline_usec): return
		var top: Array = _heap_pop(heap)
		var current: Vector3i = top[2]
		if closed.has(current):
			continue
		closed[current] = true
		_remember_search_area(query,current)
		slice_nodes += 1
		query.expanded += 1
		_nodes_expanded_total += 1

		var reached := goals.has(current) if not goals.is_empty() else \
			(current == goal or (bool(query.adjacent_ok) and _lateral_adjacent(current, goal)))
		if reached:
			query.path = _reconstruct(came, current)
			query.status = ProbeResult.REACHABLE
			return

		var g_cur: float = g[current]
		for neighbor: Vector3i in _ladder_neighbors(current, query.get("route_start",start), query.get("route_goal",goal)):
			if closed.has(neighbor): continue
			var route: Dictionary = ladder_at(current) if _rungs.has(current) else ladder_at(neighbor)
			var g_new := g_cur + (1.0 / maxf(.1, float(route.speed)) if neighbor.y != current.y else COST_LATERAL)
			if g.has(neighbor) and g_new >= float(g[neighbor]): continue
			g[neighbor] = g_new
			came[neighbor] = current
			query.tie += 1
			_heap_push(heap, [g_new + _search_heuristic(query, neighbor), query.tie, neighbor])
		if not is_walkable(current): continue
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
				query.tie += 1
				_heap_push(heap, [g_new + _search_heuristic(query, neighbor), query.tie, neighbor])
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
			query.tie += 1
			_heap_push(heap, [g_new + _search_heuristic(query, neighbor), query.tie, neighbor])
	query.status = ProbeResult.UNREACHABLE


## Multi-position work searches use distance to the goals' bounding box: a
## cheap distance estimate, independent of how many blocks were designated. Every
## goal still requires an exact match; empty space in the box is not success.
func _search_heuristic(query: Dictionary, cell: Vector3i) -> float:
	if query.has("goal_min"):
		var lo: Vector3i = query.goal_min
		var hi: Vector3i = query.goal_max
		return _heuristic(cell,Vector3i(clampi(cell.x,lo.x,hi.x),clampi(cell.y,lo.y,hi.y),clampi(cell.z,lo.z,hi.z)))
	return _heuristic(cell,query.goal)


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

## Main-thread mining commits need fresh floors before the worker snaps or
## pulls its next block. The deferred chunk signal remains the general path.
func refresh_mined_block(block: Vector3i) -> void:
	_on_chunk_dirtied(block.x >> 4,block.y >> 4,block.z >> 4)


func _on_chunk_dirtied(cx: int, cy: int, cz: int) -> void:
	_invalidate_chunk(Vector3i(cx, cy, cz))
	# A floor cell's walkability depends on CLEARANCE air blocks *above* it,
	# which can live in the chunk above the floor's own chunk. The worldgen
	# path (WorldData.submit_chunk) dirties all six neighbours, but the
	# gameplay path (WorldData.set_block → mark_chunk_dirty) dirties only the
	# edited chunk — so a block mined in this chunk's bottom rows must also
	# refresh cached walkability for floors in the chunk below (mirrors the
	# downward CLEARANCE extension in _on_occupancy_changed). Without this,
	# floors exposed near vertical chunk boundaries (y = 15/31/47…) stayed
	# cached unwalkable until an unrelated invalidation.
	if cy > 0:
		_invalidate_chunk(Vector3i(cx, cy - 1, cz))


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
	navigation_revision += 1
	_chunk_revisions[chunk_key] = int(_chunk_revisions.get(chunk_key,0)) + 1
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
