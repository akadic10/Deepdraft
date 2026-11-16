extends Node3D

## The plants on the colony's fields (doc 309): one model a tile, standing on its tilled soil, as
## a bush stands on its ground. FarmingSystem says which model each tile shows (a crop's sprout,
## growing or ripe stage, or the bare tilled tile); this node builds them a few a frame, lights
## them as the world's other plants are and hides them above the slice. A plant has no collision
## and no occupancy (Hard Rule 5): dwarves and animals walk through it.
const Lighting = preload("res://scripts/components/UndergroundLighting.gd")
const Shadows = preload("res://scripts/components/VoxelShadowSetup.gd")

## Tiles built a frame, so a loaded colony's fields never arrive in one frame.
@export var budget := 24

var _wanted: Dictionary = {}   # tile cell -> model path
var _nodes: Dictionary = {}    # tile cell -> Node3D
var _shown: Dictionary = {}    # tile cell -> the model path its node shows
var _queue: Array[Vector3i] = []
var _queued: Dictionary = {}
var _models: Dictionary = {}   # model path -> PackedScene, null for a model not installed
var _material: StandardMaterial3D
var _slice_y := SliceController.MAX_SLICE_Y


func _init() -> void:
	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true
	_material.roughness = 1.0
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED


func _process(_delta: float) -> void:
	for i in range(mini(budget, _queue.size())): _build(_queue.pop_back())


## What a tile shows from now on; "" for nothing.
func set_tile(cell: Vector3i, model: String) -> void:
	if String(_wanted.get(cell, "")) == model: return
	if model.is_empty(): _wanted.erase(cell)
	else: _wanted[cell] = model
	if not _queued.has(cell):
		_queued[cell] = true
		_queue.append(cell)


func model_of(cell: Vector3i) -> String:
	return String(_wanted.get(cell, ""))


## The node a tile shows now, or null: built tiles only.
func node_of(cell: Vector3i) -> Node3D:
	return _nodes.get(cell)


## Builds everything asked for at once: for a capture or a test that cannot wait frames.
func flush() -> void:
	while not _queue.is_empty(): _build(_queue.pop_back())


func apply_slice(y: int) -> void:
	_slice_y = y
	for cell: Vector3i in _nodes:
		(_nodes[cell] as Node3D).visible = cell.y <= y


func _build(cell: Vector3i) -> void:
	_queued.erase(cell)
	var model := String(_wanted.get(cell, ""))
	if String(_shown.get(cell, "")) == model and (model.is_empty() or _nodes.has(cell)): return
	if _nodes.has(cell):
		var old: Node3D = _nodes[cell]
		old.visible = false
		old.queue_free()
		_nodes.erase(cell)
	_shown.erase(cell)
	if model.is_empty(): return
	if not _models.has(model): _models[model] = load(model) if ResourceLoader.exists(model) else null
	var packed := _models[model] as PackedScene
	if packed == null: return
	var body := Node3D.new()
	body.name = "Tile_%d_%d_%d" % [cell.x, cell.y, cell.z]
	body.position = Vector3(cell) + Vector3(.5, 1, .5)
	body.add_child(packed.instantiate())
	for mesh in Shadows.visual_meshes(body): mesh.material_override = _material
	add_child(body)
	body.visible = cell.y <= _slice_y
	Lighting.bind_world_tree(body)
	_nodes[cell] = body
	_shown[cell] = model
