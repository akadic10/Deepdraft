extends Control

## Permanent HUD presentation. DockUI owns time actions; SliceController owns
## the plane and saved height. No independent clock or slice state lives here.
## Layout (doc 259, option B): pause, 1x and 2x sit under the Sky Dial; the view
## toggles X-ray and Slice are the main dock's last group, sized like its other icons.
## The slice tower and the X-ray options rise from Slice only while that view is on.
## Their keys (Space, 1, 2, V and X; doc 23 "Keys") work as the buttons do; SliceController
## owns Slice's.
signal speed_requested(speed: int)
signal slice_toggle_requested()

# Text sizes come from the type scale (doc 23, "Type").
const MEDIUM := UITheme.TYPE_MEDIUM
## The main dock's button row; the view toggles join it. DockUI sets it before adding
## the HUD.
var view_row: Control
var speed_buttons: Dictionary = {}
var step_buttons: Dictionary = {}
var slice_button: Button
var time_panel: Panel
var tower: Panel
var readout: Label
var level_label: Label
var _plate: Panel
var _slice: Node
var _xray: Node
var _appeal: Node
var appeal_button: Button
var appeal_panel: PanelContainer
var _appeal_labels: Array[Label] = []
var _appeal_swatches: Array[ColorRect] = []
var xray_button: Button
var xray_panel: PanelContainer
var xray_modes: Dictionary = {}
var reference_toggle: CheckButton
var reference_pin: Button
var reference_readout: Label
var _options_anchor := Vector2.ZERO   # bottom-right corner for the X-ray options


func _ready() -> void:
	add_to_group("time_slice_hud")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UITheme.apply_surface(self)
	time_panel = _panel()
	# Windows step aside from the dial and the time controls under it together.
	time_panel.add_to_group("sky_dial_extension")
	tower = _panel()
	tower.gui_input.connect(_on_tower_input)
	var entries: Dictionary = UIRegistry.get_time_slice().get("buttons", {})
	var ids := ["pause", "play", "fast"]
	for speed in range(3):
		var button := _button(entries[ids[speed]], time_panel)
		button.pressed.connect(func(): speed_requested.emit(speed))
		speed_buttons[speed] = button
	var views: Control = view_row if view_row != null else self
	appeal_button = _button(entries.appeal, views)
	appeal_button.pressed.connect(func(): if is_instance_valid(_appeal): _appeal.toggle())
	appeal_button.hide()
	xray_button = _button(entries.xray, views)
	xray_button.pressed.connect(func(): if is_instance_valid(_xray): _xray.toggle())
	xray_button.hide()
	slice_button = _button(entries.slice, views)
	slice_button.pressed.connect(func(): slice_toggle_requested.emit())
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
	level_label = _label(MEDIUM.small)
	level_label.text = "LEVEL"
	level_label.add_theme_color_override("font_color", UITheme.HEARTH_COPPER)
	readout = _label(MEDIUM.title)
	UITheme.apply_title(readout, MEDIUM.title)
	readout.add_theme_font_override("font", UITheme.font("figures"))   # the level steps with the slice
	_build_xray()
	_build_appeal()
	refresh_slice()


## Space pauses and resumes before a focused button can take it as a press. A text field
## keeps it, and it does nothing while the clock is held (the game menu, loading).
func _input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"time_pause", false, true) or WorldClock.is_loading_held(): return
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit: return
	speed_requested.emit(0)
	get_viewport().set_input_as_handled()


## The speed and view keys, after text fields and the game menu have taken theirs.
func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"time_normal", false, true): speed_requested.emit(1)
	elif event.is_action_pressed(&"time_fast", false, true): speed_requested.emit(2)
	elif event.is_action_pressed(&"view_appeal", false, true) and is_instance_valid(_appeal): _appeal.toggle()
	elif event.is_action_pressed(&"view_xray", false, true) and is_instance_valid(_xray): _xray.toggle()
	else: return
	get_viewport().set_input_as_handled()


func _build_xray() -> void:
	xray_panel = PanelContainer.new()
	xray_panel.add_theme_stylebox_override("panel",UITheme.hearth_panel(true))
	xray_panel.hide()
	add_child(xray_panel)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation",3)
	xray_panel.add_child(body)
	var modes := HBoxContainer.new()
	body.add_child(modes)
	for id in ["full","flat"]:
		var button := Button.new()
		button.text = id.capitalize()
		button.toggle_mode = true
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.tooltip_text = "Show underground floors and walls." if id=="full" else "Show floors and low walls for a clearer floor plan."
		button.pressed.connect(func(): if is_instance_valid(_xray): _xray.set_mode(id))
		modes.add_child(button)
		xray_modes[id] = button
	reference_toggle = CheckButton.new()
	reference_toggle.text = "Guide"
	reference_toggle.tooltip_text = "Project the pinned lower room and stair outlines onto the work level."
	reference_toggle.toggled.connect(func(on: bool): if is_instance_valid(_xray): _xray.set_reference_enabled(on))
	body.add_child(reference_toggle)
	reference_pin = Button.new()
	reference_pin.text = "Pin guide here"
	reference_pin.tooltip_text = "Remember this level before moving upward. The dashed guide follows known floors and steps below it."
	reference_pin.pressed.connect(func(): if is_instance_valid(_xray): _xray.pin_reference())
	body.add_child(reference_pin)
	reference_readout = Label.new()
	reference_readout.add_theme_font_size_override("font_size",MEDIUM.small)
	reference_readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reference_readout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(reference_readout)
	for control in [reference_pin,reference_toggle,xray_modes.full,xray_modes.flat]:
		control.add_theme_font_size_override("font_size",MEDIUM.small)


## The Appeal view's scale (doc 23 "The Appeal view"): each word with its tint and range,
## highest first, above the dock while the view is on, as X-ray's options are.
func _build_appeal() -> void:
	appeal_panel = PanelContainer.new()
	appeal_panel.add_theme_stylebox_override("panel", UITheme.hearth_panel(true))
	appeal_panel.hide()
	add_child(appeal_panel)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 4)
	appeal_panel.add_child(body)
	var words: Array = RoomManager.appeal_config.get("words", [])
	for i in range(words.size() - 1, -1, -1):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		body.add_child(row)
		var swatch := ColorRect.new()
		swatch.color = Color(String(words[i].get("tint", "#9a978b")))
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(swatch)
		_appeal_swatches.append(swatch)
		for text: String in [String(words[i].word), _appeal_range(words, i)]:
			var label := Label.new()
			label.text = text
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(label)
			_appeal_labels.append(label)
	var hint := Label.new()
	hint.text = "Hover a room for its appeal.\nClick it for the room."
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(hint)
	_appeal_labels.append(hint)
	_size_appeal(MEDIUM.body)


## The scores a word holds: "below 0", "0 to 8", "16 and up".
static func _appeal_range(words: Array, index: int) -> String:
	var number := func(value: Variant) -> String: return ("%.1f" % float(value)).trim_suffix(".0")
	if index == 0: return "below %s" % number.call(words[0].below)
	if index == words.size() - 1: return "%s and up" % number.call(words[index - 1].below)
	return "%s to %s" % [number.call(words[index - 1].below), number.call(words[index].below)]


func _size_appeal(font_size: int) -> void:
	for i in range(_appeal_labels.size()):
		var label := _appeal_labels[i]
		var word := i < _appeal_labels.size() - 1 and i % 2 == 0
		UITheme.format_label(label, word, font_size if word else font_size - 1, UITheme.CARD_TITLE if word else UITheme.CARD_TEXT)
		label.custom_minimum_size.x = float(font_size) * 5.6 if word else 0.0
	for swatch: ColorRect in _appeal_swatches: swatch.custom_minimum_size = Vector2.ONE * float(font_size + 4)


func bind_appeal(controller: Node) -> void:
	_appeal = controller
	_appeal.changed.connect(refresh_appeal)
	appeal_button.show()
	refresh_appeal()


func refresh_appeal() -> void:
	if not is_instance_valid(_appeal): return
	var on: bool = _appeal.active
	appeal_button.set_pressed_no_signal(on)
	appeal_button.queue_redraw()
	appeal_panel.visible = on
	_place_options()


func bind_xray(controller: Node) -> void:
	_xray = controller
	_xray.changed.connect(refresh_xray)
	xray_button.show()
	refresh_xray()


func refresh_xray() -> void:
	if not is_instance_valid(_xray): return
	var active: bool = _xray.mode!="off"
	xray_button.set_pressed_no_signal(active)
	xray_button.queue_redraw()
	xray_panel.visible = active
	_place_options()
	for id in xray_modes:
		xray_modes[id].set_pressed_no_signal(_xray.mode==id)
	reference_toggle.set_pressed_no_signal(_xray.show_reference)
	if _xray.working: reference_readout.text = "Normal view while a tool works"
	elif _xray.show_reference: reference_readout.text = "Guide: level %d" % _xray.reference_y
	else: reference_readout.text = "Guide hidden"


## The X-ray options sit above the dock, left of the slice tower, and the Appeal view's scale
## beside them (left of X-ray's while both are open).
func _place_options() -> void:
	var right := _options_anchor.x
	for panel: PanelContainer in [xray_panel, appeal_panel]:
		if panel == null: continue
		var minimum := panel.get_combined_minimum_size()
		panel.size = Vector2(maxf(minimum.x, 240.0) if panel == xray_panel else minimum.x, minimum.y)
		panel.position = Vector2(right - panel.size.x, _options_anchor.y - panel.size.y)
		if panel.visible: right = panel.position.x - 8.0


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
	var height := int(_slice.get_slice_y()) if active else SliceController.MAX_SLICE_Y
	slice_button.set_pressed_no_signal(active)
	slice_button.disabled = not is_instance_valid(_slice)
	# The arrows and level show only while slicing.
	tower.visible = active
	readout.text = str(height)
	for id: String in step_buttons:
		var button: Button = step_buttons[id]
		button.disabled = not active or (height >= SliceController.MAX_SLICE_Y if id.begins_with("up") else height <= SliceController.MIN_SLICE_Y)
		button.queue_redraw()
	slice_button.queue_redraw()
	refresh_xray()


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


## Places the time controls under the Sky Dial and the tower and X-ray options above
## the Slice button. `main_dock` and `sky_dial` are global rects. The view toggles
## themselves are laid out by the dock row.
func fit_to_viewport(main_dock: Rect2, sky_dial: Rect2) -> void:
	position = Vector2.ZERO
	size = get_viewport_rect().size
	# Time controls: centred directly under the Sky Dial.
	var side := 64.0 if sky_dial.size.x >= 220.0 else (56.0 if sky_dial.size.x >= 200.0 else 48.0)
	time_panel.size = Vector2(side * 3 + 20, side + 12)
	time_panel.position = Vector2(sky_dial.position.x + (sky_dial.size.x - time_panel.size.x) * 0.5, sky_dial.end.y + 8)
	for speed: int in speed_buttons:
		speed_buttons[speed].position = Vector2(6 + speed * (side + 4), 6)
		speed_buttons[speed].size = Vector2.ONE * side
	# The slice tower rises above the Slice button, as wide as it. On short screens it
	# would reach the clock column (the Sky Dial and the time controls), so its steps
	# shrink (down to 24) to stay clear.
	var slice_rect := slice_button.get_global_rect()
	var width := slice_rect.size.x
	var step_height := 28.0 if width < 56.0 else 36.0
	var tower_x := slice_rect.position.x - 6
	var column := sky_dial.merge(Rect2(time_panel.position, time_panel.size))
	if tower_x < column.end.x and tower_x + width + 12 > column.position.x:
		var room := main_dock.position.y - 4 - (column.end.y + 8)
		step_height = clampf(floorf((room - 64) / 4), 24.0, step_height)
	var tower_height := step_height * 4 + 64
	tower.size = Vector2(width + 12, tower_height)
	tower.position = Vector2(tower_x, main_dock.position.y - 4 - tower_height)
	for index in range(4):
		var button: Button = step_buttons[["up_four", "up_one", "down_one", "down_four"][index]]
		button.position = Vector2(6, 6 + index * (step_height + 2) + (48 if index >= 2 else 0))
		button.size = Vector2(width, step_height)
	_plate.position = Vector2(6, 6 + 2 * (step_height + 2))
	_plate.size = Vector2(width, 46)
	level_label.position = Vector2.ZERO
	level_label.size = Vector2(width, 16)
	readout.position = Vector2(0, 14)
	readout.size = Vector2(width, 32)
	_options_anchor = Vector2(tower.position.x - 8, main_dock.position.y - 4)
	# The scale reads at the dock's own size.
	if appeal_panel != null: _size_appeal(clampi(roundi(width * 0.24), MEDIUM.small, MEDIUM.heading))
	_place_options()
	refresh_slice()


func occupied_rects() -> Array[Rect2]:
	var result: Array[Rect2] = [time_panel.get_global_rect()]
	if tower.visible: result.append(tower.get_global_rect())
	if xray_panel.visible: result.append(xray_panel.get_global_rect())
	if appeal_panel.visible: result.append(appeal_panel.get_global_rect())
	return result
