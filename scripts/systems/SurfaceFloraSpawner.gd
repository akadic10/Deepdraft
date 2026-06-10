class_name SurfaceFloraSpawner
extends Node3D

## Surface flora placement — MIXED FOREST (pine, oak, apple, juniper).
##
## Scatters trees across the world by ECOLOGY: each species has an elevation +
## domain + moisture niche (see WorldGenerator.get_moisture). A single shared
## scatter grid holds at most one tree per cell; per cell every species is scored
## for suitability and one is chosen by a seeded weighted pick (or the cell is left
## open). This blends species across the moisture/elevation gradient and prevents
## overlapping trunks. Streams in/out with the camera like the terrain.
##
## Design + decisions: docs/00_dev_roadmap/14_flora_distribution_plan.md
##                     docs/00_dev_roadmap/13_flora_scatter_pine.md (pine first pass)
## Placement data:     data/entities/flora/<species>_tree.json -> "placement"
## Footprint / rules:  docs/40_economy_colony/42_farming_brewing.md (Surface Trees)
##
## OWNS its own data loading (the VisitorManager pattern — no separate registry
## autoload for flora). All FileAccess for flora JSON happens here.
##
## Determinism (Hard Rule 8): every decision is a pure function of
## WorldGenerator.world_seed + column XZ. No randi()/randf().

# ── Streaming geometry (mirror WorldData / WorldRenderer) ─────────────────────
const CHUNK_SIZE:    int = 16
const CHUNK_COUNT_X: int = 64
const CHUNK_COUNT_Z: int = 64

# ── Domain constants (must match WorldGenerator) ──────────────────────────────
const DOMAIN_LOWLAND:  int = 0
const DOMAIN_VALLEY:   int = 1   # foothill domain / valley corridor
const DOMAIN_MOUNTAIN: int = 2

# ── Tunables (exported so they can be adjusted in the editor) ─────────────────

## Flora definition JSON files. Each holds one "base:flora:*_tree" species block.
## A file without a "placement" block is skipped (assets exist but no niche yet).
@export var flora_json_paths: Array[String] = [
	"res://data/entities/flora/pine_tree.json",
	"res://data/entities/flora/oak_tree.json",
	"res://data/entities/flora/apple_tree.json",
	"res://data/entities/flora/juniper_tree.json",
]

## Shared scatter grid: one candidate tree per cell_size×cell_size block cell
## (bigger = sparser overall). This is the master density dial; per-species
## base_density (in each JSON) sets the relative mix within a cell.
@export_range(2, 64, 1) var scatter_cell_size: int = 14

## Cap on the chance a suitable cell holds a tree (summed species suitability is
## clamped to this). Keeps even the richest mixing zones from being 100% covered.
@export_range(0.0, 1.0, 0.01) var max_cell_occupancy: float = 0.9

## XZ chunk radius around the camera that spawns flora (only used when
## cover_whole_map is OFF). Match WorldRenderer's view_radius_chunks.
@export_range(1, 64, 1) var view_radius_chunks: int = 5

## Scale conversion. The live world renders 1 block = 1.0 Godot unit (doc 13 §5).
## Trees are authored 1:1 — 1 voxel = 1 block (the Stonehearth tree convention,
## doc 61) with .import root_scale = 1.0 (never edit .import). So instance_scale =
## godot_units_per_block / voxels_per_block = 1.0 / 1.0 = 1.0. Characters/items use
## 8 voxels/block via their own import scale.
@export var voxels_per_block: float = 1.0
@export var godot_units_per_block: float = 1.0

## Whole-map mode (default): scatter across the ENTIRE map once and keep it, so
## trees do not pop in/out or "follow" the overview camera. Columns are still
## spawned over several frames (spawn_budget_per_frame). Turn OFF to fall back to
## camera-radius streaming (view_radius_chunks) for a future close camera.
@export var cover_whole_map: bool = true

## Chunk-columns spawned per frame while filling in.
@export_range(1, 256, 1) var spawn_budget_per_frame: int = 24

## Mature/ancient trees get a StaticBody3D + box collider (dwarves path around
## them). With no agents yet, whole-map mode spawns thousands of bodies; turn off
## if physics cost is a problem until agents exist.
@export var enable_collision: bool = true

## Physics layer for mature/ancient tree colliders. MUST NOT include Layer 1: the
## RTS camera's SpringArm3D collides against Layer 1 (terrain only) to avoid
## clipping, so trees on Layer 1 yank the camera down on a quick pan. Layer 2
## keeps tree obstacles available for future dwarf pathing (see Camera.gd).
@export_flags_3d_physics var tree_collision_layer: int = 2

@export var debug_logging: bool = true

## Slice tool — placed flora hide above the active cut plane (11_slice_xray_plan.md
## Phase 5). Wire to the SliceController node; leave empty to disable slice culling.
@export var slice_controller_path: NodePath

# ── Loaded data ───────────────────────────────────────────────────────────────
## One entry per usable species: { key, name, placement, stages, domains }.
var _species: Array[Dictionary] = []

# ── Runtime state ─────────────────────────────────────────────────────────────
var _ready_to_spawn: bool = false
var _camera: Camera = null
var _camera_chunk: Vector2i = Vector2i(-9999, -9999)
var _season: String = "summer"

var _loaded_columns: Dictionary = {}    # Vector2i(cx,cz) -> Array[Node3D]
var _pending: Array[Vector2i] = []      # chunk-columns awaiting spawn
var _pending_set: Dictionary = {}       # Vector2i -> true (dedupe)

var _scene_cache: Dictionary = {}       # model path -> PackedScene
var _tree_material: Material = null
var _spawned_count: int = 0

const SLICE_OFF_Y: int = 127            # SliceController.MAX_SLICE_Y → slice off (all flora visible)
var _slice_controller: Node = null
var _slice_y: int = SLICE_OFF_Y         # active cut plane; trees with base_y > this are hidden


func _ready() -> void:
	_tree_material = _build_tree_material()
	if not _load_all_flora():
		push_error("SurfaceFloraSpawner: no usable flora definitions; disabled.")
		set_process(false)
		return

	# Arming is poll-based (see _process): the spawner needs the heightmap, domain
	# map and moisture noise, all valid once WorldGenerator reports maps_ready.
	if WorldClock.has_signal("season_changed"):
		WorldClock.season_changed.connect(_on_season_changed)
	_season = WorldClock.season

	_camera = _find_camera(get_tree().current_scene)

	# Slice culling: react to the Slice tool moving the cut plane.
	if not slice_controller_path.is_empty():
		_slice_controller = get_node_or_null(slice_controller_path)
		if _slice_controller != null and _slice_controller.has_signal("slice_changed"):
			_slice_controller.connect("slice_changed", _on_slice_changed)


func _arm() -> void:
	_ready_to_spawn = true
	_camera_chunk = Vector2i(-9999, -9999)   # force a full streaming pass
	if cover_whole_map:
		_enqueue_all_columns()
	if debug_logging:
		var names := []
		for sp in _species:
			names.append(sp["name"])
		print("SurfaceFloraSpawner: maps ready, scatter armed (seed=%d, species=%s, cell=%d, whole_map=%s, columns=%d)."
			% [WorldGenerator.world_seed, str(names), scatter_cell_size, str(cover_whole_map), _pending.size()])


## Queues every chunk-column, nearest-to-camera first so the looked-at area fills
## before the far corners. Used once in whole-map mode; never despawned.
func _enqueue_all_columns() -> void:
	var center := Vector2i(CHUNK_COUNT_X / 2, CHUNK_COUNT_Z / 2)
	if _camera != null:
		center = Vector2i(
			clampi(int(floor(_camera.global_position.x / CHUNK_SIZE)), 0, CHUNK_COUNT_X - 1),
			clampi(int(floor(_camera.global_position.z / CHUNK_SIZE)), 0, CHUNK_COUNT_Z - 1))
	var all: Array[Vector2i] = []
	for cx in range(CHUNK_COUNT_X):
		for cz in range(CHUNK_COUNT_Z):
			var key := Vector2i(cx, cz)
			if _loaded_columns.has(key) or _pending_set.has(key):
				continue
			all.append(key)
			_pending_set[key] = true
	all.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da: int = maxi(absi(a.x - center.x), absi(a.y - center.y))
		var db: int = maxi(absi(b.x - center.x), absi(b.y - center.y))
		return da < db)
	_pending.append_array(all)


# ── Frame loop: stream + drain spawn queue ────────────────────────────────────

func _process(_delta: float) -> void:
	if not _ready_to_spawn:
		if bool(WorldGenerator.get_streaming_stats().get("maps_ready", false)):
			_arm()
		else:
			return

	if not cover_whole_map:
		if _camera == null:
			_camera = _find_camera(get_tree().current_scene)
			if _camera == null:
				return
		_update_streaming_center()

	var budget := spawn_budget_per_frame
	while budget > 0 and not _pending.is_empty():
		var key: Vector2i = _pending.pop_front()
		_pending_set.erase(key)
		if not cover_whole_map and not _column_in_radius(key.x, key.y):
			continue
		_spawn_column(key.x, key.y)
		budget -= 1


func _update_streaming_center() -> void:
	var next_chunk := Vector2i(
		clampi(int(floor(_camera.global_position.x / CHUNK_SIZE)), 0, CHUNK_COUNT_X - 1),
		clampi(int(floor(_camera.global_position.z / CHUNK_SIZE)), 0, CHUNK_COUNT_Z - 1))
	if next_chunk == _camera_chunk:
		return
	_camera_chunk = next_chunk

	var to_free: Array[Vector2i] = []
	for key: Vector2i in _loaded_columns.keys():
		if not _column_in_radius(key.x, key.y):
			to_free.append(key)
	for key: Vector2i in to_free:
		_despawn_column(key)

	for dz in range(-view_radius_chunks, view_radius_chunks + 1):
		for dx in range(-view_radius_chunks, view_radius_chunks + 1):
			var cx := _camera_chunk.x + dx
			var cz := _camera_chunk.y + dz
			if cx < 0 or cx >= CHUNK_COUNT_X or cz < 0 or cz >= CHUNK_COUNT_Z:
				continue
			if not _column_in_radius(cx, cz):
				continue
			var key := Vector2i(cx, cz)
			if _loaded_columns.has(key) or _pending_set.has(key):
				continue
			_pending.append(key)
			_pending_set[key] = true


func _column_in_radius(cx: int, cz: int) -> bool:
	var dx := cx - _camera_chunk.x
	var dz := cz - _camera_chunk.y
	return dx * dx + dz * dz <= view_radius_chunks * view_radius_chunks


# ── Per-column scatter ────────────────────────────────────────────────────────

## Spawns every tree whose scatter cell is ANCHORED in this chunk column. A cell
## is owned by the single chunk that contains its origin corner, so cells
## straddling a chunk boundary spawn exactly once.
func _spawn_column(cx: int, cz: int) -> void:
	var nodes: Array[Node3D] = []
	var x0 := cx * CHUNK_SIZE
	var z0 := cz * CHUNK_SIZE
	var size := maxi(1, scatter_cell_size)

	var cell_x_lo := int(ceil(float(x0) / float(size)))
	var cell_x_hi := int(floor(float(x0 + CHUNK_SIZE - 1) / float(size)))
	var cell_z_lo := int(ceil(float(z0) / float(size)))
	var cell_z_hi := int(floor(float(z0 + CHUNK_SIZE - 1) / float(size)))

	for cell_x in range(cell_x_lo, cell_x_hi + 1):
		for cell_z in range(cell_z_lo, cell_z_hi + 1):
			var tree := _try_spawn_cell(cell_x, cell_z, size)
			if tree != null:
				nodes.append(tree)

	_loaded_columns[Vector2i(cx, cz)] = nodes


## Evaluates one scatter cell against ALL species; returns the spawned tree or null.
func _try_spawn_cell(cell_x: int, cell_z: int, size: int) -> Node3D:
	var h_pos := _hash(cell_x, cell_z, 101)          # jitter within cell
	var jx: int = h_pos % size
	var jz: int = (h_pos / size) % size
	var wx := cell_x * size + jx
	var wz := cell_z * size + jz

	if wx < 0 or wx >= CHUNK_COUNT_X * CHUNK_SIZE:
		return null
	if wz < 0 or wz >= CHUNK_COUNT_Z * CHUNK_SIZE:
		return null

	# Environment, read once.
	var domain := WorldGenerator.get_domain(wx, wz)
	var ground_y := WorldGenerator.get_surface_y(wx, wz)
	if ground_y < 0:
		return null
	var water := _is_water(wx, wz)
	var moisture := WorldGenerator.get_moisture(wx, wz)

	# Score every species; sum suitability.
	var total := 0.0
	var scores: Array[float] = []
	scores.resize(_species.size())
	for i in range(_species.size()):
		var s := _suitability(_species[i], domain, ground_y, moisture, water, wx, wz)
		scores[i] = s
		total += s
	if total <= 0.0:
		return null

	# Presence test (clamped so even rich cells leave some gaps).
	var presence := minf(total, max_cell_occupancy)
	if _unit(_hash(cell_x, cell_z, 202)) >= presence:
		return null

	# Weighted species pick.
	var r := _unit(_hash(cell_x, cell_z, 303)) * total
	var chosen := -1
	var acc := 0.0
	for i in range(scores.size()):
		acc += scores[i]
		if r < acc:
			chosen = i
			break
	if chosen < 0:
		return null
	var sp: Dictionary = _species[chosen]
	var placement: Dictionary = sp["placement"]
	var stages: Dictionary = sp["stages"]

	# Stage + footprint.
	var stage_name := _pick_stage(placement, _hash(cell_x, cell_z, 304))
	var stage_data: Dictionary = stages.get(stage_name, {})
	if stage_data.is_empty():
		return null
	var footprint: int = _footprint_for(placement, stage_name)

	# Flatness / validity and cliff-lip setback over the footprint.
	if not _footprint_ok(placement, wx, wz, footprint, ground_y):
		return null
	if not _edge_ok(placement, wx, wz, footprint, ground_y):
		return null

	var model_path := resolve_tree_model_for_season(
		stage_data, _season, Vector3i(wx, ground_y, wz))
	if model_path == "":
		return null

	return _instance_tree(sp["name"], model_path, stage_name, stage_data, wx, wz, ground_y, footprint)


## Per-species suitability weight for a column (0 = unsuitable). Gates on domain,
## elevation band, water and moisture niche; scaled by base_density, the treeline
## falloff (if any) and the grove mask (apple).
func _suitability(sp: Dictionary, domain: int, ground_y: int, moisture: float,
		water: bool, wx: int, wz: int) -> float:
	var pl: Dictionary = sp["placement"]
	if not (sp["domains"] as Dictionary).has(domain):
		return 0.0
	if water and bool(pl.get("exclude_water", true)):
		return 0.0
	if ground_y < int(pl.get("min_surface_y", 0)):
		return 0.0
	if ground_y > int(pl.get("max_surface_y", 100000)):
		return 0.0
	var mw := _moisture_weight(pl, moisture)
	if mw <= 0.0:
		return 0.0
	var fall := _falloff_factor(pl, ground_y)
	if fall <= 0.0:
		return 0.0
	var grove := _grove_weight(pl, wx, wz)
	if grove <= 0.0:
		return 0.0
	var base := float(pl.get("base_density", pl.get("spawn_chance", 0.4)))
	return base * mw * fall * grove


# ── Instancing ────────────────────────────────────────────────────────────────

func _instance_tree(species_name: String, model_path: String, stage_name: String,
		stage_data: Dictionary, wx: int, wz: int, ground_y: int, footprint: int) -> Node3D:
	var packed := _load_scene(model_path)
	if packed == null:
		return null

	var instance_scale := godot_units_per_block / maxf(voxels_per_block, 0.0001)
	# Trunk base sits on the TOP face of the surface block: y = ground_y + 1.
	# Centre the footprint on the trunk cell.
	var origin := Vector3(
		float(wx) + 0.5 * footprint,
		float(ground_y + 1),
		float(wz) + 0.5 * footprint)

	var is_clutter := (stage_name == "sapling") or not enable_collision
	var root: Node3D
	if is_clutter:
		root = Node3D.new()
	else:
		var body := StaticBody3D.new()
		body.collision_layer = tree_collision_layer
		body.collision_mask = 0
		root = body

	root.position = origin
	root.name = "%s_%s_%d_%d" % [species_name, stage_name, wx, wz]

	var visual := packed.instantiate() as Node3D
	if visual == null:
		root.free()
		push_error("SurfaceFloraSpawner: %s did not instance as Node3D" % model_path)
		return null
	visual.scale = Vector3.ONE * instance_scale
	_apply_material_recursive(visual)
	root.add_child(visual)

	if not is_clutter:
		var height := float(int(stage_data.get("clearance_height", footprint * 4))) \
			* godot_units_per_block
		var col := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(float(footprint), height, float(footprint))
		col.shape = box
		col.position = Vector3(0.0, height * 0.5, 0.0)
		root.add_child(col)

	# Slice culling: remember the base for later re-cull, and respect the current cut
	# plane immediately so trees streamed in while a slice is active spawn hidden.
	root.set_meta("base_y", ground_y)
	root.visible = ground_y <= _slice_y

	# Nav occupancy (doc 16 step 3a — dwarves walk around trees): mature/ancient
	# trunks register footprint × clearance_height with PlacedEntityRegistry.
	# Saplings (clutter) register nothing; canopy overhang carries no occupancy
	# (Hard Rule 5 spirit). Independent of enable_collision — occupancy is nav
	# data, the StaticBody3D is physics.
	if stage_name != "sapling":
		var occ_height := int(stage_data.get("clearance_height", footprint * 4))
		var occ_id := PlacedEntityRegistry.register_box(
			Vector3i(wx, ground_y + 1, wz),
			Vector3i(footprint, occ_height, footprint))
		root.set_meta("occupancy_id", occ_id)

	add_child(root)
	_spawned_count += 1
	return root


func _despawn_column(key: Vector2i) -> void:
	var nodes: Array = _loaded_columns.get(key, [])
	for n in nodes:
		if is_instance_valid(n):
			if n.has_meta("occupancy_id"):
				PlacedEntityRegistry.unregister(int(n.get_meta("occupancy_id")))
			_spawned_count -= 1
			n.queue_free()
	_loaded_columns.erase(key)


# ── Slice culling (11_slice_xray_plan.md Phase 5) ─────────────────────────────

## Hide trees whose base sits above the active cut plane. Coarse per-instance toggle:
## a tree straddling the plane shows whole (canopy may poke above) — acceptable v1; a
## per-prop clip plane would be the clean follow-up. slice_y = 127 (off) shows all.
func _on_slice_changed(new_slice_y: int) -> void:
	if new_slice_y == _slice_y:
		return
	_slice_y = new_slice_y
	for key in _loaded_columns:
		for n in _loaded_columns[key]:
			if is_instance_valid(n):
				n.visible = int(n.get_meta("base_y", 0)) <= _slice_y


# ── Canonical model variant resolution (the ONE resolution point, per doc 42) ─

## Resolves a season's model value (String or Array[String]) to one path, using a
## deterministic spatial hash so the same position always yields the same variant.
static func resolve_tree_model(models_value, world_pos: Vector3i) -> String:
	if models_value is String:
		return models_value
	if models_value is Array and not (models_value as Array).is_empty():
		var arr: Array = models_value
		var h: int = (world_pos.x * 73856093) ^ (world_pos.z * 19349663) ^ (world_pos.y * 83492791)
		return String(arr[abs(h) % arr.size()])
	push_error("resolve_tree_model: invalid models_value at %s" % str(world_pos))
	return ""


## Picks the model for a season with fallback: requested -> "summer" -> error.
static func resolve_tree_model_for_season(
		stage_data: Dictionary, season: String, world_pos: Vector3i) -> String:
	var models: Dictionary = stage_data.get("models", {})
	if season == "autumn" and stage_data.has("fruit_harvest") and models.has("autumn_fruiting"):
		return resolve_tree_model(models["autumn_fruiting"], world_pos)
	var value = models.get(season, models.get("summer", ""))
	if value is String and value == "":
		push_error("resolve_tree_model_for_season: no model for season '%s'" % season)
		return ""
	return resolve_tree_model(value, world_pos)


# ── Suitability helpers ───────────────────────────────────────────────────────

## Treeline / band falloff [0,1] by surface elevation. Species without
## full_density_max_y/falloff_max_y (only pine defines them) get a flat 1.0.
func _falloff_factor(pl: Dictionary, surface_y: int) -> float:
	if not pl.has("full_density_max_y"):
		return 1.0
	var full_max := int(pl.get("full_density_max_y", 75))
	var fall_max := int(pl.get("falloff_max_y", 90))
	if surface_y <= full_max:
		return 1.0
	if surface_y >= fall_max or fall_max <= full_max:
		return 0.0
	return 1.0 - float(surface_y - full_max) / float(fall_max - full_max)


## Moisture niche weight [0,1]: 1.0 inside [moisture_min, moisture_max], tapering
## to 0 over moisture_margin outside. Absent keys = no moisture preference (1.0).
func _moisture_weight(pl: Dictionary, m: float) -> float:
	var mmin := float(pl.get("moisture_min", 0.0))
	var mmax := float(pl.get("moisture_max", 1.0))
	var margin := float(pl.get("moisture_margin", 0.15))
	if m >= mmin and m <= mmax:
		return 1.0
	if margin <= 0.0:
		return 0.0
	if m < mmin:
		return maxf(0.0, 1.0 - (mmin - m) / margin)
	return maxf(0.0, 1.0 - (m - mmax) / margin)


## Grove clustering (apple). Returns 1.0 inside a grove cell, else 0.0. A grove
## cell is a coarse cell_size×cell_size block region selected by a hashed
## threshold, so wild apples cluster into orchards instead of even scatter.
func _grove_weight(pl: Dictionary, wx: int, wz: int) -> float:
	var g: Dictionary = pl.get("grove", {})
	if g.is_empty() or not bool(g.get("enabled", false)):
		return 1.0
	var cs := maxi(1, int(g.get("cell_size", 28)))
	var thr := float(g.get("threshold", 0.4))
	var gx := int(floor(float(wx) / float(cs)))
	var gz := int(floor(float(wz) / float(cs)))
	return 1.0 if _unit(_hash(gx, gz, 909)) < thr else 0.0


func _pick_stage(pl: Dictionary, h: int) -> String:
	var weights: Dictionary = pl.get("stage_weights", {})
	var total := 0.0
	for k in weights.keys():
		total += float(weights[k])
	if total <= 0.0:
		return "mature"
	var r := _unit(h) * total
	var acc := 0.0
	for k in ["sapling", "mature", "ancient"]:
		acc += float(weights.get(k, 0.0))
		if r < acc:
			return k
	return "mature"


func _footprint_for(pl: Dictionary, stage_name: String) -> int:
	var fp: Dictionary = pl.get("footprint", {})
	return int(fp.get(stage_name, 1))


## True if the footprint columns are solid ground, dry, and flat enough.
func _footprint_ok(pl: Dictionary, wx: int, wz: int, footprint: int, ground_y: int) -> bool:
	var max_slope := int(pl.get("max_surface_slope", 1))
	var min_y := int(pl.get("min_surface_y", 0))
	var excl_water := bool(pl.get("exclude_water", true))
	for ddx in range(footprint):
		for ddz in range(footprint):
			var sx := wx + ddx
			var sz := wz + ddz
			var sy := WorldGenerator.get_surface_y(sx, sz)
			if sy < min_y:
				return false
			if absi(sy - ground_y) > max_slope:
				return false
			if excl_water and _is_water(sx, sz):
				return false
	return true


## Keeps trees set back from drops. Scans a ring `edge_margin` blocks wide around
## the footprint and rejects if any ring column is off-world (void) or drops more
## than `edge_dropoff_max` below the trunk. edge_margin <= 0 disables the check.
func _edge_ok(pl: Dictionary, wx: int, wz: int, footprint: int, ground_y: int) -> bool:
	var margin := int(pl.get("edge_margin", 1))
	if margin <= 0:
		return true
	var dropoff_max := int(pl.get("edge_dropoff_max", 3))
	var x_lo := wx - margin
	var x_hi := wx + footprint - 1 + margin
	var z_lo := wz - margin
	var z_hi := wz + footprint - 1 + margin
	for sx in range(x_lo, x_hi + 1):
		for sz in range(z_lo, z_hi + 1):
			var on_ring := sx < wx or sx > wx + footprint - 1 \
				or sz < wz or sz > wz + footprint - 1
			if not on_ring:
				continue
			var sy := WorldGenerator.get_surface_y(sx, sz)
			if sy < 0:
				return false
			if ground_y - sy > dropoff_max:
				return false
	return true


func _is_water(wx: int, wz: int) -> bool:
	var c := Vector2i(wx, wz)
	return WorldGenerator.lake_columns.has(c) \
		or WorldGenerator.tarn_columns.has(c) \
		or WorldGenerator.water_bank_columns.has(c)


## Deterministic positive 31-bit hash of (x, z, salt) folded with the world seed.
func _hash(x: int, z: int, salt: int) -> int:
	var h: int = WorldGenerator.world_seed * 2654435761 + 0x9E3779B9
	h ^= x * 73856093
	h ^= z * 19349663
	h ^= salt * 83492791
	h ^= (h >> 13)
	h *= 1274126177
	h ^= (h >> 16)
	return h & 0x7FFFFFFF


func _unit(h: int) -> float:
	return float(h) / 2147483647.0


func _load_scene(path: String) -> PackedScene:
	if _scene_cache.has(path):
		return _scene_cache[path]
	if not ResourceLoader.exists(path):
		push_error("SurfaceFloraSpawner: model not found: %s" % path)
		_scene_cache[path] = null
		return null
	var packed := load(path) as PackedScene
	_scene_cache[path] = packed
	return packed


func _apply_material_recursive(node: Node) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = _tree_material
	for child in node.get_children():
		_apply_material_recursive(child)


## Mirrors WorldRenderer._create_material(): vertex colour as albedo, DOUBLE-SIDED
## (CULL_DISABLED) so the sparse canopy shell shows no see-through back faces, and
## LIT (PER_PIXEL) so the voxel facets read as 3D under the sun.
func _build_tree_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness    = 1.0
	mat.metallic     = 0.0
	mat.cull_mode    = BaseMaterial3D.CULL_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	return mat


func _on_season_changed(new_season: String) -> void:
	if new_season == _season:
		return
	var old_season := _season
	_season = new_season
	if not _ready_to_spawn:
		return
	# Skip the rebuild only if EVERY species resolves the old and new season to the
	# same model set (e.g. evergreens map spring/summer/autumn all to "summer").
	var changed := false
	for sp in _species:
		var stages: Dictionary = sp["stages"]
		if _effective_season_for(stages, old_season) != _effective_season_for(stages, new_season):
			changed = true
			break
	if not changed:
		return
	for key: Vector2i in _loaded_columns.keys():
		_despawn_column(key)
	_pending.clear()
	_pending_set.clear()
	if cover_whole_map:
		_enqueue_all_columns()
	else:
		_camera_chunk = Vector2i(-9999, -9999)


## Resolves a season to the model key it actually uses, per the summer fallback,
## using the "mature" stage as reference (all stages share the same season keys).
func _effective_season_for(stages: Dictionary, season: String) -> String:
	var ref: Dictionary = stages.get("mature", {})
	var models: Dictionary = ref.get("models", {})
	if season == "autumn" and ref.has("fruit_harvest") and models.has("autumn_fruiting"):
		return "autumn_fruiting"
	if models.has(season):
		return season
	return "summer"


func _find_camera(node: Node) -> Camera:
	if node is Camera:
		return node as Camera
	if node == null:
		return null
	for child: Node in node.get_children():
		var found := _find_camera(child)
		if found != null:
			return found
	return null


# ── Data loading (registry pattern — this system owns its flora JSON) ─────────

## Loads every flora JSON; keeps species that have both a "placement" and "stages"
## block. Files without placement (assets exist but no niche yet) are skipped.
func _load_all_flora() -> bool:
	_species.clear()
	for path in flora_json_paths:
		if not FileAccess.file_exists(path):
			push_warning("SurfaceFloraSpawner: missing %s (skipped)" % path)
			continue
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			push_warning("SurfaceFloraSpawner: cannot open %s (skipped)" % path)
			continue
		var parsed = JSON.parse_string(f.get_as_text())
		f.close()
		if typeof(parsed) != TYPE_DICTIONARY:
			push_warning("SurfaceFloraSpawner: malformed JSON %s (skipped)" % path)
			continue
		var key := _species_key(parsed)
		if key == "":
			push_warning("SurfaceFloraSpawner: no 'base:flora:*' key in %s (skipped)" % path)
			continue
		var def: Dictionary = parsed[key]
		var placement: Dictionary = def.get("placement", {})
		var stages: Dictionary = def.get("stages", {})
		if placement.is_empty() or stages.is_empty():
			if debug_logging:
				print("SurfaceFloraSpawner: %s has no placement yet (skipped)." % key)
			continue
		_species.append({
			"key": key,
			"name": _short_name(key),
			"placement": placement,
			"stages": stages,
			"domains": _domains_dict(placement.get("domains", [])),
		})
	return not _species.is_empty()


func _species_key(parsed: Dictionary) -> String:
	for k in parsed.keys():
		var s := String(k)
		if s.begins_with("base:flora:"):
			return s
	return ""


## "base:flora:pine_tree" -> "pine"
func _short_name(key: String) -> String:
	var tail := key.get_slice(":", 2)        # "pine_tree"
	return tail.replace("_tree", "")


func _domains_dict(domain_names: Array) -> Dictionary:
	var d: Dictionary = {}
	for dom_name in domain_names:
		match String(dom_name):
			"lowland":            d[DOMAIN_LOWLAND] = true
			"valley", "foothill": d[DOMAIN_VALLEY] = true
			"mountain":           d[DOMAIN_MOUNTAIN] = true
	return d


# ── Debug ─────────────────────────────────────────────────────────────────────

func get_spawn_stats() -> Dictionary:
	return {
		"spawned": _spawned_count,
		"species": _species.size(),
		"loaded_columns": _loaded_columns.size(),
		"pending_columns": _pending.size(),
		"season": _season,
	}
