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

var _material: StandardMaterial3D
var _overview_node: MeshInstance3D = null
var _overview_built: bool = false
var _overview_rock_color: Color = Color.GRAY
var _overview_sampled_top_faces: int = 0
var _overview_merged_top_faces: int = 0
var _overview_side_faces: int = 0
var _overview_validation_samples: int = 0
var _overview_validation_mismatches: int = 0
var _region_nodes: Dictionary = {}
var _chunk_nodes: Dictionary = {}   # Vector3i → MeshInstance3D

## Pending rebuild queue. _on_chunk_dirtied enqueues; _process drains.
var _dirty_queue: Array[Vector3i] = []
var _dirty_region_queue: Array[Vector2i] = []
var _dirty_region_set: Dictionary = {}
var _dirty_set:   Dictionary      = {}   # Vector3i → true  (dedup guard)

var _signals_received: int = 0
var _meshes_built: int = 0

## True until the world finishes generating AND the initial mesh queue drains.
## While true, _process builds at the faster meshes_per_frame_initial rate.
var _initial_load: bool = true

var _camera_rig: Camera = null
var _camera_chunk: Vector2i = Vector2i(-9999, -9999)
var _inspector_layer: CanvasLayer = null
var _inspector_label: Label = null
var _inspector_outline: MeshInstance3D = null


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

	if built > 0:
		_meshes_built += built
		if _meshes_built <= budget or _meshes_built % 256 == 0:
			print("WorldRenderer: built %d region meshes total, queue=%d." % [_meshes_built, _dirty_region_queue.size()])


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mbe := event as InputEventMouseButton
		if mbe.pressed and mbe.button_index == MOUSE_BUTTON_LEFT:
			_inspect_block_at_screen_position(mbe.position)


# -- Block inspector ----------------------------------------------------------

func _build_block_inspector_ui() -> void:
	_inspector_layer = CanvasLayer.new()
	_inspector_layer.name = "BlockInspector"
	add_child(_inspector_layer)

	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	panel.offset_left = -520.0
	panel.offset_top = -300.0
	panel.offset_right = -16.0
	panel.offset_bottom = -16.0
	panel.custom_minimum_size = Vector2(504.0, 284.0)
	_inspector_layer.add_child(panel)

	_inspector_label = Label.new()
	_inspector_label.name = "Details"
	_inspector_label.add_theme_font_size_override("font_size", 13)
	_inspector_label.text = "Block inspector\nclick a block"
	panel.add_child(_inspector_label)
	_build_block_inspector_outline()


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

	var mesh  := ChunkMesher.build_mesh(chunk, cx, cy, cz)

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
				var mesh := ChunkMesher.build_mesh(chunk, cx, cy, cz)
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

	_overview_side_faces += 1

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

func _block_face_overview_active() -> bool:
	return use_block_face_overview and slice_y >= overview_slice_threshold


func _update_block_face_overview() -> void:
	if _camera_rig == null:
		_camera_rig = _find_camera(get_tree().current_scene)
	if _overview_node != null:
		_overview_node.visible = true
	_free_all_streamed_nodes()

	var stats := WorldGenerator.get_streaming_stats()
	if not stats.get("maps_ready", false):
		return
	if not _overview_built:
		_build_block_face_overview()
		_initial_load = false


func _build_block_face_overview() -> void:
	var step: int = OVERVIEW_STEP
	var verts: PackedVector3Array = []
	var norms: PackedVector3Array = []
	var cols: PackedColorArray = []
	var indices: PackedInt32Array = []
	var season: String = WorldClock.season
	_cache_overview_side_colors(season)
	_overview_sampled_top_faces = 0
	_overview_merged_top_faces = 0
	_overview_side_faces = 0
	_overview_validation_samples = 0
	_overview_validation_mismatches = 0

	var sample_cells: Dictionary = {}
	var grid_w := ceili(float(WORLD_SIZE_X) / float(step))
	var grid_z := ceili(float(WORLD_SIZE_Z) / float(step))
	for wx in range(0, WORLD_SIZE_X, step):
		for wz in range(0, WORLD_SIZE_Z, step):
			var wy := WorldGenerator.get_visible_surface_y(wx, wz)
			if wy < 0 or wy > slice_y:
				continue
			var block_id := WorldGenerator.get_visible_surface_block_id(wx, wz)
			if BlockRegistry.is_transparent(block_id):
				continue
			var generated_id := WorldGenerator.get_generated_block_id(wx, wy, wz)
			_overview_validation_samples += 1
			if generated_id != block_id:
				_overview_validation_mismatches += 1

			var color := BlockRegistry.get_color(block_id, season)
			var block_def := BlockRegistry.get_def(BlockRegistry.get_key(block_id))
			var block_kind: String = block_def.get("kind", "unknown")
			var key := Vector2i(
				int(floor(float(wx) / float(step))),
				int(floor(float(wz) / float(step))))
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

	_overview_sampled_top_faces = sample_cells.size()
	_add_greedy_overview_tops(sample_cells, grid_w, grid_z, step, verts, norms, cols, indices)

	if verts.is_empty():
		return

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	if _overview_node == null:
		_overview_node = MeshInstance3D.new()
		_overview_node.name = "BlockFaceOverview"
		_overview_node.material_override = _material
		_overview_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_overview_node)

	_overview_node.mesh = mesh
	_overview_node.visible = true
	_overview_built = true
	_meshes_built += 1
	print("WorldRenderer: built block-face overview (%d verts, step=%d, tops %d->%d, sides %d, validation mismatches %d/%d)." % [
		verts.size(),
		step,
		_overview_sampled_top_faces,
		_overview_merged_top_faces,
		_overview_side_faces,
		_overview_validation_mismatches,
		_overview_validation_samples,
	])


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
	var wy := WorldGenerator.get_visible_surface_y(wx, wz)
	if wy < 0 or wy > slice_y:
		return edge_y
	return float(wy + 1)


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
	if _overview_node != null:
		_overview_node.visible = _block_face_overview_active()
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
		"overview_sides": show_overview_sides,
		"overview_sampled_top_faces": _overview_sampled_top_faces,
		"overview_merged_top_faces": _overview_merged_top_faces,
		"overview_side_faces": _overview_side_faces,
		"overview_validation_samples": _overview_validation_samples,
		"overview_validation_mismatches": _overview_validation_mismatches,
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
