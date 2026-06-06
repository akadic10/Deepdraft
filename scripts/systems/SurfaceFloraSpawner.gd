class_name SurfaceFloraSpawner
extends Node3D

## Surface flora placement — first pass: PINE only, extensible to other species.
##
## Scatters pine trees across the world BY ELEVATION (foothills + mountain slopes,
## never the lowland shelf), streaming them in and out with the camera the same
## way WorldRenderer streams terrain. This is the project's first system that
## spawns placed GLB entities into the live scene.
##
## Design + decisions: docs/00_dev_roadmap/13_flora_scatter_pine.md
## Placement data:      data/entities/flora/pine_tree.json -> "placement"
## Footprint / rules:   docs/40_economy_colony/42_farming_brewing.md (Surface Trees)
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

const PINE_KEY: String = "base:flora:pine_tree"

# ── Tunables (exported so they can be adjusted in the editor) ─────────────────

## Flora definition JSON. First pass loads pine only; extend to a folder later.
@export var pine_json_path: String = "res://data/entities/flora/pine_tree.json"

## XZ chunk radius around the camera that spawns flora. Match WorldRenderer's
## view_radius_chunks (default 5) so trees and terrain stream together.
@export_range(1, 64, 1) var view_radius_chunks: int = 5

## Scale conversion. The live world renders 1 block = 1.0 Godot unit (see doc 13
## §5). GLBs are authored at 8 MagicaVoxel voxels per block with .import
## root_scale = 1.0 (which must never be edited). So instances are scaled here by
## godot_units_per_block / voxels_per_block = 1.0 / 8.0 = 0.125. THIS is the
## number most likely to need an in-engine nudge.
@export var voxels_per_block: float = 8.0
@export var godot_units_per_block: float = 1.0

## Whole-map mode (default): scatter pine across the ENTIRE map once and keep it,
## so trees do not pop in/out or "follow" the overview camera. The columns are
## still spawned over several frames (spawn_budget_per_frame) so there is no big
## one-frame hitch, and nothing is despawned. Turn this OFF to fall back to
## camera-radius streaming (view_radius_chunks) for a future first-person/close
## camera where only nearby trees need to exist.
@export var cover_whole_map: bool = true

## Chunk-columns spawned per frame while filling in. Whole-map mode has ~4096
## columns to cover, so this is higher than a pure streaming radius would need.
@export_range(1, 256, 1) var spawn_budget_per_frame: int = 24

## Mature/ancient trees get a StaticBody3D + box collider (dwarves path around
## them). With no agents in the world yet, whole-map mode spawns thousands of
## bodies; turn this off if physics cost is a problem until agents exist.
@export var enable_collision: bool = true

## Physics layer for mature/ancient tree colliders. MUST NOT include Layer 1:
## the RTS camera's SpringArm3D collides against Layer 1 (terrain only) to avoid
## clipping, so trees on Layer 1 yank the camera down onto a tree on a quick pan.
## Layer 2 keeps tree obstacles available for future dwarf pathing without
## touching the camera (same principle as dwarves/items — see Camera.gd).
@export_flags_3d_physics var tree_collision_layer: int = 2

@export var debug_logging: bool = true

# ── Loaded data ───────────────────────────────────────────────────────────────
var _pine_def: Dictionary = {}          # the PINE_KEY block
var _placement: Dictionary = {}         # _pine_def["placement"]
var _stages: Dictionary = {}            # _pine_def["stages"]
var _allowed_domains: Dictionary = {}   # int domain -> true

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


func _ready() -> void:
	_tree_material = _build_tree_material()
	if not _load_pine_definition():
		push_error("SurfaceFloraSpawner: failed to load pine definition; disabled.")
		set_process(false)
		return

	# Arming is poll-based (see _process): the spawner only needs the heightmap
	# and domain_map, both valid once WorldGenerator reports maps_ready. Polling
	# avoids any node-_ready ordering race with the renderer that kicks off the
	# (threaded, deferred) generation.
	if WorldClock.has_signal("season_changed"):
		WorldClock.season_changed.connect(_on_season_changed)
	_season = WorldClock.season

	_camera = _find_camera(get_tree().current_scene)


func _arm() -> void:
	_ready_to_spawn = true
	_camera_chunk = Vector2i(-9999, -9999)   # force a full streaming pass
	if cover_whole_map:
		_enqueue_all_columns()
	if debug_logging:
		print("SurfaceFloraSpawner: maps ready, pine scatter armed (seed=%d, whole_map=%s, columns_queued=%d)."
			% [WorldGenerator.world_seed, str(cover_whole_map), _pending.size()])


## Queues every chunk-column in the world, ordered nearest-to-camera first so the
## area the player is looking at fills in before the far corners. Used once in
## whole-map mode; columns are then drained by the per-frame budget and never
## despawned.
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
	# Nearest-to-camera first (Chebyshev distance is fine for fill order).
	all.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da: int = maxi(absi(a.x - center.x), absi(a.y - center.y))
		var db: int = maxi(absi(b.x - center.x), absi(b.y - center.y))
		return da < db)
	_pending.append_array(all)


# ── Frame loop: stream + drain spawn queue ────────────────────────────────────

func _process(_delta: float) -> void:
	if not _ready_to_spawn:
		# Poll WorldGenerator until its terrain maps (height + domain) are built.
		if bool(WorldGenerator.get_streaming_stats().get("maps_ready", false)):
			_arm()
		else:
			return

	# Camera-radius streaming is only used when NOT covering the whole map. In
	# whole-map mode the full column list was queued once at arm time.
	if not cover_whole_map:
		if _camera == null:
			_camera = _find_camera(get_tree().current_scene)
			if _camera == null:
				return
		_update_streaming_center()

	# Drain a bounded number of pending columns this frame.
	var budget := spawn_budget_per_frame
	while budget > 0 and not _pending.is_empty():
		var key: Vector2i = _pending.pop_front()
		_pending_set.erase(key)
		if not cover_whole_map and not _column_in_radius(key.x, key.y):
			continue   # camera moved away before we got to it
		_spawn_column(key.x, key.y)
		budget -= 1


func _update_streaming_center() -> void:
	var next_chunk := Vector2i(
		clampi(int(floor(_camera.global_position.x / CHUNK_SIZE)), 0, CHUNK_COUNT_X - 1),
		clampi(int(floor(_camera.global_position.z / CHUNK_SIZE)), 0, CHUNK_COUNT_Z - 1))
	if next_chunk == _camera_chunk:
		return
	_camera_chunk = next_chunk

	# Despawn columns that fell out of radius.
	var to_free: Array[Vector2i] = []
	for key: Vector2i in _loaded_columns.keys():
		if not _column_in_radius(key.x, key.y):
			to_free.append(key)
	for key: Vector2i in to_free:
		_despawn_column(key)

	# Enqueue newly-visible columns not already loaded or pending.
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

## Spawns every pine whose scatter cell is ANCHORED in this chunk column. A cell
## is owned by the single chunk that contains its origin corner (cell_x*size,
## cell_z*size), so cells straddling a chunk boundary spawn exactly once.
func _spawn_column(cx: int, cz: int) -> void:
	var nodes: Array[Node3D] = []
	var x0 := cx * CHUNK_SIZE
	var z0 := cz * CHUNK_SIZE
	var size: int = int(_placement.get("scatter_cell_size", 5))
	if size < 1:
		size = 1

	# Cells whose origin block lies within [x0 .. x0+15].
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


## Evaluates one scatter cell; returns the spawned tree root or null.
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

	# Domain + water gate.
	var domain := WorldGenerator.get_domain(wx, wz)
	if not _allowed_domains.has(domain):
		return null
	if bool(_placement.get("exclude_water", true)) and _is_water(wx, wz):
		return null

	var ground_y := WorldGenerator.get_surface_y(wx, wz)
	if ground_y < int(_placement.get("min_surface_y", 20)):
		return null

	# Treeline falloff factor [0,1] by surface elevation.
	var falloff := _falloff_factor(ground_y)
	if falloff <= 0.0:
		return null

	# Presence test.
	var spawn_chance := float(_placement.get("spawn_chance", 0.55)) * falloff
	if _unit(_hash(cell_x, cell_z, 202)) >= spawn_chance:
		return null

	# Stage + footprint.
	var stage_name := _pick_stage(_hash(cell_x, cell_z, 303))
	var stage_data: Dictionary = _stages.get(stage_name, {})
	if stage_data.is_empty():
		return null
	var footprint: int = int(_footprint_for(stage_name))

	# Flatness / validity over the footprint.
	if not _footprint_ok(wx, wz, footprint, ground_y):
		return null

	# Edge setback: keep trees back from cliff lips and the world border so the
	# canopy (wider than the footprint) does not overhang a drop or the void.
	if not _edge_ok(wx, wz, footprint, ground_y):
		return null

	# Resolve the model for the current season (pine = summer/winter only).
	var model_path := resolve_tree_model_for_season(
		stage_data, _season, Vector3i(wx, ground_y, wz))
	if model_path == "":
		return null

	return _instance_tree(model_path, stage_name, stage_data, wx, wz, ground_y, footprint)


# ── Instancing ────────────────────────────────────────────────────────────────

func _instance_tree(
		model_path: String, stage_name: String, stage_data: Dictionary,
		wx: int, wz: int, ground_y: int, footprint: int) -> Node3D:
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

	# Saplings are "clutter": no collision (Hard Rule 5). Mature/ancient get a
	# StaticBody3D root with a box collider so future dwarves path around them
	# (unless collision is globally disabled for perf while there are no agents).
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
	root.name = "pine_%s_%d_%d" % [stage_name, wx, wz]

	# Visual GLB instance, scaled. Collider (added below) is a sibling of this
	# under the root, so it is NOT affected by the visual's scale. GLB scene
	# roots are Node3D; bail defensively if a model imports as something else.
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
		col.position = Vector3(0.0, height * 0.5, 0.0)   # box stands from the ground up
		root.add_child(col)

	add_child(root)
	_spawned_count += 1
	return root


func _despawn_column(key: Vector2i) -> void:
	var nodes: Array = _loaded_columns.get(key, [])
	for n in nodes:
		if is_instance_valid(n):
			_spawned_count -= 1
			n.queue_free()
	_loaded_columns.erase(key)


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
	var value = models.get(season, models.get("summer", ""))
	if value is String and value == "":
		push_error("resolve_tree_model_for_season: no model for season '%s'" % season)
		return ""
	return resolve_tree_model(value, world_pos)


# ── Helpers ───────────────────────────────────────────────────────────────────

func _falloff_factor(surface_y: int) -> float:
	var full_max := int(_placement.get("full_density_max_y", 75))
	var fall_max := int(_placement.get("falloff_max_y", 90))
	if surface_y <= full_max:
		return 1.0
	if surface_y >= fall_max or fall_max <= full_max:
		return 0.0
	return 1.0 - float(surface_y - full_max) / float(fall_max - full_max)


func _pick_stage(h: int) -> String:
	var weights: Dictionary = _placement.get("stage_weights", {})
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


func _footprint_for(stage_name: String) -> int:
	var fp: Dictionary = _placement.get("footprint", {})
	return int(fp.get(stage_name, 1))


## True if the footprint columns are solid ground, dry, and flat enough.
func _footprint_ok(wx: int, wz: int, footprint: int, ground_y: int) -> bool:
	var max_slope := int(_placement.get("max_surface_slope", 1))
	var min_y := int(_placement.get("min_surface_y", 20))
	for ddx in range(footprint):
		for ddz in range(footprint):
			var sx := wx + ddx
			var sz := wz + ddz
			var sy := WorldGenerator.get_surface_y(sx, sz)
			if sy < min_y:
				return false
			if absi(sy - ground_y) > max_slope:
				return false
			if bool(_placement.get("exclude_water", true)) and _is_water(sx, sz):
				return false
	return true


## Keeps trees set back from drops. Scans a ring `edge_margin` blocks wide around
## the footprint and rejects the tree if any ring column is off-world (void) or
## drops more than `edge_dropoff_max` below the trunk — i.e. the tree sits on a
## cliff lip / world border where its wider canopy would overhang empty space.
## edge_margin <= 0 disables the check.
func _edge_ok(wx: int, wz: int, footprint: int, ground_y: int) -> bool:
	var margin := int(_placement.get("edge_margin", 1))
	if margin <= 0:
		return true
	var dropoff_max := int(_placement.get("edge_dropoff_max", 3))
	var x_lo := wx - margin
	var x_hi := wx + footprint - 1 + margin
	var z_lo := wz - margin
	var z_hi := wz + footprint - 1 + margin
	for sx in range(x_lo, x_hi + 1):
		for sz in range(z_lo, z_hi + 1):
			# Only the perimeter ring matters; the interior is the footprint.
			var on_ring := sx < wx or sx > wx + footprint - 1 \
				or sz < wz or sz > wz + footprint - 1
			if not on_ring:
				continue
			var sy := WorldGenerator.get_surface_y(sx, sz)
			if sy < 0:
				return false                      # off-world / void beside the tree
			if ground_y - sy > dropoff_max:
				return false                      # a real drop the canopy would overhang
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


## Mirrors WorldRenderer._create_material() so trees render like the terrain:
## vertex colour as albedo, DOUBLE-SIDED (CULL_DISABLED) so the thin/sparse
## canopy shell never shows see-through "missing" back faces, and LIT
## (PER_PIXEL) so the voxel facets read as 3D under the sun instead of a flat
## blob. (The old unshaded/cull_back spec in 61_voxel_art_guide.md predates the
## lit, double-sided terrain material and is being reconciled to this.)
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
	# Skip the rebuild when the new season resolves to the SAME models as the old
	# one — pine uses its "summer" model for spring/summer/autumn, so those
	# transitions need no change. Avoids a pointless map-wide despawn/respawn
	# flicker; pine then only rebuilds entering/leaving winter.
	if _effective_season(old_season) == _effective_season(new_season):
		return
	# Re-resolve every tree for the new season. Tear everything down, then re-queue
	# the SAME coverage we started with — whole-map re-queues the whole map, not
	# just the camera radius, otherwise only a patch around the camera respawns.
	for key: Vector2i in _loaded_columns.keys():
		_despawn_column(key)
	_pending.clear()
	_pending_set.clear()
	if cover_whole_map:
		_enqueue_all_columns()
	else:
		_camera_chunk = Vector2i(-9999, -9999)   # force a streaming recompute next frame


## Resolves a season to the model key it actually uses, per the summer fallback.
## Pine defines only summer/winter, so spring/summer/autumn all map to "summer".
## Uses the "mature" stage as reference (all stages share the same season keys).
## NOTE: pine-only today; a multi-species spawner must check this per species.
func _effective_season(season: String) -> String:
	var ref: Dictionary = _stages.get("mature", {})
	var models: Dictionary = ref.get("models", {})
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

func _load_pine_definition() -> bool:
	if not FileAccess.file_exists(pine_json_path):
		push_error("SurfaceFloraSpawner: missing %s" % pine_json_path)
		return false
	var f := FileAccess.open(pine_json_path, FileAccess.READ)
	if f == null:
		push_error("SurfaceFloraSpawner: cannot open %s" % pine_json_path)
		return false
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has(PINE_KEY):
		push_error("SurfaceFloraSpawner: malformed pine JSON (missing '%s')" % PINE_KEY)
		return false

	_pine_def = parsed[PINE_KEY]
	_placement = _pine_def.get("placement", {})
	_stages = _pine_def.get("stages", {})
	if _placement.is_empty() or _stages.is_empty():
		push_error("SurfaceFloraSpawner: pine def missing 'placement' or 'stages'.")
		return false

	# Map domain names -> WorldGenerator domain ints.
	_allowed_domains.clear()
	for dom_name in _placement.get("domains", []):
		match String(dom_name):
			"lowland":            _allowed_domains[DOMAIN_LOWLAND] = true
			"valley", "foothill": _allowed_domains[DOMAIN_VALLEY] = true
			"mountain":           _allowed_domains[DOMAIN_MOUNTAIN] = true
	return true


# ── Debug ─────────────────────────────────────────────────────────────────────

func get_spawn_stats() -> Dictionary:
	return {
		"spawned": _spawned_count,
		"loaded_columns": _loaded_columns.size(),
		"pending_columns": _pending.size(),
		"season": _season,
	}
