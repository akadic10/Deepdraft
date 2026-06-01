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
		slice_y = v
		_apply_slice_visibility()
		_enqueue_visible_existing_chunks()

## XZ chunk radius around the camera that is allowed to build terrain meshes.
## The fog in debug_world.tscn hides this streaming boundary.
@export_range(1, 64, 1) var view_radius_chunks: int = 5

## Mesh nodes farther than this XZ radius are freed. Keep this slightly larger
## than view_radius_chunks so small camera movements do not churn nodes.
@export_range(1, 80, 1) var unload_radius_chunks: int = 6

## Extra chunk layers rendered below the current visible surface/slice layer.
## 0 is fastest for surface view. 1 keeps a little vertical context for slopes
## and shallow cutaways without drawing every hidden cave below the grass.
@export_range(0, 8, 1) var vertical_context_chunks: int = 0

## Chunk meshes built per frame. Keep this conservative until the block-faithful
## overview mesh replaces full chunk rendering for high-altitude surface views.
@export var meshes_per_frame: int = 4

## While the queue is still draining the first time, build up to this many per
## frame. Once caught up we fall back to meshes_per_frame for smooth in-game edits.
@export var meshes_per_frame_initial: int = 12

## Exact full-world overview mesh for high-altitude surface views. It emits top
## faces plus vertical faces where neighbouring columns are lower, so terrain
## bands stay block-accurate while the camera is zoomed out.
@export var use_block_face_overview: bool = true
@export var overview_slice_threshold: int = 96
@export var show_overview_sides: bool = true
@export_range(0, 128, 1) var overview_edge_bottom_y: int = 0
@export_range(1, 64, 1) var overview_tiles_per_frame: int = 8
@export_range(0, 32, 1) var overview_startup_radius_tiles: int = 5

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
var _overview_tile_side_faces_working: int = 0
var _visual_cut_blocks: Dictionary = {}
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

	_camera_rig = _find_camera(get_tree().current_scene)
	if _camera_rig != null and not _block_face_overview_active():
		_update_streaming_center()

	# Auto-create the camera rig if one isn't already in the scene.
	# Uses call_deferred so the full scene tree is ready before we add to it.
	call_deferred("_setup_camera_rig")

	if auto_generate:
		_startup_started_msec = Time.get_ticks_msec()
		WorldGenerator.generate(world_seed)
		if not _block_face_overview_active():
			_enqueue_visible_existing_chunks()
		print("WorldRenderer: generation started (seed %d)." % WorldGenerator.world_seed)


func _process(_delta: float) -> void:
	if _block_face_overview_active():
		_update_block_face_overview()
		return

	_update_streaming_center()
	_prune_dirty_queue()

	# Drain fast during the initial bulk load (nothing else needs the frame yet),
	# then settle to the smooth in-game rate once caught up.
	var budget := meshes_per_frame_initial if _initial_load else meshes_per_frame

	var built := 0
	while _dirty_region_queue.size() > 0 and built < budget:
		var key: Vector2i = _dirty_region_queue.pop_front()
		_dirty_region_set.erase(key)
		if _region_should_exist(key):
			_rebuild_region(key)
		built += 1

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
	return "streamed chunk mesh"


func set_visual_cut_blocks(blocks: Dictionary) -> void:
	_visual_cut_blocks = blocks.duplicate()
	_invalidate_visual_cut_meshes_global()


func add_visual_cut_blocks(blocks: Array[Vector3i]) -> void:
	var changed: Array[Vector3i] = []
	for block: Vector3i in blocks:
		if _visual_cut_blocks.has(block):
			continue
		_visual_cut_blocks[block] = true
		changed.append(block)
	_invalidate_visual_cut_blocks(changed)


func remove_visual_cut_blocks(blocks: Array[Vector3i]) -> void:
	var changed: Array[Vector3i] = []
	for block: Vector3i in blocks:
		if not _visual_cut_blocks.has(block):
			continue
		_visual_cut_blocks.erase(block)
		changed.append(block)
	_invalidate_visual_cut_blocks(changed)


func _invalidate_visual_cut_blocks(blocks: Array[Vector3i]) -> void:
	if blocks.is_empty():
		return
	if _block_face_overview_active():
		_enqueue_overview_tiles_for_blocks(blocks)
		return
	_enqueue_regions_for_cut_blocks(blocks)


func _invalidate_visual_cut_meshes_global() -> void:
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
	if not chunk.has_void and _is_buried(cx, cy, cz):
		_free_chunk_node(key)
		return

	var mesh  := ChunkMesher.build_mesh(chunk, cx, cy, cz, _visual_cut_blocks)

	if mesh == null:
		_free_chunk_node(key)
		return

	var mi := _get_or_create_node(key, cx, cy, cz)
	mi.mesh    = mesh
	mi.visible = _chunk_should_be_meshed(cx, cy, cz)
	if _chunk_nodes.size() == 1:
		print("WorldRenderer: first solid mesh at world pos %s (chunk %d,%d,%d)." % [str(mi.global_position), cx, cy, cz])


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


func _region_should_exist(key: Vector2i) -> bool:
	var start_cx := key.x * REGION_SIZE
	var start_cz := key.y * REGION_SIZE
	for cx in range(start_cx, mini(CHUNK_COUNT_X, start_cx + REGION_SIZE)):
		for cz in range(start_cz, mini(CHUNK_COUNT_Z, start_cz + REGION_SIZE)):
			if _chunk_in_radius(cx, cz, unload_radius_chunks):
				return true
	return false


func _rebuild_region(key: Vector2i) -> void:
	var t_start := Time.get_ticks_msec()
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
				var mesh := ChunkMesher.build_mesh(chunk, cx, cy, cz, _visual_cut_blocks)
				if mesh == null:
					continue
				_append_mesh_arrays(mesh, Vector3(cx * CHUNK_SIZE, cy * CHUNK_SIZE, cz * CHUNK_SIZE), verts, norms, cols, indices)

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
	if _first_visible_mesh_msec == 0:
		_first_visible_mesh_msec = Time.get_ticks_msec()
		print("WorldRenderer: first visible region mesh after %.3f s at region %s." % [
			_elapsed_since_start_seconds(_first_visible_mesh_msec),
			str(key),
		])

	var elapsed := Time.get_ticks_msec() - t_start
	_region_rebuild_count += 1
	_region_rebuild_msec_total += elapsed
	_region_rebuild_msec_max = maxi(_region_rebuild_msec_max, elapsed)


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
	var run_bottom := float(y0)
	var run_color := _overview_side_color_at(sample_x, y0, sample_z, top_y, top_color)

	for y in range(y0 + 1, y1):
		var color := _overview_side_color_at(sample_x, y, sample_z, top_y, top_color)
		if color != run_color:
			_add_overview_side_band(a, b, run_bottom, float(y), run_color, normal, verts, norms, cols, indices)
			run_bottom = float(y)
			run_color = color

	_add_overview_side_band(a, b, run_bottom, top_y, run_color, normal, verts, norms, cols, indices)


func _overview_side_color_at(sample_x: int, y: int, sample_z: int, top_y: float, top_color: Color) -> Color:
	if y >= int(top_y) - 1:
		return top_color
	var block_id := WorldGenerator.get_generated_block_id(sample_x, y, sample_z)
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

	_overview_tile_side_faces_working += 1

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


func _append_mesh_arrays(
		mesh: ArrayMesh,
		offset: Vector3,
		verts: PackedVector3Array,
		norms: PackedVector3Array,
		cols: PackedColorArray,
		indices: PackedInt32Array) -> void:

	var arrays := mesh.surface_get_arrays(0)
	var src_verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var src_norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var src_cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var src_indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var base := verts.size()

	for v: Vector3 in src_verts:
		verts.append(v + offset)
	for n: Vector3 in src_norms:
		norms.append(n)
	for c: Color in src_cols:
		cols.append(c)
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


func _set_overview_nodes_visible(is_visible: bool) -> void:
	if _overview_node != null:
		_overview_node.visible = is_visible
	for key: Vector2i in _overview_tile_nodes:
		(_overview_tile_nodes[key] as MeshInstance3D).visible = is_visible


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


func _block_face_overview_active() -> bool:
	return use_block_face_overview and slice_y >= overview_slice_threshold


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
		print("WorldRenderer: built block-face overview tiles (%d tiles, step=%d, tops %d->%d, sides %d, validation mismatches %d/%d)." % [
			_overview_tile_nodes.size(),
			OVERVIEW_STEP,
			_overview_sampled_top_faces,
			_overview_merged_top_faces,
			_overview_side_faces,
			_overview_validation_mismatches,
			_overview_validation_samples,
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
	var built := 0
	while _dirty_overview_tiles.size() > 0 and built < overview_tiles_per_frame:
		var key: Vector2i = _dirty_overview_tiles.pop_front()
		_dirty_overview_tile_set.erase(key)
		_rebuild_overview_tile(key)
		built += 1
	if built > 0:
		_recompute_overview_stats()
		_meshes_built += built


func _rebuild_overview_tile(tile_key: Vector2i) -> void:
	var t_start := Time.get_ticks_msec()
	var step: int = OVERVIEW_STEP
	var verts: PackedVector3Array = []
	var norms: PackedVector3Array = []
	var cols: PackedColorArray = []
	var indices: PackedInt32Array = []
	var season: String = WorldClock.season
	_cache_overview_side_colors(season)
	_overview_tile_side_faces_working = 0

	var sample_cells: Dictionary = {}
	var x0 := tile_key.x * OVERVIEW_TILE_SIZE
	var z0 := tile_key.y * OVERVIEW_TILE_SIZE
	var x1 := mini(WORLD_SIZE_X, x0 + OVERVIEW_TILE_SIZE)
	var z1 := mini(WORLD_SIZE_Z, z0 + OVERVIEW_TILE_SIZE)
	if x0 < 0 or x0 >= WORLD_SIZE_X or z0 < 0 or z0 >= WORLD_SIZE_Z:
		return

	var grid_w := ceili(float(x1 - x0) / float(step))
	var grid_z := ceili(float(z1 - z0) / float(step))
	var sampled_top_faces := 0
	var validation_samples := 0
	var validation_mismatches := 0
	for wx in range(x0, x1, step):
		for wz in range(z0, z1, step):
			var surface := _overview_visible_surface_after_cut(wx, wz)
			if surface.is_empty():
				continue
			var wy: int = surface["wy"]
			var block_id: int = surface["block_id"]
			var generated_id := WorldGenerator.get_generated_block_id(wx, wy, wz)
			validation_samples += 1
			if generated_id != block_id:
				validation_mismatches += 1

			var color := BlockRegistry.get_color(block_id, season)
			var block_def := BlockRegistry.get_def(BlockRegistry.get_key(block_id))
			var block_kind: String = block_def.get("kind", "unknown")
			var key := Vector2i(
				int(floor(float(wx - x0) / float(step))),
				int(floor(float(wz - z0) / float(step))))
			sample_cells[key] = {
				"wx": wx,
				"wz": wz,
				"wy": wy,
				"block_id": block_id,
				"color": color,
				"kind": block_kind,
			}
			if show_overview_sides:
				_add_overview_sides(wx, wz, step, float(wy + 1), color, verts, norms, cols, indices)

	sampled_top_faces = sample_cells.size()
	var merged_before := _overview_merged_top_faces
	_add_greedy_overview_tops(sample_cells, grid_w, grid_z, step, verts, norms, cols, indices)
	var merged_top_faces := _overview_merged_top_faces - merged_before
	_overview_merged_top_faces = merged_before

	if verts.is_empty():
		_free_overview_tile_node(tile_key)
		_overview_tile_stats.erase(tile_key)
		return

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var mi := _get_or_create_overview_tile_node(tile_key)
	mi.mesh = mesh
	mi.visible = true
	if _first_visible_mesh_msec == 0:
		_first_visible_mesh_msec = Time.get_ticks_msec()
		print("WorldRenderer: first visible overview tile after %.3f s at tile %s." % [
			_elapsed_since_start_seconds(_first_visible_mesh_msec),
			str(tile_key),
		])
	_overview_tile_stats[tile_key] = {
		"sampled_top_faces": sampled_top_faces,
		"merged_top_faces": merged_top_faces,
		"side_faces": _overview_tile_side_faces_working,
		"validation_samples": validation_samples,
		"validation_mismatches": validation_mismatches,
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
		indices: PackedInt32Array) -> void:

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
			_overview_merged_top_faces += 1


func _overview_top_cells_merge(a: Dictionary, b: Dictionary) -> bool:
	if a.is_empty() or b.is_empty():
		return false
	return int(a.get("wy", -999999)) == int(b.get("wy", -999998)) and int(a.get("block_id", -1)) == int(b.get("block_id", -2))


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
	var surface := _overview_visible_surface_after_cut(wx, wz)
	if surface.is_empty():
		return edge_y
	return float(int(surface["wy"]) + 1)


func _overview_visible_surface_after_cut(wx: int, wz: int) -> Dictionary:
	var wy := WorldGenerator.get_visible_surface_y(wx, wz)
	if wy < 0 or wy > slice_y:
		return {}
	while wy >= 0 and _visual_cut_blocks.has(Vector3i(wx, wy, wz)):
		wy -= 1
	if wy < 0:
		return {}
	var block_id := WorldGenerator.get_generated_block_id(wx, wy, wz)
	if BlockRegistry.is_transparent(block_id):
		return {}
	return {
		"wy": wy,
		"block_id": block_id,
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


func _chunk_y_is_visible(cx: int, cy: int, cz: int) -> bool:
	var top_y: int = WorldGenerator.get_column_top_y(cx, cz)
	var visible_y: int = mini(slice_y, top_y)
	var visible_cy: int = clampi(floori(float(visible_y) / float(CHUNK_SIZE)), 0, CHUNK_COUNT_Y - 1)
	return cy <= visible_cy and cy >= maxi(0, visible_cy - vertical_context_chunks)


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
