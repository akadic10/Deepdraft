extends PanelContainer

## The hover card, in Deepdraft's own Hearthblock style (doc 259, the owner's option C):
## a dark hearth slab drawn in voxel cells, its top in the family colour of the button it
## explains. It holds the title, the keys that trigger the command on keycaps, a planned or
## preview status on a hay tag, the explanation, and a stepped pointer at what it explains.
## Owners build one card, fill it with show_card() and place it with point_at(); it never
## takes the mouse.
const GAP := 14.0
const MARGIN := 8.0
const POINTER_ROWS := 3   # the stepped pointer's depth, in cells
var _column: VBoxContainer
var _heading: HBoxContainer
var _title: Label
var _keys: HBoxContainer
var _key_text := ""
var _tag_row: HBoxContainer
var _tag: PanelContainer
var _status: Label
var _body: Label
var _family := Color.TRANSPARENT
var _cell := UITheme.CARD_CELL
var _wide := true
var _art: Texture2D   # kept here: the canvas holds only the texture's RID
var _art_key := ""
var _side := "above"
var _wanted_side := "above"
var _anchor := Rect2()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UITheme.shared_theme()
	_column = VBoxContainer.new()
	_column.add_theme_constant_override("separation", 10)
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_column)
	_heading = HBoxContainer.new()
	_heading.add_theme_constant_override("separation", 18)
	_heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.add_child(_heading)
	_title = _label(_heading)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_keys = HBoxContainer.new()
	_keys.add_theme_constant_override("separation", 6)
	_keys.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_keys.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_heading.add_child(_keys)
	# The row keeps the tag at its own width.
	_tag_row = HBoxContainer.new()
	_tag_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.add_child(_tag_row)
	_tag = PanelContainer.new()
	_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tag_row.add_child(_tag)
	_status = _label(_tag)
	_body = _label(_column)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


## Fill the card. `wide` picks the larger type and cells used at 1200 pixels across and
## more. `family` is the colour of the button's family tile, for the card's top; without
## one the card keeps its plain lit top. `tone` colours the status tag: hay ("waiting"),
## moss ("fine") or rust ("blocked").
func show_card(title: String, body: String, key := "", status := "", wide := true, family := Color.TRANSPARENT, tone := "waiting") -> void:
	_wide = wide
	_cell = UITheme.CARD_CELL if wide else UITheme.CARD_CELL - 1
	_family = family
	var margins := StyleBoxEmpty.new()
	margins.content_margin_left = 22 if wide else 16
	margins.content_margin_right = 22 if wide else 16
	margins.content_margin_top = 18 if wide else 13
	margins.content_margin_bottom = 24 if wide else 18
	add_theme_stylebox_override("panel", margins)
	UITheme.format_label(_title, true, _type().name, UITheme.CARD_TITLE, 6 if wide else 5)
	_title.add_theme_color_override("font_outline_color", UITheme.CARD_TITLE_OUTLINE)
	UITheme.format_label(_status, false, _type().body, UITheme.tag_ink(tone))
	UITheme.format_label(_body, false, _type().lead, UITheme.CARD_TEXT)
	_title.text = title
	_set_keys(key)
	_tag.add_theme_stylebox_override("panel", UITheme.cell_style("tag_" + tone, 3 if wide else 2))
	_status.text = status
	_tag_row.visible = not status.is_empty()
	_body.text = body
	_body.visible = not body.is_empty() and body != title
	_body.custom_minimum_size.x = 400 if wide else 295   # Nunito sets about 3% wider than Segoe UI did
	reset_size()
	queue_redraw()


## The keys the card shows, one per keycap: "Ctrl + ]" shows Ctrl and ].
func shown_keys() -> PackedStringArray:
	var keys := PackedStringArray()
	for cap: Node in _keys.get_children():
		if cap is PanelContainer: keys.append((cap.get_child(0) as Label).text)
	return keys


## Each key of a chord on its own keycap, joined by a plus.
func _set_keys(key: String) -> void:
	_keys.visible = not key.is_empty()
	if key == _key_text and _keys.get_child_count() > 0 and _keys.has_meta("wide") and _keys.get_meta("wide") == _wide:
		return
	_key_text = key
	_keys.set_meta("wide", _wide)
	for child: Node in _keys.get_children():
		_keys.remove_child(child)
		child.queue_free()
	UITheme.add_keycaps(_keys, key, _type().heading, 3 if _wide else 2)


## The card's sizes from the type scale (doc 23, "Type"): the medium tier when wide, the
## small one below 1200 pixels across.
func _type() -> Dictionary:
	return UITheme.TYPE_MEDIUM if _wide else UITheme.TYPE_SMALL


## Sit beside `anchor` (a global rect): above it by default, below when there is no room
## above, or to its left with the tops level. The pointer aims at the anchor's middle.
func point_at(anchor: Rect2, side := "above") -> void:
	_anchor = anchor
	_wanted_side = side
	_place()
	# Once more after layout: wrapped text only knows its final height then.
	_place.call_deferred()


func _place() -> void:
	if not is_inside_tree() or not visible: return
	reset_size()
	var viewport := get_viewport_rect().size
	var side := _wanted_side
	var spot := Vector2(_anchor.get_center().x - size.x * 0.5, _anchor.position.y - GAP - size.y)
	if side == "left": spot = Vector2(_anchor.position.x - GAP - size.x, _anchor.position.y)
	elif spot.y < MARGIN:
		side = "below"
		spot.y = _anchor.end.y + GAP
	position = Vector2(clampf(spot.x, MARGIN, maxf(MARGIN, viewport.x - size.x - MARGIN)),
		clampf(spot.y, MARGIN, maxf(MARGIN, viewport.y - size.y - MARGIN))).round()
	_side = side
	queue_redraw()


func _draw() -> void:
	var w := ceili(size.x / _cell)
	var h := ceili(size.y / _cell)
	var header := 0
	if _family.a > 0.0 and not _title.text.is_empty():
		var top: float = get_theme_stylebox("panel").content_margin_top
		header = ceili((top + _heading.get_combined_minimum_size().y + 12.0) / _cell)
	var side := _side if _anchor.has_area() else ""
	var aim := (_anchor.get_center() - position) / _cell
	var tip := -1
	match side:
		"left": tip = clampi(roundi(aim.y), POINTER_ROWS + 1, h - POINTER_ROWS - 2)
		"above", "below": tip = clampi(roundi(aim.x), POINTER_ROWS + 2, w - POINTER_ROWS - 3)
	var key := "%d %d %d %s %s %d" % [w, h, header, _family.to_html(), side, tip]
	if key != _art_key:
		_art_key = key
		var art := _card_art(w, h, header, side, tip)
		# Whole pixels per cell, drawn nearest, so the cells stay crisp at any UI scale.
		art.resize(art.get_width() * _cell, art.get_height() * _cell, Image.INTERPOLATE_NEAREST)
		_art = UITheme.cell_texture(art)
	var shift := Vector2(0, -POINTER_ROWS * _cell) if side == "below" else Vector2.ZERO
	draw_texture_rect(_art, Rect2(shift, Vector2(_art.get_size())), false)


## The slab with its stepped pointer, one pixel per cell. Pointer cells take the colour of
## the card cells they grow from, so the pointer reads as part of the slab.
func _card_art(w: int, h: int, header: int, side: String, tip: int) -> Image:
	var card := UITheme.cell_slab(w, h, UITheme.CARD_FACE, UITheme.CARD_TOP, UITheme.CARD_SKIRT,
		UITheme.CARD_OUTLINE, 2, 2, _family, header)
	if side.is_empty(): return card
	var rows := POINTER_ROWS
	var art := Image.create(w + (rows if side == "left" else 0), h + (0 if side == "left" else rows), false, Image.FORMAT_RGBA8)
	art.fill(Color.TRANSPARENT)
	var at := Vector2i(0, rows) if side == "below" else Vector2i.ZERO
	art.blit_rect(card, Rect2i(Vector2i.ZERO, card.get_size()), at)
	for j in range(rows):   # j = 0 joins the card; the last row is the tip
		var half := rows - j
		for i in range(-half, half + 1):
			var edge := absi(i) == half or j == rows - 1
			var cell := Vector2i(tip + i, h + j)
			var inner := Vector2i(tip + i, h - 2)
			if side == "left":
				cell = Vector2i(w + j, tip + i)
				inner = Vector2i(w - 2, tip + i)
			elif side == "below":
				cell = Vector2i(tip + i, rows - 1 - j)
				inner = Vector2i(tip + i, 1)
			art.set_pixelv(cell, UITheme.CARD_OUTLINE if edge else card.get_pixelv(inner))
	# Open the card's outline where the pointer joins it.
	for i in range(-(rows - 1), rows):
		if side == "left": art.set_pixel(w - 1, tip + i, card.get_pixel(w - 2, tip + i))
		elif side == "below": art.set_pixel(tip + i, rows, card.get_pixel(tip + i, 1))
		else: art.set_pixel(tip + i, h - 1, card.get_pixel(tip + i, h - 2))
	return art


func _label(parent: Control) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label
