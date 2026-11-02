extends RefCounted

## A batch left on its workshop to finish by itself (doc 292): two fish hung on the drying rack
## dry there for their recipe's `dry_hours`. Once dry it is a COLLECT work source, as a fishing
## spot is a FISH one: a Ranger walks to the rack and takes the batch down by hand in the
## recipe's `collect_seconds`. CraftingManager owns the batches, keeps their workshop claimed
## while one hangs and saves them; what taking it down gives is its `complete_callback`.
var task_type: int = Task.Type.COLLECT
var source_id := -1
var lease_id := -1
var reserved_by := -1
var installed_id := -1             # the workshop it hangs on, and the work journal's identity
var origin := Vector3i.ZERO        # that workshop's origin cell: the lease's position
var workshop_name := "Workshop"
var recipe: Dictionary = {}
var input_key := ""                # the fish hung, given back if the rack goes before they dry
var input_count := 0
var material_id := ""
var started := 0.0                 # WorldClock.elapsed_days() when it was hung
var duration := 4.0                # work seconds to take it down
var collected := false
## `designated`: dry and waiting to be taken down. `work_seconds`: the take-down's progress,
## kept across a release (Hard Rule 12).
var state: Dictionary = {"designated": false, "work_seconds": 0.0}
var stands_callback: Callable      # () -> Array: the floor cells beside the workshop
var contact_callback: Callable     # (from: Vector3) -> Vector3: where the hands reach
var complete_callback: Callable    # (dwarf_id) -> bool: takes the batch down
var _preferred := Vector3i(-1, -1, -1)


## Game hours until it is dry; 0 once it is.
func hours_left() -> float:
	var hours := float(recipe.get("dry_hours", 0.0))
	return maxf(0.0, hours - (WorldClock.elapsed_days() - started) * float(WorldClock.hours_per_day()))


func dry() -> bool:
	return hours_left() <= 0.0


## Once dry, it posts one take-down lease.
func ensure_lease() -> void:
	state.designated = dry() and not collected
	if bool(state.designated) and lease_id < 0:
		lease_id = TaskManager.add_task(task_type, origin, {}, source_id)


func stand_cells(_from: Vector3i) -> Array[Vector3i]:
	var cells: Array[Vector3i] = []
	if stands_callback.is_valid(): cells.assign(stands_callback.call())
	if _preferred in cells:
		cells.erase(_preferred)
		cells.push_front(_preferred)
	return cells


func nearest_stand_target(from: Vector3i) -> Vector3i:
	var best := Vector3i(-1, -1, -1)
	var distance := INF
	for cell: Vector3i in stand_cells(from):
		var gap := Vector3(cell - from).length_squared()
		if gap < distance:
			best = cell
			distance = gap
	return best


func prefer_work_stand(cell: Vector3i) -> void:
	_preferred = cell


func reserve_work(dwarf_id: int, from: Vector3i) -> Array[Vector3i]:
	var empty: Array[Vector3i] = []
	if not bool(state.designated) or (reserved_by >= 0 and reserved_by != dwarf_id): return empty
	var cells := stand_cells(from)
	if not cells.is_empty(): reserved_by = dwarf_id
	return cells


func is_work_position(cell: Vector3i) -> bool:
	return cell in stand_cells(cell)


func advance_work(dwarf_id: int, seconds: float) -> bool:
	if reserved_by != dwarf_id or not bool(state.designated): return false
	state.work_seconds = minf(float(state.work_seconds) + maxf(seconds, 0.0), duration)
	if float(state.work_seconds) >= duration and complete_callback.is_valid():
		var task := TaskManager.get_task(lease_id)
		if task == null or task.attempt == null: return false
		return TaskManager.commit_step(dwarf_id, task.id, task.attempt.generation, "surface", func(): return bool(complete_callback.call(dwarf_id)))
	return false


func remaining_work() -> float:
	return maxf(0.0, duration - float(state.work_seconds))


## Where the hands reach: the rack's crossbar, where the fish hang.
func chop_contact(from: Vector3) -> Vector3:
	return contact_callback.call(from) if contact_callback.is_valid() else Vector3(origin) + Vector3(.5, 1.6, .5)


func release_worker(dwarf_id: int) -> void:
	if reserved_by == dwarf_id: reserved_by = -1


func feedback_visible() -> bool:
	return true


func display_name() -> String:
	return workshop_name


func serialize() -> Dictionary:
	var data := {"bench": installed_id, "origin": SaveManager.pack_v3i(origin), "recipe": String(recipe.get("id", "")),
		"input": input_key, "inputs": input_count, "started": started}
	if not material_id.is_empty(): data["material"] = material_id
	return data


# WorkSourceTable routing contract.
func work_task_gone(task: Task, _dwarf_id: int) -> void:
	if task.id != lease_id: return
	reserved_by = -1
	lease_id = -1
	ensure_lease()   # a lease cancelled while the batch still hangs is posted again


func work_task_released(_task: Task, dwarf_id: int) -> void:
	release_worker(dwarf_id)


func work_source_retired() -> void:
	reserved_by = -1
