extends RefCounted

## One Farmer's place in a field (doc 309): a surface work source (Task.SURFACE_WORK), as a
## fishing spot is. A field keeps as many of these as Farmers may work it at once, and each posts
## a lease while the field has work for it. The Farmer who takes one is given the nearest job it
## may do (a ripe tile to pull, a plant to hoe under, a tile to sow, ground to hoe), stands beside
## that tile and works it. The lease ends with the job, and the field posts the next.
## FarmingSystem owns the tiles, their plants and the work done on each tile (Hard Rule 12);
## nothing here is saved, and these are rebuilt from their field on restore.
const NOWHERE := Vector3i(-1, -1, -1)
const SIDES: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
## The jobs a hoe does; the others are done by hand.
const HOE_JOBS := ["till", "clear"]

var task_type: int = Task.Type.FARM
var source_id := -1
var lease_id := -1
var reserved_by := -1
var zone_id := -1
var origin := Vector3i.ZERO        # the tile being worked; the field's first tile while idle
var duration := 1.0                # work seconds the job takes
var job := ""                      # "harvest", "clear", "sow" or "till", while a Farmer holds the lease
var crop := ""                     # the crop a harvest pulls or a sowing sows
## `designated`: the field has work for this place. `work_seconds`: the job's progress, kept on
## the tile across a release. `feedback_block`: the ground a hoe strikes, for its sound and dust.
var state: Dictionary = {"designated": false, "work_seconds": 0.0, "feedback_block": "base:terrain:surface:dirt"}
var job_callback: Callable         # (agent or null, from, source) -> {cell, job, crop, seconds, work, block}, {} for none
var allows_callback: Callable      # (agent) -> bool: the field has a job this dwarf may do
var progress_callback: Callable    # (source): the work done on the tile so far
var complete_callback: Callable    # (dwarf_id, source) -> bool: the job is done
var feedback_visible_callback: Callable
var _preferred := NOWHERE


## A job in a Farmer's words: "pulling carrots", "sowing radishes", "hoeing the ground".
static func job_words(job_name: String, crop_key: String) -> String:
	var plural := String(ContentRegistry.crop(crop_key).get("plural_name", "the field"))
	match job_name:
		"harvest": return "pulling " + plural
		"sow": return "sowing " + plural
		"clear": return "hoeing under " + plural
		"till": return "hoeing the ground"
	return "walking to the field"


func ensure_lease() -> void:
	if bool(state.designated) and lease_id < 0:
		lease_id = TaskManager.add_task(task_type, origin, {}, source_id)


## The field has no more work for this place: a lease no one has taken goes. A Farmer already at
## work finishes that one job.
func withdraw_lease() -> void:
	if lease_id < 0: return
	var task := TaskManager.get_task(lease_id)
	if task == null or task.assigned_to < 0:
		var id := lease_id
		lease_id = -1
		if task != null: TaskManager.cancel_task(id)


## Where a dwarf could stand to work a tile: its walkable sides, nearest first, and last the
## tile itself, for one hemmed in on every side.
static func stands_for(cell: Vector3i, from: Vector3i) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	for side: Vector2i in SIDES:
		var stand := NavGrid.walkable_floor_at(cell.x + side.x, cell.z + side.y, cell.y, 1)
		if stand.y >= 0: result.append(stand)
	result.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		return Vector3(a - from).length_squared() < Vector3(b - from).length_squared())
	if NavGrid.is_walkable(cell): result.append(cell)
	return result


## A quote for the scheduler: beside the nearest job any Farmer may do. Nothing is reserved.
func stand_cells(from: Vector3i) -> Array[Vector3i]:
	if reserved_by >= 0: return stands_for(origin, from)
	var found: Dictionary = job_callback.call(null, from, self) if job_callback.is_valid() else {}
	if found.is_empty(): return []
	return stands_for(found.cell, from)


func nearest_stand_target(from: Vector3i) -> Vector3i:
	var cells := stand_cells(from)
	return NOWHERE if cells.is_empty() else cells[0]


func prefer_work_stand(cell: Vector3i) -> void:
	_preferred = cell


## The Farmer takes its job here: the nearest it may do, from where it stands.
func reserve_work(dwarf_id: int, from: Vector3i) -> Array[Vector3i]:
	var empty: Array[Vector3i] = []
	if not bool(state.designated) or (reserved_by >= 0 and reserved_by != dwarf_id) or not job_callback.is_valid():
		return empty
	var found: Dictionary = job_callback.call(TaskManager.get_agent(dwarf_id), from, self)
	if found.is_empty(): return empty
	origin = found.cell
	job = String(found.job)
	crop = String(found.crop)
	duration = maxf(float(found.seconds), .05)
	state.work_seconds = minf(float(found.work), duration)
	state.feedback_block = String(found.block)
	reserved_by = dwarf_id
	var cells := stands_for(origin, from)
	if cells.has(_preferred):
		cells.erase(_preferred)
		cells.push_front(_preferred)
	return cells


func is_work_position(cell: Vector3i) -> bool:
	if absi(cell.y - origin.y) > 1 or not NavGrid.is_walkable(cell): return false
	return absi(cell.x - origin.x) + absi(cell.z - origin.z) <= 1


func advance_work(dwarf_id: int, seconds: float) -> bool:
	if reserved_by != dwarf_id or job.is_empty(): return false
	state.work_seconds = minf(float(state.work_seconds) + maxf(seconds, 0.0), duration)
	if progress_callback.is_valid(): progress_callback.call(self)
	if float(state.work_seconds) >= duration and complete_callback.is_valid():
		var task := TaskManager.get_task(lease_id)
		if task == null or task.attempt == null: return false
		return TaskManager.commit_step(dwarf_id, task.id, task.attempt.generation, "surface", func(): return bool(complete_callback.call(dwarf_id, self)))
	return false


func remaining_work() -> float:
	return maxf(0.0, duration - float(state.work_seconds))


## How the job is done: the hoe's chop for hoeing ground and hoeing a plant under, the hands
## for sowing and pulling (DwarfWorkExecution).
func work_motion() -> String:
	return "hoe" if job in HOE_JOBS else "hands"


## Where the hoe strikes and the hands reach: the top of the tile, toward the Farmer's side of it.
func chop_contact(from: Vector3) -> Vector3:
	var center := Vector3(origin) + Vector3(.5, 1.0, .5)
	var toward := Vector3(from.x - center.x, 0, from.z - center.z)
	if toward.length() > .01: center += toward.normalized() * .15
	return center + Vector3(0, .04 if job in HOE_JOBS else .3, 0)


func release_worker(dwarf_id: int) -> void:
	if reserved_by != dwarf_id: return
	reserved_by = -1
	job = ""


func allows_worker(agent: DwarfAgent) -> bool:
	return not allows_callback.is_valid() or bool(allows_callback.call(agent))


func feedback_visible() -> bool:
	return feedback_visible_callback.is_valid() and bool(feedback_visible_callback.call())


func display_name() -> String:
	return "Field %d" % zone_id


func work_waiting_reason() -> String:
	return "Waiting for a Farmer"


# WorkSourceTable routing contract. The field posts the next lease itself (its on_gone hook), once
# it has counted the work that is left.
func work_task_gone(task: Task, _dwarf_id: int) -> void:
	if task.id != lease_id: return
	reserved_by = -1
	lease_id = -1
	job = ""


func work_task_released(_task: Task, dwarf_id: int) -> void:
	release_worker(dwarf_id)


func work_source_retired() -> void:
	reserved_by = -1
	job = ""


## The dwarf that holds this source, for TaskManager's self-check (WorkSourceAdapter).
func claimed_workers() -> Array:
	return [reserved_by] if reserved_by >= 0 else []
