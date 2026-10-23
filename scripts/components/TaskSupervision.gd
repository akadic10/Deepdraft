extends RefCounted

## Attempt supervision for TaskManager (doc 16 §2.8): progress sampling and
## no-progress recovery, worker reconciliation, operator retries and the
## read-only job diagnostics and lifecycle checks. Shares TaskManager's tables
## (the same objects) and asks the scheduler about rejected workers.

const SourceAdapter = preload("res://scripts/components/WorkSourceAdapter.gd")
const Scheduler = preload("res://scripts/components/TaskScheduler.gd")

var scheduler: Scheduler
var _tasks: Dictionary
var _active: Dictionary
var _idle_dwarves: Array[int]
var _agents: Dictionary
var _work_sources: Dictionary
var _source_locators: Dictionary
var _supervision_cursor := 0
var _supervision_accum := 0.0
var _reconcile_cursor := 0


func _init(p_scheduler: Scheduler = null, tables: Dictionary = {}) -> void:
	scheduler = p_scheduler
	if tables.is_empty(): return
	_tasks = tables.tasks
	_active = tables.active
	_idle_dwarves = tables.idle_dwarves
	_agents = tables.agents
	_work_sources = tables.work_sources
	_source_locators = tables.source_locators


func reset() -> void:
	_supervision_cursor = 0
	_supervision_accum = 0.0
	_reconcile_cursor = 0


func advance(seconds: float) -> void:
	if WorldClock.paused or SaveManager.is_loading(): return
	TaskManager.journal.now += maxf(0.0,seconds)
	_supervision_accum += maxf(0.0,seconds)
	if _supervision_accum < float(TaskManager.get_config_section("supervision").get("interval_seconds",.5)): return
	_supervision_accum = 0.0
	_reconcile_workers()
	var ids := _active.keys()
	if ids.is_empty(): return
	var deadline := Time.get_ticks_usec()+int(TaskManager.get_config_section("supervision").get("budget_usec",500))
	var count := mini(ids.size(),int(TaskManager.get_config_section("supervision").get("attempts_per_pass",8)))
	for unused in range(count):
		var id: int = ids[_supervision_cursor % ids.size()]
		_supervision_cursor += 1
		var task := TaskManager.get_task(int(_active.get(id,-1)))
		if task == null or task.attempt == null: continue
		var agent: DwarfAgent = _agents.get(id)
		if not is_instance_valid(agent) or agent.current_task_id != task.id:
			_recover_attempt(task,"Worker and assignment disagree")
		elif task.source_id >= 0 and not is_instance_valid(TaskManager.get_work_source(task.source_id)):
			agent.abort_task()
			TaskManager.fail_dwarf_task(id,"Work source removed",task.id,task.attempt.generation)
		else:
			task.attempt.observe(agent.work_sample(),TaskManager.journal.now,TaskManager.progress_grace())
			if task.attempt.stalled(TaskManager.journal.now,TaskManager.progress_grace()):
				_recover_attempt(task,"No progress during %s" % task.attempt.step)
			else:
				task.status = Task.Status.IN_PROGRESS
				TaskManager.journal.transition(task.order_locator,"running",task.attempt.step,task.attempt.generation,id)
		if Time.get_ticks_usec() >= deadline: break

func _recover_attempt(task: Task, reason: String) -> void:
	var id := task.assigned_to
	var generation: int = task.attempt.generation
	var agent: DwarfAgent = _agents.get(id)
	if is_instance_valid(agent): agent.abort_task()
	TaskManager.journal.transition(task.order_locator,"recovering",reason,generation,id)
	var record: Dictionary = TaskManager.journal.records.get(task.order_locator,{})
	record["failures"] = int(record.get("failures",0))+1
	TaskManager.release_dwarf_task(id,Task.ReleaseReason.NO_PROGRESS,true,task.id,generation)
	if int(record.failures) >= int(TaskManager.get_config_section("supervision").get("recovery_limit",3)):
		task.recovery_paused = true
		task.wait_reason = "Needs attention: repeated %s" % reason.to_lower()
		TaskManager.journal.transition(task.order_locator,"attention",task.wait_reason,generation,id)

func retry_order(order_key: String, reason: String = "Retry requested") -> void:
	for task: Task in _tasks.values():
		if task.order_key != order_key or task.assigned_to >= 0: continue
		task.recovery_paused = false
		task.retry_at = 0
		task.blocked_count = 0
		task.wait_reason = reason
		task.planning_context.clear()
		scheduler.forget_task(task.id)
		if TaskManager.journal.records.has(task.order_locator): TaskManager.journal.records[task.order_locator].failures = 0
		TaskManager.journal.transition(task.order_locator,"ready",task.wait_reason)
	TaskManager.request_wake()

func worker_availability(agent: DwarfAgent) -> String:
	if not is_instance_valid(agent): return "Unavailable"
	if agent.is_sleeping() or agent.is_eating() or agent.is_recreating() or agent.promotion_pending(): return "Self-care"
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
		var record: Dictionary = TaskManager.journal.records.get(locator,{})
		if record.is_empty(): continue
		var row := record.duplicate(true)
		row["attempts"] = []
		row["rejections"] = 0
		var pending := false
		for task: Task in _tasks.values():
			if task.order_locator != locator: continue
			row.rejections += scheduler.rejection_count(task.id)
			if task.assigned_to >= 0 and task.attempt != null: row.attempts.append(task.attempt.describe(TaskManager.journal.now))
			else:
				pending = true
				row.reason = task.wait_reason
				var eligible := _idle_dwarves.any(func(id: int): return is_instance_valid(_agents.get(id)) and task.type in scheduler.types_for(_agents[id]))
				if not eligible and not task.recovery_paused: row.reason = "No eligible available worker"
				row.state = "attention" if task.recovery_paused else "waiting"
		if not row.attempts.is_empty(): row.state = "running"
		elif not pending:
			row.state = "waiting"
			row.reason = SourceAdapter.waiting_reason(TaskManager.get_work_source(source_id))
		row["history"] = TaskManager.journal.history.filter(func(event: Dictionary): return event.order == row.key).slice(-12)
		result.append(row)
	result.sort_custom(func(a: Dictionary,b: Dictionary): return a.key.naturalnocasecmp_to(b.key)<0)
	return result

## Missed availability notifications cannot permanently lose a registered
## worker. This inspects a bounded subset, never scans world objects.
func _reconcile_workers() -> void:
	var ids := _agents.keys()
	for unused in range(mini(ids.size(),4)):
		var id: int = ids[_reconcile_cursor%ids.size()]
		_reconcile_cursor += 1
		var agent: DwarfAgent = _agents.get(id)
		if not is_instance_valid(agent):
			TaskManager.deregister_dwarf(id)
			continue
		if _active.has(id):
			TaskManager.notify_dwarf_unavailable(id)
			continue
		if agent.current_task_id >= 0:
			# An orphan executor must relinquish its real cargo before rejoining.
			agent.abort_task()
		if agent.is_sleeping() or agent.is_eating() or agent.is_recreating() or agent.promotion_pending() or agent.needs_bridge_exit() or agent.needs_ladder_exit():
			TaskManager.notify_dwarf_unavailable(id)
		elif not id in _idle_dwarves:
			TaskManager.notify_dwarf_idle(id)

## Read-only contract checks for fault tests and development diagnostics.
func lifecycle_errors() -> Array[String]:
	var errors: Array[String] = []
	for id: int in _active:
		var task := TaskManager.get_task(int(_active[id]))
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
			var task := TaskManager.get_task(int(_active.get(worker,-1)))
			if task == null or task.source_id!=source_id: errors.append("Orphan source claim: %d worker %d"%[source_id,worker])
	return errors
