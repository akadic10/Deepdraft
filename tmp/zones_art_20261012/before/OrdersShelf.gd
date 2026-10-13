extends Control

## Presentation only. Tool owners provide live hints and opaque undo receipts.
## A receipt may cancel remaining work; it can never restore mined/felled terrain.
signal tool_requested(tool_id: String)
signal shelf_visibility_changed()

var _controllers: Dictionary = {}
var _buttons: Dictionary = {}
var _entries: Dictionary = {}
var _group_by_tool: Dictionary = {}
var _open_group := "orders"
var _shelf_title: Label
var _shelf_header: Control
var _tool_slots: Dictionary = {}
var dock_buttons: Dictionary = {}
var _history: Array[Dictionary] = []
var _last_order: Dictionary = {}
var _shelf: PanelContainer
var _grid: GridContainer
var _banner: PanelContainer
var _banner_layout: BoxContainer
var _banner_actions: HBoxContainer
var _title: Label
var _hint: Label
var _icon: TextureRect
var _undo: Button
var _toast: PanelContainer
var _toast_label: Label
var _view: Button
var _toast_until := 0
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
	_shelf.add_theme_stylebox_override("panel", UITheme.orders_panel_style())
	_shelf.hide()
	add_child(_shelf)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	_shelf.add_child(column)
	var header := HBoxContainer.new()
	_shelf_header = header
	header.add_theme_constant_override("separation", 24)
	column.add_child(header)
	header.hide()
	_shelf_title = Label.new()
	_shelf_title.text = "Orders"
	UITheme.apply_title(_shelf_title, 20)
	_shelf_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_shelf_title)
	var help := Label.new()
	help.text = "Choose a tool"
	help.add_theme_color_override("font_color", UITheme.HEARTH_MUTED)
	header.add_child(help)
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
		var illustrated := group_for_tool(id) == "orders"
		var button: Button
		if illustrated:
			button = preload("res://scripts/ui/DockIconButton.gd").new()
			button.setup(entry, UIRegistry.get_dock_icon(entry))
			button.custom_minimum_size = Vector2(64, 64)
			button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		else:
			button = UITheme.make_button(String(entry.label), String(entry.get("tooltip", "")), Vector2(104, 76))
			button.icon = UIRegistry.get_dock_icon(entry)
			button.expand_icon = true
			button.add_theme_constant_override("icon_max_width", 30)
			button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
			for state: String in ["normal", "pressed", "hover", "hover_pressed"]:
				button.add_theme_color_override("icon_" + state + "_color", UITheme.HEARTH_COPPER)
		button.name = id.to_pascal_case()
		button.focus_mode = Control.FOCUS_ALL
		button.toggle_mode = true
		button.disabled = bool(entry.get("disabled", false))
		if button.disabled and not illustrated: button.text += "\nLater"
		button.pressed.connect(func(): tool_requested.emit(id); refresh())
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
	_banner = PanelContainer.new()
	_banner.name = "OrderModeBanner"
	_banner.add_theme_stylebox_override("panel", UITheme.orders_context_style())
	_banner.hide()
	add_child(_banner)
	_banner_layout = BoxContainer.new()
	_banner_layout.add_theme_constant_override("separation", 8)
	_banner.add_child(_banner_layout)
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 12)
	_banner_layout.add_child(row)
	_icon = TextureRect.new()
	_icon.custom_minimum_size = Vector2(30, 30)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.modulate = UITheme.HEARTH_COPPER
	row.add_child(_icon)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	_title = Label.new()
	UITheme.apply_title(_title, 17)
	text.add_child(_title)
	_hint = Label.new()
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size = Vector2(260, 0)
	_hint.add_theme_color_override("font_color", UITheme.HEARTH_MUTED)
	_hint.add_theme_font_size_override("font_size", 13)
	text.add_child(_hint)
	_banner_actions = HBoxContainer.new()
	_banner_actions.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_banner_layout.add_child(_banner_actions)
	_undo = UITheme.make_button("Undo last order", "Cancel remaining work from your last designation. Completed work stays completed.")
	_undo.pressed.connect(_undo_last)
	_banner_actions.add_child(_undo)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_banner_actions.add_child(spacer)
	var done := UITheme.make_button("Done  ·  Esc", "Finish this tool and keep confirmed orders")
	UITheme.apply_catalog_primary(done)
	done.pressed.connect(func(): tool_requested.emit(""))
	_banner_actions.add_child(done)
	_toast = PanelContainer.new()
	_toast.name = "OrderFeedback"
	_toast.add_theme_stylebox_override("panel", UITheme.orders_panel_style())
	_toast.hide()
	add_child(_toast)
	var toast_row := HBoxContainer.new()
	toast_row.add_theme_constant_override("separation", 12)
	_toast.add_child(toast_row)
	_toast_label = Label.new()
	_toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toast_row.add_child(_toast_label)
	_view = UITheme.make_button("View order")
	_view.pressed.connect(_view_last)
	toast_row.add_child(_view)
	for panel: Control in [_shelf, _banner, _toast]:
		panel.mouse_force_pass_scroll_events = false
		panel.resized.connect(_position_panels)
	get_viewport().size_changed.connect(_position_panels)
	_shelf.add_theme_stylebox_override("panel", UITheme.dock_panel_style())


func bind_controller(tool_id: String, controller: Node) -> void:
	_controllers[tool_id] = controller
	if controller.has_method("set_shared_order_ui"): controller.set_shared_order_ui(true)
	var on_order := _record_order.bind(controller)
	if controller.has_signal("order_created") and not controller.is_connected("order_created", on_order):
		controller.connect("order_created", on_order)
	var on_feedback := _on_order_feedback
	if controller.has_signal("order_feedback") and not controller.is_connected("order_feedback", on_feedback):
		controller.connect("order_feedback", on_feedback)
	refresh()


func is_open(group: String = "") -> bool:
	return _shelf.visible and (group.is_empty() or group == _open_group)


func set_open(shown: bool, group: String = "") -> void:
	if not group.is_empty():
		_open_group = group
		_shelf_title.text = String(UIRegistry.get_menu(group).get("title", group.capitalize()))
		_shelf_header.visible = group != "orders"
		_shelf.add_theme_stylebox_override("panel", UITheme.dock_panel_style() if group == "orders" else UITheme.orders_panel_style())
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
	if _banner == null: return
	var active := active_tool_id()
	for id: String in _buttons:
		_buttons[id].set_pressed_no_signal(active == id)
	_banner.visible = not active.is_empty()
	if not active.is_empty():
		var entry: Dictionary = _entries[active]
		_title.text = entry.label
		_icon.texture = _buttons[active].icon
		_icon.modulate = Color.WHITE if group_for_tool(active) == "orders" else UITheme.HEARTH_COPPER
		var controller: Node = _controllers[active]
		_hint.text = controller.get_order_summary() if controller.has_method("get_order_summary") else controller.get_order_hint()
		_hint.tooltip_text = controller.get_order_hint()
	_prune_history()
	_undo.disabled = _history.is_empty()
	_undo.visible = not _history.is_empty()
	_view.visible = _receipt_pending(_last_order)
	_position_panels()


func _process(delta: float) -> void:
	_refresh_elapsed += delta
	if _refresh_elapsed < .1: return
	_refresh_elapsed = 0
	if _toast.visible and Time.get_ticks_msec() >= _toast_until: _toast.hide()
	refresh()


func fit_above_dock(dock_rect: Rect2) -> void:
	_dock_rect = dock_rect
	_position_panels()


func _position_panels() -> void:
	if _shelf == null or _dock_rect.size == Vector2.ZERO or _positioning: return
	_positioning = true
	var viewport := get_viewport().get_visible_rect().size
	var illustrated := _open_group == "orders"
	var icon_size := 64.0 if viewport.x >= 1200 else 56.0
	var visible_count := 0
	for id: String in _buttons:
		if _buttons[id].visible: visible_count += 1
		if group_for_tool(id) == "orders":
			_buttons[id].custom_minimum_size = Vector2.ONE * icon_size
	var shelf_bottom := _dock_rect.position.y - 8
	var available := _available_width(shelf_bottom, icon_size * 2 + 24)
	_grid.columns = maxi(1, visible_count)
	if illustrated and 16 + 12 + visible_count * icon_size + (visible_count - 1) * 6 > available:
		_grid.columns = maxi(1, mini(3, int((available - 28) / (icon_size + 6))))
	_shelf.reset_size()
	var anchor := (viewport.x - _shelf.size.x) * .5
	var parent_button: Control = dock_buttons.get(_open_group)
	if illustrated and is_instance_valid(parent_button):
		anchor = parent_button.get_global_rect().position.x - 8
	_shelf.position = Vector2(_panel_x(_shelf.size, shelf_bottom - _shelf.size.y, anchor), shelf_bottom - _shelf.size.y)
	var stack_top := _shelf.position.y if _shelf.visible else _dock_rect.position.y
	var banner_width := minf(640, _available_width(stack_top - 8, 112))
	_banner_layout.vertical = banner_width < 600
	_banner.custom_minimum_size.x = banner_width
	_hint.custom_minimum_size.x = maxf(160, banner_width - 62 \
		- (0.0 if _banner_layout.vertical else _banner_actions.get_combined_minimum_size().x + 12))
	_banner.reset_size()
	var banner_top := stack_top - _banner.size.y - 8
	_banner.position = Vector2(_panel_x(_banner.size, banner_top, _shelf.position.x), banner_top)
	var toast_bottom := (_banner.position.y if _banner.visible else stack_top) - 8
	var toast_width := minf(500, _available_width(toast_bottom, 80))
	_toast.custom_minimum_size.x = toast_width
	_toast_label.custom_minimum_size.x = maxf(120, toast_width - 44 - (_view.get_combined_minimum_size().x if _view.visible else 0.0))
	_toast.reset_size()
	_toast.position = Vector2(_panel_x(_toast.size, toast_bottom - _toast.size.y, _shelf.position.x), toast_bottom - _toast.size.y)
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
	if _shelf == null or not _shelf.visible or _open_group != "orders": return
	var parent_button: Control = dock_buttons.get("orders")
	if not is_instance_valid(parent_button): return
	var x := parent_button.get_global_rect().get_center().x
	var bounds := _shelf.get_global_rect()
	if x < bounds.position.x + 8 or x > bounds.end.x - 8: return
	draw_line(Vector2(x, bounds.end.y), Vector2(x, _dock_rect.position.y), UITheme.HEARTH_COPPER, 2)


func _receipt_pending(record: Dictionary) -> bool:
	return not record.is_empty() and is_instance_valid(record.owner) and record.owner.order_is_pending(record.receipt)


func _prune_history() -> void:
	while not _history.is_empty() and not _receipt_pending(_history.back()): _history.pop_back()


func _record_order(receipt: Dictionary, order_controller: Node) -> void:
	_last_order = {"owner": order_controller, "receipt": receipt}
	_history.append(_last_order)
	if _history.size() > 20: _history.pop_front()
	_show_feedback(String(receipt.message))
	refresh()


func _show_feedback(message: String) -> void:
	_toast_label.text = message
	_toast_until = Time.get_ticks_msec() + 5500
	_toast.show()
	_toast.reset_size()
	_position_panels()


func hide_feedback() -> void:
	_toast.hide()


func _on_order_feedback(message: String) -> void:
	_last_order = {}
	_show_feedback(message)
	refresh()


func _undo_last() -> void:
	_prune_history()
	if _history.is_empty(): return
	var record: Dictionary = _history.pop_back()
	var count: int = record.owner.undo_order(record.receipt)
	_last_order = {}
	_show_feedback("Last order cancelled · %d remaining" % count)
	refresh()


func _view_last() -> void:
	if not _receipt_pending(_last_order): return
	tool_requested.emit("")
	_last_order.owner.inspect_order(_last_order.receipt)
	_toast.hide()
