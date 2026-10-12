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
	# Test-only normalization of the archived fixture's diagnostic schema.
	# The original player's file is opened read-only and never rewritten.
	var fixture := "res://tmp/ladder_extension_20261011/player_quicksave.json"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--save="): fixture = argument.trim_prefix("--save=")
	if not FileAccess.file_exists(fixture): push_error("Supply the archived ladder save with --save=..."); quit(1); return
	var snapshot: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(fixture))
	if not snapshot.scene.has("jobs"):
		snapshot.scene["jobs"] = {"next_order":1,"next_attempt":1,"time":0.0,"records":{},"history":[]}
	var number := 1
	for order: Dictionary in snapshot.scene.worker_crafting.orders:
		if not order.has("id"): order["id"] = number
		number += 1
	var copy := FileAccess.open("user://ladder_probe/quicksave.json",FileAccess.WRITE)
	copy.store_string(JSON.stringify(snapshot))
	copy.close()
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
	var stocks := root.get_node("StockpileManager")
	var initial: Dictionary = ladders.routes.get(1,{})
	if initial.is_empty() or int(initial.built)!=4 or int(initial.height)!=12 or stocks.get_available_total("base:resources:furniture:crude_ladder")!=2:
		push_error("Fixture must contain the saved 4/12 ladder and two stored kits"); quit(1); return
	print("PLAYER_LADDER routes=",ladders.serialize_state()," stock=",stocks.get_available_total("base:resources:furniture:crude_ladder"))
	clock.set_paused(false)
	clock.set_speed(2.0)
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec()-started < 45000:
		await process_frame
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
			if not tasks.lifecycle_errors().is_empty(): push_error(str(tasks.lifecycle_errors())); quit(1); return
			if stocks.get_available_total("base:resources:furniture:crude_ladder")!=0 or route.materials.size()!=3 or not route.materials.all(func(material): return material=="base:material:pine"):
				push_error("Ladder completion did not conserve the two kits and three pine sections"); quit(1); return
			print("SAVED_LADDER_JOB_OK stock=",stocks.get_available_total("base:resources:furniture:crude_ladder")," materials=",route.materials)
			quit(0); return
	print("PLAYER_LADDER_STALLED ",last_state)
	quit(1)
