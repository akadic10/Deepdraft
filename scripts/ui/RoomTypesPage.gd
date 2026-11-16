extends VBoxContainer

## The room window's Types tab (doc 23 "The Rooms Tool"): every room type with its picture,
## what it needs and what it is for, from room_kinds.json through RoomManager's RoomKinds.
## - The room's own type is tagged "This room" (a personal bedroom under the bedroom).
## - A plain room is told the steps from it to each type.
## - A line under the list says a room takes the first type it fits, in the list's order.
## It builds again only when what it says changes. Presentation only.
const HAY := UITheme.HAY
const MUTED := UITheme.MUTED

## The window's sizes for the screen (RoomInspectorPanel.SIZES): tile, name, goal, tag, gap.
var sizes: Dictionary = {}
## What each listed type shows, by its id: {name, needs, gives, steps, mine}.
var entries := {}
var _shown: Array = []


func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


## Takes the window's sizes; the next show builds the page again at them.
func set_sizes(table: Dictionary) -> void:
	sizes = table
	_shown.clear()


func show_room(room: Dictionary) -> void:
	if sizes.is_empty(): return
	var kinds = RoomManager.kinds
	var own: Dictionary = kinds.kind_of(room)
	var listed: Array = kinds.listed()
	var state := []
	for kind: Dictionary in listed:
		var mine: bool = not own.is_empty() and kinds.listed_id(own) == String(kind.id)
		state.append([String(kind.id), mine, "" if not own.is_empty() else kinds.steps_words(room, kind)])
	if state == _shown: return
	_shown = state.duplicate(true)
	for child in get_children():
		remove_child(child)
		child.queue_free()
	entries.clear()
	add_theme_constant_override("separation", int(sizes.gap) + 6)
	_line("What a sealed room holds, and how warm it is, decides its type.", MUTED, self)
	for i in range(listed.size()): _entry(listed[i], bool(state[i][1]), String(state[i][2]))
	_line("A room that fits several types takes the first of them, in this order.", MUTED, self)


## A type: its picture, its name (tagged when it is this room's), what it needs, what it is
## for and, for a plain room, the steps to it.
func _entry(kind: Dictionary, mine: bool, steps: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	add_child(row)
	var picture := TextureRect.new()
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	picture.texture = UIRegistry.get_room_symbol(String(kind.get("symbol", "walls")))
	var frame := UITheme.framed_picture(picture)   # on the settlement tile
	frame.custom_minimum_size = Vector2.ONE * float(sizes.tile)
	frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(frame)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.add_theme_constant_override("separation", 2)
	row.add_child(words)
	var title := HBoxContainer.new()
	title.add_theme_constant_override("separation", 10)
	words.add_child(title)
	var label := Label.new()
	label.text = String(kind.label)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UITheme.format_label(label, true, int(sizes.name), UITheme.CARD_TITLE)
	title.add_child(label)
	if mine: title.add_child(_tag("This room"))
	var needs := _line(RoomManager.kinds.needs_sentence(kind), UITheme.CARD_TEXT, words)
	var gives := _line(String(kind.get("gives", "")), MUTED, words)
	if not steps.is_empty(): _line("For this room: %s." % steps, HAY, words)
	entries[String(kind.id)] = {"name": label.text, "needs": needs.text, "gives": gives.text, "steps": steps, "mine": mine}


func _tag(text: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.cell_style("tag_fine", 3))
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var label := Label.new()
	label.text = text
	UITheme.format_label(label, false, int(sizes.tag), UITheme.tag_ink("fine"))
	panel.add_child(label)
	return panel


func _line(text: String, colour: Color, parent: Control) -> Label:
	var label := Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UITheme.format_label(label, false, int(sizes.goal), colour)
	parent.add_child(label)
	return label
