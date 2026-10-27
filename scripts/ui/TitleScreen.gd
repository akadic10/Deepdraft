extends CanvasLayer

## The title screen (doc 23, "The title screen"), the game's main scene. The painted panorama
## fills the screen, cropped as the loading screen crops it, so one follows the other. A
## column at the left of the screen's middle 16:9 holds the game's name, its line and the menu:
## - the newest save on a pine board, as the Load page shows a slot, with Continue (the
##   family block, focused, so Enter resumes);
## - New game, Load game…, Settings… and Exit game. Without a save, New game leads.
## - Back from Load game…, where saves can be deleted, the board shows the newest save again.
## Nothing runs here, so nothing asks first: Exit game quits at once. Load and Settings are the
## game menu's own pages (GameMenu.open_page). The clock is held while the title shows, which
## also keeps Esc from opening the game menu. SaveManager enters the world.
const Menu = preload("res://scripts/ui/GameMenu.gd")
# Text sizes come from the type scale (doc 23, "Type").
const LARGE := UITheme.TYPE_LARGE
const MEDIUM := UITheme.TYPE_MEDIUM
const SMALL := UITheme.TYPE_SMALL
## Sizes by the screen's height, as the game menu's (GameMenu.SIZES), with the title's own:
## the column, the name and its line.
const SIZES := {
	"large": {"column": 760, "mark": 150, "line": LARGE.title, "button": 78, "verb": LARGE.heading, "plain": LARGE.heading, "slot": LARGE.title,
		"slot_date": LARGE.lead, "body": LARGE.lead, "note": LARGE.body, "gap": 14, "type": LARGE},
	"medium": {"column": 520, "mark": 100, "line": MEDIUM.title, "button": 54, "verb": MEDIUM.heading, "plain": MEDIUM.heading, "slot": MEDIUM.title,
		"slot_date": MEDIUM.lead, "body": MEDIUM.lead, "note": MEDIUM.body, "gap": 10, "type": MEDIUM},
	"small": {"column": 420, "mark": 64, "line": SMALL.title, "button": 42, "verb": SMALL.heading, "plain": SMALL.heading, "slot": SMALL.title,
		"slot_date": SMALL.lead, "body": SMALL.lead, "note": SMALL.body, "gap": 7, "type": SMALL},
}
const SHADE := Color(0.03, 0.04, 0.04)

## SaveManager and the game menu, or stand-ins with the same calls in tests.
var saves: Node
var menu: Node
## Quits the game; tests give their own.
var quit_game: Callable
## The menu's buttons by id: continue (with a save), new_game, load, settings and exit.
var buttons := {}
## The newest save's board, or null without a save.
var board: PanelContainer
var _slot: Dictionary = {}
var _art: Panorama
var _shade: TextureRect
var _column: VBoxContainer
var _name: Label
var _line: Label
var _gap: Control
var _slot_labels: Array[Label] = []
var _hint: Label
var _notice: Label
var _size: Dictionary = SIZES.medium


## The art, cropped as the loading screen crops its panoramas.
class Panorama extends Control:
	const Artwork = preload("res://scripts/ui/LoadingArtwork.gd")
	var texture: Texture2D
	var widest := 32.0 / 9.0

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color("101817"))
		if texture != null:
			draw_texture_rect_region(texture, Rect2(Vector2.ZERO, size), Artwork.band_rect(texture.get_size(), size, widest))


func _enter_tree() -> void:
	add_to_group("title_screen")
	WorldClock.hold_for_loading(self, true)


func _exit_tree() -> void:
	WorldClock.hold_for_loading(self, false)


func _ready() -> void:
	if saves == null: saves = get_node("/root/SaveManager")
	if menu == null: menu = get_node("/root/GameMenu")
	if not quit_game.is_valid(): quit_game = func(): get_tree().quit()
	_build()
	get_viewport().size_changed.connect(_fit)
	menu.closed.connect(_on_menu_closed)
	_fit()
	_focus_first.call_deferred()


# ── Building ──────────────────────────────────────────────────────────────────

func _build() -> void:
	var data: Dictionary = UIRegistry.get_title_screen()
	var screen := Control.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.theme = UITheme.family_theme(UIRegistry.get_icon_family_color("system"))
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(screen)
	_art = Panorama.new()
	_art.texture = load(String(data.get("art", ""))) as Texture2D
	_art.widest = float(UIRegistry.get_loading_screen().get("panorama_aspect", 32.0 / 9.0))
	_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art.resized.connect(_art.queue_redraw)
	screen.add_child(_art)
	_shade = TextureRect.new()
	_shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_shade.stretch_mode = TextureRect.STRETCH_SCALE
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(_shade)
	_column = VBoxContainer.new()
	screen.add_child(_column)
	_name = Label.new()
	_name.text = String(data.get("name", "DEEPDRAFT"))
	_name.add_theme_font_override("font", UITheme.hearth_title_font())
	_name.add_theme_color_override("font_color", UITheme.HEARTH_TEXT)
	_name.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.05))
	_column.add_child(_name)
	_line = _text(String(data.get("line", "")), false, UITheme.TAG_TONES.waiting[0])
	_column.add_child(_line)
	_gap = Control.new()
	_column.add_child(_gap)
	_build_menu()


## The newest save's board, when there is one, then the buttons, the hint and the notice.
func _build_menu() -> void:
	_slot = _newest_slot()
	if not _slot.is_empty():
		board = PanelContainer.new()
		board.add_theme_stylebox_override("panel", UITheme.catalog_paper_style())
		_column.add_child(board)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 18)
		board.add_child(row)
		var words := VBoxContainer.new()
		words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		words.add_theme_constant_override("separation", 4)
		row.add_child(words)
		for part: Array in [[_slot.colony, true, UITheme.CATALOG_INK], [_slot.date, true, UITheme.CATALOG_INK],
				[_slot.saved, false, UITheme.CATALOG_MUTED]]:
			var label := _text(String(part[0]), bool(part[1]), part[2])
			words.add_child(label)
			_slot_labels.append(label)
		buttons["continue"] = _button("Continue", true, _continue)
		buttons["continue"].size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(buttons["continue"])
	for entry: Array in [["new_game", "New game", _new_game], ["load", "Load game…", _open_load],
			["settings", "Settings…", _open_settings], ["exit", "Exit game", _exit]]:
		buttons[entry[0]] = _button(String(entry[1]), board == null and entry[0] == "new_game", entry[2])
		_column.add_child(buttons[entry[0]])
	_hint = _text("Enter continues" if board != null else "Enter starts a new colony", false, UITheme.HEARTH_MUTED)
	_column.add_child(_hint)
	_notice = _text("", false, UITheme.TAG_TONES.blocked[1])
	_notice.visible = false
	_column.add_child(_notice)


## Back from Load game… or Settings…: a save deleted there may have been the newest, so the
## board shows the newest save again, or goes when none is left.
func _on_menu_closed() -> void:
	var newest := _newest_slot()
	if newest.get("id", "") != _slot.get("id", "") or newest.get("saved_unix", 0) != _slot.get("saved_unix", 0):
		for node: Control in [board, _hint, _notice] + buttons.values():
			if node == null or node.get_parent() != _column: continue
			_column.remove_child(node)
			node.queue_free()
		board = null
		buttons = {}
		_slot_labels.clear()
		_build_menu()
		_fit()
	_focus_first()


## The newest save, as Continue loads it: its settlement, its date in the colony and when
## it was saved. Empty without a save.
func _newest_slot() -> Dictionary:
	var newest := {}
	for slot: Dictionary in saves.save_slots():
		if bool(slot.exists) and (newest.is_empty() or int(slot.saved_unix) > int(newest.saved_unix)): newest = slot
	if newest.is_empty(): return {}
	var colony := String(newest.get("colony", ""))
	return {"id": String(newest.id), "saved_unix": int(newest.saved_unix), "colony": colony if not colony.is_empty() else "Your colony",
		"date": Menu.slot_date(newest), "saved": "Saved %s · %s" % [Menu.ago(int(newest.saved_unix)), String(newest.name)]}


func _button(text: String, primary: bool, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	UITheme.apply_hearth_button(button, primary)
	button.pressed.connect(action)
	return button


func _text(text: String, display: bool, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	UITheme.format_label(label, display, MEDIUM.heading, color)
	return label


# ── Choices ───────────────────────────────────────────────────────────────────

func _continue() -> void:
	_start(saves.request_continue(), "That save could not be loaded. Load game… offers the others.")


func _new_game() -> void:
	_start(saves.request_new_game(), "A new colony could not be started just now.")


func _open_load() -> void:
	menu.open_page("load")


func _open_settings() -> void:
	menu.open_page("settings")


func _exit() -> void:
	quit_game.call()


## A world on its way: the buttons wait while it loads. A refusal says why, under them.
func _start(started: bool, failure: String) -> void:
	_notice.text = "" if started else failure
	_notice.visible = not started
	for button: Button in buttons.values(): button.disabled = started


## Keyboard focus: Continue, or New game without a save; back here after Load or Settings.
func _focus_first() -> void:
	if is_inside_tree(): (buttons.get("continue", buttons.new_game) as Button).grab_focus()


# ── Sizes ─────────────────────────────────────────────────────────────────────

## Sizes go by the screen's height, as the game menu's. The column sits at the left of the
## screen's middle 16:9, so on a 32:9 screen it stays left of the centre, not at the far edge.
func _fit() -> void:
	var view := get_viewport().get_visible_rect().size
	_size = SIZES.large if view.y >= 1300.0 else (SIZES.small if view.y < 650.0 else SIZES.medium)
	var s := _size
	var middle := minf(view.x, view.y * 16.0 / 9.0)
	var left := (view.x - middle) * 0.5 + middle * 0.07
	var width := float(s.column)
	var reach := left + width + middle * 0.22
	_shade.texture = _fade((left + width) / reach)
	_shade.position = Vector2.ZERO
	_shade.size = Vector2(reach, view.y)
	_column.position = Vector2(left, view.y * 0.15)
	_column.custom_minimum_size.x = width
	_column.add_theme_constant_override("separation", int(s.gap))
	_name.add_theme_font_size_override("font_size", int(s.mark))
	_name.add_theme_constant_override("outline_size", roundi(float(s.mark) * 0.1))
	_line.add_theme_font_size_override("font_size", int(s.line))
	_gap.custom_minimum_size.y = float(s.gap) * 3.0
	for i in range(_slot_labels.size()):
		_slot_labels[i].add_theme_font_size_override("font_size", int([s.slot, s.slot_date, s.body][i]))
	for id: String in buttons:
		var button: Button = buttons[id]
		var primary := id == "continue" or (board == null and id == "new_game")
		button.custom_minimum_size.y = float(s.button)
		button.add_theme_font_size_override("font_size", int(s.verb if primary else s.plain))
	if buttons.has("continue"): (buttons["continue"] as Button).custom_minimum_size.x = float(s.button) * 2.7
	for label: Label in [_hint, _notice]: label.add_theme_font_size_override("font_size", int(s.note))
	_column.reset_size()


## The shade behind the column: dark at the screen's edge, fading out past the column.
func _fade(stop: float) -> GradientTexture2D:
	var ramp := Gradient.new()
	ramp.set_color(0, Color(SHADE, 0.78))
	ramp.set_color(1, Color(SHADE, 0.0))
	ramp.add_point(stop, Color(SHADE, 0.6))
	var fade := GradientTexture2D.new()
	fade.gradient = ramp
	fade.width = 512
	fade.height = 4
	return fade
