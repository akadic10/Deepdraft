extends "res://tools/performance/CameraBenchmark.gd"

## Isolated copied settlement with deterministic nearby jobs and extra workers.
## Scheduled calendar/arrival cases are explicit stress triggers, not game rules.
const TaskType = preload("res://scripts/systems/Task.gd")
var population := 5
var lifecycle: Node
var timeline: Array = []
var windows: Array = []
var samples := PackedFloat64Array()
var assignments := {}
var completions := {}
var released := {}
var workload := {}
var build_targets: Array[Vector3i] = []
var session_start := 0
var events_done := {}
var auto_count := 0
var failures: Array[String] = []

func _prepare_workload() -> void:
	if not saved: push_error("Long session requires a copied save"); quit(2); return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--population="): population=int(arg.trim_prefix("--population="))
	if population not in [5,20,30]: push_error("Use intended colony sizes"); quit(2); return
	var director=scene.get_node("DwarfDirector")
	var anchor: Vector3i=director.settlement_anchor
	while director.get_roster().size()<population:
		director.squad_size=mini(20,population-director.get_roster().size())
		if director.spawn_squad_at(anchor.x,anchor.z)==0: push_error("No safe extra-worker spawn"); quit(2); return
	var build: Array[Vector3i]=[]
	var dig: Array[Vector3i]=[]
	var floor_cells: Array[Vector3i]=[]
	var nav=root.get_node("NavGrid")
	var construction=scene.get_node("ConstructionController")
	for z in range(anchor.z-24,anchor.z+25,3):
		for x in range(anchor.x-24,anchor.x+25,3):
			if Vector2(x-anchor.x,z-anchor.z).length()<10: continue
			var cell:=Vector3i(x,generator.get_surface_y(x,z),z)
			if cell.y<=1 or not nav.is_walkable(cell): continue
			if root.get_node("WaterManager").flow.mass.has(Vector2i(x,z)): continue
			if build.size()<48 and construction.build_reason(cell+Vector3i.UP).is_empty():
				build.append(cell+Vector3i.UP)
			elif dig.size()<64:
				dig.append(cell)
			else: floor_cells.append(cell)
	var mining=scene.get_node("MiningDesignationController")
	dig=mining._filter_mineable_blocks(dig)
	if build.size()<16 or dig.size()<16 or floor_cells.is_empty(): push_error("Insufficient workload space"); quit(2); return
	build_targets = build.duplicate()
	construction.create_order(build)
	mining._create_zone(dig)
	var drops=scene.get_node("ItemDropManager")
	for i in 160:
		var cell: Vector3i=floor_cells[i%floor_cells.size()]
		drops.restore_loose_item("base:resources:stone:rough_stone",Vector3(cell)+Vector3(.5,1,.5))
	for i in 80:
		var cell: Vector3i=floor_cells[(i+17)%floor_cells.size()]
		drops.restore_loose_item("base:resources:wood:oak_log",Vector3(cell)+Vector3(.5,1,.5))
	workload={"population":population,"mining_blocks":dig.size(),"construction_blocks":build.size(),
		"loose_stone":160,"loose_logs":80,"anchor":str(anchor),
		"note":"Copied developed five-dwarf settlement, expanded roster as requested. Nearby real terrain jobs and fixed supplies; no fabricated floor. Calendar and arrival triggers are artificial, normal work/needs/simulation remain active."}
	lifecycle=load("res://tools/performance/FrameLifecycleProbe.gd").new()
	lifecycle.record_all=false
	scene.add_child(lifecycle)
	root.get_node("SaveManager").set_process(true)
	for i in 120: await process_frame

func _set_sampling_camera() -> void:
	var anchor: Vector3i=scene.get_node("DwarfDirector").settlement_anchor
	origin=Vector3(anchor)+Vector3(0,4,0)
	rig._target_pos=origin
	rig.global_position=origin
	rig._target_zoom=48

func _benchmark_modes() -> Array[String]:
	return ["active_session"]

func _sample(_mode: String) -> void:
	session_start=Time.get_ticks_usec()
	lifecycle.phase="active_session"
	var saves=root.get_node("SaveManager")
	saves._autosave_elapsed_seconds=0
	saves.autosave_finished.connect(_autosave_finished)
	var tasks=root.get_node("TaskManager")
	tasks.task_assigned.connect(func(task: RefCounted,_id: int): _increment(assignments,task))
	tasks.task_completed.connect(func(task: RefCounted): _increment(completions,task))
	tasks.task_released.connect(func(task: RefCounted,_id: int,_reason: int): _increment(released,task))
	var events=scene.get_node("WorldEventDirector")
	events.arrival_finished.connect(func(id: String,count: int,edge: String): _event("arrival_finished",{"id":id,"count":count,"edge":edge}))
	clock_node.day_changed.connect(func(day: int): _event("day_changed",{"day":day}))
	clock_node.season_changed.connect(func(season: String): _event("season_changed",{"season":season}))
	clock_node.set_paused(false)
	clock_node.set_speed(1)
	var initial:=_state()
	var window_start:=0.0
	var frame_values: Array=[]
	var subsystem_values: Dictionary={}
	var spikes: Array=[]
	var total_frames:=0
	while _elapsed()<seconds:
		var elapsed:=_elapsed()
		_drive_camera(true,elapsed)
		_trigger_events(elapsed,events,saves)
		await process_frame
		var frame: Dictionary=lifecycle.latest
		if frame.is_empty(): continue
		total_frames+=1
		frame_values.append(frame.wall_ms)
		samples.append_array(PackedFloat64Array([_elapsed(),frame.wall_ms,frame.process_ms,frame.after_process_ms,frame.draw_ms,frame.after_draw_ms,frame.setup_cpu_ms]))
		for key in measurements:
			if not subsystem_values.has(key): subsystem_values[key]=[]
			subsystem_values[key].append(measurements[key])
		if frame.wall_ms>33.333 and spikes.size()<128:
			spikes.append({"seconds":_elapsed(),"frame":frame.duplicate(true),"process":measurements.duplicate()})
		if _elapsed()-window_start>=30 or _elapsed()>=seconds:
			var window: Dictionary={"start":window_start,"end":_elapsed(),"frames":_stats(frame_values),"state":_state(),"process":{},"spikes":spikes}
			for key in subsystem_values: window.process[key]=_stats(subsystem_values[key])
			windows.append(window)
			print("LONG_SESSION_WINDOW ",JSON.stringify({"seconds":window.end,"frame":window.frames,"state":window.state}))
			frame_values=[]
			subsystem_values={}
			spikes=[]
			window_start=_elapsed()
	clock_node.set_paused(true)
	saves.set_process(false)
	var result: Dictionary={"workload":workload,"initial":initial,"final":_state(),"duration_seconds":_elapsed(),
		"frames":total_frames,"windows":windows,"events":timeline,"arrivals_history":events.history,
		"auto_count":auto_count,"failures":failures,"lifecycle_errors":tasks.lifecycle_errors(),
		"frame_columns":["seconds","wall_ms","process_ms","after_process_ms","draw_ms","after_draw_ms","setup_cpu_ms"]}
	FileAccess.open(output+"session.json",FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	FileAccess.open(output+"session_frames.json",FileAccess.WRITE).store_string(JSON.stringify(samples))
	report["long_session"]=result.duplicate()
	report.long_session.erase("windows")
	_save_report()
	if not failures.is_empty() or not tasks.lifecycle_errors().is_empty(): push_error("Long-session invariant failure"); quit(1); return
	print("LONG_SESSION_PASS ",population," dwarves ",_elapsed()," seconds; autosaves=",auto_count)

func _elapsed() -> float:
	return (Time.get_ticks_usec()-session_start)/1000000.0

func _increment(target: Dictionary,task: RefCounted) -> void:
	var kind: String=TaskType.type_name(task.type)
	target[kind]=int(target.get(kind,0))+1

func _event(kind: String,data: Dictionary) -> void:
	timeline.append({"seconds":_elapsed(),"kind":kind,"data":data})

func _autosave_finished(ok: bool) -> void:
	auto_count+=1
	_event("autosave_finished",{"ok":ok})
	if not ok: failures.append("autosave failed")

func _trigger_events(elapsed: float,events: Node,saves: Node) -> void:
	if elapsed>=30 and not events_done.has("save"):
		events_done.save=true
		var started:=Time.get_ticks_usec()
		var ok: bool=saves.request_autosave()
		_event("explicit_autosave",{"ok":ok,"main_thread_ms":(Time.get_ticks_usec()-started)/1000.0})
	if elapsed>=60 and not events_done.has("day"):
		events_done.day=true
		clock_node.hour=23.999
		clock_node._last_hour_int=23
		_event("prepare_day_boundary",{})
	if elapsed>=90 and not events_done.has("arrivals"):
		events_done.arrivals=true
		events.initialize_schedule()
		for definition in events.config.events:
			var plan: Dictionary=events.schedules[definition.id].next
			plan.due=clock_node.elapsed_days()
			plan.roll=0.0
			plan.count=2
		_event("arrival_opportunities",{"note":"normal provider eligibility, caps and route rules retained"})
	if elapsed>=150 and not events_done.has("season"):
		events_done.season=true
		clock_node.day=clock_node._days_per_season
		clock_node.hour=23.999
		clock_node._last_hour_int=23
		_event("prepare_season_boundary",{})

func _state() -> Dictionary:
	var stored:=0
	for count in root.get_node("StockpileManager")._totals.values(): stored+=int(count)
	return {"static_memory_mb":OS.get_static_memory_usage()/1048576.0,"nodes":get_node_count(),
		"objects":Performance.get_monitor(Performance.OBJECT_COUNT),"resources":Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
		"orphan_nodes":Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
		"video_memory_mb":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED)/1048576.0,
		"mined":root.get_node("WorldData").removed_terrain_count(),
		"built":build_targets.filter(func(cell): return root.get_node("BlockRegistry").is_solid(root.get_node("WorldData").get_terrain_block(cell.x,cell.y,cell.z))).size(),"stored":stored,
		"loose":scene.get_node("ItemDropManager")._loose.size(),"wildlife":scene.get_node("WildlifeManager").animals.size(),
		"scheduler":root.get_node("TaskManager").get_scheduler_stats(),"assignments":assignments.duplicate(),
		"completed":completions.duplicate(),"released":released.duplicate(),"clock":clock_node.serialize_state()}
