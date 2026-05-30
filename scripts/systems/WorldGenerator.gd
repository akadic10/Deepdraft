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
##   2. Compute domain map  (2D — mountain / valley / lowland classification)
##   3. Compute heightmap   (2D — domain-shaped elevation with blended borders)
##   4. Carve lake bodies   (lowland lake + mountain tarn)
##   5. Fill all chunks     (3D — bedrock, water, surface skin, caves, ores, stone)

# ── World dimensions ──────────────────────────────────────────────────────────
# FULL WORLD: 1024 × 128 × 1024 = 134,217,728 blocks (32,768 chunks).
# 1 engine block = 0.5 m, so the playable boundary is 512 m × 512 m × 64 m.
# (For fast iteration, temporarily drop X/Z to 128 — ~5 s generation.)
const WORLD_SIZE_X:  int = 1024
const WORLD_SIZE_Y:  int = 128
const WORLD_SIZE_Z:  int = 1024
const CHUNK_SIZE:    int = 16
const CHUNK_COUNT_X: int = WORLD_SIZE_X / CHUNK_SIZE   # 64
const CHUNK_COUNT_Y: int = WORLD_SIZE_Y / CHUNK_SIZE   # 8
const CHUNK_COUNT_Z: int = WORLD_SIZE_Z / CHUNK_SIZE   # 64
const BLOCK_COUNT_REPORT_INTERVAL_COLUMNS: int = 16

# ── Terrain domain classification ─────────────────────────────────────────────
const DOMAIN_MOUNTAIN: int = 2   # domain_n > 0.60
const DOMAIN_VALLEY:   int = 1   # domain_n 0.35 – 0.60
const DOMAIN_LOWLAND:  int = 0   # domain_n < 0.35
const DOMAIN_MOUNTAIN_THRESHOLD: float = 0.60
const DOMAIN_VALLEY_THRESHOLD: float = 0.35
const NORTHWEST_MOUNTAIN_EDGE_NOISE: float = 0.18
const SOUTHWEST_BASIN_DOMAIN_PULL: float = 0.30
const SOUTHEAST_HIGHLAND_DOMAIN_BONUS: float = 0.18
const WORLD_EDGE_BELT_WIDTH: int = 28

# ── Surface elevation ranges (Y in blocks) ────────────────────────────────────
const MOUNTAIN_MIN: int = 88;  const MOUNTAIN_MAX: int = 124
const VALLEY_MIN:   int = 64;  const VALLEY_MAX:   int = 72
const LOWLAND_MIN:  int = 62;  const LOWLAND_MAX:  int = 67
const SOUTHEAST_HIGHLAND_MIN: int = 72
const SOUTHEAST_HIGHLAND_MAX: int = 88
const VALLEY_CORRIDOR_CENTER_Z_RATIO: float = 0.43
const VALLEY_CORRIDOR_HALF_WIDTH_RATIO: float = 0.07
const VALLEY_CORRIDOR_WIGGLE_RATIO: float = 0.035
const VALLEY_TERRACE_STEP: int = 2
const FOOTHILL_TERRACE_STEP: int = 4
const MOUNTAIN_TERRACE_STEP: int = 8
const HIGHLAND_TERRACE_STEP: int = 6
const PLATEAU_MAX_HEIGHT_RANGE: int = 5
const PLATEAU_MAX_MOUNTAIN_HEIGHT: int = 104
const PLATEAU_MIN_DOMINANT_COLUMNS: int = 92
const PLATEAU_SNAP_DELTA: int = 2
const MATERIAL_MACRO_CELL_SIZE: int = 32
const WATER_BANK_RADIUS: int = 4
const STEEP_SLOPE_ROCK_DELTA: int = 3

# ── Lake / tarn parameters ────────────────────────────────────────────────────
# Radii scale with world size so the 128-block test world gets a proportional
# lake. At full 1024×1024 these evaluate to the original 40 and 15.
const LAKE_RADIUS:    int = max(8,  WORLD_SIZE_X / 25)   # 128 → 5 → clamped 8; 1024 → 40
const LAKE_DEPTH:     int = 5
const LAKE_WATERLINE: int = 62   # fixed surface elevation of the lowland lake

const TARN_RADIUS: int = max(4, WORLD_SIZE_X / 68)       # 128 → 1 → clamped 4; 1024 → 15
const TARN_DEPTH:  int = 3
# tarn_waterline is derived after carving — see _carve_mountain_tarn()

# ── Ore / gem ladder ──────────────────────────────────────────────────────────
# Evaluated in ascending rarity order. First condition match wins.
# Source of truth is block_resources.json; values are inlined here so the
# generator does not need a separate file load at generation time.
# Format per entry: [block_key, noise_threshold, max_y_exclusive]
# max_y_exclusive: ore only spawns at y < max_y (deeper = rarer).
const ORE_LADDER: Array = [
	[&"base:terrain:ore:tin",      0.68, 95],
	[&"base:terrain:ore:copper",   0.70, 90],
	[&"base:terrain:ore:coal",     0.68, 85],
	[&"base:terrain:ore:iron",     0.72, 80],
	[&"base:terrain:ore:silver",   0.75, 60],
	[&"base:terrain:ore:gold",     0.78, 40],
	[&"base:terrain:gem:jade",     0.78, 60],
	[&"base:terrain:gem:amethyst", 0.80, 55],
	[&"base:terrain:gem:ruby",     0.85, 20],
	[&"base:terrain:gem:sapphire", 0.87, 20],
	[&"base:terrain:gem:emerald",  0.86, 15],
	[&"base:terrain:gem:diamond",  0.92,  8],
]

# ── Signals ───────────────────────────────────────────────────────────────────
## Emitted from the generator thread each time a chunk is fully filled.
## WorldRenderer MUST connect with CONNECT_DEFERRED — mesh work is main-thread only.
signal chunk_generated(cx: int, cy: int, cz: int)

## Emitted from the generator thread when all chunks are complete.
signal world_complete()

# ── Generation state ──────────────────────────────────────────────────────────
var world_seed: int = 0

# Seven noise instances — one per logical layer; never reuse across passes.
var noise_stone:    FastNoiseLite   # underground stone type blobs
var noise_ore:      FastNoiseLite   # ore / gem vein mask
var noise_cave:     FastNoiseLite   # cave void mask
var noise_soil:     FastNoiseLite   # cave soil patches + surface dirt fraction
var noise_domain:   FastNoiseLite   # broad terrain domain map
var noise_mountain: FastNoiseLite   # mountain ridge detail
var noise_valley:   FastNoiseLite   # valley / lowland floor detail

# 2D column maps  (index: x * WORLD_SIZE_Z + z)
var domain_map:   PackedInt32Array    # DOMAIN_* constant per column
var domain_n_map: PackedFloat32Array  # raw [0,1] domain noise per column (for blend math)
var heightmap:    PackedInt32Array    # surface Y per column

# Lake / tarn geometry
var lake_columns: Dictionary = {}   # Vector2i → true  (lowland lake footprint)
var tarn_columns: Dictionary = {}   # Vector2i → true  (mountain tarn footprint)
var water_bank_columns: Dictionary = {}  # Vector2i → true  (near lake/tarn, but not water)
var lake_center:  Vector2i  = Vector2i.ZERO
var tarn_center:  Vector2i  = Vector2i.ZERO
var tarn_waterline: int     = 0

# Pre-cached runtime block IDs — looked up on the main thread before generation
# starts so the background thread never calls BlockRegistry directly.
var _id_void:      int = 0
var _id_bedrock:   int = 0
var _id_water:     int = 0
var _id_granite:   int = 0
var _id_basalt:    int = 0
var _id_limestone: int = 0
var _id_marble:    int = 0
var _id_cave_soil: int = 0
var _grass_ids:    Array[int] = []   # [0..15] → grass_01…grass_16
var _dirt_ids:     Array[int] = []   # [0..3]  → dirt_01…dirt_04
var _ore_ids:      Array[int] = []   # parallel to ORE_LADDER

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

## Cooperative cancel flag. Set true on the main thread (e.g. when the game
## stops) so the worker exits its chunk loop instead of touching members that
## are about to be torn down. Bool read/write is atomic enough for a one-way
## "stop now" signal — we never read it back into logic, only to bail out.
var _abort: bool = false


func _ready() -> void:
	_request_mutex = Mutex.new()
	print("WorldGenerator: ready.")


## Called when the node leaves the tree — i.e. the game is stopping. Signal the
## worker to abort, then JOIN it before the script's members are freed. Without
## this, stopping mid-generation crashes ("Bad address index" as heightmap is
## cleared under the running thread) and leaks the Thread ("destroyed without
## wait_to_finish()").
func _exit_tree() -> void:
	_abort = true
	if _gen_thread != null and _gen_thread.is_started():
		_gen_thread.wait_to_finish()
		_gen_thread = null


# ── Deferred signal helpers (main-thread only) ────────────────────────────────

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
	print("  water: lake %s r%d y%d columns %d; tarn %s r%d y%d columns %d; banks %d" % [
		str(water.get("lake_center", Vector2i.ZERO)),
		water.get("lake_radius", 0),
		water.get("lake_waterline", 0),
		water.get("lake_columns", 0),
		str(water.get("tarn_center", Vector2i.ZERO)),
		water.get("tarn_radius", 0),
		water.get("tarn_waterline", 0),
		water.get("tarn_columns", 0),
		water.get("bank_columns", 0),
	])
	print("  macro: basin %d, southeast highland %d, edge belt %d columns" % [
		macro.get("southwest_basin_columns", 0),
		macro.get("southeast_highland_columns", 0),
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
	for i in range(ORE_LADDER.size()):
		var ore_id: int = _ore_ids[i]
		var ore_count := snapshot.get(ore_id, 0) as int
		var ore_ratio := 0.0
		if total_blocks > 0:
			ore_ratio = (float(ore_count) / float(total_blocks)) * 100.0
		var ore_key := String(ORE_LADDER[i][0] as StringName)
		print("    %s: %d (%.3f%%)" % [ore_key, ore_count, ore_ratio])
	print("  all block types:")
	for row: Array in rows:
		var count := row[0] as int
		var ratio := 0.0
		if total_blocks > 0:
			ratio = (float(count) / float(total_blocks)) * 100.0
		print("  %s: %d (%.3f%%)" % [row[1] as String, count, ratio])


# ── Public API ────────────────────────────────────────────────────────────────

## Begin procedural world generation on a background thread.
## new_seed = 0  →  random seed via randi().
## new_seed ≠ 0  →  deterministic; same seed always produces the same world.
## (Param is not named "seed" — that shadows the global seed() built-in.)
func generate(new_seed: int = 0) -> void:
	if _gen_thread != null and _gen_thread.is_started():
		push_warning("WorldGenerator.generate() called while generation is already running.")
		return

	world_seed = new_seed if new_seed != 0 else randi()
	print("WorldGenerator: starting generation (seed %d)." % world_seed)

	_abort = false
	_maps_ready = false
	_column_in_flight = false
	_generation_metrics.clear()
	_domain_counts.clear()
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
	_cache_block_ids()

	# Clean up the thread object on the main thread once the world is done.
	world_complete.connect(_cleanup_thread, CONNECT_ONE_SHOT | CONNECT_DEFERRED)

	_gen_thread = Thread.new()
	_gen_thread.start(_generate_threaded)


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
	return _pick_surface_block(wx, wz, col)


func get_generated_block_id(wx: int, wy: int, wz: int) -> int:
	if not _maps_ready:
		return BlockRegistry.AIR_ID
	if wx < 0 or wx >= WORLD_SIZE_X or wy < 0 or wy >= WORLD_SIZE_Y or wz < 0 or wz >= WORLD_SIZE_Z:
		return BlockRegistry.AIR_ID
	return _generate_block_id(wx, wy, wz)


# ── ID cache (main thread) ────────────────────────────────────────────────────

func _cache_block_ids() -> void:
	_id_void      = BlockRegistry.get_id(&"base:terrain:void")
	_id_bedrock   = BlockRegistry.get_id(&"base:terrain:bedrock")
	_id_water     = BlockRegistry.get_id(&"base:terrain:water:source")
	_id_granite   = BlockRegistry.get_id(&"base:terrain:rock:granite")
	_id_basalt    = BlockRegistry.get_id(&"base:terrain:rock:basalt")
	_id_limestone = BlockRegistry.get_id(&"base:terrain:rock:limestone")
	_id_marble    = BlockRegistry.get_id(&"base:terrain:rock:marble")
	_id_cave_soil = BlockRegistry.get_id(&"base:terrain:soil:cave")

	_grass_ids.clear()
	for i in range(1, 17):
		_grass_ids.append(BlockRegistry.get_id(StringName("base:terrain:surface:grass_%02d" % i)))

	_dirt_ids.clear()
	for i in range(1, 5):
		_dirt_ids.append(BlockRegistry.get_id(StringName("base:terrain:surface:dirt_%02d" % i)))

	_ore_ids.clear()
	for entry: Array in ORE_LADDER:
		_ore_ids.append(BlockRegistry.get_id(entry[0] as StringName))


# ── Pipeline (background thread) ──────────────────────────────────────────────

func _generate_threaded() -> void:
	var t_start := Time.get_ticks_msec()

	_build_noise_instances()    # Phase 1
	_compute_domain_map()       # Phase 2
	_compute_heightmap()        # Phase 3
	_carve_lakes()              # Phase 4
	_build_generation_metrics()
	_maps_ready = true
	call_deferred("_deferred_emit_maps_ready")
	call_deferred("_deferred_print_generation_metrics", _generation_metrics.duplicate(true))
	_process_requested_columns()      # Phase 5, demand-driven
	_maybe_defer_block_spawn_report(true)

	var elapsed := (Time.get_ticks_msec() - t_start) / 1000.0
	print("WorldGenerator: stopped in %.1f s." % elapsed)
	call_deferred("_deferred_emit_world_complete")


# ── Phase 1 — Noise instances ─────────────────────────────────────────────────

func _build_noise_instances() -> void:
	# Layer 1 — Base stone type
	# Low frequency, smooth blobs → determines which rock kind fills each region.
	noise_stone = FastNoiseLite.new()
	noise_stone.noise_type      = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise_stone.seed            = world_seed
	noise_stone.frequency       = 0.005
	noise_stone.fractal_octaves = 3

	# Layer 2 — Ore vein mask
	# Medium frequency, fewer octaves → thin vein shapes.
	noise_ore = FastNoiseLite.new()
	noise_ore.noise_type        = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise_ore.seed              = world_seed + 1
	noise_ore.frequency         = 0.02
	noise_ore.fractal_octaves   = 2

	# Layer 3 — Cave void mask
	# Medium-low frequency, more octaves → organic cave networks.
	noise_cave = FastNoiseLite.new()
	noise_cave.noise_type       = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise_cave.seed             = world_seed + 2
	noise_cave.frequency        = 0.015
	noise_cave.fractal_octaves  = 4

	# Layer 4 — Soil patch mask (also drives surface dirt fraction via 2D query)
	# Higher frequency, smooth → small irregular farmable soil pockets.
	noise_soil = FastNoiseLite.new()
	noise_soil.noise_type       = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise_soil.seed             = world_seed + 3
	noise_soil.frequency        = 0.03
	noise_soil.fractal_octaves  = 2

	# Layer 5 — Terrain domain map
	# Very low frequency, large scale → broad mountain / valley / lowland zones.
	noise_domain = FastNoiseLite.new()
	noise_domain.noise_type      = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise_domain.seed            = world_seed + 4
	noise_domain.frequency       = 0.0015
	noise_domain.fractal_octaves = 2

	# Layer 6 — Mountain ridge detail
	# Ridge noise (abs of simplex, inverted) → sharp peaks and narrow spines.
	noise_mountain = FastNoiseLite.new()
	noise_mountain.noise_type      = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise_mountain.seed            = world_seed + 5
	noise_mountain.frequency       = 0.006
	noise_mountain.fractal_octaves = 5

	# Layer 7 — Valley / lowland floor detail
	# Low amplitude, gentle rolls → subtle variation in otherwise flat ground.
	noise_valley = FastNoiseLite.new()
	noise_valley.noise_type      = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise_valley.seed            = world_seed + 6
	noise_valley.frequency       = 0.012
	noise_valley.fractal_octaves = 2


# ── Phase 2 — Domain map (2D) ─────────────────────────────────────────────────

func _compute_domain_map() -> void:
	var size := WORLD_SIZE_X * WORLD_SIZE_Z
	domain_map.resize(size)
	domain_n_map.resize(size)

	var mountain_count := 0
	var valley_count := 0
	var lowland_count := 0

	for x in range(WORLD_SIZE_X):
		for z in range(WORLD_SIZE_Z):
			var northwest_influence := _northwest_mountain_influence(x, z)
			var edge_noise := (noise_domain.get_noise_2d(x, z) + 1.0) * 0.5
			var basin_strength := _southwest_basin_strength(x, z)
			var highland_strength := _southeast_highland_strength(x, z)
			var corridor_strength := _valley_corridor_strength(x, z)
			var n := clampf(
				northwest_influence + ((edge_noise - 0.5) * NORTHWEST_MOUNTAIN_EDGE_NOISE),
				0.0,
				1.0)
			n = lerp(n, 0.18, basin_strength * SOUTHWEST_BASIN_DOMAIN_PULL)
			n = lerp(n, 0.48, highland_strength * SOUTHEAST_HIGHLAND_DOMAIN_BONUS)
			n = lerp(n, 0.48, corridor_strength * 0.22)
			var idx := x * WORLD_SIZE_Z + z
			domain_n_map[idx] = n
			if n > DOMAIN_MOUNTAIN_THRESHOLD:
				domain_map[idx] = DOMAIN_MOUNTAIN
				mountain_count += 1
			elif n > DOMAIN_VALLEY_THRESHOLD:
				domain_map[idx] = DOMAIN_VALLEY
				valley_count += 1
			else:
				domain_map[idx] = DOMAIN_LOWLAND
				lowland_count += 1

	print("WorldGenerator: domain layout northwest mountain -> mountain %d, valley %d, lowland %d." % [
		mountain_count,
		valley_count,
		lowland_count,
	])
	_domain_counts = {
		"mountain": mountain_count,
		"valley": valley_count,
		"lowland": lowland_count,
	}

# ── Phase 3 — Surface heightmap (2D) ─────────────────────────────────────────

func _compute_heightmap() -> void:
	heightmap.resize(WORLD_SIZE_X * WORLD_SIZE_Z)

	var corridor_count := 0
	var corridor_height_sum := 0
	var terraced_count := 0

	for x in range(WORLD_SIZE_X):
		for z in range(WORLD_SIZE_Z):
			var idx := x * WORLD_SIZE_Z + z
			var n   := domain_n_map[idx]
			var height_f: float

			if n > 0.60:
				# Mountain zone — ridge noise gives sharp peaks.
				# abs(simplex) ∈ [0,1]; inverting gives 1 at ridgelines (peaks).
				var ridge: float = 1.0 - absf(noise_mountain.get_noise_2d(x, z))
				var mountain_depth: float = clampf((n - 0.60) / 0.40, 0.0, 1.0)
				var mountain_floor: float = lerp(float(MOUNTAIN_MIN), float(MOUNTAIN_MIN + 12), mountain_depth)
				height_f = lerp(mountain_floor, float(MOUNTAIN_MAX), ridge)
				# Blend into valley in the 0.60–0.70 transition band.
				if n < 0.70:
					var t := (n - 0.60) / 0.10   # 0 at border, 1 deep in mountains
					height_f = lerp(_valley_height(x, z), height_f, t)

			elif n > 0.35:
				# Valley zone — gentle detail, stays flat.
				height_f = _valley_height(x, z)
				# Blend into lowland in the 0.35–0.45 transition band.
				if n < 0.45:
					var t := (n - 0.35) / 0.10   # 0 at border, 1 deep in valley
					height_f = lerp(_lowland_height(x, z), height_f, t)

			else:
				# Lowland zone.
				height_f = _lowland_height(x, z)

			var corridor_strength := _valley_corridor_strength(x, z)
			if corridor_strength > 0.0:
				height_f = lerp(height_f, _valley_corridor_height(x, z), corridor_strength)
			var basin_strength := _southwest_basin_strength(x, z)
			if basin_strength > 0.0:
				height_f = lerp(height_f, _southwest_basin_height(x, z), basin_strength)
			var highland_strength := _southeast_highland_strength(x, z)
			if highland_strength > 0.0:
				height_f = lerp(height_f, _southeast_highland_height(x, z), highland_strength)

			var raw_height := int(height_f)
			var height := _terraced_height(raw_height, n, corridor_strength, x, z)
			heightmap[idx] = height
			if height != raw_height:
				terraced_count += 1
			if corridor_strength > 0.5:
				corridor_count += 1
				corridor_height_sum += height

	if corridor_count > 0:
		print("WorldGenerator: valley corridor -> columns %d, average height %.1f." % [
			corridor_count,
			float(corridor_height_sum) / float(corridor_count),
		])
	print("WorldGenerator: terrace quantization -> adjusted %d columns." % terraced_count)
	_terraced_columns = terraced_count
	_apply_plateau_smoothing()


func _valley_height(x: int, z: int) -> float:
	# Low amplitude — valley floors stay close to flat.
	var detail := (noise_valley.get_noise_2d(x, z) + 1.0) * 0.5
	return lerp(float(VALLEY_MIN), float(VALLEY_MAX), detail * 0.4)


func _terraced_height(raw_height: int, domain_n: float, corridor_strength: float, x: int, z: int) -> int:
	var step := _terrace_step_for(x, z, domain_n, corridor_strength)
	var jitter := _terrace_jitter(x, z, step)
	return clampi(((raw_height + jitter) / step) * step - jitter, 1, WORLD_SIZE_Y - 1)


func _terrace_step_for(x: int, z: int, domain_n: float, corridor_strength: float) -> int:
	if corridor_strength > 0.45:
		return VALLEY_TERRACE_STEP
	if _southeast_highland_strength(x, z) > 0.35:
		return HIGHLAND_TERRACE_STEP
	if domain_n > DOMAIN_MOUNTAIN_THRESHOLD:
		return MOUNTAIN_TERRACE_STEP
	if domain_n > DOMAIN_VALLEY_THRESHOLD:
		return FOOTHILL_TERRACE_STEP
	return VALLEY_TERRACE_STEP


func _terrace_jitter(x: int, z: int, step: int) -> int:
	if step <= 2:
		return 0
	var break_noise := (noise_domain.get_noise_2d(float(x) + 12000.0, float(z) + 12000.0) + 1.0) * 0.5
	return int(round((break_noise - 0.5) * float(step)))


func _apply_plateau_smoothing() -> void:
	var adjusted_columns := 0
	var smoothed_chunks := 0

	for cx in range(CHUNK_COUNT_X):
		for cz in range(CHUNK_COUNT_Z):
			var base_x := cx * CHUNK_SIZE
			var base_z := cz * CHUNK_SIZE
			var min_h := WORLD_SIZE_Y
			var max_h := 0
			var mountain_columns := 0
			var height_counts: Dictionary = {}

			for lx in range(CHUNK_SIZE):
				var wx := base_x + lx
				for lz in range(CHUNK_SIZE):
					var wz := base_z + lz
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
			for lx in range(CHUNK_SIZE):
				var wx := base_x + lx
				for lz in range(CHUNK_SIZE):
					var wz := base_z + lz
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
				smoothed_chunks += 1
				adjusted_columns += changed_in_chunk

	print("WorldGenerator: plateau smoothing -> adjusted %d columns across %d chunk columns." % [
		adjusted_columns,
		smoothed_chunks,
	])
	_plateau_adjusted_columns = adjusted_columns
	_plateau_smoothed_chunks = smoothed_chunks


func _plateau_bias_strength(x: int, z: int, lx: int, lz: int) -> float:
	var edge_dist := mini(mini(lx, CHUNK_SIZE - 1 - lx), mini(lz, CHUNK_SIZE - 1 - lz))
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


func _valley_corridor_height(x: int, z: int) -> float:
	var detail := (noise_valley.get_noise_2d(x + 5000, z) + 1.0) * 0.5
	var center_bias := _valley_corridor_strength(x, z)
	var floor_height: float = lerp(float(VALLEY_MIN), float(VALLEY_MIN + 2), detail * 0.55)
	return lerp(float(VALLEY_MAX - 1), floor_height, center_bias)


func _lowland_height(x: int, z: int) -> float:
	# z offset avoids the lowland pattern mirroring the valley pattern.
	var detail := (noise_valley.get_noise_2d(x, z + 1000) + 1.0) * 0.5
	return lerp(float(LOWLAND_MIN), float(LOWLAND_MAX), detail * 0.3)


func _southwest_basin_strength(x: int, z: int) -> float:
	var center := Vector2(float(WORLD_SIZE_X) * 0.16, float(WORLD_SIZE_Z) * 0.82)
	var radius := float(WORLD_SIZE_X) * 0.34
	return _radial_strength(Vector2(float(x), float(z)), center, radius)


func _southwest_basin_height(x: int, z: int) -> float:
	var detail := (noise_valley.get_noise_2d(x + 7000, z + 7000) + 1.0) * 0.5
	return lerp(float(LOWLAND_MIN - 4), float(LOWLAND_MIN + 2), detail * 0.35)


func _southeast_highland_strength(x: int, z: int) -> float:
	var center := Vector2(float(WORLD_SIZE_X) * 0.82, float(WORLD_SIZE_Z) * 0.78)
	var radius := float(WORLD_SIZE_X) * 0.30
	return _radial_strength(Vector2(float(x), float(z)), center, radius)


func _southeast_highland_height(x: int, z: int) -> float:
	var detail := (noise_valley.get_noise_2d(x - 5000, z - 5000) + 1.0) * 0.5
	return lerp(float(SOUTHEAST_HIGHLAND_MIN), float(SOUTHEAST_HIGHLAND_MAX), detail * 0.45)


func _world_edge_belt_strength(x: int, z: int) -> float:
	var edge_dist := mini(mini(x, WORLD_SIZE_X - 1 - x), mini(z, WORLD_SIZE_Z - 1 - z))
	return clampf(1.0 - (float(edge_dist) / float(WORLD_EDGE_BELT_WIDTH)), 0.0, 1.0)


func _radial_strength(pos: Vector2, center: Vector2, radius: float) -> float:
	if radius <= 0.0:
		return 0.0
	var t := clampf(1.0 - (pos.distance_to(center) / radius), 0.0, 1.0)
	return t * t * (3.0 - (2.0 * t))


# ── Phase 4 — Lake bodies ─────────────────────────────────────────────────────

func _carve_lakes() -> void:
	_carve_lowland_lake()
	_carve_mountain_tarn()
	_build_water_bank_mask()


func _carve_lowland_lake() -> void:
	# Prefer the authored southwest basin, then fall back to the whole lowland.
	var weighted_sum_x := 0.0
	var weighted_sum_z := 0.0
	var weight_total := 0.0
	var sum_x := 0
	var sum_z := 0
	var count := 0
	for x in range(WORLD_SIZE_X):
		for z in range(WORLD_SIZE_Z):
			if domain_map[x * WORLD_SIZE_Z + z] == DOMAIN_LOWLAND:
				sum_x += x
				sum_z += z
				count += 1
				var basin_strength := _southwest_basin_strength(x, z)
				if basin_strength > 0.25:
					var weight := basin_strength * basin_strength
					weighted_sum_x += float(x) * weight
					weighted_sum_z += float(z) * weight
					weight_total += weight

	if count == 0:
		push_warning("WorldGenerator: no lowland columns — lowland lake skipped.")
		return

	if weight_total > 0.0:
		lake_center = Vector2i(int(weighted_sum_x / weight_total), int(weighted_sum_z / weight_total))
	else:
		lake_center = Vector2i(sum_x / count, sum_z / count)

	for x in range(lake_center.x - LAKE_RADIUS, lake_center.x + LAKE_RADIUS + 1):
		for z in range(lake_center.y - LAKE_RADIUS, lake_center.y + LAKE_RADIUS + 1):
			if x < 0 or x >= WORLD_SIZE_X or z < 0 or z >= WORLD_SIZE_Z:
				continue
			var dist := Vector2(x, z).distance_to(Vector2(lake_center))
			if dist > LAKE_RADIUS:
				continue
			var depth_factor := 1.0 - (dist / float(LAKE_RADIUS))
			var carve        := int(LAKE_DEPTH * depth_factor)
			var idx          := x * WORLD_SIZE_Z + z
			heightmap[idx]    = min(heightmap[idx], LAKE_WATERLINE - 1 - carve)
			lake_columns[Vector2i(x, z)] = true


func _carve_mountain_tarn() -> void:
	# Centroid of the mountain/valley transition band (domain_n 0.55–0.65).
	# Sits at the mountain foot — naturally higher than the lowland lake.
	var sum_x := 0;  var sum_z := 0;  var count := 0
	for x in range(WORLD_SIZE_X):
		for z in range(WORLD_SIZE_Z):
			var n := domain_n_map[x * WORLD_SIZE_Z + z]
			if n >= 0.55 and n <= 0.65:
				sum_x += x;  sum_z += z;  count += 1

	if count == 0:
		push_warning("WorldGenerator: no mountain/valley transition band — tarn skipped.")
		return

	tarn_center = Vector2i(sum_x / count, sum_z / count)

	for x in range(tarn_center.x - TARN_RADIUS, tarn_center.x + TARN_RADIUS + 1):
		for z in range(tarn_center.y - TARN_RADIUS, tarn_center.y + TARN_RADIUS + 1):
			if x < 0 or x >= WORLD_SIZE_X or z < 0 or z >= WORLD_SIZE_Z:
				continue
			var dist := Vector2(x, z).distance_to(Vector2(tarn_center))
			if dist > TARN_RADIUS:
				continue
			var depth_factor := 1.0 - (dist / float(TARN_RADIUS))
			var carve        := int(TARN_DEPTH * depth_factor)
			var idx          := x * WORLD_SIZE_Z + z
			heightmap[idx]    = min(heightmap[idx], heightmap[idx] - carve)
			tarn_columns[Vector2i(x, z)] = true

	# Derive tarn waterline: floor of carved bowl + TARN_DEPTH - 1.
	var min_y := 9999
	for col: Vector2i in tarn_columns:
		min_y = min(min_y, heightmap[col.x * WORLD_SIZE_Z + col.y])
	tarn_waterline = min_y + TARN_DEPTH - 1


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


# -- Generation metrics -------------------------------------------------------

func _build_generation_metrics() -> void:
	var total_columns := WORLD_SIZE_X * WORLD_SIZE_Z
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
			"tarn_center": tarn_center,
			"tarn_radius": TARN_RADIUS,
			"tarn_waterline": tarn_waterline,
			"tarn_columns": tarn_columns.size(),
			"bank_columns": water_bank_columns.size(),
		},
		"settlement_candidates": _compute_settlement_candidate_metrics(),
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
	var highland_columns := 0
	var edge_columns := 0
	var basin_peak := 0.0
	var highland_peak := 0.0

	for x in range(WORLD_SIZE_X):
		for z in range(WORLD_SIZE_Z):
			var basin := _southwest_basin_strength(x, z)
			var highland := _southeast_highland_strength(x, z)
			var edge := _world_edge_belt_strength(x, z)
			if basin > 0.25:
				basin_columns += 1
			if highland > 0.25:
				highland_columns += 1
			if edge > 0.0:
				edge_columns += 1
			basin_peak = maxf(basin_peak, basin)
			highland_peak = maxf(highland_peak, highland)

	return {
		"southwest_basin_columns": basin_columns,
		"southwest_basin_peak": basin_peak,
		"southeast_highland_columns": highland_columns,
		"southeast_highland_peak": highland_peak,
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
	if block_id == _id_granite or block_id == _id_basalt or block_id == _id_limestone or block_id == _id_marble:
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


# ── Phase 5 — Block fill (3D, per chunk) ──────────────────────────────────────

func _fill_all_chunks() -> void:
	# Highest block any column in a chunk could contain = max surface in that
	# chunk's 16×16 footprint, but never below the lake waterline (water fills
	# above the carved floor). Chunk-Y layers entirely above this are pure void —
	# we skip generating AND meshing them. Most of the map is lowland (~Y 67), so
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
					continue   # pure-void chunk — never generated, never meshed

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
				# all six neighbours are also solid — see WorldRenderer.
				chunk.has_void = found_void
				WorldData.submit_chunk(cx, cy, cz, chunk)
				call_deferred("_deferred_emit_chunk_generated", cx, cy, cz)
			_counted_columns += 1
			_maybe_defer_block_spawn_report()

	print("WorldGenerator: skipped %d all-void chunks (of %d)." % [
		skipped, CHUNK_COUNT_X * CHUNK_COUNT_Y * CHUNK_COUNT_Z])
	_maybe_defer_block_spawn_report(true)


## Highest world-Y that a chunk column (cx, cz) can contain a non-void block.
## Scans the column's 16×16 surface footprint and clamps to at least the lake
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

	# Absolute floor — bedrock protocol (12_world_grid.md)
	if y == 0:
		return _id_bedrock

	# Above surface
	if y > surf_y:
		if lake_columns.has(col) and y <= LAKE_WATERLINE:
			return _id_water
		if tarn_columns.has(col) and y <= tarn_waterline:
			return _id_water
		return _id_void

	# Surface skin
	if y == surf_y:
		return _pick_surface_block(x, z, col)

	# Underground volume — evaluate noise LAZILY. The 3D noise samples are the
	# dominant generation cost, so we only compute each one when it can actually
	# affect the result, and return as early as possible.

	# Cave void — only possible deeper than 5 blocks below the surface.
	if y < surf_y - 5:
		var n_cave := (noise_cave.get_noise_3d(x, y, z) + 1.0) * 0.5
		if n_cave > 0.65:
			return _id_void

	# Ore / gem vein — the shallowest ladder entry caps at y < 95, so blocks
	# at or above 95 can never contain ore. Skip the sample there.
	if y < 95:
		var n_ore := (noise_ore.get_noise_3d(x, y, z) + 1.0) * 0.5
		var ore := _pick_ore(y, n_ore)
		if ore != -1:
			return ore

	# Farmable cave soil — only in the Y 20–60 band.
	if y >= 20 and y <= 60:
		var n_soil := (noise_soil.get_noise_3d(x, y, z) + 1.0) * 0.5
		if n_soil > 0.68:
			return _id_cave_soil

	# Base stone fill.
	var n_stone := (noise_stone.get_noise_3d(x, y, z) + 1.0) * 0.5
	return _pick_stone(n_stone, y)


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

	if _southeast_highland_strength(x, z) > 0.35:
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
	var cell := Vector3i(x / MATERIAL_MACRO_CELL_SIZE, 31, z / MATERIAL_MACRO_CELL_SIZE)
	return _grass_ids[abs(hash(cell)) % _grass_ids.size()]


func _dirt_variant(x: int, z: int) -> int:
	var cell := Vector3i(x / MATERIAL_MACRO_CELL_SIZE, 47, z / MATERIAL_MACRO_CELL_SIZE)
	return _dirt_ids[abs(hash(cell)) % _dirt_ids.size()]


func _pick_surface_rock(x: int, z: int, y: int) -> int:
	var region := _surface_region_value(x, z, 23)
	if y >= 112:
		return _id_basalt if region > 0.72 else _id_granite
	if region > 0.82:
		return _id_limestone
	if region < 0.18:
		return _id_basalt
	return _id_granite


func _pick_ore(y: int, n_ore: float) -> int:
	# Returns the ID of the first ore whose depth and noise conditions are met,
	# or -1 if this position should not contain an ore vein.
	for i in range(ORE_LADDER.size()):
		var entry: Array = ORE_LADDER[i]
		if y < (entry[2] as int) and n_ore > (entry[1] as float):
			return _ore_ids[i]
	return -1


func _pick_stone(n_stone: float, y: int) -> int:
	# Limestone bands in the mid-depth sedimentary zone
	if y >= 40 and y <= 80 and n_stone > 0.55:
		return _id_limestone
	# Marble — rare pockets anywhere below Y 50
	if y < 50 and n_stone > 0.78:
		return _id_marble
	# Basalt dominates the deep layers
	if y < 35:
		return _id_basalt
	# Granite fills everything else
	return _id_granite
