extends "res://scripts/tests/FurnitureAssignmentTest.gd"

## Inject faults into the real source/worker path, without changing player saves.
func _run() -> void:
	create_timer(90).timeout.connect(func(): push_error("Job lifecycle timed out"); quit(1))
	await _setup_crafting_fixture()
	drops.restore_loose_item(CAMP_ITEM,Vector3(46.5,21,40.5),0,1,"",false,"base:material:pine")
	furniture.activate_for(CAMP,true)
	furniture._hover_cell = Vector3i(49,20,40)
	furniture._confirm_ghost()
	furniture.deactivate()
	var ghost = furniture._ghosts.values()[0]
	var lease: int = ghost._lease_id
	var order_key: String = tasks.get_task(lease).order_key
	for phase: int in [worker.TaskPhase.FETCH_PICKUP,worker.TaskPhase.FETCH_TO_GHOST,worker.TaskPhase.FETCH_DEPOSIT]:
		_expect(await _phase(phase),"reaches physical transfer phase %d"%phase)
		var task = tasks.get_task(lease)
		if task == null: break
		var generation: int = task.attempt.generation
		tasks.advance_supervision(.5)
		var last_progress: float = task.attempt.last_progress
		clock_node.set_paused(true)
		tasks.advance_supervision(50)
		_expect(task.attempt.last_progress==last_progress and task.assigned_to==worker.dwarf_id,"pause never times out an attempt")
		clock_node.set_paused(false)
		# Deliberately stop execution while the supervisor keeps simulating.
		for tick in range(28): tasks.advance_supervision(.5)
		_expect(worker.current_task_id<0 and task.status==Task.Status.PENDING,"stalled phase releases worker")
		_expect(_count(CAMP_ITEM)==1 and worker._carried_entries.is_empty(),"interruption preserves exactly one physical item")
		_expect(drops.get_inventory_items().loose.all(func(entry): return entry.node.get_meta("material_id","")=="base:material:pine"),"recovery preserves material identity")
		_expect(task.order_key==order_key,"retry keeps the player order identity")
		tasks.retry_order(order_key)
		for tick in range(80):
			tasks._run_scheduler()
			if worker.current_task_id==lease: break
			await process_frame
		_expect(task.attempt.generation!=generation,"retry uses a fresh attempt generation")
		var effects := [0]
		_expect(not tasks.commit_step(worker.dwarf_id,lease,generation,"stale",func(): effects[0]+=1),"old callback cannot mutate a new attempt")
		tasks.complete_dwarf_task(worker.dwarf_id,lease,generation)
		_expect(worker.current_task_id==lease and effects[0]==0,"old completion leaves current attempt intact")
		_expect(tasks.lifecycle_errors().is_empty(),"shared worker/lease contract holds after recovery")
	_expect(await _installed(CAMP),"recovered real placement completes")
	worker._work_execution._fetch_complete()
	_expect(furniture._installed.size()==1 and _count(CAMP_ITEM)==0,"duplicate completion cannot install or consume twice")
	# Repeated faults become actionable instead of endlessly recycling a worker.
	# Real work: a one-block mining lease beside the worker. Supervision runs
	# without frames, so the assigned executor makes no progress.
	var id: int = _post_mine_lease(worker.current_cell()+Vector3i(1,0,0))
	var stalled = tasks.get_task(id)
	_expect(stalled != null,"fixture posts a real mining lease")
	if stalled != null:
		for attempt in range(3):
			tasks._scheduler.assign(stalled,worker)
			tasks.advance_supervision(.5)
			for tick in range(28): tasks.advance_supervision(.5)
		_expect(stalled.recovery_paused,"three stalled attempts require attention")
		_expect(stalled.wait_reason.begins_with("Needs attention"),"repeated failure is explained")
		tasks.retry_order(stalled.order_key)
		_expect(not stalled.recovery_paused,"explicit retry revalidates rather than completing")
		# An event re-entering the same commit performs the effect once.
		tasks._scheduler.assign(stalled,worker)
		var calls := [0]
		var op := func():
			calls[0]+=1
			tasks.commit_step(worker.dwarf_id,id,stalled.attempt.generation,"unit",func(): calls[0]+=10)
			return true
		_expect(tasks.commit_step(worker.dwarf_id,id,stalled.attempt.generation,"unit",op),"first commit succeeds")
		_expect(not tasks.commit_step(worker.dwarf_id,id,stalled.attempt.generation,"unit",op) and calls[0]==1,"duplicate and reentrant effects are fenced")
	_clear_mine_leases()
	# A task with no work source has no executor: assignment fails it cleanly
	# instead of hanging the worker or recycling it through PENDING.
	id = tasks.add_task(Task.Type.MINE,worker.current_cell())
	tasks._scheduler.assign(tasks.get_task(id),worker)
	_expect(tasks.get_task(id)==null and worker.current_task_id<0 and worker._task_phase==worker.TaskPhase.NONE,"source-less task is refused, not worked")
	_expect(worker.dwarf_id in tasks._idle_dwarves and tasks.lifecycle_errors().is_empty(),"refused task leaves the worker idle and consistent")
	# Saved diagnostics are compact; source checkpoints continue to own work.
	var craft_id: int = crafting.queue_order(BENCH_RECIPE,1)
	var saved_craft: Dictionary = crafting.serialize_state()
	var saved_jobs: Dictionary = JSON.parse_string(JSON.stringify(tasks.serialize_state()))
	var source = crafting.get_order(craft_id)
	var locator: String = tasks._source_locators[source.source_id]
	var stable_key: String = tasks.journal.records[locator].key
	crafting.remove_order(craft_id)
	tasks.restore_state(saved_jobs)
	crafting.restore_state(saved_craft)
	source = crafting.get_order(craft_id)
	_expect(tasks.journal.records[tasks._source_locators[source.source_id]].key==stable_key,"source order identity survives JSON save/reload")
	for n in range(250): tasks.journal.transition(locator,"waiting",str(n))
	_expect(tasks.journal.history.size()==200,"transition history is bounded")
	var inspector = load("res://scripts/ui/JobInspectorPanel.gd").new()
	manager.register_window("jobs_test","Job inspector","",inspector,{"persistent":false,"default_pos":Vector2(220,110)})
	manager.open("jobs_test")
	inspector._selected = stable_key
	inspector.refresh()
	_expect(inspector._detail.text.contains(stable_key),"job inspector exposes real order diagnostics")
	if "--capture" in OS.get_cmdline_user_args():
		tasks.journal.history.clear()
		tasks.journal.transition(locator,"waiting","Waiting for matching pine timber")
		inspector.refresh()
		await _frames(3)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tmp/job_reliability_20261011/job_inspector.png")
	for failure: String in failures: push_error(failure)
	print("JOB_LIFECYCLE_OK" if failures.is_empty() else "JOB_LIFECYCLE_FAIL")
	quit(0 if failures.is_empty() else 1)

func _tick() -> void:
	tasks.advance_supervision(.05*clock_node.speed)
	await super._tick()
