extends "res://scripts/tests/FurniturePlaceTest.gd"

## The game menu (doc 23): Esc's order and the Menu button; the world paused behind it
## without touching the player's own pause or speed; Save staying in the menu; Save as…, its
## name typed with real keys, refused names, and Replace asking first, harder for another
## colony's save; the Load page's slots and named saves, Delete asking first, and Open folder;
## the Settings page's Audio, Interface, Video and Controls tabs, a choice block and the
## render scale slider changing the live settings, the UI scale applying at once, Restore
## defaults on the open tab, and the key list's keys from the input map; Load, New game (with
## Save as… first) and Exit asking first, with Cancel leaving the colony as it is; the
## window's close button asking as Exit does; Quit to main menu asking first and leaving, at
## once or once the save is written; the title screen's Load and Settings pages on their own,
## and its board naming the newest save; the menu, Load and Save as… fitting three screens and
## two UI scales, the four Settings tabs at one size; and SaveManager reading each save's
## name, date and time from the top of its file and deleting a named save outright in test
## storage. SaveManager and quitting are stand-ins elsewhere, so nothing is loaded, saved or
## quit for real; the video settings go to a test file.
const TEST_SAVES := "user://game_menu_test"
const TEST_VIDEO := "user://game_menu_test_video.cfg"
const SaveName = preload("res://scripts/components/SaveName.gd")

var menu
var saves
var quits := 0


class FakeSaves extends Node:
	signal save_finished(success: bool)
	var saving := false
	var saved_unix := 0
	var calls: Array[String] = []
	var quick_exists := true
	## The named saves: one of this world (seed 1234) and one of another.
	var named: Array = []

	func _init() -> void:
		reset_named()

	func reset_named() -> void:
		quick_exists = true
		var now := int(Time.get_unix_time_from_system())
		named = [{"id": "named_first_winter", "name": "First winter", "named": true, "exists": true, "saved_unix": now - 600,
				"colony": "Brunhald", "season": "winter", "day": 2, "year": 1, "hour": 9.0, "seed": 1234, "bytes": 25000000},
			{"id": "named_kolgund", "name": "Kolgund", "named": true, "exists": true, "saved_unix": now - 5 * 86400,
				"colony": "Kolgund", "season": "spring", "day": 4, "year": 1, "hour": 9.2, "seed": 999, "bytes": 24000000}]

	func is_saving() -> bool: return saving
	func is_loading() -> bool: return false
	func colony_saved_unix() -> int: return saved_unix
	func save_slots() -> Array:
		var quick := {"id": "quick", "name": "Quick save", "exists": false}
		if quick_exists: quick = {"id": "quick", "name": "Quick save", "exists": true, "saved_unix": int(Time.get_unix_time_from_system()) - 7200,
			"colony": "Brunhald", "season": "autumn", "day": 7, "year": 1, "hour": 20.5}
		return [quick, {"id": "auto", "name": "Autosave", "exists": false}] + named
	func request_save() -> bool:
		calls.append("save")
		saving = true
		return true
	func request_save_as(save_name: String) -> bool:
		calls.append("save_as:" + save_name)
		saving = true
		return true
	func request_load() -> bool:
		calls.append("load")
		return true
	func request_load_autosave() -> bool:
		calls.append("load_auto")
		return true
	func request_load_save(id: String) -> bool:
		calls.append({"quick": "load", "auto": "load_auto"}.get(id, "load_" + id))
		return true
	func request_delete_save(id: String) -> bool:
		calls.append("delete_" + id)
		if id == "quick": quick_exists = false
		named = named.filter(func(slot: Dictionary) -> bool: return slot.id != id)
		return true
	func open_saves_folder() -> void:
		calls.append("folder")
	func request_new_game() -> bool:
		calls.append("new_game")
		return true
	func request_quit_to_title() -> bool:
		calls.append("quit_to_title")
		return true


func _run() -> void:
	create_timer(60).timeout.connect(func(): push_error("Game menu test timed out"); quit(1))
	root.get_node("SaveManager").set_process(false)
	root.get_node("WorldClock").set_paused(false)
	root.get_node("TaskManager").set_process(false)
	root.get_node("RoomManager").set_process(false)
	world = root.get_node("WorldData")
	blocks = root.get_node("BlockRegistry")
	_build_floor()
	root.get_node("WorldGenerator")._maps_ready = true
	root.get_node("WorldGenerator").world_seed = 1234
	root.get_node("WorldGenerator").heightmap.resize(1024 * 1024)
	root.get_node("WorldGenerator").heightmap.fill(20)
	root.get_node("WorldGenerator").waterline_map.resize(1024 * 1024)
	root.get_node("WorldGenerator").waterline_map.fill(-1)
	scene = Node3D.new()
	root.add_child(scene)
	current_scene = scene
	manager = load("res://scripts/ui/UIWindowManager.gd").new()
	manager.name = "Windows"
	scene.add_child(manager)
	manager._layout_loaded = false
	manager._layout.clear()
	items = load("res://scripts/systems/ItemDropManager.gd").new()
	scene.add_child(items)
	dock = load("res://scripts/ui/DockUI.gd").new()
	dock.name = "Dock"
	dock.window_manager_path = NodePath("../Windows")
	scene.add_child(dock)
	furniture = load("res://scripts/systems/FurniturePlacementController.gd").new()
	furniture.dock_ui_path = NodePath("../Dock")
	scene.add_child(furniture)
	furniture.set_process(false)
	furniture._process(0)
	root.size = Vector2i(1280, 720)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 22
	scene.add_child(camera)
	camera.current = true
	camera.position = Vector3(49, 41, 55)
	camera.look_at(Vector3(38, 21, 38))
	_build_review_world()
	await _settle()
	menu = root.get_node("GameMenu")
	root.get_node("VideoSettings")._preferences_path = TEST_VIDEO
	saves = FakeSaves.new()
	scene.add_child(saves)
	menu.saves = saves
	menu.quit_game = func(): quits += 1
	var clock = root.get_node("WorldClock")
	clock.set_speed(2.0)
	await _test_opening(clock)
	await _test_esc_order()
	await _test_save()
	await _test_save_as()
	await _test_load()
	await _test_settings()
	await _test_new_game()
	await _test_exit()
	await _test_quit_to_title()
	await _test_title_pages()
	await _test_sizes()
	await _test_title_board()
	_test_save_slots()
	root.get_node("VideoSettings").save_preferences()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_VIDEO))
	menu.saves = root.get_node("SaveManager")
	menu.quit_game = func(): menu.get_tree().quit()
	if failures.is_empty(): print("GAME_MENU_OK: Esc order, Menu button, pause hold, Save, Save as, Load page, Settings, questions, window close, sizes, title board, save slots")
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)


func _test_opening(clock) -> void:
	_key(KEY_ESCAPE)
	await _settle()
	_expect(menu.is_open() and clock.paused and not clock._player_paused and is_equal_approx(clock.speed, 2.0),
		"Esc with nothing open opens the menu and pauses the world without touching the player's own pause or speed")
	_expect(menu._date.text.contains("day") and menu._saved_label.text == "Not saved yet" and not menu._buttons.save.disabled,
		"the menu gives the colony's date and says it was never saved")
	_key(KEY_ESCAPE)
	await _settle()
	_expect(not menu.is_open() and not clock.paused and is_equal_approx(clock.speed, 2.0), "Esc from the menu resumes as before")
	clock.set_paused(true)
	_click(dock._button_by_target.system.get_global_rect().get_center())
	await _settle()
	_expect(menu.is_open(), "the dock's Menu button opens the menu")
	_click(menu._buttons.resume.get_global_rect().get_center())
	await _settle()
	_expect(not menu.is_open() and clock.paused and clock._player_paused, "Resume keeps the player's own pause")
	clock.set_paused(false)


func _test_esc_order() -> void:
	# An open dock menu closes first.
	_click(dock._button_by_target.orders.get_global_rect().get_center())
	await _settle()
	_expect(dock._orders.is_open(), "the Orders shelf is open")
	_key(KEY_ESCAPE)
	await _settle()
	_expect(not dock._orders.is_open() and not menu.is_open(), "Esc closes an open dock menu before the game menu")
	# The active tool ends first.
	items.spawn_drop(furniture.get_defs()[TABLE].item_key, 1, Vector3i(33, 21, 33))
	await _settle()
	furniture.activate_for(TABLE, true)
	_expect(furniture.is_active(), "placing a table")
	_key(KEY_ESCAPE)
	await _settle()
	_expect(not furniture.is_active() and not menu.is_open(), "Esc ends the active tool before the game menu")
	# The front window closes first, even one without an Esc of its own.
	manager.open("trade")
	await _settle()
	_key(KEY_ESCAPE)
	await _settle()
	_expect(not manager.is_open("trade") and not menu.is_open(), "Esc closes the front window before the game menu")
	_key(KEY_ESCAPE)
	await _settle()
	_expect(menu.is_open(), "with nothing left to close, Esc opens the game menu")
	menu.close()


func _test_save() -> void:
	menu.open()
	await _settle()
	_click(menu._buttons.save.get_global_rect().get_center())
	await _settle()
	_expect(saves.calls == ["save"] and menu.is_open() and menu._saved_label.text == "Saving…" and menu._buttons.load.disabled,
		"Save game saves and the menu stays, saying it is saving")
	saves.saving = false
	saves.saved_unix = int(Time.get_unix_time_from_system())
	menu._on_save_finished(true)
	_expect(menu._saved_label.text == "Last saved just now" and not menu._buttons.load.disabled, "a finished save reads Last saved just now")
	menu.close()
	saves.calls.clear()


func _test_load() -> void:
	menu.open()
	await _settle()
	_click(menu._buttons.load.get_global_rect().get_center())
	await _settle()
	var quick: Button = menu._slots.find_child("Load_quick", true, false)
	var auto: Button = menu._slots.find_child("Load_auto", true, false)
	_expect(menu._load.visible and menu._title.text == "Load a colony" and quick != null and not quick.disabled and auto != null and auto.disabled,
		"the Load page lists the quick save, and the missing autosave cannot be chosen")
	var words: Array = menu._slots.find_children("*", "Label", true, false).map(func(label: Label): return label.text)
	_expect(words.has("Brunhald · Autumn, day 7 · Year 1 · 20:30") and words.has("No autosave yet.") and words.any(func(text: String): return text.begins_with("Saved 2 hours ago")),
		"each slot gives its settlement's name, its date in the colony and when it was saved")
	_click(quick.get_global_rect().get_center())
	await _settle()
	_expect(menu._question == "load_quick" and menu._ask_title.text == "Load the quick save?" and menu._ask_body.text.contains("autumn, day 7")
		and menu._ask_body.text.contains("Anything since your last save, just now, is lost."), "Load asks first, saying what is lost")
	_click(_choice("Cancel").get_global_rect().get_center())
	await _settle()
	_expect(saves.calls.is_empty() and menu.is_open() and menu._question.is_empty() and menu._load.visible, "Cancel leaves the colony as it is")
	_click(quick.get_global_rect().get_center())
	await _settle()
	_click(_choice("Load").get_global_rect().get_center())
	await _settle()
	_expect(saves.calls == ["load"] and not menu.is_open(), "confirming loads the quick save, with the menu closed first")
	saves.calls.clear()
	# The named saves follow the two slots, newest first, each with Load and Delete.
	menu.open()
	await _settle()
	menu._show_page("load")
	await _settle()
	var winter: Button = menu._slots.find_child("Load_named_first_winter", true, false)
	var kolgund: Button = menu._slots.find_child("Load_named_kolgund", true, false)
	words = menu._slots.find_children("*", "Label", true, false).map(func(label: Label): return label.text)
	_expect(winter != null and kolgund != null and words.has("Your saves · 2 saves · 49 MB") and words.has("First winter")
		and words.has("Brunhald · Winter, day 2 · Year 1 · 09:00") and words.has("10 minutes ago"),
		"the Load page lists the named saves with their colony, date and age, and their room: " + str(words))
	_expect(winter != null and kolgund != null and winter.get_global_rect().position.y < kolgund.get_global_rect().position.y,
		"the newest named save comes first")
	_click(winter.get_global_rect().get_center())
	await _settle()
	_expect(menu._question == "load_named_first_winter" and menu._ask_title.text == "Load \"First winter\"?"
		and menu._ask_body.text.contains("winter, day 2, year 1"), "Load on a named save asks first: " + menu._ask_title.text)
	_click(_choice("Load").get_global_rect().get_center())
	await _settle()
	_expect(saves.calls == ["load_named_first_winter"] and not menu.is_open(), "confirming loads that named save")
	saves.calls.clear()
	menu.open()
	await _settle()
	menu._show_page("load")
	await _settle()
	_click(menu._slots.find_child("Delete_named_kolgund", true, false).get_global_rect().get_center())
	await _settle()
	_expect(menu._ask_title.text == "Delete \"Kolgund\"?" and menu._ask_body.text.contains("Recycle Bin") and _choice("Cancel").has_focus()
		and _ask_names() == ["Delete", "Cancel"], "Delete asks first, with Cancel the default: " + str(_ask_names()))
	_click(_choice("Cancel").get_global_rect().get_center())
	await _settle()
	_expect(saves.calls.is_empty() and menu._slots.find_child("Load_named_kolgund", true, false) != null, "Cancel keeps the save")
	_click(menu._slots.find_child("Delete_named_kolgund", true, false).get_global_rect().get_center())
	await _settle()
	_click(_choice("Delete").get_global_rect().get_center())
	await _settle()
	_expect(saves.calls == ["delete_named_kolgund"] and menu._load.visible and menu._slots.find_child("Load_named_kolgund", true, false) == null,
		"confirming deletes it, and the list no longer shows it")
	saves.calls.clear()
	_click(menu._folder_button.get_global_rect().get_center())
	await _settle()
	_expect(saves.calls == ["folder"], "Open folder shows the saves folder")
	saves.calls.clear()
	# The quick save and the autosave can go too, while they hold a save.
	_expect(menu._slots.find_child("Delete_quick", true, false) != null and menu._slots.find_child("Delete_auto", true, false) == null,
		"the quick save has Delete, and the missing autosave has none")
	_click(menu._slots.find_child("Delete_quick", true, false).get_global_rect().get_center())
	await _settle()
	_expect(menu._ask_title.text == "Delete the quick save?" and menu._ask_body.text.contains("Recycle Bin, and Save game writes the next one.")
		and _choice("Cancel").has_focus(), "Delete on the quick save asks first: " + menu._ask_body.text)
	_click(_choice("Cancel").get_global_rect().get_center())
	await _settle()
	_expect(saves.calls.is_empty(), "Cancel keeps the quick save")
	_click(menu._slots.find_child("Delete_quick", true, false).get_global_rect().get_center())
	await _settle()
	_click(_choice("Delete").get_global_rect().get_center())
	await _settle()
	words = menu._slots.find_children("*", "Label", true, false).map(func(label: Label): return label.text)
	_expect(saves.calls == ["delete_quick"] and words.has("No quick save yet.") and (menu._slots.find_child("Load_quick", true, false) as Button).disabled
		and menu._slots.find_child("Delete_quick", true, false) == null, "confirming deletes the quick save, and its slot reads empty")
	saves.calls.clear()
	saves.reset_named()   # Kolgund and the quick save back for the later checks
	_key(KEY_ESCAPE)
	await _settle()
	_expect(menu.is_open() and menu._menu.visible, "Esc on the Load page goes back to the menu")
	menu.close()


## Save as… (doc 23): the page opens on a suggested name, chosen so typing replaces it; real
## keys reach the field; a refused name keeps Save off and says why; a name in use (capitals
## aside) asks before replacing that save, and a save of another colony asks with Cancel
## leading; a new name saves at once and the menu page says so.
func _test_save_as() -> void:
	var clock = root.get_node("WorldClock")
	menu.open()
	await _settle()
	_expect(menu._buttons.save_as.get_parent() == menu._buttons.save.get_parent() and menu._buttons.save_as.get_index() == 1
		and not menu._buttons.save_as.disabled, "Save as… sits beside Save game")
	_click(menu._buttons.save_as.get_global_rect().get_center())
	await _settle()
	var field: LineEdit = menu._name_field
	var suggested := "Your colony, %s day %d" % [String(clock.season).to_lower(), int(clock.day)]
	_expect(menu._save_as.visible and menu._title.text == "Save as…" and field.text == suggested and field.has_focus()
		and field.has_selection() and field.get_selected_text() == suggested, "Save as… opens on the suggested name, chosen: " + field.text)
	var rows: Array = menu._save_list.find_children("Replace_*", "Button", true, false)
	_expect(rows.size() == 2 and menu._save_heading.text == "Your saves · 2 saves · 49 MB", "the page lists your saves with Replace")
	_type("Bad/name")
	await _settle()
	_expect(field.text == "Bad/name" and menu._save_button.disabled and menu._name_note.text == SaveName.RULE,
		"typed keys reach the field, and a refused name keeps Save off and gives the rules: " + field.text)
	field.select_all()
	_type("first WINTER")
	await _settle()
	_expect(not menu._save_button.disabled and menu._name_note.text.contains("\"First winter\" is a save already"),
		"a name in use, capitals aside, says Save replaces it: " + menu._name_note.text)
	_click(menu._save_button.get_global_rect().get_center())
	await _settle()
	_expect(menu._ask_title.text == "Replace \"First winter\"?" and _ask_names() == ["Replace", "Cancel"] and _choice("Cancel").has_focus()
		and menu._ask_body.text.contains("It holds Brunhald on winter, day 2, year 1"), "Save asks before replacing: " + menu._ask_body.text)
	_click(_choice("Cancel").get_global_rect().get_center())
	await _settle()
	_expect(saves.calls.is_empty() and menu._save_as.visible, "Cancel leaves the save as it was")
	_click(menu._save_list.find_child("Replace_named_kolgund", true, false).get_global_rect().get_center())
	await _settle()
	_expect(menu._ask_title.text == "Replace \"Kolgund\"?" and menu._ask_body.text.contains("holds another colony, Kolgund")
		and _ask_names() == ["Replace Kolgund", "Cancel"] and _choice("Cancel").has_focus(),
		"replacing another colony's save says that colony is lost, with Cancel leading: " + str(_ask_names()))
	_click(_choice("Replace Kolgund").get_global_rect().get_center())
	await _settle()
	_expect(saves.calls == ["save_as:Kolgund"] and menu._menu.visible and menu._saved_label.text == "Saving…",
		"confirming replaces it under its name, back on the menu page")
	saves.saving = false
	menu._on_save_finished(true)
	saves.calls.clear()
	menu._choose("save_as")
	await _settle()
	field.select_all()
	_type("Before the flood")
	_key(KEY_ENTER)
	await _settle()
	_expect(saves.calls == ["save_as:Before the flood"] and menu._menu.visible, "Enter saves a new name at once")
	saves.saving = false
	menu._on_save_finished(true)
	saves.calls.clear()
	menu.close()


func _test_settings() -> void:
	var audio = root.get_node("AmbientAudio")
	var before: float = audio.volume("effects")
	menu.open()
	await _settle()
	_click(menu._buttons.settings.get_global_rect().get_center())
	await _settle()
	var page = menu._settings
	_expect(menu.is_open() and page.visible and menu._title.text == "Settings" and not menu._menu.visible and page.section == "audio"
		and page.tabs.audio.theme_type_variation == &"FamilyBlock", "Settings… opens the Settings page inside the menu, on Audio")
	var effects: Dictionary = page.controls.effects
	effects.slider.value = 30
	_expect(is_equal_approx(audio.volume("effects"), .3) and effects.value.text == "30%", "the effects slider sets the live mix and shows it")
	var frame_size: Vector2 = menu._frame.size
	_click(page.tabs.video.get_global_rect().get_center())
	await _settle()
	_expect(page.section == "video" and page._sections.video.visible and not page._sections.audio.visible
		and page.tabs.video.theme_type_variation == &"FamilyBlock" and page.tabs.audio.theme_type_variation == &"",
		"the Video tab opens the Video section")
	_expect(menu._frame.size.is_equal_approx(frame_size), "the window keeps its size on both tabs")
	var video = root.get_node("VideoSettings")
	var medium: Button = page.controls.shadows.medium
	_click(medium.get_global_rect().get_center())
	await _settle()
	_expect(video.value("shadows") == "medium" and root.positional_shadow_atlas_size == 2048 and medium.theme_type_variation == &"FamilyBlock"
		and page.controls.shadows.high.theme_type_variation == &"", "a choice block sets the video setting and shows it chosen")
	page.controls.render_scale.slider.value = 75
	_expect(is_equal_approx(video.value("render_scale"), .75) and is_equal_approx(root.scaling_3d_scale, .75)
		and page.controls.render_scale.value.text == "75%", "the render scale slider scales the world and shows it")
	_click(page.restore_button.get_global_rect().get_center())
	await _settle()
	_expect(video.value("shadows") == "high" and is_equal_approx(root.scaling_3d_scale, 1.0) and is_equal_approx(audio.volume("effects"), .3),
		"Restore defaults puts back the open tab's settings only")
	await _check_interface(page, frame_size)
	await _check_key_list(page, frame_size)
	_key(KEY_ESCAPE)
	await _settle()
	_expect(menu.is_open() and menu._menu.visible, "Esc on the Settings page goes back to the menu")
	menu._choose("settings")
	await _settle()
	_expect(page.section == "controls", "Settings opens again on the tab last open")
	page.show_section("audio")
	audio.set_volume("effects", before)
	menu.close()


func _test_new_game() -> void:
	menu.open()
	await _settle()
	_click(menu._buttons.new_game.get_global_rect().get_center())
	await _settle()
	_expect(menu._ask_title.text == "Start a new colony?" and menu._ask_body.text.contains("Your saves stay as they are")
		and menu._ask_body.text.contains("its quick save and autosave replace the ones you have")
		and _ask_names() == ["Start a new colony", "Save as… first", "Cancel"] and _choice("Cancel").has_focus(),
		"New game asks first, saying the quick save and autosave will be replaced: " + str(_ask_names()))
	_click(_choice("Save as… first").get_global_rect().get_center())
	await _settle()
	_expect(menu._question.is_empty() and menu._save_as.visible and saves.calls.is_empty(), "Save as… first opens the Save as… page")
	_key(KEY_ESCAPE)
	await _settle()
	_click(menu._buttons.new_game.get_global_rect().get_center())
	await _settle()
	_key(KEY_ESCAPE)
	await _settle()
	_expect(menu.is_open() and menu._question.is_empty() and saves.calls.is_empty(), "Esc closes the question and keeps the colony")
	_click(menu._buttons.new_game.get_global_rect().get_center())
	await _settle()
	_click(_choice("Start a new colony").get_global_rect().get_center())
	await _settle()
	_expect(saves.calls == ["new_game"] and not menu.is_open(), "confirming starts a new colony")
	saves.calls.clear()


func _test_exit() -> void:
	menu.open()
	await _settle()
	_click(menu._buttons.exit.get_global_rect().get_center())
	await _settle()
	var names: Array = menu._ask_buttons.get_children().map(func(button: Button): return button.text)
	_expect(names == ["Save and exit", "Exit without saving", "Cancel"] and menu._ask_body.text == "Your colony was last saved just now.",
		"Exit offers Save and exit, Exit without saving and Cancel")
	_click(_choice("Exit without saving").get_global_rect().get_center())
	await _settle()
	_expect(quits == 1, "Exit without saving quits")
	_click(_choice("Save and exit").get_global_rect().get_center())
	await _settle()
	_expect(saves.calls == ["save"] and quits == 1 and menu._ask_body.text == "Saving…", "Save and exit saves first")
	saves.saving = false
	menu._on_save_finished(true)
	_expect(quits == 2, "and quits once the save is written")
	menu.close()
	menu._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	await _settle()
	_expect(menu.is_open() and menu._question == "exit", "closing the game's window asks as Exit does")
	menu.close()
	saves.calls.clear()


## Quit to main menu (doc 23): it asks as Exit does; Quit without saving leaves at once, and
## Save and quit leaves once the save is written.
func _test_quit_to_title() -> void:
	menu.open()
	await _settle()
	_expect(menu._buttons.quit_to_title.get_index() == menu._buttons.exit.get_index() - 1, "Quit to main menu… sits just above Exit game…")
	_click(menu._buttons.quit_to_title.get_global_rect().get_center())
	await _settle()
	var names: Array = menu._ask_buttons.get_children().map(func(button: Button): return button.text)
	_expect(menu._ask_title.text == "Quit to the main menu?" and names == ["Save and quit", "Quit without saving", "Cancel"]
		and _choice("Save and quit").has_focus(), "Quit to main menu asks first, saving first by default: " + str(names))
	_click(_choice("Save and quit").get_global_rect().get_center())
	await _settle()
	_expect(saves.calls == ["save"] and menu.is_open() and menu._ask_body.text == "Saving…", "Save and quit saves first")
	saves.saving = false
	menu._on_save_finished(true)
	_expect(saves.calls == ["save", "quit_to_title"] and not menu.is_open(), "and leaves for the title once the save is written")
	saves.calls.clear()
	menu.open()
	await _settle()
	menu._choose("quit_to_title")
	await _settle()
	_click(_choice("Quit without saving").get_global_rect().get_center())
	await _settle()
	_expect(saves.calls == ["quit_to_title"] and not menu.is_open(), "Quit without saving leaves at once")
	saves.calls.clear()


## The title screen's Load game… and Settings… (doc 23): each page on its own; a slot loads
## without asking, as no colony runs, and Back closes the menu again.
func _test_title_pages() -> void:
	menu.open_page("load")
	await _settle()
	_expect(menu.is_open() and menu._load.visible and not menu._menu.visible and menu._title.text == "Load a colony"
		and menu._load_intro.text == "Choose a save to play.", "the title opens the Load page on its own")
	var pick: Button = menu._slots.find_child("Load_quick", true, false)
	_click(pick.get_global_rect().get_center())
	await _settle()
	_expect(saves.calls == ["load"] and menu._question.is_empty() and not menu.is_open(), "a slot loads without asking")
	saves.calls.clear()
	menu.open_page("settings")
	await _settle()
	_expect(menu.is_open() and menu._settings.visible and menu._title.text == "Settings", "the title opens Settings on its own")
	_click(menu._settings.back_button.get_global_rect().get_center())
	await _settle()
	_expect(not menu.is_open(), "Back closes it again")
	menu.open()
	await _settle()
	menu._choose("load")
	await _settle()
	_expect(menu._load_intro.text == "Choose a save. Your colony goes back to that moment.", "the game menu's own Load page is as before")
	menu.close()


func _test_sizes() -> void:
	for viewport_size in [Vector2i(960, 540), Vector2i(1280, 720), Vector2i(2560, 1440)]:
		root.size = viewport_size
		await _settle()
		menu.open()
		await _settle()
		var bounds := Rect2(Vector2.ZERO, Vector2(viewport_size))
		_expect(bounds.encloses(menu._frame.get_global_rect()), "the menu fits " + str(viewport_size))
		menu._show_page("load")
		await _settle()
		_expect(bounds.encloses(menu._frame.get_global_rect()), "the Load page fits " + str(viewport_size))
		menu._show_page("save_as")
		await _settle()
		_expect(bounds.encloses(menu._frame.get_global_rect()), "the Save as… page fits " + str(viewport_size))
		menu._show_page("settings")
		for tab: String in ["video", "audio", "interface", "controls"]:
			menu._settings.show_section(tab)
			await _settle()
			_expect(bounds.encloses(menu._frame.get_global_rect()), "the Settings page fits with %s open at %s" % [tab, viewport_size])
		# Short screens drop the rows' lines before the inset would scroll; only the key list
		# scrolls, and only on short screens.
		var settings = menu._settings
		var inset: float = settings._scroll.size.y
		_expect(settings._rows[0].about.visible == (viewport_size.y >= 1300)
			and settings._sections.audio.get_combined_minimum_size().y <= inset and settings._sections.video.get_combined_minimum_size().y <= inset,
			"the Settings rows fit without scrolling, with their lines only where there is room: " + str(viewport_size))
		_expect((settings._scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED) == (viewport_size.y >= 1300),
			"the key list scrolls only on short screens: " + str(viewport_size))
		menu._ask("exit")
		await _settle()
		_expect(bounds.encloses(menu._ask_frame.get_global_rect()), "a question fits " + str(viewport_size))
		if "--capture" in OS.get_cmdline_user_args():
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://tmp/game_menu_20261024/test_%d.png" % viewport_size.x)
		menu.close()
	# Under a UI scale the menu lays out in the room the scale leaves (doc 23).
	var video = root.get_node("VideoSettings")
	for entry: Array in [[Vector2i(2560, 1440), 200, Vector2(1280, 720)], [Vector2i(1920, 1080), 150, Vector2(1280, 720)]]:
		root.size = entry[0]
		video.set_value("ui_scale", entry[1])
		await _settle()
		menu.open()
		menu._show_page("settings")
		var room := Rect2(Vector2.ZERO, root.get_visible_rect().size)
		_expect(room.size.is_equal_approx(entry[2]), "%d%% at %s leaves %s (got %s)" % [entry[1], entry[0], entry[2], room.size])
		for tab: String in ["audio", "interface", "video", "controls"]:
			menu._settings.show_section(tab)
			await _settle()
			_expect(room.encloses(menu._frame.get_global_rect()), "at %d%% the Settings page fits with %s open at %s" % [entry[1], tab, entry[0]])
		menu.close()
	video.set_value("ui_scale", "auto")
	root.size = Vector2i(1280, 720)


## Settings' Interface tab (doc 23): the second tab; Auto and the steps the window has room
## for as choice blocks, a step applying at once with the page laying out again in the room
## it leaves, the note under the rule, and Restore defaults putting Auto back.
func _check_interface(page, frame_size: Vector2) -> void:
	var video = root.get_node("VideoSettings")
	var order: Array = page.tabs.audio.get_parent().get_children().map(func(tab: Button) -> String: return tab.text)
	_expect(order == ["Audio", "Interface", "Video", "Controls"], "the tabs are Audio, Interface, Video and Controls (got %s)" % [order])
	_click(page.tabs.interface.get_global_rect().get_center())
	await _settle()
	var blocks: Dictionary = page.controls.ui_scale
	_expect(page.section == "interface" and page._sections.interface.visible and not page._sections.video.visible
		and page.tabs.interface.theme_type_variation == &"FamilyBlock" and page.restore_button.visible
		and menu._frame.size.is_equal_approx(frame_size), "the Interface tab opens the UI scale, and the window keeps its size")
	_expect(blocks.keys() == ["auto", 100, 125] and blocks.auto.theme_type_variation == &"FamilyBlock"
		and page._scale_note.text.begins_with("Auto: 100%, as Windows sets this screen. The interface lays out at 1280 × 720."),
		"at 1280 x 720 the blocks are Auto, 100%% and 125%%, with Auto chosen (got %s, \"%s\")" % [blocks.keys(), page._scale_note.text])
	_click(blocks[125].get_global_rect().get_center())
	await _settle()
	var room := Rect2(Vector2.ZERO, root.get_visible_rect().size)
	_expect(video.value("ui_scale") is int and video.value("ui_scale") == 125 and is_equal_approx(root.content_scale_factor, 1.25)
		and room.size.is_equal_approx(Vector2(1024, 576)) and room.encloses(menu._frame.get_global_rect())
		and page.controls.ui_scale[125].theme_type_variation == &"FamilyBlock" and page.controls.ui_scale.auto.theme_type_variation == &""
		and page._scale_note.text.begins_with("The interface lays out at 1024 × 576."),
		"125%% applies at once, and the page lays out again in the 1024 x 576 it leaves (got \"%s\")" % page._scale_note.text)
	_expect(page.first_focus() == page.controls.ui_scale[125], "focus starts on the chosen scale")
	_click(page.restore_button.get_global_rect().get_center())
	await _settle()
	_expect(video.value("ui_scale") is String and is_equal_approx(root.content_scale_factor, 1.0)
		and page.controls.ui_scale.auto.theme_type_variation == &"FamilyBlock", "Restore defaults on Interface puts Auto back")
	_click(page.tabs.video.get_global_rect().get_center())
	await _settle()


## Settings' Controls tab (doc 23 "Keys"): the key list in two columns, each row's keys on
## keycaps at its right, the input actions' keys read from the input map; nothing to restore,
## and the window keeps its size.
func _check_key_list(page, frame_size: Vector2) -> void:
	_click(page.tabs.controls.get_global_rect().get_center())
	await _settle()
	_expect(page.section == "controls" and page._sections.controls.visible and not page._sections.video.visible
		and page.tabs.controls.theme_type_variation == &"FamilyBlock" and not page.restore_button.visible
		and page._intro.text.contains("Choosing your own keys comes later"), "the Controls tab shows the key list, with nothing to restore")
	_expect(menu._frame.size.is_equal_approx(frame_size), "the window keeps its size on all three tabs")
	var shown := {"Pause or resume": "Space", "Normal speed": "1", "Fast speed": "2", "Appeal": "V", "X-ray": "X",
		"Slice": "\\", "Raise / lower 4 levels": "] / [", "Raise / lower 1 level": "Ctrl + ] / Ctrl + [",
		"Over the tower: 1 / 4 levels": "Wheel / Ctrl + Wheel", "Move": "W A S D or Arrow keys",
		"Mining width, or a door gap": "Shift + Wheel", "Take blocks out of building plans": "Ctrl + Drag", "Finish the tool": "Esc", "Close the front window, or open the menu": "Esc"}
	for label: String in shown:
		_expect(page.shown_keys(label) == shown[label], "the key list shows %s for %s, not %s" % [shown[label], label, page.shown_keys(label)])
	var inset: Rect2 = page._scroll.get_global_rect()
	var columns: Array = page._key_columns.get_children()
	_expect(columns.size() == 2 and (columns[0] as Control).get_global_rect().end.x < (columns[1] as Control).get_global_rect().position.x,
		"the groups stand in two columns")
	for row: Dictionary in page._key_rows:
		var words: Rect2 = (row.words as Label).get_global_rect()
		var keys: Rect2 = (row.keys as Control).get_global_rect()
		_expect(not page.shown_keys(row.text).is_empty() and keys.position.x >= inset.position.x and keys.end.x <= inset.end.x
			and words.end.x <= keys.position.x, "%s has its keys at its right, inside the inset" % row.text)
	# A short screen scrolls the list; its last rows come into view.
	page._scroll.scroll_vertical = 100000
	await _settle()
	var first := 0   # the first column's rows
	for group: Dictionary in root.get_node("UIRegistry").get_controls().columns[0]: first += group.entries.size()
	for row: Dictionary in [page._key_rows[first - 1], page._key_rows[page._key_rows.size() - 1]]:
		_expect(inset.encloses((row.keys as Control).get_global_rect()), "scrolling brings %s into view" % row.text)
	page._scroll.scroll_vertical = 0
	for group: Array in root.get_node("UIRegistry").get_controls().columns:
		for block: Dictionary in group:
			for entry: Dictionary in block.entries:
				for action: String in entry.get("actions", []):
					_expect(InputMap.has_action(action) and not preload("res://scripts/ui/DockIconButton.gd").key_text(action).is_empty(), action + " is an input action with a key")
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tmp/controls_20261025/test_%d.png" % root.size.x)


func _test_save_slots() -> void:
	var manager_node = root.get_node("SaveManager")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEST_SAVES.path_join("named")))
	_expect(manager_node.configure_storage_for_testing(TEST_SAVES), "test save storage")
	var file := FileAccess.open(TEST_SAVES.path_join("quicksave.json"), FileAccess.WRITE)
	file.store_string('{\n\t"clock": {\n\t\t"day": 3,\n\t\t"hour": 9.5,\n\t\t"paused": false,\n\t\t"season": "spring",\n\t\t"speed": 1.0,\n\t\t"year": 2\n\t},\n\t"colony_name": "Ost\'s Hollow",\n\t"project": "Deepdraft",\n\t"saved_at_utc": "2026-10-24 10:00:00"\n}\n')
	file.close()
	# A named save keeps its name beside the clock and its world's seed at the end.
	for ending: String in [".json", ".backup.json"]:
		file = FileAccess.open(TEST_SAVES.path_join("named/first_winter" + ending), FileAccess.WRITE)
		file.store_string('{\n\t"clock": {\n\t\t"day": 2,\n\t\t"hour": 7.25,\n\t\t"paused": false,\n\t\t"season": "winter",\n\t\t"speed": 1.0,\n\t\t"year": 1\n\t},\n\t"colony_name": "Brunhald",\n\t"project": "Deepdraft",\n\t"save_name": "First winter",\n\t"saved_at_utc": "2026-10-25 10:00:00",\n\t"world_seed": 4321\n}\n')
		file.close()
	var slots: Array = manager_node.save_slots()
	_expect(slots.size() == 3 and slots[0].exists and slots[0].season == "spring" and slots[0].day == 3 and slots[0].year == 2
		and is_equal_approx(slots[0].hour, 9.5) and slots[0].saved_unix == Time.get_unix_time_from_datetime_string("2026-10-24 10:00:00")
		and slots[0].colony == "Ost's Hollow" and not slots[1].exists, "SaveManager reads each slot's settlement, date and time from the top of its file")
	_expect(slots.size() == 3 and slots[2].named and slots[2].id == "named_first_winter" and slots[2].name == "First winter"
		and slots[2].colony == "Brunhald" and slots[2].season == "winter" and slots[2].seed == 4321 and slots[2].bytes > 0,
		"a named save gives its name, colony, date, world and room: " + str(slots[2] if slots.size() == 3 else slots))
	# Test storage deletes outright, so tests never fill the player's Recycle Bin.
	_expect(manager_node.request_delete_save("named_first_winter") and manager_node.save_slots().size() == 2
		and not FileAccess.file_exists(TEST_SAVES.path_join("named/first_winter.json"))
		and not FileAccess.file_exists(TEST_SAVES.path_join("named/first_winter.backup.json")), "Delete removes a named save and its backup")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVES.path_join("quicksave.json")))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVES.path_join("named")))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVES))
	manager_node.reset_storage_after_testing()


## The title's board (doc 23, "The title screen") names the newest save, a named one too.
func _test_title_board() -> void:
	var title = load("res://scripts/ui/TitleScreen.gd").new()
	title.saves = saves
	title.menu = menu
	title.quit_game = func(): pass
	scene.add_child(title)
	await _settle()
	var words: Array = title._slot_labels.map(func(label: Label) -> String: return label.text)
	_expect(words == ["Brunhald", "Winter, day 2 · Year 1 · 09:00", "Saved 10 minutes ago · First winter"],
		"the title's board names the newest save, a named one too: " + str(words))
	# Deleting that save in the title's Load page brings the next newest onto the board.
	title.buttons.load.pressed.emit()
	await _settle()
	_click(menu._slots.find_child("Delete_named_first_winter", true, false).get_global_rect().get_center())
	await _settle()
	_click(_choice("Delete").get_global_rect().get_center())
	await _settle()
	_click(menu._back_button.get_global_rect().get_center())
	await _settle()
	words = title._slot_labels.map(func(label: Label) -> String: return label.text)
	_expect(not menu.is_open() and words.size() == 3 and words[2] == "Saved 2 hours ago · Quick save" and title.buttons["continue"].has_focus(),
		"back on the title, the board shows the newest save left: " + str(words))
	saves.calls.clear()
	saves.reset_named()
	title.queue_free()
	await _settle()


func _ask_names() -> Array:
	return menu._ask_buttons.get_children().map(func(button: Button) -> String: return button.text)


## Types `text` into whatever has focus, a key at a time, as the keyboard would.
func _type(text: String) -> void:
	for character: String in text:
		var event := InputEventKey.new()
		event.pressed = true
		event.unicode = character.unicode_at(0)
		event.keycode = KEY_SPACE if character == " " else OS.find_keycode_from_string(character.to_upper())
		root.push_input(event, true)


func _choice(text: String) -> Button:
	for button: Button in menu._ask_buttons.get_children():
		if button.text == text: return button
	return null
