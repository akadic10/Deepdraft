extends VBoxContainer

## One grouped picture grid (doc 261): groups of pictures on family tiles, each tile with an
## optional count and a state mark, the name on hover. Built once and shared by the storage
## Filter and Contents, the crafting recipes, the room's furniture, Place and Inventory. A
## group's heading sits above its tiles, or beside them with `heading_beside` (the storage
## filter's rows). Owners pass plain data to show_groups(). An unchanged refresh keeps the
## nodes; one that changes only looks (counts, marks, dimming, the ring, hover text, pictures
## or hiding) restyles the tiles in place, so focus, hover and scroll stay with them. Pressing
## a tile emits item_pressed; pressing a group's state emits group_pressed. A tile may carry
## a caption under it (the storage filter's category names, Place's woods); a pressable
## caption emits caption_pressed. Presses are reported once the click is over, so an owner
## that rebuilds the grid in answer never frees the button mid-click; a click on a freed
## button falls through to the world behind the window. A rebuild gives keyboard focus back
## to the tile with the same id.
signal item_pressed(id: String)
signal group_pressed(id: String)
signal caption_pressed(id: String)

const MARK_RISE := 8.0   # how far a mark stands above its tile
const MARKS := {"on": ["✓", "fine"], "some": ["−", "waiting"], "missing": ["!", "waiting"], "off": ["✕", "blocked"]}
const STATES := {"All": "fine", "Some": "waiting"}
const LOOKS := ["count", "mark", "dim", "selected", "tooltip", "hidden"]   # restyled in place
# Text sizes come from the type scale (doc 23, "Type").
const MEDIUM := UITheme.TYPE_MEDIUM
var family := Color.TRANSPARENT   # the tiles' colour: the family of the window it sits in
var tile_size := 72.0
var gap := 10.0   # between tiles in a row
var caption_size := 13
var heading_beside := false
var heading_display := false   # headings above the tiles in the display face, as written (Place)
var heading_width := 200.0
var heading_size := 20
var state_size := 15
var board := false   # the grid sits on the pine board, so its captions take the board's dark ink
var _key := ""
var _shape := ""
var _tiles: Dictionary = {}   # item id -> Button
var _holders: Dictionary = {}   # item id -> what hides with it: the tile, or the tile with its name
var _captions: Dictionary = {}   # item id -> its name under the tile
var _rows: Array = []   # [a group's top node, its item ids]


func _init() -> void:
	add_theme_constant_override("separation", 14)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## groups: [{id, title, state ("", "All", "Some" or "None"), items: [{id, picture
## (Texture2D), text (a word in place of a picture), count (shown when 0 or more), mark ("",
## "on", "some", "missing" or "off"), dim, selected, hidden, tooltip, caption,
## caption_button}]}]. A group with neither title nor state has no heading; a group whose
## items are all hidden hides with them.
func show_groups(groups: Array) -> void:
	var key := _describe(groups, true)
	if key == _key: return
	_key = key
	var shape := _describe(groups, false)
	if shape == _shape:
		for group: Dictionary in groups:
			for item: Dictionary in group.get("items", []): _dress(String(item.get("id", "")), item)
		_show_rows()
		return
	_shape = shape
	var owner: Control = get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	var focused := ""
	for id: String in _tiles:
		if _tiles[id] == owner: focused = id
	_tiles.clear()
	_holders.clear()
	_captions.clear()
	_rows.clear()
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	for group: Dictionary in groups:
		var row: BoxContainer = HBoxContainer.new() if heading_beside else VBoxContainer.new()
		row.add_theme_constant_override("separation", 16 if heading_beside else 8)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var top: Control = row
		var titled := not String(group.get("title", "")).is_empty() or not String(group.get("state", "")).is_empty()
		if get_child_count() == 0 and (heading_beside or not titled):
			# The first row's tiles start at the grid's top: leave room for the marks that
			# stand above them, or the edge of a scroll or panel cuts them off.
			var room := MarginContainer.new()
			room.add_theme_constant_override("margin_top", int(MARK_RISE))
			room.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(room)
			room.add_child(row)
			top = room
		else:
			add_child(row)
		if titled:
			row.add_child(_heading(group))
		var flow := HFlowContainer.new()
		# A captioned row lets each name use its tile's gap, so the step stays tile + gap.
		var captioned: bool = group.get("items", []).any(func(item: Dictionary): return not String(item.get("caption", "")).is_empty())
		flow.add_theme_constant_override("h_separation", 0 if captioned else int(gap))
		flow.add_theme_constant_override("v_separation", 12)
		flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(flow)
		var ids: Array[String] = []
		for item: Dictionary in group.get("items", []):
			var id := String(item.get("id", ""))
			var tile := _tile(item)
			_tiles[id] = tile
			ids.append(id)
			var caption := String(item.get("caption", ""))
			if caption.is_empty():
				flow.add_child(tile)
				_holders[id] = tile
			else:
				var stack := VBoxContainer.new()   # the tile with its name under it
				stack.add_theme_constant_override("separation", 2)
				stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
				flow.add_child(stack)
				tile.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN   # square, whatever the name
				stack.add_child(tile)
				_captions[id] = _caption(item, caption)
				stack.add_child(_captions[id])
				_holders[id] = stack
			_dress(id, item)
		_rows.append([top, ids])
	_show_rows()
	if _tiles.has(focused) and _tiles[focused].is_visible_in_tree(): _tiles[focused].grab_focus()


## The tile for an item id, or null.
func get_tile(id: String) -> Button:
	return _tiles.get(id)


## Resize the tiles; the next show_groups() rebuilds them.
func set_tile_size(size: float) -> void:
	if is_equal_approx(size, tile_size): return
	tile_size = size
	_key = ""
	_shape = ""


## The tile's name under it: plain text, or a flat button that emits caption_pressed.
func _caption(item: Dictionary, text: String) -> Control:
	if not bool(item.get("caption_button", false)):
		var label := Label.new()
		label.text = text
		label.custom_minimum_size.x = tile_size + gap - 2.0
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		UITheme.format_label(label, false, caption_size, _caption_colour(false))
		return label
	var button := Button.new()
	button.text = text
	button.flat = true
	button.focus_mode = Control.FOCUS_ALL
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	button.custom_minimum_size.x = tile_size + gap - 2.0
	for look: String in ["normal", "hover", "pressed", "hover_pressed"]:
		button.add_theme_stylebox_override(look, StyleBoxEmpty.new())   # no button margins: the name has the room
	button.add_theme_stylebox_override("focus", UITheme.focus_style())
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # within the tile's width
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_font_override("font", UITheme.body_font())
	button.add_theme_font_size_override("font_size", caption_size)
	button.add_theme_constant_override("h_separation", 0)
	var id := String(item.get("id", ""))
	button.pressed.connect(func(): caption_pressed.emit.call_deferred(id))
	return button


func _caption_colour(dim: bool) -> Color:
	if board: return UITheme.CATALOG_MUTED if dim else UITheme.CATALOG_INK
	return UITheme.HEARTH_MUTED if dim else UITheme.CARD_TEXT


func _tint_caption(caption: Control, dim: bool) -> void:
	var colour := _caption_colour(dim)
	if caption is Label:
		caption.add_theme_color_override("font_color", colour)
		return
	for look: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		caption.add_theme_color_override(look, UITheme.TAG_TONES.waiting[0] if look == "font_hover_color" else colour)


func _heading(group: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if heading_beside: box.custom_minimum_size.x = heading_width
	var title := Label.new()
	title.text = String(group.get("title", ""))
	if heading_beside: UITheme.format_label(title, true, heading_size, UITheme.CARD_TITLE)
	elif heading_display:
		UITheme.format_label(title, true, heading_size, UITheme.TAG_TONES.waiting[0], 5)
		title.add_theme_color_override("font_outline_color", UITheme.CARD_TITLE_OUTLINE)
	else:
		title.text = title.text.to_upper()
		UITheme.format_label(title, false, MEDIUM.small, UITheme.TAG_TONES.waiting[0])
	box.add_child(title)
	var state := String(group.get("state", ""))
	if not state.is_empty():
		# All and Some are tags in their tone; None is quiet text. Each toggles the group.
		var button := Button.new()
		button.text = state
		button.flat = state == "None"
		button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		button.focus_mode = Control.FOCUS_NONE
		var id := String(group.get("id", ""))
		button.pressed.connect(func(): group_pressed.emit.call_deferred(id))
		if STATES.has(state):
			var style: StyleBox = UITheme.cell_style("tag_" + String(STATES[state]), 3)
			for look: String in ["normal", "hover", "pressed", "hover_pressed"]: button.add_theme_stylebox_override(look, style)
			for look: String in ["font_color", "font_hover_color", "font_pressed_color"]: button.add_theme_color_override(look, UITheme.tag_ink(String(STATES[state])))
		else:
			for look: String in ["font_color", "font_hover_color"]: button.add_theme_color_override(look, UITheme.HEARTH_MUTED)
		button.add_theme_font_override("font", UITheme.body_font())
		button.add_theme_font_size_override("font_size", state_size)
		box.add_child(button)
	return box


func _tile(item: Dictionary) -> Button:
	var tile := Button.new()
	tile.name = "Tile_" + String(item.get("id", "")).validate_node_name()
	tile.custom_minimum_size = Vector2.ONE * tile_size
	tile.focus_mode = Control.FOCUS_ALL
	tile.expand_icon = true
	tile.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tile.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	var text := String(item.get("text", ""))
	if not text.is_empty():
		# A word for a picture, such as Place's Any wood.
		tile.text = text
		tile.add_theme_font_override("font", UITheme.display_font())
		tile.add_theme_font_size_override("font_size", maxi(MEDIUM.small, int(tile_size * 0.24)))
		for look: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
			tile.add_theme_color_override(look, UITheme.CARD_TITLE)
	tile.add_theme_stylebox_override("focus", UITheme.focus_style())
	var id := String(item.get("id", ""))
	tile.pressed.connect(func(): item_pressed.emit.call_deferred(id))
	return tile


## A tile's looks: set when it is built, and again by a refresh that changes only looks.
func _dress(id: String, item: Dictionary) -> void:
	var tile: Button = _tiles[id]
	var dim := bool(item.get("dim", false))
	tile.icon = item.get("picture")
	tile.tooltip_text = String(item.get("tooltip", ""))
	var base := family if family.a > 0.0 else UITheme.RAISED_FACE
	for look: String in ["normal", "hover", "pressed", "hover_pressed"]:
		var state := "planned" if dim else look
		tile.add_theme_stylebox_override(look, UITheme.icon_tile_style(base, state))
	for look: String in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color"]:
		tile.add_theme_color_override(look, Color(0.45, 0.45, 0.45) if dim else Color.WHITE)
	for part: String in ["Selected", "Count", "Mark"]:
		var old := tile.get_node_or_null(part)
		if old != null:
			tile.remove_child(old)
			old.queue_free()
	if bool(item.get("selected", false)):
		var frame := Panel.new()
		frame.name = "Selected"
		frame.add_theme_stylebox_override("panel", UITheme.selection_ring())
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		frame.offset_left = -4
		frame.offset_top = -4
		frame.offset_right = 4
		frame.offset_bottom = 4
		tile.add_child(frame)
	var count := int(item.get("count", -1))
	if count >= 0:
		var label := Label.new()
		label.name = "Count"
		label.text = str(count)
		UITheme.format_label(label, true, MEDIUM.lead, UITheme.CARD_TITLE, 5)
		label.add_theme_color_override("font_outline_color", UITheme.CARD_TITLE_OUTLINE)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		label.offset_right = -6
		label.offset_bottom = -2
		tile.add_child(label)
	var mark := String(item.get("mark", ""))
	if MARKS.has(mark):
		var tag := PanelContainer.new()
		tag.name = "Mark"
		tag.add_theme_stylebox_override("panel", UITheme.cell_style("tag_" + String(MARKS[mark][1]), 2))
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var glyph := Label.new()
		glyph.text = MARKS[mark][0]
		UITheme.format_label(glyph, true, MEDIUM.small, UITheme.tag_ink(String(MARKS[mark][1])))
		tag.add_child(glyph)
		tile.add_child(tag)
		tag.position = Vector2(tile_size - 20, -MARK_RISE)
	_holders[id].visible = not bool(item.get("hidden", false))
	if _captions.has(id): _tint_caption(_captions[id], dim)


## A group shows while any of its tiles does.
func _show_rows() -> void:
	for row: Array in _rows:
		var ids: Array[String] = row[1]
		row[0].visible = ids.is_empty() or ids.any(func(id: String): return _holders[id].visible)


## The groups as text. With `looks`, everything a refresh can change; without, only what a
## rebuild must change: the groups and their headings, and each item's id, word and
## caption, in order.
static func _describe(groups: Array, looks: bool) -> String:
	var parts: PackedStringArray = []
	for group: Dictionary in groups:
		parts.append("%s|%s|%s" % [group.get("id", ""), group.get("title", ""), group.get("state", "")])
		for item: Dictionary in group.get("items", []):
			var line := "%s,%s,%s,%s" % [item.get("id", ""), item.get("text", ""), item.get("caption", ""), item.get("caption_button", false)]
			if looks:
				var picture: Variant = item.get("picture")
				line += "," + ((picture as Resource).resource_path if picture is Resource else "")
				for look: String in LOOKS: line += "," + str(item.get(look, ""))
			parts.append(line)
	return "\n".join(parts)
