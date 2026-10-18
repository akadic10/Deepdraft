extends CanvasLayer

## Scene presentation gate. Never uses a timer or log text as proof of readiness.
signal revealed
@export var renderer_path: NodePath
@export var flora_path: NodePath
@export var details_path: NodePath
@export var wildlife_path: NodePath
var _renderer: Node
var _flora: Node
var _details: Node
var _wildlife: Node
var _art: Control
var _hidden_layers: Array[Dictionary] = []
var _quiet_frames := 0
var _full_seconds := 0.0
var _released := false
var _last_state: Dictionary = {}

func _enter_tree() -> void:
	layer = 128
	add_to_group("world_loading_screen")
	WorldClock.hold_for_loading(self,true)

func _ready() -> void:
	_renderer = get_node_or_null(renderer_path)
	_flora = get_node_or_null(flora_path)
	_details = get_node_or_null(details_path)
	_wildlife = get_node_or_null(wildlife_path)
	_art = preload("LoadingArtwork.gd").new()
	_art.definition = UIRegistry.get_loading_screen()
	# Pick once per scene load, without consuming the simulation's random stream.
	var artwork_rng := RandomNumberGenerator.new()
	artwork_rng.randomize()
	var backgrounds: Array = _art.definition.backgrounds
	_art.artwork = load(String(backgrounds[artwork_rng.randi_range(0,backgrounds.size()-1)])) as Texture2D
	add_child(_art)
	_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hide_layers(get_parent())
	# Poll after all ordinary scene owners have drained their frame's queues.
	process_priority = 100

func _hide_layers(node: Node) -> void:
	if node == self: return
	if node is CanvasLayer:
		_hidden_layers.append({"node":weakref(node),"visible":node.visible})
		node.visible = false
	for child in node.get_children(): _hide_layers(child)

func _input(_event: InputEvent) -> void:
	if not _released: get_viewport().set_input_as_handled()

func loading_state() -> Dictionary:
	if not is_instance_valid(_renderer): return {"ready":false,"progress":0.0}
	var gen := WorldGenerator.get_streaming_stats()
	var render: Dictionary = _renderer.get_render_stats()
	var maps := bool(gen.get("maps_ready",false)) and not WorldGenerator.is_generating()
	var map_fraction := 1.0 if maps else minf(.95,float(gen.get("map_phase_timings",[]).size())/8.0)
	var tile_size := maxi(1,int(render.get("overview_tile_size",32)))
	var total := ceili(float(WorldGenerator.WORLD_SIZE_X)/tile_size)*ceili(float(WorldGenerator.WORLD_SIZE_Z)/tile_size)
	var terrain_fraction := clampf(float(render.get("overview_tiles",0))/maxi(1,total),0,1)
	var scenery: bool = _flora != null and bool(_flora.get_spawn_stats().get("ready",false)) and _details != null and _details.is_loading_complete() and _wildlife != null and _wildlife.is_loading_complete()
	var ready: bool = maps and bool(render.get("loading_complete",false)) and scenery and not SaveManager.is_loading()
	var progress := .28*map_fraction+.62*terrain_fraction+(.09 if scenery else 0.0)
	return {"ready":ready,"progress":1.0 if ready else minf(.99,progress),"maps":maps,"terrain":bool(render.get("loading_complete",false)),"scenery":scenery,"restoring":SaveManager.is_loading()}

func _process(delta: float) -> void:
	if _released: return
	_last_state = loading_state()
	_quiet_frames = _quiet_frames+1 if _last_state.ready else 0
	var ready := _quiet_frames>=3
	var target := 1.0 if ready else minf(.99,float(_last_state.progress))
	_art.progress = maxf(_art.progress,target)
	_art.complete = ready
	_art.animation_time += delta
	_art.queue_redraw()
	_full_seconds = _full_seconds+delta if ready else 0.0
	# Show a fully filled mug briefly; readiness is still rechecked each frame.
	if _full_seconds>=.25: _reveal()

func _reveal() -> void:
	_released = true
	_restore_layers()
	WorldClock.hold_for_loading(self,false)
	hide()
	set_process(false)
	set_process_input(false)
	revealed.emit()

func _restore_layers() -> void:
	for entry in _hidden_layers:
		var node = entry.node.get_ref()
		if is_instance_valid(node): node.visible = entry.visible
	_hidden_layers.clear()

func _exit_tree() -> void:
	WorldClock.hold_for_loading(self,false)
	_restore_layers()
