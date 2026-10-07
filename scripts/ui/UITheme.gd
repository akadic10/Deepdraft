class_name UITheme
extends RefCounted

## Single owner of Hearth & iron: palette, typography and Control styles.
## Theme resources are built once in code; no .tres or per-window palette copies.
const HEARTH_BG := Color("202827")
const HEARTH_CARD := Color("283230")
const HEARTH_EDGE := Color("5b5548")
const HEARTH_COPPER := Color("d2a06b")
const HEARTH_TEXT := Color("f2eadb")
const HEARTH_MUTED := Color("bdb8a9")
const HOVER_BG := Color("39433b")
const PRESSED_BG := Color("544331")
const DISABLED_BG := Color("232c29")
const TEXT_DISABLED := Color("92998e")
const TRACK_BG := Color("151c1b")
const SUCCESS := Color("9cbe8c")
const DEV_ORANGE := Color("e1ac70")
const DEV_ORANGE_HOVER := Color("f3c58f")
const DANGER_RED := Color("ee9a88")
const WINDOW_BG := HEARTH_BG
const WINDOW_BORDER := HEARTH_EDGE
const TITLEBAR_BG := HEARTH_CARD
const ACCENT_FILL := PRESSED_BG
const ACCENT_BORDER := HEARTH_COPPER
const TEXT_DIM := HEARTH_MUTED
const RADIUS := 3
const FONT_TITLE := 17
const FONT_BODY := 14
const FONT_SMALL := 13
const CATALOG_PAPER := Color("e9d8b5")
const CATALOG_INK := Color("3b342a")
const CATALOG_MUTED := Color("68583e")
const CATALOG_WOOD := Color("504634")
const CATALOG_GOLD := Color("d0af76")

static var _shared_theme: Theme
static var _heading_font: Font


static func style(bg: Color, border: Color, border_width: int, radius: int,
		content_margin_h: float = 8.0, content_margin_v: float = 6.0) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(border_width)
	box.set_corner_radius_all(radius)
	if content_margin_h >= 0.0:
		box.content_margin_left = content_margin_h
		box.content_margin_right = content_margin_h
	if content_margin_v >= 0.0:
		box.content_margin_top = content_margin_v
		box.content_margin_bottom = content_margin_v
	return box


static func shared_theme() -> Theme:
	if _shared_theme != null:
		return _shared_theme
	var theme := Theme.new()
	var body_font := SystemFont.new()
	body_font.font_names = PackedStringArray(["Segoe UI", "Noto Sans", "DejaVu Sans"])
	theme.default_font = body_font
	theme.default_font_size = FONT_BODY
	theme.set_color("font_color", "Label", HEARTH_TEXT)
	theme.set_color("default_color", "RichTextLabel", HEARTH_TEXT)
	theme.set_font_size("font_size", "Button", FONT_SMALL)
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		theme.set_color(state, "Button", HEARTH_TEXT)
	theme.set_color("font_disabled_color", "Button", TEXT_DISABLED)
	theme.set_stylebox("normal", "Button", button_normal_style())
	theme.set_stylebox("hover", "Button", button_hover_style())
	theme.set_stylebox("pressed", "Button", button_pressed_style())
	theme.set_stylebox("hover_pressed", "Button", button_pressed_style())
	theme.set_stylebox("disabled", "Button", button_disabled_style())
	theme.set_stylebox("focus", "Button", focus_style())
	theme.set_stylebox("panel", "PanelContainer", window_style())
	theme.set_stylebox("panel", "TooltipPanel", style(HEARTH_BG, HEARTH_COPPER, 1, RADIUS, 12, 8))
	theme.set_color("font_color", "TooltipLabel", HEARTH_TEXT)
	theme.set_font_size("font_size", "TooltipLabel", FONT_SMALL)
	for separator_type: String in ["HSeparator", "VSeparator"]:
		var line := StyleBoxLine.new()
		line.color = HEARTH_EDGE
		line.thickness = 1
		line.vertical = separator_type == "VSeparator"
		theme.set_stylebox("separator", separator_type, line)
		theme.set_constant("separation", separator_type, 8)
	for scroll_type: String in ["VScrollBar", "HScrollBar"]:
		theme.set_stylebox("scroll", scroll_type, style(TRACK_BG, Color.TRANSPARENT, 0, RADIUS, 4, 4))
		theme.set_stylebox("scroll_focus", scroll_type, style(TRACK_BG, HEARTH_COPPER, 1, RADIUS, 4, 4))
		theme.set_stylebox("grabber", scroll_type, style(HEARTH_EDGE, Color.TRANSPARENT, 0, RADIUS, 4, 4))
		theme.set_stylebox("grabber_highlight", scroll_type, style(HEARTH_COPPER, Color.TRANSPARENT, 0, RADIUS, 4, 4))
		theme.set_stylebox("grabber_pressed", scroll_type, style(HEARTH_COPPER, Color.TRANSPARENT, 0, RADIUS, 4, 4))
	theme.set_stylebox("background", "ProgressBar", style(TRACK_BG, Color.TRANSPARENT, 0, 2, 0, 0))
	theme.set_stylebox("fill", "ProgressBar", style(HEARTH_COPPER, Color.TRANSPARENT, 0, 2, 0, 0))
	_shared_theme = theme
	return theme


## Apply at the root Control, so dynamically added children inherit it too.
static func apply_surface(control: Control) -> void:
	control.theme = shared_theme()
	control.mouse_force_pass_scroll_events = false


static func hearth_title_font() -> Font:
	if _heading_font == null:
		var font := SystemFont.new()
		font.font_names = PackedStringArray(["Georgia", "Noto Serif", "DejaVu Serif"])
		_heading_font = font
	return _heading_font


static func apply_title(label: Label, font_size: int = FONT_TITLE) -> void:
	label.add_theme_font_override("font", hearth_title_font())
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", HEARTH_TEXT)


static func window_style() -> StyleBoxFlat:
	return style(WINDOW_BG, WINDOW_BORDER, 1, RADIUS, 0, 0)


static func storage_item_style(selected: bool = false) -> StyleBoxFlat:
	return style(PRESSED_BG if selected else HEARTH_CARD,
		HEARTH_COPPER if selected else HEARTH_EDGE, 2 if selected else 1, RADIUS, 7, 5)


static func titlebar_style() -> StyleBoxFlat:
	var box := style(TITLEBAR_BG, Color.TRANSPARENT, 0, 0, 0, 0)
	box.corner_radius_top_left = RADIUS - 1
	box.corner_radius_top_right = RADIUS - 1
	return box


static func apply_close_button(button: Button) -> void:
	button.text = "×"
	button.focus_mode = Control.FOCUS_ALL
	button.custom_minimum_size = Vector2(28, 24)
	button.tooltip_text = "Close"
	button.add_theme_font_size_override("font_size", 14)
	button.add_theme_color_override("font_color", HEARTH_MUTED)
	button.add_theme_stylebox_override("normal", style(Color.TRANSPARENT, HEARTH_EDGE, 1, RADIUS, 6, 0))
	button.add_theme_stylebox_override("hover", style(HOVER_BG, HEARTH_COPPER, 1, RADIUS, 6, 0))
	button.add_theme_stylebox_override("pressed", style(PRESSED_BG, HEARTH_COPPER, 1, RADIUS, 6, 0))
	button.add_theme_stylebox_override("hover_pressed", button.get_theme_stylebox("pressed"))
	button.add_theme_stylebox_override("focus", focus_style())


static func button_normal_style() -> StyleBoxFlat:
	return style(HEARTH_CARD, HEARTH_EDGE, 1, RADIUS, 8, 5)


static func button_hover_style() -> StyleBoxFlat:
	return style(HOVER_BG, HEARTH_COPPER, 1, RADIUS, 8, 5)


static func button_pressed_style() -> StyleBoxFlat:
	return style(PRESSED_BG, HEARTH_COPPER, 1, RADIUS, 8, 5)


static func button_disabled_style() -> StyleBoxFlat:
	return style(DISABLED_BG, Color("424940"), 1, RADIUS, 8, 5)


static func focus_style() -> StyleBoxFlat:
	return style(Color.TRANSPARENT, HEARTH_COPPER, 2, RADIUS, 0, 0)


static func apply_button_variant(button: Button, variant: String = "") -> void:
	var color := HEARTH_TEXT
	if variant == "dev": color = DEV_ORANGE
	elif variant == "danger": color = DANGER_RED
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		button.add_theme_color_override(state, color)
	button.add_theme_color_override("font_disabled_color", TEXT_DISABLED)


static func make_button(text: String, tooltip: String = "",
		min_size: Vector2 = Vector2(100, 30), variant: String = "") -> Button:
	var button := Button.new()
	button.theme = shared_theme()
	button.text = text
	button.tooltip_text = tooltip
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = min_size
	apply_button_variant(button, variant)
	return button


static func dock_button_normal_style() -> StyleBoxFlat:
	return style(Color.TRANSPARENT, Color.TRANSPARENT, 0, RADIUS)


static func dock_button_hover_style() -> StyleBoxFlat:
	return style(HOVER_BG, HEARTH_EDGE, 1, RADIUS)


static func dock_button_active_style() -> StyleBoxFlat:
	return style(ACCENT_FILL, ACCENT_BORDER, 2, RADIUS)


static func hud_panel_style(bg_alpha: float = .97) -> StyleBoxFlat:
	return style(Color(HEARTH_BG, bg_alpha), HEARTH_EDGE, 1, RADIUS)


static func dock_panel_style() -> StyleBoxFlat:
	return style(Color(HEARTH_BG, .96), HEARTH_EDGE, 1, RADIUS)


static func toast_style(is_error: bool) -> StyleBoxFlat:
	return style(HEARTH_BG, DANGER_RED if is_error else SUCCESS, 1, RADIUS)


static func hearth_panel(inset: bool = false) -> StyleBoxFlat:
	return style(HEARTH_CARD if inset else HEARTH_BG, HEARTH_EDGE, 1, RADIUS,
		12.0 if inset else 0.0, 10.0 if inset else 0.0)


static func apply_hearth_button(button: Button, primary: bool = false) -> void:
	button.theme = shared_theme()
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_size_override("font_size", FONT_BODY)
	apply_button_variant(button)
	button.add_theme_stylebox_override("normal", style(PRESSED_BG if primary else HEARTH_CARD,
		HEARTH_COPPER if primary else HEARTH_EDGE, 1, RADIUS, 12, 7))
	button.add_theme_stylebox_override("hover", style(HOVER_BG, HEARTH_COPPER, 1, RADIUS, 12, 7))
	button.add_theme_stylebox_override("pressed", style(PRESSED_BG, HEARTH_COPPER, 1, RADIUS, 12, 7))


static func hearth_progress(bar: ProgressBar) -> void:
	bar.theme = shared_theme()
	bar.show_percentage = false
	bar.custom_minimum_size.y = 5


static func catalog_paper_style(compact: bool = false) -> StyleBoxFlat:
	return style(CATALOG_PAPER, Color("af946b"), 1, 1, 12, 6 if compact else 10)


static func orders_panel_style(banner: bool = false) -> StyleBoxFlat:
	var box := style(HEARTH_BG, HEARTH_COPPER if banner else HEARTH_EDGE, 1, 2, 14, 12)
	if banner: box.border_width_top = 3
	box.shadow_color = Color(0.08, 0.12, 0.10, .28)
	box.shadow_size = 3
	box.shadow_offset = Vector2(0, 3)
	return box


static func catalog_item_style(selected: bool = false) -> StyleBoxFlat:
	return style(Color("655339") if selected else HEARTH_CARD,
		CATALOG_GOLD if selected else HEARTH_EDGE, 2 if selected else 1, 2, 6, 6)


static func apply_catalog_window(window: UIWindow) -> void:
	window.add_theme_stylebox_override("panel", style(HEARTH_BG, CATALOG_GOLD, 2, 2, 0, 0))
	window._title_bar.add_theme_stylebox_override("panel", style(CATALOG_WOOD, HEARTH_EDGE, 1, 0, 0, 0))
	UITheme.apply_title(window._title_label, 22)
	for side: String in ["left", "right", "top", "bottom"]:
		window._body_slot.add_theme_constant_override("margin_" + side, 0)


static func apply_catalog_primary(button: Button) -> void:
	apply_hearth_button(button, true)
	button.add_theme_stylebox_override("normal", style(CATALOG_GOLD, Color("80613c"), 1, 1, 10, 7))
	button.add_theme_stylebox_override("hover", style(Color("e0c28d"), Color("80613c"), 1, 1, 10, 7))
	button.add_theme_stylebox_override("pressed", style(Color("c5a068"), Color("80613c"), 1, 1, 10, 7))
	button.add_theme_stylebox_override("hover_pressed", button.get_theme_stylebox("pressed"))
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, CATALOG_INK)
