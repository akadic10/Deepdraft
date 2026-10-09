extends SceneTree

## Capture the real scene/renderer with generated terrain and flora. No mock mesh.
var _world_seed := 1234


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if not OS.get_environment("APPDATA").replace("\\", "/").contains("/tmp/world_layout_review/"):
		printerr("Use isolated APPDATA below tmp/world_layout_review.")
		quit(2)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="): _world_seed = int(arg.trim_prefix("--seed="))
	root.get_node("SaveManager").configure_storage_for_testing("user://world_layout_preview")
	var scene: Node = load("res://scenes/main/debug_world.tscn").instantiate()
	scene.get_node("Renderer").world_seed = _world_seed
	# Publish the scene during tree entry, before child _ready callbacks look
	# for scene-owned camera/UI nodes (matching normal change_scene ordering).
	var publish_scene := func(node: Node) -> void:
		if node == scene: current_scene = scene
	node_added.connect(publish_scene)
	root.add_child(scene)
	node_added.disconnect(publish_scene)
	var generator := root.get_node("WorldGenerator")
	var renderer: Node = scene.get_node("Renderer")
	var flora: Node = scene.get_node("SurfaceFloraSpawner")
	var deadline := Time.get_ticks_msec() + 120000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if generator._maps_ready and generator._grass_bands_ready and renderer._overview_built and flora._pending.is_empty(): break
	if not generator._maps_ready or not renderer._overview_built:
		printerr("Live preview timed out before terrain rendered.")
		quit(1)
		return
	var clock := root.get_node("WorldClock")
	clock.set_paused(true)
	var camera: Node3D = scene.get_node("CameraRig")
	if Vector2(camera.global_position.x, camera.global_position.z).distance_to(Vector2(camera._default_pos.x, camera._default_pos.z)) > 1.0:
		printerr("Initial camera moved away from its configured position.")
		quit(1)
		return
	if "--diagnostics" in OS.get_cmdline_user_args():
		# Surface metrics finish after the overview can already be displayed.
		while generator.get_generation_metrics().is_empty() and Time.get_ticks_msec() < deadline:
			await process_frame
		if generator.get_generation_metrics().is_empty():
			printerr("Live preview timed out before diagnostics were ready.")
			quit(1)
			return
		var overlay: Node = scene.get_node("DebugLoadingOverlay")
		overlay.visible = true
		overlay._panel.position.y = 80.0 # Review framing: keep the normal HUD clear.
		overlay._update_text()
		await _shot("diagnostics")
		print("WORLD_LAYOUT_DIAGNOSTICS_PREVIEW_PASS seed %d" % _world_seed)
		generator.prepare_for_world_reload()
		quit(0)
		return
	await _shot("initial_view")
	var flag: Node = scene.get_node("FlagPlacementController")
	var selected := Vector3i(-1, -1, -1)
	for cell in range(1024):
		var x := (cell / 32) * 32 + 16
		var z := (cell % 32) * 32 + 16
		var candidate := Vector3i(x, generator.get_surface_y(x, z), z)
		if flag._is_valid_cell(candidate) and root.get_node("NavGrid").is_walkable(candidate):
			selected = candidate
			break
	if selected.y < 0:
		printerr("Could not select a natural flag location for the preview test.")
		quit(1)
		return
	flag._place_flag(selected)
	if scene.get_node("DwarfDirector").get_child_count() != 5:
		printerr("Starter squad did not spawn at the selected natural location.")
		quit(1)
		return
	var peak: Array = generator._macro_layout["metrics"]["summit_center"]
	var target := Vector3((float(peak[0]) + 0.5) * 32.0, 60.0, (float(peak[1]) + 0.5) * 32.0)
	# Wider framing solely for review; actual terrain/materials/flora are unchanged.
	camera.set_process(false)
	camera.global_position = target
	camera.arm_node.rotation_degrees.y = 30.0
	camera.spring_arm.rotation_degrees.x = -50.0
	camera.spring_arm.spring_length = 650.0
	camera.spring_arm.collision_mask = 0
	# Remove distance fog only for the wide review shot so the whole mountain
	# can be inspected beyond the normal play camera's zoom range.
	scene.get_node("WorldEnvironment").environment.fog_enabled = false
	await _shot("mountain")
	# Historical coordinates are used only to review removal of the old clearing.
	# They have no role in generation, flora rules, initial camera or placement.
	var previous_clearings := {1234: Rect2i(256, 896, 96, 96), 65535: Rect2i(480, 320, 96, 96)}
	if previous_clearings.has(_world_seed):
		var area: Rect2i = previous_clearings[_world_seed]
		var tree_count := 0
		for cell: Vector2i in flora._trees:
			if area.has_point(cell): tree_count += 1
		if tree_count == 0:
			printerr("Former clearing has no natural trees in the review seed.")
			quit(1)
			return
		var center := area.get_center()
		camera.global_position = Vector3(center.x, generator.get_surface_y(center.x, center.y), center.y)
		camera.spring_arm.spring_length = 200.0
		await _shot("natural_terrain")
		print("Former clearing: %d naturally generated trees." % tree_count)
	# Close views expose uniform cliffs or rectangular shores hidden by zoom-out.
	var layout: Dictionary = generator._macro_layout
	for body: Dictionary in generator.water_bodies:
		var water_cell := int(body["cells"][0])
		if body["kind"] == "mountain_tarn":
			camera.global_position = Vector3((water_cell / 32) * 32 + 16, float(body["waterline_y"]), (water_cell % 32) * 32 + 16)
			camera.spring_arm.spring_length = 110.0
			camera.arm_node.rotation_degrees.y = 30.0
		else:
			var focus := _cliff_focus(layout, true)
			camera.global_position = focus["position"]
			camera.arm_node.rotation_degrees.y = focus["yaw"]
			camera.spring_arm.spring_length = 110.0
		await _shot(String(body["kind"]))
	var cliff := _cliff_focus(layout, false)
	camera.global_position = cliff["position"]
	camera.arm_node.rotation_degrees.y = cliff["yaw"]
	camera.spring_arm.spring_length = 100.0
	await _shot("lowland_cliff")
	var file := FileAccess.open("res://tmp/world_layout_review/render_%d.json" % _world_seed, FileAccess.WRITE)
	file.store_string(JSON.stringify(generator.get_streaming_stats(), "\t"))
	file.close()
	print("WORLD_LAYOUT_LIVE_PREVIEW_PASS seed %d; starter squad %d; wide shot uses extended zoom without distance fog" % [_world_seed, scene.get_node("DwarfDirector").get_child_count()])
	generator.prepare_for_world_reload()
	quit(0)


func _cliff_focus(layout: Dictionary, water: bool) -> Dictionary:
	for cell in range(1024):
		if layout["water_index"][cell] >= 0: continue
		if layout["ranks"][cell] != (0 if water else 1): continue
		var point := Vector2i(cell / 32, cell % 32)
		for direction: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next := point + direction
			if next.x < 1 or next.y < 1 or next.x >= 31 or next.y >= 31: continue
			var neighbor := next.x * 32 + next.y
			if water and layout["water_index"][neighbor] != 0: continue
			if not water and (layout["ranks"][neighbor] != 0 or layout["water_index"][neighbor] >= 0): continue
			return {"position": Vector3(point.x * 32 + 16 + direction.x * 16, 19, point.y * 32 + 16 + direction.y * 16),
				"yaw": rad_to_deg(atan2(float(direction.x), float(direction.y)))}
	return {"position": Vector3(512, 19, 512), "yaw": 30.0}


func _shot(label: String) -> void:
	for i in range(10): await process_frame
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image().save_png("res://tmp/world_layout_review/live_%d_%s.png" % [_world_seed, label])
	if result != OK: printerr("Screenshot failed: " + error_string(result))
