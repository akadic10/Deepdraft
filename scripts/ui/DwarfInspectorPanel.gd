extends VBoxContainer

## The first Hearth & iron surface. A read-only portrait uses cloned visual
## parts in its own viewport, never another live agent or a world camera feed.
const Portrait = preload("res://scripts/ui/DwarfPortrait.gd")
signal action_requested(action: String)

## The colony overview embeds the same live detail component in its own column.
var embedded := false
var _agent: DwarfAgent
var _portrait: SubViewport
var _portrait_model: Node3D
var _name_label: Label
var _profession: Label
var _activity: Label
var _explanation: Label
var _destination: Label
var _rest_label: Label
var _rest: ProgressBar
var _load_label: Label
var _load: ProgressBar
var _cargo: Label
var _location: Label
var _traits: VBoxContainer
var _shown_traits: Array = []
var _traits_initialized := false
var _follow: Button
var _overview: VBoxContainer
var _details: VBoxContainer
var _scroll: ScrollContainer
var _tabs: Array[Button] = []
var _portrait_frame: PanelContainer
var _footer_hint: Label


func _ready() -> void:
	custom_minimum_size.x = 272 if embedded else 352
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 8 if embedded else 10)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12 if embedded else 16)
	add_child(header)
	_build_portrait(header)
	var identity := VBoxContainer.new()
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	identity.add_theme_constant_override("separation", 7)
	header.add_child(identity)
	if not embedded: _label(identity, "COLONY MEMBER", 11, UITheme.HEARTH_COPPER)
	_name_label = _label(identity, "", 20 if embedded else 23)
	if embedded:
		_name_label.max_lines_visible = 2
		_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name_label.add_theme_font_override("font", UITheme.hearth_title_font())
	_profession = _label(identity, "", 14, UITheme.HEARTH_MUTED)
	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 6)
	add_child(tab_row)
	for title: String in ["Overview", "Details"]:
		var tab := _button(tab_row, title)
		var index := _tabs.size()
		tab.pressed.connect(_show_tab.bind(index))
		_tabs.append(tab)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.mouse_force_pass_scroll_events = false
	if embedded: _scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_scroll)
	var pages := VBoxContainer.new()
	pages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(pages)
	_overview = VBoxContainer.new()
	_overview.add_theme_constant_override("separation", 8 if embedded else 12)
	pages.add_child(_overview)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UITheme.hearth_panel(true))
	_overview.add_child(card)
	var activity_box := VBoxContainer.new()
	activity_box.add_theme_constant_override("separation", 6)
	card.add_child(activity_box)
	_label(activity_box, "RIGHT NOW", 11, UITheme.HEARTH_COPPER)
	_activity = _label(activity_box, "", 18)
	var destination_box := _section(_overview, "DESTINATION")
	_destination = _label(destination_box, "", 14)
	var rest_box := _section(_overview, "REST")
	_rest_label = _label(rest_box, "", 14)
	# A single compact line leaves room for the cargo readout at 720p.
	rest_box.get_child(0).hide()
	_rest = _progress(rest_box)
	_rest.tooltip_text = "Current rest level. Dwarves sleep when tired."
	var carry_box := _section(_overview, "CARRYING")
	_cargo = _label(carry_box, "", 14)
	_load_label = _label(carry_box, "", 12, UITheme.HEARTH_MUTED)
	_load = _progress(carry_box)
	_load.tooltip_text = "Carry load reflects each object's weight. Crate contents do not count as separate carried objects."
	_details = VBoxContainer.new()
	_details.add_theme_constant_override("separation", 18)
	pages.add_child(_details)
	_location = _label(_section(_details, "CURRENT LOCATION"), "", 14)
	_explanation = _label(_section(_details, "CURRENT ACTIVITY"), "", 14)
	_traits = _section(_details, "TRAITS")
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	add_child(actions)
	var locate := _button(actions, "Locate")
	locate.tooltip_text = "Center the camera on this dwarf."
	locate.pressed.connect(func(): action_requested.emit("locate"))
	_follow = _button(actions, "Follow", true)
	_follow.tooltip_text = "Follow this dwarf. Moving the camera manually stops following."
	_follow.pressed.connect(func(): action_requested.emit("follow"))
	_footer_hint = _label(self, "Move the camera to stop following" if embedded else "Move the camera to stop following · Esc to close", 11, UITheme.HEARTH_MUTED)
	get_viewport().size_changed.connect(_resize_body)
	_resize_body()
	_show_tab(0)


func show_data(data: Dictionary, following: bool) -> void:
	var agent: DwarfAgent = data.agent
	if agent != _agent:
		_agent = agent
		_refresh_portrait()
		_show_tab(0)
	_name_label.text = String(data.title)
	_name_label.tooltip_text = String(data.title)
	_profession.text = "%s · Dwarf" % String(data.profession)
	_activity.text = String(data.activity)
	_explanation.text = String(data.explanation)
	_activity.tooltip_text = String(data.explanation)
	_destination.text = String(data.destination)
	var rest_percent := roundi(float(data.rest) * 100)
	_rest_label.text = "Rest  %d%% · %s" % [rest_percent, "Sleeping" if data.sleeping else ("Tired" if rest_percent <= 25 else "Awake")]
	_rest.value = rest_percent
	var lines: Array[String] = []
	for entry: Dictionary in data.cargo:
		var line := "%d × %s" % [entry.count, entry.name]
		if entry.crate:
			line += " (%d %s)" % [entry.objects, "crate" if entry.objects == 1 else "crates"]
		lines.append(line)
	_cargo.text = "\n".join(lines) if not lines.is_empty() else "Empty hands"
	_load_label.text = "Carry load  %d / %d" % [data.load, data.capacity]
	_load.max_value = maxi(1, int(data.capacity))
	_load.value = int(data.load)
	_location.text = String(data.location)
	_show_traits(data.get("trait_details", []))
	var follow_text := "Stop following" if following else "Follow"
	if _follow.text != follow_text:
		_follow.text = follow_text
		UITheme.apply_hearth_button(_follow, following)


func _show_traits(entries: Array) -> void:
	# Trait definitions are static. Reuse the controls during live activity updates.
	if _traits_initialized and entries == _shown_traits: return
	_traits_initialized = true
	_shown_traits = entries.duplicate(true)
	for child in _traits.get_children().slice(1):
		_traits.remove_child(child)
		child.queue_free()
	if entries.is_empty():
		_label(_traits, "No distinctive traits", 14)
		return
	# Traits are currently generated/saved, but the simulation does not apply effects.
	_label(_traits, "Trait effects are not active yet.", 12, UITheme.HEARTH_MUTED)
	for entry: Dictionary in entries:
		var card := VBoxContainer.new()
		card.add_theme_constant_override("separation", 5)
		_traits.add_child(card)
		var title := _label(card, String(entry.name), 17, UITheme.HEARTH_COPPER)
		title.add_theme_font_override("font", UITheme.hearth_title_font())
		_label(card, String(entry.description), 14)


func clear_subject() -> void:
	_agent = null
	if is_instance_valid(_portrait_model):
		_portrait_model.free()
	_portrait_model = null
	_portrait.render_target_update_mode = SubViewport.UPDATE_DISABLED


func _resize_body() -> void:
	# Leave the default inspector footer clear of the centered bottom navigation.
	_scroll.custom_minimum_size.y = 40 if embedded else clampf(get_viewport_rect().size.y - 422, 120, 340)
	if embedded:
		var compact := get_viewport_rect().size.y < 650
		_portrait_frame.custom_minimum_size = Vector2(52, 52) if compact else Vector2(64, 72)
		_name_label.max_lines_visible = 1 if compact else 2
		_name_label.add_theme_font_size_override("font_size", 18 if compact else 20)
		add_theme_constant_override("separation", 6 if compact else 8)
		_footer_hint.visible = not compact


func _show_tab(index: int) -> void:
	_overview.visible = index == 0
	_details.visible = index == 1
	_scroll.scroll_vertical = 0
	for i in range(_tabs.size()):
		UITheme.apply_hearth_button(_tabs[i], i == index)


func _build_portrait(parent: Control) -> void:
	var frame := PanelContainer.new()
	_portrait_frame = frame
	frame.custom_minimum_size = Vector2(64, 72) if embedded else Vector2(80, 88)
	frame.add_theme_stylebox_override("panel", UITheme.hearth_panel())
	parent.add_child(frame)
	var texture := TextureRect.new()
	texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(texture)
	_portrait = Portrait.create_viewport(texture)


func _refresh_portrait() -> void:
	if is_instance_valid(_portrait_model):
		_portrait_model.free()
	_portrait_model = Portrait.create_model(_portrait, _agent)


func _section(parent: Control, title: String) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 7)
	parent.add_child(column)
	_label(column, title, 11, UITheme.HEARTH_MUTED)
	return column


func _label(parent: Control, text: String, font_size: int, color: Color = UITheme.HEARTH_TEXT) -> Label:
	var label := Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


func _button(parent: Control, text: String, primary: bool = false) -> Button:
	var button := Button.new()
	button.text = text
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.apply_hearth_button(button, primary)
	parent.add_child(button)
	return button


func _progress(parent: Control) -> ProgressBar:
	var bar := ProgressBar.new()
	UITheme.hearth_progress(bar)
	parent.add_child(bar)
	return bar
