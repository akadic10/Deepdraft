extends SceneTree
## Native QA using a scheduled opportunity in an isolated profile. No player
## save is loaded or changed. The time jump/empty capacity are test fixtures.
var failures: Array[String] = []
var output := "res://tmp/arrival_review/"
var species := "rabbit"

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	if "--deer" in OS.get_cmdline_user_args(): species = "deer"
	if "--wolf" in OS.get_cmdline_user_args(): species = "wolf"
	if species != "rabbit": output = "res://tmp/herd_arrival_review/"
	if not OS.get_environment("APPDATA").replace("\\", "/").contains(output.trim_prefix("res:/")):
		printerr("Use isolated APPDATA below "+output)
		quit(2)
		return
	root.get_node("SaveManager").configure_storage_for_testing("user://arrival_preview")
	var clock_node := root.get_node("WorldClock")
	clock_node.set_paused(true)
	clock_node.set_process(false)
	var scene: Node = load("res://scenes/main/debug_world.tscn").instantiate()
	scene.get_node("Renderer").world_seed = 1234
	var publish := func(node):
		if node == scene: current_scene = scene
	node_added.connect(publish)
	root.add_child(scene)
	node_added.disconnect(publish)
	var wildlife := scene.get_node("WildlifeManager")
	var events := scene.get_node("WorldEventDirector")
	var deadline := Time.get_ticks_msec()+120000
	while not wildlife.arrival_ready() and Time.get_ticks_msec() < deadline: await process_frame
	_check(wildlife.arrival_ready(), "native world and wildlife finish loading")
	if not wildlife.arrival_ready(): quit(1); return
	wildlife.set_process(false)
	events.set_process(false)
	events.initialize_schedule()
	var group_size: int = {"rabbit": 3, "deer": 4, "wolf": 2}[species]
	for i in range(group_size): wildlife.remove_animal(wildlife.animals_of_species(species).back(), "test")
	var before_count: int = wildlife.animals_of_species(species).size()
	events.schedules[species+"_arrival"].next.merge({"due": clock_node.elapsed_days(), "roll": 0.0, "count": group_size, "seed": "875323"}, true)
	clock_node.set_paused(false)
	for i in range(64):
		events.advance(.001)
		if wildlife.animals_of_species(species).size() > before_count: break
	clock_node.set_paused(true)
	var dock := scene.get_node("DockUI")
	var explorer := scene.get_node("ObjectExplorerController")
	var rig := scene.get_node("CameraRig")
	dock._dispatch_panel_action("wildlife", "DEV: Next arrival" if species == "rabbit" else "DEV: Next "+species+" arrival")
	var rabbit: Node3D = explorer._object_id
	_check(is_instance_valid(rabbit) and not rabbit.arrival.is_empty(), "development locator selects a new arrival")
	if not is_instance_valid(rabbit): quit(1); return
	for i in range(150): await process_frame
	_check(explorer._provider == wildlife and rabbit.activity == "Arriving", "shared explorer shows arriving wildlife")
	var box: AABB = wildlife.get_explorer_bounds(rabbit)
	var picked := false
	for x in range(2, 9):
		for y in range(2, 9):
			var screen := root.get_camera_3d().unproject_position(box.position+box.size*Vector3(x/10.0, y/10.0, .5))
			var hit: Dictionary = explorer.pick_at_screen(screen)
			if hit.get("provider") == wildlife and hit.get("id") == rabbit: picked = true
	_check(picked, "boundary arrival is pickable on screen")
	await _shot("arrival_entry")
	wildlife.perform_explorer_action(rabbit, "follow")
	_check(rig.is_following(rabbit), "camera follows an arrival")
	clock_node.set_paused(false)
	for i in range(150):
		wildlife.advance(.1, [])
		events.advance(.1)
	clock_node.set_paused(true)
	for i in range(90): await process_frame
	explorer._refresh_selected()
	await _shot("arrival_journey")
	_check(not events.history.is_empty() and events.history.back().count == group_size, "complete group enters through the natural corridor")
	clock_node.set_paused(false)
	for i in range(500): wildlife.advance(.1, [])
	clock_node.set_paused(true)
	for i in range(90): await process_frame
	explorer._refresh_selected()
	_check(rabbit.arrival.status == "Settled", "arrival settles in natural inland habitat")
	if species == "deer":
		# Low-angle study below the tall tree canopy; behavior, terrain and herd
		# positions stay untouched. Follow has already been verified above.
		var study := Camera3D.new()
		scene.add_child(study)
		study.current = true
		study.fov = 50
		for offset: Vector3 in [Vector3(9, 3, -7), Vector3(-9, 3, -7), Vector3(9, 3, 7), Vector3(-9, 3, 7)]:
			study.global_position = rabbit.position+offset
			study.look_at(rabbit.position+Vector3(0, 1.6, 0))
			await process_frame
			var screen := study.unproject_position(wildlife.get_explorer_bounds(rabbit).get_center())
			if explorer.pick_at_screen(screen).get("id") == rabbit: break
	dock._dispatch_panel_action("world_events", "DEV: Arrival status")
	await _shot("arrival_settled")
	print(species.to_upper()+"_ARRIVAL_LIVE_PREVIEW_OK" if failures.is_empty() else species.to_upper()+"_ARRIVAL_LIVE_PREVIEW_FAILED")
	root.get_node("WorldGenerator").prepare_for_world_reload()
	quit(0 if failures.is_empty() else 1)

func _shot(label: String) -> void:
	for i in range(4): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output+(species+"_" if species != "rabbit" else "")+label+".png")

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)
