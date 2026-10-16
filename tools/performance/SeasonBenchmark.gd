extends "res://tools/performance/LongSessionBenchmark.gd"

## Focused seasonal art workload. The calendar uses 5 real seconds per game
## hour so a complete transition night fits in one native sample. Actor speed
## stays at x1; calendar-driven needs/growth consequently also see a faster night.
func _sample(_mode: String) -> void:
	var flora = scene.get_node("SurfaceFloraSpawner")
	var details = scene.get_node("SurfaceDetailManager")
	root.get_node("SaveManager").set_process(false)
	scene.get_node("WorldEventDirector").set_process(false)
	clock_node.day = clock_node._days_per_season
	clock_node.hour = 23.5
	clock_node._last_hour_int = 23
	clock_node._real_seconds_per_game_hour = 5.0
	clock_node.set_speed(1)
	clock_node.set_paused(false)
	session_start = Time.get_ticks_usec()
	lifecycle.phase = "season_night"
	clock_node.season_changed.connect(func(value): _event("season_changed", {"season":value}))
	var initial := _state()
	var frames: Array = []
	var subsystems: Dictionary = {}
	var rows := PackedFloat64Array()
	var spikes: Array = []
	var minimum_trees: int = flora._spawned_count
	var baseline_trees: int = flora._spawned_count
	while _elapsed() < seconds:
		_drive_camera(true, _elapsed())
		await process_frame
		var frame: Dictionary = lifecycle.latest
		if frame.is_empty(): continue
		frames.append(frame.wall_ms)
		for key in measurements:
			if not subsystems.has(key): subsystems[key] = []
			subsystems[key].append(measurements[key])
		minimum_trees = mini(minimum_trees, flora._spawned_count)
		rows.append_array(PackedFloat64Array([_elapsed(), frame.wall_ms, frame.process_ms, frame.draw_ms, clock_node.hour, flora._spawned_count]))
		if frame.wall_ms > 50:
			spikes.append({"seconds":_elapsed(), "frame":frame.duplicate(true), "process":measurements.duplicate()})
	clock_node.set_paused(true)
	var costs: Dictionary = {}
	for key in subsystems: costs[key] = _stats(subsystems[key])
	var result := {"population":population, "seconds":_elapsed(), "frames":_stats(frames), "process":costs,
		"initial":initial, "final":_state(), "events":timeline, "spikes":spikes,
		"initial_trees":baseline_trees, "minimum_trees":minimum_trees, "final_trees":flora._spawned_count,
		"pending_tree_spawn":flora._pending.size(), "pending_detail_spawn":details._visual_queue.size(),
		"calendar_seconds_per_hour":5, "sources":{}}
	for path: String in ["scripts/systems/SurfaceFloraSpawner.gd", "scripts/systems/SurfaceDetailManager.gd", "scripts/systems/WorldRenderer.gd", "scripts/systems/WorldClock.gd", "scripts/components/SeasonalRefreshQueue.gd"]:
		if FileAccess.file_exists("res://"+path): result.sources[path] = FileAccess.get_sha256("res://"+path)
	FileAccess.open(output+"season.json", FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	FileAccess.open(output+"season_frames.json", FileAccess.WRITE).store_string(JSON.stringify(rows))
	report["season"] = result.duplicate()
	report.season.erase("spikes")
	print("SEASON_BENCHMARK_PASS ", JSON.stringify({"frames":result.frames,"minimum_trees":minimum_trees,"initial_trees":baseline_trees}))
