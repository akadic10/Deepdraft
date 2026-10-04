extends "res://scripts/tests/TreeFellingTest.gd"

var mining


func _setup_mining_fixture() -> void:
	for name in ["SaveManager","RoomManager","StockpileManager","WorkFeedback"]:
		root.get_node(name).set_process(false)
	clock_node = root.get_node("WorldClock")
	clock_node.set_process(false)
	clock_node.set_paused(false)
	clock_node.set_speed(1)
	tasks = root.get_node("TaskManager")
	tasks.set_process(false)
	root.get_node("WorldGenerator").world_seed = 1234
	world = root.get_node("WorldData")
	blocks = root.get_node("BlockRegistry")
	_build_floor()
	scene = Node3D.new()
	root.add_child(scene)
	current_scene = scene
	drops = load("res://scripts/systems/ItemDropManager.gd").new()
	scene.add_child(drops)
	mining = load("res://scripts/systems/MiningDesignationController.gd").new()
	scene.add_child(mining)
	mining.set_process(false)
	var factory = load("res://scripts/entities/DwarfFactory.gd").new()
	worker = factory.spawn(factory.generate(141,{}),141)
	scene.add_child(worker)
	worker.position = Vector3(41.5,21,40.5)
	worker.set_process(false)
	tasks.register_dwarf(worker)
	await process_frame


func _begin_block(block: Vector3i, key := "base:terrain:rock:rock01") -> int:
	world.set_block(block.x,block.y,block.z,blocks.get_id(key))
	var selected: Array[Vector3i] = [block]
	var id: int = mining._create_zone(selected)
	for i in range(120):
		tasks._run_scheduler()
		worker._process(.01)
		if worker._task_phase == worker.TaskPhase.ZONE_SWINGING:
			return id
		await process_frame
	_expect(false,"block %s starts through real mining scheduler" % block)
	return id


func _until_mining() -> bool:
	for i in range(120):
		tasks._run_scheduler()
		worker._process(.01)
		if worker._task_phase == worker.TaskPhase.ZONE_SWINGING:
			return true
		await process_frame
	return false


func _check_pick_grips() -> void:
	var pose: RefCounted = worker._mining_pose
	var pick: Node3D = pose.pickaxe
	_expect(is_instance_valid(pick) and pick.visible and pick.get_parent() == worker._hand_r,"mining equips pickaxe in right hand")
	var contact: Vector3 = worker.to_global(worker._mine_contact)
	var box := AABB(Vector3(worker._zone_block)-Vector3.ONE*.001,Vector3.ONE*1.002)
	_expect(box.has_point(contact),"contact lies on/just inside target voxel")
	var previous := Vector3.ZERO
	for phase in [0.0,.2,.4,.55,.75,.93,1.0]:
		pose.apply(phase,worker._mine_contact)
		_expect((worker._hand_r.global_transform*pose.PALM).distance_to(pick.global_position) < .001,"lower grip follows pick")
		_expect((worker._hand_l.global_transform*pose.PALM).distance_to(pick.global_transform*pose.SUPPORT_GRIP) < .001,"upper grip follows pick")
		if phase >= pose.CONTACT_PHASE:
			_expect((pick.global_transform*pose.PICK_POINT).distance_to(contact) < .001,"pick point reaches target face")
		if phase > 0 and phase < .93:
			_expect(previous.distance_to(pick.global_position) > .001,"wind-up and strike move pick")
		previous = pick.global_position
	worker.apply_slice(19)
	_expect(not pick.is_visible_in_tree(),"slice hides pick with dwarf")
	worker.apply_slice(127)
	pose.apply(0,worker._mine_contact)


func _check_stowed_pick(reason: String) -> void:
	_expect(not worker._mining_pose.pickaxe.visible,"%s stows pick" % reason)
	_expect(worker._hand_r.scale.is_equal_approx(Vector3(-1,1,1)) and worker._foot_r.scale.is_equal_approx(Vector3(-1,1,1)),"%s preserves mirrors" % reason)
	for part in [worker._body,worker._head,worker._hand_l,worker._hand_r,worker._foot_l,worker._foot_r]:
		_expect(part.position.is_zero_approx() and part.rotation.is_zero_approx(),"%s restores pose" % reason)


func _run() -> void:
	create_timer(45).timeout.connect(func(): push_error("Mining animation test timed out"); quit(1))
	await _setup_mining_fixture()
	# All supported vertical offsets; the worker must keep its real stand cell.
	for y in range(19,26):
		worker.position = Vector3(41.5,21,40.5)
		var id: int = await _begin_block(Vector3i(42,y,40))
		_expect(worker.current_cell() == Vector3i(41,20,40),"existing vertical reach unchanged")
		_check_pick_grips()
		mining._remove_zone(id)
		_check_stowed_pick("cancel y%d" % y)
		world.set_block(42,y,40,blocks.AIR_ID)
	# Cardinal headings and turning must not change the grip/point calculation.
	for offset in [Vector3i(-1,2,0),Vector3i(0,2,-1),Vector3i(0,2,1)]:
		var id: int = await _begin_block(Vector3i(41,20,40)+offset)
		_check_pick_grips()
		mining._remove_zone(id)
		var removed: Vector3i = Vector3i(41,20,40)+offset
		world.set_block(removed.x,removed.y,removed.z,blocks.AIR_ID)
	var block := Vector3i(42,22,40)
	var id: int = await _begin_block(block)
	var source: RefCounted = worker._zone_source()
	worker._process(.1)
	var timer: float = worker._swing_timer
	var transform: Transform3D = worker._hand_r.transform
	clock_node.set_paused(true)
	worker._process(5)
	_expect(is_equal_approx(worker._swing_timer,timer) and worker._hand_r.transform.is_equal_approx(transform),"pause freezes mining and pick")
	clock_node.set_paused(false)
	clock_node.set_speed(2)
	worker._process(.02)
	_expect(is_equal_approx(worker._swing_timer,timer-.04),"mining and pick follow clock speed")
	clock_node.set_speed(1)
	worker.dev_force_interrupt()
	_check_stowed_pick("interrupt")
	_expect(source.reserved_block_of(worker.dwarf_id).y < 0 and world.get_block(block.x,block.y,block.z) != blocks.AIR_ID,"interrupt releases block without mining it")
	_expect(await _until_mining(),"resume after interrupt")
	worker.dev_make_tired()
	worker._process(.01)
	_check_stowed_pick("sleep")
	worker._wake_up()
	_expect(await _until_mining(),"resume after sleep")
	var total: float = (worker._swings_left-1)*worker._swing_time+worker._swing_timer
	worker._process(total-.01)
	_expect(world.get_block(block.x,block.y,block.z) != blocks.AIR_ID,"full authored work still required across a long frame")
	worker._process(.02)
	_expect(world.get_block(block.x,block.y,block.z) == blocks.AIR_ID,"block commits once after authored swings")
	_check_stowed_pick("completion")
	# Underfoot uses the top face and still snaps down after the block is gone.
	worker.position = Vector3(41.5,21,40.5)
	id = await _begin_block(Vector3i(41,20,40))
	_check_pick_grips()
	worker._process(10)
	_expect(worker.global_position.y == 20,"underfoot mining settles onto next floor")
	_check_stowed_pick("underfoot completion")
	# Switching work families never leaves both implicit tools visible.
	world.set_block(41,20,40,blocks.get_id("base:terrain:rock:rock01"))
	worker.position = Vector3(41.5,21,39.5)
	flora = load("res://scripts/systems/SurfaceFloraSpawner.gd").new()
	scene.add_child(flora)
	flora.set_process(false)
	_spawn_tree("oak","mature",Vector2i(40,40))
	flora.designate_felling(Vector2i(40,40))
	_expect(await _until_working(),"switch from mining to felling")
	_expect(is_instance_valid(worker._felling_pose.axe) and worker._felling_pose.axe.visible and not worker._mining_pose.pickaxe.visible,"only axe shown for felling")
	flora.cancel_felling(Vector2i(40,40))
	flora._remove_tree_visual(Vector2i(40,40))
	worker.position = Vector3(41.5,21,39.5)
	id = await _begin_block(Vector3i(42,22,39))
	_expect(worker._mining_pose.pickaxe.visible and not worker._felling_pose.axe.visible,"only pick shown after returning to mining")
	mining._remove_zone(id)
	_check_stowed_pick("final cancel")
	for failure in failures:
		push_error(failure)
	if failures.is_empty():
		print("MINING_ANIMATION_OK: all reach heights, cardinal headings, underfoot, exact grips/contact, pause/speed, interrupt/sleep/cancel, authored work, floor snap, tool swaps")
	quit(0 if failures.is_empty() else 1)
