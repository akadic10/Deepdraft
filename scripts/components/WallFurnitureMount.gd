extends RefCounted

## Shared geometry/work targets for wall pieces. No floor cells are reserved.
## Origin is a stable placement reference, not a required floor. The fixed model
## offset converts it to the actual mount; work floors are discovered separately.
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
	return Vector3(origin) + Vector3(.5, float(mount.origin_offset_y), .5) + Vector3(back(yaw)) * .5


static func mount_cell(def: Dictionary, origin: Vector3i) -> Vector3i:
	return origin + Vector3i.UP * floori(float(def.wall_mount.origin_offset_y))


static func origin_for_mount(def: Dictionary, cell: Vector3i) -> Vector3i:
	return cell - Vector3i.UP * floori(float(def.wall_mount.origin_offset_y))


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
	var bottom := float(mount.origin_offset_y)
	var top := bottom + float(mount.get("bracket_height", 1))
	var result: Array[Vector3i] = []
	for y in range(floori(bottom), ceili(top)):
		result.append(origin + back(yaw) + Vector3i(0, y, 0))
	return result


static func work_stands(def: Dictionary, origin: Vector3i, yaw: int) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	var cell := mount_cell(def,origin)
	var reach := int(TaskManager.get_config_section("furniture").wall_reach_up_blocks)
	for offset: Vector3i in [Vector3i.ZERO,Vector3i.LEFT,Vector3i.RIGHT,Vector3i.FORWARD,Vector3i.BACK]:
		if offset == back(yaw): continue # Never work from behind the supporting wall.
		for y in range(maxi(3,cell.y-reach),cell.y):
			var stand := Vector3i(cell.x+offset.x,y,cell.z+offset.z)
			if NavGrid.is_walkable(stand) and _clear_reach(stand,cell): result.append(stand)
	return result


## Hands must have an unobstructed approach to the bracket, including through
## a low ceiling or an intervening wall. This never reserves the floor below.
static func _clear_reach(stand: Vector3i, cell: Vector3i) -> bool:
	var start := Vector3(stand)+Vector3(.5,2,.5)
	var end := Vector3(cell)+Vector3(.5,.5,.5)
	var steps := maxi(1,ceili(start.distance_to(end)*4))
	for i in range(steps+1):
		var point := start.lerp(end,float(i)/steps)
		var sample := Vector3i(floori(point.x),floori(point.y),floori(point.z))
		if WorldData.get_live_block(sample.x,sample.y,sample.z)!=BlockRegistry.AIR_ID or PlacedEntityRegistry.occupies(sample): return false
	return true


static func nearest_stand(def: Dictionary, origin: Vector3i, yaw: int, dwarf_cell: Vector3i) -> Vector3i:
	var best := Vector3i(-1, -1, -1)
	var best_dist := 0x7FFFFFFF
	for stand: Vector3i in work_stands(def,origin,yaw):
		var delta := stand - dwarf_cell
		var distance := absi(delta.x) + absi(delta.y) + absi(delta.z)
		if distance < best_dist:
			best = stand
			best_dist = distance
	return best
