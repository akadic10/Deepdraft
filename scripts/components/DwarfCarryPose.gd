extends "res://scripts/components/DwarfWorkToolPose.gd"

## Presentation only. The agent owns pickup/deposit transactions and timing.
## Bounds are measured once per pickup in the item's own frame, so crates,
## timber, stone and asymmetric packed furniture all sit between the fists.
const CONTACT_PHASE := 0.36
const HOLD_BASE := 0.95
const HOLD_BACK := 1.15
const CLIMB_RAIL_X := .28     # the ladder model's rails, as tier1.mjs builds them
const CLIMB_RAIL_Z := .2      # the rails' plane, ahead of the actor at its cell centre
const CLIMB_HAND_Y := 3.6     # just over the big head, where every camera sees them
const CLIMB_FOOT_INSET := .2  # from the stance, onto the rungs
var _bounds: Dictionary = {}
var work_spot := 0.0   # how far back the last tool work left the dwarf standing (DwarfBodyRig)
## The load's motion against the stride (DwarfMovement.walk_bob); nothing while standing.
var sway := 0.0
var roll := 0.0
var sway_target := 0.0
var roll_target := 0.0
const PICK_SECONDS := 1.7


func item_bounds(item: Node3D) -> AABB:
	if not _bounds.has(item):
		var boxes: Array[AABB] = []
		_collect_boxes(item, Transform3D.IDENTITY, boxes)
		var box := AABB(Vector3(-.4, 0, -.4), Vector3(.8, .8, .8))
		for i in range(boxes.size()):
			box = boxes[i] if i == 0 else box.merge(boxes[i])
		_bounds[item] = box
	return _bounds[item]


func _collect_boxes(node: Node3D, local: Transform3D, boxes: Array[AABB]) -> void:
	if node is MeshInstance3D and node.mesh != null:
		boxes.append(local * node.get_aabb())
	for child in node.get_children():
		if child is Node3D:
			_collect_boxes(child, local * child.transform, boxes)


func reset() -> void:
	super.reset()
	sway_target = 0.0
	roll_target = 0.0


## How much a load weighs on the walk, 0 to 1: a heavy item outright, or a growing handful.
static func heft_of(entries: Array, speed_mult: float) -> float:
	return clampf(maxf((1.0-speed_mult)/.3,entries.size()*.15),0.0,1.0)


func clear_items() -> void:
	_bounds.clear()


func hold_transform(entries: Array, index: int, bounce := 0.0) -> Transform3D:
	var bottom := HOLD_BASE + bounce
	var x := 0.0
	if entries.size() > 1:
		# Two columns keep a full pouch below the face instead of forming a
		# four-item tower. Pack by visible dimensions, without shrinking goods.
		var widths: Array[float] = [0.0, 0.0]
		for i in range(entries.size()):
			widths[i % 2] = maxf(widths[i % 2], item_bounds(entries[i][0]).size.x)
		x = (widths[1] + .025) * .5 if index % 2 == 0 else -(widths[0] + .025) * .5
		for row in range(index >> 1):
			bottom += maxf(item_bounds(entries[row * 2][0]).size.y,
				item_bounds(entries[row * 2 + 1][0]).size.y) + .025
	var box := item_bounds(entries[index][0])
	return Transform3D(Basis(Vector3.BACK, roll), Vector3(x + sway - box.get_center().x,
		bottom - box.position.y, HOLD_BACK - work_spot - box.position.z))


func _grips(item: Node3D, at: Transform3D) -> Array[Vector3]:
	var box := item_bounds(item)
	var center := box.get_center()
	center.y = box.position.y + maxf(.28, box.size.y * .4)
	return [at * (center + Vector3(box.size.x * .5 + .27, 0, 0)),
		at * (center - Vector3(box.size.x * .5 + .27, 0, 0))]


func _hands(grips: Array[Vector3]) -> void:
	_pose_hand(_left, grips[0], Quaternion.IDENTITY)
	_pose_hand(_right, grips[1], Quaternion.IDENTITY)


func _rest_grips() -> Array[Vector3]:
	var back := Vector3(0, 0, -work_spot)
	return [(_rest[_left] as Transform3D) * PALM + back, (_rest[_right] as Transform3D) * PALM + back]


func _bundle_grips(entries: Array) -> Array[Vector3]:
	var first: Node3D = entries[0][0]
	var box: AABB = first.transform * item_bounds(first)
	if entries.size() > 1:
		var second: Node3D = entries[1][0]
		box = box.merge(second.transform * item_bounds(second))
	var center := box.get_center()
	center.y = box.position.y + maxf(.28, box.size.y * .4)
	return [Vector3(box.end.x + .27, center.y, center.z),
		Vector3(box.position.x - .27, center.y, center.z)]


func hold(entries: Array, bounce := 0.0) -> void:
	if entries.is_empty():
		return
	_ease_sway()
	for i in range(entries.size()):
		var node: Node3D = entries[i][0]
		if is_instance_valid(node):
			node.transform = hold_transform(entries, i, bounce)
	_hands(_bundle_grips(entries))


## Hand over hand on the rails, reaching over the big head, where every camera can see them. The head
## is wider than the ladder, so the body climbs behind it (`back`) rather than through it. Hands never
## grip above the ladder's top (`top`, from the feet), so near the end they hold it as the body rises.
## A cycle climbs one block, so ±.25 keeps a planted hand or foot on its rung.
func climb(entries: Array, cycle: float, top := INF, back := 0.0) -> void:
	var wave := sin(cycle * TAU)
	_pose_hand(_left, Vector3(CLIMB_RAIL_X, minf(CLIMB_HAND_Y + wave * .25, top), CLIMB_RAIL_Z), Quaternion.IDENTITY)
	_pose_hand(_right, Vector3(-CLIMB_RAIL_X, minf(CLIMB_HAND_Y - wave * .25, top), CLIMB_RAIL_Z), Quaternion.IDENTITY)
	if is_instance_valid(_feet[0]): _feet[0].position = Vector3(-CLIMB_FOOT_INSET, .25 - wave * .25, .05)
	if is_instance_valid(_feet[1]): _feet[1].position = Vector3(CLIMB_FOOT_INSET, .25 + wave * .25, .05)
	if is_instance_valid(_body):
		_body.position.z = -back
		_body.rotation.z = wave * .025
	if is_instance_valid(_head):
		_head.position.z = -back
		_head.rotation.z = -wave * .015
	for i in range(entries.size()):
		var item: Node3D = entries[i][0]
		if not is_instance_valid(item): continue
		var box := item_bounds(item)
		item.transform = Transform3D(Basis.IDENTITY, Vector3(-box.get_center().x,
			.65 + i * .3 - box.position.y, -.44 - back - box.end.z))


func gather_into(phase: float, source: Transform3D, entries: Array) -> void:
	if entries.is_empty(): return
	hold(entries)
	var grips := _bundle_grips(entries)
	var reach := smoothstep(0.0,CONTACT_PHASE,phase) if phase<CONTACT_PHASE else 1.0-smoothstep(CONTACT_PHASE,1.0,phase)
	# One hand supports the existing basket while the other gathers its contents.
	grips[1]=grips[1].lerp(source.origin+Vector3(0,.35,0),reach)
	_hands(grips)


func pickup(phase: float, item: Node3D, start: Transform3D, entries: Array, lifted: bool) -> void:
	if not is_instance_valid(item):
		return
	var reach := smoothstep(0.0, CONTACT_PHASE, phase)
	var lift := smoothstep(CONTACT_PHASE, 1.0, phase)
	var previous := entries.size() - (1 if lifted else 0)
	var home := _rest_grips()
	if previous > 0:
		var prior := entries.slice(0, previous)
		hold(prior)
		for i in range(previous):
			var cargo: Node3D = entries[i][0]
			cargo.transform = hold_transform(prior, i).interpolate_with(hold_transform(entries, i), lift)
		home = _bundle_grips(prior)
	var target := _grips(item, start)
	if lifted:
		var end := hold_transform(entries, entries.size() - 1)
		item.transform = start.interpolate_with(end, lift)
		item.position.y += sin(lift * PI) * .16
		if previous > 0:
			item.position.y += sin(lift * PI) * .45
			item.position.z += sin(lift * PI) * .6
		target = _grips(item, item.transform)
	var grips: Array[Vector3] = [home[0].lerp(target[0], reach), home[1].lerp(target[1], reach)]
	if previous > 0:
		# One fist supports the existing load while the other adds the next item.
		grips[1] = home[1]
		var settled := _bundle_grips(entries) if lifted else home
		var settle := smoothstep(.82, 1.0, phase)
		grips[0] = grips[0].lerp(settled[0], settle)
		grips[1] = grips[1].lerp(settled[1], settle)
	_hands(grips)
	_reach_body(reach * (1.0 - lift))


func lower(phase: float, entries: Array, target: Vector3) -> void:
	if entries.is_empty():
		return
	_ease_sway()
	var down := smoothstep(0.0, .72, phase)
	var release := smoothstep(.78, 1.0, phase)
	# Target is the bottom-centre of the bundle at the storage handoff point.
	var box: AABB = hold_transform(entries, 0) * item_bounds(entries[0][0])
	if entries.size() > 1:
		box = box.merge(hold_transform(entries, 1) * item_bounds(entries[1][0]))
	var offset := target - Vector3(box.get_center().x, box.position.y, box.get_center().z)
	for i in range(entries.size()):
		var node: Node3D = entries[i][0]
		node.transform = hold_transform(entries, i)
		node.position += offset * down
	var grips := _bundle_grips(entries)
	var home := _rest_grips()
	_hands([grips[0].lerp(home[0], release), grips[1].lerp(home[1], release)])
	_reach_body(down * (1.0 - release) * clampf(1.0 - target.y, 0.0, 1.0))


## Reach into a loose-stone clump without a work tool or premature loot node.
func gather(phase: float, contact: Vector3) -> void:
	var reach := sin(clampf(phase, 0, 1) * PI)
	var home := _rest_grips()
	_hands([home[0].lerp(contact + Vector3(.28, .05, 0), reach),
		home[1].lerp(contact + Vector3(-.28, .05, 0), reach)])
	_reach_body(reach)


## The load settles over a few frames, so stopping never jerks it.
func _ease_sway() -> void:
	sway = lerpf(sway,sway_target,.2)
	roll = lerpf(roll,roll_target,.2)


## Picking, as from a bush: one hand at a time reaches out, unhurried, while the other waits at the
## belt with what is gathered so far. `seconds` is how long the picking has run, in either direction.
func gather_loop(seconds: float, contact: Vector3) -> void:
	var left_picks := posmod(floori(seconds/PICK_SECONDS),2) == 0
	var reach := sin(fposmod(seconds,PICK_SECONDS)/PICK_SECONDS*PI)
	var belt := Vector3(0,1.25,.8-work_spot)
	var left := belt+Vector3(.42,0,0)
	var right := belt-Vector3(.42,0,0)
	if left_picks: left = left.lerp(contact+Vector3(.2,.05,0),reach)
	else: right = right.lerp(contact+Vector3(-.2,.05,0),reach)
	_hands([left,right])
	_reach_body(reach*.75)
	if is_instance_valid(_body): _body.rotation.y = (.12 if left_picks else -.12)*reach


func _reach_body(amount: float) -> void:
	# Reach forward from the adjacent stand cell with both boots planted.
	for part in [_body, _head]:
		if is_instance_valid(part):
			part.position = Vector3(0, -.12 * amount, .06 * amount - work_spot)
			part.rotation = Vector3(.09 * amount, 0, 0)
	for foot in _feet:
		if is_instance_valid(foot):
			foot.position = Vector3(0, 0, -work_spot)
