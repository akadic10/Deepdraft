extends RefCounted

## Shapes' cells (doc 273, Phase 2): rectangles and circles, hollow or filled, and stairs, laid
## on the plane of the drag's first cell. Pure geometry: ConstructionController leaves out what
## build_reason refuses and what the slice hides, and keeps the stairs' headroom.

## How tall a door gap is, the dwarves' clearance (Hard Rule 4).
const DOOR_HEIGHT := 3


## A rectangle from corner `a` to corner `b`, `height` tall. Hollow keeps its edge, one block
## thick; a one-wide rectangle is a wall. A door gap `door` wide opens in the middle of the first
## side in `facing` (the sides toward the camera, nearest first) long enough for it.
static func rectangle(a: Vector3i, b: Vector3i, height: int, filled: bool, door: int, facing: Array[Vector3i]) -> Array[Vector3i]:
	var low := Vector2i(mini(a.x, b.x), mini(a.z, b.z))
	var high := Vector2i(maxi(a.x, b.x), maxi(a.z, b.z))
	var gap := {} if filled else door_columns(low, high, door, facing)
	var result: Array[Vector3i] = []
	for y in range(a.y, a.y + height):
		for x in range(low.x, high.x + 1):
			for z in range(low.y, high.y + 1):
				if not filled and x != low.x and x != high.x and z != low.y and z != high.y: continue
				if gap.has(Vector2i(x, z)) and y < a.y + DOOR_HEIGHT: continue
				result.append(Vector3i(x, y, z))
	return result


## The columns a door gap leaves open: centred on the first side in `facing` that has room for
## it between its corners, which stay. {} when none fits.
static func door_columns(low: Vector2i, high: Vector2i, width: int, facing: Array[Vector3i]) -> Dictionary:
	var gap := {}
	if width <= 0: return gap
	for side: Vector3i in facing:
		var along_x := side.z != 0   # a side facing ±z runs along x
		var first := low.x if along_x else low.y
		var inner := (high.x if along_x else high.y) - first - 1   # the cells between its corners
		if inner < width: continue
		var line := (high.y if side.z > 0 else low.y) if along_x else (high.x if side.x > 0 else low.x)
		var start := first + 1 + (inner - width) / 2
		for at in range(start, start + width):
			gap[Vector2i(at, line) if along_x else Vector2i(line, at)] = true
		return gap
	return gap


## The two sides of a footprint a camera looking along `forward` sees, the nearer first.
static func facing_sides(forward: Vector3) -> Array[Vector3i]:
	var x := Vector3i(-1 if forward.x > 0.0 else 1, 0, 0)
	var z := Vector3i(0, 0, -1 if forward.z > 0.0 else 1)
	var result: Array[Vector3i] = []
	result.assign([x, z] if absf(forward.x) > absf(forward.z) else [z, x])
	return result


## A circle round `center`, `radius` cells out (0 is one cell), `height` tall: a ring one block
## thick, or filled. A cell is in when its centre lies within radius + ½.
static func circle(center: Vector3i, radius: int, height: int, filled: bool) -> Array[Vector3i]:
	var reach := (float(radius) + 0.5) * (float(radius) + 0.5)
	var inside := func(dx: int, dz: int) -> bool: return float(dx * dx + dz * dz) <= reach
	var result: Array[Vector3i] = []
	for dx in range(-radius, radius + 1):
		for dz in range(-radius, radius + 1):
			if not inside.call(dx, dz): continue
			var edge: bool = not (inside.call(dx + 1, dz) and inside.call(dx - 1, dz) and inside.call(dx, dz + 1) and inside.call(dx, dz - 1))
			if not filled and not edge: continue
			for y in range(center.y, center.y + height): result.append(Vector3i(center.x + dx, y, center.z + dz))
	return result


## A flight from `foot` toward `top` (on one plane): one block up a step along the longer
## axis, as wide as the drag across it, at most `longest` steps. Each step is a solid column
## under its tread, standing on the ground and beside the step before. The steps come in order
## from the foot, each {cells, tread}: tread is the height a dwarf stands at on it.
static func stairs(foot: Vector3i, top: Vector3i, longest: int) -> Array[Dictionary]:
	var along_x := absi(top.x - foot.x) >= absi(top.z - foot.z)
	var forward := Vector3i(signi(top.x - foot.x), 0, 0) if along_x else Vector3i(0, 0, signi(top.z - foot.z))
	var length := mini((absi(top.x - foot.x) if along_x else absi(top.z - foot.z)) + 1, longest)
	var across := range(mini(foot.z, top.z), maxi(foot.z, top.z) + 1) if along_x else range(mini(foot.x, top.x), maxi(foot.x, top.x) + 1)
	var steps: Array[Dictionary] = []
	for i in range(length):
		var cells: Array[Vector3i] = []
		for w: int in across:
			var base := Vector3i(foot.x + forward.x * i, foot.y, w) if along_x else Vector3i(w, foot.y, foot.z + forward.z * i)
			for h in range(i + 1): cells.append(base + Vector3i(0, h, 0))
		steps.append({"cells": cells, "tread": foot.y + i + 1})
	return steps
