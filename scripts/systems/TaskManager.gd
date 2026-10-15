extends Node

## The colony's task scheduler (doc 16 §2 — the no-hang architecture).
## Autoload, loaded after NavGrid (probes), before nothing in particular.
##
## OWNERSHIP: Tasks are entities owned exclusively by these tables. Dwarves
## hold task IDS only. Work sources (mining zones, step 5) post intent-sized
## tasks — NEVER per-block tasks (doc 16 §2.1: O(intents), not O(blocks)).
##
## SCHEDULING MODEL — event-driven with a heartbeat, never a frame scan:
##   - Wake events set a dirty flag (task added, dwarf idle, release); the
##     flag is flushed AT MOST once per frame in _process.
##   - A slow heartbeat (task_config.json) catches retry_at expiries.
##   - Each wake is TIME-BUDGETED (scheduler_budget_usec) and PROBE-CAPPED
##     (max_probes_per_wake); the matching loop stops mid-scan and resumes
##     from per-type cursors next wake. Overload degrades into assignment
##     LATENCY — never frame time. (doc 16 §2.5, hard rules.)
##   - Unreachable tasks back off exponentially (retry_at); after
##     unreachable_signal_threshold consecutive failures task_unreachable
##     fires for the UI. chunk_dirtied near a blocked target re-arms it early.
##
## RELEASE PROTOCOL (doc 16 §2.8): releasing a task is ALWAYS cheap and legal.
## release_dwarf_task() returns the task to PENDING with its static priority;
## work sources get notified via task_released to free reservations.
##
## JSON = what things are (budgets, priorities — data/tasks/task_config.json);
## GDScript = what things do (this loop).

signal task_added(task: Task)
signal task_assigned(task: Task, dwarf_id: int)
signal task_released(task: Task, dwarf_id: int, reason: int)
signal task_completed(task: Task)
signal task_failed(task: Task, reason: String)
signal task_cancelled(task: Task)
signal task_unreachable(task: Task)

const CONFIG_PATH := "res://data/tasks/task_config.json"
const Attempt = preload("res://scripts/components/WorkAttempt.gd")
const SourceAdapter = preload("res://scripts/components/WorkSourceAdapter.gd")
const Journal = preload("res://scripts/components/WorkJournal.gd")
const Execution = preload("res://scripts/components/DwarfWorkExecution.gd")
const RouteProbe = preload("res://scripts/components/WorkRouteProbe.gd")
const FetchPlanner = preload("res://scripts/components/FurnitureFetchPlanner.gd")
var journal := Journal.new()
var _source_locators: Dictionary = {}
var _supervision_cursor := 0
var _supervision_accum := 0.0
var _planning_holds: Dictionary = {}
var _worker_cursor: Dictionary = {}
var _family_frontiers: Dictionary = {} # task_id -> suspended specialized comparison
var _family_quanta: Dictionary = {}
var _reconcile_cursor := 0

# ── Config (fallbacks mirror task_config.json) ───────────────────────────────
var _config_raw: Dictionary = {}          # full parsed task_config.json (see get_config_section)
var _budget_usec: int = 1000
var _max_probes_per_wake: int = 8
var _probe_node_cap: int = 200
var _heartbeat_s: float = 0.5
var _backoff_base_s: float = 2.0
var _backoff_max_s: float = 30.0
var _unreachable_threshold: int = 3
var _static_priorities: Dictionary = {}   # type name -> int

# ── Tables (doc 16 §2.3) ──────────────────────────────────────────────────────
var _tasks: Dictionary = {}            # id -> Task
var _pending: Dictionary = {}          # Task.Type (int) -> Array[int], static priority desc
var _active: Dictionary = {}           # dwarf_id -> task_id
var _idle_dwarves: Array[int] = []     # event-maintained
var _agents: Dictionary = {}           # dwarf_id -> DwarfAgent (weak by validity checks)
var _completed_log: Array = []         # ring buffer of dicts, last 200
var _scan_cursor: Dictionary = {}      # Task.Type -> int (resumable scan position)
var _haul_match: Dictionary = {}       # one resumable, read-only worker comparison
var _surface_match: Dictionary = {}    # adjacent surface work, including shrub uprooting
var _move_match: Dictionary = {}       # exact-plant pickup after uprooting
var _craft_match: Dictionary = {}      # first ingredient pickup, then a free workshop
var _work_probe: Dictionary = {}       # resumable ordinary work-source route
var _work_probes: Dictionary = {}      # type -> suspended ordinary route
var _surface_matches: Dictionary = {} # type -> suspended surface comparison
var _next_type: int = -1              # next bucket after a budget yield
var _worker_rejections: Dictionary = {} # lease -> failed idle workers, valid for this navigation/pool revision
var _idle_version := 0                # a newly idle dwarf must join that comparison

var _next_task_id: int = 1
var _blocked_count: int = 0            # PENDING tasks currently in backoff (fast gate)

# ── Work sources (doc 16 §2.7 — zones now, workshops later) ──────────────────
# A work source posts intent-sized lease tasks (source_id = its id) and hands
# out per-block/per-batch work to the assigned dwarf directly — the scheduler
# never sees the atomic units. Dwarves resolve a lease's source through here,
# so work sources stay scene-decoupled from agents.
var _work_sources: Dictionary = {}     # source_id -> Object (e.g. MiningZoneComponent)

# ── Wake machinery ────────────────────────────────────────────────────────────
var _wake_dirty: bool = false
var _heartbeat_accum: float = 0.0

# ── Instrumentation (doc 16 Phase 0) ─────────────────────────────────────────
var _wake_count: int = 0
var _worst_wake_usec: int = 0
var _probes_total: int = 0
var _probes_at_last_stats: int = 0
var _stats_last_msec: int = 0


func _ready() -> void:
	_load_config()
	add_to_group("save_state_owner")
	WorldData.chunk_dirtied.connect(_on_chunk_dirtied, CONNECT_DEFERRED)
	print("TaskManager: ready (budget %d us, %d probes/wake, heartbeat %.2f s)." % [
		_budget_usec, _max_probes_per_wake, _heartbeat_s])


func _process(delta: float) -> void:
	if SaveManager.is_loading() or WorldClock.paused or WorldClock.speed <= 0.0: return
	advance_supervision(delta * WorldClock.speed)
	_heartbeat_accum += delta
	if _heartbeat_accum >= _heartbeat_s:
		_heartbeat_accum = 0.0
		_wake_dirty = true
	if _wake_dirty:
		_wake_dirty = false
		_run_scheduler()


# ── Public API — tasks ────────────────────────────────────────────────────────

## Creates and enqueues a task. Static priority defaults from task_config.json
## by type; pass priority >= 0 to override. Returns the task id.
func add_task(type: int, target_pos: Vector3i, payload: Dictionary = {},
		source_id: int = -1, priority: int = -1) -> int:
	var p := priority
	if p < 0:
		p = int(_static_priorities.get(Task.type_name(type), 1))
	var task := Task.new(type, p, target_pos, payload, source_id)
	task.id = _next_task_id
	_next_task_id += 1
	_tasks[task.id] = task
	task.order_locator = String(_source_locators.get(source_id,"synthetic:%d" % task.id))
	task.order_key = journal.ensure(task.order_locator,SourceAdapter.label(get_work_source(source_id)))
	journal.transition(task.order_locator,"ready","Waiting for eligible worker")
	_insert_pending(task)
	task_added.emit(task)
	_wake_dirty = true
	return task.id


func get_task(task_id: int) -> Task:
	return _tasks.get(task_id)


## Storage hauling is a soft claim: player placement may take precedence.
## Only live HAUL pulls qualify, never crafting, fetching or another plan.
## Called on catalog/placement wakes, not by the scheduling loop.
func placement_haul_offers(claim_owner: int = -1) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for dwarf_id: int in _active:
		var task := get_task(int(_active[dwarf_id]))
		var agent: DwarfAgent = _agents.get(dwarf_id)
		if task == null or task.type != Task.Type.HAUL or not is_instance_valid(agent): continue
		var source := get_work_source(task.source_id) as StorageComponent
		if source == null: continue
		for offer: Dictionary in source.placement_haul_items(dwarf_id):
			if source.drop_manager.instance_promised(offer.instance_id, claim_owner): continue
			offer["task_id"] = task.id
			offer["dwarf_id"] = dwarf_id
			result.append(offer)
	return result


## Synchronous ownership handoff after a designation exists. Cancelling the
## old haul releases all paired storage tokens. Keep single carried objects in
## the same dwarf's hands; crates go loose so ordinary fetch can split one unit.
func redirect_haul_to_placement(task_id: int, offer: Dictionary) -> bool:
	var task := get_task(task_id)
	var old := get_task(int(offer.task_id))
	var agent: DwarfAgent = _agents.get(int(offer.dwarf_id))
	if task == null or task.type != Task.Type.FETCH_BUILD or task.assigned_to >= 0: return false
	if old == null or old.type != Task.Type.HAUL or old.assigned_to != int(offer.dwarf_id) or not is_instance_valid(agent): return false
	if agent.is_sleeping() or agent.is_eating(): return false
	var source := get_work_source(task.source_id) as FurnitureGhostComponent
	if source == null or source.has_committed_item(): return false
	var item: Node3D = offer.item
	if not is_instance_valid(item) or item.is_queued_for_deletion(): return false
	var keep := bool(offer.carried) and int(offer.count) == 1 and agent.detach_placement_cargo(item)
	cancel_task(old.id)
	if keep:
		source.fetched_instance_id = String(item.get_meta("instance_id", ""))
		source.notify_picked_up(agent.dwarf_id)
		_assign(task, agent, item)
	else:
		source._ensure_claim()
	return true


## Cancels a task outright (player action / source destroyed). Assigned tasks
## are pulled from their dwarf, who returns to the idle pool.
func cancel_task(task_id: int) -> void:
	var task: Task = _tasks.get(task_id)
	if task == null:
		return
	if task.status == Task.Status.PENDING or task.status == Task.Status.BLOCKED:
		_remove_pending(task)
	elif task.assigned_to >= 0:
		var dwarf_id := task.assigned_to
		_active.erase(dwarf_id)
		var agent: DwarfAgent = _agents.get(dwarf_id)
		if agent != null and is_instance_valid(agent):
			agent.abort_task()
		_mark_idle(dwarf_id)
	task.status = Task.Status.CANCELLED
	journal.transition(task.order_locator,"cancelled","Assignment cancelled",0,task.assigned_to)
	_tasks.erase(task_id)
	# Emit while assigned_to is still intact: source-side cancel cleanup
	# (StorageComponent.cancel_haul, FurnitureGhostComponent.cancel_fetch,
	# MiningZoneComponent.release_worker) routes by the cancelled dwarf's id.
	# Clearing it before the emit made every cancel route receive -1 and skip
	# cleanup — leaking reservations whenever the agent-side abort_task above
	# couldn't run (agent freed/invalid). abort_task and the source-side paths
	# are all owner-guarded and idempotent, so both running is safe.
	task_cancelled.emit(task)
	task.assigned_to = -1


## The dwarf finished its task. Logs it, frees the dwarf back into the pool.
func complete_dwarf_task(dwarf_id: int, expected_task := -1, generation := -1) -> void:
	if not _matches_attempt(dwarf_id,expected_task,generation): return
	var task := _take_active(dwarf_id)
	if task == null:
		return
	task.status = Task.Status.COMPLETED
	journal.transition(task.order_locator,"waiting","Assignment finished; source reassesses remaining work",task.attempt.generation,dwarf_id)
	_log_completed(task)
	_tasks.erase(task.id)
	task_completed.emit(task)
	_mark_idle(dwarf_id)


## The RELEASE protocol (doc 16 §2.8): the task returns to PENDING intact;
## reservations are the source's to free on the task_released signal.
## requeue_dwarf=false when the dwarf is heading into an interrupt behaviour
## (sleep, combat) and will report idle later.
func release_dwarf_task(dwarf_id: int, reason: int, requeue_dwarf: bool = true, expected_task := -1, generation := -1) -> void:
	if expected_task >= 0 and not _matches_attempt(dwarf_id,expected_task,generation): return
	var task := _take_active(dwarf_id)
	if task == null:
		if requeue_dwarf:
			_mark_idle(dwarf_id)
		return
	task.status = Task.Status.PENDING
	task.assigned_to = -1
	task.planning_context.clear()
	_family_frontiers.erase(task.id)
	_worker_rejections.erase(task.id)
	task.wait_reason = release_reason(reason)
	journal.transition(task.order_locator,"waiting",task.wait_reason,task.attempt.generation,dwarf_id)
	_insert_pending(task)
	# PATH_INVALID means the dwarf actually failed to path there (stronger
	# evidence than a capped probe) — back the task off so the scheduler does
	# not immediately re-assign the same dead end (doc 16 §2.7 step 2).
	if reason in [Task.ReleaseReason.PATH_INVALID,Task.ReleaseReason.NO_PROGRESS,Task.ReleaseReason.MATERIAL_UNAVAILABLE,Task.ReleaseReason.PLAN_CHANGED,Task.ReleaseReason.SEARCH_BUDGET_EXHAUSTED]:
		_apply_backoff(task, Time.get_ticks_msec())
	task_released.emit(task, dwarf_id, reason)
	if requeue_dwarf:
		_mark_idle(dwarf_id)
	_wake_dirty = true


## External terrain changes invalidate the agent's current pickup/path as well
## as its lease. Abort first so carried goods and source reservations are safe.
func invalidate_dwarf_task(dwarf_id: int) -> void:
	var agent: DwarfAgent = _agents.get(dwarf_id)
	if is_instance_valid(agent): agent.abort_task()
	release_dwarf_task(dwarf_id, Task.ReleaseReason.PATH_INVALID)


## Permanent failure (target gone, invalid state). Task is removed, not retried.
func fail_dwarf_task(dwarf_id: int, reason: String, expected_task := -1, generation := -1) -> void:
	if not _matches_attempt(dwarf_id,expected_task,generation): return
	var task := _take_active(dwarf_id)
	if task == null:
		return
	task.status = Task.Status.FAILED
	journal.transition(task.order_locator,"failed",reason,task.attempt.generation,dwarf_id)
	_tasks.erase(task.id)
	task_failed.emit(task, reason)
	_mark_idle(dwarf_id)


# ── Public API — work sources (doc 16 §2.7) ──────────────────────────────────

## Source-id allocator (doc 19 §3.6 — the doc 18 tech debt, due with the
## third/fourth work-source families). Monotonic, starting above every
## existing keyspace (mining raw ids, stockpile zones at 1M). New families
## allocate here; migrating the old keyspaces is optional cleanup.
var _next_source_id: int = 10_000_000


func allocate_source_id() -> int:
	var id := _next_source_id
	_next_source_id += 1
	return id


func register_work_source(source_id: int, source: Object) -> void:
	_work_sources[source_id] = source
	var locator := SourceAdapter.locator(source,source_id)
	_source_locators[source_id] = locator
	journal.ensure(locator,SourceAdapter.label(source))


func unregister_work_source(source_id: int) -> void:
	var locator := String(_source_locators.get(source_id,""))
	journal.transition(locator,"retired","Source finished or removed")
	_source_locators.erase(source_id)
	_work_sources.erase(source_id)
	journal.prune(_source_locators.values())


## The work source behind a lease's source_id, or null if it is gone.
func get_work_source(source_id: int) -> Object:
	return _work_sources.get(source_id)


## Cancels every task posted by a work source (zone removed / mined out).
## exclude_task_id lets the finishing dwarf's own lease complete normally.
func cancel_source_tasks(source_id: int, exclude_task_id: int = -1) -> void:
	var to_cancel: Array[int] = []
	for id in _tasks:
		var task: Task = _tasks[id]
		if task.source_id == source_id and task.id != exclude_task_id:
			to_cancel.append(task.id)
	for id: int in to_cancel:
		cancel_task(id)


# ── Public API — dwarves ──────────────────────────────────────────────────────

func register_dwarf(agent: DwarfAgent) -> void:
	_agents[agent.dwarf_id] = agent
	_mark_idle(agent.dwarf_id)


func deregister_dwarf(dwarf_id: int) -> void:
	var agent: DwarfAgent = _agents.get(dwarf_id)
	if is_instance_valid(agent) and (_active.has(dwarf_id) or agent.is_eating()): agent.abort_task()
	if _active.has(dwarf_id):
		release_dwarf_task(dwarf_id, Task.ReleaseReason.SOURCE_EMPTY, false)
	_agents.erase(dwarf_id)
	_remove_idle(dwarf_id)


## A dwarf finished an interrupt behaviour and is available again.
func notify_dwarf_idle(dwarf_id: int) -> void:
	_mark_idle(dwarf_id)


## A dwarf entered an interrupt behaviour (sleep, combat) while holding NO
## task — it must leave the idle pool so the scheduler cannot assign to it
## until notify_dwarf_idle (doc 16 §2.8: a dwarf enters _idle_dwarves only
## after its interrupt behaviour resolves). Dwarves holding a task use
## release_dwarf_task(..., requeue_dwarf = false) instead.
func notify_dwarf_unavailable(dwarf_id: int) -> void:
	_remove_idle(dwarf_id)


## Clears transient scheduling state before a scene reload. Configuration and
## signal connections remain intact because this autoload survives the reload.
func reset_runtime_state() -> void:
	_family_frontiers.clear()
	_family_quanta.clear()
	_reconcile_cursor = 0
	_source_locators.clear()
	_planning_holds.clear()
	_supervision_cursor = 0
	_supervision_accum = 0.0
	var next_generation: int = journal.next_attempt
	journal = Journal.new()
	journal.next_attempt = next_generation
	_worker_rejections.clear()
	_worker_cursor.clear()
	_work_probe.clear()
	_work_probes.clear()
	_surface_matches.clear()
	_next_type = -1
	_tasks.clear()
	_pending.clear()
	_active.clear()
	_idle_dwarves.clear()
	_agents.clear()
	_completed_log.clear()
	_scan_cursor.clear()
	_haul_match.clear()
	_surface_match.clear()
	_move_match.clear()
	_craft_match.clear()
	_idle_version += 1
	_work_sources.clear()
	_next_task_id = 1
	_next_source_id = 10_000_000
	_blocked_count = 0
	_wake_dirty = false
	_heartbeat_accum = 0.0


# ── Stats (debug overlay, doc 16 Phase 0) ────────────────────────────────────

func get_scheduler_stats() -> Dictionary:
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

func _run_scheduler() -> void:
	if _idle_dwarves.is_empty() or _tasks.is_empty():
		return
	var t_start := Time.get_ticks_usec()
	var probes_left := _max_probes_per_wake
	_wake_count += 1

	# Colony bonuses are computed ONCE per wake, per type (doc 16 §2.2) —
	# stubbed at 0 until stockpiles exist; the structure is the point.
	var bonus: Dictionary = {}
	for type in _pending:
		bonus[type] = _colony_bonus(int(type))

	_assign_idle_pass(bonus, probes_left, t_start)

	var wake_usec := int(Time.get_ticks_usec() - t_start)
	if wake_usec > _worst_wake_usec:
		_worst_wake_usec = wake_usec


func _within_budget(t_start: int, probes_left: int) -> bool:
	if Time.get_ticks_usec() - t_start < _budget_usec and probes_left > 0: return true
	_wake_dirty = true
	return false


func _assign_idle_pass(bonus: Dictionary, probes_left: int, t_start: int) -> int:
	# Visit priority buckets before workers. Otherwise a nearer dwarf could be
	# pulled into surface work before considering their higher-priority jobs.
	var types := _pending.keys().filter(func(type: int): return not (_pending[type] as Array).is_empty())
	types.sort_custom(func(a: int, b: int) -> bool:
		var pa := _bucket_priority(a, bonus)
		var pb := _bucket_priority(b, bonus)
		return pa > pb if pa != pb else a < b)
	var start := maxi(0, types.find(_next_type))
	_next_type = -1
	for offset in range(types.size()):
		var index := (start + offset) % types.size()
		var type: int = types[index]
		if not _within_budget(t_start, probes_left):
			_next_type = type
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
			_next_type = types[(index + 1) % types.size()]
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
			_remove_idle(dwarf_id)
			_agents.erase(dwarf_id)
			continue
		if type in _types_for(agent):
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
		hold_for_planning(agent)
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
			var fetch_result := FetchPlanner.advance(src,agent,_work_probe,_probe_node_cap,t_start+_budget_usec)
			task.wait_reason = String(_work_probe.get("reason","Checking pickup and installation routes"))
			if fetch_result == NavGrid.ProbeResult.SEARCHING:
				_yield_candidate(task,agent,idx)
				return 0
			if fetch_result == NavGrid.ProbeResult.REACHABLE:
				task.blocked_count = 0
				_assign(task,agent)
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
				_assign(task, agent)
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
			if type==Task.Type.UNINSTALL and src is InstalledFurnitureComponent and String(src.def.get("placement","floor"))=="wall":
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
			_assign(task, agent)
			_scan_cursor[type] = (cursor + scanned) % maxi(ids.size(), 1)
			return probes_left
		_reject_worker_route(task, agent, now)
	_scan_cursor[type] = 0
	return probes_left


## Failed worker/lease pairs are local to the idle pool and navigation state.
func _rejected_workers(task: Task) -> Dictionary:
	var signature := [_idle_version, NavGrid.ladder_revision, task.blocked_count]
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
		if is_instance_valid(other) and task.type in _types_for(other) and rejected.get(id, Vector3i(-1,-1,-1)) != other.current_cell():
			return
	_apply_backoff(task, now)


## Each matching family owns at most one frontier. Exhausting one wake yields
## and resumes next frame; only a finished failed search applies backoff.
func _advance_work_probe(context: Dictionary, from: Vector3i, goal: Vector3i, t_start: int, goals: Dictionary = {}) -> int:
	if not context.has("route_query"): context.route_query = {}
	var result := RouteProbe.advance(context.route_query, from, goal,
		_probe_node_cap, t_start + _budget_usec,goals.is_empty(),goals)
	if result == NavGrid.ProbeResult.SEARCHING:
		_wake_dirty = true
	else:
		if not context.has("route_dependencies"): context.route_dependencies = {}
		context.route_dependencies.merge(context.route_query.get("chunks",{}))
		context["last_route"] = context.route_query
		context["ladder_revision"] = NavGrid.ladder_revision
		if result == NavGrid.ProbeResult.REACHABLE: NavGrid.remember_reachable_path(context.route_query)
		if result == NavGrid.ProbeResult.BUDGET_EXHAUSTED: context["unknown"] = true
		if result == NavGrid.ProbeResult.BUDGET_EXHAUSTED:
			var task := get_task(int(context.get("task_id",-1)))
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
	if result == NavGrid.ProbeResult.SEARCHING \
			and int(context.get("route_query",{}).get("expanded",0)) > before \
			and planning_held(agent.dwarf_id):
		_planning_holds[agent.dwarf_id].until = journal.now \
			+ float(get_config_section("supervision").get("planning_hold_seconds",4.0))
	return result


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
	var result := RouteProbe.advance(query, from, _work_probe.goals.keys()[0],
		_probe_node_cap, t_start + _budget_usec, false, _work_probe.goals)
	if result == NavGrid.ProbeResult.REACHABLE:
		var candidate: Dictionary = _work_probe.goals[query.path.back()]
		if not source.mining_candidate_available(candidate):
			_work_probe.clear()
			_wake_dirty = true
			return NavGrid.ProbeResult.SEARCHING
		source.prefer_mining_stand(agent.dwarf_id, candidate)
		# Execution keeps the exact proven block, stand and route.
		NavGrid.remember_reachable_path(query)
	elif result == NavGrid.ProbeResult.SEARCHING:
		_wake_dirty = true
	return result


## Continue a Move with its uprooter when already at the pickup; otherwise
## choose a nearby eligible replacement. Normal priorities still run first.
## Both pickup and delivery probes can yield; no item changes owner until the
## selected dwarf enters the ordinary fetch executor.
func _try_assign_move(task: Task, source: Object, quote: Dictionary, probes_left: int, t_start: int) -> int:
	if int(_move_match.get("task_id", -1)) != task.id or int(_move_match.get("idle_version", -1)) != _idle_version \
		or _move_match.get("signature", []) != quote.signature:
		_move_match = {"task_id": task.id, "idle_version": _idle_version, "signature": quote.signature,
			"idle": _idle_dwarves.duplicate(), "index": 0, "candidates": [], "ranked": false,
			"probe_index": 0, "pickup_ok": false}
	while int(_move_match.index) < _move_match.idle.size():
		if not _within_budget(t_start, probes_left): return 0
		var dwarf_id: int = _move_match.idle[_move_match.index]
		_move_match.index += 1
		var agent: DwarfAgent = _agents.get(dwarf_id)
		if not is_instance_valid(agent) or not dwarf_id in _idle_dwarves or not task.type in _types_for(agent): continue
		hold_for_planning(agent)
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
			_wake_dirty = true
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
				"delivery_stand":_move_match.last_route.path.back(),"material":{"node":source._claim,"cell":source.drop_manager.item_floor_cell(source._claim),"key":source.item_key}})
			_move_match.clear()
			task.blocked_count = 0
			_assign(task, agent)
			return probes_left
		_move_match.probe_index += 1
		_move_match.pickup_ok = false
	_move_match.clear()
	_apply_backoff(task, Time.get_ticks_msec())
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
			cancel_task(task.id)
			continue
		var signature: Array = source.scheduling_signature()
		if _craft_match.get("signature",[]) != signature or int(_craft_match.get("idle_version",-1)) != _idle_version:
			_craft_match = {"task_id":task.id, "signature":signature, "idle_version":_idle_version,
				"idle":_idle_dwarves.duplicate(), "index":0, "query":{}, "candidates":[],
				"ranked":false, "excluded":{}, "eligible":0, "pickup_ok":false}
		while int(_craft_match.index) < _craft_match.idle.size():
			if not _within_budget(t_start,probes_left): return 0
			var dwarf_id: int = _craft_match.idle[_craft_match.index]
			var candidate_agent: DwarfAgent = _agents.get(dwarf_id)
			if not is_instance_valid(candidate_agent) or not dwarf_id in _idle_dwarves or not Task.Type.CRAFT in _types_for(candidate_agent):
				_craft_match.index += 1
				_craft_match.query = {}
				continue
			hold_for_planning(candidate_agent)
			var from := candidate_agent.current_cell()
			if _craft_match.get("from",from) != from: _craft_match.query = {}
			_craft_match.from = from
			var query: Dictionary = _craft_match.query
			if not source.advance_worker_quote(from,query,t_start+_budget_usec,_craft_match.excluded.get(dwarf_id,{})):
				_wake_dirty = true
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
			_apply_backoff(task,now)
			continue
		if not _within_budget(t_start,probes_left): return 0
		var candidate: Dictionary = _craft_match.candidates[0]
		var agent: DwarfAgent = _agents.get(int(candidate.dwarf_id))
		if not is_instance_valid(agent) or agent.current_cell() != candidate.from:
			_craft_match.clear()
			_wake_dirty = true
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
		_assign(task,agent)
	return probes_left


func _advance_craft_probe(from: Vector3i, goals: Dictionary, t_start: int) -> int:
	if goals.is_empty(): return NavGrid.ProbeResult.UNREACHABLE
	if not _craft_match.has("route_query"): _craft_match.route_query = {}
	var query: Dictionary = _craft_match.route_query
	var result := RouteProbe.advance(query,from,goals.keys()[0],
		_probe_node_cap,t_start+_budget_usec,false,goals)
	if not _craft_match.has("route_dependencies"): _craft_match.route_dependencies = {}
	_craft_match.route_dependencies.merge(query.get("chunks",{}))
	if result == NavGrid.ProbeResult.BUDGET_EXHAUSTED:
		var task := get_task(int(_craft_match.get("task_id",-1)))
		if task != null: task.wait_reason = "Route search budget exhausted; reachability unknown"
	if result == NavGrid.ProbeResult.SEARCHING: _wake_dirty = true
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
	return type in [Task.Type.FELL_TREE, Task.Type.CLEAR_BOULDER, Task.Type.GATHER_SCREE,
		Task.Type.HARVEST_SHRUB, Task.Type.CLEAR_SHRUB, Task.Type.CLEAR_PLANT, Task.Type.UPROOT_SHRUB, Task.Type.HARVEST_TREE]


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
		if int(_surface_match.get("task_id", -1)) != task.id or int(_surface_match.get("idle_version", -1)) != _idle_version:
			_surface_match = {"task_id": task.id, "idle_version": _idle_version,
				"idle": _idle_dwarves.duplicate(), "index": 0, "candidates": [],
				"ranked": false, "probe_index": 0, "eligible": 0}
		while int(_surface_match.index) < _surface_match.idle.size():
			if not _within_budget(t_start, probes_left): return 0
			var dwarf_id: int = _surface_match.idle[_surface_match.index]
			_surface_match.index += 1
			var agent: DwarfAgent = _agents.get(dwarf_id)
			if not is_instance_valid(agent) or not dwarf_id in _idle_dwarves or not type in _types_for(agent): continue
			_surface_match.eligible += 1
			hold_for_planning(agent)
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
			if not is_instance_valid(agent) or not int(candidate.dwarf_id) in _idle_dwarves or not type in _types_for(agent): continue
			if agent.current_cell() != candidate.from:
				_surface_match.clear()
				_wake_dirty = true
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
			_assign(task, agent)
			assigned = true
			break
		var eligible := int(_surface_match.eligible)
		_surface_match.clear()
		_scan_cursor[type] = int(_scan_cursor.get(type, 0)) + 1
		if eligible == 0: return probes_left
		if not assigned: _apply_backoff(task, now)
	return probes_left


## HAUL leases belong to destinations, but their worker should be near the
## first pickup. Compare every eligible idle dwarf before claiming any goods.
## Ranking and both route probes resume across wakes; a failed near worker
## does not back off the task until the other candidates have been tried.
func _try_assign_hauls(probes_left: int, t_start: int) -> int:
	var deadline := t_start + _budget_usec
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
		if _haul_match.is_empty() or int(_haul_match.get("idle_version",-1)) != _idle_version or int(_haul_match.get("revision",-1)) != revision:
			_haul_match = {"task_id": task.id, "idle_version": _idle_version, "revision": revision,
				"idle": _idle_dwarves.duplicate(), "index": 0, "query": {}, "candidates": [],
				"ranked": false, "probe_index": 0, "pickup_ok": false, "eligible": 0,
				"excluded": {}, "blocked_workers": {}, "failed": false, "pickup_snapshot": {}}
		while int(_haul_match.index) < _haul_match.idle.size():
			if not _within_budget(t_start, probes_left): return 0
			var dwarf_id: int = _haul_match.idle[_haul_match.index]
			var agent: DwarfAgent = _agents.get(dwarf_id)
			if not is_instance_valid(agent) or not dwarf_id in _idle_dwarves or not Task.Type.HAUL in _types_for(agent) or _haul_match.blocked_workers.has(dwarf_id):
				_haul_match.index += 1
				_haul_match.query = {}
				continue
			hold_for_planning(agent)
			var from := agent.current_cell()
			var query: Dictionary = _haul_match.query
			if query.has("from") and query.from != from: query.clear()
			query.from = from
			query.exclude = _haul_match.excluded.get(dwarf_id, {})
			# Source filtering is identical for every worker in this comparison.
			# Inventory/idle invalidation above discards the shared snapshot too.
			query.pickup_snapshot = _haul_match.pickup_snapshot
			if is_instance_valid(source) and source.has_method("advance_haul_quote"):
				if not bool(source.advance_haul_quote(from, query, deadline)):
					_wake_dirty = true
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
		while int(_haul_match.probe_index) < _haul_match.candidates.size():
			if not _within_budget(t_start, probes_left): return 0
			var candidate: Dictionary = _haul_match.candidates[_haul_match.probe_index]
			var agent: DwarfAgent = _agents.get(int(candidate.dwarf_id))
			if not is_instance_valid(agent) or not int(candidate.dwarf_id) in _idle_dwarves:
				_haul_match.probe_index += 1
				_haul_match.pickup_ok = false
				continue
			if agent.current_cell() != candidate.from:
				_haul_match.clear() # e.g. a developer walk order moved an idle actor
				_wake_dirty = true
				return 0
			if not bool(_haul_match.pickup_ok):
				probes_left -= 1
				_probes_total += 1
				var pickup_goals := {}
				if source is StorageComponent:
					for cell: Vector3i in StorageComponent.ground_access_cells(candidate.cell):
						if NavGrid.is_walkable(cell): pickup_goals[cell] = true
				var pickup := NavGrid.ProbeResult.UNREACHABLE if source is StorageComponent and pickup_goals.is_empty() else _advance_work_probe(_haul_match, candidate.from, candidate.cell, t_start,pickup_goals)
				if pickup == NavGrid.ProbeResult.SEARCHING: return 0
				if pickup != NavGrid.ProbeResult.REACHABLE:
					_haul_match.failed = true
					if is_instance_valid(source) and source.has_method("advance_haul_quote"):
						var excluded: Dictionary = _haul_match.excluded.get(int(candidate.dwarf_id), {})
						excluded[candidate.cell] = true
						_haul_match.excluded[int(candidate.dwarf_id)] = excluded
						_restart_haul_ranking()
						rerank = true
						break
					_haul_match.probe_index += 1
					continue
				_haul_match.pickup_ok = true
				candidate["pickup_stand"] = _haul_match.last_route.path.back()
			if not _within_budget(t_start, probes_left): return 0
			var destination := task.target_pos
			if is_instance_valid(source) and source.has_method("nearest_stand_target"):
				destination = source.nearest_stand_target(candidate.pickup_stand)
			var delivery_goals := {}
			if source is StorageComponent:
				for cell: Vector3i in source.delivery_stand_cells(destination):
					if NavGrid.is_walkable(cell): delivery_goals[cell] = true
			probes_left -= 1
			_probes_total += 1
			var has_approach := destination.x >= 0 and (not source is StorageComponent or not delivery_goals.is_empty())
			var delivery := _advance_work_probe(_haul_match, candidate.pickup_stand, destination, t_start,delivery_goals) if has_approach else NavGrid.ProbeResult.UNREACHABLE
			if delivery == NavGrid.ProbeResult.SEARCHING: return 0
			if delivery == NavGrid.ProbeResult.REACHABLE:
				task.blocked_count = 0
				task.payload["haul_excluded_cells"] = (_haul_match.excluded.get(agent.dwarf_id, {}) as Dictionary).keys()
				_haul_match.clear()
				_assign(task, agent)
				assigned = true
				break
			_haul_match.probe_index += 1
			_haul_match.pickup_ok = false
			_haul_match.blocked_workers[int(candidate.dwarf_id)] = true
			_haul_match.failed = true
		if assigned: continue # claims changed; rank the next lease against remaining goods
		if rerank: continue
		if int(_haul_match.eligible) == 0 and not bool(_haul_match.failed):
			_haul_match.clear()
			return probes_left
		if _haul_match.candidates.is_empty() and not bool(_haul_match.failed):
			cancel_task(task.id) # stale lease: no compatible unreserved goods/room
		else:
			_apply_backoff(task, now)
		_scan_cursor[Task.Type.HAUL] = int(_scan_cursor.get(Task.Type.HAUL, 0)) + 1
		_haul_match.clear()
	return probes_left


func _restart_haul_ranking() -> void:
	_haul_match.index = 0
	_haul_match.query = {}
	_haul_match.candidates = []
	_haul_match.ranked = false
	_haul_match.probe_index = 0
	_haul_match.pickup_ok = false
	_haul_match.eligible = 0


func _assign(task: Task, agent: DwarfAgent, carried_item: Node3D = null) -> void:
	_remove_pending(task)
	task.status = Task.Status.ASSIGNED
	task.assigned_to = agent.dwarf_id
	task.attempt = Attempt.new()
	task.attempt.generation = journal.next_attempt
	journal.next_attempt += 1
	task.attempt.task_id = task.id
	task.attempt.worker_id = agent.dwarf_id
	task.attempt.order_key = task.order_key
	task.attempt.observe({"step":"assigned"},journal.now,_progress_grace())
	task.wait_reason = ""
	journal.transition(task.order_locator,"running","Assigned",task.attempt.generation,agent.dwarf_id)
	_active[agent.dwarf_id] = task.id
	_remove_idle(agent.dwarf_id)
	agent.receive_task(task.id, task.target_pos, carried_item)
	# receive_task may synchronously reject or finish an assignment.
	if _active.get(agent.dwarf_id,-1) == task.id: task_assigned.emit(task, agent.dwarf_id)


func _apply_backoff(task: Task, now: int) -> void:
	if task.wait_reason.is_empty() or task.wait_reason == "Waiting for assessment": task.wait_reason = "No proven route for eligible workers"
	journal.transition(task.order_locator,"waiting",task.wait_reason)
	task.blocked_count += 1
	var delay_s: float = minf(pow(_backoff_base_s, float(task.blocked_count)), _backoff_max_s)
	task.retry_at = now + int(delay_s * 1000.0)
	_blocked_count += 1
	if task.blocked_count == _unreachable_threshold:
		task_unreachable.emit(task)


## Profession capability and player permissions both apply. Self-care and
## carrying supplies within an allowed assignment are never separate gates.
func _types_for(agent: DwarfAgent) -> Array[int]:
	if agent.is_sleeping() or agent.is_eating() or not NavGrid.is_navigable(agent.current_cell()): return []
	if agent.promotion_pending(): return []
	if agent.needs_bridge_exit(): return []
	var types: Array[int] = [Task.Type.MINE, Task.Type.HAUL, Task.Type.BUILD, Task.Type.FARM,
			Task.Type.BREW, Task.Type.FETCH_BUILD, Task.Type.UNINSTALL, Task.Type.FELL_TREE, Task.Type.CLEAR_BOULDER, Task.Type.GATHER_SCREE, Task.Type.HARVEST_SHRUB, Task.Type.CLEAR_SHRUB, Task.Type.CLEAR_PLANT, Task.Type.UPROOT_SHRUB, Task.Type.HARVEST_TREE]
	if agent.profession == "base:profession:worker": types.append(Task.Type.CRAFT)
	if agent.work_permissions.is_empty(): return types
	var allowed: Array[int] = []
	for type: int in types:
		if agent.allows_task(type): allowed.append(type)
	return allowed


func work_policy_changed() -> void:
	_worker_rejections.clear()
	for task: Task in _tasks.values(): task.planning_context.clear()
	# Quotes and resumable probes may include a now-ineligible dwarf.
	_idle_version += 1
	_work_probe.clear()
	_surface_match.clear()
	_work_probes.clear()
	_surface_matches.clear()
	_next_type = -1
	_move_match.clear()
	_craft_match.clear()
	_haul_match.clear()
	_wake_dirty = true


func _bucket_priority(type: int, bonus: Dictionary) -> int:
	return int(_static_priorities.get(Task.type_name(type), 1)) + int(bonus.get(type, 0))


## Colony-state priority bonuses (doc 31: +20 BREW when ale < 10, ...).
## Stub until stockpiles exist.
func _colony_bonus(_type: int) -> int:
	return 0


# ── Pending bucket maintenance (sorted by static priority desc) ──────────────

func _insert_pending(task: Task) -> void:
	if not _pending.has(task.type):
		_pending[task.type] = []
	var ids: Array = _pending[task.type]
	var lo := 0
	var hi := ids.size()
	while lo < hi:
		@warning_ignore("integer_division")
		var mid := (lo + hi) / 2
		var other: Task = _tasks.get(ids[mid])
		if other != null and other.priority >= task.priority:
			lo = mid + 1
		else:
			hi = mid
	ids.insert(lo, task.id)


func _remove_pending(task: Task) -> void:
	_family_frontiers.erase(task.id)
	_family_quanta.erase(task.id)
	_worker_rejections.erase(task.id)
	if int(_craft_match.get("task_id",-1)) == task.id: _craft_match.clear()
	var ids: Array = _pending.get(task.type, [])
	ids.erase(task.id)
	if Time.get_ticks_msec() < task.retry_at:
		_blocked_count = maxi(0, _blocked_count - 1)


func _take_active(dwarf_id: int) -> Task:
	if not _active.has(dwarf_id):
		return null
	var task: Task = _tasks.get(_active[dwarf_id])
	_active.erase(dwarf_id)
	return task


func _remove_idle(dwarf_id: int) -> void:
	_planning_holds.erase(dwarf_id)
	if dwarf_id in _idle_dwarves:
		_idle_dwarves.erase(dwarf_id)
		_idle_version += 1


func _mark_idle(dwarf_id: int) -> void:
	if _active.has(dwarf_id): return
	if not _agents.has(dwarf_id):
		return
	if not is_instance_valid(_agents[dwarf_id]) or not _agents[dwarf_id].is_inside_tree(): return
	if _agents[dwarf_id].promotion_pending() or _agents[dwarf_id].is_sleeping() or _agents[dwarf_id].is_eating(): return
	if _agents[dwarf_id].has_method("needs_ladder_exit") and _agents[dwarf_id].needs_ladder_exit():
		return
	if _agents[dwarf_id].has_method("needs_bridge_exit") and _agents[dwarf_id].needs_bridge_exit(): return
	if not _idle_dwarves.has(dwarf_id):
		if _idle_dwarves.is_empty(): _next_type = -1
		_idle_dwarves.append(dwarf_id)
		_idle_version += 1
	_wake_dirty = true


func _log_completed(task: Task) -> void:
	_worker_rejections.erase(task.id)
	task.planning_context.clear()
	_completed_log.append({
		"id": task.id, "type": Task.type_name(task.type),
		"target": task.target_pos, "at_msec": Time.get_ticks_msec(),
	})
	if _completed_log.size() > 200:
		_completed_log.pop_front()


## Registry-pattern accessor: TaskManager is the ONE owner of task_config.json;
## other task-adjacent systems (StockpileManager's hauling block, doc 18) read
## their sections through here rather than opening the file.
func get_config_section(section: String) -> Dictionary:
	return _config_raw.get(section, {})


# ── Early re-arm: terrain changed near a blocked target (doc 16 §2.4) ────────

func ladder_routes_changed() -> void:
	for task: Task in _tasks.values():
		task.planning_context.clear()
		task.recovery_paused = false
	_work_probe.clear()
	_surface_match.clear()
	_work_probes.clear()
	_surface_matches.clear()
	_next_type = -1
	_move_match.clear()
	_craft_match.clear()
	_haul_match.clear()
	for task: Task in _tasks.values():
		if task.status in [Task.Status.PENDING, Task.Status.BLOCKED]: task.retry_at = 0
	_wake_dirty = true

func _on_chunk_dirtied(cx: int, cy: int, cz: int) -> void:
	var chunk := Vector3i(cx,cy,cz)
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
	if _blocked_count <= 0:
		return   # fast gate — streaming fires this constantly during worldgen
	var now := Time.get_ticks_msec()
	var re_armed := 0
	for type in _pending:
		var ids: Array = _pending[type]
		for id in ids:
			var task: Task = _tasks.get(id)
			if task == null or now >= task.retry_at:
				continue
			if task.target_pos.x >> 4 == cx and task.target_pos.y >> 4 == cy \
					and task.target_pos.z >> 4 == cz:
				task.retry_at = now
				re_armed += 1
	if re_armed > 0:
		_blocked_count = maxi(0, _blocked_count - re_armed)
		_wake_dirty = true


# ── Config loader ─────────────────────────────────────────────────────────────

func _load_config() -> void:
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		push_warning("TaskManager: cannot open %s — using built-in defaults." % CONFIG_PATH)
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_error("TaskManager: JSON parse error in %s — %s" % [CONFIG_PATH, json.get_error_message()])
		file.close()
		return
	file.close()
	var d: Dictionary = json.data
	_config_raw = d
	var s: Dictionary = d.get("scheduler", {})
	_budget_usec = int(s.get("scheduler_budget_usec", _budget_usec))
	_max_probes_per_wake = int(s.get("max_probes_per_wake", _max_probes_per_wake))
	_probe_node_cap = int(s.get("probe_node_cap", _probe_node_cap))
	_heartbeat_s = float(s.get("heartbeat_interval_s", _heartbeat_s))
	_backoff_base_s = float(s.get("backoff_base_s", _backoff_base_s))
	_backoff_max_s = float(s.get("backoff_max_s", _backoff_max_s))
	_unreachable_threshold = int(s.get("unreachable_signal_threshold", _unreachable_threshold))
	_static_priorities = d.get("static_priorities", {})


# Shared execution contract. Optional expected IDs are retained for external
# administrative callers; all dwarf execution uses both fencing fields.
func _matches_attempt(dwarf_id: int, expected_task: int, generation: int) -> bool:
	var task := get_task(int(_active.get(dwarf_id,-1)))
	return task != null and (expected_task < 0 or task.id == expected_task) \
		and (generation < 0 or (task.attempt != null and task.attempt.generation == generation))

func commit_step(dwarf_id: int, task_id: int, generation: int, unit: String, operation: Callable) -> bool:
	if not _matches_attempt(dwarf_id,task_id,generation) or not operation.is_valid(): return false
	var task := get_task(task_id)
	var attempt: RefCounted = task.attempt
	if attempt.commits.has(unit): return false
	# Fence BEFORE the callback: source commits can synchronously emit events,
	# retire a lease or re-enter this method. A duplicate never performs effects.
	attempt.commits[unit] = "committing"
	var result: Variant = operation.call()
	if result is bool and not result:
		attempt.commits.erase(unit)
		return false
	attempt.commits[unit] = "committed"
	if journal.records.has(task.order_locator): journal.records[task.order_locator].failures = 0
	journal.transition(task.order_locator,"running","Committed %s" % unit,generation,dwarf_id)
	return true

static func release_reason(reason: int) -> String:
	match reason:
		Task.ReleaseReason.NEED_INTERRUPT: return "Worker attending to needs"
		Task.ReleaseReason.COMBAT: return "Worker interrupted by combat"
		Task.ReleaseReason.PLAYER: return "Worker interrupted by player"
		Task.ReleaseReason.PATH_INVALID: return "Route changed or approach blocked"
		Task.ReleaseReason.SOURCE_EMPTY: return "No currently available work at source"
		Task.ReleaseReason.NO_PROGRESS: return "Worker stopped making progress; replanning"
		Task.ReleaseReason.MATERIAL_UNAVAILABLE: return "Waiting for matching supplies"
		Task.ReleaseReason.PLAN_CHANGED: return "Work plan changed; reassessing"
		Task.ReleaseReason.SEARCH_BUDGET_EXHAUSTED: return "Route search budget exhausted; reachability unknown"
	return "Waiting for reassessment"

func _progress_grace() -> float:
	return float(get_config_section("supervision").get("no_progress_seconds",12.0))

func advance_supervision(seconds: float) -> void:
	if WorldClock.paused or SaveManager.is_loading(): return
	journal.now += maxf(0.0,seconds)
	_supervision_accum += maxf(0.0,seconds)
	if _supervision_accum < float(get_config_section("supervision").get("interval_seconds",.5)): return
	_supervision_accum = 0.0
	_reconcile_workers()
	var ids := _active.keys()
	if ids.is_empty(): return
	var deadline := Time.get_ticks_usec()+int(get_config_section("supervision").get("budget_usec",500))
	var count := mini(ids.size(),int(get_config_section("supervision").get("attempts_per_pass",8)))
	for unused in range(count):
		var id: int = ids[_supervision_cursor % ids.size()]
		_supervision_cursor += 1
		var task := get_task(int(_active.get(id,-1)))
		if task == null or task.attempt == null: continue
		var agent: DwarfAgent = _agents.get(id)
		if not is_instance_valid(agent) or agent.current_task_id != task.id:
			_recover_attempt(task,"Worker and assignment disagree")
		elif task.source_id >= 0 and not is_instance_valid(get_work_source(task.source_id)):
			agent.abort_task()
			fail_dwarf_task(id,"Work source removed",task.id,task.attempt.generation)
		else:
			task.attempt.observe(Execution.sample(agent),journal.now,_progress_grace())
			if task.attempt.stalled(journal.now,_progress_grace()):
				_recover_attempt(task,"No progress during %s" % task.attempt.step)
			else:
				task.status = Task.Status.IN_PROGRESS
				journal.transition(task.order_locator,"running",task.attempt.step,task.attempt.generation,id)
		if Time.get_ticks_usec() >= deadline: break

func _recover_attempt(task: Task, reason: String) -> void:
	var id := task.assigned_to
	var generation: int = task.attempt.generation
	var agent: DwarfAgent = _agents.get(id)
	if is_instance_valid(agent): agent.abort_task()
	journal.transition(task.order_locator,"recovering",reason,generation,id)
	var record: Dictionary = journal.records.get(task.order_locator,{})
	record["failures"] = int(record.get("failures",0))+1
	release_dwarf_task(id,Task.ReleaseReason.NO_PROGRESS,true,task.id,generation)
	if int(record.failures) >= int(get_config_section("supervision").get("recovery_limit",3)):
		task.recovery_paused = true
		task.wait_reason = "Needs attention: repeated %s" % reason.to_lower()
		journal.transition(task.order_locator,"attention",task.wait_reason,generation,id)

func retry_order(order_key: String, reason: String = "Retry requested") -> void:
	for task: Task in _tasks.values():
		if task.order_key != order_key or task.assigned_to >= 0: continue
		task.recovery_paused = false
		task.retry_at = 0
		task.blocked_count = 0
		task.wait_reason = reason
		task.planning_context.clear()
		_worker_rejections.erase(task.id)
		_family_frontiers.erase(task.id)
		if journal.records.has(task.order_locator): journal.records[task.order_locator].failures = 0
		journal.transition(task.order_locator,"ready",task.wait_reason)
	_wake_dirty = true

func worker_availability(agent: DwarfAgent) -> String:
	if not is_instance_valid(agent): return "Unavailable"
	if agent.is_sleeping() or agent.is_eating() or agent.promotion_pending(): return "Self-care"
	if agent.needs_bridge_exit() or agent.needs_ladder_exit(): return "Recovering access"
	if not NavGrid.is_navigable(agent.current_cell()): return "Trapped: no navigable footing"
	if _active.has(agent.dwarf_id): return "Working"
	return "Available"

func job_diagnostics() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var locators := _source_locators.values()
	for task: Task in _tasks.values():
		if not task.order_locator in locators: locators.append(task.order_locator)
	for locator: String in locators:
		var source_id: int = int(_source_locators.find_key(locator)) if _source_locators.find_key(locator) != null else -1
		var record: Dictionary = journal.records.get(locator,{})
		if record.is_empty(): continue
		var row := record.duplicate(true)
		row["attempts"] = []
		row["rejections"] = 0
		var pending := false
		for task: Task in _tasks.values():
			if task.order_locator != locator: continue
			row.rejections += (_worker_rejections.get(task.id,{}).get("workers",{}) as Dictionary).size()
			if task.assigned_to >= 0 and task.attempt != null: row.attempts.append(task.attempt.describe(journal.now))
			else:
				pending = true
				row.reason = task.wait_reason
				var eligible := _idle_dwarves.any(func(id: int): return is_instance_valid(_agents.get(id)) and task.type in _types_for(_agents[id]))
				if not eligible and not task.recovery_paused: row.reason = "No eligible available worker"
				row.state = "attention" if task.recovery_paused else "waiting"
		if not row.attempts.is_empty(): row.state = "running"
		elif not pending:
			row.state = "waiting"
			row.reason = SourceAdapter.waiting_reason(get_work_source(source_id))
		row["history"] = journal.history.filter(func(event: Dictionary): return event.order == row.key).slice(-12)
		result.append(row)
	result.sort_custom(func(a: Dictionary,b: Dictionary): return a.key.naturalnocasecmp_to(b.key)<0)
	return result

func save_section_key() -> String: return "jobs"
func save_restore_priority() -> int: return 5
func serialize_state() -> Dictionary: return journal.serialize(_source_locators.values())
func restore_state(saved: Dictionary) -> void: journal.restore(saved)

func _yield_candidate(task: Task, agent: DwarfAgent, index: int) -> void:
	var context: Dictionary = task.planning_context.get(agent.dwarf_id,{})
	context["slices"] = int(context.get("slices",0))+1
	var quantum := int(get_config_section("supervision").get("planning_quantum_slices",8))
	_scan_cursor[task.type] = index
	if int(context.slices) >= quantum:
		context.slices = 0
		_scan_cursor[task.type] = index+1
		_worker_cursor[task.type] = int(_worker_cursor.get(task.type,0))+1
	_wake_dirty = true

func hold_for_planning(agent: DwarfAgent) -> void:
	if not is_instance_valid(agent) or agent.current_task_id >= 0: return
	if agent.is_walking() and (agent._idle_behavior == null or not agent._idle_behavior.owns_walk()): return
	var hold: Dictionary = _planning_holds.get(agent.dwarf_id,{})
	if not hold.is_empty() and journal.now < float(hold.until)+2.0: return
	var duration := float(get_config_section("supervision").get("planning_hold_seconds",4.0))
	_planning_holds[agent.dwarf_id] = {"until":journal.now+duration}
	if agent._idle_behavior != null and agent._idle_behavior.state != "leaving_room": agent._idle_behavior.cancel()

func planning_held(dwarf_id: int) -> bool:
	return journal.now < float(_planning_holds.get(dwarf_id,{}).get("until",-1.0))

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
		if int(_family_quanta[retained.id]) >= int(get_config_section("supervision").get("planning_quantum_slices",8)):
			_family_quanta[retained.id] = 0
			_scan_cursor[type] = maxi(0,(_pending.get(type,[]) as Array).find(retained.id))+1
	return probes_left

## Missed availability notifications cannot permanently lose a registered
## worker. This inspects a bounded subset, never scans world objects.
func _reconcile_workers() -> void:
	var ids := _agents.keys()
	for unused in range(mini(ids.size(),4)):
		var id: int = ids[_reconcile_cursor%ids.size()]
		_reconcile_cursor += 1
		var agent: DwarfAgent = _agents.get(id)
		if not is_instance_valid(agent):
			deregister_dwarf(id)
			continue
		if _active.has(id):
			_remove_idle(id)
			continue
		if agent.current_task_id >= 0:
			# An orphan executor must relinquish its real cargo before rejoining.
			agent.abort_task()
		if agent.is_sleeping() or agent.is_eating() or agent.promotion_pending() or agent.needs_bridge_exit() or agent.needs_ladder_exit():
			_remove_idle(id)
		elif not id in _idle_dwarves:
			_mark_idle(id)

## Read-only contract checks for fault tests and development diagnostics.
func lifecycle_errors() -> Array[String]:
	var errors: Array[String] = []
	for id: int in _active:
		var task := get_task(int(_active[id]))
		var agent: DwarfAgent = _agents.get(id)
		if task == null or task.assigned_to != id: errors.append("Active worker has no matching lease: %d"%id)
		elif task.attempt == null or task.attempt.worker_id != id: errors.append("Missing attempt identity: %d"%id)
		if not is_instance_valid(agent) or agent.current_task_id != int(_active[id]): errors.append("Executor disagrees with lease: %d"%id)
		if id in _idle_dwarves: errors.append("Working actor also idle: %d"%id)
	for task: Task in _tasks.values():
		if task.assigned_to >= 0 and int(_active.get(task.assigned_to,-1)) != task.id: errors.append("Orphan assigned lease: %d"%task.id)
	for source_id: int in _work_sources:
		var source: Object = _work_sources[source_id]
		if not is_instance_valid(source): continue
		for worker: int in SourceAdapter.claimed_workers(source):
			var task := get_task(int(_active.get(worker,-1)))
			if task == null or task.source_id!=source_id: errors.append("Orphan source claim: %d worker %d"%[source_id,worker])
	return errors
