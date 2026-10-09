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
	if not required_instance_id.is_empty(): _ensure_claim()


## A cutting crate may contain many plants. Only one unit leaves it at pickup.
func take_planting_item(item: Node3D, dwarf_id: int) -> Node3D:
	_carried_by[dwarf_id] = true # Splitting emits a stock wake; don't reclaim its remainder.
	var cargo: Node3D = drop_manager.take_quantity(item, 1, dwarf_id)
	if cargo == null: _carried_by.erase(dwarf_id)
	return cargo


## A whole crate is briefly reserved until physical pickup splits one unit.
## Its spare cuttings can still support additional standing Place requests.
func spare_claimed_units() -> int:
	if not bool(def.get("from_cutting", false)): return 0
	var item: Node3D = _claim if _claim_valid() else null
	if item == null and not _fetches.is_empty(): item = _fetches.values()[0]
	return maxi(0, drop_manager.quantity_of(item) - 1) if is_instance_valid(item) else 0


func remaining_work() -> float:
	return maxf(float(def.planting_seconds) - progress, 0.0)


func advance_plant(seconds: float) -> float:
	progress = minf(float(def.planting_seconds), progress + maxf(0.0, seconds))
	return remaining_work()


func work_surface() -> Vector3:
	return Vector3(origin_cell) + Vector3(.5, 1.0, .5)
