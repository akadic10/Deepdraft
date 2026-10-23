extends "res://scripts/tests/ShrubPilotTest.gd"

const BLUE_KEY := "base:flora:blueberry_bush"
const BLUE_ITEM := "base:resources:plant:blueberry_bush"
var zone_controller


func _run() -> void:
	create_timer(90).timeout.connect(func(): push_error("Transplant test timed out"); quit(1))
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
	gen._cache_block_ids() # Live terrain edits query the baseline even in this flat fixture.
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

	_expect(details.planting_reason(BLUE_KEY, Vector3i(40,20,40)) == "plant_spacing", "existing shrub prevents overlapping placement")
	_expect(not details.planting_reason(BLUE_KEY, Vector3i(45,0,46)).is_empty(), "bedrock rejects planting")
	_expect(details.planting_reason(BLUE_KEY, Vector3i(45,20,46)).is_empty(), "player may choose clear surface ground outside wild habitat")
	details.designate_detail(BLUE,"harvest_plants")
	_expect(await _wait_for(func(): return _berry_count("blueberry") == 3), "worker harvests before move")
	var destination := Vector3i(45,20,46)
	var plan := _move(BLUE,destination)
	_expect(plan > 0 and not details.can_uproot(BLUE), "Move reserves one destination and one uprooting order")
	_expect(await _wait_for(func(): return worker._task_phase == worker.TaskPhase.FELL_WORKING), "worker starts uprooting")
	worker._process(.6)
	var partial: float = details._changes[BLUE].work_seconds
	clock_node.set_paused(true)
	worker._process(2)
	_expect(details._changes[BLUE].work_seconds == partial, "pause freezes uprooting")
	clock_node.set_paused(false)
	furniture.cancel_ghost(plan)
	_expect(not details._changes[BLUE].removed and details._changes[BLUE].work_seconds == partial and not details._changes[BLUE].designated, "cancelling Move before uproot preserves original plant and work")
	plan = _move(BLUE,destination)
	_expect(await _wait_for(func(): return worker._task_phase == worker.TaskPhase.FETCH_TO_GHOST), "worker physically carries exact uprooted plant")
	var cargo: Array = worker.serialize_state().carried_items
	_expect(cargo.size() == 1 and cargo[0].instance_id == BLUE, "carried save keeps the exact plant identity")
	_expect(details._changes[BLUE].packed and _cutting_count("blueberry_cutting") == 0, "uprooting creates no cutting")
	var snapshot: Dictionary = details.serialize_state()
	var plan_snapshot: Dictionary = furniture.serialize_state()
	_expect(plan_snapshot.ghosts[0].plant_id == BLUE, "pending Move saves exact identity")
	worker.force_interrupt()
	_expect(drops.serialize_state().loose.any(func(e): return e.get("instance_id", "") == BLUE), "interruption drops intact shrub at worker feet")
	_expect(drops.nearest_loose_of_key(BLUE_ITEM,destination) == null, "a generic placement or hauler cannot steal the interrupted Move's shrub")
	_season("winter")
	for node: Node3D in drops._loose:
		if String(node.get_meta("instance_id", "")) == BLUE:
			_expect(String(node.get_meta("visual_path", "")).contains("winter"), "packed shrub updates seasonal voxel art")
	_season("summer")
	for task in tasks._tasks.values(): task.retry_at = 0
	_expect(await _wait_for(func(): return worker._task_phase == worker.TaskPhase.FETCH_WORKING), "another lease resumes planting")
	worker._process(.7)
	var progress: float = furniture._ghosts[plan].progress
	worker.force_interrupt()
	_expect(furniture._ghosts[plan].progress >= progress, "planting progress belongs to the plan across release")
	for task in tasks._tasks.values(): task.retry_at = 0
	_expect(await _wait_for(func(): return not furniture._ghosts.has(plan)), "worker completes replanting")
	_expect(details._records[BLUE].origin == destination and not details._changes[BLUE].removed and not details._changes[BLUE].packed, "same mature shrub exists at destination only")
	_expect(not details.accepts_tool(BLUE,"harvest_plants") and _berry_count("blueberry") == 3, "moving a picked bush never refreshes its crop")
	_expect(drops.get_inventory_items().carried.is_empty(), "planting consumes its one physical packed item")
	details.restore_state(JSON.parse_string(JSON.stringify(details.serialize_state())))
	_expect(details._records[BLUE].origin == destination and not details.accepts_tool(BLUE,"harvest_plants"), "saved transplanted position and picked state restore")
	details._spawn_visual(BLUE)
	_expect(details._records[BLUE].node.find_children("*","CollisionShape3D",true,false).is_empty(), "transplanted shrubs remain nonblocking")
	await _test_storage()
	await _test_invalidated_destination()
	await _test_fresh_restore(snapshot,plan_snapshot,cargo)
	await _test_dev_spawns()
	if "--capture" in OS.get_cmdline_user_args(): await _capture_transplants()
	for message: String in failures: push_error(message)
	print("SHRUB_TRANSPLANT_OK" if failures.is_empty() else "SHRUB_TRANSPLANT_FAIL: %s" % str(failures))
	quit(0 if failures.is_empty() else 1)


func _test_dev_spawns() -> void:
	# Exercise the actual Development command and view-centre drop location.
	camera.position = Vector3(37.5,38,45.5)
	camera.look_at(Vector3(37.5,21,36.5))
	dock._stockpile_controller = zone_controller
	var before: int = details._records.size()
	dock._dispatch_command("spawn_bushes")
	_expect(details._records.size()==before+3,"DEV creates one packed bush of each species")
	var identities: Array[String] = []
	for id: String in details._records:
		if details._changes.get(id,{}).get("reason") != "dev_packed_shrub": continue
		identities.append(id)
		_expect(details._changes[id].packed and details._changes[id].removed and details._records[id].node==null,"DEV bush has no duplicate planted visual")
		var item = drops.nearest_loose_of_key(root.get_node("SurfaceDetailRegistry").packed_item(details._records[id].definition,0),Vector3i(37,20,36),{},id)
		_expect(item != null and String(item.get_meta("visual_path","")).contains("packed"),"DEV bush uses actual transport artwork")
	var state: Dictionary = JSON.parse_string(JSON.stringify(details.serialize_state()))
	details.restore_state(state)
	for id: String in identities:
		_expect(details._records.has(id) and details._changes[id].packed,"DEV plant identity survives save/restore")
	var blue := ""
	for id: String in identities:
		if details._records[id].definition==BLUE_KEY: blue=id
	furniture.activate_for(BLUE_KEY,true)
	furniture._hover_cell = Vector3i(36,20,52)
	furniture._hover_valid = furniture._placement_valid(furniture._hover_cell)
	_expect(furniture._hover_valid,"DEV bush can be selected through normal Place catalog")
	furniture._confirm_ghost()
	furniture.deactivate()
	_expect(await _wait_for(func(): return worker._task_phase==worker.TaskPhase.FETCH_TO_GHOST),"dwarf picks up a spawned bush for transport")
	_expect(worker.serialize_state().carried_items.any(func(e): return e.get("instance_id","")==blue),"dwarf carries the DEV bush's persistent identity")
	_expect(await _wait_for(func(): return not details._changes[blue].packed),"dwarf replants spawned bush through normal work")
	_expect(details._records[blue].origin==Vector3i(36,20,52),"spawned bush finishes at requested location")
	dock._dispatch_command("spawn_bushes")
	_expect(details._records.size()==before+6,"repeat DEV spawns allocate fresh identities after restore")


func _move(id: String, target: Vector3i) -> int:
	furniture.begin_shrub_move(id)
	furniture._hover_cell = target
	furniture._hover_valid = furniture._placement_valid(target)
	_expect(furniture._hover_valid, "Move destination is valid")
	var plan: int = furniture._next_ghost_id
	furniture._confirm_ghost()
	return plan


func _wait_for(condition: Callable) -> bool:
	for i in range(1600):
		furniture._process(.1)
		tasks._run_scheduler()
		worker._process(.1)
		if condition.call(): return true
		if i % 30 == 0: await process_frame
	return false


func _test_storage() -> void:
	# Uproot a ripe second species, haul to a real ground stockpile, then
	# replant through ordinary species stock (no exact Move binding).
	_season("autumn")
	details.designate_uproot(ELDER)
	_expect(await _wait_for(func(): return details._changes[ELDER].get("packed",false)), "elderberry uproots in its ripe season")
	var cells: Array[Vector3i] = [Vector3i(50,20,46)]
	var zone = zone_controller._create_zone(cells)
	zone.filter_tags.assign(["stockpile_seed"])
	root.get_node("StockpileManager")._process(1)
	_expect(await _wait_for(func():
		root.get_node("StockpileManager")._process(1)
		return zone.stored_count() == 1), "whole shrub hauls into Seeds & cuttings storage")
	_expect(zone.cell_stacks[cells[0]].instance_id == ELDER, "ground slot preserves identity")
	var saved: Dictionary = zone_controller.serialize_state()
	_expect(saved.zones[0].stacks[0].instance_id == ELDER, "stockpile save keeps plant identity")
	furniture.activate_for("base:flora:elderberry_bush",true)
	furniture._hover_cell = Vector3i(50,20,52)
	furniture._hover_valid = furniture._placement_valid(furniture._hover_cell)
	furniture._confirm_ghost()
	furniture.deactivate()
	_expect(await _wait_for(func(): return not details._changes[ELDER].packed), "Place catalog fetches and replants stored species")
	_expect(zone.stored_count() == 0, "replanting takes the shrub out of the stockpile")
	_expect(details.accepts_tool(ELDER,"harvest_plants"), "previously ripe shrub remains ripe after transplant")


func _test_invalidated_destination() -> void:
	var target := Vector3i(55,20,53)
	var plan := _move(STRAW,target)
	_expect(await _wait_for(func(): return worker._task_phase == worker.TaskPhase.FETCH_TO_GHOST), "strawberry enters physical transport")
	world.set_block(target.x,target.y,target.z,blocks.AIR_ID)
	_expect(await _wait_for(func(): return worker._carried_entries.is_empty()), "lost destination support releases cargo safely")
	_expect(details._changes[STRAW].packed, "invalid planting does not consume shrub")
	furniture.cancel_ghost(plan)
	_expect(drops.serialize_state().loose.any(func(e): return e.get("instance_id", "") == STRAW), "cancelling after uproot leaves stored-placeable shrub")


func _test_fresh_restore(snapshot: Dictionary, plans: Dictionary, cargo: Array) -> void:
	# A new world owner reconstructs changed origins and packed plants without
	# relying on an old node, worker lease or item reservation.
	var restored = load("res://scripts/systems/SurfaceDetailManager.gd").new()
	scene.add_child(restored)
	restored.set_process(false)
	restored._initialized = true
	for id: String in details._records:
		var r: Dictionary = details._records[id]
		restored.register_record({"id":id,"definition":r.definition,"origin":r.generated_origin,"variant":0,"yaw":0})
	restored.restore_state(JSON.parse_string(JSON.stringify(snapshot)))
	_expect(restored._changes[BLUE].packed and restored._records[BLUE].node == null, "fresh restore retains packed tombstone at original site")
	_expect(plans.ghosts[0].plant_id == cargo[0].instance_id and restored._changes[BLUE].harvested_cycle == "1:summer", "cargo, saved Move and crop all refer to the same plant")
	restored.queue_free()


func _capture_transplants() -> void:
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
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(.44,.55,.39)
	ground.material_override = floor_material
	scene.add_child(ground)
	details._spawn_visual(BLUE)
	explorer.select_object(details,BLUE)
	for i in range(8): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tmp/transplant_review/transplanted.png")
	for button: Button in explorer._actions.get_children():
		if button.text == "Move": _click(button.get_global_rect().get_center())
	await process_frame
	_expect(furniture.is_active() and furniture._moving_shrub == BLUE, "actual inspector Move button starts destination picking")
	_click(camera.unproject_position(Vector3(39.5,21,48.5)))
	await process_frame
	_expect(not furniture._ghosts.is_empty() and details._changes[BLUE].designated, "actual ground click commits Move without placing through inspector")
	for plan_id in furniture._ghosts.keys(): furniture.cancel_ghost(plan_id)
	explorer._window.hide()
	dock._window_manager.open("place")
	dock._place_catalog._all_toggle.button_pressed = true
	dock._place_catalog.category = "plants"
	dock._place_catalog.refresh()
	for i in range(8): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tmp/transplant_review/place_plants.png")
	_click(dock._place_catalog._tiles["base:flora:wild_strawberry_bush"].button.get_global_rect().get_center())
	_expect(furniture.active_furniture_key() == "base:flora:wild_strawberry_bush", "actual Plant catalog tile starts replanting preview")
	furniture.deactivate()
