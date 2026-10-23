extends Node

const MacroLayout = preload("res://scripts/components/WorldLayout.gd")
const LayoutValidator = preload("res://scripts/components/WorldLayoutValidator.gd")
const Caves = preload("res://scripts/components/CaveLayout.gd")
const JsonData = preload("res://scripts/registries/JsonData.gd")
const BlockFill = preload("res://scripts/components/WorldBlockFill.gd")
const Metrics = preload("res://scripts/components/WorldGenerationMetrics.gd")

var _cave_profile: Dictionary = {}
var _cave_layout: Dictionary = {"systems": [], "columns": {}, "soil": {}}:
	set(value):
		_cave_layout = value
		if block_fill != null: block_fill.bind_layers()
var spring_cave: Dictionary = {}

# All "/" between two ints in this file are intentional, exact integer divisions
# (world/chunk sizing, centroid averaging). Suppress the integer_division warning
# file-wide rather than annotating each site.
@warning_ignore_start("integer_division")

## Seeded macro geography, column expansion and edge detail.
##
## Call generate(new_seed) once at new-game time. The maps are built on a
## background Thread that ends when they are done; blocks are then read on
## demand through get_generated_block_id() and the overview helpers.
##
## Pipeline phases (from 43_mining_materials.md):
##   1. Build resource, surface and moisture noise
##   2. Generate validated seeded macro geography and expand all column maps
##   3. Roughen cliff faces / shores and validate finished terrain
##   4. Build caves, tile ranges and generation metrics

# -- World dimensions ----------------------------------------------------------
# WorldData owns the size (1 block = 0.5 m: a 512 m x 512 m x 64 m world).
# The active layout profile validates these dimensions; do not shrink them alone.
const WORLD_SIZE_X:  int = WorldData.WORLD_SIZE_X
const WORLD_SIZE_Y:  int = WorldData.WORLD_SIZE_Y
const WORLD_SIZE_Z:  int = WorldData.WORLD_SIZE_Z
const CHUNK_SIZE:   int = 16
const CHUNK_COUNT_X: int = WORLD_SIZE_X / CHUNK_SIZE   # 64
const CHUNK_COUNT_Y: int = WORLD_SIZE_Y / CHUNK_SIZE   # 8
const CHUNK_COUNT_Z: int = WORLD_SIZE_Z / CHUNK_SIZE   # 64

# -- Terrain domain classification (WorldBlockFill owns the strata constants) --
const DOMAIN_MOUNTAIN: int = BlockFill.DOMAIN_MOUNTAIN   # Y44+, mountain shelves
const DOMAIN_VALLEY:   int = BlockFill.DOMAIN_VALLEY     # Y20..43, foothill shelves (retained API name)
const DOMAIN_LOWLAND:  int = BlockFill.DOMAIN_LOWLAND    # Y19 and below, lowland / lake basin

# -- Surface elevation ranges (Y in blocks) ------------------------------------
const BEDROCK_MAX_Y: int = BlockFill.BEDROCK_MAX_Y
const TERRAIN_MACRO_CELL_SIZE: int = 32
const LOWLAND_SHELF_MIN_Y: int = BlockFill.LOWLAND_SHELF_MIN_Y
# Shelf bands come from the layout profile's shelf_tops (_apply_shelf_bands):
# rank 0 lowland, ranks 1-3 foothill shelves, ranks 4-9 mountain shelves.
var _lowland_shelf_max_y := 0;  var _foothill_shelf_min_y := 0;  var _foothill_shelf_max_y := 0
var _foothill_shelf_height := 0;  var _mountain_min := 0;  var _mountain_max := 0;  var _mountain_shelf_height := 0
const WATER_BANK_RADIUS: int = 4

# -- Signals -------------------------------------------------------------------
## Emitted on the main thread when the generator thread has finished (maps
## built, or generation failed).
signal world_complete()
## Emitted on the main thread once the terrain maps are built (is_maps_ready() is true).
signal maps_ready()

## Emitted on the main thread when generation stops without producing maps.
## The maps never become ready after this; generation_error holds the reason.
signal generation_failed(reason: String)

## Empty while generation is running or has succeeded.
var generation_error := ""


# -- Generation state ----------------------------------------------------------
var world_seed: int = 0

# Per-block identity: strata, surface skin, veins, block ids and resource windows.
var block_fill := BlockFill.new(self)

# Independent resource, surface and moisture noise; geography uses MacroLayout.
# The per-metal fields live in block_fill.metal_noise.
# Setters keep block_fill's direct references current (bind_layers).
var noise_gem: FastNoiseLite:   # small gem pocket mask
	set(value): noise_gem = value; block_fill.bind_layers()
var noise_soil: FastNoiseLite:   # cave soil patches + surface dirt fraction
	set(value): noise_soil = value; block_fill.bind_layers()
var noise_domain: FastNoiseLite:   # broad surface material variation
	set(value): noise_domain = value; block_fill.bind_layers()
var noise_moisture: FastNoiseLite   # broad moisture map (flora distribution; doc 42 World placement)

# 2D column maps  (index: x * WORLD_SIZE_Z + z)
var domain_map:   PackedInt32Array    # DOMAIN_* constant per column
var domain_n_map: PackedFloat32Array  # height-derived [0,1] terrain gradient per column
var heightmap:    PackedInt32Array    # surface Y per column
var waterline_map: PackedInt32Array   # -1 on dry land; each body's own waterline
var water_bodies: Array = []          # macro footprints, floor and waterline per body
var _layout_profile: Dictionary = {}:
	set(value):
		_layout_profile = value
		_apply_shelf_bands()
var _macro_layout: Dictionary = {}
var _layout_validation: Dictionary = {}

# Per-32x32-tile min/max VISIBLE height (waterline-aware), for the renderer's
# sliced-overview invalidation (doc 11 Phase SO): a slice change only affects
# tiles whose max reaches above the lower plane. Built on the generator thread
# after maps_ready; gated by _tile_ranges_ready, with a
# conservative full-range fallback until ready.
const TILE_RANGE_SIZE: int = 32   # must match WorldRenderer.OVERVIEW_TILE_SIZE
var _tile_min_visible_y: PackedInt32Array = PackedInt32Array()
var _tile_max_visible_y: PackedInt32Array = PackedInt32Array()
var _tile_ranges_ready: bool = false

# Lake / tarn geometry
var lake_columns: Dictionary = {}   # Vector2i -> true  (lowland lake footprint)
var tarn_columns: Dictionary = {}   # Vector2i -> true  (mountain tarn footprint)
var water_bank_columns: Dictionary = {}  # Vector2i -> true  (near lake/tarn, but not water)
var lake_center:  Vector2i  = Vector2i.ZERO
var tarn_center:  Vector2i  = Vector2i.ZERO
var tarn_waterline: int     = 0


var _gen_thread: Thread = null
var _stats_mutex: Mutex = null   # guards _map_phase_timings (written on the generator thread)
var _maps_ready: bool = false
var _generation_metrics: Dictionary = {}
var _domain_counts: Dictionary = {}
var _startup_started_msec: int = 0
var _maps_ready_msec: int = 0
var _map_precompute_msec: int = 0
var _map_phase_timings: Array[Dictionary] = []


func _init() -> void:
	block_fill.bind_layers()


func _ready() -> void:
	_stats_mutex = Mutex.new()
	_layout_profile = load_macro_layout_profile()
	print("WorldGenerator: ready.")


## Owning system loads static configuration before starting the worker thread.
## Also used by the offline seed-gallery test.
func load_macro_layout_profile() -> Dictionary:
	return JsonData.read_dict("res://data/world_gen/macro_layout.json")


## block_fill computes the bands (it reads them per block); the generator keeps
## its own copy for map building, so both always come from the same profile.
func _apply_shelf_bands() -> void:
	if not block_fill.apply_shelf_bands(_layout_profile.get("shelf_tops", [])): return # LayoutValidator.profile_errors reports it
	_lowland_shelf_max_y = block_fill.lowland_shelf_max_y;  _foothill_shelf_min_y = block_fill.foothill_shelf_min_y
	_foothill_shelf_max_y = block_fill.foothill_shelf_max_y;  _foothill_shelf_height = block_fill.foothill_shelf_height
	_mountain_min = block_fill.mountain_min;  _mountain_max = block_fill.mountain_max
	_mountain_shelf_height = block_fill.mountain_shelf_height


func load_cave_profile() -> Dictionary:
	return JsonData.read_dict("res://data/world_gen/caves.json")


var river_layout: Dictionary = {}
var water_profile: Dictionary = {}

func load_water_profile() -> Dictionary:
	return JsonData.read_dict("res://data/world_gen/water.json")

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
	block_fill.build_resource_cover_maps()
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
			var floor_id := block_fill.generate_block_id(x, span.x, z)
			if floor_id == block_fill.id_cave_soil: soil_count += 1
			boundary[Vector3i(x, span.x, z)] = true
			for dir: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var next := Vector2i(x, z) + dir
				if _cave_layout["columns"].has(next.x * WORLD_SIZE_Z + next.y): continue
				for y in range(span.x + 1, span.y + 1): boundary[Vector3i(next.x, y, next.y)] = true
		var ores := 0
		for cell: Vector3i in boundary:
			var block_id := block_fill.generate_block_id(cell.x, cell.y, cell.z)
			for window: Dictionary in block_fill.resource_focus_windows:
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


## The cave span Vector3i(floor_y, roof_y, cave_id) of a column index (x * WORLD_SIZE_Z + z), or (-1, -1, -1).
func get_cave_column(index: int) -> Vector3i:
	return _cave_layout["columns"].get(index, Vector3i(-1, -1, -1))


func get_cave_catalog() -> Array:
	return _cave_layout["systems"].duplicate(true) if _maps_ready else []


func get_cave_air_cells(cave_id: int) -> Array[Vector3i]:
	var cells: Array[Vector3i] = []
	if not _maps_ready or cave_id < 0 or cave_id >= _cave_layout["systems"].size(): return cells
	for index: int in _cave_layout["systems"][cave_id]["columns"]:
		var span: Vector3i = _cave_layout["columns"][index]
		for y in range(span.x + 1, span.y + 1): cells.append(Vector3i(index / WORLD_SIZE_Z, y, index % WORLD_SIZE_Z))
	return cells


## Called when the node leaves the tree - i.e. the game is stopping. JOIN the
## worker before the script's members are freed. Without this, stopping
## mid-generation crashes ("Bad address index" as heightmap is cleared under
## the running thread) and leaks the Thread ("destroyed without
## wait_to_finish()").
func _exit_tree() -> void:
	if _gen_thread != null and _gen_thread.is_started():
		_gen_thread.wait_to_finish()
		_gen_thread = null

# -- Deferred signal helpers (main-thread only) --------------------------------

func _deferred_emit_world_complete() -> void:
	print("WorldGenerator: world_complete signal firing.")
	world_complete.emit()

func _fail(reason: String) -> void:
	generation_error = reason
	push_error("WorldGenerator: generation failed: " + reason)
	generation_failed.emit(reason)

func _deferred_emit_maps_ready() -> void:
	print("WorldGenerator: terrain maps ready.")
	maps_ready.emit()

func _deferred_print_generation_metrics(snapshot: Dictionary) -> void:
	Metrics.print_report(snapshot)

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
		_fail("invalid layout profile: " + str(profile_errors))
		return

	# Clean up the thread object on the main thread once the world is done.
	world_complete.connect(_cleanup_thread, CONNECT_ONE_SHOT | CONNECT_DEFERRED)

	_gen_thread = Thread.new()
	_gen_thread.start(_generate_threaded)

## Stops any in-flight generation before the current scene is replaced by a
## loaded save. The next WorldRenderer starts a fresh deterministic run.
func prepare_for_world_reload() -> void:
	# Overview workers read the immutable generation maps across frames. Join
	# them before resetting those maps or replacing WorldData during save load.
	for renderer in get_tree().get_nodes_in_group("terrain_overview_renderer"):
		renderer.finish_pending_overview()
	if _gen_thread != null and _gen_thread.is_started():
		_gen_thread.wait_to_finish()
	_gen_thread = null
	_maps_ready = false
	_tile_ranges_ready = false

func _reset_generation_state() -> void:
	block_fill.resource_cover_maps.clear()
	_macro_layout.clear()
	_layout_validation.clear()
	water_bodies.clear()
	waterline_map.clear()
	_startup_started_msec = Time.get_ticks_msec()
	_maps_ready_msec = 0
	_map_precompute_msec = 0
	_map_phase_timings.clear()
	generation_error = ""
	_maps_ready = false
	_tile_ranges_ready = false
	_tile_min_visible_y.clear()
	_tile_max_visible_y.clear()
	_generation_metrics.clear()
	_cave_layout = {"systems": [], "columns": {}, "soil": {}}
	spring_cave = {}
	_domain_counts.clear()
	lake_columns.clear()
	tarn_columns.clear()
	water_bank_columns.clear()
	lake_center = Vector2i.ZERO
	tarn_center = Vector2i.ZERO
	tarn_waterline = 0

func _cleanup_thread() -> void:
	if _gen_thread != null:
		_gen_thread.wait_to_finish()
		_gen_thread = null


## True once the terrain maps are built and every map query is valid.
func is_maps_ready() -> bool:
	return _maps_ready


## True while the generator thread is still building the terrain maps.
func is_generating() -> bool:
	return not _maps_ready and _gen_thread != null and _gen_thread.is_started()


func get_streaming_stats() -> Dictionary:
	_stats_mutex.lock()
	var stats := {
		"maps_ready": _maps_ready,
		"startup_elapsed_ms": Time.get_ticks_msec() - _startup_started_msec if _startup_started_msec > 0 else 0,
		"map_precompute_ms": _map_precompute_msec,
		"map_phase_timings": _map_phase_timings.duplicate(true),
		"maps_ready_ms": _maps_ready_msec - _startup_started_msec if _maps_ready_msec > 0 and _startup_started_msec > 0 else 0,
	}
	_stats_mutex.unlock()
	return stats


func get_generation_metrics() -> Dictionary:
	return _generation_metrics.duplicate(true)


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

## Moisture at a column in [0,1] (doc 42, flora World placement). Combines the broad
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
	var dry := clampf(float(sy - _foothill_shelf_min_y)
		/ float(_mountain_max - _foothill_shelf_min_y), 0.0, 1.0)
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
	if waterline_map[wx * WORLD_SIZE_Z + wz] >= 0:
		return block_fill.id_water
	return block_fill.generate_block_id(wx, heightmap[wx * WORLD_SIZE_Z + wz], wz)

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
		"domain": Metrics.domain_label(domain_map[idx]),
		"domain_n": domain_n_map[idx],
		"moisture": get_moisture(wx, wz),
		"height_band": _height_band_label(surface_y),
		"surface_y": surface_y,
		"visible_surface_y": visible_y,
		"visible_block_id": visible_block_id,
		"visible_block_key": String(BlockRegistry.get_key(visible_block_id)),
		"is_lake": lake_columns.has(col),
		"is_tarn": tarn_columns.has(col),
		"is_water_bank": water_bank_columns.has(col),
}


func _height_band_label(surface_y: int) -> String:
	if surface_y >= LOWLAND_SHELF_MIN_Y and surface_y <= _lowland_shelf_max_y:
		return "lowland shelf"
	if surface_y >= _foothill_shelf_min_y and surface_y <= _foothill_shelf_max_y:
		var shelf := ((surface_y - _foothill_shelf_min_y) / _foothill_shelf_height) + 1
		return "foothill shelf %d" % shelf
	if surface_y >= _mountain_min and surface_y <= _mountain_max:
		var shelf := ((surface_y - _mountain_min) / _mountain_shelf_height) + 1
		return "mountain shelf %d" % shelf
	if surface_y < LOWLAND_SHELF_MIN_Y:
		return "lake basin"
	return "unassigned"


func get_generated_block_id(wx: int, wy: int, wz: int) -> int:
	if not _maps_ready:
		return BlockRegistry.AIR_ID
	if wx < 0 or wx >= WORLD_SIZE_X or wy < 0 or wy >= WORLD_SIZE_Y or wz < 0 or wz >= WORLD_SIZE_Z:
		return BlockRegistry.AIR_ID
	return block_fill.generate_block_id(wx, wy, wz)


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
	return block_fill.generate_block_id(wx, wy, wz, false)


## Construction uses existing natural stone, without caves, surface soil or
## resource veins. Above-ground blocks continue the same authored height bands.
func construction_stone_id(cell: Vector3i) -> int:
	var id := get_overview_strata_block_id(cell.x,cell.y,cell.z)
	if String(BlockRegistry.get_def(BlockRegistry.get_key(id)).get("kind","")) == "rock": return id
	return block_fill.fallback_rock_id(cell.y)


# -- ID cache (main thread) ----------------------------------------------------

func _cache_block_ids() -> void:
	_cave_profile = load_cave_profile()
	block_fill.cache_block_ids()


# -- Pipeline (background thread) ----------------------------------------------

func _generate_threaded() -> void:
	var t_start := Time.get_ticks_msec()
	var t_maps_start := t_start

	_run_timed_map_phase("noise_instances", Callable(self, "_build_noise_instances"))             # Phase 1
	_run_timed_map_phase("seeded_layout", Callable(self, "_build_seeded_maps"))
	if _macro_layout.is_empty():
		call_deferred("_fail", "layout generation failed")
		call_deferred("_deferred_emit_world_complete")
		return
	_run_timed_map_phase("edge_detail", Callable(self, "_apply_edge_detail"))
	_run_timed_map_phase("layout_validation", Callable(self, "_validate_finished_layout"))
	if not _layout_validation.get("errors", []).is_empty():
		call_deferred("_fail", "invalid finished terrain: " + str(_layout_validation["errors"]))
		call_deferred("_deferred_emit_world_complete")
		return
	_run_timed_map_phase("river", Callable(self, "_build_river"))
	_recount_domain_counts()
	_run_timed_map_phase("caves", Callable(self, "_build_cave_maps"))
	_maps_ready_msec = Time.get_ticks_msec()
	_map_precompute_msec = _maps_ready_msec - t_maps_start
	_maps_ready = true
	call_deferred("_deferred_emit_maps_ready")

	_run_timed_map_phase("tile_ranges", Callable(self, "_build_tile_visible_ranges"))

	_run_timed_map_phase("generation_metrics", Callable(self, "_build_generation_metrics"))
	call_deferred("_deferred_print_generation_metrics", _generation_metrics.duplicate(true))

	var elapsed := (Time.get_ticks_msec() - t_start) / 1000.0
	print("WorldGenerator: finished in %.1f s." % elapsed)
	call_deferred("_deferred_emit_world_complete")


func _run_timed_map_phase(label: String, fn: Callable) -> void:
	var t_phase_start := Time.get_ticks_msec()
	fn.call()
	var elapsed := Time.get_ticks_msec() - t_phase_start
	_stats_mutex.lock()
	_map_phase_timings.append({
		"name": label,
		"ms": elapsed,
	})
	_stats_mutex.unlock()


# -- Phase 1 - Noise instances -------------------------------------------------

func _build_noise_instances() -> void:
	# Metals use independent seeded fields; coal deliberately keeps a broad scale.
	# Settings were copied from BlockRegistry before the generation thread starts.
	block_fill.metal_noise.clear()
	for window: Dictionary in block_fill.metal_windows:
		var settings: Dictionary = window["noise_field"]
		var field := FastNoiseLite.new()
		field.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		field.seed = world_seed + int(settings["seed_offset"])
		field.frequency = float(settings["frequency"])
		field.fractal_octaves = int(settings["octaves"])
		block_fill.metal_noise.append(field)

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
	noise_gem.frequency        = 0.11
	noise_gem.fractal_octaves  = 3

	# Layer 8 - Moisture map (flora distribution, doc 42)
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
	var step := _mountain_shelf_height if rank >= 4 else _foothill_shelf_height
	var shelf_base := source_height - step + 1
	var offset_unit := 3 if rank >= 4 else 2
	var max_offset := step - 1
	var roll := _edge_detail_hash(x / 2, z / 2, rank * 31 + distance) % 3
	var offset := mini(max_offset, ((distance - 1) * offset_unit) + (roll * offset_unit))
	return clampi(source_height - offset, shelf_base, source_height)


func _macro_shelf_rank(height: int) -> int:
	if height <= _lowland_shelf_max_y:
		return 0
	if height < _mountain_min:
		var foothill_shelf := int(floor(float(height - _foothill_shelf_min_y) / float(_foothill_shelf_height)))
		return clampi(foothill_shelf + 1, 1, 3)
	var mountain_shelf := int(floor(float(height - _mountain_min) / float(_mountain_shelf_height)))
	return clampi(mountain_shelf + 4, 4, 9)


func _domain_for_macro_shelf_height(height: int) -> int:
	if height <= _lowland_shelf_max_y:
		return DOMAIN_LOWLAND
	if height < _mountain_min:
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


# -- Generation metrics (WorldGenerationMetrics) --------------------------------

func _build_generation_metrics() -> void:
	_generation_metrics = Metrics.build(self, _domain_counts, _layout_profile, _macro_layout, _layout_validation)


# -- Block fill (WorldBlockFill) -------------------------------------------------

## The live cave layout {systems, columns, soil}. Read-only for callers; the
## block fill reads it per block, so it is returned without a copy.
func cave_layout() -> Dictionary:
	return _cave_layout


## Burial is measured against the original exterior in every direction,
## including cliff faces. Mining edits cannot unlock rarer geology beside them.
func has_natural_cover(x: int, y: int, z: int, depth: int) -> bool:
	return block_fill.has_natural_cover(x, y, z, depth)
