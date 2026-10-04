extends "res://scripts/components/DwarfWorkToolPose.gd"

## Long-haft pick for the existing five-up/one-down mining reach envelope.
const PICK_POINT := Vector3(0,1.375,.9375)
const CONTACT_PHASE := .92
var pickaxe: Node3D:
	get: return tool


static func contact_point(block: Vector3i, feet: Vector3, forward: Vector3) -> Vector3:
	var base := Vector3(block)
	if floori(feet.x) == block.x and floori(feet.z) == block.z:
		# Underfoot: top face, just ahead of the feet rather than block centre.
		return Vector3(feet.x,base.y+1.0,feet.z) + forward*.28
	var point := Vector3(clampf(feet.x,base.x,base.x+1),
		clampf(feet.y+1.4,base.y+.15,base.y+.85),clampf(feet.z,base.z,base.z+1))
	# A small penetration keeps the point touching the rendered block face.
	var inward := Vector3(base.x+.5-point.x,0,base.z+.5-point.z).normalized()
	return point + inward*.025


func apply(phase: float, contact: Vector3) -> void:
	if not _ensure_tool(DwarfAssets.mining_pickaxe,"MiningPickaxe"):
		return
	tool.visible = true
	phase = clampf(phase,0,1)
	var low := clampf((1.4-contact.y)/2.6,0,1)
	var high := clampf((contact.y-1.4)/2.75,0,1)
	var stance := Vector3(0,-low*.20,minf(contact.z-1.4,0))
	var strike := _orientation(lerpf(lerpf(55,125,low),-25,high),40)
	var strike_grip := contact-strike*PICK_POINT
	var ready := _orientation(15,10)
	var raised := _orientation(-40,-10)
	var ready_grip := Vector3(-1.3,1.4+high*.6-low*.3,.45)+stance
	var raised_grip := Vector3(-1.25,2.0+high*.75-low*.3,-.05)+stance
	var grip: Vector3
	var rotation: Quaternion
	var effort: float
	if phase < .2:
		var t := smoothstep(0,.2,phase)
		grip = strike_grip.lerp(ready_grip,t)
		rotation = strike.slerp(ready,t)
		effort = 1.0-t
	elif phase < .55:
		var t := smoothstep(.2,.55,phase)
		grip = ready_grip.lerp(raised_grip,t)
		rotation = ready.slerp(raised,t)
		effort = -t
	elif phase < CONTACT_PHASE:
		var t := pow((phase-.55)/(CONTACT_PHASE-.55),2)
		grip = raised_grip.lerp(strike_grip,t)
		rotation = raised.slerp(strike,t)
		effort = lerpf(-1,1,t)
	else:
		grip = strike_grip
		rotation = strike
		effort = 1.0
	_pose_hand(_right,grip,rotation)
	_pose_hand(_left,grip+rotation*SUPPORT_GRIP,rotation*Quaternion(Vector3.UP,PI))
	if is_instance_valid(_body):
		_body.position = stance+Vector3(0,-absf(effort)*.04,0)
		_body.rotation = Vector3(low*.08+effort*.035,effort*.08,0)
	if is_instance_valid(_head):
		_head.position = stance+Vector3(0,-absf(effort)*.025,-.05*maxf(effort,0))
		_head.rotation = Vector3(low*.08-high*.08+effort*.025,0,0)
	for i in range(_feet.size()):
		if is_instance_valid(_feet[i]):
			_feet[i].position = Vector3(0,0,stance.z+(.12 if i == 0 else -.12))
