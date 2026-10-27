extends "res://scripts/tests/WorkerCraftingTest.gd"

## Personal tastes (doc 41 "Tastes"). A new dwarf is given one love, two
## likes and one dislike among tastes.json's things, the same from the same seed. A taste is
## found when the dwarf uses the thing, once, and the journal tells it in the dwarf's words.
## A found taste moves the appeal that dwarf feels in a room holding the thing (a design, or
## anything of the wood), once a thing; the room's thought names the strongest; a taste not
## yet found does nothing. A night in the bed finds its tastes before the room's thought. The
## character sheet's Tastes tab shows each taste as a tile, "?" until found, and how their
## own bedroom feels to them; the room window says the same for its owner.

var rooms
var probe := Vector3i(62, 21, 62)
const LOVES := {"base:furniture:log_bed": "love", "base:material:oak": "like", "base:furniture:bench": "like", "base:material:pine": "dislike"}


func _run() -> void:
	create_timer(150).timeout.connect(func(): push_error("Tastes timeout"); quit(1))
	await _setup_crafting_fixture()
	rooms = root.get_node("RoomManager")
	rooms.clear_runtime_state()
	_given()
	_walls(60, 69, 60, 69)
	_put("door", Vector3i(63, 20, 60))
	var bed = _put("log_bed", Vector3i(62, 20, 64), 0, "base:material:pine")
	_put("wooden_torch", Vector3i(68, 20, 64))
	_put("bench", Vector3i(68, 20, 61), 1)
	furniture.assign_bed(bed.installed_id, worker.dwarf_id)
	rooms._rebuild_all_rooms()
	var tastes: RefCounted = worker.get_tastes()
	tastes.setup(LOVES, [])
	_felt(tastes)
	await _night(bed)
	await _sheet()
	_room_window()
	for failure: String in failures: push_error(failure)
	print("TASTES_OK: given, found, felt, named, night, sheet and room window" if failures.is_empty() else "TASTES_FAIL")
	quit(0 if failures.is_empty() else 1)


## One love, two likes and one dislike among the things, the same from the same seed.
func _given() -> void:
	var factory = load("res://scripts/entities/DwarfFactory.gd").new()
	var things: Dictionary = root.get_node("DwarfAssets").get_taste_data().things
	var first: Dictionary = factory.generate(3, {}).tastes
	var again: Dictionary = factory.generate(3, {}).tastes
	var kinds: Array = first.values()
	_expect(first.size() == 4 and kinds.count("love") == 1 and kinds.count("like") == 2 and kinds.count("dislike") == 1
		and first.keys().all(func(id: String) -> bool: return things.has(id)), "a new dwarf loves one thing, likes two and dislikes one: %s" % first)
	_expect(first == again, "the same seed gives the same tastes")
	var others := {}
	for index in range(8): others[str(factory.generate(index, {}).tastes)] = true
	_expect(others.size() > 1, "dwarves differ in their tastes")
	_expect(factory.generate(3, {}).found_tastes.is_empty(), "a new dwarf has found none")


## A found taste moves the appeal the dwarf feels; one not found does nothing; each thing
## counts once; the strongest is named.
func _felt(tastes: RefCounted) -> void:
	var appeal: Dictionary = rooms.room_appeal(rooms.get_room_at(probe))
	var plain: Dictionary = tastes.felt(appeal)
	_expect(is_equal_approx(float(plain.score), float(appeal.score)) and String(plain.taste).is_empty(), "tastes not yet found change nothing")
	var news: Array = tastes.meet([furniture.get_installed_at(Vector3i(62, 20, 64))])
	var found_ids: Array = news.map(func(found: Dictionary) -> String: return found.id)
	_expect(found_ids == ["base:furniture:log_bed", "base:material:pine"] and tastes.meet([furniture.get_installed_at(Vector3i(62, 20, 64))]).is_empty(),
		"sleeping in a pine log bed finds the love for the bed and the dislike of pine, once: %s" % [found_ids])
	var felt: Dictionary = tastes.felt(appeal)
	_expect(is_equal_approx(float(felt.score), float(appeal.score)) and String(felt.taste) == "base:furniture:log_bed",
		"a loved bed of a disliked wood: +4 and −4, the love named: %s" % felt)
	tastes.meet([furniture.get_installed_at(Vector3i(68, 20, 61))])
	felt = tastes.felt(appeal)
	_expect(is_equal_approx(float(felt.score), float(appeal.score) + 2.0), "a liked bench adds 2 once found: %s" % felt.score)
	_expect(tastes.describe("base:furniture:log_bed") == "loves the log bed" and tastes.describe("base:material:pine") == "dislikes pine",
		"a taste reads as a sentence")
	tastes.setup(LOVES, [])


## A night in the bed finds its tastes before the room's thought, which names the love; the
## journal tells each found taste in the dwarf's words.
func _night(bed) -> void:
	var journal: Node = root.get_node("ColonyJournal")
	journal.clear_runtime_state()
	var mood: RefCounted = worker.get_mood()
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
	worker._wake_up()
	var tastes: RefCounted = worker.get_tastes()
	_expect(resting and tastes.found.has("base:furniture:log_bed") and tastes.found.has("base:material:pine") and not tastes.found.has("base:furniture:bench"),
		"a night in the pine log bed finds those two tastes")
	var lines: Array = journal.lines()
	var love: Array = lines.filter(func(line: Dictionary) -> bool: return line.topic == "found_love:base:furniture:log_bed")
	var dislike: Array = lines.filter(func(line: Dictionary) -> bool: return line.topic == "found_dislike:base:material:pine")
	_expect(love.size() == 1 and love[0].text == "Found a taste: loves the log bed" and love[0].tone == "praise" and String(love[0].words).contains("log bed")
		and dislike.size() == 1 and dislike[0].tone == "complaint" and String(dislike[0].words).contains("pine"),
		"the journal tells each found taste in the dwarf's words: %s" % [lines])
	var slept: Array = mood.thoughts().filter(func(thought: Dictionary) -> bool: return String(thought.id).begins_with("slept_"))
	var appeal: Dictionary = rooms.room_appeal(rooms.get_room_at(probe))
	_expect(float(appeal.score) < 8.0, "the room alone is Plain: %s" % appeal.score)
	_expect(slept.is_empty(), "a love and a dislike cancel out, so a plain room still leaves no thought: %s" % [slept])
	# With the bench found too, the room feels Pleasant, and the thought names the love.
	tastes.meet([furniture.get_installed_at(Vector3i(68, 20, 61))])
	mood.record_room("slept", appeal)
	slept = mood.thoughts().filter(func(thought: Dictionary) -> bool: return String(thought.id).begins_with("slept_"))
	_expect(slept.size() == 1 and slept[0].id == "slept_pleasant" and slept[0].text == "Slept in a pleasant room · loves the log bed",
		"the room's thought is the room as the dwarf feels it, naming the love: %s" % [slept])
	var saved: Dictionary = JSON.parse_string(JSON.stringify(mood.serialize()))
	_expect(saved.slept_room_taste == "base:furniture:log_bed", "the named taste is saved with the memory")


## The Tastes tab: tiles by kind, a found one's picture and name, "?" for the rest, and how
## the dwarf's own bedroom feels to them.
func _sheet() -> void:
	var panel = load("res://scripts/ui/DwarfInspectorPanel.gd").new()
	scene.add_child(panel)
	await _frames(2)
	panel.show_data(load("res://scripts/components/DwarfInspection.gd").describe(worker), false)
	panel._show_tab(panel.TASTES_TAB)
	await _frames(2)
	var loves: Array = panel._taste_rows.love.get_children()
	var likes: Array = panel._taste_rows.like.get_children()
	var dislikes: Array = panel._taste_rows.dislike.get_children()
	_expect(loves.size() == 1 and likes.size() == 2 and dislikes.size() == 1, "a tile for each taste, by kind")
	var love_name: Label = loves[0].get_child(1)
	var oak_name: Label = likes.filter(func(tile: Control) -> bool: return tile.tooltip_text.begins_with("Not found"))[0].get_child(1)
	_expect(love_name.text == "Log bed" and oak_name.text == "Not found yet", "a found taste shows its name; one not found shows only \"?\"")
	_expect(panel._own_room.text.begins_with("%s's bedroom is Plain" % worker.dwarf_name) and panel._own_room.text.contains("loves the log bed, so to them it is Pleasant")
		and not is_nan(panel._own_scale.felt), "their own bedroom, as it is and as it feels to them: %s" % panel._own_room.text)
	panel.queue_free()


## The room window says how its owner feels it when a found taste moves it.
func _room_window() -> void:
	var window = load("res://scripts/ui/RoomInspectorPanel.gd").new()
	scene.add_child(window)
	window.show_room(rooms.get_room_at(probe))
	_expect(window._appeal_feel.visible and window._appeal_feel.text.begins_with("%s loves the log bed, so to them it is Pleasant" % worker.dwarf_name)
		and not is_nan(window._appeal_scale.felt), "the room window says how its owner feels it: %s" % window._appeal_feel.text)
	window.queue_free()


func _put(short_key: String, cell: Vector3i, yaw := 0, material := ""):
	var key := "base:furniture:" + short_key
	furniture._install(key, furniture.get_defs()[key], cell, yaw, material)
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
