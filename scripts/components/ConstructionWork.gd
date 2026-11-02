extends FurnitureGhostComponent

## Project-owned stock and per-voxel work; deliveries have independent leases.
## A plan may hold several materials (doc 276): a placed blueprint is one plan whose blocks keep
## their own kind and wood where they differ from the plan's. Its crate stages each good for its
## own blocks, and a good's blocks are built once all of that good is in.
## Boxed-in blocks (doc 276): a block whose four sides are all its plan's unbuilt blocks or solid
## is built before the blocks around it, from the middle outward, its builder standing under the
## plan's own unbuilt blocks nearer the edge, since there is no other floor beside it.
## A replace plan (doc 285) holds solid blocks: its builder digs each old block out with the pick
## for its mining time, then hammers the new one in, and the swap is one terrain write, so the
## cell is never open. Its blocks never box each other in.
const Materials = preload("res://scripts/components/ConstructionMaterials.gd")
const INVALID := Vector3i(-1,-1,-1)
const SIDES: Array[Vector3i] = [Vector3i.LEFT,Vector3i.RIGHT,Vector3i.FORWARD,Vector3i.BACK]
var controller: Node
var construction_kind := "stone"  # the plan's own kind; a block of another keeps it in `own`
var wood := ""                    # logs (doc 275): the wood they are built from
var directions: Dictionary = {}   # logs: which way each cell's log lies, up, x or z
var own: Dictionary = {}          # cell -> [kind, wood] for a block whose material is not the plan's
var project_name := ""            # a placed blueprint's name; "" for Build and Shapes plans
var replace := false              # Build's Replace (doc 285): each cell's block is swapped, not built in air
var totals: Dictionary = {}       # good -> the blocks planned of it, built ones included
var cells: Array[Vector3i] = []
var total_blocks := 0
var target := INVALID
var progress := 0.0
var work_progress: Dictionary = {}
var materials: RefCounted
var builder_id := -1
var _stand_targets: Dictionary = {}
var _needs: Dictionary = {}
var _needs_size := -1
var _plan_good := ""
var _depths: Dictionary = {}
var _depths_size := -1
var _stand_levels: Array = []   # the stands for each depth, deepest first: [{stand: true}]
var _level := 1                 # the depth the builder is working at

## The staged FETCH_BUILD lease, or -1.
func lease_id() -> int:
	return _lease_id


func display_name() -> String:
	return "%s (%d blocks)" % [project_name if not project_name.is_empty() else title(),cells.size()]

## A plan's name: "Native stone area", or a replace plan's "Replace with native stone".
func title() -> String:
	var type := type_name(construction_kind,wood)
	return "Replace with %s" % type.to_lower() if replace else "%s area" % type

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

## The good a kind's blocks are built from, by item: rough stone, soil or a wood's logs.
static func good_key(kind: String, of_wood: String) -> String:
	var goods := BlockRegistry.construction_goods(kind,of_wood)
	return goods[0] if not goods.is_empty() else ""

## A good's words from its item, as good_words gives them: "oak logs", "1 oak log", "soil".
static func item_words(item: String, count := 2) -> String:
	for each: String in BlockRegistry.woods():
		var words := BlockRegistry.get_wood(each)
		if String(words.get("item_key","")) == item: return String(words.get("one" if count == 1 else "many",item))
	for kind: String in BlockRegistry.construction_keys():
		var definition := BlockRegistry.get_construction_def(kind)
		if String(definition.get("item_key","")) == item: return String(definition.get("good",item))
	return item

## Goods in words, joined: "soil", "oak logs and soil", "rough stone, oak logs and soil".
static func items_words(items: Array) -> String:
	var words: Array[String] = []
	for item: String in items: words.append(item_words(item))
	if words.size() < 2: return "".join(words)
	return "%s and %s" % [", ".join(words.slice(0,-1)),words.back()]

## A kind's picture; a log's shows its wood.
static func picture(kind: String, of_wood: String) -> String:
	return String(BlockRegistry.get_construction_def(kind).get("picture","")).replace("{wood}",of_wood)

## A block's kind and wood: its own where it has one, else the plan's.
func kind_of(cell: Vector3i) -> String:
	return String(own[cell][0]) if own.has(cell) else construction_kind

func wood_of(cell: Vector3i) -> String:
	return String(own[cell][1]) if own.has(cell) else wood

## The good a block is built from.
func good_of(cell: Vector3i) -> String:
	if own.has(cell): return good_key(String(own[cell][0]),String(own[cell][1]))
	if _plan_good.is_empty(): _plan_good = good_key(construction_kind,wood)
	return _plan_good

## How long a block takes to hammer, from its own kind, after a replaced block's dig.
func work_seconds_of(cell: Vector3i) -> float:
	var hammer := float(def.work_seconds) if not own.has(cell) else float(BlockRegistry.get_construction_def(kind_of(cell)).get("work_seconds",def.work_seconds))
	return hammer+dig_seconds_of(cell)

## A replaced block's dig, timed as Mine blocks times it ({swings, swing_time}); {} for a block
## built in air.
func _dig(cell: Vector3i) -> Dictionary:
	return controller.dig_work(cell) if replace else {}

func dig_seconds_of(cell: Vector3i) -> float:
	var dig := _dig(cell)
	return float(dig.get("swings",0))*float(dig.get("swing_time",0.0))

func dig_swing_seconds() -> float:
	return maxf(float(_dig(target).get("swing_time",1.0)),.05)

## Whether the builder is still digging the old block out of the target.
func digging() -> bool:
	return replace and progress < dig_seconds_of(target)

## Where the pick is in its swing, 0 to 1.
func dig_phase() -> float:
	return fposmod(progress,dig_swing_seconds())/dig_swing_seconds()

## How far the hammer has come on the target, after any dig.
func hammer_progress() -> float:
	return maxf(progress-dig_seconds_of(target),0.0)

func play_dig_impact(contact: Vector3, normal: Vector3) -> void:
	controller.play_dig_impact(target,contact,normal)

## Why a block can't be worked now, "" when it can: Replace's rules for a replace plan, else
## Build's for `kind`.
func blocked_reason(cell: Vector3i, kind: String, obstacles: Dictionary = {}) -> String:
	if replace: return controller.replace_reason(cell,kind_of(cell),wood_of(cell),false)
	return controller.build_reason(cell,false,true,kind,obstacles)

## Each good the unbuilt blocks still need, and how many: {item: blocks}. Blocks only leave a
## plan, so the count is kept until the plan shrinks.
func needs() -> Dictionary:
	if _needs_size == cells.size(): return _needs
	_needs = {}
	_needs_size = cells.size()
	if own.is_empty():
		if not cells.is_empty(): _needs[good_of(INVALID)] = cells.size()
		return _needs
	for cell: Vector3i in cells:
		var good := good_of(cell)
		_needs[good] = int(_needs.get(good,0))+1
	return _needs

## How deep each unbuilt block sits in its plan, at its own layer: 1 beside open space, 2 when
## its four sides are its plan's unbuilt blocks or solid, and so on inward; -1 when no path of
## unbuilt blocks leads out. An undiscovered cave counts as rock. Kept until the plan shrinks.
func depths() -> Dictionary:
	if _depths_size == cells.size(): return _depths
	_depths_size = cells.size()
	_depths = {}
	# A swap leaves its cell as solid as it found it, so nothing is closed off.
	if replace:
		for cell: Vector3i in cells: _depths[cell] = 1
		return _depths
	var pending := {}
	for cell: Vector3i in cells: pending[cell] = true
	var queue: Array[Vector3i] = []
	for cell: Vector3i in cells:
		for side: Vector3i in SIDES:
			var near := cell+side
			if pending.has(near) or BlockRegistry.is_solid(WorldData.get_live_block(near.x,near.y,near.z)) or InteriorTracker.is_hidden_cave(near): continue
			_depths[cell] = 1
			queue.append(cell)
			break
	var next := 0
	while next < queue.size():
		var cell := queue[next]
		next += 1
		for side: Vector3i in SIDES:
			var near := cell+side
			if pending.has(near) and not _depths.has(near):
				_depths[near] = int(_depths[cell])+1
				queue.append(near)
	for cell: Vector3i in cells:
		if not _depths.has(cell): _depths[cell] = -1
	return _depths

## Whether a builder may work `cell` from `stand`. A floor under the plan's own unbuilt blocks
## serves only a boxed-in block, and only when every such block above it is nearer the edge than
## the one being built: the builder always has a way out, and nothing deeper is closed off.
func _stand_allowed(stand: Vector3i, cell: Vector3i, depth: Dictionary) -> bool:
	for dy in range(1,4):
		var above := stand+Vector3i(0,dy,0)
		if not depth.has(above): continue
		var under := int(depth[above])
		if int(depth[cell]) < 2 or under < 1 or under >= int(depth[cell]): return false
	return true

## Whether a block waits because it may be the way in to a deeper boxed-in block that can't be
## built just now but soon can: its good is not all in yet, or a dwarf or a loose item is in it.
## Building this one first could close that block off. A block too high to reach holds nothing
## back.
func _keeps_access(cell: Vector3i, depth: Dictionary, ready: Dictionary, obstacles: Dictionary) -> bool:
	for side: Vector3i in SIDES:
		for dy in range(3):
			var near := cell+side-Vector3i(0,dy,0)
			if int(depth.get(near,0)) <= maxi(int(depth[cell]),1): continue
			if not ready.has(good_of(near)) or _held_up(near,obstacles): return true
	return false

## Whether something passing through is in a cell for now: a dwarf, or a loose item to haul clear.
func _held_up(cell: Vector3i, obstacles: Dictionary) -> bool:
	if obstacles.get("loose",{}).has(cell): return true
	var area := AABB(Vector3(cell)+Vector3.ONE*.001,Vector3.ONE*.998)
	for bounds: AABB in obstacles.get("actors",[]):
		if area.intersects(bounds): return true
	return false

## The goods whose blocks can be built now: all of each is in the crate.
func ready_goods() -> Dictionary:
	var result := {}
	if materials == null: return result
	var need := needs()
	for good: String in need:
		if materials.staged_count(good) >= int(need[good]): result[good] = true
	return result

## Every good the plan needs, for its crate.
func item_keys() -> Array[String]:
	var result: Array[String] = []
	for good: String in needs():
		if not good.is_empty(): result.append(good)
	return result

func initialize_materials() -> void:
	materials = Materials.new()
	materials.setup(self)

func ready_for_staged_work() -> bool:
	return not cells.is_empty() and not ready_goods().is_empty()

func item_available() -> bool:
	return ready_for_staged_work()

func work_waiting_reason() -> String:
	if ready_for_staged_work(): return "Waiting for construction access"
	var short: Array = needs().keys().filter(func(good: String) -> bool: return materials.staged_count(good) < int(needs()[good]))
	return "Delivering %s to the materials crate" % items_words(short)

## The floors a builder may work from, each kept for the deepest block it serves. Stay outside
## unfinished plans so later blocks cannot bury the worker, except beside a boxed-in block
## (`_stand_allowed`). The stands for each depth are kept, deepest first, for the route search.
func work_stands(_from: Vector3i) -> Array[Vector3i]:
	_stand_targets.clear()
	_stand_levels.clear()
	var result: Array[Vector3i] = []
	var obstacles: Dictionary = controller.obstacle_snapshot()
	var ready := ready_goods()
	var depth := depths()
	var order: Array[Vector3i] = cells.duplicate()
	order.sort_custom(_deeper_first)
	var levels := {}
	for cell: Vector3i in order:
		if not ready.has(good_of(cell)) or _keeps_access(cell,depth,ready,obstacles): continue
		if not blocked_reason(cell,"stone",obstacles).is_empty(): continue
		var level := maxi(int(depth[cell]),1)
		for stand: Vector3i in controller.stands_for(cell):
			if not _stand_allowed(stand,cell,depth): continue
			if not levels.has(level): levels[level] = {}
			levels[level][stand] = true
			if not _stand_targets.has(stand):
				_stand_targets[stand] = cell
				result.append(stand)
	var deepest: Array = levels.keys()
	deepest.sort()
	deepest.reverse()
	for level: int in deepest: _stand_levels.append(levels[level])
	return result

## Deeper blocks first, then as a plan keeps its cells: lower, then by x and z.
func _deeper_first(a: Vector3i, b: Vector3i) -> bool:
	if int(_depths[a]) != int(_depths[b]): return int(_depths[a]) > int(_depths[b])
	return a.y<b.y if a.y!=b.y else (a.x<b.x if a.x!=b.x else a.z<b.z)

## Scheduler hook: prove work access without searching for loose supplies. The deepest blocks
## are sought first; a depth none of whose floors can be reached gives way to the next.
func advance_fetch_plan(worker: DwarfAgent, context: Dictionary, budget: int, deadline: int) -> int:
	if not ready_for_staged_work(): return NavGrid.ProbeResult.UNREACHABLE
	var from := worker.current_cell()
	if context.get("from",INVALID) != from or (context.has("route_query") and not context.route_query.is_empty() and not NavGrid.search_is_current(context.route_query)):
		context.clear()
	if context.is_empty():
		work_stands(from)
		var levels: Array = _stand_levels.duplicate()
		context.merge({"from":from,"levels":levels,"goals":levels[0] if not levels.is_empty() else {},"route_query":{},"reason":"Checking construction access"})
		return NavGrid.ProbeResult.SEARCHING
	if context.goals.is_empty():
		context.reason = "No access to supported unfinished blocks"
		return NavGrid.ProbeResult.UNREACHABLE
	var result := preload("WorkRouteProbe.gd").advance(context.route_query,from,context.goals.keys()[0],budget,deadline,false,context.goals)
	if result == NavGrid.ProbeResult.UNREACHABLE and context.levels.size() > 1:
		context.levels.pop_front()
		context.goals = context.levels[0]
		context.route_query = {}
		return NavGrid.ProbeResult.SEARCHING
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
	_level = maxi(int(depths().get(target,1)),1)
	super.prefer_fetch_plan(plan)

func nearest_stand_target(from: Vector3i) -> Vector3i:
	var stands: Array[Vector3i] = controller.stands_for(target) if target.x >= 0 else work_stands(from)
	stands.sort_custom(func(a: Vector3i,b: Vector3i): return from.distance_squared_to(a)<from.distance_squared_to(b))
	return stands[0] if not stands.is_empty() else INVALID

func reserve_fetch(dwarf_id: int, from: Vector3i) -> Dictionary:
	if _preferred_fetch.is_empty() or not cells.has(target) or not ready_goods().has(good_of(target)): return {}
	var plan := _preferred_fetch
	_preferred_fetch = {}
	if int(plan.dwarf_id) != dwarf_id or plan.from != from or builder_id >= 0: return {}
	if plan.delivery_stand not in controller.stands_for(target): return {}
	builder_id = dwarf_id
	_delivery_stands[dwarf_id] = plan.delivery_stand
	return {"work_only":true}

func remaining_work() -> float:
	return maxf(0.0,work_seconds_of(target)-progress)

func total_remaining_work() -> float:
	var seconds := 0.0
	for cell: Vector3i in cells: seconds += maxf(0.0,work_seconds_of(cell)-float(work_progress.get(cell,0.0)))
	return seconds

func advance_install(seconds: float) -> float:
	progress += minf(maxf(seconds,0),remaining_work())
	work_progress[target] = progress
	return remaining_work()

func work_facing(from: Vector3i) -> Vector3i:
	return Vector3i(target.x-from.x,0,target.z-from.z)

func can_complete_build() -> bool:
	if not cells.has(target) or not ready_goods().has(good_of(target)) or not blocked_reason(target,"stone").is_empty(): return false
	var worker: DwarfAgent = TaskManager.get_agent(builder_id)
	return is_instance_valid(worker) and worker.current_cell() in controller.stands_for(target)

func commit_staged_build(dwarf_id: int) -> bool:
	if dwarf_id != builder_id or not can_complete_build() or remaining_work() > .0001: return false
	if materials.consume(good_of(target)).is_empty(): return false
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
	var obstacles: Dictionary = controller.obstacle_snapshot()
	var ready := ready_goods()
	var depth := depths()
	var next := INVALID
	for cell: Vector3i in cells:
		if absi(cell.x-stand.x)+absi(cell.z-stand.z) != 1: continue
		# Stay at the depth being built, so the middle is finished before the blocks around it.
		if maxi(int(depth[cell]),1) != _level: continue
		if not ready.has(good_of(cell)) or _keeps_access(cell,depth,ready,obstacles): continue
		if stand not in controller.stands_for(cell) or not _stand_allowed(stand,cell,depth): continue
		if not blocked_reason(cell,kind_of(cell),obstacles).is_empty(): continue
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
