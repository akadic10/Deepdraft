extends RefCounted

## Mining overlay geometry for MiningDesignationController (doc 258 step 8):
## the overlay materials, the drag preview, one overlay per confirmed zone with
## its cached slice clip state, the dimension rulers, the mesh builders and the
## renderer's visual cut set. The controller keeps the zone list and the tool;
## each rebuild receives the blocks, selection and visibility test it needs.

const WORLD_SIZE_Y := WorldData.WORLD_SIZE_Y

## Clip-state cache values for the slice-step skip rule. Assumes visibility is
## the slice plane only (renderer is_block_visible today) — revisit when X-Ray
## joins the visible-volume contract.
const ZONE_CLIP_FULL := 0      # whole zone at/below the plane → fully visible
const ZONE_CLIP_PARTIAL := 1   # plane cuts through the zone's Y range
const ZONE_CLIP_HIDDEN := 2    # whole zone above the plane → invisible

## The mining area guide; the controller builds its mesh.
var grid_node: MeshInstance3D
var _preview_fill_node: MeshInstance3D
var _preview_node: MeshInstance3D
## Exposed-layer nodes (doc 05 overlay readability, 2026-06-05): share the ghost
## layer's meshes but use depth-TESTED materials, so terrain occludes them — the
## GPU does the exposed/hidden partition. Exposed faces read strong; hidden
## structure shows only the faint no-depth ghost beneath.
var _preview_fill_exposed_node: MeshInstance3D
var _preview_exposed_node: MeshInstance3D

## Per-zone overlay nodes (doc 05, 2026-06-05): each confirmed zone owns its own
## ghost/exposed fill+line MeshInstance3Ds, so confirm/remove/select/DEV-mine
## rebuilds touch ONE zone's geometry, and slice steps skip zones whose clip
## state cannot have changed (cached Y-range test, needs_reclip).
var zones_root: Node3D
var _zone_overlays: Dictionary = {}   # zone_id -> {root, fill, fill_exposed, line, line_exposed, min_y, max_y, state, slice_y}

var _label_x: Label3D
var _label_z: Label3D
var _label_y: Label3D
var _ruler_node: MeshInstance3D
var _ruler_material: StandardMaterial3D
var _terrain_grid_material: StandardMaterial3D
var _preview_fill_material: StandardMaterial3D
var _preview_remove_fill_material: StandardMaterial3D
var _preview_material: StandardMaterial3D
var _preview_remove_material: StandardMaterial3D
var _zones_fill_material: StandardMaterial3D
var _zones_material: StandardMaterial3D
var _preview_fill_exposed_material: StandardMaterial3D
var _preview_remove_fill_exposed_material: StandardMaterial3D
var _preview_exposed_material: StandardMaterial3D
var _preview_remove_exposed_material: StandardMaterial3D
var _zones_fill_exposed_material: StandardMaterial3D
var _zones_exposed_material: StandardMaterial3D


func _init(parent: Node3D) -> void:
	_build_materials()
	_build_preview_nodes(parent)


func _build_materials() -> void:
	_terrain_grid_material = _line_material(Color.WHITE, false)
	# Layered overlay treatment (doc 05, Stonehearth parity): the original no-depth
	# materials became the faint GHOST layer (full volume, visible through terrain at
	# low alpha); the *_exposed_* variants are depth-TESTED at the original strength,
	# so exposed faces read strong and hidden structure stays faintly readable.
	# Alphas are tune-in-engine starting points (ghost ≈ 30% of the old values).
	_preview_fill_material = _solid_material(Color(1.0, 0.90, 0.0, 0.14), true)
	_preview_remove_fill_material = _solid_material(Color(1.0, 0.05, 0.03, 0.06), true)
	_preview_material = _line_material(Color(1.0, 0.98, 0.0, 0.30), true)
	_preview_remove_material = _line_material(Color(1, 0.05, 0.03, 0.30), true)
	_ruler_material = _line_material(Color(1, 1, 1, 0.9), true)
	_zones_fill_material = _solid_material(Color(1.0, 0.88, 0.0, 0.08), true)
	_zones_material = _line_material(Color(1.0, 0.92, 0.06, 0.28), true)
	_preview_fill_exposed_material = _solid_material(Color(1.0, 0.90, 0.0, 0.42), false)
	_preview_remove_fill_exposed_material = _solid_material(Color(1.0, 0.05, 0.03, 0.18), false)
	_preview_exposed_material = _line_material(Color(1.0, 0.98, 0.0, 1), false)
	_preview_remove_exposed_material = _line_material(Color(1, 0.05, 0.03, 1), false)
	_zones_fill_exposed_material = _solid_material(Color(1.0, 0.88, 0.0, 0.26), false)
	_zones_exposed_material = _line_material(Color(1.0, 0.92, 0.06, 0.92), false)


func _line_material(color: Color, no_depth: bool) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = no_depth
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


func _solid_material(color: Color, no_depth: bool) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = no_depth
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


func _build_preview_nodes(parent: Node3D) -> void:
	grid_node = MeshInstance3D.new()
	grid_node.name = "MiningAreaGuide"
	grid_node.material_override = _terrain_grid_material
	grid_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	grid_node.visible = false
	parent.add_child(grid_node)

	_preview_fill_node = MeshInstance3D.new()
	_preview_fill_node.name = "MiningPreviewFill"
	_preview_fill_node.material_override = _preview_fill_material
	_preview_fill_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_preview_fill_node.visible = false
	parent.add_child(_preview_fill_node)

	_preview_fill_exposed_node = MeshInstance3D.new()
	_preview_fill_exposed_node.name = "MiningPreviewFillExposed"
	_preview_fill_exposed_node.material_override = _preview_fill_exposed_material
	_preview_fill_exposed_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_preview_fill_exposed_node.visible = false
	parent.add_child(_preview_fill_exposed_node)

	_preview_node = MeshInstance3D.new()
	_preview_node.name = "MiningPreview"
	_preview_node.material_override = _preview_material
	_preview_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_preview_node.visible = false
	parent.add_child(_preview_node)

	_preview_exposed_node = MeshInstance3D.new()
	_preview_exposed_node.name = "MiningPreviewExposed"
	_preview_exposed_node.material_override = _preview_exposed_material
	_preview_exposed_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_preview_exposed_node.visible = false
	parent.add_child(_preview_exposed_node)

	zones_root = Node3D.new()
	zones_root.name = "MiningZoneOverlays"
	parent.add_child(zones_root)

	_ruler_node = MeshInstance3D.new()
	_ruler_node.name = "MiningRulers"
	_ruler_node.material_override = _ruler_material
	_ruler_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ruler_node.visible = false
	parent.add_child(_ruler_node)

	_label_x = _make_size_label("1")
	_label_z = _make_size_label("1")
	_label_y = _make_size_label("1")
	parent.add_child(_label_x)
	parent.add_child(_label_z)
	parent.add_child(_label_y)


func _make_size_label(text: String) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.visible = false
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = false
	label.font_size = 44
	label.outline_size = 7
	label.modulate = Color.WHITE
	label.outline_modulate = Color(0, 0, 0, 1.0)
	return label


# ── Drag preview ──────────────────────────────────────────────────────────────

## Tool activation shows the preview outline nodes.
func show_preview_lines() -> void:
	_preview_node.visible = true
	_preview_exposed_node.visible = true


## Tool deactivation: hide and empty the guide, the preview and the rulers.
func hide_preview() -> void:
	grid_node.visible = false
	grid_node.mesh = null
	_preview_fill_node.visible = false
	_preview_fill_node.mesh = null
	_preview_fill_exposed_node.visible = false
	_preview_fill_exposed_node.mesh = null
	_preview_node.visible = false
	_preview_exposed_node.visible = false
	clear_dimension_overlay()


## The cursor left the terrain: drop the preview meshes and the rulers.
func clear_preview() -> void:
	_preview_fill_node.mesh = null
	_preview_node.mesh = null
	_preview_fill_exposed_node.mesh = null
	_preview_exposed_node.mesh = null
	clear_dimension_overlay()


func rebuild_preview(raw_blocks: Array[Vector3i], is_remove: bool, visible_fn: Callable) -> void:
	_preview_node.material_override = _preview_remove_material if is_remove else _preview_material
	_preview_fill_node.material_override = _preview_remove_fill_material if is_remove else _preview_fill_material
	_preview_exposed_node.material_override = _preview_remove_exposed_material if is_remove else _preview_exposed_material
	_preview_fill_exposed_node.material_override = _preview_remove_fill_exposed_material if is_remove else _preview_fill_exposed_material
	var fill_color := Color(1.0, 0.05, 0.03, 0.18) if is_remove else Color(1.0, 0.90, 0.0, 0.42)
	var line_color := Color(1.0, 0.05, 0.03, 1) if is_remove else Color(1.0, 0.98, 0.0, 1)
	# VisibleVolume clip (doc 11 Phase 3): the preview shows exactly what confirm
	# will designate — nothing paints above the plane (matches the
	# controller's _filter_mineable_blocks visibility clip).
	var display_blocks: Array[Vector3i] = []
	for block: Vector3i in raw_blocks:
		if visible_fn.call(block):
			display_blocks.append(block)
	# Ghost (no-depth, faint) and exposed (depth-tested, strong) layers share the
	# same meshes — the depth buffer partitions exposed from hidden for free.
	var fill_mesh := build_fill_mesh(display_blocks, fill_color, 0.018)
	var line_mesh := build_bounds_line_mesh(display_blocks, line_color, 0.018)
	_preview_fill_node.mesh = fill_mesh
	_preview_fill_exposed_node.mesh = fill_mesh
	_preview_node.mesh = line_mesh
	_preview_exposed_node.mesh = line_mesh
	var has_blocks := not display_blocks.is_empty()
	_preview_fill_node.visible = has_blocks
	_preview_fill_exposed_node.visible = has_blocks
	_preview_node.visible = has_blocks
	_preview_exposed_node.visible = has_blocks


# ── Zone overlays ─────────────────────────────────────────────────────────────

## Per-zone skip rule (doc 05, 2026-06-05): a zone re-clips only if the plane
## change can alter its clip — fully-visible stays fully-visible and hidden
## stays hidden for O(1) per zone; only PARTIAL zones (and state transitions)
## pay the rebuild. Assumes plane-only visibility; revisit with X-Ray.
func needs_reclip(zone_id: int, slice_y: int) -> bool:
	var entry: Dictionary = _zone_overlays.get(zone_id, {})
	if entry.is_empty():
		return true
	var new_state := zone_clip_state(int(entry["min_y"]), int(entry["max_y"]), slice_y)
	var old_state := int(entry["state"])
	return not (new_state == old_state and (new_state != ZONE_CLIP_PARTIAL or slice_y == int(entry["slice_y"])))


## Rebuilds ONE zone's overlay geometry (creating its nodes on first use).
## VisibleVolume clip (doc 11 Phase 3, decision 2026-06-05): the overlay never
## paints inside hidden rock — Stonehearth's choice. A zone fully above the
## plane disappears (data untouched); a partially-cut zone closes its outline
## at the plane. A zone with no remaining blocks (or no record) is freed.
func rebuild_zone(zone_id: int, blocks: Array, selected: bool, slice_y: int, visible_fn: Callable) -> void:
	if blocks.is_empty():
		free_zone(zone_id)
		return

	var entry: Dictionary = _zone_overlays.get(zone_id, {})
	if entry.is_empty():
		entry = _create_zone_overlay_nodes(zone_id)
		_zone_overlays[zone_id] = entry

	var min_y := WORLD_SIZE_Y
	var max_y := 0
	var visible_blocks: Array[Vector3i] = []
	for block: Vector3i in blocks:
		min_y = mini(min_y, block.y)
		max_y = maxi(max_y, block.y)
		if visible_fn.call(block):
			visible_blocks.append(block)
	entry["min_y"] = min_y
	entry["max_y"] = max_y
	entry["slice_y"] = slice_y
	entry["state"] = zone_clip_state(min_y, max_y, slice_y)

	var fill_node: MeshInstance3D = entry["fill"]
	var fill_exposed_node: MeshInstance3D = entry["fill_exposed"]
	var line_node: MeshInstance3D = entry["line"]
	var line_exposed_node: MeshInstance3D = entry["line_exposed"]
	if visible_blocks.is_empty():
		fill_node.mesh = null
		fill_exposed_node.mesh = null
		line_node.mesh = null
		line_exposed_node.mesh = null
		return

	# Selected = ORANGE (red is reserved for the Ctrl-subtract removal preview;
	# orange also matches the zone window's DEV Mine accent).
	var line_color := Color(1.0, 0.52, 0.05, 1.0) if selected else Color(1.0, 0.88, 0.0, 0.92)
	var fill_color := Color(1.0, 0.52, 0.05, 0.30) if selected else Color(1.0, 0.88, 0.0, 0.22)

	var fill_verts: PackedVector3Array = []
	var fill_cols: PackedColorArray = []
	var line_verts: PackedVector3Array = []
	var line_cols: PackedColorArray = []
	_append_block_faces(visible_blocks, fill_color, fill_verts, fill_cols, 0.008)
	_append_exterior_region_lines(visible_blocks, line_color, line_verts, line_cols, 0.010)

	# Ghost and exposed layers share each mesh (see _build_materials).
	var fill_arrays: Array = []
	fill_arrays.resize(Mesh.ARRAY_MAX)
	fill_arrays[Mesh.ARRAY_VERTEX] = fill_verts
	fill_arrays[Mesh.ARRAY_COLOR] = fill_cols
	var fill_mesh := ArrayMesh.new()
	fill_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, fill_arrays)
	fill_node.mesh = fill_mesh
	fill_exposed_node.mesh = fill_mesh

	var line_arrays: Array = []
	line_arrays.resize(Mesh.ARRAY_MAX)
	line_arrays[Mesh.ARRAY_VERTEX] = line_verts
	line_arrays[Mesh.ARRAY_COLOR] = line_cols
	var line_mesh := ArrayMesh.new()
	line_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, line_arrays)
	line_node.mesh = line_mesh
	line_exposed_node.mesh = line_mesh


func _create_zone_overlay_nodes(zone_id: int) -> Dictionary:
	var root := Node3D.new()
	root.name = "Zone%d" % zone_id
	zones_root.add_child(root)

	var fill := MeshInstance3D.new()
	fill.name = "Fill"
	fill.material_override = _zones_fill_material
	fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(fill)

	var fill_exposed := MeshInstance3D.new()
	fill_exposed.name = "FillExposed"
	fill_exposed.material_override = _zones_fill_exposed_material
	fill_exposed.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(fill_exposed)

	var line := MeshInstance3D.new()
	line.name = "Line"
	line.material_override = _zones_material
	line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(line)

	var line_exposed := MeshInstance3D.new()
	line_exposed.name = "LineExposed"
	line_exposed.material_override = _zones_exposed_material
	line_exposed.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(line_exposed)

	return {
		"root": root,
		"fill": fill,
		"fill_exposed": fill_exposed,
		"line": line,
		"line_exposed": line_exposed,
		"min_y": 0,
		"max_y": 0,
		"state": ZONE_CLIP_FULL,
		"slice_y": -1,
	}


func free_zone(zone_id: int) -> void:
	var entry: Dictionary = _zone_overlays.get(zone_id, {})
	if entry.is_empty():
		return
	(entry["root"] as Node3D).queue_free()
	_zone_overlays.erase(zone_id)


static func zone_clip_state(min_y: int, max_y: int, slice_y: int) -> int:
	if max_y <= slice_y:
		return ZONE_CLIP_FULL
	if min_y > slice_y:
		return ZONE_CLIP_HIDDEN
	return ZONE_CLIP_PARTIAL


# ── Renderer visual cuts ──────────────────────────────────────────────────────

static func sync_visual_cuts(renderer: Node, zones: Dictionary) -> void:
	if renderer == null or not renderer.has_method("set_visual_cut_blocks"):
		return
	var cut_blocks: Dictionary = {}
	for zone_id: int in zones.keys():
		var zone: Dictionary = zones[zone_id]
		for block: Vector3i in zone.get("blocks", []):
			cut_blocks[block] = true
	renderer.call("set_visual_cut_blocks", cut_blocks)


static func add_visual_cuts(renderer: Node, blocks: Array[Vector3i], zones: Dictionary) -> void:
	if renderer == null:
		return
	if renderer.has_method("add_visual_cut_blocks"):
		renderer.call("add_visual_cut_blocks", blocks)
	else:
		sync_visual_cuts(renderer, zones)


static func remove_visual_cuts(renderer: Node, blocks: Array[Vector3i], zones: Dictionary) -> void:
	if renderer == null:
		return
	if renderer.has_method("remove_visual_cut_blocks"):
		renderer.call("remove_visual_cut_blocks", blocks)
	else:
		sync_visual_cuts(renderer, zones)


# ── Mesh builders ─────────────────────────────────────────────────────────────

static func build_bounds_line_mesh(blocks: Array[Vector3i], color: Color, outset: float) -> ArrayMesh:
	if blocks.is_empty():
		return null
	var verts: PackedVector3Array = []
	var cols: PackedColorArray = []
	_append_bounds_lines(bounds_for_blocks(blocks), color, verts, cols, outset)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = cols
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	return mesh


static func _append_bounds_lines(
		bounds: AABB,
		color: Color,
		verts: PackedVector3Array,
		cols: PackedColorArray,
		outset: float) -> void:

	var min_v := bounds.position - Vector3(outset, outset, outset)
	var max_v := bounds.position + bounds.size + Vector3(outset, outset, outset)
	var corners := [
		Vector3(min_v.x, min_v.y, min_v.z),
		Vector3(max_v.x, min_v.y, min_v.z),
		Vector3(max_v.x, max_v.y, min_v.z),
		Vector3(min_v.x, max_v.y, min_v.z),
		Vector3(min_v.x, min_v.y, max_v.z),
		Vector3(max_v.x, min_v.y, max_v.z),
		Vector3(max_v.x, max_v.y, max_v.z),
		Vector3(min_v.x, max_v.y, max_v.z),
	]
	var edges := [
		[0, 1], [1, 2], [2, 3], [3, 0],
		[4, 5], [5, 6], [6, 7], [7, 4],
		[0, 4], [1, 5], [2, 6], [3, 7],
	]
	for edge: Array in edges:
		verts.append(corners[edge[0] as int])
		verts.append(corners[edge[1] as int])
		cols.append(color)
		cols.append(color)


static func build_fill_mesh(blocks: Array[Vector3i], color: Color, outset: float) -> ArrayMesh:
	var verts: PackedVector3Array = []
	var cols: PackedColorArray = []
	_append_block_faces(blocks, color, verts, cols, outset)
	if verts.is_empty():
		return null
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = cols
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _append_block_faces(
		blocks: Array[Vector3i],
		color: Color,
		verts: PackedVector3Array,
		cols: PackedColorArray,
		outset: float) -> void:

	var block_set: Dictionary = {}
	for block: Vector3i in blocks:
		block_set[block] = true

	var directions := [
		Vector3i(-1, 0, 0),
		Vector3i(1, 0, 0),
		Vector3i(0, -1, 0),
		Vector3i(0, 1, 0),
		Vector3i(0, 0, -1),
		Vector3i(0, 0, 1),
	]
	for block: Vector3i in blocks:
		for normal: Vector3i in directions:
			if block_set.has(block + normal):
				continue
			_append_block_face(block, normal, color, verts, cols, outset)


static func _append_exterior_region_lines(
		blocks: Array,
		color: Color,
		verts: PackedVector3Array,
		cols: PackedColorArray,
		_outset: float) -> void:

	var block_set: Dictionary = {}
	for block: Vector3i in blocks:
		block_set[block] = true

	var edge_normals: Dictionary = {}
	for block: Vector3i in blocks:
		_add_exterior_face_edges(block, Vector3i(-1, 0, 0), block_set, edge_normals)
		_add_exterior_face_edges(block, Vector3i(1, 0, 0), block_set, edge_normals)
		_add_exterior_face_edges(block, Vector3i(0, -1, 0), block_set, edge_normals)
		_add_exterior_face_edges(block, Vector3i(0, 1, 0), block_set, edge_normals)
		_add_exterior_face_edges(block, Vector3i(0, 0, -1), block_set, edge_normals)
		_add_exterior_face_edges(block, Vector3i(0, 0, 1), block_set, edge_normals)

	for key: String in edge_normals.keys():
		var normals: Dictionary = edge_normals[key]
		if normals.size() <= 1:
			continue
		var points := _edge_key_to_points(key)
		if points.size() != 2:
			continue
		verts.append(points[0])
		verts.append(points[1])
		cols.append(color)
		cols.append(color)


static func _add_exterior_face_edges(
		block: Vector3i,
		normal: Vector3i,
		block_set: Dictionary,
		edge_normals: Dictionary) -> void:

	if block_set.has(block + normal):
		return
	var corners := _face_corners(block, normal, 0.0)
	_count_edge_normal(corners[0], corners[1], normal, edge_normals)
	_count_edge_normal(corners[1], corners[2], normal, edge_normals)
	_count_edge_normal(corners[2], corners[3], normal, edge_normals)
	_count_edge_normal(corners[3], corners[0], normal, edge_normals)


static func _face_corners(block: Vector3i, normal: Vector3i, outset: float) -> Array[Vector3]:
	var x0 := float(block.x) - outset
	var x1 := float(block.x + 1) + outset
	var y0 := float(block.y) - outset
	var y1 := float(block.y + 1) + outset
	var z0 := float(block.z) - outset
	var z1 := float(block.z + 1) + outset
	if normal.x < 0:
		return [Vector3(x0, y0, z1), Vector3(x0, y1, z1), Vector3(x0, y1, z0), Vector3(x0, y0, z0)]
	if normal.x > 0:
		return [Vector3(x1, y0, z0), Vector3(x1, y1, z0), Vector3(x1, y1, z1), Vector3(x1, y0, z1)]
	if normal.y < 0:
		return [Vector3(x0, y0, z0), Vector3(x1, y0, z0), Vector3(x1, y0, z1), Vector3(x0, y0, z1)]
	if normal.y > 0:
		return [Vector3(x0, y1, z1), Vector3(x1, y1, z1), Vector3(x1, y1, z0), Vector3(x0, y1, z0)]
	if normal.z < 0:
		return [Vector3(x1, y0, z0), Vector3(x0, y0, z0), Vector3(x0, y1, z0), Vector3(x1, y1, z0)]
	return [Vector3(x0, y0, z1), Vector3(x1, y0, z1), Vector3(x1, y1, z1), Vector3(x0, y1, z1)]


static func _count_edge_normal(a: Vector3, b: Vector3, normal: Vector3i, edge_normals: Dictionary) -> void:
	var key := _edge_key(a, b)
	if not edge_normals.has(key):
		edge_normals[key] = {}
	var normals: Dictionary = edge_normals[key]
	normals[_normal_key(normal)] = true
	edge_normals[key] = normals


static func _normal_key(normal: Vector3i) -> String:
	return "%d,%d,%d" % [normal.x, normal.y, normal.z]


static func _edge_key(a: Vector3, b: Vector3) -> String:
	var ka := _point_key(a)
	var kb := _point_key(b)
	return "%s|%s" % [ka, kb] if ka < kb else "%s|%s" % [kb, ka]


static func _point_key(point: Vector3) -> String:
	return "%d,%d,%d" % [
		roundi(point.x * 1000.0),
		roundi(point.y * 1000.0),
		roundi(point.z * 1000.0),
	]


static func _edge_key_to_points(key: String) -> Array[Vector3]:
	var parts := key.split("|")
	if parts.size() != 2:
		return []
	return [_point_key_to_vector(parts[0]), _point_key_to_vector(parts[1])]


static func _point_key_to_vector(key: String) -> Vector3:
	var parts := key.split(",")
	if parts.size() != 3:
		return Vector3.ZERO
	return Vector3(float(parts[0]) / 1000.0, float(parts[1]) / 1000.0, float(parts[2]) / 1000.0)


static func _append_block_face(
		block: Vector3i,
		normal: Vector3i,
		color: Color,
		verts: PackedVector3Array,
		cols: PackedColorArray,
		outset: float) -> void:

	var x0 := float(block.x) - outset
	var x1 := float(block.x + 1) + outset
	var y0 := float(block.y) - outset
	var y1 := float(block.y + 1) + outset
	var z0 := float(block.z) - outset
	var z1 := float(block.z + 1) + outset
	var face: Array[Vector3] = []
	if normal.x < 0:
		face = [Vector3(x0, y0, z1), Vector3(x0, y1, z1), Vector3(x0, y1, z0), Vector3(x0, y0, z0)]
	elif normal.x > 0:
		face = [Vector3(x1, y0, z0), Vector3(x1, y1, z0), Vector3(x1, y1, z1), Vector3(x1, y0, z1)]
	elif normal.y < 0:
		face = [Vector3(x0, y0, z0), Vector3(x1, y0, z0), Vector3(x1, y0, z1), Vector3(x0, y0, z1)]
	elif normal.y > 0:
		face = [Vector3(x0, y1, z1), Vector3(x1, y1, z1), Vector3(x1, y1, z0), Vector3(x0, y1, z0)]
	elif normal.z < 0:
		face = [Vector3(x1, y0, z0), Vector3(x0, y0, z0), Vector3(x0, y1, z0), Vector3(x1, y1, z0)]
	else:
		face = [Vector3(x0, y0, z1), Vector3(x1, y0, z1), Vector3(x1, y1, z1), Vector3(x0, y1, z1)]

	_append_face_triangle(face[0], face[1], face[2], color, verts, cols)
	_append_face_triangle(face[0], face[2], face[3], color, verts, cols)


static func _append_face_triangle(
		a: Vector3,
		b: Vector3,
		c: Vector3,
		color: Color,
		verts: PackedVector3Array,
		cols: PackedColorArray) -> void:

	verts.append(a)
	verts.append(b)
	verts.append(c)
	cols.append(color)
	cols.append(color)
	cols.append(color)


# ── Dimension overlay ─────────────────────────────────────────────────────────

## Stonehearth-style dimension overlay (#3): X and Z rulers (dimension bars with
## end caps + outward arrowheads and a midpoint count) laid flat on the top of the
## selection, plus a depth number at the top corner. Counts are the TRUE footprint
## extents, not the brush sizes. Rulers/labels hide on any axis of length <= 1.
func update_size_labels(raw_blocks: Array[Vector3i]) -> void:
	if raw_blocks.is_empty():
		clear_dimension_overlay()
		return
	var bounds := bounds_for_blocks(raw_blocks)
	var top := float(bounds.position.y + bounds.size.y)
	var label_y := top + 0.9
	var center := bounds.position + bounds.size * 0.5
	var x_count := int(round(bounds.size.x))
	var z_count := int(round(bounds.size.z))
	var y_count := int(round(bounds.size.y))

	_ruler_node.mesh = _build_ruler_mesh(bounds)
	_ruler_node.visible = _ruler_node.mesh != null

	# X ruler runs along the -Z edge; label centred over it.
	_label_x.text = str(x_count)
	_label_x.global_position = Vector3(center.x, label_y, bounds.position.z - 0.6)
	_label_x.visible = x_count > 1

	# Z ruler runs along the -X edge; label centred over it.
	_label_z.text = str(z_count)
	_label_z.global_position = Vector3(bounds.position.x - 0.6, label_y, center.z)
	_label_z.visible = z_count > 1

	# Depth number at the top far corner (matches Stonehearth's vertical label).
	_label_y.text = str(y_count)
	_label_y.global_position = Vector3(
		bounds.position.x + bounds.size.x,
		label_y,
		bounds.position.z + bounds.size.z)
	_label_y.visible = y_count > 1


func clear_dimension_overlay() -> void:
	_ruler_node.mesh = null
	_ruler_node.visible = false
	_label_x.visible = false
	_label_z.visible = false
	_label_y.visible = false


## Builds the flat X/Z dimension bars (PRIMITIVE_LINES, vertex-coloured white) on
## the top plane of the selection. Returns null when neither axis spans > 1.
static func _build_ruler_mesh(bounds: AABB) -> ArrayMesh:
	var x0 := bounds.position.x
	var x1 := bounds.position.x + bounds.size.x
	var z0 := bounds.position.z
	var z1 := bounds.position.z + bounds.size.z
	var y := bounds.position.y + bounds.size.y + 0.05   # just above the top face
	var col := Color(1, 1, 1, 0.9)
	var off := 0.6    # bar distance outside the footprint edge
	var cap := 0.22   # end-cap half length
	var av := 0.5     # arrowhead length along the bar
	var ah := 0.2     # arrowhead half spread

	var verts: PackedVector3Array = []
	var cols: PackedColorArray = []

	if bounds.size.x > 1.0:
		var zr := z0 - off
		_append_dim_line(verts, cols, col,
			Vector3(x0, y, zr), Vector3(x1, y, zr), Vector3(0, 0, 1), cap, av, ah)
	if bounds.size.z > 1.0:
		var xr := x0 - off
		_append_dim_line(verts, cols, col,
			Vector3(xr, y, z0), Vector3(xr, y, z1), Vector3(1, 0, 0), cap, av, ah)

	if verts.is_empty():
		return null
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = cols
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	return mesh


## One dimension line from a to b: main bar, perpendicular end caps, and outward
## arrowheads at each end (perp is the in-plane unit vector across the bar).
static func _append_dim_line(
		verts: PackedVector3Array, cols: PackedColorArray, col: Color,
		a: Vector3, b: Vector3, perp: Vector3,
		cap: float, av: float, ah: float) -> void:
	var dir := (b - a).normalized()
	_push_line(verts, cols, col, a, b)
	_push_line(verts, cols, col, a - perp * cap, a + perp * cap)
	_push_line(verts, cols, col, b - perp * cap, b + perp * cap)
	# arrowheads point outward: tips at a and b, barbs angled back inward
	_push_line(verts, cols, col, a, a + dir * av + perp * ah)
	_push_line(verts, cols, col, a, a + dir * av - perp * ah)
	_push_line(verts, cols, col, b, b - dir * av + perp * ah)
	_push_line(verts, cols, col, b, b - dir * av - perp * ah)


static func _push_line(
		verts: PackedVector3Array, cols: PackedColorArray, col: Color,
		p: Vector3, q: Vector3) -> void:
	verts.append(p)
	verts.append(q)
	cols.append(col)
	cols.append(col)


static func bounds_for_blocks(blocks: Array[Vector3i]) -> AABB:
	var min_v := blocks[0]
	var max_v := blocks[0]
	for block: Vector3i in blocks:
		min_v = Vector3i(mini(min_v.x, block.x), mini(min_v.y, block.y), mini(min_v.z, block.z))
		max_v = Vector3i(maxi(max_v.x, block.x), maxi(max_v.y, block.y), maxi(max_v.z, block.z))
	return AABB(Vector3(min_v), Vector3(max_v - min_v + Vector3i.ONE))
