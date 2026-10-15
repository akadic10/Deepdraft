extends FurnitureGhostComponent

## One retained order/lease per area; the current block is a physical work unit.
var controller: Node
var construction_kind := "stone"
var cells: Array[Vector3i] = []
var target := Vector3i(-1,-1,-1)
var progress := 0.0
var work_progress: Dictionary = {}
var _stand_targets: Dictionary = {}

func display_name() -> String:
	return "%s (%d blocks)" % [def.display_name,cells.size()]

func work_stands(_from: Vector3i) -> Array[Vector3i]:
	_stand_targets.clear()
	var result: Array[Vector3i] = []
	var candidates: Array[Vector3i] = [target] if not _carried_by.is_empty() else cells
	for cell: Vector3i in candidates:
		if not controller.build_reason(cell, false).is_empty(): continue
		for stand: Vector3i in controller.stands_for(cell):
			if not _stand_targets.has(stand):
				_stand_targets[stand] = cell
				result.append(stand)
	return result

func prefer_fetch_plan(plan: Dictionary) -> void:
	# The two-leg planner proves a particular reachable approach before reserving.
	target = _stand_targets.get(plan.delivery_stand,Vector3i(-1,-1,-1))
	progress = float(work_progress.get(target,0.0))
	super.prefer_fetch_plan(plan)

func nearest_stand_target(from: Vector3i) -> Vector3i:
	var stands: Array[Vector3i] = controller.stands_for(target) if target.x >= 0 else work_stands(from)
	stands.sort_custom(func(a: Vector3i,b: Vector3i): return from.distance_squared_to(a)<from.distance_squared_to(b))
	return stands[0] if not stands.is_empty() else Vector3i(-1,-1,-1)

func reserve_fetch(dwarf_id: int, from: Vector3i) -> Dictionary:
	# Construction always requires the scheduler's exact two-leg plan.
	if _preferred_fetch.is_empty() or not cells.has(target): return {}
	return super.reserve_fetch(dwarf_id,from)

func take_planting_item(item: Node3D, dwarf_id: int) -> Node3D:
	return drop_manager.take_quantity(item,1,dwarf_id)

func remaining_work() -> float:
	return maxf(0.0,float(def.work_seconds)-progress)

func advance_install(seconds: float) -> float:
	progress += minf(maxf(seconds,0),remaining_work())
	work_progress[target] = progress
	return remaining_work()

func work_facing(from: Vector3i) -> Vector3i:
	return Vector3i(target.x-from.x,0,target.z-from.z)

func can_complete_build() -> bool:
	if not bool(def.get("worker_enabled",true)): return false
	if not cells.has(target) or not controller.build_reason(target,false).is_empty(): return false
	for dwarf_id: int in _carried_by:
		var worker: DwarfAgent = TaskManager._agents.get(dwarf_id)
		if not is_instance_valid(worker) or not controller.stands_for(target).has(worker.current_cell()): return false
	return not _carried_by.is_empty()

func complete_build(dwarf_id: int) -> void:
	controller.commit_block(self)
	_carried_by.erase(dwarf_id)
	_delivery_stands.erase(dwarf_id)
	cells.erase(target)
	work_progress.erase(target)
	target = Vector3i(-1,-1,-1)
	progress = 0

func update_lease() -> void:
	if not bool(def.get("worker_enabled",true)): return
	# Quotes remain read-only until both route legs succeed. Do not redirect an
	# existing furniture haul: its destination would lack a selected work unit.
	if _lease_id < 0 and not cells.is_empty():
		_lease_id = TaskManager.add_task(Task.Type.FETCH_BUILD,origin_cell,{"construction_id":ghost_id},source_id)

func cancel_fetch(dwarf_id: int) -> void:
	super.cancel_fetch(dwarf_id)
	release_claim()
	target = Vector3i(-1,-1,-1)
	progress = 0
