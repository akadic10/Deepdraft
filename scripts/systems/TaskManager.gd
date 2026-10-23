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
## COMPONENTS: TaskScheduler (components/) runs the matching — the idle pass,
## buckets, specialised comparisons and the lease handoff; TaskSupervision
## observes attempts and recovers stalled ones. Both share this autoload's
## tables; the public API, signals and config stay here.
##
## JSON = what things are (budgets, priorities — data/tasks/task_config.json);
## GDScript = what things do (this loop).

signal task_added(task: Task)
@warning_ignore("unused_signal") # emitted by TaskScheduler
signal task_assigned(task: Task, dwarf_id: int)
signal task_released(task: Task, dwarf_id: int, reason: int)
signal task_completed(task: Task)
signal task_failed(task: Task, reason: String)
signal task_cancelled(task: Task)
signal task_unreachable(task: Task)

const CONFIG_PATH := "res://data/tasks/task_config.json"
const SourceAdapter = preload("res://scripts/components/WorkSourceAdapter.gd")
const Journal = preload("res://scripts/components/WorkJournal.gd")
const Scheduler = preload("res://scripts/components/TaskScheduler.gd")
const Supervision = preload("res://scripts/components/TaskSupervision.gd")
var journal := Journal.new()
var _source_locators: Dictionary = {}
var _planning_holds: Dictionary = {}

# ── Config (fallbacks mirror task_config.json) ───────────────────────────────
var _config_raw: Dictionary = {}          # full parsed task_config.json (see get_config_section)
## Scheduler limits live on the TaskScheduler; these forward to it.
var _budget_usec: int:
	get: return _scheduler.budget_usec
	set(value): _scheduler.budget_usec = value
var _max_probes_per_wake: int:
	get: return _scheduler.max_probes_per_wake
	set(value): _scheduler.max_probes_per_wake = value
var _probe_node_cap: int:
	get: return _scheduler.probe_node_cap
	set(value): _scheduler.probe_node_cap = value
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

## Matching and supervision (components/TaskScheduler.gd, TaskSupervision.gd).
var _scheduler: Scheduler
var _supervision: Supervision


func _init() -> void:
	var tables := {"tasks": _tasks, "pending": _pending, "active": _active, "idle_dwarves": _idle_dwarves,
		"agents": _agents, "work_sources": _work_sources, "planning_holds": _planning_holds,
		"source_locators": _source_locators}
	_scheduler = Scheduler.new(tables)
	_supervision = Supervision.new(_scheduler, tables)


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
	if agent.is_sleeping() or agent.is_eating() or agent.is_recreating(): return false
	var source := get_work_source(task.source_id) as FurnitureGhostComponent
	if source == null or source.has_committed_item(): return false
	var item: Node3D = offer.item
	if not is_instance_valid(item) or item.is_queued_for_deletion(): return false
	var keep := bool(offer.carried) and int(offer.count) == 1 and agent.detach_placement_cargo(item)
	cancel_task(old.id)
	if keep:
		source.fetched_instance_id = String(item.get_meta("instance_id", ""))
		source.notify_picked_up(agent.dwarf_id)
		_scheduler.assign(task, agent, item)
	else:
		source.ensure_claim()
	return true


## Cancels a task outright (player action / source destroyed). Assigned tasks
## are pulled from their dwarf, who returns to the idle pool.
func cancel_task(task_id: int) -> void:
	var task: Task = _tasks.get(task_id)
	if task == null:
		return
	if task.status == Task.Status.PENDING or task.status == Task.Status.BLOCKED:
		remove_pending(task)
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
	if not matches_attempt(dwarf_id,expected_task,generation): return
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
	if expected_task >= 0 and not matches_attempt(dwarf_id,expected_task,generation): return
	var task := _take_active(dwarf_id)
	if task == null:
		if requeue_dwarf:
			_mark_idle(dwarf_id)
		return
	task.status = Task.Status.PENDING
	task.assigned_to = -1
	task.planning_context.clear()
	_scheduler.forget_task(task.id)
	task.wait_reason = release_reason(reason)
	journal.transition(task.order_locator,"waiting",task.wait_reason,task.attempt.generation,dwarf_id)
	_insert_pending(task)
	# PATH_INVALID means the dwarf actually failed to path there (stronger
	# evidence than a capped probe) — back the task off so the scheduler does
	# not immediately re-assign the same dead end (doc 16 §2.7 step 2).
	if reason in [Task.ReleaseReason.PATH_INVALID,Task.ReleaseReason.NO_PROGRESS,Task.ReleaseReason.MATERIAL_UNAVAILABLE,Task.ReleaseReason.PLAN_CHANGED,Task.ReleaseReason.SEARCH_BUDGET_EXHAUSTED]:
		apply_backoff(task, Time.get_ticks_msec())
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
	if not matches_attempt(dwarf_id,expected_task,generation): return
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
	if is_instance_valid(agent) and (_active.has(dwarf_id) or agent.is_eating() or agent.is_recreating()): agent.abort_task()
	if _active.has(dwarf_id):
		release_dwarf_task(dwarf_id, Task.ReleaseReason.SOURCE_EMPTY, false)
	_agents.erase(dwarf_id)
	_remove_idle(dwarf_id)

## The registered, still valid dwarf with this id, or null.
func get_agent(dwarf_id: int) -> DwarfAgent:
	var agent = _agents.get(dwarf_id)
	return agent if is_instance_valid(agent) else null

## Every registered dwarf that is still valid, in registration order.
func get_agents() -> Array[DwarfAgent]:
	var out: Array[DwarfAgent] = []
	for agent in _agents.values():
		if is_instance_valid(agent): out.append(agent)
	return out

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
	_scheduler.reset()
	_supervision.reset()
	_source_locators.clear()
	_planning_holds.clear()
	var next_generation: int = journal.next_attempt
	journal = Journal.new()
	journal.next_attempt = next_generation
	_tasks.clear()
	_pending.clear()
	_active.clear()
	_idle_dwarves.clear()
	_agents.clear()
	_completed_log.clear()
	_work_sources.clear()
	_next_task_id = 1
	_next_source_id = 10_000_000
	_blocked_count = 0
	_wake_dirty = false
	_heartbeat_accum = 0.0


# ── Stats, scheduling and supervision (TaskScheduler / TaskSupervision) ──────

func get_scheduler_stats() -> Dictionary: return _scheduler.stats()
func _run_scheduler() -> void: _scheduler.run()
func advance_supervision(seconds: float) -> void: _supervision.advance(seconds)
func retry_order(order_key: String, reason: String = "Retry requested") -> void: _supervision.retry_order(order_key, reason)
func worker_availability(agent: DwarfAgent) -> String: return _supervision.worker_availability(agent)
func job_diagnostics() -> Array[Dictionary]: return _supervision.job_diagnostics()
## Read-only contract checks for fault tests and development diagnostics.
func lifecycle_errors() -> Array[String]: return _supervision.lifecycle_errors()


## Wake the scheduler on the next frame (used by the scheduler and supervision).
func request_wake() -> void:
	_wake_dirty = true


## Static priority of a task type from task_config.json (1 when unlisted).
func static_priority(type: int) -> int:
	return int(_static_priorities.get(Task.type_name(type), 1))


func backoff_max_seconds() -> float:
	return _backoff_max_s


## Exponential retry backoff; fires task_unreachable at the configured threshold.
func apply_backoff(task: Task, now: int) -> void:
	if task.wait_reason.is_empty() or task.wait_reason == "Waiting for assessment": task.wait_reason = "No proven route for eligible workers"
	journal.transition(task.order_locator,"waiting",task.wait_reason)
	task.blocked_count += 1
	var delay_s: float = minf(pow(_backoff_base_s, float(task.blocked_count)), _backoff_max_s)
	task.retry_at = now + int(delay_s * 1000.0)
	_blocked_count += 1
	if task.blocked_count == _unreachable_threshold:
		task_unreachable.emit(task)


func work_policy_changed() -> void:
	_scheduler.policy_changed()
	_wake_dirty = true


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


func remove_pending(task: Task) -> void:
	_scheduler.forget_pending(task)
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
		_scheduler.idle_version += 1


func _mark_idle(dwarf_id: int) -> void:
	var agent := get_agent(dwarf_id)
	if _active.has(dwarf_id) or agent == null or not agent.is_inside_tree(): return
	if agent.promotion_pending() or agent.is_sleeping() or agent.is_eating() or agent.is_recreating(): return
	if agent.needs_ladder_exit() or agent.needs_bridge_exit(): return
	if not _idle_dwarves.has(dwarf_id):
		if _idle_dwarves.is_empty(): _scheduler.next_type = -1
		_idle_dwarves.append(dwarf_id)
		_scheduler.idle_version += 1
	_wake_dirty = true


func _log_completed(task: Task) -> void:
	_scheduler.forget_rejections(task.id)
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
	_scheduler.clear_matches()
	for task: Task in _tasks.values():
		if task.status in [Task.Status.PENDING, Task.Status.BLOCKED]: task.retry_at = 0
	_wake_dirty = true

func _on_chunk_dirtied(cx: int, cy: int, cz: int) -> void:
	var chunk := Vector3i(cx,cy,cz)
	_scheduler.chunk_dirtied(chunk)
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
	var parsed: Variant = preload("res://scripts/registries/JsonData.gd").read(CONFIG_PATH)
	if parsed == null: return # reported; the built-in defaults stay
	var d: Dictionary = parsed
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
func matches_attempt(dwarf_id: int, expected_task: int, generation: int) -> bool:
	var task := get_task(int(_active.get(dwarf_id,-1)))
	return task != null and (expected_task < 0 or task.id == expected_task) \
		and (generation < 0 or (task.attempt != null and task.attempt.generation == generation))

func commit_step(dwarf_id: int, task_id: int, generation: int, unit: String, operation: Callable) -> bool:
	if not matches_attempt(dwarf_id,task_id,generation) or not operation.is_valid(): return false
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

## No-progress grace for attempt supervision and the initial assignment sample.
func progress_grace() -> float:
	return float(get_config_section("supervision").get("no_progress_seconds",12.0))

func save_section_key() -> String: return "jobs"
func save_restore_priority() -> int: return 5
func serialize_state() -> Dictionary: return journal.serialize(_source_locators.values())
func restore_state(saved: Dictionary) -> void: journal.restore(saved)

func hold_for_planning(agent: DwarfAgent) -> void:
	if not is_instance_valid(agent) or agent.current_task_id >= 0: return
	if agent.is_walking() and (agent.get_idle_behavior() == null or not agent.get_idle_behavior().owns_walk()): return
	var hold: Dictionary = _planning_holds.get(agent.dwarf_id,{})
	if not hold.is_empty() and journal.now < float(hold.until)+2.0: return
	var duration := float(get_config_section("supervision").get("planning_hold_seconds",4.0))
	_planning_holds[agent.dwarf_id] = {"until":journal.now+duration}
	# Planning needs a stable position, not a fresh idle delay. Restarting a
	# stationary dwarf's delay on every hold can prevent any leisure between
	# unsuccessful checks, and unnecessarily makes seated dwarves stand up.
	# receive_task() cancels all leisure when work is actually assigned.
	if agent.get_idle_behavior() != null and agent.get_idle_behavior().owns_walk() and agent.get_idle_behavior().state != "leaving_room":
		agent.get_idle_behavior().cancel()

func planning_held(dwarf_id: int) -> bool:
	return journal.now < float(_planning_holds.get(dwarf_id,{}).get("until",-1.0))
