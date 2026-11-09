extends RefCounted

## What an idle dwarf does with its time (doc 298), chosen from the time alone so nothing is saved
## and a squad never moves together. Each slot of a few seconds holds one gesture or none. Hands use
## the side that the slot picked; +X is the dwarf's left.
const SLOT_SECONDS := 7.0
const BLINK_EVERY := 4.3
const BLINK_SECONDS := .13
const EASE := .9

## Share of slots for each kind; the rest stay still.
const SHIFT_UNTIL := .34
const LOOK_UNTIL := .52
const SCRATCH_UNTIL := .66
const BEARD_UNTIL := .78
const STRETCH_UNTIL := .86

const LENGTHS := {"shift":5.5,"look":4.0,"scratch":3.0,"beard":3.0,"stretch":4.0}
const SHIFT := .1
const LOOK := .55


static func at(t: float, dwarf_seed: int) -> Dictionary:
	var pose := {"shift":0.0,"roll":0.0,"lean":0.0,"nod":0.0,"rise":0.0,"look":0.0,"tilt":0.0,
		"left_reach":0.0,"right_reach":0.0,"left_grip":Vector3.ZERO,"right_grip":Vector3.ZERO}
	var slot := floori(t/SLOT_SECONDS)
	var roll := _roll(slot,dwarf_seed)
	var kind := _kind(roll)
	if kind.is_empty(): return pose
	var seconds := t-slot*SLOT_SECONDS
	var length: float = LENGTHS[kind]
	if seconds >= length: return pose
	var weight := smoothstep(0.0,EASE,seconds)*(1.0-smoothstep(length-EASE,length,seconds))
	var side := 1.0 if fmod(roll*97.0,1.0) < .5 else -1.0
	match kind:
		"shift":
			pose.shift = side*SHIFT*weight
			pose.roll = -side*.04*weight
		"look":
			pose.look = side*LOOK*weight
		"scratch":
			_reach(pose,side,Vector3(side*1.15,2.8+sin(t*13.0)*.05,.05),weight)
			pose.tilt = side*.09*weight
		"beard":
			_reach(pose,side,Vector3(side*.4,1.75+sin(t*11.0)*.04,.95),weight)
			pose.nod = -.08*weight
		"stretch":
			_reach(pose,1.0,Vector3(1.15,3.3,-.1),weight)
			_reach(pose,-1.0,Vector3(-1.15,3.3,-.1),weight)
			pose.lean = -.07*weight
			pose.nod = -.14*weight
			pose.rise = .07*weight
	return pose


static func blinking(t: float, dwarf_seed: int) -> bool:
	return fposmod(t+dwarf_seed*.37,BLINK_EVERY) < BLINK_SECONDS


static func _reach(pose: Dictionary, side: float, grip: Vector3, weight: float) -> void:
	if side > 0.0:
		pose.left_reach = weight
		pose.left_grip = grip
	else:
		pose.right_reach = weight
		pose.right_grip = grip


static func _roll(slot: int, dwarf_seed: int) -> float:
	return float(hash(slot*7919+dwarf_seed) & 0xFFFF)/65536.0


static func _kind(roll: float) -> String:
	if roll < SHIFT_UNTIL: return "shift"
	if roll < LOOK_UNTIL: return "look"
	if roll < SCRATCH_UNTIL: return "scratch"
	if roll < BEARD_UNTIL: return "beard"
	if roll < STRETCH_UNTIL: return "stretch"
	return ""
