extends "res://scripts/tests/HaulingAnimationTest.gd"

## Real mining beneath bystanders, interruption with owned cargo, and recovery
## from saved unsupported positions. Also exercise valid vertical movement.
var nav
var walk_results: Array[bool] = []

func _run() -> void:
	create_timer(75).timeout.connect(func(): push_error("Dwarf support test timed out"); quit(1))
	await _setup_fixture()
	nav = root.get_node("NavGrid")
	await _check_cargo()
	await _check_bystanders()
	_check_saved_and_sleeping()
	_check_walks_and_support()
	for failure: String in failures: push_error(failure)
	print("DWARF_SUPPORT_OK: mining bystanders, cargo/claims, saved hovering, sleep/pause, deep floors, steps, ladders and decks" if failures.is_empty() else "DWARF_SUPPORT_FAIL")
	quit(0 if failures.is_empty() else 1)

func _remove_floor(cell: Vector3i) -> void:
	world.set_block(cell.x,cell.y,cell.z,blocks.AIR_ID)
	nav.refresh_mined_block(cell)

func _check_cargo() -> void:
	await _new_trip(STONE, 3)
	_expect(await _until(worker.TaskPhase.HAUL_TO_ZONE), "real worker picks up cargo")
	var cell: Vector3i = worker.current_cell()
	var task_id: int = worker.current_task_id
	_expect(not worker._carried_entries.is_empty() and not zone.reserved_cells.is_empty(), "hauler owns cargo and destination")
	_remove_floor(cell)
	worker._process(.01)
	_expect(worker.current_cell() == cell-Vector3i.UP, "hauler settles before releasing cargo")
	_expect(worker.current_task_id == -1 and worker._task_phase == worker.TaskPhase.NONE, "lost footing interrupts work")
	_expect(worker._carried_entries.is_empty() and zone.reserved_cells.is_empty() and drops._reserved.is_empty(), "cargo and all haul claims released")
	_expect(_snapshot_units() == 3 and _loose_units() == 3, "interrupted carry preserves exact goods")
	for item: Node3D in drops._loose:
		_expect(is_equal_approx(item.position.y,float(cell.y)), "cargo lands on new floor")
	_expect(not tasks._active.has(worker.dwarf_id), "released dwarf has no active lease")
	_expect(tasks.get_task(task_id) != null, "interrupted work remains available")
	world.set_block(cell.x,cell.y,cell.z,blocks.get_id("base:terrain:rock:rock01"))

func _check_bystanders() -> void:
	tasks.reset_runtime_state()
	stockpiles.reset_runtime_state()
	worker.position = Vector3(41.5,21,40.5)
	tasks.register_dwarf(worker)
	var mining = load("res://scripts/systems/MiningDesignationController.gd").new()
	scene.add_child(mining)
	mining.set_process(false)
	var factory = load("res://scripts/entities/DwarfFactory.gd").new()
	var bystanders: Array[Node3D] = []
	for i in range(2):
		var dwarf = factory.spawn(factory.generate(142+i,{}),142+i)
		scene.add_child(dwarf)
		dwarf.position = Vector3(42.5,21,40.5+i)
		dwarf.set_process(false)
		for category: String in dwarf.work_permissions: dwarf.work_permissions[category] = false
		tasks.register_dwarf(dwarf)
		tasks.notify_dwarf_unavailable(dwarf.dwarf_id)
		dwarf._process(.01) # Establish a leisure home on the soon-to-be-mined floor.
		bystanders.append(dwarf)
	for dwarf in bystanders:
		var cell: Vector3i = dwarf.current_cell()
		var selected: Array[Vector3i] = [cell]
		var zone_id: int = mining._create_zone(selected)
		var began := false
		for i in range(240):
			tasks._run_scheduler()
			worker._process(.04)
			if worker._task_phase == worker.TaskPhase.ZONE_SWINGING:
				began = true
				break
			await process_frame
		_expect(began, "miner reaches block under a different dwarf")
		worker._process(10)
		_expect(world.get_block(cell.x,cell.y,cell.z) == blocks.AIR_ID, "real mining commit removes bystander's floor")
		dwarf._process(.01)
		_expect(dwarf.current_cell() == cell-Vector3i.UP and nav.is_walkable(dwarf.current_cell()), "idle bystander settles onto a navigable floor")
		_expect(dwarf._idle_behavior.home.x < 0, "old leisure home is discarded")
		dwarf._process(.01)
		_expect(dwarf._idle_behavior.home == dwarf.current_cell(), "leisure restarts on actual floor")
		var results: Array[bool] = []
		dwarf.walk_finished.connect(func(success: bool): results.append(success))
		_expect(dwarf.walk_to(cell+Vector3i.RIGHT), "previously hovering dwarf can start walk test")
		for i in range(120):
			if not dwarf.is_walking(): break
			dwarf._process(.02)
		_expect(results == [true] and dwarf.current_cell() == cell+Vector3i.RIGHT, "bystander walks out of excavation")
		mining._remove_zone(zone_id)
		tasks.notify_dwarf_unavailable(dwarf.dwarf_id)
	mining.free()

func _check_saved_and_sleeping() -> void:
	worker.abort_task()
	tasks.release_dwarf_task(worker.dwarf_id,Task.ReleaseReason.PLAYER)
	worker.position = Vector3(55.35,31,40.7)
	worker.rotation.y = .4
	var saved: Dictionary = JSON.parse_string(JSON.stringify(worker.serialize_state()))
	worker.position = root.get_node("SaveManager").unpack_v3(saved.position)
	worker.restore_saved_runtime(saved)
	worker.apply_slice(21)
	_expect(not worker.visible, "unsupported save starts above the visible slice")
	clock_node.set_paused(true)
	worker._process(.1)
	_expect(worker.position.y == 31, "pause freezes unsupported saved position")
	clock_node.set_paused(false)
	worker._process(.01)
	_expect(worker.position == Vector3(55.35,21,40.7) and is_equal_approx(worker.rotation.y,.4), "saved hovering position settles beyond old four-block limit, preserving XZ/yaw")
	_expect(worker.visible, "settling updates visibility without changing slices")
	worker.apply_slice(127)
	for y in range(4,21): _remove_floor(Vector3i(55,y,40))
	worker._process(.01)
	_expect(worker.position.y == 4, "deep shaft stops at bedrock")
	worker.position = Vector3(57.5,21,40.5)
	worker._begin_sleep()
	var remaining: float = worker._sleep_hours_left
	_remove_floor(Vector3i(57,20,40))
	worker._process(.01)
	_expect(worker.position.y == 20 and worker._sleeping and worker._sleep_hours_left == remaining, "sleeping dwarf settles without resetting sleep")
	_expect(not tasks._idle_dwarves.has(worker.dwarf_id), "sleeping dwarf stays unavailable")
	worker._wake_up()

func _check_walks_and_support() -> void:
	worker.walk_finished.connect(func(success: bool): walk_results.append(success))
	worker.position = Vector3(60.5,21,40.5)
	_expect(worker.walk_to(Vector3i(65,20,40)), "walking fixture starts")
	_remove_floor(Vector3i(60,20,40))
	worker._process(.01)
	_expect(walk_results == [false] and not worker.is_walking() and worker.position.y == 20, "lost support cancels obsolete walk exactly once")
	walk_results.clear()
	_expect(worker.walk_to(Vector3i(65,20,40)), "walk can restart from new floor")
	_finish_walk()
	_expect(walk_results == [true], "restarted walk completes")
	# Both directions of a normal step must retain fractional interpolation.
	var stone: int = blocks.get_id("base:terrain:rock:rock01")
	world.set_block(66,21,40,stone)
	for goal in [Vector3i(66,21,40),Vector3i(65,20,40)]:
		walk_results.clear()
		_expect(worker.walk_to(goal), "normal step starts")
		_finish_walk()
		_expect(walk_results == [true] and worker.current_cell() == goal, "step completes without false support loss")
	# Clearance is a route constraint, not a reason to fall through solid rock.
	worker.position = Vector3(68.5,21,40.5)
	world.set_block(68,22,40,stone)
	_expect(not nav.is_walkable(worker.current_cell()), "obstructed floor is not walkable")
	_expect(not worker._snap_to_floor() and worker.position.y == 21, "solid support remains despite obstructed headroom")
	worker.position = Vector3(70.5,27,40.5)
	var deck: Array[Vector3i] = [worker.current_cell()]
	var exits: Array[Vector3i] = [Vector3i(69,26,40)]
	nav.set_bridge(999,deck,exits)
	_expect(not worker._snap_to_floor() and worker.position.y == 27, "bridge deck is physical support")
	nav.remove_bridge(999)
	_expect(worker._snap_to_floor() and worker.position.y == 21, "removed deck exposes floor below")
	nav.set_ladder(999,Vector3i(72,20,40),10,Vector3i.RIGHT,.5)
	worker.position = Vector3(72.5,26.4,40.5)
	_expect(not worker._snap_to_floor() and is_equal_approx(worker.position.y,26.4), "rungs support fractional climbing height")
	nav.remove_ladder(999)
	worker._process(.01)
	_expect(worker.position.y == 21, "lost ladder support also recovers")

func _finish_walk() -> void:
	for i in range(500):
		if not worker.is_walking(): break
		worker._process(.02)
