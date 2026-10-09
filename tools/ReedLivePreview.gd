extends "res://tools/BoulderLivePreview.gd"

const REPORT := "res://tmp/reed_review/live_report.json"


func _run() -> void:
	_output = "res://tmp/reed_review/"
	if not OS.get_environment("APPDATA").replace("\\", "/").contains("/tmp/reed_review/"):
		printerr("Use isolated APPDATA below tmp/reed_review."); quit(2); return
	var baseline := "--baseline" in OS.get_cmdline_user_args()
	var previous: Dictionary = {}
	if baseline:
		previous = JSON.parse_string(FileAccess.get_file_as_string(REPORT))
		root.get_node("SurfaceDetailRegistry").definitions.erase("base:detail:reeds")
	root.size = Vector2i(1600,1000)
	root.get_node("SaveManager").configure_storage_for_testing("user://reed_preview")
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
		printerr("Reed preview timed out"); quit(1); return
	clock_node.restore_state({"year":1,"season":"summer","day":1,"hour":10,"speed":1,"paused":true})
	var target := Vector3.ZERO
	var id := ""
	if baseline:
		target = Vector3(previous.target[0],previous.target[1],previous.target[2])
		# Match seasonal cache warmup so memory deltas do not include tree/shrub art.
		for season: String in ["spring","autumn","winter","summer"]:
			clock_node.restore_state({"year":1,"season":season,"day":1,"hour":10,"speed":1,"paused":true})
			while not details._visual_queue.is_empty() or not flora._pending.is_empty(): await process_frame
			for i in range(40): await process_frame
	else:
		# Begin beside the lowland lake; the menu still cycles real records.
		var ids: Array = details._records.keys()
		ids.sort()
		var best := INF
		for index in range(ids.size()):
			var record: Dictionary = details._records[ids[index]]
			if not String(ids[index]).begins_with("reeds:") or record.water_body != "lake": continue
			var distance := Vector2(record.origin.x,record.origin.z).distance_squared_to(Vector2(512,512))
			if distance < best:
				best = distance
				details._dev_cursors["reeds"] = index
		var point := Vector2(-1,-1)
		for attempt in range(30):
			dock._dispatch_panel_action("surface_details", "DEV: Next reeds")
			id = String(explorer._object_id)
			for i in range(100): await process_frame
			point = _pick_point(details,explorer,id)
			if point.x >= 0: break
		if point.x < 0:
			printerr("No exposed reeds for native picking"); quit(1); return
		target = details._records[id].node.position
		var controller := scene.get_node("TreeFellingController")
		dock._dispatch("open_panel","orders")
		dock._orders._buttons.clear_shrubs.pressed.emit()
		if not controller.designate_at_screen(point):
			printerr("Native flower clearing tool failed"); quit(1); return
		for i in range(6): await process_frame
		await _shot("world_orders")
		dock._orders._buttons.cancel_orders.pressed.emit()
		controller._begin_drag(point)
		controller._finish_drag(point)
		if details.get_clearing_order_token(id) != null:
			printerr("Native flower cancel failed"); quit(1); return
		dock._request_order_tool("")
		dock._orders.set_open(false)
		scene.get_node("CameraRig").focus_world_position(target,14)
		for i in range(100): await process_frame
		await _shot("world_summer_close")
		for season: String in ["spring","autumn","winter"]:
			clock_node.restore_state({"year":1,"season":season,"day":1,"hour":10,"speed":1,"paused":true})
			while not details._visual_queue.is_empty(): await process_frame
			for i in range(40): await process_frame
			if not String(details._records[id].model_path).ends_with(season+".glb"):
				printerr("Reed seasonal swap failed"); quit(1); return
			await _shot("world_"+season+"_close")
		clock_node.restore_state({"year":1,"season":"summer","day":1,"hour":10,"speed":1,"paused":true})
		while not details._visual_queue.is_empty(): await process_frame
		explorer.clear_selection()
		var tarn_found := false
		for other_id: String in ids:
			var record: Dictionary = details._records[other_id]
			if not String(other_id).begins_with("reeds:") or record.water_body != "tarn": continue
			scene.get_node("CameraRig").focus_world_position(record.node.position,42)
			explorer.select_object(details,other_id)
			for i in range(100): await process_frame
			await _shot("world_tarn")
			tarn_found = true
			break
		if not tarn_found: print("REED_PREVIEW_NO_ELIGIBLE_TARN")
		explorer.clear_selection()
	# Identical fixed-seed view for full-scene reed/no-reed render comparison.
	scene.get_node("CameraRig").focus_world_position(target,100)
	for i in range(180): await process_frame
	await _shot("baseline_play_zoom" if baseline else "world_play_zoom")
	var report := {"target":[target.x,target.y,target.z], "diagnostics":details.diagnostics,
		"play_zoom":await _measure()}
	scene.get_node("CameraRig").focus_world_position(Vector3(512,30,512),180)
	for i in range(180): await process_frame
	report["wide_zoom"] = await _measure()
	await _shot("baseline_wide_zoom" if baseline else "world_wide_zoom")
	var file := FileAccess.open("res://tmp/reed_review/baseline_report.json" if baseline else REPORT,FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("REED_LIVE_PREVIEW_PASS ", report)
	generator.prepare_for_world_reload()
	quit()


func _measure() -> Dictionary:
	var frames: Array[float] = []
	var draw_calls := 0.0
	var objects := 0.0
	var last := Time.get_ticks_usec()
	for i in range(90):
		await process_frame
		var now := Time.get_ticks_usec()
		frames.append((now-last)/1000.0)
		last = now
		draw_calls += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		objects += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	frames.sort()
	return {"median_frame_ms":frames[45], "p95_frame_ms":frames[85], "draw_calls":draw_calls/90,
		"render_objects":objects/90, "static_memory_bytes":Performance.get_monitor(Performance.MEMORY_STATIC),
		"video_memory_bytes":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED),
		"scene_nodes":Performance.get_monitor(Performance.OBJECT_NODE_COUNT)}
