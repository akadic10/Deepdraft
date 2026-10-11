extends CanvasLayer

@export var camera_path: NodePath
@export var slice_path: NodePath
@export var window_manager_path: NodePath
@export var dock_path: NodePath
var _info: Label
var _source: Button
var _dam: Button
var _fall := 0

func _ready() -> void:
	_build.call_deferred()

func _build() -> void:
	var body := VBoxContainer.new()
	UITheme.apply_surface(body)
	body.add_theme_constant_override("separation",10)
	_info = Label.new()
	body.add_child(_info)
	_button(body,"Focus spring cave",func(): _focus(WorldGenerator.spring_cave.get("mouth",Vector3i.ZERO)))
	_button(body,"Next waterfall",_next_fall)
	_button(body,"Focus lakebed dry stone",func(): _focus(WorldGenerator.river_layout.get("dry_stone",Vector3i.ZERO)))
	_source = _button(body,"Stop spring",func(): WaterManager.source_enabled = not WaterManager.source_enabled)
	_dam = _button(body,"Build test dam",func(): _focus(WaterManager.dev_toggle_dam()))
	var overlay := CheckButton.new()
	overlay.text = "Soil moisture overlay · brown dry / blue wet"
	overlay.toggled.connect(func(on: bool): WaterManager.show_moisture = on)
	body.add_child(overlay)
	_button(body,"Draw up to 20 blocks of lake water",func():
		if WaterManager.initialized: WaterManager.extract(WorldGenerator.river_layout.outlet,20.0))
	var hint := Label.new()
	hint.text = "Dam edits and withdrawals change the world and are saved.\nUnpause to watch rising water and bank overflow.\nOrdinary water is finite; the spring replenishes it slowly."
	body.add_child(hint)
	get_node(window_manager_path).register_window("water_dev","DEV · Water","",body,
		{"persistent":false,"default_pos":Vector2(18,90),"min_size":Vector2(420,0)})
	WaterManager.flood_warning.connect(func(): get_node(dock_path).show_persistence_status("Rising water is spilling onto dry ground."))

func _button(parent: Node,label: String,action: Callable) -> Button:
	var button := Button.new()
	button.text = label
	UITheme.apply_button_variant(button,"dev")
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _process(_delta: float) -> void:
	if _info == null: return
	if not get_node(window_manager_path).is_open("water_dev"): return
	if not WaterManager.initialized:
		_info.text = "Waiting for the landscape…"
		return
	var water := WaterManager
	var layout: Dictionary = WorldGenerator.river_layout
	_info.text = "Spring at Y%d · maximum level %.1f\nDry stone at Y%d · lake retains level %.1f\nStored: %.2f blocks³\nSpring added: %.2f · outlet drained: %.2f\nDrawn: %.2f · flow step: %.1f ms" % [layout.spring.y,layout.spring_level,layout.dry_stone.y,layout.outlet_level,water.flow.total_volume(),water.flow.added,water.flow.drained,water.flow.extracted,water.last_step_usec/1000.0]
	_source.text = "Stop spring" if water.source_enabled else "Restart spring"
	_dam.text = "Build test dam" if water.test_dam.is_empty() else "Remove test dam"

func _focus(cell: Vector3i) -> void:
	if cell == Vector3i.ZERO: return
	var slice = get_node(slice_path)
	if slice.is_active(): slice.deactivate()
	get_node(camera_path).focus_world_position(Vector3(cell)+Vector3.ONE*0.5,42.0)

func _next_fall() -> void:
	if not WaterManager.initialized: return
	var falls: Array = WorldGenerator.river_layout.falls
	if falls.is_empty(): return
	_focus(falls[_fall%falls.size()])
	_fall += 1
