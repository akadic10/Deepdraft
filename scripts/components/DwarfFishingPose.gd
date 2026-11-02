extends "res://scripts/components/DwarfWorkToolPose.gd"

## Fishing (doc 289): one catch's poses on the real rig, across the whole catch (phase 0 to 1).
## - Cast (to 0.08): the rod back over the shoulder and the free hand at the water, then the
##   swing out while the float flies to the water.
## - Wait (to 0.86): the rod out over the water about 30° up, nodding; the float bobs.
## - Bite (to 0.93): the tip dragged down and shaking, the float under.
## - Land: the rod swung up with the catch hanging from the line, a Ranger's big fish bigger.
## The right hand grips the rod at its origin and the left SUPPORT_GRIP up it (the work-tool
## contract). The line, the float and the catch stand in the world beside the dwarf. All is
## cosmetic: the catch's progress is the spot's, and nothing here is saved.
const CAST_END := 0.08
const BITE_START := 0.86
const BITE_END := 0.93
const LANDED := BITE_END + 0.02   # the fish is out of the water
const LINE := Color("d8cfb4")
## The concept's frames (tmp/fishing_concepts_20261031): grip, pitch, yaw, lean, look.
const POSES := {
	"cast": {"grip": Vector3(-0.45, 1.95, 0.05), "pitch": -38.0, "yaw": -18.0, "lean": -0.10, "look": -0.08},
	"wait": {"grip": Vector3(-0.3, 1.25, 0.6), "pitch": 60.0, "yaw": -6.0, "lean": 0.0, "look": 0.10},
	"bite": {"grip": Vector3(-0.3, 1.12, 0.78), "pitch": 76.0, "yaw": -4.0, "lean": 0.10, "look": 0.22},
	"land": {"grip": Vector3(-0.35, 1.6, 0.45), "pitch": 32.0, "yaw": -22.0, "lean": -0.08, "look": -0.12},
}

## The fish this catch lands (an item key; the spot's water decides it), hung on the line, and
## whether it is a Ranger's big fish, which hangs as its own heavier model (doc 292).
var catch_item := "base:resources:fish:perch"
var catch_big := false
var _props: Node3D
var _line: MeshInstance3D
var _float: Node3D
var _catch: Node3D
var _catch_shown := ""
var _tip := Vector3(0, 2.6, 0)     # the rod's tip in its own space, measured when first held
var _float_waterline := 0.18       # how far the float sits in the water
var _float_tie := 0.45             # where the line ties on, above the float's origin


## Poses the dwarf for this point of the catch; `contact` is the float's place on the water,
## in the dwarf's own space (as the felling pose takes its trunk contact).
func apply(phase: float, contact: Vector3) -> void:
	if not _ensure_tool(DwarfAssets.fishing_rod, "FishingRod"): return
	if not is_instance_valid(_props): _build_props()
	tool.visible = true
	_props.visible = true
	phase = clampf(phase, 0.0, 1.0)
	var agent := _body.get_parent() as Node3D
	var water: Vector3 = agent.to_global(contact)
	var pose: Dictionary
	var pointing := false
	if phase < CAST_END * 0.4:
		pose = POSES.cast
		pointing = true
	elif phase < CAST_END:
		pose = _blend(POSES.cast, POSES.wait, smoothstep(CAST_END * 0.4, CAST_END, phase))
	elif phase < BITE_START:
		pose = POSES.wait.duplicate()
		pose.pitch += sin(phase * 140.0) * 1.5     # the rod nods while waiting
	elif phase < BITE_END:
		pose = _blend(POSES.wait, POSES.bite, smoothstep(BITE_START, BITE_START + 0.02, phase))
		pose.pitch += sin(phase * 900.0) * 3.0     # the tip shakes with the bite
	else:
		pose = _blend(POSES.bite, POSES.land, smoothstep(BITE_END, 1.0, phase))
	_hold(pose, pointing)
	var tip: Vector3 = tool.global_transform * _tip
	# The float: on the rod while winding up, flying out, bobbing, then pulled under.
	var resting := Vector3(water.x, water.y - _float_waterline, water.z)
	var float_at := resting
	if phase < CAST_END * 0.4:
		float_at = tip + Vector3(0, -0.6, 0)
	elif phase < CAST_END:
		var t := smoothstep(CAST_END * 0.4, CAST_END, phase)
		float_at = (tip + Vector3(0, -0.6, 0)).lerp(resting, t) + Vector3(0, sin(t * PI) * 0.8, 0)
	elif phase < BITE_START:
		float_at.y += sin(phase * 220.0) * 0.02
	elif phase < LANDED:
		float_at.y -= 0.32
	var landed := phase >= LANDED
	if landed and _catch_shown != _catch_key(): _hang_catch()
	_float.visible = not landed
	_catch.visible = landed
	_float.global_position = float_at
	var end := float_at + Vector3(0, _float_tie, 0)
	if landed:
		var forward := -agent.global_basis.z
		_catch.global_position = tip + Vector3(0, -0.9, 0) - forward * 0.2
		_catch.global_rotation = Vector3(0, agent.global_rotation.y + PI / 2, 0)
		end = _catch.global_position
	_stretch(tip, end)


func reset() -> void:
	super.reset()
	if is_instance_valid(_props): _props.visible = false


func _hold(pose: Dictionary, pointing: bool) -> void:
	var rotation := _orientation(float(pose.pitch), float(pose.yaw))
	var grip: Vector3 = pose.grip
	_pose_hand(_right, grip, rotation)
	if pointing:   # the free hand points at the water while winding up
		_pose_hand(_left, Vector3(0.5, 1.45, 0.6), _orientation(95, 15))
	else:
		_pose_hand(_left, grip + rotation * SUPPORT_GRIP, rotation * Quaternion(Vector3.UP, PI))
	var lean := float(pose.lean)
	if is_instance_valid(_body):
		_body.position = (_rest[_body] as Transform3D).origin + Vector3(0, -absf(lean) * 0.2, lean * 0.4)
		_body.rotation = (_rest_rotations[_body] as Vector3) + Vector3(lean, 0, 0)
	if is_instance_valid(_head):
		_head.position = (_rest[_head] as Transform3D).origin + Vector3(0, -absf(lean) * 0.15, lean * 0.5)
		_head.rotation = (_rest_rotations[_head] as Vector3) + Vector3(float(pose.look), 0, 0)


func _blend(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	return {"grip": (a.grip as Vector3).lerp(b.grip, t), "pitch": lerpf(a.pitch, b.pitch, t), "yaw": lerpf(a.yaw, b.yaw, t),
		"lean": lerpf(a.lean, b.lean, t), "look": lerpf(a.look, b.look, t)}


## The line, the float and the catch live in the world (top level) under the dwarf, so they hide
## with it under the slice and go with it.
func _build_props() -> void:
	var agent := _body.get_parent() as Node3D
	_props = Node3D.new()
	_props.name = "FishingProps"
	_props.top_level = true
	agent.add_child(_props)
	_line = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.035, 1, 0.035)
	_line.mesh = box
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = LINE
	_line.material_override = material
	_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_props.add_child(_line)
	_float = DwarfAssets.fishing_float.instantiate() as Node3D
	_material(_float)
	_props.add_child(_float)
	_float_waterline = 3.0 / 16.0   # the float's model sits this deep (its third cell)
	_float_tie = _bounds(_float).end.y
	_catch = Node3D.new()
	_props.add_child(_catch)
	var rod := _bounds(tool)
	_tip = Vector3(rod.get_center().x, rod.end.y, rod.get_center().z)


## The catch's own fish on the line (perch until the art for another exists), big or not.
func _hang_catch() -> void:
	for child in _catch.get_children(): child.queue_free()
	var models: Dictionary = DwarfAssets.big_fish if catch_big else DwarfAssets.caught_fish
	var scene: PackedScene = models.get(catch_item, models["base:resources:fish:perch"])
	var fish := scene.instantiate() as Node3D
	_material(fish)
	_catch.add_child(fish)
	fish.rotation = Vector3(0, 0, -PI / 2)   # it lies along +X from its mouth: stood on end, hung by the mouth
	_catch_shown = _catch_key()


func _catch_key() -> String:
	return catch_item + (":big" if catch_big else "")


## A model's visible size in its own space, its shadow proxies left out.
func _bounds(node: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for child in node.find_children("*", "MeshInstance3D", true, false):
		if preload("res://scripts/components/VoxelShadowSetup.gd").is_proxy(child): continue
		var box: AABB = node.global_transform.affine_inverse() * (child as MeshInstance3D).global_transform * (child as MeshInstance3D).get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result


func _stretch(from: Vector3, to: Vector3) -> void:
	var span := to - from
	if span.length() < 0.01: return
	var up := span.normalized()
	var side := up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	_line.global_transform = Transform3D(Basis(side, up * span.length(), side.cross(up)), (from + to) / 2.0)
