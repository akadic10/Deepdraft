extends "res://scripts/tests/ShrubPilotTest.gd"

## Multiple real workers reproduce the idle-queue regression at a real shrub.
var _workers: Array[Node3D] = []


class SlowQuote extends RefCounted:
	var source: RefCounted
	func stand_cells(from: Vector3i) -> Array[Vector3i]:
		var cells: Array[Vector3i] = source.stand_cells(from)
		# Force a yield after one worker's read-only quote, independent of CPU.
		OS.delay_usec(2000)
		return cells


func _run() -> void:
	create_timer(90).timeout.connect(func(): push_error("Surface work selection timed out"); quit(1))
	for name in ["SaveManager", "RoomManager", "StockpileManager", "WorldClock", "TaskManager"]:
		root.get_node(name).set_process(false)
	clock_node = root.get_node("WorldClock")
	tasks = root.get_node("TaskManager")
	world = root.get_node("WorldData")
	blocks = root.get_node("BlockRegistry")
	_build_floor()
	scene = Node3D.new()
	root.add_child(scene)
	current_scene = scene
	_season("summer")
	for action: String in ["uproot", "harvest_plants", "clear_shrubs"]:
		_fresh()
		var far = _add_worker(201, Vector3i(55,20,40))
		var near = _add_worker(202, Vector3i(40,20,40))
		var source = _designate(action)
		var lease: int = source.lease_id
		await _dispatch()
		_expect(near.current_task_id == lease and far.current_task_id < 0,
			"%s: dwarf standing on shrub wins over older distant idle worker" % action)
		if near.current_task_id == lease:
			for i in range(100):
				near._process(.05)
				if near._task_phase == near.TaskPhase.FELL_WORKING: break
			_expect(near._task_phase == near.TaskPhase.FELL_WORKING,
				"%s: chosen worker reaches a valid adjacent work cell" % action)
			for i in range(80):
				near._process(.1)
				if near.current_task_id < 0: break
			_expect(near.current_task_id < 0 and tasks.get_task(lease) == null,
				"%s: nearby worker completes the real source lease" % action)
			if action == "uproot":
				_expect(details._changes[BLUE].packed, "completed uprooting preserves the whole shrub")
			elif action == "harvest_plants":
				_expect(_berry_count("blueberry") == 3, "near worker harvest yields one crop")
			else:
				_expect(_cutting_count("blueberry_cutting") == 1, "near worker clearing yields one cutting")
	await _eligibility_and_priority()
	await _blocked_workers_and_sides()
	await _resumable_comparison()
	await _other_surface_jobs()
	for message: String in failures: push_error(message)
	print("SURFACE_WORK_SELECTION_OK" if failures.is_empty() else "SURFACE_WORK_SELECTION_FAIL: %s" % str(failures))
	quit(0 if failures.is_empty() else 1)


func _fresh() -> void:
	for agent in _workers: agent.abort_task()
	if is_instance_valid(details): details.free()
	for agent in _workers: agent.free()
	_workers.clear()
	tasks.reset_runtime_state()
	tasks._budget_usec = 1000
	tasks._max_probes_per_wake = 8
	if is_instance_valid(drops): drops.free()
	drops = load("res://scripts/systems/ItemDropManager.gd").new()
	scene.add_child(drops)
	details = load("res://scripts/systems/SurfaceDetailManager.gd").new()
	scene.add_child(details)
	details.set_process(false)
	details._initialized = true
	details.register_record({"id": BLUE, "definition": "base:flora:blueberry_bush",
		"origin": Vector3i(40,20,40), "variant": 0, "yaw": 0})


func _add_worker(id: int, cell: Vector3i):
	var factory = load("res://scripts/entities/DwarfFactory.gd").new()
	var agent = factory.spawn(factory.generate(id, {}), id)
	scene.add_child(agent)
	agent.position = Vector3(cell) + Vector3(.5,1,.5)
	agent.set_process(false)
	agent.sleep = 1.0
	tasks.register_dwarf(agent)
	_workers.append(agent)
	return agent


func _designate(action := "uproot"):
	if action == "uproot":
		_expect(details.designate_uproot(BLUE), "uproot designation accepted")
	else:
		_expect(details.designate_detail(BLUE, action), "%s designation accepted" % action)
	return details._sources[BLUE]


func _dispatch(wakes := 30) -> void:
	for i in range(wakes):
		var before: int = tasks._probes_total
		tasks._run_scheduler()
		_expect(tasks._probes_total - before <= tasks._max_probes_per_wake, "per-wake probe cap is respected")
		await process_frame


func _eligibility_and_priority() -> void:
	_fresh()
	var far = _add_worker(201, Vector3i(55,20,40))
	var near = _add_worker(202, Vector3i(40,20,40))
	near.dev_make_tired()
	near._process(.1)
	var source = _designate()
	await _dispatch()
	_expect(near.is_sleeping() and near.current_task_id < 0 and far.current_task_id == source.lease_id,
		"nearby sleeping dwarf is ineligible")
	_fresh()
	near = _add_worker(202, Vector3i(40,20,40))
	far = _add_worker(201, Vector3i(55,20,40))
	var old_priority: int = tasks._static_priorities.BUILD
	tasks._static_priorities.BUILD = 60
	var urgent: int = tasks.add_task(Task.Type.BUILD, Vector3i(42,20,40))
	source = _designate()
	await _dispatch()
	_expect(near.current_task_id == urgent and far.current_task_id == source.lease_id,
		"higher-priority work is considered before proximity; busy worker is not stolen")
	tasks._static_priorities.BUILD = old_priority
	_fresh()
	far = _add_worker(201, Vector3i(55,20,40))
	source = _designate()
	await _dispatch()
	near = _add_worker(202, Vector3i(40,20,40))
	await _dispatch()
	_expect(far.current_task_id == source.lease_id and near.current_task_id < 0,
		"later arrival does not steal already assigned work")
	_fresh()
	var first = _add_worker(201, Vector3i(38,20,40))
	var second = _add_worker(202, Vector3i(42,20,40))
	source = _designate()
	await _dispatch()
	_expect(first.current_task_id == source.lease_id and second.current_task_id < 0,
		"equal-distance workers keep stable idle-order tie breaking")


func _walls(columns: Array[Vector2i], build: bool) -> void:
	var block: int = blocks.get_id("base:terrain:rock:rock01") if build else blocks.AIR_ID
	for column in columns:
		for y in range(21,25): world.set_block(column.x,y,column.y,block)
	await process_frame
	await process_frame


func _blocked_workers_and_sides() -> void:
	_fresh()
	var far = _add_worker(201, Vector3i(48,20,40))
	var near = _add_worker(202, Vector3i(40,20,37))
	var columns: Array[Vector2i] = [Vector2i(39,37), Vector2i(41,37), Vector2i(40,36), Vector2i(40,38)]
	await _walls(columns, true)
	var source = _designate()
	tasks._max_probes_per_wake = 1
	await _dispatch()
	_expect(near.current_task_id < 0 and far.current_task_id == source.lease_id,
		"blocked nearest worker does not back off a job reachable by another worker")
	_expect(tasks.get_task(source.lease_id).blocked_count == 0, "successful alternative never incurs task backoff")
	await _walls(columns, false)
	_fresh()
	near = _add_worker(202, Vector3i(37,20,40))
	far = _add_worker(201, Vector3i(52,20,40))
	# Enclose the closest stand but leave other sides accessible.
	columns = [Vector2i(38,40), Vector2i(39,39), Vector2i(39,41), Vector2i(40,40)]
	await _walls(columns, true)
	# The solid center naturally displaces the shrub. Use its real adjacent
	# work component directly to isolate routing around a blocking footprint.
	source = load("res://scripts/components/TreeFellingComponent.gd").new()
	source.origin = Vector3i(40,20,40)
	source.state = {"designated": true}
	source.source_id = tasks.allocate_source_id()
	tasks.register_work_source(source.source_id, source)
	source.ensure_lease()
	tasks._max_probes_per_wake = 1
	await _dispatch()
	_expect(near.current_task_id == source.lease_id and far.current_task_id < 0,
		"blocked closest side does not hide the near worker's reachable alternatives")
	_expect(source._probed_stand != Vector3i(39,20,40), "executor receives the reachable side found by the scheduler")
	await _walls(columns, false)
	_fresh()
	near = _add_worker(202, Vector3i(40,20,37))
	columns = [Vector2i(39,37), Vector2i(41,37), Vector2i(40,36), Vector2i(40,38)]
	await _walls(columns, true)
	source = _designate()
	tasks._max_probes_per_wake = 1
	await _dispatch(8)
	_expect(near.current_task_id < 0 and tasks.get_task(source.lease_id).blocked_count == 1,
		"fully unreachable task backs off once after trying every work side")
	await _walls(columns, false)
	await _dispatch()
	_expect(near.current_task_id == source.lease_id, "terrain opening rearms the blocked task")


func _resumable_comparison() -> void:
	_fresh()
	var far = _add_worker(201, Vector3i(55,20,40))
	var source = _designate()
	var slow := SlowQuote.new()
	slow.source = source
	tasks.register_work_source(source.source_id, slow)
	tasks._run_scheduler()
	_expect(not tasks._surface_match.is_empty() and not bool(tasks._surface_match.ranked)
		and source.reserved_by < 0 and far.current_task_id < 0,
		"budget yield preserves ranking without reserving source work")
	tasks.register_work_source(source.source_id, source)
	var near = _add_worker(202, Vector3i(40,20,40))
	await _dispatch()
	_expect(near.current_task_id == source.lease_id and far.current_task_id < 0,
		"newly idle worker joins an in-progress comparison")
	_fresh()
	near = _add_worker(202, Vector3i(40,20,40))
	far = _add_worker(201, Vector3i(55,20,40))
	source = _designate()
	slow.source = source
	tasks.register_work_source(source.source_id, slow)
	tasks._run_scheduler()
	tasks.register_work_source(source.source_id, source)
	near.dev_make_tired()
	near._process(.1)
	await _dispatch()
	_expect(near.is_sleeping() and near.current_task_id < 0 and far.current_task_id == source.lease_id,
		"worker becoming unavailable during ranking is excluded")
	_fresh()
	far = _add_worker(201, Vector3i(55,20,40))
	source = _designate()
	slow.source = source
	tasks.register_work_source(source.source_id, slow)
	tasks._run_scheduler()
	tasks.register_work_source(source.source_id, source)
	details.cancel_clearing(BLUE)
	await _dispatch()
	_expect(far.current_task_id < 0 and source.reserved_by < 0, "cancelling while ranking cannot assign stale work")
	tasks.reset_runtime_state()
	_expect(tasks._surface_match.is_empty(), "scene reset discards pending comparison")


func _other_surface_jobs() -> void:
	for spec in [["base:detail:boulder", "clear_stones"], ["base:detail:scree", "clear_stones"],
		["base:detail:flowers", "clear_shrubs"], ["base:detail:reeds", "clear_shrubs"]]:
		_fresh()
		var far = _add_worker(201, Vector3i(55,20,40))
		var near = _add_worker(202, Vector3i(40,20,43))
		details.register_record({"id": "selection:other", "definition": spec[0],
			"origin": Vector3i(40,20,44), "variant": 0, "yaw": 0})
		_expect(details.designate_detail("selection:other", spec[1]), "%s order accepted" % spec[0])
		if not details._sources.has("selection:other"): continue
		var source = details._sources["selection:other"]
		await _dispatch()
		_expect(near.current_task_id == source.lease_id and far.current_task_id < 0,
			"%s also chooses the nearest idle worker" % spec[0])
