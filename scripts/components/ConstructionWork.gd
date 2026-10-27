extends FurnitureGhostComponent

## Project-owned stock and per-voxel work; deliveries have independent leases.
const Materials = preload("res://scripts/components/ConstructionMaterials.gd")
const INVALID := Vector3i(-1,-1,-1)
var controller: Node
var construction_kind := "stone"
var wood := ""                    # logs (doc 275): the wood they are built from
var directions: Dictionary = {}   # logs: which way each cell's log lies, up, x or z
var cells: Array[Vector3i] = []
var total_blocks := 0
var target := INVALID
var progress := 0.0
var work_progress: Dictionary = {}
var materials: RefCounted
var builder_id := -1
var _stand_targets: Dictionary = {}

## The staged FETCH_BUILD lease, or -1.
func lease_id() -> int:
	return _lease_id


func display_name() -> String:
	return "%s (%d blocks)" % [type_name(construction_kind,wood),cells.size()]

## A kind's name, a log's with its wood: "Native stone", "Horizontal pine log" (doc 275).
static func type_name(kind: String, of_wood: String) -> String:
	var definition := BlockRegistry.get_construction_def(kind)
	if not definition.has("logs"): return String(definition.get("type_label",definition.get("label","")))
	var words := BlockRegistry.get_wood(of_wood)
	return "%s %s log" % [String(definition.type_label).get_slice(" ",0),String(words.get("label","")).to_lower()]

## What a kind's blocks cost in words: its good, or a wood's logs ("1 pine log", "18 pine logs").
static func good_words(kind: String, of_wood: String, count := 2) -> String:
	var definition := BlockRegistry.get_construction_def(kind)
	if not definition.has("logs"): return String(definition.get("good","materials"))
	return String(BlockRegistry.get_wood(of_wood).get("one" if count == 1 else "many",definition.good))

## A kind's picture; a log's shows its wood.
static func picture(kind: String, of_wood: String) -> String:
	return String(BlockRegistry.get_construction_def(kind).get("picture","")).replace("{wood}",of_wood)

func item_keys() -> Array[String]:
	return BlockRegistry.construction_goods(construction_kind,wood)

func initialize_materials() -> void:
	materials = Materials.new()
	materials.setup(self)

func ready_for_staged_work() -> bool:
	return materials != null and materials.count() >= cells.size() and not cells.is_empty()

func item_available() -> bool:
	return ready_for_staged_work()

func work_waiting_reason() -> String:
	return "Waiting for construction access" if ready_for_staged_work() else "Delivering %s to the materials crate" % good_words(construction_kind,wood)

func work_stands(_from: Vector3i) -> Array[Vector3i]:
	_stand_targets.clear()
	var result: Array[Vector3i] = []
	var obstacles: Dictionary = controller.obstacle_snapshot()
	var pending := {}
	for cell: Vector3i in cells: pending[cell] = true
	for cell: Vector3i in cells:
		if not controller.build_reason(cell, false, true, "stone", obstacles).is_empty(): continue
		for stand: Vector3i in controller.stands_for(cell):
			# Stay outside unfinished plans so later blocks cannot bury the worker.
			var obstructed := false
			for dy in range(1,4):
				if pending.has(stand+Vector3i(0,dy,0)): obstructed = true
			if obstructed: continue
			if not _stand_targets.has(stand):
				_stand_targets[stand] = cell
				result.append(stand)
	return result

## Scheduler hook: prove work access without searching for loose supplies.
func advance_fetch_plan(worker: DwarfAgent, context: Dictionary, budget: int, deadline: int) -> int:
	if not ready_for_staged_work(): return NavGrid.ProbeResult.UNREACHABLE
	var from := worker.current_cell()
	if context.get("from",INVALID) != from or (context.has("route_query") and not context.route_query.is_empty() and not NavGrid.search_is_current(context.route_query)):
		context.clear()
	if context.is_empty():
		var goals := {}
		for stand: Vector3i in work_stands(from): goals[stand] = true
		context.merge({"from":from,"goals":goals,"route_query":{},"reason":"Checking construction access"})
		return NavGrid.ProbeResult.SEARCHING
	if context.goals.is_empty():
		context.reason = "No access to supported unfinished blocks"
		return NavGrid.ProbeResult.UNREACHABLE
	var result := preload("WorkRouteProbe.gd").advance(context.route_query,from,context.goals.keys()[0],budget,deadline,false,context.goals)
	if result == NavGrid.ProbeResult.REACHABLE:
		var stand: Vector3i = context.route_query.path.back()
		if stand not in work_stands(from):
			context.clear()
			return NavGrid.ProbeResult.SEARCHING
		NavGrid.remember_reachable_path(context.route_query)
		prefer_fetch_plan({"dwarf_id":worker.dwarf_id,"from":from,"delivery_stand":stand})
	return result

func prefer_fetch_plan(plan: Dictionary) -> void:
	target = _stand_targets.get(plan.delivery_stand,INVALID)
	progress = float(work_progress.get(target,0.0))
	super.prefer_fetch_plan(plan)

func nearest_stand_target(from: Vector3i) -> Vector3i:
	var stands: Array[Vector3i] = controller.stands_for(target) if target.x >= 0 else work_stands(from)
	stands.sort_custom(func(a: Vector3i,b: Vector3i): return from.distance_squared_to(a)<from.distance_squared_to(b))
	return stands[0] if not stands.is_empty() else INVALID

func reserve_fetch(dwarf_id: int, from: Vector3i) -> Dictionary:
	if not ready_for_staged_work() or _preferred_fetch.is_empty() or not cells.has(target): return {}
	var plan := _preferred_fetch
	_preferred_fetch = {}
	if int(plan.dwarf_id) != dwarf_id or plan.from != from or builder_id >= 0: return {}
	if plan.delivery_stand not in controller.stands_for(target): return {}
	builder_id = dwarf_id
	_delivery_stands[dwarf_id] = plan.delivery_stand
	return {"work_only":true}

func remaining_work() -> float:
	return maxf(0.0,float(def.work_seconds)-progress)

func total_remaining_work() -> float:
	var seconds := 0.0
	for cell: Vector3i in cells: seconds += maxf(0.0,float(def.work_seconds)-float(work_progress.get(cell,0.0)))
	return seconds

func advance_install(seconds: float) -> float:
	progress += minf(maxf(seconds,0),remaining_work())
	work_progress[target] = progress
	return remaining_work()

func work_facing(from: Vector3i) -> Vector3i:
	return Vector3i(target.x-from.x,0,target.z-from.z)

func can_complete_build() -> bool:
	if not ready_for_staged_work() or not cells.has(target) or not controller.build_reason(target,false).is_empty(): return false
	var worker: DwarfAgent = TaskManager.get_agent(builder_id)
	return is_instance_valid(worker) and worker.current_cell() in controller.stands_for(target)

func commit_staged_build(dwarf_id: int) -> bool:
	if dwarf_id != builder_id or not can_complete_build() or remaining_work() > .0001: return false
	if materials.consume_one().is_empty(): return false
	controller.commit_block(self)
	cells.erase(target)
	work_progress.erase(target)
	return true

## Keep the same lease and stance while another supported block is reachable.
## Replanning is only needed after this standing position has no work left.
func continue_staged_build(dwarf_id: int) -> bool:
	if dwarf_id != builder_id or not ready_for_staged_work(): return false
	var worker: DwarfAgent = TaskManager.get_agent(dwarf_id)
	if not is_instance_valid(worker): return false
	var stand := worker.current_cell()
	if not NavGrid.is_walkable(stand): return false
	for dy in range(1,4):
		if cells.has(stand+Vector3i(0,dy,0)): return false
	var obstacles: Dictionary = controller.obstacle_snapshot()
	var next := INVALID
	for cell: Vector3i in cells:
		if absi(cell.x-stand.x)+absi(cell.z-stand.z) != 1: continue
		if stand not in controller.stands_for(cell): continue
		if not controller.build_reason(cell,false,true,construction_kind,obstacles).is_empty(): continue
		if next == INVALID: next = cell
		# Finish the current column before turning to other reachable work.
		if cell.x == target.x and cell.z == target.z:
			next = cell
			break
	if next == INVALID: return false
	target = next
	progress = float(work_progress.get(target,0.0))
	return true

func update_lease() -> void:
	materials.update_leases()
	if _lease_id < 0 and ready_for_staged_work():
		_lease_id = TaskManager.add_task(Task.Type.FETCH_BUILD,origin_cell,{"construction_id":ghost_id},source_id)

func cancel_fetch(dwarf_id: int) -> void:
	_delivery_stands.erase(dwarf_id)
	_preferred_fetch.clear()
	if builder_id == dwarf_id: builder_id = -1
	target = INVALID
	progress = 0
