extends SceneTree

## The colony's journal (doc 23): what dwarves already think when it first sees them is not
## news; a thought that begins opens today's line for its topic in the dwarf's words, and
## another dwarf whose same thought begins that day joins it; a memory that comes again
## begins anew, still one line per topic a day; a thought that ends and returns begins
## again; complaints and praises go by the thought's sign; nothing is noted while the clock
## stands still; ten days are kept; the save section round-trips and a load starts the look
## afresh. Every thought a dwarf can have has its lines. The page's journal is
## SettlementPanelTest's; validating the section is SaveManagerRoundTripTest's.
const THOUGHTS := ["bedroom", "recreation_together", "recreation_alone", "hungry", "famished", "dining_seat_only",
	"dining_table_only", "dining_neither", "cold", "chilly", "hot", "slept_horrid", "slept_pleasant", "slept_beautiful",
	"ate_horrid", "ate_pleasant", "ate_beautiful", "played_horrid", "played_pleasant", "played_beautiful"]
## A found taste's lines, by its kind (doc 41 "Tastes").
const FOUND := ["found_love", "found_like", "found_dislike"]
var failures: Array[String] = []
var journal: Node
var clock: Node
var tasks: Node
var scene: Node3D
var dwarves: Array = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	create_timer(90).timeout.connect(func(): push_error("ColonyJournalTest timed out"); quit(1))
	await process_frame
	journal = root.get_node("ColonyJournal")
	clock = root.get_node("WorldClock")
	tasks = root.get_node("TaskManager")
	for node: String in ["SaveManager", "TaskManager", "EventLog", "ColonyJournal", "WorldClock"]: root.get_node(node).set_process(false)
	journal.clear_runtime_state()
	# Flat ground for the dwarves; the clock runs (the journal rests while it is paused) but
	# only moves when the test moves it.
	var generator: Node = root.get_node("WorldGenerator")
	var columns: int = root.get_node("WorldData").WORLD_SIZE_X * root.get_node("WorldData").WORLD_SIZE_Z
	generator._maps_ready = true
	generator.world_seed = 1234
	generator.heightmap.resize(columns)
	generator.heightmap.fill(20)
	generator.waterline_map.resize(columns)
	generator.waterline_map.fill(-1)
	generator._cache_block_ids()
	clock.restore_state({"year": 1, "season": "autumn", "day": 3, "hour": 9.0, "speed": 1.0, "paused": false})
	_test_lines_data()
	await _build()
	_test_beginnings()
	_test_days()
	_test_saving()
	for dwarf: Node in dwarves: tasks.deregister_dwarf(dwarf.dwarf_id)
	root.remove_child(scene)
	scene.free()
	journal.clear_runtime_state()
	for failure in failures: push_error(failure)
	print("COLONY_JOURNAL_OK" if failures.is_empty() else "COLONY_JOURNAL_FAIL")
	quit(0 if failures.is_empty() else 1)


func _test_lines_data() -> void:
	var lines: Dictionary = journal.config.lines
	_expect(lines.keys().size() == THOUGHTS.size() + FOUND.size(), "the journal has lines for each thought and found taste and no others: %s" % [lines.keys()])
	for id: String in THOUGHTS + FOUND:
		var said: Array = lines.get(id, [])
		_expect(not said.is_empty() and said.all(func(words: Variant) -> bool: return words is String and not String(words).is_empty()),
			"a thought has words to say: " + id)
	var mood = load("res://scripts/components/DwarfMood.gd").new()
	mood.record_recreation(true)
	mood.record_dining("neither")
	mood.bedroom_memory_hours = 24.0
	mood.thermal_memory.chilly = 24.0
	var ids: Array = mood.thoughts().map(func(thought: Dictionary) -> String: return thought.id)
	_expect(ids == ["recreation_together", "dining_neither", "bedroom", "chilly"], "each thought carries its id: %s" % [ids])


func _build() -> void:
	scene = Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var factory = load("res://scripts/entities/DwarfFactory.gd").new()
	for id in [401, 402, 403]:
		var agent = factory.spawn(factory.generate(id, {}), id)
		scene.add_child(agent)
		agent.set_process(false)
		agent.set_physics_process(false)
		agent.position = Vector3(38.5 + id % 4, 21, 38.5)
		tasks.register_dwarf(agent)
		dwarves.append(agent)
	await process_frame


func _test_beginnings() -> void:
	var a: Node = dwarves[0]
	var b: Node = dwarves[1]
	a.get_mood().thermal_memory.chilly = 24.0
	journal.check_thoughts()
	_expect(journal.lines().is_empty(), "what dwarves already think when the journal first sees them is not news")
	a.get_mood().bedroom_memory_hours = 24.0
	journal.check_thoughts()
	var lines: Array = journal.lines()
	var line: Dictionary = lines[0] if lines.size() == 1 else {}
	_expect(lines.size() == 1 and line.get("topic") == "bedroom" and line.get("text") == "Slept in my own bedroom" and line.get("tone") == "praise"
		and line.get("dwarves") == [a.dwarf_id] and line.get("speaker") == a.dwarf_id and line.get("name") == a.dwarf_name
		and line.get("words") in journal.config.lines.bedroom and line.get("day") == floori(clock.elapsed_days()),
		"a thought that begins opens today's line in the dwarf's words: %s" % line)
	b.get_mood().bedroom_memory_hours = 24.0
	journal.check_thoughts()
	lines = journal.lines()
	_expect(lines.size() == 1 and lines[0].dwarves == [a.dwarf_id, b.dwarf_id] and lines[0].speaker == a.dwarf_id,
		"another dwarf whose same thought begins joins the line")
	# The memory fades a while, then comes again the same day: still one line, the dwarf once.
	a.get_mood().tick(6.0)
	journal.check_thoughts()
	a.get_mood().bedroom_memory_hours = 24.0
	journal.check_thoughts()
	_expect(journal.lines().size() == 1 and journal.lines()[0].dwarves.size() == 2, "a topic keeps one line a day, and a dwarf counts once")
	b.get_mood().record_dining("neither")
	journal.check_thoughts()
	lines = journal.lines()
	_expect(lines.size() == 2 and lines[0].topic == "dining_neither" and lines[0].tone == "complaint" and lines[0].text == "Ate without a proper place",
		"a bad thought is a complaint")


func _test_days() -> void:
	var a: Node = dwarves[0]
	var b: Node = dwarves[1]
	var c: Node = dwarves[2]
	clock.advance_hours(24.0)
	a.get_mood().tick(6.0)
	journal.check_thoughts()
	a.get_mood().bedroom_memory_hours = 24.0
	journal.check_thoughts()
	var lines: Array = journal.lines()
	_expect(lines.size() == 3 and lines[0].topic == "bedroom" and lines[0].day == floori(clock.elapsed_days()) and lines[0].dwarves == [a.dwarf_id],
		"a memory that comes again on another day opens that day's line")
	b.get_mood().dining_memory_hours = 0.0
	journal.check_thoughts()
	b.get_mood().record_dining("seat_only")
	journal.check_thoughts()
	_expect(journal.lines()[0].topic == "dining_seat_only", "a thought that ended and returns begins again")
	clock.set_paused(true)
	c.get_mood().record_recreation(true)
	journal.check_thoughts()
	_expect(journal.lines().size() == 4, "nothing is noted while the clock stands still")
	clock.set_paused(false)
	journal.check_thoughts()
	_expect(journal.lines().size() == 5 and journal.lines()[0].topic == "recreation_together" and journal.lines()[0].speaker == c.dwarf_id,
		"what began while paused is noted once the clock runs")
	var first_day: int = journal.lines().back().day
	clock.advance_hours(24.0 * 9.0)
	c.get_mood().record_dining("table_only")
	journal.check_thoughts()
	lines = journal.lines()
	_expect(not lines.any(func(line: Dictionary) -> bool: return line.day == first_day) and lines.any(func(line: Dictionary) -> bool: return line.day == first_day + 1),
		"ten days are kept, today included")


func _test_saving() -> void:
	var before: Array = journal.lines()
	var saved: Dictionary = JSON.parse_string(JSON.stringify(journal.serialize_state()))
	journal.clear_runtime_state()
	_expect(journal.lines().is_empty(), "a new world starts with an empty journal")
	journal.restore_state(saved)
	var after: Array = journal.lines()
	_expect(after == before and typeof(after[0].day) == TYPE_INT and typeof(after[0].speaker) == TYPE_INT and typeof(after[0].dwarves[0]) == TYPE_INT,
		"the journal round-trips through a save, its numbers whole")
	journal.check_thoughts()
	_expect(journal.lines() == before, "after a load, what the dwarves already think is not news again")


func _expect(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
