extends "res://scripts/tests/SaveManagerRoundTripTest.gd"

## The title screen and Quit to main menu (doc 23, "The title screen"), end to end, with
## SaveManager's real files in isolated test storage:
## - the game opens on the title, which holds the clock;
## - without a save: New game leads and has focus, Esc never opens the game menu, Settings and
##   Load open the game menu's own pages and close back to the title, Exit quits at once, and
##   closing the window quits at once;
## - Enter on New game makes a world; the game menu's Quit to main menu asks first, and Save
##   and quit writes the colony and returns to the title, with the world gone;
## - the title then shows that save on its board with Continue focused, and Continue loads it;
## - Quit without saving returns to the title again.
const TITLE_SCENE := "res://scenes/main/title_screen.tscn"
var failures: Array[String] = []
var quits := 0
var menu_quits := 0


func _expect(ok: bool, description: String) -> void:
	if not ok: failures.append(description)


func _run() -> void:
	create_timer(280).timeout.connect(func(): push_error("TITLE_SCREEN_TIMEOUT"); quit(1))
	_save_manager = root.get_node("SaveManager")
	_world_generator = root.get_node("WorldGenerator")
	_world_clock = root.get_node("WorldClock")
	_cleanup_test_storage()
	_expect(_save_manager.configure_storage_for_testing(TEST_DIRECTORY), "isolated test storage")
	var menu: Node = root.get_node("GameMenu")
	menu.quit_game = func(): menu_quits += 1
	_expect(ProjectSettings.get_setting("application/run/main_scene") == TITLE_SCENE, "the game opens on the title screen")
	_expect(change_scene_to_file(TITLE_SCENE) == OK, "the title screen loads")
	await _frames(4)
	var title: Node = current_scene
	await _without_save(title, menu)
	# New game: Enter on the focused button makes a world.
	_key(KEY_ENTER)
	_expect(_save_manager.is_loading() and title.buttons.load.disabled, "Enter starts a new colony and the buttons wait")
	if not await _wait_for_world():
		_finish("the new world never came")
		return
	var saved_seed: int = _world_generator.world_seed
	var saved_clock: Dictionary = _world_clock.serialize_state()
	# Quit to main menu, saving first.
	menu.open()
	await _frames(2)
	menu._choose("quit_to_title")
	await _frames(2)
	var names: Array = menu._ask_buttons.get_children().map(func(button: Button) -> String: return button.text)
	_expect(menu._ask_title.text == "Quit to the main menu?" and names == ["Save and quit", "Quit without saving", "Cancel"]
		and menu._ask_body.text == "Your colony has not been saved.", "Quit to main menu asks first: " + str(names))
	_expect(_choice(menu, "Save and quit").has_focus(), "saving first is the default")
	_choice(menu, "Save and quit").pressed.emit()
	_expect(await _wait_for_save(), "Save and quit writes the colony")
	title = await _wait_for_title()
	if title == null:
		_finish("Save and quit never reached the title")
		return
	_expect(not bool(_world_generator.get_streaming_stats().get("maps_ready", false)) and _save_manager.colony_saved_unix() == 0
		and get_first_node_in_group("work_audio_view") == null and not menu.is_open() and _world_clock.is_loading_held(),
		"the world is gone and the title holds the clock again")
	# The title now offers the save.
	var words: Array = title._slot_labels.map(func(label: Label) -> String: return label.text)
	var date := "%s, day %d · Year %d" % [String(saved_clock.season).capitalize(), int(saved_clock.day), int(saved_clock.year)]
	_expect(title.board != null and words.size() == 3 and words[0] == "Your colony" and String(words[1]).begins_with(date)
		and words[2] == "Saved just now · Quick save", "the board shows the save: " + str(words))
	var go: Button = title.buttons.get("continue")
	_expect(go != null and go.theme_type_variation == &"FamilyBlock" and go.has_focus()
		and title.buttons.new_game.theme_type_variation == &"" and title._hint.text == "Enter continues", "Continue leads, with focus")
	# Continue loads it.
	_save_manager.load_finished.connect(_on_load_finished, CONNECT_ONE_SHOT)
	_key(KEY_ENTER)
	_expect(_save_manager.is_loading(), "Enter continues")
	if not await _wait_for_load(LOAD_TIMEOUT_MSEC):
		_finish("Continue never loaded")
		return
	_expect(_load_succeeded and _world_generator.world_seed == saved_seed and _save_manager.colony_saved_unix() > 0
		and not current_scene.is_in_group("title_screen"), "Continue loads the newest save")
	# Quit without saving returns to the title.
	await _frames(10)
	menu.open()
	await _frames(2)
	menu._choose("quit_to_title")
	await _frames(2)
	_expect(menu._ask_body.text == "Your colony was last saved just now.", "the question says when the colony was saved")
	_choice(menu, "Quit without saving").pressed.emit()
	title = await _wait_for_title()
	_expect(title != null and title.board != null, "Quit without saving returns to the title, with the save still there")
	_finish("")


## The title without a save, and what it opens.
func _without_save(title: Node, menu: Node) -> void:
	title.quit_game = func(): quits += 1
	_expect(title.is_in_group("title_screen") and _world_clock.is_loading_held(), "the title holds the clock")
	_expect(title.board == null and not title.buttons.has("continue"), "without a save there is no board and no Continue")
	var new_game: Button = title.buttons.new_game
	_expect(new_game.theme_type_variation == &"FamilyBlock" and new_game.has_focus() and title._hint.text == "Enter starts a new colony",
		"New game leads, with focus")
	_key(KEY_ESCAPE)
	await _frames(2)
	_expect(not menu.is_open(), "Esc never opens the game menu on the title")
	title.buttons.settings.pressed.emit()
	await _frames(3)
	_expect(menu.is_open() and menu._settings.visible and not menu._menu.visible and menu._title.text == "Settings",
		"Settings… opens the game menu's Settings page on its own")
	_key(KEY_ESCAPE)
	await _frames(3)
	_expect(not menu.is_open() and new_game.has_focus(), "Esc closes it, back to the title")
	title.buttons.load.pressed.emit()
	await _frames(3)
	var picks: Array = menu._slots.find_children("Load_*", "Button", true, false)
	_expect(menu.is_open() and menu._load.visible and menu._load_intro.text == "Choose a save to play." and picks.size() == 2
		and picks.all(func(pick: Button) -> bool: return pick.disabled), "Load game… lists the slots, none to load yet")
	menu._back_button.pressed.emit()
	await _frames(3)
	_expect(not menu.is_open() and new_game.has_focus(), "Back closes it, back to the title")
	title.buttons.exit.pressed.emit()
	_expect(quits == 1, "Exit game quits at once")
	menu.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	_expect(menu_quits == 1 and not menu.is_open(), "closing the window on the title quits at once")


func _wait_for_world() -> bool:
	var deadline := Time.get_ticks_msec() + WORLD_TIMEOUT_MSEC
	while (current_scene == null or current_scene.is_in_group("title_screen")) and Time.get_ticks_msec() < deadline:
		await process_frame
	return await _wait_for_world_ready(maxi(1000, deadline - Time.get_ticks_msec())) and not _save_manager.is_loading()


func _wait_for_title() -> Node:
	var deadline := Time.get_ticks_msec() + 30000
	while (current_scene == null or not current_scene.is_in_group("title_screen")) and Time.get_ticks_msec() < deadline:
		await process_frame
	await _frames(4)
	return current_scene if current_scene != null and current_scene.is_in_group("title_screen") else null


func _choice(menu: Node, text: String) -> Button:
	for button: Button in menu._ask_buttons.get_children():
		if button.text == text: return button
	return Button.new()


func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	root.push_input(event)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event)


func _frames(count: int) -> void:
	for i in range(count): await process_frame


func _finish(error: String) -> void:
	if not error.is_empty(): failures.append(error)
	for failure in failures: push_error(failure)
	print("TITLE_SCREEN_OK: the title, its pages, New game, Save and quit, Continue and Quit without saving" if failures.is_empty()
		else "TITLE_SCREEN_FAIL")
	_cleanup_and_quit(0 if failures.is_empty() else 1)
