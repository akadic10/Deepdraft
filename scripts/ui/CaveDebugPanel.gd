extends CanvasLayer

## Explicit developer inspection. Outlines and preview never mark caves mined
## or discovered. Closing restores the previous camera/slice and normal terrain.
@export var renderer_path: NodePath
@export var camera_path: NodePath
@export var slice_path: NodePath
@export var window_manager_path: NodePath

var _renderer: Node
var _camera: Node
var _slice: Node
var _manager: Node
var _selector: OptionButton
var _info: Label
var _preview: CheckButton
var _highlight: CheckButton
var _canvas: Highlight
var _catalog: Array = []
var _camera_before: Dictionary = {}
var _slice_before: Dictionary = {}
var _is_open := false


class Highlight extends Control:
	var segments := PackedVector2Array()
	var selected := PackedVector2Array()
	var labels: Array = []
	func _draw() -> void:
		if not segments.is_empty(): draw_multiline(segments, Color(0.2, 0.95, 0.9, 0.8), 1.5, true)
		if not selected.is_empty(): draw_multiline(selected, Color(1.0, 0.72, 0.25), 2.5, true)
		for label: Dictionary in labels:
			draw_string(ThemeDB.fallback_font, label["position"], label["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1.0, 0.85, 0.5))


func _ready() -> void:
	_renderer = get_node(renderer_path)
	_camera = get_node(camera_path)
	_slice = get_node(slice_path)
	_manager = get_node(window_manager_path)
	_canvas = Highlight.new()
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_canvas)
	var body := VBoxContainer.new()
	UITheme.apply_surface(body)
	body.add_theme_constant_override("separation", 10)
	var intro := Label.new()
	intro.text = "Locate and inspect generated caves.\nPreview does not discover or excavate them."
	body.add_child(intro)
	_selector = OptionButton.new()
	_selector.item_selected.connect(_select_cave)
	body.add_child(_selector)
	var navigation := HBoxContainer.new()
	body.add_child(navigation)
	_button(navigation, "Previous", func() -> void: _cycle(-1))
	_button(navigation, "Next", func() -> void: _cycle(1))
	_button(navigation, "Focus + slice", _focus_selected)
	_highlight = CheckButton.new()
	_highlight.text = "Highlight cave outlines through terrain"
	_highlight.button_pressed = true
	body.add_child(_highlight)
	_preview = CheckButton.new()
	_preview.text = "Preview interior with DEV lighting"
	_preview.toggled.connect(func(_on: bool) -> void: _refresh_preview())
	body.add_child(_preview)
	_info = Label.new()
	body.add_child(_info)
	var footer := Label.new()
	footer.text = "Normal discovery: mine through a cave wall.\nClose this window to restore your previous view."
	body.add_child(footer)
	_manager.register_window("caves_dev", "DEV · Cave explorer", "", body,
		{"persistent": false, "default_pos": Vector2(18, 90), "min_size": Vector2(420, 0)})
	_manager.window_state_changed.connect(_on_window_state)
	set_process(false)


func _button(parent: Node, text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	UITheme.apply_button_variant(button, "dev")
	button.pressed.connect(action)
	parent.add_child(button)


func _on_window_state(id: String, opened: bool) -> void:
	if id != "caves_dev": return
	_is_open = opened
	set_process(opened)
	_canvas.visible = opened
	if opened:
		_camera_before = _camera.serialize_state()
		_slice_before = _slice.serialize_state()
		_refresh_catalog()
	else:
		_renderer.clear_debug_cave_blocks()
		_preview.set_pressed_no_signal(false)
		if not _slice_before.is_empty(): _slice.restore_state(_slice_before)
		if not _camera_before.is_empty(): _camera.restore_state(_camera_before)


func _refresh_catalog() -> void:
	_catalog = WorldGenerator.get_cave_catalog()
	_selector.clear()
	for cave: Dictionary in _catalog:
		_selector.add_item("Cave %d · floor Y%d · %d chambers" % [int(cave["id"]) + 1, cave["floor_y"], cave["rooms"]])
	if not _catalog.is_empty(): _selector.select(0)
	_update_info()


func _cycle(direction: int) -> void:
	if _catalog.is_empty(): return
	_selector.select(posmod(_selector.selected + direction, _catalog.size()))
	_select_cave(_selector.selected)
	_focus_selected()


func _select_cave(_index: int) -> void:
	_refresh_preview()
	_update_info()


func _focus_selected() -> void:
	if _catalog.is_empty(): return
	var cave: Dictionary = _catalog[_selector.selected]
	var center: Vector3i = cave["center"]
	var depth := WorldGenerator.get_visible_surface_y(center.x, center.z) - center.y
	_camera.focus_world_position(Vector3(center) + Vector3.UP, maxf(100.0, float(depth + 20) / 0.6))
	_slice.show_at_height(int(cave["floor_y"]) + 3, false)


func _refresh_preview() -> void:
	if _is_open and _preview.button_pressed and not _catalog.is_empty():
		_renderer.set_debug_cave_blocks(WorldGenerator.get_cave_air_cells(_selector.selected))
		_focus_selected()
	else:
		_renderer.clear_debug_cave_blocks()


func _update_info() -> void:
	if _catalog.is_empty():
		_info.text = "Caves are being generated…" if not WorldGenerator._maps_ready else "No caves in this world."
		return
	var cave: Dictionary = _catalog[_selector.selected]
	_info.text = "%d caves · selected cave %d\n%s\nFloor: %d blocks · air: %d blocks\nExposed ore/gem blocks: %d · cave soil: %d\n%s" % [
		_catalog.size(), _selector.selected + 1, str(cave["center"]), cave["floor_area"], cave["air_blocks"],
		cave["exposed_resource_blocks"], cave["soil_columns"],
		"Discovered through mining" if InteriorTracker.is_cave_discovered(_selector.selected) else "Undiscovered"]


func _process(_delta: float) -> void:
	if _catalog.is_empty() and WorldGenerator._maps_ready: _refresh_catalog()
	_update_info()
	_canvas.segments.clear()
	_canvas.selected.clear()
	_canvas.labels.clear()
	if _highlight.button_pressed and _camera.camera_node != null:
		var camera: Camera3D = _camera.camera_node
		for cave: Dictionary in _catalog:
			var columns: Dictionary = {}
			for index: int in cave["columns"]: columns[index] = true
			var lines := PackedVector2Array()
			var floor_y := float(cave["floor_y"]) + 1.03
			for index: int in cave["columns"]:
				var x := index / 1024
				var z := index % 1024
				for edge in [[-1024, Vector3(x, floor_y, z), Vector3(x, floor_y, z + 1)],
					[1024, Vector3(x + 1, floor_y, z), Vector3(x + 1, floor_y, z + 1)],
					[-1, Vector3(x, floor_y, z), Vector3(x + 1, floor_y, z)],
					[1, Vector3(x, floor_y, z + 1), Vector3(x + 1, floor_y, z + 1)]]:
					if columns.has(index + int(edge[0])): continue
					if camera.is_position_behind(edge[1]) or camera.is_position_behind(edge[2]): continue
					lines.append(camera.unproject_position(edge[1]))
					lines.append(camera.unproject_position(edge[2]))
			if cave["id"] == _selector.selected: _canvas.selected = lines
			else: _canvas.segments.append_array(lines)
			var center := Vector3(cave["center"]) + Vector3.UP
			if not camera.is_position_behind(center):
				_canvas.labels.append({"position": camera.unproject_position(center), "text": "Cave %d · Y%d" % [int(cave["id"]) + 1, cave["floor_y"]]})
	_canvas.queue_redraw()
