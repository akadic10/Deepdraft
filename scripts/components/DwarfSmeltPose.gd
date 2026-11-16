extends "res://scripts/components/DwarfWorkToolPose.gd"

## Charging the basic smelter (doc 300). The Blacksmith stands a long step back from the boulder,
## the charge at its feet. It takes each lump up in turn and lobs it into the stone pot in the
## boulder's crown; then it crouches and blows on the fire through a hollow stick held to the fire
## hole in the boulder's foot. A log that feeds the fire (doc 306) is not lobbed: it is swung low,
## end first, into the fire hole.
## Cosmetic only. The craft order owns the work and its goods and checks where they lie, so a real
## lump is never moved: it stops being drawn as its turn comes, and a copy of it is thrown.
## The lumps stay undrawn until the order takes them at the end of the work. `release` draws every
## lump again and drops the copies: the fetch teardown calls it, so a charge given up half way
## leaves the goods as they lay (Hard Rule 12). A lump's `visible` is never touched: it is the item
## manager's, for the slice.

const STAND_REACH := 2.3              # the walk stops this far from the pot (stop_short_of): the
                                      # boulder stands higher than a load is carried, and a crouch
                                      # at its foot needs the room
const MIN_BACK := .45                 # drawn at least this far behind the cell centre while charging
const LUMP_SHARE := .13               # of the work, for each lump
const LUMPS_MOST := .5
const THROWN := .62                   # of a lump's turn: the hands let it go,
const FLIGHT := .26                   # and it is in the air this much longer: it lands at THROWN + FLIGHT
const STICK_LENGTH := 1.3125          # the stick's mouth end to its burnt end, as its model has it
const STICK_GRIP := .1875             # its mouth end to the right hand
const BREATHS := 3.0
const BLOW_STARTS := .3               # of a breath: drawn in until here, then blown out
const CROUCHED := .16                 # of the blowing, to get down; up again from RISING
const RISING := .93
const HIP := Vector3(0, .7, 0)        # the body leans about its belt,
const NECK := Vector3(0, 1.85, .05)   # the head nods about its neck,
const MOUTH := Vector3(0, 2.02, .74)  # and the mouth is here: all in the parts' rest frame

var blowing := false                  # the stick is at the mouth and the fire hole
var _stick: PackedScene
var _stick_basis := Basis.IDENTITY
var _carrier: Node3D
var _goods: Array = []                # the real lumps, the one in hand first
var _copies: Array = []               # a copy of each, once its turn has come
var _starts: Array = []               # where each lay, in the dwarf's frame
var _boxes: Array = []
var _gone: Array = []                 # the real lumps not drawn for now,
var _undrawn: Array = []              # and each of their meshes with its layers: [[mesh, layers], ...]


## The share of the work spent throwing `count` lumps in; the rest is blowing.
static func charging_share(count: int) -> float:
	return minf(LUMP_SHARE * maxi(count, 1), LUMPS_MOST)


## What the work is heard as (WorkFeedback.play_smelting): for a charge of `count` goods, [share of
## the work, kind] for each lump as it lands ("smelt_toss" in the pot; "smelt_log" in the fire hole
## for those of `fed`, the places in the charge of the goods that feed the fire), then for each
## breath as the blow starts ("smelt_blow"), in the order they come. The marks are the ones `apply`
## draws by, so a cue is heard as it is seen.
static func cues(count: int, fed: Array = []) -> Array:
	var marks: Array = []
	var charging := charging_share(count)
	for index in range(count):
		marks.append([(index + THROWN + FLIGHT) / count * charging, "smelt_log" if index in fed else "smelt_toss"])
	for breath in range(int(BREATHS)):
		var blown := CROUCHED + (breath + BLOW_STARTS) / BREATHS * (RISING - CROUCHED)
		marks.append([charging + blown * (1.0 - charging), "smelt_blow"])
	return marks


## One frame. `share` is the work done, 0 to 1; `goods` the charge's lumps, the one in hand first;
## `pot` and `hole` the pot's mouth and the fire hole in the dwarf's frame; `back` how far behind its
## cell centre the dwarf stands (the rig's work spot); `carrier` the dwarf; `fire` those of the
## goods that feed the fire hole instead of the pot (the charge's logs).
func apply(share: float, goods: Array, pot: Vector3, hole: Vector3, stick: PackedScene, back: float, carrier: Node3D, fire: Array = []) -> void:
	if goods != _goods or carrier != _carrier: _take(goods, carrier)
	var home := maxf(back, MIN_BACK)
	var charging := charging_share(_goods.size())
	share = clampf(share, 0.0, 1.0)
	blowing = false
	# From a side the fire hole cannot be reached from, the stick and the logs go to the boulder's foot.
	if absf(hole.x) > .3 or hole.z < .2: hole = Vector3(0, hole.y, pot.z - .48)
	if share < charging and not _goods.is_empty():
		if is_instance_valid(tool): tool.visible = false
		var turn := share / charging * _goods.size()
		var index := mini(int(turn), _goods.size() - 1)
		var feeds: bool = _goods[index] in fire
		_throw(index, fposmod(turn, 1.0), hole if feeds else pot, home, feeds)
		return
	for index in range(_goods.size()): _put_in(index)
	_blow((share - charging) / maxf(1.0 - charging, .001), hole, stick, home)


## Every lump is drawn where it lies again and the copies are gone. Safe at any time.
func release() -> void:
	for entry: Array in _undrawn:
		if is_instance_valid(entry[0]): (entry[0] as VisualInstance3D).layers = entry[1]
	for copy in _copies:
		if is_instance_valid(copy): copy.queue_free()
	_undrawn.clear()
	_gone.clear()
	_copies.clear()
	_goods.clear()
	_starts.clear()
	_boxes.clear()
	_carrier = null
	blowing = false


func _take(goods: Array, carrier: Node3D) -> void:
	release()
	_carrier = carrier
	for lump in goods:
		if not is_instance_valid(lump): continue
		_goods.append(lump)
		_starts.append(carrier.global_transform.affine_inverse() * (lump as Node3D).global_transform)
		_boxes.append(_box(lump))
		_copies.append(null)


## A lump's meshes' box in its own frame, as DwarfCarryPose.item_bounds measures a load.
func _box(node: Node3D) -> AABB:
	var boxes: Array[AABB] = []
	_boxes_of(node, Transform3D.IDENTITY, boxes)
	var box := AABB(Vector3(-.3, 0, -.3), Vector3(.6, .6, .6))
	for i in range(boxes.size()): box = boxes[i] if i == 0 else box.merge(boxes[i])
	return box


func _boxes_of(node: Node3D, local: Transform3D, boxes: Array[AABB]) -> void:
	if node is MeshInstance3D and node.mesh != null: boxes.append(local * node.get_aabb())
	for child in node.get_children():
		if child is Node3D: _boxes_of(child, local * child.transform, boxes)


## The copy that is thrown in a lump's place. Making it stops the lump being drawn.
func _copy(index: int) -> Node3D:
	if not is_instance_valid(_copies[index]):
		var copy: Node3D = (_goods[index] as Node3D).duplicate(0)   # its look only: no script, signal or group
		_carrier.add_child(copy)
		copy.transform = _starts[index]
		copy.visible = true
		_copies[index] = copy
		_undraw(_goods[index])
	return _copies[index]


func _undraw(real: Variant) -> void:
	if not is_instance_valid(real) or real in _gone: return
	_gone.append(real)
	var drawn: Array = (real as Node).find_children("*", "VisualInstance3D", true, false)
	if real is VisualInstance3D: drawn.append(real)
	for part: VisualInstance3D in drawn:
		_undrawn.append([part, part.layers])
		part.layers = 0


## The lump is in the pot: nothing of it shows.
func _put_in(index: int) -> void:
	_undraw(_goods[index])
	if is_instance_valid(_copies[index]):
		_copies[index].visible = false
		_copies[index].queue_free()
	_copies[index] = null


## A lump's turn, `t` from 0 to 1. The hands take it, from the ground with a bend unless it is the
## one in hand; it is lifted to the chest and swung back, thrown, and falls into the pot.
## `low` is a log for the fire: it is turned end on, swung back beside the knee and sent low into
## the fire hole, which `pot` then is.
func _throw(index: int, t: float, pot: Vector3, home: float, low := false) -> void:
	for earlier in range(index): _put_in(earlier)
	var lump := _copy(index)
	var box: AABB = _boxes[index]
	var from: Transform3D = _starts[index]
	var lay: Vector3 = from * box.get_center()
	var held := index == 0                 # in hand already: nothing to bend for
	var base := -home
	var grab := 1.0 if held else smoothstep(0.0, .2, t)
	var bend := 0.0 if held else sin(clampf(t / .42, 0.0, 1.0) * PI)
	var lift := smoothstep(.04 if held else .2, .5, t)
	var swing := smoothstep(.5, THROWN, t)         # the throw, to the moment the hands let go
	var flight := clampf((t - THROWN) / FLIGHT, 0.0, 1.0)
	var away := smoothstep(.66, .92, t)            # the hands come back to the sides
	var wound := Vector3(0, 1.5, base + 1.05)      # swung back, low before the belt
	var let_go := Vector3(0, 2.2, base + 1.45)     # and let go high before the face
	if low:
		wound = Vector3(0, .95, base + .8)         # a log: back beside the knee,
		let_go = Vector3(0, .9, base + 1.5)        # and let go low, at arm's length
	var middle := lay.lerp(wound, lift).lerp(let_go, swing)
	if flight > 0.0:
		middle = let_go.lerp(pot, flight) + Vector3(0, sin(flight * PI) * (.12 if low else .5), 0)
	var size := lerpf(1.0, .3, smoothstep(.55, 1.0, flight))
	var turned := Basis(Vector3.RIGHT, (swing * .4 + flight * 2.2)) * from.basis.orthonormalized()
	if low:
		# No tumbling: its length turns toward the hole as it is lifted, and stays there.
		var along: Vector3 = from.basis.orthonormalized() * (Vector3.RIGHT if box.size.x >= box.size.z else Vector3.BACK)
		var aim := (pot - let_go).normalized()
		if along.dot(aim) < 0.0: along = -along
		turned = Basis(Quaternion.IDENTITY.slerp(Quaternion(along, aim), lift)) * from.basis.orthonormalized()
	lump.transform = Transform3D(turned.scaled(Vector3.ONE * size), middle - turned * (box.get_center() * size))
	lump.visible = flight < 1.0
	# The hands hold the lump by its sides until they let go, and follow it a little way.
	var hold := lay.lerp(wound, lift).lerp(let_go + Vector3(0, .1, .15), swing)
	var side := Vector3((minf(box.size.x, box.size.z) if low else box.size.x) * .5 + .2, -.05, 0)
	var tilt := Quaternion(Vector3.RIGHT, swing * (1.0 - away) * .7)
	_pose_hand(_left, _home(_left, base).lerp(hold + side, grab).lerp(_home(_left, base), away), tilt)
	_pose_hand(_right, _home(_right, base).lerp(hold + Vector3(-side.x, side.y, 0), grab).lerp(_home(_right, base), away), tilt)
	var effort := swing * (1.0 - away)             # leaning into the throw
	var back := lift * (1.0 - swing) * .5          # and back before it
	_stand(base, bend * .42, bend * .4 + effort * .16 - back * .08, bend * .1 + effort * .06 - back * .1)
	_set_feet([base + .12, base - .12])


## The blowing, `u` from 0 to 1: down into a crouch with the stick at the mouth, breath after breath,
## then up.
## A dwarf with no room behind it cannot crouch at the hole: it stoops and holds the stick steep.
func _blow(u: float, hole: Vector3, stick: PackedScene, home: float) -> void:
	var room := clampf((home - MIN_BACK) / .85, 0.0, 1.0)
	var down := smoothstep(0.0, CROUCHED, u) * (1.0 - smoothstep(RISING, 1.0, u) * .6)
	var breath := fposmod((u - CROUCHED) / (RISING - CROUCHED) * BREATHS, 1.0) if u > CROUCHED and u < RISING else 0.0
	var draw := sin(clampf(breath / BLOW_STARTS, 0.0, 1.0) * PI)                      # the chest rises as it breathes in,
	var puff := smoothstep(BLOW_STARTS, .42, breath) - smoothstep(.86, 1.0, breath)   # then it leans into the blow
	var mouth := _stand(-home, (lerpf(.12, .35, room) - draw * .1) * down,
		(lerpf(.04, .2, room) + puff * .08 - draw * .1) * down, (lerpf(.5, .34, room) + puff * .06 - draw * .05) * down)
	_set_feet([-home + .12, -home - .12])
	if stick == null or not _hold(stick): return
	var bring := smoothstep(.04, CROUCHED, u) * (1.0 - smoothstep(RISING, 1.0, u))
	tool.visible = u >= .04 and u < .995
	var tip := hole + Vector3(0, 0, .03)
	var along := (tip - mouth).normalized()
	var aim := Quaternion.IDENTITY.slerp(Quaternion(Vector3.UP, along), bring)
	var grip := _home(_right, -home).lerp(mouth + along * STICK_GRIP, bring)
	_pose_hand(_right, grip, aim)
	# One hand holds the stick, so the stick shows; the other rests on the knee.
	_pose_hand(_left, _home(_left, -home).lerp(Vector3(.62, .8, -home + .4), down), Quaternion(Vector3.RIGHT, .5 * down))
	# The burnt end stays in the hole, however near the dwarf has to stand.
	tool.basis = _stick_basis * Basis.from_scale(Vector3(1, lerpf(1.0, clampf(mouth.distance_to(tip) / STICK_LENGTH, .7, 1.2), bring), 1))
	blowing = bring > .98


func _hold(stick: PackedScene) -> bool:
	if stick != _stick and is_instance_valid(tool):
		tool.free()
		tool = null
	_stick = stick
	var fresh := not is_instance_valid(tool)
	if not _ensure_tool(stick, "BlowStick"): return false
	if fresh: _stick_basis = tool.basis
	return true


## A hand's place at rest beside a body standing at `base`.
func _home(hand: Node3D, base: float) -> Vector3:
	return (_rest[hand] as Transform3D) * PALM + Vector3(0, 0, base) if is_instance_valid(hand) else Vector3(0, 1.25, base)


## Stands the body at `base` along the dwarf's facing, sunk by `drop`, leaning `lean` about the belt
## with the head nodding `nod` more, and gives back where the mouth is.
func _stand(base: float, drop: float, lean: float, nod: float) -> Vector3:
	var hip := HIP + Vector3(0, -drop, base)
	if is_instance_valid(_body):
		_body.rotation = Vector3(lean, 0, 0)
		_body.position = hip - _body.basis * HIP
	var neck := hip + Basis(Vector3.RIGHT, lean) * (NECK - HIP)
	if is_instance_valid(_head):
		_head.rotation = Vector3(lean + nod, 0, 0)
		_head.position = neck - _head.basis * NECK
	return neck + Basis(Vector3.RIGHT, lean + nod) * (MOUTH - NECK)


## Each foot along the dwarf's facing; a foot keeps its place across the body.
func _set_feet(along: Array) -> void:
	for i in range(_feet.size()):
		if is_instance_valid(_feet[i]): _feet[i].position = Vector3(_feet[i].position.x, 0, along[i])
