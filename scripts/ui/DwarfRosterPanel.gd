extends VBoxContainer

## Colony Dwarves (doc 261), after Stonehearth's Citizens: a stable table of every dwarf
## and, at the left, the Details card for the selected one. Everything live is on the rows
## (what each dwarf is doing and carrying, their mood and rest); the card holds who the
## dwarf is and the ways into more, the character sheet first. ObjectExplorer retains
## ownership of world selection.
const Inspection = preload("res://scripts/components/DwarfInspection.gd")
const Portrait = preload("res://scripts/ui/DwarfPortrait.gd")
const Card = preload("res://scripts/ui/DwarfDetailsCard.gd")
const REFRESH_SECONDS := 0.35
# Text sizes come from the type scale (doc 23, "Type").
const LARGE := UITheme.TYPE_LARGE
const MEDIUM := UITheme.TYPE_MEDIUM
const SMALL := UITheme.TYPE_SMALL
## Sizes by the screen's height: large from 1300 px tall (the 7680×2160 screen), short
## below 900, where the card sets the portrait beside the name to save height, and small
## below 650. `width` and
## `body` are the most the window and its body take; narrow screens (below 1150 px across)
## trim the card, the search and the name column.
const SIZES := {
	"large": {"width": 1680.0, "body": 1180.0, "card": 420.0, "gap": 10, "row": 76.0, "portrait": 48.0, "identity": 240.0,
		"name": LARGE.lead, "sub": LARGE.small, "activity": LARGE.body, "note": LARGE.small, "face": 44.0, "mood": 160.0, "mood_font": LARGE.body, "rest": 72.0, "level_bar": Vector2(150, 8),
		"locate": Vector2(92, 40), "button_font": LARGE.body, "heading": LARGE.small, "filter": 44.0, "filter_font": LARGE.body, "search": Vector2(380, 42),
		"mode": Vector2(124, 38), "check": Vector2(62, 44), "footer": LARGE.small, "empty": LARGE.lead,
		"vertical": true, "card_heading": LARGE.small, "card_portrait": 180.0, "card_name": LARGE.title, "card_role": LARGE.lead, "card_role_tile": 44.0,
		"card_bar": Vector2(300, 14), "card_line": LARGE.body, "card_tag": LARGE.small, "card_button": 46.0, "card_main": 54.0, "card_button_font": LARGE.body, "type": LARGE},
	"medium": {"width": 1200.0, "body": 780.0, "card": 328.0, "gap": 8, "row": 56.0, "portrait": 32.0, "identity": 172.0,
		"name": MEDIUM.lead, "sub": MEDIUM.small, "activity": MEDIUM.body, "note": MEDIUM.small, "face": 32.0, "mood": 116.0, "mood_font": MEDIUM.body, "rest": 52.0, "level_bar": Vector2(108, 6),
		"locate": Vector2(60, 30), "button_font": MEDIUM.body, "heading": MEDIUM.small, "filter": 34.0, "filter_font": MEDIUM.body, "search": Vector2(280, 32),
		"mode": Vector2(92, 30), "check": Vector2(46, 34), "footer": MEDIUM.small, "empty": MEDIUM.lead,
		"vertical": true, "card_heading": MEDIUM.small, "card_portrait": 120.0, "card_name": MEDIUM.title, "card_role": MEDIUM.lead, "card_role_tile": 30.0,
		"card_bar": Vector2(220, 10), "card_line": MEDIUM.body, "card_tag": MEDIUM.small, "card_button": 36.0, "card_main": 42.0, "card_button_font": MEDIUM.body, "type": MEDIUM},
	"short": {"width": 1200.0, "body": 780.0, "card": 328.0, "gap": 6, "row": 56.0, "portrait": 32.0, "identity": 172.0,
		"name": MEDIUM.lead, "sub": MEDIUM.small, "activity": MEDIUM.body, "note": MEDIUM.small, "face": 32.0, "mood": 116.0, "mood_font": MEDIUM.body, "rest": 52.0, "level_bar": Vector2(108, 6),
		"locate": Vector2(60, 30), "button_font": MEDIUM.body, "heading": MEDIUM.small, "filter": 34.0, "filter_font": MEDIUM.body, "search": Vector2(280, 32),
		"mode": Vector2(92, 30), "check": Vector2(46, 34), "footer": MEDIUM.small, "empty": MEDIUM.lead,
		"vertical": false, "card_heading": SMALL.small, "card_portrait": 72.0, "card_name": SMALL.title, "card_role": SMALL.lead, "card_role_tile": 24.0,
		"card_bar": Vector2(0, 8), "card_line": SMALL.body, "card_tag": SMALL.small, "card_button": 30.0, "card_main": 34.0, "card_button_font": SMALL.body, "type": MEDIUM},
	"small": {"width": 1200.0, "body": 780.0, "card": 328.0, "gap": 4, "row": 56.0, "portrait": 32.0, "identity": 172.0,
		"name": MEDIUM.lead, "sub": MEDIUM.small, "activity": MEDIUM.body, "note": MEDIUM.small, "face": 32.0, "mood": 116.0, "mood_font": MEDIUM.body, "rest": 52.0, "level_bar": Vector2(108, 6),
		"locate": Vector2(60, 30), "button_font": MEDIUM.body, "heading": MEDIUM.small, "filter": 34.0, "filter_font": MEDIUM.body, "search": Vector2(280, 32),
		"mode": Vector2(92, 30), "check": Vector2(46, 34), "footer": MEDIUM.small, "empty": MEDIUM.lead,
		"vertical": false, "card_heading": SMALL.small, "card_portrait": 56.0, "card_name": SMALL.title, "card_role": SMALL.lead, "card_role_tile": 20.0,
		"card_bar": Vector2(0, 6), "card_line": SMALL.body, "card_tag": SMALL.small, "card_button": 28.0, "card_main": 32.0, "card_button_font": SMALL.body, "type": SMALL},
}

var director: Node
var dock: Node   # DockUI, when there is one: the roster fits above it
var window: UIWindow
var category := "all"
var _size: Dictionary = {}
var _elapsed := 0.0
var _rows := {}
var _filters := {}
var _search: LineEdit
var _scroll: ScrollContainer
var _list: VBoxContainer
var _empty: Label
var _footer: Label
var _heading: HBoxContainer
var _heading_portrait: Control
var _heading_dwarf: Label
var _heading_mood: Label
var _heading_activity: Label
var _heading_rest: Label
var _heading_action: Control
var _textures := {}
var _compact := false
var _body: HBoxContainer
var _detail_frame: PanelContainer
var _card: VBoxContainer
var _detail_empty: Label
var _explorer: Node
var _portraits_pending := false
var _work_view := false
var _view_buttons: Array[Button] = []
var _work_heading: HBoxContainer


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
	_search.text_changed.connect(func(_text: String): _scroll.scroll_vertical = 0; refresh())
	top.add_child(_search)
	_body = HBoxContainer.new()
	_body.add_theme_constant_override("separation", 12)
	add_child(_margin(_body, 12, 0))
	# The Details card, after Stonehearth's: who the selected dwarf is, and the ways in.
	_detail_frame = PanelContainer.new()
	_detail_frame.add_theme_stylebox_override("panel", UITheme.hearth_panel(true))
	_body.add_child(_detail_frame)
	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_frame.add_child(details)
	_detail_empty = _label("Select a dwarf\n\nTheir portrait, profession and traits appear here, with their character sheet a click away.", MEDIUM.lead, UITheme.HEARTH_MUTED)
	_detail_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_empty.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail_empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_detail_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	details.add_child(_detail_empty)
	_card = Card.new()
	_card.hide()
	details.add_child(_card)
	var table := VBoxContainer.new()
	table.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	table.add_theme_constant_override("separation", 6)
	_body.add_child(table)
	var modes := HBoxContainer.new()
	table.add_child(modes)
	for title: String in ["Overview", "Work"]:
		var mode := UITheme.make_button(title, "", Vector2(92, 30))
		var work_mode := title == "Work"
		mode.pressed.connect(set_work_view.bind(work_mode))
		modes.add_child(mode)
		_view_buttons.append(mode)
	_heading = HBoxContainer.new()
	_heading.add_theme_constant_override("separation", 10)
	table.add_child(_margin(_heading, 8, 4))
	_heading_portrait = Control.new()
	_heading.add_child(_heading_portrait)
	_heading_dwarf = _label("DWARF", MEDIUM.small, UITheme.HEARTH_MUTED)
	_heading.add_child(_heading_dwarf)
	# Stonehearth's Morale column: the step's face and word on every row.
	_heading_mood = _label("MOOD", MEDIUM.small, UITheme.HEARTH_MUTED)
	_heading.add_child(_heading_mood)
	_heading_activity = _label("ACTIVITY / CARRYING", MEDIUM.small, UITheme.HEARTH_MUTED)
	_heading_activity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_heading.add_child(_heading_activity)
	_heading_rest = _label("REST", MEDIUM.small, UITheme.HEARTH_MUTED)
	_heading.add_child(_heading_rest)
	_heading_action = Control.new()
	_heading.add_child(_heading_action)
	_work_heading = HBoxContainer.new()
	_work_heading.add_theme_constant_override("separation", 0)
	for entry: Dictionary in DwarfAssets.work_permissions():
		var label := _label(entry.label, MEDIUM.small, UITheme.HEARTH_MUTED)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.tooltip_text = entry.description
		_work_heading.add_child(label)
	_heading.add_child(_work_heading)
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
	_empty = _label("No dwarves have arrived yet.\nPlace a settlement flag to welcome your first settlers.", MEDIUM.lead)
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty.custom_minimum_size.y = 70
	_list.add_child(_empty)
	_footer = _label("Select a dwarf for details · Locate moves the camera", MEDIUM.small, UITheme.HEARTH_MUTED)
	_footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_margin(_footer, 12, 10))
	_scroll.get_v_scroll_bar().value_changed.connect(func(_value: float): _queue_portrait_update())
	get_viewport().size_changed.connect(func(): refit.call_deferred())
	set_process(false)


func set_work_view(enabled: bool) -> void:
	_work_view = enabled
	refresh()
	refit.call_deferred()


func begin_browsing() -> void:
	_elapsed = 0.0
	_explorer = get_tree().get_first_node_in_group("object_explorer")
	if is_instance_valid(_explorer):
		_explorer.set_dwarf_inspector_host(_card)
		if not _explorer.selection_changed.is_connected(refresh):
			_explorer.selection_changed.connect(refresh)
	refresh()
	if is_instance_valid(_explorer):
		if _explorer.selected_dwarf(director) == null:
			for agent: DwarfAgent in director.get_roster():
				if _rows[agent].button.visible and director.can_inspect_dwarf(agent):
					director.inspect_dwarf(agent)
					break
	refit.call_deferred()
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
	for i in range(_view_buttons.size()): UITheme.apply_hearth_button(_view_buttons[i], _work_view == (i == 1))
	for column: Control in [_heading_activity, _heading_rest, _heading_action]: column.visible = not _work_view
	_work_heading.visible = _work_view
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
		row.role.texture = _texture(String(data.profession_icon)) if ResourceLoader.exists(String(data.profession_icon)) else null
		var experience: Dictionary = data.experience
		row.level.self_modulate.a = 1.0 if experience.earns else 0.0
		row.level.value = float(experience.progress) * 100.0
		row.work.visible = not _work_view
		row.rest_box.visible = not _work_view
		row.locate.visible = not _work_view
		row.permissions.visible = _work_view
		for key: String in row.checks:
			var check: CheckBox = row.checks[key]
			check.disabled = key == "craft" and agent.profession != "base:profession:worker"
			check.set_pressed_no_signal(bool(agent.work_permissions.get(key, true)) and not check.disabled)
		row.work_note.text = "Mining disabled" if agent.profession == "base:profession:miner" and not bool(agent.work_permissions.get("mine", true)) else "Mining focus" if agent.profession == "base:profession:miner" else "General work"
		row.activity.text = data.summary
		row.activity.add_theme_color_override("font_color", UITheme.HEARTH_COPPER if data.group == "resting" else UITheme.SUCCESS if data.group == "working" else UITheme.HEARTH_TEXT)
		row.rest.value = roundi(float(data.rest) * 100)
		row.rest_label.text = "%d%%" % roundi(float(data.rest) * 100)
		row.rest_label.add_theme_color_override("font_color", UITheme.DEV_ORANGE if float(data.rest) <= .25 else UITheme.HEARTH_TEXT)
		row.rest_box.tooltip_text = "Rest: %d%% · %s" % [roundi(float(data.rest) * 100), "Sleeping" if data.sleeping else "Tired" if float(data.rest) <= .25 else "Awake"]
		var mood: Dictionary = data.get("mood", {})
		row.mood.visible = not mood.is_empty()
		if not mood.is_empty():
			row.mood_face.texture = _texture(String(mood.icon))
			row.mood_word.text = String(mood.word)
		row.button.tooltip_text = "%s · %s\n%s\n%s" % [data.title, data.profession, data.activity, data.explanation]
		if experience.earns: row.button.tooltip_text += "\n" + String(experience.line)
		if not mood.is_empty(): row.button.tooltip_text += "\nMood: %s · Happiness %d%%" % [mood.word, int(mood.points)]
		if _work_view: row.button.tooltip_text += "\nWork: " + row.work_note.text
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
		UITheme.show_tab(_filters[key].button, category == key)
	_empty.visible = shown == 0
	_empty.text = "No dwarves have arrived yet.\nPlace a settlement flag to welcome your first settlers." if agents.is_empty() else "No dwarves match this view.\nTry another filter or name."
	_detail_empty.visible = not _card.visible
	_footer.text = "%d of %d dwarves · Select a row for details · Locate moves the camera" % [shown, agents.size()]
	if _work_view: _footer.text = "Checked = allowed · Miners prefer mining · Supplies for a job stay allowed · Rest is automatic"
	_queue_portrait_update()
	# Never sort by changing activity, rebuild rows or refit on these wakes.


func _build_row(agent: DwarfAgent) -> void:
	var button := Button.new()
	button.toggle_mode = true
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
	line.add_child(UITheme.framed_picture(portrait))   # on the people tile
	# The profession's picture on a tile of its own, at the portrait's size (doc 23).
	var role := TextureRect.new()
	role.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	role.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	line.add_child(UITheme.framed_picture(role))
	var identity := VBoxContainer.new()
	identity.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	identity.add_theme_constant_override("separation", 1)
	line.add_child(identity)
	var name_label := _label(agent.dwarf_name, MEDIUM.lead)
	UITheme.apply_heading(name_label, MEDIUM.lead)
	identity.add_child(name_label)
	var profession := _label("", MEDIUM.small, UITheme.HEARTH_MUTED)
	identity.add_child(profession)
	# The way to the next level, where the profession earns them. Every row keeps the
	# bar's room, so names and words line up whatever the profession.
	var level := ProgressBar.new()
	UITheme.hearth_progress(level)
	level.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	identity.add_child(level)
	var mood := HBoxContainer.new()
	mood.add_theme_constant_override("separation", 6)
	mood.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(mood)
	var face := TextureRect.new()
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mood.add_child(face)
	var word := _label("", MEDIUM.body)
	UITheme.apply_heading(word, MEDIUM.body)
	word.size_flags_horizontal = Control.SIZE_EXPAND_FILL   # a clipped label has no width of its own
	word.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mood.add_child(word)
	var work := VBoxContainer.new()
	work.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	work.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(work)
	var activity := _label("", MEDIUM.body)
	work.add_child(activity)
	var cargo_row := HBoxContainer.new()
	work.add_child(cargo_row)
	var cargo_icon := TextureRect.new()
	cargo_icon.custom_minimum_size = Vector2(20, 18)
	cargo_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cargo_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	cargo_row.add_child(cargo_icon)
	var note := _label("", MEDIUM.small, UITheme.HEARTH_MUTED)
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cargo_row.add_child(note)
	var rest_box := VBoxContainer.new()
	rest_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(rest_box)
	var rest_label := _label("", MEDIUM.small)
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
	var permissions := HBoxContainer.new()
	permissions.add_theme_constant_override("separation", 0)
	permissions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(permissions)
	var checks := {}
	for entry: Dictionary in DwarfAssets.work_permissions():
		var check := CheckBox.new()
		for state: String in ["normal", "pressed", "disabled", "hover", "hover_pressed"]:
			var style := UITheme.style(UITheme.HOVER_BG if state in ["hover", "hover_pressed"] else Color.TRANSPARENT, Color.TRANSPARENT, 0, 2, 0, 0)
			style.content_margin_left = 14
			style.content_margin_right = 8
			check.add_theme_stylebox_override(state, style)
		check.tooltip_text = "%s: %s" % [entry.label, entry.description]
		check.toggled.connect(func(allowed: bool):
			if is_instance_valid(agent) and agent in director.get_roster(): agent.set_work_permission(entry.id, allowed)
			refresh())
		permissions.add_child(check)
		checks[entry.id] = check
	var work_note := _label("", MEDIUM.small, UITheme.HEARTH_MUTED)
	work_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	work_note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	permissions.add_child(work_note)
	_ignore_mouse(line)
	button.pressed.connect(func():
		if is_instance_valid(agent): director.inspect_dwarf(agent)
		refresh())
	_rows[agent] = {"button": button, "portrait": portrait, "viewport": null, "role": role, "level": level,
		"identity": identity, "name": name_label, "profession": profession, "mood": mood, "mood_face": face, "mood_word": word,
		"activity": activity, "cargo_icon": cargo_icon, "note": note, "rest_box": rest_box, "rest_label": rest_label,
		"rest": rest, "locate": locate, "work": work, "permissions": permissions, "checks": checks, "work_note": work_note}
	if not _size.is_empty(): _size_row(_rows[agent])


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
	var path := "res://assets/ui/items/%s.png" % key.replace(":", "_")
	if not ResourceLoader.exists(path):
		path = "res://assets/ui/furniture/%s.png" % key.get_slice(":", key.get_slice_count(":") - 1)
	if not ResourceLoader.exists(path): path = "res://assets/ui/icons/stocks.png"
	return _texture(path)


func _texture(path: String) -> Texture2D:
	if not _textures.has(path): _textures[path] = load(path)
	return _textures[path]


func refit() -> void:
	if window == null or not is_inside_tree(): return
	var viewport := get_viewport_rect().size
	_compact = viewport.x < 1150
	var chosen: Dictionary = SIZES.large if viewport.y >= 1300.0 else (SIZES.medium if viewport.y >= 900.0 else (SIZES.short if viewport.y >= 650.0 else SIZES.small))
	if chosen != _size:
		_size = chosen
		_apply_size()
	var s := _size
	custom_minimum_size.x = minf(float(s.width), viewport.x - 50)
	_detail_frame.custom_minimum_size.x = float(s.card) - (32.0 if _compact else 0.0)
	_search.custom_minimum_size = Vector2(s.search.x - (60.0 if _compact else 0.0), s.search.y)
	# The portrait's and the profession's tiles, each with its margin, and the gap between.
	_heading_portrait.custom_minimum_size.x = (float(s.portrait) + (4.0 if _compact else 8.0)) * 2.0 + 10.0
	_heading_dwarf.custom_minimum_size.x = _identity_width()
	for row: Dictionary in _rows.values(): _size_row(row)
	_body.custom_minimum_size.y = 0
	var body_height := _body.get_combined_minimum_size().y
	var chrome := window.get_combined_minimum_size().y - body_height
	# Between the top (lower on larger screens) and the dock, with a gap above the dock;
	# without a dock (test fixtures), down to the screen's edge.
	var top := UIWindow.VIEWPORT_MARGIN if viewport.y < 650 else 32.0
	var bottom: float = (dock.dock_top() if dock != null else viewport.y) - 8.0
	_body.custom_minimum_size.y = maxf(body_height, minf(float(s.body), bottom - top) - chrome)
	window.reset_size()
	window.position.y = minf(window.position.y, bottom - window.size.y)
	window.clamp_to_viewport()
	_queue_portrait_update()


## The size's fonts and blocks for everything but the rows.
func _apply_size() -> void:
	var s := _size
	for entry: Dictionary in _filters.values():
		entry.button.custom_minimum_size.y = float(s.filter)
		entry.button.add_theme_font_size_override("font_size", s.filter_font)
	_search.add_theme_font_size_override("font_size", s.filter_font)
	for mode: Button in _view_buttons:
		mode.custom_minimum_size = s.mode
		mode.add_theme_font_size_override("font_size", s.button_font)
	for label: Label in [_heading_dwarf, _heading_mood, _heading_activity, _heading_rest]:
		label.add_theme_font_size_override("font_size", s.heading)
	_heading_mood.custom_minimum_size.x = float(s.mood)
	_heading_rest.custom_minimum_size.x = float(s.rest)
	_heading_action.custom_minimum_size.x = float(s.locate.x) + 12.0   # Locate and the scrollbar's gutter
	for label: Label in _work_heading.get_children():
		label.custom_minimum_size.x = float(s.check.x)
		label.add_theme_font_size_override("font_size", s.heading)
	_footer.add_theme_font_size_override("font_size", s.footer)
	_footer.custom_minimum_size.y = float(s.footer) + 6.0
	for label: Label in [_empty, _detail_empty]: label.add_theme_font_size_override("font_size", s.empty)
	_card.apply_size(s)


func _size_row(row: Dictionary) -> void:
	var s := _size
	# The tile around the portrait adds 8 px, so the column stays the heading's width.
	row.portrait.custom_minimum_size.x = float(s.portrait) - (4.0 if _compact else 0.0)
	row.role.custom_minimum_size.x = row.portrait.custom_minimum_size.x
	row.level.custom_minimum_size = s.level_bar
	row.identity.custom_minimum_size.x = _identity_width()
	row.button.custom_minimum_size.y = float(s.row) - (2.0 if _compact else 0.0)
	row.name.add_theme_font_size_override("font_size", int(s.name))
	row.profession.add_theme_font_size_override("font_size", s.sub)
	row.mood.custom_minimum_size.x = float(s.mood)
	row.mood_face.custom_minimum_size = Vector2.ONE * float(s.face)
	row.mood_word.add_theme_font_size_override("font_size", s.mood_font)
	row.activity.add_theme_font_size_override("font_size", s.activity)
	row.note.add_theme_font_size_override("font_size", s.note)
	row.rest_box.custom_minimum_size.x = float(s.rest)
	row.rest_label.add_theme_font_size_override("font_size", s.note)
	row.locate.custom_minimum_size = s.locate
	row.locate.add_theme_font_size_override("font_size", s.button_font)
	for check: CheckBox in row.checks.values(): check.custom_minimum_size = s.check
	row.work_note.add_theme_font_size_override("font_size", s.note)
	row.work_note.visible = not _compact   # narrow screens: the row's hover gives it


func _identity_width() -> float:
	return float(_size.identity) - (48.0 if _compact else 0.0)


func _label(text: String, font_size: int, color := UITheme.HEARTH_TEXT) -> Label:
	var label := Label.new()
	label.text = text
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _margin(child: Control, horizontal: int, vertical_padding: int) -> MarginContainer:
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side: String in ["left", "right"]: margin.add_theme_constant_override("margin_" + side, horizontal)
	for side: String in ["top", "bottom"]: margin.add_theme_constant_override("margin_" + side, vertical_padding)
	margin.add_child(child)
	return margin


func _ignore_mouse(node: Node) -> void:
	if node is Button: return
	if node is Control: node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children(): _ignore_mouse(child)
