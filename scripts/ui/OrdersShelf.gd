extends Control

## The Orders and Zones shelf (doc 23): the open group's tools as tiles above its dock
## button. The tool bar (ToolBar) shows the active tool, its orders and Undo.
signal tool_requested(tool_id: String)
signal shelf_visibility_changed()

var _controllers: Dictionary = {}
var _buttons: Dictionary = {}
var _entries: Dictionary = {}
var _group_by_tool: Dictionary = {}
var _open_group := "orders"
var _tool_slots: Dictionary = {}
var dock_buttons: Dictionary = {}
var _shelf: PanelContainer
var _grid: GridContainer
var _dock_rect := Rect2()
var inspector: Control
var _positioning := false
var _refresh_elapsed := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UITheme.apply_surface(self)
	_shelf = PanelContainer.new()
	_shelf.name = "OrdersShelf"
	_shelf.add_theme_stylebox_override("panel", UITheme.dock_panel_style())
	_shelf.hide()
	add_child(_shelf)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	_shelf.add_child(column)
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_grid.add_theme_constant_override("h_separation", 6)
	_grid.add_theme_constant_override("v_separation", 6)
	column.add_child(_grid)
	var tool_entries: Array[Dictionary] = []
	for group: String in ["orders", "zones"]:
		for entry: Dictionary in UIRegistry.get_menu(group).get("items", []):
			_group_by_tool[String(entry.target)] = group
			tool_entries.append(entry)
	for entry: Dictionary in tool_entries:
		var id := String(entry.target)
		_entries[id] = entry
		var button = preload("res://scripts/ui/DockIconButton.gd").new()
		button.setup(entry, UIRegistry.get_dock_icon(entry))
		button.custom_minimum_size = Vector2(64, 64)
		button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		button.name = id.to_pascal_case()
		button.disabled = bool(entry.get("disabled", false))
		button.pressed.connect(_request_tool.bind(id))
		var slot := MarginContainer.new()
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if bool(entry.get("separator_before", false)):
			slot.add_theme_constant_override("margin_left", 12)
		slot.add_child(button)
		_grid.add_child(slot)
		_tool_slots[id] = slot
		_buttons[id] = button
		button.visible = group_for_tool(id) == _open_group
		slot.visible = button.visible
	_shelf.mouse_force_pass_scroll_events = false
	_shelf.resized.connect(_position_panels)
	get_viewport().size_changed.connect(_position_panels)


func _request_tool(id: String) -> void:
	# Planned entries show their explanation, without disturbing the current tool.
	if bool(_entries[id].get("planned", false)): return
	tool_requested.emit(id)
	refresh()


func bind_controller(tool_id: String, controller: Node) -> void:
	_controllers[tool_id] = controller
	refresh()


func is_open(group: String = "") -> bool:
	return _shelf.visible and (group.is_empty() or group == _open_group)


## Where the open shelf is, for the tool bar to sit above it; empty while it is closed.
func shelf_rect() -> Rect2:
	return _shelf.get_global_rect() if _shelf != null and _shelf.visible else Rect2()


func set_open(shown: bool, group: String = "") -> void:
	if not group.is_empty():
		_open_group = group
		for id: String in _buttons:
			_buttons[id].visible = group_for_tool(id) == group
			_tool_slots[id].visible = _buttons[id].visible
	_shelf.visible = shown
	_position_panels()
	shelf_visibility_changed.emit()


func group_for_tool(tool_id: String) -> String:
	return String(_group_by_tool.get(tool_id, ""))


func active_tool_id() -> String:
	for id: String in _controllers:
		var controller: Node = _controllers[id]
		if not is_instance_valid(controller) or not controller.is_active(): continue
		if controller.has_method("get_order_tool_id"): return controller.get_order_tool_id()
		return id
	return ""


func refresh() -> void:
	if _shelf == null: return
	var active := active_tool_id()
	for id: String in _buttons:
		if _buttons[id].toggle_mode: _buttons[id].set_pressed_no_signal(active == id)
	_position_panels()


func _process(delta: float) -> void:
	_refresh_elapsed += delta
	if _refresh_elapsed < .1: return
	_refresh_elapsed = 0
	refresh()


func fit_above_dock(dock_rect: Rect2) -> void:
	_dock_rect = dock_rect
	_position_panels()


func _position_panels() -> void:
	if _shelf == null or _dock_rect.size == Vector2.ZERO or _positioning: return
	_positioning = true
	var viewport := get_viewport().get_visible_rect().size
	var icon_size := 64.0 if viewport.x >= 1200 else 56.0
	var visible_count := 0
	var separator_width := 0
	for id: String in _buttons:
		if _buttons[id].visible:
			visible_count += 1
			if bool(_entries[id].get("separator_before", false)): separator_width += 12
		_buttons[id].custom_minimum_size = Vector2.ONE * icon_size
	var shelf_bottom := _dock_rect.position.y - 8
	var available := _available_width(shelf_bottom, icon_size * 2 + 24)
	_grid.columns = maxi(1, visible_count)
	if 16 + separator_width + visible_count * icon_size + (visible_count - 1) * 6 > available:
		_grid.columns = maxi(1, mini(3, int((available - 16 - separator_width) / (icon_size + 6))))
	_shelf.reset_size()
	var anchor := (viewport.x - _shelf.size.x) * .5
	var parent_button: Control = dock_buttons.get(_open_group)
	if is_instance_valid(parent_button):
		anchor = parent_button.get_global_rect().position.x - 8
	_shelf.position = Vector2(_panel_x(_shelf.size, shelf_bottom - _shelf.size.y, anchor), shelf_bottom - _shelf.size.y)
	# Where neither side of the inspector has room (the compact panel on a narrow
	# screen, doc 260), the shelf rises above it instead.
	if is_instance_valid(inspector) and inspector.visible:
		var occupied := inspector.get_global_rect().grow(8)
		if Rect2(_shelf.position, _shelf.size).intersects(occupied):
			_shelf.position.y = maxf(8.0, occupied.position.y - _shelf.size.y)
	_positioning = false
	queue_redraw()


## Keep the stack in the usable side of a moved inspector, wrapping icons only
## when that actual space is too narrow for a single row.
func _available_width(bottom: float, height: float) -> float:
	var viewport := get_viewport_rect().size
	var full := viewport.x - 32
	if is_instance_valid(inspector) and inspector.visible:
		var occupied := inspector.get_global_rect().grow(8)
		if Rect2(16, bottom - height, full, height).intersects(occupied):
			var side := maxf(occupied.position.x - 16, viewport.x - 16 - occupied.end.x)
			if side >= 240: return side
	return full


func _panel_x(panel_size: Vector2, top: float, preferred: float) -> float:
	var right := get_viewport_rect().size.x - 16 - panel_size.x
	var x := clampf(preferred, 16, right)
	if is_instance_valid(inspector) and inspector.visible:
		var occupied := inspector.get_global_rect().grow(8)
		if Rect2(Vector2(x, top), panel_size).intersects(occupied):
			var distance := INF
			for candidate: float in [occupied.position.x - panel_size.x, occupied.end.x]:
				if candidate >= 16 and candidate <= right and absf(candidate - preferred) < distance:
					x = candidate
					distance = absf(candidate - preferred)
	return x


func _draw() -> void:
	if _shelf == null or not _shelf.visible: return
	var parent_button: Control = dock_buttons.get(_open_group)
	if not is_instance_valid(parent_button): return
	var x := parent_button.get_global_rect().get_center().x
	var bounds := _shelf.get_global_rect()
	if x < bounds.position.x + 8 or x > bounds.end.x - 8: return
	var link := Rect2(x - 1, bounds.end.y, 2, _dock_rect.position.y - bounds.end.y)
	if is_instance_valid(inspector) and inspector.visible and link.intersects(inspector.get_global_rect()): return
	draw_line(Vector2(x, bounds.end.y), Vector2(x, _dock_rect.position.y), UITheme.HEARTH_COPPER, 2)

