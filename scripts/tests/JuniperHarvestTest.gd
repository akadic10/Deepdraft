extends "res://scripts/tests/TreeFellingTest.gd"

const BERRY := "base:resources:flora:juniper_berry"
const MATURE := Vector2i(40, 40)
const ANCIENT := Vector2i(52, 40)
var details: Node3D
var far: Node3D
var receipt: Dictionary = {}


func _run() -> void:
	create_timer(90).timeout.connect(func(): push_error("Juniper harvest timed out"); quit(1))
	_setup_fixture()
	if "--capture" in OS.get_cmdline_user_args(): _capture_environment()
	root.get_node("StockpileManager").set_process(false)
	_season("summer")
	var tree := _spawn_tree("juniper", "mature", MATURE)
	_spawn_tree("juniper", "ancient", ANCIENT)
	_spawn_tree("juniper", "sapling", Vector2i(64, 40))
	_spawn_tree("oak", "mature", Vector2i(72, 40))
	_spawn_tree("apple", "mature", Vector2i(80, 40))
	_expect(flora.get_explorer_data(MATURE).rows[1][1] == "Out of season", "summer shows out of season instead of N/A")
	_expect(flora.get_explorer_data(Vector2i(64,40)).rows[1][1] == "Too young", "saplings cannot bear fruit")
	_expect(not flora.designate_harvest(MATURE), "out-of-season orders rejected")
	_expect(String(flora._trees[MATURE].model_path).ends_with("_picked.glb"), "summer hides ripe berry accents")
	_season("autumn")
	_expect(flora.get_explorer_data(MATURE).rows[1][1] == "Ready to harvest", "autumn crop ready")
	_expect(flora.get_explorer_data(MATURE).rows[2][1] == "Autumn", "inspector shows authored season")
	_expect(not flora.designate_harvest(Vector2i(64,40)) and not flora.designate_harvest(Vector2i(72,40))
		and not flora.designate_harvest(Vector2i(80,40)), "saplings, oak and future apple harvesting are excluded")
	far = _worker(301, Vector3i(32,20,40))
	worker = _worker(302, Vector3i(39,20,40))
	explorer.select_object(flora, MATURE)
	explorer._perform_action("harvest")
	var source = flora._felling_sources[MATURE]
	var lease: int = source.lease_id
	flora.designate_harvest(MATURE)
	_expect(source.lease_id == lease and source.task_type == Task.Type.HARVEST_TREE and source.duration == 3,
		"one priority-configured hand-picking lease, with JSON duration")
	_expect(not flora.designate_felling(MATURE), "felling cannot replace an active harvest")
	_expect(await _until_working(), "near worker reaches tree side")
	_expect(worker.current_task_id == lease and far.current_task_id < 0, "near worker wins over older distant idle worker")
	_expect(not is_instance_valid(worker._felling_pose.axe) or not worker._felling_pose.axe.visible, "harvest uses hands without an axe")
	worker._process(.5)
	var partial: float = source.state.work_seconds
	clock_node.set_paused(true)
	worker._process(3)
	_expect(source.state.work_seconds == partial, "paused harvest preserves progress")
	clock_node.set_paused(false)
	clock_node.set_speed(2)
	worker._process(.1)
	_expect(is_equal_approx(source.state.work_seconds, partial + .2), "harvest follows speed")
	clock_node.set_speed(1)
	partial = source.state.work_seconds
	worker.dev_force_interrupt()
	_expect(source.reserved_by < 0 and source.state.work_seconds == partial, "interruption releases worker and preserves crop work")
	flora.cancel_felling(MATURE)
	_expect(flora.designate_felling(MATURE), "cancelled harvest permits felling")
	_expect(flora._tree_changes[MATURE].work_seconds == 0, "harvest progress never counts as chopping")
	flora.cancel_felling(MATURE)
	flora.designate_harvest(MATURE)
	_expect(flora._tree_changes[MATURE].work_seconds == partial, "switching back preserves same-crop work")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(flora.serialize_state()))
	flora.restore_state(saved)
	_expect(JSON.parse_string(JSON.stringify(flora.serialize_state())) == saved, "active fruit work round-trips without reservations")
	_expect(await _until_working(), "restored harvest resumes")
	if "--capture" in OS.get_cmdline_user_args(): await _capture_juniper("picking")
	var body: Node3D = flora._trees[MATURE].node
	var occupancy: int = flora._trees[MATURE].occupancy_id
	source = flora._felling_sources[MATURE]
	_expect(await _until_harvested(MATURE), "worker completes crop")
	_expect(_berries() == 2, "mature tree yields exactly two berries")
	_expect(flora._trees[MATURE].node == body and flora._trees[MATURE].occupancy_id == occupancy,
		"harvesting preserves collision body and occupancy")
	_expect(String(flora._trees[MATURE].model_path).ends_with("_picked.glb"), "harvest swaps only berry-free art")
	_expect(flora.get_explorer_data(MATURE).rows[1][1] == "Picked this season", "inspector records picked crop")
	_expect(not flora.designate_harvest(MATURE) and not source.advance_work(worker.dwarf_id, 100), "repeat requests and stale completions cannot duplicate fruit")
	for item: Node3D in drops._loose:
		if drops._loose[item] == BERRY:
			_expect(root.get_node("NavGrid").is_walkable(Vector3i(floori(item.position.x),20,floori(item.position.z))), "berry crate is on accessible ground outside the solid trunk")
	if "--capture" in OS.get_cmdline_user_args(): await _capture_juniper("picked")
	saved = JSON.parse_string(JSON.stringify(flora.serialize_state()))
	flora._despawn_column(Vector2i(2,2))
	flora.restore_state(saved)
	_spawn_tree("juniper", "mature", MATURE)
	_expect(not flora.can_harvest_tree(MATURE) and _berries() == 2, "reload/streaming cannot refresh or replay fruit")
	_expect(String(flora._trees[MATURE].model_path).ends_with("_picked.glb"), "streamed tree retains picked art")
	_season("autumn", 2)
	_expect(flora.can_harvest_tree(MATURE), "changing year renews a crop")
	clock_node.restore_state({"season":"autumn", "year":1, "paused":false})
	_expect(not flora.can_harvest_tree(MATURE) and String(flora._trees[MATURE].model_path).ends_with("_picked.glb"),
		"same-season clock restoration refreshes saved crop visuals for its year")
	flora.designate_harvest(ANCIENT)
	worker.position = Vector3(51.5,21,40.5)
	_expect(await _until_working(), "ancient tree uses its larger footprint")
	worker._process(.7)
	_season("winter")
	_expect(worker.current_task_id < 0 and not flora._felling_sources.has(ANCIENT), "season end cancels active harvest safely")
	_season("autumn", 2)
	flora.designate_harvest(ANCIENT)
	_expect(flora._tree_changes[ANCIENT].work_seconds == 0, "next year's crop starts fresh work")
	_expect(await _until_harvested(ANCIENT), "ancient crop completes next autumn")
	_expect(_berries() == 6 and flora.can_harvest_tree(MATURE), "ancient yields four; mature crop renews next year")
	await _mixed_orders()
	flora.cancel_felling(ANCIENT)
	flora.designate_felling(MATURE)
	worker.position = Vector3(39.5,21,40.5)
	var fruit_before := _berries()
	_expect(await _until_felled(MATURE), "harvested tree can later be felled normally")
	_expect(_item_count("base:resources:wood:juniper_log") == 4 and _berries() == fruit_before, "felling grants wood, with no extra berry crop")
	for message: String in failures: push_error(message)
	print("JUNIPER_HARVEST_OK" if failures.is_empty() else "JUNIPER_HARVEST_FAIL: %s" % str(failures))
	quit(0 if failures.is_empty() else 1)


func _mixed_orders() -> void:
	details = load("res://scripts/systems/SurfaceDetailManager.gd").new()
	scene.add_child(details)
	details.set_process(false)
	details._initialized = true
	details.register_record({"id":"elderberry:test", "definition":"base:flora:elderberry_bush", "origin":Vector3i(43,20,44), "variant":0, "yaw":0})
	details._spawn_visual("elderberry:test")
	chop._details = details
	chop.order_created.connect(func(value: Dictionary): receipt = value)
	dock.tool_requested.emit("harvest_plants")
	_aim_above(Vector3(42,21,42))
	await process_frame
	var trunk: Node3D = flora._trees[MATURE].node
	_expect(chop.designate_at_screen(camera.unproject_position(trunk.position + Vector3.UP)), "Harvest plants click accepts juniper")
	_expect(chop.order_is_pending(receipt) and chop.undo_order(receipt) == 1, "single-tree harvest supports undo")
	# Exercise the real ground-rectangle commit with both owners inside it.
	chop._dragging = true
	chop._box_select = true
	chop._anchor = Vector3i(38,20,38)
	var endpoint := camera.unproject_position(Vector3(46,21.02,47))
	chop._finish_drag(endpoint)
	_expect(receipt.has("trees") and receipt.has("stones") and chop.order_is_pending(receipt), "mixed rectangle creates one receipt for shrubs and junipers")
	chop.inspect_order(receipt)
	_expect(explorer._provider == flora, "View order can inspect the tree in a mixed harvest")
	_expect(chop.undo_order(receipt) == 2 and not chop.order_is_pending(receipt), "mixed Undo cancels both owners")
	flora.designate_harvest(MATURE)
	details.designate_detail("elderberry:test", "harvest_plants")
	dock.tool_requested.emit("cancel_orders")
	chop._dragging = true
	chop._box_select = true
	chop._drag_start = Vector2.ZERO
	chop._finish_drag(Vector2(root.size))
	_expect(not flora._tree_changes[MATURE].designated and not details._changes["elderberry:test"].designated, "Cancel orders includes tree and shrub harvests")
	chop.deactivate()


func _worker(id: int, cell: Vector3i) -> Node3D:
	var factory = load("res://scripts/entities/DwarfFactory.gd").new()
	var agent = factory.spawn(factory.generate(id, {}), id)
	scene.add_child(agent)
	agent.position = Vector3(cell) + Vector3(.5,1,.5)
	agent.set_process(false)
	tasks.register_dwarf(agent)
	return agent


func _season(value: String, year := 1) -> void:
	clock_node.year = year
	clock_node.season = value
	clock_node.season_changed.emit(value)
	for id: Vector2i in flora._trees: flora._refresh_tree_crop_visual(id)


func _berries() -> int:
	var count := 0
	for item: Node3D in drops._loose:
		if drops._loose[item] == BERRY: count += int(item.get_meta("quantity", 1))
	return count


func _until_harvested(id: Vector2i) -> bool:
	for i in range(1500):
		tasks._run_scheduler()
		worker._process(.1)
		if String(flora._tree_changes.get(id, {}).get("harvested_cycle", "")) == flora._fruit_cycle(): return true
		if i % 30 == 0: await process_frame
	return false


func _capture_juniper(label: String) -> void:
	var tree: Node3D = flora._trees[MATURE].node
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 23
	camera.position = tree.position + Vector3(-13,16,18)
	camera.look_at(tree.position + Vector3(-2,5,0))
	explorer.select_object(flora, MATURE)
	explorer._refresh_selected()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tmp/juniper_harvest_review/" + label + ".png")


func _capture_environment() -> void:
	var floor_node := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(128,128)
	floor_node.mesh = mesh
	floor_node.position = Vector3(64,21,64)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("79916b")
	floor_node.material_override = material
	scene.add_child(floor_node)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55,-25,0)
	light.shadow_enabled = true
	scene.add_child(light)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("809196")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = .6
	scene.add_child(env)
