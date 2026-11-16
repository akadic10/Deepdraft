extends FurnitureGhostComponent

## The shared fetch/carry contract, with persistent hand-planting work.
var progress := 0.0
var continuation_worker := -1 # Uprooter, until the first pickup assignment; never saved.


## A Move promises one exact plant. Compare workers at that physical pickup,
## not the replanting destination. Quoting never transfers its existing claim.
func move_worker_quote() -> Dictionary:
	if required_instance_id.is_empty() or not _claim_valid(): return {}
	var cell: Vector3i = drop_manager.item_floor_cell(_claim)
	var stands: Array[Vector3i] = []
	for stand in StorageComponent.ground_access_cells(cell):
		if NavGrid.is_walkable(stand): stands.append(stand)
	return {"signature": [_claim.get_instance_id(), cell, continuation_worker, stands],
		"stands": stands, "preferred": continuation_worker}


func reserve_fetch(dwarf_id: int, dwarf_cell: Vector3i) -> Dictionary:
	continuation_worker = -1
	return super.reserve_fetch(dwarf_id, dwarf_cell)


func cancel_fetch(dwarf_id: int) -> void:
	continuation_worker = -1
	super.cancel_fetch(dwarf_id)
	# Release routing runs again after the actor drops carried goods. Reclaim
	# an exact Move immediately so the next wake can quote its actual pickup.
	if not required_instance_id.is_empty(): ensure_claim()


func remaining_work() -> float:
	return maxf(float(def.planting_seconds) - progress, 0.0)


func advance_plant(seconds: float) -> float:
	progress = minf(float(def.planting_seconds), progress + maxf(0.0, seconds))
	return remaining_work()


func work_surface() -> Vector3:
	return Vector3(origin_cell) + Vector3(.5, 1.0, .5)
