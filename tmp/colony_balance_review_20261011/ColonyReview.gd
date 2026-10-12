extends SceneTree

var loaded := false
var succeeded := false

func _init() -> void: _run.call_deferred()

func _run() -> void:
	create_timer(180).timeout.connect(func(): push_error("Colony review timed out"); quit(1))
	var saves := root.get_node("SaveManager")
	saves.configure_storage_for_testing("user://colony_review")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://colony_review"))
	var input := "res://tmp/colony_balance_review_20261011/player_quicksave.json"
	DirAccess.copy_absolute(ProjectSettings.globalize_path(input),ProjectSettings.globalize_path("user://colony_review/quicksave.json"))
	saves.load_finished.connect(func(ok: bool, _backup: bool): loaded = true; succeeded = ok)
	change_scene_to_file("res://scenes/main/debug_world.tscn")
	for i in range(12): await process_frame
	if not saves.request_load(): quit(1); return
	while not loaded: await process_frame
	if not succeeded: quit(1); return
	root.get_node("WorldClock").set_paused(true)
	var rooms := root.get_node("RoomManager")
	rooms._rebuild_all_rooms()
	var report := {"rooms":[],"dwarves":[],"mined_counts":{},"mined_y":{},"rock_cover_min":9999,"rock_cover_max":-1}
	for room: Dictionary in rooms._rooms.values():
		var row := room.duplicate()
		row.erase("cells")
		report.rooms.append(row)
	var tasks := root.get_node("TaskManager")
	for agent in tasks._agents.values():
		var room: Dictionary = rooms.get_room_at(agent.current_cell()+Vector3i.UP)
		report.dwarves.append({"name":agent.dwarf_name,"id":agent.dwarf_id,"cell":str(agent.current_cell()),"room_id":room.get("id",-1),"room_type":room.get("room_type","outside"),"owner":room.get("owner_id",-1),"clear_idle_stop":agent._idle_behavior._clear_stop(agent.current_cell())})
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(input))
	var generator := root.get_node("WorldGenerator")
	var blocks := root.get_node("BlockRegistry")
	for cell: Array in data.scene.mining.mined_blocks:
		var block_id: int = generator.get_generated_block_id(int(cell[0]),int(cell[1]),int(cell[2]))
		var key: String = blocks.get_key(block_id)
		report.mined_counts[key] = int(report.mined_counts.get(key,0))+1
		var y := int(cell[1])
		report.mined_y[y] = int(report.mined_y.get(y,0))+1
		var cover: int = generator.get_surface_y(int(cell[0]),int(cell[2]))-y
		report.rock_cover_min = mini(report.rock_cover_min,cover)
		report.rock_cover_max = maxi(report.rock_cover_max,cover)
	var output := FileAccess.open("res://tmp/colony_balance_review_20261011/report.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(report,"  "))
	print("COLONY_REVIEW ",JSON.stringify(report))
	quit()
