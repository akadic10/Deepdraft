extends VBoxContainer

## Colony overview. A compact, stable table and the shared dwarf inspector
## live in one window; ObjectExplorer retains ownership of world selection.
const Inspection = preload("res://scripts/components/DwarfInspection.gd")
const Portrait = preload("res://scripts/ui/DwarfPortrait.gd")
const Inspector = preload("res://scripts/ui/DwarfInspectorPanel.gd")
const REFRESH_SECONDS := 0.35

var director: Node
var window: UIWindow
var category := "all"
var _elapsed := 0.0
var _rows := {}
var _filters := {}
var _search: LineEdit
var _scroll: ScrollContainer
var _list: VBoxContainer
var _empty: Label
var _footer: Label
var _heading: HBoxContainer
var _textures := {}
var _compact := false
var _body: HBoxContainer
var _detail_frame: PanelContainer
var _detail_panel: VBoxContainer
var _detail_empty: Label
var _explorer: Node
var _portraits_pending := false


func _ready() -> void:
	UITheme.apply_surface(self)
	add_theme_constant_override("separation", 0)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	add_child(_margin(top, 12, 10))
	var filters := HBoxContainer.new()
	filters.add_theme_constant_override("separation", 6)
	filters.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(filters)
	for entry: Dictionary in UIRegistry.get_roster_filters():
		var button := UITheme.make_button(entry.label, "", Vector2(0, 34))
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_ALL
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(func():
			category = entry.id; _scroll.scroll_vertical = 0; refresh())
		filters.add_child(button)
		_filters[entry.id] = {"button": button, "label": entry.label}
	_search = LineEdit.new()
	_search.placeholder_text = "Find a dwarf by name"
	_search.clear_button_enabled = true
	_search.custom_minimum_size.y = 32
	_search.custom_minimum_size.x = 250
	_search.text_changed.connect(func(_text: String): _scroll.scroll_vertical = 0; refresh())
	top.add_child(_search)
	_body = HBoxContainer.new()
	_body.add_theme_constant_override("separation", 12)
	add_child(_margin(_body, 12, 0))
	_detail_frame = PanelContainer.new()
	_detail_frame.add_theme_stylebox_override("panel", UITheme.hearth_panel(true))
	_body.add_child(_detail_frame)
	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_frame.add_child(details)
	_detail_empty = _label("Select a dwarf\n\nTheir portrait, current work, cargo and traits appear here.", 16, UITheme.HEARTH_MUTED)
	_detail_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_empty.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail_empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_detail_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	details.add_child(_detail_empty)
	_detail_panel = Inspector.new()
	_detail_panel.embedded = true
	_detail_panel.hide()
	details.add_child(_detail_panel)
	var table := VBoxContainer.new()
	table.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	table.add_theme_constant_override("separation", 6)
	_body.add_child(table)
	_heading = HBoxContainer.new()
	_heading.add_theme_constant_override("separation", 10)
	table.add_child(_margin(_heading, 8, 4))
	var portrait_space := Control.new()
	portrait_space.custom_minimum_size.x = 56
	_heading.add_child(portrait_space)
	_heading.add_child(_label("DWARF", 11, UITheme.HEARTH_MUTED))
	var activity := _label("ACTIVITY / CARRYING", 11, UITheme.HEARTH_MUTED)
	activity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_heading.add_child(activity)
	_heading.add_child(_label("REST", 11, UITheme.HEARTH_MUTED))
	var action_space := Control.new()
	action_space.custom_minimum_size.x = 64
	_heading.add_child(action_space)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	_scroll.mouse_force_pass_scroll_events = false
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.custom_minimum_size.y = 100
	table.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 3)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)
	_empty = _label("No dwarves have arrived yet.\nPlace a settlement flag to welcome your first settlers.", 16)
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty.custom_minimum_size.y = 70
	_list.add_child(_empty)
	_footer = _label("Select a dwarf for details · Locate moves the camera", 12, UITheme.HEARTH_MUTED)
	_footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_footer.custom_minimum_size.y = 18
	add_child(_margin(_footer, 12, 10))
	_scroll.get_v_scroll_bar().value_changed.connect(func(_value: float): _queue_portrait_update())
	get_viewport().size_changed.connect(func(): _fit.call_deferred())
	set_process(false)


func begin_browsing() -> void:
	_elapsed = 0.0
	_explorer = get_tree().get_first_node_in_group("object_explorer")
	if is_instance_valid(_explorer):
		_explorer.set_dwarf_inspector_host(_detail_panel)
		if not _explorer.selection_changed.is_connected(refresh):
			_explorer.selection_changed.connect(refresh)
	refresh()
	if is_instance_valid(_explorer):
		if _explorer.selected_dwarf(director) == null:
			for agent: DwarfAgent in director.get_roster():
				if _rows[agent].button.visible and director.can_inspect_dwarf(agent):
					director.inspect_dwarf(agent)
					break
	_fit.call_deferred()
	set_process(true)


func end_browsing() -> void:
	set_process(false)
	if is_instance_valid(_explorer):
		_explorer.set_dwarf_inspector_host(null)


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= REFRESH_SECONDS:
		_elapsed = 0.0
		refresh()


func refresh() -> void:
	if not is_instance_valid(director) or window == null or not window.visible: return
	var agents: Array = director.get_roster()
	for agent in _rows.keys():
		if not is_instance_valid(agent) or not agent in agents:
			var button: Button = _rows[agent].button
			_list.remove_child(button)
			button.queue_free()
			_rows.erase(agent)
	var counts := {"all": agents.size(), "working": 0, "resting": 0, "idle": 0}
	var shown := 0
	var query := _search.text.strip_edges().to_lower()
	var explorer := get_tree().get_first_node_in_group("object_explorer")
	for agent: DwarfAgent in agents:
		if not _rows.has(agent): _build_row(agent)
		var row: Dictionary = _rows[agent]
		var data := Inspection.roster_state(agent)
		counts[data.group] += 1
		row.button.visible = (category == "all" or category == data.group) and (query.is_empty() or String(data.title).to_lower().contains(query))
		if row.button.visible: shown += 1
		row.name.text = data.title
		row.profession.text = data.profession
		row.activity.text = data.summary
		row.activity.add_theme_color_override("font_color", UITheme.HEARTH_COPPER if data.group == "resting" else UITheme.SUCCESS if data.group == "working" else UITheme.HEARTH_TEXT)
		row.rest.value = roundi(float(data.rest) * 100)
		row.rest_label.text = "%d%%" % roundi(float(data.rest) * 100)
		row.rest_label.add_theme_color_override("font_color", UITheme.DEV_ORANGE if float(data.rest) <= .25 else UITheme.HEARTH_TEXT)
		row.rest_box.tooltip_text = "Rest: %d%% · %s" % [roundi(float(data.rest) * 100), "Sleeping" if data.sleeping else "Tired" if float(data.rest) <= .25 else "Awake"]
		row.button.tooltip_text = "%s · %s\n%s\n%s" % [data.title, data.profession, data.activity, data.explanation]
		var inspectable: bool = director.can_inspect_dwarf(agent)
		row.button.disabled = not inspectable
		row.locate.disabled = not inspectable
		row.button.set_pressed_no_signal(explorer != null and explorer.is_object_selected(director, agent))
		row.cargo_icon.visible = not data.cargo.is_empty()
		if not data.cargo.is_empty():
			var first: Dictionary = data.cargo[0]
			row.cargo_icon.texture = _cargo_texture(first.key)
			row.note.text = "%d × %s%s" % [first.count, first.name, " + more" if data.cargo.size() > 1 else ""]
			var cargo_lines: Array[String] = []
			for entry: Dictionary in data.cargo: cargo_lines.append("%d × %s" % [entry.count, entry.name])
			row.button.tooltip_text += "\nCarrying: " + ", ".join(cargo_lines)
		else:
			row.note.text = data.activity if data.activity != data.summary else data.explanation
		if not inspectable:
			row.note.text = "On another slice"
			row.button.tooltip_text += "\nChange slice level to inspect or locate this dwarf."
	for key: String in _filters:
		_filters[key].button.text = "%s  %d" % [_filters[key].label, counts[key]]
		_filters[key].button.set_pressed_no_signal(category == key)
	_empty.visible = shown == 0
	_empty.text = "No dwarves have arrived yet.\nPlace a settlement flag to welcome your first settlers." if agents.is_empty() else "No dwarves match this view.\nTry another filter or name."
	_detail_empty.visible = not _detail_panel.visible
	_footer.text = "%d of %d dwarves · Select a row for details · Locate moves the camera" % [shown, agents.size()]
	_queue_portrait_update()
	# Never sort by changing activity, rebuild rows or refit on these wakes.


func _build_row(agent: DwarfAgent) -> void:
	var button := Button.new()
	button.toggle_mode = true
	button.custom_minimum_size.y = 56
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		button.add_theme_stylebox_override(state, UITheme.catalog_item_style(state in ["hover", "pressed", "hover_pressed"]))
	_list.add_child(button)
	var line := HBoxContainer.new()
	line.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	line.offset_left = 8; line.offset_right = -8
	line.offset_top = 4; line.offset_bottom = -4
	line.add_theme_constant_override("separation", 10)
	button.add_child(line)
	var portrait := TextureRect.new()
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.custom_minimum_size.x = 56
	line.add_child(portrait)
	var identity := VBoxContainer.new()
	identity.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(identity)
	var name_label := _label(agent.dwarf_name, 16)
	UITheme.apply_title(name_label, 16)
	identity.add_child(name_label)
	var profession := _label("", 11, UITheme.HEARTH_MUTED)
	identity.add_child(profession)
	var work := VBoxContainer.new()
	work.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	work.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(work)
	var activity := _label("", 14)
	work.add_child(activity)
	var cargo_row := HBoxContainer.new()
	work.add_child(cargo_row)
	var cargo_icon := TextureRect.new()
	cargo_icon.custom_minimum_size = Vector2(20, 18)
	cargo_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cargo_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	cargo_row.add_child(cargo_icon)
	var note := _label("", 12, UITheme.HEARTH_MUTED)
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cargo_row.add_child(note)
	var rest_box := VBoxContainer.new()
	rest_box.custom_minimum_size.x = 52
	rest_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(rest_box)
	var rest_label := _label("", 12)
	rest_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rest_box.add_child(rest_label)
	var rest := ProgressBar.new()
	UITheme.hearth_progress(rest)
	rest_box.add_child(rest)
	var locate := UITheme.make_button("Locate", "Center the camera on this dwarf", Vector2(60, 30))
	locate.focus_mode = Control.FOCUS_ALL
	locate.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	locate.pressed.connect(func():
		if is_instance_valid(agent): director.perform_explorer_action(agent, "locate"))
	line.add_child(locate)
	_ignore_mouse(line)
	button.pressed.connect(func():
		if is_instance_valid(agent): director.inspect_dwarf(agent)
		refresh())
	_rows[agent] = {"button": button, "portrait": portrait, "viewport": null,
		"identity": identity, "name": name_label, "profession": profession, "activity": activity,
		"cargo_icon": cargo_icon, "note": note, "rest_box": rest_box, "rest_label": rest_label,
		"rest": rest, "locate": locate}
	_size_row(_rows[agent])


func _queue_portrait_update() -> void:
	if _portraits_pending: return
	_portraits_pending = true
	# New rows initially share an unsorted rectangle at the top of the list.
	# Let both container layout passes finish before testing viewport intersection.
	await get_tree().process_frame
	await get_tree().process_frame
	_portraits_pending = false
	_render_visible_portraits()


func _render_visible_portraits() -> void:
	if window == null or not window.visible: return
	for agent in _rows:
		var row: Dictionary = _rows[agent]
		if row.viewport != null or not is_instance_valid(agent) or not row.button.visible: continue
		if not _scroll.get_global_rect().intersects(row.button.get_global_rect()): continue
		row.viewport = Portrait.create_viewport(row.portrait, Vector2i(96, 112))
		Portrait.create_model(row.viewport, agent)


func _cargo_texture(key: String) -> Texture2D:
	if _textures.has(key): return _textures[key]
	var path := "res://assets/ui/items/%s.png" % key.replace(":", "_")
	if not ResourceLoader.exists(path):
		path = "res://assets/ui/furniture/%s.png" % key.get_slice(":", key.get_slice_count(":") - 1)
	if not ResourceLoader.exists(path): path = "res://assets/ui/icons/stocks.svg"
	_textures[key] = load(path)
	return _textures[key]


func _fit() -> void:
	if window == null or not is_inside_tree(): return
	var viewport := get_viewport_rect().size
	_compact = viewport.x < 1150
	custom_minimum_size.x = minf(1200, viewport.x - 50)
	_detail_frame.custom_minimum_size.x = 296 if _compact else 328
	_search.custom_minimum_size.x = 220 if _compact else 280
	_heading.get_child(0).custom_minimum_size.x = 36 if _compact else 40
	_heading.get_child(1).custom_minimum_size.x = 124 if _compact else 172
	_heading.get_child(3).custom_minimum_size.x = 52
	_heading.get_child(4).custom_minimum_size.x = 72 # Locate + scrollbar gutter
	for row: Dictionary in _rows.values(): _size_row(row)
	_body.custom_minimum_size.y = 0
	var body_height := _body.get_combined_minimum_size().y
	var chrome := window.get_combined_minimum_size().y - body_height
	_body.custom_minimum_size.y = maxf(body_height, minf(780, viewport.y - (132 if viewport.y < 650 else 156)) - chrome)
	window.reset_size()
	window.position.y = minf(window.position.y, viewport.y - 124 - window.size.y)
	window.clamp_to_viewport()
	_queue_portrait_update()


func _size_row(row: Dictionary) -> void:
	row.portrait.custom_minimum_size.x = 36 if _compact else 40
	row.identity.custom_minimum_size.x = 124 if _compact else 172
	row.button.custom_minimum_size.y = 54 if _compact else 56
	row.name.add_theme_font_size_override("font_size", 15 if _compact else 16)
	row.activity.add_theme_font_size_override("font_size", 14)


func _label(text: String, font_size: int, color := UITheme.HEARTH_TEXT) -> Label:
	var label := Label.new()
	label.text = text
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _margin(child: Control, horizontal: int, vertical: int) -> MarginContainer:
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side: String in ["left", "right"]: margin.add_theme_constant_override("margin_" + side, horizontal)
	for side: String in ["top", "bottom"]: margin.add_theme_constant_override("margin_" + side, vertical)
	margin.add_child(child)
	return margin


func _ignore_mouse(node: Node) -> void:
	if node is Button: return
	if node is Control: node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children(): _ignore_mouse(child)
