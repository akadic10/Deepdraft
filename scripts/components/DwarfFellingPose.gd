extends "res://scripts/components/DwarfWorkToolPose.gd"

## Cosmetic only: the existing job owns work/progress; this rig owns pose.
## Hands retain their authored floating silhouettes and grip one rigid tool.
const CUTTING_EDGE := Vector3(0, 1.0625, .6875)
const CYCLE_SECONDS := 1.15
const CONTACT_PHASE := .54

var axe: Node3D:
	get: return tool


func apply(phase: float, contact: Vector3) -> void:
	if not _ensure_tool(DwarfAssets.felling_axe,"FellingAxe"):
		return
	axe.visible = true
	phase = fposmod(phase, 1.0)
	# Small trunks can be closer than the dwarf's large head/beard. Settle the
	# visual stance back, without moving its logical navigation/collision cell.
	var stance := Vector3(0,0,minf(contact.z - 1.4, 0.0))
	var ready := _orientation(25,15)
	var raised := _orientation(-35,-15)
	var strike := _orientation(70,65)
	var ready_grip := Vector3(-1.25,1.25,.65) + stance
	var raised_grip := Vector3(-1.4,1.55,.15) + stance
	var strike_grip := contact - strike * CUTTING_EDGE
	var grip: Vector3
	var rotation: Quaternion
	var effort: float
	if phase < .36:
		var t := smoothstep(0.0,.36,phase)
		grip = ready_grip.lerp(raised_grip,t)
		rotation = ready.slerp(raised,t)
		effort = -t
	elif phase < CONTACT_PHASE:
		var t := pow((phase-.36)/(CONTACT_PHASE-.36),2.0)
		grip = raised_grip.lerp(strike_grip,t)
		rotation = raised.slerp(strike,t)
		effort = lerpf(-1.0,1.0,t)
	elif phase < .62:
		grip = strike_grip
		rotation = strike
		effort = 1.0
	else:
		var t := smoothstep(.62,1.0,phase)
		grip = strike_grip.lerp(ready_grip,t)
		rotation = strike.slerp(ready,t)
		effort = 1.0-t
	_pose_hand(_right,grip,rotation)
	_pose_hand(_left,grip + rotation * SUPPORT_GRIP,
		rotation * Quaternion(Vector3.UP,PI))
	if is_instance_valid(_body):
		_body.position = stance + Vector3(0,-absf(effort)*.035,0)
		_body.rotation = Vector3(effort*.025,effort*.12,effort*.025)
	if is_instance_valid(_head):
		_head.position = stance + Vector3(0,-absf(effort)*.025,-.06*maxf(effort,0.0))
		_head.rotation = Vector3(effort*.035,-effort*.035,0)
	for i in range(_feet.size()):
		if is_instance_valid(_feet[i]):
			_feet[i].position = stance + Vector3(0,0,.12 if i == 0 else -.12)


