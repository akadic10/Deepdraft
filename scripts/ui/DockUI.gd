class_name DockUI
extends CanvasLayer

signal dock_action_invoked(action: String, target: String)
signal tool_requested(tool_id: String)

const DOCK_HEIGHT := 92.0
const DOCK_BOTTOM_MARGIN := 24.0
const PANEL_BOTTOM_MARGIN := 118.0
const WINDOW_START := Vector2(32.0, 130.0)
const DOCK_BUTTON_SIZE := Vector2(64.0, 64.0)
const DOCK_ICON_FONT_SIZE := 40

var _root: Control
var _dock_panel: PanelContainer
var _button_by_target: Dictionary = {}
var _active_panel_target: String = ""
var _open_windows: Dictionary = {}
var _panel_container: PanelContainer
var _panel_title: Label
var _panel_body: HBoxContainer
var _window_offset: int = 0
var _ui_registry: Node
var _world_clock: Node
var _weather_mgr: Node
var _world_info_overlay: CanvasLayer
var _block_inspector_overlay: CanvasLayer
var _slice_controller: Node = null
var _dwarf_director: Node = null
var _flag_controller: Node = null
var _stockpile_controller: Node = null
var _clock_value_labels: Dictionary = {}
var _clock_refresh_accum: float = 0.0

var _normal_button_style: StyleBox
var _hover_button_style: StyleBox
var _active_button_style: StyleBox


func _ready() -> void:
	layer = 20
	_ui_registry = get_node_or_null("/root/UIRegistry")
	if _ui_registry == null:
		push_error("DockUI: UIRegistry autoload is missing.")
		return
	_world_clock = get_node_or_null("/root/WorldClock")
	_weather_mgr = get_node_or_null("/root/WeatherManager")
	_build_styles()
	_build_root()
	_build_dock()
	_build_action_panel()
	_set_world_info_overlay(_find_canvas_layer(get_tree().current_scene, "DebugLoadingOverlay"))
	_set_block_inspector_overlay(_find_canvas_layer(get_tree().current_scene, "BlockInspector"))
	_refresh_active_buttons()


func _process(delta: float) -> void:
	# Only does work while the live Clock window is open.
	if _clock_value_labels.is_empty():
		return
	_clock_refresh_accum += delta
	if _clock_refresh_accum < 0.1:
		return
	_clock_refresh_accum = 0.0
	_update_clock_labels()


func _build_styles() -> void:
	_normal_button_style = StyleBoxEmpty.new()
	_hover_button_style = StyleBoxEmpty.new()
	_active_button_style = StyleBoxEmpty.new()


func _build_root() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)


func _build_dock() -> void:
	var dock_band := Control.new()
	dock_band.name = "DockBand"
	dock_band.anchor_left = 0.0
	dock_band.anchor_right = 1.0
	dock_band.anchor_top = 1.0
	dock_band.anchor_bottom = 1.0
	dock_band.offset_top = -(DOCK_HEIGHT + DOCK_BOTTOM_MARGIN)
	dock_band.offset_bottom = -DOCK_BOTTOM_MARGIN
	dock_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dock_band)

	var center := CenterContainer.new()
	center.name = "DockCenter"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dock_band.add_child(center)

	_dock_panel = PanelContainer.new()
	_dock_panel.name = "FloatingDock"
	_dock_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.055, 0.060, 0.065, 0.82), Color(1, 1, 1, 0.13), 8))
	center.add_child(_dock_panel)

	var margin := MarginContainer.new()
	margin.name = "DockMargin"
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	_dock_panel.add_child(margin)

	var row := HBoxContainer.new()
	row.name = "Items"
	row.add_theme_constant_override("separation", 8)
	margin.add_child(row)

	for entry in _ui_registry.call("get_dock_items"):
		if entry.get("type", "") == "separator":
			row.add_child(_make_separator())
		else:
			row.add_child(_make_dock_button(entry))


func _make_dock_button(entry: Dictionary) -> Button:
	var button := Button.new()
	button.name = "%sButton" % _node_suffix(String(entry.get("id", "dock")))
	button.custom_minimum_size = DOCK_BUTTON_SIZE
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.focus_mode = Control.FOCUS_NONE
	button.toggle_mode = true
	button.text = entry.get("emoji", "")
	button.tooltip_text = entry.get("tooltip", "")
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	button.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	button.add_theme_font_size_override("font_size", DOCK_ICON_FONT_SIZE)
	button.add_theme_stylebox_override("normal", _normal_button_style)
	button.add_theme_stylebox_override("hover", _hover_button_style)
	button.add_theme_stylebox_override("pressed", _active_button_style)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	var action := String(entry.get("action", ""))
	var target := String(entry.get("target", ""))
	button.pressed.connect(func() -> void:
		_dispatch(action, target)
	)
	_button_by_target[target] = button
	return button


func _make_separator() -> Control:
	var separator_wrap := MarginContainer.new()
	separator_wrap.name = "Separator"
	separator_wrap.custom_minimum_size = Vector2(10.0, 54.0)
	separator_wrap.add_theme_constant_override("margin_left", 3)
	separator_wrap.add_theme_constant_override("margin_right", 3)

	var line := ColorRect.new()
	line.color = Color(1, 1, 1, 0.18)
	line.custom_minimum_size = Vector2(1.0, 44.0)
	separator_wrap.add_child(line)
	return separator_wrap


func _build_action_panel() -> void:
	_panel_container = PanelContainer.new()
	_panel_container.name = "ActionPanel"
	_panel_container.anchor_left = 0.5
	_panel_container.anchor_right = 0.5
	_panel_container.anchor_top = 1.0
	_panel_container.anchor_bottom = 1.0
	_panel_container.offset_left = -300.0
	_panel_container.offset_right = 300.0
	_panel_container.offset_top = -(PANEL_BOTTOM_MARGIN + 136.0)
	_panel_container.offset_bottom = -PANEL_BOTTOM_MARGIN
	_panel_container.visible = false
	_panel_container.add_theme_stylebox_override("panel", _panel_style(Color(0.070, 0.075, 0.080, 0.92), Color(1, 1, 1, 0.12), 8))
	_root.add_child(_panel_container)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	_panel_container.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	_panel_title = Label.new()
	_panel_title.add_theme_font_size_override("font_size", 17)
	column.add_child(_panel_title)

	_panel_body = HBoxContainer.new()
	_panel_body.add_theme_constant_override("separation", 8)
	column.add_child(_panel_body)


func _dispatch(action: String, target: String) -> void:
	if action == "open_panel" and target == "mine":
		_panel_container.visible = false
		_active_panel_target = ""
		tool_requested.emit("mine_precision")
		dock_action_invoked.emit(action, target)
		_refresh_active_buttons()
		return

	match action:
		"open_panel":
			_open_action_panel(target)
		"toggle_window":
			_toggle_window(target)
		_:
			push_warning("DockUI: unknown dock action '%s' for target '%s'." % [action, target])
	dock_action_invoked.emit(action, target)
	_refresh_active_buttons()


func _open_action_panel(target: String) -> void:
	if _active_panel_target == target and _panel_container.visible:
		_active_panel_target = ""
		_panel_container.visible = false
		return

	_active_panel_target = target
	_panel_title.text = _target_title(target)
	_clear_children(_panel_body)
	for label in _panel_actions(target):
		_panel_body.add_child(_make_panel_action_button(label, target))
	_panel_container.visible = true


func _make_panel_action_button(label: String, target: String) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(128.0, 46.0)
	button.focus_mode = Control.FOCUS_NONE
	button.text = label
	button.tooltip_text = label
	button.add_theme_font_size_override("font_size", 14)
	button.add_theme_stylebox_override("normal", _normal_button_style)
	button.add_theme_stylebox_override("hover", _hover_button_style)
	button.add_theme_stylebox_override("pressed", _active_button_style)
	button.pressed.connect(func() -> void:
		_dispatch_panel_action(target, label)
	)
	return button


func _dispatch_panel_action(target: String, label: String) -> void:
	if target == "mine" and label == "Mine Block":
		_panel_container.visible = false
		_active_panel_target = ""
		tool_requested.emit("mine_precision")
		_refresh_active_buttons()
		return
	if target == "storage_zone" and label == "Draw Zone":
		_panel_container.visible = false
		_active_panel_target = ""
		tool_requested.emit("storage_zone")
		_refresh_active_buttons()
		return
	if target == "storage_zone" and label == "DEV: Spawn Drops":
		if _stockpile_controller != null and _stockpile_controller.has_method("dev_spawn_drops"):
			_stockpile_controller.call("dev_spawn_drops")
		else:
			push_warning("DockUI: no StockpileDesignationController registered.")
		return
	if label == "Cancel":
		_panel_container.visible = false
		_active_panel_target = ""
		_refresh_active_buttons()


func _toggle_window(target: String) -> void:
	if target == "world_info":
		_toggle_world_info_overlay()
		return
	if target == "block_inspector":
		_toggle_block_inspector_overlay()
		return
	if target == "clock":
		_toggle_clock_window()
		return

	if target == "slice":
		_toggle_slice_tool()
		return

	if target == "dwarves":
		if _dwarf_director != null and _dwarf_director.has_method("toggle_window"):
			_dwarf_director.call("toggle_window")
		return

	if target == "flag":
		if _flag_controller != null and _flag_controller.has_method("toggle_active"):
			_flag_controller.call("toggle_active")
		return

	if _open_windows.has(target):
		var existing := _open_windows[target] as Control
		existing.queue_free()
		_open_windows.erase(target)
		return

	var window := _make_window(target)
	_root.add_child(window)
	_open_windows[target] = window


func _make_window(target: String) -> PanelContainer:
	var window := PanelContainer.new()
	window.name = "%sWindow" % _node_suffix(target)
	window.position = WINDOW_START + Vector2(28.0 * _window_offset, 28.0 * _window_offset)
	window.size = Vector2(360.0, 260.0)
	window.custom_minimum_size = Vector2(320.0, 220.0)
	window.add_theme_stylebox_override("panel", _panel_style(Color(0.065, 0.070, 0.075, 0.94), Color(1, 1, 1, 0.12), 8))
	_window_offset = (_window_offset + 1) % 5

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	window.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	column.add_child(header)

	var title := Label.new()
	title.text = _target_title(target)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 17)
	header.add_child(title)

	var close := Button.new()
	close.text = "X"
	close.custom_minimum_size = Vector2(32.0, 28.0)
	close.focus_mode = Control.FOCUS_NONE
	close.tooltip_text = "Close"
	close.add_theme_stylebox_override("normal", _normal_button_style)
	close.add_theme_stylebox_override("hover", _hover_button_style)
	close.add_theme_stylebox_override("pressed", _active_button_style)
	close.pressed.connect(func() -> void:
		if _open_windows.has(target):
			_open_windows.erase(target)
		window.queue_free()
		_refresh_active_buttons()
	)
	header.add_child(close)

	for row_text in _window_rows(target):
		var row := Label.new()
		row.text = row_text
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_theme_font_size_override("font_size", 14)
		column.add_child(row)

	return window


func _toggle_clock_window() -> void:
	if _open_windows.has("clock"):
		var existing := _open_windows["clock"] as Control
		_open_windows.erase("clock")
		_clock_value_labels.clear()
		existing.queue_free()
		_refresh_active_buttons()
		return

	var window := _make_clock_window()
	_root.add_child(window)
	_open_windows["clock"] = window
	_update_clock_labels()
	_refresh_active_buttons()


func _make_clock_window() -> PanelContainer:
	var window := PanelContainer.new()
	window.name = "ClockWindow"
	window.position = WINDOW_START + Vector2(28.0 * _window_offset, 28.0 * _window_offset)
	window.size = Vector2(220.0, 0.0)
	window.custom_minimum_size = Vector2(200.0, 0.0)
	window.add_theme_stylebox_override("panel", _panel_style(Color(0.065, 0.070, 0.075, 0.94), Color(1, 1, 1, 0.12), 8))
	_window_offset = (_window_offset + 1) % 5

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	window.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	column.add_child(header)

	var title := Label.new()
	title.text = "Clock"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 17)
	header.add_child(title)

	var close := Button.new()
	close.text = "X"
	close.custom_minimum_size = Vector2(32.0, 28.0)
	close.focus_mode = Control.FOCUS_NONE
	close.tooltip_text = "Close"
	close.add_theme_stylebox_override("normal", _normal_button_style)
	close.add_theme_stylebox_override("hover", _hover_button_style)
	close.add_theme_stylebox_override("pressed", _active_button_style)
	close.pressed.connect(func() -> void:
		_open_windows.erase("clock")
		_clock_value_labels.clear()
		window.queue_free()
		_refresh_active_buttons()
	)
	header.add_child(close)

	_clock_value_labels = {}
	for field in ["season", "day", "time", "weather"]:
		var row := Label.new()
		row.add_theme_font_size_override("font_size", 15)
		column.add_child(row)
		_clock_value_labels[field] = row

	# Test controls — advance the clock / cycle weather to preview the systems.
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	column.add_child(buttons)
	buttons.add_child(_make_clock_button("+1 Hour", Callable(self, "_advance_clock").bind("advance_hours", 1.0)))
	buttons.add_child(_make_clock_button("+1 Season", Callable(self, "_advance_clock").bind("advance_season")))

	var buttons2 := HBoxContainer.new()
	buttons2.add_theme_constant_override("separation", 8)
	column.add_child(buttons2)
	buttons2.add_child(_make_clock_button("Weather →", Callable(self, "_cycle_weather")))

	return window


func _make_clock_button(text: String, on_press: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(100.0, 30.0)
	button.add_theme_font_size_override("font_size", 13)
	button.add_theme_stylebox_override("normal",  _style(Color(1, 1, 1, 0.07), Color(1, 1, 1, 0.16), 1, 6))
	button.add_theme_stylebox_override("hover",   _style(Color(1, 1, 1, 0.14), Color(1, 1, 1, 0.22), 1, 6))
	button.add_theme_stylebox_override("pressed", _style(Color(1, 1, 1, 0.20), Color(1, 1, 1, 0.28), 1, 6))
	button.pressed.connect(on_press)
	return button


func _advance_clock(method: String, arg = null) -> void:
	if _world_clock == null:
		return
	if arg == null:
		_world_clock.call(method)
	else:
		_world_clock.call(method, arg)
	_update_clock_labels()


func _cycle_weather() -> void:
	if _weather_mgr != null:
		_weather_mgr.call("cycle_weather")
	_update_clock_labels()


func _update_clock_labels() -> void:
	if _clock_value_labels.is_empty():
		return
	var season_text := "Unknown"
	var day_text    := "Unknown"
	var time_text   := "Unknown"
	if _world_clock != null:
		season_text = String(_world_clock.get("season")).capitalize()
		day_text    = "%d" % int(_world_clock.get("day"))
		time_text   = String(_world_clock.call("time_string"))
	var weather_text := "—"
	if _weather_mgr != null:
		weather_text = String(_weather_mgr.call("current_weather_name"))
	(_clock_value_labels["season"] as Label).text = "Season      %s" % season_text
	(_clock_value_labels["day"] as Label).text    = "Day         %s" % day_text
	(_clock_value_labels["time"] as Label).text   = "Time        %s" % time_text
	if _clock_value_labels.has("weather"):
		(_clock_value_labels["weather"] as Label).text = "Weather     %s" % weather_text


func _refresh_active_buttons() -> void:
	for target in _button_by_target:
		var button := _button_by_target[target] as Button
		button.button_pressed = target == _active_panel_target or _open_windows.has(target) or _target_canvas_visible(target)


func _toggle_world_info_overlay() -> void:
	if _world_info_overlay == null:
		_set_world_info_overlay(_find_canvas_layer(get_tree().current_scene, "DebugLoadingOverlay"))
	if _world_info_overlay == null:
		push_warning("DockUI: DebugLoadingOverlay not found.")
		return
	_world_info_overlay.visible = not _world_info_overlay.visible


func _toggle_block_inspector_overlay() -> void:
	if _block_inspector_overlay == null:
		_set_block_inspector_overlay(_find_canvas_layer(get_tree().current_scene, "BlockInspector"))
	if _block_inspector_overlay == null:
		push_warning("DockUI: BlockInspector not found.")
		return
	_block_inspector_overlay.visible = not _block_inspector_overlay.visible


func _target_canvas_visible(target: String) -> bool:
	match target:
		"world_info":
			return _world_info_overlay != null and _world_info_overlay.visible
		"block_inspector":
			return _block_inspector_overlay != null and _block_inspector_overlay.visible
		"slice":
			return _slice_controller != null and bool(_slice_controller.call("is_active"))
		"storage_zone":
			return _stockpile_controller != null and bool(_stockpile_controller.call("is_active"))
	return false


# ── Slice tool integration (doc 11 Phase 2) ───────────────────────────────────
# The SliceController owns the tool state and its palette window; the dock's
# `slice` entry only toggles it. Registration happens from SliceController._ready
# via its dock_ui_path export (Scene Decoupling Contract — no node paths here).

func register_slice_controller(controller: Node) -> void:
	_slice_controller = controller
	if controller.has_signal("slice_active_changed"):
		var refresh := Callable(self, "_on_slice_active_changed")
		if not controller.is_connected("slice_active_changed", refresh):
			controller.connect("slice_active_changed", refresh)


func _toggle_slice_tool() -> void:
	if _slice_controller == null:
		push_warning("DockUI: slice button pressed but no SliceController is registered.")
		return
	_slice_controller.call("toggle_active")


## Push-registration from DwarfDirector (the SliceController pattern) — the
## dock's 'dwarves' entry routes its toggle to the director's DEV window.
func register_dwarf_director(director: Node) -> void:
	_dwarf_director = director


## Push-registration from FlagPlacementController — the dock's 'flag' entry
## toggles the settlement-flag placement tool.
func register_flag_controller(controller: Node) -> void:
	_flag_controller = controller


## Push-registration from StockpileDesignationController (doc 18 Phase 1) —
## the Storage Zone panel's actions route here.
func register_stockpile_controller(controller: Node) -> void:
	_stockpile_controller = controller


func _on_slice_active_changed(_active: bool) -> void:
	_refresh_active_buttons()


func _find_canvas_layer(node: Node, node_name: String) -> CanvasLayer:
	if node == null:
		return null
	if node.name == node_name and node is CanvasLayer:
		return node as CanvasLayer
	for child in node.get_children():
		var found := _find_canvas_layer(child, node_name)
		if found != null:
			return found
	return null


func _set_world_info_overlay(overlay: CanvasLayer) -> void:
	_world_info_overlay = overlay
	if _world_info_overlay == null:
		return
	var refresh := Callable(self, "_refresh_active_buttons")
	if not _world_info_overlay.visibility_changed.is_connected(refresh):
		_world_info_overlay.visibility_changed.connect(refresh)


func _set_block_inspector_overlay(overlay: CanvasLayer) -> void:
	_block_inspector_overlay = overlay
	if _block_inspector_overlay == null:
		return
	var refresh := Callable(self, "_refresh_active_buttons")
	if not _block_inspector_overlay.visibility_changed.is_connected(refresh):
		_block_inspector_overlay.visibility_changed.connect(refresh)


func _target_title(target: String) -> String:
	match target:
		"mine": return "Mine"
		"chop": return "Chop"
		"build": return "Build"
		"storage_zone": return "Storage Zone"
		"farm": return "Farm"
		"military": return "Military"
		"labor": return "Labor"
		"stockpiles": return "Stockpiles"
		"trade": return "Trade"
		"world_info": return "World Info"
		"block_inspector": return "Block Inspector"
	return target.capitalize()


func _panel_actions(target: String) -> Array[String]:
	match target:
		"mine":
			return ["Mine Block", "Channel", "Clear Rubble", "Cancel"]
		"chop":
			return ["Chop Trees", "Forestry Zone", "Clear Stumps", "Cancel"]
		"build":
			return ["Workshop", "Furniture", "Stockpile", "Door"]
		"storage_zone":
			return ["Draw Zone", "DEV: Spawn Drops", "Cancel"]
		"farm":
			return ["Cave Plot", "Surface Plot", "Plant Crop", "Harvest"]
		"military":
			return ["Patrol Route", "Guard Post", "Armory", "Enlist"]
	return []


func _window_rows(target: String) -> Array[String]:
	match target:
		"labor":
			return ["Name        Job        Priority", "Urist       Idle       5", "Bomrek      Hauling    4", "Dastot      Mining     6"]
		"stockpiles":
			return ["Stone       0", "Ore         0", "Food        0", "Drink       0", "Trade Goods 0"]
		"trade":
			return ["Counter     None", "Buy Orders  0", "Reputation  0", "Caravan     Away"]
		"world_info":
			return _world_info_rows()
		"block_inspector":
			return ["Mode        Ready", "Target      None", "Click a visible block to inspect it."]
	return []


func _world_info_rows() -> Array[String]:
	if _world_clock == null:
		return ["Season      Unknown", "Year        Unknown", "Day         Unknown", "Time        Unknown"]
	return [
		"Season      %s" % String(_world_clock.get("season")).capitalize(),
		"Year        %d" % int(_world_clock.get("year")),
		"Day         %d" % int(_world_clock.get("day")),
		"Time        %s" % String(_world_clock.call("time_string")),
	]


func _clear_children(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


func _node_suffix(value: String) -> String:
	var result := ""
	for part in value.split("_", false):
		result += part.capitalize().replace(" ", "")
	return result


func _style(bg: Color, border: Color, border_width: int, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.border_width_left = border_width
	style.border_width_right = border_width
	style.border_width_top = border_width
	style.border_width_bottom = border_width
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	return style


func _panel_style(bg: Color, border: Color, radius: int) -> StyleBoxFlat:
	return _style(bg, border, 1, radius)
