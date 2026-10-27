extends SceneTree

## The settlement's name (doc 23): SettlementName's rules; the suggestions the world's seed
## draws, the same for the same world and every one in the rules; and the founding card the
## flag tool opens: the first suggestion in its field, Suggest another, Found waiting for a
## name in the rules, Cancel, ✕ and Esc keeping the tool, and Found planting the flag under
## the name with its founding entry in Events. Then the game menu takes the name as its
## title. The furniture and the squad are stand-ins; the Load list's name is
## SaveManagerRoundTripTest's and GameMenuTest's.
const SettlementName = preload("res://scripts/components/SettlementName.gd")
const CELL := Vector3i(40, 20, 40)
var failures: Array[String] = []
var events: Node
var scene: Node3D
var manager: Node
var dock: Node
var flag: Node
var card: Node
var founder: Node


class FurnitureProbe extends Node:
	signal furniture_installed(key: String, cell: Vector3i)
	func install_now(key: String, cell: Vector3i, _yaw: int) -> void: furniture_installed.emit(key, cell)
	func get_catalog_location(_key: String) -> Dictionary: return {}


class FoundingProbe extends Node:
	var squads := 0
	var anchor := Vector3i(-1, -1, -1)
	func set_settlement_anchor(cell: Vector3i) -> void: anchor = cell
	func spawn_squad_at(_x: int, _z: int) -> int:
		squads += 1
		return 5


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	create_timer(90).timeout.connect(func(): push_error("SettlementNamingTest timed out"); quit(1))
	await process_frame
	events = root.get_node("EventLog")
	root.get_node("SaveManager").set_process(false)
	root.get_node("TaskManager").set_process(false)
	events.set_process(false)
	events.clear_runtime_state()
	root.get_node("WorldGenerator")._maps_ready = true
	root.get_node("WorldGenerator").world_seed = 1234
	root.size = Vector2i(1280, 720)
	_test_rules()
	_test_suggestions()
	await _build()
	await _test_card()
	await _test_founding()
	await _test_menu_title()
	root.remove_child(scene)
	scene.free()
	events.clear_runtime_state()
	for failure in failures: push_error(failure)
	print("SETTLEMENT_NAMING_OK" if failures.is_empty() else "SETTLEMENT_NAMING_FAIL")
	quit(0 if failures.is_empty() else 1)


func _test_rules() -> void:
	for good: String in ["Brunhald", "Ost's Hollow", "Stone-Deep", "Ærindal", "Ost’s Rest", "Kol", "Abcdefghijklmnopqrstuvwx"]:
		_expect(SettlementName.is_valid(good), "a name in the rules is kept: " + good)
	for bad: String in ["", "Ab", "Abcdefghijklmnopqrstuvwxy", "Brun1", "-Brun", "'Brun", "Brun\"hald", "Brun_hald", "Brun!"]:
		_expect(not SettlementName.is_valid(bad), "a name outside the rules is refused: " + bad)
	_expect(SettlementName.clean("  Brun   hald  ") == "Brun hald" and SettlementName.is_valid("  Brun   hald  "),
		"spaces at the ends go and a run of spaces becomes one")


func _test_suggestions() -> void:
	var styles: Array = load("res://scripts/registries/JsonData.gd").read_dict("res://data/colony/settlement_names.json").styles
	_expect(styles.size() == 2, "two styles of names: Dwarvish and plain words")
	for style: Dictionary in styles:
		for first: String in style.first:
			for second: String in style.second:
				_expect(SettlementName.is_valid(first + second), "every suggestion keeps the rules: " + first + second)
	var seen := {}
	for index in range(40):
		var name := SettlementName.suggestion(styles, 1234, index)
		_expect(not seen.has(name), "no suggestion repeats an earlier one: " + name)
		seen[name] = true
		var style: Dictionary = styles[index % 2]
		_expect(style.first.any(func(part: String) -> bool: return name.begins_with(part)), "the styles take turns: %d %s" % [index, name])
	_expect(SettlementName.suggestion(styles, 1234, 3) == SettlementName.suggestion(styles, 1234, 3), "the same world suggests the same names")
	for pair: Array in [["Grim", "rim"], ["Gun", "gund"], ["Skar", "rok"], ["Ash", "hollow"]]:
		_expect(SettlementName.stutters(pair[0], pair[1]), "a join that stutters is never suggested: " + pair[0] + pair[1])
	for pair: Array in [["Brun", "hald"], ["Stone", "hollow"], ["Ost", "rok"]]:
		_expect(not SettlementName.stutters(pair[0], pair[1]), "a clean join is suggested: " + pair[0] + pair[1])
	for name: String in seen: _expect(not name in ["Grimrim", "Gungund", "Skarrok", "Ashhollow"], "no suggestion stutters: " + name)
	var firsts := {}
	for seed in range(1, 11): firsts[SettlementName.suggestion(styles, seed * 7919, 0)] = true
	_expect(firsts.size() >= 5, "other worlds suggest other names: %s" % [firsts.keys()])


func _build() -> void:
	scene = Node3D.new()
	root.add_child(scene)
	current_scene = scene
	manager = load("res://scripts/ui/UIWindowManager.gd").new()
	manager.name = "Windows"
	scene.add_child(manager)
	manager._layout_loaded = false
	manager._layout.clear()
	dock = load("res://scripts/ui/DockUI.gd").new()
	dock.name = "Dock"
	dock.window_manager_path = NodePath("../Windows")
	scene.add_child(dock)
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.current = true
	camera.position = Vector3(40, 60, 60)
	camera.look_at(Vector3(CELL))
	var furniture := FurnitureProbe.new()
	furniture.add_to_group("furniture_controller")
	scene.add_child(furniture)
	founder = FoundingProbe.new()
	founder.name = "Founder"
	scene.add_child(founder)
	flag = load("res://scripts/systems/FlagPlacementController.gd").new()
	flag.dock_ui_path = NodePath("../Dock")
	flag.dwarf_director_path = NodePath("../Founder")
	scene.add_child(flag)
	flag.set_process(false)
	await _settle()
	card = dock._founding_card


## The card: the first suggestion, Suggest another, the rules, Cancel, ✕ and Esc.
func _test_card() -> void:
	var first: String = flag.suggestion(0)
	_expect(first == SettlementName.suggestion(flag._name_styles, 1234, 0) and SettlementName.is_valid(first),
		"the flag suggests the world's first name: " + first)
	flag.activate()
	flag._ask_name(CELL)
	await _settle()
	var window: Control = manager.get_ui_window("founding")
	_expect(flag.is_naming() and manager.is_open("founding") and card._field.text == first, "planting the flag asks for the name, holding the first suggestion")
	_expect(card._found.text == "Found " + first and not card._found.disabled, "Found names the settlement it will found")
	_expect(Rect2(Vector2.ZERO, Vector2(root.size)).encloses(window.get_global_rect()) and window.get_global_rect().end.y <= dock.dock_top(),
		"the card fits over the world: %s" % window.get_global_rect())
	var spot: Vector2 = get_root().get_camera_3d().unproject_position(Vector3(CELL) + Vector3(0.5, 2.0, 0.5))
	_expect(not window.get_global_rect().grow(40.0).has_point(spot), "the card keeps clear of the waiting flag")
	card._suggest.pressed.emit()
	_expect(card._field.text == flag.suggestion(1) and card._field.text != first, "Suggest another draws the next name: " + card._field.text)
	card._field.text = "X1"
	card._field.text_changed.emit(card._field.text)
	_expect(card._found.disabled and card._note.text == SettlementName.RULE, "a name outside the rules keeps Found off and says why")
	card._cancel.pressed.emit()
	await _settle()
	_expect(not manager.is_open("founding") and flag.is_active() and not flag.is_naming(), "Cancel closes the card and keeps the flag tool")
	flag._ask_name(CELL)
	await _settle()
	_expect(card._field.text == first, "the card opens on the first suggestion again")
	manager.close("founding")
	await _settle()
	_expect(flag.is_active() and not flag.is_naming(), "the card's ✕ keeps the flag tool as Cancel does")
	flag._ask_name(CELL)
	await _settle()
	card._field.grab_focus()
	var escape := InputEventKey.new()
	escape.pressed = true
	escape.keycode = KEY_ESCAPE
	root.push_input(escape, true)
	await _settle()
	_expect(not manager.is_open("founding") and flag.is_active() and not flag.is_naming(), "Esc in the field keeps the flag tool")
	_expect(founder.squads == 0 and not flag.is_founded(), "nothing is founded until Found")


## Found plants the flag under the name typed, with its entry in Events.
func _test_founding() -> void:
	flag._ask_name(CELL)
	await _settle()
	card._field.text = "  Ost's   Hollow "
	card._field.text_changed.emit(card._field.text)
	_expect(card._found.text == "Found Ost's Hollow" and not card._found.disabled, "Found shows the name as it will be kept")
	card._found.pressed.emit()
	await _settle()
	var clock: Node = root.get_node("WorldClock")
	_expect(flag.is_founded() and flag.settlement_name == "Ost's Hollow" and flag.founded_day == floori(clock.elapsed_days()),
		"Found plants the flag under the name, on today's date")
	_expect(not flag.is_active() and not manager.is_open("founding") and founder.squads == 1 and founder.anchor == CELL,
		"the card closes, the tool ends and the dwarves arrive")
	var entry: Dictionary = events.entries()[0] if not events.entries().is_empty() else {}
	_expect(entry.get("text", "") == "Ost's Hollow is founded." and entry.get("detail", "") == "5 dwarves have arrived with the flag."
		and entry.get("picture", "") == flag.PICTURE and entry.get("place", []) == [CELL.x, CELL.y, CELL.z] and entry.get("kind", "") == "colony",
		"Events announces the settlement by name: %s" % entry)
	var saved: Dictionary = flag.serialize_state()
	_expect(saved.name == "Ost's Hollow" and saved.founded_day == flag.founded_day and saved.founded, "the name and day are saved with the flag")
	_expect(flag.rename("Kolgund") and flag.settlement_name == "Kolgund" and not flag.rename("No"), "the settlement can be renamed within the rules")
	_expect(events.entries()[0].text == "Ost's Hollow is founded.", "renaming leaves Events as it was written")
	flag.activate()
	_expect(not flag.is_active(), "one founding per world")


func _test_menu_title() -> void:
	var menu: Node = root.get_node("GameMenu")
	menu.open()
	await _settle()
	_expect(menu._title.text == "Kolgund", "the game menu takes the settlement's name as its title: " + menu._title.text)
	menu.close()


func _settle() -> void:
	for frame in range(6): await process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
