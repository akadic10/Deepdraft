extends "res://tools/BoulderLivePreview.gd"


func _run() -> void:
	_output = "res://tmp/shrub_review/"
	if not OS.get_environment("APPDATA").replace("\\", "/").contains("/tmp/shrub_review/"):
		printerr("Use isolated APPDATA below tmp/shrub_review.")
		quit(2)
		return
	root.size = Vector2i(1600,1000)
	root.get_node("SaveManager").configure_storage_for_testing("user://shrub_preview")
	var scene: Node = load("res://scenes/main/debug_world.tscn").instantiate()
	scene.get_node("Renderer").world_seed = 1234
	var publish := func(node: Node):
		if node == scene: current_scene = scene
	node_added.connect(publish)
	root.add_child(scene)
	node_added.disconnect(publish)
	var generator := root.get_node("WorldGenerator")
	var renderer := scene.get_node("Renderer")
	var flora := scene.get_node("SurfaceFloraSpawner")
	var details := scene.get_node("SurfaceDetailManager")
	var dock := scene.get_node("DockUI")
	var explorer := scene.get_node("ObjectExplorerController")
	var clock_node := root.get_node("WorldClock")
	var deadline := Time.get_ticks_msec() + 120000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if generator._maps_ready and renderer._overview_built and details._initialized and flora._pending.is_empty() and details._visual_queue.is_empty(): break
	if not details._initialized or not renderer._overview_built:
		printerr("Shrub preview timed out"); quit(1); return
	clock_node.set_paused(true)
	for pair in [["blueberry","summer"], ["elderberry","autumn"], ["strawberry","spring"]]:
		clock_node.restore_state({"year":1,"season":pair[1],"day":1,"hour":10,"speed":1,"paused":true})
		var id := ""
		var point := Vector2(-1,-1)
		for attempt in range(20):
			dock._dispatch_panel_action("surface_details", "DEV: Next " + pair[0])
			id = String(explorer._object_id)
			for i in range(100): await process_frame
			point = _pick_point(details, explorer, id)
			if point.x >= 0: break
		if point.x < 0:
			printerr("No exposed shrub for native picking: ", pair[0]); quit(1); return
		var controller := scene.get_node("TreeFellingController")
		dock._dispatch("open_panel","orders")
		dock._orders._buttons.harvest_plants.pressed.emit()
		if not controller.designate_at_screen(point):
			printerr("Native harvest tool failed: ", id); quit(1); return
		for i in range(6): await process_frame
		await _shot("world_"+pair[0])
		dock._orders._buttons.cancel_orders.pressed.emit()
		controller._begin_drag(point)
		controller._finish_drag(point)
		if details.get_clearing_order_token(id) != null:
			printerr("Native shrub cancel failed"); quit(1); return
		dock._request_order_tool("")
		dock._orders.set_open(false)
		scene.get_node("CameraRig").focus_world_position(details._records[id].node.position, 14)
		for i in range(80): await process_frame
		await _shot("world_"+pair[0]+"_close")
		if pair[0] == "blueberry":
			clock_node.restore_state({"year":1,"season":"winter","day":1,"hour":10,"speed":1,"paused":true})
			for i in range(120): await process_frame
			if not String(details._records[id].model_path).ends_with("winter.glb"):
				printerr("Live seasonal swap failed"); quit(1); return
			await _shot("world_blueberry_winter")
	print("SHRUB_LIVE_PREVIEW_PASS ", details.diagnostics)
	generator.prepare_for_world_reload()
	quit()
