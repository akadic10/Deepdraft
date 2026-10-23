extends Node3D

const TileMesher = preload("res://scripts/components/TerrainTileMesher.gd")
const CavityShell = preload("res://scripts/components/TerrainCavityShell.gd")
const BlockInspector = preload("res://scripts/components/BlockInspector.gd")

## Coalesced final-state terrain invalidations; no construction ownership.
var _terrain_changes: Dictionary = {}
var _floor_art = preload("res://scripts/components/ConstructionFloorArt.gd").new()
var underground_view: Node

## Renders the terrain as the block-face overview: one MeshInstance3D per
## 32x32-column tile, built on WorkerThreadPool and uploaded within a frame
## budget. Dirty tiles are queued and drained in _process().
##
## This node owns the lifecycle, the exports, the slice plane, the cut sets,
## the added terrain, the VisibleVolume contract and the material. The work is
## split across helpers it creates:
##   tiles          TerrainTileMesher   the block-face overview tiles
##   cavity_shell   TerrainCavityShell  faces around enclosed cut cells
##   block_inspector BlockInspector     the DEV inspector (dev tools only)

# ── Exports ───────────────────────────────────────────────────────────────────

@export var auto_generate: bool = true
@export var world_seed: int = 0

@export var slice_y: int = WorldData.MAX_Y:
	set(v):
		var old_y := slice_y
		slice_y = v
		if old_y != v:
			tiles.enqueue_tiles_for_slice_change(old_y, v)
			_visible_volume_dirty = true   # VisibleVolume contract (doc 11 Phase 3)
			cavity_shell.dirty = true      # Physical shell clips only to this plane.
		tiles.begin_slice_timing(old_y, v)


## The exact full-world overview mesh is the only terrain renderer, for normal
## play and every slice depth (doc 11 Phase SO). It emits top faces plus
## vertical faces where neighbouring columns are lower, block-accurate in
## geometry; cut floors show authored strata only (slicing never reveals
## undiscovered resources).
@export var show_overview_sides: bool = true
@export_range(0, 128, 1) var overview_edge_bottom_y: int = 0
@export_range(1, 64, 1) var overview_tiles_per_frame: int = 8
@export_range(0, 32, 1) var overview_startup_radius_tiles: int = 5
## Debug only. When true, each overview column re-runs the full generation
## pipeline (get_generated_block_id) to cross-check the cached surface block.
## This doubles per-column generation cost across the whole world, so it stays
## off in normal runs. Validation has held at 0 mismatches / 1,048,576 columns.
@export var overview_validate_block_ids: bool = false
## Debug only. When true, the overview tile build accumulates per-section timing
## (surface loop, side build, top merge, mesh creation) and prints the breakdown
## plus the single slowest tile when the full overview completes.
@export var overview_profile: bool = false
## When true, overview batches run asynchronously on WorkerThreadPool and only
## completed, current results upload within a main-thread budget. Set false
## to fall back to the synchronous per-tile build (e.g. to isolate a problem).
@export var overview_threaded: bool = true
## Debug (slice plan doc 11, Phase 0). When true, every slice_y change logs how
## many tiles were re-enqueued and how long the rebuild queue took to drain
## (frames, wall ms, worst single frame).
@export var slice_debug_timing: bool = true

# ── Internal state ────────────────────────────────────────────────────────────

const WORLD_SIZE_X: int = WorldData.WORLD_SIZE_X
const WORLD_SIZE_Y: int = WorldData.WORLD_SIZE_Y
const WORLD_SIZE_Z: int = WorldData.WORLD_SIZE_Z
const OVERVIEW_STEP: int = TileMesher.OVERVIEW_STEP
const OVERVIEW_TILE_SIZE: int = TileMesher.OVERVIEW_TILE_SIZE
var _material: Material
var underground_lighting: Node
var _water_view: Node3D
## Cut cells: designations (planned), mined holes and discovered or previewed
## caves. The tiles snapshot these sets between batches; the shell reads them.
var _visual_cut_blocks: Dictionary = {}
var _planned_cut_blocks: Dictionary = {}
## Mined holes come from WorldData.is_removed_terrain (doc 11 Phase SO-2b). Under
## Option A (defect 2, 2026-06-05) designations and mined holes BOTH punch side
## bands and render in the cavity shell; removal only selects the shell's colour
## source — mined → exact generated id (mining reveals), designated → authored
## strata (a plan reveals nothing).
var _discovered_cave_blocks: Dictionary = {}
var _surface_caves_ready := false
var _debug_cave_blocks: Dictionary = {} # Explicit temporary preview; never saved or discovered.
var _debug_previous_readability := -1.0

var _camera_rig: Camera = null
## Overview tiles, cavity shell and DEV inspector (see the header).
var tiles := TileMesher.new(self)
var cavity_shell := CavityShell.new(self)
var block_inspector: BlockInspector = null


# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	add_to_group("terrain_overview_renderer")
	# All mesh positions are in world-space block coordinates.
	# The Renderer node MUST sit at world origin or every mesh will be displaced.
	if global_position != Vector3.ZERO:
		push_warning("WorldRenderer: node was not at origin (%s) — resetting." % str(global_position))
	global_position = Vector3.ZERO
	global_rotation = Vector3.ZERO
	scale           = Vector3.ONE

	underground_lighting = preload("res://scripts/components/UndergroundLighting.gd").new()
	underground_lighting.name = "UndergroundLighting"
	add_child(underground_lighting)
	_material = underground_lighting.make_material(_create_material())
	BlockRegistry.configure_terrain_material(_material)
	var water_view := preload("res://scripts/components/WaterRenderer.gd").new()
	water_view.name = "Water"
	water_view.terrain = self
	_water_view = water_view
	add_child(water_view)
	var moisture_view := preload("res://scripts/components/MoistureRenderer.gd").new()
	moisture_view.terrain = self
	add_child(moisture_view)
	if UIRegistry.dev_tools_enabled: block_inspector = BlockInspector.new(self)

	WorldData.block_changed.connect(_terrain_block_changed)
	InteriorTracker.caves_discovered.connect(add_discovered_cave_blocks)

	# Seasonal surface palettes (surface_palettes.json) are baked into vertex colours at
	# mesh-build time, so when the season turns we re-mesh whatever is currently built —
	# reuse mesh nodes and drain changes through the normal tile budget.
	WorldClock.season_changed.connect(_on_season_changed)

	_camera_rig = Camera.find_in(get_tree().current_scene)

	# Auto-create the camera rig if one isn't already in the scene.
	# Uses call_deferred so the full scene tree is ready before we add to it.
	call_deferred("_setup_camera_rig")

	if auto_generate:
		tiles.startup_started_msec = Time.get_ticks_msec()
		var generation_seed := world_seed
		if SaveManager != null:
			generation_seed = SaveManager.generation_seed_for_new_scene(world_seed)
		WorldGenerator.generate(generation_seed)
		print("WorldRenderer: generation started (seed %d)." % WorldGenerator.world_seed)


## Join only on teardown/reload, before the generator can replace its immutable
## maps. Normal frames only collect jobs that have already completed.
func finish_pending_overview() -> void:
	_seasonal_refresh.clear()
	tiles.finish_pending()


func _exit_tree() -> void:
	finish_pending_overview()


func _process(_delta: float) -> void:
	_flush_terrain_changes()
	_seasonal_refresh.drain(_enqueue_seasonal_batch)
	if not _surface_caves_ready and WorldGenerator.is_maps_ready():
		_surface_caves_ready = true
		InteriorTracker.reveal_surface_caves()
		# Also support a renderer attached after the water owner initialized.
		for cave: Dictionary in WorldGenerator.get_cave_catalog():
			if cave.get("surface_open",false):
				var cells := WorldGenerator.get_cave_air_cells(cave.id)
				add_discovered_cave_blocks(cells)
				underground_lighting.darken_discovered_caves(cells)
	if _added_terrain_dirty or (_added_terrain != null and _added_terrain_slice != slice_y):
		_rebuild_added_terrain()
	elif not _added_dirty_columns.is_empty():
		var added_columns := _added_dirty_columns.keys()
		_added_dirty_columns.clear()
		_rebuild_added_columns(added_columns)
	# VisibleVolume contract (doc 11 Phase 3, ref doc 10 rule S5): flush at most
	# ONE visible_volume_changed per frame, before the overview tiles drain, so
	# consumers rebuild reactively and never poll. Any number of state changes in
	# a frame collapse to a single emission.
	if _visible_volume_dirty:
		_visible_volume_dirty = false
		visible_volume_changed.emit()
		# X-ray chunk uploads change inspection/overlay visibility, not physical
		# terrain. Rebuilding the whole cavity here stalls every shell upload.
		# Slice changes and terrain edits invalidate the cavity independently.

	cavity_shell.flush()
	tiles.process_frame()


func is_block_inspector_active() -> bool:
	return block_inspector != null and block_inspector.is_active()


func _unhandled_input(event: InputEvent) -> void:
	if block_inspector != null:
		block_inspector.handle_input(event)


## Small views for XrayController and the terrain explorer.
func terrain_material() -> Material: return _material
func mark_visible_volume_dirty() -> void: _visible_volume_dirty = true
func is_visually_cut(cell: Vector3i) -> bool: return _visual_cut_blocks.has(cell)
func visual_cut_blocks() -> Dictionary: return _visual_cut_blocks
func discovered_cave_blocks() -> Dictionary: return _discovered_cave_blocks
func debug_cave_blocks() -> Dictionary: return _debug_cave_blocks


## The scene's Camera rig, found lazily (it may be created a frame later).
func camera_rig() -> Camera:
	if _camera_rig == null:
		_camera_rig = Camera.find_in(get_tree().current_scene)
	return _camera_rig


func set_visual_cut_blocks(blocks: Dictionary) -> void:
	_planned_cut_blocks = blocks.duplicate()
	_visual_cut_blocks = blocks.duplicate()
	_visual_cut_blocks.merge(_discovered_cave_blocks)
	_visual_cut_blocks.merge(_debug_cave_blocks)
	_visual_cut_blocks.merge(WorldData.terrain_overrides())
	cavity_shell.clear_cut_index()
	for block: Vector3i in _visual_cut_blocks.keys():
		cavity_shell.track_cut(block, 1)
	_invalidate_visual_cut_meshes_global()


func add_visual_cut_blocks(blocks: Array[Vector3i]) -> void:
	for block: Vector3i in blocks: _planned_cut_blocks[block] = true
	_add_cut_blocks(blocks)


func _add_cut_blocks(blocks: Array[Vector3i]) -> void:
	var changed: Array[Vector3i] = []
	for block: Vector3i in blocks:
		if _visual_cut_blocks.has(block):
			continue
		_visual_cut_blocks[block] = true
		cavity_shell.track_cut(block, 1)
		changed.append(block)
	_invalidate_visual_cut_blocks(changed)


func remove_visual_cut_blocks(blocks: Array[Vector3i]) -> void:
	for block: Vector3i in blocks: _planned_cut_blocks.erase(block)
	_remove_unowned_cut_blocks(blocks)


func _remove_unowned_cut_blocks(blocks: Array[Vector3i]) -> void:
	var changed: Array[Vector3i] = []
	for block: Vector3i in blocks:
		if WorldData.has_terrain_override(block) or _planned_cut_blocks.has(block) or _discovered_cave_blocks.has(block) or _debug_cave_blocks.has(block): continue
		if not _visual_cut_blocks.has(block):
			continue
		_visual_cut_blocks.erase(block)
		cavity_shell.track_cut(block, -1)
		changed.append(block)
	_invalidate_visual_cut_blocks(changed)


# ── Mined cavities (doc 11 Phase SO-2b) ───────────────────────────────────────

## Called right after blocks were removed in WorldData (which records them): the
## plans become holes. They stay in (or join) the visual-cut set, their wall
## side-bands punch open and the cavity shell grows.
func add_mined_blocks(blocks: Array[Vector3i]) -> void:
	for block: Vector3i in blocks:
		_planned_cut_blocks.erase(block)
		if not _visual_cut_blocks.has(block):
			_visual_cut_blocks[block] = true
			cavity_shell.track_cut(block, 1)
	_invalidate_visual_cut_blocks(blocks)   # re-punches tiles + rebuilds the shell


func add_discovered_cave_blocks(blocks: Array[Vector3i]) -> void:
	for block: Vector3i in blocks: _discovered_cave_blocks[block] = true
	_add_cut_blocks(blocks)
	# Preview may already have cut these cells, but discovery still changes
	# their lasting exposure status and must survive turning the preview off.
	_invalidate_visual_cut_blocks(blocks)


func set_debug_cave_blocks(blocks: Array[Vector3i]) -> void:
	if _material is ShaderMaterial:
		if not blocks.is_empty():
			if _debug_previous_readability < 0.0:
				_debug_previous_readability = float(_material.get_shader_parameter("readability_floor"))
			_material.set_shader_parameter("readability_floor", 0.35)
		elif _debug_previous_readability >= 0.0:
			_material.set_shader_parameter("readability_floor", _debug_previous_readability)
			_debug_previous_readability = -1.0
	var old: Array[Vector3i] = []
	old.assign(_debug_cave_blocks.keys())
	_debug_cave_blocks.clear()
	_remove_unowned_cut_blocks(old)
	for block: Vector3i in blocks: _debug_cave_blocks[block] = true
	_add_cut_blocks(blocks)
	old.append_array(blocks)
	_invalidate_visual_cut_blocks(old)

func clear_debug_cave_blocks() -> void:
	var empty: Array[Vector3i] = []
	set_debug_cave_blocks(empty)


func is_revealed_air(block: Vector3i) -> bool:
	return not BlockRegistry.is_solid(WorldData.get_terrain_block(block.x,block.y,block.z)) and (WorldData.is_removed_terrain(block) or _discovered_cave_blocks.has(block) or InteriorTracker.contains_air(block))


## Emits solid block n's face pointing back toward the cavity (see
## TerrainCavityShell.add_face). Also used by XrayGeometry.
func add_shell_face(
		n: Vector3i,
		dir: Vector3i,
		color: Color,
		verts: PackedVector3Array,
		norms: PackedVector3Array,
		cols: PackedColorArray,
		indices: PackedInt32Array) -> void:
	CavityShell.add_face(n, dir, color, verts, norms, cols, indices)


func _invalidate_visual_cut_blocks(blocks: Array[Vector3i]) -> void:
	if blocks.is_empty():
		return
	tiles.invalidate_cells(blocks)
	cavity_shell.invalidate_cells(blocks)   # designations and mined holes both shape the shell (SO-2b A)


func _invalidate_visual_cut_meshes_global() -> void:
	cavity_shell.dirty = true
	tiles.invalidate_global()


## Shared by natural overview plates and constructed stone cut by the slice.
## Only artificial cut faces dim; exposed tops and vertical faces keep their color.
static func slice_cut_color(color: Color) -> Color:
	return TileMesher.slice_cut_color(color)


const SeasonalRefresh = preload("res://scripts/components/SeasonalRefreshQueue.gd")
var _seasonal_refresh := SeasonalRefresh.new()

## Pace the seasonal recolour through the night. Ordinary edit/slice queues
## remain immediate and existing meshes stay visible while replacements build.
func _on_season_changed(_new_season: String) -> void:
	_added_terrain_dirty = true
	var seasonal: Array = []
	for key: Vector2i in tiles.overview_tile_nodes:
		seasonal.append([0, key])
	# Keep normal worker batch sizes: admitting single tiles repeatedly copies
	# the edit snapshot and recomputes whole-overview statistics for every tile.
	var batches: Array = []
	var batch_size := maxi(1, overview_tiles_per_frame)
	for offset in range(0, seasonal.size(), batch_size):
		batches.append(seasonal.slice(offset, mini(offset + batch_size, seasonal.size())))
	_seasonal_refresh.begin(batches, WorldClock)
	cavity_shell.dirty = true


func _enqueue_seasonal_batch(batch: Array) -> void:
	for entry: Array in batch: _enqueue_seasonal_mesh(entry)


func _enqueue_seasonal_mesh(entry: Array) -> void:
	match int(entry[0]):
		0:
			if tiles.overview_tile_nodes.has(entry[1]):
				tiles.enqueue_tile(entry[1])
				tiles.overview_built = false


# ── VisibleVolume contract (doc 11 Phase 3, ref doc 10 rule S5) ───────────────
# THE shared visibility interface for every overlay system (mining overlays
# first; X-ray inspection now composes the discovered shell). Composition order:
# clip plane first, then the x-ray set — same as Stonehearth's
# intersect_region_with_visible_volume. Consumers connect to
# visible_volume_changed (emitted at most once per frame, flushed in _process)
# and rebuild reactively; polling is a contract violation.

## Emitted at most once per frame after any visibility-state change (slice step;
## x-ray toggles / interior-set changes). Connect overlays here.
signal visible_volume_changed

var _visible_volume_dirty: bool = false


## True if a world block position is inside the visible volume.
## Slice plane first, then the discovered shell while inspecting underground.
func is_block_visible(pos: Vector3i) -> bool:
	return pos.y <= slice_y and (not is_instance_valid(underground_view) or underground_view.is_terrain_visible(pos))


## Returns the subset of blocks inside the visible volume (order preserved).
func filter_blocks(blocks: Array[Vector3i]) -> Array[Vector3i]:
	if slice_y >= WORLD_SIZE_Y - 1 and (not is_instance_valid(underground_view) or not underground_view.is_inspecting()):
		return blocks   # slice off — everything visible, skip the scan
	var out: Array[Vector3i] = []
	for block: Vector3i in blocks:
		if is_block_visible(block):
			out.append(block)
	return out


## Clips an AABB against the visible volume (cheap path for box overlays).
## Returns a zero-size AABB when the box lies entirely above the plane.
func clip_aabb(aabb: AABB) -> AABB:
	var top := float(slice_y + 1)   # plane cuts ABOVE the slice_y layer
	if aabb.position.y >= top:
		return AABB(aabb.position, Vector3.ZERO)
	if aabb.end.y <= top:
		return aabb
	var size := aabb.size
	size.y = top - aabb.position.y
	return AABB(aabb.position, size)


# ── Camera rig auto-setup ────────────────────────────────────────────────────

## Creates the Camera rig as a sibling of this Renderer node so the rig
## pans independently from the terrain meshes. Skips silently if one already
## exists anywhere in the scene (e.g. manually wired in the editor).
func _setup_camera_rig() -> void:
	_camera_rig = Camera.find_in(get_tree().current_scene)
	if _camera_rig != null:
		return   # already present — nothing to do
	_camera_rig = Camera.create_rig(get_parent())
	print("WorldRenderer: Camera rig created automatically.")


## The generated overview is immutable; mask every current override and draw
## solid overrides with their block's own art. This cache records no ownership.
func _terrain_block_changed(cell: Vector3i, _old: int, _new: int) -> void:
	_terrain_changes[cell] = true
	CavityShell.mark_columns_touching(_added_dirty_columns, [cell])

func _flush_terrain_changes() -> void:
	if _terrain_changes.is_empty(): return
	var changed: Array[Vector3i] = []
	changed.assign(_terrain_changes.keys())
	_terrain_changes.clear()
	for cell: Vector3i in changed:
		var edited := WorldData.has_terrain_override(cell)
		var cut := edited or _planned_cut_blocks.has(cell) or _discovered_cave_blocks.has(cell) or _debug_cave_blocks.has(cell)
		if cut and not _visual_cut_blocks.has(cell):
			_visual_cut_blocks[cell] = true
			cavity_shell.track_cut(cell,1)
		elif not cut and _visual_cut_blocks.erase(cell): cavity_shell.track_cut(cell,-1)
		cavity_shell.forget_generated_id(cell)
	_invalidate_visual_cut_blocks(changed)

var _added_terrain: Node3D   # container: one MeshInstance3D per column
var _added_terrain_dirty := false   # full rebuild (season); edits mark _added_dirty_columns
var _added_terrain_slice := -1
var _added_meshes: Dictionary = {}          # column -> MeshInstance3D
var _added_dirty_columns: Dictionary = {}   # column -> true

## Solid final-state overrides, including both authored floor types. All writers
## use these meshes; construction retains only previews and unfinished plans.
## Full rebuild of every column with overrides or a mesh (season turns, slice
## moves); terrain edits rebuild only the columns they touch.
func _rebuild_added_terrain() -> void:
	_added_terrain_dirty = false
	_added_dirty_columns.clear()
	var columns: Dictionary = {}
	for column: Vector2i in WorldData.override_columns(): columns[column] = true
	for column: Vector2i in _added_meshes: columns[column] = true
	_rebuild_added_columns(columns.keys())


func _rebuild_added_columns(columns: Array) -> void:
	_added_terrain_slice = slice_y
	var season: String = WorldClock.season
	for column: Vector2i in columns:
		var overrides: Dictionary = WorldData.column_overrides(column.x, column.y)
		var verts := PackedVector3Array()
		var norms := PackedVector3Array()
		var colors := PackedColorArray()
		var indices := PackedInt32Array()
		for cell: Vector3i in overrides:
			var id: int = overrides[cell]
			if not BlockRegistry.is_solid(id): continue
			if _added_terrain == null:
				# Exists once any solid override does, even above the slice, so
				# slice moves (_process) rebuild it.
				_added_terrain = Node3D.new()
				_added_terrain.name = "AddedTerrain"
				add_child(_added_terrain)
			if cell.y > slice_y: continue
			var color := BlockRegistry.get_terrain_color(id, season)
			var definition := BlockRegistry.get_def(BlockRegistry.get_key(id))
			var floor_def := BlockRegistry.get_construction_def(String(definition.get("construction","")))
			for direction: Vector3i in CavityShell.SHELL_DIRS:
				var neighbour := cell+direction
				var solid := BlockRegistry.is_solid(WorldData.get_terrain_block(neighbour.x,neighbour.y,neighbour.z))
				if neighbour.y <= slice_y and solid: continue
				var cut := direction == Vector3i.UP and cell.y == slice_y and solid
				if not floor_def.is_empty():
					var patterns: Array = floor_def.get("pattern_models",[floor_def.model])
					_floor_art.append_face(String(patterns[posmod(cell.z,patterns.size())]),cell,direction,cut,verts,norms,colors,indices)
				else:
					CavityShell.add_face(cell,-direction,slice_cut_color(color) if cut else color,verts,norms,colors,indices)
		if _added_terrain != null:
			cavity_shell.apply_column_mesh(_added_meshes, _added_terrain, column, verts, norms, colors, indices)

func is_loading_complete() -> bool:
	if tiles.initial_load or cavity_shell.dirty or _added_terrain_dirty or not _terrain_changes.is_empty(): return false
	if not cavity_shell.dirty_columns.is_empty() or not _added_dirty_columns.is_empty(): return false
	if not tiles.overview_built or not tiles.dirty_overview_tiles.is_empty() or tiles.ovt_building: return false
	return _seasonal_refresh.loading_pending_count()==0 \
		and is_instance_valid(underground_lighting) and not underground_lighting.is_updating() \
		and is_instance_valid(_water_view) and _water_view.is_loading_complete()

func get_render_stats() -> Dictionary:
	return tiles.render_stats(is_loading_complete())


# ── Material ──────────────────────────────────────────────────────────────────

func _create_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness    = 1.0
	mat.metallic     = 0.0
	mat.cull_mode    = BaseMaterial3D.CULL_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	return mat
