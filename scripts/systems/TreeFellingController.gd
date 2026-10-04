extends Node3D

## Chop > Chop Trees: single clicks or a ground rectangle. Jobs/state belong to flora,
## and both this tool and the explorer use the same designate/cancel API.
@export var dock_ui_path: NodePath
@export var flora_path: NodePath
@export var explorer_path: NodePath

const Picking = preload("res://scripts/components/ObjectPicking.gd")
const SelectionOverlay = preload("res://scripts/ui/TreeFellingOverlay.gd")
const DRAG_THRESHOLD_PX := 6.0
signal tool_active_changed(active: bool)
var _active := false
var _flora: SurfaceFloraSpawner
var _explorer: ObjectExplorerController
var _hint_layer: CanvasLayer
var _hover: MeshInstance3D
var _hover_bounds := AABB()
var _hover_elapsed := 0.0
var _hint: Label
var _selection: Control
var _dragging := false
var _box_select := false
var _drag_start := Vector2.ZERO
var _drag_screen := Vector2.ZERO
var _anchor := Vector3i(-1, -1, -1)
var _selection_rect := Rect2i()
var _preview_trees: Array[Vector2i] = []
const HINT := "Chop trees · Click a tree or drag an area · Esc to finish"


func _ready() -> void:
	process_priority = 100 # Project UI after the camera has moved this frame.
	_flora = get_node_or_null(flora_path) as SurfaceFloraSpawner
	_explorer = get_node_or_null(explorer_path) as ObjectExplorerController
	var dock := get_node_or_null(dock_ui_path)
	if dock != null:
		dock.call("register_chop_controller", self)
		dock.connect("tool_requested", _on_tool_requested)
	_hover = MeshInstance3D.new()
	_hover.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hover.visible = false
	add_child(_hover)
	_hint_layer = CanvasLayer.new()
	_hint_layer.layer = 24
	_hint_layer.visible = false
	add_child(_hint_layer)
	_selection = SelectionOverlay.new()
	_selection.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_layer.add_child(_selection)
	_hint = Label.new()
	_hint.text = HINT
	_hint.position = Vector2(24, 100)
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
	_hint.add_theme_stylebox_override("normal", UITheme.hud_panel_style())
	_hint_layer.add_child(_hint)


func is_active() -> bool:
	return _active


func _on_tool_requested(tool_id: String) -> void:
	if tool_id == "chop" and bool(WorldGenerator.get_streaming_stats().get("maps_ready", false)):
		_active = true
		_hint_layer.visible = true
		tool_active_changed.emit(true)
	else:
		deactivate()


func deactivate() -> void:
	if not _active:
		return
	_active = false
	_cancel_drag()
	_hint_layer.visible = false
	_hover.visible = false
	tool_active_changed.emit(false)


func _unhandled_input(event: InputEvent) -> void:
	if not _active:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		deactivate()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_begin_drag(event.position)
		get_viewport().set_input_as_handled()


## Capture only an already-started world gesture. Releasing over UI cancels it,
## so a window cannot swallow mouse-up and leave a stuck selection behind.
func _input(event: InputEvent) -> void:
	if not _dragging:
		return
	if event is InputEventMouseMotion:
		_drag_screen = event.position
		if not _box_select and _drag_start.distance_to(_drag_screen) >= DRAG_THRESHOLD_PX:
			_box_select = true
			_explorer.clear_selection()
			_update_drag_preview()
		# Later motion is sampled by _process, not once per high-rate mouse event.
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		if get_viewport().gui_get_hovered_control() == null:
			_finish_drag(event.position)
		else:
			_cancel_drag()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		deactivate()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT and _dragging:
		_cancel_drag()


func _begin_drag(screen_pos: Vector2) -> void:
	_dragging = true
	_box_select = false
	_drag_start = screen_pos
	_drag_screen = screen_pos
	_anchor = Vector3i(-1, -1, -1)
	var camera := get_viewport().get_camera_3d()
	if camera != null and _flora != null:
		var hit := Picking.terrain_hit(camera.project_ray_origin(screen_pos),
			camera.project_ray_normal(screen_pos), _flora.get_slice_y())
		if not hit.is_empty():
			_anchor = Vector3i(hit.x, hit.y, hit.z)


func _cancel_drag() -> void:
	_dragging = false
	_box_select = false
	_preview_trees.clear()
	_selection.set_polygon(PackedVector2Array())
	_hint.text = HINT


func _finish_drag(screen_pos: Vector2) -> void:
	_drag_screen = screen_pos
	_box_select = _box_select or _drag_start.distance_to(screen_pos) >= DRAG_THRESHOLD_PX
	if _box_select:
		_update_drag_preview()
		for id: Vector2i in _preview_trees:
			_flora.designate_felling(id)
	else:
		designate_at_screen(screen_pos)
	_cancel_drag()


func _update_drag_preview(refresh_trees: bool = true) -> void:
	_selection.set_polygon(PackedVector2Array())
	if not _box_select or _anchor.y < 0:
		_preview_trees.clear()
		return
	_hover.visible = false
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		_preview_trees.clear()
		return
	# A fixed ground plane prevents tall canopies or cliffs from jumping the end
	# point. The rectangle includes visible trees at any terrain height inside it.
	var plane := Plane(Vector3.UP, float(_anchor.y) + 1.02)
	var hit: Variant = plane.intersects_ray(camera.project_ray_origin(_drag_screen), camera.project_ray_normal(_drag_screen))
	if hit == null:
		_preview_trees.clear()
		return
	var current := Vector2i(clampi(floori(hit.x), 0, WorldData.WORLD_SIZE_X - 1),
		clampi(floori(hit.z), 0, WorldData.WORLD_SIZE_Z - 1))
	var start := Vector2i(_anchor.x, _anchor.z)
	_selection_rect = Rect2i(start.min(current), (start - current).abs() + Vector2i.ONE)
	var corners := PackedVector2Array()
	var lo := _selection_rect.position
	var hi := _selection_rect.end
	for corner in [Vector2i(lo.x, lo.y), Vector2i(hi.x, lo.y), Vector2i(hi.x, hi.y), Vector2i(lo.x, hi.y)]:
		var point := Vector3(corner.x, plane.d, corner.y)
		if camera.is_position_behind(point):
			_preview_trees.clear() # Never commit a rectangle that could not be shown.
			return
		corners.append(camera.unproject_position(point))
	# Reprojection is cheap and runs every frame. Scan the forest only on the
	# count timer or at input/commit boundaries, even during rapid camera pans.
	if refresh_trees:
		_preview_trees = _flora.trees_in_felling_rect(_selection_rect)
	_selection.set_polygon(corners)
	_hint.text = "Chop trees · %d trees in area · Release to mark · Esc to cancel" % _preview_trees.size()


func designate_at_screen(screen_pos: Vector2) -> bool:
	if _flora == null or _explorer == null:
		return false
	var hit := _explorer.pick_at_screen(screen_pos)
	if hit.is_empty() or hit["provider"] != _flora:
		return false
	if not _flora.designate_felling(hit["id"]):
		return false
	_explorer.select_object(_flora, hit["id"])
	return true


func _process(delta: float) -> void:
	if not _active or _explorer == null:
		return
	_hover_elapsed += delta
	if _dragging and _box_select:
		var refresh_trees := _hover_elapsed >= .08
		_update_drag_preview(refresh_trees)
		if refresh_trees:
			_hover_elapsed = 0.0
		return
	if _hover_elapsed < .08:
		return
	_hover_elapsed = 0.0
	var mouse := get_viewport().get_mouse_position()
	if not get_viewport().get_visible_rect().has_point(mouse) or get_viewport().gui_get_hovered_control() != null:
		_hover.visible = false
		return
	var hit := _explorer.pick_at_screen(mouse)
	if hit.is_empty() or hit["provider"] != _flora:
		_hover.visible = false
		return
	var bounds := _flora.get_explorer_bounds(hit["id"])
	_hover.visible = bounds.size != Vector3.ZERO
	if _hover.visible and bounds != _hover_bounds:
		_hover_bounds = bounds
		_hover.mesh = Picking.outline_mesh(bounds.grow(.12), Color(1.0, .85, .40))
