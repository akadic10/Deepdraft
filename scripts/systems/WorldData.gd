extends Node

# All "/" between two ints here are intentional world→chunk coordinate divisions.
# Suppress the integer_division warning file-wide.
@warning_ignore_start("integer_division")

## Owns the entire block data matrix for the world.
##
## ALL block reads and writes anywhere in the codebase must go through this
## autoload — never access Chunk.blocks directly from outside this script.
##
## Thread model:
##   - submit_chunk() inserts a whole chunk atomically (set_block's first
##     edit in a chunk; tests also fill columns through WorldGenerator).
##   - Game logic runs on the main thread and calls get_block() / set_block().
##   - _mutex guards the _chunks dictionary. Once a Chunk object is
##     retrieved from the dictionary, its PackedByteArray can be read/written
##     without holding the lock — each chunk is only written by one party
##     at a time (generator pre-submit, game logic post-submit).
##
## Signal note:
##   chunk_dirtied is emitted on the main thread (submit_chunk defers it);
##   listeners such as NavGrid and TaskManager still connect with
##   CONNECT_DEFERRED:
##
##     WorldData.chunk_dirtied.connect(_on_chunk_dirtied, CONNECT_DEFERRED)

const CHUNK_SIZE:   int = 16
const WorldSize = preload("res://scripts/systems/WorldSize.gd")
## The world size: use these everywhere instead of typed numbers.
const WORLD_SIZE_X: int = WorldSize.WORLD_SIZE_X
const WORLD_SIZE_Y: int = WorldSize.WORLD_SIZE_Y
const WORLD_SIZE_Z: int = WorldSize.WORLD_SIZE_Z
## Highest block row; also the slice "off" value (SliceController.MAX_SLICE_Y).
const MAX_Y: int = WorldSize.MAX_Y

## Emitted whenever a chunk's contents change and its mesh needs rebuilding.
## May fire from the generator thread — connect with CONNECT_DEFERRED.
signal chunk_dirtied(cx: int, cy: int, cz: int)
## Exact main-thread edits, separate from generation/mesh streaming dirtiness.
signal block_changed(position: Vector3i, old_id: int, new_id: int)

var _chunks: Dictionary = {}   # Vector3i(cx, cy, cz)  →  Chunk
var _mutex:  Mutex
var _edits: Dictionary = {} # Main-thread edits, reapplied to chunks submitted later.
var _edit_batch_depth := 0
var _batched_dirty_chunks: Dictionary = {}


func _ready() -> void:
	_mutex = Mutex.new()
	print("WorldData: ready.")


# ── Bulk write (WorldGenerator path) ─────────────────────────────────────────

## Called by WorldGenerator after it has filled an entire chunk on its
## background thread. Atomically inserts the chunk and notifies the renderer.
## This is the only safe way to introduce a new chunk from a non-main thread.
func submit_chunk(cx: int, cy: int, cz: int, chunk: Chunk) -> void:
	_mutex.lock()
	for cell: Vector3i in _edits.get(Vector3i(cx,cy,cz), {}):
		chunk.blocks[Chunk.local_index(cell.x % 16,cell.y % 16,cell.z % 16)] = _edits[Vector3i(cx,cy,cz)][cell]
	_chunks[Vector3i(cx, cy, cz)] = chunk
	_mutex.unlock()
	call_deferred("_deferred_emit_chunk_dirtied", cx, cy, cz)

## Runs on the main thread via call_deferred. Safe to emit signals here.
func _deferred_emit_chunk_dirtied(cx: int, cy: int, cz: int) -> void:
	chunk_dirtied.emit(cx, cy, cz)
	_emit_existing_neighbor_dirty(cx + 1, cy, cz)
	_emit_existing_neighbor_dirty(cx - 1, cy, cz)
	_emit_existing_neighbor_dirty(cx, cy + 1, cz)
	_emit_existing_neighbor_dirty(cx, cy - 1, cz)
	_emit_existing_neighbor_dirty(cx, cy, cz + 1)
	_emit_existing_neighbor_dirty(cx, cy, cz - 1)


func _emit_existing_neighbor_dirty(cx: int, cy: int, cz: int) -> void:
	if not chunk_exists(cx, cy, cz):
		return
	chunk_dirtied.emit(cx, cy, cz)


# ── Single-block read/write (main-thread game logic) ─────────────────────────

## Returns the runtime block ID at a world position.
## Ungenerated terrain reads as air; known live water is still overlaid.
## Use get_live_block when a deterministic terrain fallback is required.
func get_block(wx: int, wy: int, wz: int) -> int:
	return WaterManager.live_block(Vector3i(wx,wy,wz), _stored_block(wx,wy,wz))


## Authoritative terrain with deterministic fallback for unstreamed columns.
## Water geometry queries use this raw read to avoid querying themselves.
func get_terrain_block(wx: int, wy: int, wz: int) -> int:
	if chunk_exists(wx >> 4,wy >> 4,wz >> 4): return _stored_block(wx,wy,wz)
	return WorldGenerator.get_generated_block_id(wx,wy,wz)


func get_live_block(wx: int, wy: int, wz: int) -> int:
	return WaterManager.live_block(Vector3i(wx,wy,wz),get_terrain_block(wx,wy,wz))


func _stored_block(wx: int, wy: int, wz: int) -> int:
	if not _in_bounds(wx, wy, wz):
		return BlockRegistry.AIR_ID

	var key := _chunk_key(wx, wy, wz)
	_mutex.lock()
	var chunk: Chunk = _chunks.get(key, null)
	_mutex.unlock()

	if chunk == null:
		return BlockRegistry.AIR_ID

	return chunk.blocks[Chunk.local_index(wx % CHUNK_SIZE, wy % CHUNK_SIZE, wz % CHUNK_SIZE)]


## Writes a runtime block ID at a world position and marks the chunk dirty.
## Call only from the main thread during normal gameplay (mining, building).
## For worldgen bulk writes, use submit_chunk() instead.
func set_block(wx: int, wy: int, wz: int, id: int) -> void:
	if not _in_bounds(wx, wy, wz):
		push_warning("WorldData.set_block: out-of-bounds (%d, %d, %d)" % [wx, wy, wz])
		return

	# Bedrock Protocol (Hard Rule 1, 12_world_grid.md): the bedrock rows
	# (Y 0..BEDROCK_MAX_Y) are never modified by any gameplay action. Mining
	# already re-validates at its own write sites; enforcing it here too
	# closes the rule permanently for every other present and future
	# set_block caller (furniture, item drops, interior carving, …).
	if wy <= WorldGenerator.BEDROCK_MAX_Y:
		push_error("WorldData.set_block: bedrock write rejected at (%d, %d, %d) — Y <= %d is protected." % [
			wx, wy, wz, WorldGenerator.BEDROCK_MAX_Y])
		return

	var chunk := get_chunk_if_exists(wx/16,wy/16,wz/16)
	if chunk == null:
		chunk = Chunk.new()
		for x in 16:
			for y in 16:
				for z in 16:
					chunk.blocks[Chunk.local_index(x,y,z)] = WorldGenerator.get_generated_block_id((wx/16)*16+x,(wy/16)*16+y,(wz/16)*16+z)
		submit_chunk(wx/16,wy/16,wz/16,chunk)
	var old_id: int = chunk.blocks[Chunk.local_index(wx % CHUNK_SIZE, wy % CHUNK_SIZE, wz % CHUNK_SIZE)]
	var cell := Vector3i(wx,wy,wz)
	var original := WorldGenerator.get_generated_block_id(wx,wy,wz)
	_mutex.lock()
	var chunk_key := _chunk_key(wx,wy,wz)
	if WorldGenerator.is_maps_ready() and id == original:
		if _edits.has(chunk_key):
			_edits[chunk_key].erase(cell)
			if _edits[chunk_key].is_empty(): _edits.erase(chunk_key)
	else:
		if not _edits.has(chunk_key): _edits[chunk_key] = {}
		_edits[chunk_key][cell] = id
	_mutex.unlock()
	chunk.blocks[Chunk.local_index(wx % CHUNK_SIZE, wy % CHUNK_SIZE, wz % CHUNK_SIZE)] = id
	mark_chunk_dirty(wx / CHUNK_SIZE, wy / CHUNK_SIZE, wz / CHUNK_SIZE)
	if old_id != id:
		block_changed.emit(Vector3i(wx,wy,wz),old_id,id)


## Returns the Chunk at chunk coordinates, lazy-creating an empty one if absent.
## Call only from the main thread.
func get_chunk(cx: int, cy: int, cz: int) -> Chunk:
	var key := Vector3i(cx, cy, cz)
	_mutex.lock()
	if not _chunks.has(key):
		_chunks[key] = Chunk.new()
	var chunk: Chunk = _chunks[key]
	_mutex.unlock()
	return chunk


## Returns the Chunk at chunk coordinates, or null if it has not been generated.
## Unlike get_chunk(), this never creates empty chunks. Render streaming uses this
## so panning the camera does not accidentally allocate distant air chunks.
func get_chunk_if_exists(cx: int, cy: int, cz: int) -> Chunk:
	var key := Vector3i(cx, cy, cz)
	_mutex.lock()
	var chunk: Chunk = _chunks.get(key, null)
	_mutex.unlock()
	return chunk


## Returns true if a generated chunk exists at chunk coordinates.
## Does not create a chunk.
func chunk_exists(cx: int, cy: int, cz: int) -> bool:
	var key := Vector3i(cx, cy, cz)
	_mutex.lock()
	var exists := _chunks.has(key)
	_mutex.unlock()
	return exists


## Main-thread invalidation: marks the chunk immediately and emits chunk_dirtied,
## coalescing repeated notifications while a synchronous edit batch is open.
func mark_chunk_dirty(cx: int, cy: int, cz: int) -> void:
	var key := Vector3i(cx, cy, cz)
	_mutex.lock()
	var chunk: Chunk = _chunks.get(key, null)
	_mutex.unlock()
	if chunk != null:
		chunk.is_dirty = true
	if _edit_batch_depth > 0:
		_batched_dirty_chunks[key] = true
		return
	chunk_dirtied.emit(cx, cy, cz)


## Main-thread bulk restore boundary. Exact block_changed notifications still
## fire for every real edit; repeated mesh/nav invalidations coalesce per chunk.
## No frame may be yielded between begin/end. Nested callers share the batch.
func begin_edit_batch() -> void:
	_edit_batch_depth += 1


func end_edit_batch() -> void:
	assert(_edit_batch_depth > 0, "WorldData edit batch ended without begin")
	_edit_batch_depth -= 1
	if _edit_batch_depth > 0:
		return
	var dirty := _batched_dirty_chunks.keys()
	_batched_dirty_chunks.clear()
	for key: Vector3i in dirty:
		chunk_dirtied.emit(key.x, key.y, key.z)


## Load boundary: discard every materialised chunk before regenerating the
## deterministic base world. The generator thread must be stopped first.
func clear_world() -> void:
	WaterManager.reset()
	_edit_batch_depth = 0
	_batched_dirty_chunks.clear()
	_mutex.lock()
	_chunks.clear()
	_edits.clear()
	_mutex.unlock()


## Current differences from generated terrain, with one value per position.
## No origin/ownership metadata: all terrain writers share this state.
func has_terrain_override(cell: Vector3i) -> bool:
	return _edits.get(Vector3i(cell.x>>4,cell.y>>4,cell.z>>4),{}).has(cell)

func has_solid_override(cell: Vector3i) -> bool:
	return BlockRegistry.is_solid(int(_edits.get(Vector3i(cell.x>>4,cell.y>>4,cell.z>>4),{}).get(cell,0)))

## THE removed-terrain record: generated terrain that is now air (mined, cleared or
## deconstructed). Derived from the overrides, so saves and live edits agree.
func is_removed_terrain(cell: Vector3i) -> bool:
	var changes: Dictionary = _edits.get(Vector3i(cell.x>>4,cell.y>>4,cell.z>>4),{})
	return changes.has(cell) and not BlockRegistry.is_solid(int(changes[cell]))

func removed_terrain_count() -> int:
	var count := 0
	for changes: Dictionary in _edits.values():
		for id in changes.values():
			if not BlockRegistry.is_solid(int(id)): count += 1
	return count

## THE visible-surface rule: a column's surface clamped to the slice plane, then
## stepped down past cut cells. `cut` holds the caller's extra cut cells (plans,
## cave reveals); `count_removed` also steps past removed terrain (main thread
## only). Returns -1 when the column is empty or fully cut away.
func visible_top_y(x: int, z: int, surface_y: int, slice_y: int, cut: Dictionary, count_removed := false) -> int:
	if surface_y < 0:
		return -1
	var y := mini(surface_y, slice_y)
	while y >= 0 and (cut.has(Vector3i(x, y, z)) or (count_removed and is_removed_terrain(Vector3i(x, y, z)))):
		y -= 1
	return y

func terrain_overrides() -> Dictionary:
	var result := {}
	for changes: Dictionary in _edits.values(): result.merge(changes)
	return result

## Columns of chunks (chunk x, z) holding any override; renderers rebuild per column.
func override_columns() -> Array[Vector2i]:
	var seen := {}
	for key: Vector3i in _edits.keys(): seen[Vector2i(key.x, key.z)] = true
	var result: Array[Vector2i] = []
	result.assign(seen.keys())
	return result

## Every override in one column of chunks, all heights: cell -> runtime id.
func column_overrides(cx: int, cz: int) -> Dictionary:
	var result := {}
	for cy in range(WORLD_SIZE_Y >> 4):
		var changes: Dictionary = _edits.get(Vector3i(cx, cy, cz), {})
		if not changes.is_empty(): result.merge(changes)
	return result

func serialize_edits(solid_only := false) -> Array:
	var result: Array = []
	for changes: Dictionary in _edits.values():
		for cell: Vector3i in changes:
			var id := int(changes[cell])
			if not solid_only or BlockRegistry.is_solid(id):
				result.append({"cell":[cell.x,cell.y,cell.z],"block":String(BlockRegistry.get_key(id))})
	result.sort_custom(func(a: Dictionary,b: Dictionary):
		for axis in 3:
			if a.cell[axis]!=b.cell[axis]: return a.cell[axis]<b.cell[axis]
		return false)
	return result

func serialize_solid_edits() -> Array:
	return serialize_edits(true)

func restore_terrain(state: Dictionary) -> void:
	begin_edit_batch()
	for entry: Dictionary in state.edits:
		var cell := Vector3i(entry.cell[0],entry.cell[1],entry.cell[2])
		set_block(cell.x,cell.y,cell.z,BlockRegistry.get_id(entry.block))
	end_edit_batch()


# ── Helpers ───────────────────────────────────────────────────────────────────

func _chunk_key(wx: int, wy: int, wz: int) -> Vector3i:
	return Vector3i(wx / CHUNK_SIZE, wy / CHUNK_SIZE, wz / CHUNK_SIZE)


func _get_or_create_chunk(wx: int, wy: int, wz: int) -> Chunk:
	return get_chunk(wx / CHUNK_SIZE, wy / CHUNK_SIZE, wz / CHUNK_SIZE)


func _in_bounds(wx: int, wy: int, wz: int) -> bool:
	return wx >= 0 and wx < WORLD_SIZE_X \
		and wy >= 0 and wy < WORLD_SIZE_Y \
		and wz >= 0 and wz < WORLD_SIZE_Z
