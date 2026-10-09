extends "res://scripts/tests/ShrubTransplantTest.gd"

var helper


func _run() -> void:
	create_timer(90).timeout.connect(func(): push_error("Shrub Move handoff timed out"); quit(1))
	_setup_fixture()
	var plan := _move(STRAW, Vector3i(46,20,46))
	_expect(await _advance_until(func(): return bool(details._changes[STRAW].get("packed", false))),
		"Furlok uproots the strawberry")
	_expect(worker.current_task_id < 0 and helper.current_task_id < 0
		and tasks._idle_dwarves == [helper.dwarf_id, worker.dwarf_id],
		"uproot completion reproduces the near worker at the end of the idle queue")
	var ghost = furniture._ghosts[plan]
	for i in range(40):
		furniture._process(.1)
		tasks._run_scheduler()
		if worker.current_task_id >= 0 or helper.current_task_id >= 0: break
		await process_frame
	_expect(worker.current_task_id == ghost._lease_id and helper.current_task_id < 0,
		"Furlok continues the same Move instead of sending Rogan to collect the shrub")
	_expect(await _advance_until(func(): return not furniture._ghosts.has(plan)), "Move reaches replanting completion")
	_expect(details._records[STRAW].origin == Vector3i(46,20,46)
		and not details._changes[STRAW].removed and not details._changes[STRAW].packed,
		"one exact strawberry exists at its destination")
	_expect(drops.serialize_state().loose.is_empty(), "completed Move leaves no packed copy or bonus drop")
	await _tie_and_budget()
	await _sleep_and_priority()
	await _cancel_and_interrupt()
	await _blocked_routes()
	for message: String in failures: push_error(message)
	print("SHRUB_MOVE_HANDOFF_OK" if failures.is_empty() else "SHRUB_MOVE_HANDOFF_FAIL: %s" % str(failures))
	quit(0 if failures.is_empty() else 1)


func _setup_fixture() -> void:
	for name in ["SaveManager", "RoomManager", "StockpileManager", "WorldClock", "TaskManager"]:
		root.get_node(name).set_process(false)
	clock_node = root.get_node("WorldClock")
	tasks = root.get_node("TaskManager")
	world = root.get_node("WorldData")
	blocks = root.get_node("BlockRegistry")
	_build_floor()
	for x in range(32,64):
		for z in range(32,64): world.set_block(x,20,z,blocks.get_id("base:terrain:surface:grass_01"))
	var gen = root.get_node("WorldGenerator")
	gen.world_seed = 1234
	gen.heightmap.resize(1024 * 1024)
	gen.heightmap.fill(20)
	gen._maps_ready = true
	_season("summer")
	scene = Node3D.new()
	root.add_child(scene)
	current_scene = scene
	drops = load("res://scripts/systems/ItemDropManager.gd").new()
	scene.add_child(drops)
	details = load("res://scripts/systems/SurfaceDetailManager.gd").new()
	scene.add_child(details)
	details.set_process(false)
	details._initialized = true
	details.register_record({"id": STRAW, "definition": "base:flora:wild_strawberry_bush",
		"origin": Vector3i(40,20,40), "variant": 0, "yaw": 0})
	furniture = load("res://scripts/systems/FurniturePlacementController.gd").new()
	scene.add_child(furniture)
	furniture.set_process(false)
	furniture._process(0)
	# Rogan is the older idle entry. Furlok is beside the plant.
	helper = _spawn_worker(201, Vector3i(55,20,40))
	worker = _spawn_worker(202, Vector3i(39,20,40))


func _spawn_worker(id: int, cell: Vector3i):
	var factory = load("res://scripts/entities/DwarfFactory.gd").new()
	var agent = factory.spawn(factory.generate(id, {}), id)
	scene.add_child(agent)
	agent.position = Vector3(cell) + Vector3(.5,1,.5)
	agent.set_process(false)
	agent.sleep = 1.0
	tasks.register_dwarf(agent)
	return agent


func _advance_until(condition: Callable) -> bool:
	for i in range(1600):
		furniture._process(.1)
		var before: int = tasks._probes_total
		tasks._run_scheduler()
		_expect(tasks._probes_total - before <= tasks._max_probes_per_wake, "handoff respects probe budget")
		worker._process(.1)
		helper._process(.1)
		if condition.call(): return true
		if i % 20 == 0: await process_frame
	return false


func _new_case(plant_id := STRAW, plant_key := "base:flora:wild_strawberry_bush") -> int:
	worker.abort_task()
	helper.abort_task()
	furniture.free()
	details.free()
	drops.free()
	worker.free()
	helper.free()
	tasks.reset_runtime_state()
	tasks._max_probes_per_wake = 8
	drops = load("res://scripts/systems/ItemDropManager.gd").new()
	scene.add_child(drops)
	details = load("res://scripts/systems/SurfaceDetailManager.gd").new()
	scene.add_child(details)
	details.set_process(false)
	details._initialized = true
	details.register_record({"id": plant_id, "definition": plant_key,
		"origin": Vector3i(40,20,40), "variant": 0, "yaw": 0})
	furniture = load("res://scripts/systems/FurniturePlacementController.gd").new()
	scene.add_child(furniture)
	furniture.set_process(false)
	furniture._process(0)
	helper = _spawn_worker(201, Vector3i(55,20,40))
	worker = _spawn_worker(202, Vector3i(39,20,40))
	return _move(plant_id, Vector3i(46,20,46))


func _packed() -> bool:
	return bool(details._changes[STRAW].get("packed", false))


func _dispatch_only(condition: Callable) -> bool:
	for i in range(80):
		furniture._process(.1)
		var before: int = tasks._probes_total
		tasks._run_scheduler()
		_expect(tasks._probes_total - before <= tasks._max_probes_per_wake, "split handoff respects probe budget")
		if condition.call(): return true
		await process_frame
	return false


func _tie_and_budget() -> void:
	var plan := _new_case()
	_expect(await _advance_until(_packed), "tie fixture reaches the handoff")
	# Both are already at a valid pickup side; idle queue must not force a
	# handoff away from the worker who just lifted the shrub.
	helper.position = Vector3(41.5,21,40.5)
	tasks._max_probes_per_wake = 1
	var ghost = furniture._ghosts[plan]
	_expect(await _dispatch_only(func(): return bool(tasks._move_match.get("pickup_ok", false))),
		"pickup and destination route checks resume on separate wakes")
	_expect(worker.current_task_id < 0 and helper.current_task_id < 0
		and ghost._claim_valid() and drops.reserved_by(ghost._claim, ghost.claim_owner_id()),
		"ranking keeps the plant claim on the plan until both routes pass")
	_expect(await _dispatch_only(func(): return worker.current_task_id == ghost._lease_id),
		"equal-distance tie retains the uprooter")
	_expect(helper.current_task_id < 0, "tie does not assign a second carrier")
	_expect(await _advance_until(func(): return not furniture._ghosts.has(plan)), "tied handoff completes replanting")


func _sleep_and_priority() -> void:
	var plan := _new_case()
	_expect(await _advance_until(_packed), "sleep fixture reaches the handoff")
	tasks._max_probes_per_wake = 1
	_expect(await _dispatch_only(func(): return bool(tasks._move_match.get("pickup_ok", false))),
		"sleep can interrupt an in-progress comparison")
	worker.dev_make_tired()
	worker._process(.1)
	var ghost = furniture._ghosts[plan]
	_expect(await _dispatch_only(func(): return helper.current_task_id == ghost._lease_id),
		"available replacement takes over when the uprooter sleeps")
	_expect(worker.is_sleeping(), "handoff does not wake a sleeping uprooter")
	_expect(await _advance_until(func(): return not furniture._ghosts.has(plan)), "replacement finishes Move")
	plan = _new_case()
	_expect(await _advance_until(_packed), "priority fixture reaches the handoff")
	details.register_record({"id": BLUE, "definition": BLUE_KEY, "origin": Vector3i(38,20,40), "variant": 0, "yaw": 0})
	details.designate_detail(BLUE, "clear_shrubs")
	var urgent: int = details._sources[BLUE].lease_id
	ghost = furniture._ghosts[plan]
	_expect(await _dispatch_only(func(): return helper.current_task_id == ghost._lease_id),
		"replacement may take Move when its uprooter accepts higher-priority work")
	_expect(worker.current_task_id == urgent, "continuation does not bypass higher-priority jobs")
	_expect(await _advance_until(func(): return not furniture._ghosts.has(plan) and worker.current_task_id < 0),
		"both jobs complete without replacing active assignments")


func _cancel_and_interrupt() -> void:
	var plan := _new_case()
	_expect(await _advance_until(_packed), "cancellation fixture reaches the handoff")
	tasks._max_probes_per_wake = 1
	_expect(await _dispatch_only(func(): return bool(tasks._move_match.get("pickup_ok", false))),
		"cancellation can happen between route probes")
	furniture.cancel_ghost(plan)
	for i in range(5): tasks._run_scheduler()
	_expect(worker.current_task_id < 0 and helper.current_task_id < 0 and drops.serialize_state().loose.size() == 1
		and not drops.instance_promised(STRAW), "cancelled Move leaves one recoverable plant and no stale assignment")
	plan = _new_case()
	_expect(tasks._move_match.is_empty(), "scene reset drops cached Move comparisons")
	_expect(await _advance_until(func(): return worker._task_phase == worker.TaskPhase.FETCH_TO_GHOST),
		"original worker physically carries the shrub")
	var cargo: Array = worker.serialize_state().carried_items
	_expect(cargo.size() == 1 and cargo[0].instance_id == STRAW, "carried plant retains exact identity")
	var ghost = furniture._ghosts[plan]
	worker.dev_force_interrupt()
	_expect(ghost.continuation_worker < 0, "interruption removes the old worker preference")
	_expect(ghost._claim_valid(), "release reclaims the dropped Move before the next scheduler wake")
	var dropped: Vector3i = drops.item_floor_cell(ghost._claim)
	helper.position = Vector3(dropped + Vector3i.RIGHT) + Vector3(.5,1,.5)
	worker.position = Vector3(56.5,21,40.5)
	for task in tasks._tasks.values(): task.retry_at = 0
	_expect(await _dispatch_only(func(): return helper.current_task_id == ghost._lease_id),
		"interrupted Move compares replacements at the dropped plant")
	_expect(await _advance_until(func(): return not furniture._ghosts.has(plan)), "interrupted Move replants successfully")
	_expect(details._records[STRAW].origin == Vector3i(46,20,46) and drops.serialize_state().loose.is_empty(),
		"replacement neither duplicates nor loses the strawberry")


func _walls(columns: Array[Vector2i], build: bool) -> void:
	var block: int = blocks.get_id("base:terrain:rock:rock01") if build else blocks.AIR_ID
	for column in columns:
		for y in range(21,25): world.set_block(column.x,y,column.y,block)
	await process_frame
	await process_frame


func _blocked_routes() -> void:
	var plan := _new_case()
	_expect(await _advance_until(_packed), "blocked pickup fixture reaches the handoff")
	worker.position = Vector3(40.5,21,37.5)
	var walls: Array[Vector2i] = [Vector2i(39,37), Vector2i(41,37), Vector2i(40,36), Vector2i(40,38)]
	await _walls(walls, true)
	tasks._max_probes_per_wake = 1
	var ghost = furniture._ghosts[plan]
	_expect(await _dispatch_only(func(): return helper.current_task_id == ghost._lease_id),
		"blocked nearer worker does not hide a reachable replacement")
	_expect(worker.current_task_id < 0, "blocked worker stays idle")
	_expect(await _advance_until(func(): return not furniture._ghosts.has(plan)), "replacement completes with the other worker blocked")
	await _walls(walls, false)
	plan = _new_case()
	_expect(await _advance_until(_packed), "blocked destination fixture reaches the handoff")
	walls.clear()
	for v in range(44,49):
		walls.append(Vector2i(44,v))
		walls.append(Vector2i(48,v))
	for v in range(45,48):
		walls.append(Vector2i(v,44))
		walls.append(Vector2i(v,48))
	await _walls(walls, true)
	ghost = furniture._ghosts[plan]
	tasks._max_probes_per_wake = 1
	_expect(await _dispatch_only(func(): return tasks.get_task(ghost._lease_id).blocked_count > 0),
		"unreachable destination backs off only after route alternatives are tried")
	_expect(worker.current_task_id < 0 and helper.current_task_id < 0 and ghost._claim_valid(),
		"failed delivery routes leave the exact plant safely claimed at its pickup")
	await _walls(walls, false)
	_expect(await _advance_until(func(): return not furniture._ghosts.has(plan)), "opening destination routes resumes and completes Move")
