extends "res://scripts/components/DwarfWorkToolPose.gd"

## Reuse the authored stone hammer, held upright by the existing floating fists.
const HAMMER = preload("res://assets/models/items/tools/stone_hammer.glb")
const CYCLE_SECONDS := 1.0
const CONTACT_PHASE := .72
const MODEL_GRIP := Vector3(0,.16,-.40)
const MODEL_POINT := Vector3(.40,.25,.24)
const MODEL_SCALE := 1.1
var _stance := Vector3.ZERO
var _stance_ready := false

func prepare_stance(near_face: Vector3) -> void:
	if _stance_ready: return
	_stance = Vector3(0,0,minf(near_face.z-MODEL_POINT.x*MODEL_SCALE-.65,0))
	_stance_ready = true

func reset() -> void:
	super.reset()
	_stance_ready = false
	_stance = Vector3.ZERO

static func contact_point(block: Vector3i, feet: Vector3, forward: Vector3) -> Vector3:
	var base := Vector3(block)
	# Low masonry is struck on top, leaving room for the handle and both hands.
	if base.y+1.0 <= feet.y+1.1:
		var toward := feet+forward*1.25
		return Vector3(clampf(toward.x,base.x+.18,base.x+.82),base.y+1.0,
			clampf(toward.z,base.z+.18,base.z+.82))
	return preload("DwarfMiningPose.gd").contact_point(block,feet,forward)

static func contact_normal(block: Vector3i, contact: Vector3) -> Vector3:
	var offset := contact-(Vector3(block)+Vector3.ONE*.5)
	var axis := offset.abs().max_axis_index()
	var normal := Vector3.ZERO
	normal[axis] = signf(offset[axis])
	return normal

func apply(phase: float, contact: Vector3, inward: Vector3) -> void:
	if not _ensure_tool(HAMMER,"ConstructionHammer"): return
	var model_basis := Basis(Vector3.RIGHT,-PI/2)*MODEL_SCALE
	var local_basis: Basis = (_rest[_right] as Transform3D).basis.inverse()*model_basis
	tool.transform = Transform3D(local_basis,PALM-local_basis*MODEL_GRIP)
	tool.show()
	phase = fposmod(phase,1.0)
	# The authored hammer strikes with its +X end; after the model rotation its
	# shaft points +Y. Align the end squarely into the face, never broadside.
	var face := inward.normalized()
	var shaft := Vector3.UP.slide(face)
	if shaft.length_squared()<.001: shaft = Vector3.BACK.slide(face)
	shaft = shaft.normalized()
	var strike := Basis(face,shaft,face.cross(shaft)).get_rotation_quaternion()
	var raised := strike*Quaternion(Vector3.BACK,deg_to_rad(75))
	var ready := strike*Quaternion(Vector3.BACK,deg_to_rad(20))
	var point := model_basis*(MODEL_POINT-MODEL_GRIP)
	var hit_grip := contact-strike*point
	# Clearance is anchored once on arrival, not recomputed for each block.
	var stance := _stance
	var high := clampf(contact.y-1.6,0,2.5)
	var low := clampf(1.1-contact.y,0,1)
	var rest_grip := Vector3(-.8,1.4+high*.55-low*.2,.45)+stance
	var up_grip := Vector3(-.8,2.0+high*.6-low*.2,.10)+stance
	var grip: Vector3
	var rotation: Quaternion
	if phase < .38:
		var t := smoothstep(0,.38,phase)
		grip = rest_grip.lerp(up_grip,t)
		rotation = ready.slerp(raised,t)
	elif phase < CONTACT_PHASE:
		var t := pow((phase-.38)/(CONTACT_PHASE-.38),2)
		grip = up_grip.lerp(hit_grip,t)
		rotation = raised.slerp(strike,t)
	else:
		var t := smoothstep(.80,1,phase)
		grip = hit_grip.lerp(rest_grip,t)
		rotation = strike.slerp(ready,t)
	_pose_hand(_right,grip,rotation)
	_pose_hand(_left,grip+rotation*Vector3(0,.25,0),rotation*Quaternion(Vector3.UP,PI))
	var effort := sin(phase*PI)
	if is_instance_valid(_body):
		_body.position = stance+Vector3(0,-low*.10-effort*.035,0)
		_body.rotation = Vector3(low*.05+effort*.03,effort*.04,0)
	if is_instance_valid(_head):
		_head.position = stance+Vector3(0,-low*.08-effort*.025,0)
		_head.rotation = Vector3(low*.07-high*.04,0,0)
	for foot in _feet:
		if is_instance_valid(foot): foot.position = stance
