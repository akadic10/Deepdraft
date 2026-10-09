extends "res://scripts/tests/TreeFellingTest.gd"

## Real task scheduler, dwarf, picking, occupancy, drops and JSON persistence.
## The flat fixture isolates clearing from worldgen; the companion layout test
## checks generated habitat and seed/order independence on real terrain maps.
var details
const DETAIL_ID := "boulder:1234:1:1"


func _run() -> void:
	create_timer(90).timeout.connect(func(): push_error("Boulder test timed out"); quit(1))
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
	var record := {"id": DETAIL_ID, "definition": "base:detail:boulder", "origin": Vector3i(40,20,40), "variant": 0, "yaw": 0, "habitat": "fixture"}
	details.register_record(record)
	details._spawn_visual(DETAIL_ID)
	for i in range(1, 3):
		var other := record.duplicate()
		other.id = "boulder:1234:1:%d" % (i + 1)
		other.origin = Vector3i(40 + i * 6,20,40)
		other.variant = i
		details.register_record(other)
		details._spawn_visual(other.id)
	explorer = load("res://scripts/ui/ObjectExplorerController.gd").new()
	explorer.window_manager_path = NodePath("../Windows")
	scene.add_child(explorer)
	camera = Camera3D.new()
	scene.add_child(camera)
	camera.current = true
	root.size = Vector2i(1280, 800)
	root.get_node("WorldGenerator")._maps_ready = true
	_aim_above(Vector3(41,21,41))
	await process_frame
	var bounds: AABB = details.get_explorer_bounds(DETAIL_ID)
	_expect(bounds.position.y == 21 and bounds.size.y <= 2 and bounds.size.x <= 2 and bounds.size.z <= 2, "baked boulder bounds are grounded inside the logical envelope")
	_expect(not root.get_node("NavGrid").is_walkable(Vector3i(40,20,40)), "logical boulder blocks navigation")
	_expect(root.get_node("NavGrid").is_walkable(Vector3i(39,20,40)), "adjacent work floor remains walkable")
	_expect(details._records[DETAIL_ID].node.collision_layer == 2, "physics does not obstruct camera terrain mask")
	var hit: Dictionary = details.pick_explorer_object(bounds.get_center() + Vector3.UP * 10, bounds.get_center() - Vector3.UP * 3)
	_expect(hit.get("id", "") == DETAIL_ID, "exact imported mesh is selectable")
	_expect(explorer.select_object(details, DETAIL_ID), "shared inspector accepts boulders")
	explorer._perform_action("clear")
	var source: RefCounted = details._sources[DETAIL_ID]
	var lease: int = source.lease_id
	details.designate_clearing(DETAIL_ID)
	_expect(source.lease_id == lease, "repeated designation does not duplicate jobs")
	var factory = load("res://scripts/entities/DwarfFactory.gd").new()
	worker = factory.spawn(factory.generate(101, {}), 101)
	scene.add_child(worker)
	worker.position = Vector3(34.5,21,40.5)
	worker.set_process(false)
	tasks.register_dwarf(worker)
	_expect(await _until_working(), "scheduler and dwarf route to a boulder work side")
	_expect(source.is_work_position(worker.current_cell()), "work starts outside occupied stone")
	var inspection = load("res://scripts/components/DwarfInspection.gd")
	_expect(inspection.describe(worker).activity == "Breaking a boulder" and inspection.roster_state(worker).summary == "Clearing stone", "dwarf inspector and roster describe stone clearing")
	_expect(worker._mining_pose.pickaxe != null and worker._mining_pose.pickaxe.visible, "clearing equips pickaxe")
	worker._process(1.0)
	var partial := float(source.state.work_seconds)
	_expect(partial > 0 and partial < source.duration, "worker accumulates saved work")
	clock_node.set_paused(true)
	worker._process(2)
	_expect(float(source.state.work_seconds) == partial, "pause freezes work")
	clock_node.set_paused(false)
	worker.dev_force_interrupt()
	_expect(source.reserved_by == -1 and float(source.state.work_seconds) == partial, "interrupt releases ownership and retains progress")
	_expect(not worker._mining_pose.pickaxe.visible, "interrupt stows pick")
	_expect(await _until_working(), "interrupted boulder job resumes")
	worker.dev_make_tired()
	worker._process(.1)
	_expect(worker.is_sleeping() and source.reserved_by == -1, "sleep releases boulder ownership")
	_expect(is_equal_approx(source.state.work_seconds, partial), "sleep retains work")
	worker._wake_up()
	_expect(await _until_working(), "boulder clearing resumes after waking")
	if "--capture" in OS.get_cmdline_user_args(): await _capture_boulders()
	explorer._perform_action("cancel")
	_expect(worker.current_task_id == -1 and not details._sources.has(DETAIL_ID), "cancel aborts worker and source")
	_expect(is_equal_approx(details._changes[DETAIL_ID].work_seconds, partial), "cancellation keeps work")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(details.serialize_state()))
	details.restore_state(saved)
	_expect(JSON.parse_string(JSON.stringify(details.serialize_state())) == saved, "cancelled progress round trips")
	details.designate_clearing(DETAIL_ID)
	var designated: Dictionary = JSON.parse_string(JSON.stringify(details.serialize_state()))
	details.restore_state(designated)
	_expect(details._sources.size() == 1, "designated restore creates exactly one lease")
	_expect(await _until_working(), "restored work resumes through scheduler")
	for i in range(120):
		worker._process(.1)
		if details._changes[DETAIL_ID].removed: break
	_expect(details._changes[DETAIL_ID].removed and details._records[DETAIL_ID].occupancy < 0, "completion tombstones and frees occupancy")
	_expect(root.get_node("NavGrid").is_walkable(Vector3i(40,20,40)), "cleared floor immediately becomes walkable")
	_expect(_item_count("base:resources:stone:rough_stone") == 2, "completion yields exactly two rough stones")
	var removed: Dictionary = JSON.parse_string(JSON.stringify(details.serialize_state()))
	details.restore_state(removed)
	details._spawn_visual(DETAIL_ID)
	_expect(details._records[DETAIL_ID].node == null and _item_count("base:resources:stone:rough_stone") == 2, "restore does not resurrect stone or replay loot")
	var support_id := "boulder:1234:1:2"
	details.designate_clearing(support_id)
	_expect(await _until_working(), "second boulder can be reached after clearing first")
	world.set_block(46,20,40,blocks.AIR_ID)
	_expect(details._changes[support_id].removed and details._records[support_id].occupancy < 0, "excavation removes unsupported stone immediately")
	_expect(worker.current_task_id == -1 and not details._sources.has(support_id), "support loss cancels active work and releases worker")
	world.set_block(46,20,40,blocks.get_id("base:terrain:rock:rock01"))
	details._spawn_visual(support_id)
	_expect(details._records[support_id].node == null, "replacing support never resurrects removed detail")
	var remaining := "boulder:1234:1:3"
	var final_record: Dictionary = details._records[remaining]
	var final_node: Node3D = final_record.node
	root.get_node("WorldClock").season_changed.emit("winter")
	_expect(final_record.node == final_node and final_record.occupancy >= 0, "season changes preserve stone identity and occupancy")
	details.apply_slice(19)
	_expect(details.get_explorer_bounds(remaining).size == Vector3.ZERO, "slice conceals elevated detail")
	_expect(not root.get_node("NavGrid").is_walkable(Vector3i(52,20,40)), "hidden visual retains navigation occupancy")
	details.apply_slice(127)
	var occ := root.get_node("PlacedEntityRegistry")
	var walls: Array[int] = []
	for cell: Vector3i in [Vector3i(51,21,40), Vector3i(51,21,41), Vector3i(54,21,40), Vector3i(54,21,41), Vector3i(52,21,39), Vector3i(53,21,39), Vector3i(52,21,42), Vector3i(53,21,42)]:
		walls.append(occ.register_box(cell, Vector3i(1,3,1)))
	details.designate_clearing(remaining)
	for i in range(12): tasks._run_scheduler()
	var blocked_source: RefCounted = details._sources[remaining]
	var blocked_task: Task = tasks.get_task(blocked_source.lease_id)
	_expect(blocked_task.blocked_count > 0 and blocked_source.reserved_by == -1 and blocked_source.state.work_seconds == 0, "unreachable stone retries without phantom progress or reservation")
	occ.unregister(walls.pop_front())
	blocked_task.retry_at = 0
	_expect(await _until_working(), "opening one side makes blocked stone reachable")
	details.cancel_clearing(remaining)
	for handle: int in walls: occ.unregister(handle)
	var structure: int = occ.register_box(Vector3i(52,21,40), Vector3i(2,2,2))
	_expect(details._changes[remaining].removed, "committed structure wins over overlapping detail")
	occ.unregister(structure)
	for failure in failures: push_error(failure)
	print("BOULDER_PILOT_", "PASS" if failures.is_empty() else "FAIL", ": ", failures)
	quit(0 if failures.is_empty() else 1)


func _capture_boulders(output := "res://tmp/boulder_review/pilot.png") -> void:
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
	var floor_mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(32,1,20)
	floor_mesh.mesh = box
	floor_mesh.position = Vector3(43,20.5,40)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(.5,.62,.46)
	floor_mesh.material_override = material
	scene.add_child(floor_mesh)
	camera.position = Vector3(58,36,60)
	camera.look_at(Vector3(44,21.5,40))
	explorer._window.position = Vector2(24,130)
	details._update_markers()
	if tasks.get_task(worker.current_task_id).type == Task.Type.GATHER_SCREE:
		worker._carry_pose.gather(.5, worker._fell_contact)
	else: worker._mining_pose.apply(.92, worker._fell_contact)
	for i in range(8): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output)
