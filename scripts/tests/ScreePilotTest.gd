extends "res://scripts/tests/BoulderPilotTest.gd"

const SCREE_ID := "scree:1234:1:1"


func _run() -> void:
	create_timer(90).timeout.connect(func(): push_error("Scree test timed out"); quit(1))
	root.get_node("SaveManager").set_process(false)
	root.get_node("RoomManager").set_process(false)
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
	manager = load("res://scripts/ui/UIWindowManager.gd").new()
	manager.name = "Windows"
	scene.add_child(manager)
	manager._layout_loaded = false
	drops = load("res://scripts/systems/ItemDropManager.gd").new()
	scene.add_child(drops)
	details = load("res://scripts/systems/SurfaceDetailManager.gd").new()
	scene.add_child(details)
	details.set_process(false)
	details._initialized = true
	for i in range(3):
		var id := "scree:1234:1:%d" % (i+1)
		details.register_record({"id": id, "definition": "base:detail:scree", "origin": Vector3i(40+i*6,20,40), "variant": i, "yaw": 0, "habitat": "fixture"})
		details._spawn_visual(id)
		var bounds: AABB = details.get_explorer_bounds(id)
		_expect(is_equal_approx(bounds.position.y,21) and bounds.size.y <= .5 and bounds.size.x <= 3 and bounds.size.z <= 3, "imported scree is grounded, low and within footprint")
		_expect(details._records[id].occupancy < 0 and details._records[id].node.find_children("*","CollisionShape3D",true,false).is_empty(), "scree has no navigation or physics obstacle")
		for x in range(40+i*6,43+i*6):
			for z in range(40,43): _expect(root.get_node("NavGrid").is_walkable(Vector3i(x,20,z)), "every scree footprint cell is walkable")
		print("SCREE_ASSET ", i+1, " bounds ", bounds)
	explorer = load("res://scripts/ui/ObjectExplorerController.gd").new()
	explorer.window_manager_path = NodePath("../Windows")
	scene.add_child(explorer)
	camera = Camera3D.new()
	scene.add_child(camera)
	camera.current = true
	root.size = Vector2i(1280,800)
	root.get_node("WorldGenerator")._maps_ready = true
	_aim_above(Vector3(41,21,41))
	await process_frame
	var hit: Dictionary = details.pick_explorer_object(Vector3(40.75,26,40.875),Vector3(40.75,20,40.875))
	_expect(hit.get("id", "") == SCREE_ID, "scree picking works through actual stone geometry without a collider")
	_expect(explorer.select_object(details,SCREE_ID), "scree opens ordinary inspector")
	_expect(details.get_explorer_data(SCREE_ID).actions[0].text == "Gather stones", "inspector offers gathering")
	explorer._perform_action("clear")
	var source: RefCounted = details._sources[SCREE_ID]
	_expect(source.duration == 3 and source.task_type == Task.Type.GATHER_SCREE, "gathering uses its configured short work lease")
	var lease: int = source.lease_id
	details.designate_clearing(SCREE_ID)
	_expect(source.lease_id == lease, "repeated designation keeps one task")
	var factory = load("res://scripts/entities/DwarfFactory.gd").new()
	worker = factory.spawn(factory.generate(101, {}),101)
	scene.add_child(worker)
	worker.position = Vector3(34.5,21,40.5)
	worker.set_process(false)
	tasks.register_dwarf(worker)
	_expect(await _until_working(), "actual worker routes to scree gathering")
	_expect(load("res://scripts/components/DwarfInspection.gd").describe(worker).activity == "Gathering loose stones", "worker inspection names gathering")
	_expect((worker._mining_pose.pickaxe == null or not worker._mining_pose.pickaxe.visible) and (worker._felling_pose.axe == null or not worker._felling_pose.axe.visible), "gathering uses hands instead of a work tool")
	if "--capture" in OS.get_cmdline_user_args(): await _capture_scree()
	worker._process(.5)
	var partial := float(source.state.work_seconds)
	clock_node.set_paused(true)
	worker._process(2)
	_expect(source.state.work_seconds == partial, "pause freezes gathering")
	clock_node.set_paused(false)
	worker.dev_force_interrupt()
	_expect(source.reserved_by == -1 and source.state.work_seconds == partial, "interrupt releases worker and retains gathering progress")
	_expect(await _until_working(), "gathering resumes")
	worker.dev_make_tired()
	worker._process(.1)
	_expect(worker.is_sleeping() and source.reserved_by == -1, "sleep releases scree work")
	worker._wake_up()
	_expect(await _until_working(), "gathering resumes after waking")
	explorer._perform_action("cancel")
	_expect(worker.current_task_id == -1 and details._changes[SCREE_ID].work_seconds == partial, "cancel preserves partial gathering work")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(details.serialize_state()))
	details.restore_state(saved)
	_expect(JSON.parse_string(JSON.stringify(details.serialize_state())) == saved, "cancelled scree state round-trips")
	details.designate_clearing(SCREE_ID)
	details.restore_state(JSON.parse_string(JSON.stringify(details.serialize_state())))
	_expect(details._sources.size() == 1, "active restore creates one gathering source")
	_expect(await _until_working(), "restored gathering resumes through scheduler")
	for i in range(50):
		worker._process(.1)
		if details._changes[SCREE_ID].removed: break
	_expect(details._changes[SCREE_ID].removed and _item_count("base:resources:stone:rough_stone") == 1, "three-second gathering removes the clump and yields one rough stone")
	details.restore_state(JSON.parse_string(JSON.stringify(details.serialize_state())))
	details._spawn_visual(SCREE_ID)
	_expect(details._records[SCREE_ID].node == null and _item_count("base:resources:stone:rough_stone") == 1, "load cannot regrow scree or duplicate its reward")
	var second := "scree:1234:1:2"
	details.designate_clearing(second)
	_expect(await _until_working(), "worker reaches another clump")
	world.set_block(46,20,40,blocks.AIR_ID)
	_expect(details._changes[second].removed and worker.current_task_id == -1, "mining support retires active gathering")
	world.set_block(46,20,40,blocks.get_id("base:terrain:rock:rock01"))
	details._spawn_visual(second)
	_expect(details._records[second].node == null, "restoring ground does not regrow scree")
	var third := "scree:1234:1:3"
	details.apply_slice(19)
	_expect(details.get_explorer_bounds(third).size == Vector3.ZERO and root.get_node("NavGrid").is_walkable(Vector3i(52,20,40)), "slice conceals scree and keeps floor walkable")
	details.apply_slice(127)
	clock_node.season_changed.emit("winter")
	_expect(details.get_explorer_bounds(third).size != Vector3.ZERO, "season preserves scree identity")
	details.designate_clearing(third)
	var handle: int = root.get_node("PlacedEntityRegistry").register_box(Vector3i(52,21,40),Vector3i(1,3,1))
	_expect(details._changes[third].removed and not details._sources.has(third), "committed structure displaces nonblocking scree and cancels its job")
	root.get_node("PlacedEntityRegistry").unregister(handle)
	details.restore_state(JSON.parse_string(JSON.stringify(details.serialize_state())))
	details._spawn_visual(third)
	_expect(details._records[third].node == null and _item_count("base:resources:stone:rough_stone") == 1, "displacement persists and grants no unearned yield")
	for failure in failures: push_error(failure)
	print("SCREE_PILOT_", "PASS" if failures.is_empty() else "FAIL", ": ", failures)
	quit(0 if failures.is_empty() else 1)


func _capture_scree() -> void:
	# Reuse the native asset-stage setup without advancing simulation work.
	await _capture_boulders("res://tmp/scree_review/pilot.png")
