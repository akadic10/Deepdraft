class_name ObjectExplorerController
extends Node3D

## One context view for live world objects. Providers own their data/actions;
## this controller owns selection, occlusion, the outline and where it shows.
## Provider API: pick_explorer_object(start,end), get_explorer_data(id),
## get_explorer_bounds(id), optional perform_explorer_action(id,action).
## Optional on_explorer_selected(id) runs on explicit selection, never refresh.
## Every selection shows in the compact panel beside the dock (doc 260), except a
## dwarf while Colony Dwarves hosts it on its Details card. The one window is the
## selected dwarf's character sheet, opened from either; rooms, storage and DEV tools
## keep their own windows.
@export var window_manager_path: NodePath
@export var slice_controller_path: NodePath
## Tools that take world clicks while active; tools made at run time join the "click_tool"
## group instead.
@export var click_tool_paths: Array[NodePath] = []
@export var dwarf_director_path: NodePath
@export var terrain_provider_path: NodePath
@export var dock_ui_path: NodePath

const Picking = preload("res://scripts/components/ObjectPicking.gd")
const DwarfPanel = preload("res://scripts/ui/DwarfInspectorPanel.gd")
const CompactPanel = preload("res://scripts/ui/CompactObjectPanel.gd")
const COMPACT_LAYER := 20   # the dock's layer: windows the player opens sit above both
## The compact dwarf panel's big button; this controller opens the sheet itself.
const CHARACTER_SHEET := {"id": "character_sheet", "text": "Character sheet", "primary": true}
const WINDOW_ID := "character_sheet"
const RAY_MAX := 600.0
const REFRESH_SECONDS := 0.15
signal selection_changed

var _manager: UIWindowManager
var _window: UIWindow
var _provider: Node = null
var _object_id: Variant = null
var _slice_y := SliceController.MAX_SLICE_Y
var _refresh_elapsed := 0.0
var _tools: Array[Node] = []
var _dwarves: Node
var _terrain: Node
var _outline: MeshInstance3D
var _outline_bounds := AABB()
var _dwarf_panel: MarginContainer
var _inspector_positioned := false
var _outline_subject: Node3D
var _outline_offset := Vector3.ZERO
var _dwarf_host: Control
var _compact: Control
var _sheet_open := false   # the window shows the selected dwarf's character sheet


func _ready() -> void:
	add_to_group("object_explorer")
	_manager = get_node_or_null(window_manager_path) as UIWindowManager
	if _manager == null:
		push_error("ObjectExplorerController: a UIWindowManager is required.")
		set_process(false)
		set_process_unhandled_input(false)
		return
	for path: NodePath in click_tool_paths:
		var tool := get_node_or_null(path)
		if tool != null:
			_tools.append(tool)
	_dwarves = get_node_or_null(dwarf_director_path)
	_terrain = get_node_or_null(terrain_provider_path) if not terrain_provider_path.is_empty() else null
	var slice := get_node_or_null(slice_controller_path)
	if slice != null:
		slice.connect("slice_changed", _on_slice_changed)
	_build_window()
	_build_compact_panel()
	_inspector_positioned = _manager.has_saved_position(WINDOW_ID)
	_window.drag_ended.connect(func(_window_ref): _inspector_positioned = true)
	_manager.window_state_changed.connect(_on_window_state_changed)
	_outline = MeshInstance3D.new()
	_outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_outline)


func _unhandled_input(event: InputEvent) -> void:
	if _click_tool_active():
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		# Colony Dwarves owns its close action while it hosts the selected dwarf; a
		# character sheet open over it closes first.
		if is_instance_valid(_dwarf_host) and _object_id is DwarfAgent:
			if _sheet_open:
				_manager.close(WINDOW_ID)
				get_viewport().set_input_as_handled()
			return
		if _provider != null:
			clear_selection()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if select_at_screen(event.position):
			get_viewport().set_input_as_handled()
		else:
			clear_selection() # Let empty-ground clicks continue to zone inspectors.


func _click_tool_active() -> bool:
	if is_instance_valid(_terrain) and _terrain.developer_inspection_active(): return true
	for tool: Node in _tools:
		if tool.has_method("is_active") and bool(tool.call("is_active")):
			return true
	# Tools made at run time, such as Copy and placing blueprints, join this group instead.
	for tool: Node in get_tree().get_nodes_in_group("click_tool"):
		if bool(tool.call("is_active")):
			return true
	return is_instance_valid(_dwarves) and bool(_dwarves.call("is_walk_test_active"))


func select_at_screen(screen_pos: Vector2) -> bool:
	if _click_tool_active():
		return false
	var hit := pick_at_screen(screen_pos,true)
	if not hit.is_empty() and hit.provider == _terrain:
		# Existing work/storage zone inspectors take precedence over bare terrain.
		for tool: Node in _tools:
			if tool.has_method("try_select_zone_at_screen") and tool.call("try_select_zone_at_screen",screen_pos):
				clear_selection()
				return true
	return not hit.is_empty() and select_object(hit["provider"], hit["id"])


## Shared hit arbitration for ordinary selection and designation tools.
func pick_at_screen(screen_pos: Vector2, include_terrain: bool = false) -> Dictionary:
	if not bool(WorldGenerator.get_streaming_stats().get("maps_ready", false)):
		return {}
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return {}
	var start := camera.project_ray_origin(screen_pos)
	var direction := camera.project_ray_normal(screen_pos).normalized()
	var terrain: Dictionary = _terrain.terrain_hit(start,direction,_slice_y,RAY_MAX) \
		if include_terrain and is_instance_valid(_terrain) else Picking.terrain_hit(start,direction,_slice_y,RAY_MAX)
	var underground := get_tree().get_first_node_in_group("underground_view")
	if underground!=null and underground.is_inspecting():
		terrain = Picking.terrain_hit(start,direction,_slice_y,RAY_MAX,Callable(),underground.is_terrain_face_visible)
	var limit := minf(float(terrain.get("distance", RAY_MAX)) + .002, RAY_MAX)
	var end := start + direction * limit
	var nearest := limit
	var selected: Node = null
	var selected_id: Variant = null
	for provider in get_tree().get_nodes_in_group("object_explorer_provider"):
		var hit: Dictionary = provider.call("pick_explorer_object", start, end)
		if not hit.is_empty() and float(hit["distance"]) < nearest:
			nearest = float(hit["distance"])
			selected = provider
			selected_id = hit["id"]
	if selected == null:
		if include_terrain and is_instance_valid(_terrain) and not terrain.is_empty():
			return {"provider":_terrain,"id":terrain}
		return {}
	return {"provider": selected, "id": selected_id}


func select_object(provider: Node, object_id: Variant) -> bool:
	var data: Dictionary = provider.call("get_explorer_data", object_id)
	if data.is_empty():
		return false
	if _provider != provider or _object_id != object_id:
		_release_selection()
	# An open character sheet follows the selection from dwarf to dwarf only.
	if String(data.get("presentation", "")) != "dwarf": _sheet_open = false
	_provider = provider
	_object_id = object_id
	_refresh(data)
	# Explicit selection only: periodic inspector refreshes are observational.
	if provider.has_method("on_explorer_selected"):
		provider.call("on_explorer_selected", object_id)
	selection_changed.emit()
	return true


## The overview borrows presentation only; this controller still owns the
## selected actor, outline, slice guards and camera actions.
func set_dwarf_inspector_host(panel: Control) -> void:
	if panel == _dwarf_host: return
	if is_instance_valid(_dwarf_host):
		if _object_id is DwarfAgent: clear_selection()
		_dwarf_host.action_requested.disconnect(_perform_dwarf_action)
		_dwarf_host.clear_subject()
		_dwarf_host.hide()
	_dwarf_host = panel
	if is_instance_valid(_dwarf_host):
		_sheet_open = false
		_dwarf_host.action_requested.connect(_perform_dwarf_action)
		if _object_id is DwarfAgent:
			_dwarf_panel.clear_subject()
			_refresh_selected()


func selected_dwarf(provider: Node) -> DwarfAgent:
	return _object_id if _provider == provider and is_instance_valid(_object_id) and _object_id is DwarfAgent else null


func is_object_selected(provider: Node, object_id: Variant) -> bool:
	return _provider == provider and _object_id == object_id


## The compact object panel beside the dock (doc 260).
func get_compact_panel() -> Control:
	return _compact


## Open the selected dwarf's character sheet (doc 261), from the compact panel or Colony
## Dwarves' Details card; either stays open.
func open_character_sheet() -> void:
	if not is_instance_valid(_provider) or not _object_id is DwarfAgent: return
	_sheet_open = true
	_manager.open(WINDOW_ID)
	_dwarf_panel.fit()
	_refresh_selected()


func _on_compact_action(action_id: String) -> void:
	if action_id == "character_sheet": open_character_sheet()
	elif _object_id is DwarfAgent: _perform_dwarf_action(action_id)
	else: _perform_action(action_id)


func clear_selection() -> void:
	_sheet_open = false
	_release_selection()
	_provider = null
	_object_id = null
	if is_instance_valid(_outline):
		_outline.visible = false
	if is_instance_valid(_compact):
		_compact.hide()
	_manager.close(WINDOW_ID)
	selection_changed.emit()


## Closing the character sheet keeps the dwarf selected in the compact panel.
func _on_window_state_changed(id: String, opened: bool) -> void:
	if id == WINDOW_ID and not opened:
		_sheet_open = false


func _release_selection() -> void:
	if is_instance_valid(_provider) and _provider.has_method("clear_explorer_selection"):
		_provider.call("clear_explorer_selection", _object_id)
	_outline_subject = null
	_outline_bounds = AABB()
	if is_instance_valid(_compact):
		_compact.clear_subject()
	if is_instance_valid(_dwarf_panel):
		_dwarf_panel.clear_subject()
	if is_instance_valid(_dwarf_host):
		_dwarf_host.clear_subject()
		_dwarf_host.hide()


func _on_slice_changed(slice_y: int) -> void:
	_slice_y = slice_y
	_refresh_selected()


func _process(delta: float) -> void:
	# Moving actors keep a smooth outline without rebuilding its mesh every frame.
	if is_instance_valid(_outline_subject) and _outline_subject.is_inside_tree():
		_outline.global_position = _outline_subject.global_position + _outline_offset
	_refresh_elapsed += delta
	if _refresh_elapsed >= REFRESH_SECONDS:
		_refresh_elapsed = 0.0
		_refresh_selected()


func _refresh_selected() -> void:
	if _provider == null:
		return
	if not is_instance_valid(_provider):
		clear_selection()
		return
	var data: Dictionary = _provider.call("get_explorer_data", _object_id)
	if data.is_empty():
		clear_selection()
	else:
		_refresh(data)


## The one window: the selected dwarf's character sheet. It brings its own margins.
func _build_window() -> void:
	_dwarf_panel = DwarfPanel.new()
	_dwarf_panel.action_requested.connect(_perform_dwarf_action)
	_window = _manager.register_window(WINDOW_ID, "Character sheet", "", _dwarf_panel,
		{"persistent": false, "default_pos": Vector2(24, 150), "min_size": Vector2(380, 0), "family": "people", "flush": true})
	_window.keep_body_on_screen = true
	_dwarf_panel.window = _window
	get_viewport().size_changed.connect(_refresh_selected)


func _build_compact_panel() -> void:
	var layer := CanvasLayer.new()
	layer.name = "CompactObjectPanelLayer"
	layer.layer = COMPACT_LAYER
	add_child(layer)
	_compact = CompactPanel.new()
	_compact.hide()
	_compact.action_requested.connect(_on_compact_action)
	layer.add_child(_compact)
	# The dock places the panel beside itself and keeps its menus clear of it; the
	# character sheet fits above it.
	var dock := get_node_or_null(dock_ui_path) if not dock_ui_path.is_empty() else null
	if dock != null and dock.has_method("attach_selection_panel"):
		dock.attach_selection_panel(_compact)
		_dwarf_panel.dock = dock


func _refresh(data: Dictionary) -> void:
	var dwarf := String(data.get("presentation", "")) == "dwarf"
	var hosted := dwarf and is_instance_valid(_dwarf_host)
	_compact.visible = not hosted
	if hosted:
		_dwarf_host.show()
		_dwarf_host.show_data(data, bool(_provider.call("is_following", _object_id)))
	else:
		if dwarf: data.actions = data.get("actions", []) + [CHARACTER_SHEET]
		_compact.show_data(data)
	_update_outline(_provider.call("get_explorer_bounds", _object_id))
	_outline_subject = data.get("subject", data.get("agent")) as Node3D
	if is_instance_valid(_outline_subject):
		_outline_offset = _outline.global_position - _outline_subject.global_position
	if not _sheet_open:
		if _manager.is_open(WINDOW_ID): _manager.close(WINDOW_ID)
		return
	_dwarf_panel.show_data(data, bool(_provider.call("is_following", _object_id)))
	_window.reset_size()
	_position_inspector()


## The sheet starts in the right-hand inspection column. An existing saved
## position or a player drag takes precedence; it stays above the dock.
func _position_inspector() -> void:
	if not _inspector_positioned:
		_window.position = Vector2(get_viewport().get_visible_rect().size.x - _window.size.x - 24, 32)
		_inspector_positioned = true
	_window.clamp_to_viewport()
	_window.position.y = minf(_window.position.y, _dwarf_panel.lowest_top())


func _perform_action(action_id: String) -> void:
	if is_instance_valid(_provider) and _provider.has_method("perform_explorer_action"):
		_provider.call("perform_explorer_action", _object_id, action_id)
		_refresh_selected()


func _perform_dwarf_action(action_id: String) -> void:
	if not is_instance_valid(_provider):
		return
	if action_id == "character_sheet":   # Colony Dwarves' Details card
		open_character_sheet()
		return
	if action_id == "follow" and bool(_provider.call("is_following", _object_id)):
		action_id = "stop_follow"
	_perform_action(action_id)


func _update_outline(bounds: AABB) -> void:
	_outline.visible = bounds.size.length_squared() > 0.0
	if not _outline.visible:
		return
	_outline.global_position = bounds.get_center()
	var local_bounds := AABB(-bounds.size * .5, bounds.size)
	if local_bounds == _outline_bounds:
		return
	_outline_bounds = local_bounds
	_outline.mesh = Picking.outline_mesh(local_bounds.grow(.05), UITheme.HEARTH_COPPER)
