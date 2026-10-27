extends SceneTree

## The Events window and the dock's bell (doc 23): the warnings still unresolved on
## their cards, the days newest first with New and Resolved tags, Locate (a place, and a
## warning's dwarves one by one), opening Events marking the log seen, the bell's count in
## its tones, and the fit at 960×540, 1280×720 and 2560×1440. The log itself is EventLogTest's.
const FOOD_DETAIL := "Harvest berries or make stored food accessible."
const ICONS := "res://assets/ui/icons/"
var failures: Array[String] = []
var events: Node
var clock: Node
var tasks: Node
var scene: Node3D
var manager: Node
var dock: Node
var rig: Node
var panel: Node
var bell: Button
var guntris: Node3D
var ildgra: Node3D
var ids := {}


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	create_timer(120).timeout.connect(func(): push_error("EventsPanelTest timed out"); quit(1))
	await process_frame
	events = root.get_node("EventLog")
	clock = root.get_node("WorldClock")
	tasks = root.get_node("TaskManager")
	root.get_node("SaveManager").set_process(false)
	tasks.set_process(false)
	# The food check would resolve the test's own food warnings.
	events.set_process(false)
	events.clear_runtime_state()
	root.size = Vector2i(2560, 1440)
	await _build()
	_test_dates()
	await _test_window()
	await _test_locate()
	await _test_while_open()
	await _test_bell()
	await _test_sizes()
	_clean_up()
	for failure in failures: push_error(failure)
	print("EVENTS_PANEL_OK" if failures.is_empty() else "EVENTS_PANEL_FAIL")
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
	rig = load("res://scripts/systems/Camera.gd").new()
	scene.add_child(rig)
	rig.set_process(false)
	guntris = _dwarf(901, "Guntris", Vector3(10.5, 21.0, 10.5))
	ildgra = _dwarf(902, "Ildgra", Vector3(20.5, 21.0, 30.5))
	await _settle()
	panel = dock._events_panel
	bell = dock._button_by_target.get("events")


## A dwarf for Locate to find. Registered before it joins the tree, so it is never handed
## work, and with its own processing off.
func _dwarf(id: int, dwarf_name: String, at: Vector3) -> Node3D:
	var dwarf: Node3D = load("res://scripts/entities/DwarfAgent.gd").new()
	dwarf.dwarf_id = id
	dwarf.dwarf_name = dwarf_name
	tasks.register_dwarf(dwarf)
	scene.add_child(dwarf)
	dwarf.set_process(false)
	dwarf.set_physics_process(false)
	dwarf.global_position = at
	return dwarf


func _test_dates() -> void:
	_at(7, 20, 30)
	var date: Dictionary = clock.date_at(clock.elapsed_days())
	_expect(date.year == 1 and date.season == "autumn" and date.day == 7 and is_equal_approx(date.hour, 20.5), "date_at reads the calendar back: %s" % date)
	_expect(clock.time_string_at(clock.elapsed_days()) == "20:30" and clock.time_string() == "20:30", "a whole minute survives the trip through elapsed days")
	var later := 112.0 + 27.25
	var next: Dictionary = clock.date_at(later)
	_expect(next.year == 2 and next.season == "spring" and next.day == 28 and clock.time_string_at(later) == "06:00", "date_at rolls into the next year: %s" % next)
	_expect(clock.time_string_at(62.0 + 23.999999 / 24.0) == "23:59", "the day's last minute stays on its day")


## The approved concept's log: three days of news, a warning resolved yesterday, and two
## standing today. Everything up to yesterday has been seen.
func _fill() -> void:
	events.clear_runtime_state()
	_at(5, 22, 35)
	ids.carpenter = events.post("colony", "Ildgra is now a Carpenter.", {"picture": ICONS + "carpenter.png", "dwarves": [902]})
	_at(6, 0, 35)
	ids.rabbit = events.post("arrival", "A rabbit has arrived from the south.", {"picture": ICONS + "rabbit.png", "place": Vector3i(40, 21, 12)})
	_at(6, 21, 35)
	ids.hungry = events.raise("food", "3 dwarves cannot find reachable food.", {"detail": FOOD_DETAIL, "dwarves": [901, 902],
		"past": "3 dwarves could not find reachable food."})
	_at(6, 22, 35)
	events.resolve("food")
	events.mark_seen()
	_at(7, 15, 23)
	ids.miner = events.post("colony", "Guntris is now a Miner.", {"picture": ICONS + "miner.png", "dwarves": [901]})
	_at(7, 17, 59)
	ids.cavern = events.post("discovery", "Cavern discovered. Bring light to explore it.", {"place": Vector3i(30, 12, 30)})
	_at(7, 19, 23)
	ids.food = events.raise("food", "2 dwarves cannot find reachable food.", {"detail": FOOD_DETAIL, "dwarves": [901, 902],
		"past": "2 dwarves could not find reachable food."})
	_at(7, 20, 17)
	ids.flood = events.raise("flood", "Rising water is spilling onto dry ground.", {"place": Vector3i(50, 20, 44), "hold_hours": 3.0,
		"past": "Rising water spilled onto dry ground."})
	_at(7, 20, 26)
	ids.deer = events.post("arrival", "3 deer have arrived from the east.", {"picture": ICONS + "deer.png", "place": Vector3i(80, 21, 40)})
	_at(7, 20, 30)


func _test_window() -> void:
	_fill()
	_expect(bell != null and bell.get_index() == dock._button_by_target.stocks.get_index() + 1 and bell.caption == "Events"
		and bell.icon.resource_path.ends_with("/events.png"), "the bell follows Inventory on the dock")
	_expect(bell.count_text == "5" and bell.count_tone == "blocked", "the bell counts five new entries, rust for the standing warnings")
	_click(bell.get_global_rect().get_center())
	await _settle()
	var window: Control = manager.get_ui_window("events")
	_expect(manager.is_open("events") and bell.button_pressed, "the bell opens Events and stays lit")
	_expect(window.get_global_rect().position.distance_to(Vector2(24, 76)) < 1.0, "Events opens where windows open: %s" % window.get_global_rect())
	_expect(events.unseen() == 0 and bell.count_text == "!" and bell.count_tone == "blocked",
		"opening Events reads the log; the standing warnings keep the bell rust with !")
	_expect(_headings() == ["Needs attention", "Today · Autumn, day 7", "Yesterday · Autumn, day 6", "Autumn, day 5"],
		"the warnings, then the days newest first: %s" % [_headings()])
	var food := _view(ids.food)
	var flood := _view(ids.flood)
	_expect(food is PanelContainer and flood is PanelContainer and flood.get_index() < food.get_index()
		and food.get_theme_stylebox("panel") == UITheme.warning_frame(), "standing warnings sit on rust-banded cards, newest first")
	_expect(_words(food) == ["2 dwarves cannot find reachable food.", FOOD_DETAIL, "Since 19:23"] and _locate(food) != null,
		"a warning card says what is wrong, what to do and since when: %s" % [_words(food)])
	_expect(_words(flood) == ["Rising water is spilling onto dry ground.", "Since 20:17"] and _locate(flood) != null, "a warning without a second line")
	_expect(_words(_view(ids.deer)) == ["3 deer have arrived from the east.", "20:26", "New"] and _locate(_view(ids.deer)) != null,
		"an arrival: its words, its time, New, and Locate: %s" % [_words(_view(ids.deer))])
	_expect(_words(_view(ids.cavern)) == ["Cavern discovered. Bring light to explore it.", "17:59", "New"], "a cavern found today is New")
	_expect(_words(_view(ids.miner)) == ["Guntris is now a Miner.", "15:23", "New"] and _locate(_view(ids.miner)).tooltip_text.ends_with("Guntris"),
		"a promotion locates its dwarf")
	_expect(_view(ids.deer).get_index() < _view(ids.cavern).get_index() and _view(ids.cavern).get_index() < _view(ids.miner).get_index(),
		"a day's entries come newest first")
	var hungry := _view(ids.hungry)
	_expect(_words(hungry) == ["3 dwarves could not find reachable food.", "21:35", "Resolved at 22:35"] and _locate(hungry) == null
		and _labels(hungry)[0].get_theme_color("font_color") == panel.MUTED,
		"a resolved warning stays in its day, greyed, in past words, without Locate: %s" % [_words(hungry)])
	_expect(_words(_view(ids.rabbit)) == ["A rabbit has arrived from the south.", "00:35"], "an entry seen before has no New tag")
	_expect(_words(_view(ids.carpenter)) == ["Ildgra is now a Carpenter.", "22:35"] and _locate(_view(ids.carpenter)) != null, "two days back")
	_expect(_picture(_view(ids.deer)).ends_with("/deer.png") and _picture(_view(ids.cavern)).ends_with("/cavern.png")
		and _picture(food).ends_with("/warning.png") and _picture(_view(ids.miner)).ends_with("/miner.png"), "each entry shows its picture")
	_expect(_tag_style(_view(ids.deer)) == UITheme.cell_style("tag_waiting", 2) and _tag_style(hungry) == UITheme.cell_style("tag_fine", 2),
		"New is a hay tag, Resolved a moss one")


func _test_locate() -> void:
	_click(_locate(_view(ids.deer)).get_global_rect().get_center())
	await _settle()
	_expect(rig._target_pos.is_equal_approx(Vector3(80.5, 22.5, 40.5)), "Locate goes where the deer came in: %s" % rig._target_pos)
	_expect(manager.is_open("events"), "Events stays open while Locate moves the view")
	var visits: Array = []
	for turn in range(3):
		_click(_locate(_view(ids.food)).get_global_rect().get_center())
		await _settle()
		visits.append(rig._target_pos)
	var lift := Vector3(0, 1.5, 0)
	_expect(visits[0].is_equal_approx(guntris.global_position + lift) and visits[1].is_equal_approx(ildgra.global_position + lift)
		and visits[2].is_equal_approx(visits[0]), "the food warning's Locate visits its dwarves one by one: %s" % [visits])
	_click(_locate(_view(ids.carpenter)).get_global_rect().get_center())
	await _settle()
	_expect(rig._target_pos.is_equal_approx(ildgra.global_position + lift), "a promotion's Locate finds the dwarf where they are now")


func _test_while_open() -> void:
	var winter: int = events.post("colony", "Winter has come.")
	await _settle()
	_expect(_words(_view(winter)) == ["Winter has come.", "20:30", "New"] and _locate(_view(winter)) == null,
		"news landing while Events is open shows at once, New, without Locate when it has no place")
	_expect(events.unseen() == 0 and bell.count_text == "!", "what lands while Events is open counts as seen")
	events.resolve("flood")
	await _settle()
	var flood := _view(ids.flood)
	_expect(flood is HBoxContainer and _words(flood) == ["Rising water spilled onto dry ground.", "20:17", "Resolved at 20:30"],
		"a warning resolved while Events is open takes its place in its day: %s" % [_words(flood)])
	manager.close("events")
	await _settle()
	_expect(not bell.button_pressed, "the bell goes dark with the window")
	_click(bell.get_global_rect().get_center())
	await _settle()
	_expect(_words(_view(ids.deer)) == ["3 deer have arrived from the east.", "20:26"], "reopening drops the New tags of what was seen")
	events.resolve("food")
	await _settle()
	_expect(_headings()[0] == "Today · Autumn, day 7" and bell.count_text == "", "with every warning resolved, Needs attention goes and the bell is plain")


func _test_bell() -> void:
	events.clear_runtime_state()
	await _settle()
	_expect(_words(panel._list) == [panel.EMPTY], "an empty log says what will land")
	manager.close("events")
	await _settle()
	_expect(bell.count_text == "", "an empty log leaves the bell plain")
	for index in range(3): events.post("colony", "News %d." % index)
	_expect(bell.count_text == "3" and bell.count_tone == "waiting", "new entries count in hay")
	events.raise("test", "Something needs attention.")
	_expect(bell.count_text == "4" and bell.count_tone == "blocked", "a standing warning turns the count rust")
	events.mark_seen()
	_expect(bell.count_text == "!" and bell.count_tone == "blocked", "a standing warning shows ! once everything is read")
	events.resolve("test")
	_expect(bell.count_text == "", "nothing new and nothing standing: no count")
	for index in range(120): events.post("colony", "More news %d." % index)
	_expect(bell.count_text == "99+", "a long count is capped")
	var chip: Rect2 = bell.count_rect()
	_expect(chip.position.y < 0.0 and chip.end.x > bell.size.x and is_equal_approx(chip.size.y, roundf(bell.size.x * 0.42)),
		"the count overhangs the tile's top right corner: %s on %s" % [chip, bell.size])


func _test_sizes() -> void:
	_fill()
	for index in range(30):
		events.post("arrival", "%d rabbits have arrived from the west." % (index + 2), {"picture": ICONS + "rabbit.png", "place": Vector3i(index, 21, 5)})
	if not manager.is_open("events"): manager.open("events")
	for size: Vector2i in [Vector2i(960, 540), Vector2i(1280, 720), Vector2i(2560, 1440)]:
		root.size = size
		await _settle()
		var key := "small" if size.y < 650 else ("large" if size.y >= 1300 else "medium")
		var rect: Rect2 = manager.get_ui_window("events").get_global_rect()
		_expect(panel._size == panel.SIZES[key], "%s screens take the %s size" % [size, key])
		_expect(Rect2(Vector2.ZERO, Vector2(size)).encloses(rect) and rect.end.y <= dock.dock_top(), "Events fits above the dock at %s: %s" % [size, rect])
		_expect(absf(rect.size.x - float(panel.SIZES[key].width)) < 2.0, "Events is %d px wide at %s: %s" % [panel.SIZES[key].width, size, rect])
		_expect(panel._scroll.get_v_scroll_bar().visible, "a long log scrolls at %s" % size)
		var locate := _locate(_view(ids.food))
		_expect(locate != null and locate.text.is_empty() == (key == "small"), "Locate is its pin alone on small screens: %s" % size)
		_expect(not rect.intersects(dock._sky_dial.get_global_rect()), "Events keeps clear of the Sky Dial at %s" % size)


func _clean_up() -> void:
	for dwarf: Node3D in [guntris, ildgra]:
		tasks._agents.erase(dwarf.dwarf_id)
		tasks._remove_idle(dwarf.dwarf_id)
	root.remove_child(scene)
	scene.free()
	events.clear_runtime_state()
	events.set_process(true)


# ── Helpers ────────────────────────────────────────────────────────────────────

## Sets the colony's clock to autumn `day` at hours:minutes; the log stamps what lands then.
func _at(day: int, hours: int, minutes: int) -> void:
	clock.restore_state({"year": 1, "season": "autumn", "day": day, "hour": hours + minutes / 60.0, "speed": 1.0, "paused": true})


## The card or row showing the entry `id`, or null.
func _view(id: int) -> Control:
	for node: Node in panel._list.find_children("*", "Container", true, false):
		if int(node.get_meta("event_id", 0)) == id: return node
	return null


func _headings() -> Array:
	var titles: Array = []
	for section: Node in panel._list.get_children():
		if section is VBoxContainer: titles.append(section.get_child(0).text)
	return titles


func _labels(view: Node) -> Array:
	return view.find_children("*", "Label", true, false) if view != null else []


func _words(view: Node) -> Array:
	return _labels(view).map(func(label: Label) -> String: return label.text)


func _locate(view: Node) -> Button:
	if view == null: return null
	var buttons: Array = view.find_children("*", "Button", true, false)
	return buttons[0] if not buttons.is_empty() else null


func _picture(view: Node) -> String:
	var art: Array = view.find_children("*", "TextureRect", true, false) if view != null else []
	return art[0].texture.resource_path if not art.is_empty() else ""


func _tag_style(view: Node) -> StyleBox:
	for tag: Node in view.find_children("*", "PanelContainer", true, false):
		if tag.name.begins_with("Tag"): return tag.get_theme_stylebox("panel")
	return null


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
