extends "res://scripts/tests/SaveManagerRoundTripTest.gd"

const OUT := "res://tmp/mining_bed_20261013/"
const BED := "base:furniture:log_bed"

func _run() -> void:
	if not "/mining_bed_20261013/" in OS.get_user_data_dir().replace("\\", "/"):
		_fail("Mining review requires isolated APPDATA"); return
	create_timer(240).timeout.connect(func(): _fail("Mining bed review timeout"))
	root.size = Vector2i(1600,900)
	_save_manager = root.get_node("SaveManager")
	_world_generator = root.get_node("WorldGenerator")
	_world_clock = root.get_node("WorldClock")
	_save_manager.configure_storage_for_testing("user://save_copy")
	_save_manager.set_process(false)
	var read: Dictionary = _save_manager._read_snapshot("user://save_copy/quicksave.json")
	if not read.get("ok",false): _fail("Copied save invalid"); return
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
		_on_load_finished(ok,backup)
		_world_clock.set_paused(true),CONNECT_ONE_SHOT)
	if not _load_through_dock("load_game") or not await _wait_for_load(LOAD_TIMEOUT_MSEC) or not _load_succeeded:
		_fail("Copied save load failed"); return
	_save_manager.set_process(false)
	_world_clock.set_process(false)
	var tasks = root.get_node("TaskManager")
	tasks.set_process(false)
	root.get_node("StockpileManager")._process(0)
	root.get_node("StockpileManager").set_process(false)
	var agents: Array = tasks._agents.values().duplicate()
	var worker = agents[0]
	for agent in agents:
		agent.set_process(false)
		tasks.deregister_dwarf(agent.dwarf_id)
	worker.stop_walking()
	worker.position = Vector3(648.5,44,465.5)
	worker.sleep = 1.0
	worker._food.value = 1.0
	for permission in root.get_node("DwarfAssets").work_permissions():
		worker.set_work_permission(permission.id,permission.id in ["mine","build"])
	tasks.register_dwarf(worker)
	var mining = _owner("mining")
	var furniture = _owner("furniture")
	furniture._process(0)
	furniture.set_process(false)
	var source = mining._zones[1].component
	var results := {"seed":read.snapshot.world_seed,"loaded_faces":source.destination_count(),"remaining":source.remaining_count()}
	# Restore the old bed position in the copied world, then use the real Move
	# order to put it back where the player moved it. Do not touch terrain.
	var bed = furniture._installed[23]
	var material: String = bed.material_id
	furniture._teardown_installed(23,false)
	var old_bed: int = furniture._next_installed_id
	furniture._install(BED,furniture.get_defs()[BED],Vector3i(645,43,461),3,material)
	for i in 4: await process_frame
	results.blocked_faces = source.destination_count()
	if results.blocked_faces!=0: _fail("Reconstructed bed did not obstruct faces: "+str(results)); return
	_world_clock.set_speed(1)
	_world_clock.set_paused(false)
	for i in 3:
		for task_id in source.lease_ids: tasks.get_task(task_id).retry_at=0
		tasks._run_scheduler()
	results.blocked_attempts = 3
	var rig = current_scene.get_node("CameraRig")
	rig.set_process(false)
	var camera: Camera3D = rig.camera_node
	camera.reparent(current_scene)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.global_position = Vector3(638,75,483)
	camera.look_at(Vector3(647,44,465))
	camera.size = 23
	for i in (180 if DisplayServer.get_name()!="headless" else 2): await process_frame
	await _capture("blocked")
	furniture.begin_furniture_move(old_bed)
	furniture._yaw=3
	furniture._hover_cell=Vector3i(642,43,461)
	if not furniture._placement_valid(furniture._hover_cell): _fail("Bed Move destination invalid"); return
	furniture._confirm_ghost()
	furniture.deactivate()
	results.mining_stands = []
	var moved := false
	var captured_work := false
	for i in 5000:
		for ghost in furniture._ghosts.values(): ghost.update_lease()
		tasks._process(.04)
		worker._process(.04)
		if not moved and furniture._ghosts.is_empty():
			moved = true
			results.faces_after_move = source.destination_count()
			await _capture("bed_moved")
		if worker._task_phase==worker.TaskPhase.ZONE_SWINGING and not captured_work:
			results.mining_stands.append(worker.current_cell())
			await _capture("mining")
			captured_work = true
		if moved and not mining._zones.has(1): break
		await process_frame
	results.bed_moved = moved
	results.mining_finished = not mining._zones.has(1)
	results.lifecycle_errors = tasks.lifecycle_errors()
	var world = root.get_node("WorldData")
	results.blocks_removed = world.get_block(646,47,460)==0 and world.get_block(647,47,460)==0
	var report := FileAccess.open(OUT+"copied_save_review.json",FileAccess.WRITE)
	report.store_string(JSON.stringify(results,"\t"))
	await _capture("finished")
	if not moved or not results.mining_finished or not results.blocks_removed or not results.lifecycle_errors.is_empty():
		_fail("Mining bed review failed: "+str(results)); return
	print("COPIED_SAVE_MINING_BED_PASS ",results)
	quit()

func _capture(label: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT+label+".png")
