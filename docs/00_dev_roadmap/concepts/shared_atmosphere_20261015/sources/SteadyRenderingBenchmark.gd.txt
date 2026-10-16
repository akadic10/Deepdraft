extends "res://tools/performance/LongSessionBenchmark.gd"

## Normal-speed copied settlement. No artificial calendar, save or arrival events.
const Detail = preload("res://tools/performance/RenderProfile.gd")
var detailed := false

func _prepare_workload() -> void:
	await super._prepare_workload()
	detailed = "--detailed" in OS.get_cmdline_user_args()
	# Isolate recurring frame cost. Event/soak interaction is a separate scenario.
	root.get_node("SaveManager").set_process(false)
	scene.get_node("WorldEventDirector").set_process(false)
	workload.note = "Copied developed settlement expanded to 30 dwarves with normal jobs. Normal x1 clock (60 real seconds/game hour), needs and simulation. Autosave and arrival scheduling disabled for steady-cost attribution; no artificial events."
	var tasks = root.get_node("TaskManager")
	tasks.task_assigned.connect(func(task: RefCounted, _id: int): _increment(assignments, task))
	tasks.task_completed.connect(func(task: RefCounted): _increment(completions, task))
	tasks.task_released.connect(func(task: RefCounted, _id: int, _reason: int): _increment(released, task))

func _benchmark_modes() -> Array[String]:
	return ["active_static", "active_pan", "active_pan_repeat"]

func _sample(mode: String) -> void:
	clock_node.set_speed(1)
	clock_node.set_paused(false)
	assert(is_equal_approx(clock_node._real_seconds_per_game_hour, 60.0))
	var pan := mode.contains("pan")
	lifecycle.phase = "warmup_" + mode
	var started := Time.get_ticks_usec()
	while Time.get_ticks_usec() - started < 8000000:
		_drive_camera(pan, (Time.get_ticks_usec() - started) / 1000000.0)
		await process_frame
	var initial := _state()
	var light = renderer.underground_lighting
	var lighting_initial := _lighting_state(light)
	var rows: Array = []
	var rid := root.get_viewport_rid()
	lifecycle.phase = mode
	Detail.take()
	started = Time.get_ticks_usec()
	while Time.get_ticks_usec() - started < int(seconds * 1000000):
		_drive_camera(pan, (Time.get_ticks_usec() - started) / 1000000.0)
		await process_frame
		var frame: Dictionary = lifecycle.latest
		var detail := Detail.take()
		if frame.is_empty(): continue
		var costs := measurements.duplicate()
		if markers:
			for key in water_view.last_update_ms: costs["water_render/" + key] = water_view.last_update_ms[key]
			for key in root.get_node("WaterManager").last_update_ms: costs["water_sim/" + key] = root.get_node("WaterManager").last_update_ms[key]
			for key in scene.get_node("WildlifeManager").last_update_ms: costs["wildlife/" + key] = scene.get_node("WildlifeManager").last_update_ms[key]
		rows.append({"seconds":(Time.get_ticks_usec()-started)/1000000.0,
			"frame_ms":frame.wall_ms, "process_ms":frame.process_ms,
			"after_process_ms":frame.after_process_ms, "draw_ms":frame.draw_ms,
			"after_draw_ms":frame.after_draw_ms, "physics_ms":frame.physics_ms,
			"gpu_ms":RenderingServer.viewport_get_measured_render_time_gpu(rid),
			"render_cpu_ms":RenderingServer.viewport_get_measured_render_time_cpu(rid),
			"render_setup_ms":RenderingServer.get_frame_setup_time_cpu(),
			"draw_calls":RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
			"primitives":RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME),
			"process":costs, "detail":detail, "pipelines":frame.pipelines})
	var summary := {"frames":rows.size(), "seconds":(Time.get_ticks_usec()-started)/1000000.0,
		"initial":initial, "final":_state(), "lighting_initial":lighting_initial,
		"lighting_final":_lighting_state(light), "process":{}, "detail":{},
		"detailed":detailed, "calendar_seconds_per_hour":clock_node._real_seconds_per_game_hour}
	for key in ["frame_ms", "process_ms", "after_process_ms", "draw_ms", "after_draw_ms", "physics_ms", "gpu_ms", "render_cpu_ms", "render_setup_ms", "draw_calls", "primitives"]:
		var values: Array = []
		for row: Dictionary in rows: values.append(row[key])
		summary[key] = _stats(values)
	for category in ["process", "detail"]:
		var keys := {}
		for row: Dictionary in rows:
			for key in row[category]: keys[key] = true
		for key in keys:
			var values: Array = []
			for row: Dictionary in rows: values.append(row[category].get(key, 0.0))
			summary[category][key] = _stats(values)
	FileAccess.open(output + mode + "_frames.json", FileAccess.WRITE).store_string(JSON.stringify(rows))
	report.phases[mode] = summary
	report["workload"] = workload
	report["lifecycle_errors"] = root.get_node("TaskManager").lifecycle_errors()
	report["source_hashes"] = {}
	for path in ["scripts/systems/WorldRenderer.gd", "scripts/components/UndergroundLighting.gd", "scripts/entities/DwarfAgent.gd", "tools/performance/SteadyRenderingBenchmark.gd", "tools/performance/RenderProfile.gd"]:
		report.source_hashes[path] = FileAccess.get_sha256("res://" + path)
	_save_report()
	print("STEADY_RENDER_SAMPLE ", mode, " ", JSON.stringify({"frame":summary.frame_ms, "gpu":summary.gpu_ms, "clock":summary.final.clock}))
	assert(report.lifecycle_errors.is_empty())
	clock_node.set_paused(true)

func _lighting_state(light: Node) -> Dictionary:
	var actors := {}
	var invalid := 0
	for entry: Dictionary in light._actor_meshes.values():
		var actor = entry.actor.get_ref()
		if actor == null: invalid += 1
		else: actors[actor.get_instance_id()] = true
	return {"actor_meshes":light._actor_meshes.size(), "actors":actors.size(), "invalid_actor_refs":invalid,
		"materials":light._material_cache.size(), "completed_updates":light.completed_updates,
		"phase":light._phase, "pending":light._pending.size()}
