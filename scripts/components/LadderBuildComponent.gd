extends FurnitureGhostComponent

## One physical section, installed from the floor or the preceding section.
var progress := 0.0

func nearest_stand_target(_from: Vector3i) -> Vector3i:
	return origin_cell if NavGrid.is_navigable(origin_cell) else Vector3i(-1, -1, -1)

func take_planting_item(item: Node3D, dwarf_id: int) -> Node3D:
	_carried_by[dwarf_id] = true
	var cargo: Node3D = drop_manager.take_quantity(item, 1, dwarf_id)
	if cargo == null: _carried_by.erase(dwarf_id)
	return cargo

func remaining_work() -> float:
	return maxf(0.0, float(def.ladder.install_seconds) - progress)

func advance_install(seconds: float) -> float:
	progress += minf(maxf(seconds, 0.0), remaining_work())
	return remaining_work()

func work_surface() -> Vector3:
	return Vector3(origin_cell) + Vector3(.5, 2.2, .5)

func work_facing() -> Vector3i:
	return [Vector3i.FORWARD, Vector3i.LEFT, Vector3i.BACK, Vector3i.RIGHT][yaw_steps]
