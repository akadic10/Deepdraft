extends VBoxContainer

## Presentation only: room topology, temperature and installed lights are owned
## by RoomManager. A selection overlay never represents the room's illumination.
var window: UIWindow
var _status: Label
var _temperature: Label
var _zone: Label
var _lighting: Label
var _lighting_hint: Label
var _volume: Label
var _doors: Label
var _heat: Label
var _season: Label
var _level: Label
var _overview: VBoxContainer
var _details: VBoxContainer
var _scroll: ScrollContainer
var _tabs: Array[Button] = []


func _ready() -> void:
	UITheme.apply_surface(self)
	custom_minimum_size.x = 332
	add_theme_constant_override("separation", 12)
	_status = _label(self, "SEALED ROOM", 11, UITheme.HEARTH_COPPER)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	add_child(tabs)
	for caption in ["Overview", "Details"]:
		var tab := UITheme.make_button(caption, "", Vector2(0, 34))
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.pressed.connect(_show_tab.bind(_tabs.size()))
		tabs.add_child(tab)
		_tabs.append(tab)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.mouse_force_pass_scroll_events = false
	add_child(_scroll)
	var pages := VBoxContainer.new()
	pages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(pages)
	_overview = VBoxContainer.new()
	_overview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_overview.add_theme_constant_override("separation", 14)
	pages.add_child(_overview)
	var temperature := _card(_overview, "TEMPERATURE")
	_temperature = _label(temperature, "", 28)
	UITheme.apply_title(_temperature, 28)
	_zone = _label(temperature, "", 13, UITheme.HEARTH_MUTED)
	var lighting := _card(_overview, "LIGHTING")
	_lighting = _label(lighting, "", 18)
	_lighting_hint = _label(lighting, "", 13, UITheme.HEARTH_MUTED)
	_volume = _row(_overview, "Room volume")
	_doors = _row(_overview, "Doors")
	_details = VBoxContainer.new()
	_details.add_theme_constant_override("separation", 18)
	pages.add_child(_details)
	_heat = _row(_details, "Heating")
	_season = _row(_details, "Seasonal influence")
	_level = _row(_details, "Average floor level")
	_label(_details, "Doors enclose the room. Its depth, the season and heat sources inside determine its temperature.", 13, UITheme.HEARTH_MUTED)
	_label(self, "Select another room to inspect · Esc to finish", 11, UITheme.HEARTH_MUTED)
	get_viewport().size_changed.connect(_fit)
	_show_tab(0)
	_fit()


func show_room(room: Dictionary) -> void:
	var frozen := bool(room.get("is_frozen_vault", false))
	_status.text = "FROZEN VAULT · SEALED" if frozen else "SEALED ROOM"
	_temperature.text = "%.1f°C" % float(room.get("temp_c", 0.0))
	var level := float(room.get("mean_floor_y", 0.0))
	_zone.text = _zone_name(level)
	var count := RoomManager.count_room_lights(room.get("cells", {}))
	_lighting.text = "No light sources" if count == 0 else "%d light source%s" % [count, "" if count == 1 else "s"]
	_lighting_hint.text = "Place a torch or brazier inside to light this room." if count == 0 else "Installed lights illuminate the space around them."
	var volume := int(room.get("volume", 0))
	_volume.text = "%d blocks" % volume
	_doors.text = str(room.get("door_cells", {}).size())
	var heat := int(room.get("heat_units", 0))
	_heat.text = "%d units · +%.1f°C" % [heat, float(heat) / maxf(1, volume)]
	_season.text = "%d%%" % roundi(float(room.get("seasonal_influence", 0)) * 100)
	_level.text = "%.1f" % level
	# Wrapped text gets its actual height after the window establishes a width.
	# Shrink the first-open layout too, not just subsequent viewport resizes.
	_fit.call_deferred()


func _show_tab(index: int) -> void:
	_overview.visible = index == 0
	_details.visible = index == 1
	for i in range(_tabs.size()): UITheme.apply_hearth_button(_tabs[i], i == index)
	_scroll.scroll_vertical = 0
	_fit()


func _fit() -> void:
	_scroll.custom_minimum_size.y = clampf(get_viewport_rect().size.y - 260, 170, 310)
	if window != null:
		window.reset_size()
		window.clamp_to_viewport.call_deferred()


func _card(parent: Node, title: String) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.hearth_panel(true))
	parent.add_child(panel)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	panel.add_child(body)
	_label(body, title, 11, UITheme.HEARTH_COPPER)
	return body


func _row(parent: Node, title: String) -> Label:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	var caption := _label(row, title, 13, UITheme.HEARTH_MUTED)
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var value := _label(row, "", 14)
	value.autowrap_mode = TextServer.AUTOWRAP_OFF
	value.size_flags_horizontal = Control.SIZE_SHRINK_END
	return value


func _label(parent: Node, text: String, font_size: int, color: Color = UITheme.HEARTH_TEXT) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


func _zone_name(level: float) -> String:
	if level >= 65: return "Cool Cave"
	if level >= 50: return "Cold Cave"
	if level >= 37: return "Deep Cold"
	return "Frozen Zone"
