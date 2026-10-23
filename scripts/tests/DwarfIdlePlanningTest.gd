extends "res://scripts/tests/DwarfIdleBehaviorTest.gd"

## A pending job can be checked repeatedly without ever giving this dwarf an
## assignment. Planning must not restart the idle delay on every failed pass.
func _run() -> void:
	create_timer(80).timeout.connect(func(): push_error("Idle planning timed out"); quit(1))
	await _setup_crafting_fixture()
	worker._food.value=1.0
	worker.sleep=1.0
	var start: Vector3=worker.position
	var furthest:=0.0
	var held_frames:=0
	for i in 400:
		tasks.advance_supervision(.1)
		tasks.hold_for_planning(worker)
		if tasks.planning_held(worker.dwarf_id): held_frames+=1
		worker._process(.1)
		furthest=maxf(furthest,worker.position.distance_to(start))
		if i%20==0: await process_frame
	_expect(held_frames>200,"fixture repeatedly checks pending work using real planning holds")
	_expect(furthest>1.0,"unproductive job checks leave enough idle progress to stroll")
	_expect(worker.dwarf_id in tasks._idle_dwarves and worker.current_task_id<0,"leisure remains available for a real assignment")
	# An actual assignment still owns movement and immediately interrupts leisure.
	var job: int=_post_mine_lease(worker.current_cell()+Vector3i(2,0,0))
	for i in 80:
		tasks._run_scheduler()
		if worker.current_task_id==job: break
		await process_frame
	_expect(worker.current_task_id==job and not worker._idle_behavior.active(),"reachable work interrupts the resumed leisure")
	_clear_mine_leases()
	# A seated dwarf's position is already stable. Merely considering work
	# must not repeatedly stand them up before any assignment exists.
	_reset_at(worker,Vector3i(44,20,44))
	tasks._planning_holds.clear()
	_configure(worker)
	worker._idle_behavior.config.seat_chance=1.0
	furniture._install(CHAIR,furniture.get_defs()[CHAIR],Vector3i(47,20,44),0)
	var chair=furniture._installed.values()[0]
	_expect(await _seat_phase(worker,"sitting"),"fixture reaches a free chair")
	worker._process(1)
	var pose: Vector3=worker._body.position
	tasks.hold_for_planning(worker)
	_expect(worker._idle_behavior.state=="sitting" and chair.idle_seat_owner==worker.dwarf_id and worker._body.position==pose,"read-only planning preserves an already stationary seated dwarf")
	chair.set_uninstall(true)
	worker._process(.1)
	_expect(chair.idle_seat_owner<0 and not worker._idle_behavior.active(),"planning cannot retain a chair that becomes unavailable")
	chair.set_uninstall(false)
	tasks._planning_holds.clear()
	_expect(await _seat_phase(worker,"sitting"),"released chair can be reused")
	tasks.hold_for_planning(worker)
	job=_post_mine_lease(Vector3i(44,20,42))
	for i in 80:
		tasks._run_scheduler()
		if worker.current_task_id==job: break
		await process_frame
	_expect(worker.current_task_id==job and chair.idle_seat_owner<0,"a real assignment releases the retained chair")
	_expect(tasks.lifecycle_errors().is_empty(),"planning and leisure keep consistent worker ownership")
	_clear_mine_leases()
	print("IDLE_PLANNING_DISTANCE ",furthest)
	for failure: String in failures: push_error(failure)
	print("DWARF_IDLE_PLANNING_OK" if failures.is_empty() else "DWARF_IDLE_PLANNING_FAIL")
	quit(0 if failures.is_empty() else 1)
