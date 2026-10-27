class_name UIWindow
extends PanelContainer

## The shared window chrome (docs 24/51), in Deepdraft's Hearthblock style (doc 261): the
## voxel slab with a title band in the window's family colour and a stone keycap to close.
##
## Structure: title bar (emoji + title, drag surface, drawn on the band) + close button +
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

# Text sizes come from the type scale (doc 23, "Type").
const MEDIUM := UITheme.TYPE_MEDIUM
## Emitted on any mouse-down inside the window; the manager raises it on top.
signal focus_requested(window: UIWindow)

## Emitted by the close button. The manager owns hide + bookkeeping — this
## window never hides itself.
signal close_pressed(window: UIWindow)

## Emitted when a title-bar drag finishes; the manager persists the position.
signal drag_ended(window: UIWindow)

const TITLEBAR_HEIGHT := float(UITheme.WINDOW_BAND_ROWS * UITheme.CARD_CELL)   # exactly the band
const VIEWPORT_MARGIN := 4.0

var window_id: String = ""
## Persistent windows (doc 24 §2) restore their open state at startup; context
## windows never do. The manager reads this flag; the window itself only
## carries it.
var persistent: bool = false
## The family whose colour the title band wears (work, settlement, people, system, dev),
## from register_window()'s "family" option. Set before the window enters the tree.
var family := ""
## The content fills the body to its edges and brings its own margins.
var flush := false

var _title_label: Label = null
var _body_slot: MarginContainer = null
var _content: Control = null
var _pending_title: String = ""
var _dragging: bool = false
var keep_body_on_screen := false
var _title_bar: PanelContainer
var _close_button: Button


func _ready() -> void:
	# The registry is fetched from the tree, so scripts that preload windows still compile.
	var registry: Node = get_tree().root.get_node_or_null("UIRegistry")
	var band: Color = registry.get_icon_family_color(family) if registry != null and not family.is_empty() else Color.TRANSPARENT
	# The family theme dresses the contents' shown tabs, main actions and pictures.
	theme = UITheme.family_theme(band)
	mouse_force_pass_scroll_events = false
	add_theme_stylebox_override("panel", UITheme.window_frame(band))

	# The frame's margins keep the body off its outline and skirt; the title bar covers
	# the band, so the body starts under the band's seam.
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	add_child(column)

	var title_bar := PanelContainer.new()
	_title_bar = title_bar
	title_bar.name = "TitleBar"
	title_bar.custom_minimum_size = Vector2(0.0, TITLEBAR_HEIGHT)
	title_bar.mouse_default_cursor_shape = Control.CURSOR_MOVE
	title_bar.add_theme_stylebox_override("panel", StyleBoxEmpty.new())   # the band is the frame's
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
	UITheme.format_label(_title_label, true, MEDIUM.name, UITheme.CARD_TITLE, 6)
	_title_label.add_theme_color_override("font_outline_color", UITheme.CARD_TITLE_OUTLINE)
	header.add_child(_title_label)

	var close := Button.new()
	_close_button = close
	close.name = "CloseButton"
	UITheme.apply_close_button(close)
	close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(func() -> void:
		close_pressed.emit(self)
	)
	header.add_child(close)

	_body_slot = MarginContainer.new()
	_body_slot.name = "Body"
	_body_slot.add_theme_constant_override("margin_left", 0 if flush else 14)
	_body_slot.add_theme_constant_override("margin_right", 0 if flush else 14)
	_body_slot.add_theme_constant_override("margin_top", 0 if flush else 10)
	_body_slot.add_theme_constant_override("margin_bottom", 0 if flush else 12)
	column.add_child(_body_slot)

	if _content != null and _content.get_parent() == null:
		_body_slot.add_child(_content)

	gui_input.connect(_on_window_gui_input)


func get_title_bar() -> PanelContainer: return _title_bar
func get_title_label() -> Label: return _title_label
func get_body_slot() -> MarginContainer: return _body_slot


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
	# Content themed before it reached the window would hide the family theme.
	if content.theme == UITheme.shared_theme():
		content.theme = null
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
	var dial := get_tree().get_first_node_in_group("sky_dial") as Control
	if dial != null and dial.is_visible_in_tree():
		var reserved := dial.get_global_rect()
		# The time controls hang under the dial (doc 259); windows clear both.
		for extension: Control in get_tree().get_nodes_in_group("sky_dial_extension"):
			if extension.is_visible_in_tree(): reserved = reserved.merge(extension.get_global_rect())
		reserved = reserved.grow(8)
		if get_global_rect().intersects(reserved):
			if window_size.x <= reserved.position.x - VIEWPORT_MARGIN:
				position.x = reserved.position.x - window_size.x
			elif window_size.y <= vp.y - reserved.end.y - VIEWPORT_MARGIN:
				position.y = reserved.end.y
			# Wide/tall browsers at small resolutions keep their full usable
			# area and normal window priority above the status layer.


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
