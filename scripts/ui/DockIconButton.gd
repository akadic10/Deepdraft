extends Button

## Illustrated dock command. The approved artwork stays in one shared atlas;
## its region, caption and action are supplied by UIRegistry/DockUI.
var caption: String
var description: String
var planned := false
var preview := false
var status_label := ""
var key_hint := ""   # the key that triggers this command, from its entry's key_action
var family_color := Color.TRANSPARENT   # its family tile's colour, the top of its hover card
var count_text := ""   # a count on the tile's corner (doc 23, "Counts"); empty hides it
var count_tone := "waiting"   # hay, moss ("fine") or rust ("blocked") while something needs attention
var count_note := ""   # what the count counts, on the hover card's tag: "2 dwarves are idle"
## The shelf this button sits on, if any: its hover card stands above the whole shelf, so on a
## shelf of two rows it never covers the row above (doc 23, "Copy and Blueprints").
var shelf: Control
var _hovered := false
var _info_suppressed := false
var _info_timer: Timer
var _info_layer: CanvasLayer
var _info: Control


func setup(entry: Dictionary, artwork: Texture2D) -> void:
	caption = String(entry.label)
	description = String(entry.get("tooltip", entry.label))
	planned = bool(entry.get("planned", false))
	preview = bool(entry.get("preview", false))
	status_label = String(entry.get("status_label", "Planned" if planned else "DEV preview"))
	key_hint = key_text(String(entry.get("key_action", "")))
	icon = artwork
	text = ""
	focus_mode = Control.FOCUS_ALL
	toggle_mode = not planned
	expand_icon = true
	icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	# Hearthblock icons (doc 259) sit on a tile in their family's colour. The registry is
	# fetched from the tree, so scripts that preload this button still compile.
	var family := String(entry.get("family", ""))
	var registry: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("UIRegistry")
	var tile: Color = Color.TRANSPARENT if family.is_empty() or registry == null else registry.get_icon_family_color(family)
	family_color = tile
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		if tile.a == 0.0 or state == "focus":
			add_theme_stylebox_override(state, StyleBoxEmpty.new())
		else:
			add_theme_stylebox_override(state, UITheme.icon_tile_style(tile, "planned" if planned and state == "normal" else state))
		add_theme_color_override("icon_" + state + "_color", Color(.48, .48, .48) if planned else Color.WHITE)
	if tile.a > 0.0:
		add_theme_stylebox_override("disabled", UITheme.icon_tile_style(tile, "disabled"))
	add_theme_color_override("icon_hover_color", Color(.65, .65, .65) if planned else Color(1.10, 1.10, 1.10))


func _ready() -> void:
	_info_timer = Timer.new()
	_info_timer.one_shot = true
	_info_timer.wait_time = 0.3
	add_child(_info_timer)
	_info_timer.timeout.connect(_show_info)
	mouse_entered.connect(func():
		_hovered = true
		_info_suppressed = false
		_info_timer.start()
		queue_redraw())
	mouse_exited.connect(func():
		_hovered = false
		_hide_info()
		queue_redraw())
	focus_entered.connect(func():
		_info_suppressed = false
		_info_timer.start()
		queue_redraw())
	focus_exited.connect(_hide_info)
	pressed.connect(func():
		# Planned commands remain focusable so their status is accessible.
		if planned:
			_info_suppressed = false
			_show_info()
			return
		_info_suppressed = true
		_hide_info())
	toggled.connect(func(_on: bool): queue_redraw())
	resized.connect(_hide_info)
	visibility_changed.connect(_hide_info)


func _draw() -> void:
	if planned:
		# The lock distinguishes availability without relying on dimming alone.
		var badge := Vector2(size.x - 13, size.y - 13)
		draw_circle(badge, 10, UITheme.HEARTH_BG)
		draw_arc(badge + Vector2(0, -2), 4, PI, TAU, 12, UITheme.HEARTH_COPPER, 2, true)
		draw_rect(Rect2(badge + Vector2(-5, -2), Vector2(10, 7)), UITheme.HEARTH_COPPER)
		draw_line(badge + Vector2(0, 0), badge + Vector2(0, 3), UITheme.HEARTH_BG, 2)
	elif preview:
		# A small flask marks a usable development preview, distinct from a lock.
		var badge := Vector2(size.x - 13, size.y - 13)
		draw_circle(badge, 10, UITheme.HEARTH_BG)
		var outline := PackedVector2Array([Vector2(-2,-6), Vector2(-2,-2),
			Vector2(-6,5), Vector2(6,5), Vector2(2,-2), Vector2(2,-6)])
		for i in outline.size(): outline[i] += badge
		draw_polyline(outline, UITheme.HEARTH_COPPER, 1.5, true)
		draw_line(badge + Vector2(-3,-6), badge + Vector2(3,-6), UITheme.HEARTH_COPPER, 2)
		draw_line(badge + Vector2(-3,2), badge + Vector2(3,2), UITheme.HEARTH_COPPER, 2)
	if button_pressed or _hovered or has_focus(): _draw_outline()
	if not count_text.is_empty():
		# The count, over everything else on the tile: a tag in its tone with dark or light ink.
		var chip := count_rect()
		draw_style_box(UITheme.cell_style("tag_" + count_tone, 3), chip)
		var font := UITheme.display_font()
		var font_size := int(chip.size.y * 0.6)
		var baseline := chip.position.y + (chip.size.y + font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5 - 2.0
		draw_string(font, Vector2(chip.position.x, baseline), count_text, HORIZONTAL_ALIGNMENT_CENTER, chip.size.x,
			font_size, UITheme.tag_ink(count_tone))


func _draw_outline() -> void:
	var edge := UITheme.HEARTH_COPPER if button_pressed else UITheme.HEARTH_TEXT
	var inset := 3.0
	var cut := size.x * 0.08
	var x := size.x - inset
	var y := size.y - inset
	var points := PackedVector2Array([
		Vector2(inset + cut, inset), Vector2(x - cut, inset),
		Vector2(x, inset + cut), Vector2(x, y - cut),
		Vector2(x - cut, y), Vector2(inset + cut, y),
		Vector2(inset, y - cut), Vector2(inset, inset + cut),
		Vector2(inset + cut, inset)])
	draw_polyline(points, edge, 2.0 if button_pressed else 1.0, true)
	if button_pressed:
		# A solid notch also distinguishes the active command without color.
		var center := Vector2(size.x * 0.5, size.y - 4)
		draw_colored_polygon(PackedVector2Array([center + Vector2(-7, 0),
			center + Vector2(0, -5), center + Vector2(7, 0)]), UITheme.HEARTH_COPPER)


## Shows a count on the tile's top right corner in its tone: hay, moss ("fine"), or rust
## ("blocked") while something needs attention. `note` says on the hover card what it
## counts. An empty text hides it.
func show_count(text: String, tone := "waiting", note := "") -> void:
	if text == count_text and tone == count_tone and note == count_note: return
	count_text = text
	count_tone = tone
	count_note = note
	queue_redraw()


## Where the count sits: overhanging the tile's top right corner, 30 px tall on a 72 px tile.
func count_rect() -> Rect2:
	var side := roundf(size.x * 0.42)
	var text_width := UITheme.display_font().get_string_size(count_text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(side * 0.6)).x
	var width := maxf(side, ceilf(text_width + side * 0.5))
	return Rect2(Vector2(size.x - width + roundf(side * 0.3), -roundf(side * 0.3)), Vector2(width, side))


func _hide_info() -> void:
	if _info_timer != null: _info_timer.stop()
	if _info != null: _info.hide()
	queue_redraw()


func _show_info() -> void:
	if _info_suppressed or not is_visible_in_tree() or not (_hovered or has_focus()): return
	if _info == null:
		_info_layer = CanvasLayer.new()
		_info_layer.layer = 30
		add_child(_info_layer)
		_info = preload("res://scripts/ui/HoverCard.gd").new()
		_info_layer.add_child(_info)
	# The hover card (doc 259, option C): the family's colour on top, the name, the keys,
	# the status (or what the count counts, in its tone) and the explanation.
	var flagged := planned or preview
	_info.show_card(caption, description, key_hint, status_label if flagged else count_note,
		get_viewport_rect().size.x >= 1200.0, family_color, "waiting" if flagged else count_tone)
	_info.show()
	call_deferred("_position_info")


func _position_info() -> void:
	if _info == null or not _info.visible: return
	var anchor := get_global_rect()
	if is_instance_valid(shelf) and shelf.is_visible_in_tree():
		var top := minf(anchor.position.y, shelf.get_global_rect().position.y)
		anchor = Rect2(Vector2(anchor.position.x, top), Vector2(anchor.size.x, anchor.end.y - top))
	_info.point_at(anchor)


## The key that triggers an input action, as a player reads it: "]" or "Ctrl + [".
static func key_text(action: String) -> String:
	if action.is_empty() or not InputMap.has_action(action): return ""
	for event: InputEvent in InputMap.action_get_events(action):
		if not event is InputEventKey: continue
		var key := event as InputEventKey
		# The key's own character first: asking the display server for the keyboard
		# layout is not possible in headless runs. Space and the named keys (Esc, the
		# arrows) are the same on every layout, so they go by name.
		var label := char(key.unicode) if key.unicode > 32 else OS.get_keycode_string(key.keycode)
		if label.is_empty() and (key.physical_keycode == KEY_SPACE or (key.physical_keycode & KEY_SPECIAL) != 0):
			label = OS.get_keycode_string(key.physical_keycode)
		if label.is_empty(): label = OS.get_keycode_string(DisplayServer.keyboard_get_keycode_from_physical(key.physical_keycode))
		return ("Ctrl + " if key.ctrl_pressed else "") + ("Shift + " if key.shift_pressed else "") + ("Alt + " if key.alt_pressed else "") + label
	return ""
