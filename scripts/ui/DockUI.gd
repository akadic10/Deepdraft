class_name DockUI
extends CanvasLayer

signal dock_action_invoked(action: String, target: String)
signal tool_requested(tool_id: String)
## Persistence backend hooks. The dock owns presentation only; SaveManager
## connects to these signals and owns all file/state work.
signal save_game_requested()
signal load_game_requested()
signal load_autosave_requested()
signal new_game_requested()

const DOCK_BOTTOM_MARGIN := 24.0
const PANEL_TOP_MARGIN := 76.0
const PANEL_DOCK_GAP := 8.0
const DOCK_ICON_SIZE := 72.0
const DOCK_ICON_COMPACT_SIZE := 56.0
const DOCK_ICON_GAP := 4
const DOCK_GROUP_GAP := 12.0

## Window chrome and placement live in UIWindowManager (doc 24) — the dock
## only toggles windows by id and reflects their open state on its buttons.
@export var window_manager_path: NodePath

var _root: Control
var _dock_panel: PanelContainer
var _dock_row: HBoxContainer
var _button_by_target: Dictionary = {}
var _active_panel_target: String = ""
var _panel_container: PanelContainer
var _panel_title: Label
var _panel_body: GridContainer
var _panel_scroll: ScrollContainer
var _panel_back: Button
var _panel_margin: MarginContainer
var _panel_header: Control
var _panel_rail_back: Button
var _panel_connector: Line2D
var _time_slice_hud: Control
var _sky_dial: Control
var _sky_hud_root: Control
var _food_warning: Control
var _slice_button: Button
var _speed_buttons: Dictionary = {}
var _ui_registry: Node
var _world_clock: Node
var _weather_mgr: Node
var _window_manager: UIWindowManager = null
var _world_info_overlay: CanvasLayer
var _block_inspector_overlay: CanvasLayer
var _slice_controller: Node = null
var _xray_controller: Node = null
var _flag_controller: Node = null
var _stockpile_controller: Node = null
var _furniture_controller: Node = null
var _place_catalog: FurniturePlacePanel
var _place_window: UIWindow
var _inventory_panel: Control
var _inventory_window: UIWindow
var _craft_panel: Control
var _craft_window: UIWindow
var _mining_controller: Node = null
var _construction_controller: Node = null
var _room_controller: Node = null
var _chop_controller: Node = null
var _orders: Control
var _toast_layer: CanvasLayer = null
var _persistence_toast: PanelContainer = null
var _persistence_toast_label: Label = null
var _persistence_toast_until_msec: int = 0

## Legacy build-label bindings for older callers/art fixtures. The live Place
## catalog uses namespaced keys and UIRegistry.get_place_catalog() (doc 54).
const FURNITURE_PANEL_ITEMS: Dictionary = {
	"📥 Log Bench": "base:furniture:bench",
	"📥 Hearth": "base:furniture:hearth",
	"📥 Log Door (2 wide)": "base:furniture:door",
}

## Dock targets whose window content the dock itself owns (doc 24 Phase U2a).
## Other manager windows (e.g. "dwarves") are registered by their own systems.
const DOCK_WINDOW_EMOJI: Dictionary = {
	"labor": "👷",
	"stockpiles": "🗃️",
	"trade": "💰",
}

var _clock_refresh_accum: float = 0.0

func _ready() -> void:
	add_to_group("command_dock")
	layer = 20
	_ui_registry = get_node_or_null("/root/UIRegistry")
	if _ui_registry == null:
		push_error("DockUI: UIRegistry autoload is missing.")
		return
	_world_clock = get_node_or_null("/root/WorldClock")
	_weather_mgr = get_node_or_null("/root/WeatherManager")
	_window_manager = get_node_or_null(window_manager_path) as UIWindowManager
	if _window_manager == null:
		push_error("DockUI: UIWindowManager not found at '%s' — windows disabled." % window_manager_path)
	else:
		_window_manager.window_state_changed.connect(_on_window_state_changed)
	_build_root()
	_build_dock()
	_build_action_panel()
	_build_sky_dial()
	_build_time_slice_hud()
	_orders = preload("res://scripts/ui/OrdersShelf.gd").new()
	_orders.name = "Orders"
	_orders.dock_buttons = _button_by_target
	_root.add_child(_orders)
	_orders.tool_requested.connect(_request_order_tool)
	_orders.shelf_visibility_changed.connect(_refresh_active_buttons)
	if _mining_controller != null: _orders.bind_controller("mine_precision", _mining_controller)
	_orders.fit_above_dock(_dock_panel.get_global_rect())
	_build_persistence_toast()
	_food_warning = preload("ColonyFoodWarning.gd").new()
	_sky_hud_root.add_child(_food_warning)
	_position_sky_dial()
	InteriorTracker.caves_discovered.connect(_on_caves_discovered)
	tool_requested.connect(func(id: String):
		if _craft_window != null: _window_manager.close("craft")
		if _inventory_window != null: _window_manager.close("inventory")
		if id != "furniture" and _place_window != null:
			_window_manager.close("place"))
	if _window_manager != null:
		_register_dock_windows()
	_set_world_info_overlay(_find_canvas_layer(get_tree().current_scene, "DebugLoadingOverlay"))
	_set_block_inspector_overlay(_find_canvas_layer(get_tree().current_scene, "BlockInspector"))
	_refresh_active_buttons()
	SaveManager.register_dock(self)


func _process(delta: float) -> void:
	if _persistence_toast != null and _persistence_toast.visible \
			and Time.get_ticks_msec() >= _persistence_toast_until_msec:
		_persistence_toast.visible = false
	_clock_refresh_accum += delta
	if _clock_refresh_accum < 0.1:
		return
	_clock_refresh_accum = 0.0
	_update_navigation_status()


## Persistence toast lives on its own always-on-top HUD layer (doc 24 layer
## plan: dock 20, windows 22, mouse-ignoring HUD 24) so a dragged window can
## never cover a save/load result.
func _build_persistence_toast() -> void:
	_toast_layer = CanvasLayer.new()
	_toast_layer.name = "ToastLayer"
	_toast_layer.layer = 24
	add_child(_toast_layer)

	var toast_root := Control.new()
	UITheme.apply_surface(toast_root)
	toast_root.name = "ToastRoot"
	toast_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	toast_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_layer.add_child(toast_root)

	_persistence_toast = PanelContainer.new()
	_persistence_toast.name = "PersistenceToast"
	_persistence_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_persistence_toast.position = Vector2(-180.0, 28.0)
	_persistence_toast.custom_minimum_size = Vector2(360.0, 44.0)
	_persistence_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_persistence_toast.visible = false
	toast_root.add_child(_persistence_toast)
	_persistence_toast_label = Label.new()
	_persistence_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_persistence_toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_persistence_toast_label.add_theme_font_size_override("font_size", 15)
	_persistence_toast.add_child(_persistence_toast_label)


func show_persistence_status(message: String, is_error: bool = false) -> void:
	if _persistence_toast == null:
		return
	_persistence_toast.add_theme_stylebox_override(
		"panel", UITheme.toast_style(is_error))
	_persistence_toast_label.text = message
	_persistence_toast.visible = true
	_persistence_toast_until_msec = Time.get_ticks_msec() + (4500 if is_error else 2500)


func _on_caves_discovered(_cells: Array[Vector3i]) -> void:
	if SaveManager._loading: return
	show_persistence_status("Cavern discovered. Bring light to explore it.")


func _build_root() -> void:
	_root = Control.new()
	UITheme.apply_surface(_root)
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)


func _build_dock() -> void:
	_dock_panel = PanelContainer.new()
	_dock_panel.name = "FloatingDock"
	_dock_panel.mouse_force_pass_scroll_events = false
	_dock_panel.add_theme_stylebox_override("panel", UITheme.dock_panel_style())
	_root.add_child(_dock_panel)
	_dock_row = HBoxContainer.new()
	_dock_row.add_theme_constant_override("separation", DOCK_ICON_GAP)
	_dock_panel.add_child(_dock_row)
	for entry: Dictionary in _ui_registry.call("get_dock_items"):
		if bool(entry.get("separator_before", false)):
			var gap := Control.new()
			gap.name = "%sGap" % _node_suffix(String(entry.id))
			gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
			gap.custom_minimum_size.x = DOCK_GROUP_GAP
			_dock_row.add_child(gap)
		_dock_row.add_child(_make_dock_button(entry))
	get_viewport().size_changed.connect(_fit_dock)
	_dock_panel.resized.connect(_position_dock)
	_fit_dock()


func _fit_dock() -> void:
	if _dock_row == null or _button_by_target.is_empty():
		return
	var viewport_width := get_viewport().get_visible_rect().size.x
	var gaps := _dock_row.get_child_count() - _button_by_target.size()
	var chrome := 16 + (_dock_row.get_child_count() - 1) * DOCK_ICON_GAP + gaps * DOCK_GROUP_GAP
	var preferred := DOCK_ICON_SIZE if viewport_width >= 1200 else DOCK_ICON_COMPACT_SIZE
	var width := floorf(minf(preferred, (viewport_width - 32 - chrome) / _button_by_target.size()))
	for button: Button in _button_by_target.values():
		button.custom_minimum_size = Vector2(width, width)
	_dock_panel.reset_size()
	_position_dock()
	if _panel_container != null:
		call_deferred("_layout_action_panel")


func _position_dock() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	_dock_panel.position = Vector2((viewport_size.x - _dock_panel.size.x) * 0.5,
		viewport_size.y - DOCK_BOTTOM_MARGIN - _dock_panel.size.y)
	if _time_slice_hud != null:
		var utility_width: float = _time_slice_hud.preferred_row_width()
		if _dock_panel.size.x + utility_width + 48 <= viewport_size.x:
			_dock_panel.position.x = minf(_dock_panel.position.x, viewport_size.x - 28 - utility_width - _dock_panel.size.x)
	if _place_catalog != null: _place_catalog.fit_above_dock(_dock_panel.position.y)
	if _inventory_panel != null: _inventory_panel.fit_above_dock(_dock_panel.position.y)
	if _craft_panel != null: _craft_panel.fit_above_dock(_dock_panel.position.y)
	if _orders != null: _orders.fit_above_dock(_dock_panel.get_global_rect())
	_position_time_slice_hud()


func _make_dock_button(entry: Dictionary) -> Button:
	var button := preload("res://scripts/ui/DockIconButton.gd").new()
	button.name = "%sButton" % _node_suffix(String(entry.id))
	button.custom_minimum_size = Vector2.ONE * DOCK_ICON_SIZE
	button.setup(entry, _ui_registry.get_dock_icon(entry))
	button.pressed.connect(_dispatch.bind(String(entry.action), String(entry.target)))
	_button_by_target[String(entry.target)] = button
	return button

func _build_action_panel() -> void:
	_panel_container = PanelContainer.new()
	_panel_container.name = "ActionPanel"
	_panel_container.mouse_force_pass_scroll_events = false
	_panel_container.visible = false
	_panel_container.add_theme_stylebox_override("panel", UITheme.hud_panel_style())
	# Colony menus must remain clickable while the wide roster is open.
	# Keep the dock at 20, windows at 22, and only its popup menu above them.
	var menu_layer := CanvasLayer.new()
	menu_layer.name = "DockMenus"
	menu_layer.layer = 23
	add_child(menu_layer)
	_panel_connector = Line2D.new()
	_panel_connector.width = 2
	_panel_connector.default_color = UITheme.HEARTH_COPPER
	_panel_connector.hide()
	menu_layer.add_child(_panel_connector)
	menu_layer.add_child(_panel_container)
	UITheme.apply_surface(_panel_container)
	var margin := MarginContainer.new()
	_panel_margin = margin
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	_panel_container.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	var header := HBoxContainer.new()
	_panel_header = header
	column.add_child(header)
	_panel_back = UITheme.make_button("‹", "Back", Vector2(28, 28))
	_panel_back.pressed.connect(func():
		_open_action_panel(String(UIRegistry.get_menu(_active_panel_target).get("parent", ""))))
	header.add_child(_panel_back)
	_panel_title = Label.new()
	_panel_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.apply_title(_panel_title)
	header.add_child(_panel_title)
	var close := Button.new()
	UITheme.apply_close_button(close)
	close.pressed.connect(_close_action_panel)
	header.add_child(close)
	_panel_scroll = ScrollContainer.new()
	_panel_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(_panel_scroll)
	var rail := HBoxContainer.new()
	rail.add_theme_constant_override("separation", 6)
	_panel_scroll.add_child(rail)
	_panel_rail_back = UITheme.make_button("‹", "Back", Vector2(28, 56))
	_panel_rail_back.name = "IllustratedMenuBack"
	_panel_rail_back.add_theme_font_size_override("font_size", 28)
	_panel_rail_back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_panel_rail_back.hide()
	_panel_rail_back.pressed.connect(func():
		_open_action_panel(String(UIRegistry.get_menu(_active_panel_target).get("parent", ""))))
	rail.add_child(_panel_rail_back)
	_panel_body = GridContainer.new()
	_panel_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panel_body.add_theme_constant_override("h_separation", 8)
	_panel_body.add_theme_constant_override("v_separation", 8)
	rail.add_child(_panel_body)
	rail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panel_container.resized.connect(_position_action_panel)
	_panel_container.visibility_changed.connect(_position_action_panel)


func _layout_action_panel() -> void:
	# A scene reload can detach this dock before queued layout callbacks run.
	if not is_inside_tree():
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var menu := UIRegistry.get_menu(_active_panel_target)
	if bool(menu.get("illustrated", false)):
		var icon_size := 64.0 if viewport_size.x >= 1200 else 56.0
		for button: Control in _panel_body.get_children():
			button.custom_minimum_size = Vector2.ONE * icon_size
		_panel_rail_back.custom_minimum_size = Vector2(28, icon_size)
		var preferred := int(menu.get("columns" if viewport_size.x >= 1200 else "compact_columns", 1))
		var available_columns := maxi(1, int((viewport_size.x - 80) / (icon_size + 6)))
		_panel_body.columns = mini(preferred, available_columns)
		# A moved inspector can occupy the center of the menu's usual strip.
		# Wrap before shrinking icons so every command remains reachable beside it.
		var inspector := _window_manager.get_ui_window("object_explorer") if _window_manager != null else null
		if inspector != null and inspector.visible:
			var obstacle := inspector.get_global_rect().grow(PANEL_DOCK_GAP)
			var proposed_rows := ceili(float(_panel_body.get_child_count()) / _panel_body.columns)
			var top := _dock_panel.position.y - PANEL_DOCK_GAP - proposed_rows * (icon_size + 8) - 16
			if obstacle.end.y > top and obstacle.position.y < _dock_panel.position.y:
				var side_width := maxf(obstacle.position.x - 24, viewport_size.x - obstacle.end.x - 24)
				var side_columns := maxi(1, int((side_width - 16 - (34 if _panel_rail_back.visible else 0)) / (icon_size + 6)))
				_panel_body.columns = mini(_panel_body.columns, side_columns)
				if _active_panel_target == "craft":
					_panel_body.columns = ceili(float(_panel_body.get_child_count()) / ceili(float(_panel_body.get_child_count()) / _panel_body.columns))
		var content_width := _panel_body.columns * icon_size + (_panel_body.columns - 1) * 6
		if _panel_rail_back.visible: content_width += 34
		var rows := ceili(float(_panel_body.get_child_count()) / _panel_body.columns)
		_panel_scroll.custom_minimum_size = Vector2(content_width, rows * icon_size + maxi(0, rows - 1) * 8)
		_panel_container.custom_minimum_size = Vector2.ZERO
		_panel_container.reset_size()
		call_deferred("_position_action_panel")
		return
	# Leave the default inspector column clear on a normal desktop viewport.
	var available := viewport_size.x - 48 - (400 if viewport_size.x >= 900 else 0)
	var width := minf(820 if _active_panel_target == "build" else 460, available)
	_panel_body.columns = (4 if width >= 780 else (3 if width >= 600 else 2)) if _active_panel_target == "build" else 2
	if _active_panel_target == "craft":
		# A row of professions on desktop, balanced rows on compact screens.
		var count := maxi(1,_panel_body.get_child_count())
		var columns := count if viewport_size.x >= count*112+40 else mini(5,count)
		_panel_body.columns = mini(columns,maxi(1,int((viewport_size.x-48)/112)))
		width = _panel_body.columns*112+32
	# Measure the real header, padding and borders; font metrics can change the
	# dock's height, so a fixed bottom allowance can overlap it at small sizes.
	var chrome_height := _panel_container.get_combined_minimum_size().y - _panel_scroll.get_combined_minimum_size().y
	var body_height := minf(_panel_body.get_combined_minimum_size().y,
		maxf(0, _dock_panel.position.y - PANEL_DOCK_GAP - PANEL_TOP_MARGIN - chrome_height))
	_panel_scroll.custom_minimum_size = Vector2(width - 40, body_height)
	_panel_container.custom_minimum_size.x = width
	_panel_container.reset_size()
	call_deferred("_position_action_panel")


func _position_action_panel() -> void:
	if not is_inside_tree():
		return
	var viewport_width := get_viewport().get_visible_rect().size.x
	var centered_x := (viewport_width - _panel_container.size.x) * 0.5
	var menu: Dictionary = UIRegistry.get_menu(_active_panel_target)
	var illustrated := bool(menu.get("illustrated", false))
	var anchor: Control = _button_by_target.get(String(menu.get("dock_anchor", "")))
	if illustrated and is_instance_valid(anchor):
		centered_x = clampf(anchor.get_global_rect().position.x - 8, 24, viewport_width - _panel_container.size.x - 24)
	var panel_position := Vector2(centered_x, maxf(PANEL_TOP_MARGIN,
		_dock_panel.position.y - PANEL_DOCK_GAP - _panel_container.size.y))
	# Keep the menu visually attached to the dock. At compact widths, move only
	# far enough to clear the inspector, whose higher CanvasLayer would cover it.
	var inspector := _window_manager.get_ui_window("object_explorer") if _window_manager != null else null
	if inspector != null:
		if not inspector.item_rect_changed.is_connected(_layout_action_panel):
			inspector.item_rect_changed.connect(_layout_action_panel)
		var inspector_rect := inspector.get_global_rect().grow(PANEL_DOCK_GAP)
		if inspector.visible and Rect2(panel_position, _panel_container.size).intersects(inspector_rect):
			var closest_distance := INF
			for candidate_x: float in [inspector_rect.position.x - _panel_container.size.x, inspector_rect.end.x]:
				if candidate_x < 24 or candidate_x + _panel_container.size.x > viewport_width - 24:
					continue
				var distance := absf(candidate_x - centered_x)
				if distance < closest_distance:
					panel_position.x = candidate_x
					closest_distance = distance
	_panel_container.position = panel_position
	# The fixed utility controls remain usable while a command menu is open.
	if _time_slice_hud != null:
		for reserved: Rect2 in _time_slice_hud.occupied_rects():
			reserved = reserved.grow(PANEL_DOCK_GAP)
			if not _panel_container.get_global_rect().intersects(reserved): continue
			var candidate := Vector2(reserved.position.x - _panel_container.size.x, panel_position.y)
			if candidate.x >= 24 and (inspector == null or not inspector.visible or not Rect2(candidate, _panel_container.size).intersects(inspector.get_global_rect().grow(PANEL_DOCK_GAP))):
				panel_position = candidate
			else:
				panel_position.y = maxf(PANEL_TOP_MARGIN, reserved.position.y - _panel_container.size.y)
			_panel_container.position = panel_position
	_panel_connector.visible = illustrated and _panel_container.visible and is_instance_valid(anchor)
	if _panel_connector.visible:
		var x := anchor.get_global_rect().get_center().x
		var bounds := _panel_container.get_global_rect()
		_panel_connector.visible = x >= bounds.position.x + 8 and x <= bounds.end.x - 8
		_panel_connector.points = PackedVector2Array([Vector2(x, bounds.end.y), Vector2(x, _dock_panel.position.y)])


func is_action_menu_open() -> bool:
	return _panel_container != null and _panel_container.visible


func _close_action_panel() -> void:
	_panel_container.hide()
	_panel_connector.hide()
	_active_panel_target = ""
	_refresh_active_buttons()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE \
			and _craft_window != null and _craft_window.visible:
		_window_manager.close("craft")
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE \
			and _inventory_window != null and _inventory_window.visible:
		_window_manager.close("inventory")
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and _orders != null:
		if not _orders.active_tool_id().is_empty():
			_request_order_tool("")
			get_viewport().set_input_as_handled()
			return
		if _orders.is_open():
			_orders.set_open(false)
			get_viewport().set_input_as_handled()
			return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE \
			and _place_window != null and _place_window.visible:
		# First Escape finishes the active tool; second closes the catalog.
		if _furniture_controller != null and _furniture_controller.is_active(): return
		_window_manager.close("place")
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and _panel_container.visible:
		_close_action_panel()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE \
			and _window_manager != null and _window_manager.is_open("dwarves") \
			and not _window_manager.is_open("object_explorer"):
		_window_manager.close("dwarves")
		get_viewport().set_input_as_handled()


func _build_time_slice_hud() -> void:
	_time_slice_hud = preload("res://scripts/ui/TimeSliceHUD.gd").new()
	_time_slice_hud.name = "TimeSliceHUD"
	var hud_layer := CanvasLayer.new()
	hud_layer.name = "TimeSliceLayer"
	hud_layer.layer = 24
	add_child(hud_layer)
	hud_layer.add_child(_time_slice_hud)
	_time_slice_hud.speed_requested.connect(_set_clock_speed)
	_time_slice_hud.slice_toggle_requested.connect(_toggle_slice_tool)
	_speed_buttons = _time_slice_hud.speed_buttons
	_slice_button = _time_slice_hud.slice_button
	if _slice_controller != null: _time_slice_hud.bind_slice(_slice_controller)
	if _xray_controller != null: _time_slice_hud.bind_xray(_xray_controller)
	get_viewport().size_changed.connect(_position_time_slice_hud)
	_position_dock()
	_update_navigation_status()


func _position_time_slice_hud() -> void:
	if _time_slice_hud == null: return
	_time_slice_hud.fit_to_viewport(_dock_panel.get_global_rect())
	if _panel_container != null: call_deferred("_position_action_panel")
	if _window_manager != null: _window_manager.call_deferred("fit_visible_windows")


func _build_sky_dial() -> void:
	# Dedicated status layer. Large windows keep normal priority on compact
	# screens; ordinary inspectors make room through the shared window clamp.
	var hud := CanvasLayer.new()
	hud.name = "SkyHUD"
	hud.layer = 21
	add_child(hud)
	_sky_hud_root = Control.new()
	_sky_hud_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_sky_hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(_sky_hud_root)
	_sky_dial = preload("res://scripts/ui/SkyDial.gd").new()
	_sky_hud_root.add_child(_sky_dial)
	get_viewport().size_changed.connect(_position_sky_dial)
	_position_sky_dial()


func _position_sky_dial() -> void:
	var viewport := get_viewport().get_visible_rect().size
	var side := 224.0 if viewport.x >= 1600 else (204.0 if viewport.x >= 1200 else 184.0)
	_sky_dial.size = Vector2.ONE * side
	_sky_dial.position = Vector2(viewport.x - side - 16, 12)
	if _window_manager != null: _window_manager.call_deferred("fit_visible_windows")
	if _food_warning != null:
		_food_warning.offset_top = _sky_dial.position.y + side + 8
		_food_warning.offset_bottom = _food_warning.offset_top


func _set_clock_speed(speed: int) -> void:
	if _world_clock == null:
		return
	if speed == 0:
		var resume := bool(_world_clock.paused) or float(_world_clock.speed) <= 0
		_world_clock.set_paused(not resume)
		if resume and float(_world_clock.speed) <= 0: _world_clock.set_speed(1)
	else:
		_world_clock.set_speed(speed)
		_world_clock.set_paused(false)
	_update_navigation_status()


func _update_navigation_status() -> void:
	if _world_clock == null:
		return
	var paused := bool(_world_clock.paused) or float(_world_clock.speed) <= 0
	for speed: int in _speed_buttons:
		var button: Button = _speed_buttons[speed]
		button.button_pressed = paused if speed == 0 else (not paused and is_equal_approx(float(speed), float(_world_clock.speed)))
	_slice_button.button_pressed = _target_canvas_visible("slice")

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
		"open_crafting":
			open_crafting("",target)
		_:
			push_warning("DockUI: unknown dock action '%s' for target '%s'." % [action, target])
	dock_action_invoked.emit(action, target)
	_refresh_active_buttons()


func _open_action_panel(target: String) -> void:
	if _craft_window != null: _window_manager.close("craft")
	if _target_canvas_visible("rooms"):
		tool_requested.emit("")
	if target == "stocks":
		_open_inventory()
		return
	if _inventory_window != null: _window_manager.close("inventory")
	if target in ["orders", "zones"]:
		if _place_window != null: _window_manager.close("place")
		_close_action_panel()
		var show_shelf: bool = not _orders.is_open(target)
		var active: String = _orders.active_tool_id()
		if show_shelf and not active.is_empty() and _orders.group_for_tool(active) != target:
			_request_order_tool("")
		_orders.set_open(show_shelf, target)
		return
	if _orders != null and not _orders.active_tool_id().is_empty(): _request_order_tool("")
	if _orders != null: _orders.set_open(false)
	if target in ["place", "build"]:
		_open_place_catalog()
		return
	if _place_window != null: _window_manager.close("place")
	if _active_panel_target == target and _panel_container.visible:
		_close_action_panel()
		return
	_active_panel_target = target
	_panel_title.text = _target_title(target)
	var menu: Dictionary = UIRegistry.get_menu(target)
	var illustrated := bool(menu.get("illustrated", false))
	_panel_header.visible = not illustrated
	_panel_rail_back.visible = illustrated and not String(menu.get("parent", "")).is_empty()
	_panel_rail_back.tooltip_text = "Back to " + _target_title(String(menu.get("parent", "")))
	_panel_container.add_theme_stylebox_override("panel", UITheme.dock_panel_style() if illustrated else UITheme.hud_panel_style())
	for side: String in ["left", "right", "top", "bottom"]:
		_panel_margin.add_theme_constant_override("margin_" + side, 0 if illustrated else 12)
	_panel_body.add_theme_constant_override("h_separation", 6 if illustrated else 8)
	_panel_body.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN if illustrated else Control.SIZE_EXPAND_FILL
	_panel_back.visible = not String(menu.get("parent", "")).is_empty()
	_clear_children(_panel_body)
	_panel_scroll.scroll_vertical = 0
	for entry: Dictionary in menu.get("items", []):
		if illustrated:
			var icon_button := preload("res://scripts/ui/DockIconButton.gd").new()
			var presentation := entry.duplicate()
			if String(entry.action) == "open_crafting":
				var section: Dictionary = _craft_panel.controller.sections.get(String(entry.target), {}) if _craft_panel != null else {}
				presentation.planned = bool(section.get("planned", false))
				presentation.status_label = "Catalog preview" if presentation.planned else ""
				icon_button.disabled = _craft_panel == null or section.is_empty()
			icon_button.setup(presentation, UIRegistry.get_dock_icon(entry))
			icon_button.name = String(entry.id).to_pascal_case()
			if String(entry.action) == "open_crafting":
				icon_button.name = "Crafter" + String(entry.target).to_pascal_case()
			icon_button.custom_minimum_size = Vector2(64, 64)
			icon_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			icon_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			icon_button.pressed.connect(_dispatch_menu_entry.bind(entry))
			_panel_body.add_child(icon_button)
			continue
		var button := UITheme.make_button(String(entry.label),
			String(entry.get("tooltip", entry.label)), Vector2(128,46),
			"dev" if String(entry.label).begins_with("DEV") else "")
		button.add_theme_font_size_override("font_size", 14)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.disabled = bool(entry.get("disabled", false))
		if String(entry.action)=="open_crafting":
			_style_crafter_button(button,entry)
		button.pressed.connect(_dispatch_menu_entry.bind(entry))
		_panel_body.add_child(button)
	if _panel_body.get_child_count() == 0:
		for label in _panel_actions(target):
			_panel_body.add_child(_make_panel_action_button(label, target))
	_panel_container.visible = true
	call_deferred("_layout_action_panel")
	_refresh_active_buttons()


func _style_crafter_button(button: Button, entry: Dictionary) -> void:
	button.name = "Crafter"+String(entry.target).to_pascal_case()
	button.custom_minimum_size = Vector2(104,82)
	button.add_theme_font_size_override("font_size",12)
	button.icon = load(String(entry.icon)) as Texture2D
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width",28)
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	button.toggle_mode = true
	var section: Dictionary = _craft_panel.controller.sections.get(String(entry.target),{}) if _craft_panel != null else {}
	var planned := bool(section.get("planned",false))
	button.text += "\n"+("Preview" if section.has("status_label") else "Planned") if planned else "\nWorker crafts"
	button.add_theme_color_override("icon_normal_color",UITheme.HEARTH_MUTED if planned else UITheme.HEARTH_COPPER)
	button.add_theme_color_override("icon_hover_color",UITheme.HEARTH_COPPER)
	button.set_pressed_no_signal(_craft_panel != null and _craft_panel.section_id==String(entry.target))
	# Planned professions remain clickable so their own preview menu is browsable.
	button.disabled = _craft_panel == null or section.is_empty()


func _dispatch_menu_entry(entry: Dictionary) -> void:
	var action := String(entry.action)
	var target := String(entry.target)
	if action == "open_panel":
		_dispatch(action, target)
	elif action == "panel_action":
		if not _dispatch_command(String(entry.id)):
			_dispatch_panel_action(target, String(entry.label))
	else:
		_close_action_panel()
		if action == "activate_tool":
			tool_requested.emit(target)
			dock_action_invoked.emit(action, target)
		else:
			_dispatch(action, target)


## Live save/test commands use stable IDs, independent of captions and artwork.
func _dispatch_command(id: String) -> bool:
	# Finish local UI work before a listener can synchronously reload the scene.
	match id:
		"new_game":
			_close_action_panel()
			new_game_requested.emit()
		"save_game":
			_close_action_panel()
			save_game_requested.emit()
		"load_game":
			_close_action_panel()
			load_game_requested.emit()
		"load_autosave":
			_close_action_panel()
			load_autosave_requested.emit()
		"spawn_drops", "spawn_furniture", "spawn_bushes":
			if _stockpile_controller != null:
				_stockpile_controller.call("dev_" + id)
		"arrival_status_development":
			var events := get_tree().get_first_node_in_group("world_events")
			if events != null:
				show_persistence_status(events.dev_status())
				_persistence_toast_until_msec = Time.get_ticks_msec() + 6000
		"hearthblock_lighting_development":
			# A/B review of the lighting pass; the choice lasts until the game closes.
			SkyController.set_hearthblock_lighting(not SkyController.is_hearthblock_enabled())
			show_persistence_status("Hearthblock lighting " + ("on" if SkyController.is_hearthblock_enabled() else "off"))
			_persistence_toast_until_msec = Time.get_ticks_msec() + 4000
		_:
			return false
	return true

func _make_panel_action_button(label: String, target: String) -> Button:
	var button := Button.new()
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size = Vector2(128.0, 46.0)
	button.focus_mode = Control.FOCUS_NONE
	button.text = label
	button.tooltip_text = label
	if label.begins_with("DEV"):
		UITheme.apply_button_variant(button, "dev")
	if target in ["farm", "military"] or (target == "chop" and label in ["Forestry Zone", "Clear Stumps"]):
		button.disabled = true
		button.tooltip_text = "Coming later"
	button.add_theme_font_size_override("font_size", 14)
	button.pressed.connect(func() -> void:
		_dispatch_panel_action(target, label)
	)
	return button


func _dispatch_panel_action(target: String, label: String) -> void:
	if target == "world_events" and label == "DEV: Arrival status":
		var events := get_tree().get_first_node_in_group("world_events")
		if events != null:
			show_persistence_status(events.dev_status())
			_persistence_toast_until_msec = Time.get_ticks_msec()+6000
		return
	if target == "chop":
		if label == "Chop Trees":
			_panel_container.visible = false
			_active_panel_target = ""
			tool_requested.emit("chop")
			_refresh_active_buttons()
		elif label == "Cancel":
			if _chop_controller != null:
				_chop_controller.call("deactivate")
			_panel_container.visible = false
			_active_panel_target = ""
			_refresh_active_buttons()
		return
	if target == "save_load":
		match label:
			"💾 Save Game":
				_dispatch_command("save_game")
			"📂 Load Game":
				_dispatch_command("load_game")
			"🕒 Load Autosave":
				_dispatch_command("load_autosave")
		return
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
	if target == "build" and FURNITURE_PANEL_ITEMS.has(label):
		_panel_container.visible = false
		_active_panel_target = ""
		# Announce first so every other click-tool deactivates (2026-07-06
		# contract), then arm the furniture tool with the chosen def.
		tool_requested.emit("furniture")
		if _furniture_controller != null and _furniture_controller.has_method("activate_for"):
			_furniture_controller.call("activate_for", String(FURNITURE_PANEL_ITEMS[label]))
		else:
			push_warning("DockUI: no FurniturePlacementController registered.")
		_refresh_active_buttons()
		return
	if target == "storage_zone" and label == "DEV: Spawn Drops":
		if _stockpile_controller != null and _stockpile_controller.has_method("dev_spawn_drops"):
			_stockpile_controller.call("dev_spawn_drops")
		return
	if target == "storage_zone" and label == "DEV: Spawn Bushes":
		_dispatch_command("spawn_bushes")
		return
	if target == "storage_zone" and label == "DEV: Spawn Furniture":
		if _stockpile_controller != null and _stockpile_controller.has_method("dev_spawn_furniture"):
			_stockpile_controller.call("dev_spawn_furniture")
		else:
			push_warning("DockUI: no StockpileDesignationController registered.")
		return
	if label == "Cancel":
		_panel_container.visible = false
		_active_panel_target = ""
		_refresh_active_buttons()


## Window toggles route through UIWindowManager (doc 24). The remaining
## branches are click-TOOLS and overlays, not windows: slice/rooms/flag follow
## the announce-first contract; world_info and block_inspector stay
## overlay-toggles until their doc 24 Phase U2 migrations land.
func _toggle_window(target: String) -> void:
	if target == "labor":
		tool_requested.emit("")
		if _orders != null: _orders.set_open(false)
		var director := get_tree().get_first_node_in_group("dwarf_director")
		if director != null: director.open_work_view()
		return
	if target in ["dwarves", "caves_dev", "water_dev"] and _window_manager != null and not _window_manager.is_open(target):
		tool_requested.emit("")
		if _orders != null: _orders.set_open(false)
	if target in ["stockpiles", "inventory"]:
		_open_inventory()
		return
	if target == "world_info":
		_toggle_world_info_overlay()
		return
	if target == "block_inspector":
		_toggle_block_inspector_overlay()
		return
	if target == "slice":
		_toggle_slice_tool()
		return
	if target == "rooms":
		_close_action_panel()
		if _orders != null: _orders.set_open(false)
		# Announce-first (2026-07-06 contract). RoomOverlayController
		# self-toggles on its own id; every other click-tool deactivates on
		# the announce — the emit alone is the whole toggle.
		tool_requested.emit("rooms")
		return
	if target == "flag":
		if _flag_controller != null and _flag_controller.is_founded():
			_open_settlement_flag()
			return
		# Announce so other click-tools (mining, storage zone) deactivate —
		# two active tools eating the same click caused the 2026-07-06 crash.
		tool_requested.emit("flag")
		if _flag_controller != null and _flag_controller.has_method("toggle_active"):
			_flag_controller.call("toggle_active")
		return

	if _window_manager == null:
		push_warning("DockUI: no UIWindowManager — cannot toggle window '%s'." % target)
		return
	if not _window_manager.has_window(target):
		push_warning("DockUI: no window registered for dock target '%s'." % target)
		return
	_window_manager.toggle(target)


func _open_settlement_flag() -> void:
	tool_requested.emit("")
	if _orders != null: _orders.set_open(false)
	if _furniture_controller == null: return
	var key := FlagPlacementController.FURNITURE_KEY
	var location: Dictionary = _furniture_controller.get_catalog_location(key)
	if location.has("position"):
		var rig: Node = get_viewport().get_camera_3d()
		while rig != null and not rig.has_method("locate_position"): rig = rig.get_parent()
		if rig != null: rig.locate_position(location.position)
	if location.has("object_id"):
		var explorer := get_tree().get_first_node_in_group("object_explorer")
		if explorer != null and explorer.select_object(_furniture_controller, location.object_id):
			if location.state == "moving": show_persistence_status("The settlement flag is being moved. Its current order is shown.")
			elif location.state == "packing": show_persistence_status("The settlement flag is marked for packing into storage.")
			elif location.state == "placing": show_persistence_status("The settlement flag is awaiting installation. Its current order is shown.")
			return
		show_persistence_status("The settlement flag is at this location. Change the slice level to inspect it.")
		return
	if location.state == "packed" and _place_catalog != null:
		_window_manager.open("place")
		_place_catalog.category = "rooms"
		_place_catalog.selected_key = key
		_place_catalog.begin_browsing()
		_place_catalog.fit_above_dock(_dock_panel.position.y)
		show_persistence_status("The settlement flag is packed. Select it in Place to choose a new position.")
	else:
		show_persistence_status("A dwarf is carrying the settlement flag. It will be available in Place after delivery." if location.state == "carried" else "The settlement is founded, but no flag is currently available to place.")


# ── Dock-owned windows (doc 24 Phase U2a) ─────────────────────────────────────

func _register_dock_windows() -> void:
	var audio_panel := preload("res://scripts/ui/AudioSettingsPanel.gd").new()
	var audio_window := _window_manager.register_window("audio", "Audio", "", audio_panel,
		{"persistent": false, "default_pos": Vector2(32, 130)})
	audio_window.keep_body_on_screen = true
	_window_manager.register_window("time_weather_dev", "Time & weather tools", "",
		_build_time_weather_tools(), {"persistent": true, "default_pos": Vector2(32, 130)})

	_inventory_panel = preload("res://scripts/ui/ColonyInventoryPanel.gd").new()
	_inventory_window = _window_manager.register_window("inventory", "Colony Inventory", "", _inventory_panel,
		{"persistent": false, "default_pos": Vector2(24, 76)})
	_inventory_window.keep_body_on_screen = true
	UITheme.apply_catalog_window(_inventory_window)
	_inventory_panel.window = _inventory_window
	_inventory_panel.locate_requested.connect(_locate_inventory_item)
	_inventory_panel.fit_above_dock(_dock_panel.position.y)
	var placeholder_targets: Array[String] = ["trade"]
	for target: String in placeholder_targets:
		_window_manager.register_window(target, _target_title(target),
			String(DOCK_WINDOW_EMOJI[target]), _build_placeholder_content(target),
			{"persistent": true, "min_size": Vector2(300.0, 0.0)})


func _build_time_weather_tools() -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	var note := Label.new()
	note.text = "Advance the simulation to test time and weather."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(note)
	# Development only; the player's Sky Dial is a read-only HUD.
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	column.add_child(buttons)
	var plus_hour := UITheme.make_button("+1 Hour")
	plus_hour.pressed.connect(Callable(self, "_advance_clock").bind("advance_hours", 1.0))
	buttons.add_child(plus_hour)
	var plus_season := UITheme.make_button("+1 Season")
	plus_season.pressed.connect(Callable(self, "_advance_clock").bind("advance_season"))
	buttons.add_child(plus_season)

	var buttons2 := HBoxContainer.new()
	buttons2.add_theme_constant_override("separation", 8)
	column.add_child(buttons2)
	var weather := UITheme.make_button("Weather →")
	weather.pressed.connect(Callable(self, "_cycle_weather"))
	buttons2.add_child(weather)

	return column


## Placeholder bodies for systems that are not built yet (doc 24 decision:
## Labor/Stockpiles/Trade stay on the dock with placeholder content and real
## movable chrome).
func _build_placeholder_content(target: String) -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	for row_text: String in _window_rows(target):
		var row := Label.new()
		row.text = row_text
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
		column.add_child(row)
	var note := Label.new()
	note.text = "Planned · Trading and merchant visits are not available yet."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 11)
	note.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	column.add_child(note)
	return column


func _advance_clock(method: String, arg = null) -> void:
	if _world_clock == null:
		return
	if arg == null:
		_world_clock.call(method)
	else:
		_world_clock.call(method, arg)
	if _sky_dial != null: _sky_dial.refresh()


func _cycle_weather() -> void:
	if _weather_mgr != null:
		_weather_mgr.call("cycle_weather")
	if _sky_dial != null: _sky_dial.refresh()


func _refresh_active_buttons() -> void:
	var parent := String(UIRegistry.get_menu(_active_panel_target).get("parent", ""))
	for target: String in _button_by_target:
		var button: Button = _button_by_target[target]
		button.button_pressed = _panel_container != null and _panel_container.visible \
			and (target == _active_panel_target or target == parent)
	if _button_by_target.has("place"):
		_button_by_target.place.button_pressed = _place_window != null and _place_window.visible
	if _button_by_target.has("stocks"):
		_button_by_target.stocks.button_pressed = _inventory_window != null and _inventory_window.visible
	if _button_by_target.has("craft"):
		_button_by_target.craft.button_pressed = (_craft_window != null and _craft_window.visible) \
			or (_panel_container.visible and _active_panel_target=="craft")
	if _button_by_target.has("rooms"):
		_button_by_target.rooms.button_pressed = _target_canvas_visible("rooms")
	if _button_by_target.has("construction") and _target_canvas_visible("construction"):
		_button_by_target.construction.button_pressed = true
	if _orders != null:
		for group: String in ["orders", "zones"]:
			_button_by_target[group].button_pressed = _orders.is_open(group) \
				or _orders.group_for_tool(_orders.active_tool_id()) == group
	_update_navigation_status()

func _on_window_state_changed(_id: String, _open: bool) -> void:
	if _id == "inventory" and _open and _inventory_panel != null: _inventory_panel.begin_browsing()
	if _id == "place":
		if not _open and _furniture_controller != null: _furniture_controller.deactivate()
		elif _open and _place_catalog != null: _place_catalog.begin_browsing()
	_refresh_active_buttons()
	if _id == "object_explorer" and _panel_container != null:
		call_deferred("_layout_action_panel")
		if _orders != null: _orders.inspector = _window_manager.get_ui_window("object_explorer")


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
		# Chop's axe opens a menu. Its highlight follows that menu; the tool's
		# on-screen hint communicates ongoing tree selection after the menu closes.
		"chop":
			return false
		"world_info":
			return _world_info_overlay != null and _world_info_overlay.visible
		"block_inspector":
			return _block_inspector_overlay != null and _block_inspector_overlay.visible
		"slice":
			return _slice_controller != null and bool(_slice_controller.call("is_active"))
		"storage_zone":
			return _stockpile_controller != null and bool(_stockpile_controller.call("is_active"))
		"flag":
			return _flag_controller != null and _flag_controller.has_method("is_active") \
				and bool(_flag_controller.call("is_active"))
		"mine":
			return _mining_controller != null and _mining_controller.has_method("is_active") \
				and bool(_mining_controller.call("is_active"))
		"construction":
			return _construction_controller != null and _construction_controller.is_active()
		"rooms":
			return _room_controller != null and _room_controller.has_method("is_active") \
				and bool(_room_controller.call("is_active"))
	return false


# ── Slice tool integration (doc 11 Phase 2) ───────────────────────────────────
# The SliceController owns the tool state and its palette window; the dock's
# `slice` entry only toggles it. Registration happens from SliceController._ready
# via its dock_ui_path export (Scene Decoupling Contract — no node paths here).

func register_slice_controller(controller: Node) -> void:
	_slice_controller = controller
	if _time_slice_hud != null: _time_slice_hud.bind_slice(controller)
	if controller.has_signal("slice_active_changed"):
		var refresh := Callable(self, "_on_slice_active_changed")
		if not controller.is_connected("slice_active_changed", refresh):
			controller.connect("slice_active_changed", refresh)


func register_xray_controller(controller: Node) -> void:
	_xray_controller = controller
	if _time_slice_hud != null:
		_time_slice_hud.bind_xray(controller)
		_position_time_slice_hud.call_deferred()


func _toggle_slice_tool() -> void:
	if _slice_controller == null:
		push_warning("DockUI: slice button pressed but no SliceController is registered.")
		return
	_slice_controller.call("toggle_active")


## Push-registration from FlagPlacementController — the dock's 'flag' entry
## toggles the settlement-flag placement tool.
func register_flag_controller(controller: Node) -> void:
	_flag_controller = controller
	_connect_tool_active(controller)


## Push-registration from StockpileDesignationController (doc 18 Phase 1) —
## the Storage Zone panel's actions route here.
func register_stockpile_controller(controller: Node) -> void:
	_stockpile_controller = controller
	_connect_tool_active(controller)
	if _orders != null: _orders.bind_controller("storage_zone", controller)


func register_furniture_controller(controller: Node) -> void:
	_furniture_controller = controller
	if _inventory_panel != null: _inventory_panel.bind_controller(controller)
	_connect_tool_active(controller)
	if _window_manager == null or _place_catalog != null: return
	_place_catalog = FurniturePlacePanel.new()
	_place_window = _window_manager.register_window("place", "Place an item", "", _place_catalog,
		{"persistent": false, "default_pos": Vector2(24, 76)})
	_place_window.keep_body_on_screen = true
	UITheme.apply_catalog_window(_place_window)
	_place_catalog.window = _place_window
	_place_catalog.bind_controller(controller)
	_place_catalog.place_requested.connect(_start_catalog_placement)
	_place_catalog.fit_above_dock(_dock_panel.position.y)


func register_crafting_controller(controller: Node) -> void:
	if _window_manager == null or _craft_panel != null: return
	_craft_panel = preload("res://scripts/ui/WorkerCraftingPanel.gd").new()
	_craft_window = _window_manager.register_window("craft", "Rudimentary crafting", "", _craft_panel,
		{"persistent":false,"default_pos":Vector2(24,76)})
	_craft_window.keep_body_on_screen = true
	UITheme.apply_catalog_window(_craft_window)
	_craft_panel.window = _craft_window
	_craft_panel.bind_controller(controller)
	_craft_panel.crafters_requested.connect(_open_action_panel.bind("craft"))
	_craft_panel.place_requested.connect(func(key: String):
		_window_manager.close("craft")
		_window_manager.open("place")
		_place_catalog.show_all = true
		_place_catalog._all_toggle.set_pressed_no_signal(true)
		_place_catalog.category = "all"
		_place_catalog.selected_key = key
		_start_catalog_placement(key))
	_craft_panel.fit_above_dock(_dock_panel.position.y)
	if _place_catalog != null: controller.changed.connect(_place_catalog.refresh)


func open_crafting(recipe_id := "", section_id := "") -> void:
	if _craft_window == null: return
	_close_action_panel()
	if _orders != null: _orders.set_open(false)
	tool_requested.emit("")
	_window_manager.open("craft")
	_craft_panel.select_section("rudimentary" if section_id.is_empty() else section_id)
	if not recipe_id.is_empty(): _craft_panel.select_recipe(recipe_id)
	_craft_panel.refresh()
	_craft_panel.fit_above_dock(_dock_panel.position.y)


func _open_place_catalog() -> void:
	if _place_window == null: return
	if _orders != null: _orders.set_open(false)
	_panel_container.hide()
	_active_panel_target = ""
	if _place_window.visible:
		_window_manager.close("place")
	else:
		tool_requested.emit("furniture")
		_window_manager.open("place")
		_place_catalog.refresh()
		_place_catalog.fit_above_dock(_dock_panel.position.y)
	_refresh_active_buttons()


func _start_catalog_placement(key: String) -> void:
	tool_requested.emit("furniture")
	_furniture_controller.activate_for(key, true)
	_place_catalog.refresh()


func _open_inventory() -> void:
	if _inventory_window == null: return
	if _inventory_window.visible:
		_window_manager.close("inventory")
		return
	_close_action_panel()
	if _orders != null: _orders.set_open(false)
	tool_requested.emit("")
	_window_manager.open("inventory")
	_inventory_panel.fit_above_dock(_dock_panel.position.y)


func _locate_inventory_item(key: String, storage_only: bool) -> void:
	# Resolve current owners at click time: hauling and removal can invalidate
	# yesterday's location without changing the selected inventory tile.
	var items := get_tree().get_first_node_in_group("item_drop_manager") as ItemDropManager
	if items == null: return
	var locations := StockpileManager.get_item_locations(key)
	if not storage_only:
		var physical := items.get_inventory_items()
		for entry: Dictionary in physical.loose + physical.carried + physical.equipped:
			var node: Node3D = entry.node
			if bool(node.get_meta("equipped", false)): node = node.get_parent() as Node3D
			if entry.key != key or not node.is_inside_tree() or not node.is_visible_in_tree(): continue
			locations.append({"kind": "item", "node": node, "position": node.global_position})
	var rig: Node = get_viewport().get_camera_3d()
	while rig != null and not rig.has_method("locate_position"): rig = rig.get_parent()
	for location: Dictionary in locations:
		if float(location.position.y) > items._slice_y + 1.0: continue
		if location.has("node") and not location.node.is_visible_in_tree(): continue
		var inspected := false
		if storage_only:
			if location.kind == "stockpile" and _stockpile_controller != null:
				inspected = _stockpile_controller.inspect_storage(location.owner)
			elif location.kind == "container" and _furniture_controller != null:
				inspected = _furniture_controller.inspect_storage(location.owner)
			if not inspected: continue
		if rig == null and not inspected: continue
		if rig != null: rig.locate_position(location.position)
		_window_manager.close("inventory")
		return
	show_persistence_status("No accessible location on this slice. Change the slice level and try again.")


## Push-registration from MiningDesignationController — gives the dock's
## 'mine' entry live pressed-state (the tool previously had none at all).
func register_mining_controller(controller: Node) -> void:
	_mining_controller = controller
	_connect_tool_active(controller)
	if _orders != null: _orders.bind_controller("mine_precision", controller)
	if _chop_controller != null: _chop_controller.set_mining_controller(controller)


func register_construction_controller(controller: Node) -> void:
	_construction_controller = controller
	_connect_tool_active(controller)


## Push-registration from RoomOverlayController (🚪 Rooms tool, 2026-08-07) —
## the dock's 'rooms' entry announces via tool_requested; the controller
## self-toggles. Registration exists for the pressed-state readback only.
func register_room_controller(controller: Node) -> void:
	_room_controller = controller
	_connect_tool_active(controller)


func register_chop_controller(controller: Node) -> void:
	_chop_controller = controller
	_connect_tool_active(controller)
	controller.set_mining_controller(_mining_controller)
	if _orders != null:
		_orders.bind_controller("chop", controller)
		_orders.bind_controller("clear_stones", controller)
		_orders.bind_controller("harvest_plants", controller)
		_orders.bind_controller("clear_shrubs", controller)
		_orders.bind_controller("cancel_orders", controller)


func _request_order_tool(tool_id: String) -> void:
	# Clicking the selected tile keeps its brush and size; Done/Escape exits.
	if not tool_id.is_empty() and _orders.active_tool_id() == tool_id: return
	_orders.hide_feedback()
	tool_requested.emit(tool_id)
	_orders.refresh()
	_refresh_active_buttons()


## Shared hookup for the slice pattern generalised to every click-tool: the
## controller emits tool_active_changed on activate/deactivate (Esc included)
## and the dock re-derives every button's pressed state. Before this, only the
## slice tool pushed refreshes — Esc-cancelling any other tool left its button
## lit until the next dock interaction.
func _connect_tool_active(controller: Node) -> void:
	if not controller.has_signal("tool_active_changed"):
		return
	var refresh := Callable(self, "_on_tool_active_changed")
	if not controller.is_connected("tool_active_changed", refresh):
		controller.connect("tool_active_changed", refresh)


func _on_tool_active_changed(_active: bool) -> void:
	_refresh_active_buttons()
	if _orders != null: _orders.call_deferred("refresh")


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
	var menu: Dictionary = UIRegistry.get_menu(target)
	if not menu.is_empty(): return String(menu.title)
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
		"save_load": return "Save / Load"
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
			var actions: Array[String] = []
			actions.assign(FURNITURE_PANEL_ITEMS.keys())
			actions.append("Cancel")
			return actions
		"storage_zone":
			return ["Draw Zone", "DEV: Spawn Drops", "DEV: Spawn Furniture", "DEV: Spawn Bushes", "Cancel"]
		"farm":
			return ["Cave Plot", "Surface Plot", "Plant Crop", "Harvest"]
		"military":
			return ["Patrol Route", "Guard Post", "Armory", "Enlist"]
		"save_load":
			return ["💾 Save Game", "📂 Load Game", "🕒 Load Autosave"]
	return []


## Placeholder row content for the not-yet-built systems (doc 24: kept until
## Labor/Stockpiles/Trade land for real).
func _window_rows(target: String) -> Array[String]:
	match target:
		"stockpiles":
			return ["Stone       0", "Ore         0", "Food        0", "Drink       0", "Trade Goods 0"]
		"trade":
			return ["Trade preview", "Exchange colony goods with visiting merchants in a future update."]
	return []


func _clear_children(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


func _node_suffix(value: String) -> String:
	var result := ""
	for part in value.split("_", false):
		result += part.capitalize().replace(" ", "")
	return result
