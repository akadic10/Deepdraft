extends SceneTree

## Regression from the reported seed/ladder/zone, without player save files.
## The closest valid stand is an isolated cliff shelf, while the top is reachable.
var failures: Array[String] = []

func _init() -> void:
	run.call_deferred()

func expect(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func run() -> void:
	create_timer(120).timeout.connect(func(): push_error("Mining ledge test timed out"); quit(1))
	var clock = root.get_node("WorldClock")
	clock.set_process(false)
	clock.set_paused(true)
	root.get_node("SaveManager").set_process(false)
	var tasks = root.get_node("TaskManager")
	tasks.set_process(false)
	var scene = load("res://scenes/main/debug_world.tscn").instantiate()
	scene.get_node("Renderer").world_seed = 3912970522
	# Scene owners discover their camera during _ready; provide a current
	# scene while the deterministic, preconfigured world enters the tree.
	var holder := Node3D.new()
	root.add_child(holder)
	current_scene = holder
	holder.add_child(scene)
	var generator = root.get_node("WorldGenerator")
	while not bool(generator.get_streaming_stats().get("maps_ready",false)):
		await process_frame
	# Allow flora and terrain callbacks to settle before probing or capturing.
	for i in range(100): await process_frame
	var nav = root.get_node("NavGrid")
	var ladders = get_first_node_in_group("ladders")
	ladders.restore_state({"next_id":2,"routes":[{"id":1,
		"key":"base:furniture:crude_ladder","base":[415,35,575],"yaw":3,
		"height":8,"built":8,"mode":"ready","progress":0.0}]})
	var mining = scene.get_node("MiningDesignationController")
	var selected: Array[Vector3i] = []
	for x in range(419,423):
		for z in range(576,584): selected.append(Vector3i(x,43,z))
	var zone_id: int = mining._create_zone(selected)
	var source = tasks.get_work_source(zone_id)
	var factory = load("res://scripts/entities/DwarfFactory.gd").new()
	var workers: Array = []
	for i in range(5):
		var worker = factory.spawn(factory.generate(i,{}),i)
		scene.add_child(worker)
		worker.position = Vector3(410.5-i,36,570.5)
		worker.set_process(false)
		tasks.register_dwarf(worker)
		workers.append(worker)
	await process_frame
	var worker = workers[0]
	var start: Vector3i = worker.current_cell()
	var nearest: Vector3i = source.nearest_stand_target(start)
	expect(nearest == Vector3i(419,39,575),"fixture retains the isolated nearest shelf")
	expect(nav.find_path(start,nearest).is_empty(),"closest stand is disconnected")
	expect(not nav.find_path(start,Vector3i(418,43,576)).is_empty(),"ladder reaches the upper work floor")
	nav._path_cache.clear()
	# Exact work positions must not succeed merely by reaching a nearby rung.
	var exact := {}
	var result: int = nav.ProbeResult.SEARCHING
	while result == nav.ProbeResult.SEARCHING:
		result = nav.advance_reachability(exact,start,nearest,17,Time.get_ticks_usec()+100000,false)
	expect(result == nav.ProbeResult.UNREACHABLE,"exact shelf probe rejects the isolated work position")
	var alternatives := {nearest:true, Vector3i(418,43,576):true}
	result = nav.ProbeResult.SEARCHING
	while result == nav.ProbeResult.SEARCHING:
		result = nav.advance_reachability(exact,start,nearest,17,Time.get_ticks_usec()+100000,false,alternatives)
	expect(result == nav.ProbeResult.REACHABLE and exact.path.back() == Vector3i(418,43,576),
		"adding alternative exact goals restarts the proof and reaches the upper stand")
	expect(int(exact.expanded) <= nav.DEFAULT_MAX_NODES+nav.APPROACH_PROBE_NODES,
		"alternatives share one bounded search")
	nav._path_cache.clear()
	clock.set_paused(false)
	var saved_cap: int = tasks._probe_node_cap
	tasks._probe_node_cap = 1
	for i in range(8):
		tasks._run_scheduler()
		await process_frame
	for task in tasks._tasks.values():
		expect(task.blocked_count == 0 and task.retry_at == 0,"failed first shelf does not back off the zone")
	tasks._probe_node_cap = saved_cap
	var climbed := false
	var captured := false
	var first_assignment_nodes := -1
	for i in range(1800):
		var before: int = nav._nodes_expanded_total
		tasks._run_scheduler()
		if first_assignment_nodes < 0 and worker.current_task_id >= 0:
			first_assignment_nodes = nav._nodes_expanded_total-before
			expect(worker._move_path.back().y == 43,"execution keeps the proven upper-floor approach")
			expect(first_assignment_nodes < 1200,"assignment reuses proof instead of retrying full failed shelf paths")
		for dwarf in workers:
			dwarf._process(.2)
			climbed = climbed or (dwarf.current_cell().y == 43 and dwarf._task_phase == dwarf.TaskPhase.ZONE_SWINGING)
		if climbed and not captured and DisplayServer.get_name() != "headless":
			var rig = scene.get_node("CameraRig")
			rig.set_process(false)
			var camera := Camera3D.new()
			scene.add_child(camera)
			camera.current = true
			camera.global_position = Vector3(393,69,553)
			camera.look_at(Vector3(418,39,576))
			camera.projection = Camera3D.PROJECTION_ORTHOGONAL
			camera.size = 37
			for frame in range(4): await process_frame
			await RenderingServer.frame_post_draw
			DirAccess.make_dir_recursive_absolute("res://tmp/ladder_mining_live")
			root.get_texture().get_image().save_png("res://tmp/ladder_mining_live/seeded_mining.png")
			captured = true
		if source.remaining_count() == 0: break
		await process_frame
	expect(climbed,"miners climb the real seeded cliff without DEV Walk")
	expect(source.remaining_count() == 0,"all 32 designated blocks are mined")
	print("MINING_LEDGE_RESULT remaining=",source.remaining_count()," assignment_nodes=",first_assignment_nodes)
	for failure in failures: push_error(failure)
	print("MINING_LEDGE_ACCESS_OK" if failures.is_empty() else "MINING_LEDGE_ACCESS_FAIL")
	quit(0 if failures.is_empty() else 1)
