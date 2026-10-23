extends RefCounted

## The block-face overview for WorldRenderer: one MeshInstance3D per 32x32-column
## tile, built on WorkerThreadPool and uploaded within a frame budget. Dirty
## tiles are queued and drained by process_frame(). Owns the tile queue, the
## immutable cut/mined snapshots the workers read, tile meshing, the startup and
## slice-change timing reports and the render statistics.
##
## WorldRenderer keeps the exports, the slice plane and the cut sets; this reads
## them through `renderer`. Worker threads read only the batch snapshots
## (_ovt_*), the generator maps and BlockRegistry, and write only their own
## result slot.

const WORLD_SIZE_X: int = WorldData.WORLD_SIZE_X
const WORLD_SIZE_Y: int = WorldData.WORLD_SIZE_Y
const WORLD_SIZE_Z: int = WorldData.WORLD_SIZE_Z
const OVERVIEW_STEP: int = 1
const OVERVIEW_TILE_SIZE: int = 32
const RENDER_MODE := "block-face overview exact"

## Luminance factor for SLICE-CUT strata floors (doc 11 Phase SO-2c): cut planes
## read as "inside the mountain", never as walkable ground. Stonehearth's number
## for de-emphasized geometry (its darkened shader family) is 0.5; theirs comes
## from fog-of-war — when Deepdraft grows visibility regions (doc 06), this
## constant folds into that multiply and dies. Luminance-only: identity untouched
## (Hard Rule 9). Tune in-engine.
const SLICE_CUT_DIM: float = 0.5

var renderer: Node3D

## Full-world scheduling is separate from local dirty work. Discovery/mining
## can enqueue tiles before the first frame or after global invalidation.
var _overview_initialized: bool = false
var overview_built: bool = false
var _overview_rebuild_queued: bool = false
var _overview_rock_color: Color = Color.GRAY
var _overview_sampled_top_faces: int = 0
var _overview_merged_top_faces: int = 0
var _overview_side_faces: int = 0
var _overview_validation_samples: int = 0
var _overview_validation_mismatches: int = 0
var overview_tile_nodes: Dictionary = {}
var _overview_tile_stats: Dictionary = {}
var dirty_overview_tiles: Array[Vector2i] = []
var _dirty_overview_tile_set: Dictionary = {}
# Immutable mined-set snapshot for the threaded overview build (same pattern as
# _ovt_cut): the cut-floor colour rule (defects 3/4) reads it on worker threads.
var _ovt_mined: Dictionary = {}
# Immutable cut-block snapshot read by the overview build (incl. worker threads).
# Set on the main thread before each batch so workers never read the live
# cut set while mining could mutate it.
var _ovt_cut: Dictionary = {}
## Invalidate on input changes; reuse immutable dictionaries across tile batches.
## Replacement is allowed only after every reader of the previous batch finishes.
## The flag forces a full copy (global invalidation); block edits instead list
## their cells in _snapshot_dirty_cells, patched in place between batches — a
## full copy per mining commit cost ~30 ms in a 50k-cut colony.
var _overview_snapshot_dirty := true
var _snapshot_dirty_cells: Dictionary = {}   # cell -> true
# Group-task scratch for the threaded overview build (main thread sets these
# before dispatch; workers read _ovt_batch/_ovt_season read-only and write their
# own disjoint _ovt_results slot).
var _ovt_batch: Array[Vector2i] = []
var _ovt_results: Array = []
var _ovt_season: String = ""
var _ovt_slice: int = WorldData.MAX_Y
var _ovt_task: int = -1
var ovt_building := false
var _ovt_assign_index := 0
var _ovt_revisions: Array[int] = []
var _ovt_epoch := 0
var _overview_epoch := 0
var _overview_revisions: Dictionary = {}
var _overview_stale_results := 0
const OVERVIEW_UPLOAD_BUDGET_USEC := 4000
# Per-section profiling accumulators (usec), only written when the renderer's overview_profile is on.
var _ovp_loop_usec: int = 0
var _ovp_sides_usec: int = 0
var _ovp_merge_usec: int = 0
var _ovp_mesh_usec: int = 0
var _ovp_tiles: int = 0
var _ovp_max_tile_usec: int = 0
var _ovp_max_tile_key: Vector2i = Vector2i(-1, -1)
var _ovp_max_breakdown: Dictionary = {}

var _meshes_built: int = 0
var startup_started_msec: int = 0
var _first_visible_mesh_msec: int = 0
var _overview_build_msec_total: int = 0
var _overview_build_msec_max: int = 0
var _overview_build_count: int = 0
var _terrain_drain_max_usec: int = 0
var _terrain_worker_wait_max_usec: int = 0
var _terrain_upload_max_usec: int = 0
var _overview_startup_tile_goal: int = 0
var _overview_startup_center: Vector2i = Vector2i(-1, -1)
var _overview_startup_ready_msec: int = 0
var _overview_complete_msec: int = 0
var _startup_report_printed: bool = false

## True until the startup overview radius is built (or the full overview completes).
var initial_load: bool = true

# ── Slice-change timing instrumentation (doc 11 Phase 0; gated by slice_debug_timing) ──
var _slice_timing_active: bool = false
var _slice_timing_start_msec: int = 0
var _slice_timing_from: int = 0
var _slice_timing_to: int = 0
var _slice_timing_tiles_enqueued: int = 0
var _slice_timing_frames: int = 0
var _slice_timing_max_frame_ms: int = 0
var _slice_timing_rebuilds_at_start: int = 0


func _init(owner: Node3D) -> void:
	renderer = owner


## Join only on teardown/reload, before the generator can replace its immutable
## maps. Normal frames only collect jobs that have already completed.
func finish_pending() -> void:
	if _ovt_task >= 0:
		WorkerThreadPool.wait_for_group_task_completion(_ovt_task)
	_ovt_task = -1
	ovt_building = false
	_ovt_results.clear()
	_ovt_batch.clear()
	_overview_epoch += 1
	_overview_initialized = false
	overview_built = false


## One frame of tile work, then the slice-change timing report when active.
func process_frame() -> void:
	# Stamp unconditionally — timing can begin between frames, and a zero
	# stamp poisoned the worst-frame stat (measured against engine start).
	var t_frame := Time.get_ticks_msec()
	_update_block_face_overview()
	if _slice_timing_active:
		_update_slice_timing(t_frame)


## Cut-set edits at these cells: patch the snapshots and rebuild their tiles.
func invalidate_cells(blocks: Array[Vector3i]) -> void:
	for block: Vector3i in blocks: _snapshot_dirty_cells[block] = true
	_enqueue_overview_tiles_for_blocks(blocks)


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
			color = BlockRegistry.get_terrain_color(exact_id, _ovt_season if ovt_building else WorldClock.season) \
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
	return BlockRegistry.get_terrain_color(block_id, _ovt_season if ovt_building else WorldClock.season)


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



# -- Block-face overview ------------------------------------------------------

func invalidate_global() -> void:
	_overview_snapshot_dirty = true
	_overview_epoch += 1
	_overview_revisions.clear()
	_overview_initialized = false
	overview_built = false
	_overview_rebuild_queued = false
	dirty_overview_tiles.clear()
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
	for key: Vector2i in overview_tile_nodes.keys():
		(overview_tile_nodes[key] as MeshInstance3D).queue_free()
	overview_tile_nodes.clear()


## Slice-change invalidation for the far field (doc 11 Phase SO): only tiles
## whose visible terrain reaches above the LOWER of the two planes can change —
## a tile entirely below both planes is cut by neither. Affected tiles plus
## their 4-neighbours (boundary walls read neighbour tops) are re-enqueued
## through the normal threaded/budgeted tile queue. Lowland tiles never rebuild
## for mountain-depth slices. ~1k Vector2i range reads; trivial.
## Load fast-path: when a save is mid-restore, adopt its slice height BEFORE
## the first overview tiles are queued, so every tile builds cut correctly the
## first time. Without this, the startup tiles built at the default plane
## (127); the slice restore (priority 80) then re-queued and re-built them —
## the most visible tiles (the startup radius around the camera) built twice,
## popping uncut before re-cutting. Called at the moment the tile queue is
## still empty, so the setter's slice-change enqueue early-outs; when
## SliceController.restore_state later applies the same value, old_y == v
## skips the requeue again.
func _apply_pending_restore_slice() -> void:
	if SaveManager == null or not SaveManager.has_method("pending_slice_for_new_scene"):
		return
	var target := int(SaveManager.call("pending_slice_for_new_scene", renderer.slice_y))
	if target != renderer.slice_y:
		renderer.slice_y = target


func enqueue_tiles_for_slice_change(old_y: int, new_y: int) -> void:
	if overview_tile_nodes.is_empty() and not _overview_rebuild_queued:
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
		enqueue_tile(key)
	overview_built = false


func _enqueue_overview_tiles_for_blocks(blocks: Array[Vector3i]) -> void:
	for block: Vector3i in blocks:
		_enqueue_overview_tile_for_world(block.x, block.z)
		_enqueue_overview_tile_for_world(block.x - 1, block.z)
		_enqueue_overview_tile_for_world(block.x + 1, block.z)
		_enqueue_overview_tile_for_world(block.x, block.z - 1)
		_enqueue_overview_tile_for_world(block.x, block.z + 1)
	overview_built = false


func _enqueue_overview_tile_for_world(wx: int, wz: int) -> void:
	if wx < 0 or wx >= WORLD_SIZE_X or wz < 0 or wz >= WORLD_SIZE_Z:
		return
	enqueue_tile(Vector2i(
		floori(float(wx) / float(OVERVIEW_TILE_SIZE)),
		floori(float(wz) / float(OVERVIEW_TILE_SIZE))))


func enqueue_tile(key: Vector2i) -> void:
	_overview_revisions[key] = int(_overview_revisions.get(key, 0)) + 1
	if _dirty_overview_tile_set.has(key):
		return
	_dirty_overview_tile_set[key] = true
	dirty_overview_tiles.append(key)


func _get_or_create_overview_tile_node(key: Vector2i) -> MeshInstance3D:
	if overview_tile_nodes.has(key):
		return overview_tile_nodes[key] as MeshInstance3D

	var mi := MeshInstance3D.new()
	mi.name = "BlockFaceOverview_%d_%d" % [key.x, key.y]
	mi.material_override = renderer.terrain_material()
	preload("res://scripts/components/TerrainLighting.gd").configure_mesh(mi)
	renderer.add_child(mi)
	overview_tile_nodes[key] = mi
	return mi


func _free_overview_tile_node(key: Vector2i) -> void:
	if not overview_tile_nodes.has(key):
		return
	(overview_tile_nodes[key] as MeshInstance3D).queue_free()
	overview_tile_nodes.erase(key)


func _set_overview_nodes_visible(make_visible: bool) -> void:
	for key: Vector2i in overview_tile_nodes:
		(overview_tile_nodes[key] as MeshInstance3D).visible = make_visible


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


func _update_block_face_overview() -> void:
	_set_overview_nodes_visible(true)

	var stats := WorldGenerator.get_streaming_stats()
	if not stats.get("maps_ready", false):
		return
	if not _overview_initialized:
		_apply_pending_restore_slice()
		_queue_full_overview_rebuild()
	_drain_overview_tile_queue()
	if initial_load and _overview_startup_tile_goal > 0 and overview_tile_nodes.size() >= _overview_startup_tile_goal:
		initial_load = false
		_overview_startup_ready_msec = Time.get_ticks_msec()
		print("WorldRenderer: startup overview radius ready (%d/%d tiles built, queue=%d)." % [
			overview_tile_nodes.size(),
			_overview_startup_tile_goal,
			dirty_overview_tiles.size(),
		])
		_print_startup_performance_report()
	if not dirty_overview_tiles.is_empty() or ovt_building:
		return
	if _overview_rebuild_queued:
		_overview_rebuild_queued = false
		overview_built = true
		_overview_complete_msec = Time.get_ticks_msec()
		initial_load = false
		print("WorldRenderer: built block-face overview tiles (%d tiles, step=%d, tops %d->%d, sides %d, validation mismatches %d/%d) in %.2f s since startup." % [
			overview_tile_nodes.size(),
			OVERVIEW_STEP,
			_overview_sampled_top_faces,
			_overview_merged_top_faces,
			_overview_side_faces,
			_overview_validation_mismatches,
			_overview_validation_samples,
			_elapsed_since_start_seconds(_overview_complete_msec),
		])
		if renderer.overview_profile and _ovp_tiles > 0:
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
		overview_built = true


func _queue_full_overview_rebuild() -> void:
	invalidate_global()
	var tile_count_x := ceili(float(WORLD_SIZE_X) / float(OVERVIEW_TILE_SIZE))
	var tile_count_z := ceili(float(WORLD_SIZE_Z) / float(OVERVIEW_TILE_SIZE))
	var center := _overview_startup_center_tile(tile_count_x, tile_count_z)
	_overview_startup_center = center
	# All material variants are final at maps_ready. Build visible tiles first,
	# then continue outward without the former grass-band deferral/requeue.
	_overview_startup_tile_goal = 0
	for key in _overview_tiles_center_first(center, tile_count_x, tile_count_z):
		enqueue_tile(key)
		if _overview_tile_distance(key, center) <= renderer.overview_startup_radius_tiles:
			_overview_startup_tile_goal += 1
	_overview_initialized = true
	_overview_rebuild_queued = true


func _overview_startup_center_tile(tile_count_x: int, tile_count_z: int) -> Vector2i:
	var camera_rig: Node3D = renderer.camera_rig()
	if camera_rig == null:
		return Vector2i(floori(float(tile_count_x) * 0.5), floori(float(tile_count_z) * 0.5))
	return Vector2i(
		clampi(int(floor(camera_rig.global_position.x / float(OVERVIEW_TILE_SIZE))), 0, tile_count_x - 1),
		clampi(int(floor(camera_rig.global_position.z / float(OVERVIEW_TILE_SIZE))), 0, tile_count_z - 1))


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
	var drain_started := Time.get_ticks_usec()
	if _ovt_task >= 0:
		if not WorkerThreadPool.is_group_task_completed(_ovt_task): return
		var wait_started := Time.get_ticks_usec()
		WorkerThreadPool.wait_for_group_task_completion(_ovt_task)
		_terrain_worker_wait_max_usec = maxi(_terrain_worker_wait_max_usec, Time.get_ticks_usec()-wait_started)
		_ovt_task = -1
	if ovt_building:
		_consume_overview_results(drain_started)
		_terrain_drain_max_usec = maxi(_terrain_drain_max_usec, Time.get_ticks_usec()-drain_started)
		# Start the next batch on the next frame so upload and dispatch have a
		# bounded combined cost. Existing meshes remain visible while workers run.
		return
	if dirty_overview_tiles.is_empty(): return
	# Read-only-during-build state, set once on the main thread before any worker
	# runs. Never replace these snapshots until this batch has been consumed.
	_cache_overview_side_colors(WorldClock.season)
	_refresh_overview_snapshots()
	_ovt_season = WorldClock.season
	_ovt_slice = renderer.slice_y
	_ovt_epoch = _overview_epoch
	_ovt_revisions.clear()

	# Pull this frame's batch off the dirty queue.
	var batch: Array[Vector2i] = []
	while dirty_overview_tiles.size() > 0 and batch.size() < renderer.overview_tiles_per_frame:
		var key: Vector2i = dirty_overview_tiles.pop_front()
		_dirty_overview_tile_set.erase(key)
		batch.append(key)
		_ovt_revisions.append(int(_overview_revisions.get(key, 0)))
	if batch.is_empty():
		return

	_ovt_batch = batch
	_ovt_results = []
	_ovt_results.resize(batch.size())
	_ovt_assign_index = 0
	ovt_building = true
	overview_built = false
	if renderer.overview_threaded:
		_ovt_task = WorkerThreadPool.add_group_task(
			Callable(self, "_overview_build_worker"), batch.size(), -1, false, "overview_tiles")
	else:
		for i in batch.size(): _overview_build_worker(i)
		_consume_overview_results(drain_started)
	_terrain_drain_max_usec = maxi(_terrain_drain_max_usec, Time.get_ticks_usec()-drain_started)


func _refresh_overview_snapshots() -> void:
	assert(not ovt_building and _ovt_task < 0, "Overview snapshots still have active readers")
	var visual_cut: Dictionary = renderer.visual_cut_blocks()
	var discovered: Dictionary = renderer.discovered_cave_blocks()
	var debug_caves: Dictionary = renderer.debug_cave_blocks()
	@warning_ignore("integer_division")
	if _overview_snapshot_dirty or _snapshot_dirty_cells.size() > visual_cut.size() / 4:
		_ovt_cut = visual_cut.duplicate()
		_ovt_mined = discovered.duplicate()
		_ovt_mined.merge(debug_caves)
		_ovt_mined.merge(WorldData.terrain_overrides())
		_overview_snapshot_dirty = false
		_snapshot_dirty_cells.clear()
		return
	# No batch is reading (asserted above), so membership is patched in place.
	for cell: Vector3i in _snapshot_dirty_cells:
		if visual_cut.has(cell): _ovt_cut[cell] = true
		else: _ovt_cut.erase(cell)
		if discovered.has(cell) \
				or debug_caves.has(cell) or WorldData.has_terrain_override(cell):
			_ovt_mined[cell] = true
		else: _ovt_mined.erase(cell)
	_snapshot_dirty_cells.clear()


func _overview_result_is_current(index: int) -> bool:
	return _ovt_epoch == _overview_epoch and _ovt_slice == renderer.slice_y \
		and _ovt_season == WorldClock.season \
		and _ovt_revisions[index] == int(_overview_revisions.get(_ovt_batch[index], 0))


func _consume_overview_results(started: int) -> void:
	while _ovt_assign_index < _ovt_batch.size():
		var i := _ovt_assign_index
		var key := _ovt_batch[i]
		if _overview_result_is_current(i):
			_assign_overview_tile(key, _ovt_results[i])
			_meshes_built += 1
		else:
			_overview_stale_results += 1
			# A global reset already schedules a complete replacement. Local
			# changes must explicitly keep this tile queued for a fresh snapshot.
			if _ovt_epoch == _overview_epoch: enqueue_tile(key)
		_ovt_assign_index += 1
		if Time.get_ticks_usec()-started >= OVERVIEW_UPLOAD_BUDGET_USEC: break
	_recompute_overview_stats()
	if _ovt_assign_index == _ovt_batch.size():
		ovt_building = false
		_ovt_batch.clear()
		_ovt_results.clear()


## WorkerThreadPool group-task body: builds one tile of the current batch into its
## own results slot. Pure read of shared state (see _build_overview_tile_geometry).
func _overview_build_worker(i: int) -> void:
	_ovt_results[i] = _build_overview_tile_geometry(_ovt_batch[i], _ovt_season)


# PURE geometry build for one overview tile. Reads only read-only state
# (WorldGenerator maps/noise, BlockRegistry, _ovt_cut, _overview_rock_color
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
	# Renderer exports are read once per tile, not per column.
	var prof: bool = renderer.overview_profile
	var validate_ids: bool = renderer.overview_validate_block_ids
	var show_sides: bool = renderer.show_overview_sides
	var edge_y := float(renderer.overview_edge_bottom_y)
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
			# Debug-only cross-check; off by default (see WorldRenderer.overview_validate_block_ids).
			if validate_ids:
				var generated_id := WorldGenerator.get_generated_block_id(wx, wy, wz)
				validation_samples += 1
				if generated_id != block_id:
					validation_mismatches += 1

			var color := BlockRegistry.get_terrain_color(block_id, season)
			# SO-2c: slice-cut strata floors dim to read as "inside the
			# mountain", never walkable ground. Luminance-only (Hard Rule 9).
			var sliced: bool = surface.get("slice_cut", false)
			if sliced:
				color = slice_cut_color(color)
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
			if show_sides:
				if prof:
					var s := Time.get_ticks_usec()
					_add_overview_sides(wx, wz, step, float(wy + 1), color, edge_y, verts, norms, cols, indices)
					t_sides_usec += Time.get_ticks_usec() - s
				else:
					_add_overview_sides(wx, wz, step, float(wy + 1), color, edge_y, verts, norms, cols, indices)

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
	var upload_started := Time.get_ticks_usec()
	if result.is_empty():
		_free_overview_tile_node(tile_key)
		_overview_tile_stats.erase(tile_key)
		return

	var t_mesh0 := Time.get_ticks_usec() if renderer.overview_profile else 0
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
	_terrain_upload_max_usec = maxi(_terrain_upload_max_usec, Time.get_ticks_usec()-upload_started)

	if renderer.overview_profile:
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
		and a.get("color", Color.MAGENTA) == b.get("color", Color.TRANSPARENT) \
		and bool(a.get("sliced", false)) == bool(b.get("sliced", false))


func _add_overview_sides(
		wx: int,
		wz: int,
		step: int,
		top_y: float,
		top_color: Color,
		edge_y: float,
		verts: PackedVector3Array,
		norms: PackedVector3Array,
		cols: PackedColorArray,
		indices: PackedInt32Array) -> void:

	var size := float(mini(step, mini(WORLD_SIZE_X - wx, WORLD_SIZE_Z - wz)))
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
	# Slice-aware (Phase SO): a neighbour above the plane is clamped to its cut
	# top, so boundary walls hang from the cut floor, not the world bottom.
	var wy := WorldData.visible_top_y(wx, wz, WorldGenerator.get_surface_y(wx, wz),
		_ovt_slice if ovt_building else renderer.slice_y, _ovt_cut)
	return edge_y if wy < 0 else float(wy + 1)


func _overview_visible_surface_after_cut(wx: int, wz: int) -> Dictionary:
	# Slice-aware far field (doc 11 Phase SO): a column whose surface is above
	# the plane shows its CUT FLOOR at slice_y instead of disappearing — the
	# whole map stays present at any slice depth (the Stonehearth model).
	var surface := WorldGenerator.get_surface_y(wx, wz)
	var cut_y: int = _ovt_slice if ovt_building else renderer.slice_y
	var start := mini(surface, cut_y)
	var wy := WorldData.visible_top_y(wx, wz, surface, cut_y, _ovt_cut)
	if wy < 0:
		return {}
	# The cut run, not the plane, owns the floor once any cut cell was crossed.
	var slice_cut := surface > cut_y and wy == start
	# Defects 3/4 fix (2026-06-05): the floor's colour source follows the SOURCE
	# of the removed blocks above. A walk that crosses ANY designated-only block
	# is a plan's floor — strata (plans reveal nothing; designation must not be
	# a free prospecting scanner). Exact colours are earned only when the entire
	# run above was MINED (mining reveals what it exposes). Conservative on
	# mixed runs until they are fully mined; DEV-mining a zone flips its floor
	# strata → exact at that moment, which is the reveal working as intended.
	var crossed_plan := false
	for y in range(wy + 1, start + 1):
		if not _ovt_mined.has(Vector3i(wx, y, wz)):
			crossed_plan = true
			break
	var block_id: int
	if slice_cut or crossed_plan:
		# STRATA-ONLY cut floor (design rule, Alen 2026-06-04; extended to
		# designation floors 2026-06-05): slicing and PLANNING must never reveal
		# undiscovered resources — these floors show the authored material strata
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


## Shared by natural overview plates and constructed stone cut by the slice.
## Only artificial cut faces dim; exposed tops and vertical faces keep their color.
static func slice_cut_color(color: Color) -> Color:
	# Tagged terrain cut planes use quiet detail. Imported floor art keeps alpha=1.
	var tag := roundi(color.a * 16.0)
	var alpha := color.a + 0.5 if tag > 0 and tag < 8 else color.a
	return Color(color.r * SLICE_CUT_DIM, color.g * SLICE_CUT_DIM, color.b * SLICE_CUT_DIM, alpha)


func _cache_overview_side_colors(season: String) -> void:
	_overview_rock_color = BlockRegistry.get_terrain_color(
		BlockRegistry.get_id(&"base:terrain:rock:rock07"),
		season)


# ── Slice-change timing (doc 11 Phase 0) ─────────────────────────────────────
# Measures what one slice_y change costs: tiles re-enqueued, frames and wall
# time until the tile queue drains. Gated by slice_debug_timing; zero work when off.

func begin_slice_timing(from_y: int, to_y: int) -> void:
	if not renderer.slice_debug_timing or from_y == to_y:
		return
	_slice_timing_active = true
	_slice_timing_start_msec = Time.get_ticks_msec()
	_slice_timing_from = from_y
	_slice_timing_to = to_y
	_slice_timing_tiles_enqueued = dirty_overview_tiles.size()
	_slice_timing_frames = 0
	_slice_timing_max_frame_ms = 0
	_slice_timing_rebuilds_at_start = _overview_build_count
	# Reset the overview profile accumulators so a profiled slice step reports
	# only its own breakdown (overview_profile must be enabled on the renderer).
	if renderer.overview_profile:
		_ovp_loop_usec = 0
		_ovp_sides_usec = 0
		_ovp_merge_usec = 0
		_ovp_mesh_usec = 0
		_ovp_tiles = 0
		_ovp_max_tile_usec = 0
		_ovp_max_tile_key = Vector2i(-1, -1)
		_ovp_max_breakdown = {}
	print("SliceTiming: slice %d -> %d — %d tiles queued, %d tile nodes." % [
		from_y,
		to_y,
		dirty_overview_tiles.size(),
		overview_tile_nodes.size(),
	])


## Called once per frame from _process while timing is active (t_frame = msec
## stamp taken before this frame's tile drain). Ends when the tile queue is
## empty and no batch is in flight.
func _update_slice_timing(t_frame: int) -> void:
	_slice_timing_frames += 1
	_slice_timing_max_frame_ms = maxi(_slice_timing_max_frame_ms, Time.get_ticks_msec() - t_frame)
	if not dirty_overview_tiles.is_empty() or ovt_building:
		return
	if WorldGenerator.is_generating():
		return
	_slice_timing_active = false
	var total_ms := Time.get_ticks_msec() - _slice_timing_start_msec
	print("SliceTiming: slice %d -> %d DONE — %d tiles rebuilt (%d queued at start) over %d frames, %.3f s total, worst frame %d ms." % [
		_slice_timing_from,
		_slice_timing_to,
		_overview_build_count - _slice_timing_rebuilds_at_start,
		_slice_timing_tiles_enqueued,
		_slice_timing_frames,
		float(total_ms) / 1000.0,
		_slice_timing_max_frame_ms,
	])
	# Per-step cost breakdown (only when overview_profile is enabled): where the
	# tile time went — worker column loop / side walls / top merge vs main-thread
	# mesh creation — plus the single slowest tile. Diagnose before tuning.
	if renderer.overview_profile and _ovp_tiles > 0:
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


func _elapsed_since_start_seconds(at_msec: int) -> float:
	if startup_started_msec <= 0 or at_msec <= 0:
		return 0.0
	return float(at_msec - startup_started_msec) / 1000.0


func _print_startup_performance_report() -> void:
	if _startup_report_printed:
		return
	_startup_report_printed = true

	var now := Time.get_ticks_msec()
	var gen_stats := WorldGenerator.get_streaming_stats()
	var first_mesh_sec := _elapsed_since_start_seconds(_first_visible_mesh_msec)
	var total_sec := _elapsed_since_start_seconds(now)
	var avg_overview_ms := 0.0
	if _overview_build_count > 0:
		avg_overview_ms = float(_overview_build_msec_total) / float(_overview_build_count)

	print("StartupPerformance:")
	print("  total_to_initial_load: %.3f s" % total_sec)
	print("  first_visible_terrain: %.3f s" % first_mesh_sec)
	print("  mode: %s  slice=%d" % [RENDER_MODE, renderer.slice_y])
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
	print("  overview_tiles: count=%d  nodes=%d  total=%.3f s  avg=%.2f ms  max=%d ms" % [
		_overview_build_count,
		overview_tile_nodes.size(),
		float(_overview_build_msec_total) / 1000.0,
		avg_overview_ms,
		_overview_build_msec_max,
	])
	print("  overview_startup: center=%s  radius_tiles=%d  goal=%d  queue_remaining=%d" % [
		str(_overview_startup_center),
		renderer.overview_startup_radius_tiles,
		_overview_startup_tile_goal,
		dirty_overview_tiles.size(),
	])
	print("  overview_state: startup_ready=%s  startup_ready_at=%.3f s  full_complete=%s  full_complete_at=%.3f s" % [
		str(_overview_startup_ready_msec > 0),
		_elapsed_since_start_seconds(_overview_startup_ready_msec),
		str(overview_built),
		_elapsed_since_start_seconds(_overview_complete_msec),
	])
	print("  meshes_built_counter: %d" % _meshes_built)



func render_stats(loading_complete: bool) -> Dictionary:
	return {
		"loading_complete": loading_complete,
		"meshes_built": _meshes_built,
		"initial_load": initial_load,
		"slice_y": renderer.slice_y,
		"render_mode": RENDER_MODE,
		"overview_built": overview_built,
		"overview_in_flight": ovt_building,
		"overview_stale_results": _overview_stale_results,
		"overview_step": OVERVIEW_STEP,
		"overview_tile_size": OVERVIEW_TILE_SIZE,
		"overview_tiles": overview_tile_nodes.size(),
		"overview_dirty_tiles": dirty_overview_tiles.size(),
		"overview_sides": renderer.show_overview_sides,
		"overview_sampled_top_faces": _overview_sampled_top_faces,
		"overview_merged_top_faces": _overview_merged_top_faces,
		"overview_side_faces": _overview_side_faces,
		"overview_validation_samples": _overview_validation_samples,
		"overview_validation_mismatches": _overview_validation_mismatches,
		"startup_elapsed_ms": Time.get_ticks_msec() - startup_started_msec if startup_started_msec > 0 else 0,
		"first_visible_mesh_ms": _first_visible_mesh_msec - startup_started_msec if _first_visible_mesh_msec > 0 and startup_started_msec > 0 else 0,
		"overview_build_count": _overview_build_count,
		"terrain_drain_max_ms": _terrain_drain_max_usec/1000.0,
		"terrain_worker_wait_max_ms": _terrain_worker_wait_max_usec/1000.0,
		"terrain_upload_max_ms": _terrain_upload_max_usec/1000.0,
		"overview_build_ms_total": _overview_build_msec_total,
		"overview_build_ms_max": _overview_build_msec_max,
		"overview_startup_center": _overview_startup_center,
		"overview_startup_radius_tiles": renderer.overview_startup_radius_tiles,
		"overview_startup_tile_goal": _overview_startup_tile_goal,
		"overview_startup_ready_ms": _overview_startup_ready_msec - startup_started_msec if _overview_startup_ready_msec > 0 and startup_started_msec > 0 else 0,
		"overview_complete_ms": _overview_complete_msec - startup_started_msec if _overview_complete_msec > 0 and startup_started_msec > 0 else 0,
	}

