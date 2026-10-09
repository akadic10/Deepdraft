extends RefCounted

## One designated tree (felling or fruit picking), one worker lease. Progress lives in the flora owner's
## saved record, not on a worker or on the replaceable seasonal visual.
# Boulders share the adjacent-work lease/release contract, with their own type
# and tombstone field; presentation/loot remain with the owning system.
var task_type: int = Task.Type.FELL_TREE
var removed_key := "felled"
var source_id := -1
var lease_id := -1
var reserved_by := -1
var origin := Vector3i.ZERO
var footprint := 1
var duration := 1.0
var state: Dictionary = {}
var complete_callback: Callable
var contact_distance_callback: Callable
var feedback_visible_callback: Callable
var work_contact_callback: Callable
var _probe_cursor := 0
var _probed_stand := Vector3i(-1, -1, -1)


func ensure_lease() -> void:
	if bool(state.get("designated", false)) and not bool(state.get(removed_key, false)) and lease_id < 0:
		lease_id = TaskManager.add_task(task_type, origin, {}, source_id)


func stand_cells(from: Vector3i) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	for offset in range(footprint):
		for column: Vector2i in [Vector2i(origin.x - 1, origin.z + offset),
			Vector2i(origin.x + footprint, origin.z + offset),
			Vector2i(origin.x + offset, origin.z - 1),
			Vector2i(origin.x + offset, origin.z + footprint)]:
			var cell := NavGrid.walkable_floor_at(column.x, column.y, origin.y, 1)
			if cell.y >= 0:
				result.append(cell)
	result.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		return Vector3(a - from).length_squared() < Vector3(b - from).length_squared())
	return result


## Rotate the probe through alternative sides across retries. A blocked nearest
## side must not permanently starve a tree whose other side can be reached.
func nearest_stand_target(from: Vector3i) -> Vector3i:
	var cells := stand_cells(from)
	if cells.is_empty():
		return Vector3i(-1, -1, -1)
	_probed_stand = cells[_probe_cursor % cells.size()]
	_probe_cursor += 1
	return _probed_stand


## Only the chosen worker's successful scheduler probe affects execution.
## Comparing idle workers calls stand_cells() without changing reservations.
func prefer_work_stand(cell: Vector3i) -> void:
	_probed_stand = cell


func reserve_work(dwarf_id: int, from: Vector3i) -> Array[Vector3i]:
	var empty: Array[Vector3i] = []
	if not bool(state.get("designated", false)) or bool(state.get(removed_key, false)):
		return empty
	if reserved_by >= 0 and reserved_by != dwarf_id:
		return empty
	var cells := stand_cells(from)
	if cells.is_empty():
		return empty
	reserved_by = dwarf_id
	if cells.has(_probed_stand):
		cells.erase(_probed_stand)
		cells.push_front(_probed_stand)
	return cells


func is_work_position(cell: Vector3i) -> bool:
	if absi(cell.y - origin.y) > 1 or not NavGrid.is_walkable(cell):
		return false
	return ((cell.x == origin.x - 1 or cell.x == origin.x + footprint) and cell.z >= origin.z and cell.z < origin.z + footprint) \
		or ((cell.z == origin.z - 1 or cell.z == origin.z + footprint) and cell.x >= origin.x and cell.x < origin.x + footprint)


func advance_work(dwarf_id: int, seconds: float) -> bool:
	if reserved_by != dwarf_id or not bool(state.get("designated", false)) or bool(state.get(removed_key, false)):
		return false
	state["work_seconds"] = minf(float(state.get("work_seconds", 0.0)) + maxf(seconds, 0.0), duration)
	if float(state["work_seconds"]) >= duration and complete_callback.is_valid():
		return bool(complete_callback.call(dwarf_id))
	return false


## A one-time visual aim query at work start. Use the visible trunk surface
## when available; the logical footprint remains the offscreen fallback.
func chop_contact(from: Vector3) -> Vector3:
	if work_contact_callback.is_valid(): return work_contact_callback.call(from)
	var center := Vector3(origin.x + footprint * .5,
		clampf(origin.y + 2.1, from.y + .5, from.y + 1.8), origin.z + footprint * .5)
	var start := Vector3(from.x,center.y,from.z)
	var direction := (center-start).normalized()
	var distance := INF
	if contact_distance_callback.is_valid():
		distance = float(contact_distance_callback.call(start,center))
	if not is_finite(distance):
		distance = maxf(start.distance_to(center)-footprint*.5,.35)
	return start + direction * (distance + .035)


func release_worker(dwarf_id: int) -> void:
	if reserved_by == dwarf_id:
		reserved_by = -1


func feedback_visible() -> bool:
	return feedback_visible_callback.is_valid() and bool(feedback_visible_callback.call())


func on_task_gone(task: Task) -> void:
	if task.id != lease_id:
		return
	reserved_by = -1
	lease_id = -1
	ensure_lease()
