extends SceneTree

func _init() -> void:
	call_deferred("run")

func run() -> void:
	create_timer(120).timeout.connect(func(): push_error("Live inspection timed out"); quit(1))
	var save = root.get_node("SaveManager")
	save.configure_storage_for_testing("user://live_inspect")
	DirAccess.make_dir_recursive_absolute("user://live_inspect")
	DirAccess.copy_absolute("res://tmp/ladder_mining_live/quicksave.json","user://live_inspect/quicksave.json")
	change_scene_to_file("res://scenes/main/debug_world.tscn")
	await process_frame
	await process_frame
	if not save.request_load(): quit(1); return
	await save.load_finished
	var clock = root.get_node("WorldClock")
	clock.set_paused(true)
	var nav = root.get_node("NavGrid")
	var tasks = root.get_node("TaskManager")
	tasks.set_process(false)
	print("LIVE_LADDERS ",nav._ladders)
	var source = tasks.get_work_source(1)
	for worker in tasks._agents.values():
		worker.set_process(false)
		var start: Vector3i = worker.current_cell()
		var target: Vector3i = source.nearest_stand_target(start)
		var before: int = nav._nodes_expanded_total
		var path = nav.find_path(start,target)
		print("LIVE_PATH ",worker.dwarf_id," from=",start," target=",target," length=",path.size()," expanded=",nav._nodes_expanded_total-before)
		var query = {}
		var status = 0
		while status == 0: status = nav.advance_reachability(query,start,target,1200,Time.get_ticks_usec()+100000)
		print("LIVE_PROBE ",worker.dwarf_id," status=",status," expanded=",query.expanded)
		var stand: Array = []
		for block in source.region:
			for cell in source._walkable_stand_cells(block,start):
				if not cell in stand: stand.append(cell)
		stand.sort_custom(func(a,b): return Vector3(a-start).length_squared()<Vector3(b-start).length_squared())
		for cell in stand.slice(0,15):
			before = nav._nodes_expanded_total
			path = nav.find_path(start,cell)
			print("LIVE_STAND ",cell," path=",path.size()," expansions=",nav._nodes_expanded_total-before)
	print("LIVE_INSPECT_DONE")
	quit()
