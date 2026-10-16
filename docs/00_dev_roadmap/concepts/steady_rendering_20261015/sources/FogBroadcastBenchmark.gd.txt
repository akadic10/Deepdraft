extends "res://tools/performance/SteadyRenderingBenchmark.gd"

## Diagnostic intervention: frozen material fog values are intentionally stale.
## Movement, calendar, needs, water, wildlife, light field and actor sampling run.
const Switch = preload("res://tools/performance/FogBroadcastSwitch.gd")

func _benchmark_modes() -> Array[String]:
	return ["fog_broadcast_intervention"]

func _sample(_mode: String) -> void:
	clock_node.set_speed(1)
	clock_node.set_paused(false)
	assert(is_equal_approx(clock_node._real_seconds_per_game_hour, 60.0))
	var started := Time.get_ticks_usec()
	# Let the initial mining settle before alternating the single visual callback.
	lifecycle.phase = "fog_intervention_warmup"
	while Time.get_ticks_usec() - started < 60000000:
		_drive_camera(true, (Time.get_ticks_usec()-started)/1000000.0)
		await process_frame
	var blocks: Array = []
	var rid := root.get_viewport_rid()
	var light = renderer.underground_lighting
	var initial := _state()
	for index in range(12):
		# ABBA balances both halves of the eight-second camera orbit and time drift.
		Switch.disabled = index % 4 in [1, 2]
		lifecycle.phase = "fog_frozen" if Switch.disabled else "fog_live"
		var block_start := Time.get_ticks_usec()
		# Discard one second after every toggle, including deferred render setup.
		while Time.get_ticks_usec() - block_start < 1000000:
			_drive_camera(true, (Time.get_ticks_usec()-started)/1000000.0)
			await process_frame
		Detail.take()
		var rows: Array = []
		var sample_start := Time.get_ticks_usec()
		while Time.get_ticks_usec() - sample_start < 3000000:
			_drive_camera(true, (Time.get_ticks_usec()-started)/1000000.0)
			await process_frame
			var frame: Dictionary = lifecycle.latest
			rows.append({"frame_ms":frame.wall_ms, "process_ms":frame.process_ms,
				"gpu_ms":RenderingServer.viewport_get_measured_render_time_gpu(rid),
				"render_setup_ms":RenderingServer.get_frame_setup_time_cpu(),
				"detail":Detail.take(), "process":measurements.duplicate(), "pipelines":frame.pipelines})
		blocks.append({"index":index, "frozen":Switch.disabled, "rows":rows})
	Switch.disabled = false
	clock_node.set_paused(true)
	var result := {"initial":initial, "final":_state(), "lighting":_lighting_state(light),
		"calendar_seconds_per_hour":clock_node._real_seconds_per_game_hour,
		"blocks":blocks, "note":"Three ABBA groups balance camera direction and time drift. Three-second samples follow one-second settling intervals. Only material fog broadcasts are skipped in frozen blocks. Stale atmosphere values are a diagnostic, not a valid gameplay optimization. GPU timestamps may lag; phase settling precedes collection."}
	FileAccess.open(output + "fog_intervention.json", FileAccess.WRITE).store_string(JSON.stringify(result, "  "))
	report["fog_intervention"] = {"blocks":blocks.size(), "initial":initial, "final":result.final}
	report["source_hashes"] = {}
	for path in ["scripts/systems/WorldRenderer.gd", "scripts/components/UndergroundLighting.gd", "scripts/entities/DwarfAgent.gd", "tools/performance/FogBroadcastBenchmark.gd", "tools/performance/FogBroadcastSwitch.gd"]:
		report.source_hashes[path] = FileAccess.get_sha256("res://"+path)
	_save_report()
	assert(root.get_node("TaskManager").lifecycle_errors().is_empty())
	print("FOG_BROADCAST_INTERVENTION_PASS")
