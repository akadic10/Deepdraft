extends "res://tools/BoulderLivePreview.gd"

## Isolated full-scene review. Run enabled first, then --baseline for each seed.
## No project settings or live JSON are changed by this benchmark.
var _details: Node
var _flora: Node
var _renderer: Node
var _rig: Node3D
var _clock: Node
var _failures: Array[String] = []


func _run() -> void:
	if not OS.get_environment("APPDATA").replace("\\","/").contains("/tmp/surface_review/"):
		printerr("Use isolated APPDATA below tmp/surface_review."); quit(2); return
	var seed_value := 1234
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="): seed_value = int(arg.trim_prefix("--seed="))
	var baseline := "--baseline" in OS.get_cmdline_user_args()
	var directory := "res://tmp/surface_review/%d/" % seed_value
	DirAccess.make_dir_recursive_absolute(directory)
	_output = directory + ("baseline_" if baseline else "details_")
	if "--after" in OS.get_cmdline_user_args(): _output = directory + "optimized_"
	var previous: Dictionary = {}
	if baseline:
		previous = JSON.parse_string(FileAccess.get_file_as_string(directory + "details_report.json"))
		root.get_node("SurfaceDetailRegistry").definitions.clear()
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	root.size = Vector2i(1600,1000)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	root.get_node("SaveManager").configure_storage_for_testing("user://surface_review")
	var scene: Node = load("res://scenes/main/debug_world.tscn").instantiate()
	scene.get_node("Renderer").world_seed = seed_value
	var publish := func(node: Node):
		if node == scene: current_scene = scene
	node_added.connect(publish)
	var boot := Time.get_ticks_usec()
	root.add_child(scene)
	node_added.disconnect(publish)
	var generator := root.get_node("WorldGenerator")
	_renderer = scene.get_node("Renderer")
	_flora = scene.get_node("SurfaceFloraSpawner")
	_details = scene.get_node("SurfaceDetailManager")
	_rig = scene.get_node("CameraRig")
	_clock = root.get_node("WorldClock")
	await _settle()
	var ready_ms := (Time.get_ticks_usec()-boot)/1000.0
	if not generator._maps_ready or not _details._initialized:
		printerr("World did not become ready"); quit(1); return
	var census: Dictionary = previous.census if baseline else load("res://tools/SurfaceDetailCensus.gd").summarize(_details)
	var targets: Dictionary = census.targets
	var report := {"seed":seed_value,"baseline":baseline,"ready_ms":ready_ms,"diagnostics":_details.diagnostics,
		"census":census,"gpu":RenderingServer.get_video_adapter_name(),"godot":Engine.get_version_info().string,
		"vsync_mode":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"season_changes":{},"views":{}}
	_focus(targets.dense)
	# Identical seasons, captures and waiting in both processes, including caches.
	for season: String in ["spring","autumn","winter","summer"]:
		var frames: Array[float] = []
		var started := Time.get_ticks_usec()
		_clock.restore_state({"year":1,"season":season,"day":1,"hour":10,"speed":1,"paused":true})
		var synchronous_ms := (Time.get_ticks_usec()-started)/1000.0
		var last := started
		while _pending():
			await process_frame
			var now := Time.get_ticks_usec()
			frames.append((now-last)/1000.0)
			last = now
		var elapsed := (Time.get_ticks_usec()-started)/1000.0
		frames.sort()
		report.season_changes[season] = {"synchronous_ms":synchronous_ms,"settle_ms":elapsed,
			"frames":frames.size(),"max_frame_ms":frames.back() if not frames.is_empty() else synchronous_ms}
		await _settle()
		await _shot("dense_"+season)
	for name: String in ["dense","cliff","mountain","shore","wide"]:
		if not targets.has(name): continue
		_focus(targets[name])
		await _settle()
		report.views[name] = await _measure(180)
		await _shot(name)
	_focus(targets.dense)
	await _settle()
	report["pan_zoom"] = await _measure(240,targets.dense)
	# Measurements end before selection/slicing so action UI does not skew them.
	if not baseline:
		var slice := scene.get_node("SliceController")
		var level := clampi(int(targets.dense.position[1])-2,4,114)
		_focus(targets.dense)
		slice.restore_state({"active":true,"slice_y":level,"last_slice_y":level,"seeded":true})
		await _settle()
		var hidden := 0
		for record: Dictionary in _details._records.values():
			if record.origin.y > level:
				hidden += 1
				_expect(_details.get_explorer_bounds(record.id).size == Vector3.ZERO,"slice excludes above-plane detail picking")
		await _shot("slice")
		slice.deactivate()
		await _settle()
		for record: Dictionary in _details._records.values():
			_expect(_details.get_explorer_bounds(record.id).size != Vector3.ZERO,"full world restores detail visibility")
		report["slice"] = {"level":level,"hidden_clumps":hidden}
		if seed_value == 1234: report["picking"] = await _review_picking(scene,targets)
		report["saved_changes_after_viewing"] = _details.serialize_state().changes.size()
		report["visual_nodes"] = _details.find_children("*","Node3D",true,false).size()
		_expect(_details.serialize_state().changes.is_empty(),"viewing seasons/camera/slices leaves no plant edits")
	report["failures"] = _failures
	var file := FileAccess.open(_output+"report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t")); file.close()
	for failure in _failures: push_error(failure)
	print("SURFACE_REVIEW_", "PASS" if _failures.is_empty() else "FAIL", " seed=",seed_value," baseline=",baseline)
	generator.prepare_for_world_reload()
	quit(0 if _failures.is_empty() else 1)


func _pending() -> bool:
	return not _renderer._overview_built or not _renderer._dirty_overview_tiles.is_empty() or not _details._initialized or not _details._visual_queue.is_empty() or not _flora._pending.is_empty()


func _settle() -> void:
	var deadline := Time.get_ticks_msec()+120000
	while _pending() and Time.get_ticks_msec() < deadline: await process_frame
	if _pending():
		printerr("Review settling timed out"); quit(1); return
	# Give deferred frees, lighting and the camera an equal quiet interval.
	var until := Time.get_ticks_msec()+300
	while Time.get_ticks_msec() < until: await process_frame


func _focus(target: Dictionary) -> void:
	_rig.focus_world_position(Vector3(target.position[0],target.position[1],target.position[2]),target.zoom)


func _measure(count: int, moving: Dictionary = {}) -> Dictionary:
	var frames: Array[float] = []
	var render_cpu: Array[float] = []
	var render_gpu: Array[float] = []
	var calls := 0.0
	var objects := 0.0
	# Sample complete rendered frames for at least two seconds and use viewport
	# timestamps, rather than the coarse process monitor's prior rebuild sample.
	await RenderingServer.frame_post_draw
	var started := Time.get_ticks_usec()
	var last := started
	var first_frame := Engine.get_process_frames()
	while frames.size() < count or Time.get_ticks_usec()-started < 2000000:
		if not moving.is_empty():
			var t := minf(1,float(Time.get_ticks_usec()-started)/2000000.0)
			var origin := Vector3(moving.position[0],moving.position[1],moving.position[2])
			_rig.focus_world_position(origin+Vector3(sin(t*TAU)*64,0,cos(t*TAU)*32),100+sin(t*TAU)*60)
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		frames.append((now-last)/1000.0)
		last = now
		render_cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()))
		render_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
		calls += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		objects += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	var elapsed := (Time.get_ticks_usec()-started)/1000.0
	var process_frames := Engine.get_process_frames()-first_frame
	count = frames.size()
	frames.sort(); render_cpu.sort(); render_gpu.sort()
	return {"frames":count,"elapsed_ms":elapsed,"process_frames":process_frames,"median_frame_ms":frames[count/2],"p95_frame_ms":frames[floori(count*.95)],"max_frame_ms":frames.back(),
		"median_render_cpu_ms":render_cpu[count/2],"median_render_gpu_ms":render_gpu[count/2],"p95_render_gpu_ms":render_gpu[floori(count*.95)],
		"draw_calls":calls/count,"render_objects":objects/count,
		"static_memory_bytes":Performance.get_monitor(Performance.MEMORY_STATIC),"video_memory_bytes":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED),
		"scene_nodes":Performance.get_monitor(Performance.OBJECT_NODE_COUNT)}


func _review_picking(scene: Node, targets: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var explorer := scene.get_node("ObjectExplorerController")
	var registry := root.get_node("SurfaceDetailRegistry")
	for category: String in ["boulder","scree","blueberry","elderberry","wild_strawberry","flowers","reeds"]:
		var ids: Array = _details._records.keys().filter(func(id): return String(registry.get_definition(_details._records[id].definition).category) == category)
		var target: Dictionary = targets.shore if category == "reeds" else targets.dense
		var center := Vector3(target.position[0],target.position[1],target.position[2])
		ids.sort_custom(func(a,b): return Vector3(_details._records[a].origin).distance_squared_to(center) < Vector3(_details._records[b].origin).distance_squared_to(center))
		var found := ""
		for index in range(mini(30,ids.size())):
			var id := String(ids[index])
			_rig.focus_world_position(_details._records[id].node.position,42)
			await _settle()
			if _pick_point(_details,explorer,id).x < 0: continue
			found = id
			explorer.select_object(_details,id)
			await _shot("selected_"+category)
			explorer.clear_selection()
			break
		result[category] = found
		_expect(not found.is_empty(),"exposed selectable "+category)
	return result


func _expect(ok: bool, message: String) -> void:
	if not ok and not _failures.has(message): _failures.append(message)
