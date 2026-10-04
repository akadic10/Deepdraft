extends RefCounted

## Shared geometry/work targets for wall pieces. No floor cells are reserved.
## Their saved origin remains a FLOOR cell, preserving the furniture save schema.
static func is_wall(def: Dictionary) -> bool:
	return String(def.get("placement", "floor")) == "wall"


static func back(yaw: int) -> Vector3i:
	match posmod(yaw, 4):
		1: return Vector3i.LEFT
		2: return Vector3i.BACK
		3: return Vector3i.RIGHT
	return Vector3i.FORWARD


static func position_for(def: Dictionary, origin: Vector3i, yaw: int) -> Vector3:
	var mount: Dictionary = def.get("wall_mount", {})
	return Vector3(origin) + Vector3(.5, 1.0 + float(mount.get("height_above_floor", 0)), .5) + Vector3(back(yaw)) * .5


static func bounds_for(def: Dictionary, origin: Vector3i, yaw: int) -> AABB:
	var mount: Dictionary = def.get("wall_mount", {})
	var lo: Array = mount.get("bounds_min", [0, 0, 0])
	var hi: Array = mount.get("bounds_max", [0, 0, 0])
	var low := Vector3(float(lo[0]), float(lo[1]), float(lo[2]))
	var high := Vector3(float(hi[0]), float(hi[1]), float(hi[2]))
	var transform := Transform3D(Basis(Vector3.UP, float(yaw) * PI * .5), position_for(def, origin, yaw))
	return transform * AABB(low, high - low)


static func supports(def: Dictionary, origin: Vector3i, yaw: int) -> Array[Vector3i]:
	var mount: Dictionary = def.get("wall_mount", {})
	var bottom := 1.0 + float(mount.get("height_above_floor", 0))
	var top := bottom + float(mount.get("bracket_height", 1))
	var result: Array[Vector3i] = []
	for y in range(floori(bottom), ceili(top)):
		result.append(origin + back(yaw) + Vector3i(0, y, 0))
	return result


static func nearest_stand(origin: Vector3i, dwarf_cell: Vector3i) -> Vector3i:
	var best := Vector3i(-1, -1, -1)
	var best_dist := 0x7FFFFFFF
	# Standing underneath is safe: wall pieces never register nav occupancy.
	for offset: Vector3i in [Vector3i.ZERO, Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK]:
		var stand := origin + offset
		if not NavGrid.is_walkable(stand):
			continue
		var delta := stand - dwarf_cell
		var distance := absi(delta.x) + absi(delta.y) + absi(delta.z)
		if distance < best_dist:
			best = stand
			best_dist = distance
	return best
