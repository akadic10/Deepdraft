extends MarginContainer

## A field's window (doc 309): the zone's own window, as Storage and Fishing have one.
## - One line on what a field is.
## - The year's plan: a tile for each season with its crop's picture and a line on it, the season
##   it is now lit and marked NOW. A click on a season lists the crops that can be sown in it, each with its
##   days, what a tile gives and how long it keeps; one no Farmer may sow yet says the level it
##   needs.
## - In the field: tiles hoed, sown and ripe, what ripens next, and how many tiles are damp.
## - The bushes and fruit trees the Farmers pick here.
## - At work: the Farmers here and what each is doing, or that the colony has none.
## - Remove field.
## FarmingSystem owns the field; this window shows its zone_data() and asks for changes.
signal plan_requested(season: String, crop_key: String)
signal remove_requested

const MUTED := UITheme.MUTED
const HAY := UITheme.HAY

var _seasons: Dictionary = {}       # season -> {"button", "name", "picture", "crop", "note"}
var _season_row: HBoxContainer
var _choices_heading: Label
var _choices: VBoxContainer
var _counts: Label
var _growing: Label
var _water: Label
var _standing: Label
var _work_heading: Label
var _farmers: VBoxContainer
var _remove: Button
var _open_season := ""
var _choices_shown := ""            # what the list was last built from
var _pictures: Dictionary = {}
var _type: Dictionary = UITheme.TYPE_MEDIUM


func _ready() -> void:
	UITheme.apply_surface(self)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	add_child(column)
	_text(column, "A Farmer hoes this ground, sows each season's crop and pulls it when ripe. Bushes and fruit trees inside are picked too.", MUTED)
	var body := PanelContainer.new()
	body.add_theme_stylebox_override("panel", UITheme.hearth_panel(true))
	column.add_child(body)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 8)
	body.add_child(inner)
	_text(inner, "THE YEAR'S PLAN", HAY, false, "small")
	_season_row = HBoxContainer.new()
	_season_row.add_theme_constant_override("separation", 6)
	inner.add_child(_season_row)
	_choices_heading = _text(inner, "", HAY, false, "small")
	_choices = VBoxContainer.new()
	_choices.add_theme_constant_override("separation", 4)
	inner.add_child(_choices)
	inner.add_child(HSeparator.new())
	_text(inner, "IN THE FIELD", HAY, false, "small")
	_counts = _text(inner, "")
	_growing = _text(inner, "")
	_water = _text(inner, "", MUTED, false, "small")
	_standing = _text(inner, "", MUTED, false, "small")
	inner.add_child(HSeparator.new())
	_work_heading = _text(inner, "AT WORK", HAY, false, "small")
	_farmers = VBoxContainer.new()
	_farmers.add_theme_constant_override("separation", 6)
	inner.add_child(_farmers)
	_remove = UITheme.make_button("Remove field", "Unmark this field. Its plants go with it; the tilled soil stays.", Vector2(0, 32), "danger")
	_remove.pressed.connect(func(): remove_requested.emit())
	column.add_child(_remove)
	get_viewport().size_changed.connect(_fit)
	_fit()


## Fills the window from FarmingSystem.zone_data().
func show_field(data: Dictionary) -> void:
	if data.is_empty() or _counts == null: return
	for entry: Dictionary in data.plan: _show_season(entry)
	_show_choices(data)
	var counts: Dictionary = data.counts
	var tiles := int(counts.tiles)
	_counts.text = "%d tile%s · %d hoed · %d sown · %d ripe" % [tiles, "" if tiles == 1 else "s", int(counts.tilled), int(counts.sown), int(counts.ripe)]
	if int(counts.alone) > 0: _counts.text += " · %d left alone" % int(counts.alone)
	_growing.text = String(data.growing)
	_growing.visible = not _growing.text.is_empty()
	_water.text = "Rain today: every tile is damp, and damp soil grows a crop faster." if bool(data.wet_sky) \
		else "%d of %d tiles damp. Damp soil grows a crop faster." % [int(counts.damp), tiles]
	var standing: Array[String] = []
	if int(data.bushes) > 0: standing.append("%d bush%s" % [int(data.bushes), "" if int(data.bushes) == 1 else "es"])
	if int(data.trees) > 0: standing.append("%d tree%s" % [int(data.trees), "" if int(data.trees) == 1 else "s"])
	_standing.text = "Standing here: %s. Their fruit is picked as it ripens." % " and ".join(standing)
	_standing.visible = not standing.is_empty()
	_work_heading.text = "AT WORK · %d FARMER%s" % [data.farmers.size(), "" if data.farmers.size() == 1 else "S"]
	for child in _farmers.get_children(): child.queue_free()
	if data.farmers.is_empty():
		_text(_farmers, "No Farmer yet: a dwarf becomes one by collecting a copper hoe, which a Blacksmith makes." if bool(data.no_farmer) \
			else "No one is working here now. Farmers need Farm allowed in Labor.", MUTED)
	for farmer: Dictionary in data.farmers:
		_text(_farmers, "%s · %s" % [farmer.name, farmer.doing])


## One season's tile: its crop's picture and name and a line on it. The season it is now is lit.
func _show_season(entry: Dictionary) -> void:
	var season := String(entry.season)
	if not _seasons.has(season): _build_season(season)
	var parts: Dictionary = _seasons[season]
	(parts.name as Label).text = season.to_upper()
	(parts.name as Label).add_theme_color_override("font_color", HAY if bool(entry.now) else MUTED)
	(parts.now as Label).text = "NOW" if bool(entry.now) else ""
	(parts.picture as TextureRect).texture = _picture(String(entry.picture))
	(parts.crop as Label).text = String(entry.name)
	var locked := String(entry.locked)
	(parts.note as Label).text = locked if not locked.is_empty() else String(entry.note)
	(parts.note as Label).add_theme_color_override("font_color", UITheme.DANGER_RED if not locked.is_empty() else MUTED)
	(parts.button as Button).set_pressed_no_signal(season == _open_season)
	(parts.button as Button).tooltip_text = "Choose what is sown in %s." % season


func _build_season(season: String) -> void:
	var button := UITheme.make_button("", "")
	button.toggle_mode = true
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.clip_contents = true
	button.pressed.connect(func():
		_open_season = "" if _open_season == season else season
		_choices_shown = ""
		for other: String in _seasons: (_seasons[other].button as Button).set_pressed_no_signal(other == _open_season)
		_choices_wanted.call_deferred())
	_season_row.add_child(button)
	var stack := VBoxContainer.new()
	stack.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 4)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.add_theme_constant_override("separation", 2)
	button.add_child(stack)
	var name_label := _text(stack, "", MUTED, false, "small")
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	# A line of its own under the name, kept on every tile so the pictures stay level.
	var now_label := _text(stack, "", HAY, false, "small")
	now_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	now_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	var picture := TextureRect.new()
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(picture)
	var crop := _text(stack, "", UITheme.CARD_TITLE, true, "lead")
	crop.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var note := _text(stack, "", MUTED, false, "small")
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_seasons[season] = {"button": button, "name": name_label, "now": now_label, "picture": picture, "crop": crop, "note": note}
	_fit()


## The last data shown, kept so an opened season can list its crops at once.
var _last: Dictionary = {}


func _choices_wanted() -> void:
	if not _last.is_empty(): _show_choices(_last)


## The crops that can be sown in the opened season. The list is rebuilt only when it changes, so
## a click is never lost to the window's own refresh.
func _show_choices(data: Dictionary) -> void:
	_last = data
	var opened: Dictionary = {}
	for entry: Dictionary in data.plan:
		if String(entry.season) == _open_season: opened = entry
	_choices_heading.visible = not opened.is_empty()
	_choices.visible = not opened.is_empty()
	if opened.is_empty():
		_choices_shown = ""
		return
	var built := _open_season + ">" + String(opened.crop)
	for choice: Dictionary in opened.choices: built += "|%s:%s" % [choice.crop, choice.locked]
	if built == _choices_shown: return
	_choices_shown = built
	_choices_heading.text = "SOWN IN %s" % _open_season.to_upper()
	for child in _choices.get_children(): child.queue_free()
	for choice: Dictionary in opened.choices:
		var locked := String(choice.locked)
		var chosen := String(choice.crop) == String(opened.crop)
		var row := UITheme.make_button("", locked if not locked.is_empty() else String(choice.get("idea", choice.words)))
		row.disabled = not locked.is_empty()
		row.clip_contents = true
		row.set_meta("choice", true)
		if chosen: UITheme.apply_hearth_button(row, true)
		var season := _open_season
		var crop_key := String(choice.crop)
		row.pressed.connect(func():
			_open_season = ""
			plan_requested.emit(season, crop_key))
		_choices.add_child(row)
		var line := HBoxContainer.new()
		line.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_theme_constant_override("separation", 10)
		row.add_child(line)
		var picture := TextureRect.new()
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		picture.texture = _picture(String(choice.picture))
		picture.set_meta("choice_picture", true)
		line.add_child(picture)
		var words := VBoxContainer.new()
		words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		words.alignment = BoxContainer.ALIGNMENT_CENTER
		words.mouse_filter = Control.MOUSE_FILTER_IGNORE
		words.add_theme_constant_override("separation", 0)
		line.add_child(words)
		var title := _text(words, String(choice.name) + (" · in the plan" if chosen else ""), UITheme.TEXT_DISABLED if not locked.is_empty() else UITheme.CARD_TEXT)
		title.autowrap_mode = TextServer.AUTOWRAP_OFF
		var detail := _text(words, locked if not locked.is_empty() else String(choice.words), UITheme.DANGER_RED if not locked.is_empty() else MUTED, false, "small")
		detail.autowrap_mode = TextServer.AUTOWRAP_OFF
	_fit()


func _picture(path: String) -> Texture2D:
	if path.is_empty(): return null
	if not _pictures.has(path): _pictures[path] = load(path) if ResourceLoader.exists(path) else null
	return _pictures[path]


## Sizes by the screen's height, as the Storage and Fishing windows': large from 1300 px tall,
## small below 650.
func _fit() -> void:
	if _remove == null: return
	var height := get_viewport_rect().size.y
	_type = UITheme.TYPE_LARGE if height >= 1300 else (UITheme.TYPE_SMALL if height < 650 else UITheme.TYPE_MEDIUM)
	var big := _type == UITheme.TYPE_LARGE
	custom_minimum_size.x = 600 if big else 452   # wrapping needs a width to wrap to
	for edge: String in ["left", "right"]: add_theme_constant_override("margin_" + edge, 20 if big else 14)
	add_theme_constant_override("margin_top", 12 if big else 8)
	add_theme_constant_override("margin_bottom", 12 if big else 8)
	for season: String in _seasons:
		var parts: Dictionary = _seasons[season]
		(parts.button as Button).custom_minimum_size = Vector2(0, 200 if big else 158)
		(parts.picture as TextureRect).custom_minimum_size = Vector2.ONE * (64 if big else 48)
	for row: Button in _choices.find_children("*", "Button", false, false):
		row.custom_minimum_size = Vector2(0, 58 if big else 46)
	for picture: TextureRect in _choices.find_children("*", "TextureRect", true, false):
		picture.custom_minimum_size = Vector2.ONE * (46 if big else 36)
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
