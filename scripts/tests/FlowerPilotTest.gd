extends "res://scripts/tests/BoulderPilotTest.gd"

var category := "flowers"
var clear_label := "Clear flowers"
var activity := "Clearing flowers"
var max_height := 1.0
var variants := 3
var review_dir := "flower_review"


func _fixture(index: int) -> String:
	return "%s:1234:fixture:%d" % [category,index]


func _run() -> void:
	create_timer(90).timeout.connect(func(): push_error("Flower test timed out"); quit(1))
	root.get_node("SaveManager").set_process(false)
	root.get_node("RoomManager").set_process(false)
	clock_node = root.get_node("WorldClock")
	clock_node.set_process(false)
	_season("summer")
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
		var id := _fixture(i)
		details.register_record({"id": id, "definition": "base:detail:" + category, "origin": Vector3i(40+i*6,20,40), "variant": i % variants, "yaw": i, "habitat": "fixture"})
		for season: String in ["spring","summer","autumn","winter"]:
			_season(season)
			details._spawn_visual(id)
			var record: Dictionary = details._records[id]
			var bounds: AABB = details.get_explorer_bounds(id)
			_expect(is_equal_approx(bounds.position.y,21) and bounds.size.y <= max_height and bounds.size.x <= 1.5 and bounds.size.z <= 1.5, "all flower assets grounded and within envelope")
			_expect(String(record.model_path).ends_with("%s.glb" % season), "season chooses authored flower appearance")
			_expect(record.origin == Vector3i(40+i*6,20,40) and record.variant == i % variants and record.yaw == i, "season never moves or reseeds flowers")
			_expect(record.occupancy < 0 and record.node.find_children("*","CollisionShape3D",true,false).is_empty(), "flowers never block movement")
			_expect(root.get_node("NavGrid").is_walkable(record.origin), "flower support stays walkable")
		_expect(not details.accepts_tool(id,"clear_stones") and not details.accepts_tool(id,"harvest_plants"), "flowers excluded from stone and harvest tools")
	_season("summer")
	for id: String in details._records: details._spawn_visual(id)
	explorer = load("res://scripts/ui/ObjectExplorerController.gd").new()
	explorer.window_manager_path = NodePath("../Windows")
	scene.add_child(explorer)
	camera = Camera3D.new()
	scene.add_child(camera)
	camera.current = true
	root.size = Vector2i(1280,800)
	root.get_node("WorldGenerator")._maps_ready = true
	_aim_above(Vector3(40.5,21,40.5))
	await process_frame
	_expect(explorer.select_object(details,_fixture(0)), "flower inspector opens")
	_expect(details.get_explorer_data(_fixture(0)).actions.any(func(a): return a.id == "clear" and a.text == clear_label), "flowers retain permanent clearing alongside Move and Uproot")
	explorer._perform_action("clear")
	var source: RefCounted = details._sources[_fixture(0)]
	_expect(source.task_type == Task.Type.CLEAR_PLANT and source.duration == 1.5, "flower clearing uses configured hand-work lease")
	var factory = load("res://scripts/entities/DwarfFactory.gd").new()
	worker = factory.spawn(factory.generate(101, {}),101)
	scene.add_child(worker)
	worker.position = Vector3(34.5,21,40.5)
	worker.set_process(false)
	tasks.register_dwarf(worker)
	_expect(await _until_working(), "worker routes to clear flowers")
	_expect(load("res://scripts/components/DwarfInspection.gd").describe(worker).activity == activity, "worker inspector names flower work")
	_expect((worker._mining_pose.pickaxe == null or not worker._mining_pose.pickaxe.visible) and (worker._felling_pose.axe == null or not worker._felling_pose.axe.visible), "flowers cleared by hand")
	if "--capture" in OS.get_cmdline_user_args():
		var cube := MeshInstance3D.new()
		cube.mesh = BoxMesh.new()
		cube.position = Vector3(38,21.5,43)
		scene.add_child(cube)
		await _capture_boulders("res://tmp/" + review_dir + "/worker_scale.png")
	worker._process(.4)
	var partial := float(source.state.work_seconds)
	clock_node.set_paused(true)
	worker._process(2)
	_expect(source.state.work_seconds == partial, "pause preserves flower work")
	clock_node.set_paused(false)
	worker.dev_force_interrupt()
	_expect(source.reserved_by == -1 and source.state.work_seconds == partial, "interruption keeps progress and frees worker")
	_expect(await _until_working(), "worker resumes interrupted clearing")
	details.cancel_clearing(_fixture(0))
	_expect(worker.current_task_id == -1 and drops._loose.is_empty(), "cancel grants no items")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(details.serialize_state()))
	details.restore_state(saved)
	_expect(JSON.parse_string(JSON.stringify(details.serialize_state())) == saved, "cancelled clearing round-trips")
	details.designate_clearing(_fixture(0))
	details.restore_state(JSON.parse_string(JSON.stringify(details.serialize_state())))
	_season("winter")
	details._spawn_visual(_fixture(0))
	_expect(details._sources.size() == 1 and details._changes[_fixture(0)].work_seconds == partial, "active clearing survives load and seasonal swap")
	_expect(await _until_working(), "restored worker clearing resumes")
	for i in range(30): worker._process(.1)
	_expect(details._changes[_fixture(0)].removed and drops._loose.is_empty(), "worker removes flowers without loot")
	_expect(not details._complete_clearing(101,_fixture(0)), "duplicate completion rejected")
	details.restore_state(JSON.parse_string(JSON.stringify(details.serialize_state())))
	_season("spring")
	details._spawn_visual(_fixture(0))
	_expect(details._records[_fixture(0)].node == null, "removed flowers never regrow after season/load")
	var second := _fixture(1)
	details.designate_clearing(second)
	_expect(await _until_working(), "worker reaches another flower clump")
	world.set_block(46,20,40,blocks.AIR_ID)
	_expect(details._changes[second].removed and worker.current_task_id == -1, "support loss cancels active clearing")
	world.set_block(46,20,40,blocks.get_id("base:terrain:rock:rock01"))
	details._spawn_visual(second)
	_expect(details._records[second].node == null, "ground repair does not regrow flowers")
	var third := _fixture(2)
	details.apply_slice(19)
	_expect(details.get_explorer_bounds(third).size == Vector3.ZERO and details.details_in_rect(Rect2i(50,38,5,5),"clear_shrubs").is_empty(), "slice hides flowers and excludes orders")
	details.apply_slice(127)
	details.designate_clearing(third)
	var handle: int = root.get_node("PlacedEntityRegistry").register_box(Vector3i(52,21,40),Vector3i(1,3,1))
	_expect(details._changes[third].removed and not details._sources.has(third), "building displaces flowers and cancels work")
	root.get_node("PlacedEntityRegistry").unregister(handle)
	details.restore_state(JSON.parse_string(JSON.stringify(details.serialize_state())))
	details._spawn_visual(third)
	_expect(details._records[third].node == null and drops._loose.is_empty(), "displacement persists with no items")
	for failure in failures: push_error(failure)
	print(category.to_upper() + "_PILOT_", "PASS" if failures.is_empty() else "FAIL", ": ", failures)
	quit(0 if failures.is_empty() else 1)


func _season(season: String) -> void:
	clock_node.restore_state({"year":1,"season":season,"day":1,"hour":12,"speed":1,"paused":false})
