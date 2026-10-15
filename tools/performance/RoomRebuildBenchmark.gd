extends "res://scripts/tests/RoomRebuildSchedulingTest.gd"

## Isolated deterministic CPU comparison, separate from native camera timings.
func _run() -> void:
	var destination := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): destination = arg.trim_prefix("--output=")
	if destination.is_empty(): push_error("Benchmark requires output"); quit(2); return
	await _setup_crafting_fixture()
	var generator := root.get_node("WorldGenerator")
	generator.waterline_map.resize(1024 * 1024)
	generator.waterline_map.fill(-1)
	rooms = root.get_node("RoomManager")
	rooms.clear_runtime_state()
	clock_node.set_paused(true)
	var old_script := GDScript.new()
	old_script.source_code = FileAccess.get_file_as_string("res://docs/00_dev_roadmap/concepts/room_rebuild_20261014/RoomManager.before.txt")
	_expect(old_script.reload() == OK, "reference compiles")
	reference = old_script.new()
	reference.temperature_config = rooms.temperature_config
	reference.appeal_config = rooms.appeal_config
	_build_bedroom()
	_put("door", Vector3i(63,20,60))
	_put("log_bed", Vector3i(62,20,64))
	_put("wooden_torch", Vector3i(68,20,64))
	var cases := []
	cases.append(_measure_case("one_room"))
	_build_second_room()
	cases.append(_measure_case("shared_door"))
	_build_limit_hall()
	cases.append(_measure_case("4096_cell_hall"))
	var result := {"cases": cases, "failures": failures,
		"room_manager_sha256": FileAccess.get_sha256("res://scripts/systems/RoomManager.gd"),
		"builder_sha256": FileAccess.get_sha256("res://scripts/components/RoomRebuild.gd"),
		"config": rooms.detection_config}
	FileAccess.open(destination, FileAccess.WRITE).store_string(JSON.stringify(result, "  "))
	reference.free()
	for failure: String in failures: push_error(failure)
	print("ROOM_CPU_BENCHMARK_PASS " if failures.is_empty() else "ROOM_CPU_BENCHMARK_FAIL ", JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)

func _measure_case(label: String) -> Dictionary:
	for key in ["_door_cells", "_heat_cells", "_light_cells", "_bed_cells", "_bed_assignments"]:
		reference.set(key, rooms.get(key).duplicate(true))
	reference._rebuild_all_rooms()
	rooms._rebuild_all_rooms()
	var before := []
	var after := []
	var slices_ms := []
	var counts := []
	for trial in 12:
		# Alternate order to avoid assigning every cold/early iteration to one path.
		for mode in ([0,1] if trial % 2 == 0 else [1,0]):
			if mode == 0:
				var start := Time.get_ticks_usec()
				reference._rebuild_all_rooms()
				before.append((Time.get_ticks_usec() - start) / 1000.0)
			else:
				rooms._mark_dirty()
				var total := 0.0
				var count := 0
				while rooms.is_updating():
					var start := Time.get_ticks_usec()
					rooms._process(.5 if count == 0 else .016)
					var elapsed := (Time.get_ticks_usec() - start) / 1000.0
					total += elapsed
					slices_ms.append(elapsed)
					count += 1
				after.append(total)
				counts.append(count)
		_expect(reference._cell_to_room.size() == rooms._cell_to_room.size(), label + ": cell count")
		for room: Dictionary in rooms.get_rooms().values():
			_expect(room == reference.get_room_at(room.cells.keys()[0]), label + ": exact fields")
	return {"case": label, "before_ms": before, "after_cpu_ms": after,
		"slice_ms": slices_ms, "slice_counts": counts, "rooms": rooms.get_rooms().size()}
