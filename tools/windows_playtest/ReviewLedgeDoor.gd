extends "res://scripts/tests/SaveManagerRoundTripTest.gd"

## Supply a copied save in this review's isolated APPDATA/save_copy directory.
const OUT := "res://tmp/ledge_door_20261013/"
const COPPER := "base:resources:ore:copper"

func _run() -> void:
	if not "/ledge_door_20261013/" in OS.get_user_data_dir().replace("\\", "/"):
		_fail("Ledge review requires isolated APPDATA"); return
	create_timer(240).timeout.connect(func(): _fail("Ledge review timeout"))
	root.size = Vector2i(1600,900)
	_save_manager = root.get_node("SaveManager")
	_world_generator = root.get_node("WorldGenerator")
	_world_clock = root.get_node("WorldClock")
	_save_manager.configure_storage_for_testing("user://save_copy")
	_save_manager.set_process(false)
	var read: Dictionary = _save_manager._read_snapshot("user://save_copy/quicksave.json")
	if not read.get("ok", false): _fail("Copied save invalid"); return
	_world_generator.world_seed = int(read.snapshot.world_seed)
	_world_clock.set_paused(true)
	node_added.connect(func(node: Node):
		if node.name == "Renderer" and node.get_script() != null: node.world_seed = int(read.snapshot.world_seed))
	change_scene_to_file("res://scenes/main/debug_world.tscn")
	await process_frame
	await process_frame
	if not await _wait_for_world_ready(WORLD_TIMEOUT_MSEC): _fail("World timeout"); return
	_save_manager.set_process(true)
	_save_manager.load_finished.connect(func(ok: bool, backup: bool):
		_on_load_finished(ok, backup)
		_world_clock.set_paused(true), CONNECT_ONE_SHOT)
	if not _load_through_dock("load_game") or not await _wait_for_load(LOAD_TIMEOUT_MSEC) or not _load_succeeded:
		_fail("Copied save load failed"); return
	_save_manager.set_process(false)
	_world_clock.set_process(false)
	var tasks = root.get_node("TaskManager")
	var stockpiles = root.get_node("StockpileManager")
	tasks.set_process(false)
	# Finish the normal lazy hookup before manually driving this owner.
	stockpiles._process(0)
	stockpiles.set_process(false)
	var agents: Array = tasks._agents.values().duplicate()
	var worker = agents[0]
	for agent in agents:
		agent.set_process(false)
		tasks.deregister_dwarf(agent.dwarf_id)
	worker.stop_walking()
	worker.position = Vector3(582.5,44,593.5)
	worker.sleep = 1.0
	worker._food.value = 1.0
	for permission in root.get_node("DwarfAssets").work_permissions():
		worker.set_work_permission(permission.id, permission.id == "haul")
	tasks.register_dwarf(worker)
	var rig = current_scene.get_node("CameraRig")
	rig.set_process(false)
	var camera: Camera3D = rig.camera_node
	camera.reparent(current_scene)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.global_position = Vector3(575,80,609)
	camera.look_at(Vector3(580,44,597))
	camera.size = 24
	for i in (300 if DisplayServer.get_name() != "headless" else 2): await process_frame
	var furniture = _owner("furniture")
	furniture.set_process(false)
	var results := {"doors": [], "pickups": []}
	for name in ["door", "log_door_3", "log_door_4"]:
		var key: String = "base:furniture:" + name
		var origin := Vector3i(579,43,599) if name != "log_door_4" else Vector3i(579,43,597)
		furniture.activate_for(key, false)
		furniture._yaw = 0
		furniture._update_hover(true, camera.unproject_position(Vector3(origin) + Vector3(.5,1,.5)))
		var good: bool = furniture._preview != null and furniture._preview.visible and furniture._hover_valid and furniture._hover_cell == origin
		results.doors.append({"key": key, "preview": good, "cell": furniture._hover_cell})
		if not good: _fail("Door preview failed: " + str(results.doors[-1])); return
		await _capture(name)
		furniture.deactivate()
	var drops = _owner("items")
	if drops == null: drops = get_first_node_in_group("item_drop_manager")
	var ores: Array = []
	for node in drops._loose:
		if drops.item_key_of(node) == COPPER: ores.append(node)
	if ores.size() != 3: _fail("Expected three original copper chunks"); return
	var nav = root.get_node("NavGrid")
	var storage = load("res://scripts/components/StorageComponent.gd")
	results.worker = {"cell":worker.current_cell(), "navigable":nav.is_navigable(worker.current_cell()), "types":tasks._types_for(worker), "idle":tasks._idle_dwarves.duplicate()}
	results.access = []
	for ore in ores:
		var stands := []
		for stand in storage.ground_access_cells(drops.item_floor_cell(ore)):
			if nav.is_walkable(stand): stands.append(stand)
		results.access.append({"ore":ore.position, "stands":stands})
	for zone in stockpiles._zones.values():
		if not is_instance_valid(zone.drop_manager): _fail("Review storage not bound"); return
		zone.set_all_accepted(false)
		zone.set_item_accepted(COPPER, true)
	_world_clock.set_speed(1)
	_world_clock.set_paused(false)
	var prior_phase := -1
	for i in 4000:
		for zone in stockpiles._zones.values(): zone.update_leases()
		tasks._run_scheduler()
		worker._process(.04)
		if worker._task_phase == worker.TaskPhase.HAUL_PICKUP and prior_phase != worker._task_phase:
			results.pickups.append({"stand": worker.current_cell(), "ore": worker._handling_item.global_position})
			worker._process(.20)
			await _capture("reach_%d" % results.pickups.size())
		prior_phase = worker._task_phase
		if stockpiles.get_total(COPPER) == 3: break
		await process_frame
	results.stored_copper = stockpiles.get_total(COPPER)
	var report := FileAccess.open(OUT + "copied_save_review.json", FileAccess.WRITE)
	report.store_string(JSON.stringify(results,"\t"))
	if results.stored_copper != 3: _fail("Copper was not delivered: " + str(results)); return
	print("COPIED_SAVE_LEDGE_DOOR_PASS ", results)
	quit()

func _capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + label + ".png")
