extends SceneTree

## Headless integration regression for validated save replacement and backup
## recovery. Run from the project root:
##
## godot --headless --path . --script res://scripts/tests/SaveManagerRoundTripTest.gd

const TEST_DIRECTORY := "user://save_manager_round_trip_test"
const TEST_PRIMARY := TEST_DIRECTORY + "/quicksave.json"
const TEST_BACKUP := TEST_DIRECTORY + "/quicksave.backup.json"
const TEST_TEMP := TEST_DIRECTORY + "/quicksave.tmp.json"
const TEST_BACKUP_STAGE := TEST_DIRECTORY + "/quicksave.backup.tmp.json"
const TEST_AUTOSAVE := TEST_DIRECTORY + "/autosave.json"
const TEST_AUTOSAVE_BACKUP := TEST_DIRECTORY + "/autosave.backup.json"
const TEST_AUTOSAVE_TEMP := TEST_DIRECTORY + "/autosave.tmp.json"
const TEST_AUTOSAVE_BACKUP_STAGE := TEST_DIRECTORY + "/autosave.backup.tmp.json"
const WORLD_TIMEOUT_MSEC := 90000
const LOAD_TIMEOUT_MSEC := 90000
const OWNER_GROUP := "save_state_owner"

var _load_completed := false
var _load_succeeded := false
var _load_used_backup := false
var _save_manager: Node = null
var _world_generator: Node = null
var _world_clock: Node = null


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_save_manager = root.get_node_or_null("SaveManager")
	_world_generator = root.get_node_or_null("WorldGenerator")
	_world_clock = root.get_node_or_null("WorldClock")
	if _save_manager == null or _world_generator == null or _world_clock == null:
		_fail("required autoloads are unavailable")
		return
	_cleanup_test_storage()
	if not bool(_save_manager.call("configure_storage_for_testing", TEST_DIRECTORY)):
		_fail("could not isolate test storage")
		return

	var scene_error := change_scene_to_file("res://scenes/main/debug_world.tscn")
	if scene_error != OK:
		_fail("could not load debug_world.tscn (%s)" % error_string(scene_error))
		return
	await process_frame
	await process_frame
	if not await _wait_for_world_ready(WORLD_TIMEOUT_MSEC):
		_fail("world generation timed out")
		return

	var expected_seed := int(_world_generator.get("world_seed"))
	var setup_error := _build_nonempty_colony_state()
	if not setup_error.is_empty():
		_fail(setup_error)
		return

	# Advancing the timer by one interval must write only the independent
	# autosave slot and must not mutate authoritative scene state.
	var scene_before_autosave := JSON.stringify(_collect_scene_state())
	_save_manager.call("_tick_autosave", 300.0)
	if not FileAccess.file_exists(TEST_AUTOSAVE):
		_fail("five-minute timer did not create an autosave")
		return
	if FileAccess.file_exists(TEST_PRIMARY):
		_fail("autosave overwrote or created the manual quick-save slot")
		return
	var autosave_result: Dictionary = _save_manager.call("_read_snapshot", TEST_AUTOSAVE)
	if not bool(autosave_result.get("ok", false)):
		_fail("autosave did not validate")
		return
	_save_manager.call("_tick_autosave", 300.0)
	if not FileAccess.file_exists(TEST_AUTOSAVE_BACKUP):
		_fail("second autosave did not rotate the previous autosave to backup")
		return
	if scene_before_autosave != JSON.stringify(_collect_scene_state()):
		_fail("autosaving mutated authoritative scene state")
		return

	var scene_before := JSON.stringify(_collect_scene_state())
	if not bool(_save_manager.call("request_save")):
		_fail("first validated save failed")
		return
	var scene_after := JSON.stringify(_collect_scene_state())
	if scene_before != scene_after:
		_fail("saving mutated authoritative scene state")
		return

	# The second save must rotate the first valid snapshot to the backup.
	_world_clock.call("restore_state", {
		"day": 9,
		"season": "winter",
		"year": 4,
		"hour": 18.5,
		"speed": 3.0,
		"paused": true,
	})
	if not bool(_save_manager.call("request_save")):
		_fail("second save/backup rotation failed")
		return
	if not FileAccess.file_exists(TEST_BACKUP):
		_fail("validated backup was not created")
		return

	# The autosave must be independently loadable and must not use the manual
	# primary or backup created above.
	_load_completed = false
	_load_succeeded = false
	_load_used_backup = false
	_save_manager.connect("load_finished", _on_load_finished, CONNECT_ONE_SHOT)
	if not bool(_save_manager.call("request_load_autosave")):
		_fail("autosave load did not start")
		return
	if not await _wait_for_load(LOAD_TIMEOUT_MSEC):
		_fail("autosave load timed out")
		return
	if not _load_succeeded or _load_used_backup:
		_fail("autosave did not load from its independent primary slot")
		return
	var autosave_verification_error := _verify_restored_state(expected_seed)
	if not autosave_verification_error.is_empty():
		_fail("autosave: %s" % autosave_verification_error)
		return

	# Fault injection stays inside SaveManager, the sole save-file I/O owner.
	var corrupt_error := String(_save_manager.call("_write_text_file", TEST_PRIMARY, "{invalid json"))
	if not corrupt_error.is_empty():
		_fail("could not inject a corrupt primary: %s" % corrupt_error)
		return

	_load_completed = false
	_load_succeeded = false
	_load_used_backup = false
	_save_manager.connect("load_finished", _on_load_finished, CONNECT_ONE_SHOT)
	if not bool(_save_manager.call("request_load")):
		_fail("backup load did not start")
		return
	if not await _wait_for_load(LOAD_TIMEOUT_MSEC):
		_fail("backup load timed out")
		return
	if not _load_succeeded or not _load_used_backup:
		_fail("load did not complete through the backup path")
		return

	var verification_error := _verify_restored_state(expected_seed)
	if not verification_error.is_empty():
		_fail(verification_error)
		return

	var repaired_primary: Dictionary = _save_manager.call("_read_snapshot", TEST_PRIMARY)
	if not bool(repaired_primary.get("ok", false)):
		_fail("backup load did not repair the primary slot")
		return

	print("SAVE_MANAGER_ROUND_TRIP_OK")
	_cleanup_and_quit(0)


func _build_nonempty_colony_state() -> String:
	var mining := _owner("mining")
	var flag := _owner("settlement_flag")
	var stockpiles := _owner("stockpiles")
	var furniture := _owner("furniture")
	var items := _owner("items")
	var dwarves := _owner("dwarves")
	var camera := _owner("camera")
	var slice := _owner("slice")
	if [mining, flag, stockpiles, furniture, items, dwarves, camera, slice].has(null):
		return "one or more save-state owners are missing"

	var flag_cell := _surface_cell(0, 0)
	var dwarf_cell := _surface_cell(2, 0)
	var stockpile_cell := _surface_cell(4, 0)
	var furniture_cell := _surface_cell(6, 0)
	var ghost_cell := _surface_cell(8, 0)
	var item_cell := _surface_cell(10, 0)
	var mined_cell := _surface_cell(12, 0)
	var designated_cell := _surface_cell(14, 0)

	mining.call("restore_state", {
		"mined_blocks": [_pack_v3i(mined_cell)],
		"zones": [{ "id": 101, "blocks": [_pack_v3i(designated_cell)] }],
	})
	flag.call("restore_state", {
		"placed": true,
		"cell": _pack_v3i(flag_cell),
	})
	stockpiles.call("restore_state", {
		"zones": [{
			"id": 201,
			"cells": [_pack_v3i(stockpile_cell)],
			"filter_tags": ["stockpile_stone"],
			"stacks": [{
				"cell": _pack_v3i(stockpile_cell),
				"item": "base:resources:stone:rough_stone",
				"count": 1,
			}],
		}],
	})
	furniture.call("restore_state", {
		"ghosts": [{
			"id": 301,
			"key": "base:furniture:storage_shelf",
			"origin": _pack_v3i(ghost_cell),
			"yaw": 0,
		}],
		"installed": [{
			"id": 401,
			"key": "base:furniture:barrel",
			"origin": _pack_v3i(furniture_cell),
			"yaw": 0,
			"flagged_uninstall": false,
			"inventory": { "base:resources:stone:rough_stone": 2 },
		}],
	})
	items.call("restore_state", {
		"loose": [{
			"item_key": "base:resources:stone:rough_stone",
			"position": _pack_v3(Vector3(
				float(item_cell.x) + 0.5, float(item_cell.y) + 1.05, float(item_cell.z) + 0.5)),
			"rotation_y": 0.25,
		}],
	})
	dwarves.call("restore_state", {
		"birth_index": 1,
		"settlement_anchor": _pack_v3i(flag_cell),
		"roster": [{
			"id": 0,
			"name": "Testur",
			"gender": "male",
			"appearance": {
				"gender": "male",
				"age_tier": "adult",
				"skin_tone": "medium",
				"eye_color": "grey",
				"hair_color": "brown",
				"hair_style": "short_back",
				"eyebrow_style": "thick_flat",
				"beard_style": "",
				"scar": "none",
			},
			"traits": [],
			"profession": "base:profession:worker",
			"profession_experience": { "base:profession:worker": 7 },
			"position": _pack_v3(Vector3(
				float(dwarf_cell.x) + 0.5, float(dwarf_cell.y) + 1.0, float(dwarf_cell.z) + 0.5)),
			"rotation_y": 0.5,
			"sleep": 0.4,
			"sleeping": true,
			"sleep_hours_left": 2.5,
			"carried_items": [],
		}],
	})
	camera.call("restore_state", {
		"target_position": _pack_v3(Vector3(520.0, 64.0, 500.0)),
		"zoom": 42.0,
		"pitch": -55.0,
		"orbit_y": 25.0,
	})
	slice.call("restore_state", {
		"active": true,
		"seeded": true,
		"slice_y": 25,
		"last_slice_y": 25,
	})
	_world_clock.call("restore_state", {
		"day": 7,
		"season": "autumn",
		"year": 3,
		"hour": 6.25,
		"speed": 2.0,
		"paused": true,
	})
	return ""


func _verify_restored_state(expected_seed: int) -> String:
	if int(_world_generator.get("world_seed")) != expected_seed:
		return "world seed did not round-trip"
	if int(_world_clock.get("day")) != 7 \
			or String(_world_clock.get("season")) != "autumn" \
			or int(_world_clock.get("year")) != 3:
		return "calendar did not restore from the saved snapshot"
	if not is_equal_approx(float(_world_clock.get("hour")), 6.25) \
			or not is_equal_approx(float(_world_clock.get("speed")), 2.0):
		return "clock hour/speed did not restore from the backup snapshot"
	if not bool(_world_clock.get("paused")):
		return "clock paused state did not round-trip"

	var scene_state := _collect_scene_state()
	var expected_keys := [
		"mining", "settlement_flag", "stockpiles", "furniture",
		"items", "dwarves", "camera", "slice",
	]
	for key in expected_keys:
		if not scene_state.has(key):
			return "restored scene is missing section %s" % key
	if (scene_state["mining"] as Dictionary).get("mined_blocks", []).size() != 1:
		return "mined blocks did not round-trip"
	if (scene_state["mining"] as Dictionary).get("zones", []).size() != 1:
		return "mining zones did not round-trip"
	if not bool((scene_state["settlement_flag"] as Dictionary).get("placed", false)):
		return "settlement flag did not round-trip"
	if (scene_state["stockpiles"] as Dictionary).get("zones", []).size() != 1:
		return "stockpile state did not round-trip"
	var furniture_state := scene_state["furniture"] as Dictionary
	if furniture_state.get("ghosts", []).size() != 1 or furniture_state.get("installed", []).size() != 1:
		return "furniture state did not round-trip"
	if (scene_state["items"] as Dictionary).get("loose", []).size() != 1:
		return "loose items did not round-trip"
	var roster: Array = (scene_state["dwarves"] as Dictionary).get("roster", [])
	if roster.size() != 1 or not bool((roster[0] as Dictionary).get("sleeping", false)):
		return "dwarf roster/runtime state did not round-trip"
	var camera_state := scene_state["camera"] as Dictionary
	if not is_equal_approx(float(camera_state.get("zoom", 0.0)), 42.0):
		return "camera state did not round-trip"
	var slice_state := scene_state["slice"] as Dictionary
	if not bool(slice_state.get("active", false)) or int(slice_state.get("slice_y", -1)) != 25:
		return "slice state did not round-trip"
	return ""


func _collect_scene_state() -> Dictionary:
	var result: Dictionary = {}
	for state_owner in get_nodes_in_group(OWNER_GROUP):
		if state_owner.has_method("save_section_key") and state_owner.has_method("serialize_state"):
			result[String(state_owner.call("save_section_key"))] = state_owner.call("serialize_state")
	return result


func _owner(section_key: String) -> Node:
	for state_owner in get_nodes_in_group(OWNER_GROUP):
		if state_owner.has_method("save_section_key") \
				and String(state_owner.call("save_section_key")) == section_key:
			return state_owner
	return null


func _surface_cell(offset_x: int, offset_z: int) -> Vector3i:
	var x := 512 + offset_x
	var z := 491 + offset_z
	return Vector3i(x, int(_world_generator.call("get_surface_y", x, z)), z)


func _wait_for_world_ready(timeout_msec: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_msec
	while Time.get_ticks_msec() < deadline:
		var stats: Dictionary = _world_generator.call("get_streaming_stats")
		if bool(stats.get("maps_ready", false)) and not bool(_world_generator.call("is_generating")):
			return true
		await process_frame
	return false


func _wait_for_load(timeout_msec: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_msec
	while not _load_completed and Time.get_ticks_msec() < deadline:
		await process_frame
	return _load_completed


func _on_load_finished(success: bool, used_backup: bool) -> void:
	_load_succeeded = success
	_load_used_backup = used_backup
	_load_completed = true


func _fail(message: String) -> void:
	push_error("SAVE_MANAGER_ROUND_TRIP_FAIL: %s" % message)
	_cleanup_and_quit(1)


func _cleanup_and_quit(exit_code: int) -> void:
	if _save_manager != null:
		_save_manager.call("reset_storage_after_testing")
	_cleanup_test_storage()
	quit(exit_code)


func _pack_v3i(value: Vector3i) -> Array:
	return [value.x, value.y, value.z]


func _pack_v3(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


func _cleanup_test_storage() -> void:
	for path in [
		TEST_PRIMARY, TEST_BACKUP, TEST_TEMP, TEST_BACKUP_STAGE,
		TEST_AUTOSAVE, TEST_AUTOSAVE_BACKUP, TEST_AUTOSAVE_TEMP,
		TEST_AUTOSAVE_BACKUP_STAGE,
	]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var absolute_directory := ProjectSettings.globalize_path(TEST_DIRECTORY)
	if DirAccess.dir_exists_absolute(absolute_directory):
		# The fixed test directory is removed only when the exact files above left it empty.
		DirAccess.remove_absolute(absolute_directory)
