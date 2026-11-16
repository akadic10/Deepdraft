extends "res://scripts/components/DwarfWorkToolPose.gd"

## The Farmer's hoe (doc 309): raised, chopped into the ground a step ahead, then drawn back
## through the soil toward the feet. Cosmetic only: the field's job owns the work and its
## progress, and this rig owns the pose. Hands keep their floating silhouettes and grip one
## rigid tool, the right hand at its foot and the left up the haft.
const HOE_EDGE := Vector3(0, 1.375, .625)   # the blade's edge: tool cell (0, 22, 10)
const CYCLE_SECONDS := 1.1
const CONTACT_PHASE := .5
## How far the blade is drawn back through the soil after it bites.
const DRAW := Vector3(0, .03, -.32)

var hoe: Node3D:
	get: return tool
var _held: PackedScene


## `held`: the hoe's model (DwarfAssets.field_tool). `contact`: where the blade bites, in the
## dwarf's own frame, facing it.
func apply(phase: float, contact: Vector3, held: PackedScene) -> void:
	if held == null: return
	if held != _held and is_instance_valid(tool):
		tool.free()   # a fresh tool takes the node's name at once
		tool = null
	_held = held
	if not _ensure_tool(held, "FieldHoe"): return
	tool.visible = true
	phase = fposmod(phase, 1.0)
	# Ground a step ahead is closer than the swing's reach: the body settles back, without moving
	# its logical cell.
	var stance := Vector3(0, 0, minf(contact.z - STANCE_REACH, 0.0))
	# The haft reaches over the spot and the blade comes down behind it, so the fists stay well
	# out in front of the belly; raised, they go beside the big head, as the axe's do.
	var strike := _orientation(138, 8)
	var drawn := _orientation(132, 5)
	var raised := _orientation(30, -12)
	var strike_grip := contact - strike * HOE_EDGE
	var drawn_grip := contact + DRAW - drawn * HOE_EDGE
	var raised_grip := Vector3(-1.25, 1.7, .25) + stance
	var grip: Vector3
	var rotation: Quaternion
	var effort: float
	if phase < .3:
		var t := smoothstep(0.0, .3, phase)   # lifted out of the soil and back over the shoulder
		grip = drawn_grip.lerp(raised_grip, t)
		rotation = drawn.slerp(raised, t)
		effort = -t
	elif phase < CONTACT_PHASE:
		var t := pow((phase - .3) / (CONTACT_PHASE - .3), 2.0)
		grip = raised_grip.lerp(strike_grip, t)
		rotation = raised.slerp(strike, t)
		effort = lerpf(-1.0, 1.0, t)
	elif phase < .85:
		var t := smoothstep(CONTACT_PHASE, .85, phase)   # the blade is drawn back through the soil
		grip = strike_grip.lerp(drawn_grip, t)
		rotation = strike.slerp(drawn, t)
		effort = 1.0 - t * .4
	else:
		grip = drawn_grip
		rotation = drawn
		effort = .6 * (1.0 - smoothstep(.85, 1.0, phase))
	_pose_hand(_right, grip, rotation)
	_pose_hand(_left, grip + rotation * SUPPORT_GRIP, rotation * Quaternion(Vector3.UP, PI))
	if is_instance_valid(_body):
		_body.position = stance + Vector3(0, -absf(effort) * .04, 0)
		_body.rotation = Vector3(.05 + maxf(effort, 0.0) * .09, effort * .1, 0)
	if is_instance_valid(_head):
		_head.position = stance + Vector3(0, -absf(effort) * .03, -.05 * maxf(effort, 0.0))
		_head.rotation = Vector3(.14 + maxf(effort, 0.0) * .04, 0, 0)   # eyes on the ground
	for i in range(_feet.size()):
		if is_instance_valid(_feet[i]):
			_feet[i].position = stance + Vector3(0, 0, .12 if i == 0 else -.12)
