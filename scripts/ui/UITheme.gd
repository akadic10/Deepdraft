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
# Type (doc 23, "Type"). Each role's face is a font shipped in assets/ui/fonts/ at a weight of
# its variable 'wght' axis: text for most words; rows for fact rows, status and cards; names
# for names, headings and buttons; hud for the HUD's titles and the title screen; figures for
# numbers that change while you watch (Nunito's digits share one width, Fredoka's do not).
# The symbol font draws what the faces lack; tools/fit_font_metrics.py fitted its line metrics
# so it never makes a line taller.
const FACES := {
	"text": ["res://assets/ui/fonts/nunito_variable.ttf", 500],
	"rows": ["res://assets/ui/fonts/nunito_variable.ttf", 700],
	"names": ["res://assets/ui/fonts/fredoka_variable.ttf", 600],
	"hud": ["res://assets/ui/fonts/fredoka_variable.ttf", 600],
	"figures": ["res://assets/ui/fonts/nunito_variable.ttf", 800],
}
const SYMBOL_FONT := "res://assets/ui/fonts/noto_sans_symbols_2.ttf"
# The type scale: every text size is one of seven steps, sized by tier (large from 1300 px of
# room, small below 650). Windows read their tier's table; what has no tier uses the medium.
const TYPE_LARGE := {"display": 42, "name": 34, "title": 28, "heading": 23, "lead": 19, "body": 17, "small": 14}
const TYPE_MEDIUM := {"display": 34, "name": 28, "title": 23, "heading": 19, "lead": 16, "body": 14, "small": 12}
const TYPE_SMALL := {"display": 28, "name": 24, "title": 20, "heading": 16, "lead": 14, "body": 12, "small": 10}
const CATALOG_PAPER := Color("e9d8b5")
const CATALOG_INK := Color("3b342a")
const CATALOG_MUTED := Color("68583e")
const CATALOG_WOOD := Color("504634")
const CATALOG_GOLD := Color("d0af76")
# Kept from the Stonehearth-style format (doc 260): the dark label outline, tan buttons
# for actions without a picture, and the olive band and blue tabs, kept for when windows
# take a new look (doc 259).
const FRAME_OUTLINE := Color("231b19")
const TAN_INK := Color("3a2f2b")
const TAN_FILL := Color("c8b07a")
const TAN_EDGE := Color("7b6a45")
const BAND_FILL := Color("8a7b4f")
const BAND_EDGE := Color("5d5333")
const TAB_FILL := Color("2d4f8f")
const TAB_ACTIVE := Color("3d68b8")
# Deepdraft's own Hearthblock style (doc 259). Hover cards (option C) are a dark hearth slab
# drawn in voxel cells, with notched corners, a dark outline, a lit top and a dark skirt
# (doc 64), their top in the family colour of the button they explain. The compact panel
# (option A of its review) is the same slab with a band in the selected kind's family
# colour. Keys sit on pale stone keycaps, badges on stone chips, statuses on tone tags.
const CARD_CELL := 4
const CARD_FACE := Color("232b2a")
const CARD_TOP := Color("2f3a38")
const CARD_SKIRT := Color("181e1d")
const CARD_OUTLINE := Color("111514")
const CARD_TEXT := Color("e9e4d8")
const CARD_TITLE := Color("f6f2ea")
const CARD_TITLE_OUTLINE := Color("16181c")
const KEYCAP_FACE := Color("e9e2d0")
const KEYCAP_TOP := Color("f7f2e6")
const KEYCAP_SKIRT := Color("b9b09a")
const KEYCAP_OUTLINE := Color("1d1b18")
const KEYCAP_INK := Color("2a2622")
# Windows in the same style (doc 261): the slab with a title band in the window's family
# colour; raised blocks for buttons, with the family block for the shown tab and the main
# action; pictures on the family tile, with a hay rim when selected; recessed insets, a
# pale pine board for light cards with dark ink, cell grooves for bars and scrollbars.
const WINDOW_BAND_ROWS := 12   # the title band, in slab cells: 48 px
const TOAST_BAND_ROWS := 3     # a toast's band, in 3 px cells (doc 23)
# A warning that needs attention (Events, doc 23): the toast's slab warmed toward rust.
const WARNING_FACE := Color("2b2523")
const WARNING_TOP := Color("362d29")
const WARNING_SKIRT := Color("1b1716")
const RAISED_FACE := Color("34403e")
const RAISED_TOP := Color("43514e")
const RAISED_SKIRT := Color("1c2423")
const RAISED_HOVER := Color("3d4a47")
const INSET_FACE := Color("1b2221")
const BOARD_FACE := Color("e3cb9b")
# Status tags by tone: moss when fine, hay when waiting, rust when blocked. Each holds the
# face, lit top, skirt, outline and ink.
const TAG_TONES := {
	"fine": [Color("8fbf5a"), Color("a8d377"), Color("6f9a43"), Color("2a3a17"), Color("1d2a0e")],
	"waiting": [Color("e2c06a"), Color("f0d58f"), Color("bf9c45"), Color("3d2e10"), Color("2a1d08")],
	"blocked": [Color("c8664a"), Color("da8166"), Color("9f4b33"), Color("3a160c"), Color("fff1e8")],
}

static var _shared_theme: Theme
static var _faces: Dictionary = {}   # role -> Font
static var _icon_tiles: Dictionary = {}
static var _cell_styles: Dictionary = {}
static var _window_frames: Dictionary = {}
static var _toast_frames: Dictionary = {}
static var _family_themes: Dictionary = {}
static var _banners: Dictionary = {}


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


## The theme of every surface outside the windows: the dock, its menus and the HUD. Its
## text face is also the project's fallback, for what draws without a theme.
static func shared_theme() -> Theme:
	if _shared_theme == null:
		_shared_theme = _build_theme(Color.TRANSPARENT)
		ThemeDB.fallback_font = font("text")
	return _shared_theme


## A role's face (doc 23, "Type"): text, rows, names, hud or figures (FACES), with the
## symbol font behind it for what the face lacks.
static func font(role: String) -> Font:
	if not _faces.has(role):
		var face := FontVariation.new()
		face.base_font = load(String(FACES[role][0]))
		face.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): int(FACES[role][1])}
		face.fallbacks = [load(SYMBOL_FONT)]
		_faces[role] = face
	return _faces[role]


## A window's theme (doc 261): the shared theme with the window's family colour on the
## shown tab, the main action and the picture tiles. The window carries it and its
## contents inherit it, so they set no theme of their own.
static func family_theme(family: Color) -> Theme:
	if family.a <= 0.0:
		return shared_theme()
	var key := family.to_html()
	if not _family_themes.has(key):
		_family_themes[key] = _build_theme(family)
	return _family_themes[key]


static func _build_theme(family: Color) -> Theme:
	var theme := Theme.new()
	theme.default_font = font("text")
	theme.default_font_size = TYPE_MEDIUM.body
	theme.set_color("font_color", "Label", HEARTH_TEXT)
	theme.set_color("default_color", "RichTextLabel", HEARTH_TEXT)
	theme.set_font_size("font_size", "Button", TYPE_MEDIUM.body)
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		theme.set_color(state, "Button", HEARTH_TEXT)
	theme.set_color("font_disabled_color", "Button", TEXT_DISABLED)
	theme.set_stylebox("normal", "Button", button_normal_style())
	theme.set_stylebox("hover", "Button", button_hover_style())
	theme.set_stylebox("pressed", "Button", button_pressed_style())
	theme.set_stylebox("hover_pressed", "Button", button_pressed_style())
	theme.set_stylebox("disabled", "Button", button_disabled_style())
	for state: String in ["normal", "focus", "read_only"]:
		theme.set_stylebox(state, "LineEdit", cell_style("groove", 2))
	theme.set_stylebox("focus", "Button", focus_style())
	theme.set_stylebox("panel", "PanelContainer", window_style())
	# Tooltips are the hover card's hearth slab (doc 259, option C) with light body text,
	# on every surface: the dock, its menus, the compact panel and every window.
	theme.set_stylebox("panel", "TooltipPanel", cell_style("card", CARD_CELL))
	theme.set_font("font", "TooltipLabel", UITheme.body_font())
	theme.set_font_size("font_size", "TooltipLabel", TYPE_MEDIUM.lead)
	theme.set_color("font_color", "TooltipLabel", CARD_TEXT)
	for separator_type: String in ["HSeparator", "VSeparator"]:
		var line := StyleBoxLine.new()
		line.color = HEARTH_EDGE
		line.thickness = 1
		line.vertical = separator_type == "VSeparator"
		theme.set_stylebox("separator", separator_type, line)
		theme.set_constant("separation", separator_type, 8)
	for scroll_type: String in ["VScrollBar", "HScrollBar"]:
		theme.set_stylebox("scroll", scroll_type, cell_style("groove", 2))
		theme.set_stylebox("scroll_focus", scroll_type, cell_style("groove", 2))
		theme.set_stylebox("grabber", scroll_type, cell_style("grabber", 2))
		theme.set_stylebox("grabber_highlight", scroll_type, cell_style("grabber_hover", 2))
		theme.set_stylebox("grabber_pressed", scroll_type, cell_style("grabber_hover", 2))
	theme.set_stylebox("background", "ProgressBar", cell_style("groove", 2))
	theme.set_stylebox("fill", "ProgressBar", cell_style("fill", 2))
	_add_family_pieces(theme, family)
	return theme


## The pieces that wear a window's family colour (doc 261). Outside the windows they keep
## the neutral look: a hay edge when toggled on, hay blocks for a main action.
## - Toggled-on buttons: the family block.
## - "FamilyBlock" (a Button): the shown tab and the main action, in the display face.
## - "PictureTile" (a Button): a picture on the family tile, with a hay rim while selected
##   (pressed or toggled on) and dimmed while disabled.
## - "PictureFrame" (a PanelContainer): a picture on the family tile.
static func _add_family_pieces(theme: Theme, family: Color) -> void:
	var tile := family if family.a > 0.0 else RAISED_FACE
	var blocks := {"normal": cell_style("hay", 3), "hover": cell_style("hay_hover", 3), "pressed": cell_style("hay_on", 3)}
	var ink := tag_ink("waiting")
	if family.a > 0.0:
		blocks = {"normal": family_block_style(family), "hover": family_block_style(family, "hover"),
			"pressed": family_block_style(family, "pressed")}
		ink = CARD_TITLE
		theme.set_stylebox("pressed", "Button", blocks.normal)
		theme.set_stylebox("hover_pressed", "Button", blocks.hover)
		for state: String in ["font_pressed_color", "font_hover_pressed_color"]:
			theme.set_color(state, "Button", CARD_TITLE)
	theme.set_type_variation("FamilyBlock", "Button")
	theme.set_stylebox("normal", "FamilyBlock", blocks.normal)
	theme.set_stylebox("hover", "FamilyBlock", blocks.hover)
	theme.set_stylebox("pressed", "FamilyBlock", blocks.pressed)
	theme.set_stylebox("hover_pressed", "FamilyBlock", blocks.hover)
	theme.set_stylebox("disabled", "FamilyBlock", button_disabled_style())
	theme.set_font("font", "FamilyBlock", display_font())
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		theme.set_color(state, "FamilyBlock", ink)
	theme.set_color("font_disabled_color", "FamilyBlock", TEXT_DISABLED)
	theme.set_constant("outline_size", "FamilyBlock", 4 if family.a > 0.0 else 0)
	theme.set_color("font_outline_color", "FamilyBlock", CARD_TITLE_OUTLINE)
	theme.set_type_variation("PictureTile", "Button")
	for state: String in ["normal", "hover"]:
		theme.set_stylebox(state, "PictureTile", icon_tile_style(tile, state))
	theme.set_stylebox("pressed", "PictureTile", icon_tile_style(tile, "selected"))
	theme.set_stylebox("hover_pressed", "PictureTile", icon_tile_style(tile, "selected_hover"))
	theme.set_stylebox("disabled", "PictureTile", icon_tile_style(tile, "planned"))
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		theme.set_color(state, "PictureTile", CARD_TITLE)
	theme.set_type_variation("PictureFrame", "PanelContainer")
	theme.set_stylebox("panel", "PictureFrame", icon_tile_style(tile))


## Apply at a surface's root Control, so dynamically added children inherit it too. Inside
## a window the window's family theme already reaches the control, and a theme of its own
## would hide it, so the control inherits instead.
static func apply_surface(control: Control) -> void:
	if not _inside_themed(control):
		control.theme = shared_theme()
	control.mouse_force_pass_scroll_events = false


static func _inside_themed(control: Control) -> bool:
	var node := control.get_parent()
	while node != null:
		if (node is Control and (node as Control).theme != null) or (node is Window and (node as Window).theme != null):
			return true
		node = node.get_parent()
	return false


## The HUD's title face: the Sky Dial, the slice tower, the dock's menus, and the title and
## loading screens (doc 23, "Type").
static func hearth_title_font() -> Font:
	return font("hud")


## A title on the HUD (the Sky Dial, the time controls, the dock's menus).
static func apply_title(label: Label, font_size: int = TYPE_MEDIUM.heading) -> void:
	label.add_theme_font_override("font", hearth_title_font())
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", HEARTH_TEXT)


## A name or heading inside a window: the display face, never the HUD's title face (doc 261).
static func apply_heading(label: Label, font_size: int = TYPE_MEDIUM.heading) -> void:
	label.add_theme_font_override("font", display_font())
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", CARD_TITLE)


## A panel without a band: the slab in cells, with no content margin of its own.
static func window_style() -> StyleBox:
	return cell_style("panel", CARD_CELL)


## The window frame (doc 261): the slab with a title band in the window's family colour,
## as one nine-slice, so the band stretches only across. Without a family the slab keeps
## its plain lit top.
static func window_frame(family: Color) -> StyleBoxTexture:
	var key := family.to_html()
	if _window_frames.has(key):
		return _window_frames[key]
	var cell := CARD_CELL
	var art := cell_slab(12, WINDOW_BAND_ROWS + 6, CARD_FACE, CARD_TOP, CARD_SKIRT, CARD_OUTLINE,
		2, 2, family, WINDOW_BAND_ROWS if family.a > 0.0 else 0)
	art.resize(art.get_width() * cell, art.get_height() * cell, Image.INTERPOLATE_NEAREST)
	var box := StyleBoxTexture.new()
	box.texture = cell_texture(art)
	box.texture_margin_left = 3 * cell
	box.texture_margin_right = 3 * cell
	box.texture_margin_top = (WINDOW_BAND_ROWS + 1) * cell
	box.texture_margin_bottom = 4 * cell
	box.content_margin_left = cell
	box.content_margin_right = cell
	box.content_margin_top = 0
	box.content_margin_bottom = 3 * cell
	_window_frames[key] = box
	return box


## A toast (doc 23): the dark slab in 3 px cells with a thin band in its tone along the
## top (the people family for an event, rust for a warning, moss for the player's own
## message).
static func toast_frame(band: Color) -> StyleBoxTexture:
	return _banded_frame(band, CARD_FACE, CARD_TOP, CARD_SKIRT)


## A warning still unresolved, at the top of Events (doc 23): the toast's slab, warmed,
## with the rust band.
static func warning_frame() -> StyleBoxTexture:
	return _banded_frame(TAG_TONES.blocked[0], WARNING_FACE, WARNING_TOP, WARNING_SKIRT)


static func _banded_frame(band: Color, face: Color, top: Color, skirt: Color) -> StyleBoxTexture:
	var key := band.to_html() + face.to_html()
	if _toast_frames.has(key):
		return _toast_frames[key]
	var cell := 3
	var art := cell_slab(12, TOAST_BAND_ROWS + 7, face, top, skirt, CARD_OUTLINE,
		1, 2, band, TOAST_BAND_ROWS)
	art.resize(art.get_width() * cell, art.get_height() * cell, Image.INTERPOLATE_NEAREST)
	var box := StyleBoxTexture.new()
	box.texture = cell_texture(art)
	box.texture_margin_left = 3 * cell
	box.texture_margin_right = 3 * cell
	box.texture_margin_top = (TOAST_BAND_ROWS + 1) * cell
	box.texture_margin_bottom = 3 * cell
	box.content_margin_left = 5 * cell
	box.content_margin_right = 6 * cell
	box.content_margin_top = (TOAST_BAND_ROWS + 3) * cell
	box.content_margin_bottom = 5 * cell
	_toast_frames[key] = box
	return box


## The title bar of a panel that draws its own chrome (the DEV overlays): a raised block.
static func titlebar_style() -> StyleBox:
	return cell_style("raised", 3)


## A close button: a stone keycap with ✕, 36 px square so it stands inside a window's band.
static func apply_close_button(button: Button) -> void:
	button.text = "✕"
	button.focus_mode = Control.FOCUS_ALL
	button.custom_minimum_size = Vector2(36, 36)
	button.tooltip_text = "Close"
	button.add_theme_font_override("font", display_font())
	button.add_theme_font_size_override("font_size", TYPE_MEDIUM.lead)
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		button.add_theme_color_override(state, KEYCAP_INK)
	button.add_theme_stylebox_override("normal", _close_cap("keycap"))
	for state: String in ["hover", "pressed", "hover_pressed"]:
		button.add_theme_stylebox_override(state, _close_cap("keycap_hover"))
	button.add_theme_stylebox_override("focus", focus_style())


## The keycap with its glyph margins trimmed to the cap's face, so the key keeps its
## 36 px; the hover card's keycaps keep the roomier margins.
static func _close_cap(kind: String) -> StyleBoxTexture:
	var key := "close_" + kind
	if not _cell_styles.has(key):
		var cap: StyleBoxTexture = cell_style(kind, 3).duplicate()
		cap.content_margin_top = 3
		cap.content_margin_bottom = 9
		_cell_styles[key] = cap
	return _cell_styles[key]


static func button_normal_style() -> StyleBox:
	return cell_style("raised", 3)


static func button_hover_style() -> StyleBox:
	return cell_style("raised_hover", 3)


## Pressed, and a toggled or selected button outside the windows: the raised block with a
## hay edge. Inside a window a toggled button wears the family block (doc 261).
static func button_pressed_style() -> StyleBox:
	return cell_style("raised_on", 3)


static func button_disabled_style() -> StyleBox:
	return cell_style("raised_off", 3)


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


## The Hearthblock icon tile (doc 259): stepped notched corners, a dark rim, a lit top
## band and a dark lower band, nine-sliced so corners and bands keep their size.
## States are tile changes: hover and active lighten it, planned dims it, and selected and
## selected_hover give it a hay rim (a selected picture in a window, doc 261).
static func icon_tile_style(base: Color, state: String = "normal") -> StyleBoxTexture:
	var key := base.to_html() + state
	if _icon_tiles.has(key):
		return _icon_tiles[key]
	var fill := base
	match state:
		"hover", "hover_pressed", "selected_hover": fill = base.lightened(0.14)
		"pressed": fill = base.lightened(0.07)
		"planned", "disabled": fill = Color(base.darkened(0.35), 1.0).lerp(HEARTH_BG, 0.35)
	var hay := state.begins_with("selected")
	var size := 32
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	for y in range(size):
		for x in range(size):
			var ex := mini(x, size - 1 - x)
			var ey := mini(y, size - 1 - y)
			if (ex < 2 and ey < 4) or (ex < 4 and ey < 2):
				continue
			var color := fill
			if y < 8: color = fill.lightened(0.12)
			elif y >= size - 8: color = fill.darkened(0.22)
			if ex < 2 or ey < 2 or (ex < 4 and ey < 6) or (ex < 6 and ey < 4):
				color = TAG_TONES.waiting[0] if hay else fill.darkened(0.55)
			elif hay and (ex < 3 or ey < 3):
				color = TAG_TONES.waiting[2]
			image.set_pixel(x, y, color)
	var box := StyleBoxTexture.new()
	box.texture = cell_texture(image)
	box.set_texture_margin_all(9)
	box.set_content_margin_all(4)
	_icon_tiles[key] = box
	return box


## The hay ring drawn just outside a selected picture tile (doc 261).
static func selection_ring() -> StyleBoxFlat:
	if not _cell_styles.has("selection_ring"):
		var ring := style(Color.TRANSPARENT, TAG_TONES.waiting[0], 3, 0, 0, 0)
		ring.draw_center = false
		_cell_styles["selection_ring"] = ring
	return _cell_styles["selection_ring"]


static func hud_panel_style(bg_alpha: float = .97) -> StyleBoxFlat:
	return style(Color(HEARTH_BG, bg_alpha), HEARTH_EDGE, 1, RADIUS)


static func dock_panel_style() -> StyleBoxFlat:
	return style(Color(TRACK_BG, .96), HEARTH_EDGE, 1, RADIUS, 8, 5)


## A content card: a recessed inset in the slab (doc 261); without `inset`, a slab of its own.
static func hearth_panel(inset: bool = false) -> StyleBox:
	return cell_style("inset", 3) if inset else cell_style("panel", CARD_CELL)


## A button in a window's content. `primary`: the shown tab or the main action, so the
## family block (doc 261). Call it again whenever that changes.
static func apply_hearth_button(button: Button, primary: bool = false) -> void:
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_size_override("font_size", TYPE_MEDIUM.body)
	show_tab(button, primary)


## A tab: the family block while it is the shown one, a raised block otherwise (doc 261).
## The block's ink comes from the theme, so colour overrides go.
static func show_tab(button: Button, shown: bool) -> void:
	button.theme_type_variation = &"FamilyBlock" if shown else &""
	for state: String in ["normal", "hover", "pressed", "hover_pressed"]:
		button.remove_theme_stylebox_override(state)
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		button.remove_theme_color_override(state)


## A picture button on its window's family tile (doc 261): a hay rim while selected
## (pressed or toggled on), dimmed while disabled.
static func apply_picture_tile(button: Button) -> void:
	button.theme_type_variation = &"PictureTile"


## A picture on its window's family tile (doc 261). The frame lets clicks through.
static func framed_picture(picture: Control) -> PanelContainer:
	var frame := PanelContainer.new()
	frame.theme_type_variation = &"PictureFrame"
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(picture)
	return frame


## A bar: a cell groove with a hay fill, tall enough for its cells.
static func hearth_progress(bar: ProgressBar) -> void:
	bar.show_percentage = false
	bar.custom_minimum_size.y = 12


## A light card with dark ink: the pale pine board (doc 261).
static func catalog_paper_style(compact: bool = false) -> StyleBox:
	return cell_style("board_compact" if compact else "board", 3)


## A list row, such as a dwarf in Colony Dwarves: a raised block with a hay edge when
## selected.
static func catalog_item_style(selected: bool = false) -> StyleBox:
	return cell_style("raised_on" if selected else "raised", 3)


## The main action of a window: the family block (doc 261); outside the windows, a hay
## block with dark ink.
static func apply_catalog_primary(button: Button) -> void:
	apply_hearth_button(button, true)


# ── Panel format (doc 260) ───────────────────────────────────────────────────────

## The display face, for names, titles, badges and keys (the names role).
static func display_font() -> Font:
	return font("names")


## The format's body face, for flavour, status and fact rows (the rows role).
static func body_font() -> Font:
	return font("rows")


## Style a label in the format: display or body face, size, colour, and a dark outline
## when it sits on a band or over the world.
static func format_label(label: Label, display: bool, font_size: int, color: Color, outline: int = 0) -> void:
	label.add_theme_font_override("font", display_font() if display else body_font())
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("outline_size", outline)
	label.add_theme_color_override("font_outline_color", FRAME_OUTLINE)


## A key or chord on keycaps, added to `box`: "Ctrl + ]" shows Ctrl and ] joined by a plus.
## Hover cards and Settings' key list draw keys with it; `cell` is the caps' cell size.
static func add_keycaps(box: Control, key: String, font_size: int, cell: int) -> void:
	var parts := key.split(" + ", false)
	for i in range(parts.size()):
		if i > 0:
			var plus := Label.new()
			plus.text = "+"
			plus.mouse_filter = Control.MOUSE_FILTER_IGNORE
			plus.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			format_label(plus, true, roundi(font_size * 0.9), CARD_TEXT)
			box.add_child(plus)
		var cap := PanelContainer.new()
		cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cap.add_theme_stylebox_override("panel", cell_style("keycap", cell))
		box.add_child(cap)
		var glyph := Label.new()
		glyph.text = parts[i]
		glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		glyph.custom_minimum_size.x = roundi(font_size * 0.74)   # "1" and "[" stay key-shaped
		format_label(glyph, true, font_size, KEYCAP_INK)
		cap.add_child(glyph)


## Voxel cell art (doc 64), one pixel per cell: a notched slab with a dark outline, a lit
## top `top_rows` deep and a dark skirt `skirt_rows` deep. When `header` is set, a band of
## that colour, `header_rows` deep, replaces the lit top: lit along its top edge, with a
## dark seam under it.
static func cell_slab(w: int, h: int, face: Color, top: Color, skirt: Color, outline: Color,
		top_rows := 2, skirt_rows := 2, header := Color.TRANSPARENT, header_rows := 0) -> Image:
	var image := Image.create(w, h, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	for y in range(h):
		for x in range(w):
			var ex := mini(x, w - 1 - x)
			var ey := mini(y, h - 1 - y)
			if (ex == 0 and ey <= 1) or (ex <= 1 and ey == 0):
				continue
			var color := face
			if header.a > 0.0 and y < header_rows:
				color = header.lightened(0.12) if y <= top_rows else header
				if y == header_rows - 1: color = header.darkened(0.55)
			elif y <= top_rows:
				color = top
			if y >= h - 1 - skirt_rows: color = skirt
			if ex == 0 or ey == 0 or (ex == 1 and ey == 1): color = outline
			image.set_pixel(x, y, color)
	return image


## Cell art as a nine-slice style, each cell `cell` pixels. The stretched middle and edges
## are plain rows and columns, so the cells stay crisp at any size. Kinds:
## - "card" (plain tooltips) and "panel" (the same slab with no content margin);
## - "keycap" and "keycap_hover" (a deep skirt, so the key stands up);
## - "chip" (a badge on pale stone) and the tone tags "tag_fine", "tag_waiting" and
##   "tag_blocked";
## - window pieces (doc 261): "raised", "raised_hover", "raised_on" (a hay edge),
##   "raised_off", "hay", "hay_hover" and "hay_on" (a main action), "inset", "board" and
##   "board_compact" (the pine board), "groove", "fill", "grabber" and "grabber_hover".
static func cell_style(kind: String, cell: int) -> StyleBoxTexture:
	var key := "%s%d" % [kind, cell]
	if _cell_styles.has(key):
		return _cell_styles[key]
	var art: Image
	var edges := [3, 4, 3, 4]   # left, top, right, bottom, in cells
	var content := [cell * 4 - 2, cell * 3 + 1, cell * 4 - 2, cell * 4]
	match kind:
		"keycap":
			art = cell_slab(8, 10, KEYCAP_FACE, KEYCAP_TOP, KEYCAP_SKIRT, KEYCAP_OUTLINE, 1, 3)
			edges = [3, 3, 3, 5]
			content = [cell * 3 + 2, cell + 2, cell * 3 + 2, cell * 4 + 1]
		"keycap_hover":
			art = cell_slab(8, 10, Color("fbf7ee"), Color.WHITE, KEYCAP_SKIRT, KEYCAP_OUTLINE, 1, 3)
			edges = [3, 3, 3, 5]
			content = [cell * 3 + 2, cell + 2, cell * 3 + 2, cell * 4 + 1]
		"chip":
			art = cell_slab(8, 8, KEYCAP_FACE, KEYCAP_TOP, KEYCAP_SKIRT, KEYCAP_OUTLINE, 1, 1)
			edges = [3, 3, 3, 3]
			content = [cell * 4, cell + 2, cell * 4 + 2, cell * 2 + 3]
		"raised", "raised_hover", "raised_on", "raised_off", "hay", "hay_hover", "hay_on":
			var hay: Array = TAG_TONES.waiting
			var looks := {
				"raised": [RAISED_FACE, RAISED_TOP, RAISED_SKIRT, CARD_OUTLINE],
				"raised_hover": [RAISED_HOVER, Color("4d5c58"), Color("20292a"), CARD_OUTLINE],
				"raised_on": [RAISED_HOVER, Color("4d5c58"), Color("20292a"), hay[0]],
				"raised_off": [Color("262e2d"), Color("2c3533"), Color("1a201f"), CARD_OUTLINE],
				"hay": [hay[0], hay[1], hay[2], hay[3]],
				"hay_hover": [Color(hay[0]).lightened(0.12), Color(hay[1]).lightened(0.12), hay[2], hay[3]],
				"hay_on": [Color(hay[0]).darkened(0.08), hay[0], hay[2], hay[3]],
			}
			var look: Array = looks[kind]
			art = cell_slab(8, 9, look[0], look[1], look[2], look[3], 1, 2)
			edges = [3, 3, 3, 4]
			content = [12, 6, 12, 9]
		"inset":
			art = cell_slab(8, 8, INSET_FACE, Color("111615"), Color("2c3734"), Color("0d1110"), 1, 1)
			edges = [3, 3, 3, 3]
			content = [12, 10, 12, 10]
		"board", "board_compact":
			art = cell_slab(10, 10, BOARD_FACE, Color("f2e1b9"), Color("c1a170"), Color("3b2a1c"))
			edges = [3, 4, 3, 4]
			content = [14, 6 if kind == "board_compact" else 12, 14, 12]
		"groove":
			art = cell_slab(8, 8, Color("171d1c"), Color("0f1312"), Color("2a3432"), Color("0d1110"), 1, 1)
			edges = [3, 3, 3, 3]
			content = [6, 6, 6, 6]
		"fill":
			var tone: Array = TAG_TONES.waiting
			art = cell_slab(8, 8, tone[0], tone[1], tone[2], Color("6d5520"), 1, 1)
			edges = [3, 3, 3, 3]
			content = [0, 0, 0, 0]
		"grabber", "grabber_hover":
			var lit := kind == "grabber_hover"
			art = cell_slab(8, 8, Color("566663") if lit else RAISED_TOP, Color("6a7b77") if lit else Color("566663"), Color("2a3432"), CARD_OUTLINE, 1, 1)
			edges = [3, 3, 3, 3]
			content = [6, 6, 6, 6]
		"tag_fine", "tag_waiting", "tag_blocked":
			var tone: Array = TAG_TONES[kind.trim_prefix("tag_")]
			art = cell_slab(8, 8, tone[0], tone[1], tone[2], tone[3], 1, 1)
			edges = [3, 3, 3, 3]
			content = [cell * 4, cell + 2, cell * 4, cell * 2 + 2]
		_:
			art = cell_slab(10, 10, CARD_FACE, CARD_TOP, CARD_SKIRT, CARD_OUTLINE)
			if kind == "panel": content = [0, 0, 0, 0]
	_cell_styles[key] = _cell_box(art, cell, edges, content)
	return _cell_styles[key]


## The family block (doc 261): a raised block in a window's family colour, for the shown
## tab, a toggled button and the main action. States: normal, hover and pressed.
static func family_block_style(family: Color, state := "normal") -> StyleBoxTexture:
	var key := "family_%s_%s" % [family.to_html(), state]
	if not _cell_styles.has(key):
		var face := family
		match state:
			"hover": face = family.lightened(0.1)
			"pressed": face = family.darkened(0.08)
		var art := cell_slab(8, 9, face, face.lightened(0.12), face.darkened(0.35), CARD_OUTLINE, 1, 2)
		_cell_styles[key] = _cell_box(art, 3, [3, 3, 3, 4], [12, 6, 12, 9])
	return _cell_styles[key]


## A hanging banner in a family colour with a swallowtail (doc 261), like Stonehearth's Town
## Morale ribbon: the character sheet's mood and, later, a room's appeal. Cell art `w` by
## `h` cells at `cell` pixels a cell, drawn at its size rather than stretched, so the tail
## keeps its cells.
static func banner_texture(family: Color, w: int, h: int, cell: int = CARD_CELL) -> Texture2D:
	var key := "banner_%s_%d_%d_%d" % [family.to_html(), w, h, cell]
	if not _banners.has(key):
		var art := cell_slab(w, h, family, family.lightened(0.12), family.darkened(0.3), CARD_OUTLINE, 2, 2)
		var depth := mini(6, h / 4)
		var middle := w / 2
		for y in range(h - depth - 1, h):
			var half := int(float(y - (h - depth - 1)) * float(middle) / float(depth))
			for x in range(w):
				var off := absi(x - middle)
				if off < half: art.set_pixel(x, y, Color.TRANSPARENT)
				elif off == half and y > h - depth - 1: art.set_pixel(x, y, CARD_OUTLINE)
		art.resize(w * cell, h * cell, Image.INTERPOLATE_NEAREST)
		_banners[key] = cell_texture(art)
	return _banners[key]


## Cell art as a texture that always draws nearest, whatever its control's filter, so its
## cells stay crisp when the UI scale draws it larger (doc 23). Pictures keep their own
## filtering. The art is the texture's diffuse_texture.
static func cell_texture(art: Image) -> Texture2D:
	var texture := CanvasTexture.new()
	texture.diffuse_texture = ImageTexture.create_from_image(art)
	texture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return texture


## A rendered picture (a portrait) sized `base` in the interface renders at that size times
## the UI scale, so it stays sharp when drawn larger, and follows a change of scale.
static func follow_ui_scale(viewport: SubViewport, base: Vector2i) -> void:
	var window := (Engine.get_main_loop() as SceneTree).root
	var fit := func() -> void:
		if not is_instance_valid(viewport): return
		var wanted := Vector2i((Vector2(base) * maxf(window.content_scale_factor, 1.0)).ceil())
		if viewport.size == wanted: return
		viewport.size = wanted
		if viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED: viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	fit.call()
	window.size_changed.connect(fit)
	viewport.tree_exiting.connect(func(): if window.size_changed.is_connected(fit): window.size_changed.disconnect(fit))


## Lay a tree out now rather than at the next frame, so wrapped text and picture rows
## report the height they need at their real width (a window fitting its contents).
static func lay_out_now(control: Control) -> void:
	if control is Container: control.notification(Container.NOTIFICATION_SORT_CHILDREN)
	elif control is Label: control.update_minimum_size()
	for child: Node in control.get_children():
		if child is Control and (child as Control).visible: lay_out_now(child)


## Cell art scaled to `cell` pixels a cell, as a nine-slice with edges in cells and content
## margins in pixels (left, top, right, bottom).
static func _cell_box(art: Image, cell: int, edges: Array, content: Array) -> StyleBoxTexture:
	art.resize(art.get_width() * cell, art.get_height() * cell, Image.INTERPOLATE_NEAREST)
	var box := StyleBoxTexture.new()
	box.texture = cell_texture(art)
	box.texture_margin_left = edges[0] * cell
	box.texture_margin_top = edges[1] * cell
	box.texture_margin_right = edges[2] * cell
	box.texture_margin_bottom = edges[3] * cell
	box.content_margin_left = content[0]
	box.content_margin_top = content[1]
	box.content_margin_right = content[2]
	box.content_margin_bottom = content[3]
	return box


## The tan button, for text actions inside the format.
static func tan_button_style(state: String = "normal") -> StyleBoxFlat:
	var fill := TAN_FILL
	match state:
		"hover": fill = TAN_FILL.lightened(0.14)
		"pressed", "hover_pressed": fill = TAN_FILL.darkened(0.12)
		"disabled": fill = TAN_FILL.darkened(0.4)
	return style(fill, TAN_EDGE, 2, 6, 14, 6)


static func apply_tan_button(button: Button, font_size: int = 17) -> void:
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		button.add_theme_stylebox_override(state, tan_button_style(state))
	button.add_theme_stylebox_override("focus", focus_style())
	button.add_theme_font_override("font", display_font())
	button.add_theme_font_size_override("font_size", font_size)
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		button.add_theme_color_override(state, TAN_INK)
	button.add_theme_color_override("font_disabled_color", TAN_EDGE)


## A window's olive title band, for when windows move to the format (doc 259).
static func title_band_style() -> StyleBoxFlat:
	return style(BAND_FILL, BAND_EDGE, 2, 6, 14, 6)


## A window tab: blue, brighter while selected, rounded on top only.
static func tab_style(selected: bool = false) -> StyleBoxFlat:
	var box := style(TAB_ACTIVE if selected else TAB_FILL, FRAME_OUTLINE, 2, 0, 14, 6)
	box.corner_radius_top_left = 6
	box.corner_radius_top_right = 6
	return box


## The ink on a tone tag: dark on moss and hay, light on rust.
static func tag_ink(tone: String) -> Color:
	return TAG_TONES.get(tone, TAG_TONES.fine)[4]
