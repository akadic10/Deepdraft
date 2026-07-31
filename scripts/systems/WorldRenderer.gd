extends Node3D

## Manages one MeshInstance3D per chunk and rebuilds meshes as chunks change.
##
## Mesh building is throttled: at most MESHES_PER_FRAME chunks are built per
## frame so the main thread stays responsive during world generation.
## Dirty chunks are queued and drained in _process().

# ── Exports ───────────────────────────────────────────────────────────────────

@export var auto_generate: bool = true
@export var world_seed: int = 0

@export var slice_y: int = 127:
	set(v):
		var old_y := slice_y
		slice_y = v
		_apply_slice_visibility()
		_enqueue_visible_existing_chunks()
		if old_y != v:
			_enqueue_regions_for_slice_change(old_y, v)
			_enqueue_overview_tiles_for_slice_change(old_y, v)
			_visible_volume_dirty = true   # VisibleVolume contract (doc 11 Phase 3)
		_begin_slice_timing(old_y, v)

## XZ chunk radius around the camera that is allowed to build terrain meshes.
## The fog in debug_world.tscn hides this streaming boundary.
@export_range(1, 64, 1) var view_radius_chunks: int = 5

## Mesh nodes farther than this XZ radius are freed. Keep this slightly larger
## than view_radius_chunks so small camera movements do not churn nodes.
@export_range(1, 80, 1) var unload_radius_chunks: int = 6

## REMOVED (slice plan doc 11): vertical_context_chunks limited meshing to the
## top chunk row per column, which made sliced/streamed views read as floating
## slabs — cliff faces below the visible row were never meshed. All rows up to
## the visible row are meshable now; the buried-skip keeps interiors free.

## Chunk meshes built per frame. Keep this conservative until the block-faithful
## overview mesh replaces full chunk rendering for high-altitude surface views.
@export var meshes_per_frame: int = 4

## While the queue is still draining the first time, build up to this many per
## frame. Once caught up we fall back to meshes_per_frame for smooth in-game edits.
@export var meshes_per_frame_initial: int = 12

## Exact full-world overview mesh — THE renderer for normal play and for every
## slice depth (doc 11 Phase SO). It emits top faces plus vertical faces where
## neighbouring columns are lower, block-accurate in geometry; cut floors show
## authored strata only (slicing never reveals undiscovered resources).
@export var use_block_face_overview: bool = true
## REMOVED (Phase SO consolidation): overview_slice_threshold used to switch to
## the streamed-bubble mode below slice 96. The sliced overview now covers all
## depths; the streamed path is dormant (set_overview_enabled).
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
## When true, each frame's batch of overview tiles is built in parallel on a
## WorkerThreadPool; the main thread only assigns the finished meshes. Set false
## to fall back to the synchronous per-tile build (e.g. to isolate a problem).
@export var overview_threaded: bool = true
## Debug (slice plan doc 11, Phase 0). When true, every slice_y change logs how
## many regions were re-enqueued and how long the rebuild queue took to drain
## (frames, wall ms, worst single frame). Quiet in normal play — nothing changes
## slice_y at runtime yet, so this only fires on inspector pokes / the slice tool.
@export var slice_debug_timing: bool = true
## When true (doc 11 Phase 1c), each frame's batch of dirty regions builds its
## mesh arrays in parallel on a WorkerThreadPool; the main thread only creates
## and assigns the ArrayMeshes. The frame cost becomes the MAX single region
## build instead of the SUM of the batch. Set false for the serial fallback.
@export var region_threaded: bool = true

# ── Internal state ────────────────────────────────────────────────────────────

const CHUNK_SIZE: int = 16
const CHUNK_COUNT_X: int = 64
const CHUNK_COUNT_Y: int = 8
const CHUNK_COUNT_Z: int = 64
const WORLD_SIZE_X: int = 1024
const WORLD_SIZE_Y: int = 128
const WORLD_SIZE_Z: int = 1024
const REGION_SIZE: int = 4
const OVERVIEW_STEP: int = 1
const OVERVIEW_TILE_SIZE: int = 32
## Luminance factor for SLICE-CUT strata floors (doc 11 Phase SO-2c): cut planes
## read as "inside the mountain", never as walkable ground. Stonehearth's number
## for de-emphasized geometry (its darkened shader family) is 0.5; theirs comes
## from fog-of-war — when Deepdraft grows visibility regions (doc 06), this
## constant folds into that multiply and dies. Luminance-only: identity untouched
## (Hard Rule 9). Tune in-engine.
const SLICE_CUT_DIM: float = 0.5
## Vertical sampling stride for cliff-side coloring. The side walk samples one
## block in this many to find color bands; at navigation zoom per-block vertical
## banding is not resolvable, so >1 cuts side-face generation calls proportionally.
var _material: StandardMaterial3D
var _overview_node: MeshInstance3D = null
var _overview_built: bool = false
var _overview_rebuild_queued: bool = false
var _overview_rock_color: Color = Color.GRAY
var _overview_sampled_top_faces: int = 0
var _overview_merged_top_faces: int = 0
var _overview_side_faces: int = 0
var _overview_validation_samples: int = 0
var _overview_validation_mismatches: int = 0
var _overview_tile_nodes: Dictionary = {}
var _overview_tile_stats: Dictionary = {}
var _dirty_overview_tiles: Array[Vector2i] = []
var _dirty_overview_tile_set: Dictionary = {}
var _visual_cut_blocks: Dictionary = {}
## MINED blocks (doc 11 Phase SO-2b) — a strict subset of _visual_cut_blocks.
## Under Option A (defect 2, 2026-06-05) designations and mined holes BOTH punch
## side bands and render in the cavity shell; this set only selects the shell's
## colour source — mined → exact generated id (mining reveals), designated →
## authored strata (a plan reveals nothing). Producer today: the DEV
## instant-mine tool; later: real mining execution.
var _mined_blocks: Dictionary = {}
# Immutable mined-set snapshot for the threaded overview build (same pattern as
# _ovt_cut): the cut-floor colour rule (defects 3/4) reads it on worker threads.
var _ovt_mined: Dictionary = {}
var _cavity_shell_node: MeshInstance3D = null
## Coalesced-rebuild flag: every shell-shaping event (cut/mined block changes,
## slice moves, season turns, grass bands) marks dirty; _process drains it into
## at most ONE _rebuild_cavity_shell() per frame. Real mining commits one block
## per swing — rebuilding synchronously per commit made block N cost O(N) (and
## save-restore O(N²)); coalescing caps it at one rebuild per frame no matter
## the batch size.
var _cavity_shell_dirty: bool = false
## Memoised WorldGenerator id lookups for shell neighbour blocks. Generated ids
## are deterministic and immutable for the lifetime of a world (the seed never
## changes within a scene; a load reloads the scene and this node with it), so
## entries never go stale — with one exception: ids sampled during the
## grass-band gate window may hold fallback grass, so _on_grass_bands_ready
## clears both caches. Turns steady-state shell rebuilds from 3D-noise sampling
## per face into dictionary hits.
var _shell_exact_ids: Dictionary = {}    # Vector3i -> int (exact generated id)
var _shell_strata_ids: Dictionary = {}   # Vector3i -> int (authored strata id)
## Chunk coords (Vector3i) → count of visual-cut blocks inside. Lets the
## buried-skip exempt chunks that mining has carved into (their cavity faces
## must mesh even though the chunk data itself is all-solid).
var _cut_chunks: Dictionary = {}
# Immutable cut-block snapshot read by the overview build (incl. worker threads).
# Set on the main thread before each drain so workers never read the live
# _visual_cut_blocks while mining could mutate it.
var _ovt_cut: Dictionary = {}
# Group-task scratch for the threaded overview build (main thread sets these
# before dispatch; workers read _ovt_batch/_ovt_season read-only and write their
# own disjoint _ovt_results slot).
var _ovt_batch: Array[Vector2i] = []
var _ovt_results: Array = []
var _ovt_season: String = ""
# Per-section profiling accumulators (usec), only written when overview_profile.
var _ovp_loop_usec: int = 0
var _ovp_sides_usec: int = 0
var _ovp_merge_usec: int = 0
var _ovp_mesh_usec: int = 0
var _ovp_tiles: int = 0
var _ovp_max_tile_usec: int = 0
var _ovp_max_tile_key: Vector2i = Vector2i(-1, -1)
var _ovp_max_breakdown: Dictionary = {}
var _region_nodes: Dictionary = {}
var _chunk_nodes: Dictionary = {}   # Vector3i → MeshInstance3D

## Pending rebuild queue. _on_chunk_dirtied enqueues; _process drains.
var _dirty_queue: Array[Vector3i] = []
var _dirty_region_queue: Array[Vector2i] = []
var _dirty_region_set: Dictionary = {}
var _dirty_set:   Dictionary      = {}   # Vector3i → true  (dedup guard)

var _signals_received: int = 0
var _meshes_built: int = 0
var _startup_started_msec: int = 0
var _first_visible_mesh_msec: int = 0
var _region_rebuild_msec_total: int = 0
var _region_rebuild_msec_max: int = 0
var _region_rebuild_count: int = 0
var _overview_build_msec_total: int = 0
var _overview_build_msec_max: int = 0
var _overview_build_count: int = 0
var _overview_startup_tile_goal: int = 0
var _overview_startup_center: Vector2i = Vector2i(-1, -1)
var _overview_startup_ready_msec: int = 0
var _overview_complete_msec: int = 0
var _startup_report_printed: bool = false

## True until the world finishes generating AND the initial mesh queue drains.
## While true, _process builds at the faster meshes_per_frame_initial rate.
var _initial_load: bool = true

# Group-task scratch for the threaded region build (doc 11 Phase 1c). The main
# thread fills _rgn_batch, dispatches, and BLOCKS until the batch completes, so
# workers read shared state (slice_y, _visual_cut_blocks, _camera_chunk, the
# WorldGenerator maps) without it mutating mid-build; each worker writes only
# its own _rgn_results slot. WorldData reads are mutex-guarded.
var _rgn_batch: Array[Vector2i] = []
var _rgn_results: Array = []

# ── Slice-change timing instrumentation (doc 11 Phase 0; gated by slice_debug_timing) ──
var _slice_timing_active: bool = false
var _slice_timing_start_msec: int = 0
var _slice_timing_from: int = 0
var _slice_timing_to: int = 0
var _slice_timing_regions_enqueued: int = 0
var _slice_timing_frames: int = 0
var _slice_timing_max_frame_ms: int = 0
var _slice_timing_rebuilds_at_start: int = 0

var _camera_rig: Camera = null
var _camera_chunk: Vector2i = Vector2i(-9999, -9999)
var _inspector_layer: CanvasLayer = null
var _inspector_panel: PanelContainer = null
var _inspector_label: Label = null
var _inspector_outline: MeshInstance3D = null
var _inspector_dragging: bool = false


# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	# All chunk positions are in world-space block coordinates (cx*16, cy*16, cz*16).
	# The Renderer node MUST sit at world origin or every mesh will be displaced.
	if global_position != Vector3.ZERO:
		push_warning("WorldRenderer: node was not at origin (%s) — resetting." % str(global_position))
	global_position = Vector3.ZERO
	global_rotation = Vector3.ZERO
	scale           = Vector3.ONE

	_material = _create_material()
	_build_block_inspector_ui()

	# No CONNECT_DEFERRED — signal is already emitted on the main thread
	# via WorldData._deferred_emit_chunk_dirtied, so immediate connection is safe.
	WorldData.chunk_dirtied.connect(_on_chunk_dirtied)

	# Grass bands are computed after maps_ready, so the first overview tiles are
	# meshed with fallback grass. When the bands finish, re-mesh the already-built
	# overview tiles in place so the band tiers appear (no node free => no flicker).
	# Emitted on the main thread, so immediate connection is safe.
	WorldGenerator.grass_bands_ready.connect(_on_grass_bands_ready)

	# Seasonal surface palettes (surface_palettes.json) are baked into vertex colours at
	# mesh-build time, so when the season turns we re-mesh whatever is currently built —
	# same in-place, no-flicker pattern as _on_grass_bands_ready().
	WorldClock.season_changed.connect(_on_season_changed)

	_camera_rig = _find_camera(get_tree().current_scene)
	if _camera_rig != null and not _block_face_overview_active():
		_update_streaming_center()

	# Auto-create the camera rig if one isn't already in the scene.
	# Uses call_deferred so the full scene tree is ready before we add to it.
	call_deferred("_setup_camera_rig")

	if auto_generate:
		_startup_started_msec = Time.get_ticks_msec()
		var generation_seed := world_seed
		if SaveManager != null:
			generation_seed = SaveManager.generation_seed_for_new_scene(world_seed)
		WorldGenerator.generate(generation_seed)
		if not _block_face_overview_active():
			_enqueue_visible_existing_chunks()
		print("WorldRenderer: generation started (seed %d)." % WorldGenerator.world_seed)


func _process(_delta: float) -> void:
	# VisibleVolume contract (doc 11 Phase 3, ref doc 10 rule S5): flush at most
	# ONE visible_volume_changed per frame, before either render branch runs, so
	# consumers rebuild reactively and never poll. Any number of state changes in
	# a frame collapse to a single emission.
	if _visible_volume_dirty:
		_visible_volume_dirty = false
		visible_volume_changed.emit()
		_cavity_shell_dirty = true   # re-clip cavity faces against the new plane (SO-2b)

	# Drain the coalesced shell flag BEFORE the overview early-return so both
	# render branches get the rebuild; any number of same-frame shell mutations
	# (mining commits, slice moves, restore batches) collapse to one build.
	if _cavity_shell_dirty:
		_cavity_shell_dirty = false
		_rebuild_cavity_shell()

	if _block_face_overview_active():
		# Stamp unconditionally — timing can begin between frames, and a zero
		# stamp poisoned the worst-frame stat (measured against engine start).
		var t_frame_ov := Time.get_ticks_msec()
		_update_block_face_overview()
		if _slice_timing_active:
			_update_slice_timing(t_frame_ov)
		return

	_update_streaming_center()
	_prune_dirty_queue()

	# Drain fast during the initial bulk load (nothing else needs the frame yet),
	# then settle to the smooth in-game rate once caught up.
	var budget := meshes_per_frame_initial if _initial_load else meshes_per_frame

	# Stamp unconditionally (see the overview branch note above).
	var t_frame := Time.get_ticks_msec()

	# Pull this frame's batch off the dirty queue, skipping out-of-radius keys
	# and DEFERRING regions whose columns are still streaming in (Phase 1e) —
	# each completing column re-dirties its region anyway, so rebuilding early
	# is pure waste (the Phase-0 cold run rebuilt regions up to ~16x this way).
	# Deferred regions are requeued at the tail, never dropped, so a rare race
	# with the generator's completion bookkeeping only delays them one frame.
	# The scan is bounded to one pass over the queue so pending regions cannot
	# starve ready ones behind them.
	_rgn_batch.clear()
	var scan_limit := _dirty_region_queue.size()
	var scanned := 0
	while _dirty_region_queue.size() > 0 and _rgn_batch.size() < budget and scanned < scan_limit:
		scanned += 1
		var key: Vector2i = _dirty_region_queue.pop_front()
		_dirty_region_set.erase(key)
		if not _region_should_exist(key):
			continue
		# Defer REbuilds only: a region with no mesh yet builds immediately from
		# whatever columns exist (progressive fill, no holes while streaming);
		# once it has a mesh, further rebuilds wait until its columns settle —
		# one final rebuild instead of one per completing column (~2 total).
		if _region_nodes.has(key) and _region_has_pending_columns(key):
			_enqueue_region(key)
			continue
		_rgn_batch.append(key)
	var built := _rgn_batch.size()

	if not _rgn_batch.is_empty():
		if region_threaded and _rgn_batch.size() > 1:
			# Build all regions of the batch in parallel; assign meshes after.
			_rgn_results.clear()
			_rgn_results.resize(_rgn_batch.size())
			var task_id := WorkerThreadPool.add_group_task(
				Callable(self, "_region_build_worker"), _rgn_batch.size(), -1, false, "region_meshes")
			WorkerThreadPool.wait_for_group_task_completion(task_id)
			for i in range(_rgn_batch.size()):
				_assign_region_mesh(_rgn_batch[i], _rgn_results[i])
			_rgn_results.clear()
		else:
			for key: Vector2i in _rgn_batch:
				_rebuild_region(key)
		_rgn_batch.clear()

	if _slice_timing_active:
		_update_slice_timing(t_frame)

	# Leave initial-load mode once generation is done and the queue is empty.
	if _initial_load and _dirty_region_queue.is_empty() and not WorldGenerator.is_generating():
		_initial_load = false
		print("WorldRenderer: initial load complete — %d meshes built." % _meshes_built)
		_print_startup_performance_report()

	if built > 0:
		_meshes_built += built
		if _meshes_built <= budget or _meshes_built % 256 == 0:
			print("WorldRenderer: built %d region meshes total, queue=%d." % [_meshes_built, _dirty_region_queue.size()])


func _unhandled_input(event: InputEvent) -> void:
	if _inspector_layer == null or not _inspector_layer.visible:
		return
	if event is InputEventMouseButton:
		var mbe := event as InputEventMouseButton
		if mbe.pressed and mbe.button_index == MOUSE_BUTTON_LEFT:
			_inspect_block_at_screen_position(mbe.position)


# -- Block inspector ----------------------------------------------------------

func _build_block_inspector_ui() -> void:
	_inspector_layer = CanvasLayer.new()
	_inspector_layer.name = "BlockInspector"
	add_child(_inspector_layer)
	_inspector_layer.visible = false
	_inspector_layer.visibility_changed.connect(_on_inspector_visibility_changed)

	_inspector_panel = PanelContainer.new()
	_inspector_panel.name = "Panel"
	_inspector_panel.position = Vector2(48.0, 128.0)
	_inspector_panel.custom_minimum_size = Vector2(420.0, 270.0)
	_inspector_panel.add_theme_stylebox_override("panel", _inspector_window_style())
	_inspector_layer.add_child(_inspector_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 1)
	margin.add_theme_constant_override("margin_right", 1)
	margin.add_theme_constant_override("margin_top", 1)
	margin.add_theme_constant_override("margin_bottom", 1)
	_inspector_panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	margin.add_child(column)

	var title_bar := PanelContainer.new()
	title_bar.name = "TitleBar"
	title_bar.custom_minimum_size = Vector2(0.0, 34.0)
	title_bar.mouse_default_cursor_shape = Control.CURSOR_MOVE
	title_bar.add_theme_stylebox_override("panel", _inspector_title_bar_style())
	title_bar.gui_input.connect(_on_inspector_title_bar_gui_input)
	column.add_child(title_bar)

	var title_margin := MarginContainer.new()
	title_margin.add_theme_constant_override("margin_left", 10)
	title_margin.add_theme_constant_override("margin_right", 8)
	title_margin.add_theme_constant_override("margin_top", 4)
	title_margin.add_theme_constant_override("margin_bottom", 4)
	title_bar.add_child(title_margin)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	title_margin.add_child(header)

	var title := Label.new()
	title.text = "Block Inspector"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 15)
	header.add_child(title)

	var close := Button.new()
	close.name = "CloseButton"
	close.text = "X"
	close.custom_minimum_size = Vector2(28.0, 24.0)
	close.focus_mode = Control.FOCUS_NONE
	close.tooltip_text = "Close"
	close.add_theme_font_size_override("font_size", 13)
	close.add_theme_stylebox_override("normal", _inspector_close_button_style(Color(0.58, 0.08, 0.08, 0.95)))
	close.add_theme_stylebox_override("hover", _inspector_close_button_style(Color(0.78, 0.10, 0.10, 1.0)))
	close.add_theme_stylebox_override("pressed", _inspector_close_button_style(Color(0.42, 0.04, 0.04, 1.0)))
	close.pressed.connect(func() -> void:
		_inspector_layer.visible = false
		if _inspector_outline != null:
			_inspector_outline.visible = false
	)
	header.add_child(close)

	var body_margin := MarginContainer.new()
	body_margin.add_theme_constant_override("margin_left", 10)
	body_margin.add_theme_constant_override("margin_right", 10)
	body_margin.add_theme_constant_override("margin_top", 8)
	body_margin.add_theme_constant_override("margin_bottom", 10)
	column.add_child(body_margin)

	_inspector_label = Label.new()
	_inspector_label.name = "Details"
	_inspector_label.add_theme_font_size_override("font_size", 13)
	_inspector_label.text = "Block inspector\nclick a block"
	body_margin.add_child(_inspector_label)
	_build_block_inspector_outline()


func _on_inspector_title_bar_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_LEFT:
			_inspector_dragging = mouse.pressed
	elif event is InputEventMouseMotion and _inspector_dragging:
		var motion := event as InputEventMouseMotion
		_inspector_panel.position += motion.relative


func _on_inspector_visibility_changed() -> void:
	if _inspector_layer != null and not _inspector_layer.visible and _inspector_outline != null:
		_inspector_outline.visible = false


func _inspector_window_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.070, 0.075, 0.080, 0.92)
	style.border_color = Color(1, 1, 1, 0.16)
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 7
	style.corner_radius_top_right = 7
	style.corner_radius_bottom_left = 7
	style.corner_radius_bottom_right = 7
	return style


func _inspector_title_bar_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.13, 0.14, 0.98)
	style.corner_radius_top_left = 7
	style.corner_radius_top_right = 7
	return style


func _inspector_close_button_style(bg: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = Color(1.0, 0.45, 0.45, 0.50)
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 5
	style.corner_radius_top_right = 5
	style.corner_radius_bottom_left = 5
	style.corner_radius_bottom_right = 5
	style.content_margin_left = 6.0
	style.content_margin_right = 6.0
	return style


func _build_block_inspector_outline() -> void:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	mesh.surface_set_color(Color.YELLOW)

	var corners := [
		Vector3(0, 0, 0),
		Vector3(1, 0, 0),
		Vector3(1, 1, 0),
		Vector3(0, 1, 0),
		Vector3(0, 0, 1),
		Vector3(1, 0, 1),
		Vector3(1, 1, 1),
		Vector3(0, 1, 1),
	]
	var edges := [
		[0, 1], [1, 2], [2, 3], [3, 0],
		[4, 5], [5, 6], [6, 7], [7, 4],
		[0, 4], [1, 5], [2, 6], [3, 7],
	]
	for edge: Array in edges:
		mesh.surface_add_vertex(corners[edge[0] as int])
		mesh.surface_add_vertex(corners[edge[1] as int])
	mesh.surface_end()

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color.YELLOW
	material.vertex_color_use_as_albedo = true
	material.no_depth_test = true

	_inspector_outline = MeshInstance3D.new()
	_inspector_outline.name = "BlockInspectorOutline"
	_inspector_outline.mesh = mesh
	_inspector_outline.material_override = material
	_inspector_outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_inspector_outline.visible = false
	add_child(_inspector_outline)


func _inspect_block_at_screen_position(screen_pos: Vector2) -> void:
	if _camera_rig == null:
		_camera_rig = _find_camera(get_tree().current_scene)
	if _camera_rig == null or _camera_rig.camera_node == null:
		_set_inspector_text("Block inspector\nno camera")
		return

	var camera := _camera_rig.camera_node
	var origin := camera.project_ray_origin(screen_pos)
	var direction := camera.project_ray_normal(screen_pos).normalized()
	var hit := _find_block_on_ray(origin, direction, camera.far)
	if hit.is_empty():
		_set_inspector_text("Block inspector\nno block hit")
		return

	var pos: Vector3i = hit["pos"]
	var block_id: int = hit["block_id"]
	var generated_block_id: int = hit.get("generated_block_id", block_id)
	var source: String = hit.get("source", "unknown")
	var face: String = hit.get("face", "unknown")
	var key_name := BlockRegistry.get_key(block_id)
	var key := String(key_name)
	var def := BlockRegistry.get_def(key_name)
	var kind: String = def.get("kind", "unknown")
	var generated_key := String(BlockRegistry.get_key(generated_block_id))
	var season: String = WorldClock.season
	var color := BlockRegistry.get_color(block_id, season)
	var column_info: Dictionary = WorldGenerator.get_column_debug_info(pos.x, pos.z) if WorldGenerator.has_method("get_column_debug_info") else {}
	var visible_key: String = column_info.get("visible_block_key", "")
	var agreement: String = "yes" if generated_block_id == block_id else "NO"
	_move_block_inspector_outline(pos)
	_set_inspector_text("\n".join([
		"Block inspector",
		"render: %s" % _inspector_render_mode(),
		"source: %s  face: %s" % [source, face],
		"hit: %s" % key,
		"generated: %s  agree: %s" % [generated_key, agreement],
		"visible top: y %d  %s" % [
			column_info.get("visible_surface_y", -1),
			visible_key,
		],
		"domain: %s %.3f  surface y: %d" % [
			column_info.get("domain", "unknown"),
			column_info.get("domain_n", 0.0),
			column_info.get("surface_y", -1),
		],
		"height band: %s" % column_info.get("height_band", "unknown"),
		"lowland cap grass: band %d  distance %d" % [
			column_info.get("lowland_cap_grass_band", 0),
			column_info.get("lowland_cap_grass_distance", -1),
		],
		"foothill cap grass: band %d  distance %d" % [
			column_info.get("foothill_cap_grass_band", 0),
			column_info.get("foothill_cap_grass_distance", -1),
		],
		"water: lake %s  tarn %s  bank %s" % [
			str(column_info.get("is_lake", false)),
			str(column_info.get("is_tarn", false)),
			str(column_info.get("is_water_bank", false)),
		],
		"kind: %s  color: %s" % [kind, color.to_html(false)],
		"x: %d  y: %d  z: %d" % [pos.x, pos.y, pos.z],
	]))


func _find_block_on_ray(origin: Vector3, direction: Vector3, max_distance: float) -> Dictionary:
	var step := 0.25
	var distance := 0.0
	var last_pos := Vector3i(-999999, -999999, -999999)
	var last_empty_pos := last_pos
	while distance <= max_distance:
		var sample := origin + direction * distance
		var pos := Vector3i(floori(sample.x), floori(sample.y), floori(sample.z))
		if pos != last_pos:
			var prev_pos := last_pos
			last_pos = pos
			var hit_info := _inspect_block_id(pos)
			var block_id: int = hit_info.get("block_id", BlockRegistry.AIR_ID)
			if BlockRegistry.is_transparent(block_id):
				last_empty_pos = pos
			else:
				return {
					"pos": pos,
					"block_id": block_id,
					"generated_block_id": hit_info.get("generated_block_id", block_id),
					"source": hit_info.get("source", "unknown"),
					"face": _hit_face_label(pos - last_empty_pos if last_empty_pos != Vector3i(-999999, -999999, -999999) else pos - prev_pos),
				}
		distance += step
	return {}


func _inspect_block_id(pos: Vector3i) -> Dictionary:
	if pos.x < 0 or pos.x >= WORLD_SIZE_X or pos.y < 0 or pos.y >= WORLD_SIZE_Y or pos.z < 0 or pos.z >= WORLD_SIZE_Z:
		return {"block_id": BlockRegistry.AIR_ID, "generated_block_id": BlockRegistry.AIR_ID, "source": "out_of_bounds"}
	if pos.y > slice_y:
		return {"block_id": BlockRegistry.AIR_ID, "generated_block_id": BlockRegistry.AIR_ID, "source": "above_slice"}

	var generated_block_id := BlockRegistry.AIR_ID
	if WorldGenerator.has_method("get_generated_block_id"):
		generated_block_id = WorldGenerator.get_generated_block_id(pos.x, pos.y, pos.z)
	var block_id := WorldData.get_block(pos.x, pos.y, pos.z)
	if not BlockRegistry.is_transparent(block_id):
		return {"block_id": block_id, "generated_block_id": generated_block_id, "source": "streamed_chunk"}
	return {"block_id": generated_block_id, "generated_block_id": generated_block_id, "source": _fallback_source_label(pos)}


func _fallback_source_label(pos: Vector3i) -> String:
	if _block_face_overview_active():
		return "overview_generated"
	if WorldData.chunk_exists(
			int(floor(float(pos.x) / float(CHUNK_SIZE))),
			int(floor(float(pos.y) / float(CHUNK_SIZE))),
			int(floor(float(pos.z) / float(CHUNK_SIZE)))):
		return "generated_fallback"
	return "unstreamed_generated"


func _inspector_render_mode() -> String:
	if _block_face_overview_active():
		return "block-face overview exact"
	return "composited: streamed chunks + sliced overview"


func set_visual_cut_blocks(blocks: Dictionary) -> void:
	_visual_cut_blocks = blocks.duplicate()
	_cut_chunks.clear()
	for block: Vector3i in _visual_cut_blocks.keys():
		_track_cut_chunk(block, 1)
	_invalidate_visual_cut_meshes_global()


func add_visual_cut_blocks(blocks: Array[Vector3i]) -> void:
	var changed: Array[Vector3i] = []
	for block: Vector3i in blocks:
		if _visual_cut_blocks.has(block):
			continue
		_visual_cut_blocks[block] = true
		_track_cut_chunk(block, 1)
		changed.append(block)
	_invalidate_visual_cut_blocks(changed)


func remove_visual_cut_blocks(blocks: Array[Vector3i]) -> void:
	var changed: Array[Vector3i] = []
	for block: Vector3i in blocks:
		if not _visual_cut_blocks.has(block):
			continue
		_visual_cut_blocks.erase(block)
		_track_cut_chunk(block, -1)
		changed.append(block)
	_invalidate_visual_cut_blocks(changed)


# ── Mined cavities (doc 11 Phase SO-2b) ───────────────────────────────────────

## Marks blocks as MINED — real holes, not designation plans. Mined blocks stay
## in (or join) the visual-cut set, so the top-deduction path is unchanged; in
## addition their wall side-bands punch open (overview tile re-mesh via the
## standard cut invalidation) and the cavity shell grows. There is no removal
## path — mining is permanent until real execution defines restoration.
func add_mined_blocks(blocks: Array[Vector3i]) -> void:
	var changed: Array[Vector3i] = []
	for block: Vector3i in blocks:
		if _mined_blocks.has(block):
			continue
		_mined_blocks[block] = true
		changed.append(block)
		if not _visual_cut_blocks.has(block):
			_visual_cut_blocks[block] = true
			_track_cut_chunk(block, 1)
	if changed.is_empty():
		return
	_invalidate_visual_cut_blocks(changed)   # re-punches tiles + rebuilds the shell


const _SHELL_DIRS: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 1, 0), Vector3i(0, -1, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]


## Rebuilds the cavity-shell mesh (doc 11 SO-2b + defect fixes 2026-06-05):
## for every ENCLOSED cavity block — designated or mined — render the faces of
## adjacent SOLID blocks (floor/ceiling/back walls).
##
## Defect-1 rule: a cavity block ABOVE its column's cut-aware effective top is
## open-from-above — the overview already expresses it (lowered top plate +
## side bands) and drawing it again z-fights. The shell renders only blocks
## with solid rock above (true interiors).
##
## Defect-2 / Option A rule: colour per cavity-block source — MINED → exact
## generated id (mining legitimately reveals, Hard Rule 11); DESIGNATED →
## authored strata id (a plan reveals nothing; reads as a ghost preview under
## the yellow zone overlay).
##
## Skips: cavity-continuation neighbours, faces above the slice plane, world
## edges, and naturally-void neighbours (cave adjacency — discovery rendering
## is a future decision). Full rebuild — trivial at DEV scale; per-chunk nodes
## are the scale path when real mining lands (X0's 3×3×3 dirty rule).
func _rebuild_cavity_shell() -> void:
	if _cavity_shell_node == null:
		_cavity_shell_node = MeshInstance3D.new()
		_cavity_shell_node.name = "CavityShell"
		_cavity_shell_node.material_override = _material
		_cavity_shell_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_cavity_shell_node)

	if _visual_cut_blocks.is_empty():
		_cavity_shell_node.mesh = null
		return

	var verts: PackedVector3Array = []
	var norms: PackedVector3Array = []
	var cols: PackedColorArray = []
	var indices: PackedInt32Array = []
	var season: String = WorldClock.season
	var col_tops: Dictionary = {}   # per-rebuild cache: Vector2i -> effective top

	for block: Vector3i in _visual_cut_blocks.keys():
		if block.y > slice_y:
			continue   # cavity above the plane — hidden with everything else
		if block.y > _cavity_column_top(block.x, block.z, col_tops):
			continue   # open-from-above — the overview's job (defect 1)
		var mined := _mined_blocks.has(block)
		for dir: Vector3i in _SHELL_DIRS:
			var n: Vector3i = block + dir
			if _visual_cut_blocks.has(n):
				continue   # open continuation of the cavity (plan or hole)
			if n.y > slice_y:
				continue   # never draw above the plane
			if n.x < 0 or n.x >= WORLD_SIZE_X \
					or n.y < 0 or n.y >= WORLD_SIZE_Y \
					or n.z < 0 or n.z >= WORLD_SIZE_Z:
				continue   # world edge
			# Memoised: generated ids are deterministic per world (see the
			# _shell_exact_ids declaration), so repeat rebuilds hit the dict
			# instead of re-sampling 3D noise per face.
			var exact_id: int
			if _shell_exact_ids.has(n):
				exact_id = _shell_exact_ids[n]
			else:
				exact_id = WorldGenerator.get_generated_block_id(n.x, n.y, n.z)
				_shell_exact_ids[n] = exact_id
			if BlockRegistry.is_transparent(exact_id):
				continue   # natural air/cave — nothing to show (yet)
			var display_id: int
			if mined:
				display_id = exact_id
			elif _shell_strata_ids.has(n):
				display_id = _shell_strata_ids[n]
			else:
				display_id = WorldGenerator.get_overview_strata_block_id(n.x, n.y, n.z)
				_shell_strata_ids[n] = display_id
			_add_shell_face(n, dir, BlockRegistry.get_color(display_id, season), verts, norms, cols, indices)

	if verts.is_empty():
		_cavity_shell_node.mesh = null
		return

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_cavity_shell_node.mesh = mesh


## Cut-aware effective top of a column (cached per shell rebuild): walk down
## from min(visible surface, slice plane) through cut blocks — the first solid
## block is the floor of the open pocket. Cavity blocks ABOVE this value are
## open-from-above (overview territory); blocks BELOW it are enclosed and get
## shell faces. Returns -1 while the generator maps are not ready (everything
## then counts as open — there can be no cavities before maps exist).
func _cavity_column_top(wx: int, wz: int, col_tops: Dictionary) -> int:
	var key := Vector2i(wx, wz)
	if col_tops.has(key):
		return col_tops[key]
	var wy := int(WorldGenerator.get_visible_surface_y(wx, wz))
	if wy < 0:
		col_tops[key] = -1
		return -1
	wy = mini(wy, slice_y)
	while wy >= 0 and _visual_cut_blocks.has(Vector3i(wx, wy, wz)):
		wy -= 1
	col_tops[key] = wy
	return wy


## Emits solid block n's face pointing back toward the cavity (normal = -dir,
## where dir is cavity→n). Corner tables and reversed winding match
## ChunkMesher._add_quad so the face renders from inside the cavity.
func _add_shell_face(
		n: Vector3i,
		dir: Vector3i,
		color: Color,
		verts: PackedVector3Array,
		norms: PackedVector3Array,
		cols: PackedColorArray,
		indices: PackedInt32Array) -> void:

	var ox := float(n.x)
	var oy := float(n.y)
	var oz := float(n.z)
	var v0: Vector3
	var v1: Vector3
	var v2: Vector3
	var v3: Vector3

	# dir points cavity→n, so the face we draw is n's face with normal -dir.
	if dir == Vector3i(-1, 0, 0):      # n is -X of cavity → n's +X face
		v0 = Vector3(ox + 1, oy, oz)
		v1 = Vector3(ox + 1, oy + 1, oz)
		v2 = Vector3(ox + 1, oy + 1, oz + 1)
		v3 = Vector3(ox + 1, oy, oz + 1)
	elif dir == Vector3i(1, 0, 0):     # n's -X face
		v0 = Vector3(ox, oy, oz + 1)
		v1 = Vector3(ox, oy + 1, oz + 1)
		v2 = Vector3(ox, oy + 1, oz)
		v3 = Vector3(ox, oy, oz)
	elif dir == Vector3i(0, -1, 0):    # n below cavity → n's +Y face (the floor)
		v0 = Vector3(ox, oy + 1, oz)
		v1 = Vector3(ox, oy + 1, oz + 1)
		v2 = Vector3(ox + 1, oy + 1, oz + 1)
		v3 = Vector3(ox + 1, oy + 1, oz)
	elif dir == Vector3i(0, 1, 0):     # n above cavity → n's -Y face (the ceiling)
		v0 = Vector3(ox + 1, oy, oz)
		v1 = Vector3(ox + 1, oy, oz + 1)
		v2 = Vector3(ox, oy, oz + 1)
		v3 = Vector3(ox, oy, oz)
	elif dir == Vector3i(0, 0, -1):    # n's +Z face
		v0 = Vector3(ox + 1, oy, oz + 1)
		v1 = Vector3(ox + 1, oy + 1, oz + 1)
		v2 = Vector3(ox, oy + 1, oz + 1)
		v3 = Vector3(ox, oy, oz + 1)
	else:                              # n's -Z face
		v0 = Vector3(ox, oy, oz)
		v1 = Vector3(ox, oy + 1, oz)
		v2 = Vector3(ox + 1, oy + 1, oz)
		v3 = Vector3(ox + 1, oy, oz)

	var normal := Vector3(-dir.x, -dir.y, -dir.z)
	var base := verts.size()
	verts.push_back(v0); verts.push_back(v1)
	verts.push_back(v2); verts.push_back(v3)
	for i in range(4):
		norms.push_back(normal)
		cols.push_back(color)
	# Reversed winding (see ChunkMesher._add_quad).
	indices.push_back(base); indices.push_back(base + 2); indices.push_back(base + 1)
	indices.push_back(base); indices.push_back(base + 3); indices.push_back(base + 2)


func _track_cut_chunk(block: Vector3i, delta: int) -> void:
	var key := Vector3i(
		floori(float(block.x) / float(CHUNK_SIZE)),
		floori(float(block.y) / float(CHUNK_SIZE)),
		floori(float(block.z) / float(CHUNK_SIZE)))
	var count := int(_cut_chunks.get(key, 0)) + delta
	if count > 0:
		_cut_chunks[key] = count
	else:
		_cut_chunks.erase(key)


func _invalidate_visual_cut_blocks(blocks: Array[Vector3i]) -> void:
	if blocks.is_empty():
		return
	_cavity_shell_dirty = true   # designations and mined holes both shape the shell (SO-2b A)
	if _block_face_overview_active():
		_enqueue_overview_tiles_for_blocks(blocks)
		return
	_enqueue_regions_for_cut_blocks(blocks)


func _invalidate_visual_cut_meshes_global() -> void:
	_cavity_shell_dirty = true
	_invalidate_overview_global()
	if _block_face_overview_active():
		return
	for key: Vector2i in _region_nodes.keys():
		_enqueue_region(key)
	_enqueue_visible_existing_chunks()


func _hit_face_label(delta: Vector3i) -> String:
	if delta.x > 0:
		return "west"
	if delta.x < 0:
		return "east"
	if delta.y > 0:
		return "bottom"
	if delta.y < 0:
		return "top"
	if delta.z > 0:
		return "north"
	if delta.z < 0:
		return "south"
	return "unknown"


func _set_inspector_text(text: String) -> void:
	if _inspector_label != null:
		_inspector_label.text = text


func _move_block_inspector_outline(pos: Vector3i) -> void:
	if _inspector_outline == null:
		return
	_inspector_outline.global_position = Vector3(float(pos.x), float(pos.y), float(pos.z))
	_inspector_outline.visible = true


# ── Signal handlers ───────────────────────────────────────────────────────────

func _on_chunk_dirtied(cx: int, cy: int, cz: int) -> void:
	_signals_received += 1
	if _signals_received == 1:
		print("WorldRenderer: first chunk_dirtied received (%d,%d,%d)." % [cx, cy, cz])
	if _block_face_overview_active():
		return
	if not _chunk_should_be_meshed(cx, cy, cz):
		return
	_enqueue_region_for_chunk(cx, cz)


func _enqueue_chunk(key: Vector3i) -> void:
	if not _dirty_set.has(key):
		_dirty_set[key] = true
		_dirty_queue.append(key)


# ── Mesh management ───────────────────────────────────────────────────────────

func _rebuild_chunk(cx: int, cy: int, cz: int) -> void:
	var key   := Vector3i(cx, cy, cz)
	var chunk := WorldData.get_chunk_if_exists(cx, cy, cz)
	if chunk == null:
		_free_chunk_node(key)
		return

	# Fully-buried skip: a solid chunk (no void of its own) whose six neighbours
	# are also all solid can emit no visible faces. Skip the expensive mesh
	# build entirely. Cheap has_void flags, set at generation time, drive this.
	# NOTE: only valid when the chunk is entirely below the slice plane — a
	# buried chunk that the plane cuts through must still mesh its cut floor.
	if not chunk.has_void and _is_buried(cx, cy, cz) and (cy + 1) * CHUNK_SIZE - 1 < slice_y:
		_free_chunk_node(key)
		return

	var mesh  := ChunkMesher.build_mesh(chunk, cx, cy, cz, _visual_cut_blocks, slice_y)

	if mesh == null:
		_free_chunk_node(key)
		return

	var mi := _get_or_create_node(key, cx, cy, cz)
	mi.mesh    = mesh
	mi.visible = _chunk_should_be_meshed(cx, cy, cz)
	if _chunk_nodes.size() == 1:
		print("WorldRenderer: first solid mesh at world pos %s (chunk %d,%d,%d)." % [str(mi.global_position), cx, cy, cz])


## True if this chunk or any of its six direct neighbours contains visual-cut
## blocks — such chunks are exempt from the buried-skip because mining cavities
## expose faces in them. O(7) dictionary lookups; worker-safe (read-only during
## a batch, the main thread blocks while workers run).
func _cut_chunk_nearby(cx: int, cy: int, cz: int) -> bool:
	return _cut_chunks.has(Vector3i(cx, cy, cz)) \
		or _cut_chunks.has(Vector3i(cx + 1, cy, cz)) \
		or _cut_chunks.has(Vector3i(cx - 1, cy, cz)) \
		or _cut_chunks.has(Vector3i(cx, cy + 1, cz)) \
		or _cut_chunks.has(Vector3i(cx, cy - 1, cz)) \
		or _cut_chunks.has(Vector3i(cx, cy, cz + 1)) \
		or _cut_chunks.has(Vector3i(cx, cy, cz - 1))


## True when all six neighbour chunks are solid (contain no void). A missing
## neighbour counts as void (air), so edge/surface chunks are never "buried".
## NOTE: when mining is added, set_block must dirty the neighbouring chunk on a
## chunk-boundary edit so a previously-buried chunk gets re-meshed once exposed.
func _is_buried(cx: int, cy: int, cz: int) -> bool:
	return not WorldData.chunk_has_void(cx + 1, cy, cz) \
		and not WorldData.chunk_has_void(cx - 1, cy, cz) \
		and not WorldData.chunk_has_void(cx, cy + 1, cz) \
		and not WorldData.chunk_has_void(cx, cy - 1, cz) \
		and not WorldData.chunk_has_void(cx, cy, cz + 1) \
		and not WorldData.chunk_has_void(cx, cy, cz - 1)


func _get_or_create_node(key: Vector3i, cx: int, cy: int, cz: int) -> MeshInstance3D:
	if _chunk_nodes.has(key):
		return _chunk_nodes[key] as MeshInstance3D

	var mi := MeshInstance3D.new()
	mi.position          = Vector3(cx * CHUNK_SIZE, cy * CHUNK_SIZE, cz * CHUNK_SIZE)
	mi.material_override = _material
	mi.cast_shadow       = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_chunk_nodes[key] = mi
	return mi


func _free_chunk_node(key: Vector3i) -> void:
	if not _chunk_nodes.has(key):
		return
	(_chunk_nodes[key] as MeshInstance3D).queue_free()
	_chunk_nodes.erase(key)


func _enqueue_region_for_chunk(cx: int, cz: int) -> void:
	_enqueue_region(_region_key(cx, cz))


func _enqueue_region(key: Vector2i) -> void:
	if not _dirty_region_set.has(key):
		_dirty_region_set[key] = true
		_dirty_region_queue.append(key)


func _enqueue_regions_for_cut_blocks(blocks: Array[Vector3i]) -> void:
	var offsets := [
		Vector3i.ZERO,
		Vector3i(-1, 0, 0),
		Vector3i(1, 0, 0),
		Vector3i(0, -1, 0),
		Vector3i(0, 1, 0),
		Vector3i(0, 0, -1),
		Vector3i(0, 0, 1),
	]
	for block: Vector3i in blocks:
		for offset: Vector3i in offsets:
			var pos := block + offset
			if pos.x < 0 or pos.x >= WORLD_SIZE_X \
					or pos.y < 0 or pos.y >= WORLD_SIZE_Y \
					or pos.z < 0 or pos.z >= WORLD_SIZE_Z:
				continue
			var cx := floori(float(pos.x) / float(CHUNK_SIZE))
			var cz := floori(float(pos.z) / float(CHUNK_SIZE))
			var key := _region_key(cx, cz)
			if _region_should_exist(key):
				_enqueue_region(key)


func _region_key(cx: int, cz: int) -> Vector2i:
	return Vector2i(
		floori(float(cx) / float(REGION_SIZE)),
		floori(float(cz) / float(REGION_SIZE)))


## Doc 11 Phase 1e: true while any chunk column in the region is still queued
## or in flight on the generator thread. Rebuilding such a region is wasted
## work — every completing column emits chunk_dirtied and re-enqueues it.
## 16 brief mutex checks per call; negligible next to one region mesh build.
func _region_has_pending_columns(key: Vector2i) -> bool:
	var start_cx := key.x * REGION_SIZE
	var start_cz := key.y * REGION_SIZE
	for cx in range(start_cx, mini(CHUNK_COUNT_X, start_cx + REGION_SIZE)):
		for cz in range(start_cz, mini(CHUNK_COUNT_Z, start_cz + REGION_SIZE)):
			if WorldGenerator.is_column_pending(cx, cz):
				return true
	return false


func _region_should_exist(key: Vector2i) -> bool:
	var start_cx := key.x * REGION_SIZE
	var start_cz := key.y * REGION_SIZE
	for cx in range(start_cx, mini(CHUNK_COUNT_X, start_cx + REGION_SIZE)):
		for cz in range(start_cz, mini(CHUNK_COUNT_Z, start_cz + REGION_SIZE)):
			if _chunk_in_radius(cx, cz, unload_radius_chunks):
				return true
	return false


## Serial path: build one region's geometry and assign it immediately. Used for
## single-region batches and the region_threaded = false fallback.
func _rebuild_region(key: Vector2i) -> void:
	var t_start := Time.get_ticks_msec()
	var result := _build_region_geometry(key)
	result["build_ms"] = Time.get_ticks_msec() - t_start
	_assign_region_mesh(key, result)


## WorkerThreadPool group-task body (doc 11 Phase 1c): builds one region of the
## current batch into its own results slot. See the _rgn_batch declaration for
## the thread-safety contract.
func _region_build_worker(i: int) -> void:
	var t_start := Time.get_ticks_msec()
	var result := _build_region_geometry(_rgn_batch[i])
	result["build_ms"] = Time.get_ticks_msec() - t_start
	_rgn_results[i] = result


## PURE geometry build for one region: the combined mesh arrays of every visible
## chunk in the 4x4 chunk area. Writes no member state and touches no scene
## nodes, so it is safe on a WorkerThreadPool task (ChunkMesher.build_arrays is
## worker-safe; WorldData reads are mutex-guarded). Returns {} when the region
## has no geometry.
func _build_region_geometry(key: Vector2i) -> Dictionary:
	var verts: PackedVector3Array = []
	var norms: PackedVector3Array = []
	var cols: PackedColorArray = []
	var indices: PackedInt32Array = []

	var start_cx := key.x * REGION_SIZE
	var start_cz := key.y * REGION_SIZE
	for cx in range(start_cx, mini(CHUNK_COUNT_X, start_cx + REGION_SIZE)):
		for cz in range(start_cz, mini(CHUNK_COUNT_Z, start_cz + REGION_SIZE)):
			for cy in range(CHUNK_COUNT_Y):
				if not _chunk_should_be_meshed(cx, cy, cz):
					continue
				var chunk := WorldData.get_chunk_if_exists(cx, cy, cz)
				if chunk == null:
					continue
				# Buried-skip (worker-safe: has_void flag + mutex-guarded neighbour
				# checks): a solid chunk whose six neighbours are also solid emits
				# no faces — UNLESS the slice plane cuts through or sits on it
				# (cut-floor top faces), or mining has carved into it or a direct
				# neighbour (cavity wall faces live in the adjacent chunk). This
				# keeps the all-rows visibility rule cheap: interior rock costs
				# one flag check plus a few dictionary lookups.
				if not chunk.has_void \
						and (cy + 1) * CHUNK_SIZE - 1 < slice_y \
						and not _cut_chunk_nearby(cx, cy, cz) \
						and _is_buried(cx, cy, cz):
					continue
				var built := ChunkMesher.build_arrays(chunk, cx, cy, cz, _visual_cut_blocks, slice_y)
				if built.is_empty():
					continue
				_append_region_arrays(built, Vector3(cx * CHUNK_SIZE, cy * CHUNK_SIZE, cz * CHUNK_SIZE), verts, norms, cols, indices)

	if verts.is_empty():
		return {}
	return {
		"verts": verts,
		"norms": norms,
		"cols": cols,
		"indices": indices,
	}


## Main-thread: create the ArrayMesh from a (possibly worker-built) geometry
## result, assign or free the region node, and update rebuild bookkeeping.
func _assign_region_mesh(key: Vector2i, result: Dictionary) -> void:
	var build_ms := int(result.get("build_ms", 0))
	_region_rebuild_count += 1
	_region_rebuild_msec_total += build_ms
	_region_rebuild_msec_max = maxi(_region_rebuild_msec_max, build_ms)

	if not result.has("verts"):
		_free_region_node(key)
		return

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = result["verts"]
	arrays[Mesh.ARRAY_NORMAL] = result["norms"]
	arrays[Mesh.ARRAY_COLOR] = result["cols"]
	arrays[Mesh.ARRAY_INDEX] = result["indices"]

	var region_mesh := ArrayMesh.new()
	region_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := _get_or_create_region_node(key)
	mi.mesh = region_mesh
	if _first_visible_mesh_msec == 0:
		_first_visible_mesh_msec = Time.get_ticks_msec()
		print("WorldRenderer: first visible region mesh after %.3f s at region %s." % [
			_elapsed_since_start_seconds(_first_visible_mesh_msec),
			str(key),
		])


func _rebuild_surface_region(key: Vector2i) -> void:
	var verts: PackedVector3Array = []
	var norms: PackedVector3Array = []
	var cols: PackedColorArray = []
	var indices: PackedInt32Array = []
	var season: String = WorldClock.season

	var start_cx := key.x * REGION_SIZE
	var start_cz := key.y * REGION_SIZE
	for cx in range(start_cx, mini(CHUNK_COUNT_X, start_cx + REGION_SIZE)):
		for cz in range(start_cz, mini(CHUNK_COUNT_Z, start_cz + REGION_SIZE)):
			if not _chunk_in_radius(cx, cz, view_radius_chunks):
				continue
			var base_x := cx * CHUNK_SIZE
			var base_z := cz * CHUNK_SIZE
			for lx in range(CHUNK_SIZE):
				var wx := base_x + lx
				for lz in range(CHUNK_SIZE):
					var wz := base_z + lz
					var wy := WorldGenerator.get_surface_y(wx, wz)
					if wy < 0 or wy > slice_y:
						continue
					var block_id := WorldData.get_block(wx, wy, wz)
					if BlockRegistry.is_transparent(block_id):
						continue
					_add_surface_quad(
						Vector3(float(wx), float(wy + 1), float(wz)),
						BlockRegistry.get_color(block_id, season),
						verts,
						norms,
						cols,
						indices)

	if verts.is_empty():
		_free_region_node(key)
		return

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = indices

	var region_mesh := ArrayMesh.new()
	region_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := _get_or_create_region_node(key)
	mi.mesh = region_mesh


func _add_surface_quad(
		origin: Vector3,
		color: Color,
		verts: PackedVector3Array,
		norms: PackedVector3Array,
		cols: PackedColorArray,
		indices: PackedInt32Array,
		size: float = 1.0) -> void:

	_add_surface_rect(origin, color, verts, norms, cols, indices, size, size)


func _add_surface_rect(
		origin: Vector3,
		color: Color,
		verts: PackedVector3Array,
		norms: PackedVector3Array,
		cols: PackedColorArray,
		indices: PackedInt32Array,
		size_x: float,
		size_z: float) -> void:

	var base := verts.size()
	verts.append(origin)
	verts.append(origin + Vector3(0, 0, size_z))
	verts.append(origin + Vector3(size_x, 0, size_z))
	verts.append(origin + Vector3(size_x, 0, 0))

	for i in range(4):
		norms.append(Vector3.UP)
		cols.append(color)

	indices.append(base)
	indices.append(base + 2)
	indices.append(base + 1)
	indices.append(base)
	indices.append(base + 3)
	indices.append(base + 2)


func _add_overview_side(
		sample_x: int,
		sample_z: int,
		neighbor_x: int,
		neighbor_z: int,
		a: Vector3,
		b: Vector3,
		bottom_y: float,
		top_color: Color,
		normal: Vector3,
		verts: PackedVector3Array,
		norms: PackedVector3Array,
		cols: PackedColorArray,
		indices: PackedInt32Array) -> void:

	if a.y <= bottom_y:
		return

	var top_y := a.y
	var drop := top_y - bottom_y
	if drop <= 0.0:
		return

	_add_overview_side_column(
		sample_x,
		sample_z,
		neighbor_x,
		neighbor_z,
		a,
		b,
		bottom_y,
		top_y,
		top_color,
		normal,
		verts,
		norms,
		cols,
		indices)


func _add_overview_side_column(
		sample_x: int,
		sample_z: int,
		neighbor_x: int,
		neighbor_z: int,
		a: Vector3,
		b: Vector3,
		bottom_y: float,
		top_y: float,
		top_color: Color,
		normal: Vector3,
		verts: PackedVector3Array,
		norms: PackedVector3Array,
		cols: PackedColorArray,
		indices: PackedInt32Array) -> void:

	var y0 := clampi(floori(bottom_y), 0, WORLD_SIZE_Y - 1)
	var y1 := clampi(ceili(top_y), 1, WORLD_SIZE_Y)
	var has_cuts := not _ovt_cut.is_empty()
	var has_mined := not _ovt_mined.is_empty()
	var run_bottom := -1.0
	var run_color := Color()

	for y in range(y0, y1):
		# Cut wall blocks punch holes (doc 11 SO-2b, Option A 2026-06-05): the
		# face at height y belongs to block (sample_x, y, sample_z) — if it is
		# designated OR mined, end the current run and skip it. The cavity shell
		# fills the interior behind (strata-coloured for plans, exact for holes).
		if has_cuts and _ovt_cut.has(Vector3i(sample_x, y, sample_z)):
			if run_bottom >= 0.0:
				_add_overview_side_band(a, b, run_bottom, float(y), run_color, normal, verts, norms, cols, indices)
				run_bottom = -1.0
			continue
		# Per-block — every wall block face shows its own block's colour (no sampling step).
		# Defect 5 (2026-06-05) — exposure-source-aware colour: a face whose
		# facing air block was MINED open tells the truth (exact generated id,
		# veins included — mining reveals what it exposes); every other face
		# (natural cliff, slice cut, designation) stays strata-concealed.
		var color: Color
		if has_mined and _ovt_mined.has(Vector3i(neighbor_x, y, neighbor_z)):
			var exact_id := WorldGenerator.get_generated_block_id(sample_x, y, sample_z)
			color = BlockRegistry.get_color(exact_id, WorldClock.season) \
					if not BlockRegistry.is_transparent(exact_id) else _overview_rock_color
		else:
			color = _overview_side_color_at(sample_x, y, sample_z, top_y, top_color)
		if run_bottom < 0.0:
			run_bottom = float(y)
			run_color = color
		elif color != run_color:
			_add_overview_side_band(a, b, run_bottom, float(y), run_color, normal, verts, norms, cols, indices)
			run_bottom = float(y)
			run_color = color

	if run_bottom >= 0.0:
		_add_overview_side_band(a, b, run_bottom, top_y, run_color, normal, verts, norms, cols, indices)


## Per-block honest side colour (Hard Rule 9): every wall block face shows that block's OWN
## colour — the grass cap samples as grass, soil bands as soil, rock shelves as rock. The former
## top-colour override and 4-block sampling step repainted blocks and were removed (2026-06-03).
## _top_y/_top_color are retained in the signature for call-site stability only.
func _overview_side_color_at(sample_x: int, y: int, sample_z: int, _top_y: float, _top_color: Color) -> Color:
	# Strata-only lookup: ore veins stay concealed on natural walls (that is a DATA rule —
	# 43_mining_materials.md resource concealment) and caves are skipped (invisible at overview
	# zoom), which avoids the dominant per-Y 3D-noise cost of the full generation pipeline.
	var block_id := WorldGenerator.get_overview_strata_block_id(sample_x, y, sample_z)
	if BlockRegistry.is_transparent(block_id):
		return _overview_rock_color
	return BlockRegistry.get_color(block_id, WorldClock.season)


func _add_overview_side_band(
		a: Vector3,
		b: Vector3,
		bottom_y: float,
		top_y: float,
		color: Color,
		normal: Vector3,
		verts: PackedVector3Array,
		norms: PackedVector3Array,
		cols: PackedColorArray,
		indices: PackedInt32Array) -> void:

	if top_y <= bottom_y:
		return

	var base := verts.size()
	verts.append(Vector3(a.x, top_y, a.z))
	verts.append(Vector3(b.x, top_y, b.z))
	verts.append(Vector3(b.x, bottom_y, b.z))
	verts.append(Vector3(a.x, bottom_y, a.z))

	for i in range(4):
		norms.append(normal)
		cols.append(color)

	indices.append(base)
	indices.append(base + 1)
	indices.append(base + 2)
	indices.append(base)
	indices.append(base + 2)
	indices.append(base + 3)


## Appends one chunk's packed arrays (from ChunkMesher.build_arrays) into the
## combined region arrays, offsetting vertices into region space. Pure data —
## worker-safe. Normals and colours are bulk-copied; vertices and indices need
## the per-element offset/rebase.
func _append_region_arrays(
		built: Array,
		offset: Vector3,
		verts: PackedVector3Array,
		norms: PackedVector3Array,
		cols: PackedColorArray,
		indices: PackedInt32Array) -> void:

	var src_verts: PackedVector3Array = built[0]
	var src_norms: PackedVector3Array = built[1]
	var src_cols: PackedColorArray = built[2]
	var src_indices: PackedInt32Array = built[3]
	var base := verts.size()

	for v: Vector3 in src_verts:
		verts.append(v + offset)
	norms.append_array(src_norms)
	cols.append_array(src_cols)
	for i: int in src_indices:
		indices.append(base + i)


func _get_or_create_region_node(key: Vector2i) -> MeshInstance3D:
	if _region_nodes.has(key):
		return _region_nodes[key] as MeshInstance3D

	var mi := MeshInstance3D.new()
	mi.name = "Region_%d_%d" % [key.x, key.y]
	mi.material_override = _material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_region_nodes[key] = mi
	return mi


func _free_region_node(key: Vector2i) -> void:
	if not _region_nodes.has(key):
		return
	(_region_nodes[key] as MeshInstance3D).queue_free()
	_region_nodes.erase(key)


# -- Block-face overview ------------------------------------------------------

func _invalidate_overview_global() -> void:
	_overview_built = false
	_overview_rebuild_queued = false
	_dirty_overview_tiles.clear()
	_dirty_overview_tile_set.clear()
	_overview_tile_stats.clear()
	_overview_sampled_top_faces = 0
	_overview_merged_top_faces = 0
	_overview_side_faces = 0
	_overview_validation_samples = 0
	_overview_validation_mismatches = 0
	_ovp_loop_usec = 0
	_ovp_sides_usec = 0
	_ovp_merge_usec = 0
	_ovp_mesh_usec = 0
	_ovp_tiles = 0
	_ovp_max_tile_usec = 0
	_ovp_max_tile_key = Vector2i(-1, -1)
	_ovp_max_breakdown = {}
	_overview_startup_tile_goal = 0
	_overview_startup_center = Vector2i(-1, -1)
	_overview_startup_ready_msec = 0
	_overview_complete_msec = 0
	if _overview_node != null:
		_overview_node.queue_free()
		_overview_node = null
	for key: Vector2i in _overview_tile_nodes.keys():
		(_overview_tile_nodes[key] as MeshInstance3D).queue_free()
	_overview_tile_nodes.clear()


## Re-mesh the already-built block-face overview tiles in place after the
## deferred grass-band passes finish. We re-queue existing tile keys rather than
## calling _invalidate_overview_global(), so nodes are reused (no free/recreate)
## and the surface does not flicker. Tiles still queued from the initial build
## are left alone — they will mesh fresh with the now-open grass gate. Streamed
## chunks are not handled here: at this point startup is in overview mode, and
## any later streamed chunk builds after the gate is already open.
func _on_grass_bands_ready() -> void:
	# Shell ids memoised during the gate window may hold fallback grass — drop
	# them and re-bake the shell with the final band variants.
	_shell_exact_ids.clear()
	_shell_strata_ids.clear()
	_cavity_shell_dirty = true
	# SO-2: the far field exists in both modes now — refresh it regardless.
	if _overview_tile_nodes.is_empty():
		return
	for key: Vector2i in _overview_tile_nodes.keys():
		_enqueue_overview_tile(key)
	_overview_built = false


## Re-bake seasonal surface colours when the season turns. Every mesh path reads
## WorldClock.season at build time (ChunkMesher, regions, overview tiles), so re-queuing
## the already-built meshes is sufficient — nodes are reused in place (no free, no flicker)
## and the queues drain at the normal per-frame budget, so the recolour sweeps across the
## map over a few seconds rather than stalling a frame.
func _on_season_changed(_new_season: String) -> void:
	# Block-face overview tiles (the zoomed-out surface).
	if not _overview_tile_nodes.is_empty():
		for key: Vector2i in _overview_tile_nodes.keys():
			_enqueue_overview_tile(key)
		_overview_built = false
	# Streamed surface regions and chunk meshes (the zoomed-in view).
	for rkey: Vector2i in _region_nodes.keys():
		_enqueue_region(rkey)
	for ckey: Vector3i in _chunk_nodes.keys():
		_enqueue_chunk(ckey)
	# Cavity shell bakes seasonal colours too (SO-2b).
	_cavity_shell_dirty = true


## Slice-change invalidation for the far field (doc 11 Phase SO): only tiles
## whose visible terrain reaches above the LOWER of the two planes can change —
## a tile entirely below both planes is cut by neither. Affected tiles plus
## their 4-neighbours (boundary walls read neighbour tops) are re-enqueued
## through the normal threaded/budgeted tile queue. Lowland tiles never rebuild
## for mountain-depth slices. ~1k Vector2i range reads; trivial.
func _enqueue_overview_tiles_for_slice_change(old_y: int, new_y: int) -> void:
	if _overview_tile_nodes.is_empty() and not _overview_rebuild_queued:
		return   # far field not built (or already torn down) — nothing to refresh
	var low := mini(old_y, new_y)
	var tile_count_x := ceili(float(WORLD_SIZE_X) / float(OVERVIEW_TILE_SIZE))
	var tile_count_z := ceili(float(WORLD_SIZE_Z) / float(OVERVIEW_TILE_SIZE))
	var affected: Dictionary = {}
	for tx in range(tile_count_x):
		for tz in range(tile_count_z):
			if WorldGenerator.get_tile_visible_range(tx, tz).y > low:
				affected[Vector2i(tx, tz)] = true
	if affected.is_empty():
		return
	# Add the 1-tile wall margin, then enqueue CENTER-FIRST so the sweep fills
	# outward from the camera instead of wiping west-to-east across the map.
	var neighbor_offsets := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var to_build: Dictionary = {}
	for key: Vector2i in affected.keys():
		to_build[key] = true
		for offset: Vector2i in neighbor_offsets:
			var nkey: Vector2i = key + offset
			if nkey.x < 0 or nkey.x >= tile_count_x or nkey.y < 0 or nkey.y >= tile_count_z:
				continue
			to_build[nkey] = true
	var center := _overview_startup_center_tile(tile_count_x, tile_count_z)
	var ordered: Array = to_build.keys()
	ordered.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return _overview_tile_distance(a, center) < _overview_tile_distance(b, center)
	)
	for key: Vector2i in ordered:
		_enqueue_overview_tile(key)
	_overview_built = false


func _enqueue_overview_tiles_for_blocks(blocks: Array[Vector3i]) -> void:
	for block: Vector3i in blocks:
		_enqueue_overview_tile_for_world(block.x, block.z)
		_enqueue_overview_tile_for_world(block.x - 1, block.z)
		_enqueue_overview_tile_for_world(block.x + 1, block.z)
		_enqueue_overview_tile_for_world(block.x, block.z - 1)
		_enqueue_overview_tile_for_world(block.x, block.z + 1)
	_overview_built = false


func _enqueue_overview_tile_for_world(wx: int, wz: int) -> void:
	if wx < 0 or wx >= WORLD_SIZE_X or wz < 0 or wz >= WORLD_SIZE_Z:
		return
	_enqueue_overview_tile(Vector2i(
		floori(float(wx) / float(OVERVIEW_TILE_SIZE)),
		floori(float(wz) / float(OVERVIEW_TILE_SIZE))))


func _enqueue_overview_tile(key: Vector2i) -> void:
	if _dirty_overview_tile_set.has(key):
		return
	_dirty_overview_tile_set[key] = true
	_dirty_overview_tiles.append(key)


func _get_or_create_overview_tile_node(key: Vector2i) -> MeshInstance3D:
	if _overview_tile_nodes.has(key):
		return _overview_tile_nodes[key] as MeshInstance3D

	var mi := MeshInstance3D.new()
	mi.name = "BlockFaceOverview_%d_%d" % [key.x, key.y]
	mi.material_override = _material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_overview_tile_nodes[key] = mi
	return mi


func _free_overview_tile_node(key: Vector2i) -> void:
	if not _overview_tile_nodes.has(key):
		return
	(_overview_tile_nodes[key] as MeshInstance3D).queue_free()
	_overview_tile_nodes.erase(key)


func _set_overview_nodes_visible(make_visible: bool) -> void:
	if _overview_node != null:
		_overview_node.visible = make_visible
	for key: Vector2i in _overview_tile_nodes:
		(_overview_tile_nodes[key] as MeshInstance3D).visible = make_visible


func _recompute_overview_stats() -> void:
	_overview_sampled_top_faces = 0
	_overview_merged_top_faces = 0
	_overview_side_faces = 0
	_overview_validation_samples = 0
	_overview_validation_mismatches = 0
	for stats: Dictionary in _overview_tile_stats.values():
		_overview_sampled_top_faces += int(stats.get("sampled_top_faces", 0))
		_overview_merged_top_faces += int(stats.get("merged_top_faces", 0))
		_overview_side_faces += int(stats.get("side_faces", 0))
		_overview_validation_samples += int(stats.get("validation_samples", 0))
		_overview_validation_mismatches += int(stats.get("validation_mismatches", 0))


## The sliced overview IS the slice view (decision 2026-06-04, doc 11 Phase SO):
## it covers the whole map at any slice depth, honours mining cuts, and never
## reveals undiscovered resources. The streamed chunk path stays in the code
## but DORMANT — reachable only via set_overview_enabled(false), reserved for a
## future true-3D-interior need (side views into roofed tunnels).
func _block_face_overview_active() -> bool:
	return use_block_face_overview


func _update_block_face_overview() -> void:
	if _camera_rig == null:
		_camera_rig = _find_camera(get_tree().current_scene)
	_set_overview_nodes_visible(true)
	_free_all_streamed_nodes()

	var stats := WorldGenerator.get_streaming_stats()
	if not stats.get("maps_ready", false):
		return
	if not _overview_built and not _overview_rebuild_queued and _dirty_overview_tiles.is_empty():
		_queue_full_overview_rebuild()
	_drain_overview_tile_queue()
	if _initial_load and _overview_startup_tile_goal > 0 and _overview_tile_nodes.size() >= _overview_startup_tile_goal:
		_initial_load = false
		_overview_startup_ready_msec = Time.get_ticks_msec()
		print("WorldRenderer: startup overview radius ready (%d/%d tiles built, queue=%d)." % [
			_overview_tile_nodes.size(),
			_overview_startup_tile_goal,
			_dirty_overview_tiles.size(),
		])
		_print_startup_performance_report()
	if not _dirty_overview_tiles.is_empty():
		return
	if _overview_rebuild_queued:
		_overview_rebuild_queued = false
		_overview_built = true
		_overview_complete_msec = Time.get_ticks_msec()
		_initial_load = false
		print("WorldRenderer: built block-face overview tiles (%d tiles, step=%d, tops %d->%d, sides %d, validation mismatches %d/%d) in %.2f s since startup." % [
			_overview_tile_nodes.size(),
			OVERVIEW_STEP,
			_overview_sampled_top_faces,
			_overview_merged_top_faces,
			_overview_side_faces,
			_overview_validation_mismatches,
			_overview_validation_samples,
			_elapsed_since_start_seconds(_overview_complete_msec),
		])
		if overview_profile and _ovp_tiles > 0:
			var total_us := _ovp_loop_usec + _ovp_sides_usec + _ovp_merge_usec + _ovp_mesh_usec
			print("WorldRenderer: overview build profile over %d tiles (CPU %.2f s): surface_loop %.2f s (%.0f%%), sides %.2f s (%.0f%%), top_merge %.2f s (%.0f%%), mesh_create %.2f s (%.0f%%)." % [
				_ovp_tiles,
				float(total_us) / 1e6,
				float(_ovp_loop_usec) / 1e6, 100.0 * float(_ovp_loop_usec) / float(maxi(total_us, 1)),
				float(_ovp_sides_usec) / 1e6, 100.0 * float(_ovp_sides_usec) / float(maxi(total_us, 1)),
				float(_ovp_merge_usec) / 1e6, 100.0 * float(_ovp_merge_usec) / float(maxi(total_us, 1)),
				float(_ovp_mesh_usec) / 1e6, 100.0 * float(_ovp_mesh_usec) / float(maxi(total_us, 1)),
			])
			print("WorldRenderer: slowest overview tile %s at %.1f ms -> %s" % [
				str(_ovp_max_tile_key),
				float(_ovp_max_tile_usec) / 1000.0,
				str(_ovp_max_breakdown),
			])
		_print_startup_performance_report()
	else:
		_overview_built = true


func _queue_full_overview_rebuild() -> void:
	_invalidate_overview_global()
	var tile_count_x := ceili(float(WORLD_SIZE_X) / float(OVERVIEW_TILE_SIZE))
	var tile_count_z := ceili(float(WORLD_SIZE_Z) / float(OVERVIEW_TILE_SIZE))
	var center := _overview_startup_center_tile(tile_count_x, tile_count_z)
	_overview_startup_center = center
	for key in _overview_tiles_center_first(center, tile_count_x, tile_count_z):
		_enqueue_overview_tile(key)
		if _overview_startup_tile_goal == 0 and _overview_tile_distance(key, center) > overview_startup_radius_tiles:
			_overview_startup_tile_goal = _dirty_overview_tiles.size() - 1
	if _overview_startup_tile_goal == 0:
		_overview_startup_tile_goal = _dirty_overview_tiles.size()
	_overview_rebuild_queued = true


func _overview_startup_center_tile(tile_count_x: int, tile_count_z: int) -> Vector2i:
	if _camera_rig == null:
		_camera_rig = _find_camera(get_tree().current_scene)
	if _camera_rig == null:
		return Vector2i(floori(float(tile_count_x) * 0.5), floori(float(tile_count_z) * 0.5))
	return Vector2i(
		clampi(int(floor(_camera_rig.global_position.x / float(OVERVIEW_TILE_SIZE))), 0, tile_count_x - 1),
		clampi(int(floor(_camera_rig.global_position.z / float(OVERVIEW_TILE_SIZE))), 0, tile_count_z - 1))


func _overview_tiles_center_first(center: Vector2i, tile_count_x: int, tile_count_z: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var max_radius := maxi(
		maxi(center.x, tile_count_x - 1 - center.x),
		maxi(center.y, tile_count_z - 1 - center.y))
	for radius in range(max_radius + 1):
		for dx in range(-radius, radius + 1):
			for dz in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dz)) != radius:
					continue
				var key := Vector2i(center.x + dx, center.y + dz)
				if key.x < 0 or key.x >= tile_count_x or key.y < 0 or key.y >= tile_count_z:
					continue
				result.append(key)
	return result


func _overview_tile_distance(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


func _drain_overview_tile_queue() -> void:
	if _dirty_overview_tiles.is_empty():
		return
	# Read-only-during-build state, set once on the main thread before any worker
	# runs: side rock color, cut-block snapshot, and season.
	_cache_overview_side_colors(WorldClock.season)
	_ovt_cut = _visual_cut_blocks.duplicate()
	_ovt_mined = _mined_blocks.duplicate()
	_ovt_season = WorldClock.season

	# Pull this frame's batch off the dirty queue.
	var batch: Array[Vector2i] = []
	while _dirty_overview_tiles.size() > 0 and batch.size() < overview_tiles_per_frame:
		var key: Vector2i = _dirty_overview_tiles.pop_front()
		_dirty_overview_tile_set.erase(key)
		batch.append(key)
	if batch.is_empty():
		return

	if overview_threaded and batch.size() > 1:
		# Build all tiles in the batch in parallel; each worker writes only its own
		# _ovt_results slot and reads only the read-only state above. The main thread
		# blocks until the batch finishes (~batch_time / cores) then assigns meshes.
		_ovt_batch = batch
		_ovt_results = []
		_ovt_results.resize(batch.size())
		var task_id := WorkerThreadPool.add_group_task(
			Callable(self, "_overview_build_worker"), batch.size(), -1, false, "overview_tiles")
		WorkerThreadPool.wait_for_group_task_completion(task_id)
		for i in range(batch.size()):
			_assign_overview_tile(batch[i], _ovt_results[i])
	else:
		for key: Vector2i in batch:
			_assign_overview_tile(key, _build_overview_tile_geometry(key, _ovt_season))

	_recompute_overview_stats()
	_meshes_built += batch.size()


## WorkerThreadPool group-task body: builds one tile of the current batch into its
## own results slot. Pure read of shared state (see _build_overview_tile_geometry).
func _overview_build_worker(i: int) -> void:
	_ovt_results[i] = _build_overview_tile_geometry(_ovt_batch[i], _ovt_season)


# PURE geometry build for one overview tile. Reads only read-only state
# (WorldGenerator maps/noise, BlockRegistry, _visual_cut_blocks, _overview_rock_color
# which is set before the batch) and writes NO member variables, so it is safe to
# run on a WorkerThreadPool task. Returns the mesh arrays + per-tile stats/timings,
# or {} when the tile has no geometry. The main-thread wrapper creates the mesh.
func _build_overview_tile_geometry(tile_key: Vector2i, season: String) -> Dictionary:
	var step: int = OVERVIEW_STEP
	var x0 := tile_key.x * OVERVIEW_TILE_SIZE
	var z0 := tile_key.y * OVERVIEW_TILE_SIZE
	if x0 < 0 or x0 >= WORLD_SIZE_X or z0 < 0 or z0 >= WORLD_SIZE_Z:
		return {}
	var x1 := mini(WORLD_SIZE_X, x0 + OVERVIEW_TILE_SIZE)
	var z1 := mini(WORLD_SIZE_Z, z0 + OVERVIEW_TILE_SIZE)

	var verts: PackedVector3Array = []
	var norms: PackedVector3Array = []
	var cols: PackedColorArray = []
	var indices: PackedInt32Array = []
	var sample_cells: Dictionary = {}
	var grid_w := ceili(float(x1 - x0) / float(step))
	var grid_z := ceili(float(z1 - z0) / float(step))
	var validation_samples := 0
	var validation_mismatches := 0
	var prof := overview_profile
	var t_sides_usec := 0
	var t_loop_usec := 0
	var t_merge_usec := 0
	var t_loop0 := Time.get_ticks_usec() if prof else 0
	for wx in range(x0, x1, step):
		for wz in range(z0, z1, step):
			var surface := _overview_visible_surface_after_cut(wx, wz)
			if surface.is_empty():
				continue
			var wy: int = surface["wy"]
			var block_id: int = surface["block_id"]
			# Debug-only cross-check; off by default (see overview_validate_block_ids).
			if overview_validate_block_ids:
				var generated_id := WorldGenerator.get_generated_block_id(wx, wy, wz)
				validation_samples += 1
				if generated_id != block_id:
					validation_mismatches += 1

			var color := BlockRegistry.get_color(block_id, season)
			# SO-2c: slice-cut strata floors dim to read as "inside the
			# mountain", never walkable ground. Luminance-only (Hard Rule 9).
			var sliced: bool = surface.get("slice_cut", false)
			if sliced:
				color = Color(color.r * SLICE_CUT_DIM, color.g * SLICE_CUT_DIM, color.b * SLICE_CUT_DIM, color.a)
			var key := Vector2i(
				int(floor(float(wx - x0) / float(step))),
				int(floor(float(wz - z0) / float(step))))
			sample_cells[key] = {
				"wx": wx,
				"wz": wz,
				"wy": wy,
				"block_id": block_id,
				"color": color,
				"sliced": sliced,
			}
			if show_overview_sides:
				if prof:
					var s := Time.get_ticks_usec()
					_add_overview_sides(wx, wz, step, float(wy + 1), color, verts, norms, cols, indices)
					t_sides_usec += Time.get_ticks_usec() - s
				else:
					_add_overview_sides(wx, wz, step, float(wy + 1), color, verts, norms, cols, indices)

	if prof:
		t_loop_usec = (Time.get_ticks_usec() - t_loop0) - t_sides_usec

	# Sides are the only geometry added in the loop above; each band is one quad
	# (6 indices), so this counts side faces without a shared running counter.
	@warning_ignore("integer_division")
	var side_faces := indices.size() / 6
	var sampled_top_faces := sample_cells.size()
	var t_merge0 := Time.get_ticks_usec() if prof else 0
	var merged_top_faces := _add_greedy_overview_tops(sample_cells, grid_w, grid_z, step, verts, norms, cols, indices)
	if prof:
		t_merge_usec = Time.get_ticks_usec() - t_merge0

	if verts.is_empty():
		return {}

	return {
		"verts": verts,
		"norms": norms,
		"cols": cols,
		"indices": indices,
		"sampled_top_faces": sampled_top_faces,
		"merged_top_faces": merged_top_faces,
		"side_faces": side_faces,
		"validation_samples": validation_samples,
		"validation_mismatches": validation_mismatches,
		"t_loop_usec": t_loop_usec,
		"t_sides_usec": t_sides_usec,
		"t_merge_usec": t_merge_usec,
	}


# Main-thread: take a (possibly worker-built) geometry result and create the mesh
# + update bookkeeping. Only this part touches member state / the scene tree.
func _assign_overview_tile(tile_key: Vector2i, result: Dictionary) -> void:
	var t_start := Time.get_ticks_msec()
	if result.is_empty():
		_free_overview_tile_node(tile_key)
		_overview_tile_stats.erase(tile_key)
		return

	var t_mesh0 := Time.get_ticks_usec() if overview_profile else 0
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = result["verts"]
	arrays[Mesh.ARRAY_NORMAL] = result["norms"]
	arrays[Mesh.ARRAY_COLOR] = result["cols"]
	arrays[Mesh.ARRAY_INDEX] = result["indices"]

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var mi := _get_or_create_overview_tile_node(tile_key)
	mi.mesh = mesh
	mi.visible = true

	if overview_profile:
		var t_mesh_usec := Time.get_ticks_usec() - t_mesh0
		_ovp_loop_usec += int(result["t_loop_usec"])
		_ovp_sides_usec += int(result["t_sides_usec"])
		_ovp_merge_usec += int(result["t_merge_usec"])
		_ovp_mesh_usec += t_mesh_usec
		_ovp_tiles += 1
		var tile_total := int(result["t_loop_usec"]) + int(result["t_sides_usec"]) + int(result["t_merge_usec"]) + t_mesh_usec
		if tile_total > _ovp_max_tile_usec:
			_ovp_max_tile_usec = tile_total
			_ovp_max_tile_key = tile_key
			_ovp_max_breakdown = {
				"loop_us": int(result["t_loop_usec"]),
				"sides_us": int(result["t_sides_usec"]),
				"merge_us": int(result["t_merge_usec"]),
				"mesh_us": t_mesh_usec,
				"verts": (result["verts"] as PackedVector3Array).size(),
			}
	if _first_visible_mesh_msec == 0:
		_first_visible_mesh_msec = Time.get_ticks_msec()
		print("WorldRenderer: first visible overview tile after %.3f s at tile %s." % [
			_elapsed_since_start_seconds(_first_visible_mesh_msec),
			str(tile_key),
		])
	_overview_tile_stats[tile_key] = {
		"sampled_top_faces": int(result["sampled_top_faces"]),
		"merged_top_faces": int(result["merged_top_faces"]),
		"side_faces": int(result["side_faces"]),
		"validation_samples": int(result["validation_samples"]),
		"validation_mismatches": int(result["validation_mismatches"]),
	}
	var elapsed := Time.get_ticks_msec() - t_start
	_overview_build_count += 1
	_overview_build_msec_total += elapsed
	_overview_build_msec_max = maxi(_overview_build_msec_max, elapsed)


func _add_greedy_overview_tops(
		sample_cells: Dictionary,
		grid_w: int,
		grid_z: int,
		step: int,
		verts: PackedVector3Array,
		norms: PackedVector3Array,
		cols: PackedColorArray,
		indices: PackedInt32Array) -> int:

	var merged := 0
	var visited: Dictionary = {}
	for gx in range(grid_w):
		for gz in range(grid_z):
			var key := Vector2i(gx, gz)
			if visited.has(key) or not sample_cells.has(key):
				continue

			var cell: Dictionary = sample_cells[key]
			var width := 1
			while gx + width < grid_w:
				var next_key := Vector2i(gx + width, gz)
				if visited.has(next_key) or not _overview_top_cells_merge(cell, sample_cells.get(next_key, {})):
					break
				width += 1

			var height := 1
			var can_extend := true
			while gz + height < grid_z and can_extend:
				for dx in range(width):
					var row_key := Vector2i(gx + dx, gz + height)
					if visited.has(row_key) or not _overview_top_cells_merge(cell, sample_cells.get(row_key, {})):
						can_extend = false
						break
				if can_extend:
					height += 1

			for dx in range(width):
				for dz in range(height):
					visited[Vector2i(gx + dx, gz + dz)] = true

			var wx: int = cell["wx"]
			var wz: int = cell["wz"]
			var wy: int = cell["wy"]
			var color: Color = cell["color"]
			var size_x := float(mini(step * width, WORLD_SIZE_X - wx))
			var size_z := float(mini(step * height, WORLD_SIZE_Z - wz))
			_add_surface_rect(
				Vector3(float(wx), float(wy + 1), float(wz)),
				color,
				verts,
				norms,
				cols,
				indices,
				size_x,
				size_z)
			merged += 1
	return merged


func _overview_top_cells_merge(a: Dictionary, b: Dictionary) -> bool:
	if a.is_empty() or b.is_empty():
		return false
	# SO-2c: a dimmed slice-cut plate must never merge with an undimmed natural
	# plate of the same block at the same height — the merged rect would paint
	# one brightness over both.
	return int(a.get("wy", -999999)) == int(b.get("wy", -999998)) \
		and int(a.get("block_id", -1)) == int(b.get("block_id", -2)) \
		and bool(a.get("sliced", false)) == bool(b.get("sliced", false))


func _add_overview_sides(
		wx: int,
		wz: int,
		step: int,
		top_y: float,
		top_color: Color,
		verts: PackedVector3Array,
		norms: PackedVector3Array,
		cols: PackedColorArray,
		indices: PackedInt32Array) -> void:

	var size := float(mini(step, mini(WORLD_SIZE_X - wx, WORLD_SIZE_Z - wz)))
	var edge_y := float(overview_edge_bottom_y)
	var east_y := _overview_neighbor_top_y(wx + step, wz, edge_y)
	var south_y := _overview_neighbor_top_y(wx, wz + step, edge_y)
	var west_y := _overview_neighbor_top_y(wx - step, wz, edge_y)
	var north_y := _overview_neighbor_top_y(wx, wz - step, edge_y)

	if wx + step < WORLD_SIZE_X:
		_add_overview_side(
			wx + step - 1,
			wz,
			wx + step,
			wz,
			Vector3(float(wx) + size, top_y, float(wz) + size),
			Vector3(float(wx) + size, top_y, float(wz)),
			east_y,
			top_color,
			Vector3.RIGHT,
			verts,
			norms,
			cols,
			indices)
	else:
		_add_overview_side(
			wx + step - 1,
			wz,
			wx + step,
			wz,
			Vector3(float(wx) + size, top_y, float(wz) + size),
			Vector3(float(wx) + size, top_y, float(wz)),
			edge_y,
			top_color,
			Vector3.RIGHT,
			verts,
			norms,
			cols,
			indices)
	if wz + step < WORLD_SIZE_Z:
		_add_overview_side(
			wx,
			wz + step - 1,
			wx,
			wz + step,
			Vector3(float(wx), top_y, float(wz) + size),
			Vector3(float(wx) + size, top_y, float(wz) + size),
			south_y,
			top_color,
			Vector3.BACK,
			verts,
			norms,
			cols,
			indices)
	else:
		_add_overview_side(
			wx,
			wz + step - 1,
			wx,
			wz + step,
			Vector3(float(wx), top_y, float(wz) + size),
			Vector3(float(wx) + size, top_y, float(wz) + size),
			edge_y,
			top_color,
			Vector3.BACK,
			verts,
			norms,
			cols,
			indices)
	if wx - step >= 0:
		_add_overview_side(
			wx,
			wz,
			wx - step,
			wz,
			Vector3(float(wx), top_y, float(wz)),
			Vector3(float(wx), top_y, float(wz) + size),
			west_y,
			top_color,
			Vector3.LEFT,
			verts,
			norms,
			cols,
			indices)
	else:
		_add_overview_side(
			wx,
			wz,
			wx - step,
			wz,
			Vector3(float(wx), top_y, float(wz)),
			Vector3(float(wx), top_y, float(wz) + size),
			edge_y,
			top_color,
			Vector3.LEFT,
			verts,
			norms,
			cols,
			indices)
	if wz - step >= 0:
		_add_overview_side(
			wx,
			wz,
			wx,
			wz - step,
			Vector3(float(wx) + size, top_y, float(wz)),
			Vector3(float(wx), top_y, float(wz)),
			north_y,
			top_color,
			Vector3.FORWARD,
			verts,
			norms,
			cols,
			indices)
	else:
		_add_overview_side(
			wx,
			wz,
			wx,
			wz - step,
			Vector3(float(wx) + size, top_y, float(wz)),
			Vector3(float(wx), top_y, float(wz)),
			edge_y,
			top_color,
			Vector3.FORWARD,
			verts,
			norms,
			cols,
			indices)


func _overview_neighbor_top_y(wx: int, wz: int, edge_y: float) -> float:
	if wx < 0 or wx >= WORLD_SIZE_X or wz < 0 or wz >= WORLD_SIZE_Z:
		return edge_y
	# WATERLINE-AWARE neighbour top (fix 2026-06-04): the old water-blind helper
	# returned -1 for lake/tarn columns, so every water column and every bank
	# drew side walls down to edge_y (Y0) — the tarn tile alone built ~127k
	# verts (843 ms). Buried inside terrain it went unnoticed; the slice cut
	# exposed it as a striped water monolith. With the waterline as the top:
	# water-vs-water emits no walls, banks emit a 1-block lip, and the water
	# surface quad (opaque) hides the basin interior anyway.
	var wy := WorldGenerator.get_visible_surface_y(wx, wz)
	if wy < 0:
		return edge_y
	# Slice-aware (Phase SO): a neighbour above the plane is clamped to its cut
	# top, so boundary walls hang from the cut floor, not the world bottom.
	if wy > slice_y:
		wy = slice_y
	while wy >= 0 and _ovt_cut.has(Vector3i(wx, wy, wz)):
		wy -= 1
	if wy < 0:
		return edge_y
	return float(wy + 1)


func _overview_visible_surface_after_cut(wx: int, wz: int) -> Dictionary:
	var wy := WorldGenerator.get_visible_surface_y(wx, wz)
	if wy < 0:
		return {}
	# Slice-aware far field (doc 11 Phase SO): a column whose surface is above
	# the plane shows its CUT FLOOR at slice_y instead of disappearing — the
	# whole map stays present at any slice depth (the Stonehearth model).
	var slice_cut := false
	if wy > slice_y:
		wy = slice_y
		slice_cut = true
	# Defects 3/4 fix (2026-06-05): the floor's colour source follows the SOURCE
	# of the removed blocks above. A walk that crosses ANY designated-only block
	# is a plan's floor — strata (plans reveal nothing; designation must not be
	# a free prospecting scanner). Exact colours are earned only when the entire
	# run above was MINED (mining reveals what it exposes). Conservative on
	# mixed runs until they are fully mined; DEV-mining a zone flips its floor
	# strata → exact at that moment, which is the reveal working as intended.
	var crossed_plan := false
	while wy >= 0 and _ovt_cut.has(Vector3i(wx, wy, wz)):
		if not _ovt_mined.has(Vector3i(wx, wy, wz)):
			crossed_plan = true
		wy -= 1
		slice_cut = false   # the cut run, not the plane, owns this floor now
	if wy < 0:
		return {}
	var block_id: int
	if slice_cut or crossed_plan:
		# STRATA-ONLY cut floor (design rule, Alen 2026-06-04; extended to
		# designation floors 2026-06-05): slicing and PLANNING must never reveal
		# undiscovered resources — these floors show the authored rock bands
		# only. Veins/gems/caves become visible exclusively through mining.
		# Bonus: uniform plates greedy-merge into a few large rects.
		block_id = WorldGenerator.get_overview_strata_block_id(wx, wy, wz)
	else:
		block_id = WorldGenerator.get_generated_block_id(wx, wy, wz)
	if BlockRegistry.is_transparent(block_id):
		return {}
	return {
		"wy": wy,
		"block_id": block_id,
		"slice_cut": slice_cut,   # SO-2c: cut floors dim at colour-bake time
	}


func _cache_overview_side_colors(season: String) -> void:
	_overview_rock_color = BlockRegistry.get_color(
		BlockRegistry.get_id(&"base:terrain:rock:rock07"),
		season)


func _free_all_streamed_nodes() -> void:
	if _region_nodes.is_empty() and _chunk_nodes.is_empty() and _dirty_region_queue.is_empty():
		return
	for key: Vector2i in _region_nodes.keys():
		(_region_nodes[key] as MeshInstance3D).queue_free()
	_region_nodes.clear()
	for key: Vector3i in _chunk_nodes.keys():
		(_chunk_nodes[key] as MeshInstance3D).queue_free()
	_chunk_nodes.clear()
	_dirty_queue.clear()
	_dirty_set.clear()
	_dirty_region_queue.clear()
	_dirty_region_set.clear()


# -- View-radius streaming ----------------------------------------------------

func _update_streaming_center() -> void:
	if _block_face_overview_active():
		return
	if _camera_rig == null:
		_camera_rig = _find_camera(get_tree().current_scene)
	if _camera_rig == null:
		return

	var next_chunk := Vector2i(
		clampi(int(floor(_camera_rig.global_position.x / CHUNK_SIZE)), 0, CHUNK_COUNT_X - 1),
		clampi(int(floor(_camera_rig.global_position.z / CHUNK_SIZE)), 0, CHUNK_COUNT_Z - 1))

	if next_chunk == _camera_chunk:
		return

	_camera_chunk = next_chunk
	_enqueue_visible_existing_chunks()
	_unload_far_chunks()


func _enqueue_visible_existing_chunks() -> void:
	if _block_face_overview_active():
		return
	if _camera_chunk.x < 0:
		return

	for col: Vector2i in _visible_columns_center_first():
		WorldGenerator.request_chunk_column(col.x, col.y)
		for cy in range(CHUNK_COUNT_Y):
			if not _chunk_y_is_visible(col.x, cy, col.y):
				continue
			var region_key := _region_key(col.x, col.y)
			if WorldData.chunk_exists(col.x, cy, col.y) and not _region_nodes.has(region_key):
				_enqueue_region(region_key)


func _visible_columns_center_first() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for radius in range(view_radius_chunks + 1):
		for dx in range(-radius, radius + 1):
			for dz in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dz)) != radius:
					continue
				var cx := _camera_chunk.x + dx
				var cz := _camera_chunk.y + dz
				if cx < 0 or cx >= CHUNK_COUNT_X or cz < 0 or cz >= CHUNK_COUNT_Z:
					continue
				if not _chunk_in_radius(cx, cz, view_radius_chunks):
					continue
				result.append(Vector2i(cx, cz))
	return result


func _unload_far_chunks() -> void:
	var to_free: Array[Vector2i] = []
	for key: Vector2i in _region_nodes:
		if not _region_should_exist(key):
			to_free.append(key)

	for key: Vector2i in to_free:
		_free_region_node(key)

	_prune_dirty_queue()


func _prune_dirty_queue() -> void:
	var kept_queue: Array[Vector2i] = []
	_dirty_region_set.clear()
	for key: Vector2i in _dirty_region_queue:
		if _region_should_exist(key):
			kept_queue.append(key)
			_dirty_region_set[key] = true
	_dirty_region_queue = kept_queue


func _chunk_should_be_meshed(cx: int, cy: int, cz: int) -> bool:
	return _chunk_y_is_visible(cx, cy, cz) and _chunk_in_radius(cx, cz, view_radius_chunks)


## All chunk rows from bedrock UP TO the visible row are meshable, so cliff
## faces spanning multiple rows and the world below a slice plane render solid
## (the Stonehearth model: the cut face runs unbroken to the valley floor).
## Solid interior chunks are discarded cheaply at build time by the buried-skip
## in _build_region_geometry — only chunks with exposed faces cost anything.
func _chunk_y_is_visible(cx: int, cy: int, cz: int) -> bool:
	var top_y: int = WorldGenerator.get_column_top_y(cx, cz)
	var visible_y: int = mini(slice_y, top_y)
	var visible_cy: int = clampi(floori(float(visible_y) / float(CHUNK_SIZE)), 0, CHUNK_COUNT_Y - 1)
	return cy <= visible_cy


func _chunk_in_radius(cx: int, cz: int, radius: int) -> bool:
	if _camera_chunk.x < 0:
		return true
	var dx := cx - _camera_chunk.x
	var dz := cz - _camera_chunk.y
	return dx * dx + dz * dz <= radius * radius


# ── Slice visibility ──────────────────────────────────────────────────────────

func _apply_slice_visibility() -> void:
	_set_overview_nodes_visible(_block_face_overview_active())
	if _block_face_overview_active():
		_free_all_streamed_nodes()
		return
	for key: Vector2i in _region_nodes:
		(_region_nodes[key] as MeshInstance3D).visible = _region_should_exist(key)
	_unload_far_chunks()


## Localized slice invalidation (doc 11 Phase 1b). A region's mesh can only
## change with the slice plane if some column in it reaches above the LOWER of
## the two planes — terrain entirely below min(old, new) is untouched by either
## clip, so its geometry is provably identical. This re-enqueues exactly the
## affected live region nodes; regions without nodes are handled by
## _enqueue_visible_existing_chunks (and would mesh with the new slice anyway).
## Also fixes the Phase-0 latent bug: chunk-boundary crossings previously left
## stale geometry on regions that already had nodes.
func _enqueue_regions_for_slice_change(old_y: int, new_y: int) -> void:
	if _block_face_overview_active():
		return
	var low_plane := mini(old_y, new_y)
	for key: Vector2i in _region_nodes.keys():
		if _region_reaches_above(key, low_plane):
			_enqueue_region(key)


## True if any chunk column in the region has terrain above the given Y.
## Reads the generator's per-column max (16x16 heightmap scan per chunk column);
## ~4k int reads per region — negligible next to one region mesh build.
func _region_reaches_above(key: Vector2i, plane_y: int) -> bool:
	var start_cx := key.x * REGION_SIZE
	var start_cz := key.y * REGION_SIZE
	for cx in range(start_cx, mini(CHUNK_COUNT_X, start_cx + REGION_SIZE)):
		for cz in range(start_cz, mini(CHUNK_COUNT_Z, start_cz + REGION_SIZE)):
			if WorldGenerator.get_column_top_y(cx, cz) > plane_y:
				return true
	return false


# ── VisibleVolume contract (doc 11 Phase 3, ref doc 10 rule S5) ───────────────
# THE shared visibility interface for every overlay system (mining overlays
# first; water, entities, and the X-Ray interior set later). Composition order
# when X-Ray lands: clip plane first, then the x-ray set — same as Stonehearth's
# intersect_region_with_visible_volume. Consumers connect to
# visible_volume_changed (emitted at most once per frame, flushed in _process)
# and rebuild reactively; polling is a contract violation.

## Emitted at most once per frame after any visibility-state change (slice step;
## later: x-ray toggles / interior-set changes). Connect overlays here.
signal visible_volume_changed

var _visible_volume_dirty: bool = false


## True if a world block position is inside the visible volume.
## Today: the slice plane. Phase X3 composes the x-ray interior set here.
func is_block_visible(pos: Vector3i) -> bool:
	return pos.y <= slice_y


## Returns the subset of blocks inside the visible volume (order preserved).
func filter_blocks(blocks: Array[Vector3i]) -> Array[Vector3i]:
	if slice_y >= WORLD_SIZE_Y - 1:
		return blocks   # slice off — everything visible, skip the scan
	var out: Array[Vector3i] = []
	for block: Vector3i in blocks:
		if block.y <= slice_y:
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


## Slice tool hook (doc 11 Phase 4.1): the slice tool forces streamed mode while
## active, because overview tiles bake slice_y into their geometry and have no
## cheap per-tile invalidation for a moving plane. Overview tile nodes are
## hidden, never freed — restoring the surface view on tool close is free.
func set_overview_enabled(enabled: bool) -> void:
	if use_block_face_overview == enabled:
		return
	use_block_face_overview = enabled
	_apply_slice_visibility()
	if not _block_face_overview_active():
		_update_streaming_center()
		_enqueue_visible_existing_chunks()


# ── Slice-change timing (doc 11 Phase 0) ─────────────────────────────────────
# Measures what one slice_y change actually costs with the CURRENT invalidation
# (global _enqueue_visible_existing_chunks). This is the baseline the Phase 1
# localized dirty math must beat. Gated by slice_debug_timing; zero work when off.

func _begin_slice_timing(from_y: int, to_y: int) -> void:
	if not slice_debug_timing or from_y == to_y:
		return
	_slice_timing_active = true
	_slice_timing_start_msec = Time.get_ticks_msec()
	_slice_timing_from = from_y
	_slice_timing_to = to_y
	_slice_timing_regions_enqueued = _dirty_region_queue.size() + _dirty_overview_tiles.size()
	_slice_timing_frames = 0
	_slice_timing_max_frame_ms = 0
	_slice_timing_rebuilds_at_start = _region_rebuild_count + _overview_build_count
	# Reset the overview profile accumulators so a profiled slice step reports
	# only its own breakdown (overview_profile must be enabled on the node).
	if overview_profile:
		_ovp_loop_usec = 0
		_ovp_sides_usec = 0
		_ovp_merge_usec = 0
		_ovp_mesh_usec = 0
		_ovp_tiles = 0
		_ovp_max_tile_usec = 0
		_ovp_max_tile_key = Vector2i(-1, -1)
		_ovp_max_breakdown = {}
	print("SliceTiming: slice %d -> %d — %d regions + %d tiles queued, %d region nodes, %d tile nodes, generator %s." % [
		from_y,
		to_y,
		_dirty_region_queue.size(),
		_dirty_overview_tiles.size(),
		_region_nodes.size(),
		_overview_tile_nodes.size(),
		"streaming" if WorldGenerator.is_generating() else "idle",
	])


## Called once per frame from _process while timing is active (t_frame = msec
## stamp taken before this frame's drain — region or overview-tile, whichever
## branch ran). Ends when BOTH rebuild queues are empty AND the generator has
## no pending columns — newly exposed rows may still be streaming in, and
## their meshes are part of the slice change's true cost.
func _update_slice_timing(t_frame: int) -> void:
	_slice_timing_frames += 1
	_slice_timing_max_frame_ms = maxi(_slice_timing_max_frame_ms, Time.get_ticks_msec() - t_frame)
	if not _dirty_region_queue.is_empty():
		return
	if not _dirty_overview_tiles.is_empty():
		return
	if WorldGenerator.is_generating():
		return
	_slice_timing_active = false
	var total_ms := Time.get_ticks_msec() - _slice_timing_start_msec
	print("SliceTiming: slice %d -> %d DONE — %d regions+tiles rebuilt (%d queued at start) over %d frames, %.3f s total, worst frame %d ms." % [
		_slice_timing_from,
		_slice_timing_to,
		(_region_rebuild_count + _overview_build_count) - _slice_timing_rebuilds_at_start,
		_slice_timing_regions_enqueued,
		_slice_timing_frames,
		float(total_ms) / 1000.0,
		_slice_timing_max_frame_ms,
	])
	# Per-step cost breakdown (only when overview_profile is enabled): where the
	# tile time went — worker column loop / side walls / top merge vs main-thread
	# mesh creation — plus the single slowest tile. Diagnose before tuning.
	if overview_profile and _ovp_tiles > 0:
		var total_us := _ovp_loop_usec + _ovp_sides_usec + _ovp_merge_usec + _ovp_mesh_usec
		print("SliceTiming profile: %d tiles — surface_loop %.2f s (%.0f%%), sides %.2f s (%.0f%%), top_merge %.2f s (%.0f%%), mesh_create %.2f s (%.0f%%); slowest tile %s at %.1f ms -> %s" % [
			_ovp_tiles,
			float(_ovp_loop_usec) / 1e6, 100.0 * float(_ovp_loop_usec) / float(maxi(total_us, 1)),
			float(_ovp_sides_usec) / 1e6, 100.0 * float(_ovp_sides_usec) / float(maxi(total_us, 1)),
			float(_ovp_merge_usec) / 1e6, 100.0 * float(_ovp_merge_usec) / float(maxi(total_us, 1)),
			float(_ovp_mesh_usec) / 1e6, 100.0 * float(_ovp_mesh_usec) / float(maxi(total_us, 1)),
			str(_ovp_max_tile_key),
			float(_ovp_max_tile_usec) / 1000.0,
			str(_ovp_max_breakdown),
		])


# ── Camera rig auto-setup ────────────────────────────────────────────────────

## Creates the Camera rig as a sibling of this Renderer node so the rig
## pans independently from the terrain meshes. Skips silently if one already
## exists anywhere in the scene (e.g. manually wired in the editor).
func _setup_camera_rig() -> void:
	_camera_rig = _find_camera(get_tree().current_scene)
	if _camera_rig != null:
		_update_streaming_center()
		return   # already present — nothing to do
	var rig := Camera.new()
	rig.name = "CameraRig"
	get_parent().add_child(rig)
	_camera_rig = rig
	_update_streaming_center()
	print("WorldRenderer: Camera rig created automatically.")


func _find_camera(node: Node) -> Camera:
	if node is Camera:
		return node as Camera
	for child: Node in node.get_children():
		var found := _find_camera(child)
		if found != null:
			return found
	return null


func _elapsed_since_start_seconds(at_msec: int) -> float:
	if _startup_started_msec <= 0 or at_msec <= 0:
		return 0.0
	return float(at_msec - _startup_started_msec) / 1000.0


func _print_startup_performance_report() -> void:
	if _startup_report_printed:
		return
	_startup_report_printed = true

	var now := Time.get_ticks_msec()
	var gen_stats := WorldGenerator.get_streaming_stats()
	var first_mesh_sec := _elapsed_since_start_seconds(_first_visible_mesh_msec)
	var total_sec := _elapsed_since_start_seconds(now)
	var avg_region_ms := 0.0
	if _region_rebuild_count > 0:
		avg_region_ms = float(_region_rebuild_msec_total) / float(_region_rebuild_count)
	var avg_overview_ms := 0.0
	if _overview_build_count > 0:
		avg_overview_ms = float(_overview_build_msec_total) / float(_overview_build_count)
	var avg_column_ms := 0.0
	var column_count := int(gen_stats.get("column_fill_count", 0))
	if column_count > 0:
		avg_column_ms = float(gen_stats.get("column_fill_ms_total", 0)) / float(column_count)

	print("StartupPerformance:")
	print("  total_to_initial_load: %.3f s" % total_sec)
	print("  first_visible_terrain: %.3f s" % first_mesh_sec)
	print("  mode: %s  camera_chunk=%s  slice=%d" % [_inspector_render_mode(), str(_camera_chunk), slice_y])
	print("  world_maps: ready=%s  precompute=%.3f s  ready_at=%.3f s" % [
		str(gen_stats.get("maps_ready", false)),
		float(gen_stats.get("map_precompute_ms", 0)) / 1000.0,
		float(gen_stats.get("maps_ready_ms", 0)) / 1000.0,
	])
	var map_phase_timings: Array = gen_stats.get("map_phase_timings", [])
	if not map_phase_timings.is_empty():
		print("  map_phases:")
		for phase in map_phase_timings:
			var phase_dict: Dictionary = phase
			print("    %s: %.3f s" % [
				String(phase_dict.get("name", "unknown")),
				float(phase_dict.get("ms", 0)) / 1000.0,
			])
	print("  columns: filled=%d  chunks=%d  total=%.3f s  avg=%.2f ms  max=%d ms  requested=%d  queue=%d" % [
		column_count,
		int(gen_stats.get("column_chunks_submitted", 0)),
		float(gen_stats.get("column_fill_ms_total", 0)) / 1000.0,
		avg_column_ms,
		int(gen_stats.get("column_fill_ms_max", 0)),
		int(gen_stats.get("requested_columns", 0)),
		int(gen_stats.get("queue_size", 0)),
	])
	print("  region_meshes: count=%d  nodes=%d  total=%.3f s  avg=%.2f ms  max=%d ms" % [
		_region_rebuild_count,
		_region_nodes.size(),
		float(_region_rebuild_msec_total) / 1000.0,
		avg_region_ms,
		_region_rebuild_msec_max,
	])
	print("  overview_tiles: count=%d  nodes=%d  total=%.3f s  avg=%.2f ms  max=%d ms  active=%s" % [
		_overview_build_count,
		_overview_tile_nodes.size(),
		float(_overview_build_msec_total) / 1000.0,
		avg_overview_ms,
		_overview_build_msec_max,
		str(_block_face_overview_active()),
	])
	print("  overview_startup: center=%s  radius_tiles=%d  goal=%d  queue_remaining=%d" % [
		str(_overview_startup_center),
		overview_startup_radius_tiles,
		_overview_startup_tile_goal,
		_dirty_overview_tiles.size(),
	])
	print("  overview_state: startup_ready=%s  startup_ready_at=%.3f s  full_complete=%s  full_complete_at=%.3f s" % [
		str(_overview_startup_ready_msec > 0),
		_elapsed_since_start_seconds(_overview_startup_ready_msec),
		str(_overview_built),
		_elapsed_since_start_seconds(_overview_complete_msec),
	])
	print("  meshes_built_counter: %d" % _meshes_built)


func get_render_stats() -> Dictionary:
	var overview_active := _block_face_overview_active()
	return {
		"camera_chunk": _camera_chunk,
		"view_radius_chunks": view_radius_chunks,
		"unload_radius_chunks": unload_radius_chunks,
		"mesh_nodes": _region_nodes.size(),
		"dirty_queue": _dirty_region_queue.size(),
		"meshes_built": _meshes_built,
		"initial_load": _initial_load,
		"slice_y": slice_y,
		"render_mode": _inspector_render_mode(),
		"overview_active": overview_active,
		"overview_built": _overview_built,
		"overview_step": OVERVIEW_STEP,
		"overview_tile_size": OVERVIEW_TILE_SIZE,
		"overview_tiles": _overview_tile_nodes.size(),
		"overview_dirty_tiles": _dirty_overview_tiles.size(),
		"overview_sides": show_overview_sides,
		"overview_sampled_top_faces": _overview_sampled_top_faces,
		"overview_merged_top_faces": _overview_merged_top_faces,
		"overview_side_faces": _overview_side_faces,
		"overview_validation_samples": _overview_validation_samples,
		"overview_validation_mismatches": _overview_validation_mismatches,
		"startup_elapsed_ms": Time.get_ticks_msec() - _startup_started_msec if _startup_started_msec > 0 else 0,
		"first_visible_mesh_ms": _first_visible_mesh_msec - _startup_started_msec if _first_visible_mesh_msec > 0 and _startup_started_msec > 0 else 0,
		"region_rebuild_count": _region_rebuild_count,
		"region_rebuild_ms_total": _region_rebuild_msec_total,
		"region_rebuild_ms_max": _region_rebuild_msec_max,
		"overview_build_count": _overview_build_count,
		"overview_build_ms_total": _overview_build_msec_total,
		"overview_build_ms_max": _overview_build_msec_max,
		"overview_startup_center": _overview_startup_center,
		"overview_startup_radius_tiles": overview_startup_radius_tiles,
		"overview_startup_tile_goal": _overview_startup_tile_goal,
		"overview_startup_ready_ms": _overview_startup_ready_msec - _startup_started_msec if _overview_startup_ready_msec > 0 and _startup_started_msec > 0 else 0,
		"overview_complete_ms": _overview_complete_msec - _startup_started_msec if _overview_complete_msec > 0 and _startup_started_msec > 0 else 0,
	}


# ── Material ──────────────────────────────────────────────────────────────────

func _create_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness    = 1.0
	mat.metallic     = 0.0
	mat.cull_mode    = BaseMaterial3D.CULL_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	return mat
