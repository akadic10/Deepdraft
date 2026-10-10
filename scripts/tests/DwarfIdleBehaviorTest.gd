extends "res://scripts/tests/WorkerCraftingTest.gd"

var inspection
const CHAIR := "base:furniture:wooden_chair"

func _run() -> void:
	create_timer(100).timeout.connect(func(): push_error("Idle behavior timed out"); quit(1))
	await _setup_crafting_fixture()
	inspection = load("res://scripts/components/DwarfInspection.gd")
	_configure(worker)
	drops.spawn_drop(PINE,1,Vector3i(42,21,40))
	var id: int = crafting.queue_order(BENCH_RECIPE,1)
	_expect(await _completed(id),"real work completes before leisure begins")
	var start: Vector3 = worker.position
	for i in range(100):
		await _tick()
		if worker.position.distance_to(start)>1: break
	_expect(worker.position.distance_to(start)>1,"finished worker leaves the old work spot")
	_expect(worker.dwarf_id in tasks._idle_dwarves and worker.current_task_id<0,
		"strolling dwarf remains eligible for work")
	_expect(inspection.roster_state(worker).group=="idle" and inspection.describe(worker).activity=="Strolling nearby",
		"roster and inspector distinguish leisure from assigned work")
	var before: Vector3 = worker.position
	var elapsed: float = worker._idle_behavior.elapsed
	clock_node.set_paused(true)
	worker._process(4)
	_expect(worker.position==before and worker._idle_behavior.elapsed==elapsed,"pause freezes leisure movement and decisions")
	clock_node.set_paused(false)
	clock_node.set_speed(2)
	worker._process(.1)
	_expect(is_equal_approx(worker._idle_behavior.elapsed,elapsed+.2),"leisure follows simulation speed")
	clock_node.set_speed(1)
	drops.spawn_drop(PINE,1,worker.current_cell()+Vector3i(1,1,0))
	id = crafting.queue_order(BENCH_RECIPE,1)
	_expect(await _phase(worker.TaskPhase.FETCH_WORKING),"new work immediately interrupts the stroll")
	_expect(not worker._idle_behavior.active(),"work owns movement and pose after assignment")
	_expect(await _completed(id),"interrupted stroll cannot lose crafting materials or progress")
	var home: Vector3i = worker.current_cell()
	for i in range(300):
		worker._process(.1)
		_expect(Vector3(worker.current_cell()-home).length() <= 9.5,"repeated walks stay near the last job instead of drifting across the map")
		if worker._idle_behavior.state=="strolling":
			_expect(worker._idle_behavior._clear_stop(worker._idle_behavior.goal),"wandering destinations avoid stockpiles, furniture edges and ladder approaches")
	await _chairs_and_interruptions()
	await _boxed_in_and_external_walk()
	if "--capture" in OS.get_cmdline_user_args(): await _capture_seating()
	for failure in failures: push_error(failure)
	print("DWARF_IDLE_OK: work completion, local movement, priorities, pause/speed, seating claims, interruption, teardown, save-safe position and trapped fallback" if failures.is_empty() else "DWARF_IDLE_FAIL")
	quit(0 if failures.is_empty() else 1)

func _configure(agent) -> void:
	var config: Dictionary = tasks.get_config_section("idle").duplicate(true)
	config.start_delay_min_s = .2
	config.start_delay_max_s = .2
	config.pause_min_s = .4
	config.pause_max_s = .6
	config.seat_chance = 0.0
	agent._idle_behavior.config = config

func _reset_at(agent, cell: Vector3i) -> void:
	agent._idle_behavior.cancel()
	agent.position = Vector3(cell)+Vector3(.5,1,.5)

func _seat_phase(agent, desired: String) -> bool:
	for i in range(160):
		agent._process(.1)
		if agent._idle_behavior.state==desired: return true
		await process_frame
	return false

func _chairs_and_interruptions() -> void:
	_reset_at(worker,Vector3i(44,20,44))
	furniture._install(CHAIR,furniture.get_defs()[CHAIR],Vector3i(47,20,44),0)
	var chair = furniture._installed.values()[0]
	worker._idle_behavior.config.seat_chance = 1.0
	_expect(await _seat_phase(worker,"sitting"),"idle dwarf walks to a free chair and sits")
	worker._process(1)
	_expect(chair.idle_seat_owner==worker.dwarf_id,"chair has one transient occupant")
	_expect(inspection.describe(worker).activity=="Sitting" and inspection.roster_state(worker).group=="idle", "seated dwarf is visibly resting but still available for work")
	var saved: Dictionary = worker.serialize_state()
	var pos: Vector3 = root.get_node("SaveManager").unpack_v3(saved.position)
	_expect(root.get_node("NavGrid").is_walkable(Vector3i(floori(pos.x),roundi(pos.y)-1,floori(pos.z))),"save uses the real access floor instead of restoring inside solid furniture")
	var pose: Vector3 = worker._body.position
	clock_node.set_paused(true)
	worker._process(3)
	_expect(worker._body.position==pose,"pause freezes seated pose")
	clock_node.set_paused(false)
	var factory = load("res://scripts/entities/DwarfFactory.gd").new()
	extra_worker = factory.spawn(factory.generate(142,{}),142)
	scene.add_child(extra_worker)
	extra_worker.position = Vector3(50.5,21,47.5)
	extra_worker.set_process(false)
	extra_worker.sleep = 1.0
	tasks.register_dwarf(extra_worker)
	_configure(extra_worker)
	extra_worker._idle_behavior.config.seat_chance = 1.0
	for i in range(100): extra_worker._process(.1)
	_expect(extra_worker._idle_behavior.seat==null and chair.idle_seat_owner==worker.dwarf_id,"two dwarves cannot reserve or sit in the same chair")
	tasks.notify_dwarf_unavailable(extra_worker.dwarf_id)
	var urgent: int = tasks.add_task(Task.Type.BUILD,Vector3i(44,20,42))
	for i in range(60):
		tasks._run_scheduler()
		if worker.current_task_id==urgent: break
		await process_frame
	_expect(worker.current_task_id==urgent and chair.idle_seat_owner<0 and worker._body.position.is_zero_approx(),"work releases the seat and clears its pose immediately")
	tasks.cancel_task(urgent)
	_reset_at(worker,Vector3i(44,20,44))
	_expect(await _seat_phase(worker,"sitting"),"chair can be reused after a work interruption")
	worker.dev_make_tired()
	worker._process(.1)
	_expect(worker.is_sleeping() and chair.idle_seat_owner<0 and not worker._idle_behavior.active(),"sleep safely releases leisure and seating")
	worker._wake_up()
	_expect(await _seat_phase(worker,"sitting"),"awake dwarf can use the chair again")
	chair.set_uninstall(true)
	worker._process(.1)
	_expect(chair.idle_seat_owner<0 and not worker._idle_behavior.active(),"uninstall flag evicts the idle occupant without stranding them")
	chair.set_uninstall(false)
	_expect(await _seat_phase(worker,"sitting"),"unflagging permits seating again")
	worker.restore_saved_runtime(saved)
	_expect(chair.idle_seat_owner<0 and worker._body.position.is_zero_approx(),"runtime restore discards transient seat claims and pose")
	tasks.deregister_dwarf(extra_worker.dwarf_id)
	extra_worker.free()
	extra_worker = null
	# A separately built table must not prevent use of its correctly facing chair.
	furniture._install("base:furniture:wooden_table",furniture.get_defs()["base:furniture:wooden_table"],Vector3i(47,20,46),0)
	_expect(await _seat_phase(worker,"sitting"),"standalone chair remains usable when a table is built in front")
	worker._idle_behavior.timer = .1
	_expect(await _seat_phase(worker,"waiting"),"normal rest finishes with a stand-up transition and releases the chair")
	_expect(chair.idle_seat_owner<0 and worker._body.position.is_zero_approx(),"normal standing restores all visual offsets")
	_expect(await _seat_phase(worker,"sitting"),"free chair can be used again")
	furniture.dev_remove_installed(chair.installed_id)
	worker._process(.1)
	_expect(not worker._idle_behavior.active() and chair.idle_seat_owner<0,"chair removal safely clears its occupant")
	furniture._install(CHAIR,furniture.get_defs()[CHAIR],Vector3i(47,20,44),0)

func _boxed_in_and_external_walk() -> void:
	worker._idle_behavior.config.seat_chance = 0.0
	_reset_at(worker,Vector3i(70,20,70))
	var stone: int = blocks.get_id("base:terrain:rock:rock01")
	for offset: Vector3i in [Vector3i.LEFT,Vector3i.RIGHT,Vector3i.FORWARD,Vector3i.BACK]:
		var cell := Vector3i(70,20,70)+offset
		for y in range(21,25): world.set_block(cell.x,y,cell.z,stone)
	await process_frame
	await process_frame
	for i in range(100): worker._process(.1)
	_expect(worker.current_cell()==Vector3i(70,20,70) and not worker.is_walking(),"boxed-in dwarf waits safely without teleporting or an unbounded path search")
	_reset_at(worker,Vector3i(60,20,60))
	worker._process(.1)
	_expect(worker.walk_to(Vector3i(63,20,60)),"explicit developer walk remains usable")
	for i in range(25):
		worker._process(.1)
		if not worker.is_walking(): break
	_expect(worker.current_cell()==Vector3i(63,20,60),"idle decisions do not override explicit movement")

func _capture_seating() -> void:
	DirAccess.make_dir_recursive_absolute("res://tmp/idle_review")
	for piece in furniture._installed.values().duplicate():
		if piece.furniture_key != CHAIR: furniture.dev_remove_installed(piece.installed_id)
	for yaw in range(4):
		var chair = furniture._installed.values()[0]
		# Reinstall to exercise real rotated furniture geometry and access data.
		furniture.dev_remove_installed(chair.installed_id)
		for node in drops._loose.keys(): drops.take(node); node.free()
		furniture._install(CHAIR,furniture.get_defs()[CHAIR],Vector3i(47,20,44),yaw)
		_reset_at(worker,Vector3i(44,20,42))
		worker._idle_behavior.config.seat_chance = 1.0
		_expect(await _seat_phase(worker,"sitting"),"rotated chair can be reached and used")
		worker._process(1)
		camera.size = 8
		camera.position = Vector3(56,29,53)
		camera.look_at(Vector3(48,22.5,45))
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tmp/idle_review/seated_%d.png" % yaw)
