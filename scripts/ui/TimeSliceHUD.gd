extends Control

## Permanent HUD presentation. DockUI owns time actions; SliceController owns
## the plane and saved height. No independent clock or slice state lives here.
signal speed_requested(speed: int)
signal slice_toggle_requested()

var speed_buttons: Dictionary = {}
var step_buttons: Dictionary = {}
var slice_button: Button
var row: Panel
var tower: Panel
var readout: Label
var level_label: Label
var _plate: Panel
var _divider: ColorRect
var _slice: Node


func _ready() -> void:
	add_to_group("time_slice_hud")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UITheme.apply_surface(self)
	row = _panel()
	tower = _panel()
	tower.gui_input.connect(_on_tower_input)
	var entries: Dictionary = UIRegistry.get_time_slice().get("buttons", {})
	var ids := ["pause", "play", "fast"]
	for speed in range(3):
		var button := _button(entries[ids[speed]], row)
		button.pressed.connect(func(): speed_requested.emit(speed))
		speed_buttons[speed] = button
	slice_button = _button(entries.slice, row)
	slice_button.pressed.connect(func(): slice_toggle_requested.emit())
	_divider = ColorRect.new()
	_divider.color = UITheme.HEARTH_COPPER.darkened(.25)
	_divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_divider)
	for id in ["up_four", "up_one", "down_one", "down_four"]:
		var button := _button(entries[id], tower)
		button.toggle_mode = false
		button.pressed.connect(_step.bind(id))
		button.gui_input.connect(_on_tower_input)
		step_buttons[id] = button
	_plate = Panel.new()
	_plate.mouse_filter = Control.MOUSE_FILTER_PASS
	_plate.mouse_force_pass_scroll_events = false
	_plate.add_theme_stylebox_override("panel", UITheme.hearth_panel(true))
	_plate.gui_input.connect(_on_tower_input)
	tower.add_child(_plate)
	level_label = _label(10)
	level_label.text = "LEVEL"
	level_label.add_theme_color_override("font_color", UITheme.HEARTH_COPPER)
	readout = _label(24)
	UITheme.apply_title(readout, 24)
	refresh_slice()


func _panel() -> Panel:
	var panel := Panel.new()
	panel.mouse_force_pass_scroll_events = false
	panel.add_theme_stylebox_override("panel", UITheme.dock_panel_style())
	add_child(panel)
	return panel


func _button(entry: Dictionary, parent: Control) -> Button:
	var button := preload("res://scripts/ui/TimeSliceButton.gd").new()
	button.setup(entry, UIRegistry.get_dock_icon(entry))
	parent.add_child(button)
	return button


func _label(font_size: int) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	_plate.add_child(label)
	return label


func bind_slice(controller: Node) -> void:
	_slice = controller
	if not _slice.slice_changed.is_connected(_slice_changed): _slice.slice_changed.connect(_slice_changed)
	if not _slice.slice_active_changed.is_connected(_active_changed): _slice.slice_active_changed.connect(_active_changed)
	refresh_slice()


func _slice_changed(_height: int) -> void:
	refresh_slice()


func _active_changed(_active: bool) -> void:
	refresh_slice()


func refresh_slice() -> void:
	var active := is_instance_valid(_slice) and bool(_slice.is_active())
	var height := int(_slice.get_slice_y()) if active else 127
	slice_button.set_pressed_no_signal(active)
	slice_button.disabled = not is_instance_valid(_slice)
	level_label.visible = active
	readout.text = str(height) if active else "Full\nworld"
	readout.add_theme_font_size_override("font_size", 24 if active else 15)
	readout.position.y = 14 if active else 0
	readout.size.y = _plate.size.y - readout.position.y
	for id: String in step_buttons:
		var button: Button = step_buttons[id]
		button.disabled = not active or (height >= SliceController.MAX_SLICE_Y if id.begins_with("up") else height <= SliceController.MIN_SLICE_Y)
		button.queue_redraw()
	slice_button.queue_redraw()


func _step(id: String) -> void:
	if not is_instance_valid(_slice) or not _slice.is_active(): return
	match id:
		"up_four": _slice.step_cell_up()
		"up_one": _slice.step_single_up()
		"down_one": _slice.step_single_down()
		"down_four": _slice.step_cell_down()


func _on_tower_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		if event.pressed:
			var direction := "up" if event.button_index == MOUSE_BUTTON_WHEEL_UP else "down"
			_step(direction + ("_four" if event.ctrl_pressed else "_one"))
		accept_event()


func fit_to_viewport(main_dock: Rect2) -> void:
	var viewport := get_viewport_rect().size
	var side := 64.0 if viewport.x >= 1600 else (56.0 if viewport.x >= 1200 else 48.0)
	var row_width := side * 4 + 32
	var row_height := side + 12
	var step_height := 28.0 if side < 56 else 36.0
	var tower_height := step_height * 4 + 64
	size = Vector2(row_width, tower_height + row_height)
	position = Vector2(viewport.x - 16 - row_width, viewport.y - 24 - size.y)
	# On compact screens the transport sits above the right end of the main
	# dock. All controls retain their size; the main commands stay centered.
	if Rect2(position + Vector2(0, tower_height), Vector2(row_width, row_height)).grow(8).intersects(main_dock):
		position.y = main_dock.position.y - 8 - size.y
	row.position = Vector2(0, tower_height)
	row.size = Vector2(row_width, row_height)
	for speed: int in speed_buttons:
		var button: Button = speed_buttons[speed]
		button.position = Vector2(6 + speed * (side + 4), 6)
		button.size = Vector2.ONE * side
	slice_button.position = Vector2(row_width - side - 6, 6)
	slice_button.size = Vector2.ONE * side
	_divider.position = Vector2(slice_button.position.x - 7, 10)
	_divider.size = Vector2(1, side - 8)
	tower.position = Vector2(slice_button.position.x - 6, 0)
	tower.size = Vector2(side + 12, tower_height + 5)
	for index in range(4):
		var button: Button = step_buttons[["up_four", "up_one", "down_one", "down_four"][index]]
		button.position = Vector2(6, 6 + index * (step_height + 2) + (48 if index >= 2 else 0))
		button.size = Vector2(side, step_height)
	_plate.position = Vector2(6, 6 + 2 * (step_height + 2))
	_plate.size = Vector2(side, 46)
	level_label.position = Vector2.ZERO
	level_label.size = Vector2(side, 16)
	readout.size.x = side
	refresh_slice()


func occupied_rects() -> Array[Rect2]:
	return [row.get_global_rect(), tower.get_global_rect()]


func preferred_row_width() -> float:
	var width := get_viewport_rect().size.x
	return (64.0 if width >= 1600 else (56.0 if width >= 1200 else 48.0)) * 4 + 32
