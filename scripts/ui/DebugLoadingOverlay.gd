class_name DebugLoadingOverlay
extends CanvasLayer

@export var renderer_path: NodePath

var _panel: PanelContainer
var _title_bar: PanelContainer
var _label: Label
var _renderer: Node
var _world_generator: Node
var _elapsed: float = 0.0
var _dragging: bool = false


func _ready() -> void:
	_renderer = get_node_or_null(renderer_path)
	_world_generator = get_node_or_null("/root/WorldGenerator")
	_build_ui()
	visible = false


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < 0.15:
		return
	_elapsed = 0.0
	_update_text()


func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.position = Vector2(16.0, 16.0)
	_panel.custom_minimum_size = Vector2(540.0, 0.0)
	_panel.add_theme_stylebox_override("panel", _window_style())
	add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 1)
	margin.add_theme_constant_override("margin_right", 1)
	margin.add_theme_constant_override("margin_top", 1)
	margin.add_theme_constant_override("margin_bottom", 1)
	_panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	margin.add_child(column)

	_title_bar = PanelContainer.new()
	_title_bar.name = "TitleBar"
	_title_bar.custom_minimum_size = Vector2(0.0, 34.0)
	_title_bar.mouse_default_cursor_shape = Control.CURSOR_MOVE
	_title_bar.add_theme_stylebox_override("panel", _title_bar_style())
	_title_bar.gui_input.connect(_on_title_bar_gui_input)
	column.add_child(_title_bar)

	var title_margin := MarginContainer.new()
	title_margin.add_theme_constant_override("margin_left", 10)
	title_margin.add_theme_constant_override("margin_right", 8)
	title_margin.add_theme_constant_override("margin_top", 4)
	title_margin.add_theme_constant_override("margin_bottom", 4)
	_title_bar.add_child(title_margin)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	title_margin.add_child(header)

	var title := Label.new()
	title.text = "World Build"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 15)
	header.add_child(title)

	var close := Button.new()
	close.name = "CloseButton"
	close.text = "X"
	close.custom_minimum_size = Vector2(28.0, 24.0)
	close.focus_mode = Control.FOCUS_NONE
	close.tooltip_text = "Close"
	close.add_theme_font_size_override("font_size", 13)
	close.add_theme_stylebox_override("normal", _close_button_style(Color(0.58, 0.08, 0.08, 0.95)))
	close.add_theme_stylebox_override("hover", _close_button_style(Color(0.78, 0.10, 0.10, 1.0)))
	close.add_theme_stylebox_override("pressed", _close_button_style(Color(0.42, 0.04, 0.04, 1.0)))
	close.pressed.connect(func() -> void:
		visible = false
	)
	header.add_child(close)

	var body_margin := MarginContainer.new()
	body_margin.add_theme_constant_override("margin_left", 10)
	body_margin.add_theme_constant_override("margin_right", 10)
	body_margin.add_theme_constant_override("margin_top", 8)
	body_margin.add_theme_constant_override("margin_bottom", 10)
	column.add_child(body_margin)

	_label = Label.new()
	_label.name = "Stats"
	_label.add_theme_font_size_override("font_size", 15)
	body_margin.add_child(_label)
	_update_text()


func _update_text() -> void:
	if _label == null:
		return

	var gen := {}
	var metrics := {}
	if _world_generator != null:
		gen = _world_generator.call("get_streaming_stats")
		metrics = _world_generator.call("get_generation_metrics")
	var render := {}
	if _renderer != null and _renderer.has_method("get_render_stats"):
		render = _renderer.call("get_render_stats")

	var camera_chunk: Vector2i = render.get("camera_chunk", Vector2i.ZERO)
	var maps_text := "ready" if gen.get("maps_ready", false) else "building"
	var in_flight_text := "yes" if gen.get("column_in_flight", false) else "no"
	var render_mode: String = render.get("render_mode", "unknown")
	var domains: Dictionary = metrics.get("domains", {})
	var surface: Dictionary = metrics.get("surface", {})
	var surface_by_domain: Dictionary = surface.get("by_domain", {})
	var mountain_surface: Dictionary = surface_by_domain.get("mountain", {})
	var valley_surface: Dictionary = surface_by_domain.get("valley", {})
	var heights: Dictionary = metrics.get("heights", {})
	var shaping: Dictionary = metrics.get("shaping", {})
	var water: Dictionary = metrics.get("water", {})
	var macro: Dictionary = metrics.get("macro", {})
	var candidates: Dictionary = metrics.get("settlement_candidates", {})
	var map_phase_text := "n/a"
	var map_phase_timings: Array = gen.get("map_phase_timings", [])
	var slowest_map_phase_ms := -1
	for phase in map_phase_timings:
		var phase_dict: Dictionary = phase
		var phase_ms := int(phase_dict.get("ms", 0))
		if phase_ms > slowest_map_phase_ms:
			slowest_map_phase_ms = phase_ms
			map_phase_text = "%s %.2fs" % [
				String(phase_dict.get("name", "unknown")),
				float(phase_ms) / 1000.0,
			]

	_label.text = "\n".join([
		"render: %s" % render_mode,
		"overview: step %d  sides %s" % [
			render.get("overview_step", 0),
			"on" if render.get("overview_sides", false) else "off",
		],
		"overview faces: top %d->%d  side %d  check %d/%d" % [
			render.get("overview_sampled_top_faces", 0),
			render.get("overview_merged_top_faces", 0),
			render.get("overview_side_faces", 0),
			render.get("overview_validation_mismatches", 0),
			render.get("overview_validation_samples", 0),
		],
		"maps: %s" % maps_text,
		"domain %%: M %.1f  V %.1f  L %.1f" % [
			domains.get("mountain_pct", 0.0),
			domains.get("valley_pct", 0.0),
			domains.get("lowland_pct", 0.0),
		],
		"height: %d-%d  avg %.1f" % [
			heights.get("min", 0),
			heights.get("max", 0),
			heights.get("avg", 0.0),
		],
		"surface %%: grass %.1f  dirt %.1f  rock %.1f  water %.1f" % [
			surface.get("grass_pct", 0.0),
			surface.get("dirt_pct", 0.0),
			surface.get("rock_pct", 0.0),
			surface.get("water_pct", 0.0),
		],
		"surface domain: M rock %.1f  V g/d/r %.1f/%.1f/%.1f" % [
			mountain_surface.get("rock_pct", 0.0),
			valley_surface.get("grass_pct", 0.0),
			valley_surface.get("dirt_pct", 0.0),
			valley_surface.get("rock_pct", 0.0),
		],
		"shape: terrace %.1f%%  plateau %d" % [
			shaping.get("terraced_pct", 0.0),
			shaping.get("plateau_adjusted_columns", 0),
		],
		"water: lake %s d%d  tarn %s d%d  bank %d" % [
			str(water.get("lake_center", Vector2i.ZERO)),
			water.get("lake_depth_max", 0),
			str(water.get("tarn_center", Vector2i.ZERO)),
			water.get("tarn_depth_max", 0),
			water.get("bank_columns", 0),
		],
		"macro: basin %d  SE foothill %d  edge %d" % [
			macro.get("southwest_basin_columns", 0),
			macro.get("southeast_foothill_columns", 0),
			macro.get("edge_belt_columns", 0),
		],
		"settlement candidates: %d" % candidates.get("count", 0),
		"columns: %d / %d" % [gen.get("generated_columns", 0), gen.get("total_columns", 0)],
		"timing: maps %.2fs  columns %.2fs  region %.2fs  overview %.2fs" % [
			float(gen.get("map_precompute_ms", 0)) / 1000.0,
			float(gen.get("column_fill_ms_total", 0)) / 1000.0,
			float(render.get("region_rebuild_ms_total", 0)) / 1000.0,
			float(render.get("overview_build_ms_total", 0)) / 1000.0,
		],
		"slowest map phase: %s" % map_phase_text,
		"first terrain: %.2fs  elapsed: %.2fs" % [
			float(render.get("first_visible_mesh_ms", 0)) / 1000.0,
			float(render.get("startup_elapsed_ms", gen.get("startup_elapsed_ms", 0))) / 1000.0,
		],
		"overview startup: %d/%d  ready %.2fs  full %.2fs" % [
			render.get("overview_build_count", 0),
			render.get("overview_startup_tile_goal", 0),
			float(render.get("overview_startup_ready_ms", 0)) / 1000.0,
			float(render.get("overview_complete_ms", 0)) / 1000.0,
		],
		"requested: %d  queue: %d  active: %s" % [
			gen.get("requested_columns", 0),
			gen.get("queue_size", 0),
			in_flight_text,
		],
		"camera chunk: %d,%d  slice: %d" % [
			camera_chunk.x,
			camera_chunk.y,
			render.get("slice_y", 0),
		],
		"meshes: %d  queued: %d  built: %d" % [
			render.get("mesh_nodes", 0),
			render.get("dirty_queue", 0),
			render.get("meshes_built", 0),
		],
	])


func _on_title_bar_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mouse.pressed
	elif event is InputEventMouseMotion and _dragging:
		var motion := event as InputEventMouseMotion
		_panel.position += motion.relative


func _window_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.070, 0.075, 0.080, 0.92)
	style.border_color = Color(1, 1, 1, 0.16)
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 7
	style.corner_radius_top_right = 7
	style.corner_radius_bottom_left = 7
	style.corner_radius_bottom_right = 7
	return style


func _title_bar_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.13, 0.14, 0.98)
	style.corner_radius_top_left = 7
	style.corner_radius_top_right = 7
	return style


func _close_button_style(bg: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = Color(1.0, 0.45, 0.45, 0.50)
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 5
	style.corner_radius_top_right = 5
	style.corner_radius_bottom_left = 5
	style.corner_radius_bottom_right = 5
	style.content_margin_left = 6.0
	style.content_margin_right = 6.0
	return style
