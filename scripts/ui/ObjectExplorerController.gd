class_name ObjectExplorerController
extends Node3D

## One context window for live world objects. Providers own their data/actions;
## this controller owns selection, occlusion, window layout and the outline.
## Provider API: pick_explorer_object(start,end), get_explorer_data(id),
## get_explorer_bounds(id), optional perform_explorer_action(id,action).
## Optional on_explorer_selected(id) runs on explicit selection, never refresh.
@export var window_manager_path: NodePath
@export var slice_controller_path: NodePath
@export var click_tool_paths: Array[NodePath] = []
@export var dwarf_director_path: NodePath

const Picking = preload("res://scripts/components/ObjectPicking.gd")
const DwarfPanel = preload("res://scripts/ui/DwarfInspectorPanel.gd")
const StoragePanel = preload("res://scripts/ui/StorageInspectorPanel.gd")
const WINDOW_ID := "object_explorer"
const RAY_MAX := 600.0
const REFRESH_SECONDS := 0.15
signal selection_changed

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
var _standard_content: Control
var _standard_details_scroll: ScrollContainer
var _dwarf_panel: VBoxContainer
var _storage_panel: VBoxContainer
var _inspector_positioned := false
var _outline_subject: Node3D
var _outline_offset := Vector3.ZERO
var _dwarf_host: Control
var _moving_dwarf_presentation := false


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
		# The overview owns its close action while it hosts the selected dwarf.
		if is_instance_valid(_dwarf_host) and _object_id is DwarfAgent: return
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
	if _provider != provider or _object_id != object_id:
		_release_selection()
	_provider = provider
	_object_id = object_id
	_refresh(data)
	if String(data.get("presentation", "")) == "dwarf" and is_instance_valid(_dwarf_host):
		_hide_detached_inspector()
	else:
		_manager.open(WINDOW_ID)
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
		_dwarf_host.action_requested.connect(_perform_dwarf_action)
		if _object_id is DwarfAgent:
			_dwarf_panel.clear_subject()
			_refresh_selected()
			_hide_detached_inspector()


func selected_dwarf(provider: Node) -> DwarfAgent:
	return _object_id if _provider == provider and is_instance_valid(_object_id) and _object_id is DwarfAgent else null


func _hide_detached_inspector() -> void:
	_moving_dwarf_presentation = true
	_manager.close(WINDOW_ID)
	_moving_dwarf_presentation = false


func is_object_selected(provider: Node, object_id: Variant) -> bool:
	return _provider == provider and _object_id == object_id


func clear_selection() -> void:
	_release_selection()
	_provider = null
	_object_id = null
	if is_instance_valid(_outline):
		_outline.visible = false
	_manager.close(WINDOW_ID)
	selection_changed.emit()


func _on_window_state_changed(id: String, opened: bool) -> void:
	if id == WINDOW_ID and not opened and not _moving_dwarf_presentation:
		_release_selection()
		_provider = null
		_object_id = null
		_outline.visible = false
		selection_changed.emit()


func _release_selection() -> void:
	if is_instance_valid(_provider) and _provider.has_method("clear_explorer_selection"):
		_provider.call("clear_explorer_selection", _object_id)
	_outline_subject = null
	_outline_bounds = AABB()
	if is_instance_valid(_dwarf_panel):
		_dwarf_panel.clear_subject()
	if is_instance_valid(_dwarf_host):
		_dwarf_host.clear_subject()
		_dwarf_host.hide()
	if is_instance_valid(_storage_panel):
		_storage_panel.clear_subject()


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


func _build_window() -> void:
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	var root_content := VBoxContainer.new()
	root_content.add_theme_constant_override("separation", 0)
	margin.add_child(root_content)
	var content := VBoxContainer.new()
	_standard_content = content
	root_content.add_child(content)
	content.custom_minimum_size.x = 352.0
	content.add_theme_constant_override("separation", 10)
	var identity := PanelContainer.new()
	identity.add_theme_stylebox_override("panel", UITheme.hearth_panel(true))
	content.add_child(identity)
	var heading := VBoxContainer.new()
	heading.add_theme_constant_override("separation", 5)
	identity.add_child(heading)
	_kind_label = Label.new()
	_kind_label.add_theme_font_size_override("font_size", 11)
	_kind_label.add_theme_color_override("font_color", UITheme.HEARTH_COPPER)
	heading.add_child(_kind_label)
	_name_label = Label.new()
	UITheme.apply_title(_name_label, 26)
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	heading.add_child(_name_label)
	var scroll := ScrollContainer.new()
	_standard_details_scroll = scroll
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.mouse_force_pass_scroll_events = false
	content.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	scroll.add_child(body)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 0)
	body.add_child(_rows)
	_details = Label.new()
	_details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_details.add_theme_font_size_override("font_size", UITheme.FONT_SMALL)
	_details.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	body.add_child(_details)
	_actions = VBoxContainer.new()
	content.add_child(_actions)
	_dwarf_panel = DwarfPanel.new()
	_dwarf_panel.visible = false
	_dwarf_panel.action_requested.connect(_perform_dwarf_action)
	root_content.add_child(_dwarf_panel)
	_storage_panel = StoragePanel.new()
	_storage_panel.visible = false
	_storage_panel.action_requested.connect(_perform_action)
	root_content.add_child(_storage_panel)
	_window = _manager.register_window(WINDOW_ID, "Object explorer", "", margin,
		{"persistent": false, "default_pos": Vector2(24, 150), "min_size": Vector2(380, 0)})
	UITheme.apply_catalog_window(_window)
	_window.keep_body_on_screen = true
	_storage_panel.window = _window
	get_viewport().size_changed.connect(_refresh_selected)


func _refresh(data: Dictionary) -> void:
	var is_dwarf := String(data.get("presentation", "")) == "dwarf"
	var is_storage := String(data.get("presentation", "")) == "storage"
	_standard_content.visible = not is_dwarf and not is_storage
	_dwarf_panel.visible = is_dwarf and not is_instance_valid(_dwarf_host)
	_storage_panel.visible = is_storage
	_window.custom_minimum_size.x = 380
	_window.set_window_title("DWARF INSPECTOR" if is_dwarf else "Object explorer")
	if is_storage:
		_outline_subject = null
		_window.set_window_title(String(data.title))
		_storage_panel.show_storage(data.storage, data.get("actions", []))
		_update_outline(_provider.call("get_explorer_bounds", _object_id))
		_storage_panel._fit()
		_position_inspector()
		return
	if is_dwarf:
		var panel := _dwarf_host if is_instance_valid(_dwarf_host) else _dwarf_panel
		panel.show()
		panel.show_data(data, bool(_provider.call("is_following", _object_id)))
		_outline_subject = data.agent
		_update_outline(_provider.call("get_explorer_bounds", _object_id))
		_outline_offset = _outline.global_position - _outline_subject.global_position
		if is_instance_valid(_dwarf_host): return
		_window.reset_size()
		_position_inspector()
		return
	_outline_subject = null
	_name_label.text = String(data.get("title", "Object"))
	_kind_label.text = String(data.get("kind", "")).to_upper()
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
	_details.visible = not _details.text.is_empty()
	var actions: Array = data.get("actions", [])
	_actions.visible = not actions.is_empty()
	if actions != _action_data:
		_action_data = actions.duplicate(true)
		for child in _actions.get_children():
			_actions.remove_child(child)
			child.queue_free()
		for action: Dictionary in actions:
			var button := UITheme.make_button(String(action["text"]), "", Vector2(0, 30), String(action.get("variant", "")))
			if action.has("icon"):
				button.icon = load(String(action.icon))
				button.add_theme_constant_override("icon_max_width",20)
			button.pressed.connect(_perform_action.bind(String(action["id"])))
			_actions.add_child(button)
	_update_outline(_provider.call("get_explorer_bounds", _object_id))
	# The facts and description scroll together; identity and actions stay in view.
	_outline_subject = data.get("subject") as Node3D
	if is_instance_valid(_outline_subject):
		_outline_offset = _outline.global_position - _outline_subject.global_position
	var fixed_height := _window.get_combined_minimum_size().y - _standard_details_scroll.get_combined_minimum_size().y
	var body_height: float = _standard_details_scroll.get_child(0).get_combined_minimum_size().y
	_standard_details_scroll.custom_minimum_size.y = clampf(body_height, 80, maxf(80, minf(300, get_viewport().get_visible_rect().size.y - 152 - fixed_height)))
	_window.reset_size()
	_position_inspector()


## Every object starts in the same right-hand inspection column. An existing
## saved position or a player drag takes precedence for every subject type.
func _position_inspector() -> void:
	if not _inspector_positioned:
		_window.position = Vector2(get_viewport().get_visible_rect().size.x - _window.size.x - 24, 32)
		_inspector_positioned = true
	_window.clamp_to_viewport()


func _perform_action(action_id: String) -> void:
	if is_instance_valid(_provider) and _provider.has_method("perform_explorer_action"):
		_provider.call("perform_explorer_action", _object_id, action_id)
		_refresh_selected()


func _perform_dwarf_action(action_id: String) -> void:
	if not is_instance_valid(_provider):
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
