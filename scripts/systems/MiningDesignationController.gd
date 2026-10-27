class_name MiningDesignationController
extends Node3D

@export var camera_path: NodePath
@export var dock_ui_path: NodePath
@export var renderer_path: NodePath
@export var window_manager_path: NodePath

const CONFIG_PATH := "res://data/terrain/mining_config.json"
const WORLD_SIZE_X := WorldData.WORLD_SIZE_X
const WORLD_SIZE_Y := WorldData.WORLD_SIZE_Y
const WORLD_SIZE_Z := WorldData.WORLD_SIZE_Z
const BEDROCK_MAX_Y := 3
const Picking = preload("res://scripts/components/ObjectPicking.gd")
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
const FALLBACK_MAX_DRAG_LENGTH := 32
const FALLBACK_ZONE_MAX_WORKERS := 4
const FALLBACK_SWING_BASE_TIME := 2.0

enum ToolState { INACTIVE, HOVER, DRAGGING }

## Fired on every activate/deactivate — DockUI refreshes button pressed-state
## from it, so the ⛏️ button lights while the tool is active and clears on Esc
## (previously the mine target had no dock state at all).
signal tool_active_changed(active: bool)
signal order_created(receipt: Dictionary)
var _shared_order_ui := false
var _mining_guide_enabled := false
var _guide_spacing := 32
var _guide_width := 0.16
var _guide_color := Color("edbd71b8")
## The dotted lines splitting each guide square (0: none).
var _dotted_spacing := 16
var _dotted_width := 0.1
var _dotted_color := Color("edbd7194")
var _dot_length := 0.4
var _pointer_screen := Vector2.INF

var _state: ToolState = ToolState.INACTIVE
var _camera_rig: Camera
var _dock_ui: DockUI
var _renderer: Node

var _horizontal_size: int = FALLBACK_DEFAULT_SIZE
var _vertical_size: int = FALLBACK_DEFAULT_SIZE
var _max_horizontal: int = FALLBACK_MAX_HORIZONTAL
var _max_vertical: int = FALLBACK_MAX_VERTICAL
var _max_drag_length: int = FALLBACK_MAX_DRAG_LENGTH
var _reach_up: int = 5
var _reach_down: int = 1

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

## Helpers (doc 258 step 8): overlay geometry, zone work (leases, execution,
## DEV mine) and the zone window. No class_name — preloaded here only.
const Overlay = preload("res://scripts/components/MiningZoneOverlay.gd")
const Work = preload("res://scripts/components/MiningZoneWork.gd")
const ZoneWindow = preload("res://scripts/components/MiningZoneWindow.gd")
var _overlay: Overlay
var _work := Work.new(self, _zones, _zone_by_block, FALLBACK_ZONE_MAX_WORKERS, FALLBACK_SWING_BASE_TIME)
var _zone_ui: ZoneWindow
var _window_manager: UIWindowManager
var _last_grid_center := Vector2i(-999999, -999999)
var _last_grid_slice := -999999
var _last_grid_radius := -1


func _ready() -> void:
	WorldData.block_changed.connect(func(_cell: Vector3i,_old: int,_new_id: int): _grid_dirty = true)

	add_to_group(SaveManager.OWNER_GROUP)
	_load_config()
	_camera_rig = get_node_or_null(camera_path) as Camera
	_dock_ui = get_node_or_null(dock_ui_path) as DockUI
	_renderer = get_node_or_null(renderer_path)
	_window_manager = get_node_or_null(window_manager_path) as UIWindowManager
	_overlay = Overlay.new(self)
	_zone_ui = ZoneWindow.new(self, _window_manager)
	_zone_ui.remove_pressed.connect(_remove_selected_zone)
	_zone_ui.dev_mine_pressed.connect(_dev_mine_selected_zone)
	_zone_ui.closed.connect(func() -> void: _set_selected_zone(-1))

	if _dock_ui != null and _dock_ui.has_signal("tool_requested"):
		_dock_ui.tool_requested.connect(_on_tool_requested)
	if _dock_ui != null and _dock_ui.has_method("register_mining_controller"):
		_dock_ui.call("register_mining_controller", self)

	# VisibleVolume contract (doc 11 Phase 3): all overlay rebuilds triggered by
	# visibility changes go through this one signal — never per-consumer polling.
	if _renderer != null and _renderer.has_signal("visible_volume_changed"):
		_renderer.connect("visible_volume_changed", _on_visible_volume_changed)

	# Work-source routing (doc 16 step 5): zones are work sources; TaskManager
	# signals route reservation releases and lease accounting back to the
	# owning MiningZoneComponent. The controller is the single router.
	TaskManager.task_released.connect(_work.on_task_released)
	TaskManager.task_completed.connect(_work.on_task_completed)
	TaskManager.task_failed.connect(_work.on_task_failed)
	TaskManager.task_cancelled.connect(_work.on_task_cancelled)
	# Zero-lease zone revival: terrain changes near a stalled zone re-arm it
	# (mirrors TaskManager's chunk-dirtied early re-arm for blocked tasks).
	WorldData.chunk_dirtied.connect(_work.on_world_chunk_dirtied, CONNECT_DEFERRED)
	PlacedEntityRegistry.occupancy_changed.connect(_work.on_occupancy_changed)
	# Resolve hidden-air plans after the current mining commit completes.
	InteriorTracker.caves_discovered.connect(_remove_blocks_from_zones, CONNECT_DEFERRED)


## One reactive rebuild per visibility change (the renderer emits at most once
## per frame). Zones re-clip even while the tool is inactive — confirmed zones
## are always on screen; grid and preview only exist while the tool is active.
## The overlay's per-zone skip rule (MiningZoneOverlay.needs_reclip) keeps a
## slice step O(1) for zones whose clip state cannot change.
func _on_visible_volume_changed() -> void:
	var slice_y := _current_slice_y()
	for zone_id: int in _zones.keys():
		if _overlay.needs_reclip(zone_id, slice_y):
			refresh_zone_overlay(zone_id)
	if _state != ToolState.INACTIVE:
		_rebuild_terrain_grid(true)
		_update_hover_preview(true)


func _process(delta: float) -> void:
	# Keep the zone window's worker/blocked line live while it is open —
	# independent of tool state (the window outlives tool deactivation).
	if _zone_ui != null and _zone_ui.is_showing() and _selected_zone_id >= 0:
		if _zone_ui.refresh_due(delta) and _zones.has(_selected_zone_id):
			refresh_zone_window(_selected_zone_id)
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
				if try_select_zone_at_screen(mouse.position):
					get_viewport().set_input_as_handled()
			return

		if mouse.pressed and mouse.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			if _handle_resize_wheel(mouse.button_index):
				_update_hover_preview(true)
				get_viewport().set_input_as_handled()
			return

		if mouse.button_index == MOUSE_BUTTON_LEFT:
			if mouse.pressed:
				_update_hover_preview(true)
				if try_select_zone_at_screen(mouse.position) and not Input.is_key_pressed(KEY_CTRL):
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


## An already-started gesture owns its release, even when it ends over UI.
func _input(event: InputEvent) -> void:
	if event is InputEventMouse: _pointer_screen = event.position
	if _state != ToolState.DRAGGING: return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		if get_viewport().gui_get_hovered_control() == null:
			_update_hover_preview(true)
			_confirm_preview()
		_anchor_hit.clear()
		_state = ToolState.HOVER
		_update_hover_preview(true)
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT and _state == ToolState.DRAGGING:
		_anchor_hit.clear()
		_state = ToolState.HOVER


func _on_tool_requested(tool_id: String) -> void:
	if tool_id != "mine_precision":
		# Another click-tool is activating — close this one (the doc 16 tool-
		# exclusion wart, fixed 2026-07-06 after two active tools ate one click).
		if _state != ToolState.INACTIVE:
			_deactivate_tool()
		return
	# TOGGLE, matching every other click-tool: a second press of the dock
	# button turns the tool off. (Previously the only exit was Esc, and the
	# button re-activated a tool that was already active.)
	if _state != ToolState.INACTIVE:
		_deactivate_tool()
		return
	_state = ToolState.HOVER
	_overlay.show_preview_lines()
	if _zone_ui != null:
		_zone_ui.hint_window.visible = not _shared_order_ui
	_rebuild_terrain_grid(true)
	# Only Shift/Alt wheel belong to the brush; plain wheel stays with the camera.
	tool_active_changed.emit(true)
	print("MiningDesignationController: precision mining active.")


func is_active() -> bool:
	return _state != ToolState.INACTIVE


func is_mining_guide_enabled() -> bool:
	return _mining_guide_enabled


func set_mining_guide_enabled(enabled: bool) -> void:
	if _mining_guide_enabled == enabled: return
	_mining_guide_enabled = enabled
	_rebuild_terrain_grid(true)


func _deactivate_tool() -> void:
	_state = ToolState.INACTIVE
	_anchor_hit.clear()
	_hover_hit.clear()
	_preview_raw_blocks.clear()
	_preview_blocks.clear()
	_overlay.hide_preview()
	if _zone_ui != null:
		_zone_ui.hint_window.visible = false
	_last_grid_center = Vector2i(-999999, -999999)
	_last_grid_slice = -999999
	_last_grid_radius = -1
	tool_active_changed.emit(false)


func _load_config() -> void:
	var parsed: Variant = preload("res://scripts/registries/JsonData.gd").read(CONFIG_PATH)
	if parsed == null: return # reported; the fallback sizes stay
	var root: Dictionary = parsed
	var precision: Dictionary = root.get("precision_tool", {})
	var dig_tool: Dictionary = root.get("dig_tool", {})
	_horizontal_size = int(precision.get("default_size", FALLBACK_DEFAULT_SIZE))
	_vertical_size = int(precision.get("default_size", FALLBACK_DEFAULT_SIZE))
	_max_horizontal = int(precision.get("max_horizontal", FALLBACK_MAX_HORIZONTAL))
	_max_vertical = int(precision.get("max_vertical", FALLBACK_MAX_VERTICAL))
	var guide: Dictionary = root.get("area_guide", {})
	_guide_spacing = maxi(1,int(guide.get("cell_size",32)))
	_guide_width = clampf(float(guide.get("line_width",.16)),.02,.5)
	_guide_color = Color(String(guide.get("color","edbd71b8")))
	# A dotted spacing that does not split the squares evenly draws no dotted lines.
	_dotted_spacing = int(guide.get("dotted_cell_size",16))
	if _dotted_spacing<=0 or _dotted_spacing>=_guide_spacing or _guide_spacing%_dotted_spacing!=0: _dotted_spacing = 0
	_dotted_width = clampf(float(guide.get("dotted_line_width",.1)),.02,.5)
	_dotted_color = Color(String(guide.get("dotted_color","edbd7194")))
	_dot_length = clampf(float(guide.get("dot_length",.4)),.1,1.)
	_max_drag_length = maxi(1, int(dig_tool.get("max_drag_length", FALLBACK_MAX_DRAG_LENGTH)))
	var zone_cfg: Dictionary = root.get("zone", {})
	_work.max_workers = int(zone_cfg.get("max_workers", FALLBACK_ZONE_MAX_WORKERS))
	var exec_cfg: Dictionary = root.get("execution", {})
	_work.swing_base_time = float(exec_cfg.get("swing_base_time_s", FALLBACK_SWING_BASE_TIME))
	_reach_up = int(exec_cfg.get("reach_up_blocks", _reach_up))
	_reach_down = int(exec_cfg.get("reach_down_blocks", _reach_down))


func _rebuild_terrain_grid(force: bool = false) -> void:
	_overlay.grid_node.visible = is_active() and _mining_guide_enabled
	if not _overlay.grid_node.visible:
		_overlay.grid_node.mesh = null
		return
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
	_overlay.grid_node.mesh = _area_guide_mesh(
		clampi(center.x - radius, 0, WORLD_SIZE_X - 1), clampi(center.x + radius, 0, WORLD_SIZE_X - 1),
		clampi(center.y - radius, 0, WORLD_SIZE_Z - 1), clampi(center.y + radius, 0, WORLD_SIZE_Z - 1), slice_y)


## The guide over columns x0..x1, z0..z1: solid lines on the multiples of the cell
## size, dotted lines on the other multiples of the dotted size. Null when nothing
## there is visible.
func _area_guide_mesh(x0: int, x1: int, z0: int, z1: int, slice_y: int) -> ArrayMesh:
	var verts: PackedVector3Array = []
	var cols: PackedColorArray = []
	# Only visit columns touching a world-aligned area boundary. There are no
	# per-voxel outlines, and panning never shifts the guide's origin.
	var step := _dotted_spacing if _dotted_spacing>0 else _guide_spacing
	for x in range(ceili(float(x0)/step)*step,x1+2,step):
		_append_area_line(x,true,z0,z1,slice_y,x%_guide_spacing!=0,verts,cols)
	for z in range(ceili(float(z0)/step)*step,z1+2,step):
		_append_area_line(z,false,x0,x1,slice_y,z%_guide_spacing!=0,verts,cols)
	if verts.is_empty():
		return null
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = cols
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _terrain_grid_radius() -> int:
	var radius := TERRAIN_GRID_MIN_RADIUS
	if _camera_rig != null and _camera_rig.spring_arm != null:
		radius = clampi(ceili(_camera_rig.spring_arm.spring_length * .9),TERRAIN_GRID_MIN_RADIUS,TERRAIN_GRID_MAX_RADIUS)
	# Wider displays reveal more terrain. Sparse area lines can cover that
	# extra width without restoring the old per-voxel mesh cost.
	var viewport := get_viewport().get_visible_rect().size
	var aspect_scale := maxf(1.0,(viewport.x/maxf(1.0,viewport.y))/(16.0/9.0))
	return mini(WORLD_SIZE_X,ceili(radius*aspect_scale))


## Effective visible top for the mining grid (doc 11 Phase 2b): the natural
## surface clamped to the slice plane, then stepped down past designated and
## removed blocks — WorldData.visible_top_y, the rule the overview also uses.
## Returns -1 when no visible block remains in the column.
func _effective_grid_top(x: int, z: int, slice_y: int) -> int:
	return WorldData.visible_top_y(x, z, int(WorldGenerator.get_visible_surface_y(x, z)), slice_y, _zone_by_block, true)


## One boundary line over columns from..to along it, each column's top read once.
## Thick surface ribbons, or a dotted line's dash centred on each block, split at
## the boundary so unequal neighboring tops each receive their own half.
## Perpendicular cliffs get one continuous stripe (a dotted line: a dash per block
## of height), never a box around every block. Depth testing keeps buried guides
## hidden.
func _append_area_line(across: int, along_z: bool, from: int, to: int, slice_y: int, dotted: bool,
		verts: PackedVector3Array, cols: PackedColorArray) -> void:
	var width := _dotted_width if dotted else _guide_width
	var color := _dotted_color if dotted else _guide_color
	var inset := (1.0-_dot_length)*.5 if dotted else 0.0
	var length := WORLD_SIZE_Z if along_z else WORLD_SIZE_X
	for side: int in [-1,0]:
		var row := across+side
		if row<0 or row>=(WORLD_SIZE_X if along_z else WORLD_SIZE_Z): continue
		var a := across-width*.5 if side<0 else float(across)
		var b := float(across) if side<0 else across+width*.5
		var top := _line_top(row,from,along_z,slice_y)
		for along: int in range(from,to+1):
			var next_top := _line_top(row,along+1,along_z,slice_y) if along+1<length else -1
			if top>=0:
				var y := float(top+1)+TERRAIN_GRID_OFFSET
				_append_guide_quad(_guide_point(a,y,along+inset,along_z),_guide_point(b,y,along+inset,along_z),
					_guide_point(b,y,along+1-inset,along_z),_guide_point(a,y,along+1-inset,along_z),color,verts,cols)
				if next_top>=0 and next_top!=top:
					var face := along+1+TERRAIN_GRID_OFFSET*(1.0 if top>next_top else -1.0)
					var low := mini(top,next_top)+1
					var high := maxi(top,next_top)+1
					var rise := 1 if dotted else high-low
					for h: int in range(low,high,rise):
						_append_guide_quad(_guide_point(a,h+inset,face,along_z),_guide_point(b,h+inset,face,along_z),
							_guide_point(b,h+rise-inset,face,along_z),_guide_point(a,h+rise-inset,face,along_z),color,verts,cols)
			top = next_top


func _line_top(row: int, along: int, along_z: bool, slice_y: int) -> int:
	return _effective_grid_top(row,along,slice_y) if along_z else _effective_grid_top(along,row,slice_y)


func _guide_point(across: float, height: float, along: float, along_z: bool) -> Vector3:
	return Vector3(across,height,along) if along_z else Vector3(along,height,across)


func _append_guide_quad(a: Vector3,b: Vector3,c: Vector3,d: Vector3,color: Color,
		verts: PackedVector3Array,cols: PackedColorArray) -> void:
	verts.append_array([a,b,c,a,c,d])
	for i in range(6): cols.append(color)


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
		_overlay.clear_preview()
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
	_overlay.rebuild_preview(_preview_raw_blocks, _preview_is_remove, _visible_in_slice)
	_overlay.update_size_labels(_preview_raw_blocks)


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

	var zone_id := _create_zone(blocks)
	order_created.emit({"zone_id": zone_id, "source": _zones[zone_id].component,
		"message": "%d blocks marked for mining" % blocks.size()})


func set_shared_order_ui(enabled: bool) -> void:
	_shared_order_ui = enabled
	if _zone_ui != null: _zone_ui.hint_window.visible = is_active() and not enabled


## What the tool bar shows (doc 23, "The tool bar"): the brush's width and depth as
## steppers, the area guide's switch, and the blocks a held drag would mark or unmark.
func tool_bar_state() -> Dictionary:
	var state := {"tool": "mine_precision",
		"settings": [{"id": "width", "label": "Width", "value": _horizontal_size, "min": 1, "max": _max_horizontal,
			"keys": "Shift + Wheel", "tooltip": "How many blocks wide the brush marks."},
			{"id": "depth", "label": "Depth", "value": _vertical_size, "min": 1, "max": _max_vertical,
			"keys": "Alt + Wheel", "tooltip": "How many blocks deep the brush marks, from the face you drag on."}],
		"toggle": {"id": "guide", "label": "%d × %d guide" % [_guide_spacing, _guide_spacing], "on": _mining_guide_enabled,
			"tooltip": "Thicker lines every %d blocks%s while mining. A guide only: mining still marks single blocks." % [_guide_spacing,
				" and dotted lines every %d" % _dotted_spacing if _dotted_spacing > 0 else ""]}}
	if _state == ToolState.DRAGGING:
		state.selection = {"count": "%d block%s" % [_preview_blocks.size(), "" if _preview_blocks.size() == 1 else "s"],
			"detail": "to unmark" if Input.is_key_pressed(KEY_CTRL) else "to mine", "at": _pointer_screen}
	return state


func set_tool_setting(id: String, value: Variant) -> void:
	match id:
		"width": _horizontal_size = clampi(int(value), 1, _max_horizontal)
		"depth": _vertical_size = clampi(int(value), 1, _max_vertical)
		"guide": set_mining_guide_enabled(bool(value))
	_update_hover_preview(true)


## The tool bar's Done, as Esc.
func deactivate() -> void:
	if _state != ToolState.INACTIVE: _deactivate_tool()


func order_is_pending(receipt: Dictionary) -> bool:
	return _zones.get(receipt.zone_id, {}).get("component") == receipt.source


func undo_order(receipt: Dictionary) -> int:
	if not order_is_pending(receipt): return 0
	var count: int = _zones[receipt.zone_id].blocks.size()
	_remove_zone(receipt.zone_id)
	if _selected_zone_id == receipt.zone_id: close_zone_window()
	return count


func inspect_order(receipt: Dictionary) -> void:
	if order_is_pending(receipt): _open_zone_window(receipt.zone_id)


## Cancellation selects the same slice-visible marks the player can see.
func marked_blocks_in_screen_rect(rect: Rect2, camera: Camera3D) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	for block: Vector3i in _zone_by_block:
		var centre := Vector3(block) + Vector3.ONE * .5
		if _visible_in_slice(block) and not camera.is_position_behind(centre) and rect.has_point(camera.unproject_position(centre)):
			result.append(block)
	return result


func marked_block_at_screen(screen_pos: Vector2) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	var hit := _raycast_voxel(screen_pos)
	if not hit.is_empty() and _zone_by_block.has(hit.block_pos): result.append(hit.block_pos)
	return result


func cancel_order_blocks(blocks: Array[Vector3i]) -> int:
	var count := 0
	for block in blocks:
		if _zone_by_block.has(block): count += 1
	_remove_blocks_from_zones(blocks)
	return count


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
	refresh_zone_overlay(zone_id)
	Overlay.add_visual_cuts(_renderer, blocks, _zones)
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
		var block_id := _designation_block_id_at(block)
		if not BlockRegistry.is_solid(block_id):
			continue
		var def := BlockRegistry.get_def(BlockRegistry.get_key(block_id))
		if int(def.get("hardness",1))<0: continue
		if String(def.get("kind", "")) == "water":
			continue
		result.append(block)
	return result


func _block_id_at(pos: Vector3i) -> int:
	return Work.block_id_at(pos)


func _designation_block_id_at(pos: Vector3i) -> int:
	return Work.designation_block_id_at(pos)


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
	# Hard cap: the most whole brush steps that fit in max_drag_length blocks.
	# A longer drag stops growing at the cap; the anchor side stays put.
	if extent > _max_drag_length:
		extent = maxi(size_horizontal, _max_drag_length - _max_drag_length % size_horizontal)

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
	var mouse_pos := get_viewport().get_mouse_position() if _pointer_screen == Vector2.INF else _pointer_screen
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
	var mouse_pos := get_viewport().get_mouse_position() if _pointer_screen == Vector2.INF else _pointer_screen
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
	# Mined blocks are air: the ray passes through so the freshly exposed blocks
	# behind/beneath them can be designated (iterative digs).
	var hit := Picking.terrain_hit(camera.project_ray_origin(screen_pos),
		camera.project_ray_normal(screen_pos).normalized(), WorldData.MAX_Y, camera.far,
		_pickable_block_id, func(pos: Vector3i, _normal: Vector3i) -> bool: return _visible_in_slice(pos))
	if hit.is_empty():
		return {}
	var block := Vector3i(hit.x, hit.y, hit.z)
	return {"hit": true, "block_pos": block, "face_normal": hit.normal, "block_id": _pickable_block_id(block)}


## The concealed block a designation ray stops on, or air (water never stops it).
func _pickable_block_id(pos: Vector3i) -> int:
	var block_id := _designation_block_id_at(pos)
	if not BlockRegistry.is_solid(block_id) or String(BlockRegistry.get_def(BlockRegistry.get_key(block_id)).get("kind", "")) == "water":
		return BlockRegistry.AIR_ID
	return block_id


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


## Rebuilds ONE zone's overlay geometry (MiningZoneOverlay.rebuild_zone); an
## erased or emptied zone frees its overlay. Public for the zone-work helper.
func refresh_zone_overlay(zone_id: int) -> void:
	var zone: Dictionary = _zones.get(zone_id, {})
	_overlay.rebuild_zone(zone_id, zone.get("blocks", []), zone_id == _selected_zone_id,
		_current_slice_y(), _visible_in_slice)


## Shared with ConstructionController's plan and preview meshes.
func build_fill_mesh(blocks: Array[Vector3i], color: Color, outset: float) -> ArrayMesh:
	return Overlay.build_fill_mesh(blocks, color, outset)


## Selection recolor: only the previously and newly selected zones rebake.
func _set_selected_zone(zone_id: int) -> void:
	if _selected_zone_id == zone_id:
		return
	var previous := _selected_zone_id
	_selected_zone_id = zone_id
	if previous >= 0 and _zones.has(previous):
		refresh_zone_overlay(previous)
	if zone_id >= 0 and _zones.has(zone_id):
		refresh_zone_overlay(zone_id)


func try_select_zone_at_screen(screen_pos: Vector2) -> bool:
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
	if _zone_ui == null or _zone_ui.zone_window == null or not _zones.has(zone_id):
		return
	_set_selected_zone(zone_id)
	_zone_ui.update_text(_zones[zone_id])
	_zone_ui.open()


func close_zone_window() -> void:
	_set_selected_zone(-1)
	if _zone_ui != null:
		_zone_ui.close()


func refresh_zone_window(zone_id: int) -> void:
	if _selected_zone_id != zone_id or _zone_ui == null or not _zone_ui.is_showing():
		return
	# Live worker counts must not raise this window over the player's active one.
	_zone_ui.update_text(_zones[zone_id])


func _remove_selected_zone() -> void:
	if _selected_zone_id < 0:
		return
	_remove_zone(_selected_zone_id)
	close_zone_window()


func _dev_mine_selected_zone() -> void:
	if _selected_zone_id < 0:
		return
	_work.dev_mine_zone(_selected_zone_id)
	close_zone_window()


# ── Zone work source (MiningZoneWork) ─────────────────────────────────────────

## Called by MiningZoneComponent.get_block_work.
func get_zone_block_work(block: Vector3i) -> Dictionary:
	return _work.get_block_work(block)


func play_zone_mining_impact(block: Vector3i, impact_position: Vector3, normal: Vector3) -> void:
	_work.play_impact(block, impact_position, normal)


## Called by MiningZoneComponent.commit_mined; see MiningZoneWork.execute_block_mined.
func execute_zone_block_mined(zone_id: int, block: Vector3i, dwarf_id: int) -> bool:
	return _work.execute_block_mined(zone_id, block, dwarf_id)


func ensure_chunk_real(block: Vector3i) -> void:
	Work.ensure_chunk_real(block)


func _mine_block_world(block: Vector3i) -> void:
	_work.mine_block_world(block)


func _mine_blocks_world(blocks: Array[Vector3i]) -> void:
	_work.mine_blocks_world(blocks)


func _top_up_zone_leases(zone_id: int) -> void:
	_work.top_up_leases(zone_id)


# ── Hooks for the helpers (public so they never reach into private state) ────

func get_renderer() -> Node:
	return _renderer


func get_selected_zone_id() -> int:
	return _selected_zone_id


func mark_grid_dirty() -> void:
	_grid_dirty = true


## Terrain changed under an active tool: redraw the area guide and preview.
func refresh_tool_view() -> void:
	if _state != ToolState.INACTIVE:
		_rebuild_terrain_grid(true)
		_update_hover_preview(true)


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
	refresh_zone_overlay(zone_id)   # frees the overlay of the erased zone
	# zone["blocks"] holds only REMAINING blocks — already-mined ones left the
	# list at execution time, so mined cuts are never un-cut here.
	Overlay.remove_visual_cuts(_renderer, removed_blocks, _zones)
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
		close_zone_window()
	for zone_id: int in affected.keys():
		refresh_zone_overlay(zone_id)   # frees the overlay if the zone was erased
	Overlay.remove_visual_cuts(_renderer, removed_blocks, _zones)
	if _state != ToolState.INACTIVE:
		_rebuild_terrain_grid(true)   # restored blocks change effective grid tops (Phase 2b)


func save_section_key() -> String:
	return "mining"


func save_restore_priority() -> int:
	return 10


func serialize_state() -> Dictionary:
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
	return { "zones": saved_zones }


func capture_save_state() -> Dictionary:
	var zones := {}
	for id in _zones: zones[id]=_zones[id].get("blocks",[]).duplicate()
	return {"zones":zones}


func restore_state(state: Dictionary) -> void:
	# Terrain (and with it the removed-terrain record) is restored once by
	# SaveManager before any scene owners.
	for raw in state.get("zones", []):
		if not (raw is Dictionary):
			continue
		var entry := raw as Dictionary
		var blocks: Array[Vector3i] = []
		for packed in entry.get("blocks", []):
			var block := SaveManager.unpack_v3i(packed)
			# Construction restores after mining removals and before simulation.
			# A saved mining order may target a rebuilt cell in that removal history.
			if _in_bounds(block) and not _zone_by_block.has(block):
				blocks.append(block)
		if not blocks.is_empty():
			_create_zone(blocks, int(entry.get("id", -1)))


func _in_bounds(pos: Vector3i) -> bool:
	return pos.x >= 0 and pos.x < WORLD_SIZE_X \
		and pos.y >= 0 and pos.y < WORLD_SIZE_Y \
		and pos.z >= 0 and pos.z < WORLD_SIZE_Z
