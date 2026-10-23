extends FurnitureGhostComponent

## Prefer the worker who just packed this exact piece, as shrub Move does.
var continuation_worker := -1

func move_worker_quote() -> Dictionary:
	if required_instance_id.is_empty() or not _claim_valid(): return {}
	var cell: Vector3i = drop_manager.item_floor_cell(_claim)
	var stands: Array[Vector3i] = []
	for stand in StorageComponent.ground_access_cells(cell):
		if NavGrid.is_walkable(stand): stands.append(stand)
	return {"signature":[_claim.get_instance_id(),cell,continuation_worker,stands],
		"stands":stands,"preferred":continuation_worker}

func reserve_fetch(dwarf_id: int, dwarf_cell: Vector3i) -> Dictionary:
	continuation_worker = -1
	return super.reserve_fetch(dwarf_id,dwarf_cell)

func cancel_fetch(dwarf_id: int) -> void:
	continuation_worker = -1
	super.cancel_fetch(dwarf_id)
	ensure_claim()
