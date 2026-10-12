extends SceneTree

var loaded := false
var succeeded := false
var last_state := ""

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	create_timer(150).timeout.connect(func(): push_error("Player ladder probe timed out"); quit(1))
	var saves := root.get_node("SaveManager")
	saves.configure_storage_for_testing("user://ladder_probe")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://ladder_probe"))
	DirAccess.copy_absolute(ProjectSettings.globalize_path("res://tmp/ladder_extension_20261011/player_quicksave.json"), ProjectSettings.globalize_path("user://ladder_probe/quicksave.json"))
	saves.load_finished.connect(func(ok: bool, _backup: bool): loaded = true; succeeded = ok)
	change_scene_to_file("res://scenes/main/debug_world.tscn")
	for i in range(12): await process_frame
	if not saves.request_load(): quit(1); return
	while not loaded: await process_frame
	if not succeeded: quit(1); return
	var clock := root.get_node("WorldClock")
	clock.set_paused(true)
	var ladders := get_first_node_in_group("ladders")
	var tasks := root.get_node("TaskManager")
	var nav := root.get_node("NavGrid")
	var stocks := root.get_node("StockpileManager")
	print("PLAYER_LADDER routes=",ladders.serialize_state()," stock=",stocks.get_available_total("base:resources:furniture:crude_ladder"))
	for route: Dictionary in ladders.routes.values():
		var source = route.source
		print("PLAYER_LADDER geometry=",ladders.describe(route.base,route.yaw,route.id)," work=",source.origin_cell," navigable=",nav.is_navigable(source.origin_cell)," lease=",source._lease_id)
		for agent in tasks._agents.values():
			print("PLAYER_LADDER dwarf=",agent.dwarf_name," cell=",agent.current_cell()," chosen=",source.nearest_stand_target(agent.current_cell())," path=",nav.find_path(agent.current_cell(),source.origin_cell))
	clock.set_paused(false)
	clock.set_speed(2.0)
	var started := Time.get_ticks_msec()
	var next_debug := started
	while Time.get_ticks_msec()-started < 45000:
		await process_frame
		if Time.get_ticks_msec() >= next_debug:
			next_debug = Time.get_ticks_msec() + 2000
			var query: Dictionary = tasks._work_probe.get("route_query", {})
			print("SCHED_DEBUG ", {"paused":paused,"clock_paused":clock.paused,"processing":tasks.is_processing(),"idle":tasks._idle_dwarves,"stats":tasks.get_scheduler_stats(),"probe_key":tasks._work_probe.get("key", []),"expanded":query.get("expanded",-1),"approach":query.get("approach", {}).get("expanded", -1),"revision":nav.navigation_revision,"ladder_revision":nav.ladder_revision,"rejections":tasks._worker_rejections,"cursor":tasks._scan_cursor})
		var route: Dictionary = ladders.routes.get(1,{})
		if route.is_empty(): push_error("Route vanished"); quit(1); return
		var source = route.source
		var work := []
		for agent in tasks._agents.values():
			if agent.current_task_id>=0:
				work.append({"name":agent.dwarf_name,"task":agent.current_task_id,"phase":agent.TaskPhase.keys()[agent._task_phase],"cell":str(agent.current_cell()),"cargo":agent._carried_entries.size()})
		var task = tasks.get_task(source._lease_id) if source != null else null
		var state := JSON.stringify({"built":route.built,"mode":route.mode,"work":work,"lease":source._lease_id if source != null else -1,"status":task.status if task != null else -1,"blocked":task.blocked_count if task != null else 0})
		if state!=last_state:
			print("PLAYER_LADDER_TICK ",state)
			last_state=state
		if route.built==route.height:
			print("PLAYER_LADDER_COMPLETE stock=",stocks.get_available_total("base:resources:furniture:crude_ladder")," materials=",route.materials)
			quit(0); return
	print("PLAYER_LADDER_STALLED ",last_state)
	quit(1)
