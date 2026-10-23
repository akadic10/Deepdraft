extends SceneTree

## Run against the exported PCK in an isolated profile holding a copied save.
var failures: Array[String] = []
var output := ""
var reference_path := ""
var rooms: Node
var reference: Node
var comparisons := 0

func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=").trim_suffix("/") + "/"
		if arg.begins_with("--reference="): reference_path = arg.trim_prefix("--reference=")
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func _run() -> void:
	if output.is_empty() or reference_path.is_empty() or not "/room_rebuild_20261014/" in OS.get_user_data_dir().replace("\\", "/"):
		push_error("Room check requires isolated profile, output and frozen reference"); quit(2); return
	if FileAccess.file_exists("res://tools/performance/CameraBenchmark.gd"):
		push_error("Packed check must not resolve loose workspace files"); quit(2); return
	DirAccess.make_dir_recursive_absolute(output)
	create_timer(150).timeout.connect(func(): push_error("Room packed timeout"); quit(1))
	var clock_node := root.get_node("WorldClock")
	var saves := root.get_node("SaveManager")
	rooms = root.get_node("RoomManager")
	clock_node.set_paused(true)
	var placeholder := Node3D.new()
	placeholder.scene_file_path = "res://scenes/main/debug_world.tscn"
	root.add_child(placeholder)
	current_scene = placeholder
	if not saves.request_load(): quit(1); return
	while saves.is_loading(): await process_frame
	saves.set_process(false)
	clock_node.set_paused(true)
	var terrain := current_scene.get_node("Renderer")
	while not terrain.tiles.overview_built or not terrain.tiles.dirty_overview_tiles.is_empty() or terrain.cavity_shell.dirty or terrain.underground_lighting.is_updating(): await process_frame
	await _settle()
	var old_script := GDScript.new()
	old_script.source_code = FileAccess.get_file_as_string(reference_path)
	check(old_script.reload() == OK, "reference compiles against packaged autoloads")
	reference = old_script.new()
	reference.temperature_config = rooms.temperature_config
	reference.appeal_config = rooms.appeal_config
	_compare("saved rooms")
	check(not rooms.get_rooms().is_empty(), "copied settlement has sealed rooms")
	var initial_rooms: int = rooms.get_rooms().size()
	var water := root.get_node("WaterManager")
	var water_before: Dictionary = water.serialize_state()
	var furniture := current_scene.get_node("FurniturePlacementController")
	var door = null
	for piece in furniture._installed.values():
		if piece.def.get("furniture_category", "") == "door":
			door = piece
			break
	check(door != null, "saved settlement has installed door")
	if door != null:
		var key: String = door.furniture_key
		var origin: Vector3i = door.origin_cell
		var yaw: int = door.yaw_steps
		rooms._mark_dirty()
		rooms._process(.5)
		furniture._teardown_installed(door.installed_id, false)
		check(not rooms.get_door_boundaries().has(origin + Vector3i.UP), "door boundary changes immediately")
		await _settle()
		_compare("removed door")
		furniture._install(key, furniture.get_defs()[key], origin, yaw)
		await _settle()
		_compare("reinstalled door")
		check(rooms.get_rooms().size() == initial_rooms, "door repair restores room count")
	check(water_before == water.serialize_state(), "paused room edits preserve water state")
	clock_node.set_speed(1)
	clock_node.set_paused(false)
	await create_timer(5).timeout
	clock_node.set_paused(true)
	await _settle()
	_compare("after active colony")
	var result := {"failures": failures, "comparisons": comparisons,
		"dwarves": current_scene.get_node("DwarfDirector").get_roster().size(),
		"initial_rooms": initial_rooms, "rooms": rooms.get_stats(), "scheduler": rooms.get_rebuild_stats(),
		"room_manager_sha256": FileAccess.get_sha256("res://scripts/systems/RoomManager.gd"),
		"builder_sha256": FileAccess.get_sha256("res://scripts/components/RoomRebuild.gd"),
		"config": rooms.detection_config}
	FileAccess.open(output + "packed_smoke.json", FileAccess.WRITE).store_string(JSON.stringify(result, "  "))
	reference.free()
	print("ROOM_REBUILD_EXPORT_PASS " if failures.is_empty() else "ROOM_REBUILD_EXPORT_FAIL ", JSON.stringify(result))
	root.get_node("WorldGenerator").prepare_for_world_reload()
	quit(0 if failures.is_empty() else 1)

func _settle() -> void:
	await process_frame
	await process_frame
	while rooms.is_updating(): await process_frame

func _compare(label: String) -> void:
	for key in ["_door_cells", "_heat_cells", "_light_cells", "_bed_cells", "_bed_assignments"]:
		reference.set(key, rooms.get(key).duplicate(true))
	reference._rebuild_all_rooms()
	check(reference.get_rooms().size() == rooms.get_rooms().size(), label + ": room count matches")
	check(reference._cell_to_room.size() == rooms._cell_to_room.size(), label + ": cell count matches")
	for room: Dictionary in rooms.get_rooms().values():
		var expected: Dictionary = reference.get_room_at(room.cells.keys()[0])
		# Hourly temperature refresh occurs independently of geometry; compare
		# both detectors at the same current clock without changing room geometry.
		var current: Dictionary = room.duplicate()
		rooms._recompute_temp(current)
		check(current == expected, label + ": all room fields match")
	comparisons += 1
