extends Control

## The tool bar (doc 23, "The tool bar"): one bar for every tool, above the dock, or above
## the shelf while one is open. Left to right:
## - the tool's picture on its family tile, its name, and its keys on keycaps;
## - its choices as rows of pictures (Shapes' shape, Build's material), then its settings as
##   − value + steppers (a wall's height, a door gap, mining's width and depth). A choice's
##   picture can open a menu above the bar (Build's Stone and Wood, doc 275);
## - a tool's standing numbers (Place's stock);
## - the tool's message, else the newest order with View;
## - Undo, and Done · Esc as the family block.
## While a drag is held, a tag beside it shows what the drag would order and what that
## costs, in rust when the stock runs short.
## Undo works through one list of the last 20 orders, whichever tool made them, newest
## first. Ctrl + Z (tool_undo) does the same, also with no tool on.
## Tools join with bind_tool() and answer tool_bar_state() (fields in doc 23). Presentation
## only: each tool keeps its orders, and a receipt cancels remaining work but never restores
## mined or felled terrain.
signal undone(message: String)

const DockButton = preload("res://scripts/ui/DockIconButton.gd")
const HoverCard = preload("res://scripts/ui/HoverCard.gd")
const HISTORY := 20
# Text sizes come from the type scale (doc 23, "Type").
const LARGE := UITheme.TYPE_LARGE
const MEDIUM := UITheme.TYPE_MEDIUM
const SMALL := UITheme.TYPE_SMALL
## Sizes by the screen's height, as the windows': large from 1300 px tall, small below 650.
const SIZES := {
	"large": {"icon": 56, "name": LARGE.heading, "text": LARGE.body, "small": LARGE.small, "key": LARGE.small, "value": LARGE.heading, "verb": LARGE.lead,
		"button": 46, "step": 36, "gap": 14, "pad": 10, "type": LARGE},
	"medium": {"icon": 44, "name": MEDIUM.heading, "text": MEDIUM.body, "small": MEDIUM.small, "key": MEDIUM.small, "value": MEDIUM.heading, "verb": MEDIUM.lead,
		"button": 36, "step": 28, "gap": 10, "pad": 6, "type": MEDIUM},
	"small": {"icon": 34, "name": SMALL.heading, "text": SMALL.body, "small": SMALL.small, "key": SMALL.small, "value": SMALL.heading, "verb": SMALL.lead,
		"button": 30, "step": 24, "gap": 7, "pad": 3, "type": SMALL},
}

## The Orders shelf: while it is open the bar sits above it.
var shelf: Control
## The rects the bar keeps clear of: the slice tower, the X-ray and Appeal options, the
## compact panel. Returns Array[Rect2].
var reserved_rects := Callable()
## X-ray waits while a tool works; the bar says so.
var xray: Node
var _tools: Array[Node] = []
var _active: Node
var _history: Array[Dictionary] = []   # {owner, receipt, tool}, newest last
var _note := ""   # the active tool's latest message ("No clear cells to build")
var _dock_rect := Rect2()
var _size: Dictionary = SIZES.medium
var _tier := ""
var _family := Color.TRANSPARENT
var _shown_keys := ""
var _shown_settings := ""
var _refresh_elapsed := 0.0
var _textures := {}
var _cards := {}   # control -> [title, body, keys]
var _bar: PanelContainer
var _pad: MarginContainer
var _row: HBoxContainer
var _tile: PanelContainer
var _picture: TextureRect
var _name: Label
var _keys: HBoxContainer
var _xray_note: Label
var _settings_rule: ColorRect
var _settings: HBoxContainer
var _standing_rule: ColorRect
var _standing: VBoxContainer
var _standing_big: Label
var _standing_small: Label
var _status_rule: ColorRect
var _status: HBoxContainer
var _status_label: Label
var _status_text: Label
var _view: Button
var _undo: Button
var _done: Button
var _tag: PanelContainer
var _tag_big: Label
var _tag_small: Label
var _card: PanelContainer
var _card_for: Control
var _card_timer: Timer
# A choice's menu (doc 275, format A): the dock's menu slab over the picture that opened it.
var _menu_layer: CanvasLayer
var _menu: PanelContainer
var _menu_line: Line2D
var _menu_for := ""      # "choice/option" whose menu is open
var _menu_shown := ""    # the open menu's rows and options, so it is rebuilt only when they change


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UITheme.apply_surface(self)
	_bar = PanelContainer.new()
	_bar.name = "Bar"
	_bar.mouse_force_pass_scroll_events = false
	_bar.hide()
	add_child(_bar)
	_pad = MarginContainer.new()
	_bar.add_child(_pad)
	_row = HBoxContainer.new()
	_pad.add_child(_row)
	_tile = PanelContainer.new()
	_tile.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_row.add_child(_tile)
	_picture = TextureRect.new()
	_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_tile.add_child(_picture)
	var words := VBoxContainer.new()
	words.add_theme_constant_override("separation", 2)
	words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_row.add_child(words)
	var title := HBoxContainer.new()
	title.add_theme_constant_override("separation", 10)
	words.add_child(title)
	_name = _label(true, UITheme.CARD_TITLE)
	_name.mouse_filter = Control.MOUSE_FILTER_PASS
	title.add_child(_name)
	_keys = HBoxContainer.new()
	words.add_child(_keys)
	_xray_note = _label(false, UITheme.HEARTH_MUTED)
	_xray_note.text = "X-ray waits while you work."
	words.add_child(_xray_note)
	_settings_rule = _rule()
	_settings = HBoxContainer.new()
	_settings.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_row.add_child(_settings)
	_standing_rule = _rule()
	_standing = VBoxContainer.new()
	_standing.add_theme_constant_override("separation", 0)
	_standing.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_row.add_child(_standing)
	_standing_big = _label(true, UITheme.CARD_TITLE)
	_standing.add_child(_standing_big)
	_standing_small = _label(false, UITheme.HEARTH_MUTED)
	_standing.add_child(_standing_small)
	_status_rule = _rule()
	_status = HBoxContainer.new()
	_status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_row.add_child(_status)
	var said := VBoxContainer.new()
	said.add_theme_constant_override("separation", 0)
	said.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_status.add_child(said)
	_status_label = _label(false, UITheme.HEARTH_MUTED)
	_status_label.text = "LAST ORDER"
	said.add_child(_status_label)
	_status_text = _label(false, UITheme.CARD_TEXT)
	_status_text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	said.add_child(_status_text)
	_view = _button("View", false)
	_view.pressed.connect(_view_newest)
	_status.add_child(_view)
	_hover(_view, "View", "Finishes the tool and shows the newest order: where it is and how it is going.", "")
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_child(spacer)
	_undo = _button("Undo", false)
	_undo.name = "Undo"
	_undo.pressed.connect(undo_newest)
	_row.add_child(_undo)
	_done = _button("Done · Esc", true)
	_done.name = "Done"
	_done.pressed.connect(func(): if is_instance_valid(_active): _active.deactivate())
	_row.add_child(_done)
	_tag = PanelContainer.new()
	_tag.name = "Tag"
	_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tag.add_theme_stylebox_override("panel", UITheme.hearth_panel(false))
	_tag.hide()
	add_child(_tag)
	var tag_pad := MarginContainer.new()
	tag_pad.name = "Pad"
	tag_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tag.add_child(tag_pad)
	var tag_words := VBoxContainer.new()
	tag_words.add_theme_constant_override("separation", 0)
	tag_words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag_pad.add_child(tag_words)
	_tag_big = _label(true, UITheme.CARD_TITLE)
	tag_words.add_child(_tag_big)
	_tag_small = _label(false, UITheme.HEARTH_MUTED)
	tag_words.add_child(_tag_small)
	var cards := CanvasLayer.new()
	cards.layer = 30   # the hover cards' layer
	add_child(cards)
	_card = HoverCard.new()
	_card.hide()
	cards.add_child(_card)
	_card_timer = Timer.new()
	_card_timer.one_shot = true
	_card_timer.wait_time = 0.3
	_card_timer.timeout.connect(_show_card)
	add_child(_card_timer)
	_menu_layer = CanvasLayer.new()
	_menu_layer.layer = 23   # the dock's menus' layer
	add_child(_menu_layer)
	_menu_line = Line2D.new()
	_menu_line.width = 2
	_menu_line.default_color = UITheme.HEARTH_COPPER
	_menu_line.hide()
	_menu_layer.add_child(_menu_line)
	_apply_sizes(true)
	get_viewport().size_changed.connect(refresh)


## A tool joins the bar. Its orders join the one Undo list.
func bind_tool(tool: Node) -> void:
	if _tools.has(tool): return
	_tools.append(tool)
	if tool.has_method("set_shared_order_ui"): tool.set_shared_order_ui(true)
	if tool.has_signal("order_created"): tool.connect("order_created", _record_order.bind(tool))
	if tool.has_signal("order_feedback"): tool.connect("order_feedback", _on_feedback.bind(tool))
	refresh()


func fit_above_dock(dock_rect: Rect2) -> void:
	_dock_rect = dock_rect
	refresh()


## The tool the bar shows, or null.
func active_tool() -> Node:
	for tool: Node in _tools:
		if is_instance_valid(tool) and tool.is_active(): return tool
	return null


func _process(delta: float) -> void:
	_refresh_elapsed += delta
	if _refresh_elapsed < 0.1: return
	_refresh_elapsed = 0.0
	refresh()


func refresh() -> void:
	if _bar == null: return
	var tool := active_tool()
	if tool != _active:
		_active = tool
		_note = ""
	if _active == null:
		_bar.hide()
		_tag.hide()
		_hide_card()
		_close_menu()
		return
	var state: Dictionary = _active.tool_bar_state()
	var id := String(state.get("tool", ""))
	var entry: Dictionary = UIRegistry.get_tool_entry(id)
	_apply_sizes()
	_apply_family(UIRegistry.get_icon_family_color(String(state.get("family", entry.get("family", "work")))))
	_picture.texture = _texture(String(state.get("picture", entry.get("icon", ""))))
	_name.text = String(state.get("name", entry.get("label", id)))
	_show_keys(UIRegistry.get_tool_bar().get("keys", {}).get(id, []))
	_xray_note.visible = is_instance_valid(xray) and String(xray.mode) != "off" and bool(xray.working)
	_show_settings(state.get("settings", []), state.get("toggle", {}), state.get("choices", []))
	var standing: Array = state.get("standing", [])
	_standing.visible = not standing.is_empty()
	_standing_rule.visible = _standing.visible
	if _standing.visible:
		_standing_big.text = String(standing[0])
		_standing_small.text = String(standing[1]) if standing.size() > 1 else ""
	_show_status(String(state.get("message", "")), bool(state.get("undo", true)))
	_undo.visible = bool(state.get("undo", true))
	var newest := newest_order()
	_undo.disabled = newest.is_empty()
	_hover(_undo, "Undo", ("Takes back your newest order, whichever tool made it: %s. Unfinished work is cancelled; finished work stays." \
		% _order_words(newest)) if not newest.is_empty() else "Nothing to take back yet. Your last 20 orders can be taken back, newest first.",
		DockButton.key_text("tool_undo"))
	_hover(_done, "Done", "Finishes %s. Its orders stay." % _name.text, "Esc")
	_show_tag(state.get("selection", {}))
	_bar.show()
	_fit_and_place()
	_show_menu(state.get("choices", []))


# ── Undo ──────────────────────────────────────────────────────────────────────

## The newest order that still has work left, or {}.
func newest_order() -> Dictionary:
	while not _history.is_empty() and not _pending(_history.back()): _history.pop_back()
	return {} if _history.is_empty() else _history.back()


## Takes back the newest order, whichever tool made it. False when there is none.
func undo_newest() -> bool:
	var newest := newest_order()
	if newest.is_empty(): return false
	_history.pop_back()
	newest.owner.undo_order(newest.receipt)
	var message := "Took back: %s" % String(newest.receipt.get("message", "an order"))
	_note = message
	undone.emit(message)
	refresh()
	return true


func _pending(record: Dictionary) -> bool:
	return is_instance_valid(record.owner) and record.owner.order_is_pending(record.receipt)


func _record_order(receipt: Dictionary, tool: Node) -> void:
	_history.append({"owner": tool, "receipt": receipt, "tool": _name.text if tool == _active else ""})
	if _history.size() > HISTORY: _history.pop_front()
	if tool == _active: _note = ""
	refresh()


func _on_feedback(message: String, tool: Node) -> void:
	if tool == active_tool(): _note = message
	refresh()


func _order_words(record: Dictionary) -> String:
	var words := String(record.receipt.get("message", "an order"))
	return words if String(record.tool).is_empty() or record.tool == _name.text else "%s (%s)" % [words, record.tool]


func _view_newest() -> void:
	var newest := newest_order()
	if newest.is_empty() or not newest.owner.has_method("inspect_order"): return
	if is_instance_valid(_active): _active.deactivate()
	newest.owner.inspect_order(newest.receipt)


## An open menu closes on Esc before the tool hears it, and on a press anywhere off the menu and
## the bar; that press still reaches the world.
func _input(event: InputEvent) -> void:
	if _menu == null: return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_close_menu()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT] \
			and not _menu.get_global_rect().has_point(event.position) and not _bar.get_global_rect().has_point(event.position):
		_close_menu()


## Ctrl + Z, after text fields and the game menu have had the keys.
func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"tool_undo", false, true) and undo_newest():
		get_viewport().set_input_as_handled()


# ── Showing ───────────────────────────────────────────────────────────────────

## The tool's message, else what it last said, else the newest order with View. A tool that
## makes orders keeps the place, so the bar does not change width as they come.
func _show_status(message: String, ordering: bool) -> void:
	var newest := newest_order()
	var text := message if not message.is_empty() else _note
	var order_shown := text.is_empty() and ordering
	if order_shown: text = _order_words(newest) if not newest.is_empty() else "None yet"
	_status_label.visible = order_shown
	_status_text.text = text
	_status_text.add_theme_color_override("font_color", UITheme.HEARTH_MUTED if order_shown and newest.is_empty() else UITheme.CARD_TEXT)
	_view.visible = ordering
	_view.disabled = not order_shown or newest.is_empty() or not newest.owner.has_method("inspect_order")
	_status.visible = ordering or not text.is_empty()
	_status_rule.visible = _status.visible


func _show_keys(pairs: Array) -> void:
	var shown := str(pairs) + _tier
	if shown == _shown_keys: return
	_shown_keys = shown
	for child: Node in _keys.get_children():
		_keys.remove_child(child)
		child.queue_free()
	_keys.add_theme_constant_override("separation", 5)
	for i in range(pairs.size()):
		if i > 0:
			var gap := Control.new()
			gap.custom_minimum_size.x = float(_size.gap)
			_keys.add_child(gap)
		var caps := HBoxContainer.new()
		caps.add_theme_constant_override("separation", 3)
		caps.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		UITheme.add_keycaps(caps, String(pairs[i][0]), int(_size.key), 2)
		_keys.add_child(caps)
		var words := _label(false, UITheme.HEARTH_MUTED)
		words.text = String(pairs[i][1])
		words.add_theme_font_size_override("font_size", int(_size.text))
		_keys.add_child(words)


## The tool's choices, steppers for the settings, and the tool's switch. They are rebuilt only
## when the settings change; the chosen pictures and the values follow every refresh.
func _show_settings(settings: Array, toggle: Dictionary, choices: Array) -> void:
	var shown := ",".join(settings.map(func(setting: Dictionary) -> String: return String(setting.id))) \
		+ "|" + String(toggle.get("id", "")) + "|" + ",".join(choices.map(func(choice: Dictionary) -> String:
			return String(choice.id) + ":" + ",".join(choice.options.map(func(option: Dictionary) -> String: return String(option.id))))) + _tier
	if shown != _shown_settings:
		_shown_settings = shown
		for child: Node in _settings.get_children():
			_settings.remove_child(child)
			child.queue_free()
		_settings.add_theme_constant_override("separation", int(_size.gap))
		for choice: Dictionary in choices: _settings.add_child(_choice(choice))
		for setting: Dictionary in settings: _settings.add_child(_stepper(setting))
		if not toggle.is_empty():
			var button := _button(String(toggle.label), false)
			button.name = "Toggle"
			button.toggle_mode = true
			button.add_theme_font_size_override("font_size", int(_size.small))
			button.custom_minimum_size = Vector2(0, float(_size.step))
			button.toggled.connect(func(on: bool): if is_instance_valid(_active): _active.set_tool_setting(String(toggle.id), on))
			_hover(button, String(toggle.label), String(toggle.get("tooltip", "")), String(toggle.get("keys", "")))
			_settings.add_child(button)
	for choice: Dictionary in choices:
		for option: Dictionary in choice.options:
			var button: Button = _settings.get_node(String(choice.id).to_pascal_case() + "/Row/" + String(option.id).to_pascal_case())
			var chosen := String(option.id) == String(choice.value)
			button.set_pressed_no_signal(chosen)
			UITheme.apply_hearth_button(button, chosen)
			# A material's picture and card follow its chosen type and wood.
			(button.get_node("Picture") as TextureRect).texture = _texture(String(option.picture))
			_hover(button, String(option.label), String(option.get("tooltip", "")), String(choice.get("keys", "")))
	var i := choices.size()   # the steppers follow the choices
	for setting: Dictionary in settings:
		var stepper: Control = _settings.get_child(i)
		(stepper.get_node("Row/Value") as Label).text = str(setting.value)
		(stepper.get_node("Row/Less") as Button).disabled = int(setting.value) <= int(setting.min)
		(stepper.get_node("Row/More") as Button).disabled = int(setting.value) >= int(setting.max)
		i += 1
	if not toggle.is_empty():
		(_settings.get_node("Toggle") as Button).set_pressed_no_signal(bool(toggle.on))
		UITheme.apply_hearth_button(_settings.get_node("Toggle"), bool(toggle.on))
		(_settings.get_node("Toggle") as Button).add_theme_font_size_override("font_size", int(_size.small))
	_settings.visible = not settings.is_empty() or not toggle.is_empty() or not choices.is_empty()
	_settings_rule.visible = _settings.visible


## A setting as its name over − value +; its keys and what it does on the hover card.
func _stepper(setting: Dictionary) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.name = String(setting.id).to_pascal_case()
	column.add_theme_constant_override("separation", 0)
	column.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var heading := _label(false, UITheme.HEARTH_MUTED)
	heading.text = String(setting.label).to_upper()
	heading.add_theme_font_size_override("font_size", int(_size.small * 0.8))
	column.add_child(heading)
	var row := HBoxContainer.new()
	row.name = "Row"
	row.add_theme_constant_override("separation", 4)
	column.add_child(row)
	for part: String in ["Less", "Value", "More"]:
		if part == "Value":
			var value := _label(true, UITheme.CARD_TITLE)
			value.name = "Value"
			value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			value.custom_minimum_size.x = float(_size.value) * 1.3
			value.add_theme_font_size_override("font_size", int(_size.value))
			row.add_child(value)
			continue
		var step := _button("−" if part == "Less" else "+", false)
		step.name = part
		step.custom_minimum_size = Vector2.ONE * float(_size.step)
		var delta := -1 if part == "Less" else 1
		var id := String(setting.id)
		step.pressed.connect(func():
			if not is_instance_valid(_active): return
			for current: Dictionary in _active.tool_bar_state().get("settings", []):
				if String(current.id) == id: _active.set_tool_setting(id, int(current.value) + delta)
			refresh())
		_hover(step, String(setting.label), String(setting.get("tooltip", "")), String(setting.get("keys", "")))
		row.add_child(step)
	return column


## A choice as its name over a row of pictures, the chosen one lit. Each picture's hover card
## names it, says what it costs and gives the keys that step through them.
func _choice(choice: Dictionary) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.name = String(choice.id).to_pascal_case()
	column.add_theme_constant_override("separation", 0)
	column.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var heading := _label(false, UITheme.HEARTH_MUTED)
	heading.text = String(choice.label).to_upper()
	heading.add_theme_font_size_override("font_size", int(_size.small * 0.8))
	column.add_child(heading)
	var row := HBoxContainer.new()
	row.name = "Row"
	row.add_theme_constant_override("separation", 4)
	column.add_child(row)
	var id := String(choice.id)
	for option: Dictionary in choice.options:
		var button := _button("", false)
		button.name = String(option.id).to_pascal_case()
		button.set_meta("option", String(option.id))
		button.toggle_mode = true
		button.custom_minimum_size = Vector2.ONE * float(_size.step) * 1.2
		# The picture fills the button, past the slab's padding, so it reads at this size.
		var picture := TextureRect.new()
		picture.name = "Picture"
		picture.texture = _texture(String(option.picture))
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var inset := maxf(2.0, float(_size.step) * 0.08)
		picture.offset_left = inset
		picture.offset_top = inset
		picture.offset_right = -inset
		picture.offset_bottom = -inset
		button.add_child(picture)
		var value := String(option.id)
		var opens := option.has("menu")
		button.pressed.connect(func():
			if is_instance_valid(_active): _active.set_tool_setting(id, value)
			# A picture with a menu opens it, and closes it when it is open.
			var key := id + "/" + value
			if opens and _menu_for != key: _menu_for = key
			else: _close_menu()
			refresh())
		_hover(button, String(option.label), String(option.get("tooltip", "")), String(choice.get("keys", "")))
		row.add_child(button)
	return column


## The open menu (doc 275, format A): its option's rows, each a heading over the dock's tiles, the
## chosen ones lit and a wood's stock on its corner. It rises 8 px above the bar over the picture
## that opened it, joined to it by a short copper line, as the dock's menus are. It closes when its
## option is no longer chosen.
func _show_menu(choices: Array) -> void:
	if _menu_for.is_empty(): return
	var rows: Array = []
	for choice: Dictionary in choices:
		for option: Dictionary in choice.options:
			if String(choice.id) + "/" + String(option.id) == _menu_for and String(option.id) == String(choice.value):
				rows = option.get("menu", [])
	var opener: Control = _settings.get_node_or_null(_menu_for.get_slice("/", 0).to_pascal_case() + "/Row/" + _menu_for.get_slice("/", 1).to_pascal_case())
	if rows.is_empty() or opener == null:
		_close_menu()
		return
	var side := 64.0 if get_viewport_rect().size.x >= 1200.0 else 56.0
	var shown := _tier + str(side) + str(rows.map(func(row: Dictionary) -> String:
		return String(row.id) + ":" + ",".join(row.options.map(func(option: Dictionary) -> String: return String(option.id)))))
	if shown != _menu_shown:
		_close_menu(false)
		_menu_shown = shown
		_menu = PanelContainer.new()
		_menu.name = "ChoiceMenu"
		_menu.add_theme_stylebox_override("panel", UITheme.dock_panel_style())
		UITheme.apply_surface(_menu)
		var pad := MarginContainer.new()
		pad.name = "Pad"
		for edge: String in ["left", "right", "top", "bottom"]: pad.add_theme_constant_override("margin_" + edge, 10)
		_menu.add_child(pad)
		var column := VBoxContainer.new()
		column.name = "Rows"
		column.add_theme_constant_override("separation", 6)
		pad.add_child(column)
		for row: Dictionary in rows:
			var heading := _label(false, UITheme.HEARTH_MUTED)
			heading.text = String(row.label).to_upper()
			heading.add_theme_font_size_override("font_size", int(_size.small * 0.8))
			column.add_child(heading)
			var tiles := HBoxContainer.new()
			tiles.name = String(row.id).to_pascal_case()
			tiles.add_theme_constant_override("separation", 6)
			column.add_child(tiles)
			for option: Dictionary in row.options:
				var tile := DockButton.new()
				tile.setup({"id": option.id, "label": option.label, "family": "work", "tooltip": option.get("tooltip", "")}, _texture(String(option.picture)))
				tile.name = String(option.id).to_pascal_case()
				tile.custom_minimum_size = Vector2.ONE * side
				tile.shelf = _menu
				var setting := String(row.id)
				var value := String(option.id)
				tile.pressed.connect(func():
					if is_instance_valid(_active): _active.set_tool_setting(setting, value)
					refresh())
				tiles.add_child(tile)
		_menu_layer.add_child(_menu)
	for row: Dictionary in rows:
		for option: Dictionary in row.options:
			var tile: Button = _menu.get_node("Pad/Rows/" + String(row.id).to_pascal_case() + "/" + String(option.id).to_pascal_case())
			tile.set_pressed_no_signal(String(option.id) == String(row.value))
			tile.queue_redraw()
			if option.has("count"): tile.show_count(String(option.count), String(option.get("tone", "fine")), String(option.get("note", "")))
	_menu.reset_size()
	var bar := _bar.get_global_rect()
	var picture := opener.get_global_rect()
	var at := Vector2(picture.get_center().x - _menu.size.x * 0.5, bar.position.y - 8.0 - _menu.size.y)
	at.x = clampf(at.x, 8.0, get_viewport_rect().size.x - _menu.size.x - 8.0)
	_menu.position = at
	_menu_line.points = PackedVector2Array([Vector2(picture.get_center().x, bar.position.y), Vector2(picture.get_center().x, at.y + _menu.size.y)])
	_menu_line.show()


## Closes the open menu; `forget` also forgets which one was open.
func _close_menu(forget := true) -> void:
	if forget: _menu_for = ""
	_menu_shown = ""
	if _menu != null:
		_menu.queue_free()
		_menu = null
	if _menu_line != null: _menu_line.hide()


## The open menu, or null: for tests and captures.
func open_menu() -> PanelContainer:
	return _menu


## The drag's numbers beside it, in rust when the stock runs short.
func _show_tag(selection: Dictionary) -> void:
	if selection.is_empty():
		_tag.hide()
		return
	_tag_big.text = String(selection.get("count", ""))
	_tag_small.text = String(selection.get("detail", ""))
	_tag_small.visible = not _tag_small.text.is_empty()
	_tag_small.add_theme_color_override("font_color", UITheme.TAG_TONES.blocked[1] if bool(selection.get("short", false)) else UITheme.HEARTH_MUTED)
	_tag.show()
	_tag.reset_size()
	var view := get_viewport_rect().size
	var at: Vector2 = selection.get("at", Vector2.INF)
	if not at.is_finite(): at = get_viewport().get_mouse_position()
	# Above and right of the drag's end; near an edge, or over the slice tower and the panels the
	# bar keeps clear of, it turns to the other side, clear of the corner controls.
	var gap := float(_size.gap) * 2.0
	var spot := at + Vector2(gap, -_tag.size.y - gap)
	var blockers: Array = reserved_rects.call() if reserved_rects.is_valid() else []
	if spot.x + _tag.size.x > view.x - 8.0 - view.x * 0.08 or _overlap(Rect2(spot, _tag.size), blockers, gap).size != Vector2.ZERO:
		spot.x = at.x - gap - _tag.size.x
	if spot.y < 8.0 + view.y * 0.08: spot.y = at.y + gap
	_tag.position = Vector2(clampf(spot.x, 8.0, view.x - _tag.size.x - 8.0), clampf(spot.y, 8.0, view.y - _tag.size.y - 8.0))


## Narrow screens drop the keys line first (its keys stay on the name's hover card), then
## the standing numbers. Then the bar sits over the dock, or the open shelf, sliding aside
## only as far as it must to clear the tower and the panels beside it. A bar too wide to slide
## clear (Shapes, with its many settings) narrows its status line, trimmed, and drops View,
## then drops the status line, before it rises above what it cannot pass.
func _fit_and_place() -> void:
	var view := get_viewport_rect().size
	var room := view.x - 32.0
	_keys.visible = true
	_status_text.custom_minimum_size.x = float(_size.text) * 20.0
	if _bar.get_combined_minimum_size().x > room:
		_keys.visible = false
		_standing.visible = false
		_standing_rule.visible = false
	var placed := _place(view, false)
	if not placed.clear:
		_status_text.custom_minimum_size.x = float(_size.text) * 5.0
		_view.visible = false
		placed = _place(view, false)
	if not placed.clear:   # last, the status line itself goes; a drag's tag still says what it plans
		_status.visible = false
		_status_rule.visible = false
		placed = _place(view, true)
	_bar.position = Vector2(placed.spot.x, maxf(8.0, placed.spot.y))


## Where the bar goes: over the dock or the open shelf, slid aside to clear the blockers, or
## (when `rise`) above one it cannot pass. {spot, clear}: clear is false when it would rise.
func _place(view: Vector2, rise: bool) -> Dictionary:
	_bar.reset_size()
	var size := _bar.size
	var gap := float(_size.gap)
	var bottom := _dock_rect.position.y - 8.0
	if is_instance_valid(shelf) and shelf.has_method("shelf_rect"):
		var open: Rect2 = shelf.shelf_rect()
		if open.size != Vector2.ZERO: bottom = minf(bottom, open.position.y - 8.0)
	var preferred := clampf(_dock_rect.get_center().x - size.x * 0.5, 16.0, maxf(16.0, view.x - 16.0 - size.x))
	var spot := Vector2(preferred, bottom - size.y)
	var blockers: Array = reserved_rects.call() if reserved_rects.is_valid() else []
	for attempt in range(4):
		var hit := _overlap(Rect2(spot, size), blockers, gap)
		if hit.size == Vector2.ZERO: break
		var best := INF
		for x: float in [hit.position.x - gap - size.x, hit.end.x + gap]:
			if x >= 16.0 and x + size.x <= view.x - 16.0 and _overlap(Rect2(Vector2(x, spot.y), size), blockers, gap).size == Vector2.ZERO \
					and absf(x - preferred) < best:
				best = absf(x - preferred)
				spot.x = x
		if best == INF:
			if not rise: return {"spot": spot, "clear": false}
			spot = Vector2(preferred, hit.position.y - gap - size.y)
	return {"spot": spot, "clear": true}


func _overlap(rect: Rect2, blockers: Array, gap: float) -> Rect2:
	for blocker: Rect2 in blockers:
		if rect.intersects(blocker.grow(gap * 0.5)): return blocker
	return Rect2()


## The family colour on the band, the tile and the Done block.
func _apply_family(family: Color) -> void:
	if family == _family: return
	_family = family
	_bar.theme = UITheme.family_theme(family)
	_bar.add_theme_stylebox_override("panel", UITheme.toast_frame(family))
	_tile.add_theme_stylebox_override("panel", UITheme.icon_tile_style(family))
	UITheme.apply_hearth_button(_done, true)
	_done.add_theme_font_size_override("font_size", int(_size.verb))


func _apply_sizes(force := false) -> void:
	var height := get_viewport_rect().size.y
	var tier := "large" if height >= 1300.0 else ("small" if height < 650.0 else "medium")
	if tier == _tier and not force: return
	_tier = tier
	_size = SIZES[tier]
	_pad.add_theme_constant_override("margin_left", int(_size.pad))
	_pad.add_theme_constant_override("margin_right", int(_size.pad))
	_pad.add_theme_constant_override("margin_top", int(_size.pad * 0.4))
	_pad.add_theme_constant_override("margin_bottom", int(_size.pad * 0.4))
	_row.add_theme_constant_override("separation", int(_size.gap))
	_tile.custom_minimum_size = Vector2.ONE * float(_size.icon)
	_picture.custom_minimum_size = Vector2.ONE * float(_size.icon) * 0.82
	_name.add_theme_font_size_override("font_size", int(_size.name))
	_xray_note.add_theme_font_size_override("font_size", int(_size.small))
	_standing_big.add_theme_font_size_override("font_size", int(_size.value))
	_standing_small.add_theme_font_size_override("font_size", int(_size.small))
	_status_label.add_theme_font_size_override("font_size", int(_size.small * 0.8))
	_status_text.add_theme_font_size_override("font_size", int(_size.text))
	_status_text.custom_minimum_size.x = float(_size.text) * 20.0
	for button: Button in [_view, _undo, _done]:
		button.add_theme_font_size_override("font_size", int(_size.verb))
		button.custom_minimum_size = Vector2(float(_size.button) * (1.2 if button == _view else 2.0), float(_size.button))
	_tag_big.add_theme_font_size_override("font_size", int(_size.value * 0.85))
	_tag_small.add_theme_font_size_override("font_size", int(_size.small))
	var tag_pad: MarginContainer = _tag.get_node("Pad")
	for side: String in ["left", "right"]: tag_pad.add_theme_constant_override("margin_" + side, int(_size.gap))
	tag_pad.add_theme_constant_override("margin_top", int(_size.gap * 0.45))
	tag_pad.add_theme_constant_override("margin_bottom", int(_size.gap * 0.55))
	_shown_keys = ""
	_shown_settings = ""


# ── Pieces ────────────────────────────────────────────────────────────────────

func _label(display: bool, color: Color) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UITheme.format_label(label, display, UITheme.TYPE_MEDIUM.body, color)
	return label


func _button(text: String, primary: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UITheme.apply_hearth_button(button, primary)
	return button


func _rule() -> ColorRect:
	var rule := ColorRect.new()
	rule.color = Color(UITheme.HEARTH_EDGE, 0.7)
	rule.custom_minimum_size = Vector2(2, 0)
	rule.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_child(rule)
	return rule


func _texture(path: String) -> Texture2D:
	if path.is_empty(): return null
	if not _textures.has(path): _textures[path] = load(path) if ResourceLoader.exists(path) else null
	return _textures[path]


# ── Hover cards ───────────────────────────────────────────────────────────────

## A control's hover card: its name, what it does and its keys, as the dock's.
func _hover(control: Control, title: String, body: String, keys: String) -> void:
	if not _cards.has(control):
		control.mouse_entered.connect(func():
			_card_for = control
			_card_timer.start())
		control.mouse_exited.connect(func(): if _card_for == control: _hide_card())
	_cards[control] = [title, body, keys]
	if _card_for == control and _card.visible: _show_card()


func _show_card() -> void:
	if not is_instance_valid(_card_for) or not _card_for.is_visible_in_tree() or not _cards.has(_card_for): return
	var card: Array = _cards[_card_for]
	if String(card[1]).is_empty() and String(card[2]).is_empty(): return
	_card.show_card(String(card[0]), String(card[1]), String(card[2]), "", get_viewport_rect().size.x >= 1200.0, _family)
	_card.show()
	_card.point_at.call_deferred(_card_for.get_global_rect())


func _hide_card() -> void:
	_card_for = null
	_card_timer.stop()
	if _card != null: _card.hide()
