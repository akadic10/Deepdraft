class_name UIWindow
extends PanelContainer

## The shared Hearth & iron window chrome (docs 24/51).
##
## Structure: title bar (emoji + title, drag surface) + close button +
## a content slot the owning system fills. Behaviour: drag by the title bar
## (viewport-clamped so the bar can never leave the screen), click anywhere to
## request focus (front-most), close hides — never frees — so content state and
## position survive reopen.
##
## Never instance this directly from game systems: UIWindowManager.register_window()
## is the only constructor call site. Owners keep the returned reference to
## update their content and title.
##
## New `class_name` — after pulling this change, run Project → Reload Current
## Project once.

## Emitted on any mouse-down inside the window; the manager raises it on top.
signal focus_requested(window: UIWindow)

## Emitted by the close button. The manager owns hide + bookkeeping — this
## window never hides itself.
signal close_pressed(window: UIWindow)

## Emitted when a title-bar drag finishes; the manager persists the position.
signal drag_ended(window: UIWindow)

const TITLEBAR_HEIGHT := 34.0
const VIEWPORT_MARGIN := 4.0

var window_id: String = ""
## Persistent windows (doc 24 §2) restore their open state at startup; context
## windows never do. The manager reads this flag; the window itself only
## carries it.
var persistent: bool = false

var _title_label: Label = null
var _body_slot: MarginContainer = null
var _content: Control = null
var _pending_title: String = ""
var _dragging: bool = false
var keep_body_on_screen := false
var _title_bar: PanelContainer
var _close_button: Button


func _ready() -> void:
	UITheme.apply_surface(self)
	add_theme_stylebox_override("panel", UITheme.window_style())

	# 1px inset so the body never paints over the border (the World Build
	# window's proven layout).
	var outer := MarginContainer.new()
	outer.add_theme_constant_override("margin_left", 1)
	outer.add_theme_constant_override("margin_right", 1)
	outer.add_theme_constant_override("margin_top", 1)
	outer.add_theme_constant_override("margin_bottom", 1)
	add_child(outer)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	outer.add_child(column)

	var title_bar := PanelContainer.new()
	_title_bar = title_bar
	title_bar.name = "TitleBar"
	title_bar.custom_minimum_size = Vector2(0.0, TITLEBAR_HEIGHT)
	title_bar.mouse_default_cursor_shape = Control.CURSOR_MOVE
	title_bar.add_theme_stylebox_override("panel", UITheme.titlebar_style())
	title_bar.gui_input.connect(_on_title_bar_gui_input)
	column.add_child(title_bar)

	var title_margin := MarginContainer.new()
	title_margin.add_theme_constant_override("margin_left", 10)
	title_margin.add_theme_constant_override("margin_right", 8)
	title_margin.add_theme_constant_override("margin_top", 4)
	title_margin.add_theme_constant_override("margin_bottom", 4)
	title_bar.add_child(title_margin)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	title_margin.add_child(header)

	_title_label = Label.new()
	_title_label.text = _pending_title
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UITheme.apply_title(_title_label)
	header.add_child(_title_label)

	var close := Button.new()
	_close_button = close
	close.name = "CloseButton"
	close.text = "X"
	UITheme.apply_close_button(close)
	close.pressed.connect(func() -> void:
		close_pressed.emit(self)
	)
	header.add_child(close)

	_body_slot = MarginContainer.new()
	_body_slot.name = "Body"
	_body_slot.add_theme_constant_override("margin_left", 14)
	_body_slot.add_theme_constant_override("margin_right", 14)
	_body_slot.add_theme_constant_override("margin_top", 10)
	_body_slot.add_theme_constant_override("margin_bottom", 12)
	column.add_child(_body_slot)

	if _content != null and _content.get_parent() == null:
		_body_slot.add_child(_content)

	gui_input.connect(_on_window_gui_input)


## Sets the title-bar text. Safe before or after _ready.
func set_window_title(title: String, emoji: String = "") -> void:
	var text := ("%s  %s" % [emoji, title]) if not emoji.is_empty() else title
	if _title_label == null:
		_pending_title = text
		return
	_title_label.text = text


## Installs the owner-built content Control. Replaces any previous content
## (the old content is freed — owners that swap content rebuild it fresh).
func set_content(content: Control) -> void:
	if _content != null and is_instance_valid(_content) and _content != content:
		_content.queue_free()
	_content = content
	if _body_slot != null and content.get_parent() == null:
		_body_slot.add_child(content)
	reset_size()


func get_content() -> Control:
	return _content


## Keeps the title bar reachable whatever the viewport does (drag, resize,
## restored layout from a larger monitor).
func clamp_to_viewport() -> void:
	var vp := get_viewport_rect().size
	var window_size := size
	position.x = clampf(position.x, VIEWPORT_MARGIN,
			maxf(VIEWPORT_MARGIN, vp.x - window_size.x - VIEWPORT_MARGIN))
	position.y = clampf(position.y, VIEWPORT_MARGIN,
			maxf(VIEWPORT_MARGIN, vp.y - (window_size.y if keep_body_on_screen else TITLEBAR_HEIGHT) - VIEWPORT_MARGIN))


# ── Input ─────────────────────────────────────────────────────────────────────

func _on_title_bar_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_LEFT:
			var was_dragging := _dragging
			_dragging = mouse.pressed
			if mouse.pressed:
				focus_requested.emit(self)
			elif was_dragging:
				clamp_to_viewport()
				drag_ended.emit(self)
	elif event is InputEventMouseMotion and _dragging:
		var motion := event as InputEventMouseMotion
		position += motion.relative
		clamp_to_viewport()


func _on_window_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		focus_requested.emit(self)
