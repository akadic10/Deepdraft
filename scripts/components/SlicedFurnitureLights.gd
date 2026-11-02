extends RefCounted

## Lights the slice has cut away keep burning (doc 287). The slice still hides the whole piece,
## so it stays out of picking, the explorer and the fire sound; only its light leaves the hidden
## model for a holder beside it, once the renderer's shadow-only rock (SliceLightOccluders)
## covers the light's reach above the cut, so it cannot shine past a sliced-away wall. Until then,
## and for a light too far above the cut to reach anything shown, it stays dark as before. A
## light goes home when the slice shows its piece again or the piece is removed. Owned by
## FurniturePlacementController.

const Lighting = preload("res://scripts/components/FurnitureLighting.gd")
const HOME := &"sliced_light_home"
## Shadow rock for one chunk layer below the cut is built ahead, so a step down never leaves a
## light dark while its rock builds (each chunk takes about 0.7 ms).
const AHEAD := 16

var controller: Node3D
## Set when shadow rock arrives or a sliced light is installed; the owner refreshes next frame.
var dirty := false
## The terrain renderer; found like the camera finds it unless set (tests).
var renderer: Node
var _occluders: Node
var _holder: Node3D


func _init(owner: Node3D) -> void:
	controller = owner


## Sorts every installed light against the slice: home inside its piece, or lifted beside it.
func refresh(slice_y: int) -> void:
	dirty = false
	var occluders := _bind()
	var boxes: Array[AABB] = []
	var ahead: Array[AABB] = []
	var waiting: Array = []   # [piece node, light, reach]
	for piece: InstalledFurnitureComponent in controller.get_installed_pieces():
		if not is_instance_valid(piece.node): continue
		var light := Lighting.light_of(piece.node)
		if light == null: continue
		var soon := ahead_box(light, slice_y, AHEAD)
		if soon.has_volume(): ahead.append(soon)
		var reach := reach_box(light, slice_y)
		if piece.node.visible or occluders == null or not reach.has_volume():
			_home(piece.node, light)
			continue
		boxes.append(reach)
		waiting.append([piece.node, light, reach])
	_drop_orphans()
	if occluders == null: return
	occluders.request(boxes, ahead)
	for entry: Array in waiting:
		if occluders.covers(entry[2]): _lift(entry[0], entry[1])
		else: _home(entry[0], entry[1])


## Before a piece is torn down: its light goes back inside, dark at once and freed with it.
func removed(node: Node3D) -> void:
	if not is_instance_valid(node): return
	var light := Lighting.light_of(node)
	if light != null: _home(node, light)


## Where rock can stand between the light and anything the slice shows: within its range, from
## the cut up to the light (a ray from it never climbs back down). Empty when its range ends
## above the cut.
static func reach_box(light: OmniLight3D, slice_y: int) -> AABB:
	var at := light.global_position
	var bottom := float(slice_y + 1)
	if at.y - light.omni_range >= bottom or at.y <= bottom: return AABB()
	return _column(at, light.omni_range, bottom)


## The same for every cut down to `depth` below this one, lights below the cut included.
static func ahead_box(light: OmniLight3D, slice_y: int, depth: int) -> AABB:
	var at := light.global_position
	var bottom := maxf(float(slice_y + 1 - depth), at.y - light.omni_range)
	if at.y <= bottom: return AABB()
	return _column(at, light.omni_range, bottom)


static func _column(at: Vector3, radius: float, bottom: float) -> AABB:
	return AABB(Vector3(at.x - radius, bottom, at.z - radius), Vector3(radius * 2.0, at.y - bottom, radius * 2.0))


func _bind() -> Node:
	if is_instance_valid(_occluders): return _occluders
	if not is_instance_valid(renderer) and controller.is_inside_tree():
		renderer = controller.get_tree().get_first_node_in_group("terrain_overview_renderer")
	if not is_instance_valid(renderer): return null
	var found: Variant = renderer.get("light_occluders")
	if not is_instance_valid(found): return null
	_occluders = found
	_occluders.chunks_ready.connect(_mark_dirty)
	return _occluders


func _mark_dirty() -> void:
	dirty = true


func _lift(node: Node3D, light: OmniLight3D) -> void:
	if _holder == null:
		_holder = Node3D.new()
		_holder.name = "SlicedLights"
		controller.add_child(_holder)
	if light.get_parent() == _holder: return
	light.set_meta(HOME, weakref(node))
	light.reparent(_holder)
	_sync_flame(node)


func _home(node: Node3D, light: OmniLight3D) -> void:
	if light.get_parent() == node: return
	light.reparent(node)
	_sync_flame(node)


func _sync_flame(node: Node3D) -> void:
	var flame := node.get_node_or_null("FlameAnimation")
	if flame != null: flame.sync_visibility()


## A piece freed some other way must not leave its light burning in the holder.
func _drop_orphans() -> void:
	if _holder == null: return
	for light: Node in _holder.get_children():
		var home: WeakRef = light.get_meta(HOME) if light.has_meta(HOME) else null
		if home == null or not is_instance_valid(home.get_ref()): light.queue_free()
