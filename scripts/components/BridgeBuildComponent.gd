extends FurnitureGhostComponent

var progress := 0.0
var stands: Array[Vector3i] = []

func nearest_stand_target(from: Vector3i) -> Vector3i:
	var best := Vector3i(-1,-1,-1)
	for cell: Vector3i in stands:
		if NavGrid.is_walkable(cell) and (best.x < 0 or from.distance_squared_to(cell) < from.distance_squared_to(best)):
			best = cell
	return best

func take_planting_item(item: Node3D, dwarf_id: int) -> Node3D:
	_carried_by[dwarf_id] = true
	var cargo: Node3D = drop_manager.take_quantity(item, 1, dwarf_id)
	if cargo == null: _carried_by.erase(dwarf_id)
	return cargo

func remaining_work() -> float:
	return maxf(0.0, float(def.bridge.install_seconds) - progress)

func advance_install(seconds: float) -> float:
	progress += minf(maxf(seconds, 0.0), remaining_work())
	return remaining_work()

func work_facing(from: Vector3i) -> Vector3i:
	var direction: Vector3i = [Vector3i.FORWARD, Vector3i.LEFT, Vector3i.BACK, Vector3i.RIGHT][yaw_steps]
	var offset := from-origin_cell
	return -direction if offset.x*direction.x+offset.z*direction.z>0 else direction
