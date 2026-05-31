class_name DebugLoadingOverlay
extends CanvasLayer

@export var renderer_path: NodePath

var _label: Label
var _renderer: Node
var _elapsed: float = 0.0


func _ready() -> void:
	_renderer = get_node_or_null(renderer_path)
	_build_ui()


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < 0.15:
		return
	_elapsed = 0.0
	_update_text()


func _build_ui() -> void:
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.offset_left = 16.0
	panel.offset_top = 16.0
	panel.custom_minimum_size = Vector2(520.0, 0.0)
	add_child(panel)

	_label = Label.new()
	_label.name = "Stats"
	_label.add_theme_font_size_override("font_size", 15)
	panel.add_child(_label)
	_update_text()


func _update_text() -> void:
	if _label == null:
		return

	var gen := WorldGenerator.get_streaming_stats()
	var metrics := WorldGenerator.get_generation_metrics()
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

	_label.text = "\n".join([
		"World build",
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
