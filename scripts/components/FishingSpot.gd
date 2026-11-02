extends RefCounted

## One spot of a Fishing zone (doc 289): one dwarf stands on its floor cell and casts into the
## water in front of it. A surface work source (Task.SURFACE_WORK): the surface matcher brings
## a worker here and the work executor times the catch, as for a tree. The fishing system owns
## the stock, the catch and the zone's record; nothing here is saved, and spots are rebuilt
## from their zone on restore.
var task_type: int = Task.Type.FISH
var source_id := -1
var lease_id := -1
var reserved_by := -1
var zone_id := -1
var origin := Vector3i.ZERO        # the floor cell the fisher stands on (NavGrid's convention)
var water := Vector3i.ZERO         # the water cell the float lands in
var item := ""                     # the fish its water gives, for the catch on the line
var duration := 30.0               # work seconds this catch takes
var roll := 1.0                    # this catch's seeded roll: big below the Ranger's big_chance (doc 292)
## `designated`: the zone wants fish now. `work_seconds`: this catch's progress, kept on the
## spot across a release (Hard Rule 12).
var state: Dictionary = {"designated": false, "work_seconds": 0.0}
var complete_callback: Callable    # (dwarf_id) -> bool: lands the fish
var float_callback: Callable       # () -> Vector3: where the float rests on the water
var feedback_visible_callback: Callable
var big_callback: Callable         # (dwarf_id) -> bool: this catch is that fisher's big fish
var rate_callback: Callable        # (dwarf_id) -> float: how much a Ranger's patience speeds it


func ensure_lease() -> void:
	if bool(state.designated) and lease_id < 0:
		lease_id = TaskManager.add_task(task_type, origin, {}, source_id)


## The zone has enough fish, or its water is fished out: a lease no one has taken goes. A
## fisher already at work lands this one catch.
func withdraw_lease() -> void:
	if lease_id < 0: return
	var task := TaskManager.get_task(lease_id)
	if task == null or task.assigned_to < 0:
		var id := lease_id
		lease_id = -1
		if task != null: TaskManager.cancel_task(id)


func stand_cells(_from: Vector3i) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	if NavGrid.is_walkable(origin): result.append(origin)
	return result


func nearest_stand_target(_from: Vector3i) -> Vector3i:
	return origin if NavGrid.is_walkable(origin) else Vector3i(-1, -1, -1)


func prefer_work_stand(_cell: Vector3i) -> void:
	pass


func reserve_work(dwarf_id: int, from: Vector3i) -> Array[Vector3i]:
	var empty: Array[Vector3i] = []
	if not bool(state.designated) or (reserved_by >= 0 and reserved_by != dwarf_id):
		return empty
	var cells := stand_cells(from)
	if not cells.is_empty(): reserved_by = dwarf_id
	return cells


func is_work_position(cell: Vector3i) -> bool:
	return cell == origin and NavGrid.is_walkable(cell)


func advance_work(dwarf_id: int, seconds: float) -> bool:
	if reserved_by != dwarf_id or not bool(state.designated):
		return false
	state.work_seconds = minf(float(state.work_seconds) + maxf(seconds, 0.0), duration)
	if float(state.work_seconds) >= duration and complete_callback.is_valid():
		var task := TaskManager.get_task(lease_id)
		if task == null or task.attempt == null: return false
		return TaskManager.commit_step(dwarf_id, task.id, task.attempt.generation, "surface", func(): return bool(complete_callback.call(dwarf_id)))
	return false


func remaining_work() -> float:
	return maxf(0.0, duration - float(state.work_seconds))


## Whether this catch lands as `dwarf_id`'s big fish: the pose hangs it on the line.
func big_for(dwarf_id: int) -> bool:
	return big_callback.is_valid() and bool(big_callback.call(dwarf_id))


## The work rate a fisher's patience adds this season, 1 without (DwarfWorkExecution).
func rate_for(dwarf_id: int) -> float:
	return float(rate_callback.call(dwarf_id)) if rate_callback.is_valid() else 1.0


## Where the dwarf faces and the line ends: the float on the water in front.
func chop_contact(_from: Vector3) -> Vector3:
	if float_callback.is_valid(): return float_callback.call()
	return Vector3(water) + Vector3(.5, .9, .5)


func release_worker(dwarf_id: int) -> void:
	if reserved_by == dwarf_id:
		reserved_by = -1


func feedback_visible() -> bool:
	return feedback_visible_callback.is_valid() and bool(feedback_visible_callback.call())


func display_name() -> String:
	return "Fishing Zone %d" % zone_id


# WorkSourceTable routing contract.
func work_task_gone(task: Task, _dwarf_id: int) -> void:
	if task.id != lease_id:
		return
	reserved_by = -1
	lease_id = -1
	ensure_lease()


func work_task_released(_task: Task, dwarf_id: int) -> void:
	release_worker(dwarf_id)


func work_source_retired() -> void:
	reserved_by = -1
