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

const Picking = preload("res://scripts/components/ObjectPicking.gd")
var _picking := Picking.new()
## Stable world-position identities survive seasonal visual replacement. Records
## are presentation metadata; felling/growth state will belong to the flora system.
var _trees: Dictionary = {}  # Vector2i(wx, wz) -> {name, stage, cell, node, bounds}
var _flight_tree_reach := 32.0 # Conservative initial canopy broad-phase radius.
const FellingSource = preload("res://scripts/components/TreeFellingComponent.gd")
var _tree_changes: Dictionary = {} # Vector2i -> authoritative, saveable forestry delta
var _felling_sources: Dictionary = {} # Vector2i -> TreeFellingComponent
var _source_trees: Dictionary = {} # source id -> Vector2i
var _felling_markers: Dictionary = {} # Vector2i -> Label (projected UI, never a pick target)
var _felling_marker_layer: CanvasLayer
signal tree_felling_changed(tree_id: Vector2i)

const SLICE_OFF_Y: int = 127            # SliceController.MAX_SLICE_Y → slice off (all flora visible)
var _slice_controller: Node = null
var _slice_y: int = SLICE_OFF_Y         # active cut plane; trees with base_y > this are hidden


func _ready() -> void:
	add_to_group("object_explorer_provider")
	add_to_group("surface_flora")
	add_to_group(SaveManager.OWNER_GROUP)
	_felling_marker_layer = CanvasLayer.new()
	_felling_marker_layer.layer = 19 # Below dock/windows; visible with the Chop tool off.
	add_child(_felling_marker_layer)
	TaskManager.task_released.connect(_on_felling_released)
	TaskManager.task_completed.connect(_on_felling_task_gone)
	TaskManager.task_cancelled.connect(_on_felling_task_gone)
	TaskManager.task_failed.connect(func(task: Task, _reason: String) -> void: _on_felling_task_gone(task))
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
	var center := Vector2i(CHUNK_COUNT_X >> 1, CHUNK_COUNT_Z >> 1)
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
	_update_felling_marker_positions()
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


## Shared immutable candidate query. Detail placement uses exactly the same
## tree selector as spawning, including cells on the other side of a chunk.
func generated_tree_candidate(cell_x: int, cell_z: int, size: int) -> Dictionary:
	var h_pos := _hash(cell_x, cell_z, 101)          # jitter within cell
	var jx: int = h_pos % size
	var jz: int = floori(float(h_pos) / float(size)) % size
	var wx := cell_x * size + jx
	var wz := cell_z * size + jz

	if wx < 0 or wx >= CHUNK_COUNT_X * CHUNK_SIZE:
		return {}
	if wz < 0 or wz >= CHUNK_COUNT_Z * CHUNK_SIZE:
		return {}

	# Environment, read once.
	var domain := WorldGenerator.get_domain(wx, wz)
	var ground_y := WorldGenerator.get_surface_y(wx, wz)
	if ground_y < 0:
		return {}
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
		return {}

	# Presence test (clamped so even rich cells leave some gaps).
	var presence := minf(total, max_cell_occupancy)
	if _unit(_hash(cell_x, cell_z, 202)) >= presence:
		return {}

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
		return {}
	var sp: Dictionary = _species[chosen]
	var placement: Dictionary = sp["placement"]
	var stages: Dictionary = sp["stages"]

	# Stage + footprint.
	var stage_name := _pick_stage(placement, _hash(cell_x, cell_z, 304))
	var stage_data: Dictionary = stages.get(stage_name, {})
	if stage_data.is_empty():
		return {}
	var footprint: int = _footprint_for(placement, stage_name)

	# Flatness / validity and cliff-lip setback over the footprint.
	if not _footprint_ok(placement, wx, wz, footprint, ground_y):
		return {}
	if not _edge_ok(placement, wx, wz, footprint, ground_y):
		return {}

	return {"species": sp, "stage": stage_name, "stage_data": stage_data,
		"origin": Vector3i(wx, ground_y, wz), "footprint": footprint}


func _try_spawn_cell(cell_x: int, cell_z: int, size: int) -> Node3D:
	var candidate := generated_tree_candidate(cell_x, cell_z, size)
	if candidate.is_empty():
		return null
	var origin: Vector3i = candidate.origin
	var path := resolve_tree_model_for_season(candidate.stage_data, _season, origin)
	if path.is_empty():
		return null
	return _instance_tree(candidate.species.name, path, candidate.stage,
		candidate.stage_data, origin.x, origin.z, origin.y, candidate.footprint)


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
	var tree_id := Vector2i(wx, wz)
	if bool(_tree_changes.get(tree_id, {}).get("felled", false)):
		return null
	model_path = resolve_tree_model_for_season(stage_data, _season, Vector3i(wx, ground_y, wz),
		String(_tree_changes.get(tree_id, {}).get("harvested_cycle", "")) == _fruit_cycle())
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
		var occ_id := int(_trees.get(tree_id, {}).get("occupancy_id", -1))
		if occ_id < 0:
			occ_id = PlacedEntityRegistry.register_box(
				Vector3i(wx, ground_y + 1, wz),
				Vector3i(footprint, occ_height, footprint))
		root.set_meta("occupancy_id", occ_id)

	add_child(root)
	root.set_meta("tree_id", tree_id)
	_trees[tree_id] = {"name": species_name, "stage": stage_name,
		"cell": Vector3i(wx, ground_y, wz), "node": root,
		"model_path": model_path,
		"bounds": Picking.world_bounds(root), "occupancy_id": int(root.get_meta("occupancy_id", -1))}
	_track_flight_reach(_trees[tree_id].bounds,root.position)
	_update_felling_marker(tree_id)
	_spawned_count += 1
	return root


func _despawn_column(key: Vector2i, preserve_occupancy: bool = false) -> void:
	var nodes: Array = _loaded_columns.get(key, [])
	for n in nodes:
		if is_instance_valid(n):
			var tree_id: Vector2i = n.get_meta("tree_id")
			if _trees.has(tree_id):
				_trees[tree_id]["node"] = null
			_clear_felling_marker(tree_id)
			if not preserve_occupancy:
				_unregister_tree_occupancy(tree_id)
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
	_update_felling_marker_positions()


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
		stage_data: Dictionary, season: String, world_pos: Vector3i, picked := false) -> String:
	var models: Dictionary = stage_data.get("models", {})
	var fruit: Dictionary = stage_data.get("fruit_harvest", {})
	if stage_data.has("picked_models") and (picked or season != String(fruit.get("harvest_season", ""))):
		models = stage_data.picked_models
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
	# Reconcile even when restoring the same season: the saved year/crop may differ.
	for id: Vector2i in _tree_changes:
		var state: Dictionary = _tree_changes[id]
		if String(state.get("action", "fell")) == "harvest" and bool(state.get("designated", false)) and not can_harvest_tree(id):
			cancel_felling(id)
	if new_season == _season:
		for id: Vector2i in _tree_changes: _refresh_tree_crop_visual(id)
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
		_despawn_column(key, true) # Seasonal visuals must not briefly open paths through trunks.
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
	if ref.has("picked_models"):
		return season # Crop models can change even when evergreen foliage does not.
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


## Flying wildlife respects whole canopies, including sliced/hidden trees.
## Ground occupancy remains trunk-only. Query nearby streamed columns instead
## of scanning the entire forest on each flight step.
func flight_obstacles(area: AABB) -> Array[AABB]:
	var result: Array[AABB] = []
	var search := area.grow(_flight_tree_reach)
	for x in range(maxi(0,floori(search.position.x/16)),mini(63,floori(search.end.x/16))+1):
		for z in range(maxi(0,floori(search.position.z/16)),mini(63,floori(search.end.z/16))+1):
			for node: Node3D in _loaded_columns.get(Vector2i(x,z),[]):
				if not is_instance_valid(node): continue
				var id: Vector2i = node.get_meta("tree_id",Vector2i(-1,-1))
				if not _trees.has(id) or bool(_tree_changes.get(id,{}).get("felled",false)): continue
				var box: AABB = _trees[id].bounds
				if area.intersects(box): result.append(box)
	return result

func _track_flight_reach(box: AABB, origin: Vector3) -> void:
	_flight_tree_reach = maxf(_flight_tree_reach,maxf(absf(box.position.x-origin.x),absf(box.end.x-origin.x)))
	_flight_tree_reach = maxf(_flight_tree_reach,maxf(absf(box.position.z-origin.z),absf(box.end.z-origin.z)))


# ── Object explorer provider ──────────────────────────────────────────────────

func pick_explorer_object(start: Vector3, end: Vector3) -> Dictionary:
	var result := {}
	var nearest := start.distance_to(end)
	for tree_id: Vector2i in _trees:
		var tree: Dictionary = _trees[tree_id]
		var node := tree["node"] as Node3D
		if not is_instance_valid(node) or not node.is_visible_in_tree():
			continue
		if (tree["bounds"] as AABB).intersects_segment(start, end) == null:
			continue
		var distance := _picking.hit_distance(node, start, end)
		if distance < nearest:
			nearest = distance
			result = {"id": tree_id, "distance": distance}
	return result


func get_explorer_bounds(tree_id: Variant) -> AABB:
	if not _trees.has(tree_id):
		return AABB()
	var node := _trees[tree_id]["node"] as Node3D
	if not is_instance_valid(node) or not node.is_visible_in_tree():
		return AABB()
	return _trees[tree_id]["bounds"]


func get_explorer_data(tree_id: Variant) -> Dictionary:
	if not _trees.has(tree_id):
		return {}
	if bool(_tree_changes.get(tree_id, {}).get("felled", false)):
		return {}
	var tree: Dictionary = _trees[tree_id]
	if (tree["cell"] as Vector3i).y > _slice_y:
		return {}
	var species := {}
	for entry: Dictionary in _species:
		if entry["name"] == tree["name"]:
			species = entry
			break
	if species.is_empty():
		return {}
	var stages: Dictionary = species["stages"]
	var stage: Dictionary = stages.get(tree["stage"], {})
	# Species capability and current-stage capability are distinct: apple saplings
	# are too young, while oaks have no seasonal fruit at any age.
	var fruit: Dictionary = stage.get("fruit_harvest", {})
	var species_fruit: Dictionary = stages.get("mature", {}).get("fruit_harvest", {})
	var fruit_status := "N/A"
	var fruit_season := "N/A"
	if not species_fruit.is_empty():
		fruit_season = String(species_fruit.get("harvest_season", "")).capitalize()
		if fruit.is_empty():
			fruit_status = "Too young"
		elif String(fruit.get("harvest_season", "")) != _season:
			fruit_status = "Out of season"
		else:
			fruit_status = "In season"
		if float(species_fruit.get("work_seconds", 0)) > 0 and not fruit.is_empty():
			fruit_status = "Ready to harvest" if can_harvest_tree(tree_id) else "Picked this season" \
				if String(_tree_changes.get(tree_id, {}).get("harvested_cycle", "")) == _fruit_cycle() else "Out of season"
	var guaranteed: Array[String] = []
	var possible: Array[String] = []
	for drop: Dictionary in stage.get("harvest", {}).get("yields", []):
		var line := "%d × %s" % [int(drop.get("count", 1)), _explorer_item_name(String(drop.get("item", "")))]
		var chance := float(drop.get("chance", 1.0))
		if chance >= 1.0:
			guaranteed.append(line)
		else:
			possible.append("%s (%d%%)" % [line, roundi(chance * 100.0)])
	var details := ""
	if not species_fruit.is_empty():
		details = "Seasonal fruit: %s." % _explorer_item_name(String(species_fruit.get("yield_item", "")))
		if float(species_fruit.get("work_seconds", 0)) > 0:
			details += " Pick once per harvest season; the tree stays standing."
			if not fruit.is_empty(): details += "\nHarvest: %d berries · %.0f seconds." % [int(fruit.yield_count), float(fruit.work_seconds)]
	if not possible.is_empty():
		if not details.is_empty():
			details += "\n\n"
		details += "Possible extras when felled:\n" + "\n".join(possible)
	var change: Dictionary = _tree_changes.get(tree_id, {})
	var marked := bool(change.get("designated", false))
	var harvesting := String(change.get("action", "fell")) == "harvest"
	var progress := float(change.get("work_seconds", 0.0))
	var duration := float(stage.get("fruit_harvest" if harvesting else "felling", {}).get("work_seconds", 1.0))
	var status := "Standing"
	if marked:
		status = "Marked for harvest" if harvesting else "Marked for felling"
		var source: RefCounted = _felling_sources.get(tree_id)
		if source != null:
			var task := TaskManager.get_task(int(source.get("lease_id")))
			if task != null:
				if task.retry_at > Time.get_ticks_msec():
					status = "Awaiting reachable route"
				elif task.status == Task.Status.ASSIGNED:
					status = "Dwarf approaching"
				elif task.status == Task.Status.IN_PROGRESS:
					status = "Picking berries" if harvesting else "Chopping"
	if progress > 0.0:
		status += " · %d%%" % mini(99, floori(progress / maxf(duration, .001) * 100.0))
	if harvesting:
		if marked: fruit_status = status
		status = "Standing"
	var actions: Array = []
	if marked:
		actions.append({"id": "cancel_felling", "text": "Cancel harvest" if harvesting else "Cancel felling"})
	else:
		if can_harvest_tree(tree_id): actions.append({"id": "harvest", "text": "Harvest berries"})
		actions.append({"id": "fell", "text": "Fell tree"})
	return {"title": String(tree["name"]).capitalize() + " tree", "kind": "Tree",
		"rows": [
			["Growth stage", String(tree["stage"]).capitalize()],
			["Fruit", fruit_status],
			["Fruit season", fruit_season],
			["Felling yield", ", ".join(guaranteed) if not guaranteed.is_empty() else "None"],
			["Felling", status],
		], "details": details, "actions": actions}


func perform_explorer_action(tree_id: Variant, action_id: String) -> void:
	if tree_id is Vector2i:
		if action_id == "fell":
			designate_felling(tree_id)
		elif action_id == "cancel_felling":
			cancel_felling(tree_id)
		elif action_id == "harvest":
			designate_harvest(tree_id)


func _explorer_item_name(item_key: String) -> String:
	var items := get_tree().get_first_node_in_group("item_drop_manager")
	if items != null:
		var definition: Dictionary = items.call("get_item_def", item_key)
		if definition.has("display_name"):
			return String(definition["display_name"])
	return item_key.get_slice(":", item_key.get_slice_count(":") - 1).capitalize()


# ── Persistent forestry state / work sources ──────────────────────────────────

func _species_for_key(key: String) -> Dictionary:
	for species: Dictionary in _species:
		if species["key"] == key:
			return species
	return {}


func designate_felling(tree_id: Vector2i) -> bool:
	return _designate_tree_work(tree_id, "fell")


func designate_harvest(tree_id: Vector2i) -> bool:
	return can_harvest_tree(tree_id) and _designate_tree_work(tree_id, "harvest")


func _fruit_cycle() -> String:
	return "%d:%s" % [WorldClock.year, WorldClock.season]


func _tree_fruit(tree_id: Vector2i) -> Dictionary:
	var state: Dictionary = _tree_changes.get(tree_id, {})
	var tree: Dictionary = _trees.get(tree_id, {})
	var species := _species_for_key(String(state.get("species", "base:flora:%s_tree" % tree.get("name", ""))))
	return species.get("stages", {}).get(state.get("stage", tree.get("stage", "")), {}).get("fruit_harvest", {})


func can_harvest_tree(tree_id: Vector2i) -> bool:
	var fruit := _tree_fruit(tree_id)
	var state: Dictionary = _tree_changes.get(tree_id, {})
	# Only definitions with authored worker timing are live harvest tasks.
	return float(fruit.get("work_seconds", 0)) > 0 and not bool(state.get("felled", false)) \
		and String(fruit.get("harvest_season", "")) == WorldClock.season \
		and String(state.get("harvested_cycle", "")) != _fruit_cycle()


func trees_in_harvest_rect(rect: Rect2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for id: Vector2i in trees_in_felling_rect(rect):
		if can_harvest_tree(id) and not (bool(_tree_changes.get(id, {}).get("designated", false)) \
			and String(_tree_changes[id].get("action", "fell")) == "fell"):
			result.append(id)
	return result


func _designate_tree_work(tree_id: Vector2i, action: String) -> bool:
	if not _trees.has(tree_id) or bool(_tree_changes.get(tree_id, {}).get("felled", false)):
		return false
	if bool(_tree_changes.get(tree_id, {}).get("designated", false)):
		return String(_tree_changes[tree_id].get("action", "fell")) == action
	if not _tree_changes.has(tree_id):
		var tree: Dictionary = _trees[tree_id]
		var species_key := "base:flora:%s_tree" % String(tree["name"])
		if _species_for_key(species_key).is_empty():
			return false
		_tree_changes[tree_id] = {"species": species_key, "stage": String(tree["stage"]),
			"origin": tree["cell"], "work_seconds": 0.0, "designated": false, "felled": false,
			"action": "fell", "fell_work_seconds": 0.0, "harvest_work_seconds": 0.0,
			"harvest_work_cycle": "", "harvested_cycle": ""}
	var state: Dictionary = _tree_changes[tree_id]
	state[String(state.get("action", "fell")) + "_work_seconds"] = float(state.work_seconds)
	if action == "harvest" and String(state.get("harvest_work_cycle", "")) != _fruit_cycle():
		state["harvest_work_seconds"] = 0.0
		state["harvest_work_cycle"] = _fruit_cycle()
	state["action"] = action
	state.work_seconds = float(state.get(action + "_work_seconds", 0.0))
	_tree_changes[tree_id]["designated"] = true
	_ensure_felling_source(tree_id)
	_update_felling_marker(tree_id)
	tree_felling_changed.emit(tree_id)
	return true


func get_slice_y() -> int:
	return _slice_y


## Opaque identity for a designation; a new mark after cancellation gets a new
## source. UI undo cannot accidentally cancel a later order or a loaded save.
func get_felling_order_token(tree_id: Vector2i) -> RefCounted:
	return _felling_sources.get(tree_id)


func marked_trees_in_screen_rect(rect: Rect2, camera: Camera3D) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for id: Vector2i in _felling_sources:
		var bounds := get_explorer_bounds(id)
		if bounds.size == Vector3.ZERO: continue
		var centre := bounds.get_center()
		if not camera.is_position_behind(centre) and rect.has_point(camera.unproject_position(centre)):
			result.append(id)
	return result


## Rectangle membership uses the trunk's centre, not its overhanging canopy.
## Hidden/streamed-out/felled trees cannot receive an invisible designation.
func trees_in_felling_rect(rect: Rect2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for id: Vector2i in _trees:
		var tree: Dictionary = _trees[id]
		var node := tree["node"] as Node3D
		if not is_instance_valid(node) or not node.is_visible_in_tree():
			continue
		if bool(_tree_changes.get(id, {}).get("felled", false)):
			continue
		var centre := Vector2i(floori(node.position.x), floori(node.position.z))
		if rect.has_point(centre):
			result.append(id)
	return result


func cancel_felling(tree_id: Vector2i) -> void:
	if not _tree_changes.has(tree_id) or bool(_tree_changes[tree_id]["felled"]):
		return
	_tree_changes[tree_id]["designated"] = false
	_retire_felling_source(tree_id, true)
	_clear_felling_marker(tree_id)
	# Retain completed work on the tree, including after cancellation/re-designation.
	tree_felling_changed.emit(tree_id)


func _ensure_felling_source(tree_id: Vector2i) -> void:
	if _felling_sources.has(tree_id):
		return
	var state: Dictionary = _tree_changes[tree_id]
	var species := _species_for_key(String(state["species"]))
	var stage: Dictionary = species["stages"][state["stage"]]
	var source := FellingSource.new()
	var harvest := String(state.get("action", "fell")) == "harvest"
	source.task_type = Task.Type.HARVEST_TREE if harvest else Task.Type.FELL_TREE
	source.source_id = TaskManager.allocate_source_id()
	source.origin = state["origin"]
	source.footprint = _footprint_for(species["placement"], String(state["stage"]))
	source.duration = maxf(float(stage.get("fruit_harvest" if harvest else "felling", {}).get("work_seconds", 1.0)), .01)
	source.state = state
	source.complete_callback = _complete_felling.bind(tree_id)
	source.contact_distance_callback = _felling_contact_distance.bind(tree_id)
	source.feedback_visible_callback = _felling_feedback_visible.bind(tree_id)
	_felling_sources[tree_id] = source
	_source_trees[source.source_id] = tree_id
	TaskManager.register_work_source(source.source_id, source)
	source.ensure_lease()


func _felling_feedback_visible(tree_id: Vector2i) -> bool:
	var node: Node3D = _trees.get(tree_id,{}).get("node")
	return is_instance_valid(node) and node.is_visible_in_tree()


func _felling_contact_distance(start: Vector3, end: Vector3, tree_id: Vector2i) -> float:
	var record: Dictionary = _trees.get(tree_id,{})
	var node: Node3D = record.get("node")
	return _picking.hit_distance(node,start,end) if is_instance_valid(node) else INF


func _retire_felling_source(tree_id: Vector2i, cancel_task: bool) -> void:
	var source: RefCounted = _felling_sources.get(tree_id)
	if source == null:
		return
	var source_id := int(source.get("source_id"))
	_felling_sources.erase(tree_id)
	_source_trees.erase(source_id) # Retired tasks cannot re-post a lease in callbacks.
	if cancel_task:
		TaskManager.cancel_source_tasks(source_id)
	TaskManager.unregister_work_source(source_id)


func _on_felling_released(task: Task, dwarf_id: int, _reason: int) -> void:
	if _source_trees.has(task.source_id):
		_felling_sources[_source_trees[task.source_id]].release_worker(dwarf_id)


func _on_felling_task_gone(task: Task) -> void:
	if _source_trees.has(task.source_id):
		_felling_sources[_source_trees[task.source_id]].on_task_gone(task)


func _complete_felling(dwarf_id: int, tree_id: Vector2i) -> bool:
	var source: RefCounted = _felling_sources.get(tree_id)
	if source == null or int(source.get("reserved_by")) != dwarf_id:
		return false
	var state: Dictionary = _tree_changes[tree_id]
	if bool(state["felled"]) or not bool(state["designated"]):
		return false
	if float(state["work_seconds"]) < float(source.get("duration")):
		return false
	if String(state.get("action", "fell")) == "harvest":
		return _complete_tree_harvest(dwarf_id, tree_id)
	var drops := get_tree().get_first_node_in_group("item_drop_manager")
	if drops == null:
		return false
	# Commit the tombstone before emitting any drops. Reloading/seasonal spawning
	# only consults this state and can never rerun the completion side effects.
	state["felled"] = true
	state["designated"] = false
	var show_feedback := _felling_feedback_visible(tree_id)
	_remove_tree_visual(tree_id)
	_retire_felling_source(tree_id, false) # The finishing dwarf completes its lease.
	var species := _species_for_key(String(state["species"]))
	var yields: Array = species["stages"][state["stage"]].get("harvest", {}).get("yields", [])
	var drop_cell: Vector3i = state["origin"]
	var width := _footprint_for(species["placement"], String(state["stage"]))
	if show_feedback:
		WorkFeedback.tree_felled(Vector3(drop_cell)+Vector3(width*.5,1,width*.5),String(state["stage"]),drop_cell.y)
	var half := floori(float(width) * .5)
	drop_cell += Vector3i(half, 1, half)
	for i in range(yields.size()):
		var drop: Dictionary = yields[i]
		if _unit(_hash(tree_id.x, tree_id.y, 17001 + i)) < float(drop.get("chance", 1.0)):
			drops.call("spawn_drop", String(drop["item"]), int(drop.get("count", 1)), drop_cell)
	tree_felling_changed.emit(tree_id)
	return true


func _complete_tree_harvest(dwarf_id: int, tree_id: Vector2i) -> bool:
	if not can_harvest_tree(tree_id): return false
	var drops := get_tree().get_first_node_in_group("item_drop_manager")
	var dwarf: DwarfAgent = TaskManager._agents.get(dwarf_id)
	if drops == null or dwarf == null: return false
	var state: Dictionary = _tree_changes[tree_id]
	var fruit := _tree_fruit(tree_id)
	# Commit once before rewards. Neither felling nor streaming refreshes this crop.
	state["harvested_cycle"] = _fruit_cycle()
	state.designated = false
	state.work_seconds = 0.0
	state["harvest_work_seconds"] = 0.0
	_retire_felling_source(tree_id, false)
	_clear_felling_marker(tree_id)
	_refresh_tree_crop_visual(tree_id)
	# The trunk stays solid: put the crate on the worker's accessible side.
	drops.call("spawn_drop", String(fruit.yield_item), int(fruit.yield_count), dwarf.current_cell() + Vector3i.UP)
	tree_felling_changed.emit(tree_id)
	return true


func _refresh_tree_crop_visual(tree_id: Vector2i) -> void:
	var tree: Dictionary = _trees.get(tree_id, {})
	var node: Node3D = tree.get("node")
	if not is_instance_valid(node): return
	var species := _species_for_key("base:flora:%s_tree" % tree.name)
	var stage: Dictionary = species.stages[tree.stage]
	if not stage.has("picked_models"): return
	var path := resolve_tree_model_for_season(stage, _season, tree.cell,
		String(_tree_changes.get(tree_id, {}).get("harvested_cycle", "")) == _fruit_cycle())
	if path == String(tree.get("model_path", "")): return
	var packed := _load_scene(path)
	if packed == null: return
	var visual := packed.instantiate() as Node3D
	visual.scale = Vector3.ONE * godot_units_per_block / maxf(voxels_per_block, .0001)
	_apply_material_recursive(visual)
	# Replace only the art. Occupancy, collision body and reservations stay intact.
	var old := node.get_child(0)
	node.remove_child(old)
	old.queue_free()
	node.add_child(visual)
	node.move_child(visual, 0)
	tree.model_path = path
	tree.bounds = Picking.world_bounds(node)
	_track_flight_reach(tree.bounds,node.position)


func _remove_tree_visual(tree_id: Vector2i) -> void:
	_clear_felling_marker(tree_id)
	_unregister_tree_occupancy(tree_id) # Also works between seasonal visual instances.
	if not _trees.has(tree_id):
		return
	var node := _trees[tree_id]["node"] as Node3D
	_trees[tree_id]["node"] = null
	if not is_instance_valid(node):
		return
	var column := Vector2i(tree_id.x >> 4, tree_id.y >> 4)
	if _loaded_columns.has(column):
		_loaded_columns[column].erase(node)
	node.visible = false
	if node is CollisionObject3D:
		(node as CollisionObject3D).collision_layer = 0
	node.queue_free()
	_spawned_count -= 1


func _unregister_tree_occupancy(tree_id: Vector2i) -> void:
	if not _trees.has(tree_id):
		return
	var id := int(_trees[tree_id].get("occupancy_id", -1))
	if id >= 0:
		PlacedEntityRegistry.unregister(id)
		_trees[tree_id]["occupancy_id"] = -1


func _update_felling_marker(tree_id: Vector2i) -> void:
	_clear_felling_marker(tree_id)
	if not bool(_tree_changes.get(tree_id, {}).get("designated", false)):
		return
	var bounds := get_explorer_bounds(tree_id)
	if bounds.size == Vector3.ZERO:
		return
	var marker := Label.new()
	marker.text = "✿" if String(_tree_changes[tree_id].get("action", "fell")) == "harvest" else "🪓"
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marker.add_theme_font_size_override("font_size", 28)
	marker.add_theme_color_override("font_outline_color", Color(.08, .07, .06, .95))
	marker.add_theme_constant_override("outline_size", 4)
	marker.visible = false
	_felling_marker_layer.add_child(marker)
	_felling_markers[tree_id] = marker


func _update_felling_marker_positions() -> void:
	var camera := get_viewport().get_camera_3d()
	var screen := get_viewport().get_visible_rect()
	for id: Vector2i in _felling_markers:
		var marker: Label = _felling_markers[id]
		var bounds := get_explorer_bounds(id)
		marker.visible = camera != null and bounds.size != Vector3.ZERO
		if not marker.visible:
			continue
		var above := Vector3(bounds.get_center().x, bounds.end.y + .6, bounds.get_center().z)
		marker.visible = not camera.is_position_behind(above)
		if not marker.visible:
			continue
		var position := camera.unproject_position(above)
		# Stay above the entire projected canopy, including the far top corner
		# seen by an angled RTS camera, rather than drifting into its leaves.
		for i in range(8):
			var corner := bounds.get_endpoint(i)
			if not camera.is_position_behind(corner):
				position.y = minf(position.y, camera.unproject_position(corner).y - 6.0)
		marker.visible = screen.has_point(position)
		marker.position = position - Vector2(marker.size.x * .5, marker.size.y)


func _clear_felling_marker(tree_id: Vector2i) -> void:
	var marker: Label = _felling_markers.get(tree_id)
	if is_instance_valid(marker):
		marker.visible = false
		marker.queue_free()
	_felling_markers.erase(tree_id)


func save_section_key() -> String:
	return "flora"


func save_restore_priority() -> int:
	return 15 # After mined terrain; before furniture/items/dwarf task reconstruction.


func serialize_state() -> Dictionary:
	var entries: Array = []
	var ids: Array = _tree_changes.keys()
	ids.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x or (a.x == b.x and a.y < b.y))
	for id: Vector2i in ids:
		var entry: Dictionary = _tree_changes[id].duplicate(true)
		entry[String(entry.get("action", "fell")) + "_work_seconds"] = float(entry.work_seconds)
		entry["origin"] = SaveManager.pack_v3i(entry["origin"])
		entries.append(entry)
	return {"trees": entries}


func restore_state(state: Dictionary) -> void:
	for id: Vector2i in _felling_sources.keys():
		_retire_felling_source(id, true)
	for id: Vector2i in _felling_markers.keys():
		_clear_felling_marker(id)
	_tree_changes.clear()
	# Missing section in a pre-forestry save means the untouched seeded forest.
	for raw in state.get("trees", []):
		if not (raw is Dictionary):
			continue
		var entry: Dictionary = raw
		var species := _species_for_key(String(entry.get("species", "")))
		var stage_name := String(entry.get("stage", ""))
		if species.is_empty() or not species["stages"].has(stage_name):
			continue
		var origin := SaveManager.unpack_v3i(entry.get("origin", []))
		if origin.x < 0 or origin.x >= WorldData.WORLD_SIZE_X or origin.z < 0 \
				or origin.z >= WorldData.WORLD_SIZE_Z or origin.y < 1 or origin.y >= WorldData.WORLD_SIZE_Y - 1:
			continue
		var id := Vector2i(origin.x, origin.z)
		var felled := bool(entry.get("felled", false))
		var stage: Dictionary = species.stages[stage_name]
		var action := String(entry.get("action", "fell"))
		var fruit: Dictionary = stage.get("fruit_harvest", {})
		if action != "harvest" or float(fruit.get("work_seconds", 0)) <= 0: action = "fell"
		var fell_duration := float(stage.get("felling", {}).get("work_seconds", 1.0))
		var harvest_duration := float(fruit.get("work_seconds", 0))
		var duration := harvest_duration if action == "harvest" else fell_duration
		_tree_changes[id] = {"species": String(species["key"]), "stage": stage_name, "origin": origin,
			"work_seconds": clampf(float(entry.get("work_seconds", 0.0)), 0.0, duration),
			"action": action, "fell_work_seconds": clampf(float(entry.get("fell_work_seconds", 0)), 0, fell_duration),
			"harvest_work_seconds": clampf(float(entry.get("harvest_work_seconds", 0)), 0, harvest_duration),
			"harvest_work_cycle": String(entry.get("harvest_work_cycle", "")), "harvested_cycle": String(entry.get("harvested_cycle", "")),
			"felled": felled, "designated": bool(entry.get("designated", false)) and not felled}
		if felled:
			_remove_tree_visual(id)
		elif bool(_tree_changes[id]["designated"]):
			_ensure_felling_source(id)
			_update_felling_marker(id)
		if not felled: _refresh_tree_crop_visual(id)


func _exit_tree() -> void:
	for id: Vector2i in _felling_sources.keys():
		_retire_felling_source(id, true)
	for id: Vector2i in _trees:
		_unregister_tree_occupancy(id)
