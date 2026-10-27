extends MarginContainer

## The founding card (doc 23): planting the settlement flag asks for the settlement's name.
## A window in the people family over the world, clear of the flag that waits where the
## player clicked. The field holds the world's first suggestion, Suggest another draws the
## next, and Found <name> plants the flag and brings the dwarves. Cancel, ✕ or Esc keeps
## the flag tool. A name outside SettlementName's rules keeps Found off and says why.
signal found_requested(settlement_name: String)
signal cancelled

const SettlementName = preload("res://scripts/components/SettlementName.gd")
const NOTE := "Suggested from the world's seed. You can rename it later in Colony."
const MUTED := Color("aeb5ad")
# Text sizes come from the type scale (doc 23, "Type").
const LARGE := UITheme.TYPE_LARGE
const MEDIUM := UITheme.TYPE_MEDIUM
const SMALL := UITheme.TYPE_SMALL
## Sizes by the screen's height, as the windows': large from 1300 px tall (the concept's,
## on the 7680×2160 screen), small below 650 px.
const SIZES := {
	"large": {"width": 900, "margin": 24, "gap": 16, "ask": LARGE.lead, "field": LARGE.name, "button": 64, "verb": LARGE.lead, "main": LARGE.lead, "note": LARGE.body, "type": LARGE},
	"medium": {"width": 640, "margin": 16, "gap": 12, "ask": MEDIUM.lead, "field": MEDIUM.name, "button": 48, "verb": MEDIUM.lead, "main": MEDIUM.lead, "note": MEDIUM.body, "type": MEDIUM},
	"small": {"width": 480, "margin": 12, "gap": 8, "ask": SMALL.lead, "field": SMALL.name, "button": 38, "verb": SMALL.lead, "main": SMALL.lead, "note": SMALL.body, "type": SMALL},
}

var window: UIWindow
## Draws the suggestions: FlagPlacementController, or a stand-in with suggestion(index).
var names: Object
var _size: Dictionary = SIZES.medium
var _index := 0
var _column: VBoxContainer
var _line: HBoxContainer
var _choices: HBoxContainer
var _ask: Label
var _field: LineEdit
var _suggest: Button
var _note: Label
var _cancel: Button
var _found: Button


func _ready() -> void:
	UITheme.apply_surface(self)
	_column = VBoxContainer.new()
	add_child(_column)
	_ask = _label("Name your settlement")
	_column.add_child(_ask)
	_line = HBoxContainer.new()
	_column.add_child(_line)
	_field = LineEdit.new()
	_field.name = "Name"
	_field.max_length = SettlementName.MAX_LENGTH
	_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_field.add_theme_font_override("font", UITheme.display_font())
	_field.add_theme_color_override("font_color", UITheme.CARD_TITLE)
	_field.add_theme_color_override("caret_color", UITheme.TAG_TONES.waiting[0])
	for state: String in ["normal", "focus"]: _field.add_theme_stylebox_override(state, UITheme.cell_style("inset", 3))
	_field.text_changed.connect(func(_text: String): _check())
	_field.text_submitted.connect(func(_text: String): _submit())
	_field.gui_input.connect(_on_field_input)
	_line.add_child(_field)
	_suggest = _button("Suggest another", false, "Draw the next name the world's seed suggests")
	_suggest.pressed.connect(_next_suggestion)
	_line.add_child(_suggest)
	_note = _label(NOTE)
	_column.add_child(_note)
	_choices = HBoxContainer.new()
	_choices.alignment = BoxContainer.ALIGNMENT_END
	_column.add_child(_choices)
	_cancel = _button("Cancel", false, "Keep the flag tool and choose another place")
	_cancel.pressed.connect(func(): cancelled.emit())
	_choices.add_child(_cancel)
	_found = _button("Found the settlement", true, "Plant the flag here. Your dwarves arrive with it.")
	_found.name = "Found"
	_found.pressed.connect(_submit)
	_choices.add_child(_found)
	_apply_size()


## A new founding: the world's first suggestion, ready to keep or to type over.
func begin() -> void:
	_index = 0
	_field.text = String(names.suggestion(0)) if names != null else ""
	_check()
	var height := get_viewport_rect().size.y
	_size = SIZES.large if height >= 1300.0 else (SIZES.small if height < 650.0 else SIZES.medium)
	_apply_size()
	_field.grab_focus.call_deferred()
	_field.select_all.call_deferred()


## Over the world near the top, clear of the waiting flag at `spot` (its point on the screen)
## and of the dock.
func place_clear_of(spot: Vector2, dock_top: float) -> void:
	if window == null: return
	window.reset_size()
	var at := Vector2(roundf((get_viewport_rect().size.x - window.size.x) / 2.0), 76.0)
	if Rect2(at, window.size).grow(48.0).has_point(spot):
		at.y = spot.y + 72.0
		if at.y + window.size.y > dock_top - 8.0: at.y = spot.y - 120.0 - window.size.y
	window.position = at
	window.clamp_to_viewport()


func _next_suggestion() -> void:
	_index += 1
	var suggestion := String(names.suggestion(_index))
	if suggestion == SettlementName.clean(_field.text):
		_index += 1
		suggestion = String(names.suggestion(_index))
	_field.text = suggestion
	_field.caret_column = suggestion.length()
	_check()


## Found waits for a name in the rules, says the name it will found, and the note says why
## while it waits.
func _check() -> void:
	var valid := SettlementName.is_valid(_field.text)
	_found.disabled = not valid
	_found.text = "Found " + SettlementName.clean(_field.text) if valid else "Found the settlement"
	_note.text = NOTE if valid else SettlementName.RULE
	_note.add_theme_color_override("font_color", MUTED if valid else UITheme.TAG_TONES.blocked[1])


func _submit() -> void:
	if SettlementName.is_valid(_field.text): found_requested.emit(SettlementName.clean(_field.text))


func _on_field_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
		_field.accept_event()
		cancelled.emit()


func _apply_size() -> void:
	var s := _size
	custom_minimum_size.x = float(s.width) - 8.0   # the window's frame brings 4 px a side
	for side: String in ["left", "right", "top", "bottom"]: add_theme_constant_override("margin_" + side, s.margin)
	for box: BoxContainer in [_column, _line, _choices]: box.add_theme_constant_override("separation", s.gap)
	_ask.add_theme_font_size_override("font_size", s.ask)
	_note.add_theme_font_size_override("font_size", s.note)
	_field.add_theme_font_size_override("font_size", s.field)
	_field.custom_minimum_size.y = float(s.button) + 8.0
	for button: Button in [_suggest, _cancel, _found]:
		button.custom_minimum_size.y = float(s.button)
		button.add_theme_font_size_override("font_size", s.main if button == _found else s.verb)
	_cancel.custom_minimum_size.x = float(s.button) * 2.6
	_found.custom_minimum_size.x = float(s.button) * 5.2
	if window != null and window.visible: window.reset_size()


func _button(text: String, main: bool, tooltip: String) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tooltip
	UITheme.apply_hearth_button(button, main)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return button


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", UITheme.body_font())
	label.add_theme_color_override("font_color", MUTED)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
