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

# ── Config (fallbacks mirror task_config.json) ───────────────────────────────
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
	WorldData.chunk_dirtied.connect(_on_chunk_dirtied, CONNECT_DEFERRED)
	print("TaskManager: ready (budget %d us, %d probes/wake, heartbeat %.2f s)." % [
		_budget_usec, _max_probes_per_wake, _heartbeat_s])


func _process(delta: float) -> void:
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
	_insert_pending(task)
	task_added.emit(task)
	_wake_dirty = true
	return task.id


func get_task(task_id: int) -> Task:
	return _tasks.get(task_id)


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
	task.assigned_to = -1
	_tasks.erase(task_id)
	task_cancelled.emit(task)


## The dwarf finished its task. Logs it, frees the dwarf back into the pool.
func complete_dwarf_task(dwarf_id: int) -> void:
	var task := _take_active(dwarf_id)
	if task == null:
		return
	task.status = Task.Status.COMPLETED
	_log_completed(task)
	_tasks.erase(task.id)
	task_completed.emit(task)
	_mark_idle(dwarf_id)


## The RELEASE protocol (doc 16 §2.8): the task returns to PENDING intact;
## reservations are the source's to free on the task_released signal.
## requeue_dwarf=false when the dwarf is heading into an interrupt behaviour
## (sleep, combat) and will report idle later.
func release_dwarf_task(dwarf_id: int, reason: int, requeue_dwarf: bool = true) -> void:
	var task := _take_active(dwarf_id)
	if task == null:
		if requeue_dwarf:
			_mark_idle(dwarf_id)
		return
	task.status = Task.Status.PENDING
	task.assigned_to = -1
	_insert_pending(task)
	# PATH_INVALID means the dwarf actually failed to path there (stronger
	# evidence than a capped probe) — back the task off so the scheduler does
	# not immediately re-assign the same dead end (doc 16 §2.7 step 2).
	if reason == Task.ReleaseReason.PATH_INVALID:
		_apply_backoff(task, Time.get_ticks_msec())
	task_released.emit(task, dwarf_id, reason)
	if requeue_dwarf:
		_mark_idle(dwarf_id)
	_wake_dirty = true


## Permanent failure (target gone, invalid state). Task is removed, not retried.
func fail_dwarf_task(dwarf_id: int, reason: String) -> void:
	var task := _take_active(dwarf_id)
	if task == null:
		return
	task.status = Task.Status.FAILED
	_tasks.erase(task.id)
	task_failed.emit(task, reason)
	_mark_idle(dwarf_id)


# ── Public API — work sources (doc 16 §2.7) ──────────────────────────────────

func register_work_source(source_id: int, source: Object) -> void:
	_work_sources[source_id] = source


func unregister_work_source(source_id: int) -> void:
	_work_sources.erase(source_id)


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
	if _active.has(dwarf_id):
		release_dwarf_task(dwarf_id, Task.ReleaseReason.SOURCE_EMPTY, false)
	_agents.erase(dwarf_id)
	_idle_dwarves.erase(dwarf_id)


## A dwarf finished an interrupt behaviour and is available again.
func notify_dwarf_idle(dwarf_id: int) -> void:
	_mark_idle(dwarf_id)


## A dwarf entered an interrupt behaviour (sleep, combat) while holding NO
## task — it must leave the idle pool so the scheduler cannot assign to it
## until notify_dwarf_idle (doc 16 §2.8: a dwarf enters _idle_dwarves only
## after its interrupt behaviour resolves). Dwarves holding a task use
## release_dwarf_task(..., requeue_dwarf = false) instead.
func notify_dwarf_unavailable(dwarf_id: int) -> void:
	_idle_dwarves.erase(dwarf_id)


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

	# Iterate a snapshot of the idle pool; dwarves that get work are removed
	# from the live list inside _try_assign.
	var idle_snapshot := _idle_dwarves.duplicate()
	for dwarf_id in idle_snapshot:
		if Time.get_ticks_usec() - t_start >= _budget_usec or probes_left <= 0:
			_wake_dirty = true   # resume next frame from the cursors
			break
		var agent: DwarfAgent = _agents.get(dwarf_id)
		if agent == null or not is_instance_valid(agent):
			_idle_dwarves.erase(dwarf_id)
			_agents.erase(dwarf_id)
			continue
		probes_left = _try_assign(agent, bonus, probes_left, t_start)

	var wake_usec := int(Time.get_ticks_usec() - t_start)
	if wake_usec > _worst_wake_usec:
		_worst_wake_usec = wake_usec


## Scans this dwarf's compatible type buckets in bonus-adjusted priority order.
## Returns the remaining probe allowance.
func _try_assign(agent: DwarfAgent, bonus: Dictionary, probes_left: int, t_start: int) -> int:
	var types := _types_for(agent)
	types.sort_custom(func(a: int, b: int) -> bool:
		return _bucket_priority(a, bonus) > _bucket_priority(b, bonus))

	var now := Time.get_ticks_msec()
	var dwarf_cell := agent.current_cell()

	for type in types:
		var ids: Array = _pending.get(type, [])
		if ids.is_empty():
			continue
		var cursor := int(_scan_cursor.get(type, 0))
		var scanned := 0
		while scanned < ids.size():
			if Time.get_ticks_usec() - t_start >= _budget_usec or probes_left <= 0:
				_scan_cursor[type] = cursor
				return 0
			var idx := (cursor + scanned) % ids.size()
			scanned += 1
			var task: Task = _tasks.get(ids[idx])
			if task == null or not task.is_available(now):
				continue
			probes_left -= 1
			_probes_total += 1
			# Dwarf-relative probe target for zone leases (Alen, 2026-06-26): the
			# lease's static target_pos is one top-of-zone cell that can be
			# unreachable even when this dwarf could mine lower faces via reach-up.
			# Probe the workable stand cell nearest THIS dwarf instead.
			var probe_target := task.target_pos
			if task.type == Task.Type.MINE and task.source_id != -1:
				var src: Object = _work_sources.get(task.source_id)
				if src != null and src.has_method("nearest_stand_target"):
					var t: Vector3i = src.nearest_stand_target(dwarf_cell)
					if t.x >= 0:
						probe_target = t
			if NavGrid.probe_reachable(dwarf_cell, probe_target, _probe_node_cap):
				task.blocked_count = 0
				_assign(task, agent)
				_scan_cursor[type] = (cursor + scanned) % maxi(ids.size(), 1)
				return probes_left
			_apply_backoff(task, now)
		_scan_cursor[type] = 0
	return probes_left


func _assign(task: Task, agent: DwarfAgent) -> void:
	_remove_pending(task)
	task.status = Task.Status.ASSIGNED
	task.assigned_to = agent.dwarf_id
	_active[agent.dwarf_id] = task.id
	_idle_dwarves.erase(agent.dwarf_id)
	agent.receive_task(task.id, task.target_pos)
	task_assigned.emit(task, agent.dwarf_id)


func _apply_backoff(task: Task, now: int) -> void:
	task.blocked_count += 1
	var delay_s: float = minf(pow(_backoff_base_s, float(task.blocked_count)), _backoff_max_s)
	task.retry_at = now + int(delay_s * 1000.0)
	_blocked_count += 1
	if task.blocked_count == _unreachable_threshold:
		task_unreachable.emit(task)


## Compatible task types for a dwarf. v1: every dwarf takes any economic type
## (doc 31: off-profession work runs at x0.7 speed — applied at execution in
## step 6). Profession-gated types (FORGE etc., doc 44) refine this later.
func _types_for(_agent: DwarfAgent) -> Array[int]:
	return [Task.Type.MINE, Task.Type.HAUL, Task.Type.BUILD, Task.Type.FARM, Task.Type.BREW]


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


func _mark_idle(dwarf_id: int) -> void:
	if not _agents.has(dwarf_id):
		return
	if not _idle_dwarves.has(dwarf_id):
		_idle_dwarves.append(dwarf_id)
	_wake_dirty = true


func _log_completed(task: Task) -> void:
	_completed_log.append({
		"id": task.id, "type": Task.type_name(task.type),
		"target": task.target_pos, "at_msec": Time.get_ticks_msec(),
	})
	if _completed_log.size() > 200:
		_completed_log.pop_front()


# ── Early re-arm: terrain changed near a blocked target (doc 16 §2.4) ────────

func _on_chunk_dirtied(cx: int, cy: int, cz: int) -> void:
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
	var s: Dictionary = d.get("scheduler", {})
	_budget_usec = int(s.get("scheduler_budget_usec", _budget_usec))
	_max_probes_per_wake = int(s.get("max_probes_per_wake", _max_probes_per_wake))
	_probe_node_cap = int(s.get("probe_node_cap", _probe_node_cap))
	_heartbeat_s = float(s.get("heartbeat_interval_s", _heartbeat_s))
	_backoff_base_s = float(s.get("backoff_base_s", _backoff_base_s))
	_backoff_max_s = float(s.get("backoff_max_s", _backoff_max_s))
	_unreachable_threshold = int(s.get("unreachable_signal_threshold", _unreachable_threshold))
	_static_priorities = d.get("static_priorities", {})
