extends "res://scripts/tests/ConstructionTest.gd"

const OUT := "res://tmp/construction_hammer_20261017/"

func _frames(count: int) -> void:
	for i in range(count): await process_frame

func _run() -> void:
	create_timer(60).timeout.connect(func(): push_error("Construction presentation timeout"); quit(1))
	await _setup_fixture()
	await _new_trip(STONE,3)
	stockpiles.reset_runtime_state()
	stockpiles._process(0)
	nav = root.get_node("NavGrid")
	root.get_node("WorldGenerator")._cache_block_ids()
	mine = load("res://scripts/systems/MiningDesignationController.gd").new()
	scene.add_child(mine)
	mine.set_process(false)
	construction = load("res://scripts/systems/ConstructionController.gd").new()
	construction.mining = mine
	scene.add_child(construction)
	construction.set_process(false)
	var id: int = construction.create_order(_cells([Vector3i(44,21,40),Vector3i(44,22,40),Vector3i(44,23,40)]))
	var order = construction.orders[id]
	_expect(await _wait_phase(worker.TaskPhase.FETCH_WORKING),"presentation uses a real supplied project and assigned builder")
	if worker._task_phase != worker.TaskPhase.FETCH_WORKING:
		quit(1)
		return
	clock_node.set_paused(true)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("84929c")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = .55
	scene.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	scene.add_child(sun)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 12
	scene.add_child(camera)
	camera.position = Vector3(53,31,32)
	camera.look_at(Vector3(43,22,40))
	camera.current = true
	root.size = Vector2i(1280,900)
	var floor := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(30,1,30)
	floor.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("73885a")
	floor.material_override = material
	floor.position = Vector3(43,20.5,40)
	scene.add_child(floor)
	await _frames(5)
	sun.rotation_degrees = Vector3(-50,-30,0)
	sun.light_energy = 1.2
	environment.environment.fog_enabled = false
	order.materials.tick_site(0,127)
	_expect(order.materials._contents.get_child_count()==3,"crate visibly contains staged stones")
	for mesh in order.materials.visual.find_children("*","MeshInstance3D",true,false):
		_expect(mesh.material_override!=null,"crate and contents have their world materials")
	construction._rebuild_visuals()
	# Opaque reference block makes the strike readable without three overlaid
	# blueprint faces hiding the tool in these close-up animation captures.
	construction._plans.hide()
	var target_mesh := MeshInstance3D.new()
	var target_box := BoxMesh.new()
	target_mesh.mesh = target_box
	var stone_material := StandardMaterial3D.new()
	stone_material.albedo_color = Color("7b858e")
	target_mesh.material_override = stone_material
	scene.add_child(target_mesh)
	target_mesh.position = Vector3(order.target)+Vector3.ONE*.5
	camera.position = worker.global_position+worker.global_basis*Vector3(5,4,7)
	camera.look_at(worker.global_position+Vector3.UP*1.6)
	camera.size = 6
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for phase in [.1,.4,.72,.9]:
		order.progress = phase
		worker._construction_work_pose(order)
		if is_equal_approx(phase,.72):
			var pose = worker._construction_pose
			var point: Vector3 = pose.tool.global_transform*pose.MODEL_POINT
			var intended: Vector3 = worker.ConstructionPose.contact_point(order.target,worker.global_position,worker.global_basis.z)
			_expect(point.distance_to(intended)<.001,"hammer head contacts the actual target face")
			_expect(pose.tool.global_basis.x.normalized().dot(Vector3.DOWN)>.999,"low block is struck squarely from above")
		await _frames(3)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OUT+"hammer_%d.png"%roundi(phase*100))
	var original_target: Vector3i = order.target
	var feet := Vector3i(floori(worker.position.x),floori(worker.position.y),floori(worker.position.z))
	# Check independent surface normals at every approach and reachable height.
	for direction in [Vector3i.LEFT,Vector3i.RIGHT,Vector3i.FORWARD,Vector3i.BACK]:
		for height in [-1,0,1,2]:
			order.target = feet+direction+Vector3i.UP*height
			order.progress = worker.ConstructionPose.CONTACT_PHASE
			worker._construction_work_pose(order)
			var pose = worker._construction_pose
			var normal := Vector3.UP if height<=0 else -Vector3(direction)
			_expect(pose.tool.global_basis.x.normalized().dot(-normal)>.999,"hammer end faces into the surface at every approach/height")
			var point: Vector3 = pose.tool.global_transform*pose.MODEL_POINT
			var intended: Vector3 = worker.ConstructionPose.contact_point(order.target,worker.global_position,worker.global_basis.z)
			_expect(point.distance_to(intended)<.001,"face alignment preserves exact head contact")
			_expect((worker._hand_r.global_transform*pose.PALM).y>worker.global_position.y+.15,"striking grip stays above ground")
			_expect(pose.tool.global_basis.determinant()>0,"mirrored fist does not reflect the hammer")
	order.target = original_target+Vector3i.UP
	target_mesh.position = Vector3(order.target)+Vector3.ONE*.5
	order.progress = worker.ConstructionPose.CONTACT_PHASE
	worker._construction_work_pose(order)
	camera.position = worker.global_position+worker.global_basis*Vector3(8,3,1)
	camera.look_at(worker.global_position+Vector3.UP*1.6)
	await _frames(3)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT+"hammer_raised_block.png")
	order.target = original_target
	order.materials.tick_site(0,19)
	_expect(not order.materials.visual.visible,"slice hides the crate and its contents")
	order.materials.tick_site(0,127)
	_expect(order.materials.visual.visible,"returning slice reveals the crate")
	var hit: Dictionary = construction.pick_explorer_object(Vector3(order.materials.crate_cell)+Vector3(.5,5,.5),Vector3(order.materials.crate_cell)+Vector3(.5,1,.5))
	_expect(hit.get("id",-1)==id,"clicking the temporary crate inspects its project")
	worker.dev_force_interrupt()
	_expect(not worker._construction_pose.tool.visible,"hammer stows on player interruption")
	for failure: String in failures: push_error(failure)
	print("CONSTRUCTION_PRESENTATION_OK" if failures.is_empty() else "CONSTRUCTION_PRESENTATION_FAIL")
	quit(0 if failures.is_empty() else 1)
