extends RefCounted

## Mining UI for MiningDesignationController (doc 258 step 8): the Mining Zone
## window (zone statistics, Remove, the DEV instant mine) and the mining-mode
## hint callout. The controller owns zone selection; the buttons and the
## window's close report back through signals.

# Text sizes come from the type scale (doc 23, "Type").
const MEDIUM := UITheme.TYPE_MEDIUM
signal remove_pressed
signal dev_mine_pressed
signal closed

const ZONE_WINDOW_ID := "mining_zone_info"
const REFRESH_INTERVAL_S := 0.5

var window_manager: UIWindowManager
var zone_window: UIWindow
var zone_body: Label
var hint_window: PanelContainer
var _ui_layer: CanvasLayer
var _refresh_accum: float = 0.0


func _init(parent: Node, manager: UIWindowManager) -> void:
	window_manager = manager
	_build_zone_window()
	_build_hint_window(parent)


func _build_zone_window() -> void:
	# Simulation fixtures may omit the presentation layer.
	if window_manager == null:
		return

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)

	zone_body = Label.new()
	zone_body.text = "Blocks: 0"
	zone_body.add_theme_font_size_override("font_size", MEDIUM.small)
	column.add_child(zone_body)

	var remove := Button.new()
	remove.text = "Remove"
	UITheme.apply_button_variant(remove, "danger")
	remove.custom_minimum_size = Vector2(98.0, 34.0)
	remove.focus_mode = Control.FOCUS_NONE
	remove.tooltip_text = "Remove mining zone"
	remove.pressed.connect(func() -> void:
		remove_pressed.emit()
	)
	column.add_child(remove)

	# DEV-only instant mine: executes the zone immediately — blocks are removed
	# from the game (no drops, no dwarves). Testing tool for slice/interiors;
	# replaced by real mining execution later.
	var dev_mine := Button.new()
	dev_mine.text = "DEV Mine (no drops)"
	dev_mine.custom_minimum_size = Vector2(98.0, 34.0)
	dev_mine.focus_mode = Control.FOCUS_NONE
	dev_mine.tooltip_text = "DEV: remove this zone's blocks from the game instantly"
	UITheme.apply_button_variant(dev_mine, "dev")
	dev_mine.pressed.connect(func() -> void:
		dev_mine_pressed.emit()
	)
	dev_mine.visible = UIRegistry.dev_tools_enabled
	column.add_child(dev_mine)

	zone_window = window_manager.register_window(ZONE_WINDOW_ID, "Mining Zone", "", column,
		{"default_pos": Vector2(18, 118), "min_size": Vector2(280, 118), "family": "work"})
	window_manager.window_state_changed.connect(_on_zone_window_state_changed)


func _on_zone_window_state_changed(id: String, shown: bool) -> void:
	if id == ZONE_WINDOW_ID and not shown:
		closed.emit()


## Mining-mode instruction callout (#5): a small control-summary panel shown while
## the tool is active. Informational only — ignores the mouse so it never blocks
## clicks. Cursor assets are deferred (see doc 05).
func _build_hint_window(parent: Node) -> void:
	_ui_layer = CanvasLayer.new()
	_ui_layer.name = "MiningHintUI"
	_ui_layer.layer = 24
	parent.add_child(_ui_layer)

	hint_window = PanelContainer.new()
	UITheme.apply_surface(hint_window)
	hint_window.name = "MiningHintWindow"
	hint_window.visible = false
	hint_window.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_window.add_theme_stylebox_override("panel", UITheme.window_style())
	# Centred near the top of the screen, content-sized.
	hint_window.anchor_left = 0.5
	hint_window.anchor_right = 0.5
	hint_window.anchor_top = 0.0
	hint_window.anchor_bottom = 0.0
	hint_window.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hint_window.grow_vertical = Control.GROW_DIRECTION_END
	hint_window.offset_top = 14.0
	_ui_layer.add_child(hint_window)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 7)
	margin.add_theme_constant_override("margin_bottom", 8)
	hint_window.add_child(margin)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 3)
	margin.add_child(column)

	var title := Label.new()
	title.text = "Mining Tool"
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.apply_title(title, MEDIUM.lead)
	column.add_child(title)

	var body := Label.new()
	body.text = "Drag: designate   ·   Ctrl: remove\nShift / Alt + wheel: width / depth   ·   Esc: exit"
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_theme_font_size_override("font_size", MEDIUM.small)
	body.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	column.add_child(body)


func is_showing() -> bool:
	return zone_window != null and zone_window.visible


func open() -> void:
	window_manager.open(ZONE_WINDOW_ID)


func close() -> void:
	if window_manager != null:
		window_manager.close(ZONE_WINDOW_ID)


## True every REFRESH_INTERVAL_S of open-window time: the worker/blocked line
## stays live while the window is open, independent of tool state.
func refresh_due(delta: float) -> bool:
	_refresh_accum += delta
	if _refresh_accum < REFRESH_INTERVAL_S:
		return false
	_refresh_accum = 0.0
	return true


func update_text(zone: Dictionary) -> void:
	var component: MiningZoneComponent = zone.get("component")
	if component != null:
		var text := "Blocks left: %d / %d   Workers: %d   Faces: %d" % [
			component.remaining_count(), component.total_count(),
			component.reserved.size(), component.destination_count()]
		# Lease health: tell the player WHY nobody is coming (doc 31's
		# task_unreachable intent — no toast system yet, so it lives here).
		var now := Time.get_ticks_msec()
		var assigned := 0
		var blocked := 0
		for task_id: int in component.lease_ids.keys():
			var task := TaskManager.get_task(task_id)
			if task == null:
				continue
			if task.assigned_to >= 0:
				assigned += 1
			elif now < task.retry_at:
				blocked += 1
		if assigned == 0 and blocked > 0:
			text += "\nNo worker can reach this zone — retrying."
		zone_body.text = text
	else:
		zone_body.text = "Blocks: %d" % (zone.get("blocks", []) as Array).size()
