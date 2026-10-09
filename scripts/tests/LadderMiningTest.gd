extends "res://scripts/tests/MiningAnimationTest.gd"

var nav
var mine_zone: int

func _run() -> void:
	create_timer(90).timeout.connect(func(): push_error("Ladder mining timed out"); quit(1))
	await _setup_mining_fixture()
	nav = root.get_node("NavGrid")
	if not nav.ladder_routes_changed.is_connected(tasks.ladder_routes_changed):
		nav.ladder_routes_changed.connect(tasks.ladder_routes_changed)
	var rock: int = blocks.get_id("base:terrain:rock:rock01")
	# A wide upper plateau with two offset sixteen-block ladders, like the
	# reported natural ledge. Broad lower ground exposes probe search limits.
	var chunk_script = load("res://scripts/systems/Chunk.gd")
	for cx in range(3,7):
		for cz in range(7):
			for cy in range(1,4):
				var chunk = chunk_script.new()
				for x in range(16):
					for z in range(16):
						for y in range(16):
							var top := 36 if cx*16+x == 48 else 52
							if cy*16+y <= 20 or (cz*16+z >= 8 and cy*16+y <= top):
								chunk.blocks[x+16*z+256*y] = rock
				world.submit_chunk(cx,cy,cz,chunk)
	await process_frame
	nav.set_ladder(101,Vector3i(47,20,48),16,Vector3i.RIGHT,.45)
	nav.set_ladder(102,Vector3i(48,36,48),16,Vector3i.RIGHT,.45)
	worker.position = Vector3(35.5,21,59.5)
	var selected: Array[Vector3i] = []
	for x in range(50,54):
		for z in range(48,60): selected.append(Vector3i(x,52,z))
	mine_zone = mining._create_zone(selected)
	var source = tasks.get_work_source(mine_zone)
	var target: Vector3i = source.nearest_stand_target(worker.current_cell())
	var before: int = nav._nodes_expanded_total
	var path: Array[Vector3i] = nav.find_path(worker.current_cell(),target)
	print("LADDER_MINING_PATH: target=",target," length=",path.size()," expansions=",nav._nodes_expanded_total-before)
	_expect(not path.is_empty(),"DEV walk/full path reaches the upper mining stand")
	before = nav._nodes_expanded_total
	print("LADDER_MINING_PROBE: ",nav.probe_reachable(worker.current_cell(),target,tasks._probe_node_cap)," expansions=",nav._nodes_expanded_total-before," cap=",tasks._probe_node_cap)
	nav._path_cache.clear() # The scheduler must work without a warm DEV path.
	await _check_probe_continuation(target)
	if DisplayServer.get_name() != "headless": _build_capture_scene()
	var saved_cap: int = tasks._probe_node_cap
	tasks._probe_node_cap = 7
	for i in range(20):
		tasks._run_scheduler()
		await process_frame
	_expect(worker.current_task_id < 0 and not tasks._work_probe.is_empty(), "small slices preserve a pending assignment search")
	var progress: int = tasks._work_probe.route_query.expanded
	world.set_block(100,60,100,rock)
	await process_frame
	await process_frame
	tasks._run_scheduler()
	_expect(int(tasks._work_probe.get("route_query", {}).get("expanded",0)) > progress, "unrelated terrain edits preserve pending search progress")
	for task in tasks._tasks.values():
		_expect(task.blocked_count == 0 and task.retry_at == 0, "unfinished search never marks a reachable zone blocked")
	tasks._probe_node_cap = saved_cap
	var started := false
	var captured := false
	var assignment_wakes := 0
	for i in range(900):
		tasks._run_scheduler()
		if worker.current_task_id < 0: assignment_wakes += 1
		worker._process(.1)
		if not captured and DisplayServer.get_name() != "headless" and worker._climbing and worker.position.y > 40:
			await _capture_ladder_mining("automatic_climb")
			captured = true
		if worker._task_phase == worker.TaskPhase.ZONE_SWINGING:
			started = true
			break
		await process_frame
	_expect(started and worker.current_cell().y == 52,"ordinary mining assignment climbs both ladders without a DEV walk")
	print("LADDER_MINING_ASSIGNMENT_WAKES: ",assignment_wakes)
	if started and DisplayServer.get_name() != "headless":
		worker._process(.2)
		camera.position = Vector3(34,65,77)
		camera.look_at(Vector3(49,49,55))
		camera.size = 25
		await _capture_ladder_mining("automatic_mining")
	for i in range(300):
		worker._process(.1)
		if source.remaining_count() < 48: break
		await process_frame
	_expect(source.remaining_count() < 48, "automatic climber actually commits mined blocks")
	mining._remove_zone(mine_zone)
	for failure: String in failures: push_error(failure)
	print("LADDER_MINING_OK" if failures.is_empty() else "LADDER_MINING_FAIL")
	quit(0 if failures.is_empty() else 1)

func _check_probe_continuation(target: Vector3i) -> void:
	var query := {}
	var from: Vector3i = worker.current_cell()
	var status: int = nav.advance_reachability(query,from,target,17,Time.get_ticks_usec()-1)
	_expect(status == nav.ProbeResult.SEARCHING and int(query.expanded) == 0, "expired time budget yields without claiming unreachable")
	for i in range(400):
		var previous: int = query.expanded
		status = nav.advance_reachability(query,from,target,17,Time.get_ticks_usec()+100000)
		_expect(int(query.expanded)-previous <= 17, "resumed probe honors its node slice")
		if status != nav.ProbeResult.SEARCHING: break
	_expect(status == nav.ProbeResult.REACHABLE and int(query.expanded) > tasks._probe_node_cap, "multiple slices prove the complete tall-ladder route")
	world.set_block(48,44,48,blocks.get_id("base:terrain:rock:rock01"))
	await process_frame
	await process_frame
	_expect(not nav.search_is_current(query), "terrain in the climbing clearance invalidates route proof")
	world.set_block(48,44,48,blocks.AIR_ID)
	await process_frame
	await process_frame
	for i in range(400):
		status = nav.advance_reachability(query,from,target,100,Time.get_ticks_usec()+100000)
		if status != nav.ProbeResult.SEARCHING: break
	_expect(status == nav.ProbeResult.REACHABLE, "cleared climbing column restores the route")
	var registry = root.get_node("PlacedEntityRegistry")
	var obstruction: int = registry.register_box(Vector3i(48,44,48),Vector3i.ONE)
	_expect(not nav.search_is_current(query), "occupied climbing clearance invalidates route proof")
	registry.unregister(obstruction)
	# Removing the upper ladder invalidates even a completed positive query.
	var revision: int = query.revision
	nav.remove_ladder(102)
	status = nav.advance_reachability(query,from,target,17,Time.get_ticks_usec()+100000)
	_expect(int(query.revision) != revision and int(query.expanded) <= 17 and status == nav.ProbeResult.SEARCHING, "removed ladder discards stale route proof")
	for i in range(400):
		status = nav.advance_reachability(query,from,target,100,Time.get_ticks_usec()+100000)
		if status != nav.ProbeResult.SEARCHING: break
	_expect(status == nav.ProbeResult.UNREACHABLE and int(query.expanded) <= nav.DEFAULT_MAX_NODES + nav.APPROACH_PROBE_NODES, "missing upper section remains unreachable with a bounded full search")
	# A failed mining gate must wake as soon as construction connects the route.
	for i in range(400):
		tasks._run_scheduler()
		if tasks._tasks.values().any(func(task): return task.blocked_count > 0): break
		await process_frame
	_expect(worker.current_task_id < 0 and tasks._tasks.values().any(func(task): return task.blocked_count > 0), "missing ladder backs off mining without assigning a worker")
	nav.set_ladder(102,Vector3i(48,36,48),16,Vector3i.RIGHT,.45)
	for task in tasks._tasks.values():
		_expect(task.retry_at == 0, "completed ladder wakes mining immediately")
		# Counts describe previous failures; clear only for the pending-slice assertion.
		task.blocked_count = 0

func _build_capture_scene() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("788b98")
	for spec in [[Vector3(50,20.5,52),Vector3(70,1,70)],
			[Vector3(48.5,29,50),Vector3(1,16,44)], [Vector3(59,37,50),Vector3(20,32,44)]]:
		var mesh := MeshInstance3D.new()
		mesh.mesh = BoxMesh.new()
		mesh.mesh.size = spec[1]
		mesh.position = spec[0]
		mesh.material_override = material
		scene.add_child(mesh)
	var loader = load("res://scripts/systems/FurniturePlacementController.gd").new()
	loader._load_defs()
	var def: Dictionary = loader.get_defs()["base:furniture:crude_ladder"]
	for base in [Vector3i(47,20,48),Vector3i(48,36,48)]:
		var route := Node3D.new()
		scene.add_child(route)
		route.position = Vector3(base)+Vector3(.5,1,.5)
		route.rotation.y = PI*1.5
		for offset in range(0,16,4):
			var model: Node3D = load(def.ladder.models["4"]).instantiate()
			model.position.y = offset
			route.add_child(model)
			loader._apply_material(model,loader._make_solid_material())
	loader.free()
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("607282")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_energy = .7
	scene.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40,-40,0)
	light.shadow_enabled = true
	scene.add_child(light)
	camera = Camera3D.new()
	scene.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.position = Vector3(18,65,87)
	camera.look_at(Vector3(48,37,50))
	camera.size = 47
	camera.current = true
	root.size = Vector2i(1280,900)

func _capture_ladder_mining(label: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tmp/ladder_mining_review/"+label+".png")
