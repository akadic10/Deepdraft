extends InstalledFurnitureComponent

var record: Dictionary
var progress: float:
	get: return float(record.get("work", 0.0))

func advance_removal(seconds: float, _worker: int) -> float:
	record.work = progress + maxf(0.0, seconds)
	return maxf(0.0, float(WorldGenerator.water_profile.stones[record.kind].packing_seconds)-progress)

func work_facing() -> Vector3i: return Vector3i.FORWARD

func nearest_stand_target(from: Vector3i) -> Vector3i:
	var best := Vector3i(-1,-1,-1)
	var distance := INF
	for stand in StorageComponent.ground_access_cells(origin_cell):
		if not NavGrid.is_walkable(stand): continue
		var delta := stand-from
		var d := float(absi(delta.x)+absi(delta.y)+absi(delta.z))
		if d<distance:
			distance=d
			best=stand
	return best
