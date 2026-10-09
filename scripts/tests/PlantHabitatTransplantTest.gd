extends "res://scripts/tests/ShrubMoveHandoffTest.gd"

const FLOWER := "flowers:1234:3:3"
const FLOWER_KEY := "base:detail:flowers"
const FLOWER_CATALOG := "base:detail:flowers_3"
const FLOWER_ITEM := "base:resources:plant:flowers_3"


func _run() -> void:
	create_timer(100).timeout.connect(func(): push_error("Plant habitat test timed out"); quit(1))
	_setup_fixture()
	_test_spacing()
	details.register_record({"id":FLOWER,"definition":FLOWER_KEY,"origin":Vector3i(50,20,50),"variant":2,"yaw":1})
	details._spawn_visual(FLOWER)
	_expect(details.get_explorer_data(FLOWER).actions.map(func(a): return a.id) == ["move","uproot","clear"], "flower inspector offers relocation and permanent clearing")
	worker.position = Vector3(49.5,21,50.5)
	helper.position = Vector3(34.5,21,34.5)
	_expect(details.flower_blooming(FLOWER), "summer clump blooms")
	var target := Vector3i(44,20,47)
	var plan := _move(FLOWER, target)
	_expect(furniture._ghosts[plan].furniture_key == FLOWER_CATALOG, "Move selects exact flower shape catalog")
	_expect(furniture._ghosts[plan].node.get_node_or_null("PlantingArea") != null, "queued plant shows its 3x3 area")
	_expect(details.planting_reason(BLUE_KEY,target + Vector3i(2,0,2)) == "plant_spacing", "pending flower reserves diagonal space against bush")
	_expect(await _advance_until(func(): return worker._task_phase == worker.TaskPhase.FELL_WORKING), "nearest dwarf starts flower uprooting")
	worker._process(.4)
	var work: float = details._changes[FLOWER].work_seconds
	var saved: Dictionary = JSON.parse_string(JSON.stringify(details.serialize_state()))
	_expect(saved.changes.any(func(e): return e.id == FLOWER and e.action == "uproot" and e.work_seconds == work), "flower partial work and action serialize")
	furniture.cancel_ghost(plan)
	_expect(not details._changes[FLOWER].removed and details._changes[FLOWER].work_seconds == work, "cancel before uproot preserves clump and progress")
	_expect(details.planting_reason(BLUE_KEY,target).is_empty(), "cancel releases complete area")
	details.restore_state(saved)
	details.cancel_clearing(FLOWER)
	_expect(details._changes[FLOWER].work_seconds == work, "restored flower work survives release")
	plan = _move(FLOWER,target)
	_expect(await _advance_until(func(): return worker._task_phase == worker.TaskPhase.FETCH_TO_GHOST), "same uprooter carries flower, no distant handoff")
	_expect(helper.current_task_id < 0, "other dwarf remains available")
	_expect(worker.serialize_state().carried_items[0].instance_id == FLOWER, "flower cargo saves stable identity")
	_expect(not details.flower_blooming(FLOWER) and details.flowering_clumps(Vector3(50,21,50),10).is_empty(), "packed flower has no forage")
	worker.dev_force_interrupt()
	var cargo = drops._loose.keys().filter(func(n): return n.get_meta("instance_id", "") == FLOWER)[0]
	_season("winter")
	_expect(String(cargo.get_meta("visual_path")).ends_with("flowers_3_packed_winter.glb"), "interrupted flower keeps variant with dormant packed art")
	for task in tasks._tasks.values(): task.retry_at = 0
	_expect(await _advance_until(func(): return not furniture._ghosts.has(plan)), "flower resumes and replants")
	details._spawn_visual(FLOWER)
	_expect(details._records[FLOWER].origin == target and details._records[FLOWER].variant == 2, "same variant at requested location")
	_expect(not details.flower_blooming(FLOWER), "moving dormant flowers does not trigger bloom")
	_expect(String(details._records[FLOWER].model_path).ends_with("flowers_3_winter.glb"), "planted winter art preserved")
	_expect(details._records[FLOWER].occupancy == -1 and root.get_node("NavGrid").is_walkable(target), "planting area remains walkable")
	await _storage_roundtrip()
	_season("spring")
	_expect(details.flower_blooming(FLOWER), "spring blooms return by season")
	var location: Vector3 = Vector3(details._records[FLOWER].origin) + Vector3(.5,1,.5)
	_expect(details.flowering_clumps(location,.1).size() == 1 and details.flowering_clumps(Vector3(50,21,50),.1).is_empty(), "future forage uses new location only")
	if "--capture" in OS.get_cmdline_user_args(): await _capture_flowers()
	details.designate_clearing(FLOWER)
	_expect(await _advance_until(func(): return details._changes[FLOWER].removed), "flowers still clear permanently")
	_expect(details.flowering_clumps(location,10).is_empty() and drops.serialize_state().loose.is_empty(), "clearing removes forage without a yield")
	for failure: String in failures: push_error(failure)
	print("PLANT_HABITAT_TRANSPLANT_OK" if failures.is_empty() else "PLANT_HABITAT_TRANSPLANT_FAIL: %s" % str(failures))
	quit(0 if failures.is_empty() else 1)


func _test_spacing() -> void:
	var registry = root.get_node("SurfaceDetailRegistry")
	for source_key: String in [BLUE_KEY,"base:flora:elderberry_bush","base:flora:wild_strawberry_bush",FLOWER_KEY]:
		details._records[STRAW].definition = source_key
		for target_key: String in [BLUE_KEY,"base:flora:elderberry_bush","base:flora:wild_strawberry_bush",FLOWER_KEY]:
			for offset in [Vector3i.ZERO,Vector3i(1,0,0),Vector3i(2,0,0),Vector3i(2,0,2),Vector3i(-2,0,-2)]:
				_expect(details.planting_reason(target_key,Vector3i(40,20,40)+offset) == "plant_spacing", "all plant pairs reject overlapping/diagonal areas")
			_expect(details.planting_reason(target_key,Vector3i(43,20,40)).is_empty(), "3-block center spacing allows touching areas")
	details._records[STRAW].definition = "base:flora:wild_strawberry_bush"
	for species: String in [BLUE_KEY,"base:flora:elderberry_bush","base:flora:wild_strawberry_bush"]:
		var def: Dictionary = registry.get_definition(species)
		_expect(def.placement.max_y == 43 and "rock" not in def.placement.ground_kinds, "wild berry habitat ends before mountains and excludes rock")
	# Cuttings reserve mature space from placement, through growth.
	var cutting: String = details.plant_cutting(BLUE_KEY,Vector3i(47,20,35),0)
	_expect(details.planting_reason(FLOWER_KEY,Vector3i(49,20,37)) == "plant_spacing", "young shrub reserves mature area")
	details._remove(cutting,"test_cleanup")
	# Player mountain cultivation is valid on soil, never bare rock.
	for x in range(46,53):
		for z in range(34,39):
			world.set_block(x,91,z,blocks.get_id("base:terrain:surface:grass_01"))
	_expect(details.planting_reason(BLUE_KEY,Vector3i(49,91,36)).is_empty(), "cultivation allowed on mountain grass")
	world.set_block(49,91,36,blocks.get_id("base:terrain:rock:rock01"))
	_expect(details.planting_reason(BLUE_KEY,Vector3i(49,91,36)) == "plant_soil", "cultivation rejects bare rock")
	for x in range(39,42):
		for z in range(39,42): world.set_block(x,91,z,blocks.get_id("base:terrain:surface:grass_01"))
	_expect(details.planting_reason(FLOWER_KEY,Vector3i(40,91,40)).is_empty(), "plant below on another terrain level does not overlap")
	for x in range(39,42):
		for z in range(39,42): world.set_block(x,91,z,blocks.AIR_ID)
	for x in range(46,53):
		for z in range(34,39): world.set_block(x,91,z,blocks.AIR_ID)
	# Pending cutting reserves the same area, including after controller restoration.
	furniture.activate_for("base:flora:blueberry_cutting")
	furniture._hover_cell = Vector3i(47,20,35)
	furniture._confirm_ghost()
	var pending: Dictionary = furniture.serialize_state()
	_expect(details.planting_reason(FLOWER_KEY,Vector3i(49,20,37)) == "plant_spacing", "pending cutting reserves mature area")
	furniture.cancel_ghost(1)
	furniture.restore_state(pending)
	_expect(details.planting_reason(FLOWER_KEY,Vector3i(49,20,37)) == "plant_spacing", "restored pending cutting restores full reservation")
	furniture.cancel_ghost(1)
	furniture.deactivate()


func _storage_roundtrip() -> void:
	details.designate_uproot(FLOWER)
	_expect(await _advance_until(func(): return details._changes[FLOWER].packed), "standalone flower Uproot packs clump")
	var item: Node3D = drops.nearest_loose_of_key(FLOWER_ITEM,Vector3i(44,20,47))
	furniture._install("base:furniture:storage_chest",furniture.get_defs()["base:furniture:storage_chest"],Vector3i(55,20,46),0)
	var chest = furniture._installed.values().back().storage
	chest.drop_manager = drops
	var token = chest._reserve_deposit(FLOWER_ITEM,Vector3i(44,20,47),999,1)
	token["instance_id"] = FLOWER
	drops.take(item)
	chest._commit_one(token,FLOWER_ITEM)
	chest.changed_callback.call(FLOWER_ITEM,1)
	chest._place_visual(item,token)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(details.serialize_state()))
	var furniture_save: Dictionary = JSON.parse_string(JSON.stringify(furniture.serialize_state()))
	var entry: Dictionary = furniture_save.installed.back()
	_expect(entry.instances[0].instance_id == FLOWER, "container save retains exact clump")
	details.restore_state(saved)
	chest.restore_inventory(entry.inventory,drops,entry.instances)
	_expect(details._records[FLOWER].variant == 2 and details._changes[FLOWER].packed and not details.flower_blooming(FLOWER), "saved storage flower preserves identity and dormancy")
	chest.dump_contents(Vector3i(54,20,46))
	furniture.activate_for(FLOWER_CATALOG,true)
	furniture._hover_cell = Vector3i(48,20,46)
	_expect(furniture._placement_valid(furniture._hover_cell), "stored flower destination valid")
	var plan: int = furniture._next_ghost_id
	furniture._confirm_ghost()
	furniture.deactivate()
	_expect(await _advance_until(func(): return not furniture._ghosts.has(plan)), "Place catalog replants stored flower")
	_expect(details._records[FLOWER].origin == Vector3i(48,20,46), "stored flower has one new location")


func _capture_flowers() -> void:
	root.size = Vector2i(1280,800)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55,-30,0)
	light.shadow_enabled = true
	scene.add_child(light)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("465956")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_energy = .7
	scene.add_child(environment)
	var floor_mesh := MeshInstance3D.new()
	var plane := BoxMesh.new()
	plane.size = Vector3(30,.1,30)
	floor_mesh.mesh = plane
	floor_mesh.position = Vector3(47,20.95,44)
	scene.add_child(floor_mesh)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 10
	scene.add_child(camera)
	camera.position = Vector3(52,28,56)
	camera.look_at(Vector3(48,21,46))
	for i in range(3):
		var id := "flowers:1234:art:%d" % i
		details.register_record({"id":id,"definition":FLOWER_KEY,"origin":Vector3i(44+i*3,20,43),"variant":i,"yaw":0})
		details._spawn_visual(id)
	details._spawn_visual(FLOWER)
	furniture.begin_shrub_move(FLOWER)
	furniture._hover_cell = Vector3i(46,20,48)
	furniture._hover_valid = furniture._placement_valid(furniture._hover_cell)
	furniture._position_preview(furniture._hover_cell)
	for i in range(8): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tmp/plant_habitat_review/planting_spacing.png")
	furniture._hover_cell = Vector3i(48,20,44)
	furniture._hover_valid = furniture._placement_valid(furniture._hover_cell)
	_expect(not furniture._hover_valid, "native preview rejects adjacent planted clump")
	furniture._position_preview(furniture._hover_cell)
	for i in range(4): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tmp/plant_habitat_review/planting_spacing_blocked.png")
	furniture.deactivate()
	for id: String in details._records.keys():
		if id.contains(":art:"): details._remove(id,"test_cleanup")
