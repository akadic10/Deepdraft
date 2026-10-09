extends "res://scripts/components/DwarfWorkToolPose.gd"

## Presentation only. The agent owns pickup/deposit transactions and timing.
## Bounds are measured once per pickup in the item's own frame, so crates,
## timber, stone and asymmetric packed furniture all sit between the fists.
const CONTACT_PHASE := 0.36
const HOLD_BASE := 0.95
const HOLD_BACK := 1.15
var _bounds: Dictionary = {}


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
		for row in range(index / 2):
			bottom += maxf(item_bounds(entries[row * 2][0]).size.y,
				item_bounds(entries[row * 2 + 1][0]).size.y) + .025
	var box := item_bounds(entries[index][0])
	return Transform3D(Basis.IDENTITY, Vector3(x - box.get_center().x,
		bottom - box.position.y, HOLD_BACK - box.position.z))


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
	return [(_rest[_left] as Transform3D) * PALM, (_rest[_right] as Transform3D) * PALM]


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
	for i in range(entries.size()):
		var node: Node3D = entries[i][0]
		if is_instance_valid(node):
			node.transform = hold_transform(entries, i, bounce)
	_hands(_bundle_grips(entries))


## Both hands reach rungs; carried goods ride against the dwarf's back.
func climb(entries: Array, cycle: float) -> void:
	var wave := sin(cycle * TAU)
	_pose_hand(_left, Vector3(.30, 2.05 + wave * .28, .38), Quaternion.IDENTITY)
	_pose_hand(_right, Vector3(-.30, 2.05 - wave * .28, .38), Quaternion.IDENTITY)
	for i in range(entries.size()):
		var item: Node3D = entries[i][0]
		if not is_instance_valid(item): continue
		var box := item_bounds(item)
		item.transform = Transform3D(Basis.IDENTITY, Vector3(-box.get_center().x,
			.65 + i * .3 - box.position.y, -.5 - box.end.z))


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


func _reach_body(amount: float) -> void:
	# Reach forward from the adjacent stand cell with both boots planted.
	for part in [_body, _head]:
		if is_instance_valid(part):
			part.position = Vector3(0, -.12 * amount, .06 * amount)
			part.rotation = Vector3(.09 * amount, 0, 0)
	for foot in _feet:
		if is_instance_valid(foot):
			foot.position = Vector3.ZERO
