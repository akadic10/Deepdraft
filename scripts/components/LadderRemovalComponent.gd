extends InstalledFurnitureComponent

var progress := 0.0
var safe_callback: Callable

func work_facing() -> Vector3i:
	return [Vector3i.FORWARD, Vector3i.LEFT, Vector3i.BACK, Vector3i.RIGHT][yaw_steps]

func nearest_stand_target(_from: Vector3i) -> Vector3i:
	return origin_cell if NavGrid.is_navigable(origin_cell) else Vector3i(-1, -1, -1)

func advance_removal(seconds: float, dwarf_id: int) -> float:
	if safe_callback.is_valid() and not safe_callback.call(dwarf_id): return 1.0
	progress = minf(float(def.ladder.remove_seconds), progress + maxf(seconds, 0.0))
	return maxf(0.0, float(def.ladder.remove_seconds) - progress)
