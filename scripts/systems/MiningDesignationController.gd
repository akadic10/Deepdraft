class_name MiningDesignationController
extends Node3D

@export var camera_path: NodePath
@export var dock_ui_path: NodePath
@export var renderer_path: NodePath

const CONFIG_PATH := "res://data/terrain/mining_config.json"
const WORLD_SIZE_X := 1024
const WORLD_SIZE_Y := 128
const WORLD_SIZE_Z := 1024
const BEDROCK_MAX_Y := 3
const TERRAIN_GRID_MIN_RADIUS := 72
const TERRAIN_GRID_MAX_RADIUS := 168
const TERRAIN_GRID_REBUILD_CELL := 8
const TERRAIN_GRID_OFFSET := 0.006

## Fallback defaults only — data/terrain/mining_config.json is the single tuning
## surface (JSON wins; see _load_config). These exist so the tool fails gracefully
## if the config file is missing or malformed.
const FALLBACK_DEFAULT_SIZE := 1
const FALLBACK_MAX_HORIZONTAL := 8
const FALLBACK_MAX_VERTICAL := 8
const FALLBACK_MAX_DRAG_LENGTH := 40

enum ToolState { INACTIVE, HOVER, DRAGGING }

var _state: ToolState = ToolState.INACTIVE
var _camera_rig: Camera
var _dock_ui: DockUI
var _renderer: Node

var _horizontal_size: int = FALLBACK_DEFAULT_SIZE
var _vertical_size: int = FALLBACK_DEFAULT_SIZE
var _max_horizontal: int = FALLBACK_MAX_HORIZONTAL
var _max_vertical: int = FALLBACK_MAX_VERTICAL
var _max_drag_length: int = FALLBACK_MAX_DRAG_LENGTH

var _hover_hit: Dictionary = {}
var _anchor_hit: Dictionary = {}
var _preview_raw_blocks: Array[Vector3i] = []
var _preview_blocks: Array[Vector3i] = []
var _preview_is_remove: bool = false
var _next_zone_id: int = 1
var _zones: Dictionary = {}
var _zone_by_block: Dictionary = {}
var _selected_zone_id: int = -1

## DEV instant-mine state (testing tool — no drops, no dwarves). Mined blocks
## stay in the renderer's visual-cut set forever (that IS their removal in
## overview mode, where most block data is generated on demand) and become
## transparent to this controller's raycast/grid/designation so the player can
## designate the newly exposed blocks and dig deeper iteratively.
var _mined_blocks: Dictionary = {}   # Vector3i -> true

var _terrain_grid_node: MeshInstance3D
var _preview_fill_node: MeshInstance3D
var _preview_node: MeshInstance3D
var _zones_fill_node: MeshInstance3D
var _zones_node: MeshInstance3D
var _label_horizontal: Label3D
var _label_vertical: Label3D
var _terrain_grid_material: StandardMaterial3D
var _preview_fill_material: StandardMaterial3D
var _preview_remove_fill_material: StandardMaterial3D
var _preview_material: StandardMaterial3D
var _preview_remove_material: StandardMaterial3D
var _zones_fill_material: StandardMaterial3D
var _zones_material: StandardMaterial3D
var _selected_zone_material: StandardMaterial3D
var _ui_layer: CanvasLayer
var _zone_window: PanelContainer
var _zone_title: Label
var _zone_body: Label
var _last_grid_center := Vector2i(-999999, -999999)
var _last_grid_slice := -999999
var _last_grid_radius := -1


func _ready() -> void:
	_load_config()
	_camera_rig = get_node_or_null(camera_path) as Camera
	_dock_ui = get_node_or_null(dock_ui_path) as DockUI
	_renderer = get_node_or_null(renderer_path)
	_build_materials()
	_build_preview_nodes()
	_build_zone_window()

	if _dock_ui != null and _dock_ui.has_signal("tool_requested"):
		_dock_ui.tool_requested.connect(_on_tool_requested)

	# VisibleVolume contract (doc 11 Phase 3): all overlay rebuilds triggered by
	# visibility changes go through this one signal — never per-consumer polling.
	if _renderer != null and _renderer.has_signal("visible_volume_changed"):
		_renderer.connect("visible_volume_changed", _on_visible_volume_changed)


## One reactive rebuild per visibility change (the renderer emits at most once
## per frame). Zones re-clip even while the tool is inactive — confirmed zones
## are always on screen; grid and preview only exist while the tool is active.
func _on_visible_volume_changed() -> void:
	_rebuild_zones_mesh()
	if _state != ToolState.INACTIVE:
		_rebuild_terrain_grid(true)
		_update_hover_preview(true)


func _process(_delta: float) -> void:
	if _state == ToolState.INACTIVE:
		return
	_rebuild_terrain_grid()
	_update_hover_preview()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and key.keycode == KEY_ESCAPE and _state != ToolState.INACTIVE:
			_deactivate_tool()
			get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_RIGHT and _state != ToolState.INACTIVE:
			_deactivate_tool()
			get_viewport().set_input_as_handled()
			return

		if _state == ToolState.INACTIVE:
			if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
				if _try_select_zone_at_screen(mouse.position):
					get_viewport().set_input_as_handled()
			return

		if mouse.pressed and mouse.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			if _handle_resize_wheel(mouse.button_index):
				_update_hover_preview(true)
				get_viewport().set_input_as_handled()
			return

		if mouse.button_index == MOUSE_BUTTON_LEFT:
			if mouse.pressed:
				if _try_select_zone_at_screen(mouse.position) and not Input.is_key_pressed(KEY_CTRL):
					get_viewport().set_input_as_handled()
					return
				if not _hover_hit.is_empty():
					_anchor_hit = _hover_hit.duplicate()
					_state = ToolState.DRAGGING
					_update_hover_preview(true)
					get_viewport().set_input_as_handled()
			elif _state == ToolState.DRAGGING:
				_confirm_preview()
				_anchor_hit.clear()
				_state = ToolState.HOVER
				_update_hover_preview(true)
				get_viewport().set_input_as_handled()


func _on_tool_requested(tool_id: String) -> void:
	if tool_id != "mine_precision":
		return
	_state = ToolState.HOVER
	_terrain_grid_node.visible = true
	_preview_node.visible = true
	_rebuild_terrain_grid(true)
	print("MiningDesignationController: precision mining active.")


func _deactivate_tool() -> void:
	_state = ToolState.INACTIVE
	_anchor_hit.clear()
	_hover_hit.clear()
	_preview_raw_blocks.clear()
	_preview_blocks.clear()
	_terrain_grid_node.visible = false
	_terrain_grid_node.mesh = null
	_preview_fill_node.visible = false
	_preview_fill_node.mesh = null
	_preview_node.visible = false
	_label_horizontal.visible = false
	_label_vertical.visible = false
	_last_grid_center = Vector2i(-999999, -999999)
	_last_grid_slice = -999999
	_last_grid_radius = -1


func _load_config() -> void:
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		push_warning("MiningDesignationController: cannot open %s; using defaults." % CONFIG_PATH)
		return

	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	file.close()
	if err != OK:
		push_warning("MiningDesignationController: JSON parse error in %s." % CONFIG_PATH)
		return

	var root: Dictionary = json.data
	var precision: Dictionary = root.get("precision_tool", {})
	var dig_tool: Dictionary = root.get("dig_tool", {})
	_horizontal_size = int(precision.get("default_size", FALLBACK_DEFAULT_SIZE))
	_vertical_size = int(precision.get("default_size", FALLBACK_DEFAULT_SIZE))
	_max_horizontal = int(precision.get("max_horizontal", FALLBACK_MAX_HORIZONTAL))
	_max_vertical = int(precision.get("max_vertical", FALLBACK_MAX_VERTICAL))
	_max_drag_length = int(dig_tool.get("max_drag_length", FALLBACK_MAX_DRAG_LENGTH))


func _build_materials() -> void:
	_terrain_grid_material = _line_material(Color(0, 0, 0, 0.28), false)
	_preview_fill_material = _solid_material(Color(1.0, 0.90, 0.0, 0.42), true)
	_preview_remove_fill_material = _solid_material(Color(1.0, 0.05, 0.03, 0.18), true)
	_preview_material = _line_material(Color(1.0, 0.98, 0.0, 1), true)
	_preview_remove_material = _line_material(Color(1, 0.05, 0.03, 1), true)
	_zones_fill_material = _solid_material(Color(1.0, 0.88, 0.0, 0.26), true)
	_zones_material = _line_material(Color(1.0, 0.92, 0.06, 0.92), true)
	_selected_zone_material = _line_material(Color(1.0, 1.0, 0.35, 1), true)


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


func _build_preview_nodes() -> void:
	_terrain_grid_node = MeshInstance3D.new()
	_terrain_grid_node.name = "MiningTerrainGrid"
	_terrain_grid_node.material_override = _terrain_grid_material
	_terrain_grid_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_terrain_grid_node.visible = false
	add_child(_terrain_grid_node)

	_preview_fill_node = MeshInstance3D.new()
	_preview_fill_node.name = "MiningPreviewFill"
	_preview_fill_node.material_override = _preview_fill_material
	_preview_fill_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_preview_fill_node.visible = false
	add_child(_preview_fill_node)

	_preview_node = MeshInstance3D.new()
	_preview_node.name = "MiningPreview"
	_preview_node.material_override = _preview_material
	_preview_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_preview_node.visible = false
	add_child(_preview_node)

	_zones_fill_node = MeshInstance3D.new()
	_zones_fill_node.name = "MiningZoneFills"
	_zones_fill_node.material_override = _zones_fill_material
	_zones_fill_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_zones_fill_node)

	_zones_node = MeshInstance3D.new()
	_zones_node.name = "MiningZones"
	_zones_node.material_override = _zones_material
	_zones_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_zones_node)

	_label_horizontal = _make_size_label("1")
	_label_vertical = _make_size_label("1")
	add_child(_label_horizontal)
	add_child(_label_vertical)


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


func _build_zone_window() -> void:
	_ui_layer = CanvasLayer.new()
	_ui_layer.name = "MiningZoneUI"
	_ui_layer.layer = 24
	add_child(_ui_layer)

	_zone_window = PanelContainer.new()
	_zone_window.name = "MiningZoneWindow"
	_zone_window.position = Vector2(18.0, 118.0)
	_zone_window.custom_minimum_size = Vector2(280.0, 118.0)
	_zone_window.visible = false
	_zone_window.add_theme_stylebox_override("panel", _window_style())
	_ui_layer.add_child(_zone_window)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 10)
	_zone_window.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	column.add_child(header)

	_zone_title = Label.new()
	_zone_title.text = "Mining Zone"
	_zone_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_zone_title.add_theme_font_size_override("font_size", 16)
	header.add_child(_zone_title)

	var close := Button.new()
	close.text = "X"
	close.custom_minimum_size = Vector2(30.0, 26.0)
	close.focus_mode = Control.FOCUS_NONE
	close.tooltip_text = "Close"
	close.pressed.connect(func() -> void:
		_close_zone_window()
	)
	header.add_child(close)

	_zone_body = Label.new()
	_zone_body.text = "Blocks: 0"
	_zone_body.add_theme_font_size_override("font_size", 13)
	column.add_child(_zone_body)

	var remove := Button.new()
	remove.text = "Remove"
	remove.custom_minimum_size = Vector2(98.0, 34.0)
	remove.focus_mode = Control.FOCUS_NONE
	remove.tooltip_text = "Remove mining zone"
	remove.pressed.connect(func() -> void:
		_remove_selected_zone()
	)
	column.add_child(remove)

	# DEV-only instant mine: executes the zone immediately — blocks are removed
	# from the game (no drops, no dwarves). Testing tool for slice/interiors;
	# replaced by real mining execution later.
	var dev_mine := Button.new()
	dev_mine.text = "DEV Mine (no drops)"
	dev_mine.custom_minimum_size = Vector2(98.0, 34.0)
	dev_mine.focus_mode = Control.FOCUS_NONE
	dev_mine.tooltip_text = "DEV: remove this zone's blocks from the game instantly"
	dev_mine.add_theme_color_override("font_color", Color(1.0, 0.62, 0.26))
	dev_mine.add_theme_color_override("font_hover_color", Color(1.0, 0.72, 0.40))
	dev_mine.pressed.connect(func() -> void:
		_dev_mine_selected_zone()
	)
	column.add_child(dev_mine)


func _window_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.085, 0.07, 0.94)
	style.border_color = Color(0.78, 0.55, 0.34, 0.65)
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	return style


func _rebuild_terrain_grid(force: bool = false) -> void:
	if _camera_rig == null or not WorldGenerator.has_method("get_visible_surface_y"):
		return
	if WorldGenerator.has_method("get_streaming_stats"):
		var stats: Dictionary = WorldGenerator.get_streaming_stats()
		if not bool(stats.get("maps_ready", false)):
			return

	var center := Vector2i(
		clampi(floori(_camera_rig.global_position.x), 0, WORLD_SIZE_X - 1),
		clampi(floori(_camera_rig.global_position.z), 0, WORLD_SIZE_Z - 1))
	var radius := _terrain_grid_radius()
	var rebuild_center := Vector2i(
		floori(float(center.x) / float(TERRAIN_GRID_REBUILD_CELL)),
		floori(float(center.y) / float(TERRAIN_GRID_REBUILD_CELL)))
	var slice_y := _current_slice_y()
	if not force \
			and rebuild_center == _last_grid_center \
			and slice_y == _last_grid_slice \
			and radius == _last_grid_radius:
		return

	_last_grid_center = rebuild_center
	_last_grid_slice = slice_y
	_last_grid_radius = radius

	var verts: PackedVector3Array = []
	var cols: PackedColorArray = []
	var color := Color(0, 0, 0, 0.28)
	var x0 := clampi(center.x - radius, 0, WORLD_SIZE_X - 1)
	var x1 := clampi(center.x + radius, 0, WORLD_SIZE_X - 1)
	var z0 := clampi(center.y - radius, 0, WORLD_SIZE_Z - 1)
	var z1 := clampi(center.y + radius, 0, WORLD_SIZE_Z - 1)

	for x in range(x0, x1 + 1):
		for z in range(z0, z1 + 1):
			var top_y := _effective_grid_top(x, z, slice_y)
			if top_y < 0:
				continue
			_append_top_face_grid(x, top_y, z, color, verts, cols)
			_append_visible_side_grid(x, top_y, z, Vector2i(-1, 0), slice_y, color, verts, cols)
			_append_visible_side_grid(x, top_y, z, Vector2i(1, 0), slice_y, color, verts, cols)
			_append_visible_side_grid(x, top_y, z, Vector2i(0, -1), slice_y, color, verts, cols)
			_append_visible_side_grid(x, top_y, z, Vector2i(0, 1), slice_y, color, verts, cols)

	if verts.is_empty():
		_terrain_grid_node.mesh = null
		return

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = cols
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	_terrain_grid_node.mesh = mesh


func _terrain_grid_radius() -> int:
	if _camera_rig == null or _camera_rig.spring_arm == null:
		return TERRAIN_GRID_MIN_RADIUS
	var zoom := _camera_rig.spring_arm.spring_length
	return clampi(ceili(zoom * 0.9), TERRAIN_GRID_MIN_RADIUS, TERRAIN_GRID_MAX_RADIUS)


## Effective visible top for the mining grid (doc 11 Phase 2b): the natural
## surface clamped to the slice plane, then stepped down past designated cut
## blocks — the same visible-surface rule the overview applies in
## WorldRenderer._overview_visible_surface_after_cut(). _zone_by_block is the
## controller's own designation set, which the renderer's _visual_cut_blocks
## mirrors, so no renderer query is needed. Returns -1 when no visible block
## remains in the column (out of bounds / maps not ready / fully cut away —
## the cut floor cannot reach bedrock because zones never include y <= 3).
func _effective_grid_top(x: int, z: int, slice_y: int) -> int:
	var top_y := int(WorldGenerator.get_visible_surface_y(x, z))
	if top_y < 0:
		return -1
	top_y = mini(top_y, slice_y)
	while top_y >= 0 and (_zone_by_block.has(Vector3i(x, top_y, z)) or _mined_blocks.has(Vector3i(x, top_y, z))):
		top_y -= 1
	return top_y


func _append_visible_side_grid(
		x: int,
		top_y: int,
		z: int,
		dir: Vector2i,
		slice_y: int,
		color: Color,
		verts: PackedVector3Array,
		cols: PackedColorArray) -> void:

	var nx := x + dir.x
	var nz := z + dir.y
	var neighbor_top := -1
	if nx >= 0 and nx < WORLD_SIZE_X and nz >= 0 and nz < WORLD_SIZE_Z:
		# Effective (slice- and cut-aware) neighbour top, so cut walls grid from
		# the cut lip down and flat plane-cut floors emit no side faces between
		# equal tops (doc 11 Phase 2b).
		neighbor_top = _effective_grid_top(nx, nz, slice_y)
	if neighbor_top >= top_y:
		return

	var bottom_y := maxi(neighbor_top + 1, 0)
	var top_limit := mini(top_y, slice_y)
	for y in range(bottom_y, top_limit + 1):
		_append_side_face_grid(x, y, z, dir, color, verts, cols)


func _append_top_face_grid(
		x: int,
		y: int,
		z: int,
		color: Color,
		verts: PackedVector3Array,
		cols: PackedColorArray) -> void:

	var top := float(y + 1) + TERRAIN_GRID_OFFSET
	var a := Vector3(float(x), top, float(z))
	var b := Vector3(float(x + 1), top, float(z))
	var c := Vector3(float(x + 1), top, float(z + 1))
	var d := Vector3(float(x), top, float(z + 1))
	_append_grid_line(a, b, color, verts, cols)
	_append_grid_line(b, c, color, verts, cols)
	_append_grid_line(c, d, color, verts, cols)
	_append_grid_line(d, a, color, verts, cols)


func _append_side_face_grid(
		x: int,
		y: int,
		z: int,
		dir: Vector2i,
		color: Color,
		verts: PackedVector3Array,
		cols: PackedColorArray) -> void:

	var y0 := float(y)
	var y1 := float(y + 1)
	var a: Vector3
	var b: Vector3
	var c: Vector3
	var d: Vector3

	if dir.x < 0:
		var fx := float(x) - TERRAIN_GRID_OFFSET
		a = Vector3(fx, y0, float(z))
		b = Vector3(fx, y1, float(z))
		c = Vector3(fx, y1, float(z + 1))
		d = Vector3(fx, y0, float(z + 1))
	elif dir.x > 0:
		var fx := float(x + 1) + TERRAIN_GRID_OFFSET
		a = Vector3(fx, y0, float(z + 1))
		b = Vector3(fx, y1, float(z + 1))
		c = Vector3(fx, y1, float(z))
		d = Vector3(fx, y0, float(z))
	elif dir.y < 0:
		var fz := float(z) - TERRAIN_GRID_OFFSET
		a = Vector3(float(x + 1), y0, fz)
		b = Vector3(float(x + 1), y1, fz)
		c = Vector3(float(x), y1, fz)
		d = Vector3(float(x), y0, fz)
	else:
		var fz := float(z + 1) + TERRAIN_GRID_OFFSET
		a = Vector3(float(x), y0, fz)
		b = Vector3(float(x), y1, fz)
		c = Vector3(float(x + 1), y1, fz)
		d = Vector3(float(x + 1), y0, fz)

	_append_grid_line(a, b, color, verts, cols)
	_append_grid_line(b, c, color, verts, cols)
	_append_grid_line(c, d, color, verts, cols)
	_append_grid_line(d, a, color, verts, cols)


func _append_grid_line(
		a: Vector3,
		b: Vector3,
		color: Color,
		verts: PackedVector3Array,
		cols: PackedColorArray) -> void:

	verts.append(a)
	verts.append(b)
	cols.append(color)
	cols.append(color)


func _update_hover_preview(force: bool = false) -> void:
	var hit := _raycast_mouse()
	if _dict_equal_hit(hit, _hover_hit) and not force:
		return
	_hover_hit = hit

	if _hover_hit.is_empty():
		_preview_raw_blocks.clear()
		_preview_blocks.clear()
		_preview_fill_node.mesh = null
		_preview_node.mesh = null
		_label_horizontal.visible = false
		_label_vertical.visible = false
		return

	var start_hit := _anchor_hit if _state == ToolState.DRAGGING and not _anchor_hit.is_empty() else _hover_hit
	_preview_raw_blocks = _build_precision_region(
		start_hit["block_pos"],
		_hover_hit["block_pos"],
		start_hit["face_normal"],
		_horizontal_size,
		_vertical_size)
	_preview_blocks = _filter_mineable_blocks(_preview_raw_blocks)
	_preview_is_remove = Input.is_key_pressed(KEY_CTRL)
	_rebuild_preview_mesh()
	_update_size_labels(_preview_raw_blocks)


func _dict_equal_hit(a: Dictionary, b: Dictionary) -> bool:
	if a.is_empty() or b.is_empty():
		return a.is_empty() and b.is_empty()
	return a.get("block_pos", Vector3i.ZERO) == b.get("block_pos", Vector3i.ZERO) \
		and a.get("face_normal", Vector3i.ZERO) == b.get("face_normal", Vector3i.ZERO)


func _handle_resize_wheel(button_index: MouseButton) -> bool:
	var delta := 1 if button_index == MOUSE_BUTTON_WHEEL_UP else -1
	if Input.is_key_pressed(KEY_SHIFT):
		_horizontal_size = clampi(_horizontal_size + delta, 1, _max_horizontal)
		return true
	if Input.is_key_pressed(KEY_ALT):
		_vertical_size = clampi(_vertical_size + delta, 1, _max_vertical)
		return true
	return false


func _confirm_preview() -> void:
	if _preview_blocks.is_empty():
		return
	if Input.is_key_pressed(KEY_CTRL):
		_remove_blocks_from_zones(_preview_blocks)
		return

	var blocks: Array[Vector3i] = []
	for block: Vector3i in _preview_blocks:
		if not _zone_by_block.has(block):
			blocks.append(block)
	if blocks.is_empty():
		return

	var zone_id := _next_zone_id
	_next_zone_id += 1
	_zones[zone_id] = {
		"id": zone_id,
		"tool": "mine_precision",
		"blocks": blocks,
		"enabled": true,
	}
	for block: Vector3i in blocks:
		_zone_by_block[block] = zone_id
	_rebuild_zones_mesh()
	_add_visual_cut_blocks(blocks)
	# New cut blocks change the effective grid tops (Phase 2b) — re-grid now.
	_rebuild_terrain_grid(true)


func _filter_mineable_blocks(blocks: Array[Vector3i]) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	for block: Vector3i in blocks:
		if not _in_bounds(block):
			continue
		if block.y <= BEDROCK_MAX_Y:
			continue
		# VisibleVolume clip (doc 11 Phase 3): you designate what you can see —
		# the marquee is visible-volume-intersected, exactly like Stonehearth's
		# custom-block handler (ref doc 10 §2.5). Blocks above the plane are
		# excluded from the DESIGNATION, not just the display (WYSIWYG).
		if not _visible_in_slice(block):
			continue
		# DEV-mined blocks are gone — air cannot be designated.
		if _mined_blocks.has(block):
			continue
		var block_id := _block_id_at(block)
		if not BlockRegistry.is_solid(block_id):
			continue
		var def := BlockRegistry.get_def(BlockRegistry.get_key(block_id))
		if String(def.get("kind", "")) == "water":
			continue
		result.append(block)
	return result


func _block_id_at(pos: Vector3i) -> int:
	var id := WorldData.get_block(pos.x, pos.y, pos.z)
	if not BlockRegistry.is_transparent(id):
		return id
	if WorldGenerator.has_method("get_generated_block_id"):
		return WorldGenerator.get_generated_block_id(pos.x, pos.y, pos.z)
	return id


func _build_precision_region(
		anchor: Vector3i,
		current: Vector3i,
		normal: Vector3i,
		size_horizontal: int,
		size_vertical: int) -> Array[Vector3i]:

	var min_x := mini(anchor.x, current.x)
	var max_x := maxi(anchor.x, current.x) + 1
	var min_z := mini(anchor.z, current.z)
	var max_z := maxi(anchor.z, current.z) + 1

	var y_min: int
	var y_max_exclusive: int
	if normal.y != 0:
		y_min = anchor.y + 1 - size_vertical
		y_max_exclusive = anchor.y + 1
	else:
		y_min = anchor.y - floori(float(size_vertical) / 2.0)
		y_max_exclusive = anchor.y + floori(float(size_vertical) / 2.0 + 0.5)

	var x_range := _map_precision_axis(min_x, max_x, anchor.x, normal.x, size_horizontal)
	var z_range := _map_precision_axis(min_z, max_z, anchor.z, normal.z, size_horizontal)

	var result: Array[Vector3i] = []
	for x in range(x_range.x, x_range.y):
		for y in range(y_min, y_max_exclusive):
			for z in range(z_range.x, z_range.y):
				result.append(Vector3i(x, y, z))
	return result


func _map_precision_axis(
		min_coord: int,
		max_coord: int,
		origin_coord: int,
		normal_coord: int,
		size_horizontal: int) -> Vector2i:

	var extent := max_coord - min_coord
	var remainder := extent % size_horizontal
	if remainder > 0:
		extent = extent - remainder + size_horizontal
	if extent > _max_drag_length:
		extent = maxi(size_horizontal, extent - size_horizontal)

	var offset: float
	if normal_coord > 0:
		offset = float(size_horizontal) - 0.5 if min_coord == origin_coord else 0.5
	elif normal_coord < 0:
		offset = 0.5 if min_coord == origin_coord else float(size_horizontal) - 0.5
	else:
		offset = float(size_horizontal) / 2.0

	var min_result: int
	var max_result: int
	if min_coord == origin_coord:
		min_result = origin_coord - floori(offset)
		max_result = origin_coord - floori(offset) + extent
	else:
		min_result = origin_coord + floori(offset + 0.5) - extent
		max_result = origin_coord + floori(offset + 0.5)

	return Vector2i(min_result, max_result)


func _raycast_mouse() -> Dictionary:
	if _camera_rig == null or _camera_rig.camera_node == null:
		return {}
	var mouse_pos := get_viewport().get_mouse_position()
	return _raycast_voxel(mouse_pos)


func _raycast_voxel(screen_pos: Vector2) -> Dictionary:
	var camera := _camera_rig.camera_node
	var origin := camera.project_ray_origin(screen_pos)
	var direction := camera.project_ray_normal(screen_pos).normalized()
	var max_distance := camera.far

	var pos := Vector3i(floori(origin.x), floori(origin.y), floori(origin.z))
	var step := Vector3i(
		1 if direction.x > 0.0 else -1,
		1 if direction.y > 0.0 else -1,
		1 if direction.z > 0.0 else -1)
	var t_delta := Vector3(
		abs(1.0 / direction.x) if not is_zero_approx(direction.x) else INF,
		abs(1.0 / direction.y) if not is_zero_approx(direction.y) else INF,
		abs(1.0 / direction.z) if not is_zero_approx(direction.z) else INF)
	var t_max := Vector3(
		_axis_t_max(origin.x, direction.x, pos.x),
		_axis_t_max(origin.y, direction.y, pos.y),
		_axis_t_max(origin.z, direction.z, pos.z))
	var travelled := 0.0
	var face_normal := Vector3i.ZERO

	while travelled <= max_distance:
		# DEV-mined blocks are air: the ray passes through so the freshly
		# exposed blocks behind/beneath them can be designated (iterative digs).
		if _in_bounds(pos) and _visible_in_slice(pos) and not _mined_blocks.has(pos):
			var block_id := _block_id_at(pos)
			if BlockRegistry.is_solid(block_id):
				var def := BlockRegistry.get_def(BlockRegistry.get_key(block_id))
				if String(def.get("kind", "")) != "water":
					return {
						"hit": true,
						"block_pos": pos,
						"face_normal": face_normal,
						"block_id": block_id,
					}

		if t_max.x <= t_max.y and t_max.x <= t_max.z:
			pos.x += step.x
			travelled = t_max.x
			t_max.x += t_delta.x
			face_normal = Vector3i(-step.x, 0, 0)
		elif t_max.y <= t_max.z:
			pos.y += step.y
			travelled = t_max.y
			t_max.y += t_delta.y
			face_normal = Vector3i(0, -step.y, 0)
		else:
			pos.z += step.z
			travelled = t_max.z
			t_max.z += t_delta.z
			face_normal = Vector3i(0, 0, -step.z)

	return {}


func _axis_t_max(origin_axis: float, direction_axis: float, pos_axis: int) -> float:
	if is_zero_approx(direction_axis):
		return INF
	var boundary := float(pos_axis + 1) if direction_axis > 0.0 else float(pos_axis)
	return (boundary - origin_axis) / direction_axis


## Single visibility test for everything this controller draws or designates —
## routed through the renderer's VisibleVolume contract (doc 11 Phase 3) so the
## future X-Ray set composes in with zero changes here.
func _visible_in_slice(pos: Vector3i) -> bool:
	if _renderer != null and _renderer.has_method("is_block_visible"):
		return bool(_renderer.call("is_block_visible", pos))
	return pos.y <= _current_slice_y()


func _current_slice_y() -> int:
	if _renderer == null:
		return WORLD_SIZE_Y - 1
	return int(_renderer.get("slice_y"))


func _rebuild_preview_mesh() -> void:
	_preview_node.material_override = _preview_remove_material if _preview_is_remove else _preview_material
	_preview_fill_node.material_override = _preview_remove_fill_material if _preview_is_remove else _preview_fill_material
	var fill_color := Color(1.0, 0.05, 0.03, 0.18) if _preview_is_remove else Color(1.0, 0.90, 0.0, 0.42)
	var line_color := Color(1.0, 0.05, 0.03, 1) if _preview_is_remove else Color(1.0, 0.98, 0.0, 1)
	# VisibleVolume clip (doc 11 Phase 3): the preview shows exactly what confirm
	# will designate — nothing paints above the plane (matches the
	# _filter_mineable_blocks visibility clip).
	var display_blocks: Array[Vector3i] = []
	for block: Vector3i in _preview_raw_blocks:
		if _visible_in_slice(block):
			display_blocks.append(block)
	_preview_fill_node.mesh = _build_fill_mesh(display_blocks, fill_color, 0.018)
	_preview_node.mesh = _build_bounds_line_mesh(display_blocks, line_color, 0.018)
	_preview_fill_node.visible = not display_blocks.is_empty()
	_preview_node.visible = not display_blocks.is_empty()


func _rebuild_zones_mesh() -> void:
	var line_verts: PackedVector3Array = []
	var line_cols: PackedColorArray = []
	var fill_verts: PackedVector3Array = []
	var fill_cols: PackedColorArray = []
	for zone_id: int in _zones.keys():
		var zone: Dictionary = _zones[zone_id]
		var blocks: Array = zone.get("blocks", [])
		# VisibleVolume clip (doc 11 Phase 3, decision 2026-06-05): the overlay
		# never paints inside hidden rock — Stonehearth's choice. A zone fully
		# above the plane disappears (data untouched); a partially-cut zone
		# closes its outline at the plane.
		var visible_blocks: Array[Vector3i] = []
		for block: Vector3i in blocks:
			if _visible_in_slice(block):
				visible_blocks.append(block)
		if visible_blocks.is_empty():
			continue
		var line_color := Color(1.0, 0.05, 0.03, 1.0) if zone_id == _selected_zone_id else Color(1.0, 0.88, 0.0, 0.92)
		var fill_color := Color(1.0, 0.05, 0.03, 0.28) if zone_id == _selected_zone_id else Color(1.0, 0.88, 0.0, 0.22)
		_append_block_faces(visible_blocks, fill_color, fill_verts, fill_cols, 0.008)
		_append_exterior_region_lines(visible_blocks, line_color, line_verts, line_cols, 0.010)

	if line_verts.is_empty():
		_zones_node.mesh = null
	else:
		var line_arrays: Array = []
		line_arrays.resize(Mesh.ARRAY_MAX)
		line_arrays[Mesh.ARRAY_VERTEX] = line_verts
		line_arrays[Mesh.ARRAY_COLOR] = line_cols
		var line_mesh := ArrayMesh.new()
		line_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, line_arrays)
		_zones_node.mesh = line_mesh

	if fill_verts.is_empty():
		_zones_fill_node.mesh = null
	else:
		var fill_arrays: Array = []
		fill_arrays.resize(Mesh.ARRAY_MAX)
		fill_arrays[Mesh.ARRAY_VERTEX] = fill_verts
		fill_arrays[Mesh.ARRAY_COLOR] = fill_cols
		var fill_mesh := ArrayMesh.new()
		fill_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, fill_arrays)
		_zones_fill_node.mesh = fill_mesh


func _sync_visual_cut_blocks() -> void:
	if _renderer == null or not _renderer.has_method("set_visual_cut_blocks"):
		return
	var cut_blocks: Dictionary = {}
	for zone_id: int in _zones.keys():
		var zone: Dictionary = _zones[zone_id]
		for block: Vector3i in zone.get("blocks", []):
			cut_blocks[block] = true
	_renderer.call("set_visual_cut_blocks", cut_blocks)


func _add_visual_cut_blocks(blocks: Array[Vector3i]) -> void:
	if _renderer == null:
		return
	if _renderer.has_method("add_visual_cut_blocks"):
		_renderer.call("add_visual_cut_blocks", blocks)
	else:
		_sync_visual_cut_blocks()


func _remove_visual_cut_blocks(blocks: Array[Vector3i]) -> void:
	if _renderer == null:
		return
	if _renderer.has_method("remove_visual_cut_blocks"):
		_renderer.call("remove_visual_cut_blocks", blocks)
	else:
		_sync_visual_cut_blocks()


func _build_line_mesh(blocks: Array[Vector3i], color: Color, inset: float) -> ArrayMesh:
	var verts: PackedVector3Array = []
	var cols: PackedColorArray = []
	_append_block_lines(blocks, color, verts, cols, inset)
	if verts.is_empty():
		return null
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = cols
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	return mesh


func _build_bounds_line_mesh(blocks: Array[Vector3i], color: Color, outset: float) -> ArrayMesh:
	if blocks.is_empty():
		return null
	var verts: PackedVector3Array = []
	var cols: PackedColorArray = []
	_append_bounds_lines(_bounds_for_blocks(blocks), color, verts, cols, outset)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = cols
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	return mesh


func _append_bounds_lines(
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


func _build_fill_mesh(blocks: Array[Vector3i], color: Color, outset: float) -> ArrayMesh:
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


func _append_block_faces(
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


func _append_exterior_region_lines(
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


func _add_exterior_face_edges(
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


func _face_corners(block: Vector3i, normal: Vector3i, outset: float) -> Array[Vector3]:
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


func _count_edge_normal(a: Vector3, b: Vector3, normal: Vector3i, edge_normals: Dictionary) -> void:
	var key := _edge_key(a, b)
	if not edge_normals.has(key):
		edge_normals[key] = {}
	var normals: Dictionary = edge_normals[key]
	normals[_normal_key(normal)] = true
	edge_normals[key] = normals


func _normal_key(normal: Vector3i) -> String:
	return "%d,%d,%d" % [normal.x, normal.y, normal.z]


func _edge_key(a: Vector3, b: Vector3) -> String:
	var ka := _point_key(a)
	var kb := _point_key(b)
	return "%s|%s" % [ka, kb] if ka < kb else "%s|%s" % [kb, ka]


func _point_key(point: Vector3) -> String:
	return "%d,%d,%d" % [
		roundi(point.x * 1000.0),
		roundi(point.y * 1000.0),
		roundi(point.z * 1000.0),
	]


func _edge_key_to_points(key: String) -> Array[Vector3]:
	var parts := key.split("|")
	if parts.size() != 2:
		return []
	return [_point_key_to_vector(parts[0]), _point_key_to_vector(parts[1])]


func _point_key_to_vector(key: String) -> Vector3:
	var parts := key.split(",")
	if parts.size() != 3:
		return Vector3.ZERO
	return Vector3(float(parts[0]) / 1000.0, float(parts[1]) / 1000.0, float(parts[2]) / 1000.0)


func _append_block_face(
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


func _append_face_triangle(
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


func _append_block_lines(
		blocks: Array,
		color: Color,
		verts: PackedVector3Array,
		cols: PackedColorArray,
		inset: float) -> void:

	var corners := [
		Vector3(inset, inset, inset),
		Vector3(1.0 - inset, inset, inset),
		Vector3(1.0 - inset, 1.0 - inset, inset),
		Vector3(inset, 1.0 - inset, inset),
		Vector3(inset, inset, 1.0 - inset),
		Vector3(1.0 - inset, inset, 1.0 - inset),
		Vector3(1.0 - inset, 1.0 - inset, 1.0 - inset),
		Vector3(inset, 1.0 - inset, 1.0 - inset),
	]
	var edges := [
		[0, 1], [1, 2], [2, 3], [3, 0],
		[4, 5], [5, 6], [6, 7], [7, 4],
		[0, 4], [1, 5], [2, 6], [3, 7],
	]

	for block: Vector3i in blocks:
		var base := Vector3(block) - Vector3(inset * 0.5, inset * 0.5, inset * 0.5)
		for edge: Array in edges:
			verts.append(base + corners[edge[0] as int])
			verts.append(base + corners[edge[1] as int])
			cols.append(color)
			cols.append(color)


func _update_size_labels(raw_blocks: Array[Vector3i]) -> void:
	if raw_blocks.is_empty():
		_label_horizontal.visible = false
		_label_vertical.visible = false
		return
	var bounds := _bounds_for_blocks(raw_blocks)
	var top := float(bounds.position.y + bounds.size.y) + 0.85
	var center := bounds.position + bounds.size * 0.5

	_label_horizontal.text = str(_horizontal_size)
	_label_horizontal.global_position = Vector3(center.x, top, bounds.position.z - 0.85)
	_label_horizontal.visible = _horizontal_size > 1

	_label_vertical.text = str(_vertical_size)
	_label_vertical.global_position = Vector3(bounds.position.x - 0.85, top, center.z)
	_label_vertical.visible = _vertical_size > 1


func _bounds_for_blocks(blocks: Array[Vector3i]) -> AABB:
	var min_v := blocks[0]
	var max_v := blocks[0]
	for block: Vector3i in blocks:
		min_v = Vector3i(mini(min_v.x, block.x), mini(min_v.y, block.y), mini(min_v.z, block.z))
		max_v = Vector3i(maxi(max_v.x, block.x), maxi(max_v.y, block.y), maxi(max_v.z, block.z))
	return AABB(Vector3(min_v), Vector3(max_v - min_v + Vector3i.ONE))


func _try_select_zone_at_screen(screen_pos: Vector2) -> bool:
	var hit := _raycast_voxel(screen_pos)
	if hit.is_empty():
		return false
	var block: Vector3i = hit.get("block_pos", Vector3i.ZERO)
	if not _zone_by_block.has(block):
		return false
	_selected_zone_id = int(_zone_by_block[block])
	_open_zone_window(_selected_zone_id)
	_rebuild_zones_mesh()
	return true


func _open_zone_window(zone_id: int) -> void:
	if not _zones.has(zone_id):
		return
	var zone: Dictionary = _zones[zone_id]
	_zone_title.text = "Mining Zone"
	_zone_body.text = "Blocks: %d" % (zone.get("blocks", []) as Array).size()
	_zone_window.visible = true


func _close_zone_window() -> void:
	_zone_window.visible = false
	_selected_zone_id = -1
	_rebuild_zones_mesh()


func _remove_selected_zone() -> void:
	if _selected_zone_id < 0:
		return
	_remove_zone(_selected_zone_id)
	_close_zone_window()


# ── DEV instant mine (testing tool — no drops) ────────────────────────────────

func _dev_mine_selected_zone() -> void:
	if _selected_zone_id < 0:
		return
	_dev_mine_zone(_selected_zone_id)
	_close_zone_window()


## Executes a zone immediately: its blocks leave the game. The renderer's
## visual cuts are deliberately KEPT (in overview mode the cut set is the
## authoritative record of removal — the generated heightmap would resurrect
## the rock otherwise); zone bookkeeping is erased so the overlay disappears;
## WorldData gets void written wherever a chunk actually exists (streamed-mode
## correctness — never allocate chunks just to hold air). No drops.
func _dev_mine_zone(zone_id: int) -> void:
	if not _zones.has(zone_id):
		return
	var zone: Dictionary = _zones[zone_id]
	var mined: Array[Vector3i] = []
	for block: Vector3i in zone.get("blocks", []):
		if _zone_by_block.get(block, -1) == zone_id:
			_zone_by_block.erase(block)
		_mined_blocks[block] = true
		mined.append(block)
		if WorldData.chunk_exists(
				floori(float(block.x) / 16.0),
				floori(float(block.y) / 16.0),
				floori(float(block.z) / 16.0)):
			WorldData.set_block(block.x, block.y, block.z, BlockRegistry.AIR_ID)
	_zones.erase(zone_id)
	# NOTE: no _remove_visual_cut_blocks() here — the cuts ARE the mined holes.
	# Promote the blocks to MINED in the renderer (doc 11 Phase SO-2b): punches
	# wall side-bands and grows the cavity shell.
	if _renderer != null and _renderer.has_method("add_mined_blocks"):
		_renderer.call("add_mined_blocks", mined)
	_rebuild_zones_mesh()
	if _state != ToolState.INACTIVE:
		_rebuild_terrain_grid(true)   # mined blocks change effective grid tops
		_update_hover_preview(true)
	print("MiningDesignationController: DEV mined zone %d (%d blocks, no drops)." % [
		zone_id, (zone.get("blocks", []) as Array).size()])


func _remove_zone(zone_id: int) -> void:
	if not _zones.has(zone_id):
		return
	var zone: Dictionary = _zones[zone_id]
	var removed_blocks: Array[Vector3i] = []
	for block: Vector3i in zone.get("blocks", []):
		if _zone_by_block.get(block, -1) == zone_id:
			_zone_by_block.erase(block)
			removed_blocks.append(block)
	_zones.erase(zone_id)
	_rebuild_zones_mesh()
	_remove_visual_cut_blocks(removed_blocks)
	if _state != ToolState.INACTIVE:
		_rebuild_terrain_grid(true)   # restored blocks change effective grid tops (Phase 2b)


func _remove_blocks_from_zones(blocks: Array[Vector3i]) -> void:
	var affected: Dictionary = {}
	var removed_blocks: Array[Vector3i] = []
	for block: Vector3i in blocks:
		if _zone_by_block.has(block):
			affected[int(_zone_by_block[block])] = true
			_zone_by_block.erase(block)
			removed_blocks.append(block)

	for zone_id: int in affected.keys():
		if not _zones.has(zone_id):
			continue
		var zone: Dictionary = _zones[zone_id]
		var kept: Array[Vector3i] = []
		for block: Vector3i in zone.get("blocks", []):
			if _zone_by_block.get(block, -1) == zone_id:
				kept.append(block)
		if kept.is_empty():
			_zones.erase(zone_id)
		else:
			zone["blocks"] = kept
			_zones[zone_id] = zone
	if affected.has(_selected_zone_id) and not _zones.has(_selected_zone_id):
		_close_zone_window()
	_rebuild_zones_mesh()
	_remove_visual_cut_blocks(removed_blocks)
	if _state != ToolState.INACTIVE:
		_rebuild_terrain_grid(true)   # restored blocks change effective grid tops (Phase 2b)


func _in_bounds(pos: Vector3i) -> bool:
	return pos.x >= 0 and pos.x < WORLD_SIZE_X \
		and pos.y >= 0 and pos.y < WORLD_SIZE_Y \
		and pos.z >= 0 and pos.z < WORLD_SIZE_Z
