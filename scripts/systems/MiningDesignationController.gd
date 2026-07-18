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
const FALLBACK_ZONE_MAX_WORKERS := 4
const FALLBACK_SWING_BASE_TIME := 2.0

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
var _zone_max_workers: int = FALLBACK_ZONE_MAX_WORKERS
var _swing_base_time: float = FALLBACK_SWING_BASE_TIME
var _reach_up: int = 5
var _reach_down: int = 1

## Cached ItemDropManager scene node (group lookup, lazy).
var _drop_manager_node: Node = null

## Set when a mined block changes effective grid tops; drained in _process
## while the tool is active (per-block forced rebuilds would thrash).
var _grid_dirty: bool = false

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
## Exposed-layer nodes (doc 05 overlay readability, 2026-06-05): share the ghost
## layer's meshes but use depth-TESTED materials, so terrain occludes them — the
## GPU does the exposed/hidden partition. Exposed faces read strong; hidden
## structure shows only the faint no-depth ghost beneath.
var _preview_fill_exposed_node: MeshInstance3D
var _preview_exposed_node: MeshInstance3D

## Per-zone overlay nodes (doc 05, 2026-06-05): each confirmed zone owns its own
## ghost/exposed fill+line MeshInstance3Ds, so confirm/remove/select/DEV-mine
## rebuilds touch ONE zone's geometry, and slice steps skip zones whose clip
## state cannot have changed (cached Y-range test below).
var _zones_root: Node3D
var _zone_overlays: Dictionary = {}   # zone_id -> {root, fill, fill_exposed, line, line_exposed, min_y, max_y, state, slice_y}

## Clip-state cache values for the slice-step skip rule. Assumes visibility is
## the slice plane only (renderer is_block_visible today) — revisit when X-Ray
## joins the visible-volume contract.
const ZONE_CLIP_FULL := 0      # whole zone at/below the plane → fully visible
const ZONE_CLIP_PARTIAL := 1   # plane cuts through the zone's Y range
const ZONE_CLIP_HIDDEN := 2    # whole zone above the plane → invisible
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
var _ui_layer: CanvasLayer
var _zone_window: PanelContainer
var _zone_title: Label
var _zone_body: Label
var _hint_window: PanelContainer
var _last_grid_center := Vector2i(-999999, -999999)
var _last_grid_slice := -999999
var _last_grid_radius := -1


func _ready() -> void:
	add_to_group(SaveManager.OWNER_GROUP)
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

	# Work-source routing (doc 16 step 5): zones are work sources; TaskManager
	# signals route reservation releases and lease accounting back to the
	# owning MiningZoneComponent. The controller is the single router.
	TaskManager.task_released.connect(_on_zone_task_released)
	TaskManager.task_completed.connect(_on_zone_task_completed)
	TaskManager.task_failed.connect(_on_zone_task_failed)
	TaskManager.task_cancelled.connect(_on_zone_task_cancelled)
	# Zero-lease zone revival: terrain changes near a stalled zone re-arm it
	# (mirrors TaskManager's chunk-dirtied early re-arm for blocked tasks).
	WorldData.chunk_dirtied.connect(_on_world_chunk_dirtied, CONNECT_DEFERRED)


## One reactive rebuild per visibility change (the renderer emits at most once
## per frame). Zones re-clip even while the tool is inactive — confirmed zones
## are always on screen; grid and preview only exist while the tool is active.
## Per-zone skip rule (doc 05, 2026-06-05): a zone re-clips only if the plane
## change can alter its clip — fully-visible stays fully-visible and hidden
## stays hidden for O(1) per zone; only PARTIAL zones (and state transitions)
## pay the rebuild. Assumes plane-only visibility; revisit with X-Ray.
func _on_visible_volume_changed() -> void:
	var slice_y := _current_slice_y()
	for zone_id: int in _zones.keys():
		var entry: Dictionary = _zone_overlays.get(zone_id, {})
		if entry.is_empty():
			_rebuild_zone_overlay(zone_id)
			continue
		var new_state := _zone_clip_state(int(entry["min_y"]), int(entry["max_y"]), slice_y)
		var old_state := int(entry["state"])
		if new_state == old_state and (new_state != ZONE_CLIP_PARTIAL or slice_y == int(entry["slice_y"])):
			continue
		_rebuild_zone_overlay(zone_id)
	if _state != ToolState.INACTIVE:
		_rebuild_terrain_grid(true)
		_update_hover_preview(true)


var _window_refresh_accum: float = 0.0

func _process(delta: float) -> void:
	# Keep the zone window's worker/blocked line live while it is open —
	# independent of tool state (the window outlives tool deactivation).
	if _zone_window != null and _zone_window.visible and _selected_zone_id >= 0:
		_window_refresh_accum += delta
		if _window_refresh_accum >= 0.5:
			_window_refresh_accum = 0.0
			if _zones.has(_selected_zone_id):
				_open_zone_window(_selected_zone_id)
	if _state == ToolState.INACTIVE:
		return
	if _grid_dirty:
		_grid_dirty = false
		_rebuild_terrain_grid(true)   # mined blocks changed effective grid tops
	_rebuild_terrain_grid()
	# Modifier redraw (#4): force a rebuild when Ctrl is pressed/released so the
	# removal colour updates even if the cursor has not moved to a new block
	# (otherwise _update_hover_preview early-returns on an unchanged hit).
	var ctrl_changed := Input.is_key_pressed(KEY_CTRL) != _preview_is_remove
	_update_hover_preview(ctrl_changed)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and key.keycode == KEY_ESCAPE and _state != ToolState.INACTIVE:
			_deactivate_tool()
			get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		# Tool cancel is ESC-only (above). Right-mouse is reserved for the camera orbit
		# (21_camera.md, Tool input contract) — do not consume it here.

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
		# Another click-tool is activating — close this one (the doc 16 tool-
		# exclusion wart, fixed 2026-07-06 after two active tools ate one click).
		if _state != ToolState.INACTIVE:
			_deactivate_tool()
		return
	_state = ToolState.HOVER
	_terrain_grid_node.visible = true
	_preview_node.visible = true
	_preview_exposed_node.visible = true
	if _hint_window != null:
		_hint_window.visible = true
	_rebuild_terrain_grid(true)
	# The wheel now resizes the brush, so stop the camera zooming on it while active.
	if _camera_rig != null and _camera_rig.has_method("set_zoom_suppressed"):
		_camera_rig.set_zoom_suppressed(true)
	print("MiningDesignationController: precision mining active.")


func _deactivate_tool() -> void:
	_state = ToolState.INACTIVE
	if _camera_rig != null and _camera_rig.has_method("set_zoom_suppressed"):
		_camera_rig.set_zoom_suppressed(false)   # hand the wheel back to camera zoom
	_anchor_hit.clear()
	_hover_hit.clear()
	_preview_raw_blocks.clear()
	_preview_blocks.clear()
	_terrain_grid_node.visible = false
	_terrain_grid_node.mesh = null
	_preview_fill_node.visible = false
	_preview_fill_node.mesh = null
	_preview_fill_exposed_node.visible = false
	_preview_fill_exposed_node.mesh = null
	_preview_node.visible = false
	_preview_exposed_node.visible = false
	_clear_dimension_overlay()
	if _hint_window != null:
		_hint_window.visible = false
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
	var zone_cfg: Dictionary = root.get("zone", {})
	_zone_max_workers = int(zone_cfg.get("max_workers", FALLBACK_ZONE_MAX_WORKERS))
	var exec_cfg: Dictionary = root.get("execution", {})
	_swing_base_time = float(exec_cfg.get("swing_base_time_s", FALLBACK_SWING_BASE_TIME))
	_reach_up = int(exec_cfg.get("reach_up_blocks", _reach_up))
	_reach_down = int(exec_cfg.get("reach_down_blocks", _reach_down))


func _build_materials() -> void:
	_terrain_grid_material = _line_material(Color(0, 0, 0, 0.28), false)
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

	_preview_fill_exposed_node = MeshInstance3D.new()
	_preview_fill_exposed_node.name = "MiningPreviewFillExposed"
	_preview_fill_exposed_node.material_override = _preview_fill_exposed_material
	_preview_fill_exposed_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_preview_fill_exposed_node.visible = false
	add_child(_preview_fill_exposed_node)

	_preview_node = MeshInstance3D.new()
	_preview_node.name = "MiningPreview"
	_preview_node.material_override = _preview_material
	_preview_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_preview_node.visible = false
	add_child(_preview_node)

	_preview_exposed_node = MeshInstance3D.new()
	_preview_exposed_node.name = "MiningPreviewExposed"
	_preview_exposed_node.material_override = _preview_exposed_material
	_preview_exposed_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_preview_exposed_node.visible = false
	add_child(_preview_exposed_node)

	_zones_root = Node3D.new()
	_zones_root.name = "MiningZoneOverlays"
	add_child(_zones_root)

	_ruler_node = MeshInstance3D.new()
	_ruler_node.name = "MiningRulers"
	_ruler_node.material_override = _ruler_material
	_ruler_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ruler_node.visible = false
	add_child(_ruler_node)

	_label_x = _make_size_label("1")
	_label_z = _make_size_label("1")
	_label_y = _make_size_label("1")
	add_child(_label_x)
	add_child(_label_z)
	add_child(_label_y)


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

	_build_hint_window()


## Mining-mode instruction callout (#5): a small control-summary panel shown while
## the tool is active. Informational only — ignores the mouse so it never blocks
## clicks. Cursor assets are deferred (see doc 05).
func _build_hint_window() -> void:
	_hint_window = PanelContainer.new()
	_hint_window.name = "MiningHintWindow"
	_hint_window.visible = false
	_hint_window.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_window.add_theme_stylebox_override("panel", _window_style())
	# Centred near the top of the screen, content-sized.
	_hint_window.anchor_left = 0.5
	_hint_window.anchor_right = 0.5
	_hint_window.anchor_top = 0.0
	_hint_window.anchor_bottom = 0.0
	_hint_window.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hint_window.grow_vertical = Control.GROW_DIRECTION_END
	_hint_window.offset_top = 14.0
	_ui_layer.add_child(_hint_window)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 7)
	margin.add_theme_constant_override("margin_bottom", 8)
	_hint_window.add_child(margin)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 3)
	margin.add_child(column)

	var title := Label.new()
	title.text = "Mining Tool"
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 15)
	column.add_child(title)

	var body := Label.new()
	body.text = "Drag: designate   ·   Ctrl: remove\nShift / Alt + wheel: width / depth   ·   Esc or right-click: exit"
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_theme_font_size_override("font_size", 12)
	body.add_theme_color_override("font_color", Color(0.86, 0.82, 0.74))
	column.add_child(body)


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
	# Drag height locking (#1): while dragging from a horizontal (top/bottom) face,
	# lock the moving end to the anchor's height plane instead of following the
	# terrain raycast, so the selection footprint stays flat across slopes/terraces.
	if _state == ToolState.DRAGGING and not _anchor_hit.is_empty() \
			and int(_anchor_hit.get("face_normal", Vector3i.ZERO).y) > 0:
		var plane_hit := _raycast_anchor_plane()
		if not plane_hit.is_empty():
			hit = plane_hit
	if _dict_equal_hit(hit, _hover_hit) and not force:
		return
	_hover_hit = hit

	if _hover_hit.is_empty():
		_preview_raw_blocks.clear()
		_preview_blocks.clear()
		_preview_fill_node.mesh = null
		_preview_node.mesh = null
		_preview_fill_exposed_node.mesh = null
		_preview_exposed_node.mesh = null
		_clear_dimension_overlay()
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

	_create_zone(blocks)


func _create_zone(blocks: Array[Vector3i], requested_id: int = -1) -> int:
	var zone_id := requested_id if requested_id > 0 else _next_zone_id
	_next_zone_id = maxi(_next_zone_id, zone_id + 1)
	# The component is the WORK SOURCE (doc 16 §2.7): it owns the
	# region/completed/destination/reserved split. zone["blocks"] stays the
	# live REMAINING list for overlay/window paths (mined blocks are erased).
	var component := MiningZoneComponent.new(self, zone_id, blocks)
	component.reach_up = _reach_up
	component.reach_down = _reach_down
	_zones[zone_id] = {
		"id": zone_id,
		"tool": "mine_precision",
		"blocks": blocks,
		"enabled": true,
		"component": component,
	}
	for block: Vector3i in blocks:
		_zone_by_block[block] = zone_id
	TaskManager.register_work_source(zone_id, component)
	_top_up_zone_leases(zone_id)
	_rebuild_zone_overlay(zone_id)
	_add_visual_cut_blocks(blocks)
	# New cut blocks change the effective grid tops (Phase 2b) — re-grid now.
	_rebuild_terrain_grid(true)
	return zone_id


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


## Drag height locking (#1): intersect the mouse ray with the horizontal plane at
## the anchor block's top face and return a synthetic hit whose X/Z come from that
## intersection while Y stays pinned to the anchor. Used only mid-drag on a
## horizontal face so the rectangle does not climb slopes. Returns {} if the ray
## is parallel to the plane or points away from it (caller falls back to terrain).
func _raycast_anchor_plane() -> Dictionary:
	if _camera_rig == null or _camera_rig.camera_node == null or _anchor_hit.is_empty():
		return {}
	var camera := _camera_rig.camera_node
	var mouse_pos := get_viewport().get_mouse_position()
	var origin := camera.project_ray_origin(mouse_pos)
	var direction := camera.project_ray_normal(mouse_pos).normalized()
	if is_zero_approx(direction.y):
		return {}
	var anchor_pos: Vector3i = _anchor_hit["block_pos"]
	# The selection rests on the anchor block's top face: plane at y = anchor.y + 1.
	var plane_y := float(anchor_pos.y) + 1.0
	var t := (plane_y - origin.y) / direction.y
	if t <= 0.0:
		return {}
	var p := origin + direction * t
	return {
		"hit": true,
		"block_pos": Vector3i(floori(p.x), anchor_pos.y, floori(p.z)),
		"face_normal": _anchor_hit["face_normal"],
		"block_id": _anchor_hit.get("block_id", 0),
	}


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
	_preview_exposed_node.material_override = _preview_remove_exposed_material if _preview_is_remove else _preview_exposed_material
	_preview_fill_exposed_node.material_override = _preview_remove_fill_exposed_material if _preview_is_remove else _preview_fill_exposed_material
	var fill_color := Color(1.0, 0.05, 0.03, 0.18) if _preview_is_remove else Color(1.0, 0.90, 0.0, 0.42)
	var line_color := Color(1.0, 0.05, 0.03, 1) if _preview_is_remove else Color(1.0, 0.98, 0.0, 1)
	# VisibleVolume clip (doc 11 Phase 3): the preview shows exactly what confirm
	# will designate — nothing paints above the plane (matches the
	# _filter_mineable_blocks visibility clip).
	var display_blocks: Array[Vector3i] = []
	for block: Vector3i in _preview_raw_blocks:
		if _visible_in_slice(block):
			display_blocks.append(block)
	# Ghost (no-depth, faint) and exposed (depth-tested, strong) layers share the
	# same meshes — the depth buffer partitions exposed from hidden for free.
	var fill_mesh := _build_fill_mesh(display_blocks, fill_color, 0.018)
	var line_mesh := _build_bounds_line_mesh(display_blocks, line_color, 0.018)
	_preview_fill_node.mesh = fill_mesh
	_preview_fill_exposed_node.mesh = fill_mesh
	_preview_node.mesh = line_mesh
	_preview_exposed_node.mesh = line_mesh
	var has_blocks := not display_blocks.is_empty()
	_preview_fill_node.visible = has_blocks
	_preview_fill_exposed_node.visible = has_blocks
	_preview_node.visible = has_blocks
	_preview_exposed_node.visible = has_blocks


## Rebuilds ONE zone's overlay geometry (creating its nodes on first use).
## VisibleVolume clip (doc 11 Phase 3, decision 2026-06-05): the overlay never
## paints inside hidden rock — Stonehearth's choice. A zone fully above the
## plane disappears (data untouched); a partially-cut zone closes its outline
## at the plane.
func _rebuild_zone_overlay(zone_id: int) -> void:
	if not _zones.has(zone_id):
		_free_zone_overlay(zone_id)
		return
	var zone: Dictionary = _zones[zone_id]
	var blocks: Array = zone.get("blocks", [])
	if blocks.is_empty():
		_free_zone_overlay(zone_id)
		return

	var entry: Dictionary = _zone_overlays.get(zone_id, {})
	if entry.is_empty():
		entry = _create_zone_overlay_nodes(zone_id)
		_zone_overlays[zone_id] = entry

	var slice_y := _current_slice_y()
	var min_y := WORLD_SIZE_Y
	var max_y := 0
	var visible_blocks: Array[Vector3i] = []
	for block: Vector3i in blocks:
		min_y = mini(min_y, block.y)
		max_y = maxi(max_y, block.y)
		if _visible_in_slice(block):
			visible_blocks.append(block)
	entry["min_y"] = min_y
	entry["max_y"] = max_y
	entry["slice_y"] = slice_y
	entry["state"] = _zone_clip_state(min_y, max_y, slice_y)

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
	var selected := zone_id == _selected_zone_id
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
	_zones_root.add_child(root)

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


func _free_zone_overlay(zone_id: int) -> void:
	var entry: Dictionary = _zone_overlays.get(zone_id, {})
	if entry.is_empty():
		return
	(entry["root"] as Node3D).queue_free()
	_zone_overlays.erase(zone_id)


func _rebuild_all_zone_overlays() -> void:
	# Free orphans first (zones erased without going through a removal path).
	for zone_id: int in _zone_overlays.keys().duplicate():
		if not _zones.has(zone_id):
			_free_zone_overlay(zone_id)
	for zone_id: int in _zones.keys():
		_rebuild_zone_overlay(zone_id)


func _zone_clip_state(min_y: int, max_y: int, slice_y: int) -> int:
	if max_y <= slice_y:
		return ZONE_CLIP_FULL
	if min_y > slice_y:
		return ZONE_CLIP_HIDDEN
	return ZONE_CLIP_PARTIAL


## Selection recolor: only the previously and newly selected zones rebake.
func _set_selected_zone(zone_id: int) -> void:
	if _selected_zone_id == zone_id:
		return
	var previous := _selected_zone_id
	_selected_zone_id = zone_id
	if previous >= 0 and _zones.has(previous):
		_rebuild_zone_overlay(previous)
	if zone_id >= 0 and _zones.has(zone_id):
		_rebuild_zone_overlay(zone_id)


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


## Stonehearth-style dimension overlay (#3): X and Z rulers (dimension bars with
## end caps + outward arrowheads and a midpoint count) laid flat on the top of the
## selection, plus a depth number at the top corner. Counts are the TRUE footprint
## extents, not the brush sizes. Rulers/labels hide on any axis of length <= 1.
func _update_size_labels(raw_blocks: Array[Vector3i]) -> void:
	if raw_blocks.is_empty():
		_clear_dimension_overlay()
		return
	var bounds := _bounds_for_blocks(raw_blocks)
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


func _clear_dimension_overlay() -> void:
	_ruler_node.mesh = null
	_ruler_node.visible = false
	_label_x.visible = false
	_label_z.visible = false
	_label_y.visible = false


## Builds the flat X/Z dimension bars (PRIMITIVE_LINES, vertex-coloured white) on
## the top plane of the selection. Returns null when neither axis spans > 1.
func _build_ruler_mesh(bounds: AABB) -> ArrayMesh:
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
func _append_dim_line(
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


func _push_line(
		verts: PackedVector3Array, cols: PackedColorArray, col: Color,
		p: Vector3, q: Vector3) -> void:
	verts.append(p)
	verts.append(q)
	cols.append(col)
	cols.append(col)


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
	_set_selected_zone(int(_zone_by_block[block]))
	_open_zone_window(_selected_zone_id)
	return true


func _open_zone_window(zone_id: int) -> void:
	if not _zones.has(zone_id):
		return
	var zone: Dictionary = _zones[zone_id]
	_zone_title.text = "Mining Zone"
	var component: MiningZoneComponent = zone.get("component")
	if component != null:
		var text := "Blocks left: %d / %d   Workers: %d   Faces: %d" % [
			component.remaining_count(), component.total_count(),
			component.reserved.size(), component.destination_count()]
		# Lease health: tell the player WHY nobody is coming (doc 31's
		# task_unreachable intent — no toast system yet, so it lives here).
		var now := Time.get_ticks_msec()
		var assigned := 0
		var blocked := 0
		for task_id: int in component.lease_ids.keys():
			var task := TaskManager.get_task(task_id)
			if task == null:
				continue
			if task.assigned_to >= 0:
				assigned += 1
			elif now < task.retry_at:
				blocked += 1
		if assigned == 0 and blocked > 0:
			text += "\nNo worker can reach this zone — retrying."
		_zone_body.text = text
	else:
		_zone_body.text = "Blocks: %d" % (zone.get("blocks", []) as Array).size()
	_zone_window.visible = true


func _close_zone_window() -> void:
	_zone_window.visible = false
	_set_selected_zone(-1)


func _remove_selected_zone() -> void:
	if _selected_zone_id < 0:
		return
	_remove_zone(_selected_zone_id)
	_close_zone_window()


# ── Zone work source — leases & execution (doc 16 steps 5/6) ─────────────────

## Posts MINE leases up to min(max_workers, unreserved remaining blocks).
## Leases are INTENT-sized (doc 16 §2.1) — at most max_workers per zone, never
## per-block tasks. Excess leases self-correct: a dwarf that pulls nothing
## completes its lease early.
func _top_up_zone_leases(zone_id: int) -> void:
	var zone: Dictionary = _zones.get(zone_id, {})
	if zone.is_empty():
		return
	var component: MiningZoneComponent = zone.get("component")
	if component == null:
		return
	var target := mini(_zone_max_workers, component.unreserved_remaining())
	while component.lease_ids.size() < target:
		var rep := component.representative_target()
		if rep.y < 0:
			break
		var task_id := TaskManager.add_task(
			Task.Type.MINE, rep, { "zone_id": zone_id }, zone_id)
		component.lease_ids[task_id] = true


## The component behind a task, or null if the task is not a zone lease.
func _zone_component_for(task: Task) -> MiningZoneComponent:
	if task == null or task.type != Task.Type.MINE:
		return null
	var zone: Dictionary = _zones.get(task.source_id, {})
	if zone.is_empty():
		return null
	return zone.get("component")


func _on_zone_task_released(task: Task, dwarf_id: int, _reason: int) -> void:
	var component := _zone_component_for(task)
	if component != null:
		component.release_worker(dwarf_id)   # reservation freed; completed set untouched (§2.8)


func _on_zone_task_completed(task: Task) -> void:
	_on_zone_lease_finished(task)


func _on_zone_task_failed(task: Task, _reason: String) -> void:
	_on_zone_lease_finished(task)


func _on_zone_task_cancelled(task: Task) -> void:
	_on_zone_lease_finished(task)


func _on_zone_lease_finished(task: Task) -> void:
	var component := _zone_component_for(task)
	if component == null:
		return
	component.lease_ids.erase(task.id)
	if task.assigned_to >= 0:
		component.release_worker(task.assigned_to)
	_maybe_destroy_finished_zone(task.source_id)
	if _zones.has(task.source_id):
		_refresh_zone_window(task.source_id)


## Stuck-zone revival: a terrain change near a zone with NO working dwarves
## refreshes it — destination recomputed, leases re-targeted and re-armed,
## missing leases reposted. This covers BOTH stall shapes:
##   - zero leases (all completed early while unreachable), and
##   - blocked leases whose targets went stale (zone designated while sealed;
##     a later dig exposes its face, but the leases kept probing the interior
##     rock they were aimed at on confirm — caught in-engine 2026-06-10).
## Zones with an assigned worker self-maintain (targets refresh on their own
## mined blocks), so they are skipped. Per-zone 250 ms throttle keeps the
## per-mined-block cost bounded; worldgen streaming is naturally cheap here
## because fresh zones rarely intersect streaming chunks without also being
## worked.
func _on_world_chunk_dirtied(cx: int, cy: int, cz: int) -> void:
	if _zones.is_empty():
		return
	var chunk := Vector3i(cx, cy, cz)
	var now := Time.get_ticks_msec()
	for zone_id: int in _zones.keys():
		var component: MiningZoneComponent = (_zones[zone_id] as Dictionary).get("component")
		if component == null or component.is_empty():
			continue
		if not component.intersects_chunk(chunk):
			continue
		if _zone_has_assigned_worker(component):
			continue
		if now - component.last_refresh_msec < 250:
			continue
		component.last_refresh_msec = now
		component.mark_destination_dirty()
		_top_up_zone_leases(zone_id)
		_refresh_zone_lease_targets(zone_id)


func _zone_has_assigned_worker(component: MiningZoneComponent) -> bool:
	for task_id: int in component.lease_ids.keys():
		var task := TaskManager.get_task(task_id)
		if task != null and task.assigned_to >= 0:
			return true
	return false


## Swing parameters for one block (doc 43: mine_time = base × hardness /
## skill; doc 16 §2.7: durability swings per block). Skill speed is applied by
## the AGENT (its profession multiplier) — this is the block's base cost.
## Called by MiningZoneComponent.get_block_work.
func get_zone_block_work(block: Vector3i) -> Dictionary:
	var block_id := _block_id_at(block)
	if not BlockRegistry.is_solid(block_id):
		return {}
	var key := BlockRegistry.get_key(block_id)
	var def := BlockRegistry.get_def(key)
	var hardness := maxi(int(def.get("hardness", 1)), 1)
	var res := BlockRegistry.get_resource_def(key)
	var durability := maxi(int(res.get("durability", 2)), 1)
	var block_time := _swing_base_time * float(hardness)
	return {
		"swings": durability,
		"swing_time": block_time / float(durability),
	}


## THE mining execution pipeline (doc 16 §2.7 step 4) — one block leaves the
## world. Called by MiningZoneComponent.commit_mined (real mining); the DEV
## instant-mine button runs the same world-mutation steps minus dwarf/drops.
## Returns false (and writes nothing) on any guard failure.
func execute_zone_block_mined(zone_id: int, block: Vector3i, dwarf_id: int) -> bool:
	var zone: Dictionary = _zones.get(zone_id, {})
	if zone.is_empty():
		return false
	# Hard Rule 1 — re-validated at the moment of the void write, independent
	# of designation-time filters.
	if block.y <= BEDROCK_MAX_Y:
		push_error("MiningDesignationController: bedrock write blocked at %s." % str(block))
		return false

	# Capture identity BEFORE the void write (drops + sanity).
	var pre_id := _block_id_at(block)
	var was_solid := BlockRegistry.is_solid(pre_id)

	_mine_block_world(block)
	if was_solid:
		_spawn_block_drops(pre_id, block)

	# Zone bookkeeping.
	var component: MiningZoneComponent = zone.get("component")
	if component != null:
		component.mark_completed(block, dwarf_id)
	(zone["blocks"] as Array).erase(block)

	if component != null and component.is_empty():
		_cancel_pending_zone_leases(zone_id)
		_maybe_destroy_finished_zone(zone_id)
	else:
		_rebuild_zone_overlay(zone_id)
		_top_up_zone_leases(zone_id)
		_refresh_zone_lease_targets(zone_id)
	if _zones.has(zone_id):
		_refresh_zone_window(zone_id)
	return true


## Mining opens new stand cells, so the zone's reachable-representative moves.
## Re-target the zone's still-PENDING leases (≤ max_workers of them) so their
## probes and the chunk-dirtied re-arm aim at live geometry, and clear their
## backoff — the terrain just changed in this very zone.
func _refresh_zone_lease_targets(zone_id: int) -> void:
	var zone: Dictionary = _zones.get(zone_id, {})
	var component: MiningZoneComponent = zone.get("component") if not zone.is_empty() else null
	if component == null:
		return
	var rep := component.representative_target()
	if rep.y < 0:
		return
	for task_id: int in component.lease_ids.keys():
		var task := TaskManager.get_task(task_id)
		if task == null or task.assigned_to >= 0:
			continue
		task.target_pos = rep
		task.retry_at = 0   # re-arm immediately; the next wake re-probes


## World-mutation core shared by real mining and DEV mine: materialise the
## chunk, write void through WorldData (NavGrid + future systems see truth —
## closes the step-3b DEV wart), promote to MINED in the renderer (exposure
## pipeline, SO-2b), feed X0, update controller raycast/grid bookkeeping.
func _mine_block_world(block: Vector3i) -> void:
	_ensure_chunk_real(block)
	WorldData.set_block(block.x, block.y, block.z, BlockRegistry.AIR_ID)
	_mined_blocks[block] = true
	if _zone_by_block.has(block):
		_zone_by_block.erase(block)
	if _renderer != null and _renderer.has_method("add_mined_blocks"):
		var mined: Array[Vector3i] = [block]
		_renderer.call("add_mined_blocks", mined)
	var x0_blocks: Array[Vector3i] = [block]
	InteriorTracker.on_blocks_mined(x0_blocks)
	_grid_dirty = true


## Materialises an ungenerated chunk from the deterministic generator before
## the first real write. Without this, WorldData's lazy chunk creation would
## hand back an ALL-VOID chunk and silently delete 4,095 innocent blocks.
## Cost: 4,096 generator calls, once per first-touched chunk (~ms scale) —
## acceptable for v1; thread it only if profiling ever disagrees (doc 11
## lesson: one variable at a time).
func _ensure_chunk_real(block: Vector3i) -> void:
	var cx := block.x >> 4
	var cy := block.y >> 4
	var cz := block.z >> 4
	if WorldData.chunk_exists(cx, cy, cz):
		return
	var chunk: Chunk = WorldData.get_chunk(cx, cy, cz)   # creates empty (all void)
	var has_void := false
	var base_x := cx << 4
	var base_y := cy << 4
	var base_z := cz << 4
	for ly in range(16):
		for lz in range(16):
			for lx in range(16):
				var id := int(WorldGenerator.get_generated_block_id(
					base_x + lx, base_y + ly, base_z + lz))
				chunk.blocks[Chunk.local_index(lx, ly, lz)] = id
				if BlockRegistry.is_transparent(id):
					has_void = true
	chunk.has_void = has_void


## Rolls the block's loot table (block_resources.json) and hands drops to the
## ItemDropManager. randf chance rolls are runtime behaviour, not worldgen —
## Hard Rule 8 (deterministic terrain identity) does not apply to drops.
func _spawn_block_drops(pre_block_id: int, block: Vector3i) -> void:
	var manager := _drop_manager()
	if manager == null:
		return
	var key := BlockRegistry.get_key(pre_block_id)
	var res := BlockRegistry.get_resource_def(key)
	var drops: Array = res.get("drops", [])
	for entry in drops:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var drop: Dictionary = entry
		if randf() > float(drop.get("chance", 1.0)):
			continue
		manager.call("spawn_drop",
			String(drop.get("item", "")), int(drop.get("count", 1)), block)


func _drop_manager() -> Node:
	if _drop_manager_node == null or not is_instance_valid(_drop_manager_node):
		_drop_manager_node = get_tree().get_first_node_in_group("item_drop_manager")
	return _drop_manager_node


## Cancels a finished zone's still-PENDING leases; assigned leases complete
## naturally (their dwarves pull nothing and finish).
func _cancel_pending_zone_leases(zone_id: int) -> void:
	var zone: Dictionary = _zones.get(zone_id, {})
	var component: MiningZoneComponent = zone.get("component") if not zone.is_empty() else null
	if component == null:
		return
	for task_id: int in component.lease_ids.keys().duplicate():
		var task := TaskManager.get_task(task_id)
		if task != null and task.assigned_to < 0:
			TaskManager.cancel_task(task_id)   # cancelled handler erases the lease id


## Destroys a zone once it is mined out AND its last lease has finished.
## (Player removal goes through _remove_zone instead — that path cancels
## assigned leases too.)
func _maybe_destroy_finished_zone(zone_id: int) -> void:
	var zone: Dictionary = _zones.get(zone_id, {})
	if zone.is_empty():
		return
	var component: MiningZoneComponent = zone.get("component")
	if component == null or not component.is_empty() or not component.lease_ids.is_empty():
		return
	TaskManager.unregister_work_source(zone_id)
	_zones.erase(zone_id)
	_free_zone_overlay(zone_id)
	if _selected_zone_id == zone_id:
		_close_zone_window()
	print("MiningDesignationController: zone %d mined out — destroyed." % zone_id)


func _refresh_zone_window(zone_id: int) -> void:
	if _selected_zone_id != zone_id or _zone_window == null or not _zone_window.visible:
		return
	_open_zone_window(zone_id)


# ── DEV instant mine (testing tool — no drops) ────────────────────────────────

func _dev_mine_selected_zone() -> void:
	if _selected_zone_id < 0:
		return
	_dev_mine_zone(_selected_zone_id)
	_close_zone_window()


## Executes a zone immediately: its blocks leave the game through the SAME
## world-mutation pipeline as real mining, minus the dwarf and minus drops
## (doc 16 Phase 4: "the same pipeline minus the dwarf"). The renderer's
## visual cuts are deliberately KEPT (in overview mode the cut set is the
## authoritative record of removal — the generated heightmap would resurrect
## the rock otherwise). Chunks are MATERIALISED before the void write, so
## WorldData and NavGrid see truth everywhere (the step-3b DEV wart is
## closed). X0 interior tracking runs here too.
func _dev_mine_zone(zone_id: int) -> void:
	if not _zones.has(zone_id):
		return
	var zone: Dictionary = _zones[zone_id]
	# Pull the work source out from under any dwarves first.
	TaskManager.cancel_source_tasks(zone_id)
	TaskManager.unregister_work_source(zone_id)
	var mined: Array[Vector3i] = []
	for block: Vector3i in zone.get("blocks", []):
		if block.y <= BEDROCK_MAX_Y:
			continue   # Hard Rule 1 — never write bedrock, even in DEV paths
		if _zone_by_block.get(block, -1) == zone_id:
			_zone_by_block.erase(block)
		_mined_blocks[block] = true
		mined.append(block)
		_ensure_chunk_real(block)
		WorldData.set_block(block.x, block.y, block.z, BlockRegistry.AIR_ID)
	_zones.erase(zone_id)
	# NOTE: no _remove_visual_cut_blocks() here — the cuts ARE the mined holes.
	# Promote the blocks to MINED in the renderer (doc 11 Phase SO-2b): punches
	# wall side-bands and grows the cavity shell.
	if _renderer != null and _renderer.has_method("add_mined_blocks"):
		_renderer.call("add_mined_blocks", mined)
	InteriorTracker.on_blocks_mined(mined)
	_free_zone_overlay(zone_id)
	if _state != ToolState.INACTIVE:
		_rebuild_terrain_grid(true)   # mined blocks change effective grid tops
		_update_hover_preview(true)
	print("MiningDesignationController: DEV mined zone %d (%d blocks, no drops)." % [
		zone_id, mined.size()])


func _remove_zone(zone_id: int) -> void:
	if not _zones.has(zone_id):
		return
	var zone: Dictionary = _zones[zone_id]
	# Player removal cancels EVERY lease, assigned ones included — working
	# dwarves abort and return to the idle pool (release protocol, §2.8).
	TaskManager.cancel_source_tasks(zone_id)
	TaskManager.unregister_work_source(zone_id)
	var removed_blocks: Array[Vector3i] = []
	for block: Vector3i in zone.get("blocks", []):
		if _zone_by_block.get(block, -1) == zone_id:
			_zone_by_block.erase(block)
			removed_blocks.append(block)
	_zones.erase(zone_id)
	_free_zone_overlay(zone_id)
	# zone["blocks"] holds only REMAINING blocks — already-mined ones left the
	# list at execution time, so mined cuts are never un-cut here.
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
		var component: MiningZoneComponent = zone.get("component")
		if kept.is_empty():
			TaskManager.cancel_source_tasks(zone_id)
			TaskManager.unregister_work_source(zone_id)
			_zones.erase(zone_id)
		else:
			zone["blocks"] = kept
			if component != null:
				component.subtract_blocks(removed_blocks)
			_zones[zone_id] = zone
	if affected.has(_selected_zone_id) and not _zones.has(_selected_zone_id):
		_close_zone_window()
	for zone_id: int in affected.keys():
		_rebuild_zone_overlay(zone_id)   # frees the overlay if the zone was erased
	_remove_visual_cut_blocks(removed_blocks)
	if _state != ToolState.INACTIVE:
		_rebuild_terrain_grid(true)   # restored blocks change effective grid tops (Phase 2b)


func save_section_key() -> String:
	return "mining"


func save_restore_priority() -> int:
	return 10


func serialize_state() -> Dictionary:
	var mined: Array = []
	var mined_keys: Array = _mined_blocks.keys()
	mined_keys.sort_custom(_sort_v3i)
	for value in mined_keys:
		mined.append(SaveManager.pack_v3i(value as Vector3i))
	var saved_zones: Array = []
	var ids: Array = _zones.keys()
	ids.sort()
	for value in ids:
		var zone_id := int(value)
		var zone: Dictionary = _zones[zone_id]
		var blocks: Array = []
		for block: Vector3i in zone.get("blocks", []):
			blocks.append(SaveManager.pack_v3i(block))
		saved_zones.append({ "id": zone_id, "blocks": blocks })
	return { "mined_blocks": mined, "zones": saved_zones }


func restore_state(state: Dictionary) -> void:
	for packed in state.get("mined_blocks", []):
		var block := SaveManager.unpack_v3i(packed)
		if _in_bounds(block) and block.y > BEDROCK_MAX_Y and not _mined_blocks.has(block):
			_mine_block_world(block)
	for raw in state.get("zones", []):
		if not (raw is Dictionary):
			continue
		var entry := raw as Dictionary
		var blocks: Array[Vector3i] = []
		for packed in entry.get("blocks", []):
			var block := SaveManager.unpack_v3i(packed)
			if _in_bounds(block) and not _mined_blocks.has(block) and not _zone_by_block.has(block):
				blocks.append(block)
		if not blocks.is_empty():
			_create_zone(blocks, int(entry.get("id", -1)))


func _sort_v3i(a: Vector3i, b: Vector3i) -> bool:
	if a.x != b.x:
		return a.x < b.x
	if a.y != b.y:
		return a.y < b.y
	return a.z < b.z


func _in_bounds(pos: Vector3i) -> bool:
	return pos.x >= 0 and pos.x < WORLD_SIZE_X \
		and pos.y >= 0 and pos.y < WORLD_SIZE_Y \
		and pos.z >= 0 and pos.z < WORLD_SIZE_Z
