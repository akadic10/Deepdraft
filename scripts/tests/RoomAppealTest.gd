extends "res://scripts/tests/WorkerCraftingTest.gd"

## Room appeal (doc 23 "Room appeal") and the room thoughts (doc 41). A sealed room's appeal
## adds up what it holds: each piece by its design and wood, the hearth's new 2, minus a
## pile of loose goods each and half a stocked storage cell each. A room past 64 floor tiles
## counts its share; the words turn at 0, 8 and 16, and
## the score is worked out again after every change and never saved. A sleep, a meal or a
## game in a room leaves its word's thought for its hours (Plain none), the next replaces
## it, and outside rooms leaves none; a real sleep in a bed takes in its room. The room
## window's banner and Appeal tab show it all.

const BED := "base:furniture:log_bed"
var rooms
var probe := Vector3i(62, 21, 62)
var wide_probe := Vector3i(85, 21, 64)
var room_window_tool


func _run() -> void:
	create_timer(150).timeout.connect(func(): push_error("Room appeal timeout"); quit(1))
	await _setup_crafting_fixture()
	rooms = root.get_node("RoomManager")
	rooms.clear_runtime_state()
	_words()
	_walls(60, 69, 60, 69)
	_put("door", Vector3i(63, 20, 60))
	var appeal := _appeal(probe)
	_expect(appeal.parts.size() == 1 and appeal.parts[0].key == "base:furniture:door" and is_equal_approx(appeal.total, 2.0)
		and appeal.tiles == 64 and is_equal_approx(appeal.share, 1.0) and is_equal_approx(appeal.score, 2.0) and appeal.word.word == "Plain",
		"a bare 8 by 8 room holds only its door's 2: Plain")
	var bed = _put("log_bed", Vector3i(62, 20, 64))
	_put("wooden_torch", Vector3i(68, 20, 64))
	_put("hearth", Vector3i(67, 20, 67))
	_put("bench", Vector3i(68, 20, 61), 1)
	appeal = _appeal(probe)
	var hearth: Array = appeal.parts.filter(func(part: Dictionary) -> bool: return part.key == "base:furniture:hearth")
	_expect(is_equal_approx(appeal.total, 9.5) and appeal.word.word == "Pleasant" and hearth.size() == 1 and is_equal_approx(hearth[0].value, 2.0),
		"a bed 3, a torch 0.5, the hearth 2 and a bench 2 with the door make 9.5: Pleasant (%s)" % appeal.total)
	_expect(float(appeal.parts[0].value) >= float(appeal.parts[appeal.parts.size() - 1].value), "the parts are listed largest first")
	drops.spawn_drop(STONE, 1, Vector3i(61, 21, 62))
	drops.spawn_drop(LOG, 1, Vector3i(61, 21, 63))
	var store = load("res://scripts/components/StockpileZoneComponent.gd").new()
	var stored: Array[Vector3i] = [Vector3i(61, 20, 68), Vector3i(62, 20, 68)]
	store.setup(77, stored)
	stockpiles.register_zone(store)
	for cell: Vector3i in stored:
		store.cell_stacks[cell] = {"item": STONE, "count": 1}
		drops.restore_stored_item(STONE, cell, 1)
	appeal = _appeal(probe)
	var loose: Array = appeal.parts.filter(func(part: Dictionary) -> bool: return part.key == "loose")
	var stocked: Array = appeal.parts.filter(func(part: Dictionary) -> bool: return part.key == "stocked")
	_expect(loose.size() == 1 and loose[0].count == 2 and is_equal_approx(loose[0].value, -1.0) and stocked.size() == 1 and stocked[0].count == 2
		and is_equal_approx(stocked[0].value, -0.5) and is_equal_approx(appeal.score, 6.5) and appeal.word.word == "Plain",
		"two piles of loose goods take 2 and two stocked cells take 1: Plain 6.5 (%s)" % appeal.score)
	# Taking the store away turns its goods loose; then every loose pile goes.
	stockpiles.deregister_zone(store)
	for node in drops._loose.keys():
		drops.take(node)
		node.free()
	appeal = _appeal(probe)
	_expect(is_equal_approx(appeal.score, 9.5) and appeal.word.word == "Pleasant", "with the goods gone it is Pleasant 9.5 again (%s)" % appeal.score)
	var table = _put("log_table", Vector3i(65, 20, 61))
	appeal = _appeal(probe)
	_expect(is_equal_approx(appeal.score, 10.5) and appeal.word.word == "Pleasant", "a table is worked in at once: 10.5")
	var stool = _put("log_chair", Vector3i(66, 20, 64), 2)
	appeal = _appeal(probe)
	_expect(is_equal_approx(appeal.score, 11.5) and appeal.word.word == "Pleasant" and rooms.appeal_at(probe + Vector3i(3, 0, 3)) == appeal
		and rooms.appeal_at(Vector3i(50, 21, 50)).is_empty(), "a stool makes it Pleasant 11.5; outside the room there is none")
	_expect(not rooms.is_in_group("save_state_owner") and not rooms.has_method("serialize_state"), "appeal is worked out, never saved")
	_wide_room()
	await _check_window()
	await _thoughts(bed)
	var held := float(_appeal(probe).score)
	furniture._teardown_installed(stool.installed_id, false)
	furniture._teardown_installed(table.installed_id, false)
	appeal = _appeal(probe)
	_expect(is_equal_approx(appeal.score, held - 4.0) and appeal.word.word == "Plain",
		"taking the stool and table out takes their 2, and the two packed pieces left lying take 2 more: Plain %s from %s" % [appeal.score, held])
	for failure: String in failures: push_error(failure)
	print("ROOM_APPEAL_OK: words, parts, hearth, loose and stocked goods, size share, changes, thoughts, sleep and window" if failures.is_empty() else "ROOM_APPEAL_FAIL")
	quit(0 if failures.is_empty() else 1)


## The words turn at 0, 8 and 16, and a save names them in lower case.
func _words() -> void:
	var said := [-0.1, 0.0, 7.99, 8.0, 15.99, 16.0, 120.0].map(func(score: float) -> String: return rooms.appeal_word(score))
	_expect(said == ["Horrid", "Plain", "Plain", "Pleasant", "Pleasant", "Beautiful", "Beautiful"], "the words turn at 0, 8 and 16: %s" % [said])
	_expect(rooms.appeal_word_ids().keys() == ["", "horrid", "plain", "pleasant", "beautiful"], "a save may name each word, or none")
	_expect(is_equal_approx(float(rooms.appeal_step(20.0).points), 0.08) and is_equal_approx(float(rooms.appeal_step(-3.0).points), -0.06)
		and is_zero_approx(float(rooms.appeal_step(3.0).points)), "Beautiful gives 8, Horrid takes 6 and Plain gives nothing")


## A 16 by 8 room counts half of what it holds.
func _wide_room() -> void:
	_walls(80, 97, 60, 69)
	_put("door", Vector3i(83, 20, 60))
	var appeal := _appeal(wide_probe)
	_expect(appeal.tiles == 128 and is_equal_approx(appeal.share, 0.5) and is_equal_approx(appeal.score, 1.0),
		"a 128-tile room counts half its door's 2: 1 (%s over %s tiles)" % [appeal.score, appeal.tiles])


## The banner shows the word and the number; the Appeal tab lists each part, the size and
## the score on the scale, and says what a stay here leaves.
func _check_window() -> void:
	room_window_tool = load("res://scripts/systems/RoomOverlayController.gd").new()
	room_window_tool.window_manager_path = NodePath("../Windows")
	room_window_tool.dock_ui_path = NodePath("../Dock")
	scene.add_child(room_window_tool)
	room_window_tool._select_room(rooms.get_room_id_at(probe), probe)
	await _frames(4)
	var panel = room_window_tool._window_content
	var appeal := _appeal(probe)
	_expect(panel._banner_word.text == "Pleasant" and panel._banner_value.text == "11.5", "the banner shows Pleasant 11.5")
	_expect(panel._tabs.map(func(tab: Button) -> String: return tab.text) == ["Overview", "Appeal", "Details"], "the room window has an Appeal tab")
	panel._show_tab(1)
	await _frames(3)
	_expect(panel._appeal.visible and not panel._overview.visible and not panel._details.visible, "the Appeal tab shows its page alone")
	var titles: Array = panel._appeal_rows.map(func(row: Dictionary) -> String: return row.title.text)
	_expect(panel._appeal_rows.size() == appeal.parts.size() and "Rudimentary hearth" in titles and "Log bed" in titles,
		"each part has its row: %s" % [titles])
	var hearth_row: Dictionary = panel._appeal_rows[titles.find("Rudimentary hearth")]
	_expect(hearth_row.value.text == "+2" and hearth_row.frame.get_child(0).texture != null, "a part shows its picture and what it adds")
	_expect(panel._appeal_total.value.text == "11.5" and panel._appeal_size.note.text == "64 floor tiles · counts in full",
		"the sums: 11.5 held, counted in full (%s · %s)" % [panel._appeal_total.value.text, panel._appeal_size.note.text])
	_expect(panel._appeal_score.text == "Appeal 11.5 · Pleasant" and panel._appeal_note.text.contains("+4 happiness"),
		"the score and what a stay leaves: %s / %s" % [panel._appeal_score.text, panel._appeal_note.text])
	var scale = panel._appeal_scale
	var segment: float = scale.size.x / 4.0
	_expect(scale.size.x > 0.0 and scale.place(16.5) > segment * 3.0 and scale.place(2.0) > segment and scale.place(2.0) < segment * 2.0
		and scale.place(-20.0) == 0.0, "the scale marks a score inside its word's segment")
	room_window_tool._select_room(rooms.get_room_id_at(wide_probe), wide_probe)
	await _frames(4)
	_expect(panel._appeal_size.note.text == "128 floor tiles · counts 50%" and panel._appeal_size.value.text == "1"
		and panel._appeal_note.text.contains("At 8 it is Pleasant"), "a large plain room shows its share and what makes it Pleasant: %s / %s" % [
			panel._appeal_size.note.text, panel._appeal_note.text])
	room_window_tool._close_window()


## A sleep, a meal or a game in a room leaves its word's thought; Plain and outside rooms
## leave none, the next of each replaces it, and they end with their hours.
func _thoughts(bed) -> void:
	var mood: RefCounted = worker.get_mood()
	mood.restore(_blank(mood))
	var before: float = mood.value()
	var beautiful := {"score": 20.0, "word": rooms.appeal_step(20.0), "parts": []}
	mood.record_room("slept", beautiful)
	var row: Dictionary = _row(mood, "slept_beautiful")
	_expect(row.get("text") == "Slept in a beautiful room" and row.get("points") == 8 and is_equal_approx(float(row.get("hours", 0)), 24.0)
		and is_equal_approx(mood.value(), before + 0.08), "a sleep in a beautiful room is +8 for 24 hours: %s" % row)
	var horrid := {"score": -1.0, "word": rooms.appeal_step(-1.0), "parts": []}
	mood.record_room("ate", horrid)
	row = _row(mood, "ate_horrid")
	_expect(row.get("text") == "Ate in a horrid room" and row.get("points") == -6 and is_equal_approx(float(row.get("hours", 0)), 8.0)
		and String(row.get("help", "")).begins_with("Furnish the room"), "a meal in a horrid room is −6 for 8 hours, with what helps: %s" % row)
	mood.record_room("played", {"score": 4.0, "word": rooms.appeal_step(4.0), "parts": []})
	mood.record_room("ate", {})
	_expect(_row(mood, "ate_horrid").is_empty() and mood.thoughts().filter(func(thought: Dictionary) -> bool: return String(thought.id).begins_with("played")).is_empty(),
		"a plain room leaves no thought, and a meal outside a room ends the last one")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(mood.serialize()))
	mood.restore(_blank(mood))
	mood.restore(saved)
	_expect(not _row(mood, "slept_beautiful").is_empty() and saved.slept_room == "beautiful", "a room memory survives a save")
	mood.tick(24.5)
	_expect(_row(mood, "slept_beautiful").is_empty() and is_equal_approx(mood.value(), before), "the memory ends with its hours")
	# A real night in the bed takes in its room.
	worker.stop_walking()
	worker.position = Vector3(63.5, 21, 58.5)
	worker._begin_sleep()
	var resting := false
	for i in 400:
		worker._process(.1)
		if worker.is_resting():
			resting = worker._rest_behavior.bed_rest.bed == bed
			break
		await process_frame
	worker._sleep_hours_left = 0.01
	for i in 3: worker._process(.5)
	_expect(resting and not _row(mood, "slept_pleasant").is_empty(), "a night in the bed leaves the room's thought: %s" % [mood.thoughts().map(func(thought: Dictionary) -> String: return thought.id)])
	worker._wake_up()


func _row(mood: RefCounted, id: String) -> Dictionary:
	for thought: Dictionary in mood.thoughts():
		if thought.id == id: return thought
	return {}


func _blank(mood: RefCounted) -> Dictionary:
	var blank: Dictionary = mood.serialize()
	for key: String in blank: blank[key] = "" if blank[key] is String else 0.0
	return blank


func _appeal(cell: Vector3i) -> Dictionary:
	rooms._rebuild_all_rooms()
	return rooms.appeal_at(cell)


func _put(short_key: String, cell: Vector3i, yaw := 0):
	var key := "base:furniture:" + short_key
	furniture._install(key, furniture.get_defs()[key], cell, yaw)
	return furniture._installed[furniture._next_installed_id - 1]


## Stone walls and a roof around the floor x0+1..x1-1 by z0+1..z1-1 (y 20), with a
## two-wide doorway at x0+3 on the z0 side.
func _walls(x0: int, x1: int, z0: int, z1: int) -> void:
	var stone: int = blocks.get_id("base:terrain:rock:rock01")
	for x in range(x0, x1 + 1):
		for z in range(z0, z1 + 1):
			for y in range(21, 26):
				if x in [x0 + 3, x0 + 4] and z == z0 and y < 25: continue
				if x in [x0, x1] or z in [z0, z1] or y == 25: world.set_block(x, y, z, stone)
