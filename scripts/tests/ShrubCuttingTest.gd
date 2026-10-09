extends "res://scripts/tests/ShrubTransplantTest.gd"

const CUTTING := "base:flora:blueberry_cutting"
const CUTTING_ITEM := "base:resources:seed:blueberry_cutting"


func _run() -> void:
	_setup_cuttings()
	await process_frame
	clock_node.restore_state({"season":"summer", "year":1,"day":1,"hour":12,"paused":false})
	drops.spawn_drop(CUTTING_ITEM,5,Vector3i(37,21,43))
	var first := _plant_plan(CUTTING,Vector3i(43,20,47))
	_expect(int(furniture.get_catalog_stock()[CUTTING].available) == 4, "one plan reserves one cutting, not the entire five-unit crate")
	var cancelled := _plant_plan(CUTTING,Vector3i(47,20,47))
	furniture.cancel_ghost(cancelled)
	_expect(_cutting_count("blueberry_cutting") == 5, "cancel before pickup leaves the entire crate")
	_expect(await _wait_for(func(): return worker._task_phase == worker.TaskPhase.FETCH_TO_GHOST), "worker carries a cutting")
	_expect(worker.serialize_state().carried_items[0].count == 1 and _cutting_count("blueberry_cutting") == 4, "pickup splits exactly one cutting and leaves four")
	for item: Node3D in drops._loose:
		if drops.item_key_of(item) == CUTTING_ITEM:
			_expect(drops.item_floor_cell(item) == Vector3i(37,20,43), "pickup animation leaves the remainder at its original world position")
	worker.dev_force_interrupt()
	_expect(_cutting_count("blueberry_cutting") == 5, "interruption returns cutting without loss")
	for task in tasks._tasks.values(): task.retry_at = 0
	_expect(await _wait_for(func(): return worker._task_phase == worker.TaskPhase.FETCH_WORKING), "planting resumes")
	worker._process(.6)
	var work: float = furniture._ghosts[first].progress
	worker.dev_force_interrupt()
	_expect(furniture._ghosts[first].progress >= work, "planting progress survives interrupt")
	for task in tasks._tasks.values(): task.retry_at = 0
	_expect(await _wait_for(func(): return not furniture._ghosts.has(first)), "worker finishes first cutting")
	var id := _planted_at(Vector3i(43,20,47))
	_expect(not id.is_empty() and _cutting_count("blueberry_cutting") == 4, "one consumed unit creates one player plant")
	_expect(not details.can_uproot(id) and not details.accepts_tool(id,"harvest_plants"), "young plant cannot be harvested or uprooted")
	details._spawn_visual(id)
	_expect(String(details._records[id].model_path).contains("young_summer"), "new plant has young summer art")
	_expect(details._records[id].node.find_children("*","CollisionShape3D",true,false).is_empty(), "young plants stay nonblocking")
	var cancelled_carry := _plant_plan(CUTTING,Vector3i(58,20,46))
	var transporting := await _wait_for(func(): return worker._task_phase == worker.TaskPhase.FETCH_TO_GHOST)
	_expect(transporting, "second cutting enters transport")
	furniture.cancel_ghost(cancelled_carry)
	_expect(_cutting_count("blueberry_cutting") == 4 and _planted_at(Vector3i(58,20,46)).is_empty(), "cancel while carrying returns one cutting and creates no plant")
	clock_node.set_paused(true)
	var paused_age: float = _age(id)
	clock_node._process(120)
	_expect(is_equal_approx(_age(id),paused_age), "pause freezes growth")
	clock_node.set_paused(false)
	clock_node.advance_hours(24)
	_expect(is_equal_approx(_age(id),1), "fractional noon planting receives exactly one full day after 24 hours")
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(details.serialize_state()))
	var saved_clock: Dictionary = clock_node.serialize_state()
	_expect(JSON.parse_string(JSON.stringify(details.serialize_state())) == snapshot, "saving is observational")
	clock_node.advance_hours(24*10)
	details.restore_state(snapshot) # Owner restores before clock in the real pipeline.
	clock_node.restore_state(saved_clock)
	_expect(is_equal_approx(_age(id),1) and not details.can_uproot(id), "restore never matures a young plant against the old clock")
	_expect(JSON.parse_string(JSON.stringify(details.serialize_state())) == snapshot, "player identities and ages round-trip")
	await _fresh_owner(snapshot,saved_clock,id)
	if "--capture" in OS.get_cmdline_user_args(): await _capture_young(id)
	clock_node.advance_hours(47)
	_expect(not details.can_uproot(id), "young blueberry remains young before three growth days")
	clock_node.advance_hours(1)
	details._spawn_visual(id)
	_expect(details.can_uproot(id) and details.accepts_tool(id,"harvest_plants"), "three summer days unlock mature harvest and move")
	_expect(String(details._records[id].model_path).ends_with("blueberry_summer.glb"), "maturity swaps to full-size seasonal art")
	details.designate_detail(id,"harvest_plants")
	_expect(await _wait_for(func(): return _berry_count("blueberry") == 3), "grown plant gives its first crop")
	var move := _move(id,Vector3i(47,20,47))
	_expect(await _wait_for(func(): return not furniture._ghosts.has(move)), "player-grown mature plant uses Move")
	_expect(not details.accepts_tool(id,"harvest_plants"), "moving grown plant retains picked crop")
	await _other_species()
	for failure: String in failures: push_error(failure)
	print("SHRUB_CUTTING_OK" if failures.is_empty() else "SHRUB_CUTTING_FAIL: %s" % failures)
	quit(0 if failures.is_empty() else 1)


func _plant_plan(key: String, target: Vector3i) -> int:
	furniture.activate_for(key,true)
	furniture._hover_cell = target
	furniture._hover_valid = furniture._placement_valid(target)
	_expect(furniture._hover_valid,"cutting site is valid")
	var id: int = furniture._next_ghost_id
	furniture._confirm_ghost()
	furniture.deactivate()
	return id


func _planted_at(cell: Vector3i) -> String:
	for id: String in details._records:
		if bool(details._records[id].get("player_created",false)) and details._records[id].origin == cell: return id
	return ""


func _age(id: String) -> float:
	var crop = load("res://scripts/components/ShrubSeason.gd")
	return crop.grown_days(root.get_node("SurfaceDetailRegistry").get_definition(details._records[id].definition),details._changes[id])


func _fresh_owner(snapshot: Dictionary, saved_clock: Dictionary, id: String) -> void:
	var restored = load("res://scripts/systems/SurfaceDetailManager.gd").new()
	scene.add_child(restored)
	restored.set_process(false)
	restored._initialized = true
	restored.restore_state(snapshot)
	clock_node.restore_state(saved_clock)
	_expect(restored._records.has(id) and restored._records[id].player_created and not restored.can_uproot(id), "new owner reconstructs planted record without a generated candidate")
	_expect(restored._next_plant_id > int(id.get_slice(":",2)), "new identities cannot reuse a saved plant id")
	restored.queue_free()
	await process_frame


func _other_species() -> void:
	clock_node.restore_state({"season":"winter","year":1,"day":28,"hour":12,"paused":false})
	drops.spawn_drop("base:resources:seed:elderberry_cutting",1,Vector3i(37,21,43))
	var plan := _plant_plan("base:flora:elderberry_cutting",Vector3i(54,20,47))
	_expect(await _wait_for(func(): return not furniture._ghosts.has(plan)), "elderberry cutting plants")
	var elder := _planted_at(Vector3i(54,20,47))
	clock_node.advance_hours(12)
	_expect(clock_node.year == 2 and is_zero_approx(_age(elder)), "winter growth pauses across year rollover")
	clock_node.advance_hours(60)
	_expect(is_equal_approx(_age(elder),3) and not details.can_uproot(elder), "spring multiplier applies and elderberry needs four growth days")
	details.dev_mature_shrub(elder)
	_expect(details.can_uproot(elder) and not details.accepts_tool(elder,"harvest_plants"), "DEV shortcut matures selected plant without granting out-of-season fruit")
	drops.spawn_drop("base:resources:seed:strawberry_cutting",2,Vector3i(37,21,43))
	var cells: Array[Vector3i] = [Vector3i(49,20,53)]
	var zone = zone_controller._create_zone(cells)
	zone.filter_tags.clear()
	zone.filter_items.assign(["base:resources:seed:strawberry_cutting"])
	_expect(await _wait_for(func():
		root.get_node("StockpileManager")._process(1)
		return zone.stored_count() == 2), "cuttings haul to ground stockpile")
	plan = _plant_plan("base:flora:wild_strawberry_cutting",Vector3i(54,20,53))
	_expect(await _wait_for(func(): return not furniture._ghosts.has(plan)), "strawberry uses the existing strawberry cutting key")
	_expect(zone.stored_count() == 1, "planting withdraws just one stored cutting")
	var straw := _planted_at(Vector3i(54,20,53))
	details.designate_clearing(straw)
	_expect(await _wait_for(func(): return details._changes[straw].removed), "young plant can be cleared")
	_expect(_cutting_count("strawberry_cutting") + zone.stored_count() == 2, "young clearing returns exactly its cutting without multiplication")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(details.serialize_state()))
	details.restore_state(saved)
	clock_node.advance_hours(200)
	_expect(details._changes[straw].removed and details._records[straw].node == null, "cleared young shrub never regrows on load or aging")
	var rows: Dictionary = root.get_node("SurfaceDetailRegistry").definitions
	for definition: Dictionary in rows.values():
		if definition.get("kind") != "shrub": continue
		for path: String in definition.young_models.values():
			var model: Node3D = load(path).instantiate()
			_expect(model.scale == Vector3.ONE and model.find_children("*","CollisionShape3D",true,false).is_empty(),"young seasonal art uses baked scale and no colliders")
			model.free()


func _capture_young(id: String) -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55,-30,0)
	scene.add_child(light)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_energy = .8
	scene.add_child(env)
	var ground := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(34,1,30)
	ground.mesh = box
	ground.position = Vector3(46,20.5,43)
	scene.add_child(ground)
	details._spawn_visual(id)
	explorer.select_object(details,id)
	for i in range(8): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tmp/cutting_review/young_inspector.png")
	var before_dev: Dictionary = details.serialize_state()
	var before_clock: Dictionary = clock_node.serialize_state()
	for button: Button in explorer._actions.get_children():
		if button.text == "DEV: Grow to maturity": _click(button.get_global_rect().get_center())
	_expect(details.can_uproot(id) and clock_node.serialize_state() == before_clock, "actual DEV button matures only selected plant without advancing calendar")
	details.restore_state(before_dev)
	clock_node.restore_state(before_clock)
	explorer._window.hide()
	dock._window_manager.open("place")
	dock._place_catalog._all_toggle.button_pressed = true
	dock._place_catalog.category = "plants"
	dock._place_catalog.refresh()
	for i in range(8): await process_frame
	_click(dock._place_catalog._tiles[CUTTING].button.get_global_rect().get_center())
	_expect(furniture.active_furniture_key() == CUTTING,"actual cutting tile starts planting")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tmp/cutting_review/place_cuttings.png")
	furniture.deactivate()
	dock._place_catalog.window.hide()


func _setup_cuttings() -> void:
	create_timer(90).timeout.connect(func(): push_error("Cutting test timed out"); quit(1))
	root.get_node("SaveManager").set_process(false)
	root.get_node("RoomManager").set_process(false)
	clock_node = root.get_node("WorldClock")
	clock_node.set_process(false)
	tasks = root.get_node("TaskManager")
	tasks.set_process(false)
	root.get_node("StockpileManager").set_process(false)
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
	for spec in [[BLUE, BLUE_KEY, Vector3i(40,20,40)], [ELDER, "base:flora:elderberry_bush", Vector3i(48,20,40)], [STRAW, "base:flora:wild_strawberry_bush", Vector3i(52,20,40)]]:
		details.register_record({"id":spec[0], "definition":spec[1], "origin":spec[2], "variant":0,"yaw":0})
		details._spawn_visual(spec[0])
	dock = load("res://scripts/ui/DockUI.gd").new()
	dock.name = "Dock"
	dock.window_manager_path = NodePath("../Windows")
	scene.add_child(dock)
	furniture = load("res://scripts/systems/FurniturePlacementController.gd").new()
	furniture.dock_ui_path = NodePath("../Dock")
	scene.add_child(furniture)
	furniture.set_process(false)
	furniture._process(0)
	zone_controller = load("res://scripts/systems/StockpileDesignationController.gd").new()
	scene.add_child(zone_controller)
	zone_controller.set_process(false)
	var factory = load("res://scripts/entities/DwarfFactory.gd").new()
	worker = factory.spawn(factory.generate(101, {}),101)
	scene.add_child(worker)
	worker.position = Vector3(36.5,21,40.5)
	worker.set_process(false)
	tasks.register_dwarf(worker)
	camera = Camera3D.new()
	scene.add_child(camera)
	camera.current = true
	camera.position = Vector3(55,40,64)
	camera.look_at(Vector3(44,21,43))
	explorer = load("res://scripts/ui/ObjectExplorerController.gd").new()
	explorer.window_manager_path = NodePath("../Windows")
	scene.add_child(explorer)
	root.size = Vector2i(1280,800)
