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
##   - WorldGenerator runs on a background Thread and calls submit_chunk()
##     to hand completed chunks to WorldData atomically.
##   - WorldRenderer and game logic run on the main thread and call
##     get_block() / set_block().
##   - _mutex guards the _chunks dictionary. Once a Chunk object is
##     retrieved from the dictionary, its PackedByteArray can be read/written
##     without holding the lock — each chunk is only written by one party
##     at a time (generator pre-submit, game logic post-submit).
##
## Signal note:
##   WorldRenderer MUST connect to chunk_dirtied with CONNECT_DEFERRED so
##   mesh rebuilds always execute on the main thread, even when the signal
##   fires from the generator's background thread:
##
##     WorldData.chunk_dirtied.connect(_on_chunk_dirtied, CONNECT_DEFERRED)

const CHUNK_SIZE:   int = 16
const WORLD_SIZE_X: int = 1024
const WORLD_SIZE_Y: int = 128
const WORLD_SIZE_Z: int = 1024

## Emitted whenever a chunk's contents change and its mesh needs rebuilding.
## May fire from the generator thread — connect with CONNECT_DEFERRED.
signal chunk_dirtied(cx: int, cy: int, cz: int)

var _chunks: Dictionary = {}   # Vector3i(cx, cy, cz)  →  Chunk
var _mutex:  Mutex


func _ready() -> void:
	_mutex = Mutex.new()
	print("WorldData: ready.")


# ── Bulk write (WorldGenerator path) ─────────────────────────────────────────

## Called by WorldGenerator after it has filled an entire chunk on its
## background thread. Atomically inserts the chunk and notifies the renderer.
## This is the only safe way to introduce a new chunk from a non-main thread.
func submit_chunk(cx: int, cy: int, cz: int, chunk: Chunk) -> void:
	_mutex.lock()
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
## Returns BlockRegistry.AIR_ID for any out-of-bounds coordinate or
## coordinates within an ungenerated chunk.
func get_block(wx: int, wy: int, wz: int) -> int:
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

	var chunk := _get_or_create_chunk(wx, wy, wz)
	chunk.blocks[Chunk.local_index(wx % CHUNK_SIZE, wy % CHUNK_SIZE, wz % CHUNK_SIZE)] = id
	# Keep the buried-chunk optimisation honest: has_void is baked at
	# generation time and was never updated afterwards, so carving air into a
	# previously all-solid chunk left it flagged void-free and eligible for
	# mesh skipping (WorldRenderer._is_buried). Setting the flag on any air
	# write keeps it conservative-correct; solid writes leave it alone (a
	# stale true only costs a skipped optimisation, never a wrong skip).
	if id == BlockRegistry.AIR_ID:
		chunk.has_void = true
	mark_chunk_dirty(wx / CHUNK_SIZE, wy / CHUNK_SIZE, wz / CHUNK_SIZE)


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


## Returns true if the chunk at (cx, cy, cz) contains any void block, OR does
## not exist yet (a missing chunk is treated as pure air). Does NOT create a
## chunk. Used by WorldRenderer to detect fully-buried interior chunks whose
## six neighbours are all solid — those can be skipped entirely when meshing.
func chunk_has_void(cx: int, cy: int, cz: int) -> bool:
	var key := Vector3i(cx, cy, cz)
	_mutex.lock()
	var chunk: Chunk = _chunks.get(key, null)
	_mutex.unlock()
	if chunk == null:
		return true
	return chunk.has_void


## Marks a chunk as dirty and emits chunk_dirtied.
## Used by set_block and any system that modifies block data directly.
func mark_chunk_dirty(cx: int, cy: int, cz: int) -> void:
	var key := Vector3i(cx, cy, cz)
	_mutex.lock()
	var chunk: Chunk = _chunks.get(key, null)
	_mutex.unlock()
	if chunk != null:
		chunk.is_dirty = true
	chunk_dirtied.emit(cx, cy, cz)


## Load boundary: discard every materialised chunk before regenerating the
## deterministic base world. The generator thread must be stopped first.
func clear_world() -> void:
	_mutex.lock()
	_chunks.clear()
	_mutex.unlock()


# ── Helpers ───────────────────────────────────────────────────────────────────

func _chunk_key(wx: int, wy: int, wz: int) -> Vector3i:
	return Vector3i(wx / CHUNK_SIZE, wy / CHUNK_SIZE, wz / CHUNK_SIZE)


func _get_or_create_chunk(wx: int, wy: int, wz: int) -> Chunk:
	return get_chunk(wx / CHUNK_SIZE, wy / CHUNK_SIZE, wz / CHUNK_SIZE)


func _in_bounds(wx: int, wy: int, wz: int) -> bool:
	return wx >= 0 and wx < WORLD_SIZE_X \
		and wy >= 0 and wy < WORLD_SIZE_Y \
		and wz >= 0 and wz < WORLD_SIZE_Z
