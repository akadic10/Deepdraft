extends RefCounted

## Shared floating-hand attachment and safe mirrored-part restoration.
const PALM := Vector3(1.0625,1.25,.1875)
const SUPPORT_GRIP := Vector3(0,.625,0)
var tool: Node3D
var _body: Node3D
var _head: Node3D
var _left: Node3D
var _right: Node3D
var _feet: Array[Node3D] = []
var _rest: Dictionary = {}
var _rest_scales: Dictionary = {}
var _rest_rotations: Dictionary = {}


func setup(body: Node3D, head: Node3D, left: Node3D, right: Node3D,
		foot_left: Node3D, foot_right: Node3D) -> void:
	_body = body
	_head = head
	_left = left
	_right = right
	_feet = [foot_left,foot_right]
	for part in [body,head,left,right,foot_left,foot_right]:
		if is_instance_valid(part):
			_rest[part] = part.transform
			_rest_scales[part] = part.scale
			_rest_rotations[part] = part.rotation


func _ensure_tool(scene: PackedScene, node_name: String) -> bool:
	if not is_instance_valid(_right):
		return false
	if not is_instance_valid(tool):
		tool = scene.instantiate() as Node3D
		tool.name = node_name
		_right.add_child(tool)
		# Undo the right hand's reflection for the tool, not for the hand.
		tool.transform = Transform3D((_rest[_right] as Transform3D).basis.inverse(),PALM)
		_material(tool)
	return true


func reset() -> void:
	if is_instance_valid(tool):
		tool.visible = false
	for part in _rest:
		if is_instance_valid(part):
			# Explicit signed scale prevents reflected bases decomposing into
			# three negative scales and flipping when the gait writes Euler angles.
			part.rotation = _rest_rotations[part]
			part.scale = _rest_scales[part]
			part.position = (_rest[part] as Transform3D).origin


func _pose_hand(hand: Node3D, grip: Vector3, rotation: Quaternion) -> void:
	if is_instance_valid(hand):
		var basis := Basis(rotation) * (_rest[hand] as Transform3D).basis
		hand.transform = Transform3D(basis,grip-basis*PALM)


func _orientation(pitch: float, yaw: float) -> Quaternion:
	return Quaternion(Vector3.UP,deg_to_rad(yaw)) * Quaternion(Vector3.RIGHT,deg_to_rad(pitch))


func _material(node: Node) -> void:
	if node is MeshInstance3D:
		var material := StandardMaterial3D.new()
		material.vertex_color_use_as_albedo = true
		material.roughness = .85
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		(node as MeshInstance3D).material_override = material
	for child in node.get_children():
		_material(child)
