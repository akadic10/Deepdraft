extends "res://tools/performance/LongSessionBenchmark.gd"
## Same copied settlement and work as 191; one deliberately due opportunity batch.
func _sample(_mode: String) -> void:
	session_start=Time.get_ticks_usec()
	lifecycle.phase="arrivals"
	var events=scene.get_node("WorldEventDirector")
	var wildlife=scene.get_node("WildlifeManager")
	root.get_node("SaveManager").set_process(false)
	clock_node.set_paused(false)
	clock_node.set_speed(1)
	var initial:=_state()
	var frames: Array=[]
	var event_cpu: Array=[]
	var rows:=PackedFloat64Array()
	var spikes: Array=[]
	var triggered:=false
	events.arrival_finished.connect(func(id,count,edge): _event("arrival_finished",{"id":id,"count":count,"edge":edge}))
	while _elapsed()<seconds:
		_drive_camera(true,_elapsed())
		if not triggered and _elapsed()>=6:
			triggered=true
			events.initialize_schedule()
			for definition in events.config.events:
				var plan: Dictionary=events.schedules[definition.id].next
				plan.due=clock_node.elapsed_days()
				plan.roll=0.0
				plan.count=2
			_event("opportunities",{})
		await process_frame
		var frame: Dictionary=lifecycle.latest
		if frame.is_empty(): continue
		var cpu:=float(measurements.get("DebugWorld/WorldEventDirector",0))
		frames.append(frame.wall_ms)
		event_cpu.append(cpu)
		rows.append_array(PackedFloat64Array([_elapsed(),frame.wall_ms,cpu,frame.process_ms,frame.draw_ms]))
		if cpu>3 or frame.wall_ms>75: spikes.append({"seconds":_elapsed(),"frame":frame.duplicate(true),"process":measurements.duplicate()})
	clock_node.set_paused(true)
	var result: Dictionary={"population":population,"seconds":_elapsed(),"frames":_stats(frames),"event_cpu":_stats(event_cpu),
		"initial":initial,"final":_state(),"events":timeline,"schedules":events.serialize_state(),"spikes":spikes,
		"profile":wildlife.get("arrival_profile"),"director_sha256":FileAccess.get_sha256("res://scripts/systems/WorldEventDirector.gd"),
		"wildlife_sha256":FileAccess.get_sha256("res://scripts/systems/WildlifeManager.gd")}
	FileAccess.open(output+"arrivals.json",FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	FileAccess.open(output+"arrival_frames.json",FileAccess.WRITE).store_string(JSON.stringify(rows))
	report["arrivals"]=result.duplicate()
	report.arrivals.erase("spikes")
	print("ARRIVAL_BENCHMARK_PASS ",JSON.stringify({"frame":result.frames,"event_cpu":result.event_cpu,"events":timeline}))
