extends "res://scripts/tests/ShrubMoveHandoffTest.gd"


func _run() -> void:
	create_timer(90).timeout.connect(func(): push_error("Planting animation timed out"); quit(1))
	_setup_fixture()
	if "--capture" in OS.get_cmdline_user_args(): _setup_camera()
	for spec in [[BLUE, BLUE_KEY], [ELDER, "base:flora:elderberry_bush"], [STRAW, "base:flora:wild_strawberry_bush"]]:
		var plan := _new_case(spec[0], spec[1])
		_expect(await _advance_until(func(): return worker._task_phase == worker.TaskPhase.FETCH_WORKING), "worker arrives for planting")
		var ghost = furniture._ghosts[plan]
		var duration: float = ghost.def.planting_seconds
		_expect(is_equal_approx(duration, 1.25), "%s uses the shortened JSON replant duration" % spec[1])
		_expect(is_zero_approx(ghost.progress), "arrival starts the planting sequence without spending hidden work")
		var item: Node3D = worker._fetch_item
		var start: Vector3 = item.global_position
		worker._process(.15)
		_expect(item.global_position.y < start.y - .025, "shrub starts lowering within 150 ms of arrival")
		_expect(worker._foot_l.position.is_zero_approx() and worker._foot_r.position.is_zero_approx(), "planting keeps both boots planted")
		var cargo: Array = worker.serialize_state().carried_items
		_expect(cargo.size() == 1 and cargo[0].instance_id == spec[0], "animated shrub remains saved cargo until final commit")
		await _capture_pose(String(spec[0]).get_slice(":",0) + "_start")
		var progress: float = ghost.progress
		var transform := item.global_transform
		var hand: Transform3D = worker._hand_l.transform
		clock_node.set_paused(true)
		worker._process(3)
		_expect(is_equal_approx(ghost.progress, progress) and item.global_transform.is_equal_approx(transform)
			and worker._hand_l.transform.is_equal_approx(hand), "pause freezes work, cargo and hands together")
		clock_node.set_paused(false)
		clock_node.set_speed(2)
		worker._process(.1)
		_expect(is_equal_approx(ghost.progress, progress + .2), "animation work follows clock speed")
		clock_node.set_speed(1)
		worker._process(duration * .5 - ghost.progress)
		await _capture_pose(String(spec[0]).get_slice(":",0) + "_middle")
		worker._process(duration * .85 - ghost.progress)
		var bounds: AABB = item.global_transform * worker._carry_pose.item_bounds(item)
		var contact: Vector3 = ghost.work_surface()
		_expect(absf(bounds.position.y - contact.y) < .005
			and absf(bounds.get_center().x - contact.x) < .005
			and absf(bounds.get_center().z - contact.z) < .005, "plant settles exactly on its destination ground")
		await _capture_pose(String(spec[0]).get_slice(":",0) + "_release")
		var simulated: float = ghost.progress
		while worker.current_task_id >= 0 and simulated < duration + .5:
			worker._process(.01)
			simulated += .01
			_expect(worker._task_phase != worker.TaskPhase.FETCH_DEPOSIT, "planting never adds a second set-down phase")
		_expect(absf(simulated - duration) < .02 and not furniture._ghosts.has(plan), "planting completes within its single configured duration")
		_expect(details._records[spec[0]].origin == Vector3i(46,20,46) and not details._changes[spec[0]].packed
			and drops.serialize_state().loose.is_empty() and worker._carried_entries.is_empty(), "one shrub is committed, without cargo or duplicate drops")
	await _resume_and_cancel()
	for message: String in failures: push_error(message)
	print("SHRUB_PLANTING_ANIMATION_OK" if failures.is_empty() else "SHRUB_PLANTING_ANIMATION_FAIL: %s" % str(failures))
	quit(0 if failures.is_empty() else 1)


func _resume_and_cancel() -> void:
	var plan := _new_case()
	_expect(await _advance_until(func(): return worker._task_phase == worker.TaskPhase.FETCH_WORKING), "resume fixture reaches planting")
	worker._process(.45)
	var ghost = furniture._ghosts[plan]
	var progress: float = ghost.progress
	worker.dev_force_interrupt()
	_expect(is_equal_approx(ghost.progress, progress) and worker._carried_entries.is_empty(), "interrupt preserves partial work and releases animated cargo")
	for task in tasks._tasks.values(): task.retry_at = 0
	_expect(await _advance_until(func(): return worker._task_phase == worker.TaskPhase.FETCH_WORKING), "worker returns to unfinished planting")
	_expect(is_equal_approx(worker._plant_animation_duration, 1.25 - progress), "resumed reach uses only remaining work")
	var item: Node3D = worker._fetch_item
	var start := item.global_position
	worker._process(.1)
	_expect(item.global_position.y < start.y, "resumed planting animates immediately")
	furniture.cancel_ghost(plan)
	_expect(worker.current_task_id < 0 and worker._carried_entries.is_empty() and drops.serialize_state().loose.size() == 1,
		"cancelling during planting leaves one intact packed shrub")
	_expect(details._changes[STRAW].packed and details._changes[STRAW].removed, "cancellation never creates a planted copy")


func _setup_camera() -> void:
	camera = Camera3D.new()
	scene.add_child(camera)
	camera.current = true
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 7
	camera.position = Vector3(51,27,52)
	camera.look_at(Vector3(45.8,22,46))
	var floor_node := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(32,32)
	floor_node.mesh = mesh
	floor_node.position = Vector3(44,21,44)
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
	root.size = Vector2i(960,720)


func _capture_pose(label: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tmp/shrub_planting_review/" + label + ".png")
