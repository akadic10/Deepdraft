extends InstalledFurnitureComponent

var progress := 0.0
var stands: Array[Vector3i] = []
var safe_callback: Callable

func nearest_stand_target(from: Vector3i) -> Vector3i:
	var best := Vector3i(-1,-1,-1)
	for cell: Vector3i in stands:
		if NavGrid.is_walkable(cell) and (best.x < 0 or from.distance_squared_to(cell) < from.distance_squared_to(best)):
			best = cell
	return best

func work_facing() -> Vector3i:
	return [Vector3i.FORWARD, Vector3i.LEFT, Vector3i.BACK, Vector3i.RIGHT][yaw_steps]

func advance_removal(seconds: float, _dwarf_id: int) -> float:
	if safe_callback.is_valid() and not safe_callback.call(): return 1.0
	progress = minf(float(def.bridge.remove_seconds), progress + maxf(seconds, 0.0))
	return maxf(0.0, float(def.bridge.remove_seconds) - progress)
