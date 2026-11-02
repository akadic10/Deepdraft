extends MarginContainer

## A Fishing zone's window (doc 289, concept A): the zone's own window, as Storage has one.
## - One line on what the zone does.
## - Its water and fish: the fish's picture, the water's name, how long a fish keeps.
## - The fish in the water: Plenty, Some, Few or Fished out, the count, a bar, and how fast it
##   regrows.
## - Keep: − and + step how many fish the colony keeps before the zone stops, with how many
##   it keeps now.
## - At work: the Rangers fishing here, casting or on their way, or that the colony has none.
## - Remove zone.
## FishingSystem owns the zone; this window shows its zone_data() and asks for changes.
signal keep_step_requested(steps: int)
signal remove_requested

const MUTED := Color("aeb5ad")
const HAY := Color("e2c06a")

var _hint: Label
var _picture: TextureRect
var _water: Label
var _fish: Label
var _word: Label
var _bar: ProgressBar
var _regrowth: Label
var _keep_heading: Label
var _keep: Label
var _kept: Label
var _fewer: Button
var _more: Button
var _work_heading: Label
var _fishers: VBoxContainer
var _remove: Button
var _picture_path := ""
var _type: Dictionary = UITheme.TYPE_MEDIUM


func _ready() -> void:
	UITheme.apply_surface(self)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	add_child(column)
	_hint = _text(column, "Rangers stand on these cells and cast into the water. They stop while the colony keeps enough fish.", MUTED)
	var body := PanelContainer.new()
	body.add_theme_stylebox_override("panel", UITheme.hearth_panel(true))
	column.add_child(body)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 8)
	body.add_child(inner)
	var water := HBoxContainer.new()
	water.add_theme_constant_override("separation", 14)
	inner.add_child(water)
	_picture = TextureRect.new()
	_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var frame := UITheme.framed_picture(_picture)
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	water.add_child(frame)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	water.add_child(words)
	_water = _text(words, "", UITheme.CARD_TITLE, true)
	_fish = _text(words, "")
	_text(inner, "FISH IN THE WATER", HAY, false, "small")
	_word = _text(inner, "", HAY, true, "heading")
	_bar = ProgressBar.new()
	UITheme.hearth_progress(_bar)
	_bar.show_percentage = false
	inner.add_child(_bar)
	_regrowth = _text(inner, "", MUTED, false, "small")
	inner.add_child(HSeparator.new())
	_keep_heading = _text(inner, "KEEP", HAY, false, "small")
	var keep := HBoxContainer.new()
	keep.add_theme_constant_override("separation", 8)
	inner.add_child(keep)
	_fewer = UITheme.make_button("−", "Keep fewer fish")
	_fewer.pressed.connect(func(): keep_step_requested.emit(-1))
	keep.add_child(_fewer)
	_keep = _text(keep, "", UITheme.CARD_TEXT, true, "heading")
	_keep.autowrap_mode = TextServer.AUTOWRAP_OFF
	_keep.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_keep.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_more = UITheme.make_button("+", "Keep more fish")
	_more.pressed.connect(func(): keep_step_requested.emit(1))
	keep.add_child(_more)
	_kept = _text(keep, "", MUTED)
	_kept.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_kept.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	inner.add_child(HSeparator.new())
	_work_heading = _text(inner, "", HAY, false, "small")
	_fishers = VBoxContainer.new()
	_fishers.add_theme_constant_override("separation", 6)
	inner.add_child(_fishers)
	_remove = UITheme.make_button("Remove zone", "Unmark these spots. A fisher at work stops; nothing is lost.", Vector2(0, 32), "danger")
	_remove.pressed.connect(func(): remove_requested.emit())
	column.add_child(_remove)
	get_viewport().size_changed.connect(_fit)
	_fit()


## Fills the window from FishingSystem.zone_data().
func show_zone(data: Dictionary) -> void:
	if data.is_empty() or _water == null: return
	if String(data.picture) != _picture_path:
		_picture_path = String(data.picture)
		_picture.texture = load(_picture_path) if ResourceLoader.exists(_picture_path) else null
	_water.text = String(data.water)
	_fish.text = "%s · a portion each, keeps %d days" % [data.fish_name, roundi(float(data.keeps_days))]
	_word.text = "%s · %d of %d" % [data.word, data.stock, data.maximum]
	_bar.max_value = maxi(1, int(data.maximum))
	_bar.value = int(data.stock)
	_regrowth.text = "Regrows about %d a day · Fished out below %d" % [roundi(float(data.regrowth)), int(data.fished_out_below)]
	_keep.text = "%d fish" % int(data.keep)
	var state := "fishing" if bool(data.wants) else ("the water is fished out" if data.word == "Fished out" else "enough kept, paused")
	_kept.text = "%d kept now · %s" % [int(data.kept), state]
	_work_heading.text = "AT WORK · %d OF %d SPOT%s" % [data.fishers.size(), data.spots, "" if int(data.spots) == 1 else "S"]
	for child in _fishers.get_children(): child.queue_free()
	if data.fishers.is_empty():
		# Fishing is the Ranger's work (doc 292).
		_text(_fishers, "No Ranger yet: promote one to fish here." if bool(data.get("no_fisher", false)) else "No one is fishing here now. Rangers need Fish allowed in Labor.", MUTED)
	for fisher: Dictionary in data.fishers:
		_text(_fishers, "%s · %s" % [fisher.name, fisher.doing])


## Sizes by the screen's height, as the Storage window's: large from 1300 px tall, small
## below 650.
func _fit() -> void:
	var height := get_viewport_rect().size.y
	_type = UITheme.TYPE_LARGE if height >= 1300 else (UITheme.TYPE_SMALL if height < 650 else UITheme.TYPE_MEDIUM)
	var big := _type == UITheme.TYPE_LARGE
	custom_minimum_size.x = 560 if big else 420   # wrapping needs a width to wrap to
	for edge: String in ["left", "right"]: add_theme_constant_override("margin_" + edge, 20 if big else 14)
	add_theme_constant_override("margin_top", 12 if big else 8)
	add_theme_constant_override("margin_bottom", 12 if big else 8)
	_picture.custom_minimum_size = Vector2.ONE * (84 if big else 64)
	_bar.custom_minimum_size.y = 14 if big else 10
	for button: Button in [_fewer, _more]: button.custom_minimum_size = Vector2(44, 40) if big else Vector2(34, 30)
	_keep.custom_minimum_size.x = 96 if big else 72
	_remove.custom_minimum_size.y = 40 if big else 32
	for label: Label in find_children("*", "Label", true, false):
		label.add_theme_font_size_override("font_size", int(_type.get(String(label.get_meta("size", "body")), _type.body)))


func _text(parent: Node, value: String, color := UITheme.CARD_TEXT, display := false, size := "body") -> Label:
	var label := Label.new()
	label.text = value
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.set_meta("size", "title" if display and size == "body" else size)
	UITheme.format_label(label, display, int(_type.get(String(label.get_meta("size")), _type.body)), color)
	parent.add_child(label)
	return label
