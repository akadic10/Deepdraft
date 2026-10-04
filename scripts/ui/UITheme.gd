class_name UITheme
extends RefCounted

## Single owner of the UI visual language (doc 24, Phase U1).
##
## Every window, panel, and in-window button stylebox comes from here. No other
## script may hand-build a StyleBoxFlat for window chrome — the eight drifted
## `_style()` copies this class replaces are exactly the failure mode it exists
## to prevent (doc 24 §1.2 finding 5).
##
## All functions are static; never instance this class. New `class_name` — after
## pulling this change, run Project → Reload Current Project once.

# ── Palette (canonical values; the pre-U1 code had drifted variants) ──────────

const WINDOW_BG := Color(0.065, 0.070, 0.075, 0.94)
const WINDOW_BORDER := Color(1, 1, 1, 0.14)
const TITLEBAR_BG := Color(0.12, 0.13, 0.14, 0.98)

const ACCENT_FILL := Color(0.45, 0.72, 1.0, 0.25)      # active-tool blue-cyan
const ACCENT_BORDER := Color(0.55, 0.80, 1.0, 0.9)

const CLOSE_RED := Color(0.58, 0.08, 0.08, 0.95)
const CLOSE_RED_HOVER := Color(0.78, 0.10, 0.10, 1.0)
const CLOSE_RED_PRESSED := Color(0.42, 0.04, 0.04, 1.0)
const CLOSE_RED_BORDER := Color(1.0, 0.45, 0.45, 0.50)

const DEV_ORANGE := Color(1.0, 0.62, 0.26)             # DEV-only actions
const DEV_ORANGE_HOVER := Color(1.0, 0.72, 0.40)
const DANGER_RED := Color(1.0, 0.48, 0.43)             # destructive actions

const TEXT_DIM := Color(0.86, 0.82, 0.74)

const RADIUS := 8

const FONT_TITLE := 15
const FONT_BODY := 14
const FONT_SMALL := 13


# ── Core stylebox factory ─────────────────────────────────────────────────────

## General-purpose flat stylebox. content_margin < 0 leaves Godot's defaults.
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


# ── Window chrome (consumed by UIWindow) ──────────────────────────────────────

## Outer window panel. Zero content margins — UIWindow lays out its own
## title bar and body padding.
static func window_style() -> StyleBoxFlat:
	return style(WINDOW_BG, WINDOW_BORDER, 1, RADIUS, 0.0, 0.0)


## Title-bar band: rounded on top only, square where it meets the body.
static func titlebar_style() -> StyleBoxFlat:
	var box := style(TITLEBAR_BG, Color(0, 0, 0, 0), 0, 0, 0.0, 0.0)
	box.corner_radius_top_left = RADIUS - 1
	box.corner_radius_top_right = RADIUS - 1
	return box


static func close_button_style(bg: Color) -> StyleBoxFlat:
	var box := style(bg, CLOSE_RED_BORDER, 1, 5, 6.0, 0.0)
	return box


## Applies the standard red close-button look (the doc 24 single close design).
static func apply_close_button(button: Button) -> void:
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(28.0, 22.0)
	button.tooltip_text = "Close"
	button.add_theme_font_size_override("font_size", 12)
	button.add_theme_stylebox_override("normal", close_button_style(CLOSE_RED))
	button.add_theme_stylebox_override("hover", close_button_style(CLOSE_RED_HOVER))
	button.add_theme_stylebox_override("pressed", close_button_style(CLOSE_RED_PRESSED))


# ── In-window buttons (the bordered trio, ex-Clock-window language) ───────────

static func button_normal_style() -> StyleBoxFlat:
	return style(Color(1, 1, 1, 0.07), Color(1, 1, 1, 0.16), 1, 6)


static func button_hover_style() -> StyleBoxFlat:
	return style(Color(1, 1, 1, 0.14), Color(1, 1, 1, 0.22), 1, 6)


static func button_pressed_style() -> StyleBoxFlat:
	return style(Color(1, 1, 1, 0.20), Color(1, 1, 1, 0.28), 1, 6)


## Standard in-window button. Variants: "dev" (orange text, testing-only
## actions) and "danger" (red text, destructive actions).
static func make_button(text: String, tooltip: String = "",
		min_size: Vector2 = Vector2(100.0, 30.0), variant: String = "") -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tooltip
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = min_size
	button.add_theme_font_size_override("font_size", FONT_SMALL)
	button.add_theme_stylebox_override("normal", button_normal_style())
	button.add_theme_stylebox_override("hover", button_hover_style())
	button.add_theme_stylebox_override("pressed", button_pressed_style())
	match variant:
		"dev":
			button.add_theme_color_override("font_color", DEV_ORANGE)
			button.add_theme_color_override("font_hover_color", DEV_ORANGE_HOVER)
		"danger":
			button.add_theme_color_override("font_color", DANGER_RED)
			button.add_theme_color_override("font_hover_color", DANGER_RED)
	return button


# ── Dock buttons (the transparent trio, unchanged look) ───────────────────────

static func dock_button_normal_style() -> StyleBoxFlat:
	return style(Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.0), 0, RADIUS)


static func dock_button_hover_style() -> StyleBoxFlat:
	return style(Color(1, 1, 1, 0.10), Color(1, 1, 1, 0.14), 1, RADIUS)


static func dock_button_active_style() -> StyleBoxFlat:
	return style(ACCENT_FILL, ACCENT_BORDER, 2, RADIUS)


# ── HUD panels (dock band, action panel, toast, hint callouts) ────────────────

static func hud_panel_style(bg_alpha: float = 0.92) -> StyleBoxFlat:
	return style(Color(0.070, 0.075, 0.080, bg_alpha), Color(1, 1, 1, 0.12), 1, RADIUS)


static func dock_panel_style() -> StyleBoxFlat:
	return style(Color(0.055, 0.060, 0.065, 0.82), Color(1, 1, 1, 0.13), 1, RADIUS)
