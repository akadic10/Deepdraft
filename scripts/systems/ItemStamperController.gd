extends Node3D

## The DEV item stamper's tool (doc 23, "The item stamper"). While it is on, a click on a
## floor puts the chosen item there, as play makes it:
## - goods land as one pile of the amount through ItemDropManager, as crafting drops them,
##   and dwarves carry them to storage;
## - uprooted bushes come through the flora owner, one to a floor around the click, so each
##   keeps its record as play's do.
## Some items keep a record a stamp cannot make, so they cannot be stamped (refusal()).
## ItemStamperPanel chooses the item, the amount and the wood; the tool bar's Done, or Esc,
## ends stamping (doc 23, "The tool bar"). It only works with DEV tools on.
const Picking = preload("res://scripts/components/ObjectPicking.gd")
const RAY_MAX := 600.0
const FLAG_ITEM := "base:resources:special:settlement_flag"
## How far around the clicked floor bushes look for room, in floors.
const BUSH_REACH := 6
const NO_FLOOR := Vector3i(-1, -1, -1)
@export var dock_path: NodePath
@export var slice_path: NodePath
signal tool_active_changed(active: bool)
## A stamp landed: the item, how many, and the floor it stands on.
signal stamped(key: String, count: int, floor: Vector3i)
## What a stamp did, for the tool bar.
signal order_feedback(message: String)
## The chosen item, how many a click puts down, and its wood ("" for none).
var key := ""
var amount := 1
var material := ""
var _active := false
var _slice: Node
var _marker: MeshInstance3D


func _ready() -> void:
	add_to_group("item_stamper")
	set_process(false)
	_slice = get_node_or_null(slice_path) if not slice_path.is_empty() else null
	_marker = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.96, 0.06, 0.96)
	var look := StandardMaterial3D.new()
	look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	look.albedo_color = Color(UIRegistry.get_icon_family_color("dev"), 0.6)
	_marker.mesh = box
	_marker.material_override = look
	_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marker.visible = false
	add_child(_marker)
	var dock := get_node_or_null(dock_path) if not dock_path.is_empty() else null
	if dock == null or not UIRegistry.dev_tools_enabled: return
	dock.tool_requested.connect(_on_tool_requested)
	dock.register_item_stamper(self)


func is_active() -> bool:
	return _active


## What the tool bar shows (doc 23, "The tool bar"): the item being stamped with its
## picture, in the DEV family. A stamp merges into a pile, so there is no Undo (doc 23).
func tool_bar_state() -> Dictionary:
	var definition: Dictionary = ContentRegistry.item_def(key)
	var picture := "res://assets/ui/items/%s.png" % key.replace(":", "_")
	if not ResourceLoader.exists(picture): picture = "res://assets/ui/furniture/%s.png" % key.get_slice(":", key.get_slice_count(":") - 1)
	return {"tool": "item_stamper", "family": "dev", "undo": false, "picture": picture,
		"name": "Stamp · %s" % String(definition.get("display_name", key))}


## Stamping starts once an item that can be stamped is chosen.
func activate() -> void:
	if _active or not refusal(key).is_empty(): return
	_active = true
	set_process(true)
	tool_active_changed.emit(true)


func deactivate() -> void:
	if not _active: return
	_active = false
	set_process(false)
	_marker.visible = false
	tool_active_changed.emit(false)


## The window's choice: the item, how many a click puts down, and its wood.
func choose(item: String, count: int, wood: String) -> void:
	key = item
	amount = maxi(count, 1)
	material = wood
	if not refusal(key).is_empty(): deactivate()


## Why an item cannot be stamped, or "" when it can. These keep a record elsewhere that a
## stamp could not make.
static func refusal(item: String) -> String:
	var definition: Dictionary = ContentRegistry.item_def(item)
	if definition.is_empty(): return "Choose an item to stamp."
	if definition.has("water_stone"): return "Water stones belong to the river: pack one to move it."
	if definition.has("plant_definition") \
			and SurfaceDetailRegistry.get_definition(String(definition.plant_definition)).get("kind") != "shrub":
		return "Wildflowers keep a record with the land: uproot one to carry it."
	if item == FLAG_ITEM: return "The colony has one flag."
	return ""


func _on_tool_requested(tool_id: String) -> void:
	if tool_id != "item_stamper": deactivate()


func _process(_delta: float) -> void:
	var floor := floor_under(get_viewport().get_mouse_position())
	_marker.visible = floor != NO_FLOOR and get_viewport().gui_get_hovered_control() == null
	if _marker.visible: _marker.position = Vector3(floor) + Vector3(0.5, 1.03, 0.5)


func _unhandled_input(event: InputEvent) -> void:
	if not _active: return
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_ESCAPE:
		deactivate()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var floor := floor_under(event.position)
		if floor != NO_FLOOR: stamp_at(floor)
		get_viewport().set_input_as_handled()


## The floor a pile would stand on under a screen point: the block the pointer shows under
## the slice, or the floor below the air beside the face it shows. NO_FLOOR for none.
func floor_under(screen_pos: Vector2) -> Vector3i:
	var camera := get_viewport().get_camera_3d()
	var drops := ItemDropManager.find(get_tree())
	if camera == null or drops == null: return NO_FLOOR
	var cut := int(_slice.get_slice_y()) if _slice != null and bool(_slice.is_active()) else SliceController.MAX_SLICE_Y
	var hit := Picking.terrain_hit(camera.project_ray_origin(screen_pos), camera.project_ray_normal(screen_pos).normalized(), cut, RAY_MAX)
	if hit.is_empty(): return NO_FLOOR
	var air := Vector3i(int(hit.x), int(hit.y), int(hit.z)) + Vector3i(hit.normal)
	return Vector3i(air.x, drops.floor_rest_y(air) - 1, air.z)


## Puts the chosen item on `floor`: goods as one pile of the amount, bushes one to a floor
## around it. Returns how many it put down.
func stamp_at(floor: Vector3i) -> int:
	var drops := ItemDropManager.find(get_tree())
	if drops == null or not refusal(key).is_empty(): return 0
	var definition: Dictionary = ContentRegistry.item_def(key)
	var count := 0
	if definition.has("plant_definition"):
		var flora := get_tree().get_first_node_in_group("surface_details")
		for stand: Vector3i in _floors_around(floor, amount):
			if flora != null and not String(flora.dev_spawn_packed_shrub(String(definition.plant_definition), stand)).is_empty():
				count += 1
	else:
		drops.spawn_drop(key, amount, floor + Vector3i.UP, material)
		count = amount
	if count > 0:
		stamped.emit(key, count, floor)
		order_feedback.emit("Stamped %d %s at %d, %d, %d" % [count,
			String(definition.get("display_name", key)), floor.x, floor.y + 1, floor.z])
	return count


## Up to `wanted` dry floors a dwarf can stand on, nearest the centre first.
func _floors_around(center: Vector3i, wanted: int) -> Array[Vector3i]:
	var floors: Array[Vector3i] = []
	for ring in range(BUSH_REACH + 1):
		for dx in range(-ring, ring + 1):
			for dz in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dz)) != ring or floors.size() >= wanted: continue
				var stand := center + Vector3i(dx, 0, dz)
				if NavGrid.is_walkable(stand) and not WaterManager.has_standing_water(stand + Vector3i.UP): floors.append(stand)
	return floors
