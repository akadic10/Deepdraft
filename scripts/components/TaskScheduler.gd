extends RefCounted

## The colony scheduler's matching half (doc 16 §2.4 / §2.5): the idle pass
## over priority buckets, per-type and specialised (haul, craft, surface, move)
## comparisons, resumable route probes, worker rejection and the lease handoff
## (assign). TaskManager owns the task tables, signals, config and wake
## machinery; it hands this object the same table objects, so both read and
## mutate one set of tables. Scheduling state that only matching uses lives
## here. See TaskManager.gd for the scheduling model.

const Attempt = preload("res://scripts/components/WorkAttempt.gd")
const RouteProbe = preload("res://scripts/components/WorkRouteProbe.gd")
const FetchPlanner = preload("res://scripts/components/FurnitureFetchPlanner.gd")

# ── Shared tables (owned by TaskManager; the same Dictionary/Array objects) ──
var _tasks: Dictionary
var _pending: Dictionary
var _active: Dictionary
var _idle_dwarves: Array[int]
var _agents: Dictionary
var _work_sources: Dictionary
var _planning_holds: Dictionary

# ── Limits (task_config.json; TaskManager forwards its config fields here) ───
var budget_usec: int = 1000
var max_probes_per_wake: int = 8
var probe_node_cap: int = 200

# ── Matching state ────────────────────────────────────────────────────────────
var _worker_cursor: Dictionary = {}
var _family_frontiers: Dictionary = {} # task_id -> suspended specialized comparison
var _family_quanta: Dictionary = {}
var _scan_cursor: Dictionary = {}      # Task.Type -> int (resumable scan position)
var _haul_match: Dictionary = {}       # one resumable, read-only worker comparison
var _haul_route_cache: Dictionary = {} # shared read-only geometry, independent of goods/leases
var _surface_match: Dictionary = {}    # adjacent surface work, including shrub uprooting
var _move_match: Dictionary = {}       # exact-plant pickup after uprooting
var _craft_match: Dictionary = {}      # first ingredient pickup, then a free workshop
var _work_probe: Dictionary = {}       # resumable ordinary work-source route
var _work_probes: Dictionary = {}      # type -> suspended ordinary route
var _surface_matches: Dictionary = {} # type -> suspended surface comparison
var next_type: int = -1               # next bucket after a budget yield
var _worker_rejections: Dictionary = {} # lease -> failed idle workers, valid for this navigation/pool revision
var idle_version := 0                 # a newly idle dwarf must join that comparison

# ── Instrumentation (doc 16 Phase 0) ─────────────────────────────────────────
var _wake_count: int = 0
var _worst_wake_usec: int = 0
var _probes_total: int = 0
var _probes_at_last_stats: int = 0
var _stats_last_msec: int = 0


func _init(tables: Dictionary = {}) -> void:
	if tables.is_empty(): return
	_tasks = tables.tasks
	_pending = tables.pending
	_active = tables.active
	_idle_dwarves = tables.idle_dwarves
	_agents = tables.agents
	_work_sources = tables.work_sources
	_planning_holds = tables.planning_holds


## Clears transient matching state before a scene reload (TaskManager.reset_runtime_state).
func reset() -> void:
	_haul_route_cache.clear()
	_family_frontiers.clear()
	_family_quanta.clear()
	_worker_rejections.clear()
	_worker_cursor.clear()
	_work_probe.clear()
	_work_probes.clear()
	_surface_matches.clear()
	next_type = -1
	_scan_cursor.clear()
	_haul_match.clear()
	_surface_match.clear()
	_move_match.clear()
	_craft_match.clear()
	idle_version += 1


## Quotes and resumable probes may include a now-ineligible dwarf or route.
func clear_matches() -> void:
	_work_probe.clear()
	_surface_match.clear()
	_work_probes.clear()
	_surface_matches.clear()
	next_type = -1
	_move_match.clear()
	_craft_match.clear()
	_haul_match.clear()


## Work policy (professions, permissions) changed: every comparison restarts.
func policy_changed() -> void:
	_worker_rejections.clear()
	for task: Task in _tasks.values(): task.planning_context.clear()
	idle_version += 1
	clear_matches()


## A lease returned to the pool or was retried: drop its suspended comparison.
func forget_task(task_id: int) -> void:
	_family_frontiers.erase(task_id)
	_worker_rejections.erase(task_id)


func forget_rejections(task_id: int) -> void:
	_worker_rejections.erase(task_id)


## A lease left the pending buckets.
func forget_pending(task: Task) -> void:
	_family_frontiers.erase(task.id)
	_family_quanta.erase(task.id)
	_worker_rejections.erase(task.id)
	if int(_craft_match.get("task_id",-1)) == task.id: _craft_match.clear()


func rejection_count(task_id: int) -> int:
	return (_worker_rejections.get(task_id,{}).get("workers",{}) as Dictionary).size()


## Terrain changed in this chunk: drop every route proof that crossed it.
func chunk_dirtied(chunk: Vector3i) -> void:
	for task: Task in _tasks.values():
		for worker_id: int in task.planning_context:
			var context: Dictionary = task.planning_context[worker_id]
			if context.get("route_query",{}).get("chunks",{}).has(chunk) or context.get("route_dependencies",{}).has(chunk):
				context.clear()
				_worker_rejections.erase(task.id)
				task.retry_at = 0
				task.recovery_paused = false
	for context: Dictionary in [_work_probe, _surface_match, _move_match, _haul_match, _craft_match] + _work_probes.values() + _surface_matches.values() + _family_frontiers.values():
		var query: Dictionary = context.get("route_query", {})
		# Completed pickup legs matter too while a delivery probe is pending.
		if query.get("chunks",{}).has(chunk) or context.get("route_dependencies", {}).has(chunk):
			context.clear()


# ── Stats (debug overlay, doc 16 Phase 0) ────────────────────────────────────

func stats() -> Dictionary:
	var now := Time.get_ticks_msec()
	var pending_total := 0
	var blocked := 0
	var oldest_age_s := 0.0
	var by_type: Dictionary = {}
	for type in _pending:
		var ids: Array = _pending[type]
		by_type[Task.type_name(int(type))] = ids.size()
		pending_total += ids.size()
		for id in ids:
			var task: Task = _tasks.get(id)
			if task == null:
				continue
			if now < task.retry_at:
				blocked += 1
			var age := float(now - task.created_at) / 1000.0
			if age > oldest_age_s:
				oldest_age_s = age
	var dt := float(now - _stats_last_msec) / 1000.0
	var probes_rate := 0.0
	if _stats_last_msec > 0 and dt > 0.0:
		probes_rate = float(_probes_total - _probes_at_last_stats) / dt
	_stats_last_msec = now
	_probes_at_last_stats = _probes_total
	return {
		"pending_total": pending_total,
		"pending_by_type": by_type,
		"active": _active.size(),
		"blocked": blocked,
		"oldest_pending_age_s": oldest_age_s,
		"probes_per_sec": probes_rate,
		"worst_wake_usec": _worst_wake_usec,
		"wake_count": _wake_count,
	}


# ── The scheduler (doc 16 §2.4 / §2.5) ───────────────────────────────────────

func run() -> void:
	if _idle_dwarves.is_empty() or _tasks.is_empty():
		return
	var t_start := Time.get_ticks_usec()
	var probes_left := max_probes_per_wake
	_wake_count += 1

	_assign_idle_pass(probes_left, t_start)

	var wake_usec := int(Time.get_ticks_usec() - t_start)
	if wake_usec > _worst_wake_usec:
		_worst_wake_usec = wake_usec


func _within_budget(t_start: int, probes_left: int) -> bool:
	if Time.get_ticks_usec() - t_start < budget_usec and probes_left > 0: return true
	TaskManager.request_wake()
	return false


func _assign_idle_pass(probes_left: int, t_start: int) -> int:
	# Visit priority buckets before workers. Otherwise a nearer dwarf could be
	# pulled into surface work before considering their higher-priority jobs.
	var types := _pending.keys().filter(func(type: int): return not (_pending[type] as Array).is_empty())
	types.sort_custom(func(a: int, b: int) -> bool:
		var pa := _bucket_priority(a)
		var pb := _bucket_priority(b)
		return pa > pb if pa != pb else a < b)
	var start := maxi(0, types.find(next_type))
	next_type = -1
	for offset in range(types.size()):
		var index := (start + offset) % types.size()
		var type: int = types[index]
		if not _within_budget(t_start, probes_left):
			next_type = type
			return 0
		# A search can span many wakes, especially for mining above an unfinished
		# ladder. Give other buckets a turn after it yields; otherwise the access
		# job can never run. Each bucket retains its own bounded search frontier.
		_work_probe = _work_probes.get(type, {})
		_surface_match = _surface_matches.get(type, {})
		probes_left = _assign_bucket(type, probes_left, t_start)
		if _work_probe.is_empty(): _work_probes.erase(type)
		else: _work_probes[type] = _work_probe
		if _surface_match.is_empty(): _surface_matches.erase(type)
		else: _surface_matches[type] = _surface_match
		if not _within_budget(t_start, probes_left):
			next_type = types[(index + 1) % types.size()]
			return 0
	return probes_left


func _assign_bucket(type: int, probes_left: int, t_start: int) -> int:
	if type in [Task.Type.HAUL,Task.Type.CRAFT] or _is_surface_work(type):
		return _assign_specialized_bucket(type,probes_left,t_start)
	# Give idle Miners first refusal without bypassing the bucket order.
	var candidates := _idle_dwarves.duplicate()
	if type == Task.Type.MINE:
		var specialists: Array[int] = []
		var generalists: Array[int] = []
		for id: int in candidates:
			var dwarf: DwarfAgent = _agents.get(id)
			if is_instance_valid(dwarf) and dwarf.profession == "base:profession:miner": specialists.append(id)
			else: generalists.append(id)
		candidates = specialists + generalists
	var worker_start := int(_worker_cursor.get(type,0))
	for worker_offset in range(candidates.size()):
		var dwarf_id: int = candidates[(worker_start+worker_offset)%candidates.size()]
		if not _within_budget(t_start, probes_left): return 0
		if not dwarf_id in _idle_dwarves: continue # A Move comparison may assign another worker.
		var agent: DwarfAgent = _agents.get(dwarf_id)
		if not is_instance_valid(agent):
			TaskManager.notify_dwarf_unavailable(dwarf_id)
			_agents.erase(dwarf_id)
			continue
		if type in types_for(agent):
			probes_left = _try_assign_type(agent, type, probes_left, t_start)
	return probes_left


## Source-specific probes, with pickup comparison for exact-plant Moves.
func _try_assign_type(agent: DwarfAgent, type: int, probes_left: int, t_start: int) -> int:
	var now := Time.get_ticks_msec()
	var dwarf_cell := agent.current_cell()
	var ids: Array = _pending.get(type, [])
	var cursor := int(_scan_cursor.get(type, 0))
	var scanned := 0
	while scanned < ids.size():
		if not _within_budget(t_start, probes_left):
			_scan_cursor[type] = cursor + scanned
			return 0
		var idx := (cursor + scanned) % ids.size()
		scanned += 1
		var task: Task = _tasks.get(ids[idx])
		if task == null or not task.is_available(now): continue
		var src: Object = _work_sources.get(task.source_id)
		TaskManager.hold_for_planning(agent)
		_work_probe = task.planning_context.get(agent.dwarf_id,{})
		task.planning_context[agent.dwarf_id] = _work_probe
		if type == Task.Type.FETCH_BUILD and is_instance_valid(src) and src.has_method("move_worker_quote"):
			var quote: Dictionary = src.move_worker_quote()
			if not quote.is_empty():
				_move_match = task.planning_context.get(-1,{})
				probes_left = _try_assign_move(task, src, quote, probes_left, t_start)
				task.planning_context[-1] = _move_match
				if probes_left <= 0:
					_yield_candidate(task,agent,idx)
					return 0
				if agent.dwarf_id in _active: return probes_left
				# The chosen worker may be later in the idle snapshot. Keep this
				# worker available for other same-priority work without skipping
				# the task that shifted into the removed lease's bucket position.
				if task.status != Task.Status.PENDING: scanned -= 1
				continue
		if type == Task.Type.FETCH_BUILD and src is FurnitureGhostComponent:
			if _rejected_workers(task).get(agent.dwarf_id,Vector3i(-1,-1,-1)) == dwarf_cell: continue
			probes_left -= 1
			_probes_total += 1
			var fetch_result := FetchPlanner.advance(src,agent,_work_probe,probe_node_cap,t_start+budget_usec)
			task.wait_reason = String(_work_probe.get("reason","Checking pickup and installation routes"))
			if fetch_result == NavGrid.ProbeResult.SEARCHING:
				_yield_candidate(task,agent,idx)
				return 0
			if fetch_result == NavGrid.ProbeResult.REACHABLE:
				task.blocked_count = 0
				assign(task,agent)
				return probes_left
			_reject_worker_route(task,agent,now)
			continue
		if type == Task.Type.MINE and is_instance_valid(src) and src.has_method("mining_stand_candidates"):
			var rejected := _rejected_workers(task)
			if rejected.get(agent.dwarf_id, Vector3i(-1,-1,-1)) == dwarf_cell: continue
			probes_left -= 1
			_probes_total += 1
			var mining_result := _advance_mining_probe(task, agent, src, t_start)
			if mining_result == NavGrid.ProbeResult.SEARCHING:
				_yield_candidate(task,agent,idx)
				return 0
			if mining_result == NavGrid.ProbeResult.BUDGET_EXHAUSTED: task.wait_reason = "Route search budget exhausted; reachability unknown"
			if mining_result == NavGrid.ProbeResult.REACHABLE:
				task.blocked_count = 0
				assign(task, agent)
				_scan_cursor[type] = (cursor + scanned) % maxi(ids.size(), 1)
				return probes_left
			_reject_worker_route(task, agent, now)
			continue
		if _rejected_workers(task).get(agent.dwarf_id, Vector3i(-1,-1,-1)) == dwarf_cell: continue
		probes_left -= 1
		_probes_total += 1
		# Source leases use a dwarf-relative stand target, not the zone's
		# representative position (which may be unreachable from this side).
		var probe_key := [task.id, agent.dwarf_id, dwarf_cell]
		if _work_probe.get("key", []) != probe_key or not NavGrid.search_is_current(_work_probe.get("route_query", {})):
			var target := task.target_pos
			var goals := {}
			if is_instance_valid(src) and src.has_method("nearest_stand_target"):
				var stand: Vector3i = src.nearest_stand_target(dwarf_cell)
				if stand.x >= 0: target = stand
			if type==Task.Type.UNINSTALL and src is InstalledFurnitureComponent and (String(src.def.get("placement","floor"))=="wall" or src.def.has("grid_fence")):
				for stand: Vector3i in src.wall_work_stands(): goals[stand] = true
				target = goals.keys()[0] if not goals.is_empty() else Vector3i(-1,-1,-1)
			_work_probe.clear()
			_work_probe.merge({"key":probe_key, "target":target,"goals":goals})
		var result := _advance_work_probe(_work_probe, dwarf_cell, _work_probe.target, t_start,_work_probe.goals) if _work_probe.target.x>=0 else NavGrid.ProbeResult.UNREACHABLE
		if result == NavGrid.ProbeResult.SEARCHING:
			_yield_candidate(task,agent,idx)
			return 0
		if result == NavGrid.ProbeResult.BUDGET_EXHAUSTED: task.wait_reason = "Route search budget exhausted; reachability unknown"
		if result == NavGrid.ProbeResult.REACHABLE:
			task.blocked_count = 0
			if not _work_probe.goals.is_empty(): task.payload["wall_work_stand"] = _work_probe.last_route.path.back()
			assign(task, agent)
			_scan_cursor[type] = (cursor + scanned) % maxi(ids.size(), 1)
			return probes_left
		_reject_worker_route(task, agent, now)
	_scan_cursor[type] = 0
	return probes_left


## Failed worker/lease pairs are local to the idle pool and navigation state.
func _rejected_workers(task: Task) -> Dictionary:
	var signature := [idle_version, NavGrid.ladder_revision, task.blocked_count]
	var context: Dictionary = _worker_rejections.get(task.id, {})
	if context.get("signature", []) != signature:
		context = {"signature": signature, "workers": {}}
		_worker_rejections[task.id] = context
	for id: int in context.workers.keys():
		var plan: Dictionary = task.planning_context.get(id,{})
		var query: Dictionary = plan.get("route_query",{})
		if (not query.is_empty() and not NavGrid.search_is_current(query)) or not FetchPlanner.dependencies_current(plan) or (plan.has("stock_revision") and int(plan.stock_revision)!=StockpileManager.hauling_revision):
			context.workers.erase(id)
			plan.clear()
	return context.workers


## Reachability failure belongs to this worker/lease pair. An isolated dwarf
## must not delay furniture (or mining) that another idle worker can reach.
## Keep failures across budget yields; only back off after all eligible workers
## fail. Pool, policy and navigation changes invalidate the comparison.
func _reject_worker_route(task: Task, agent: DwarfAgent, now: int) -> void:
	var rejected := _rejected_workers(task)
	rejected[agent.dwarf_id] = agent.current_cell()
	if task.wait_reason in ["Waiting for assessment","Checking route"]: task.wait_reason = "No route for eligible workers"
	for id: int in _idle_dwarves:
		var other: DwarfAgent = _agents.get(id)
		if is_instance_valid(other) and task.type in types_for(other) and rejected.get(id, Vector3i(-1,-1,-1)) != other.current_cell():
			return
	TaskManager.apply_backoff(task, now)


## Each matching context owns its frontier. Exhausting one wake yields
## and resumes next frame; only a finished failed search applies backoff.
func _advance_work_probe(context: Dictionary, from: Vector3i, goal: Vector3i, t_start: int, goals: Dictionary = {}) -> int:
	if not context.has("route_query"): context.route_query = {}
	var result := RouteProbe.advance(context.route_query, from, goal,
		probe_node_cap, t_start + budget_usec,goals.is_empty(),goals)
	if result == NavGrid.ProbeResult.SEARCHING:
		TaskManager.request_wake()
	else:
		if not context.has("route_dependencies"): context.route_dependencies = {}
		context.route_dependencies.merge(context.route_query.get("chunks",{}))
		context["last_route"] = context.route_query
		context["ladder_revision"] = NavGrid.ladder_revision
		if result == NavGrid.ProbeResult.REACHABLE: NavGrid.remember_reachable_path(context.route_query)
		if result == NavGrid.ProbeResult.BUDGET_EXHAUSTED: context["unknown"] = true
		if result == NavGrid.ProbeResult.BUDGET_EXHAUSTED:
			var task := TaskManager.get_task(int(context.get("task_id",-1)))
			if task != null: task.wait_reason = "Route search budget exhausted; reachability unknown"
		context.erase("route_query")
	return result


## A distant job can take longer to plan than the initial leisure hold. Keep
## that hold alive only while this worker's bounded search makes progress;
## wandering must not repeatedly invalidate the start of an unfinished route.
func _advance_worker_probe(context: Dictionary, agent: DwarfAgent, from: Vector3i,
		goal: Vector3i, t_start: int, goals: Dictionary = {}) -> int:
	var before := int(context.get("route_query",{}).get("expanded",0))
	var result := _advance_work_probe(context,from,goal,t_start,goals)
	_extend_planning_hold(agent, context.get("route_query",{}), before, result)
	return result


func _extend_planning_hold(agent: DwarfAgent, query: Dictionary, before: int, result: int) -> void:
	if result == NavGrid.ProbeResult.SEARCHING \
			and int(query.get("expanded",0)) > before \
			and TaskManager.planning_held(agent.dwarf_id):
		_planning_holds[agent.dwarf_id].until = TaskManager.journal.now \
			+ float(TaskManager.get_config_section("supervision").get("planning_hold_seconds",4.0))


## One search accepts any exact mining position. Disconnected shelves cannot
## hide the reachable plateau, and a sealed zone consumes one bounded search
## rather than repeating the same failed exploration for every work position.
func _advance_mining_probe(task: Task, agent: DwarfAgent, source: Object, t_start: int) -> int:
	var from := agent.current_cell()
	var key := [task.id, agent.dwarf_id, from]
	var query: Dictionary = _work_probe.get("route_query", {})
	if _work_probe.get("key", []) != key or (not query.is_empty() and not NavGrid.search_is_current(query)):
		var goals: Dictionary = {}
		for candidate: Dictionary in source.mining_stand_candidates(from): goals[candidate.cell] = candidate
		_work_probe.clear()
		_work_probe.merge({"key":key, "goals":goals, "route_query":{}})
	if _work_probe.goals.is_empty(): return NavGrid.ProbeResult.UNREACHABLE
	query = _work_probe.route_query
	var before := int(query.get("expanded",0))
	var result := RouteProbe.advance(query, from, _work_probe.goals.keys()[0],
		probe_node_cap, t_start + budget_usec, false, _work_probe.goals)
	# Leisure must not move the start of a mining route that is still making
	# progress, even when the search spans several planning-hold periods.
	_extend_planning_hold(agent, query, before, result)
	if result == NavGrid.ProbeResult.REACHABLE:
		var candidate: Dictionary = _work_probe.goals[query.path.back()]
		if not source.mining_candidate_available(candidate):
			_work_probe.clear()
			TaskManager.request_wake()
			return NavGrid.ProbeResult.SEARCHING
		source.prefer_mining_stand(agent.dwarf_id, candidate)
		# Execution keeps the exact proven block, stand and route.
		NavGrid.remember_reachable_path(query)
	elif result == NavGrid.ProbeResult.SEARCHING:
		TaskManager.request_wake()
	return result


## Continue a Move with its uprooter when already at the pickup; otherwise
## choose a nearby eligible replacement. Normal priorities still run first.
## Both pickup and delivery probes can yield; no item changes owner until the
## selected dwarf enters the ordinary fetch executor.
func _try_assign_move(task: Task, source: Object, quote: Dictionary, probes_left: int, t_start: int) -> int:
	if int(_move_match.get("task_id", -1)) != task.id or int(_move_match.get("idle_version", -1)) != idle_version \
		or _move_match.get("signature", []) != quote.signature:
		_move_match = {"task_id": task.id, "idle_version": idle_version, "signature": quote.signature,
			"idle": _idle_dwarves.duplicate(), "index": 0, "candidates": [], "ranked": false,
			"probe_index": 0, "pickup_ok": false}
	while int(_move_match.index) < _move_match.idle.size():
		if not _within_budget(t_start, probes_left): return 0
		var dwarf_id: int = _move_match.idle[_move_match.index]
		_move_match.index += 1
		var agent: DwarfAgent = _agents.get(dwarf_id)
		if not is_instance_valid(agent) or not dwarf_id in _idle_dwarves or not task.type in types_for(agent): continue
		TaskManager.hold_for_planning(agent)
		var from := agent.current_cell()
		for cell: Vector3i in quote.stands:
			var distance := absi(cell.x - from.x) + absi(cell.y - from.y) + absi(cell.z - from.z)
			_move_match.candidates.append({"dwarf_id": dwarf_id, "from": from, "cell": cell,
				"distance": distance, "continuing": distance == 0 and dwarf_id == int(quote.preferred),
				"tie": _move_match.candidates.size()})
	if not bool(_move_match.ranked):
		if not _within_budget(t_start, probes_left): return 0
		_move_match.candidates.sort_custom(func(a: Dictionary, b: Dictionary):
			if a.distance != b.distance: return a.distance < b.distance
			if a.continuing != b.continuing: return a.continuing
			return a.tie < b.tie)
		_move_match.ranked = true
	while int(_move_match.probe_index) < _move_match.candidates.size():
		if not _within_budget(t_start, probes_left): return 0
		var candidate: Dictionary = _move_match.candidates[_move_match.probe_index]
		var agent: DwarfAgent = _agents.get(int(candidate.dwarf_id))
		if not is_instance_valid(agent) or not int(candidate.dwarf_id) in _idle_dwarves:
			_move_match.probe_index += 1
			_move_match.pickup_ok = false
			continue
		if agent.current_cell() != candidate.from:
			_move_match.clear()
			TaskManager.request_wake()
			return 0
		if not bool(_move_match.pickup_ok):
			probes_left -= 1
			_probes_total += 1
			var pickup := _advance_worker_probe(_move_match, agent, candidate.from, candidate.cell, t_start,{candidate.cell:true})
			if pickup == NavGrid.ProbeResult.SEARCHING: return 0
			if pickup != NavGrid.ProbeResult.REACHABLE:
				_move_match.probe_index += 1
				continue
			_move_match.pickup_ok = true
		if not _within_budget(t_start, probes_left): return 0
		var destination: Vector3i = source.nearest_stand_target(candidate.cell)
		var goals := {}
		for cell: Vector3i in source.work_stands(candidate.cell): goals[cell] = true
		probes_left -= 1
		_probes_total += 1
		var delivery := _advance_worker_probe(_move_match, agent, candidate.cell, destination, t_start,goals) if not goals.is_empty() else NavGrid.ProbeResult.UNREACHABLE
		if delivery == NavGrid.ProbeResult.SEARCHING: return 0
		if delivery == NavGrid.ProbeResult.REACHABLE:
			source.prefer_fetch_plan({"dwarf_id":agent.dwarf_id,"from":candidate.from,"pickup_stand":candidate.cell,
				"delivery_stand":_move_match.last_route.path.back(),"material":{"node":source.claimed_item(),"cell":source.drop_manager.item_floor_cell(source.claimed_item()),"key":source.item_key}})
			_move_match.clear()
			task.blocked_count = 0
			assign(task, agent)
			return probes_left
		_move_match.probe_index += 1
		_move_match.pickup_ok = false
	_move_match.clear()
	TaskManager.apply_backoff(task, Time.get_ticks_msec())
	return probes_left


## Crafting starts at its ingredient, not at the workbench. Rank every eligible
## idle worker before reserving goods, then prove pickup AND delivery. A failed
## material is excluded only for that worker; later candidates stay available.
func _try_assign_crafts(probes_left: int, t_start: int) -> int:
	while not _idle_dwarves.is_empty():
		if not _within_budget(t_start,probes_left): return 0
		var now := Time.get_ticks_msec()
		var task: Task = _tasks.get(int(_craft_match.get("task_id",-1)))
		if task == null or not task.is_available(now):
			_craft_match.clear()
			task = null
			for id: int in _pending.get(Task.Type.CRAFT,[]):
				var next: Task = _tasks.get(id)
				if next != null and next.is_available(now):
					task = next
					break
		if task == null: return probes_left
		var source: Object = _work_sources.get(task.source_id)
		if not is_instance_valid(source):
			TaskManager.cancel_task(task.id)
			continue
		var signature: Array = source.scheduling_signature()
		if _craft_match.get("signature",[]) != signature or int(_craft_match.get("idle_version",-1)) != idle_version:
			_craft_match = {"task_id":task.id, "signature":signature, "idle_version":idle_version,
				"idle":_idle_dwarves.duplicate(), "index":0, "query":{}, "candidates":[],
				"ranked":false, "excluded":{}, "eligible":0, "pickup_ok":false}
		while int(_craft_match.index) < _craft_match.idle.size():
			if not _within_budget(t_start,probes_left): return 0
			var dwarf_id: int = _craft_match.idle[_craft_match.index]
			var candidate_agent: DwarfAgent = _agents.get(dwarf_id)
			if not is_instance_valid(candidate_agent) or not dwarf_id in _idle_dwarves or not Task.Type.CRAFT in types_for(candidate_agent):
				_craft_match.index += 1
				_craft_match.query = {}
				continue
			TaskManager.hold_for_planning(candidate_agent)
			var from := candidate_agent.current_cell()
			if _craft_match.get("from",from) != from: _craft_match.query = {}
			_craft_match.from = from
			var query: Dictionary = _craft_match.query
			if not source.advance_worker_quote(from,query,t_start+budget_usec,_craft_match.excluded.get(dwarf_id,{})):
				TaskManager.request_wake()
				return 0
			_craft_match.eligible += 1
			if not query.material.is_empty():
				_craft_match.candidates.append({"dwarf_id":dwarf_id, "from":from,
					"material":query.material, "goals":query.goals,
					"distance":int(query.material.distance), "tie":int(_craft_match.index)})
			_craft_match.index += 1
			_craft_match.query = {}
		if not bool(_craft_match.ranked):
			_craft_match.candidates.sort_custom(func(a: Dictionary,b: Dictionary):
				return a.distance < b.distance if a.distance != b.distance else a.tie < b.tie)
			_craft_match.ranked = true
		if _craft_match.candidates.is_empty():
			var eligible := int(_craft_match.eligible)
			_craft_match.clear()
			if eligible == 0: return probes_left
			TaskManager.apply_backoff(task,now)
			continue
		if not _within_budget(t_start,probes_left): return 0
		var candidate: Dictionary = _craft_match.candidates[0]
		var agent: DwarfAgent = _agents.get(int(candidate.dwarf_id))
		if not is_instance_valid(agent) or agent.current_cell() != candidate.from:
			_craft_match.clear()
			TaskManager.request_wake()
			return 0
		if not bool(_craft_match.pickup_ok):
			var pickup_goals := {}
			for cell in StorageComponent.ground_access_cells(candidate.material.cell):
				if NavGrid.is_walkable(cell): pickup_goals[cell] = true
			probes_left -= 1
			_probes_total += 1
			var pickup_result := _advance_craft_probe(candidate.from,pickup_goals,t_start)
			if pickup_result == NavGrid.ProbeResult.SEARCHING: return 0
			if pickup_result != NavGrid.ProbeResult.REACHABLE:
				_reject_craft_material(candidate)
				continue
			candidate.pickup_stand = _craft_match.route_query.path.back()
			candidate.pickup_route = _craft_match.route_query
			_craft_match.erase("route_query")
			_craft_match.pickup_ok = true
		if not _within_budget(t_start,probes_left): return 0
		var goals: Dictionary = candidate.goals
		# Bootstrap recipes work at the pickup. Workshop recipes consider every
		# free bench edge, so the nearest sealed side cannot hide an open one.
		if String(source.recipe.workshop).is_empty(): goals = {candidate.pickup_stand:-1}
		probes_left -= 1
		_probes_total += 1
		var result := _advance_craft_probe(candidate.pickup_stand,goals,t_start)
		if result == NavGrid.ProbeResult.SEARCHING: return 0
		if result != NavGrid.ProbeResult.REACHABLE:
			_reject_craft_material(candidate)
			continue
		candidate.delivery_stand = _craft_match.route_query.path.back()
		candidate.bench_id = goals[candidate.delivery_stand]
		NavGrid.remember_reachable_path(candidate.pickup_route)
		NavGrid.remember_reachable_path(_craft_match.route_query)
		source.prefer_fetch_plan(candidate)
		_craft_match.clear()
		task.blocked_count = 0
		assign(task,agent)
	return probes_left


func _advance_craft_probe(from: Vector3i, goals: Dictionary, t_start: int) -> int:
	if goals.is_empty(): return NavGrid.ProbeResult.UNREACHABLE
	if not _craft_match.has("route_query"): _craft_match.route_query = {}
	var query: Dictionary = _craft_match.route_query
	var result := RouteProbe.advance(query,from,goals.keys()[0],
		probe_node_cap,t_start+budget_usec,false,goals)
	if not _craft_match.has("route_dependencies"): _craft_match.route_dependencies = {}
	_craft_match.route_dependencies.merge(query.get("chunks",{}))
	if result == NavGrid.ProbeResult.BUDGET_EXHAUSTED:
		var task := TaskManager.get_task(int(_craft_match.get("task_id",-1)))
		if task != null: task.wait_reason = "Route search budget exhausted; reachability unknown"
	if result == NavGrid.ProbeResult.SEARCHING: TaskManager.request_wake()
	return result


func _reject_craft_material(candidate: Dictionary) -> void:
	var excluded: Dictionary = _craft_match.excluded.get(int(candidate.dwarf_id),{})
	excluded[candidate.material.cell] = true
	_craft_match.excluded[int(candidate.dwarf_id)] = excluded
	_craft_match.index = 0
	_craft_match.query = {}
	_craft_match.candidates = []
	_craft_match.ranked = false
	_craft_match.pickup_ok = false
	_craft_match.eligible = 0
	_craft_match.erase("route_query")


func _is_surface_work(type: int) -> bool:
	return type in Task.SURFACE_WORK


## Compare all eligible idle workers to the actual adjacent work cells. Quotes
## do not reserve work or rotate the source's retry cursor. Ranking and capped
## probes resume across wakes; one blocked worker/side cannot hide the others.
func _try_assign_surface(type: int, probes_left: int, t_start: int) -> int:
	while not _idle_dwarves.is_empty():
		if not _within_budget(t_start, probes_left): return 0
		var now := Time.get_ticks_msec()
		var task: Task = _tasks.get(int(_surface_match.get("task_id", -1)))
		if task == null or task.type != type or not task.is_available(now):
			task = null
			var ids: Array = _pending.get(type, [])
			var cursor := int(_scan_cursor.get(type, 0))
			for scanned in range(ids.size()):
				if not _within_budget(t_start, probes_left):
					_scan_cursor[type] = cursor + scanned
					return 0
				var next: Task = _tasks.get(ids[(cursor + scanned) % ids.size()])
				if next != null and next.is_available(now):
					task = next
					_scan_cursor[type] = cursor + scanned
					break
		if task == null: return probes_left
		var source: Object = _work_sources.get(task.source_id)
		if int(_surface_match.get("task_id", -1)) != task.id or int(_surface_match.get("idle_version", -1)) != idle_version:
			_surface_match = {"task_id": task.id, "idle_version": idle_version,
				"idle": _idle_dwarves.duplicate(), "index": 0, "candidates": [],
				"ranked": false, "probe_index": 0, "eligible": 0}
		while int(_surface_match.index) < _surface_match.idle.size():
			if not _within_budget(t_start, probes_left): return 0
			var dwarf_id: int = _surface_match.idle[_surface_match.index]
			_surface_match.index += 1
			var agent: DwarfAgent = _agents.get(dwarf_id)
			if not is_instance_valid(agent) or not dwarf_id in _idle_dwarves or not type in types_for(agent): continue
			_surface_match.eligible += 1
			TaskManager.hold_for_planning(agent)
			var from := agent.current_cell()
			var cells: Array[Vector3i] = [task.target_pos]
			if is_instance_valid(source) and source.has_method("stand_cells"):
				cells = source.stand_cells(from)
			for cell: Vector3i in cells:
				var distance := absi(cell.x - from.x) + absi(cell.y - from.y) + absi(cell.z - from.z)
				_surface_match.candidates.append({"dwarf_id": dwarf_id, "from": from,
					"cell": cell, "distance": distance, "tie": _surface_match.candidates.size()})
		if not bool(_surface_match.ranked):
			if not _within_budget(t_start, probes_left): return 0
			_surface_match.candidates.sort_custom(func(a: Dictionary, b: Dictionary):
				return a.distance < b.distance if a.distance != b.distance else a.tie < b.tie)
			_surface_match.ranked = true
		var assigned := false
		while int(_surface_match.probe_index) < _surface_match.candidates.size():
			if not _within_budget(t_start, probes_left): return 0
			var candidate: Dictionary = _surface_match.candidates[_surface_match.probe_index]
			_surface_match.probe_index += 1
			var agent: DwarfAgent = _agents.get(int(candidate.dwarf_id))
			if not is_instance_valid(agent) or not int(candidate.dwarf_id) in _idle_dwarves or not type in types_for(agent): continue
			if agent.current_cell() != candidate.from:
				_surface_match.clear()
				TaskManager.request_wake()
				return 0
			probes_left -= 1
			_probes_total += 1
			# Execution needs this exact work stand, and can reuse its proven path.
			var result := _advance_worker_probe(_surface_match, agent, candidate.from, candidate.cell, t_start,{candidate.cell:true})
			if result == NavGrid.ProbeResult.SEARCHING:
				_surface_match.probe_index -= 1
				return 0
			if result != NavGrid.ProbeResult.REACHABLE: continue
			if is_instance_valid(source) and source.has_method("prefer_work_stand"):
				source.prefer_work_stand(candidate.cell)
			task.blocked_count = 0
			assign(task, agent)
			assigned = true
			break
		var eligible := int(_surface_match.eligible)
		_surface_match.clear()
		_scan_cursor[type] = int(_scan_cursor.get(type, 0)) + 1
		if eligible == 0: return probes_left
		if not assigned: TaskManager.apply_backoff(task, now)
	return probes_left


## HAUL leases belong to destinations, but their worker should be near the
## first pickup. Compare every eligible idle dwarf before claiming any goods.
## Ranking and both route probes resume across wakes; a failed near worker
## does not back off the task until the other candidates have been tried.
func _try_assign_hauls(probes_left: int, t_start: int) -> int:
	var deadline := t_start + budget_usec
	while not _idle_dwarves.is_empty():
		if not _within_budget(t_start, probes_left): return 0
		var task: Task = _tasks.get(int(_haul_match.get("task_id", -1)))
		var now := Time.get_ticks_msec()
		if task == null or not task.is_available(now):
			_haul_match.clear()
			var ids: Array = _pending.get(Task.Type.HAUL, [])
			var cursor := int(_scan_cursor.get(Task.Type.HAUL, 0))
			for scanned in range(ids.size()):
				if not _within_budget(t_start, probes_left):
					_scan_cursor[Task.Type.HAUL] = cursor + scanned
					return 0
				var next: Task = _tasks.get(ids[(cursor + scanned) % ids.size()])
				if next != null and next.is_available(now):
					task = next
					_scan_cursor[Task.Type.HAUL] = cursor + scanned
					break
		if task == null or not task.is_available(now): return probes_left
		var source: Object = _work_sources.get(task.source_id)
		var revision := int(source.scheduling_revision()) if is_instance_valid(source) and source.has_method("scheduling_revision") else 0
		if _haul_match.is_empty() or int(_haul_match.get("idle_version",-1)) != idle_version or int(_haul_match.get("revision",-1)) != revision:
			# Needs and inventory changes require fresh quotes, not fresh geometry.
			# Retain routes and alternatives for unchanged worker positions; each
			# reused proof still checks its own navigation dependencies below.
			var routes := {}
			var deferred := {}
			if int(_haul_match.get("task_id",-1)) == task.id:
				for route_key: Array in _haul_match.get("routes",{}):
					var worker: DwarfAgent = _agents.get(int(route_key[0]))
					if is_instance_valid(worker) and worker.current_cell() == route_key[1]:
						routes[route_key] = _haul_match.routes[route_key]
						if _haul_match.get("deferred",{}).get(worker.dwarf_id,{}).has(route_key[2]):
							if not deferred.has(worker.dwarf_id): deferred[worker.dwarf_id] = {}
							deferred[worker.dwarf_id][route_key[2]] = true
			_haul_match = {"task_id": task.id, "idle_version": idle_version, "revision": revision,
				"idle": _idle_dwarves.duplicate(), "index": 0, "query": {}, "candidates": [],
				"ranked": false, "probe_index": 0, "eligible": 0,
				"excluded": {}, "deferred": deferred, "blocked_workers": {}, "failed": false, "pickup_snapshot": {}, "routes": routes}
		while int(_haul_match.index) < _haul_match.idle.size():
			if not _within_budget(t_start, probes_left): return 0
			var dwarf_id: int = _haul_match.idle[_haul_match.index]
			var agent: DwarfAgent = _agents.get(dwarf_id)
			if not is_instance_valid(agent) or not dwarf_id in _idle_dwarves or not Task.Type.HAUL in types_for(agent) or _haul_match.blocked_workers.has(dwarf_id):
				_haul_match.index += 1
				_haul_match.query = {}
				continue
			TaskManager.hold_for_planning(agent)
			var from := agent.current_cell()
			var query: Dictionary = _haul_match.query
			if query.has("from") and query.from != from: query.clear()
			query.from = from
			query.exclude = (_haul_match.excluded.get(dwarf_id, {}) as Dictionary).duplicate()
			query.exclude.merge(_haul_match.deferred.get(dwarf_id,{}))
			# Source filtering is identical for every worker in this comparison.
			# Inventory/idle invalidation above discards the shared snapshot too.
			query.pickup_snapshot = _haul_match.pickup_snapshot
			if is_instance_valid(source) and source.has_method("advance_haul_quote"):
				if not bool(source.advance_haul_quote(from, query, deadline)):
					TaskManager.request_wake()
					return 0
			else:
				query.cell = task.target_pos
			_haul_match.eligible += 1
			var cell: Vector3i = query.cell
			if cell.x >= 0:
				var distance := absi(cell.x - from.x) + absi(cell.y - from.y) + absi(cell.z - from.z)
				_haul_match.candidates.append({"dwarf_id": dwarf_id, "cell": cell, "from": from,
					"distance": distance, "tie": int(_haul_match.index)})
			_haul_match.index += 1
			_haul_match.query = {}
		if not bool(_haul_match.ranked):
			_haul_match.candidates.sort_custom(func(a: Dictionary, b: Dictionary):
				return a.distance < b.distance if a.distance != b.distance else a.tie < b.tie)
			_haul_match.ranked = true
		var assigned := false
		var rerank := false
		while not _haul_match.candidates.is_empty():
			if not _within_budget(t_start, probes_left): return 0
			_haul_match.probe_index = int(_haul_match.probe_index) % _haul_match.candidates.size()
			var candidate: Dictionary = _haul_match.candidates[_haul_match.probe_index]
			var agent: DwarfAgent = _agents.get(int(candidate.dwarf_id))
			if not is_instance_valid(agent) or not int(candidate.dwarf_id) in _idle_dwarves:
				_haul_match.candidates.remove_at(_haul_match.probe_index)
				continue
			if agent.current_cell() != candidate.from:
				_haul_match.idle_version = -1 # Re-rank; retain other workers' unchanged searches.
				TaskManager.request_wake()
				return 0
			# Each worker/pickup keeps its own search. A hard route gets a bounded
			# turn, then another candidate can prove a different pickup reachable.
			# Otherwise a nearby item on another level stalls every ready worker.
			var route_key := [candidate.dwarf_id,candidate.from,candidate.cell]
			if not _haul_match.routes.has(route_key): _haul_match.routes[route_key] = {"task_id":task.id}
			var route: Dictionary = _haul_match.routes[route_key]
			if not FetchPlanner.dependencies_current(route): route.clear()
			route.task_id = task.id
			if not bool(route.get("pickup_ok",false)):
				probes_left -= 1
				_probes_total += 1
				var pickup_goals := {}
				if source is StorageComponent:
					for cell: Vector3i in StorageComponent.ground_access_cells(candidate.cell):
						if NavGrid.is_walkable(cell): pickup_goals[cell] = true
				var pickup := NavGrid.ProbeResult.UNREACHABLE if source is StorageComponent and pickup_goals.is_empty() else _advance_haul_probe(route, agent, candidate.from, candidate.cell, t_start,pickup_goals)
				if pickup == NavGrid.ProbeResult.SEARCHING:
					_yield_haul_candidate(route)
					return 0
				if pickup != NavGrid.ProbeResult.REACHABLE:
					_haul_match.failed = true
					_haul_match.routes.erase(route_key)
					if is_instance_valid(source) and source.has_method("advance_haul_quote"):
						var excluded: Dictionary = _haul_match.excluded.get(int(candidate.dwarf_id), {})
						excluded[candidate.cell] = true
						_haul_match.excluded[int(candidate.dwarf_id)] = excluded
						_restart_haul_ranking()
						rerank = true
						break
					_haul_match.candidates.remove_at(_haul_match.probe_index)
					continue
				route.pickup_ok = true
				route["pickup_stand"] = route.last_route.path.back()
				route["pickup_path"] = route.last_route.path
				route.slices = 0
			if not _within_budget(t_start, probes_left): return 0
			var destination := task.target_pos
			if is_instance_valid(source) and source.has_method("nearest_stand_target"):
				destination = source.nearest_stand_target(route.pickup_stand)
			var delivery_goals := {}
			if source is StorageComponent:
				for cell: Vector3i in source.delivery_stand_cells(destination):
					if NavGrid.is_walkable(cell): delivery_goals[cell] = true
			probes_left -= 1
			_probes_total += 1
			var has_approach := destination.x >= 0 and (not source is StorageComponent or not delivery_goals.is_empty())
			var delivery := _advance_haul_probe(route, agent, route.pickup_stand, destination, t_start,delivery_goals) if has_approach else NavGrid.ProbeResult.UNREACHABLE
			if delivery == NavGrid.ProbeResult.SEARCHING:
				_yield_haul_candidate(route)
				return 0
			if delivery == NavGrid.ProbeResult.REACHABLE:
				task.blocked_count = 0
				var excluded: Dictionary = (_haul_match.excluded.get(agent.dwarf_id, {}) as Dictionary).duplicate()
				excluded.merge(_haul_match.deferred.get(agent.dwarf_id,{}))
				task.payload["haul_excluded_cells"] = excluded.keys()
				task.payload["haul_pickup_path"] = route.pickup_path
				task.payload["haul_delivery_path"] = route.last_route.path
				_haul_match.clear()
				assign(task, agent)
				assigned = true
				break
			_haul_match.candidates.remove_at(_haul_match.probe_index)
			_haul_match.routes.erase(route_key)
			_haul_match.blocked_workers[int(candidate.dwarf_id)] = true
			_haul_match.failed = true
		if assigned: continue # claims changed; rank the next lease against remaining goods
		if rerank: continue
		if int(_haul_match.eligible) == 0 and not bool(_haul_match.failed):
			_haul_match.clear()
			return probes_left
		if not _haul_match.deferred.is_empty():
			# All alternatives had a turn. Resume the retained long searches;
			# a time slice ending is never proof that an item is unreachable.
			_haul_match.deferred.clear()
			_restart_haul_ranking()
			TaskManager.request_wake()
			return 0
		if _haul_match.candidates.is_empty() and not bool(_haul_match.failed):
			TaskManager.cancel_task(task.id) # stale lease: no compatible unreserved goods/room
		else:
			TaskManager.apply_backoff(task, now)
		_scan_cursor[Task.Type.HAUL] = int(_scan_cursor.get(Task.Type.HAUL, 0)) + 1
		_haul_match.clear()
	return probes_left


## Many storage leases ask the same geometry question. Share their bounded
## search and proof, not inventory quotes or claims. A pickup/deposit elsewhere
## changes supplies but must not restart a still-valid route for idle workers.
func _advance_haul_probe(route: Dictionary, agent: DwarfAgent, from: Vector3i,
		goal: Vector3i, t_start: int, goals: Dictionary = {}) -> int:
	var key := [from,goal,goals.keys()]
	if not _haul_route_cache.has(key):
		var capacity := maxi(1,int(TaskManager.get_config_section("hauling").get("route_cache_entries",64)))
		if _haul_route_cache.size() >= capacity:
			_haul_route_cache.erase(_haul_route_cache.keys()[0])
		_haul_route_cache[key] = {}
		# Eviction limits sharing, not an individual lease's progress. Its own
		# unfinished frontier can rejoin the cache on its next scheduling turn.
		var retained: Dictionary = route.get("route_query",{})
		if retained.get("start") == from and retained.get("goal") == goal and retained.get("goals",{}) == goals:
			_haul_route_cache[key]["route_query"] = retained
	var shared: Dictionary = _haul_route_cache[key]
	if not FetchPlanner.dependencies_current(shared) \
			or (shared.has("route_query") and not NavGrid.search_is_current(shared.route_query)) \
			or (int(shared.get("result",-1)) == NavGrid.ProbeResult.BUDGET_EXHAUSTED and TaskManager.journal.now >= float(shared.get("retry_at",0))):
		shared.clear()
	var result := int(shared.get("result",NavGrid.ProbeResult.SEARCHING))
	if not shared.has("result"):
		shared["task_id"] = int(route.get("task_id",-1))
		result = _advance_worker_probe(shared,agent,from,goal,t_start,goals)
		if result != NavGrid.ProbeResult.SEARCHING:
			shared["result"] = result
			shared["retry_at"] = TaskManager.journal.now + TaskManager.backoff_max_seconds()
	if result == NavGrid.ProbeResult.SEARCHING:
		# The planning quantum belongs to this geometry too. Otherwise every
		# duplicate lease spends another full quantum on the same hard pickup
		# before any of them considers the next available load.
		var quantum := int(TaskManager.get_config_section("supervision").get("planning_quantum_slices",8))
		shared["slices"] = mini(quantum,int(shared.get("slices",0))+1)
		route["slices"] = int(shared.slices)-1
		route["route_query"] = shared.route_query
	else:
		route.erase("route_query")
		if not route.has("route_dependencies"): route.route_dependencies = {}
		route.route_dependencies.merge(shared.get("route_dependencies",{}))
		route["last_route"] = shared.last_route
		route["ladder_revision"] = shared.ladder_revision
		if result == NavGrid.ProbeResult.BUDGET_EXHAUSTED:
			var task := TaskManager.get_task(int(route.get("task_id",-1)))
			if task != null: task.wait_reason = "Route search budget exhausted; reachability unknown"
	return result


func _yield_haul_candidate(route: Dictionary) -> void:
	route["slices"] = int(route.get("slices",0))+1
	if int(route.slices) >= int(TaskManager.get_config_section("supervision").get("planning_quantum_slices",8)):
		route.slices = 0
		var candidate: Dictionary = _haul_match.candidates[_haul_match.probe_index]
		if not _haul_match.deferred.has(candidate.dwarf_id): _haul_match.deferred[candidate.dwarf_id] = {}
		_haul_match.deferred[candidate.dwarf_id][candidate.cell] = true
		_restart_haul_ranking()
	TaskManager.request_wake()


func _restart_haul_ranking() -> void:
	_haul_match.index = 0
	_haul_match.query = {}
	_haul_match.candidates = []
	_haul_match.ranked = false
	_haul_match.probe_index = 0
	_haul_match.eligible = 0


func assign(task: Task, agent: DwarfAgent, carried_item: Node3D = null) -> void:
	TaskManager.remove_pending(task)
	task.status = Task.Status.ASSIGNED
	task.assigned_to = agent.dwarf_id
	task.attempt = Attempt.new()
	task.attempt.generation = TaskManager.journal.next_attempt
	TaskManager.journal.next_attempt += 1
	task.attempt.task_id = task.id
	task.attempt.worker_id = agent.dwarf_id
	task.attempt.order_key = task.order_key
	task.attempt.observe({"step":"assigned"},TaskManager.journal.now,TaskManager.progress_grace())
	task.wait_reason = ""
	TaskManager.journal.transition(task.order_locator,"running","Assigned",task.attempt.generation,agent.dwarf_id)
	_active[agent.dwarf_id] = task.id
	TaskManager.notify_dwarf_unavailable(agent.dwarf_id)
	agent.receive_task(task.id, task.target_pos, carried_item)
	# receive_task may synchronously reject or finish an assignment.
	if _active.get(agent.dwarf_id,-1) == task.id: TaskManager.task_assigned.emit(task, agent.dwarf_id)



## Profession capability and player permissions both apply. Self-care and
## carrying supplies within an allowed assignment are never separate gates.
func types_for(agent: DwarfAgent) -> Array[int]:
	if agent.is_sleeping() or agent.is_eating() or agent.is_recreating() or not NavGrid.is_navigable(agent.current_cell()): return []
	if agent.promotion_pending(): return []
	if agent.needs_bridge_exit(): return []
	var types: Array[int] = []
	types.assign(Task.COMMON_WORK)
	if agent.profession == "base:profession:worker": types.append(Task.Type.CRAFT)
	if agent.work_permissions.is_empty(): return types
	var allowed: Array[int] = []
	for type: int in types:
		if agent.allows_task(type): allowed.append(type)
	return allowed


func _bucket_priority(type: int) -> int:
	return TaskManager.static_priority(type)


func _yield_candidate(task: Task, agent: DwarfAgent, index: int) -> void:
	var context: Dictionary = task.planning_context.get(agent.dwarf_id,{})
	context["slices"] = int(context.get("slices",0))+1
	var quantum := int(TaskManager.get_config_section("supervision").get("planning_quantum_slices",8))
	_scan_cursor[task.type] = index
	if int(context.slices) >= quantum:
		context.slices = 0
		_scan_cursor[task.type] = index+1
		_worker_cursor[task.type] = int(_worker_cursor.get(task.type,0))+1
	TaskManager.request_wake()


func _assign_specialized_bucket(type: int, probes_left: int, t_start: int) -> int:
	var ids: Array = _pending.get(type,[])
	var selected: Task
	var cursor := int(_scan_cursor.get(type,0))
	for offset in range(ids.size()):
		var next: Task = _tasks.get(ids[(cursor+offset)%ids.size()])
		if next != null and next.is_available(Time.get_ticks_msec()):
			selected = next
			_scan_cursor[type] = (cursor+offset)%ids.size()
			break
	if selected == null: return probes_left
	var context: Dictionary = _family_frontiers.get(selected.id,{})
	if not FetchPlanner.dependencies_current(context): context.clear()
	context["task_id"] = selected.id
	if type == Task.Type.HAUL:
		_haul_match = context
		probes_left = _try_assign_hauls(probes_left,t_start)
		context = _haul_match
	elif type == Task.Type.CRAFT:
		_craft_match = context
		probes_left = _try_assign_crafts(probes_left,t_start)
		context = _craft_match
	else:
		_surface_match = context
		probes_left = _try_assign_surface(type,probes_left,t_start)
		context = _surface_match
	var retained: Task = _tasks.get(int(context.get("task_id",-1)))
	if retained != null and retained.status == Task.Status.PENDING:
		_family_frontiers[retained.id] = context
		_family_quanta[retained.id] = int(_family_quanta.get(retained.id,0))+1
		if int(_family_quanta[retained.id]) >= int(TaskManager.get_config_section("supervision").get("planning_quantum_slices",8)):
			_family_quanta[retained.id] = 0
			_scan_cursor[type] = maxi(0,(_pending.get(type,[]) as Array).find(retained.id))+1
	return probes_left
