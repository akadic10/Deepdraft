extends "res://scripts/components/DwarfWorkToolPose.gd"

## The build hammer (doc 298): one-handed, raised out beside the big head and struck on the dwarf's
## right, with the free hand steadying the block. Cosmetic: the job owns timing and progress.
const HAMMER = preload("res://assets/models/items/tools/stone_hammer.glb")
const CYCLE_SECONDS := 1.0
const CONTACT_PHASE := .72
const MODEL_GRIP := Vector3(0,.16,-.40)
const MODEL_POINT := Vector3(.375,.25,.25)
const MODEL_SCALE := 1.1
const STRIKE_RIGHT := .3
const NECK := Vector3(0,1.8125,0)
const RAISED_PHASE := .3
const COCKED_PHASE := .44
const HOLD_PHASE := .75    # the head rests on the block, then bounces off
const REBOUND_PHASE := .8
var _stance := Vector3.ZERO
var _stance_ready := false

func prepare_stance(near_face: Vector3) -> void:
	if _stance_ready: return
	_stance = Vector3(0,0,minf(near_face.z-stand_reach(),0))
	_stance_ready = true

## How far from the block's face the builder stands, and how far short a walk to it stops.
static func stand_reach() -> float:
	return MODEL_POINT.x*MODEL_SCALE+.85

func reset() -> void:
	super.reset()
	_stance_ready = false
	_stance = Vector3.ZERO

static func contact_point(block: Vector3i, feet: Vector3, forward: Vector3) -> Vector3:
	var base := Vector3(block)
	var right := forward.cross(Vector3.UP)*STRIKE_RIGHT
	# Low masonry is struck on top, leaving room for the handle and both hands.
	if base.y+1.0 <= feet.y+1.1:
		var toward := feet+forward*1.25+right
		return Vector3(clampf(toward.x,base.x+.18,base.x+.82),base.y+1.0,
			clampf(toward.z,base.z+.18,base.z+.82))
	# Across the face only: the point stays on the face the mining rule found.
	var point: Vector3 = preload("DwarfMiningPose.gd").contact_point(block,feet,forward)+right
	if absf(right.x) > absf(right.z): point.x = clampf(point.x,base.x+.18,base.x+.82)
	else: point.z = clampf(point.z,base.z+.18,base.z+.82)
	return point

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
	var face := inward.normalized()
	# The handle leans in from the right hand, so the fist stays clear of the body at the strike.
	var across := Vector3.RIGHT.slide(face)
	if across.length_squared() < .001: across = Vector3.BACK.slide(face)
	across = across.normalized()
	var along := Vector3.UP.slide(face)
	if along.length_squared() < .001: along = Vector3.BACK.slide(face)
	var strike := _frame(face,along.normalized()*.75+across*.65)
	var ready := _frame(Vector3.BACK,Vector3(-.2,.95,.25))
	var raised := _frame(Vector3.BACK+Vector3.UP,Vector3(-.5,.8,-.3))
	var cocked := _frame(Vector3.BACK+Vector3.UP*1.5,Vector3(-.55,.7,-.45))
	var stance := _stance
	var high := clampf(contact.y-1.6,0,2.5)
	var low := clampf(1.1-contact.y,0,1)
	var hit_grip := contact-strike*(model_basis*(MODEL_POINT-MODEL_GRIP))
	var ready_grip := Vector3(-1.2,1.3+high*.5-low*.2,.75)+stance
	var raised_grip := Vector3(-1.6,2.35+high*.6-low*.25,.45)+stance
	var cocked_grip := raised_grip+Vector3(-.05,.15,-.08)
	var grip: Vector3
	var rotation: Quaternion
	var effort: float
	if phase < RAISED_PHASE:
		var t := smoothstep(0,RAISED_PHASE,phase)
		grip = ready_grip.lerp(raised_grip,t)
		rotation = ready.slerp(raised,t)
		effort = -t
	elif phase < COCKED_PHASE:
		var t := smoothstep(RAISED_PHASE,COCKED_PHASE,phase)
		grip = raised_grip.lerp(cocked_grip,t)
		rotation = raised.slerp(cocked,t)
		effort = -1.0
	elif phase < CONTACT_PHASE:
		var t := pow((phase-COCKED_PHASE)/(CONTACT_PHASE-COCKED_PHASE),3)
		grip = cocked_grip.lerp(hit_grip,t)
		rotation = cocked.slerp(strike,t)
		effort = lerpf(-1,1,t)
	elif phase < REBOUND_PHASE:
		var t := maxf(phase-HOLD_PHASE,0)/(REBOUND_PHASE-HOLD_PHASE)
		grip = hit_grip-face*sin(t*PI)*.06
		rotation = strike
		effort = 1.0
	else:
		var t := smoothstep(REBOUND_PHASE,1,phase)
		grip = hit_grip.lerp(ready_grip,t)
		rotation = strike.slerp(ready,t)
		effort = 1.0-t
	_pose_hand(_right,grip,rotation)
	# The free hand steadies the block beside the strike, and takes a little of each blow.
	var flat := .18 if absf(face.y) > .5 else .3   # the fist's depth, on top of a block or against its side
	_pose_hand(_left,contact+across*.7-face*flat+face*maxf(effort,0)*.03,Quaternion.IDENTITY)
	var impact := maxf(effort,0)
	if is_instance_valid(_body):
		_body.position = stance+Vector3(0,-low*.10-absf(effort)*.04,0)
		_body.rotation = Vector3(low*.05+effort*.05,effort*.10,-effort*.02)
	if is_instance_valid(_head):
		_head.rotation = Vector3(low*.07-high*.07+effort*.04,-.1+effort*.04,0)
		# About the neck: the head looks up and across without leaving the shoulders.
		_head.position = stance+Vector3(0,-low*.08-absf(effort)*.03,-high*.1-impact*.04)+NECK-_head.basis*NECK
	for i in range(_feet.size()):
		if is_instance_valid(_feet[i]): _feet[i].position = stance+Vector3(0,0,.12 if i == 0 else -.12)


## The hammer's turn: `face` is where its striking end points, `shaft` where the handle runs.
func _frame(face: Vector3, shaft: Vector3) -> Quaternion:
	var up := shaft.normalized()
	var front := face.slide(up).normalized()
	return Basis(front,up,front.cross(up)).get_rotation_quaternion()
