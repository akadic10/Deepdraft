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
	panel.custom_minimum_size = Vector2(360.0, 0.0)
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
	var render := {}
	if _renderer != null and _renderer.has_method("get_render_stats"):
		render = _renderer.call("get_render_stats")

	var camera_chunk: Vector2i = render.get("camera_chunk", Vector2i.ZERO)
	var maps_text := "ready" if gen.get("maps_ready", false) else "building"
	var in_flight_text := "yes" if gen.get("column_in_flight", false) else "no"
	var render_mode := "overview faces" if render.get("diorama_active", false) else "streamed block faces"

	_label.text = "\n".join([
		"World build",
		"render: %s" % render_mode,
		"maps: %s" % maps_text,
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
