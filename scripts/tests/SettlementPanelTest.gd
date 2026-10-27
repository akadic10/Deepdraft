extends SceneTree

## Colony's page (doc 23): Colony on the dock opens it and lights while it is open; before
## the flag it offers Found the settlement, which starts the flag tool; after it, the header
## (name, founding line, profession badges, the colony's mood), Colony's entries opening
## their windows, and the five rows at a glance from a set colony, each value, meter, goal
## and tag in its tone; the page reading three real dwarves; Rename with its rules, Suggest
## another, Done and Esc; the journal beside the rows (days, complaints then praises, faces,
## counts and words, scrolling by itself); and the fit at 960×540, 1280×720 and 2560×1440,
## the journal under the rows on small screens. The furniture and the squad are stand-ins;
## naming at the flag is SettlementNamingTest's, the journal's own rules ColonyJournalTest's.
const SettlementName = preload("res://scripts/components/SettlementName.gd")
const CELL := Vector3i(40, 20, 40)
var failures: Array[String] = []
var tasks: Node
var scene: Node3D
var manager: Node
var dock: Node
var flag: Node
var panel: Node
var dwarves: Array = []


class FurnitureProbe extends Node:
	signal furniture_installed(key: String, cell: Vector3i)
	func install_now(key: String, cell: Vector3i, _yaw: int) -> void: furniture_installed.emit(key, cell)
	func get_catalog_location(_key: String) -> Dictionary: return {}


class FoundingProbe extends Node:
	func set_settlement_anchor(_cell: Vector3i) -> void: pass
	func spawn_squad_at(_x: int, _z: int) -> int: return 3


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	create_timer(120).timeout.connect(func(): push_error("SettlementPanelTest timed out"); quit(1))
	await process_frame
	tasks = root.get_node("TaskManager")
	root.get_node("SaveManager").set_process(false)
	tasks.set_process(false)
	root.get_node("EventLog").set_process(false)
	root.get_node("EventLog").clear_runtime_state()
	# Flat ground, for the walkability the roster's work groups read.
	var generator: Node = root.get_node("WorldGenerator")
	var columns: int = root.get_node("WorldData").WORLD_SIZE_X * root.get_node("WorldData").WORLD_SIZE_Z
	generator._maps_ready = true
	generator.world_seed = 1234
	generator.heightmap.resize(columns)
	generator.heightmap.fill(20)
	generator.waterline_map.resize(columns)
	generator.waterline_map.fill(-1)
	generator._cache_block_ids()
	root.get_node("WorldClock").restore_state({"year": 1, "season": "autumn", "day": 3, "hour": 9.0, "speed": 1.0, "paused": true})
	root.size = Vector2i(2560, 1440)
	await _build()
	await _test_before_founding()
	await _test_founded()
	_test_rows()
	await _test_entries()
	await _test_rename()
	await _test_journal()
	await _test_sizes()
	for dwarf: Node in dwarves: tasks.deregister_dwarf(dwarf.dwarf_id)
	root.remove_child(scene)
	scene.free()
	root.get_node("EventLog").clear_runtime_state()
	for failure in failures: push_error(failure)
	print("SETTLEMENT_PANEL_OK" if failures.is_empty() else "SETTLEMENT_PANEL_FAIL")
	quit(0 if failures.is_empty() else 1)


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
	var furniture := FurnitureProbe.new()
	furniture.add_to_group("furniture_controller")
	scene.add_child(furniture)
	var founder := FoundingProbe.new()
	founder.name = "Founder"
	scene.add_child(founder)
	flag = load("res://scripts/systems/FlagPlacementController.gd").new()
	flag.dock_ui_path = NodePath("../Dock")
	flag.dwarf_director_path = NodePath("../Founder")
	scene.add_child(flag)
	flag.set_process(false)
	await _settle()
	panel = dock._colony_panel


func _test_before_founding() -> void:
	var colony: Button = dock._button_by_target.colony
	_click(colony.get_global_rect().get_center())
	await _settle()
	_expect(manager.is_open("colony") and manager.get_ui_window("colony").get_title_label().text == "Colony" and colony.button_pressed,
		"Colony on the dock opens its page, titled Colony, and lights while it is open")
	_expect(not dock.is_action_menu_open(), "Colony opens no menu any more")
	_expect(panel._name.text == "No settlement yet" and panel._found.visible and not panel._rename.visible and panel._before.visible,
		"before the flag the page says so and offers Found the settlement")
	_expect(not panel._entries.visible and not panel._scroll.visible and not panel._mood.visible and panel._founded.text == panel.BEFORE,
		"before the flag there are no entries, rows or mood")
	panel._found.pressed.emit()
	await _settle()
	_expect(not manager.is_open("colony") and flag.is_active() and not colony.button_pressed, "Found the settlement closes the page and starts the flag tool")
	flag.deactivate()


func _test_founded() -> void:
	for id in [301, 302, 303]: dwarves.append(_dwarf(id))
	dwarves[2].profession = "base:profession:miner"
	for dwarf: Node in dwarves.slice(0, 2): dwarf.get_mood().thermal_memory.chilly = 12.0
	flag._place_flag(CELL)
	dock._dispatch("toggle_window", "colony")
	await _settle()
	_expect(panel._name.text == flag.settlement_name and panel._name.visible and panel._rename.visible and not panel._found.visible,
		"the header names the settlement, with Rename")
	_expect(panel._founded.text == "Founded Autumn, day 3, year 1 · 3 dwarves", "the founding line: " + panel._founded.text)
	var live: Dictionary = panel.read_colony(self)
	_expect(live.dwarves == 3 and live.professions == {"base:profession:worker": 2, "base:profession:miner": 1}
		and (live.groups.idle as Array).size() == 3, "the page reads the real dwarves, their work and professions: %s" % live)
	_expect(live.complaint.get("text", "") == "Chilly sleep" and live.complaint.get("count", 0) == 2
		and live.complaint.get("help", "") == "Warm the sleeping room with a hearth.", "the main complaint, how many share it and what helps: %s" % live.complaint)
	var points: Array = dwarves.map(func(dwarf: Node) -> int: return dwarf.get_mood().points())
	_expect(live.points == roundi((points[0] + points[1] + points[2]) / 3.0), "happiness is the dwarves' average: %s of %s" % [live.points, points])
	_expect(live.capacity == 0 and _row_text("storage") == "No storage yet", "without storage the row says so")
	_expect(panel._entries.visible and panel._scroll.visible and panel._mood.visible and not panel._before.visible, "after founding the entries, rows and mood show")


## The rows from a set colony: values in words, meters toward their goals, tags in tones.
func _test_rows() -> void:
	panel.set_process(false)
	var colony := {"dwarves": 5, "groups": {"working": ["Guntris"], "resting": ["Ildgra"], "idle": ["Brokk", "Hilde", "Ulfa"]},
		"professions": {"base:profession:worker": 3, "base:profession:miner": 1, "base:profession:carpenter": 1}, "points": 58,
		"complaint": {"text": "Chilly sleep", "count": 4, "help": "Warm the sleeping room with a hearth."},
		"food_days": 6.4, "beds": 5, "used": 105, "capacity": 242, "items": 380}
	panel.show_colony(colony)
	_expect(_row_text("dwarves") == "5 dwarves" and _tags("dwarves") == [["1 working", "fine"], ["1 resting", "waiting"], ["3 idle", "waiting"]],
		"Dwarves: how many, and a tag for each group: %s" % [_tags("dwarves")])
	var idle: Control = panel._rows.dwarves.line.get_child(2)
	_expect(idle.tooltip_text == "Brokk, Hilde, Ulfa", "a group's names show on hover")
	_expect(_row_text("food") == "Food for 6 days" and _goal("food") == "Goal 10 days" and _tags("food") == [["Low", "waiting"]]
		and is_equal_approx(panel._rows.food.meter.fraction, 0.64), "Food: days of food toward the goal, Low in hay")
	_expect(_row_text("beds") == "5 of 5 sleep in their own bedroom" and _tags("beds") == [["Everyone", "fine"]], "Beds: everyone has a bedroom")
	_expect(_row_text("storage") == "105 of 242 cells used" and _goal("storage") == "380 items stored" and _tags("storage") == [["Room to spare", "fine"]],
		"Storage: cells used, the items stored and room to spare")
	var happiness: Dictionary = panel._rows.happiness
	_expect(_row_text("happiness") == "Happy · 58" and happiness.meter.tone == "fine" and happiness.meter.ticks == [0.25, 0.4, 0.54, 0.64]
		and happiness.note.text == "Main complaint: chilly sleep, 4 dwarves. Warm the sleeping room with a hearth.",
		"Happiness: the step and points, the steps marked, the main complaint and what helps")
	_expect(happiness.art.texture.resource_path == "res://assets/ui/icons/mood_happy.png", "the Happiness row wears the colony's face")
	var badges: Array = panel._badges.get_children().map(func(badge: Node) -> String: return badge.tooltip_text)
	_expect(badges == ["3 Workers", "1 Miner", "1 Carpenter"], "a badge for each profession, in professions.json's order: %s" % [badges])
	_expect(panel._mood_word.text == "Happy" and panel._mood_points.text == "Happiness 58 of 100" and panel._mood_line.text == "Things are going well down here."
		and panel._face.texture.resource_path == "res://assets/ui/icons/mood_happy.png", "the header's mood: face, word, line and points")
	colony.merge({"food_days": 2.5, "beds": 3, "used": 200, "points": 20, "complaint": {}}, true)
	panel.show_colony(colony)
	_expect(_row_text("food") == "Food for 2 days" and _tags("food") == [["Short", "blocked"]], "Food under three days is Short, in rust")
	_expect(_tags("beds") == [["2 without", "waiting"]] and _tags("storage") == [["Filling up", "waiting"]], "Beds and storage below their goals are hay")
	_expect(_row_text("happiness") == "Miserable · 20" and happiness.meter.tone == "blocked" and happiness.note.text.begins_with("No complaints"),
		"Happiness at the bottom is rust, and no complaint says so")
	colony.merge({"food_days": 12.0, "used": 242}, true)
	panel.show_colony(colony)
	_expect(_tags("food") == [["Plenty", "fine"]] and _tags("storage") == [["Full", "blocked"]], "Food from the goal is Plenty; full storage is rust")
	for case: Array in [[0.5, "Food for less than a day"], [1.5, "Food for 1 day"]]:
		colony.food_days = case[0]
		panel.show_colony(colony)
		_expect(_row_text("food") == case[1], "food in words: " + String(case[1]))
	panel.set_process(true)


func _test_entries() -> void:
	var names: Array = panel._entries.get_children().map(func(button: Node) -> String: return button.name)
	_expect(names == ["EntryDwarves", "EntryLabor", "EntryFlag", "EntryTrade"], "Colony's entries, in the concept's order: %s" % [names])
	for button: Button in panel._entries.get_children():
		_expect(not button.text.is_empty() and button.icon != null and button.size.y >= float(panel._size.entry), "an entry shows its picture and word: " + button.name)
	var trade: Button = panel._entries.get_child(3)
	var planned := trade.find_children("*", "PanelContainer", true, false)
	_expect(not planned.is_empty() and planned[0].get_child(0).text == "Planned", "Trade is marked planned")
	if not planned.is_empty():
		var words := UITheme.body_font().get_string_size(trade.text, HORIZONTAL_ALIGNMENT_LEFT, -1, panel._size.line).x
		var words_end: float = trade.global_position.x + 12.0 + float(panel._size.icon) + 10.0 + words
		_expect(trade.get_global_rect().encloses(planned[0].get_global_rect()) and planned[0].global_position.x >= words_end,
			"the Planned tag sits inside Trade, clear of its word")
	trade.pressed.emit()
	await _settle()
	_expect(not manager.is_open("colony") and manager.is_open("trade"), "an entry closes the page and opens its own window")
	manager.close("trade")


func _test_rename() -> void:
	dock._dispatch("toggle_window", "colony")
	await _settle()
	var before: String = flag.settlement_name
	panel._rename.pressed.emit()
	await _settle()
	_expect(panel._edit_row.visible and not panel._name_row.visible and panel._field.text == before, "Rename turns the name into a field")
	panel._field.text = "No"
	panel._field.text_changed.emit("No")
	_expect(panel._done.disabled and panel._founded.text == SettlementName.RULE, "a name outside the rules keeps Done off and says why")
	panel._edit_row.get_child(1).pressed.emit()
	_expect(SettlementName.is_valid(panel._field.text) and panel._field.text != before and not panel._done.disabled, "Suggest another fills in a name: " + panel._field.text)
	var suggested: String = panel._field.text
	panel._done.pressed.emit()
	await _settle()
	_expect(flag.settlement_name == suggested and panel._name.text == suggested and panel._name_row.visible and not panel._edit_row.visible,
		"Done renames the settlement")
	panel._rename.pressed.emit()
	await _settle()
	panel._field.text = "Kolgund"
	panel._field.grab_focus()
	var escape := InputEventKey.new()
	escape.pressed = true
	escape.keycode = KEY_ESCAPE
	root.push_input(escape, true)
	await _settle()
	_expect(flag.settlement_name == suggested and not panel._edit_row.visible and manager.is_open("colony"), "Esc leaves the name as it was and the page open")


## The journal beside the rows: the days newest first, complaints then praises, the most
## shared first, each line with its speaker's face, name, thought, count and words.
func _test_journal() -> void:
	var journal: Node = root.get_node("ColonyJournal")
	var today := floori(root.get_node("WorldClock").elapsed_days())
	journal.clear_runtime_state()
	panel.refresh()
	await _settle()
	_expect(_journal_words().has(panel.JOURNAL_EMPTY), "an empty journal says what will land in it")
	var a: Node = dwarves[0]
	var b: Node = dwarves[1]
	var c: Node = dwarves[2]
	journal.restore_state({"lines": [
		_line(today - 1, "bedroom", "Slept in my own bedroom", "praise", [a.dwarf_id], a, "A door that shuts and a bed of my own. Bliss."),
		_line(today, "bedroom", "Slept in my own bedroom", "praise", [b.dwarf_id], b, "Slept like a stone. My own stone, in my own room."),
		_line(today, "chilly", "Chilly sleep", "complaint", [a.dwarf_id, b.dwarf_id, 999], null, "Woke with frost in my beard. A hearth would not go amiss."),
		_line(today, "dining_neither", "Ate without a proper place", "complaint", [c.dwarf_id], c, "Ate in the dirt like a mole."),
	]})
	panel.refresh()
	await _settle()
	var days: Array = panel._journal_list.get_children().filter(func(node: Node) -> bool: return node is VBoxContainer)
	_expect(days.size() == 2 and days[0].get_child(0).text == "Today · Autumn, day 3" and days[1].get_child(0).text == "Yesterday · Autumn, day 2",
		"the journal's days, newest first")
	var order: Array = days[0].get_children().map(func(node: Node) -> String: return node.text if node is Label else "line")
	_expect(order == ["Today · Autumn, day 3", "Complaints", "line", "line", "Praises", "line"], "complaints, then praises: %s" % [order])
	var chilly: Control = days[0].get_child(2)
	var words: Array = chilly.find_children("*", "Label", true, false).map(func(label: Label) -> String: return label.text)
	_expect(words == ["Hilde", "· Chilly sleep", "3 dwarves", "“Woke with frost in my beard. A hearth would not go amiss.”"],
		"a line: the speaker, the thought, how many share it and the words, the most shared first: %s" % [words])
	var shared: Control = chilly.find_children("*", "PanelContainer", true, false).back()
	_expect(shared.tooltip_text == "%s, %s" % [a.dwarf_name, b.dwarf_name], "the dwarves sharing it on hover, those still here")
	_expect(_face(chilly).resource_path == panel.NO_FACE, "a speaker no longer here shows the dwarves' picture")
	var bedroom: Control = days[0].get_child(5)
	_expect(_face(bedroom) is AtlasTexture and _face(bedroom).atlas is ViewportTexture, "a speaker still here shows their head and shoulders")
	var glance: Rect2 = panel._glance.get_global_rect()
	var column: Rect2 = panel._journal.get_global_rect()
	_expect(panel._wide and column.position.x >= glance.end.x and absf(column.end.y - glance.end.y) <= 2.0,
		"the journal stands beside the rows, as tall as they are: %s beside %s" % [column, glance])
	var many: Array = []
	for back in range(10):
		for topic: Array in [["bedroom", "praise"], ["chilly", "complaint"], ["hungry", "complaint"]]:
			many.append(_line(today - 9 + back, topic[0], String(topic[0]).capitalize(), topic[1], [a.dwarf_id], a, "Words for day %d." % back))
	journal.restore_state({"lines": many})
	panel.refresh()
	await _settle()
	_expect(panel._journal_scroll.get_v_scroll_bar().visible and panel._scroll.size.y >= panel._glance.get_combined_minimum_size().y - 1.0,
		"a long journal scrolls by itself, and the rows stay whole")


func _line(day: int, topic: String, text: String, tone: String, shared: Array, speaker: Node, words: String) -> Dictionary:
	return {"day": day, "topic": topic, "text": text, "tone": tone, "dwarves": shared, "words": words,
		"speaker": speaker.dwarf_id if speaker != null else int(shared.back()), "name": speaker.dwarf_name if speaker != null else "Hilde"}


func _journal_words() -> Array:
	return panel._journal_list.find_children("*", "Label", true, false).map(func(label: Label) -> String: return label.text)


## A journal line's picture.
func _face(line: Control) -> Texture2D:
	return (line.get_child(0).get_child(0) as TextureRect).texture


func _test_sizes() -> void:
	for size: Vector2i in [Vector2i(960, 540), Vector2i(1280, 720), Vector2i(2560, 1440)]:
		root.size = size
		await _settle()
		await _settle()
		var key := "small" if size.y < 650 else ("large" if size.y >= 1300 else ("medium" if size.y >= 900 else "short"))
		var rect: Rect2 = manager.get_ui_window("colony").get_global_rect()
		_expect(panel._size == panel.SIZES[key], "%s screens take the %s size" % [size, key])
		_expect(Rect2(Vector2.ZERO, Vector2(size)).encloses(rect) and rect.end.y <= dock.dock_top(), "the page fits above the dock at %s: %s" % [size, rect])
		_expect(not rect.intersects(dock._sky_dial.get_global_rect()), "the page keeps clear of the Sky Dial at %s" % size)
		var header: Control = panel._header
		_expect(rect.encloses(header.get_global_rect()) and rect.encloses(panel._entries.get_global_rect()), "the header and entries fit at %s" % size)
		var trade: Button = panel._entries.get_child(3)
		var tag: Control = trade.get_child(0)
		var words_end: float = trade.global_position.x + 12.0 + float(panel._size.icon) + 10.0 \
			+ UITheme.body_font().get_string_size(trade.text, HORIZONTAL_ALIGNMENT_LEFT, -1, panel._size.line).x
		_expect(trade.get_global_rect().encloses(tag.get_global_rect()) and tag.global_position.x >= words_end - 1.0,
			"the Planned tag stays inside Trade and clear of its word at %s" % size)
		var list_height: float = panel._glance.get_combined_minimum_size().y
		_expect(panel._scroll.size.y >= list_height - 1.0 or (key == "small" and panel._scroll.get_v_scroll_bar().visible),
			"all five rows show above the dock, and only small screens scroll them: %s at %s" % [panel._scroll.size.y, size])
		var glance: Rect2 = panel._glance.get_global_rect()
		var journal: Rect2 = panel._journal.get_global_rect()
		if key == "small":
			_expect(not panel._wide and journal.position.y >= glance.end.y - 1.0, "small screens set the journal under the rows")
		else:
			_expect(panel._wide and journal.position.x >= glance.end.x and rect.encloses(journal), "the journal stands beside the rows at %s" % size)
		if "--capture" in OS.get_cmdline_user_args():
			await RenderingServer.frame_post_draw
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tmp/settlement_panel_20261025/"))
			root.get_texture().get_image().save_png("res://tmp/settlement_panel_20261025/page_%d.png" % size.x)


# ── Helpers ────────────────────────────────────────────────────────────────────

func _dwarf(id: int) -> Node:
	var factory = load("res://scripts/entities/DwarfFactory.gd").new()
	var agent = factory.spawn(factory.generate(id, {}), id)
	scene.add_child(agent)
	agent.set_process(false)
	agent.set_physics_process(false)
	agent.position = Vector3(38.5 + id % 4, 21, 38.5)
	tasks.register_dwarf(agent)
	return agent


func _row_text(id: String) -> String:
	return panel._rows[id].value.text


func _goal(id: String) -> String:
	return panel._rows[id].goal.text


## The row's shown tags as [words, tone].
func _tags(id: String) -> Array:
	var shown: Array = []
	for tag: Node in panel._rows[id].line.find_children("*", "PanelContainer", true, false):
		if not tag.visible: continue
		for tone: String in ["fine", "waiting", "blocked"]:
			if tag.get_theme_stylebox("panel") == UITheme.cell_style("tag_" + tone, 2): shown.append([tag.get_child(0).text, tone])
	return shown


func _click(position: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = position
		root.push_input(event, true)


func _settle() -> void:
	for frame in range(6): await process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
