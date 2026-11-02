extends "res://scripts/tests/BedroomTest.gd"

## Compare every room field against the frozen detector, then exercise the
## production scheduler through edits, furniture changes and world teardown.
var reference: Node
var comparisons := 0
var commits := 0
var slices := 0

func _run() -> void:
	create_timer(150).timeout.connect(func(): push_error("Room scheduling timeout"); quit(1))
	await _setup_crafting_fixture()
	root.get_node("WorldGenerator").waterline_map.resize(1024 * 1024)
	root.get_node("WorldGenerator").waterline_map.fill(-1)
	rooms = root.get_node("RoomManager")
	rooms.clear_runtime_state()
	clock_node.set_paused(true)
	var old_script := GDScript.new()
	old_script.source_code = FileAccess.get_file_as_string("res://docs/00_dev_roadmap/concepts/room_rebuild_20261014/RoomManager.before.txt")
	_expect(old_script.reload() == OK, "frozen reference compiles")
	reference = old_script.new()
	# The frozen detector reads the climate keys it was written with. Its climate fields are
	# not compared (doc 34's climate replaced them on 2026-10-29); its geometry and bedrooms are.
	reference.temperature_config = {"rock_temperature_c": 10.0, "seasonal_swing_c": 6.0, "daily_swing_c": 2.0,
		"sealed_exposure": 0.25, "cover_damping_blocks": 16.0, "minimum_heated_volume": 128.0,
		"cold_below_c": 8.0, "comfortable_min_c": 16.0, "comfortable_max_c": 26.0}
	reference.appeal_config = rooms.appeal_config
	rooms.detection_config = {"rebuild_budget_ms": 0.01, "budget_check_operations": 1}
	rooms.room_updated.connect(_observe_commit)
	_build_bedroom()
	door = _put("door", Vector3i(63,20,60))
	bed = _put("log_bed", Vector3i(62,20,64))
	lamp = _put("wooden_torch", Vector3i(68,20,64))
	rooms.on_bed_assignment_changed(bed.origin_cell, 141)
	var heater = _put("hearth", Vector3i(66,20,66))
	_drain_and_compare("initial personal heated bedroom")
	_expect(rooms.get_room_at(room_probe).room_type == "personal_bedroom", "initial bedroom ownership")
	# Keep two maps coherent throughout pending work and every signal callback.
	rooms._mark_dirty()
	rooms._process(.5)
	_expect(rooms._rebuild != null, "small budget yields unfinished work")
	var job = rooms._rebuild
	rooms._on_chunk_dirtied(60,7,60)
	_expect(rooms._rebuild == job, "distant streaming preserves pending progress")
	_drain_and_compare("distant streaming")
	# Alter a wall the job has already read, and a far room it has not reached.
	rooms._mark_dirty()
	rooms._process(.5)
	while rooms._rebuild != null and not rooms._rebuild.read_chunks.has(Vector3i(3,1,3)):
		rooms._process(.016)
	var cancelled: int = rooms.get_rebuild_stats().cancelled
	world.set_block(60,22,62, blocks.AIR_ID)
	_expect(rooms._rebuild == null and rooms.get_rebuild_stats().cancelled > cancelled, "mining an examined wall cancels stale work")
	_drain_and_compare("wall breach")
	_expect(rooms.get_room_at(room_probe).is_empty(), "breach removes room")
	world.set_block(60,22,62, blocks.get_id("base:terrain:rock:rock01"))
	_drain_and_compare("wall repair")
	# A roof breach during construction, then repair, never leaks partial rooms.
	rooms._mark_dirty()
	rooms._process(.5)
	world.set_block(64,25,64, blocks.AIR_ID)
	_drain_and_compare("roof breach")
	_expect(rooms.get_room_at(room_probe).is_empty(), "roof opening unseals")
	world.set_block(64,25,64, blocks.get_id("base:terrain:rock:rock01"))
	_drain_and_compare("roof repair")
	# Ownership and light changes while pending must reach the committed room.
	rooms._mark_dirty()
	rooms._process(.5)
	rooms.on_bed_assignment_changed(bed.origin_cell, 142)
	_drain_and_compare("ownership during scan")
	_expect(rooms.get_room_at(room_probe).owner_id == 142, "pending ownership not stale")
	rooms._mark_dirty()
	rooms._process(.5)
	furniture._teardown_installed(lamp.installed_id, false)
	furniture._teardown_installed(heater.installed_id, false)
	_drain_and_compare("light removed during scan")
	_expect(rooms.get_room_at(room_probe).room_type == "room", "missing light revokes bedroom")
	lamp = _put("wooden_torch", Vector3i(68,20,64))
	# Add a second enclosed room sharing a two-wide door with the first.
	_build_second_room()
	_drain_and_compare("shared door separates two rooms")
	_expect(rooms.get_rooms().size() == 2, "shared boundary keeps two rooms")
	# Restart/reload discards old jobs and registrations before furniture restore.
	var saved: Dictionary = JSON.parse_string(JSON.stringify(furniture.serialize_state()))
	rooms._mark_dirty()
	rooms._process(.5)
	for id in furniture._installed.keys(): furniture._teardown_installed(id, false)
	rooms.clear_runtime_state()
	_expect(not rooms.is_updating() and rooms.get_rooms().is_empty(), "reload clears pending and published rooms")
	furniture.restore_state(saved)
	_drain_and_compare("furniture restore after cancelled scan")
	# Installed door boundaries are immediate even though room results are deferred.
	var door_id: int = furniture._cell_to_installed[Vector3i(63,20,60)]
	furniture._teardown_installed(door_id, false)
	_expect(not rooms.get_door_boundaries().has(Vector3i(63,22,60)), "door light boundary removal immediate")
	_drain_and_compare("exterior door removed")
	# Hour advances during a job use the latest temperature when it publishes.
	rooms._mark_dirty()
	rooms._process(.5)
	clock_node.hour = 19
	rooms._on_hour_changed(19)
	_drain_and_compare("latest clock at publication")
	# Preserve the exact inclusive room-size limit, including a tall hall.
	_build_limit_hall()
	_drain_and_compare("4096 cell hall")
	_expect(rooms.get_room_at(Vector3i(101,21,101)).get("volume", 0) == 4096, "4096 cells are still sealed")
	var stone: int = blocks.get_id("base:terrain:rock:rock01")
	for z in range(100,118):
		for y in range(20,38):
			world.set_block(118,y,z,stone)
			if z > 100 and z < 117 and y > 20 and y < 37: world.set_block(117,y,z,blocks.AIR_ID)
	_drain_and_compare("hall beyond leak limit")
	_expect(rooms.get_room_at(Vector3i(101,21,101)).is_empty(), "larger hall retains original leak approximation")
	# Clearing without a replacement must never republish the old world.
	rooms._mark_dirty()
	rooms._process(.5)
	rooms.clear_runtime_state()
	rooms._process(1)
	_expect(rooms.get_rooms().is_empty() and not rooms.is_updating(), "old world cannot publish after clear")
	reference.free()
	var result := {"failures": failures, "comparisons": comparisons, "commits_observed": commits, "scheduler_slices": slices}
	DirAccess.make_dir_recursive_absolute("res://tmp/room_rebuild_20261014")
	FileAccess.open("res://tmp/room_rebuild_20261014/scheduling.json", FileAccess.WRITE).store_string(JSON.stringify(result, "  "))
	for failure: String in failures: push_error(failure)
	print("ROOM_REBUILD_SCHEDULING_PASS " if failures.is_empty() else "ROOM_REBUILD_SCHEDULING_FAIL ", JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)

func _drain_and_compare(label: String) -> void:
	var previous: Dictionary = rooms.get_rooms()
	var previous_cells: Dictionary = rooms._cell_to_room
	var previous_snapshot := previous.duplicate(true)
	var cells_snapshot := previous_cells.duplicate()
	var completed: int = rooms.get_rebuild_stats().completed
	for i in 100000:
		if not rooms.is_updating(): break
		rooms._process(.016)
		slices += 1
		if rooms.get_rebuild_stats().completed == completed:
			_expect(rooms.get_rooms() == previous and rooms._cell_to_room == previous_cells, label + ": pending maps unchanged")
	_expect(not rooms.is_updating(), label + ": scan terminates")
	_expect(previous == previous_snapshot and previous_cells == cells_snapshot, label + ": previous maps never mutated")
	for key in ["_door_cells", "_heat_cells", "_light_cells", "_bed_cells", "_bed_assignments"]:
		reference.set(key, rooms.get(key).duplicate(true))
	reference._rebuild_all_rooms()
	_expect(reference.get_rooms().size() == rooms.get_rooms().size(), label + ": exact room count")
	_expect(reference._cell_to_room.size() == rooms._cell_to_room.size(), label + ": exact cell count")
	for room: Dictionary in rooms.get_rooms().values():
		var other: Dictionary = reference.get_room_at(room.cells.keys()[0]).duplicate()
		var mine: Dictionary = room.duplicate()
		# Tended fires (2026-10-30) make the heat bonus follow the climate too.
		for key in ["seasonal_influence", "temp_c", "is_frozen_vault", "own_form", "temp_form", "heat_bonus_c", "heat_cap_c"]:
			other.erase(key)
			mine.erase(key)
		_expect(mine == other, label + ": exact geometry, heat and bedroom fields")
		_expect(is_equal_approx(float(room.seasonal_influence), _expected_influence(room)), label + ": the season reaches the room through its cover")
		_expect(is_equal_approx(rooms.climate.form_temperature(room.own_form), rooms.climate.temperature(float(room.mean_floor_y), float(room.seasonal_influence), 0.0) + float(room.heat_bonus_c)),
			label + ": on its own the room is the climate's plus its heat")
		_expect(is_equal_approx(float(room.temp_c), rooms.climate.form_temperature(room.temp_form)), label + ": the room's temperature is its form's after the doors leak")
	comparisons += 1

## The season's share by the climate's rule: the mean over the room's columns of its rock
## share under the solid blocks over the column's lowest air.
func _expected_influence(room: Dictionary) -> float:
	var lowest := {}
	for cell: Vector3i in room.cells:
		var column := Vector2i(cell.x, cell.z)
		if not lowest.has(column) or cell.y < int(lowest[column]): lowest[column] = cell.y
	var total := 0.0
	for column: Vector2i in lowest:
		total += rooms.climate.rock_share(rooms.climate.cover_above(Vector3i(column.x, int(lowest[column]), column.y)))
	return total / maxi(1, lowest.size())

func _observe_commit(_id: int) -> void:
	commits += 1
	for id: int in rooms.get_rooms():
		for cell: Vector3i in rooms.get_rooms()[id].cells:
			_expect(rooms.get_room_id_at(cell) == id, "signal observer sees complete matching maps")

func _build_second_room() -> void:
	var stone: int = blocks.get_id("base:terrain:rock:rock01")
	for x in range(69,79):
		for z in range(60,70):
			for y in range(20,26):
				var solid := x in [69,78] or z in [60,69] or y in [20,25]
				world.set_block(x,y,z,stone if solid else blocks.AIR_ID)
	for z in [64,65]:
		for y in range(21,25): world.set_block(69,y,z,blocks.AIR_ID)
	_put("door", Vector3i(69,20,64), 1)

func _build_limit_hall() -> void:
	var stone: int = blocks.get_id("base:terrain:rock:rock01")
	for x in range(100,118):
		for z in range(100,118):
			for y in range(20,38):
				var solid := x in [100,117] or z in [100,117] or y in [20,37]
				world.set_block(x,y,z,stone if solid else blocks.AIR_ID)
	for x in [107,108]:
		for y in range(21,25): world.set_block(x,y,100,blocks.AIR_ID)
	_put("door", Vector3i(107,20,100))
