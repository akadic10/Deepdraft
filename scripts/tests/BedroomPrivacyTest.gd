extends "res://scripts/tests/BedroomTest.gd"

func _run() -> void:
	create_timer(120).timeout.connect(func(): push_error("Privacy timeout"); quit(1))
	await _setup_crafting_fixture()
	var Privacy = load("res://scripts/components/DwarfPrivacy.gd")
	var factory = load("res://scripts/entities/DwarfFactory.gd").new()
	extra_worker = factory.spawn(factory.generate(142,{}),142)
	scene.add_child(extra_worker)
	extra_worker.position = Vector3(55.5,21,55.5)
	extra_worker.set_process(false)
	tasks.register_dwarf(extra_worker)
	rooms = root.get_node("RoomManager")
	rooms.clear_runtime_state()
	_build_bedroom()
	door = _put("door_2",Vector3i(63,20,60))
	bed = _put("log_bed",Vector3i(62,20,64))
	lamp = _put("torch",Vector3i(68,20,64))
	_room_data()
	var inside := Vector3i(66,20,62)
	_expect(not Privacy.allowed(inside,worker.dwarf_id) and Privacy.allowed(inside,worker.dwarf_id,true),"unassigned bedroom allows sleep, not lounging")
	furniture.assign_bed(bed.installed_id,worker.dwarf_id)
	_expect(Privacy.allowed(inside,worker.dwarf_id),"owner may relax in own room")
	_expect(not Privacy.allowed(inside,142,true),"visitor cannot sleep on private bedroom floor")
	_expect(not Privacy.segment(Vector3i(64,20,58),inside,142),"leisure segment cannot cross private threshold")
	# The filtered route must find a detour, and must not poison normal work paths.
	var nav := root.get_node("NavGrid")
	var bypass := func(cell: Vector3i): return not (cell.x in range(74,77) and cell.z in range(74,77))
	var route: Array[Vector3i] = nav.find_path(Vector3i(72,20,75),Vector3i(78,20,75),1200,bypass)
	_expect(not route.is_empty(),"sleep route finds a public detour")
	for cell: Vector3i in route: _expect(bypass.call(cell),"sleep route does not cross another bedroom")
	_expect(nav.find_path(Vector3i(72,20,75),Vector3i(75,20,75)).size()>0,"filtered sleep search leaves work navigation unchanged")
	worker.position = Vector3(66.5,21,62.5)
	worker._idle_behavior.cancel()
	worker.stop_walking()
	# Assignment change displaces an existing idle visitor without teleporting.
	furniture.assign_bed(bed.installed_id,142)
	for i in 500:
		worker._idle_behavior.tick(.1)
		if Privacy.allowed(worker.current_cell(),worker.dwarf_id): break
	_expect(Privacy.allowed(worker.current_cell(),worker.dwarf_id) and worker.position.distance_to(Vector3(66.5,21,62.5))>2,"visitor physically walks out after assignment changes")
	worker._idle_behavior.cancel()
	_expect(worker.walk_to(inside),"normal task-style navigation can still enter private room")
	worker.stop_walking()
	worker.position = Vector3(66.5,21,62.5)
	worker._begin_sleep()
	var remaining: float = worker._sleep_hours_left
	for i in 500:
		worker._process_sleeping(.1)
		if Privacy.allowed(worker.current_cell(),worker.dwarf_id,true): break
	_expect(Privacy.allowed(worker.current_cell(),worker.dwarf_id,true) and worker._sleep_hours_left==remaining,"tired visitor leaves before resting, with no sleep credited while walking")
	worker._wake_up()
	furniture.assign_bed(bed.installed_id,-1)
	_expect(await _sleep_unassigned(),"unassigned bedroom remains available for real bed sleep")
	_private_replan(Privacy)
	for failure: String in failures: push_error(failure)
	print("BEDROOM_PRIVACY_OK" if failures.is_empty() else "BEDROOM_PRIVACY_FAIL")
	quit(0 if failures.is_empty() else 1)

func _sleep_unassigned() -> bool:
	worker._begin_sleep()
	return await _sleep_in_bed(worker)


## A walk to a meal's seat or a game keeps out of rooms the dwarf may not use when it replans, as
## its first route did (the project review, 2026-11-09: a replan crossed a private bedroom). A
## second door makes the bedroom the short way through; it is for sleep, not a walk to a meal.
func _private_replan(Privacy) -> void:
	for x in [63, 64]:
		for y in range(21, 25): world.set_block(x, y, 69, blocks.AIR_ID)
	_put("door_2", Vector3i(63, 20, 69))
	_room_data()
	var nav := root.get_node("NavGrid")
	var start := Vector3i(63, 20, 57)
	var goal := Vector3i(63, 20, 72)
	var through: Array[Vector3i] = nav.find_path(start, goal)
	_expect(through.any(func(cell: Vector3i) -> bool: return not Privacy.allowed(cell, 142)), "the short way runs through the bedroom")
	var detour: Array[Vector3i] = nav.find_path(start, goal, 4000, func(cell: Vector3i): return Privacy.allowed(cell, 142))
	_expect(not detour.is_empty(), "a public way round exists")
	extra_worker.position = Vector3(start) + Vector3(.5, 1, .5)
	extra_worker.start_route(detour, true)
	extra_worker._movement._repath_walk()
	var replanned: Array = extra_worker.get_move_path()
	_expect(not replanned.is_empty() and replanned.all(func(cell: Vector3i) -> bool: return Privacy.allowed(cell, 142)),
		"a replanned walk to a meal keeps out of the bedroom: %d of %d cells inside" % [replanned.filter(func(cell: Vector3i) -> bool: return not Privacy.allowed(cell, 142)).size(), replanned.size()])
	extra_worker.stop_walking()
