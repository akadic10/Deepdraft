class_name ObjectExplorerController
extends Node3D

## One context window for live world objects. Providers own their data/actions;
## this controller owns selection, occlusion, window layout and the outline.
## Provider API: pick_explorer_object(start,end), get_explorer_data(id),
## get_explorer_bounds(id), optional perform_explorer_action(id,action).
@export var window_manager_path: NodePath
@export var slice_controller_path: NodePath
@export var click_tool_paths: Array[NodePath] = []
@export var dwarf_director_path: NodePath

const Picking = preload("res://scripts/components/ObjectPicking.gd")
const WINDOW_ID := "object_explorer"
const RAY_MAX := 600.0
const REFRESH_SECONDS := 0.15

var _manager: UIWindowManager
var _window: UIWindow
var _provider: Node = null
var _object_id: Variant = null
var _slice_y := 127
var _refresh_elapsed := 0.0
var _tools: Array[Node] = []
var _dwarves: Node
var _name_label: Label
var _kind_label: Label
var _rows: VBoxContainer
var _row_names: Array[String] = []
var _row_values: Array[Label] = []
var _details: Label
var _actions: VBoxContainer
var _action_data: Array = []
var _outline: MeshInstance3D
var _outline_bounds := AABB()


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
	var slice := get_node_or_null(slice_controller_path)
	if slice != null:
		slice.connect("slice_changed", _on_slice_changed)
	_build_window()
	_manager.window_state_changed.connect(_on_window_state_changed)
	_outline = MeshInstance3D.new()
	_outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_outline)


func _unhandled_input(event: InputEvent) -> void:
	if _click_tool_active():
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
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
	for tool: Node in _tools:
		if tool.has_method("is_active") and bool(tool.call("is_active")):
			return true
	return is_instance_valid(_dwarves) and bool(_dwarves.call("is_walk_test_active"))


func select_at_screen(screen_pos: Vector2) -> bool:
	if _click_tool_active():
		return false
	var hit := pick_at_screen(screen_pos)
	return not hit.is_empty() and select_object(hit["provider"], hit["id"])


## Shared hit arbitration for ordinary selection and designation tools.
func pick_at_screen(screen_pos: Vector2) -> Dictionary:
	if not bool(WorldGenerator.get_streaming_stats().get("maps_ready", false)):
		return {}
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return {}
	var start := camera.project_ray_origin(screen_pos)
	var direction := camera.project_ray_normal(screen_pos).normalized()
	var terrain := Picking.terrain_hit(start, direction, _slice_y, RAY_MAX)
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
		return {}
	return {"provider": selected, "id": selected_id}


func select_object(provider: Node, object_id: Variant) -> bool:
	var data: Dictionary = provider.call("get_explorer_data", object_id)
	if data.is_empty():
		return false
	_provider = provider
	_object_id = object_id
	_refresh(data)
	_manager.open(WINDOW_ID)
	return true


func clear_selection() -> void:
	_provider = null
	_object_id = null
	if is_instance_valid(_outline):
		_outline.visible = false
	_manager.close(WINDOW_ID)


func _on_window_state_changed(id: String, opened: bool) -> void:
	if id == WINDOW_ID and not opened:
		_provider = null
		_object_id = null
		_outline.visible = false


func _on_slice_changed(slice_y: int) -> void:
	_slice_y = slice_y
	_refresh_selected()


func _process(delta: float) -> void:
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


func _build_window() -> void:
	var content := VBoxContainer.new()
	content.custom_minimum_size.x = 352.0
	content.add_theme_constant_override("separation", 10)
	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 19)
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	content.add_child(_name_label)
	_kind_label = Label.new()
	_kind_label.add_theme_font_size_override("font_size", UITheme.FONT_SMALL)
	_kind_label.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	content.add_child(_kind_label)
	content.add_child(HSeparator.new())
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 0)
	content.add_child(_rows)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 112.0
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	_details = Label.new()
	_details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_details.add_theme_font_size_override("font_size", UITheme.FONT_SMALL)
	_details.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	scroll.add_child(_details)
	_actions = VBoxContainer.new()
	content.add_child(_actions)
	_window = _manager.register_window(WINDOW_ID, "Object explorer", "", content,
		{"persistent": false, "default_pos": Vector2(24, 150), "min_size": Vector2(380, 0)})


func _refresh(data: Dictionary) -> void:
	_name_label.text = String(data.get("title", "Object"))
	_kind_label.text = String(data.get("kind", ""))
	var rows: Array = data.get("rows", [])
	var names: Array[String] = []
	for row: Array in rows:
		names.append(String(row[0]))
	# Reuse every row across tree selections: optional values never move fields.
	if names != _row_names:
		for child in _rows.get_children():
			_rows.remove_child(child)
			child.queue_free()
		_row_values.clear()
		_row_names = names
		for row_name: String in names:
			var row := HBoxContainer.new()
			row.custom_minimum_size.y = 30.0
			_rows.add_child(row)
			var label := Label.new()
			label.text = row_name
			label.custom_minimum_size.x = 132.0
			label.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
			label.add_theme_color_override("font_color", UITheme.TEXT_DIM)
			row.add_child(label)
			var value := Label.new()
			value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			value.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			value.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
			row.add_child(value)
			_row_values.append(value)
	for i in range(rows.size()):
		_row_values[i].text = String(rows[i][1])
		_row_values[i].tooltip_text = String(rows[i][1])
	_details.text = String(data.get("details", ""))
	var actions: Array = data.get("actions", [])
	if actions != _action_data:
		_action_data = actions.duplicate(true)
		for child in _actions.get_children():
			_actions.remove_child(child)
			child.queue_free()
		for action: Dictionary in actions:
			var button := UITheme.make_button(String(action["text"]), "", Vector2(0, 30), String(action.get("variant", "")))
			button.pressed.connect(_perform_action.bind(String(action["id"])))
			_actions.add_child(button)
	_update_outline(_provider.call("get_explorer_bounds", _object_id))
	_window.reset_size()
	_window.clamp_to_viewport()


func _perform_action(action_id: String) -> void:
	if is_instance_valid(_provider) and _provider.has_method("perform_explorer_action"):
		_provider.call("perform_explorer_action", _object_id, action_id)
		_refresh_selected()


func _update_outline(bounds: AABB) -> void:
	_outline.visible = bounds.size.length_squared() > 0.0
	if not _outline.visible or bounds == _outline_bounds:
		return
	_outline_bounds = bounds
	_outline.mesh = Picking.outline_mesh(bounds.grow(.05), Color(.65, .85, 1.0))
