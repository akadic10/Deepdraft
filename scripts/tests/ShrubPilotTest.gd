extends "res://scripts/tests/BoulderPilotTest.gd"

const BLUE := "blueberry:1234:1:1"
const ELDER := "elderberry:1234:1:1"
const STRAW := "wild_strawberry:1234:1:1"


func _run() -> void:
	create_timer(90).timeout.connect(func(): push_error("Shrub test timed out"); quit(1))
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
	var ids := [BLUE, ELDER, STRAW]
	for i in range(3):
		var species := String(ids[i]).get_slice(":", 0)
		details.register_record({"id": ids[i], "definition": "base:flora:%s_bush" % species,
			"origin": Vector3i(40+i*6,20,40), "variant": 0, "yaw": 0, "habitat": "fixture"})
		details._spawn_visual(ids[i])
		_expect(details._records[ids[i]].occupancy < 0 and details._records[ids[i]].node.find_children("*", "CollisionShape3D", true, false).is_empty(), "shrubs are single-tile logical plants without colliders")
		_expect(root.get_node("NavGrid").is_walkable(Vector3i(40+i*6,20,40)), "shrubs remain walkable")
		for season: String in ["spring", "summer", "autumn", "winter"]:
			_season(season)
			details._spawn_visual(ids[i])
			var bounds: AABB = details.get_explorer_bounds(ids[i])
			_expect(is_equal_approx(bounds.position.y, 21) and bounds.size.y <= [2,3,1][i], "every seasonal model is grounded and within authored height")
			_expect(details._records[ids[i]].model_path.contains(season), "each season selects its own voxel asset")
	_season("summer")
	for id: String in ids: details._spawn_visual(id)
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
	_expect(explorer.select_object(details,BLUE), "ordinary explorer selects shrubs")
	_expect(details.get_explorer_data(BLUE).actions.size() == 4, "ripe plant offers harvest, move, uproot and clear actions")
	_expect(not details.accepts_tool(BLUE,"clear_stones") and not details.accepts_tool(ELDER,"harvest_plants"), "tools reject wrong categories and out-of-season crops")
	explorer._perform_action("harvest")
	var source: RefCounted = details._sources[BLUE]
	_expect(source.task_type == Task.Type.HARVEST_SHRUB and source.duration == 3, "harvest uses configured adjacent work")
	_expect(not details.designate_detail(BLUE,"clear_shrubs"), "clearing cannot silently replace a harvest order")
	var factory = load("res://scripts/entities/DwarfFactory.gd").new()
	worker = factory.spawn(factory.generate(101, {}),101)
	scene.add_child(worker)
	worker.position = Vector3(34.5,21,40.5)
	worker.set_process(false)
	tasks.register_dwarf(worker)
	_expect(await _until_working(), "real worker routes to harvest")
	_expect(load("res://scripts/components/DwarfInspection.gd").describe(worker).activity == "Harvesting berries", "worker inspector names harvest")
	if "--capture" in OS.get_cmdline_user_args(): await _capture_shrubs()
	worker._process(.6)
	var partial := float(source.state.work_seconds)
	clock_node.set_paused(true)
	worker._process(2)
	_expect(source.state.work_seconds == partial, "pause freezes harvest")
	clock_node.set_paused(false)
	worker.dev_force_interrupt()
	_expect(source.reserved_by == -1 and source.state.work_seconds == partial, "interrupt preserves harvest work and releases claim")
	details.cancel_clearing(BLUE)
	details.designate_detail(BLUE,"clear_shrubs")
	_expect(details._sources[BLUE].task_type == Task.Type.CLEAR_SHRUB and details._changes[BLUE].work_seconds == 0, "clearing keeps separate progress")
	details.cancel_clearing(BLUE)
	details.designate_detail(BLUE,"harvest_plants")
	_expect(details._changes[BLUE].work_seconds == partial, "returning to harvest restores its partial work")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(details.serialize_state()))
	# Scene owners restore before WorldClock: a temporary winter must not cancel
	# the saved summer job. The final restored clock decides availability.
	_season("winter")
	details.restore_state(saved)
	_expect(details._sources.size() == 1, "owner restore does not use transient clock to cancel a job")
	_season("summer")
	_expect(JSON.parse_string(JSON.stringify(details.serialize_state())) == saved, "active partial crop state round-trips")
	_expect(await _until_working(), "restored harvest resumes through scheduler")
	for i in range(45):
		worker._process(.1)
		if not details._sources.has(BLUE): break
	_expect(_berry_count("blueberry") == 3 and not details._changes[BLUE].removed, "harvest yields three berries and keeps plant")
	_expect(not details.designate_detail(BLUE,"harvest_plants"), "same crop cannot be harvested twice")
	details._spawn_visual(BLUE)
	_expect(details._records[BLUE].model_path.ends_with("summer_picked.glb"), "harvesting visibly removes berries")
	var picked: Dictionary = JSON.parse_string(JSON.stringify(details.serialize_state()))
	details.restore_state(picked)
	_season("summer")
	_expect(not details.accepts_tool(BLUE,"harvest_plants") and _berry_count("blueberry") == 3, "load and duplicate season signal cannot refresh crop or reward")
	_season("autumn")
	_expect(details.designate_detail(ELDER,"harvest_plants"), "elderberry becomes ripe in autumn")
	_expect(await _until_working(), "worker reaches elderberry")
	worker._process(.4)
	_season("winter")
	_expect(not details._sources.has(ELDER) and worker.current_task_id == -1 and details._changes[ELDER].work_seconds > 0, "season end cancels active harvest safely and keeps progress")
	_season("autumn",2)
	details.designate_detail(ELDER,"harvest_plants")
	_expect(await _until_working(), "elderberry harvest resumes in eligible season")
	for i in range(40): worker._process(.1)
	_expect(_berry_count("elderberry") == 4, "elderberry yields four fruit")
	for season: String in ["spring", "summer"]:
		_season(season,3)
		_expect(details.designate_detail(STRAW,"harvest_plants"), "strawberries have one crop in each of spring and summer")
		_expect(await _until_working(), "worker reaches strawberry patch")
		for i in range(40): worker._process(.1)
	_expect(_berry_count("wild_strawberry") == 6, "two strawberry seasons yield six fruit total")
	for cutting: String in ["blueberry_cutting", "elderberry_cutting", "strawberry_cutting"]:
		_expect(_cutting_count(cutting) == 0, "berry harvest never produces a cutting")
	_expect(details.accepts_tool(BLUE,"harvest_plants"), "blueberry regrows next year")
	details.designate_detail(BLUE,"clear_shrubs")
	_expect(await _until_working(), "worker reaches permanent clearing")
	for i in range(30): worker._process(.1)
	_expect(details._changes[BLUE].removed and _berry_count("blueberry") == 3, "permanent clearing removes plant without granting berries")
	details.restore_state(JSON.parse_string(JSON.stringify(details.serialize_state())))
	_season("summer",4)
	details._spawn_visual(BLUE)
	_expect(details._records[BLUE].node == null, "cleared plant never regrows on load or next season")
	details.designate_detail(ELDER,"clear_shrubs")
	world.set_block(46,20,40,blocks.AIR_ID)
	_expect(details._changes[ELDER].removed and not details._sources.has(ELDER), "support excavation removes shrub and its order")
	var handle: int = root.get_node("PlacedEntityRegistry").register_box(Vector3i(52,21,40),Vector3i(1,3,1))
	_expect(details._changes[STRAW].removed, "committed construction displaces shrubs")
	root.get_node("PlacedEntityRegistry").unregister(handle)
	await _test_cuttings()
	for failure in failures: push_error(failure)
	print("SHRUB_PILOT_", "PASS" if failures.is_empty() else "FAIL", ": ", failures)
	quit(0 if failures.is_empty() else 1)


func _season(season: String, year := 1) -> void:
	clock_node.restore_state({"year": year, "season": season, "day": 1, "hour": 12, "speed": 1, "paused": false})


func _berry_count(species: String) -> int:
	var total := 0
	for node in drops._loose:
		if is_instance_valid(node) and drops.item_key_of(node) == "base:resources:flora:" + species: total += drops.quantity_of(node)
	return total


func _cutting_count(cutting: String) -> int:
	var total := 0
	for node in drops._loose:
		if is_instance_valid(node) and drops.item_key_of(node) == "base:resources:seed:" + cutting: total += drops.quantity_of(node)
	return total


func _test_cuttings() -> void:
	# All plants now yield one cutting, including positions that failed at 20/25%.
	# Keep these outcomes stable through cancellations, season changes and loads.
	var fixtures := [
		["blueberry", "blueberry_cutting", Vector3i(39,20,46)],
		["blueberry", "blueberry_cutting", Vector3i(32,20,46)],
		["elderberry", "elderberry_cutting", Vector3i(39,20,51)],
		["elderberry", "elderberry_cutting", Vector3i(32,20,51)],
		["wild_strawberry", "strawberry_cutting", Vector3i(32,20,56)],
		["wild_strawberry", "strawberry_cutting", Vector3i(35,20,56)]]
	_season("winter",4)
	for i in range(fixtures.size()):
		var fixture: Array = fixtures[i]
		var id := "%s:1234:cutting:%d" % [fixture[0], i]
		details.register_record({"id": id, "definition": "base:flora:%s_bush" % fixture[0], "origin": fixture[2], "variant": 0, "yaw": 0, "habitat": "fixture"})
		details._spawn_visual(id)
		_expect(String(details.get_explorer_data(id).details).contains("100% chance"), "inspector shows guaranteed cutting chance")
		var before := _cutting_count(fixture[1])
		details.designate_detail(id,"clear_shrubs")
		_expect(await _until_working(), "worker reaches cutting fixture")
		worker._process(.4)
		var partial: float = details._changes[id].work_seconds
		details.cancel_clearing(id)
		_expect(_cutting_count(fixture[1]) == before, "cancelled clearing never grants a cutting")
		details.designate_detail(id,"clear_shrubs")
		details.restore_state(JSON.parse_string(JSON.stringify(details.serialize_state())))
		_expect(details._changes[id].work_seconds == partial, "partial clearing survives load")
		if i == 0: _season("spring",5) # Change appearance between the partial and final work.
		_expect(await _until_working(), "restored cutting work resumes")
		for step in range(30): worker._process(.1)
		var expected := before + 1
		_expect(details._changes[id].removed and _cutting_count(fixture[1]) == expected, "guaranteed single cutting for " + id)
		_expect(not details._complete_shrub(101,id), "duplicate completion callback cannot grant another cutting")
		details.restore_state(JSON.parse_string(JSON.stringify(details.serialize_state())))
		_expect(_cutting_count(fixture[1]) == expected and not details.designate_detail(id,"clear_shrubs"), "removed plant stays removed without replaying cutting drops")
		_season("winter",5)
	# Displacement is not worker clearing and never grants the guaranteed reward.
	for index in range(2):
		var id := "blueberry:1234:displaced:%d" % index
		var origin := Vector3i(39,20,46)
		details.register_record({"id": id, "definition": "base:flora:blueberry_bush", "origin": origin, "variant": 0, "yaw": 0, "habitat": "fixture"})
		details.designate_detail(id,"clear_shrubs")
		var before := _cutting_count("blueberry_cutting")
		if index == 0:
			world.set_block(origin.x,origin.y,origin.z,blocks.AIR_ID)
			world.set_block(origin.x,origin.y,origin.z,blocks.get_id("base:terrain:rock:rock01"))
		else:
			var handle: int = root.get_node("PlacedEntityRegistry").register_box(origin+Vector3i.UP, Vector3i(1,3,1))
			root.get_node("PlacedEntityRegistry").unregister(handle)
		_expect(details._changes[id].removed and not details._sources.has(id) and _cutting_count("blueberry_cutting") == before, "support/construction displacement never drops cuttings")
	_expect(drops._missing_models.is_empty(), "all cutting crates have valid models")
	# Restore actual item quantities, then exercise the established Seeds & cuttings filter.
	var saved_items: Dictionary = JSON.parse_string(JSON.stringify(drops.serialize_state()))
	var quantities: Array = [_cutting_count("blueberry_cutting"), _cutting_count("elderberry_cutting"), _cutting_count("strawberry_cutting")]
	root.get_node("StockpileManager").reset_runtime_state()
	drops.free()
	drops = load("res://scripts/systems/ItemDropManager.gd").new()
	scene.add_child(drops)
	drops.restore_state(saved_items)
	var storage = root.get_node("StockpileManager")
	storage.set_process(false)
	storage._process(.3)
	var zone = load("res://scripts/components/StockpileZoneComponent.gd").new()
	var cells: Array[Vector3i] = [Vector3i(46,20,54),Vector3i(47,20,54),Vector3i(48,20,54)]
	zone.setup(502,cells)
	zone.filter_tags.assign(["stockpile_seed"])
	storage.register_zone(zone)
	var cutting_names := ["blueberry_cutting", "elderberry_cutting", "strawberry_cutting"]
	for i in range(3): _expect(_cutting_count(cutting_names[i]) == quantities[i], "cutting quantities round-trip through item saves")
	for step in range(2400):
		storage._process(.3)
		tasks._run_scheduler()
		worker._process(.1)
		if storage.get_total("base:resources:seed:"+cutting_names[0]) == quantities[0] and storage.get_total("base:resources:seed:"+cutting_names[1]) == quantities[1] and storage.get_total("base:resources:seed:"+cutting_names[2]) == quantities[2]: break
		if step % 30 == 0: await process_frame
	for i in range(3): _expect(storage.get_total("base:resources:seed:"+cutting_names[i]) == quantities[i], "worker hauls cutting crates into Seeds & cuttings storage")
	_expect(_berry_count("blueberry") == 3 and _berry_count("elderberry") == 4 and _berry_count("wild_strawberry") == 6, "clearing and seed storage leave berries unchanged")
	worker.dev_force_interrupt()
	storage.deregister_zone(zone)


func _capture_shrubs() -> void:
	root.size = Vector2i(1680,1000)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(.26,.33,.36)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = .65
	scene.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50,-30,0)
	sun.shadow_enabled = true
	scene.add_child(sun)
	for spec in [[Vector3(43,20.5,40),Vector3(32,1,20)], [Vector3(38,21.5,43),Vector3.ONE]]:
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = spec[1]
		mesh.mesh = box
		mesh.position = spec[0]
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(.5,.62,.46) if spec[1].x > 1 else Color(.55,.58,.61)
		mesh.material_override = material
		scene.add_child(mesh)
	camera.position = Vector3(57,33,56)
	camera.look_at(Vector3(44,21.6,40))
	explorer._window.position = Vector2(24,130)
	worker._carry_pose.gather(.5, worker._fell_contact)
	details._update_markers()
	for i in range(8): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tmp/shrub_review/worker_scale.png")
