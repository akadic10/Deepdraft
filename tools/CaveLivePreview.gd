extends SceneTree

var _failures: Array[String] = []
var _seed := 1234
var _generator: Node
var _renderer: Node


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if not OS.get_environment("APPDATA").replace("\\", "/").contains("/tmp/world_layout_review/"):
		printerr("Use isolated APPDATA below tmp/world_layout_review.")
		quit(2)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="): _seed = int(arg.trim_prefix("--seed="))
	root.get_node("SaveManager").configure_storage_for_testing("user://cave_live_review")
	var scene: Node = load("res://scenes/main/debug_world.tscn").instantiate()
	scene.get_node("Renderer").world_seed = _seed
	var publish := func(node: Node) -> void:
		if node == scene: current_scene = scene
	node_added.connect(publish)
	root.add_child(scene)
	node_added.disconnect(publish)
	_generator = root.get_node("WorldGenerator")
	_renderer = scene.get_node("Renderer")
	var deadline := Time.get_ticks_msec() + 90000
	while not _generator._grass_bands_ready or not _renderer._overview_built:
		await process_frame
		if Time.get_ticks_msec() > deadline:
			_failures.append("Scene did not finish terrain generation.")
			_finish()
			return
	root.get_node("WorldClock").set_paused(true)
	root.get_node("SaveManager").set_process(false)
	var manager: Node = scene.get_node("UIWindowManager")
	var panel: Node = scene.get_node("CaveDebugPanel")
	var camera: Node = scene.get_node("CameraRig")
	var slice: Node = scene.get_node("SliceController")
	var interior := root.get_node("InteriorTracker")
	var mining: Node = scene.get_node("MiningDesignationController")
	var camera_before: Dictionary = camera.serialize_state()
	var slice_before: Dictionary = slice.serialize_state()
	scene.get_node("DockUI")._toggle_window("caves_dev")
	_expect(manager.is_open("caves_dev"), "Cave explorer is not reachable through the menu route.")
	var catalog: Array = _generator.get_cave_catalog()
	if catalog.is_empty():
		_failures.append("No caves available in rendered world.")
		_finish()
		return
	var chosen := 0
	for i in range(catalog.size()):
		if int(catalog[i]["soil_columns"]) > int(catalog[chosen]["soil_columns"]): chosen = i
	panel._selector.select(chosen)
	panel._select_cave(chosen)
	panel._focus_selected()
	await _settle()
	await _shot("highlight")
	_expect(interior.discovered_cave_count() == 0, "Highlighting discovered a cave.")
	var cave: Dictionary = catalog[chosen]
	var center: Vector3i = cave["center"]
	var hidden: Dictionary = _renderer._overview_visible_surface_after_cut(center.x, center.z)
	_expect(hidden.get("wy", -1) == center.y + 3, "Hidden cave appeared through the normal slice.")
	panel._preview.button_pressed = true
	await _settle()
	await _shot("preview")
	_expect(interior.discovered_cave_count() == 0 and mining._mined_blocks.is_empty(), "Developer preview modified saved world state.")
	var preview: Dictionary = _renderer._overview_visible_surface_after_cut(center.x, center.z)
	_expect(preview.get("wy", -1) == center.y, "Preview did not expose the actual cave floor.")
	manager.close("caves_dev")
	_expect(_renderer._debug_cave_blocks.is_empty(), "Closing preview left cave cuts active.")
	_expect(camera.serialize_state() == camera_before and slice.serialize_state() == slice_before, "Closing explorer did not restore view.")
	# Exercise the real mining notification chain, including discovery, lighting
	# and the removal of now-obsolete designations on hidden cave air.
	var planned: Array[Vector3i] = [center + Vector3i.UP]
	mining._create_zone(planned)
	var first := int(cave["columns"][0])
	var wall := Vector3i(first / 1024 - 1, center.y + 1, first % 1024)
	mining._mine_block_world(wall)
	await _settle()
	_expect(interior.discovered_cave_count() == 1, "Mining did not discover one cave.")
	_expect(not mining._zone_by_block.has(planned[0]), "Discovery left a mining job targeting natural air.")
	_expect(_renderer._discovered_cave_blocks.has(center + Vector3i.UP), "Discovered cave is missing from renderer.")
	_expect(_renderer.underground_lighting._samples.has(center + Vector3i.UP), "Cave interior was not initialized for underground lighting.")
	_expect(float(_renderer.underground_lighting._samples.get(center + Vector3i.UP, 1.0)) < 0.01, "Sealed cave has unexplained daylight.")
	manager.open("caves_dev")
	panel._selector.select(chosen)
	panel._select_cave(chosen)
	panel._focus_selected()
	await _settle()
	await _shot("discovered")
	manager.close("caves_dev")
	_expect(_renderer._debug_cave_blocks.is_empty() and _renderer._discovered_cave_blocks.has(center + Vector3i.UP), "Preview cleanup erased real discovery.")
	_finish()


func _settle() -> void:
	var deadline := Time.get_ticks_msec() + 60000
	for i in range(10): await process_frame
	while (not _renderer._dirty_overview_tiles.is_empty() or _renderer._cavity_shell_dirty or _renderer.underground_lighting.is_updating()) and Time.get_ticks_msec() < deadline:
		await process_frame
	_expect(Time.get_ticks_msec() < deadline, "Cave view did not finish rebuilding.")


func _shot(label: String) -> void:
	if "--no-capture" in OS.get_cmdline_user_args(): return
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png("res://tmp/world_layout_review/caves_%d_%s.png" % [_seed, label])
	_expect(error == OK, "Screenshot failed.")


func _expect(condition: bool, message: String) -> void:
	if not condition and message not in _failures: _failures.append(message)


func _finish() -> void:
	for failure in _failures: printerr(failure)
	print("CAVE_LIVE_PREVIEW_%s seed %d" % ["PASS" if _failures.is_empty() else "FAIL", _seed])
	_generator.prepare_for_world_reload()
	quit(0 if _failures.is_empty() else 1)
