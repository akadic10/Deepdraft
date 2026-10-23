extends RefCounted

## One family of work sources owned by a system (doc 258 step 6): the owner's
## key (route id, tree id, detail id, ghost id...) <-> live source, its
## TaskManager registration, and task-event routing. Plain helper, no autoload.
##
## Sources implement the routing contract:
##   work_task_gone(task: Task, dwarf_id: int)      completed (-1) / cancelled / failed
##   work_task_released(task: Task, dwarf_id: int)  returned to PENDING; never re-post
##   work_source_retired()                          free source-held claims
## Release is never routed as "gone": a released lease stays pending, so a
## source that re-posted on release would duplicate the job (Hard Rule 12).
## Retire forgets the source BEFORE cancelling its tasks, so cancellation
## events cannot re-post a lease for a source that is going away.
## Nothing here is saved: owners save their own records and rebuild sources on
## restore; TaskManager's journal keys come from WorkSourceAdapter.locator().

## Owner key -> source. Read freely; change only through add() and retire().
var sources: Dictionary = {}
## Optional owner hook, called after the source handled a gone task: (key, task).
var on_gone: Callable
var _keys: Dictionary = {} # source id -> owner key


func _init() -> void:
	TaskManager.task_completed.connect(_on_completed)
	TaskManager.task_cancelled.connect(_on_cancelled)
	TaskManager.task_failed.connect(_on_failed)
	TaskManager.task_released.connect(_on_released)


## Gives the source a fresh source id and registers it. Set every field the
## work-journal locator reads (ids, origin, task_type) before calling.
func add(key: Variant, source: Object) -> int:
	if sources.has(key):
		push_error("WorkSourceTable: %s already has a source; retiring it." % str(key))
		retire(key, true)
	var source_id := TaskManager.allocate_source_id()
	source.set("source_id", source_id)
	sources[key] = source
	_keys[source_id] = key
	TaskManager.register_work_source(source_id, source)
	return source_id


func get_source(key: Variant) -> Object:
	return sources.get(key)


func has(key: Variant) -> bool:
	return sources.has(key)


func keys() -> Array:
	return sources.keys()


func size() -> int:
	return sources.size()


## The owner key for a task's source id, or null.
func key_for(source_id: int) -> Variant:
	return _keys.get(source_id)


## Stops the source. cancel_tasks is false when the finishing worker's own
## lease completes normally. Returns the retired source, or null.
func retire(key: Variant, cancel_tasks: bool) -> Object:
	var source: Object = sources.get(key)
	if source == null:
		return null
	var source_id := int(source.get("source_id"))
	sources.erase(key)
	_keys.erase(source_id)
	if cancel_tasks:
		TaskManager.cancel_source_tasks(source_id)
	TaskManager.unregister_work_source(source_id)
	source.work_source_retired()
	return source


func retire_all(cancel_tasks := true) -> void:
	for key: Variant in sources.keys():
		retire(key, cancel_tasks)


func _on_completed(task: Task) -> void:
	_gone(task, -1)


func _on_cancelled(task: Task) -> void:
	_gone(task, task.assigned_to)


func _on_failed(task: Task, _reason: String) -> void:
	_gone(task, task.assigned_to)


func _gone(task: Task, dwarf_id: int) -> void:
	if not _keys.has(task.source_id):
		return
	var key: Variant = _keys[task.source_id]
	sources[key].work_task_gone(task, dwarf_id)
	if on_gone.is_valid():
		on_gone.call(key, task)


func _on_released(task: Task, dwarf_id: int, _reason: int) -> void:
	if not _keys.has(task.source_id):
		return
	sources[_keys[task.source_id]].work_task_released(task, dwarf_id)
