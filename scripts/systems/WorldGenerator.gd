extends Node

# All "/" between two ints in this file are intentional, exact integer divisions
# (world/chunk sizing, centroid averaging). Suppress the integer_division warning
# file-wide rather than annotating each site.
@warning_ignore_start("integer_division")

## Five-phase procedural world generation pipeline.
##
## Call generate(new_seed) once at new-game time. Generation runs on a background
## Thread; the main thread receives completed chunks via the chunk_generated
## signal and builds meshes progressively.
##
## Pipeline phases (from 43_mining_materials.md):
##   1. Build 7 FastNoiseLite instances
##   2. Compute domain map  (2D - mountain / foothill / lowland classification)
##   3. Compute heightmap   (2D - domain-shaped elevation with blended borders)
##   4. Carve lake bodies   (lowland lake + mountain tarn)
##   5. Fill all chunks     (3D - bedrock, water, surface skin, caves, ores, stone)

# -- World dimensions ----------------------------------------------------------
# FULL WORLD: 1024 x 128 x 1024 = 134,217,728 blocks (32,768 chunks).
# 1 engine block = 0.5 m, so the playable boundary is 512 m x 512 m x 64 m.
# (For fast iteration, temporarily drop X/Z to 128 -> ~5 s generation.)
const WORLD_SIZE_X:  int = 1024
const WORLD_SIZE_Y:  int = 128
const WORLD_SIZE_Z:  int = 1024
const CHUNK_SIZE:    int = 16
const CHUNK_COUNT_X: int = WORLD_SIZE_X / CHUNK_SIZE   # 64
const CHUNK_COUNT_Y: int = WORLD_SIZE_Y / CHUNK_SIZE   # 8
const CHUNK_COUNT_Z: int = WORLD_SIZE_Z / CHUNK_SIZE   # 64
const BLOCK_COUNT_REPORT_INTERVAL_COLUMNS: int = 16

# -- Terrain domain classification ---------------------------------------------
const DOMAIN_MOUNTAIN: int = 2   # domain_n > 0.60, mountain shelves
const DOMAIN_VALLEY:   int = 1   # domain_n 0.35-0.60, foothill domain / valley corridor
const DOMAIN_LOWLAND:  int = 0   # domain_n < 0.35, lowland shelf
const DOMAIN_MOUNTAIN_THRESHOLD: float = 0.60
const DOMAIN_VALLEY_THRESHOLD: float = 0.35
const LOWLAND_MACRO_MIN_FRACTION: float = 0.50
const NORTHWEST_MOUNTAIN_EDGE_NOISE: float = 0.18
const SOUTHWEST_BASIN_DOMAIN_PULL: float = 0.30
const SOUTHEAST_FOOTHILL_DOMAIN_BONUS: float = 0.18
const SOUTHEAST_FOOTHILL_MACRO_MIN: float = 0.18
const SOUTHEAST_FOOTHILL_SHELF_2_MIN: float = 0.42
const SOUTHEAST_FOOTHILL_SHELF_3_MIN: float = 0.68
const WORLD_EDGE_BELT_WIDTH: int = 28

# -- Surface elevation ranges (Y in blocks) ------------------------------------
const BEDROCK_MAX_Y: int = 3
const FOUNDATION_ROCK_MAX_Y: int = 11
const MOUNTAIN_MIN: int = 44;  const MOUNTAIN_MAX: int = 115
const VALLEY_CORRIDOR_MIN_Y:   int = 20;  const VALLEY_CORRIDOR_MAX_Y:   int = 27
const LOWLAND_RAW_HEIGHT_MIN_Y:  int = 12;  const LOWLAND_RAW_HEIGHT_MAX_Y:  int = 15
const FOOTHILL_SHELF_MIN_Y: int = 20;  const FOOTHILL_SHELF_MAX_Y: int = 43
const VALLEY_CORRIDOR_CENTER_Z_RATIO: float = 0.43
const VALLEY_CORRIDOR_HALF_WIDTH_RATIO: float = 0.07
const VALLEY_CORRIDOR_WIGGLE_RATIO: float = 0.035
const TERRAIN_MACRO_CELL_SIZE: int = 32
const LOWLAND_SHELF_MIN_Y: int = 12
const LOWLAND_SHELF_MAX_Y: int = 19
const SETTLEMENT_PLAIN_SURFACE_Y: int = 19
const SETTLEMENT_PLAIN_MACRO_THRESHOLD: float = 0.20
const LOWLAND_CAP_GRASS_EDGE_1_WIDTH: int = 4
const LOWLAND_CAP_GRASS_EDGE_2_WIDTH: int = 6
const LOWLAND_CAP_GRASS_EDGE_3_WIDTH: int = 8
const LOWLAND_CAP_GRASS_EDGE_TOTAL_DISTANCE: int = LOWLAND_CAP_GRASS_EDGE_1_WIDTH + LOWLAND_CAP_GRASS_EDGE_2_WIDTH + LOWLAND_CAP_GRASS_EDGE_3_WIDTH
const FOOTHILL_CAP_GRASS_EDGE_1_WIDTH: int = 2
const FOOTHILL_CAP_GRASS_EDGE_2_WIDTH: int = 3
const FOOTHILL_CAP_GRASS_EDGE_3_WIDTH: int = 4
const FOOTHILL_CAP_GRASS_EDGE_TOTAL_DISTANCE: int = FOOTHILL_CAP_GRASS_EDGE_1_WIDTH + FOOTHILL_CAP_GRASS_EDGE_2_WIDTH + FOOTHILL_CAP_GRASS_EDGE_3_WIDTH
const VALLEY_TERRACE_STEP: int = 2
const FOOTHILL_SHELF_HEIGHT: int = 8
const MOUNTAIN_SHELF_HEIGHT: int = 12
const FOOTHILL_EDGE_DETAIL_MAX_DEPTH: int = 2
const MOUNTAIN_EDGE_DETAIL_MAX_DEPTH: int = 3
const PLATEAU_MAX_HEIGHT_RANGE: int = 5
const PLATEAU_MAX_MOUNTAIN_HEIGHT: int = 115
const PLATEAU_MIN_DOMINANT_COLUMNS: int = 768
const PLATEAU_SNAP_DELTA: int = 2
const MATERIAL_MACRO_CELL_SIZE: int = 32
const WATER_BANK_RADIUS: int = 4
const STEEP_SLOPE_ROCK_DELTA: int = 3

# -- Lake / tarn parameters ----------------------------------------------------
# Radii scale with world size so the 128-block test world gets a proportional
# lake. At full 1024x1024 these evaluate to the original 40 and 15.
const LAKE_RADIUS:    int = max(8,  WORLD_SIZE_X / 25)   # 128 / 25 = 5, clamped to 8; 1024 / 25 = 40
const LAKE_DEPTH:     int = 5
const LAKE_WATERLINE: int = 18   # fixed surface elevation of the lowland lake
const LAKE_FLOOR_Y:   int = 11   # water fills the lowland stack from Y12 through Y18
const LAKE_RADIUS_X_SCALE: float = 1.35
const LAKE_RADIUS_Z_SCALE: float = 0.82
const LAKE_SHORE_NOISE: float = 0.18
const LAKE_MACRO_RADIUS_X: int = 4
const LAKE_MACRO_RADIUS_Z: int = 5
const LAKE_MIN_MACRO_CELLS: int = 12

const TARN_RADIUS: int = max(4, WORLD_SIZE_X / 68)       # metrics label; macro tarn no longer uses circular carving
const TARN_FLOOR_Y: int = 47
const TARN_WATERLINE: int = 54

# -- Resource distribution order ----------------------------------------------
# Rarest-first. Placement windows are cached from block_resources.json on the
# main thread before generation starts so the worker never touches registries.
const METAL_RESOURCE_KEYS: Array = [
	&"base:terrain:ore:gold",
	&"base:terrain:ore:silver",
	&"base:terrain:ore:iron",
	&"base:terrain:ore:copper",
	&"base:terrain:ore:tin",
	&"base:terrain:ore:coal",
]

const GEM_RESOURCE_KEYS: Array = [
	&"base:terrain:gem:diamond",
	&"base:terrain:gem:emerald",
	&"base:terrain:gem:sapphire",
	&"base:terrain:gem:ruby",
	&"base:terrain:gem:amethyst",
	&"base:terrain:gem:jade",
]

const SOIL_RESOURCE_KEYS: Array = [
	&"base:terrain:soil:cave",
]
const RESOURCE_PERIMETER_SUPPRESSION_WIDTH: int = 8

# -- Signals -------------------------------------------------------------------
## Emitted from the generator thread each time a chunk is fully filled.
## WorldRenderer MUST connect with CONNECT_DEFERRED - mesh work is main-thread only.
signal chunk_generated(cx: int, cy: int, cz: int)

## Emitted from the generator thread when all chunks are complete.
signal world_complete()

# -- Generation state ----------------------------------------------------------
var world_seed: int = 0

# Seven noise instances - one per logical layer; never reuse across passes.
var noise_ore:      FastNoiseLite   # broad metal vein mask
var noise_gem:      FastNoiseLite   # small gem pocket mask
var noise_cave:     FastNoiseLite   # cave void mask
var noise_soil:     FastNoiseLite   # cave soil patches + surface dirt fraction
var noise_domain:   FastNoiseLite   # broad terrain domain map
var noise_mountain: FastNoiseLite   # mountain ridge detail
var noise_valley:   FastNoiseLite   # valley / lowland floor detail

# 2D column maps  (index: x * WORLD_SIZE_Z + z)
var domain_map:   PackedInt32Array    # DOMAIN_* constant per column
var domain_n_map: PackedFloat32Array  # raw [0,1] domain noise per column (for blend math)
var heightmap:    PackedInt32Array    # surface Y per column
var lowland_cap_grass_band_map: PackedByteArray # 0 = no override, 1/2 = tiered edge rings, 4 = base grass
var lowland_cap_grass_distance_map: PackedInt32Array # -1 = not on the lowland cap, otherwise nearest edge distance
var foothill_cap_grass_band_map: PackedByteArray # 0 = no override, 1/2/3 = tiered edge rings, 4 = base grass
var foothill_cap_grass_distance_map: PackedInt32Array # -1 = not on a foothill cap, otherwise nearest edge distance

# Lake / tarn geometry
var lake_columns: Dictionary = {}   # Vector2i -> true  (lowland lake footprint)
var tarn_columns: Dictionary = {}   # Vector2i -> true  (mountain tarn footprint)
var water_bank_columns: Dictionary = {}  # Vector2i -> true  (near lake/tarn, but not water)
var lake_center:  Vector2i  = Vector2i.ZERO
var tarn_center:  Vector2i  = Vector2i.ZERO
var tarn_waterline: int     = 0

# Pre-cached runtime block IDs - looked up on the main thread before generation
# starts so the background thread never calls BlockRegistry directly.
var _id_void:      int = 0
var _id_bedrock:   int = 0
var _id_water:     int = 0
var _id_rock07:    int = 0
var _id_rock08:    int = 0
var _id_rock09:    int = 0
var _id_rock10:    int = 0
var _id_rock11:    int = 0
var _mountain_rock_ids: Array[int] = [] # shelf 1..6 -> rock06..rock01
var _grass_ids:    Array[int] = []   # [0..7] -> active grass_01..grass_08
var _dirt_ids:     Array[int] = []   # [0..3]  -> dirt_01..dirt_04
var _resource_replaceable_rock_ids: Dictionary = {}
var _metal_windows: Array[Dictionary] = []
var _gem_windows:   Array[Dictionary] = []
var _soil_windows:  Array[Dictionary] = []
var _resource_focus_windows: Array[Dictionary] = []

var _gen_thread: Thread = null
var _request_mutex: Mutex = null
var _column_queue: Array[Vector2i] = []
var _requested_columns: Dictionary = {}   # Vector2i -> true
var _generated_columns: Dictionary = {}   # Vector2i -> true
var _maps_ready: bool = false
var _column_in_flight: bool = false
var _block_spawn_counts: Dictionary = {}  # runtime block ID -> generated count
var _counted_columns: int = 0
var _last_count_report_column: int = 0
var _generation_metrics: Dictionary = {}
var _domain_counts: Dictionary = {}
var _terraced_columns: int = 0
var _plateau_adjusted_columns: int = 0
var _plateau_smoothed_chunks: int = 0
var _startup_started_msec: int = 0
var _maps_ready_msec: int = 0
var _map_precompute_msec: int = 0
var _map_phase_timings: Array[Dictionary] = []
var _column_fill_msec_total: int = 0
var _column_fill_msec_max: int = 0
var _column_fill_count: int = 0
var _column_chunks_submitted: int = 0

## Scratch state shared with WorkerThreadPool group-task workers during the
## parallel map-fill phases. Each worker handles one X column (all Z), writing
## only its own disjoint slice of the destination maps, so concurrent writes to
## these member arrays never touch the same index. Read-only inputs (macro
## grids) and per-column debug accumulators live here so the worker callable
## needs no captured locals. Only valid for the duration of the phase that sets
## them; generation is single-flight, so reuse across phases is safe.
var _hm_macro_heights: PackedInt32Array = PackedInt32Array()
var _hm_macro_count_z: int = 0
var _hm_terraced_col: PackedInt32Array = PackedInt32Array()
var _hm_corridor_count_col: PackedInt32Array = PackedInt32Array()
var _hm_corridor_height_col: PackedInt32Array = PackedInt32Array()

## Cooperative cancel flag. Set true on the main thread (e.g. when the game
## stops) so the worker exits its chunk loop instead of touching members that
## are about to be torn down. Bool read/write is atomic enough for a one-way
## "stop now" signal - we never read it back into logic, only to bail out.
var _abort: bool = false


func _ready() -> void:
	_request_mutex = Mutex.new()
	print("WorldGenerator: ready.")


## Called when the node leaves the tree - i.e. the game is stopping. Signal the
## worker to abort, then JOIN it before the script's members are freed. Without
## this, stopping mid-generation crashes ("Bad address index" as heightmap is
## cleared under the running thread) and leaks the Thread ("destroyed without
## wait_to_finish()").
func _exit_tree() -> void:
	_abort = true
	if _gen_thread != null and _gen_thread.is_started():
		_gen_thread.wait_to_finish()
		_gen_thread = null


# -- Deferred signal helpers (main-thread only) --------------------------------

func _deferred_emit_chunk_generated(cx: int, cy: int, cz: int) -> void:
	chunk_generated.emit(cx, cy, cz)

func _deferred_emit_world_complete() -> void:
	print("WorldGenerator: world_complete signal firing.")
	world_complete.emit()


func _deferred_emit_maps_ready() -> void:
	print("WorldGenerator: terrain maps ready; waiting for chunk column requests.")


func _deferred_print_generation_metrics(snapshot: Dictionary) -> void:
	var domains: Dictionary = snapshot.get("domains", {})
	var heights: Dictionary = snapshot.get("heights", {})
	var surface: Dictionary = snapshot.get("surface", {})
	var shaping: Dictionary = snapshot.get("shaping", {})
	var water: Dictionary = snapshot.get("water", {})
	var candidates: Dictionary = snapshot.get("settlement_candidates", {})
	var macro: Dictionary = snapshot.get("macro", {})

	print("WorldGenerator metrics:")
	print("  domains: mountain %.1f%%, valley %.1f%%, lowland %.1f%%" % [
		domains.get("mountain_pct", 0.0),
		domains.get("valley_pct", 0.0),
		domains.get("lowland_pct", 0.0),
	])
	print("  height: min %d, max %d, avg %.1f" % [
		heights.get("min", 0),
		heights.get("max", 0),
		heights.get("avg", 0.0),
	])
	print("  surface: grass %.1f%%, dirt %.1f%%, rock %.1f%%, water %.1f%%" % [
		surface.get("grass_pct", 0.0),
		surface.get("dirt_pct", 0.0),
		surface.get("rock_pct", 0.0),
		surface.get("water_pct", 0.0),
	])
	var surface_by_domain: Dictionary = surface.get("by_domain", {})
	var mountain_surface: Dictionary = surface_by_domain.get("mountain", {})
	var valley_surface: Dictionary = surface_by_domain.get("valley", {})
	print("  surface domains: mountain rock %.1f%%; valley grass %.1f%% dirt %.1f%% rock %.1f%%" % [
		mountain_surface.get("rock_pct", 0.0),
		valley_surface.get("grass_pct", 0.0),
		valley_surface.get("dirt_pct", 0.0),
		valley_surface.get("rock_pct", 0.0),
	])
	print("  shaping: terraced %d, plateau-adjusted %d across %d chunk columns" % [
		shaping.get("terraced_columns", 0),
		shaping.get("plateau_adjusted_columns", 0),
		shaping.get("plateau_smoothed_chunks", 0),
	])
	print("  water: lake %s r%d y%d floor %d-%d depth %d columns %d; tarn %s r%d y%d floor %d-%d depth %d columns %d; banks %d" % [
		str(water.get("lake_center", Vector2i.ZERO)),
		water.get("lake_radius", 0),
		water.get("lake_waterline", 0),
		water.get("lake_floor_min", 0),
		water.get("lake_floor_max", 0),
		water.get("lake_depth_max", 0),
		water.get("lake_columns", 0),
		str(water.get("tarn_center", Vector2i.ZERO)),
		water.get("tarn_radius", 0),
		water.get("tarn_waterline", 0),
		water.get("tarn_floor_min", 0),
		water.get("tarn_floor_max", 0),
		water.get("tarn_depth_max", 0),
		water.get("tarn_columns", 0),
		water.get("bank_columns", 0),
	])
	print("  macro: basin %d, southeast foothill %d, edge belt %d columns" % [
		macro.get("southwest_basin_columns", 0),
		macro.get("southeast_foothill_columns", 0),
		macro.get("edge_belt_columns", 0),
	])
	print("  settlement candidates: %d sampled 20x20 flats" % candidates.get("count", 0))


func _deferred_print_block_spawn_report(
		snapshot: Dictionary,
		generated_columns: int,
		total_columns: int
	) -> void:
	var total_blocks := 0
	var rows: Array = []
	for id_variant: Variant in snapshot.keys():
		var id := id_variant as int
		var count := snapshot[id_variant] as int
		total_blocks += count

		var key := String(BlockRegistry.get_key(id))
		if key.is_empty():
			key = "<unknown:%d>" % id
		rows.append([count, key])

	rows.sort_custom(func(a: Array, b: Array) -> bool:
		return (a[0] as int) > (b[0] as int)
	)

	print("WorldGenerator block counts: %d/%d streamed columns, %d generated blocks." % [
		generated_columns,
		total_columns,
		total_blocks,
	])
	print("  ore/gem focus:")
	for window: Dictionary in _resource_focus_windows:
		var resource_id: int = window.get("id", -1)
		var resource_count := snapshot.get(resource_id, 0) as int
		var resource_ratio := 0.0
		if total_blocks > 0:
			resource_ratio = (float(resource_count) / float(total_blocks)) * 100.0
		print("    %s: %d (%.3f%%)" % [String(window.get("key", &"")), resource_count, resource_ratio])
	print("  all block types:")
	for row: Array in rows:
		var count := row[0] as int
		var ratio := 0.0
		if total_blocks > 0:
			ratio = (float(count) / float(total_blocks)) * 100.0
		print("  %s: %d (%.3f%%)" % [row[1] as String, count, ratio])


# -- Public API ----------------------------------------------------------------

## Begin procedural world generation on a background thread.
## new_seed = 0  -> random seed via randi().
## new_seed != 0 -> deterministic; same seed always produces the same world.
## (Param is not named "seed" - that shadows the global seed() built-in.)
func generate(new_seed: int = 0) -> void:
	if _gen_thread != null and _gen_thread.is_started():
		push_warning("WorldGenerator.generate() called while generation is already running.")
		return

	world_seed = new_seed if new_seed != 0 else randi()
	print("WorldGenerator: starting generation (seed %d)." % world_seed)

	_reset_generation_state()
	_cache_block_ids()

	# Clean up the thread object on the main thread once the world is done.
	world_complete.connect(_cleanup_thread, CONNECT_ONE_SHOT | CONNECT_DEFERRED)

	_gen_thread = Thread.new()
	_gen_thread.start(_generate_threaded)


func _reset_generation_state() -> void:
	_startup_started_msec = Time.get_ticks_msec()
	_maps_ready_msec = 0
	_map_precompute_msec = 0
	_map_phase_timings.clear()
	_column_fill_msec_total = 0
	_column_fill_msec_max = 0
	_column_fill_count = 0
	_column_chunks_submitted = 0
	_abort = false
	_maps_ready = false
	_column_in_flight = false
	_generation_metrics.clear()
	_domain_counts.clear()
	lowland_cap_grass_band_map.clear()
	lowland_cap_grass_distance_map.clear()
	foothill_cap_grass_band_map.clear()
	foothill_cap_grass_distance_map.clear()
	lake_columns.clear()
	tarn_columns.clear()
	water_bank_columns.clear()
	lake_center = Vector2i.ZERO
	tarn_center = Vector2i.ZERO
	tarn_waterline = 0
	_terraced_columns = 0
	_plateau_adjusted_columns = 0
	_plateau_smoothed_chunks = 0
	_reset_block_spawn_counts()
	_request_mutex.lock()
	_column_queue.clear()
	_requested_columns.clear()
	_generated_columns.clear()
	_request_mutex.unlock()


func _cleanup_thread() -> void:
	if _gen_thread != null:
		_gen_thread.wait_to_finish()
		_gen_thread = null


## True while the background generation thread is still running. WorldRenderer
## uses this to know when the initial bulk load is finished.
func is_generating() -> bool:
	if not _maps_ready:
		return _gen_thread != null and _gen_thread.is_started()
	_request_mutex.lock()
	var has_work := _column_in_flight or not _column_queue.is_empty()
	_request_mutex.unlock()
	return has_work


## Requests a 16x16 XZ chunk column. The background generator fills all
## generated Y chunks for that column when the global 2D maps are ready.
func request_chunk_column(cx: int, cz: int) -> void:
	if cx < 0 or cx >= CHUNK_COUNT_X or cz < 0 or cz >= CHUNK_COUNT_Z:
		return
	var key := Vector2i(cx, cz)
	_request_mutex.lock()
	if not _requested_columns.has(key) and not _generated_columns.has(key):
		_requested_columns[key] = true
		_column_queue.append(key)
	_request_mutex.unlock()


func get_streaming_stats() -> Dictionary:
	_request_mutex.lock()
	var stats := {
		"maps_ready": _maps_ready,
		"queue_size": _column_queue.size(),
		"requested_columns": _requested_columns.size(),
		"generated_columns": _generated_columns.size(),
		"column_in_flight": _column_in_flight,
		"total_columns": CHUNK_COUNT_X * CHUNK_COUNT_Z,
		"startup_elapsed_ms": Time.get_ticks_msec() - _startup_started_msec if _startup_started_msec > 0 else 0,
		"map_precompute_ms": _map_precompute_msec,
		"map_phase_timings": _map_phase_timings.duplicate(true),
		"maps_ready_ms": _maps_ready_msec - _startup_started_msec if _maps_ready_msec > 0 and _startup_started_msec > 0 else 0,
		"column_fill_ms_total": _column_fill_msec_total,
		"column_fill_ms_max": _column_fill_msec_max,
		"column_fill_count": _column_fill_count,
		"column_chunks_submitted": _column_chunks_submitted,
	}
	_request_mutex.unlock()
	return stats


func get_generation_metrics() -> Dictionary:
	return _generation_metrics.duplicate(true)


func get_column_top_y(cx: int, cz: int) -> int:
	if not _maps_ready:
		return WORLD_SIZE_Y - 1
	if cx < 0 or cx >= CHUNK_COUNT_X or cz < 0 or cz >= CHUNK_COUNT_Z:
		return WORLD_SIZE_Y - 1
	return _column_chunk_max_y(cx, cz)


func get_surface_y(wx: int, wz: int) -> int:
	if not _maps_ready:
		return -1
	if wx < 0 or wx >= WORLD_SIZE_X or wz < 0 or wz >= WORLD_SIZE_Z:
		return -1
	return heightmap[wx * WORLD_SIZE_Z + wz]


func get_visible_surface_y(wx: int, wz: int) -> int:
	if not _maps_ready:
		return -1
	if wx < 0 or wx >= WORLD_SIZE_X or wz < 0 or wz >= WORLD_SIZE_Z:
		return -1
	var col := Vector2i(wx, wz)
	if lake_columns.has(col):
		return LAKE_WATERLINE
	if tarn_columns.has(col):
		return tarn_waterline
	return heightmap[wx * WORLD_SIZE_Z + wz]


func get_visible_surface_block_id(wx: int, wz: int) -> int:
	if not _maps_ready:
		return BlockRegistry.AIR_ID
	if wx < 0 or wx >= WORLD_SIZE_X or wz < 0 or wz >= WORLD_SIZE_Z:
		return BlockRegistry.AIR_ID
	var col := Vector2i(wx, wz)
	if lake_columns.has(col) or tarn_columns.has(col):
		return _id_water
	return _generate_block_id(wx, heightmap[wx * WORLD_SIZE_Z + wz], wz)


func get_column_debug_info(wx: int, wz: int) -> Dictionary:
	if not _maps_ready:
		return {}
	if wx < 0 or wx >= WORLD_SIZE_X or wz < 0 or wz >= WORLD_SIZE_Z:
		return {}
	var idx := wx * WORLD_SIZE_Z + wz
	var col := Vector2i(wx, wz)
	var surface_y: int = heightmap[idx]
	var visible_y := get_visible_surface_y(wx, wz)
	var visible_block_id := get_visible_surface_block_id(wx, wz)
	return {
		"domain": _domain_label(domain_map[idx]),
		"domain_n": domain_n_map[idx],
		"height_band": _height_band_label(surface_y),
		"lowland_cap_grass_band": _lowland_cap_grass_band_debug(idx),
		"lowland_cap_grass_distance": _lowland_cap_grass_distance_debug(idx),
		"foothill_cap_grass_band": _foothill_cap_grass_band_debug(idx),
		"foothill_cap_grass_distance": _foothill_cap_grass_distance_debug(idx),
		"surface_y": surface_y,
		"visible_surface_y": visible_y,
		"visible_block_id": visible_block_id,
		"visible_block_key": String(BlockRegistry.get_key(visible_block_id)),
		"is_lake": lake_columns.has(col),
		"is_tarn": tarn_columns.has(col),
		"is_water_bank": water_bank_columns.has(col),
}


func _height_band_label(surface_y: int) -> String:
	if surface_y >= LOWLAND_SHELF_MIN_Y and surface_y <= LOWLAND_SHELF_MAX_Y:
		return "lowland shelf"
	if surface_y >= FOOTHILL_SHELF_MIN_Y and surface_y <= FOOTHILL_SHELF_MAX_Y:
		var shelf := ((surface_y - FOOTHILL_SHELF_MIN_Y) / FOOTHILL_SHELF_HEIGHT) + 1
		return "foothill shelf %d" % shelf
	if surface_y >= MOUNTAIN_MIN and surface_y <= MOUNTAIN_MAX:
		var shelf := ((surface_y - MOUNTAIN_MIN) / MOUNTAIN_SHELF_HEIGHT) + 1
		return "mountain shelf %d" % shelf
	if surface_y <= LAKE_WATERLINE:
		return "lake basin"
	return "unassigned"


func _lowland_cap_grass_band_debug(idx: int) -> int:
	if lowland_cap_grass_band_map.is_empty():
		return 0
	return lowland_cap_grass_band_map[idx]


func _lowland_cap_grass_distance_debug(idx: int) -> int:
	if lowland_cap_grass_distance_map.is_empty():
		return -1
	return lowland_cap_grass_distance_map[idx]


func _foothill_cap_grass_band_debug(idx: int) -> int:
	if foothill_cap_grass_band_map.is_empty():
		return 0
	return foothill_cap_grass_band_map[idx]


func _foothill_cap_grass_distance_debug(idx: int) -> int:
	if foothill_cap_grass_distance_map.is_empty():
		return -1
	return foothill_cap_grass_distance_map[idx]


func get_generated_block_id(wx: int, wy: int, wz: int) -> int:
	if not _maps_ready:
		return BlockRegistry.AIR_ID
	if wx < 0 or wx >= WORLD_SIZE_X or wy < 0 or wy >= WORLD_SIZE_Y or wz < 0 or wz >= WORLD_SIZE_Z:
		return BlockRegistry.AIR_ID
	return _generate_block_id(wx, wy, wz)


# -- ID cache (main thread) ----------------------------------------------------

func _cache_block_ids() -> void:
	_id_void      = BlockRegistry.get_id(&"base:terrain:void")
	_id_bedrock   = BlockRegistry.get_id(&"base:terrain:bedrock")
	_id_water     = BlockRegistry.get_id(&"base:terrain:water:source")
	_id_rock07    = BlockRegistry.get_id(&"base:terrain:rock:rock07")
	_id_rock08    = BlockRegistry.get_id(&"base:terrain:rock:rock08")
	_id_rock09    = BlockRegistry.get_id(&"base:terrain:rock:rock09")
	_id_rock10    = BlockRegistry.get_id(&"base:terrain:rock:rock10")
	_id_rock11    = BlockRegistry.get_id(&"base:terrain:rock:rock11")
	_resource_replaceable_rock_ids.clear()
	for i in range(1, 12):
		_resource_replaceable_rock_ids[BlockRegistry.get_id(StringName("base:terrain:rock:rock%02d" % i))] = true

	_mountain_rock_ids.clear()
	for i in range(6, 0, -1):
		_mountain_rock_ids.append(BlockRegistry.get_id(StringName("base:terrain:rock:rock%02d" % i)))

	_grass_ids.clear()
	for i in range(1, 9):
		_grass_ids.append(BlockRegistry.get_id(StringName("base:terrain:surface:grass_%02d" % i)))

	_dirt_ids.clear()
	for i in range(1, 5):
		_dirt_ids.append(BlockRegistry.get_id(StringName("base:terrain:surface:dirt_%02d" % i)))

	_cache_resource_windows()


func _cache_resource_windows() -> void:
	_metal_windows = _build_resource_windows(METAL_RESOURCE_KEYS, "ore")
	_gem_windows = _build_resource_windows(GEM_RESOURCE_KEYS, "gem")
	_soil_windows = _build_resource_windows(SOIL_RESOURCE_KEYS, "soil")

	_resource_focus_windows.clear()
	_resource_focus_windows.append_array(_gem_windows)
	_resource_focus_windows.append_array(_metal_windows)
	_resource_focus_windows.append_array(_soil_windows)


func _build_resource_windows(keys: Array, expected_channel: String) -> Array[Dictionary]:
	var windows: Array[Dictionary] = []
	for key_variant: Variant in keys:
		var key := key_variant as StringName
		var id := BlockRegistry.get_id(key)
		if id < 0:
			push_warning("WorldGenerator: resource block key is not registered: %s" % String(key))
			continue

		var def := BlockRegistry.get_resource_def(key)
		if def.is_empty():
			push_warning("WorldGenerator: missing block_resources metadata for %s" % String(key))
			continue

		var channel := String(def.get("noise_channel", ""))
		if channel != expected_channel:
			push_warning("WorldGenerator: %s uses noise_channel '%s', expected '%s'." % [String(key), channel, expected_channel])
			continue

		var depth_bias: Dictionary = def.get("depth_bias", {})
		windows.append({
			"key": key,
			"id": id,
			"min_y": int(depth_bias.get("min_y", 0)),
			"max_y": int(depth_bias.get("max_y", WORLD_SIZE_Y - 1)),
			"threshold": float(def.get("noise_threshold", 1.0)),
			"channel": channel,
		})
	return windows


# -- Pipeline (background thread) ----------------------------------------------

func _generate_threaded() -> void:
	var t_start := Time.get_ticks_msec()
	var t_maps_start := t_start

	_run_timed_map_phase("noise_instances", Callable(self, "_build_noise_instances"))             # Phase 1
	_run_timed_map_phase("domain_map", Callable(self, "_compute_domain_map"))                    # Phase 2
	_run_timed_map_phase("heightmap", Callable(self, "_compute_heightmap"))                      # Phase 3
	_run_timed_map_phase("lakes", Callable(self, "_carve_lakes"))                                # Phase 4
	_run_timed_map_phase("edge_detail", Callable(self, "_apply_edge_detail"))
	_run_timed_map_phase("lowland_grass_band", Callable(self, "_build_lowland_cap_grass_band_map"))
	_run_timed_map_phase("foothill_grass_band", Callable(self, "_build_foothill_cap_grass_band_map"))
	_maps_ready_msec = Time.get_ticks_msec()
	_map_precompute_msec = _maps_ready_msec - t_maps_start
	_maps_ready = true
	call_deferred("_deferred_emit_maps_ready")

	_run_timed_map_phase("generation_metrics", Callable(self, "_build_generation_metrics"))
	call_deferred("_deferred_print_generation_metrics", _generation_metrics.duplicate(true))
	_process_requested_columns()      # Phase 5, demand-driven
	_maybe_defer_block_spawn_report(true)

	var elapsed := (Time.get_ticks_msec() - t_start) / 1000.0
	print("WorldGenerator: stopped in %.1f s." % elapsed)
	call_deferred("_deferred_emit_world_complete")


func _run_timed_map_phase(label: String, fn: Callable) -> void:
	var t_phase_start := Time.get_ticks_msec()
	fn.call()
	var elapsed := Time.get_ticks_msec() - t_phase_start
	_request_mutex.lock()
	_map_phase_timings.append({
		"name": label,
		"ms": elapsed,
	})
	_request_mutex.unlock()


# -- Phase 1 - Noise instances -------------------------------------------------

func _build_noise_instances() -> void:
	# Layer 1 - Ore vein mask
	# Medium frequency, fewer octaves for thin vein shapes.
	noise_ore = FastNoiseLite.new()
	noise_ore.noise_type        = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise_ore.seed              = world_seed + 1
	noise_ore.frequency         = 0.02
	noise_ore.fractal_octaves   = 2

	# Layer 2 - Cave void mask
	# Medium-low frequency, more octaves for organic cave networks.
	noise_cave = FastNoiseLite.new()
	noise_cave.noise_type       = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise_cave.seed             = world_seed + 2
	noise_cave.frequency        = 0.015
	noise_cave.fractal_octaves  = 4

	# Layer 3 - Soil patch mask (also drives surface dirt fraction via 2D query)
	# Higher frequency, smooth noise for small irregular farmable soil pockets.
	noise_soil = FastNoiseLite.new()
	noise_soil.noise_type       = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise_soil.seed             = world_seed + 3
	noise_soil.frequency        = 0.03
	noise_soil.fractal_octaves  = 2

	# Layer 4 - Terrain domain map
	# Very low frequency, large scale noise for broad mountain / valley / lowland zones.
	noise_domain = FastNoiseLite.new()
	noise_domain.noise_type      = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise_domain.seed            = world_seed + 4
	noise_domain.frequency       = 0.0015
	noise_domain.fractal_octaves = 2

	# Layer 5 - Mountain ridge detail
	# Ridge noise (abs of simplex, inverted) for sharp peaks and narrow spines.
	noise_mountain = FastNoiseLite.new()
	noise_mountain.noise_type      = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise_mountain.seed            = world_seed + 5
	noise_mountain.frequency       = 0.006
	noise_mountain.fractal_octaves = 5

	# Layer 6 - Valley / lowland floor detail
	# Low amplitude, gentle rolls for subtle variation in otherwise flat ground.
	noise_valley = FastNoiseLite.new()
	noise_valley.noise_type      = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise_valley.seed            = world_seed + 6
	noise_valley.frequency       = 0.012
	noise_valley.fractal_octaves = 2

	# Layer 7 - Gem pocket mask
	# Higher frequency than metal veins so gems appear as smaller clusters.
	noise_gem = FastNoiseLite.new()
	noise_gem.noise_type       = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise_gem.seed             = world_seed + 7
	noise_gem.frequency        = 0.06
	noise_gem.fractal_octaves  = 3


# -- Phase 2 - Domain map (2D) -------------------------------------------------

func _compute_domain_map() -> void:
	var size := WORLD_SIZE_X * WORLD_SIZE_Z
	domain_map.resize(size)
	domain_n_map.resize(size)

	# Embarrassingly parallel: each X column writes a disjoint Z slice of
	# domain_map / domain_n_map and calls only read-only helpers + noise reads.
	# One group-task element per X column; the pool chunks them across threads.
	var task_id := WorkerThreadPool.add_group_task(
		Callable(self, "_domain_map_column"), WORLD_SIZE_X, -1, false, "domain_map")
	WorkerThreadPool.wait_for_group_task_completion(task_id)

	_apply_macro_domain_coherence()
	_recount_domain_counts()
	print("WorldGenerator: domain layout northwest mountain -> mountain %d, valley %d, lowland %d." % [
		_domain_counts.get("mountain", 0),
		_domain_counts.get("valley", 0),
		_domain_counts.get("lowland", 0),
	])


## WorkerThreadPool group-task body: fills one X column of the domain maps.
## Writes only indices [x * WORLD_SIZE_Z .. x * WORLD_SIZE_Z + WORLD_SIZE_Z),
## which are disjoint across X, so concurrent execution is race-free. All
## helpers called here are pure reads (noise sampling is a const read on
## FastNoiseLite and safe to call from multiple threads).
func _domain_map_column(x: int) -> void:
	var base := x * WORLD_SIZE_Z
	for z in range(WORLD_SIZE_Z):
		var northwest_influence := _northwest_mountain_influence(x, z)
		var edge_noise := (noise_domain.get_noise_2d(x, z) + 1.0) * 0.5
		var basin_strength := _southwest_basin_strength(x, z)
		var southeast_foothill_strength := _southeast_foothill_strength(x, z)
		var corridor_strength := _valley_corridor_strength(x, z)
		var n := clampf(
			northwest_influence + ((edge_noise - 0.5) * NORTHWEST_MOUNTAIN_EDGE_NOISE),
			0.0,
			1.0)
		n = lerp(n, 0.18, basin_strength * SOUTHWEST_BASIN_DOMAIN_PULL)
		n = lerp(n, 0.48, southeast_foothill_strength * SOUTHEAST_FOOTHILL_DOMAIN_BONUS)
		n = lerp(n, 0.48, corridor_strength * 0.22)
		var idx := base + z
		domain_n_map[idx] = n
		if n > DOMAIN_MOUNTAIN_THRESHOLD:
			domain_map[idx] = DOMAIN_MOUNTAIN
		elif n > DOMAIN_VALLEY_THRESHOLD:
			domain_map[idx] = DOMAIN_VALLEY
		else:
			domain_map[idx] = DOMAIN_LOWLAND


func _apply_macro_domain_coherence() -> void:
	var macro_count_x := (WORLD_SIZE_X + TERRAIN_MACRO_CELL_SIZE - 1) / TERRAIN_MACRO_CELL_SIZE
	var macro_count_z := (WORLD_SIZE_Z + TERRAIN_MACRO_CELL_SIZE - 1) / TERRAIN_MACRO_CELL_SIZE
	var macro_domains := PackedInt32Array()
	macro_domains.resize(macro_count_x * macro_count_z)

	for mx in range(macro_count_x):
		for mz in range(macro_count_z):
			macro_domains[mx * macro_count_z + mz] = _macro_cell_terrain_profile(mx, mz)["domain"]

	var promoted_lowland_islands := _promote_disconnected_macro_lowlands(macro_domains, macro_count_x, macro_count_z)

	for mx in range(macro_count_x):
		for mz in range(macro_count_z):
			var macro_domain: int = macro_domains[mx * macro_count_z + mz]
			var start_x := mx * TERRAIN_MACRO_CELL_SIZE
			var start_z := mz * TERRAIN_MACRO_CELL_SIZE
			var end_x := mini(WORLD_SIZE_X, start_x + TERRAIN_MACRO_CELL_SIZE)
			var end_z := mini(WORLD_SIZE_Z, start_z + TERRAIN_MACRO_CELL_SIZE)
			for x in range(start_x, end_x):
				for z in range(start_z, end_z):
					domain_map[x * WORLD_SIZE_Z + z] = macro_domain

	if promoted_lowland_islands > 0:
		print("WorldGenerator: macro domain coherence -> promoted %d disconnected lowland cells to valley." % promoted_lowland_islands)


func _promote_disconnected_macro_lowlands(macro_domains: PackedInt32Array, macro_count_x: int, macro_count_z: int) -> int:
	var reachable := PackedByteArray()
	reachable.resize(macro_domains.size())
	var queue: Array[Vector2i] = []

	for mx in range(macro_count_x):
		for mz in range(macro_count_z):
			var idx := mx * macro_count_z + mz
			if macro_domains[idx] != DOMAIN_LOWLAND:
				continue
			if not _is_macro_lowland_anchor(mx, mz, macro_count_x, macro_count_z):
				continue
			reachable[idx] = 1
			queue.append(Vector2i(mx, mz))

	var head: int = 0
	var directions: Array[Vector2i] = [
		Vector2i(-1, 0),
		Vector2i(1, 0),
		Vector2i(0, -1),
		Vector2i(0, 1),
	]
	while head < queue.size():
		var cell: Vector2i = queue[head]
		head += 1
		for direction: Vector2i in directions:
			var nx: int = cell.x + direction.x
			var nz: int = cell.y + direction.y
			if nx < 0 or nx >= macro_count_x or nz < 0 or nz >= macro_count_z:
				continue
			var nidx: int = nx * macro_count_z + nz
			if reachable[nidx] == 1:
				continue
			if macro_domains[nidx] != DOMAIN_LOWLAND:
				continue
			reachable[nidx] = 1
			queue.append(Vector2i(nx, nz))

	var promoted := 0

	for mx in range(macro_count_x):
		for mz in range(macro_count_z):
			var idx := mx * macro_count_z + mz
			if macro_domains[idx] != DOMAIN_LOWLAND:
				continue
			if reachable[idx] == 0:
				macro_domains[idx] = DOMAIN_VALLEY
				promoted += 1

	return promoted


func _is_macro_lowland_anchor(mx: int, mz: int, macro_count_x: int, macro_count_z: int) -> bool:
	var center_x := mini((mx * TERRAIN_MACRO_CELL_SIZE) + (TERRAIN_MACRO_CELL_SIZE / 2), WORLD_SIZE_X - 1)
	var center_z := mini((mz * TERRAIN_MACRO_CELL_SIZE) + (TERRAIN_MACRO_CELL_SIZE / 2), WORLD_SIZE_Z - 1)
	return (
		_southwest_basin_strength(center_x, center_z) > 0.30
		or mx == 0
		or mz == 0
		or mx == macro_count_x - 1
		or mz == macro_count_z - 1
	)

# -- Phase 3 - Surface heightmap (2D) -----------------------------------------

func _compute_heightmap() -> void:
	heightmap.resize(WORLD_SIZE_X * WORLD_SIZE_Z)

	var macro_count_x := (WORLD_SIZE_X + TERRAIN_MACRO_CELL_SIZE - 1) / TERRAIN_MACRO_CELL_SIZE
	var macro_count_z := (WORLD_SIZE_Z + TERRAIN_MACRO_CELL_SIZE - 1) / TERRAIN_MACRO_CELL_SIZE
	var macro_heights := PackedInt32Array()
	macro_heights.resize(macro_count_x * macro_count_z)

	for mx in range(macro_count_x):
		for mz in range(macro_count_z):
			macro_heights[mx * macro_count_z + mz] = _macro_height_for_cell(mx, mz)

	# Parallel per-column fill. Each X column writes its own disjoint Z slice of
	# heightmap and records its debug tallies into its own slot of the per-column
	# scratch arrays, so there are no cross-thread writes to shared indices.
	# macro_heights is read-only during the fill.
	_hm_macro_heights = macro_heights
	_hm_macro_count_z = macro_count_z
	_hm_terraced_col.resize(WORLD_SIZE_X)
	_hm_corridor_count_col.resize(WORLD_SIZE_X)
	_hm_corridor_height_col.resize(WORLD_SIZE_X)

	var task_id := WorkerThreadPool.add_group_task(
		Callable(self, "_heightmap_column"), WORLD_SIZE_X, -1, false, "heightmap")
	WorkerThreadPool.wait_for_group_task_completion(task_id)

	var corridor_count := 0
	var corridor_height_sum := 0
	var terraced_count := 0
	for x in range(WORLD_SIZE_X):
		terraced_count += _hm_terraced_col[x]
		corridor_count += _hm_corridor_count_col[x]
		corridor_height_sum += _hm_corridor_height_col[x]

	if corridor_count > 0:
		print("WorldGenerator: valley corridor -> columns %d, average height %.1f." % [
			corridor_count,
			float(corridor_height_sum) / float(corridor_count),
		])
	print("WorldGenerator: macro heightmap -> %d cells expanded at %d columns per cell." % [
		macro_count_x * macro_count_z,
		TERRAIN_MACRO_CELL_SIZE,
	])
	print("WorldGenerator: macro expansion -> local offsets on %d columns." % terraced_count)
	_terraced_columns = terraced_count
	_apply_plateau_smoothing()
	_apply_mountain_foothill_transition()
	_apply_lowland_foothill_transition()
	_apply_macro_shelf_step_limit()


## WorkerThreadPool group-task body: fills one X column of the heightmap and
## records that column's debug tallies into its own scratch slot. Writes only
## heightmap[x * WORLD_SIZE_Z + z] for this x (disjoint across X) and the single
## scratch slot at index x, so concurrent execution is race-free. Reads
## _hm_macro_heights / domain_n_map (filled by the prior phase) and noise, all
## read-only. Must be called only between the add_group_task and its
## wait_for_group_task_completion in _compute_heightmap.
func _heightmap_column(x: int) -> void:
	var macro_count_z := _hm_macro_count_z
	var mx := x / TERRAIN_MACRO_CELL_SIZE
	var base := x * WORLD_SIZE_Z
	var terraced := 0
	var corridor_count := 0
	var corridor_height_sum := 0
	for z in range(WORLD_SIZE_Z):
		var mz := z / TERRAIN_MACRO_CELL_SIZE
		var macro_height: int = _hm_macro_heights[mx * macro_count_z + mz]
		var height := _expanded_macro_height(x, z, macro_height)
		var corridor_strength := _valley_corridor_strength(x, z)
		heightmap[base + z] = height
		if height != macro_height:
			terraced += 1
		if corridor_strength > 0.5:
			corridor_count += 1
			corridor_height_sum += height
	_hm_terraced_col[x] = terraced
	_hm_corridor_count_col[x] = corridor_count
	_hm_corridor_height_col[x] = corridor_height_sum


func _macro_height_for_cell(mx: int, mz: int) -> int:
	var center_x := mini((mx * TERRAIN_MACRO_CELL_SIZE) + (TERRAIN_MACRO_CELL_SIZE / 2), WORLD_SIZE_X - 1)
	var center_z := mini((mz * TERRAIN_MACRO_CELL_SIZE) + (TERRAIN_MACRO_CELL_SIZE / 2), WORLD_SIZE_Z - 1)
	var idx := center_x * WORLD_SIZE_Z + center_z
	var profile := _macro_cell_terrain_profile(mx, mz)
	var macro_domain: int = profile["domain"]
	var domain_n := domain_n_map[idx]
	var southeast_foothill_strength := _southeast_foothill_macro_strength(center_x, center_z)

	if macro_domain == DOMAIN_LOWLAND:
		return LOWLAND_SHELF_MAX_Y

	var raw_height := _raw_macro_height(center_x, center_z, domain_n)
	var corridor_strength := _valley_corridor_strength(center_x, center_z)
	var settlement_strength := _settlement_plain_strength(center_x, center_z)
	var basin_strength := _southwest_basin_strength(center_x, center_z)

	if corridor_strength > 0.0:
		raw_height = lerp(raw_height, _valley_corridor_height(center_x, center_z), corridor_strength)
	if basin_strength > 0.0:
		raw_height = lerp(raw_height, _southwest_basin_height(center_x, center_z), basin_strength)
	if southeast_foothill_strength > 0.0 and domain_n > DOMAIN_VALLEY_THRESHOLD:
		raw_height = lerp(raw_height, _southeast_foothill_height(center_x, center_z), southeast_foothill_strength)
	if settlement_strength > 0.0:
		raw_height = lerp(raw_height, float(SETTLEMENT_PLAIN_SURFACE_Y), settlement_strength)

	if settlement_strength > SETTLEMENT_PLAIN_MACRO_THRESHOLD and macro_domain == DOMAIN_LOWLAND:
		return SETTLEMENT_PLAIN_SURFACE_Y
	if settlement_strength > SETTLEMENT_PLAIN_MACRO_THRESHOLD:
		return FOOTHILL_SHELF_MIN_Y + FOOTHILL_SHELF_HEIGHT - 1
	if southeast_foothill_strength > SOUTHEAST_FOOTHILL_MACRO_MIN and macro_domain == DOMAIN_VALLEY:
		return _southeast_foothill_macro_height(center_x, center_z, southeast_foothill_strength)

	var rounded_height := int(round(raw_height))
	if rounded_height >= LOWLAND_SHELF_MIN_Y and rounded_height <= LOWLAND_SHELF_MAX_Y:
		return LOWLAND_SHELF_MAX_Y

	var step: int = _terrace_step_for(center_x, center_z, domain_n, corridor_strength)
	var base: int = _terrace_base_for(center_x, center_z, domain_n, corridor_strength)
	if domain_n > DOMAIN_MOUNTAIN_THRESHOLD:
		return _quantize_height_to_mountain_shelf_top(rounded_height)
	if _is_foothill_terrace_context(center_x, center_z, domain_n, corridor_strength):
		return _quantize_height_to_shelf_top(rounded_height, FOOTHILL_SHELF_HEIGHT, FOOTHILL_SHELF_MIN_Y)
	return _quantize_height_to_band(rounded_height, step, base)


func _macro_cell_terrain_profile(mx: int, mz: int) -> Dictionary:
	var start_x := mx * TERRAIN_MACRO_CELL_SIZE
	var start_z := mz * TERRAIN_MACRO_CELL_SIZE
	var end_x := mini(WORLD_SIZE_X, start_x + TERRAIN_MACRO_CELL_SIZE)
	var end_z := mini(WORLD_SIZE_Z, start_z + TERRAIN_MACRO_CELL_SIZE)
	var lowland_count := 0
	var valley_count := 0
	var mountain_count := 0
	var total := 0

	for x in range(start_x, end_x):
		for z in range(start_z, end_z):
			total += 1
			match domain_map[x * WORLD_SIZE_Z + z]:
				DOMAIN_MOUNTAIN:
					mountain_count += 1
				DOMAIN_VALLEY:
					valley_count += 1
				_:
					lowland_count += 1

	var center_x := mini(start_x + ((end_x - start_x) / 2), WORLD_SIZE_X - 1)
	var center_z := mini(start_z + ((end_z - start_z) / 2), WORLD_SIZE_Z - 1)
	var southeast_foothill_strength := _southeast_foothill_macro_strength(center_x, center_z)

	var domain := DOMAIN_VALLEY
	if mountain_count > valley_count and mountain_count > lowland_count:
		domain = DOMAIN_MOUNTAIN
	elif southeast_foothill_strength > SOUTHEAST_FOOTHILL_MACRO_MIN and mountain_count == 0:
		domain = DOMAIN_VALLEY
	elif lowland_count >= int(ceil(float(total) * LOWLAND_MACRO_MIN_FRACTION)) and lowland_count > valley_count and mountain_count == 0:
		domain = DOMAIN_LOWLAND

	return {
		"domain": domain,
		"lowland": lowland_count,
		"valley": valley_count,
		"mountain": mountain_count,
		"total": total,
	}


func _raw_macro_height(x: int, z: int, domain_n: float) -> float:
	if domain_n > DOMAIN_MOUNTAIN_THRESHOLD:
		var ridge: float = 1.0 - absf(noise_mountain.get_noise_2d(x, z))
		var mountain_depth: float = clampf((domain_n - DOMAIN_MOUNTAIN_THRESHOLD) / 0.40, 0.0, 1.0)
		var mountain_floor: float = lerp(float(MOUNTAIN_MIN), float(MOUNTAIN_MIN + MOUNTAIN_SHELF_HEIGHT - 1), mountain_depth)
		var mountain_height: float = lerp(mountain_floor, float(MOUNTAIN_MAX), ridge)
		if domain_n < 0.70:
			var t := (domain_n - DOMAIN_MOUNTAIN_THRESHOLD) / 0.10
			mountain_height = lerp(_foothill_height(x, z, domain_n), mountain_height, t)
		return mountain_height

	if domain_n > DOMAIN_VALLEY_THRESHOLD:
		var foothill_surface_y: float = _foothill_height(x, z, domain_n)
		if domain_n < 0.45:
			var t := (domain_n - DOMAIN_VALLEY_THRESHOLD) / 0.10
			foothill_surface_y = lerp(_lowland_height(x, z), foothill_surface_y, t)
		return foothill_surface_y

	return _lowland_height(x, z)


func _expanded_macro_height(x: int, z: int, macro_height: int) -> int:
	var idx := x * WORLD_SIZE_Z + z
	var domain_n := domain_n_map[idx]
	var corridor_strength := _valley_corridor_strength(x, z)

	if _is_settlement_plain_macro_column(x, z):
		return SETTLEMENT_PLAIN_SURFACE_Y if macro_height <= LOWLAND_SHELF_MAX_Y else macro_height
	if domain_n > DOMAIN_MOUNTAIN_THRESHOLD:
		return clampi(macro_height, 1, WORLD_SIZE_Y - 1)
	if macro_height >= LOWLAND_SHELF_MIN_Y and macro_height <= LOWLAND_SHELF_MAX_Y:
		return LOWLAND_SHELF_MAX_Y
	if macro_height >= FOOTHILL_SHELF_MIN_Y and macro_height <= FOOTHILL_SHELF_MAX_Y:
		return _quantize_height_to_shelf_top(macro_height, FOOTHILL_SHELF_HEIGHT, FOOTHILL_SHELF_MIN_Y)
	if macro_height > FOOTHILL_SHELF_MAX_Y and macro_height < MOUNTAIN_MIN:
		return FOOTHILL_SHELF_MAX_Y
	if macro_height >= MOUNTAIN_MIN and macro_height <= MOUNTAIN_MAX:
		return _quantize_height_to_mountain_shelf_top(macro_height)

	var local_variation := _macro_local_variation(x, z, corridor_strength)
	var expanded_height := clampi(macro_height + local_variation, 1, WORLD_SIZE_Y - 1)
	if expanded_height >= LOWLAND_SHELF_MIN_Y and expanded_height <= LOWLAND_SHELF_MAX_Y:
		return LOWLAND_SHELF_MAX_Y
	if expanded_height >= FOOTHILL_SHELF_MIN_Y and expanded_height <= FOOTHILL_SHELF_MAX_Y:
		return _quantize_height_to_shelf_top(expanded_height, FOOTHILL_SHELF_HEIGHT, FOOTHILL_SHELF_MIN_Y)
	if expanded_height > FOOTHILL_SHELF_MAX_Y and expanded_height < MOUNTAIN_MIN:
		return FOOTHILL_SHELF_MAX_Y
	return expanded_height


func _macro_local_variation(x: int, z: int, corridor_strength: float) -> int:
	if corridor_strength > 0.65:
		return 0
	var cell := Vector3i(x / TERRAIN_MACRO_CELL_SIZE, 71, z / TERRAIN_MACRO_CELL_SIZE)
	var base: int = abs(hash(cell)) % 3
	var field := (noise_valley.get_noise_2d(float(x) * 0.08 + 19000.0, float(z) * 0.08 - 19000.0) + 1.0) * 0.5
	return mini(2, int(round((float(base) * 0.55) + (field * 1.1))))


func _foothill_height(x: int, z: int, domain_n: float) -> float:
	var foothill_t: float = clampf((domain_n - DOMAIN_VALLEY_THRESHOLD) / (DOMAIN_MOUNTAIN_THRESHOLD - DOMAIN_VALLEY_THRESHOLD), 0.0, 1.0)
	var shelf_bias: float = (noise_valley.get_noise_2d(float(x) + 2400.0, float(z) - 2400.0) + 1.0) * 0.06 - 0.03
	var shelf_index := clampi(int(floor((foothill_t + shelf_bias) * 3.0)), 0, 2)
	return float(FOOTHILL_SHELF_MIN_Y + (shelf_index * FOOTHILL_SHELF_HEIGHT) + FOOTHILL_SHELF_HEIGHT - 1)


func _southeast_foothill_macro_height(x: int, z: int, strength: float) -> int:
	var detail := (noise_valley.get_noise_2d(float(x) - 5000.0, float(z) - 5000.0) + 1.0) * 0.5
	var shelf_score := clampf(strength + ((detail - 0.5) * 0.12), 0.0, 1.0)
	if shelf_score >= SOUTHEAST_FOOTHILL_SHELF_3_MIN:
		return FOOTHILL_SHELF_MAX_Y
	if shelf_score >= SOUTHEAST_FOOTHILL_SHELF_2_MIN:
		return FOOTHILL_SHELF_MIN_Y + (FOOTHILL_SHELF_HEIGHT * 2) - 1
	return FOOTHILL_SHELF_MIN_Y + FOOTHILL_SHELF_HEIGHT - 1


func _terraced_height(raw_height: int, domain_n: float, corridor_strength: float, x: int, z: int) -> int:
	var step := _terrace_step_for(x, z, domain_n, corridor_strength)
	var base := _terrace_base_for(x, z, domain_n, corridor_strength)
	return _quantize_height_to_band(raw_height, step, base)


func _quantize_height_to_band(raw_height: int, step: int, base: int) -> int:
	if step <= 2:
		return clampi(raw_height, 1, WORLD_SIZE_Y - 1)
	var band := int(round(float(raw_height - base) / float(step)))
	return clampi(base + (band * step), 1, WORLD_SIZE_Y - 1)


func _quantize_height_to_shelf_top(raw_height: int, step: int, shelf_min: int) -> int:
	if step <= 1:
		return clampi(raw_height, 1, WORLD_SIZE_Y - 1)
	var band := int(floor(float(raw_height - shelf_min) / float(step)))
	var shelf_top := shelf_min + (band * step) + step - 1
	return clampi(shelf_top, shelf_min + step - 1, FOOTHILL_SHELF_MAX_Y)


func _quantize_height_to_mountain_shelf_top(raw_height: int) -> int:
	var band := int(floor(float(raw_height - MOUNTAIN_MIN) / float(MOUNTAIN_SHELF_HEIGHT)))
	var shelf_top := MOUNTAIN_MIN + (band * MOUNTAIN_SHELF_HEIGHT) + MOUNTAIN_SHELF_HEIGHT - 1
	return clampi(shelf_top, MOUNTAIN_MIN + MOUNTAIN_SHELF_HEIGHT - 1, MOUNTAIN_MAX)


func _is_foothill_terrace_context(x: int, z: int, domain_n: float, corridor_strength: float) -> bool:
	if _is_settlement_plain_macro_column(x, z):
		return false
	if _southeast_foothill_strength(x, z) > 0.35 and domain_n > DOMAIN_VALLEY_THRESHOLD:
		return false
	if domain_n > DOMAIN_MOUNTAIN_THRESHOLD:
		return false
	if corridor_strength > 0.45 and domain_n >= 0.44:
		return true
	return domain_n > DOMAIN_VALLEY_THRESHOLD


func _is_foothill_shelf_column(x: int, z: int) -> bool:
	var idx := x * WORLD_SIZE_Z + z
	var h: int = heightmap[idx]
	if h < FOOTHILL_SHELF_MIN_Y or h > FOOTHILL_SHELF_MAX_Y:
		return false
	return true


func _is_settlement_plain_macro_column(x: int, z: int) -> bool:
	var center_x := mini(((x / TERRAIN_MACRO_CELL_SIZE) * TERRAIN_MACRO_CELL_SIZE) + (TERRAIN_MACRO_CELL_SIZE / 2), WORLD_SIZE_X - 1)
	var center_z := mini(((z / TERRAIN_MACRO_CELL_SIZE) * TERRAIN_MACRO_CELL_SIZE) + (TERRAIN_MACRO_CELL_SIZE / 2), WORLD_SIZE_Z - 1)
	return _settlement_plain_strength(center_x, center_z) > SETTLEMENT_PLAIN_MACRO_THRESHOLD


func _is_lowland_shelf_column(x: int, z: int) -> bool:
	var h: int = heightmap[x * WORLD_SIZE_Z + z]
	return h >= LOWLAND_SHELF_MIN_Y and h <= LOWLAND_SHELF_MAX_Y


func _is_mountain_shelf_column(x: int, z: int) -> bool:
	var h: int = heightmap[x * WORLD_SIZE_Z + z]
	return h >= MOUNTAIN_MIN and h <= MOUNTAIN_MAX


func _terrace_step_for(x: int, z: int, domain_n: float, corridor_strength: float) -> int:
	if _is_settlement_plain_macro_column(x, z):
		return VALLEY_TERRACE_STEP
	if corridor_strength > 0.45 and domain_n < 0.44:
		return VALLEY_TERRACE_STEP
	if corridor_strength > 0.45:
		return FOOTHILL_SHELF_HEIGHT
	if _southeast_foothill_strength(x, z) > 0.35 and domain_n > DOMAIN_VALLEY_THRESHOLD:
		return FOOTHILL_SHELF_HEIGHT
	if domain_n > DOMAIN_MOUNTAIN_THRESHOLD:
		return MOUNTAIN_SHELF_HEIGHT
	if domain_n > DOMAIN_VALLEY_THRESHOLD:
		return FOOTHILL_SHELF_HEIGHT
	return VALLEY_TERRACE_STEP


func _terrace_base_for(x: int, z: int, domain_n: float, corridor_strength: float) -> int:
	if _is_settlement_plain_macro_column(x, z):
		return VALLEY_CORRIDOR_MIN_Y
	if corridor_strength > 0.45 and domain_n < 0.44:
		return VALLEY_CORRIDOR_MIN_Y
	if corridor_strength > 0.45:
		return FOOTHILL_SHELF_MIN_Y
	if _southeast_foothill_strength(x, z) > 0.35 and domain_n > DOMAIN_VALLEY_THRESHOLD:
		return FOOTHILL_SHELF_MIN_Y
	if domain_n > DOMAIN_MOUNTAIN_THRESHOLD:
		return MOUNTAIN_MIN
	if domain_n > DOMAIN_VALLEY_THRESHOLD:
		return FOOTHILL_SHELF_MIN_Y
	return LOWLAND_RAW_HEIGHT_MIN_Y


func _terrace_jitter(x: int, z: int, step: int) -> int:
	if step <= 2:
		return 0
	var break_noise := (noise_domain.get_noise_2d(float(x) + 12000.0, float(z) + 12000.0) + 1.0) * 0.5
	return int(round((break_noise - 0.5) * float(step)))


func _apply_plateau_smoothing() -> void:
	var adjusted_columns := 0
	var smoothed_macro_cells := 0
	var macro_count_x := (WORLD_SIZE_X + TERRAIN_MACRO_CELL_SIZE - 1) / TERRAIN_MACRO_CELL_SIZE
	var macro_count_z := (WORLD_SIZE_Z + TERRAIN_MACRO_CELL_SIZE - 1) / TERRAIN_MACRO_CELL_SIZE

	for mx in range(macro_count_x):
		for mz in range(macro_count_z):
			var base_x := mx * TERRAIN_MACRO_CELL_SIZE
			var base_z := mz * TERRAIN_MACRO_CELL_SIZE
			var min_h := WORLD_SIZE_Y
			var max_h := 0
			var mountain_columns := 0
			var height_counts: Dictionary = {}

			for lx in range(TERRAIN_MACRO_CELL_SIZE):
				var wx := base_x + lx
				if wx >= WORLD_SIZE_X:
					break
				for lz in range(TERRAIN_MACRO_CELL_SIZE):
					var wz := base_z + lz
					if wz >= WORLD_SIZE_Z:
						break
					var idx := wx * WORLD_SIZE_Z + wz
					var height: int = heightmap[idx]
					min_h = mini(min_h, height)
					max_h = maxi(max_h, height)
					height_counts[height] = (height_counts.get(height, 0) as int) + 1
					if domain_map[idx] == DOMAIN_MOUNTAIN:
						mountain_columns += 1

			if max_h - min_h > PLATEAU_MAX_HEIGHT_RANGE:
				continue
			var target_height := _dominant_height(height_counts)
			var dominant_count := height_counts.get(target_height, 0) as int
			if dominant_count < PLATEAU_MIN_DOMINANT_COLUMNS:
				continue
			if mountain_columns > 128 and target_height > PLATEAU_MAX_MOUNTAIN_HEIGHT:
				continue

			var changed_in_chunk := 0
			for lx in range(TERRAIN_MACRO_CELL_SIZE):
				var wx := base_x + lx
				if wx >= WORLD_SIZE_X:
					break
				for lz in range(TERRAIN_MACRO_CELL_SIZE):
					var wz := base_z + lz
					if wz >= WORLD_SIZE_Z:
						break
					var idx := wx * WORLD_SIZE_Z + wz
					var current: int = heightmap[idx]
					if absi(current - target_height) > PLATEAU_SNAP_DELTA:
						continue
					if current == target_height:
						continue
					if _plateau_bias_strength(wx, wz, lx, lz) < 0.50:
						continue
					heightmap[idx] = target_height
					changed_in_chunk += 1

			if changed_in_chunk > 0:
				smoothed_macro_cells += 1
				adjusted_columns += changed_in_chunk

	print("WorldGenerator: plateau smoothing -> adjusted %d columns across %d macro cells." % [
		adjusted_columns,
		smoothed_macro_cells,
	])
	_plateau_adjusted_columns = adjusted_columns
	_plateau_smoothed_chunks = smoothed_macro_cells


func _apply_mountain_foothill_transition() -> void:
	var macro_count_x := (WORLD_SIZE_X + TERRAIN_MACRO_CELL_SIZE - 1) / TERRAIN_MACRO_CELL_SIZE
	var macro_count_z := (WORLD_SIZE_Z + TERRAIN_MACRO_CELL_SIZE - 1) / TERRAIN_MACRO_CELL_SIZE
	var far_distance := macro_count_x + macro_count_z
	var mountain_distance := PackedInt32Array()
	mountain_distance.resize(macro_count_x * macro_count_z)

	for idx in range(mountain_distance.size()):
		mountain_distance[idx] = far_distance

	for mx in range(macro_count_x):
		for mz in range(macro_count_z):
			var has_mountain := false
			var base_x := mx * TERRAIN_MACRO_CELL_SIZE
			var base_z := mz * TERRAIN_MACRO_CELL_SIZE
			for lx in range(TERRAIN_MACRO_CELL_SIZE):
				var wx := base_x + lx
				if wx >= WORLD_SIZE_X:
					break
				for lz in range(TERRAIN_MACRO_CELL_SIZE):
					var wz := base_z + lz
					if wz >= WORLD_SIZE_Z:
						break
					if heightmap[wx * WORLD_SIZE_Z + wz] >= MOUNTAIN_MIN:
						has_mountain = true
						break
				if has_mountain:
					break
			if has_mountain:
				mountain_distance[mx * macro_count_z + mz] = 0

	for mx in range(macro_count_x):
		for mz in range(macro_count_z):
			var idx := mx * macro_count_z + mz
			var best: int = mountain_distance[idx]
			if mx > 0:
				best = mini(best, mountain_distance[(mx - 1) * macro_count_z + mz] + 1)
			if mz > 0:
				best = mini(best, mountain_distance[mx * macro_count_z + mz - 1] + 1)
			mountain_distance[idx] = best

	for mx in range(macro_count_x - 1, -1, -1):
		for mz in range(macro_count_z - 1, -1, -1):
			var idx := mx * macro_count_z + mz
			var best: int = mountain_distance[idx]
			if mx < macro_count_x - 1:
				best = mini(best, mountain_distance[(mx + 1) * macro_count_z + mz] + 1)
			if mz < macro_count_z - 1:
				best = mini(best, mountain_distance[mx * macro_count_z + mz + 1] + 1)
			mountain_distance[idx] = best

	var adjusted_columns := 0
	for mx in range(macro_count_x):
		for mz in range(macro_count_z):
			var distance_to_mountain: int = mountain_distance[mx * macro_count_z + mz]
			var target_height := 0
			if distance_to_mountain == 1:
				target_height = FOOTHILL_SHELF_MAX_Y
			elif distance_to_mountain == 2:
				target_height = FOOTHILL_SHELF_MIN_Y + (FOOTHILL_SHELF_HEIGHT * 2) - 1
			elif distance_to_mountain == 3:
				target_height = FOOTHILL_SHELF_MIN_Y + FOOTHILL_SHELF_HEIGHT - 1
			else:
				continue
			if int(_macro_cell_terrain_profile(mx, mz)["domain"]) == DOMAIN_LOWLAND:
				continue

			var base_x := mx * TERRAIN_MACRO_CELL_SIZE
			var base_z := mz * TERRAIN_MACRO_CELL_SIZE
			for lx in range(TERRAIN_MACRO_CELL_SIZE):
				var wx := base_x + lx
				if wx >= WORLD_SIZE_X:
					break
				for lz in range(TERRAIN_MACRO_CELL_SIZE):
					var wz := base_z + lz
					if wz >= WORLD_SIZE_Z:
						break
					var idx := wx * WORLD_SIZE_Z + wz
					var current: int = heightmap[idx]
					if current >= MOUNTAIN_MIN:
						continue
					if domain_map[idx] == DOMAIN_LOWLAND:
						continue
					if _is_settlement_plain_macro_column(wx, wz):
						continue

					if target_height > current:
						heightmap[idx] = target_height
						adjusted_columns += 1

	print("WorldGenerator: mountain foothill transition -> raised %d columns into approach shelves." % adjusted_columns)


func _apply_lowland_foothill_transition() -> void:
	var macro_count_x := (WORLD_SIZE_X + TERRAIN_MACRO_CELL_SIZE - 1) / TERRAIN_MACRO_CELL_SIZE
	var macro_count_z := (WORLD_SIZE_Z + TERRAIN_MACRO_CELL_SIZE - 1) / TERRAIN_MACRO_CELL_SIZE
	var far_distance := macro_count_x + macro_count_z
	var lowland_distance := PackedInt32Array()
	lowland_distance.resize(macro_count_x * macro_count_z)

	for idx in range(lowland_distance.size()):
		lowland_distance[idx] = far_distance

	for mx in range(macro_count_x):
		for mz in range(macro_count_z):
			var has_lowland := false
			var base_x := mx * TERRAIN_MACRO_CELL_SIZE
			var base_z := mz * TERRAIN_MACRO_CELL_SIZE
			for lx in range(TERRAIN_MACRO_CELL_SIZE):
				var wx := base_x + lx
				if wx >= WORLD_SIZE_X:
					break
				for lz in range(TERRAIN_MACRO_CELL_SIZE):
					var wz := base_z + lz
					if wz >= WORLD_SIZE_Z:
						break
					if heightmap[wx * WORLD_SIZE_Z + wz] <= LOWLAND_SHELF_MAX_Y:
						has_lowland = true
						break
				if has_lowland:
					break
			if has_lowland:
				lowland_distance[mx * macro_count_z + mz] = 0

	for mx in range(macro_count_x):
		for mz in range(macro_count_z):
			var idx := mx * macro_count_z + mz
			var best: int = lowland_distance[idx]
			if mx > 0:
				best = mini(best, lowland_distance[(mx - 1) * macro_count_z + mz] + 1)
			if mz > 0:
				best = mini(best, lowland_distance[mx * macro_count_z + mz - 1] + 1)
			lowland_distance[idx] = best

	for mx in range(macro_count_x - 1, -1, -1):
		for mz in range(macro_count_z - 1, -1, -1):
			var idx := mx * macro_count_z + mz
			var best: int = lowland_distance[idx]
			if mx < macro_count_x - 1:
				best = mini(best, lowland_distance[(mx + 1) * macro_count_z + mz] + 1)
			if mz < macro_count_z - 1:
				best = mini(best, lowland_distance[mx * macro_count_z + mz + 1] + 1)
			lowland_distance[idx] = best

	var adjusted_columns := 0
	for mx in range(macro_count_x):
		for mz in range(macro_count_z):
			var distance_to_lowland: int = lowland_distance[mx * macro_count_z + mz]
			var max_height := 0
			if distance_to_lowland == 1:
				max_height = FOOTHILL_SHELF_MIN_Y + FOOTHILL_SHELF_HEIGHT - 1
			elif distance_to_lowland == 2:
				max_height = FOOTHILL_SHELF_MIN_Y + (FOOTHILL_SHELF_HEIGHT * 2) - 1
			elif distance_to_lowland == 3:
				max_height = FOOTHILL_SHELF_MAX_Y
			else:
				continue

			var base_x := mx * TERRAIN_MACRO_CELL_SIZE
			var base_z := mz * TERRAIN_MACRO_CELL_SIZE
			for lx in range(TERRAIN_MACRO_CELL_SIZE):
				var wx := base_x + lx
				if wx >= WORLD_SIZE_X:
					break
				for lz in range(TERRAIN_MACRO_CELL_SIZE):
					var wz := base_z + lz
					if wz >= WORLD_SIZE_Z:
						break
					var idx := wx * WORLD_SIZE_Z + wz
					var current: int = heightmap[idx]
					if current <= LOWLAND_SHELF_MAX_Y or current >= MOUNTAIN_MIN:
						continue
					if current > max_height:
						heightmap[idx] = max_height
						adjusted_columns += 1

	print("WorldGenerator: lowland foothill transition -> capped %d columns to one-shelf steps." % adjusted_columns)


func _apply_foothill_step_limit() -> void:
	_apply_macro_shelf_step_limit()


func _apply_mountain_step_limit() -> void:
	_apply_macro_shelf_step_limit()


func _apply_macro_shelf_step_limit() -> void:
	var macro_count_x := (WORLD_SIZE_X + TERRAIN_MACRO_CELL_SIZE - 1) / TERRAIN_MACRO_CELL_SIZE
	var macro_count_z := (WORLD_SIZE_Z + TERRAIN_MACRO_CELL_SIZE - 1) / TERRAIN_MACRO_CELL_SIZE
	var macro_heights := PackedInt32Array()
	macro_heights.resize(macro_count_x * macro_count_z)

	for mx in range(macro_count_x):
		for mz in range(macro_count_z):
			macro_heights[mx * macro_count_z + mz] = _macro_cell_height(mx, mz)

	var changed := true
	while changed:
		changed = false
		var next_heights := macro_heights.duplicate()
		for mx in range(macro_count_x):
			for mz in range(macro_count_z):
				var idx := mx * macro_count_z + mz
				var current: int = macro_heights[idx]
				var current_rank := _macro_shelf_rank(current)
				if current_rank <= 0:
					continue

				var max_rank := current_rank
				for dx in range(-1, 2):
					for dz in range(-1, 2):
						if dx == 0 and dz == 0:
							continue
						var nx := mx + dx
						var nz := mz + dz
						if nx < 0 or nx >= macro_count_x or nz < 0 or nz >= macro_count_z:
							continue
						var neighbor_rank := _macro_shelf_rank(macro_heights[nx * macro_count_z + nz])
						max_rank = mini(max_rank, neighbor_rank + 1)

				if max_rank < current_rank:
					next_heights[idx] = _height_for_macro_shelf_rank(max_rank)
					changed = true

		macro_heights = next_heights

	var adjusted_columns := 0
	for mx in range(macro_count_x):
		for mz in range(macro_count_z):
			var target_height: int = macro_heights[mx * macro_count_z + mz]
			var base_x := mx * TERRAIN_MACRO_CELL_SIZE
			var base_z := mz * TERRAIN_MACRO_CELL_SIZE
			for lx in range(TERRAIN_MACRO_CELL_SIZE):
				var wx := base_x + lx
				if wx >= WORLD_SIZE_X:
					break
				for lz in range(TERRAIN_MACRO_CELL_SIZE):
					var wz := base_z + lz
					if wz >= WORLD_SIZE_Z:
						break
					var idx := wx * WORLD_SIZE_Z + wz
					var current: int = heightmap[idx]
					if current <= LOWLAND_SHELF_MAX_Y:
						continue
					if _is_settlement_plain_macro_column(wx, wz):
						continue
					if target_height < current:
						heightmap[idx] = target_height
						domain_map[idx] = _domain_for_macro_shelf_height(target_height)
						adjusted_columns += 1

	print("WorldGenerator: macro shelf step limit -> capped %d columns to adjacent one-shelf steps, including corners." % adjusted_columns)


func _apply_edge_detail() -> void:
	var source_heights := heightmap.duplicate()
	var detailed_heights := heightmap.duplicate()
	var adjusted_columns := 0
	var directions: Array[Vector2i] = [
		Vector2i(-1, 0),
		Vector2i(1, 0),
		Vector2i(0, -1),
		Vector2i(0, 1),
	]

	for x in range(WORLD_SIZE_X):
		for z in range(WORLD_SIZE_Z):
			if _is_edge_detail_protected_column(x, z):
				continue

			var source_idx := x * WORLD_SIZE_Z + z
			var source_height: int = source_heights[source_idx]
			var source_rank := _macro_shelf_rank(source_height)
			if source_rank <= 0:
				continue

			var source_step := _edge_detail_step_for_rank(source_rank)
			var lower_dirs: Array[Vector2i] = []
			for direction in directions:
				var nx := x + direction.x
				var nz := z + direction.y
				if nx < 0 or nx >= WORLD_SIZE_X or nz < 0 or nz >= WORLD_SIZE_Z:
					continue
				var neighbor_height: int = source_heights[nx * WORLD_SIZE_Z + nz]
				if source_height - neighbor_height >= source_step:
					lower_dirs.append(direction)

			if lower_dirs.size() != 1:
				continue

			var detail_depth := _edge_detail_depth(x, z, source_rank)
			var direction := lower_dirs[0]
			for distance in range(1, detail_depth + 1):
				var tx := x + (direction.x * distance)
				var tz := z + (direction.y * distance)
				if tx < 0 or tx >= WORLD_SIZE_X or tz < 0 or tz >= WORLD_SIZE_Z:
					break
				if _is_edge_detail_protected_column(tx, tz):
					break

				var target_idx := tx * WORLD_SIZE_Z + tz
				var target_height: int = source_heights[target_idx]
				if target_height >= source_height:
					break

				var detail_height := _edge_detail_height(source_height, source_rank, x, z, distance)
				if detail_height <= target_height:
					continue
				if detail_height <= detailed_heights[target_idx]:
					continue

				detailed_heights[target_idx] = detail_height
				domain_map[target_idx] = _domain_for_macro_shelf_height(detail_height)
				adjusted_columns += 1

	heightmap = detailed_heights
	print("WorldGenerator: edge detail -> pushed %d foothill/mountain edge columns." % adjusted_columns)


func _is_edge_detail_protected_column(x: int, z: int) -> bool:
	var col := Vector2i(x, z)
	return (
		_is_settlement_plain_macro_column(x, z)
		or lake_columns.has(col)
		or tarn_columns.has(col)
		or water_bank_columns.has(col)
	)


func _edge_detail_step_for_rank(rank: int) -> int:
	if rank >= 4:
		return MOUNTAIN_SHELF_HEIGHT
	return FOOTHILL_SHELF_HEIGHT


func _edge_detail_depth(x: int, z: int, rank: int) -> int:
	var max_depth := MOUNTAIN_EDGE_DETAIL_MAX_DEPTH if rank >= 4 else FOOTHILL_EDGE_DETAIL_MAX_DEPTH
	var roll: int = abs(hash(Vector3i(x / 2, rank * 13, z / 2))) % max_depth
	return 1 + roll


func _edge_detail_height(source_height: int, rank: int, x: int, z: int, distance: int) -> int:
	var step := _edge_detail_step_for_rank(rank)
	var shelf_base := source_height - step + 1
	var offset_unit := 3 if rank >= 4 else 2
	var max_offset := step - 1
	var roll: int = abs(hash(Vector3i(x / 4, (rank * 31) + distance, z / 4))) % 3
	var offset := mini(max_offset, ((distance - 1) * offset_unit) + (roll * offset_unit))
	return clampi(source_height - offset, shelf_base, source_height)


func _macro_cell_height(mx: int, mz: int) -> int:
	var base_x := mx * TERRAIN_MACRO_CELL_SIZE
	var base_z := mz * TERRAIN_MACRO_CELL_SIZE
	var counts: Dictionary = {}
	for lx in range(TERRAIN_MACRO_CELL_SIZE):
		var wx := base_x + lx
		if wx >= WORLD_SIZE_X:
			break
		for lz in range(TERRAIN_MACRO_CELL_SIZE):
			var wz := base_z + lz
			if wz >= WORLD_SIZE_Z:
				break
			var height: int = heightmap[wx * WORLD_SIZE_Z + wz]
			counts[height] = (counts.get(height, 0) as int) + 1
	return _dominant_height(counts)


func _macro_shelf_rank(height: int) -> int:
	if height <= LOWLAND_SHELF_MAX_Y:
		return 0
	if height < MOUNTAIN_MIN:
		var foothill_shelf := int(floor(float(height - FOOTHILL_SHELF_MIN_Y) / float(FOOTHILL_SHELF_HEIGHT)))
		return clampi(foothill_shelf + 1, 1, 3)
	var mountain_shelf := int(floor(float(height - MOUNTAIN_MIN) / float(MOUNTAIN_SHELF_HEIGHT)))
	return clampi(mountain_shelf + 4, 4, 9)


func _height_for_macro_shelf_rank(rank: int) -> int:
	if rank <= 0:
		return LOWLAND_SHELF_MAX_Y
	if rank <= 3:
		return FOOTHILL_SHELF_MIN_Y + ((rank - 1) * FOOTHILL_SHELF_HEIGHT) + FOOTHILL_SHELF_HEIGHT - 1
	return mini(MOUNTAIN_MAX, MOUNTAIN_MIN + ((rank - 4) * MOUNTAIN_SHELF_HEIGHT) + MOUNTAIN_SHELF_HEIGHT - 1)


func _domain_for_macro_shelf_height(height: int) -> int:
	if height <= LOWLAND_SHELF_MAX_Y:
		return DOMAIN_LOWLAND
	if height < MOUNTAIN_MIN:
		return DOMAIN_VALLEY
	return DOMAIN_MOUNTAIN


func _foothill_neighbor_cap(neighbor_height: int) -> int:
	if neighbor_height <= LOWLAND_SHELF_MAX_Y:
		return FOOTHILL_SHELF_MIN_Y + FOOTHILL_SHELF_HEIGHT - 1
	if neighbor_height >= MOUNTAIN_MIN:
		return FOOTHILL_SHELF_MAX_Y
	return mini(FOOTHILL_SHELF_MAX_Y, neighbor_height + FOOTHILL_SHELF_HEIGHT)


func _mountain_neighbor_cap(neighbor_height: int) -> int:
	if neighbor_height < MOUNTAIN_MIN:
		return MOUNTAIN_MIN + MOUNTAIN_SHELF_HEIGHT - 1
	var neighbor_shelf := int(floor(float(neighbor_height - MOUNTAIN_MIN) / float(MOUNTAIN_SHELF_HEIGHT)))
	var max_shelf := mini(neighbor_shelf + 1, 5)
	return mini(MOUNTAIN_MAX, MOUNTAIN_MIN + (max_shelf * MOUNTAIN_SHELF_HEIGHT) + MOUNTAIN_SHELF_HEIGHT - 1)


func _plateau_bias_strength(x: int, z: int, lx: int, lz: int) -> float:
	var edge_dist := mini(
		mini(lx, TERRAIN_MACRO_CELL_SIZE - 1 - lx),
		mini(lz, TERRAIN_MACRO_CELL_SIZE - 1 - lz))
	var interior := clampf(float(edge_dist) / 5.0, 0.0, 1.0)
	var broad_noise := (noise_domain.get_noise_2d(float(x) + 18000.0, float(z) + 18000.0) + 1.0) * 0.5
	return (interior * 0.65) + (broad_noise * 0.35)


func _dominant_height(height_counts: Dictionary) -> int:
	var best_height := 0
	var best_count := -1
	for height_variant: Variant in height_counts.keys():
		var height := height_variant as int
		var count := height_counts[height_variant] as int
		if count > best_count:
			best_height = height
			best_count = count
	return best_height


func _northwest_mountain_influence(x: int, z: int) -> float:
	var pos := Vector2(float(x), float(z))
	var north_influence := 1.0 - (float(z) / float(WORLD_SIZE_Z - 1))
	var west_influence := 1.0 - (float(x) / float(WORLD_SIZE_X - 1))
	var corner := sqrt(north_influence * west_influence)
	var anchor := Vector2.ZERO
	var radius := float(WORLD_SIZE_X) * 1.05
	var radial := _radial_strength(pos, anchor, radius)
	var diagonal := clampf(1.0 - ((float(x) * 0.42 + float(z)) / (float(WORLD_SIZE_Z) * 1.04)), 0.0, 1.0)
	return clampf((corner * 0.72) + (radial * 0.32) + (diagonal * 0.12), 0.0, 1.0)


func _valley_corridor_strength(x: int, z: int) -> float:
	var center_z := float(WORLD_SIZE_Z) * VALLEY_CORRIDOR_CENTER_Z_RATIO
	var spline_drop := _northwest_mountain_influence(x, z) * float(WORLD_SIZE_Z) * 0.10
	var wiggle := noise_valley.get_noise_2d(float(x) * 0.25, 3000.0) * float(WORLD_SIZE_Z) * VALLEY_CORRIDOR_WIGGLE_RATIO
	var half_width := maxf(32.0, float(WORLD_SIZE_Z) * VALLEY_CORRIDOR_HALF_WIDTH_RATIO)
	var dist := absf(float(z) - (center_z - spline_drop + wiggle))
	var t := clampf(1.0 - (dist / half_width), 0.0, 1.0)
	return t * t * (3.0 - (2.0 * t))


func _settlement_plain_strength(x: int, z: int) -> float:
	var center := Vector2(float(WORLD_SIZE_X) * 0.50, float(WORLD_SIZE_Z) * 0.48)
	var half_extents := Vector2(float(WORLD_SIZE_X) * 0.12, float(WORLD_SIZE_Z) * 0.09)
	var dx := absf(float(x) - center.x) / half_extents.x
	var dz := absf(float(z) - center.y) / half_extents.y
	var box_strength := clampf(1.0 - maxf(dx, dz), 0.0, 1.0)
	var corridor_strength := _valley_corridor_strength(x, z)
	var mountain_penalty := clampf((domain_n_map[x * WORLD_SIZE_Z + z] - 0.56) / 0.12, 0.0, 1.0)
	var strength := box_strength * box_strength * (3.0 - (2.0 * box_strength))
	return clampf(strength * corridor_strength * (1.0 - mountain_penalty), 0.0, 1.0)


func _valley_corridor_height(x: int, z: int) -> float:
	var detail := (noise_valley.get_noise_2d(x + 5000, z) + 1.0) * 0.5
	var center_bias := _valley_corridor_strength(x, z)
	var floor_height: float = lerp(float(VALLEY_CORRIDOR_MIN_Y), float(VALLEY_CORRIDOR_MIN_Y + 2), detail * 0.55)
	return lerp(float(VALLEY_CORRIDOR_MAX_Y - 1), floor_height, center_bias)


func _lowland_height(x: int, z: int) -> float:
	# z offset avoids the lowland pattern mirroring the valley pattern.
	var detail := (noise_valley.get_noise_2d(x, z + 1000) + 1.0) * 0.5
	return lerp(float(LOWLAND_RAW_HEIGHT_MIN_Y), float(LOWLAND_RAW_HEIGHT_MAX_Y), detail * 0.3)


func _southwest_basin_strength(x: int, z: int) -> float:
	var center := Vector2(float(WORLD_SIZE_X) * 0.16, float(WORLD_SIZE_Z) * 0.82)
	var radius := float(WORLD_SIZE_X) * 0.34
	return _radial_strength(Vector2(float(x), float(z)), center, radius)


func _southwest_basin_height(x: int, z: int) -> float:
	var detail := (noise_valley.get_noise_2d(x + 7000, z + 7000) + 1.0) * 0.5
	return lerp(float(LOWLAND_RAW_HEIGHT_MIN_Y), float(LOWLAND_RAW_HEIGHT_MIN_Y + 2), detail * 0.35)


func _southeast_foothill_strength(x: int, z: int) -> float:
	var center := Vector2(float(WORLD_SIZE_X) * 0.82, float(WORLD_SIZE_Z) * 0.78)
	var radius := float(WORLD_SIZE_X) * 0.30
	return _radial_strength(Vector2(float(x), float(z)), center, radius)


func _southeast_foothill_macro_strength(x: int, z: int) -> float:
	var nx := float(x) / float(maxi(WORLD_SIZE_X - 1, 1))
	var nz := float(z) / float(maxi(WORLD_SIZE_Z - 1, 1))
	var east := _smooth_unit((nx - 0.68) / 0.18)
	var south := _smooth_unit((nz - 0.62) / 0.20)
	var diagonal := _smooth_unit(((nx + nz) - 1.38) / 0.24)
	var macro_footprint := minf(east, south) * diagonal
	var corner_center := Vector2(float(WORLD_SIZE_X) * 0.84, float(WORLD_SIZE_Z) * 0.80)
	var corner_radius := float(WORLD_SIZE_X) * 0.25
	var corner_radial := _radial_strength(Vector2(float(x), float(z)), corner_center, corner_radius) * 0.55
	return maxf(corner_radial, macro_footprint)


func _southeast_foothill_height(x: int, z: int) -> float:
	var detail := (noise_valley.get_noise_2d(x - 5000, z - 5000) + 1.0) * 0.5
	return lerp(float(FOOTHILL_SHELF_MIN_Y), float(FOOTHILL_SHELF_MAX_Y), detail * 0.45)


func _world_edge_belt_strength(x: int, z: int) -> float:
	var edge_dist := mini(mini(x, WORLD_SIZE_X - 1 - x), mini(z, WORLD_SIZE_Z - 1 - z))
	return clampf(1.0 - (float(edge_dist) / float(WORLD_EDGE_BELT_WIDTH)), 0.0, 1.0)


func _radial_strength(pos: Vector2, center: Vector2, radius: float) -> float:
	if radius <= 0.0:
		return 0.0
	var t := clampf(1.0 - (pos.distance_to(center) / radius), 0.0, 1.0)
	return t * t * (3.0 - (2.0 * t))


func _smooth_unit(value: float) -> float:
	var t := clampf(value, 0.0, 1.0)
	return t * t * (3.0 - (2.0 * t))


# -- Phase 4 - Lake bodies -----------------------------------------------------

func _carve_lakes() -> void:
	_carve_lowland_lake()
	_apply_macro_shelf_step_limit()
	_carve_mountain_tarn()
	_build_water_bank_mask()


func _carve_lowland_lake() -> void:
	var macro_count_x := (WORLD_SIZE_X + TERRAIN_MACRO_CELL_SIZE - 1) / TERRAIN_MACRO_CELL_SIZE
	var macro_count_z := (WORLD_SIZE_Z + TERRAIN_MACRO_CELL_SIZE - 1) / TERRAIN_MACRO_CELL_SIZE
	var anchor := _southern_lowland_lake_macro_cell(macro_count_x, macro_count_z)
	if anchor.x < 0:
		push_warning("WorldGenerator: no lowland macro cells - lowland lake skipped.")
		return

	var selected_cells: Array[Vector2i] = []
	for mx in range(macro_count_x):
		for mz in range(macro_count_z):
			if not _lake_macro_cell_is_eligible(mx, mz, anchor):
				continue
			var shape := _lake_macro_shape(mx, mz, anchor)
			if shape <= 1.0:
				selected_cells.append(Vector2i(mx, mz))

	if not selected_cells.has(anchor):
		selected_cells.append(anchor)
	_expand_lake_to_minimum_macro_cells(selected_cells, anchor, macro_count_x, macro_count_z)

	var sum_x := 0
	var sum_z := 0
	for cell: Vector2i in selected_cells:
		sum_x += mini((cell.x * TERRAIN_MACRO_CELL_SIZE) + (TERRAIN_MACRO_CELL_SIZE / 2), WORLD_SIZE_X - 1)
		sum_z += mini((cell.y * TERRAIN_MACRO_CELL_SIZE) + (TERRAIN_MACRO_CELL_SIZE / 2), WORLD_SIZE_Z - 1)
		_apply_lowland_lake_macro_cell(cell.x, cell.y)

	_recount_domain_counts()
	lake_center = Vector2i(sum_x / selected_cells.size(), sum_z / selected_cells.size())
	print("WorldGenerator: lowland lake uses %d macro cells; southern anchor %s; water Y%d-Y%d." % [
		selected_cells.size(),
		str(anchor),
		LAKE_FLOOR_Y + 1,
		LAKE_WATERLINE,
	])


func _southern_lowland_lake_macro_cell(macro_count_x: int, macro_count_z: int) -> Vector2i:
	var southern_mz := macro_count_z - 1
	var best_cell := Vector2i(-1, -1)
	var best_score := -INF

	for mx in range(macro_count_x):
		var center_x := mini((mx * TERRAIN_MACRO_CELL_SIZE) + (TERRAIN_MACRO_CELL_SIZE / 2), WORLD_SIZE_X - 1)
		var center_z := mini((southern_mz * TERRAIN_MACRO_CELL_SIZE) + (TERRAIN_MACRO_CELL_SIZE / 2), WORLD_SIZE_Z - 1)
		var idx := center_x * WORLD_SIZE_Z + center_z
		if domain_map[idx] != DOMAIN_LOWLAND and heightmap[idx] > LOWLAND_SHELF_MAX_Y:
			continue

		var west_bias := 1.0 - (float(mx) / float(maxi(macro_count_x - 1, 1)))
		var basin_strength := _southwest_basin_strength(center_x, center_z)
		var score := (basin_strength * 2.0) + west_bias
		if score > best_score:
			best_score = score
			best_cell = Vector2i(mx, southern_mz)

	if best_cell.x >= 0:
		return best_cell

	for mx in range(macro_count_x):
		var center_x := mini((mx * TERRAIN_MACRO_CELL_SIZE) + (TERRAIN_MACRO_CELL_SIZE / 2), WORLD_SIZE_X - 1)
		var center_z := mini((southern_mz * TERRAIN_MACRO_CELL_SIZE) + (TERRAIN_MACRO_CELL_SIZE / 2), WORLD_SIZE_Z - 1)
		var west_bias := 1.0 - (float(mx) / float(maxi(macro_count_x - 1, 1)))
		var basin_strength := _southwest_basin_strength(center_x, center_z)
		var score := (basin_strength * 2.0) + west_bias
		if score > best_score:
			best_score = score
			best_cell = Vector2i(mx, southern_mz)

	return best_cell


func _lake_macro_cell_is_eligible(mx: int, mz: int, anchor: Vector2i) -> bool:
	if Vector2i(mx, mz) == anchor:
		return true
	var center_x := mini((mx * TERRAIN_MACRO_CELL_SIZE) + (TERRAIN_MACRO_CELL_SIZE / 2), WORLD_SIZE_X - 1)
	var center_z := mini((mz * TERRAIN_MACRO_CELL_SIZE) + (TERRAIN_MACRO_CELL_SIZE / 2), WORLD_SIZE_Z - 1)
	var idx := center_x * WORLD_SIZE_Z + center_z
	if domain_map[idx] == DOMAIN_MOUNTAIN:
		return false
	return heightmap[idx] < MOUNTAIN_MIN


func _lake_macro_shape(mx: int, mz: int, anchor: Vector2i) -> float:
	var dx := float(mx - anchor.x) / float(maxi(LAKE_MACRO_RADIUS_X, 1))
	var dz := float(mz - anchor.y) / float(maxi(LAKE_MACRO_RADIUS_Z, 1))
	var ellipse := sqrt((dx * dx) + (dz * dz))
	var center_x := mini((mx * TERRAIN_MACRO_CELL_SIZE) + (TERRAIN_MACRO_CELL_SIZE / 2), WORLD_SIZE_X - 1)
	var center_z := mini((mz * TERRAIN_MACRO_CELL_SIZE) + (TERRAIN_MACRO_CELL_SIZE / 2), WORLD_SIZE_Z - 1)
	var shore_noise := (noise_domain.get_noise_2d(float(center_x) * 0.075 + 9100.0, float(center_z) * 0.075 - 9100.0) + 1.0) * 0.5
	return ellipse - ((shore_noise - 0.5) * LAKE_SHORE_NOISE)


func _expand_lake_to_minimum_macro_cells(selected_cells: Array[Vector2i], anchor: Vector2i, macro_count_x: int, macro_count_z: int) -> void:
	if selected_cells.size() >= LAKE_MIN_MACRO_CELLS:
		return

	var candidates: Array = []
	for mx in range(macro_count_x):
		for mz in range(macro_count_z):
			var cell := Vector2i(mx, mz)
			if selected_cells.has(cell):
				continue
			if not _lake_macro_cell_is_eligible(mx, mz, anchor):
				continue
			candidates.append([_lake_macro_shape(mx, mz, anchor), cell])

	candidates.sort_custom(func(a: Array, b: Array) -> bool:
		return (a[0] as float) < (b[0] as float)
	)

	for row: Array in candidates:
		if selected_cells.size() >= LAKE_MIN_MACRO_CELLS:
			break
		selected_cells.append(row[1] as Vector2i)


func _apply_lowland_lake_macro_cell(mx: int, mz: int) -> void:
	var start_x := mx * TERRAIN_MACRO_CELL_SIZE
	var start_z := mz * TERRAIN_MACRO_CELL_SIZE
	var end_x := mini(WORLD_SIZE_X, start_x + TERRAIN_MACRO_CELL_SIZE)
	var end_z := mini(WORLD_SIZE_Z, start_z + TERRAIN_MACRO_CELL_SIZE)

	for x in range(start_x, end_x):
		for z in range(start_z, end_z):
			var idx := x * WORLD_SIZE_Z + z
			domain_map[idx] = DOMAIN_LOWLAND
			heightmap[idx] = LAKE_FLOOR_Y
			lake_columns[Vector2i(x, z)] = true


func _recount_domain_counts() -> void:
	var mountain_count := 0
	var valley_count := 0
	var lowland_count := 0
	for domain: int in domain_map:
		match domain:
			DOMAIN_MOUNTAIN:
				mountain_count += 1
			DOMAIN_VALLEY:
				valley_count += 1
			_:
				lowland_count += 1
	_domain_counts = {
		"mountain": mountain_count,
		"valley": valley_count,
		"lowland": lowland_count,
	}


func _carve_mountain_tarn() -> void:
	var macro_count_x := (WORLD_SIZE_X + TERRAIN_MACRO_CELL_SIZE - 1) / TERRAIN_MACRO_CELL_SIZE
	var macro_count_z := (WORLD_SIZE_Z + TERRAIN_MACRO_CELL_SIZE - 1) / TERRAIN_MACRO_CELL_SIZE
	var anchor := _mountain_tarn_anchor(macro_count_x, macro_count_z)
	if anchor.x < 0:
		push_warning("WorldGenerator: no mountain tarn cell with full M1/M2 3x3 surround - mountain tarn skipped.")
		return

	_apply_mountain_tarn_macro_cell(anchor.x, anchor.y)
	tarn_center = Vector2i(
		mini((anchor.x * TERRAIN_MACRO_CELL_SIZE) + (TERRAIN_MACRO_CELL_SIZE / 2), WORLD_SIZE_X - 1),
		mini((anchor.y * TERRAIN_MACRO_CELL_SIZE) + (TERRAIN_MACRO_CELL_SIZE / 2), WORLD_SIZE_Z - 1)
	)
	tarn_waterline = TARN_WATERLINE
	_recount_domain_counts()
	print("WorldGenerator: mountain shelf-1 tarn uses 1 macro cell; anchor %s; water Y%d-Y%d." % [
		str(anchor),
		TARN_FLOOR_Y + 1,
		tarn_waterline,
	])


func _mountain_tarn_anchor(macro_count_x: int, macro_count_z: int) -> Vector2i:
	var best_cell := Vector2i(-1, -1)
	var best_score := -INF

	for mx in range(1, macro_count_x - 1):
		for mz in range(1, macro_count_z - 1):
			if not _tarn_has_required_mountain_surround(mx, mz):
				continue

			var center_x := mini((mx * TERRAIN_MACRO_CELL_SIZE) + (TERRAIN_MACRO_CELL_SIZE / 2), WORLD_SIZE_X - 1)
			var center_z := mini((mz * TERRAIN_MACRO_CELL_SIZE) + (TERRAIN_MACRO_CELL_SIZE / 2), WORLD_SIZE_Z - 1)
			var idx := center_x * WORLD_SIZE_Z + center_z
			var domain_n := domain_n_map[idx]
			var near_mountain_edge := 1.0 - clampf(absf(domain_n - 0.64) / 0.18, 0.0, 1.0)
			var northwest_bias := _northwest_mountain_influence(center_x, center_z)
			var score := (near_mountain_edge * 2.0) + northwest_bias
			if score > best_score:
				best_score = score
				best_cell = Vector2i(mx, mz)

	return best_cell


func _tarn_has_required_mountain_surround(mx: int, mz: int) -> bool:
	# Hard rule: a mountain tarn is one water macro cell surrounded by a full
	# 3x3 macro footprint. The center must be mountain shelf 1; every surrounding
	# cell must be mountain shelf 1 or mountain shelf 2.
	if _macro_shelf_rank(_macro_cell_height(mx, mz)) != 4:
		return false

	for dx in range(-1, 2):
		for dz in range(-1, 2):
			if dx == 0 and dz == 0:
				continue
			var rank := _macro_shelf_rank(_macro_cell_height(mx + dx, mz + dz))
			if rank != 4 and rank != 5:
				return false

	return true


func _apply_mountain_tarn_macro_cell(mx: int, mz: int) -> void:
	_apply_macro_cell_height_and_domain(mx, mz, TARN_FLOOR_Y, DOMAIN_MOUNTAIN)
	for x in range(mx * TERRAIN_MACRO_CELL_SIZE, mini(WORLD_SIZE_X, (mx + 1) * TERRAIN_MACRO_CELL_SIZE)):
		for z in range(mz * TERRAIN_MACRO_CELL_SIZE, mini(WORLD_SIZE_Z, (mz + 1) * TERRAIN_MACRO_CELL_SIZE)):
			tarn_columns[Vector2i(x, z)] = true


func _apply_macro_cell_height_and_domain(mx: int, mz: int, target_height: int, target_domain: int) -> void:
	var start_x := mx * TERRAIN_MACRO_CELL_SIZE
	var start_z := mz * TERRAIN_MACRO_CELL_SIZE
	var end_x := mini(WORLD_SIZE_X, start_x + TERRAIN_MACRO_CELL_SIZE)
	var end_z := mini(WORLD_SIZE_Z, start_z + TERRAIN_MACRO_CELL_SIZE)

	for x in range(start_x, end_x):
		for z in range(start_z, end_z):
			var idx := x * WORLD_SIZE_Z + z
			domain_map[idx] = target_domain
			heightmap[idx] = target_height


func _sink_water_columns_below_waterline(columns: Dictionary, waterline: int) -> void:
	for col_variant: Variant in columns.keys():
		var col := col_variant as Vector2i
		if heightmap[col.x * WORLD_SIZE_Z + col.y] >= waterline:
			heightmap[col.x * WORLD_SIZE_Z + col.y] = waterline - 1


func _water_shape_value(x: int, z: int, center: Vector2i, radius_x: float, radius_z: float, rotation: float, noise_amount: float, salt: float) -> float:
	if radius_x <= 0.0 or radius_z <= 0.0:
		return 999.0
	var dx := float(x - center.x)
	var dz := float(z - center.y)
	var cos_r := cos(rotation)
	var sin_r := sin(rotation)
	var local_x := (dx * cos_r) - (dz * sin_r)
	var local_z := (dx * sin_r) + (dz * cos_r)
	var ellipse := sqrt((local_x * local_x) / (radius_x * radius_x) + (local_z * local_z) / (radius_z * radius_z))
	var shore_noise := (noise_domain.get_noise_2d(float(x) * 0.075 + salt, float(z) * 0.075 - salt) + 1.0) * 0.5
	return ellipse - ((shore_noise - 0.5) * noise_amount)


func _build_water_bank_mask() -> void:
	water_bank_columns.clear()
	for water_set: Dictionary in [lake_columns, tarn_columns]:
		for water_col_variant: Variant in water_set.keys():
			var water_col := water_col_variant as Vector2i
			for dx in range(-WATER_BANK_RADIUS, WATER_BANK_RADIUS + 1):
				for dz in range(-WATER_BANK_RADIUS, WATER_BANK_RADIUS + 1):
					if absi(dx) + absi(dz) > WATER_BANK_RADIUS:
						continue
					var wx := water_col.x + dx
					var wz := water_col.y + dz
					if wx < 0 or wx >= WORLD_SIZE_X or wz < 0 or wz >= WORLD_SIZE_Z:
						continue
					var bank_col := Vector2i(wx, wz)
					if lake_columns.has(bank_col) or tarn_columns.has(bank_col):
						continue
					water_bank_columns[bank_col] = true


func _build_lowland_cap_grass_band_map() -> void:
	var total_columns := WORLD_SIZE_X * WORLD_SIZE_Z
	lowland_cap_grass_band_map.resize(total_columns)
	lowland_cap_grass_band_map.fill(0)
	lowland_cap_grass_distance_map.resize(total_columns)
	lowland_cap_grass_distance_map.fill(-1)

	var distances := PackedInt32Array()
	distances.resize(total_columns)
	distances.fill(-1)

	var queue: Array[int] = []
	var head := 0

	for x in range(WORLD_SIZE_X):
		for z in range(WORLD_SIZE_Z):
			var idx := x * WORLD_SIZE_Z + z
			if not _is_lowland_cap_grass_band_column(x, z, idx):
				continue
			lowland_cap_grass_band_map[idx] = 4
			if _is_lowland_cap_grass_band_seed(x, z):
				lowland_cap_grass_band_map[idx] = 1
				distances[idx] = 0
				lowland_cap_grass_distance_map[idx] = 0
				queue.append(idx)

	while head < queue.size():
		var idx := queue[head]
		head += 1

		var distance := distances[idx]
		if distance >= LOWLAND_CAP_GRASS_EDGE_TOTAL_DISTANCE - 1:
			continue

		var x := idx / WORLD_SIZE_Z
		var z := idx % WORLD_SIZE_Z
		for offset: Vector2i in _lowland_cap_neighbor_offsets():
			var nx := x + offset.x
			var nz := z + offset.y
			if nx < 0 or nx >= WORLD_SIZE_X or nz < 0 or nz >= WORLD_SIZE_Z:
				continue
			var nidx := nx * WORLD_SIZE_Z + nz
			if lowland_cap_grass_band_map[nidx] == 0 or distances[nidx] != -1:
				continue

			var next_distance := distance + 1
			distances[nidx] = next_distance
			lowland_cap_grass_distance_map[nidx] = next_distance
			lowland_cap_grass_band_map[nidx] = _lowland_cap_grass_band_for_distance(next_distance)
			queue.append(nidx)


func _is_lowland_cap_grass_band_column(x: int, z: int, idx: int) -> bool:
	if heightmap[idx] != LOWLAND_SHELF_MAX_Y:
		return false
	var col := Vector2i(x, z)
	return not lake_columns.has(col) and not tarn_columns.has(col)


func _is_lowland_cap_grass_band_seed(x: int, z: int) -> bool:
	for offset: Vector2i in _lowland_cap_neighbor_offsets():
		var nx := x + offset.x
		var nz := z + offset.y
		if nx < 0 or nx >= WORLD_SIZE_X or nz < 0 or nz >= WORLD_SIZE_Z:
			continue

		var col := Vector2i(nx, nz)
		if lake_columns.has(col):
			return true

		var nidx := nx * WORLD_SIZE_Z + nz
		if _is_lowland_cap_grass_edge_source(nidx):
			return true

	return false


func _lowland_cap_neighbor_offsets() -> Array[Vector2i]:
	return [
		Vector2i(1, 0),
		Vector2i(-1, 0),
		Vector2i(0, 1),
		Vector2i(0, -1),
		Vector2i(1, 1),
		Vector2i(1, -1),
		Vector2i(-1, 1),
		Vector2i(-1, -1),
	]


func _is_lowland_cap_grass_edge_source(idx: int) -> bool:
	var h: int = heightmap[idx]
	return h > LOWLAND_SHELF_MAX_Y


func _lowland_cap_grass_band_for_distance(distance: int) -> int:
	if distance < LOWLAND_CAP_GRASS_EDGE_1_WIDTH:
		return 1
	if distance < LOWLAND_CAP_GRASS_EDGE_1_WIDTH + LOWLAND_CAP_GRASS_EDGE_2_WIDTH:
		return 2
	if distance < LOWLAND_CAP_GRASS_EDGE_TOTAL_DISTANCE:
		return 3
	return 4


func _foothill_cap_grass_band_for_distance(distance: int) -> int:
	if distance < FOOTHILL_CAP_GRASS_EDGE_1_WIDTH:
		return 1
	if distance < FOOTHILL_CAP_GRASS_EDGE_1_WIDTH + FOOTHILL_CAP_GRASS_EDGE_2_WIDTH:
		return 2
	if distance < FOOTHILL_CAP_GRASS_EDGE_TOTAL_DISTANCE:
		return 3
	return 4


func _build_foothill_cap_grass_band_map() -> void:
	var total_columns := WORLD_SIZE_X * WORLD_SIZE_Z
	foothill_cap_grass_band_map.resize(total_columns)
	foothill_cap_grass_band_map.fill(0)
	foothill_cap_grass_distance_map.resize(total_columns)
	foothill_cap_grass_distance_map.fill(-1)

	var distances := PackedInt32Array()
	distances.resize(total_columns)
	distances.fill(-1)

	var queue: Array[int] = []
	var head := 0

	for x in range(WORLD_SIZE_X):
		for z in range(WORLD_SIZE_Z):
			var idx := x * WORLD_SIZE_Z + z
			if not _is_foothill_cap_grass_band_column(x, z):
				continue
			foothill_cap_grass_band_map[idx] = 4
			if _is_foothill_cap_grass_band_seed(x, z, idx):
				foothill_cap_grass_band_map[idx] = 1
				distances[idx] = 0
				foothill_cap_grass_distance_map[idx] = 0
				queue.append(idx)

	while head < queue.size():
		var idx := queue[head]
		head += 1

		var distance := distances[idx]
		if distance >= FOOTHILL_CAP_GRASS_EDGE_TOTAL_DISTANCE - 1:
			continue

		var x := idx / WORLD_SIZE_Z
		var z := idx % WORLD_SIZE_Z
		for offset: Vector2i in _lowland_cap_neighbor_offsets():
			var nx := x + offset.x
			var nz := z + offset.y
			if nx < 0 or nx >= WORLD_SIZE_X or nz < 0 or nz >= WORLD_SIZE_Z:
				continue
			var nidx := nx * WORLD_SIZE_Z + nz
			if foothill_cap_grass_band_map[nidx] == 0 or distances[nidx] != -1:
				continue

			var next_distance := distance + 1
			distances[nidx] = next_distance
			foothill_cap_grass_distance_map[nidx] = next_distance
			foothill_cap_grass_band_map[nidx] = _foothill_cap_grass_band_for_distance(next_distance)
			queue.append(nidx)


func _is_foothill_cap_grass_band_column(x: int, z: int) -> bool:
	if not _is_foothill_shelf_column(x, z):
		return false
	var col := Vector2i(x, z)
	return not lake_columns.has(col) and not tarn_columns.has(col)


func _is_foothill_cap_grass_band_seed(x: int, z: int, idx: int) -> bool:
	var center_height := heightmap[idx]
	for offset: Vector2i in _lowland_cap_neighbor_offsets():
		var nx := x + offset.x
		var nz := z + offset.y
		if nx < 0 or nx >= WORLD_SIZE_X or nz < 0 or nz >= WORLD_SIZE_Z:
			continue

		var col := Vector2i(nx, nz)
		if lake_columns.has(col) or tarn_columns.has(col):
			return true

		var nidx := nx * WORLD_SIZE_Z + nz
		if heightmap[nidx] != center_height:
			return true

	return false


# -- Generation metrics -------------------------------------------------------

func _build_generation_metrics() -> void:
	var total_columns := WORLD_SIZE_X * WORLD_SIZE_Z
	var lake_floor := _water_floor_metrics(lake_columns, LAKE_WATERLINE)
	var tarn_floor := _water_floor_metrics(tarn_columns, tarn_waterline)
	_generation_metrics = {
		"seed": world_seed,
		"world_size": Vector3i(WORLD_SIZE_X, WORLD_SIZE_Y, WORLD_SIZE_Z),
		"domains": {
			"mountain": _domain_counts.get("mountain", 0),
			"valley": _domain_counts.get("valley", 0),
			"lowland": _domain_counts.get("lowland", 0),
			"mountain_pct": _pct(_domain_counts.get("mountain", 0), total_columns),
			"valley_pct": _pct(_domain_counts.get("valley", 0), total_columns),
			"lowland_pct": _pct(_domain_counts.get("lowland", 0), total_columns),
		},
		"heights": _compute_height_metrics(),
		"surface": _compute_surface_metrics(),
		"macro": _compute_macro_layout_metrics(),
		"shaping": {
			"terraced_columns": _terraced_columns,
			"terraced_pct": _pct(_terraced_columns, total_columns),
			"plateau_adjusted_columns": _plateau_adjusted_columns,
			"plateau_adjusted_pct": _pct(_plateau_adjusted_columns, total_columns),
			"plateau_smoothed_chunks": _plateau_smoothed_chunks,
		},
		"water": {
			"lake_center": lake_center,
			"lake_radius": LAKE_RADIUS,
			"lake_waterline": LAKE_WATERLINE,
			"lake_columns": lake_columns.size(),
			"lake_floor_min": lake_floor.get("floor_min", 0),
			"lake_floor_max": lake_floor.get("floor_max", 0),
			"lake_depth_max": lake_floor.get("depth_max", 0),
			"tarn_center": tarn_center,
			"tarn_radius": TARN_RADIUS,
			"tarn_waterline": tarn_waterline,
			"tarn_columns": tarn_columns.size(),
			"tarn_floor_min": tarn_floor.get("floor_min", 0),
			"tarn_floor_max": tarn_floor.get("floor_max", 0),
			"tarn_depth_max": tarn_floor.get("depth_max", 0),
			"bank_columns": water_bank_columns.size(),
		},
		"settlement_candidates": _compute_settlement_candidate_metrics(),
	}


func _water_floor_metrics(columns: Dictionary, waterline: int) -> Dictionary:
	if columns.is_empty():
		return {"floor_min": 0, "floor_max": 0, "depth_max": 0}
	var floor_min := WORLD_SIZE_Y
	var floor_max := 0
	for col_variant: Variant in columns.keys():
		var col := col_variant as Vector2i
		var floor_y: int = heightmap[col.x * WORLD_SIZE_Z + col.y]
		floor_min = mini(floor_min, floor_y)
		floor_max = maxi(floor_max, floor_y)
	return {
		"floor_min": floor_min,
		"floor_max": floor_max,
		"depth_max": maxi(0, waterline - floor_min),
	}


func _compute_height_metrics() -> Dictionary:
	var total_columns := WORLD_SIZE_X * WORLD_SIZE_Z
	var min_h := WORLD_SIZE_Y
	var max_h := 0
	var sum_h := 0
	var by_domain := {
		"mountain": _new_height_bucket(),
		"valley": _new_height_bucket(),
		"lowland": _new_height_bucket(),
	}

	for x in range(WORLD_SIZE_X):
		for z in range(WORLD_SIZE_Z):
			var idx := x * WORLD_SIZE_Z + z
			var h: int = heightmap[idx]
			min_h = mini(min_h, h)
			max_h = maxi(max_h, h)
			sum_h += h

			var bucket: Dictionary = by_domain[_domain_label(domain_map[idx])]
			bucket["count"] = (bucket.get("count", 0) as int) + 1
			bucket["min"] = mini(bucket.get("min", WORLD_SIZE_Y) as int, h)
			bucket["max"] = maxi(bucket.get("max", 0) as int, h)
			bucket["sum"] = (bucket.get("sum", 0) as int) + h

	for key: String in by_domain.keys():
		var bucket: Dictionary = by_domain[key]
		var count := bucket.get("count", 0) as int
		bucket["avg"] = float(bucket.get("sum", 0) as int) / float(maxi(count, 1))
		bucket.erase("sum")

	return {
		"min": min_h,
		"max": max_h,
		"avg": float(sum_h) / float(maxi(total_columns, 1)),
		"by_domain": by_domain,
	}


func _compute_surface_metrics() -> Dictionary:
	var counts := {
		"grass": 0,
		"dirt": 0,
		"rock": 0,
		"water": 0,
		"other": 0,
	}
	var total_columns := WORLD_SIZE_X * WORLD_SIZE_Z
	var by_domain := {
		"mountain": _new_surface_bucket(),
		"valley": _new_surface_bucket(),
		"lowland": _new_surface_bucket(),
	}

	for x in range(WORLD_SIZE_X):
		for z in range(WORLD_SIZE_Z):
			var col := Vector2i(x, z)
			var block_id := _id_water if lake_columns.has(col) or tarn_columns.has(col) else _pick_surface_block(x, z, col)
			var category := _surface_category(block_id)
			counts[category] = (counts[category] as int) + 1
			var bucket: Dictionary = by_domain[_domain_label(domain_map[x * WORLD_SIZE_Z + z])]
			bucket[category] = (bucket[category] as int) + 1
			bucket["total"] = (bucket["total"] as int) + 1

	for key: String in by_domain.keys():
		_add_surface_bucket_percentages(by_domain[key])

	return {
		"grass": counts["grass"],
		"dirt": counts["dirt"],
		"rock": counts["rock"],
		"water": counts["water"],
		"other": counts["other"],
		"grass_pct": _pct(counts["grass"] as int, total_columns),
		"dirt_pct": _pct(counts["dirt"] as int, total_columns),
		"rock_pct": _pct(counts["rock"] as int, total_columns),
		"water_pct": _pct(counts["water"] as int, total_columns),
		"other_pct": _pct(counts["other"] as int, total_columns),
		"by_domain": by_domain,
	}


func _compute_macro_layout_metrics() -> Dictionary:
	var basin_columns := 0
	var southeast_foothill_columns := 0
	var edge_columns := 0
	var basin_peak := 0.0
	var southeast_foothill_peak := 0.0

	for x in range(WORLD_SIZE_X):
		for z in range(WORLD_SIZE_Z):
			var basin := _southwest_basin_strength(x, z)
			var southeast_foothill := _southeast_foothill_strength(x, z)
			var edge := _world_edge_belt_strength(x, z)
			if basin > 0.25:
				basin_columns += 1
			if southeast_foothill > 0.25:
				southeast_foothill_columns += 1
			if edge > 0.0:
				edge_columns += 1
			basin_peak = maxf(basin_peak, basin)
			southeast_foothill_peak = maxf(southeast_foothill_peak, southeast_foothill)

	return {
		"southwest_basin_columns": basin_columns,
		"southwest_basin_peak": basin_peak,
		"southeast_foothill_columns": southeast_foothill_columns,
		"southeast_foothill_peak": southeast_foothill_peak,
		"edge_belt_columns": edge_columns,
		"edge_belt_width": WORLD_EDGE_BELT_WIDTH,
	}


func _compute_settlement_candidate_metrics() -> Dictionary:
	const CANDIDATE_SIZE := 20
	const CANDIDATE_STEP := 8
	const MAX_HEIGHT_DELTA := 2
	var count := 0
	var examples: Array[Vector2i] = []

	for x in range(0, WORLD_SIZE_X - CANDIDATE_SIZE, CANDIDATE_STEP):
		for z in range(0, WORLD_SIZE_Z - CANDIDATE_SIZE, CANDIDATE_STEP):
			var min_h := WORLD_SIZE_Y
			var max_h := 0
			var has_water := false
			var mountain_edge_score := 0

			for lx in range(CANDIDATE_SIZE):
				for lz in range(CANDIDATE_SIZE):
					var wx := x + lx
					var wz := z + lz
					var idx := wx * WORLD_SIZE_Z + wz
					var h: int = heightmap[idx]
					min_h = mini(min_h, h)
					max_h = maxi(max_h, h)
					if lake_columns.has(Vector2i(wx, wz)) or tarn_columns.has(Vector2i(wx, wz)):
						has_water = true
					var n := domain_n_map[idx]
					if n > 0.50 and n < 0.72:
						mountain_edge_score += 1

			if has_water:
				continue
			if max_h - min_h > MAX_HEIGHT_DELTA:
				continue
			if mountain_edge_score < CANDIDATE_SIZE * CANDIDATE_SIZE / 4:
				continue

			count += 1
			if examples.size() < 5:
				examples.append(Vector2i(x + CANDIDATE_SIZE / 2, z + CANDIDATE_SIZE / 2))

	return {
		"count": count,
		"sample_size": CANDIDATE_SIZE,
		"sample_step": CANDIDATE_STEP,
		"max_height_delta": MAX_HEIGHT_DELTA,
		"examples": examples,
	}


func _new_height_bucket() -> Dictionary:
	return {"count": 0, "min": WORLD_SIZE_Y, "max": 0, "sum": 0}


func _new_surface_bucket() -> Dictionary:
	return {"grass": 0, "dirt": 0, "rock": 0, "water": 0, "other": 0, "total": 0}


func _add_surface_bucket_percentages(bucket: Dictionary) -> void:
	var total := bucket.get("total", 0) as int
	bucket["grass_pct"] = _pct(bucket.get("grass", 0) as int, total)
	bucket["dirt_pct"] = _pct(bucket.get("dirt", 0) as int, total)
	bucket["rock_pct"] = _pct(bucket.get("rock", 0) as int, total)
	bucket["water_pct"] = _pct(bucket.get("water", 0) as int, total)
	bucket["other_pct"] = _pct(bucket.get("other", 0) as int, total)


func _surface_category(block_id: int) -> String:
	if _grass_ids.has(block_id):
		return "grass"
	if _dirt_ids.has(block_id):
		return "dirt"
	if block_id == _id_water:
		return "water"
	if block_id == _id_rock07 or block_id == _id_rock08 or block_id == _id_rock09 or block_id == _id_rock10 or block_id == _id_rock11 or _mountain_rock_ids.has(block_id):
		return "rock"
	return "other"


func _domain_label(domain: int) -> String:
	match domain:
		DOMAIN_MOUNTAIN:
			return "mountain"
		DOMAIN_VALLEY:
			return "valley"
	return "lowland"


func _pct(value: int, total: int) -> float:
	if total <= 0:
		return 0.0
	return float(value) / float(total) * 100.0


# -- Phase 5 - Block fill (3D, per chunk) --------------------------------------

func _fill_all_chunks() -> void:
	# Highest block any column in a chunk could contain = max surface in that
	# chunk's 16x16 footprint, but never below the lake waterline (water fills
	# above the carved floor). Chunk-Y layers entirely above this are pure void -
	# we skip generating AND meshing them. Most of the map is lowland, so
	# this prunes the upper ~half of every column instead of filling 8 layers of
	# mostly-air to Y 127. Missing chunks read back as AIR via WorldData.get_block.
	var skipped := 0
	for cx in range(CHUNK_COUNT_X):
		# Bail out cleanly if the game is stopping (see _exit_tree).
		if _abort:
			print("WorldGenerator: generation aborted at cx=%d." % cx)
			return
		for cz in range(CHUNK_COUNT_Z):
			# Tallest surface (or waterline) in this chunk column's footprint.
			var top_y := _column_chunk_max_y(cx, cz)
			var top_cy := top_y / CHUNK_SIZE   # highest chunk-Y that holds blocks

			for cy in range(CHUNK_COUNT_Y):
				if cy > top_cy:
					skipped += 1
					continue   # pure-void chunk - never generated, never meshed

				var chunk := Chunk.new()
				var found_void := false
				for ly in range(CHUNK_SIZE):
					var wy := cy * CHUNK_SIZE + ly
					for lx in range(CHUNK_SIZE):
						var wx := cx * CHUNK_SIZE + lx
						for lz in range(CHUNK_SIZE):
							var wz := cz * CHUNK_SIZE + lz
							var bid := _generate_block_id(wx, wy, wz)
							_count_block_spawn(bid)
							if bid == _id_void:
								found_void = true
							chunk.blocks[Chunk.local_index(lx, ly, lz)] = bid
				# Solid interior chunks (no void) can be skipped at mesh time if
				# all six neighbours are also solid - see WorldRenderer.
				chunk.has_void = found_void
				WorldData.submit_chunk(cx, cy, cz, chunk)
				call_deferred("_deferred_emit_chunk_generated", cx, cy, cz)
			_counted_columns += 1
			_maybe_defer_block_spawn_report()

	print("WorldGenerator: skipped %d all-void chunks (of %d)." % [
		skipped, CHUNK_COUNT_X * CHUNK_COUNT_Y * CHUNK_COUNT_Z])
	_maybe_defer_block_spawn_report(true)


## Highest world-Y that a chunk column (cx, cz) can contain a non-void block.
## Scans the column's 16x16 surface footprint and clamps to at least the lake
## waterline so water-filled basins above the carved floor are not pruned.
## Same fill pass as _fill_all_chunks(), but visits chunk columns from the world
## center outward. The debug camera starts at the world center, so this avoids a
## blank fog screen while corner chunks generate first.
func _fill_all_chunks_center_first() -> void:
	var skipped := 0

	for col: Vector2i in _chunk_columns_center_first():
		var cx := col.x
		var cz := col.y

		if _abort:
			print("WorldGenerator: generation aborted at cx=%d." % cx)
			return

		var top_y := _column_chunk_max_y(cx, cz)
		var top_cy := top_y / CHUNK_SIZE

		for cy in range(CHUNK_COUNT_Y):
			if cy > top_cy:
				skipped += 1
				continue

			var chunk := Chunk.new()
			var found_void := false
			for ly in range(CHUNK_SIZE):
				var wy := cy * CHUNK_SIZE + ly
				for lx in range(CHUNK_SIZE):
					var wx := cx * CHUNK_SIZE + lx
					for lz in range(CHUNK_SIZE):
						var wz := cz * CHUNK_SIZE + lz
						var bid := _generate_block_id(wx, wy, wz)
						_count_block_spawn(bid)
						if bid == _id_void:
							found_void = true
						chunk.blocks[Chunk.local_index(lx, ly, lz)] = bid

			chunk.has_void = found_void
			WorldData.submit_chunk(cx, cy, cz, chunk)
			call_deferred("_deferred_emit_chunk_generated", cx, cy, cz)
		_counted_columns += 1
		_maybe_defer_block_spawn_report()

	print("WorldGenerator: skipped %d all-void chunks (of %d)." % [
		skipped, CHUNK_COUNT_X * CHUNK_COUNT_Y * CHUNK_COUNT_Z])
	_maybe_defer_block_spawn_report(true)


func _process_requested_columns() -> void:
	while not _abort:
		var col := _pop_requested_column()
		if col.x < 0:
			OS.delay_msec(10)
			continue

		_fill_chunk_column(col.x, col.y)
		_request_mutex.lock()
		_generated_columns[col] = true
		_requested_columns.erase(col)
		_column_in_flight = false
		_request_mutex.unlock()
		_counted_columns += 1
		_maybe_defer_block_spawn_report()


func _pop_requested_column() -> Vector2i:
	_request_mutex.lock()
	if _column_queue.is_empty():
		_request_mutex.unlock()
		return Vector2i(-1, -1)
	var col: Vector2i = _column_queue.pop_front()
	_column_in_flight = true
	_request_mutex.unlock()
	return col


func _fill_chunk_column(cx: int, cz: int) -> void:
	var t_column_start := Time.get_ticks_msec()
	var submitted_chunks := 0
	var top_y := _column_chunk_max_y(cx, cz)
	var top_cy := top_y / CHUNK_SIZE

	for cy in range(CHUNK_COUNT_Y):
		if _abort:
			return
		if cy > top_cy:
			continue

		var chunk := Chunk.new()
		var found_void := false
		for ly in range(CHUNK_SIZE):
			var wy := cy * CHUNK_SIZE + ly
			for lx in range(CHUNK_SIZE):
				var wx := cx * CHUNK_SIZE + lx
				for lz in range(CHUNK_SIZE):
					var wz := cz * CHUNK_SIZE + lz
					var bid := _generate_block_id(wx, wy, wz)
					_count_block_spawn(bid)
					if bid == _id_void:
						found_void = true
					chunk.blocks[Chunk.local_index(lx, ly, lz)] = bid

		chunk.has_void = found_void
		WorldData.submit_chunk(cx, cy, cz, chunk)
		call_deferred("_deferred_emit_chunk_generated", cx, cy, cz)
		submitted_chunks += 1

	var elapsed := Time.get_ticks_msec() - t_column_start
	_request_mutex.lock()
	_column_fill_count += 1
	_column_fill_msec_total += elapsed
	_column_fill_msec_max = maxi(_column_fill_msec_max, elapsed)
	_column_chunks_submitted += submitted_chunks
	_request_mutex.unlock()


func _reset_block_spawn_counts() -> void:
	_block_spawn_counts.clear()
	_counted_columns = 0
	_last_count_report_column = 0


func _count_block_spawn(block_id: int) -> void:
	_block_spawn_counts[block_id] = (_block_spawn_counts.get(block_id, 0) as int) + 1


func _maybe_defer_block_spawn_report(force: bool = false) -> void:
	if _counted_columns <= 0:
		return
	if not force and _counted_columns != 1:
		var columns_since_report := _counted_columns - _last_count_report_column
		if columns_since_report < BLOCK_COUNT_REPORT_INTERVAL_COLUMNS:
			return

	_last_count_report_column = _counted_columns
	call_deferred(
		"_deferred_print_block_spawn_report",
		_block_spawn_counts.duplicate(),
		_counted_columns,
		CHUNK_COUNT_X * CHUNK_COUNT_Z
	)


func _chunk_columns_center_first() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var center := Vector2i(CHUNK_COUNT_X / 2, CHUNK_COUNT_Z / 2)
	var max_radius := maxi(CHUNK_COUNT_X, CHUNK_COUNT_Z)

	for radius in range(max_radius):
		for dx in range(-radius, radius + 1):
			for dz in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dz)) != radius:
					continue
				var cx := center.x + dx
				var cz := center.y + dz
				if cx < 0 or cx >= CHUNK_COUNT_X or cz < 0 or cz >= CHUNK_COUNT_Z:
					continue
				result.append(Vector2i(cx, cz))

	return result


func _column_chunk_max_y(cx: int, cz: int) -> int:
	var max_y := LAKE_WATERLINE
	var base_x := cx * CHUNK_SIZE
	var base_z := cz * CHUNK_SIZE
	for lx in range(CHUNK_SIZE):
		var wx := base_x + lx
		for lz in range(CHUNK_SIZE):
			var wz := base_z + lz
			var h: int = heightmap[wx * WORLD_SIZE_Z + wz]
			if h > max_y:
				max_y = h
	return max_y


func _generate_block_id(x: int, y: int, z: int) -> int:
	var col    := Vector2i(x, z)
	var surf_y := heightmap[x * WORLD_SIZE_Z + z]

	# Absolute floor - four-layer bedrock protocol.
	if y <= BEDROCK_MAX_Y:
		return _id_bedrock

	# Stable foundation layer above bedrock.
	if y > BEDROCK_MAX_Y and y <= FOUNDATION_ROCK_MAX_Y:
		return _apply_resource_veins(x, y, z, surf_y, _id_rock11)

	# Above surface
	if y > surf_y:
		if lake_columns.has(col) and y <= LAKE_WATERLINE:
			return _id_water
		if tarn_columns.has(col) and y <= tarn_waterline:
			return _id_water
		return _id_void

	if _is_lowland_shelf_column(x, z) and y >= LOWLAND_SHELF_MIN_Y and y <= LOWLAND_SHELF_MAX_Y:
		var lowland_block := _lowland_shelf_block_id(x, z, y)
		return _apply_resource_veins(x, y, z, surf_y, lowland_block)

	if _is_foothill_shelf_column(x, z) and y >= LOWLAND_SHELF_MIN_Y and y < _foothill_shelf_start_for_column(x, z):
		var foothill_body_block := _foothill_body_rock_id(y)
		return _apply_resource_veins(x, y, z, surf_y, foothill_body_block)

	if _is_foothill_shelf_column(x, z) and y >= FOOTHILL_SHELF_MIN_Y and y <= FOOTHILL_SHELF_MAX_Y:
		var foothill_shelf_block := _foothill_shelf_block_id(x, z, y)
		return _apply_resource_veins(x, y, z, surf_y, foothill_shelf_block)

	if _is_mountain_shelf_column(x, z) and y >= LOWLAND_SHELF_MIN_Y and y < MOUNTAIN_MIN:
		var mountain_body_block := _altitude_rock_body_id(y)
		return _apply_resource_veins(x, y, z, surf_y, mountain_body_block)

	if _is_mountain_shelf_column(x, z) and y >= MOUNTAIN_MIN and y <= MOUNTAIN_MAX:
		var mountain_shelf_block := _mountain_shelf_block_id(y)
		return _apply_resource_veins(x, y, z, surf_y, mountain_shelf_block)

	# Surface skin
	if y == surf_y:
		return _pick_surface_block(x, z, col)

	# Underground volume - evaluate noise LAZILY. The 3D noise samples are the
	# dominant generation cost, so we only compute each one when it can actually
	# affect the result, and return as early as possible.

	# Cave void - only possible deeper than 5 blocks below the surface.
	if y < surf_y - 5:
		var n_cave := (noise_cave.get_noise_3d(x, y, z) + 1.0) * 0.5
		if n_cave > 0.65:
			return _id_void

	# Fallback for columns outside authored strata ranges. Current worldgen
	# should rarely reach this; keep it on the active rock ladder if it does.
	var fallback_rock := _fallback_rock_id(y)
	return _apply_resource_veins(x, y, z, surf_y, fallback_rock)


func _pick_surface_block(x: int, z: int, col: Vector2i) -> int:
	var idx := x * WORLD_SIZE_Z + z
	var height := heightmap[idx]
	var slope := _surface_slope(x, z)
	var domain := domain_map[idx]
	var region := _surface_region_value(x, z, 0)

	# Submerged floors and immediate banks are soil/stone, never grass.
	if lake_columns.has(col) or tarn_columns.has(col):
		if _surface_region_value(x, z, 7) > 0.72:
			return _pick_surface_rock(x, z, height)
		return _dirt_variant(x, z)
	if _is_water_bank(x, z):
		if slope >= 2 or _surface_region_value(x, z, 11) > 0.68:
			return _pick_surface_rock(x, z, height)
		return _dirt_variant(x, z)

	if slope >= STEEP_SLOPE_ROCK_DELTA:
		return _pick_surface_rock(x, z, height)

	if domain == DOMAIN_MOUNTAIN:
		var sheltered_shelf := slope <= 1 and height < 96 and domain_n_map[idx] < 0.68
		if sheltered_shelf and region > 0.94:
			return _grass_variant(x, z)
		if sheltered_shelf and region > 0.86:
			return _dirt_variant(x, z)
		return _pick_surface_rock(x, z, height)

	if domain == DOMAIN_VALLEY:
		if slope >= 2 and _surface_region_value(x, z, 17) > 0.35:
			return _pick_surface_rock(x, z, height)
		if region < 0.50:
			return _grass_variant(x, z)
		if region < 0.82:
			return _dirt_variant(x, z)
		return _pick_surface_rock(x, z, height)

	if _southeast_foothill_strength(x, z) > 0.35 and domain != DOMAIN_LOWLAND:
		if region < 0.42:
			return _grass_variant(x, z)
		if region < 0.66:
			return _dirt_variant(x, z)
		return _pick_surface_rock(x, z, height)

	if _southwest_basin_strength(x, z) > 0.30:
		if region < 0.48:
			return _dirt_variant(x, z)
		if region < 0.86:
			return _grass_variant(x, z)
		return _pick_surface_rock(x, z, height)

	if region < 0.62:
		return _grass_variant(x, z)
	if region < 0.86:
		return _dirt_variant(x, z)
	return _pick_surface_rock(x, z, height)

func _surface_slope(x: int, z: int) -> int:
	var center := heightmap[x * WORLD_SIZE_Z + z]
	var max_delta := 0
	if x > 0:
		max_delta = maxi(max_delta, absi(center - heightmap[(x - 1) * WORLD_SIZE_Z + z]))
	if x < WORLD_SIZE_X - 1:
		max_delta = maxi(max_delta, absi(center - heightmap[(x + 1) * WORLD_SIZE_Z + z]))
	if z > 0:
		max_delta = maxi(max_delta, absi(center - heightmap[x * WORLD_SIZE_Z + z - 1]))
	if z < WORLD_SIZE_Z - 1:
		max_delta = maxi(max_delta, absi(center - heightmap[x * WORLD_SIZE_Z + z + 1]))
	return max_delta


func _is_water_bank(x: int, z: int) -> bool:
	return water_bank_columns.has(Vector2i(x, z))


func _surface_region_value(x: int, z: int, salt: int) -> float:
	var macro := Vector3i(x / MATERIAL_MACRO_CELL_SIZE, salt, z / MATERIAL_MACRO_CELL_SIZE)
	var macro_hash := float(abs(hash(macro)) % 1000) / 999.0
	var field := (noise_domain.get_noise_2d(float(x) * 0.12 + float(salt * 997), float(z) * 0.12 - float(salt * 541)) + 1.0) * 0.5
	return clampf((macro_hash * 0.62) + (field * 0.38), 0.0, 1.0)


func _grass_variant(x: int, z: int) -> int:
	if _grass_ids.is_empty():
		return _id_rock10

	var lowland_cap_band_index := _lowland_cap_grass_band_variant_index(x, z)
	if lowland_cap_band_index >= 0:
		return _grass_ids[mini(lowland_cap_band_index, _grass_ids.size() - 1)]

	var foothill_cap_band_index := _foothill_cap_grass_band_variant_index(x, z)
	if foothill_cap_band_index >= 0:
		return _grass_ids[mini(4 + foothill_cap_band_index, _grass_ids.size() - 1)]

	var lowland_palette_group := _uses_lowland_grass_palette(x, z)
	var edge_variant := _is_grass_edge_column(x, z)
	var cell := Vector3i(x / MATERIAL_MACRO_CELL_SIZE, 31, z / MATERIAL_MACRO_CELL_SIZE)
	var pick: int = abs(hash(cell)) % 2
	var variant_index: int = 0

	if lowland_palette_group:
		variant_index = 1 + (pick * 2) if edge_variant else pick * 2
	else:
		variant_index = 5 + (pick * 2) if edge_variant else 4 + (pick * 2)

	return _grass_ids[mini(variant_index, _grass_ids.size() - 1)]


func _lowland_cap_grass_band_variant_index(x: int, z: int) -> int:
	if lowland_cap_grass_band_map.is_empty():
		return -1
	var idx := x * WORLD_SIZE_Z + z
	var band := lowland_cap_grass_band_map[idx]
	if band <= 0:
		return -1
	return int(band) - 1


func _foothill_cap_grass_band_variant_index(x: int, z: int) -> int:
	if foothill_cap_grass_band_map.is_empty():
		return -1
	var idx := x * WORLD_SIZE_Z + z
	var band := foothill_cap_grass_band_map[idx]
	if band <= 0:
		return -1
	return int(band) - 1


func _uses_lowland_grass_palette(x: int, z: int) -> bool:
	var h: int = heightmap[x * WORLD_SIZE_Z + z]
	if h >= FOOTHILL_SHELF_MIN_Y and h <= FOOTHILL_SHELF_MAX_Y:
		return false
	if h >= LOWLAND_SHELF_MIN_Y and h <= LOWLAND_SHELF_MAX_Y:
		return true
	var idx := x * WORLD_SIZE_Z + z
	if _settlement_plain_strength(x, z) > 0.18:
		return true
	if _southwest_basin_strength(x, z) > 0.30:
		return true
	return domain_map[idx] == DOMAIN_LOWLAND


func _is_grass_edge_column(x: int, z: int) -> bool:
	var center := heightmap[x * WORLD_SIZE_Z + z]
	if x > 0 and heightmap[(x - 1) * WORLD_SIZE_Z + z] != center:
		return true
	if x < WORLD_SIZE_X - 1 and heightmap[(x + 1) * WORLD_SIZE_Z + z] != center:
		return true
	if z > 0 and heightmap[x * WORLD_SIZE_Z + z - 1] != center:
		return true
	if z < WORLD_SIZE_Z - 1 and heightmap[x * WORLD_SIZE_Z + z + 1] != center:
		return true
	var edge_noise := _surface_region_value(x, z, 29)
	return edge_noise > 0.82


func _dirt_variant(x: int, z: int) -> int:
	var cell := Vector3i(x / MATERIAL_MACRO_CELL_SIZE, 47, z / MATERIAL_MACRO_CELL_SIZE)
	return _dirt_ids[abs(hash(cell)) % _dirt_ids.size()]


func _foothill_shelf_block_id(x: int, z: int, y: int) -> int:
	var shelf_y := (y - FOOTHILL_SHELF_MIN_Y) % FOOTHILL_SHELF_HEIGHT
	if shelf_y == FOOTHILL_SHELF_HEIGHT - 1:
		return _grass_variant(x, z)
	if shelf_y <= 1:
		return _dirt_ids[0]
	if shelf_y <= 3:
		return _dirt_ids[1]
	if shelf_y <= 5:
		return _dirt_ids[2]
	return _dirt_ids[3]


func _foothill_shelf_start_for_column(x: int, z: int) -> int:
	var h: int = heightmap[x * WORLD_SIZE_Z + z]
	var shelf_index := int(floor(float(h - FOOTHILL_SHELF_MIN_Y) / float(FOOTHILL_SHELF_HEIGHT)))
	return FOOTHILL_SHELF_MIN_Y + (shelf_index * FOOTHILL_SHELF_HEIGHT)


func _foothill_body_rock_id(y: int) -> int:
	return _altitude_rock_body_id(y)


func _altitude_rock_body_id(y: int) -> int:
	if y >= FOOTHILL_SHELF_MIN_Y and y < FOOTHILL_SHELF_MIN_Y + FOOTHILL_SHELF_HEIGHT:
		return _id_rock09
	if y >= LOWLAND_SHELF_MIN_Y and y <= LOWLAND_SHELF_MAX_Y:
		return _id_rock10
	if y >= FOOTHILL_SHELF_MIN_Y + FOOTHILL_SHELF_HEIGHT and y < FOOTHILL_SHELF_MIN_Y + (FOOTHILL_SHELF_HEIGHT * 2):
		return _id_rock08
	if y >= FOOTHILL_SHELF_MIN_Y + (FOOTHILL_SHELF_HEIGHT * 2) and y <= FOOTHILL_SHELF_MAX_Y:
		return _id_rock07
	return _fallback_rock_id(y)


func _lowland_shelf_block_id(x: int, z: int, y: int) -> int:
	var shelf_y := y - LOWLAND_SHELF_MIN_Y
	if y == LOWLAND_SHELF_MAX_Y:
		return _grass_variant(x, z)
	if shelf_y <= 1:
		return _dirt_ids[0]
	if shelf_y <= 3:
		return _dirt_ids[1]
	if shelf_y <= 5:
		return _dirt_ids[2]
	return _dirt_ids[3]


func _mountain_shelf_block_id(y: int) -> int:
	if _mountain_rock_ids.is_empty():
		return _id_rock11
	var shelf_index := int(floor(float(y - MOUNTAIN_MIN) / float(MOUNTAIN_SHELF_HEIGHT)))
	return _mountain_rock_ids[clampi(shelf_index, 0, _mountain_rock_ids.size() - 1)]


func _pick_surface_rock(x: int, z: int, y: int) -> int:
	var region := _surface_region_value(x, z, 23)
	if y >= 112:
		return _mountain_rock_ids[_mountain_rock_ids.size() - 1] if not _mountain_rock_ids.is_empty() else _id_rock07
	if region > 0.82:
		return _id_rock08
	if region < 0.18:
		return _id_rock09
	return _id_rock07


func _apply_resource_veins(x: int, y: int, z: int, surf_y: int, rock_id: int) -> int:
	if y <= BEDROCK_MAX_Y:
		return rock_id
	if y >= surf_y:
		return rock_id
	if not _is_resource_replaceable_rock(rock_id):
		return rock_id
	if _is_resource_perimeter_column(x, z):
		return rock_id
	if _is_natural_exposed_wall(x, y, z):
		return rock_id

	if _y_in_any_resource_window(_gem_windows, y):
		var n_gem := (noise_gem.get_noise_3d(x, y, z) + 1.0) * 0.5
		var gem := _pick_resource_from_windows(_gem_windows, y, n_gem)
		if gem != -1:
			return gem

	if _y_in_any_resource_window(_metal_windows, y):
		var n_ore := (noise_ore.get_noise_3d(x, y, z) + 1.0) * 0.5
		var ore := _pick_resource_from_windows(_metal_windows, y, n_ore)
		if ore != -1:
			return ore

	if _y_in_any_resource_window(_soil_windows, y):
		var n_soil := (noise_soil.get_noise_3d(x, y, z) + 1.0) * 0.5
		var soil := _pick_resource_from_windows(_soil_windows, y, n_soil)
		if soil != -1:
			return soil

	return rock_id


func _is_resource_replaceable_rock(block_id: int) -> bool:
	return _resource_replaceable_rock_ids.has(block_id)


func _is_resource_perimeter_column(x: int, z: int) -> bool:
	var edge_dist := mini(mini(x, WORLD_SIZE_X - 1 - x), mini(z, WORLD_SIZE_Z - 1 - z))
	return edge_dist < RESOURCE_PERIMETER_SUPPRESSION_WIDTH


func _is_natural_exposed_wall(x: int, y: int, z: int) -> bool:
	if x > 0 and heightmap[(x - 1) * WORLD_SIZE_Z + z] < y:
		return true
	if x < WORLD_SIZE_X - 1 and heightmap[(x + 1) * WORLD_SIZE_Z + z] < y:
		return true
	if z > 0 and heightmap[x * WORLD_SIZE_Z + z - 1] < y:
		return true
	if z < WORLD_SIZE_Z - 1 and heightmap[x * WORLD_SIZE_Z + z + 1] < y:
		return true
	return false


func _pick_resource_from_windows(windows: Array[Dictionary], y: int, noise_value: float) -> int:
	for window: Dictionary in windows:
		if y >= int(window.get("min_y", 0)) and y <= int(window.get("max_y", WORLD_SIZE_Y - 1)) and noise_value > float(window.get("threshold", 1.0)):
			return int(window.get("id", -1))
	return -1


func _y_in_any_resource_window(windows: Array[Dictionary], y: int) -> bool:
	for window: Dictionary in windows:
		if y >= int(window.get("min_y", 0)) and y <= int(window.get("max_y", WORLD_SIZE_Y - 1)):
			return true
	return false


func _fallback_rock_id(y: int) -> int:
	# Keep legacy fallback paths on the authored rock01..rock11 ladder.
	if y <= FOUNDATION_ROCK_MAX_Y:
		return _id_rock11
	if y < FOOTHILL_SHELF_MIN_Y:
		return _id_rock10
	if y < FOOTHILL_SHELF_MIN_Y + FOOTHILL_SHELF_HEIGHT:
		return _id_rock09
	if y < FOOTHILL_SHELF_MIN_Y + (FOOTHILL_SHELF_HEIGHT * 2):
		return _id_rock08
	if y <= FOOTHILL_SHELF_MAX_Y:
		return _id_rock07
	if not _mountain_rock_ids.is_empty():
		var shelf_index := int(floor(float(y - MOUNTAIN_MIN) / float(MOUNTAIN_SHELF_HEIGHT)))
		return _mountain_rock_ids[clampi(shelf_index, 0, _mountain_rock_ids.size() - 1)]
	return _id_rock07
