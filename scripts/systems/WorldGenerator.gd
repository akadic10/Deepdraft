extends Node

const MacroLayout = preload("res://scripts/components/WorldLayout.gd")
const LayoutValidator = preload("res://scripts/components/WorldLayoutValidator.gd")
const Caves = preload("res://scripts/components/CaveLayout.gd")

var _cave_profile: Dictionary = {}
var _cave_layout: Dictionary = {"systems": [], "columns": {}, "soil": {}}
var spring_cave: Dictionary = {}
var _id_cave_soil: int = -1

# All "/" between two ints in this file are intentional, exact integer divisions
# (world/chunk sizing, centroid averaging). Suppress the integer_division warning
# file-wide rather than annotating each site.
@warning_ignore_start("integer_division")

## Seeded macro geography, column expansion, edge detail and streamed blocks.
##
## Call generate(new_seed) once at new-game time. Generation runs on a background
## Thread; the main thread receives completed chunks via the chunk_generated
## signal and builds meshes progressively.
##
## Pipeline phases (from 43_mining_materials.md):
##   1. Build resource, surface and moisture noise
##   2. Generate validated seeded macro geography and expand all column maps
##   3. Roughen cliff faces / shores and validate finished terrain
##   4. Build grass bands / tile ranges and stream requested block columns

# -- World dimensions ----------------------------------------------------------
# FULL WORLD: 1024 x 128 x 1024 = 134,217,728 blocks (32,768 chunks).
# 1 engine block = 0.5 m, so the playable boundary is 512 m x 512 m x 64 m.
# The active layout profile validates these dimensions; do not shrink them alone.
const WORLD_SIZE_X:  int = 1024
const WORLD_SIZE_Y:  int = 128
const WORLD_SIZE_Z:  int = 1024
const CHUNK_SIZE:    int = 16
const CHUNK_COUNT_X: int = WORLD_SIZE_X / CHUNK_SIZE   # 64
const CHUNK_COUNT_Y: int = WORLD_SIZE_Y / CHUNK_SIZE   # 8
const CHUNK_COUNT_Z: int = WORLD_SIZE_Z / CHUNK_SIZE   # 64
const BLOCK_COUNT_REPORT_INTERVAL_COLUMNS: int = 16

# -- Terrain domain classification ---------------------------------------------
const DOMAIN_MOUNTAIN: int = 2   # Y44+, mountain shelves
const DOMAIN_VALLEY:   int = 1   # Y20..43, foothill shelves (retained API name)
const DOMAIN_LOWLAND:  int = 0   # Y19 and below, lowland / lake basin

# -- Surface elevation ranges (Y in blocks) ------------------------------------
const BEDROCK_MAX_Y: int = 3
const FOUNDATION_ROCK_MAX_Y: int = 11
const MOUNTAIN_MIN: int = 44;  const MOUNTAIN_MAX: int = 115
const FOOTHILL_SHELF_MIN_Y: int = 20;  const FOOTHILL_SHELF_MAX_Y: int = 43
const TERRAIN_MACRO_CELL_SIZE: int = 32
const LOWLAND_SHELF_MIN_Y: int = 12
const LOWLAND_SHELF_MAX_Y: int = 19
const LOWLAND_CAP_GRASS_EDGE_1_WIDTH: int = 4
const LOWLAND_CAP_GRASS_EDGE_2_WIDTH: int = 6
const LOWLAND_CAP_GRASS_EDGE_3_WIDTH: int = 8
const LOWLAND_CAP_GRASS_EDGE_TOTAL_DISTANCE: int = LOWLAND_CAP_GRASS_EDGE_1_WIDTH + LOWLAND_CAP_GRASS_EDGE_2_WIDTH + LOWLAND_CAP_GRASS_EDGE_3_WIDTH
const FOOTHILL_CAP_GRASS_EDGE_1_WIDTH: int = 2
const FOOTHILL_CAP_GRASS_EDGE_2_WIDTH: int = 3
const FOOTHILL_CAP_GRASS_EDGE_3_WIDTH: int = 4
const FOOTHILL_CAP_GRASS_EDGE_TOTAL_DISTANCE: int = FOOTHILL_CAP_GRASS_EDGE_1_WIDTH + FOOTHILL_CAP_GRASS_EDGE_2_WIDTH + FOOTHILL_CAP_GRASS_EDGE_3_WIDTH
const FOOTHILL_SHELF_HEIGHT: int = 8
const MOUNTAIN_SHELF_HEIGHT: int = 12
const PLATEAU_MAX_MOUNTAIN_HEIGHT: int = 115
const MATERIAL_MACRO_CELL_SIZE: int = 32
const WATER_BANK_RADIUS: int = 4
const STEEP_SLOPE_ROCK_DELTA: int = 3

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

## Emitted (deferred, main thread) once the post-maps_ready grass-band surface
## passes finish. Listeners should refresh any surface meshes already built
## during the gate window so the grass-band tiers become visible.
signal grass_bands_ready()

# -- Generation state ----------------------------------------------------------
var world_seed: int = 0

# Independent resource, surface and moisture noise; geography uses MacroLayout.
var _metal_noise: Array[FastNoiseLite] = [] # one field per cached metal window
var noise_gem:      FastNoiseLite   # small gem pocket mask
var noise_soil:     FastNoiseLite   # cave soil patches + surface dirt fraction
var noise_domain:   FastNoiseLite   # broad surface material variation
var noise_moisture: FastNoiseLite   # broad moisture map (flora distribution; doc 14)

# 2D column maps  (index: x * WORLD_SIZE_Z + z)
var domain_map:   PackedInt32Array    # DOMAIN_* constant per column
var domain_n_map: PackedFloat32Array  # height-derived [0,1] terrain gradient per column
var heightmap:    PackedInt32Array    # surface Y per column
var waterline_map: PackedInt32Array   # -1 on dry land; each body's own waterline
var water_bodies: Array = []          # macro footprints, floor and waterline per body
var _layout_profile: Dictionary = {}
var _macro_layout: Dictionary = {}
var _layout_validation: Dictionary = {}

# Per-32x32-tile min/max VISIBLE height (waterline-aware), for the renderer's
# sliced-overview invalidation (doc 11 Phase SO): a slice change only affects
# tiles whose max reaches above the lower plane. Built on the generator thread
# after the grass bands; gated by _tile_ranges_ready (same pattern), with a
# conservative full-range fallback until ready.
const TILE_RANGE_SIZE: int = 32   # must match WorldRenderer.OVERVIEW_TILE_SIZE
var _tile_min_visible_y: PackedInt32Array = PackedInt32Array()
var _tile_max_visible_y: PackedInt32Array = PackedInt32Array()
var _tile_ranges_ready: bool = false
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
## Gate read on the main thread by the grass-band variant lookups. False while
## the deferred grass-band passes are still writing their arrays, so readers
## return the procedural fallback instead of touching arrays mid-write. Flipped
## true (main thread) by _deferred_finalize_grass_bands once writes complete.
var _grass_bands_ready: bool = false
var _column_in_flight: bool = false
var _block_spawn_counts: Dictionary = {}  # runtime block ID -> generated count
var _counted_columns: int = 0
var _last_count_report_column: int = 0
var _generation_metrics: Dictionary = {}
var _domain_counts: Dictionary = {}
var _startup_started_msec: int = 0
var _maps_ready_msec: int = 0
var _map_precompute_msec: int = 0
var _map_phase_timings: Array[Dictionary] = []
var _column_fill_msec_total: int = 0
var _column_fill_msec_max: int = 0
var _column_fill_count: int = 0
var _column_chunks_submitted: int = 0

## Cooperative cancel flag. Set true on the main thread (e.g. when the game
## stops) so the worker exits its chunk loop instead of touching members that
## are about to be torn down. Bool read/write is atomic enough for a one-way
## "stop now" signal - we never read it back into logic, only to bail out.
var _abort: bool = false


func _ready() -> void:
	_request_mutex = Mutex.new()
	print("WorldGenerator: ready.")


## Owning system loads static configuration before starting the worker thread.
## Also used by the offline seed-gallery test.
func load_macro_layout_profile() -> Dictionary:
	var path := "res://data/world_gen/macro_layout_v1.json"
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("WorldGenerator: cannot read macro layout profile.")
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		push_error("WorldGenerator: invalid macro layout profile.")
		return {}
	return parsed


func load_cave_profile() -> Dictionary:
	var file := FileAccess.open("res://data/world_gen/caves_v1.json", FileAccess.READ)
	if file == null:
		push_error("WorldGenerator: cannot read cave profile.")
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}


var river_layout: Dictionary = {}
var water_profile: Dictionary = {}

func load_water_profile() -> Dictionary:
	var file := FileAccess.open("res://data/world_gen/water.json", FileAccess.READ)
	return JSON.parse_string(file.get_as_text()) if file != null else {}

func _build_river() -> void:
	river_layout = preload("res://scripts/components/RiverLayout.gd").carve(world_seed, _macro_layout, heightmap, waterline_map, water_profile.river)
	for col: Vector2i in river_layout.columns:
		water_bank_columns[col] = true
	print("WorldGenerator: spring %s; river %d columns, %d falls." % [river_layout.spring, river_layout.columns.size(), river_layout.falls.size()])


func _build_cave_maps() -> void:
	spring_cave = {}
	if not river_layout.is_empty():
		spring_cave = preload("res://scripts/components/SpringCaveLayout.gd").build(world_seed,river_layout,heightmap,water_profile.spring_cave)
		# Form a continuous natural rock ledge where a rough cliff or a nearby
		# river bend had cut away its support. These are generated solid blocks,
		# not invisible navigation supports. Preserve the three-cell stream.
		for cell: Vector3i in spring_cave.ledges:
			var index := cell.x*WORLD_SIZE_Z+cell.z
			heightmap[index] = maxi(heightmap[index],cell.y)
			waterline_map[index] = -1
			river_layout.columns.erase(Vector2i(cell.x,cell.z))
			river_layout.initial_units.erase(Vector2i(cell.x,cell.z))
	_cave_layout = Caves.build(world_seed, heightmap, waterline_map, _cave_profile,spring_cave.get("bounds",Rect2i()))
	if not spring_cave.is_empty():
		var id: int = _cave_layout.systems.size()
		var indices := PackedInt32Array()
		var volume := 0
		for index: int in spring_cave.columns:
			var span: Vector3i = spring_cave.columns[index]
			span.z = id
			_cave_layout.columns[index] = span
			indices.append(index)
			volume += span.y-span.x
		indices.sort()
		_cave_layout.systems.append({"id":id,"center":spring_cave.source-Vector3i.UP,
			"floor_y":spring_cave.source.y-1,"ceiling_y":spring_cave.ceiling+1,
			"bounds":spring_cave.bounds,"columns":indices,"floor_area":indices.size(),
			"air_blocks":volume,"rooms":1,"soil_candidates":0,"surface_open":true})
		river_layout.spring = spring_cave.source
	# Cache actual exposed resources for the developer catalog. No extra ore is
	# painted onto caves: they intersect the same veins as ordinary tunneling.
	for system: Dictionary in _cave_layout["systems"]:
		var boundary: Dictionary = {}
		var soil_count := 0
		for index: int in system["columns"]:
			var x := index / WORLD_SIZE_Z
			var z := index % WORLD_SIZE_Z
			var span: Vector3i = _cave_layout["columns"][index]
			var floor_id := _generate_block_id(x, span.x, z)
			if floor_id == _id_cave_soil: soil_count += 1
			boundary[Vector3i(x, span.x, z)] = true
			for dir: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var next := Vector2i(x, z) + dir
				if _cave_layout["columns"].has(next.x * WORLD_SIZE_Z + next.y): continue
				for y in range(span.x + 1, span.y + 1): boundary[Vector3i(next.x, y, next.y)] = true
		var ores := 0
		for cell: Vector3i in boundary:
			var block_id := _generate_block_id(cell.x, cell.y, cell.z)
			for window: Dictionary in _resource_focus_windows:
				if window["channel"] != "soil" and window["id"] == block_id:
					ores += 1
					break
		system["exposed_resource_blocks"] = ores
		system["soil_columns"] = soil_count
	print("WorldGenerator: %d cave systems (including exposed spring when present)." % _cave_layout["systems"].size())


## Cave identity is independent of discovery. These APIs are for simulation
## and explicit developer inspection, never ordinary hidden-resource picking.
func get_cave_id(pos: Vector3i) -> int:
	if not _maps_ready or pos.x < 0 or pos.z < 0 or pos.x >= WORLD_SIZE_X or pos.z >= WORLD_SIZE_Z: return -1
	var span: Vector3i = _cave_layout["columns"].get(pos.x * WORLD_SIZE_Z + pos.z, Vector3i(-1, -1, -1))
	return span.z if pos.y > span.x and pos.y <= span.y else -1


func get_cave_catalog() -> Array:
	return _cave_layout["systems"].duplicate(true) if _maps_ready else []


func get_cave_air_cells(cave_id: int) -> Array[Vector3i]:
	var cells: Array[Vector3i] = []
	if not _maps_ready or cave_id < 0 or cave_id >= _cave_layout["systems"].size(): return cells
	for index: int in _cave_layout["systems"][cave_id]["columns"]:
		var span: Vector3i = _cave_layout["columns"][index]
		for y in range(span.x + 1, span.y + 1): cells.append(Vector3i(index / WORLD_SIZE_Z, y, index % WORLD_SIZE_Z))
	return cells


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


## Runs on the main thread after the generator thread finishes the deferred
## grass-band passes. Opening the gate here (rather than on the generator
## thread) guarantees the array writes are complete and visible before any
## reader is allowed in, and pairs the gate flip with the refresh request so
## listeners re-mesh surfaces that were built with fallback grass.
func _deferred_finalize_grass_bands() -> void:
	_grass_bands_ready = true
	print("WorldGenerator: grass bands finalized %.3f s after maps_ready." % (
		float(Time.get_ticks_msec() - _maps_ready_msec) / 1000.0))
	grass_bands_ready.emit()


func _deferred_print_generation_metrics(snapshot: Dictionary) -> void:
	var domains: Dictionary = snapshot.get("domains", {})
	var heights: Dictionary = snapshot.get("heights", {})
	var surface: Dictionary = snapshot.get("surface", {})
	var water: Dictionary = snapshot.get("water", {})
	var macro: Dictionary = snapshot.get("macro", {})
	var finished: Dictionary = macro.get("finished", {})

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
	print("  top surface: grass %.1f%%, dirt %.1f%%, rock %.1f%%, water %.1f%%" % [
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
	print("  finished terrain: summit %d columns, detailed %d, dry shore %d" % [
		finished.get("summit_columns", 0),
		finished.get("detailed_columns", 0),
		finished.get("shore_land_columns", 0),
	])
	print("  water: lake %s y%d floor %d-%d depth %d columns %d; tarn %s y%d floor %d-%d depth %d columns %d; banks %d" % [
		str(water.get("lake_center", Vector2i.ZERO)),
		water.get("lake_waterline", 0),
		water.get("lake_floor_min", 0),
		water.get("lake_floor_max", 0),
		water.get("lake_depth_max", 0),
		water.get("lake_columns", 0),
		str(water.get("tarn_center", Vector2i.ZERO)),
		water.get("tarn_waterline", 0),
		water.get("tarn_floor_min", 0),
		water.get("tarn_floor_max", 0),
		water.get("tarn_depth_max", 0),
		water.get("tarn_columns", 0),
		water.get("bank_columns", 0),
	])
	print("  layout: %s; attempts %d; fallback %s" % [
		macro.get("profile_id", ""), macro.get("attempts", 0), macro.get("used_fallback", false)])


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
	_layout_profile = load_macro_layout_profile()
	water_profile = load_water_profile()
	river_layout = {}
	var profile_errors := LayoutValidator.profile_errors(_layout_profile)
	if not profile_errors.is_empty():
		push_error("WorldGenerator: " + str(profile_errors))
		return

	# Clean up the thread object on the main thread once the world is done.
	world_complete.connect(_cleanup_thread, CONNECT_ONE_SHOT | CONNECT_DEFERRED)

	_gen_thread = Thread.new()
	_gen_thread.start(_generate_threaded)


## Stops any in-flight generation before the current scene is replaced by a
## loaded save. The next WorldRenderer starts a fresh deterministic run.
func prepare_for_world_reload() -> void:
	_abort = true
	if _gen_thread != null and _gen_thread.is_started():
		_gen_thread.wait_to_finish()
	_gen_thread = null
	_maps_ready = false
	_grass_bands_ready = false
	_tile_ranges_ready = false
	_request_mutex.lock()
	_column_queue.clear()
	_requested_columns.clear()
	_generated_columns.clear()
	_column_in_flight = false
	_request_mutex.unlock()


func _reset_generation_state() -> void:
	_macro_layout.clear()
	_layout_validation.clear()
	water_bodies.clear()
	waterline_map.clear()
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
	_grass_bands_ready = false
	_tile_ranges_ready = false
	_tile_min_visible_y.clear()
	_tile_max_visible_y.clear()
	_column_in_flight = false
	_generation_metrics.clear()
	_cave_layout = {"systems": [], "columns": {}, "soil": {}}
	spring_cave = {}
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


## True while a chunk column is requested but not yet generated (queued or in
## flight on the generator thread; the entry is erased on completion). The
## renderer uses this to defer region mesh rebuilds until a region's streaming
## columns are settled (doc 11 Phase 1e). Safe from any thread; one brief
## mutex acquisition.
func is_column_pending(cx: int, cz: int) -> bool:
	var key := Vector2i(cx, cz)
	_request_mutex.lock()
	var pending := _requested_columns.has(key)
	_request_mutex.unlock()
	return pending


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


## Terrain domain (DOMAIN_LOWLAND / DOMAIN_VALLEY / DOMAIN_MOUNTAIN) at a column.
## Returns -1 before maps are ready or out of bounds. O(1), thread-safe read of
## the immutable post-maps domain_map. Used by SurfaceFloraSpawner to gate flora
## by domain (e.g. pine = foothill + mountain only).
func get_domain(wx: int, wz: int) -> int:
	if not _maps_ready:
		return -1
	if wx < 0 or wx >= WORLD_SIZE_X or wz < 0 or wz >= WORLD_SIZE_Z:
		return -1
	return domain_map[wx * WORLD_SIZE_Z + wz]


## Moisture at a column in [0,1] (doc 14, flora distribution). Combines the broad
## moisture noise with two adjustments: higher columns trend drier, and columns on
## a water bank / lake / tarn read wetter. Deterministic from world_seed (Hard
## Rule 8). Returns 0.5 before maps ready / out of bounds. O(1), thread-safe read.
func get_moisture(wx: int, wz: int) -> float:
	if not _maps_ready:
		return 0.5
	if wx < 0 or wx >= WORLD_SIZE_X or wz < 0 or wz >= WORLD_SIZE_Z:
		return 0.5
	var m := (noise_moisture.get_noise_2d(float(wx), float(wz)) + 1.0) * 0.5
	# Elevation drying: drier as the surface rises above the foothill base.
	var sy: int = heightmap[wx * WORLD_SIZE_Z + wz]
	var dry := clampf(float(sy - FOOTHILL_SHELF_MIN_Y)
		/ float(PLATEAU_MAX_MOUNTAIN_HEIGHT - FOOTHILL_SHELF_MIN_Y), 0.0, 1.0)
	m -= dry * 0.35
	# Water-proximity boost: banks and water columns are wetter.
	var col := Vector2i(wx, wz)
	if water_bank_columns.has(col) or lake_columns.has(col) or tarn_columns.has(col):
		m += 0.25
	return clampf(m, 0.0, 1.0)


func get_visible_surface_y(wx: int, wz: int) -> int:
	if not _maps_ready or wx < 0 or wz < 0 or wx >= WORLD_SIZE_X or wz >= WORLD_SIZE_Z: return -1
	var index := wx * WORLD_SIZE_Z + wz
	return maxi(heightmap[index], waterline_map[index])


## Visible surface height for the overview's neighbor/side math, returning -1
## when the visible surface is non-solid (water) so callers can treat it as a
## map edge - matching the transparency result of get_generated_block_id without
## generating the (discarded) surface block. Water is the only transparent
## surface skin, so the lake/tarn check is equivalent. O(1), thread-safe.
func get_overview_surface_height(wx: int, wz: int) -> int:
	if not _maps_ready:
		return -1
	if wx < 0 or wx >= WORLD_SIZE_X or wz < 0 or wz >= WORLD_SIZE_Z:
		return -1
	var col := Vector2i(wx, wz)
	if lake_columns.has(col) or tarn_columns.has(col):
		return -1
	return heightmap[wx * WORLD_SIZE_Z + wz]


func get_visible_surface_block_id(wx: int, wz: int) -> int:
	if not _maps_ready:
		return BlockRegistry.AIR_ID
	if wx < 0 or wx >= WORLD_SIZE_X or wz < 0 or wz >= WORLD_SIZE_Z:
		return BlockRegistry.AIR_ID
	var col := Vector2i(wx, wz)
	if waterline_map[wx * WORLD_SIZE_Z + wz] >= 0:
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
		"moisture": get_moisture(wx, wz),
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
	if surface_y < LOWLAND_SHELF_MIN_Y:
		return "lake basin"
	return "unassigned"


func _lowland_cap_grass_band_debug(idx: int) -> int:
	if not _grass_bands_ready or lowland_cap_grass_band_map.is_empty():
		return 0
	return lowland_cap_grass_band_map[idx]


func _lowland_cap_grass_distance_debug(idx: int) -> int:
	if not _grass_bands_ready or lowland_cap_grass_distance_map.is_empty():
		return -1
	return lowland_cap_grass_distance_map[idx]


func _foothill_cap_grass_band_debug(idx: int) -> int:
	if not _grass_bands_ready or foothill_cap_grass_band_map.is_empty():
		return 0
	return foothill_cap_grass_band_map[idx]


func _foothill_cap_grass_distance_debug(idx: int) -> int:
	if not _grass_bands_ready or foothill_cap_grass_distance_map.is_empty():
		return -1
	return foothill_cap_grass_distance_map[idx]


func get_generated_block_id(wx: int, wy: int, wz: int) -> int:
	if not _maps_ready:
		return BlockRegistry.AIR_ID
	if wx < 0 or wx >= WORLD_SIZE_X or wy < 0 or wy >= WORLD_SIZE_Y or wz < 0 or wz >= WORLD_SIZE_Z:
		return BlockRegistry.AIR_ID
	return _generate_block_id(wx, wy, wz)


## Strata block id without ore/gem/soil veins or cave voids. Same authored rock
## the full generator would place, minus the 3D-noise detail. Used by the
## block-face overview for cliff-side coloring, where that detail is invisible
## but its noise sampling dominates the build cost. Thread-safe (reads only the
## immutable maps + noise; no member writes), so it is safe to call from a
## WorkerThreadPool task.
func get_overview_strata_block_id(wx: int, wy: int, wz: int) -> int:
	if not _maps_ready:
		return BlockRegistry.AIR_ID
	if wx < 0 or wx >= WORLD_SIZE_X or wy < 0 or wy >= WORLD_SIZE_Y or wz < 0 or wz >= WORLD_SIZE_Z:
		return BlockRegistry.AIR_ID
	return _generate_block_id(wx, wy, wz, false)


# -- ID cache (main thread) ----------------------------------------------------

func _cache_block_ids() -> void:
	_cave_profile = load_cave_profile()
	_id_cave_soil = BlockRegistry.get_id(&"base:terrain:soil:cave")
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
		var noise_field: Dictionary = def.get("noise_field", {})
		if expected_channel == "ore" and (not noise_field.has("seed_offset") or float(noise_field.get("frequency", 0.0)) <= 0.0 or int(noise_field.get("octaves", 0)) < 1 or int(noise_field.get("octaves", 0)) > 10):
			push_error("WorldGenerator: missing or invalid ore noise_field for %s." % String(key))
			continue
		windows.append({
			"key": key,
			"id": id,
			"min_y": int(depth_bias.get("min_y", 0)),
			"max_y": int(depth_bias.get("max_y", WORLD_SIZE_Y - 1)),
			"threshold": float(def.get("noise_threshold", 1.0)),
			"channel": channel,
			"noise_field": noise_field.duplicate(true),
		})
	return windows


# -- Pipeline (background thread) ----------------------------------------------

func _generate_threaded() -> void:
	var t_start := Time.get_ticks_msec()
	var t_maps_start := t_start

	_run_timed_map_phase("noise_instances", Callable(self, "_build_noise_instances"))             # Phase 1
	_run_timed_map_phase("seeded_layout", Callable(self, "_build_seeded_maps"))
	if _macro_layout.is_empty():
		call_deferred("_deferred_emit_world_complete")
		return
	_run_timed_map_phase("edge_detail", Callable(self, "_apply_edge_detail"))
	_run_timed_map_phase("layout_validation", Callable(self, "_validate_finished_layout"))
	if not _layout_validation.get("errors", []).is_empty():
		push_error("WorldGenerator: invalid finished terrain: " + str(_layout_validation["errors"]))
		call_deferred("_deferred_emit_world_complete")
		return
	_run_timed_map_phase("river", Callable(self, "_build_river"))
	_recount_domain_counts()
	_run_timed_map_phase("caves", Callable(self, "_build_cave_maps"))
	_maps_ready_msec = Time.get_ticks_msec()
	_map_precompute_msec = _maps_ready_msec - t_maps_start
	_maps_ready = true
	call_deferred("_deferred_emit_maps_ready")

	# Grass-band surface caps are cosmetic surface-variant overrides only; they
	# do not change terrain shape. They are deferred until AFTER maps_ready so
	# first-visible terrain does not wait on them. While they run, the
	# _grass_bands_ready gate keeps the variant readers from touching these
	# arrays, so the main-thread overview build (which renders fallback grass)
	# never reads them concurrently. _deferred_finalize_grass_bands flips the
	# gate and asks listeners to refresh once the arrays are fully written.
	_run_timed_map_phase("grass_bands", Callable(self, "_build_cap_grass_band_maps"))
	call_deferred("_deferred_finalize_grass_bands")
	_run_timed_map_phase("tile_ranges", Callable(self, "_build_tile_visible_ranges"))

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
	# Metals use independent seeded fields; coal deliberately keeps a broad scale.
	# Settings were copied from BlockRegistry before the generation thread starts.
	_metal_noise.clear()
	for window: Dictionary in _metal_windows:
		var settings: Dictionary = window["noise_field"]
		var field := FastNoiseLite.new()
		field.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		field.seed = world_seed + int(settings["seed_offset"])
		field.frequency = float(settings["frequency"])
		field.fractal_octaves = int(settings["octaves"])
		_metal_noise.append(field)

	# Layer 3 - Soil patch mask (also drives surface dirt fraction via 2D query)
	# Higher frequency, smooth noise for small irregular farmable soil pockets.
	noise_soil = FastNoiseLite.new()
	noise_soil.noise_type       = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise_soil.seed             = world_seed + 3
	noise_soil.frequency        = 0.03
	noise_soil.fractal_octaves  = 2

	# Layer 4 - Broad surface material variation (domain labels follow heights).
	noise_domain = FastNoiseLite.new()
	noise_domain.noise_type      = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise_domain.seed            = world_seed + 4
	noise_domain.frequency       = 0.0015
	noise_domain.fractal_octaves = 2

	# Layer 7 - Gem pocket mask
	# Higher frequency than metal veins so gems appear as smaller clusters.
	noise_gem = FastNoiseLite.new()
	noise_gem.noise_type       = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise_gem.seed             = world_seed + 7
	noise_gem.frequency        = 0.06
	noise_gem.fractal_octaves  = 3

	# Layer 8 - Moisture map (flora distribution, doc 14)
	# Very low frequency, broad wet/dry regions for the mixed-forest niches.
	noise_moisture = FastNoiseLite.new()
	noise_moisture.noise_type      = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise_moisture.seed            = world_seed + 8
	noise_moisture.frequency       = 0.004
	noise_moisture.fractal_octaves = 2


## Seeded layout is generated once, then expanded into authoritative column maps.
## Workers write disjoint X rows. Water metadata is published with the maps.
func _build_seeded_maps() -> void:
	_macro_layout = MacroLayout.new().generate(world_seed, _layout_profile)
	if not _macro_layout.get("ok", false):
		push_error("WorldGenerator: layout generation failed: " + str(_macro_layout.get("errors", [])))
		_macro_layout = {}
		return
	water_bodies = _macro_layout["water_bodies"].duplicate(true)
	# A prior world may still have read-only packed-array snapshots. Give the
	# worker rows exclusive backing storage before their disjoint writes;
	# resizing a shared array to the same size does not detach copy-on-write.
	heightmap = PackedInt32Array()
	domain_map = PackedInt32Array()
	domain_n_map = PackedFloat32Array()
	waterline_map = PackedInt32Array()
	heightmap.resize(WORLD_SIZE_X * WORLD_SIZE_Z)
	domain_map.resize(heightmap.size())
	domain_n_map.resize(heightmap.size())
	waterline_map.resize(heightmap.size())
	var task := WorkerThreadPool.add_group_task(_expand_layout_column, WORLD_SIZE_X, -1, false, "seeded geography")
	WorkerThreadPool.wait_for_group_task_completion(task)
	_rebuild_water_footprints()
	print("WorldGenerator: seeded layout %s; summit %d macro cells; water bodies %d." % [
		_layout_profile["profile_id"], _macro_layout["metrics"]["summit_cells"], water_bodies.size()])


## Rebuild membership from final water columns after shoreline rock displaces water.
func _rebuild_water_footprints() -> void:
	lake_columns.clear()
	tarn_columns.clear()
	for body: Dictionary in water_bodies:
		var columns: Dictionary = lake_columns if body["kind"] == "lowland_lake" else tarn_columns
		var sum := Vector2i.ZERO
		for index: int in body["cells"]:
			var corner := Vector2i(index / 32, index % 32) * TERRAIN_MACRO_CELL_SIZE
			sum += corner + Vector2i(16, 16)
			for x in range(corner.x, corner.x + TERRAIN_MACRO_CELL_SIZE):
				for z in range(corner.y, corner.y + TERRAIN_MACRO_CELL_SIZE):
					if waterline_map[x * WORLD_SIZE_Z + z] >= 0: columns[Vector2i(x, z)] = true
		if body["kind"] == "lowland_lake": lake_center = sum / body["cells"].size()
		else:
			tarn_center = sum / body["cells"].size()
			tarn_waterline = int(body["waterline_y"])
	_build_water_bank_mask()


func _expand_layout_column(x: int) -> void:
	var macro_heights: PackedInt32Array = _macro_layout["heights"]
	var macro_water: PackedInt32Array = _macro_layout["water_index"]
	for z in range(WORLD_SIZE_Z):
		var macro_index := (x / TERRAIN_MACRO_CELL_SIZE) * 32 + z / TERRAIN_MACRO_CELL_SIZE
		var index := x * WORLD_SIZE_Z + z
		var height := macro_heights[macro_index]
		heightmap[index] = height
		domain_map[index] = _domain_for_macro_shelf_height(height)
		domain_n_map[index] = _domain_value_for_height(height)
		var body := macro_water[macro_index]
		waterline_map[index] = int(water_bodies[body]["waterline_y"]) if body >= 0 else -1


func _domain_value_for_height(height: int) -> float:
	var rank := _macro_shelf_rank(height)
	if rank == 0: return 0.2
	if rank <= 3: return 0.4 + float(rank - 1) * 0.08
	return 0.64 + float(rank - 4) * 0.06


func _validate_finished_layout() -> void:
	_layout_validation = LayoutValidator.inspect_columns(_macro_layout, _layout_profile, heightmap, domain_map, waterline_map)


func get_waterline(wx: int, wz: int) -> int:
	if not _maps_ready or wx < 0 or wz < 0 or wx >= WORLD_SIZE_X or wz >= WORLD_SIZE_Z: return -1
	return waterline_map[wx * WORLD_SIZE_Z + wz]


func _is_foothill_shelf_column(x: int, z: int) -> bool:
	var idx := x * WORLD_SIZE_Z + z
	var h: int = heightmap[idx]
	if h < FOOTHILL_SHELF_MIN_Y or h > FOOTHILL_SHELF_MAX_Y:
		return false
	return true


func _is_lowland_shelf_column(x: int, z: int) -> bool:
	var h: int = heightmap[x * WORLD_SIZE_Z + z]
	return h >= LOWLAND_SHELF_MIN_Y and h <= LOWLAND_SHELF_MAX_Y


func _is_mountain_shelf_column(x: int, z: int) -> bool:
	var h: int = heightmap[x * WORLD_SIZE_Z + z]
	return h >= MOUNTAIN_MIN and h <= MOUNTAIN_MAX


func _apply_edge_detail() -> void:
	var source_heights := heightmap.duplicate()
	var macro_heights: PackedInt32Array = _macro_layout["heights"]
	var macro_water: PackedInt32Array = _macro_layout["water_index"]
	var config: Dictionary = _layout_profile["edge_detail"]
	var adjusted_columns := 0
	# Visit every original land boundary, including summit, lowland, foothill
	# and water banks. Detail grows outward; it never cuts the summit interior.
	# Read only original heights so the result is independent of traversal order.
	for cell in range(macro_heights.size()):
		if macro_water[cell] >= 0: continue
		var mx := cell / 32
		var mz := cell % 32
		var source_height := macro_heights[cell]
		var rank := _macro_shelf_rank(source_height)
		for direction: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next := Vector2i(mx, mz) + direction
			if next.x < 0 or next.y < 0 or next.x >= 32 or next.y >= 32: continue
			var neighbor := next.x * 32 + next.y
			if macro_heights[neighbor] >= source_height: continue
			var shore := macro_water[neighbor] >= 0
			var max_depth := int(config["shore_depth"] if shore else config["mountain_depth"] if rank >= 4 else config["foothill_depth"])
			for along in range(32):
				var x := mx * 32 + (31 if direction.x > 0 else 0 if direction.x < 0 else along)
				var z := mz * 32 + (31 if direction.y > 0 else 0 if direction.y < 0 else along)
				var roll := _edge_detail_hash(x / 2, z / 2, rank * 13)
				var depth := 1 + roll % max_depth
				# The dry lip varies in width as well as height. Beyond it, ledges
				# descend into the lake so both shoreline and submerged walls vary.
				var lip := roll % (depth + 1)
				for distance in range(1, depth + 1):
					var tx := x + direction.x * distance
					var tz := z + direction.y * distance
					var index := tx * WORLD_SIZE_Z + tz
					var height := source_height if shore and distance <= lip else _edge_detail_height(source_height, rank, x, z, distance)
					height = mini(height, _edge_detail_height_limit(tx, tz, source_heights, macro_water))
					if height <= heightmap[index]: continue
					heightmap[index] = height
					domain_map[index] = _domain_for_macro_shelf_height(height)
					domain_n_map[index] = _domain_value_for_height(height)
					if shore and height >= int(water_bodies[macro_water[neighbor]]["waterline_y"]): waterline_map[index] = -1
					adjusted_columns += 1
	_rebuild_water_footprints()
	print("WorldGenerator: edge detail -> pushed %d cliff/shore columns." % adjusted_columns)


func _edge_detail_hash(x: int, z: int, salt: int) -> int:
	return hash(Vector3i(x, salt ^ int(world_seed & 0x7fffffff), z)) & 0x7fffffff


## Prevent a protrusion at a shelf corner from creating a two-rank dry drop.
func _edge_detail_height_limit(x: int, z: int, original: PackedInt32Array, macro_water: PackedInt32Array) -> int:
	var limit := 115
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var nx := x + dx
			var nz := z + dz
			if nx < 0 or nz < 0 or nx >= WORLD_SIZE_X or nz >= WORLD_SIZE_Z: continue
			if macro_water[(nx / 32) * 32 + nz / 32] >= 0: continue
			var rank := _macro_shelf_rank(original[nx * WORLD_SIZE_Z + nz])
			limit = mini(limit, int(_layout_profile["shelf_tops"][mini(9, rank + 1)]))
	return limit


func _edge_detail_height(source_height: int, rank: int, x: int, z: int, distance: int) -> int:
	var step := MOUNTAIN_SHELF_HEIGHT if rank >= 4 else FOOTHILL_SHELF_HEIGHT
	var shelf_base := source_height - step + 1
	var offset_unit := 3 if rank >= 4 else 2
	var max_offset := step - 1
	var roll := _edge_detail_hash(x / 2, z / 2, rank * 31 + distance) % 3
	var offset := mini(max_offset, ((distance - 1) * offset_unit) + (roll * offset_unit))
	return clampi(source_height - offset, shelf_base, source_height)


func _macro_shelf_rank(height: int) -> int:
	if height <= LOWLAND_SHELF_MAX_Y:
		return 0
	if height < MOUNTAIN_MIN:
		var foothill_shelf := int(floor(float(height - FOOTHILL_SHELF_MIN_Y) / float(FOOTHILL_SHELF_HEIGHT)))
		return clampi(foothill_shelf + 1, 1, 3)
	var mountain_shelf := int(floor(float(height - MOUNTAIN_MIN) / float(MOUNTAIN_SHELF_HEIGHT)))
	return clampi(mountain_shelf + 4, 4, 9)


func _domain_for_macro_shelf_height(height: int) -> int:
	if height <= LOWLAND_SHELF_MAX_Y:
		return DOMAIN_LOWLAND
	if height < MOUNTAIN_MIN:
		return DOMAIN_VALLEY
	return DOMAIN_MOUNTAIN


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


## Builds the per-tile visible-height ranges (doc 11 Phase SO). Runs on the
## generator thread; readers are gated by _tile_ranges_ready, flipped on the
## main thread after the arrays are fully written.
func _build_tile_visible_ranges() -> void:
	var tiles_x := (WORLD_SIZE_X + TILE_RANGE_SIZE - 1) / TILE_RANGE_SIZE
	var tiles_z := (WORLD_SIZE_Z + TILE_RANGE_SIZE - 1) / TILE_RANGE_SIZE
	_tile_min_visible_y.resize(tiles_x * tiles_z)
	_tile_min_visible_y.fill(WORLD_SIZE_Y)
	_tile_max_visible_y.resize(tiles_x * tiles_z)
	_tile_max_visible_y.fill(0)

	for x in range(WORLD_SIZE_X):
		var tx := x / TILE_RANGE_SIZE
		for z in range(WORLD_SIZE_Z):
			var v: int = heightmap[x * WORLD_SIZE_Z + z]
			v = maxi(v, waterline_map[x * WORLD_SIZE_Z + z])
			var idx := tx * tiles_z + (z / TILE_RANGE_SIZE)
			if v < _tile_min_visible_y[idx]:
				_tile_min_visible_y[idx] = v
			if v > _tile_max_visible_y[idx]:
				_tile_max_visible_y[idx] = v

	call_deferred("_deferred_mark_tile_ranges_ready")


func _deferred_mark_tile_ranges_ready() -> void:
	_tile_ranges_ready = true


## Per-32x32-tile visible-height range (min, max), waterline-aware. Returns the
## full world range until the ranges are computed — conservative: every tile
## then counts as slice-affected. Thread-safe after the ready gate flips (the
## arrays are immutable from that point).
func get_tile_visible_range(tx: int, tz: int) -> Vector2i:
	if not _tile_ranges_ready:
		return Vector2i(0, WORLD_SIZE_Y - 1)
	var tiles_x := (WORLD_SIZE_X + TILE_RANGE_SIZE - 1) / TILE_RANGE_SIZE
	var tiles_z := (WORLD_SIZE_Z + TILE_RANGE_SIZE - 1) / TILE_RANGE_SIZE
	if tx < 0 or tx >= tiles_x or tz < 0 or tz >= tiles_z:
		return Vector2i(0, WORLD_SIZE_Y - 1)
	return Vector2i(_tile_min_visible_y[tx * tiles_z + tz], _tile_max_visible_y[tx * tiles_z + tz])


## Shared 8-neighbour offsets for the cap grass-band passes. A const, NOT a
## function returning a fresh array: the old _lowland_cap_neighbor_offsets()
## allocated a typed 8-element array per call — once per BFS dequeue and per
## seed candidate across two 1M-column passes, the single largest cost of the
## band phase (which gates the overview tiles' final grass colours).
const CAP_GRASS_NEIGHBOR_OFFSETS: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(0, -1),
	Vector2i(1, 1),
	Vector2i(1, -1),
	Vector2i(-1, 1),
	Vector2i(-1, -1),
]


## Fused builder for BOTH cap grass-band maps. One 1M-column seed scan feeds
## the lowland and foothill maps together — their cap heights are disjoint
## (lowland cap is exactly LOWLAND_SHELF_MAX_Y = 19; foothill shelves span
## 20–43), so each column is at most one kind of cap and one `elif` chain
## replaces what used to be two full scans. The two BFS floods stay inline and
## verbatim (packed arrays are copy-on-write across function boundaries, so a
## shared helper mutating them via parameters would silently write to copies).
## Output is byte-identical to the former two-pass build: seeds enqueue in the
## same x,z order, and each BFS is unchanged. The bands gate the overview
## tiles' final grass colours — every second saved here is a second less of
## band tiles building twice at startup.
func _build_cap_grass_band_maps() -> void:
	var total_columns := WORLD_SIZE_X * WORLD_SIZE_Z
	lowland_cap_grass_band_map.resize(total_columns)
	lowland_cap_grass_band_map.fill(0)
	lowland_cap_grass_distance_map.resize(total_columns)
	lowland_cap_grass_distance_map.fill(-1)
	foothill_cap_grass_band_map.resize(total_columns)
	foothill_cap_grass_band_map.fill(0)
	foothill_cap_grass_distance_map.resize(total_columns)
	foothill_cap_grass_distance_map.fill(-1)

	var lowland_distances := PackedInt32Array()
	lowland_distances.resize(total_columns)
	lowland_distances.fill(-1)
	var foothill_distances := PackedInt32Array()
	foothill_distances.resize(total_columns)
	foothill_distances.fill(-1)

	var lowland_queue: Array[int] = []
	var foothill_queue: Array[int] = []

	for x in range(WORLD_SIZE_X):
		var row := x * WORLD_SIZE_Z
		for z in range(WORLD_SIZE_Z):
			var idx := row + z
			var h: int = heightmap[idx]
			if h == LOWLAND_SHELF_MAX_Y:
				if not _is_lowland_cap_grass_band_column(x, z, idx):
					continue
				lowland_cap_grass_band_map[idx] = 4
				if _is_lowland_cap_grass_band_seed(x, z):
					lowland_cap_grass_band_map[idx] = 1
					lowland_distances[idx] = 0
					lowland_cap_grass_distance_map[idx] = 0
					lowland_queue.append(idx)
			elif h >= FOOTHILL_SHELF_MIN_Y and h <= FOOTHILL_SHELF_MAX_Y:
				if not _is_foothill_cap_grass_band_column(x, z):
					continue
				foothill_cap_grass_band_map[idx] = 4
				if _is_foothill_cap_grass_band_seed(x, z, idx):
					foothill_cap_grass_band_map[idx] = 1
					foothill_distances[idx] = 0
					foothill_cap_grass_distance_map[idx] = 0
					foothill_queue.append(idx)

	# BFS floods. The neighbour loop is UNROLLED into pure integer index deltas
	# (±1 = z, ±stride = x, and the four diagonal sums) with boolean edge
	# guards — measured 2026-07-31: with the offsets const and the fused scan
	# in place, these floods were the entire remaining ~4.2 s of the band
	# phase, and per-node Vector2i iteration was the cost. Output is identical
	# to the offsets-loop version: BFS level order doesn't depend on
	# intra-level neighbour order, and the band value is a function of
	# distance alone (precomputed once per dequeued node — every accepted
	# neighbour shares the same next_distance).
	var stride := WORLD_SIZE_Z

	# Lowland flood.
	var head := 0
	while head < lowland_queue.size():
		var idx := lowland_queue[head]
		head += 1

		var distance := lowland_distances[idx]
		if distance >= LOWLAND_CAP_GRASS_EDGE_TOTAL_DISTANCE - 1:
			continue

		var x := idx / stride
		var z := idx % stride
		var next_distance := distance + 1
		var band := _lowland_cap_grass_band_for_distance(next_distance)
		var x_hi := x < WORLD_SIZE_X - 1
		var x_lo := x > 0
		var z_hi := z < WORLD_SIZE_Z - 1
		var z_lo := z > 0

		if x_hi:
			var nidx := idx + stride
			if lowland_cap_grass_band_map[nidx] != 0 and lowland_distances[nidx] == -1:
				lowland_distances[nidx] = next_distance
				lowland_cap_grass_distance_map[nidx] = next_distance
				lowland_cap_grass_band_map[nidx] = band
				lowland_queue.append(nidx)
		if x_lo:
			var nidx := idx - stride
			if lowland_cap_grass_band_map[nidx] != 0 and lowland_distances[nidx] == -1:
				lowland_distances[nidx] = next_distance
				lowland_cap_grass_distance_map[nidx] = next_distance
				lowland_cap_grass_band_map[nidx] = band
				lowland_queue.append(nidx)
		if z_hi:
			var nidx := idx + 1
			if lowland_cap_grass_band_map[nidx] != 0 and lowland_distances[nidx] == -1:
				lowland_distances[nidx] = next_distance
				lowland_cap_grass_distance_map[nidx] = next_distance
				lowland_cap_grass_band_map[nidx] = band
				lowland_queue.append(nidx)
		if z_lo:
			var nidx := idx - 1
			if lowland_cap_grass_band_map[nidx] != 0 and lowland_distances[nidx] == -1:
				lowland_distances[nidx] = next_distance
				lowland_cap_grass_distance_map[nidx] = next_distance
				lowland_cap_grass_band_map[nidx] = band
				lowland_queue.append(nidx)
		if x_hi and z_hi:
			var nidx := idx + stride + 1
			if lowland_cap_grass_band_map[nidx] != 0 and lowland_distances[nidx] == -1:
				lowland_distances[nidx] = next_distance
				lowland_cap_grass_distance_map[nidx] = next_distance
				lowland_cap_grass_band_map[nidx] = band
				lowland_queue.append(nidx)
		if x_hi and z_lo:
			var nidx := idx + stride - 1
			if lowland_cap_grass_band_map[nidx] != 0 and lowland_distances[nidx] == -1:
				lowland_distances[nidx] = next_distance
				lowland_cap_grass_distance_map[nidx] = next_distance
				lowland_cap_grass_band_map[nidx] = band
				lowland_queue.append(nidx)
		if x_lo and z_hi:
			var nidx := idx - stride + 1
			if lowland_cap_grass_band_map[nidx] != 0 and lowland_distances[nidx] == -1:
				lowland_distances[nidx] = next_distance
				lowland_cap_grass_distance_map[nidx] = next_distance
				lowland_cap_grass_band_map[nidx] = band
				lowland_queue.append(nidx)
		if x_lo and z_lo:
			var nidx := idx - stride - 1
			if lowland_cap_grass_band_map[nidx] != 0 and lowland_distances[nidx] == -1:
				lowland_distances[nidx] = next_distance
				lowland_cap_grass_distance_map[nidx] = next_distance
				lowland_cap_grass_band_map[nidx] = band
				lowland_queue.append(nidx)

	# Foothill flood — same unrolled shape.
	head = 0
	while head < foothill_queue.size():
		var idx := foothill_queue[head]
		head += 1

		var distance := foothill_distances[idx]
		if distance >= FOOTHILL_CAP_GRASS_EDGE_TOTAL_DISTANCE - 1:
			continue

		var x := idx / stride
		var z := idx % stride
		var next_distance := distance + 1
		var band := _foothill_cap_grass_band_for_distance(next_distance)
		var x_hi := x < WORLD_SIZE_X - 1
		var x_lo := x > 0
		var z_hi := z < WORLD_SIZE_Z - 1
		var z_lo := z > 0

		if x_hi:
			var nidx := idx + stride
			if foothill_cap_grass_band_map[nidx] != 0 and foothill_distances[nidx] == -1:
				foothill_distances[nidx] = next_distance
				foothill_cap_grass_distance_map[nidx] = next_distance
				foothill_cap_grass_band_map[nidx] = band
				foothill_queue.append(nidx)
		if x_lo:
			var nidx := idx - stride
			if foothill_cap_grass_band_map[nidx] != 0 and foothill_distances[nidx] == -1:
				foothill_distances[nidx] = next_distance
				foothill_cap_grass_distance_map[nidx] = next_distance
				foothill_cap_grass_band_map[nidx] = band
				foothill_queue.append(nidx)
		if z_hi:
			var nidx := idx + 1
			if foothill_cap_grass_band_map[nidx] != 0 and foothill_distances[nidx] == -1:
				foothill_distances[nidx] = next_distance
				foothill_cap_grass_distance_map[nidx] = next_distance
				foothill_cap_grass_band_map[nidx] = band
				foothill_queue.append(nidx)
		if z_lo:
			var nidx := idx - 1
			if foothill_cap_grass_band_map[nidx] != 0 and foothill_distances[nidx] == -1:
				foothill_distances[nidx] = next_distance
				foothill_cap_grass_distance_map[nidx] = next_distance
				foothill_cap_grass_band_map[nidx] = band
				foothill_queue.append(nidx)
		if x_hi and z_hi:
			var nidx := idx + stride + 1
			if foothill_cap_grass_band_map[nidx] != 0 and foothill_distances[nidx] == -1:
				foothill_distances[nidx] = next_distance
				foothill_cap_grass_distance_map[nidx] = next_distance
				foothill_cap_grass_band_map[nidx] = band
				foothill_queue.append(nidx)
		if x_hi and z_lo:
			var nidx := idx + stride - 1
			if foothill_cap_grass_band_map[nidx] != 0 and foothill_distances[nidx] == -1:
				foothill_distances[nidx] = next_distance
				foothill_cap_grass_distance_map[nidx] = next_distance
				foothill_cap_grass_band_map[nidx] = band
				foothill_queue.append(nidx)
		if x_lo and z_hi:
			var nidx := idx - stride + 1
			if foothill_cap_grass_band_map[nidx] != 0 and foothill_distances[nidx] == -1:
				foothill_distances[nidx] = next_distance
				foothill_cap_grass_distance_map[nidx] = next_distance
				foothill_cap_grass_band_map[nidx] = band
				foothill_queue.append(nidx)
		if x_lo and z_lo:
			var nidx := idx - stride - 1
			if foothill_cap_grass_band_map[nidx] != 0 and foothill_distances[nidx] == -1:
				foothill_distances[nidx] = next_distance
				foothill_cap_grass_distance_map[nidx] = next_distance
				foothill_cap_grass_band_map[nidx] = band
				foothill_queue.append(nidx)


func _is_lowland_cap_grass_band_column(x: int, z: int, idx: int) -> bool:
	if heightmap[idx] != LOWLAND_SHELF_MAX_Y:
		return false
	var col := Vector2i(x, z)
	return not lake_columns.has(col) and not tarn_columns.has(col)


func _is_lowland_cap_grass_band_seed(x: int, z: int) -> bool:
	for offset: Vector2i in CAP_GRASS_NEIGHBOR_OFFSETS:
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


func _is_foothill_cap_grass_band_column(x: int, z: int) -> bool:
	if not _is_foothill_shelf_column(x, z):
		return false
	var col := Vector2i(x, z)
	return not lake_columns.has(col) and not tarn_columns.has(col)


func _is_foothill_cap_grass_band_seed(x: int, z: int, idx: int) -> bool:
	var center_height := heightmap[idx]
	for offset: Vector2i in CAP_GRASS_NEIGHBOR_OFFSETS:
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
	var lake_waterline := int(_layout_profile["lowland_lake"]["waterline_y"])
	var lake_floor := _water_floor_metrics(lake_columns, lake_waterline)
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
		"caves": {"systems": _cave_layout["systems"].size(), "floor_columns": _cave_layout["columns"].size()},
		"water": {
			"lake_center": lake_center,
			"lake_waterline": lake_waterline,
			"lake_columns": lake_columns.size(),
			"lake_floor_min": lake_floor.get("floor_min", 0),
			"lake_floor_max": lake_floor.get("floor_max", 0),
			"lake_depth_max": lake_floor.get("depth_max", 0),
			"tarn_center": tarn_center,
			"tarn_waterline": tarn_waterline,
			"tarn_columns": tarn_columns.size(),
			"tarn_floor_min": tarn_floor.get("floor_min", 0),
			"tarn_floor_max": tarn_floor.get("floor_max", 0),
			"tarn_depth_max": tarn_floor.get("depth_max", 0),
			"bank_columns": water_bank_columns.size(),
			"bodies": water_bodies.duplicate(true),
		},
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


## One top visible generated block per column, including water above its bed.
## This measures plan-view coverage, not exposed cliff area or material volume.
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
			var idx := x * WORLD_SIZE_Z + z
			var visible_y := maxi(heightmap[idx], waterline_map[idx])
			var block_id := _generate_block_id(x, visible_y, z)
			var category := _surface_category(block_id)
			counts[category] = (counts[category] as int) + 1
			var bucket: Dictionary = by_domain[_domain_label(domain_map[idx])]
			bucket[category] = (bucket[category] as int) + 1
			bucket["total"] = (bucket["total"] as int) + 1

	for key: String in by_domain.keys():
		_add_surface_bucket_percentages(by_domain[key])

	return {
		"total": total_columns,
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
	return {"profile_id": _layout_profile.get("profile_id", ""),
		"attempts": _macro_layout.get("attempts", 0), "used_fallback": _macro_layout.get("used_fallback", false),
		"macro": _macro_layout.get("metrics", {}).duplicate(true), "finished": _layout_validation.duplicate(true)}


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
	var max_y := 0
	for x in range(cx * CHUNK_SIZE, (cx + 1) * CHUNK_SIZE):
		for z in range(cz * CHUNK_SIZE, (cz + 1) * CHUNK_SIZE):
			var index := x * WORLD_SIZE_Z + z
			max_y = maxi(max_y, maxi(heightmap[index], waterline_map[index]))
	return max_y


# apply_resource_detail: when false, the authored strata rock is returned
# without ore/gem/soil vein replacement and without cave voids. The block-face
# overview uses this for cliff-side coloring, where the 3D resource/cave noise
# is invisible at navigation zoom but dominates the per-column cost. Real chunk
# generation always passes true.
func _generate_block_id(x: int, y: int, z: int, apply_resource_detail: bool = true) -> int:
	var col    := Vector2i(x, z)
	var surf_y := heightmap[x * WORLD_SIZE_Z + z]

	# Absolute floor - four-layer bedrock protocol.
	if y <= BEDROCK_MAX_Y:
		return _id_bedrock

	# Stable foundation layer above bedrock.
	if y > BEDROCK_MAX_Y and y <= FOUNDATION_ROCK_MAX_Y:
		return _apply_resource_veins(x, y, z, surf_y, _id_rock11) if apply_resource_detail else _id_rock11

	# Above surface
	if y > surf_y:
		if y <= waterline_map[x * WORLD_SIZE_Z + z]:
			return _id_water
		return _id_void

	if apply_resource_detail:
		var cave: Vector3i = _cave_layout["columns"].get(x * WORLD_SIZE_Z + z, Vector3i(-1, -1, -1))
		if y > cave.x and y <= cave.y: return _id_void

	if _is_lowland_shelf_column(x, z) and y >= LOWLAND_SHELF_MIN_Y and y <= LOWLAND_SHELF_MAX_Y:
		var lowland_block := _lowland_shelf_block_id(x, z, y)
		return _apply_resource_veins(x, y, z, surf_y, lowland_block) if apply_resource_detail else lowland_block

	if _is_foothill_shelf_column(x, z) and y >= LOWLAND_SHELF_MIN_Y and y < _foothill_shelf_start_for_column(x, z):
		var foothill_body_block := _foothill_body_rock_id(y)
		return _apply_resource_veins(x, y, z, surf_y, foothill_body_block) if apply_resource_detail else foothill_body_block

	if _is_foothill_shelf_column(x, z) and y >= FOOTHILL_SHELF_MIN_Y and y <= FOOTHILL_SHELF_MAX_Y:
		var foothill_shelf_block := _foothill_shelf_block_id(x, z, y)
		return _apply_resource_veins(x, y, z, surf_y, foothill_shelf_block) if apply_resource_detail else foothill_shelf_block

	if _is_mountain_shelf_column(x, z) and y >= LOWLAND_SHELF_MIN_Y and y < MOUNTAIN_MIN:
		var mountain_body_block := _altitude_rock_body_id(y)
		return _apply_resource_veins(x, y, z, surf_y, mountain_body_block) if apply_resource_detail else mountain_body_block

	if _is_mountain_shelf_column(x, z) and y >= MOUNTAIN_MIN and y <= MOUNTAIN_MAX:
		var mountain_shelf_block := _mountain_shelf_block_id(y)
		return _apply_resource_veins(x, y, z, surf_y, mountain_shelf_block) if apply_resource_detail else mountain_shelf_block

	# Surface skin
	if y == surf_y:
		return _pick_surface_block(x, z, col)

	# Fallback for columns outside authored strata ranges. Current worldgen
	# should rarely reach this; keep it on the active rock ladder if it does.
	var fallback_rock := _fallback_rock_id(y)
	return _apply_resource_veins(x, y, z, surf_y, fallback_rock) if apply_resource_detail else fallback_rock


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


## True when any column of the tile rect carries a nonzero cap grass-band
## override. Band-0 columns resolve identically before and after the
## _grass_bands_ready gate (_grass_variant falls through to the pure position
## hash), so a tile with no band columns meshes the same either way —
## WorldRenderer._on_grass_bands_ready uses this to requeue ONLY tiles whose
## meshes actually change when the bands finalize, instead of every built tile.
## Main-thread only, after the gate has flipped (the maps are complete then).
## Heightmap-only PREDICTION of tile_has_grass_band, safe to call the moment
## maps_ready flips — the band maps themselves may still be mid-build on the
## generator thread then, but band-capable columns are exactly the cap-height
## columns (lowland: h == LOWLAND_SHELF_MAX_Y; foothill: h in shelf range),
## and the heightmap is final at maps_ready. Samples a stride-4 grid rather
## than every column: cap plateaus are large contiguous regions, so a missed
## sliver (< 4 columns wide) merely falls back to today's behaviour for that
## tile (built early, requeued at bands-ready) — never a correctness issue.
## WorldRenderer uses this to order band-capable tiles LAST in the full
## overview build, so the band passes finish before those tiles build.
func tile_may_have_grass_band(tx: int, tz: int, tile_size: int) -> bool:
	var x0 := tx * tile_size
	var z0 := tz * tile_size
	var x1 := mini(x0 + tile_size, WORLD_SIZE_X)
	var z1 := mini(z0 + tile_size, WORLD_SIZE_Z)
	for x in range(x0, x1, 4):
		var row := x * WORLD_SIZE_Z
		for z in range(z0, z1, 4):
			var h: int = heightmap[row + z]
			if h == LOWLAND_SHELF_MAX_Y \
					or (h >= FOOTHILL_SHELF_MIN_Y and h <= FOOTHILL_SHELF_MAX_Y):
				return true
	return false


func tile_has_grass_band(tx: int, tz: int, tile_size: int) -> bool:
	var check_lowland := not lowland_cap_grass_band_map.is_empty()
	var check_foothill := not foothill_cap_grass_band_map.is_empty()
	if not check_lowland and not check_foothill:
		return false
	var x0 := tx * tile_size
	var z0 := tz * tile_size
	var x1 := mini(x0 + tile_size, WORLD_SIZE_X)
	var z1 := mini(z0 + tile_size, WORLD_SIZE_Z)
	for x in range(x0, x1):
		var row := x * WORLD_SIZE_Z
		for z in range(z0, z1):
			var idx := row + z
			if check_lowland and lowland_cap_grass_band_map[idx] != 0:
				return true
			if check_foothill and foothill_cap_grass_band_map[idx] != 0:
				return true
	return false


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
	if not _grass_bands_ready:
		return -1
	if lowland_cap_grass_band_map.is_empty():
		return -1
	var idx := x * WORLD_SIZE_Z + z
	var band := lowland_cap_grass_band_map[idx]
	if band <= 0:
		return -1
	return int(band) - 1


func _foothill_cap_grass_band_variant_index(x: int, z: int) -> int:
	if not _grass_bands_ready:
		return -1
	if foothill_cap_grass_band_map.is_empty():
		return -1
	var idx := x * WORLD_SIZE_Z + z
	var band := foothill_cap_grass_band_map[idx]
	if band <= 0:
		return -1
	return int(band) - 1


func _uses_lowland_grass_palette(x: int, z: int) -> bool:
	return domain_map[x * WORLD_SIZE_Z + z] == DOMAIN_LOWLAND


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

	var ore := _pick_metal_from_fields(x, y, z)
	if ore != -1:
		return ore

	var column_index := x * WORLD_SIZE_Z + z
	if _cave_layout["soil"].has(column_index) and y == (_cave_layout["columns"][column_index] as Vector3i).x:
		return _id_cave_soil

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


func _pick_metal_from_fields(x: int, y: int, z: int) -> int:
	# Priority resolves actual spatial overlaps, not intervals of one shared field.
	# Reject depth first so each block only samples fields that could replace it.
	for i in range(_metal_windows.size()):
		var window: Dictionary = _metal_windows[i]
		if y < window["min_y"] or y > window["max_y"]:
			continue
		var value := (_metal_noise[i].get_noise_3d(x, y, z) + 1.0) * 0.5
		if value > window["threshold"]:
			return window["id"]
	return -1


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
