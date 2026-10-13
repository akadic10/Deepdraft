extends Button

## Illustrated dock command. The approved artwork stays in one shared atlas;
## its region, caption and action are supplied by UIRegistry/DockUI.
var caption: String
var description: String
var _hovered := false
var _info_suppressed := false
var _info_timer: Timer
var _info_layer: CanvasLayer
var _info: PanelContainer


func setup(entry: Dictionary, artwork: Texture2D) -> void:
	caption = String(entry.label)
	description = String(entry.get("tooltip", entry.label))
	icon = artwork
	text = ""
	focus_mode = Control.FOCUS_ALL
	toggle_mode = true
	expand_icon = true
	icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
		add_theme_color_override("icon_" + state + "_color", Color.WHITE)
	add_theme_color_override("icon_hover_color", Color(1.10, 1.10, 1.10))


func _ready() -> void:
	_info_timer = Timer.new()
	_info_timer.one_shot = true
	_info_timer.wait_time = 0.3
	add_child(_info_timer)
	_info_timer.timeout.connect(_show_info)
	mouse_entered.connect(func():
		_hovered = true
		_info_suppressed = false
		_info_timer.start()
		queue_redraw())
	mouse_exited.connect(func():
		_hovered = false
		_hide_info()
		queue_redraw())
	focus_entered.connect(func():
		_info_suppressed = false
		_info_timer.start()
		queue_redraw())
	focus_exited.connect(_hide_info)
	pressed.connect(func():
		_info_suppressed = true
		_hide_info())
	toggled.connect(func(_on: bool): queue_redraw())
	resized.connect(_hide_info)
	visibility_changed.connect(_hide_info)


func _draw() -> void:
	if not button_pressed and not _hovered and not has_focus(): return
	var edge := UITheme.HEARTH_COPPER if button_pressed else UITheme.HEARTH_TEXT
	var inset := 3.0
	var cut := size.x * 0.08
	var x := size.x - inset
	var y := size.y - inset
	var points := PackedVector2Array([
		Vector2(inset + cut, inset), Vector2(x - cut, inset),
		Vector2(x, inset + cut), Vector2(x, y - cut),
		Vector2(x - cut, y), Vector2(inset + cut, y),
		Vector2(inset, y - cut), Vector2(inset, inset + cut),
		Vector2(inset + cut, inset)])
	draw_polyline(points, edge, 2.0 if button_pressed else 1.0, true)
	if button_pressed:
		# A solid notch also distinguishes the active command without color.
		var center := Vector2(size.x * 0.5, size.y - 4)
		draw_colored_polygon(PackedVector2Array([center + Vector2(-7, 0),
			center + Vector2(0, -5), center + Vector2(7, 0)]), UITheme.HEARTH_COPPER)


func _hide_info() -> void:
	if _info_timer != null: _info_timer.stop()
	if _info != null: _info.hide()
	queue_redraw()


func _show_info() -> void:
	if _info_suppressed or not is_visible_in_tree() or not (_hovered or has_focus()): return
	if _info == null:
		_info_layer = CanvasLayer.new()
		_info_layer.layer = 30
		add_child(_info_layer)
		_info = PanelContainer.new()
		_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
		UITheme.apply_surface(_info)
		_info.add_theme_stylebox_override("panel", UITheme.dock_tooltip_style())
		_info_layer.add_child(_info)
		var body := VBoxContainer.new()
		body.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.add_theme_constant_override("separation", 4)
		_info.add_child(body)
		var title := Label.new()
		title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		title.text = caption
		UITheme.apply_title(title)
		body.add_child(title)
		var detail := Label.new()
		detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
		detail.text = description
		detail.custom_minimum_size.x = 244
		detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_child(detail)
	_info.show()
	_info.reset_size()
	call_deferred("_position_info")


func _position_info() -> void:
	var bounds := get_global_rect()
	var viewport := get_viewport_rect().size
	_info.position = Vector2(clampf(bounds.get_center().x - _info.size.x * 0.5,
		8, maxf(8, viewport.x - _info.size.x - 8)), maxf(8, bounds.position.y - _info.size.y - 10))
