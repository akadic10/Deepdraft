extends "res://tools/performance/LongSessionBenchmark.gd"

## Two saves of a continuously running copied settlement: fresh and rotation.
var save_events: Array = []
var save_completions: Array = []

func _prepare_workload() -> void:
	await super._prepare_workload()
	var saves=root.get_node("SaveManager")
	if "--profile-baseline" in OS.get_cmdline_user_args():
		saves.set_script(load("res://tools/performance/ProfileSaveManager.gd"))
	saves.autosave_finished.connect(func(ok: bool):
		var event: Dictionary={"seconds":_elapsed(),"ok":ok}
		if saves.get("last_save_profile")!=null: event["profile"]=saves.last_save_profile.duplicate(true)
		save_completions.append(event))
	saves.set_process(true)

func _sample(_mode: String) -> void:
	session_start=Time.get_ticks_usec()
	var saves=root.get_node("SaveManager")
	saves._autosave_elapsed_seconds=0
	clock_node.set_paused(false)
	clock_node.set_speed(1)
	var initial:=_state()
	var frames: Array=[]
	var spikes: Array=[]
	var rows:=PackedFloat64Array()
	var issued:=0
	while _elapsed()<seconds:
		_drive_camera(true,_elapsed())
		if issued<2 and _elapsed()>=6+issued*8:
			var started:=Time.get_ticks_usec()
			var ok: bool=saves.request_autosave()
			var event: Dictionary={"seconds":_elapsed(),"accepted":ok,"request_ms":(Time.get_ticks_usec()-started)/1000.0}
			if "--profile-baseline" in OS.get_cmdline_user_args():
				event["stages"]=saves.stages.duplicate(true)
				saves.stages.clear()
			save_events.append(event)
			issued+=1
		await process_frame
		var frame: Dictionary=lifecycle.latest
		if frame.is_empty(): continue
		frames.append(frame.wall_ms)
		rows.append_array(PackedFloat64Array([_elapsed(),frame.wall_ms,frame.process_ms,frame.draw_ms,frame.setup_cpu_ms]))
		if frame.wall_ms>33.333: spikes.append({"seconds":_elapsed(),"frame":frame.duplicate(true),"process":measurements.duplicate()})
	clock_node.set_paused(true)
	var summary: Dictionary={"population":population,"seconds":_elapsed(),"frames":_stats(frames),
		"initial":initial,"final":_state(),"saves":save_events,"completions":save_completions,"spikes":spikes,
		"save_manager_sha256":FileAccess.get_sha256("res://scripts/systems/SaveManager.gd"),
		"validator_sha256":FileAccess.get_sha256("res://scripts/components/SaveSnapshotValidator.gd")}
	FileAccess.open(output+"autosave.json",FileAccess.WRITE).store_string(JSON.stringify(summary,"  "))
	FileAccess.open(output+"autosave_frames.json",FileAccess.WRITE).store_string(JSON.stringify(rows))
	report["autosave"]=summary.duplicate()
	report.autosave.erase("spikes")
	if save_completions.size()!=2 or save_completions.any(func(e): return not e.ok):
		push_error("Autosave benchmark did not complete two saves"); quit(1); return
	print("AUTOSAVE_BENCHMARK_PASS ",JSON.stringify(report.autosave.frames)," requests=",save_events.map(func(e): return e.request_ms))
