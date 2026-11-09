extends "res://scripts/components/DwarfWorkToolPose.gd"

## Cosmetic only: the existing job owns work/progress; this rig owns pose.
## Hands retain their authored floating silhouettes and grip one rigid tool.
const CUTTING_EDGE := Vector3(0, 1.0625, .6875)
const CYCLE_SECONDS := 1.15
const CONTACT_PHASE := .54

var axe: Node3D:
	get: return tool
var _held: PackedScene


## A crafting career's own motion at the bench (doc 298), on the swing's timing, so the job and its
## sound are unchanged. Raised is measured from the strike: `raise` over the strike, or at `beside`
## from the body when the fist has to clear the head. `one_hand` leaves the free hand on the work.
const BENCH_MOTIONS := {
	"adze": {"raise":Vector3(-.35,.4,.15),"pitch":25.0,"yaw":25.0,"strike_pitch":75.0,"strike_yaw":40.0,"effort":.55,"one_hand":false},
	"tap": {"raise":Vector3(-.3,.25,.1),"pitch":42.0,"yaw":30.0,"strike_pitch":65.0,"strike_yaw":40.0,"effort":.3,"one_hand":true},
	"blow": {"raise":Vector3(0,1.05,-.45),"beside":-1.3,"pitch":-38.0,"yaw":-6.0,"strike_pitch":72.0,"strike_yaw":45.0,"effort":1.0,"one_hand":true},
}


func apply_bench(phase: float, contact: Vector3, held: PackedScene, motion: String) -> void:
	if not BENCH_MOTIONS.has(motion):
		apply(phase,contact,held)
		return
	if not _hold_tool(held): return
	phase = fposmod(phase,1.0)
	var shape: Dictionary = BENCH_MOTIONS[motion]
	var stance := Vector3(0,0,minf(contact.z-STANCE_REACH,0.0))
	var strike := _orientation(float(shape.strike_pitch),float(shape.strike_yaw))
	var raised := _orientation(float(shape.pitch),float(shape.yaw))
	var strike_grip := contact-strike*CUTTING_EDGE
	var raised_grip: Vector3 = strike_grip+(shape.raise as Vector3)
	if shape.has("beside"): raised_grip.x = float(shape.beside)
	var grip: Vector3
	var rotation: Quaternion
	var effort: float
	if phase < .36:
		var t := smoothstep(0.0,.3,phase)   # up, then a short pause at the top
		grip = strike_grip.lerp(raised_grip,t)
		rotation = strike.slerp(raised,t)
		effort = -t
	elif phase < CONTACT_PHASE:
		var t := pow((phase-.36)/(CONTACT_PHASE-.36),2.0)
		grip = raised_grip.lerp(strike_grip,t)
		rotation = raised.slerp(strike,t)
		effort = lerpf(-1.0,1.0,t)
	else:
		# It rests on the work and eases off, ready for the next stroke.
		var t := smoothstep(.62,1.0,phase)
		grip = strike_grip+Vector3(0,.07,-.05)*t
		rotation = strike
		effort = 1.0-t
	var amount := float(shape.effort)
	_pose_hand(_right,grip,rotation)
	if shape.one_hand:
		_pose_hand(_left,contact+Vector3(.42,.12,-.2)+Vector3(0,-.02,0)*maxf(effort,0.0),Quaternion.IDENTITY)
	else:
		_pose_hand(_left,grip+rotation*SUPPORT_GRIP,rotation*Quaternion(Vector3.UP,PI))
	if is_instance_valid(_body):
		_body.position = stance+Vector3(0,-absf(effort)*.035*amount,0)
		_body.rotation = Vector3(.05+effort*.05*amount,effort*.12*amount,0)
	if is_instance_valid(_head):
		_head.position = stance+Vector3(0,-absf(effort)*.025*amount,-.06*maxf(effort,0.0)*amount)
		_head.rotation = Vector3(.12+effort*.035*amount,0,0)   # eyes on the work
	for i in range(_feet.size()):
		if is_instance_valid(_feet[i]):
			_feet[i].position = stance+Vector3(0,0,.12 if i == 0 else -.12)


func _hold_tool(held: PackedScene) -> bool:
	if held != _held and is_instance_valid(tool):
		tool.free()   # a fresh tool takes the axe's node name at once
		tool = null
	_held = held
	if not _ensure_tool(held,"FellingAxe"): return false
	axe.visible = true
	return true


## `held`: the tool this swing holds in place of the axe, a crafting career's own (doc 293: the
## Carpenter's stone adze, the Stonemason's maul). Each strikes at the axe's CUTTING_EDGE.
func apply(phase: float, contact: Vector3, held: PackedScene = null) -> void:
	if held == null: held = DwarfAssets.felling_axe
	if not _hold_tool(held): return
	phase = fposmod(phase, 1.0)
	# Small trunks can be closer than the dwarf's large head/beard. Settle the
	# visual stance back, without moving its logical navigation/collision cell.
	var stance := Vector3(0,0,minf(contact.z - STANCE_REACH, 0.0))
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


