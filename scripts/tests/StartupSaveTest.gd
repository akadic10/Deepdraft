extends "res://scripts/tests/SaveManagerRoundTripTest.gd"

## Run --prepare, then --resume in a separate process with the same isolated
## APPDATA. The second run exercises actual first-boot autoload ordering.
var failures: Array[String] = []
var renderer_count := 0
var initial_clock: Dictionary

func _expect(ok: bool, description: String) -> void:
	if not ok: failures.append(description)

func _run() -> void:
	create_timer(240).timeout.connect(func(): push_error("STARTUP_SAVE_TIMEOUT"); quit(1))
	_save_manager = root.get_node("SaveManager")
	_world_generator = root.get_node("WorldGenerator")
	_world_clock = root.get_node("WorldClock")
	initial_clock = _world_clock.serialize_state()
	var preparing := "--prepare" in OS.get_cmdline_user_args()
	if preparing: _cleanup_test_storage()
	_expect(_save_manager.configure_storage_for_testing(TEST_DIRECTORY), "isolated test storage")
	node_added.connect(func(node: Node):
		if node.name == "Renderer" and node.get_script() != null:
			renderer_count += 1
			node.set("world_seed", 1234 if preparing else 9876))
	if not preparing:
		_save_manager.load_finished.connect(_on_load_finished, CONNECT_ONE_SHOT)
	_expect(change_scene_to_file("res://scenes/main/debug_world.tscn") == OK, "main scene starts")
	await process_frame
	await process_frame
	if preparing:
		if not await _wait_for_world_ready(WORLD_TIMEOUT_MSEC): _finish("generation timed out"); return
		_world_clock.set_paused(true)
		_expect(not _save_manager.is_loading() and _world_generator.world_seed == 1234,
			"no-save startup generates the normal fresh world")
		if not _choose_fixture_origin(): _finish("no colony fixture origin"); return
		var error := _build_nonempty_colony_state()
		if not error.is_empty(): _finish(error); return
		_world_clock.restore_state({"year": 4, "season": "winter", "day": 9,
			"hour": 18.5, "speed": 3.0, "paused": true})
		var snapshot: Dictionary = _save_manager._build_snapshot()
		_expect(_save_manager._file_store()._validate_snapshot(snapshot).is_empty(), "nonempty colony fixture validates")
		_test_selection(snapshot)
		# The newer autosave must win at actual startup, not the scene's seed or
		# an older manual file copied later. Keep a real backup and ignored temp.
		_write_save(TEST_AUTOSAVE, snapshot, "2026-10-18 12:00:00")
		_write_save(TEST_PRIMARY, snapshot, "2026-10-18 11:00:00")
		_write_save(TEST_BACKUP, snapshot, "2026-10-18 10:00:00")
		_write_save(TEST_TEMP, snapshot, "2026-10-18 13:00:00")
		print("STARTUP_SAVE_PREPARED")
	else:
		_expect(_save_manager.is_loading(), "first scene is restoring immediately")
		_expect(not _save_manager.request_new_game(), "New Game cannot interrupt restoration")
		var before := _file_hashes()
		if not await _wait_for_load(LOAD_TIMEOUT_MSEC): _finish("startup restore timed out"); return
		_expect(_load_succeeded and not _load_used_backup, "startup loads the latest primary")
		_expect(renderer_count == 1, "startup generates once without a throwaway world")
		_expect(_world_generator.world_seed == 1234, "saved seed wins over scene seed")
		var expected: Dictionary = _save_manager._read_snapshot(TEST_AUTOSAVE).snapshot
		var actual: Dictionary = _save_manager._build_snapshot()
		# Scheduler diagnostics are deliberately reassessed on restore; compare
		# stable order identities and all physical state, as the round-trip test does.
		var identities := {}
		for locator: String in expected.scene.jobs.records:
			var record: Dictionary = expected.scene.jobs.records[locator]
			identities[locator] = {"key": record.key, "label": record.label}
		expected.scene.jobs = {"records": identities}
		var scene_diff := _deep_diff(expected.scene, _collect_scene_state(), "scene")
		_expect(scene_diff.is_empty(), "all colony owners restore exactly: " + scene_diff)
		_expect(_deep_diff(expected.clock, actual.clock, "clock").is_empty(), "saved calendar, speed and pause restore")
		_expect(_deep_diff(expected.weather, actual.weather, "weather").is_empty(), "saved weather and RNG restore")
		var screen = current_scene.get_node("WorldLoadingScreen")
		while not screen._released: await process_frame
		_expect(not _save_manager.is_loading() and screen.loading_state().ready, "loading cover waits for restoration")
		var menu = root.get_node("GameMenu")
		menu.open()
		for _i in 3: await process_frame
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://tmp/startup_resume_20261018/options_menu.png")
		menu._buttons.new_game.pressed.emit()
		var found := false
		for button: Button in menu._ask_buttons.get_children():
			if button.text == "Start a new colony":
				found = true
				button.pressed.emit()
		_expect(found and _save_manager.is_loading() and not menu.is_open(), "the game menu's New game, once confirmed, starts scene replacement")
		await scene_changed
		await process_frame
		_expect(_world_generator.world_seed != 1234 and _world_generator.world_seed != 9876,
			"New Game chooses a fresh seed and bypasses auto-resume")
		_expect(_world_clock.year == initial_clock.year and _world_clock.season == initial_clock.season
			and _world_clock.day == initial_clock.day and is_equal_approx(_world_clock.hour, initial_clock.hour),
			"New Game resets the configured calendar")
		_expect(_world_clock.speed == 1.0 and not _world_clock.serialize_state().paused,
			"New Game resets player speed and pause, retaining loading hold")
		var weather = root.get_node("WeatherManager")
		var weather_before: Dictionary = weather.serialize_state()
		weather.reset_for_new_game()
		_expect(weather_before == weather.serialize_state(), "fresh weather derives from the new world seed")
		if not await _wait_for_world_ready(WORLD_TIMEOUT_MSEC): _finish("new world timed out"); return
		actual = _save_manager._build_snapshot()
		_expect(_save_manager._file_store()._validate_snapshot(actual).is_empty(), "fresh world can be saved")
		_expect(not actual.scene.settlement_flag.founded and actual.scene.dwarves.roster.is_empty(), "old settlement and dwarves are gone")
		_expect(actual.scene.furniture.installed.is_empty() and actual.scene.furniture.ghosts.is_empty(), "old furniture and plans are gone")
		_expect(actual.scene.terrain.edits.is_empty(), "terrain edits are reset")
		# Surface-connected caves are naturally revealed on a fresh world. Only
		# the new seed's exposed cave cells may remain; player exploration is gone.
		var exposed := {}
		var cave_ids: Array = []
		for cave: Dictionary in _world_generator.get_cave_catalog():
			if cave.get("surface_open", false):
				cave_ids.append(cave.id)
				for cell: Vector3i in _world_generator.get_cave_air_cells(cave.id): exposed[cell] = true
		cave_ids.sort()
		_expect(actual.scene.exploration.caves == cave_ids and actual.scene.exploration.cells.size() == exposed.size(),
			"fresh exploration contains only the new world's exposed caves")
		for cell: Array in actual.scene.exploration.cells:
			if not exposed.has(Vector3i(cell[0], cell[1], cell[2])):
				_expect(false, "old player exploration survived New Game")
				break
		_expect(actual.scene.worker_crafting.orders.is_empty(), "crafting queue is reset")
		_expect(root.get_node("TaskManager").get_scheduler_stats().pending_total == 0, "old jobs are gone")
		_expect(_save_manager._autosave_elapsed_seconds < 60.0, "autosave interval restarts")
		_expect(before == _file_hashes(), "auto-resume and New Game leave every save byte unchanged")
		_expect(renderer_count == 2, "one generation per requested world")
		# Explicit Load remains available after New Game and must not auto-select.
		_load_completed = false
		_save_manager.load_finished.connect(_on_load_finished, CONNECT_ONE_SHOT)
		_expect(_save_manager.request_load(), "manual Load still works after New Game")
		if not await _wait_for_load(LOAD_TIMEOUT_MSEC): _finish("manual restore timed out"); return
		_expect(_load_succeeded and _world_generator.world_seed == 1234, "manual save restores after New Game")
	_finish()

func _test_selection(snapshot: Dictionary) -> void:
	_expect(_save_manager._latest_valid_save().is_empty(), "no committed saves is a fresh start")
	_write_save(TEST_AUTOSAVE, snapshot, "2026-10-18 12:00:00")
	_write_save(TEST_PRIMARY, snapshot, "2026-10-18 11:00:00")
	_expect(_save_manager._latest_valid_save().path == TEST_AUTOSAVE, "internal timestamp wins over later file copy")
	_write_save(TEST_PRIMARY, snapshot, "2026-10-18 13:00:00")
	_expect(_save_manager._latest_valid_save().path == TEST_PRIMARY, "newer manual save wins")
	_write_save(TEST_TEMP, snapshot, "2026-10-18 19:00:00")
	_expect(_save_manager._latest_valid_save().path == TEST_PRIMARY, "unfinished temporary save is ignored")
	_write_save(TEST_BACKUP, snapshot, "2026-10-18 13:00:00")
	_expect(_save_manager._latest_valid_save().path == TEST_PRIMARY, "same-timestamp primary preferred over backup")
	_write_save(TEST_BACKUP, snapshot, "2026-10-18 14:00:00")
	_expect(_save_manager._latest_valid_save().path == TEST_BACKUP, "latest valid backup is recoverable")
	var invalid := snapshot.duplicate(true)
	invalid.scene = {}
	_write_save(TEST_BACKUP, invalid, "2026-10-18 15:00:00")
	_expect(_save_manager._latest_valid_save().path == TEST_PRIMARY, "invalid newest save falls back to next valid file")
	for path in [TEST_PRIMARY, TEST_AUTOSAVE]:
		_expect(_save_manager._file_store()._write_text_file(ProjectSettings.globalize_path(path), "{broken").is_empty(), "corrupt fixture written")
	_expect(_save_manager._latest_valid_save().is_empty(), "all invalid saves allow fresh startup")
	_write_save(TEST_AUTOSAVE_BACKUP, snapshot, "2026-10-18 12:00:00")
	var before := _file_hashes()
	var selected: Dictionary = _save_manager._latest_valid_save()
	_expect(selected.path == TEST_AUTOSAVE_BACKUP and selected.backup and selected.autosave, "autosave backup survives damaged primaries")
	_expect(before == _file_hashes(), "startup recovery never rewrites a file")
	# A newer named save wins too, and the notices name it by the name inside it.
	var named := snapshot.duplicate(true)
	named.save_name = "First winter"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEST_NAMED))
	_write_save(TEST_NAMED + "/first_winter.json", named, "2026-10-18 20:00:00")
	selected = _save_manager._latest_valid_save()
	_expect(selected.path == TEST_NAMED + "/first_winter.json" and selected.label == "\"First winter\"" and not selected.autosave,
		"a newer named save wins startup and Continue")
	_cleanup_test_storage()

func _write_save(path: String, snapshot: Dictionary, timestamp: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEST_DIRECTORY))
	var state := snapshot.duplicate(true)
	state.saved_at_utc = timestamp
	_expect(_save_manager._file_store()._write_text_file(ProjectSettings.globalize_path(path), JSON.stringify(state, "\t")).is_empty(), "write fixture " + path)

func _file_hashes() -> Dictionary:
	var hashes := {}
	for path in [TEST_PRIMARY, TEST_BACKUP, TEST_AUTOSAVE, TEST_AUTOSAVE_BACKUP, TEST_TEMP]:
		if FileAccess.file_exists(path): hashes[path] = FileAccess.get_sha256(path)
	return hashes

func _finish(error: String = "") -> void:
	if not error.is_empty(): failures.append(error)
	for failure in failures: push_error(failure)
	print("STARTUP_SAVE_OK" if failures.is_empty() else "STARTUP_SAVE_FAIL")
	quit(0 if failures.is_empty() else 1)
