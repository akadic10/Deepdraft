extends SceneTree

var loaded := false
var succeeded := false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	create_timer(600).timeout.connect(func(): push_error("Berry probe timeout"); quit(1))
	var saves := root.get_node("SaveManager")
	saves.configure_storage_for_testing("user://berry_probe")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://berry_probe"))
	var copy := FileAccess.open("user://berry_probe/quicksave.json",FileAccess.WRITE)
	var snapshot: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tmp/berry_move_20261012/player_quicksave.json"))
	# Archived fixture predates the flag-as-furniture change. Normalize only the
	# isolated investigation copy; no production migration or player save edit.
	if snapshot.scene.settlement_flag.has("placed"):
		snapshot.scene.settlement_flag["founded"] = snapshot.scene.settlement_flag.placed
		snapshot.scene.furniture.installed.append({"id":99,"key":"base:furniture:settlement_flag","origin":snapshot.scene.settlement_flag.cell,"yaw":0,"layout_version":1,"material_id":"","flagged_uninstall":false})
		snapshot.scene.settlement_flag.erase("placed")
	copy.store_string(JSON.stringify(snapshot))
	copy.close()
	saves.load_finished.connect(func(ok: bool, _backup: bool): loaded = true; succeeded = ok)
	change_scene_to_file("res://scenes/main/debug_world.tscn")
	for i in range(12): await process_frame
	if not saves.request_load(): push_error(str(saves._read_snapshot("user://berry_probe/quicksave.json"))); quit(1); return
	while not loaded: await process_frame
	if not succeeded: quit(1); return
	var clock := root.get_node("WorldClock")
	var tasks := root.get_node("TaskManager")
	var furniture := get_first_node_in_group("furniture_controller")
	var details := get_first_node_in_group("surface_details")
	var expected := {}
	for ghost in furniture._ghosts.values(): expected[ghost.required_instance_id] = ghost.origin_cell
	clock.set_speed(1.0)
	clock.set_paused(false)
	var start := Time.get_ticks_msec()
	var next := 0
	while Time.get_ticks_msec()-start < 480000:
		await process_frame
		if furniture._ghosts.is_empty():
			for id: String in expected:
				if details._records[id].origin != expected[id] or details._changes[id].removed or details._changes[id].packed:
					push_error("Incorrect restored plant: "+id); quit(1); return
			if not tasks.lifecycle_errors().is_empty(): push_error(str(tasks.lifecycle_errors())); quit(1); return
			print("SAVED_BERRY_MOVE_OK count=",expected.size()," elapsed=",(Time.get_ticks_msec()-start)/1000.0)
			quit(0); return
		if Time.get_ticks_msec()-start < next: continue
		next += 5000
		var workers := []
		for agent in tasks._agents.values():
			workers.append({"id":agent.dwarf_id,"task":agent.current_task_id,"phase":agent.TaskPhase.keys()[agent._task_phase],"cell":str(agent.current_cell()),"cargo":agent._carried_entries.size(),"available":tasks.worker_availability(agent)})
		var queries := []
		for type in tasks._surface_matches:
			var ctx: Dictionary = tasks._surface_matches[type]
			var query: Dictionary = ctx.get("route_query",{})
			queries.append({"type":type,"task":ctx.get("task_id",-1),"candidate":ctx.get("probe_index",-1),"expanded":query.get("expanded",-1),"status":query.get("status",-1),"start":str(query.get("start",null)),"goal":str(query.get("goal",null)),"pool":ctx.get("idle_version",-1)})
		var jobs := []
		for row: Dictionary in tasks.job_diagnostics():
			if row.label in ["Wild strawberry","TreeFellingComponent"]: jobs.append({"id":row.key,"state":row.state,"reason":row.reason,"attempts":row.attempts})
		print("BERRY_TICK ",JSON.stringify({"sec":next/1000,"workers":workers,"idle":tasks._idle_dwarves,"pool":tasks._idle_version,"queries":queries,"ghosts":furniture._ghosts.keys(),"jobs":jobs}))
	push_error("Saved berry moves did not complete")
	quit(1)
