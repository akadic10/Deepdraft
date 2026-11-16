extends SceneTree

## The colony's event log (doc 23): entries and their pictures, kept as a line code and
## fields and worded when read (one and several, a warning's past words), warnings raised,
## updated and resolved (rising water by its hold), the unseen count, pruning, the save section,
## the sources that need no world (caverns, rising water, the seasons, a finished
## arrival through WorldEventDirector), and the Hearthblock toasts. Promotions are
## checked in EquipmentFeedbackTest, the food warning in DwarfDiningTest and the full
## save pipeline in SaveManagerRoundTripTest.
const FOOD_DETAIL := "Harvest berries or make stored food accessible."
var failures: Array[String] = []
var events: Node
var clock: Node


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	create_timer(60).timeout.connect(func(): push_error("EventLogTest timed out"); quit(1))
	await process_frame
	events = root.get_node("EventLog")
	clock = root.get_node("WorldClock")
	clock.restore_state({"year": 1, "season": "autumn", "day": 7, "hour": 14.0, "speed": 1.0, "paused": true})
	events.clear_runtime_state()
	_test_entries()
	_test_warnings()
	_test_sources()
	_test_pruning()
	_test_saving()
	await _test_toasts()
	events.clear_runtime_state()
	for failure in failures: push_error(failure)
	print("EVENT_LOG_OK" if failures.is_empty() else "EVENT_LOG_FAIL")
	quit(0 if failures.is_empty() else 1)


func _test_entries() -> void:
	var added: Array = []
	var record := func(entry: Dictionary): added.append(entry)
	events.entry_added.connect(record)
	var first: int = events.post("discovery", "cavern_found", {}, {"place": Vector3i(10, 20, 30)})
	var second: int = events.post("colony", "season_came", {"season": "autumn"})
	var third: int = events.post("arrival", "arrived", {"count": 3, "event": "deer_arrival", "edge": "east"},
		{"picture": "res://assets/ui/icons/deer.png", "dwarves": [4]})
	_expect(first == 1 and second == 2 and third == 3, "entries are numbered in order")
	var listed: Array = events.entries()
	_expect(listed.size() == 3 and listed[0].id == 3 and listed[2].id == 1, "entries come newest first")
	_expect(listed[2].line == "cavern_found" and listed[1].line == "season_came" and listed[1].fields == {"season": "autumn"}
		and listed[1].text == "Autumn has come.", "an entry is kept as its line and fields, and read in words: %s" % [listed[1]])
	_expect(listed[2].picture == "res://assets/ui/icons/cavern.png" and listed[2].place == [10, 20, 30],
		"a discovery takes its kind's picture and keeps its place")
	_expect(listed[1].picture == "res://assets/ui/icons/colony.png" and listed[1].detail == "" and not listed[1].has("place"),
		"colony news takes the Colony head")
	_expect(String(listed[0].picture).ends_with("/deer.png") and listed[0].dwarves == [4], "an entry's own picture and dwarves win")
	_expect(is_equal_approx(float(listed[0].time), clock.elapsed_days()), "an entry carries the colony's time")
	_expect(added.size() == 3 and String(added[0].text).begins_with("Cavern"), "every entry is announced once")
	listed[0].text = "changed"
	_expect(events.entries()[0].text != "changed", "entries() hands out copies")
	_expect(events.unseen() == 3 and events.last_seen() == 0, "three entries are unseen")
	events.mark_seen()
	_expect(events.unseen() == 0 and events.last_seen() == 3, "mark_seen clears the unseen count")
	events.post("colony", "promoted", {"name": "Ildgra", "profession": "base:profession:carpenter"})
	_expect(events.unseen() == 1 and events.entries()[0].text == "Ildgra is now a Carpenter.",
		"a new entry is unseen again, and a profession's id reads as its name: %s" % events.entries()[0].text)
	# Nothing lands while a save loads: the load restores the saved log instead.
	var saves := root.get_node("SaveManager")
	saves._loading = true
	_expect(events.post("colony", "season_came", {"season": "winter"}) == 0 and events.raise("ignored", "flood") == 0 and events.entries().size() == 4,
		"posting and raising wait while a save loads")
	saves._loading = false
	events.entry_added.disconnect(record)


func _test_warnings() -> void:
	events.clear_runtime_state()
	var added := [0]
	var changes := [0]
	var count_added := func(_entry: Dictionary): added[0] += 1
	var count_changed := func(): changes[0] += 1
	events.entry_added.connect(count_added)
	events.changed.connect(count_changed)
	var id: int = events.raise("food", "food_short", {"count": 1}, {"dwarves": [2]})
	_expect(added[0] == 1 and events.warning("food").id == id and events.warning("food").kind == "warning",
		"raising a warning adds one entry")
	_expect(String(events.warning("food").picture).ends_with("/warning.png"), "a warning takes the warning sign")
	changes[0] = 0
	_expect(events.warning("food").text == "1 dwarf cannot find reachable food." and events.warning("food").detail == FOOD_DETAIL,
		"one dwarf takes the words for one, with the line's second line: %s" % events.warning("food").text)
	events.raise("food", "food_short", {"count": 1}, {"dwarves": [2]})
	_expect(added[0] == 1 and changes[0] == 0, "raising it again unchanged is quiet")
	events.raise("food", "food_short", {"count": 2}, {"dwarves": [2, 5]})
	_expect(added[0] == 1 and changes[0] == 1 and events.warning("food").id == id and events.warning("food").dwarves == [2, 5]
		and events.warning("food").fields == {"count": 2} and events.warning("food").text == "2 dwarves cannot find reachable food.",
		"a changed warning updates in place, without a new toast, and two dwarves take the words for several")
	events.resolve("food")
	_expect(events.warning("food").is_empty() and events.entries()[0].has("resolved"), "a resolved warning stays as an entry")
	_expect(events.raise("food", "food_short", {"count": 1}) != id and added[0] == 2, "a new shortage is a new warning")
	events.resolve("food")
	# Pinned warnings, newest first, and their line's past words once resolved.
	var first: int = events.raise("first", "flood")
	var second: int = events.raise("second", "cavern_found")   # a line with no past words
	_expect(events.pinned().map(func(entry: Dictionary) -> int: return entry.id) == [second, first], "pinned() lists the standing warnings, newest first")
	events.raise("first", "food_short", {"count": 3})   # its line and fields change while it stands
	events.resolve("first")
	var settled: Dictionary = events.entries().filter(func(entry: Dictionary) -> bool: return entry.id == first)[0]
	_expect(settled.line == "food_short" and settled.text == "3 dwarves could not find reachable food." and events.pinned().size() == 1,
		"a resolved warning reads in its line's past words: %s" % settled.text)
	events.resolve("second")
	_expect(events.entries()[0].text == "Cavern discovered. Bring light to explore it.", "a line without past words keeps its words")
	events.check_food()
	_expect(events.warning("food").is_empty(), "with no hungry dwarves the food check raises nothing")
	# A held warning resolves itself once it has not been raised again for its hold.
	events.raise("flood", "flood", {}, {"place": Vector3i(5, 20, 7), "hold_hours": 3.0})
	clock.advance_hours(2.0)
	events._expire_held()
	_expect(not events.warning("flood").is_empty(), "rising water stays pinned within its hold")
	events.raise("flood", "flood", {}, {"place": Vector3i(6, 20, 7), "hold_hours": 3.0})
	clock.advance_hours(2.5)
	events._expire_held()
	_expect(not events.warning("flood").is_empty() and events.warning("flood").place == [6, 20, 7],
		"raising it again renews the hold and moves its place")
	clock.advance_hours(1.0)
	events._expire_held()
	_expect(events.warning("flood").is_empty(), "rising water resolves itself after its hold")
	events.entry_added.disconnect(count_added)
	events.changed.disconnect(count_changed)


func _test_sources() -> void:
	events.clear_runtime_state()
	# Caverns the colony mines into: Locate goes to the found cell nearest their middle.
	var cells: Array[Vector3i] = [Vector3i(10, 20, 10), Vector3i(12, 20, 10), Vector3i(14, 20, 10), Vector3i(30, 20, 10)]
	root.get_node("InteriorTracker").cavern_found.emit(cells)
	var cavern: Dictionary = events.entries()[0]
	_expect(cavern.kind == "discovery" and cavern.line == "cavern_found" and cavern.place == [14, 20, 10],
		"a cavern found by mining lands in Events")
	# Rising water raises its held warning where it spills.
	root.get_node("WaterManager").flood_warning.emit(Vector3i(8, 22, 9))
	_expect(events.warning("flood").get("place", []) == [8, 22, 9] and events.warning("flood").has("hold")
		and events.warning("flood").text == "Rising water is spilling onto dry ground.", "rising water raises a held warning")
	events.resolve("flood")
	_expect(events.entries()[0].text == "Rising water spilled onto dry ground.", "settled water is told in the past")
	# A new season is colony news; the clock being restored is not.
	clock.advance_season()
	_expect(events.entries()[0].line == "season_came" and events.entries()[0].fields == {"season": "winter"}
		and events.entries()[0].text == "Winter has come." and events.entries()[0].kind == "colony", "a new season is colony news")
	var before: int = events.entries().size()
	clock.restore_state({"year": 1, "season": "autumn", "day": 7, "hour": 20.0, "speed": 1.0, "paused": true})
	_expect(events.entries().size() == before, "restoring the clock is not news")
	# A finished arrival, with the species' picture; Locate goes inland where it heads.
	var director: Node = load("res://scripts/systems/WorldEventDirector.gd").new()
	root.add_child(director)
	director.set_process(false)
	var deer: Dictionary = {}
	for event: Dictionary in director.config.events:
		if event.id == "deer_arrival": deer = event
	director._finish(deer, {"active": {"id": "deer_arrival:test", "issued": 3, "edge": "east", "route": [[100, 20, 5], [80, 21, 40]]}}, "arrived")
	var arrival: Dictionary = events.entries()[0]
	_expect(arrival.kind == "arrival" and arrival.line == "arrived" and arrival.fields == {"count": 3, "event": "deer_arrival", "edge": "east"}
		and arrival.text == "3 deer have arrived from the east."
		and arrival.picture == "res://assets/ui/icons/deer.png" and arrival.place == [80, 21, 40],
		"a finished arrival lands in Events with the species' picture: %s" % [arrival])
	events.post("arrival", "arrived", {"count": 1, "event": "wolf_arrival", "edge": "north"})
	_expect(events.entries()[0].text == "A wolf has arrived from the north.", "one animal takes the words for one: %s" % events.entries()[0].text)
	arrival = events.entries()[0]
	director._finish(deer, {"active": {"id": "deer_arrival:none", "issued": 0, "edge": "", "route": []}}, "expired")
	_expect(events.entries()[0].id == arrival.id, "a group that never arrived is not news")
	root.remove_child(director)
	director.free()


func _test_pruning() -> void:
	events.clear_runtime_state()
	events.post("colony", "season_came", {"season": "spring"})   # the old entry
	events.raise("old_warning", "flood")
	clock.advance_hours(24.0 * 11.0)
	events.post("colony", "season_came", {"season": "winter"})
	var kept: Array = events.entries().map(func(entry: Dictionary) -> String: return "%s %s" % [entry.line, entry.fields.get("season", "")])
	_expect(kept == ["season_came winter", "flood "], "entries older than keep_days go; warnings still standing stay: %s" % [kept])
	events.clear_runtime_state()
	for index in range(events.MAX_ENTRIES + 5): events.post("colony", "promoted", {"name": "Dwarf %d" % index, "profession": "base:profession:miner"})
	_expect(events.entries().size() == events.MAX_ENTRIES and events.entries()[-1].fields.name == "Dwarf 5",
		"the log keeps at most MAX_ENTRIES, dropping the oldest")


func _test_saving() -> void:
	events.clear_runtime_state()
	events.post("discovery", "cavern_found", {}, {"place": Vector3i(3, 20, 4)})
	events.raise("flood", "flood", {}, {"place": Vector3i(5, 20, 6), "hold_hours": 3.0})
	events.raise("food", "food_short", {"count": 1}, {"dwarves": [7]})
	events.resolve("food")
	events.mark_seen()
	events.post("warning", "food_rotted", {"count": 2, "item": "base:item:carrot", "where": "stockpile:3"})
	var read_before: Array = events.entries().map(func(entry: Dictionary) -> Array: return [entry.text, entry.detail])
	var saved: Dictionary = events.serialize_state()
	var coded: bool = saved.entries.all(func(entry: Dictionary) -> bool: return entry.has("line") and entry.has("fields") and not (entry.has("text") or entry.has("detail") or entry.has("past")))
	_expect(coded and saved.entries[-1].line == "food_rotted" and saved.entries[-1].fields == {"count": 2, "item": "base:item:carrot", "where": "stockpile:3"},
		"the log is saved as lines and fields, with no sentence: %s" % [saved.entries[-1]])
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(saved))
	var validator = load("res://scripts/components/SaveSnapshotValidator.gd")
	var catalogs: Dictionary = root.get_node("SaveManager")._capture_catalogs()
	_expect(validator._validate(parsed, validator.SCENE.events, "events", catalogs).is_empty(), "the saved log validates")
	# A line or an item the game does not have cannot be worded again: the save is refused.
	var other_line: Dictionary = parsed.duplicate(true)
	other_line.entries[0].line = "no_such_line"
	var other_item: Dictionary = parsed.duplicate(true)
	other_item.entries[-1].fields.item = "base:item:no_such_food"
	_expect(not validator._validate(other_line, validator.SCENE.events, "events", catalogs).is_empty()
		and not validator._validate(other_item, validator.SCENE.events, "events", catalogs).is_empty(),
		"a saved entry naming a line or an item the game does not have is refused")
	events.clear_runtime_state()
	_expect(events.entries().is_empty() and events.unseen() == 0, "a new world starts with an empty log")
	events.restore_state(parsed)
	_expect(_same(events.serialize_state(), saved), "the log round-trips through JSON")
	_expect(typeof(events.entries()[0].id) == TYPE_INT and typeof(events.warning("flood").place[0]) == TYPE_INT
		and typeof(events.entries()[0].fields.count) == TYPE_INT, "ids, cells and counts come back as whole numbers")
	var read_after: Array = events.entries().map(func(entry: Dictionary) -> Array: return [entry.text, entry.detail])
	_expect(read_after == read_before and read_after[0] == ["2 carrots rotted in Stockpile 3.", ""]
		and read_after[1] == ["1 dwarf could not find reachable food.", FOOD_DETAIL],
		"after a load every entry reads as it did, a resolved warning in the past: %s" % [read_after])
	_expect(events.unseen() == 1 and events.warning("flood").place == [5, 20, 6] and events.warning("food").is_empty(),
		"the unseen count, the pinned warning and the resolved one come back")
	events.resolve("flood")
	_expect(events.entries().filter(func(entry: Dictionary) -> bool: return entry.line == "flood")[0].text == "Rising water spilled onto dry ground.",
		"a warning that stood through a load still reads in the past once resolved")
	_expect(events.post("colony", "season_came", {"season": "spring"}) == int(saved.next_id), "numbering continues after a load")


func _test_toasts() -> void:
	events.clear_runtime_state()
	root.size = Vector2i(2560, 1440)
	# As DockUI hosts it: a full-screen root on the toast layer. Loaded once the
	# autoloads are up, since ToastStack names them.
	var layer := CanvasLayer.new()
	root.add_child(layer)
	var toast_root := Control.new()
	toast_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	toast_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(toast_root)
	var toasts: VBoxContainer = load("res://scripts/ui/ToastStack.gd").new()
	toast_root.add_child(toasts)
	await process_frame
	_expect(toasts.size_key == "large", "toasts take the large size at 1440 px")
	var people: Color = root.get_node("UIRegistry").get_icon_family_color("people")
	events.post("arrival", "arrived", {"count": 3, "event": "deer_arrival", "edge": "east"}, {"picture": "res://assets/ui/icons/deer.png"})
	events.raise("food", "food_short", {"count": 2})
	await process_frame
	_expect(toasts.get_child_count() == 2 and _words(toasts.get_child(0)) == ["2 dwarves cannot find reachable food.", FOOD_DETAIL],
		"events toast, newest on top, a warning with its second line")
	_expect(toasts.get_child(0).get_theme_stylebox("panel") == UITheme.toast_frame(UITheme.TAG_TONES.blocked[0]), "a warning's toast has the rust band")
	_expect(toasts.get_child(1).get_theme_stylebox("panel") == UITheme.toast_frame(people), "an event's toast has the people band")
	_expect(_picture(toasts.get_child(1)) != null and _picture(toasts.get_child(1)).resource_path.ends_with("/deer.png"),
		"an event's toast shows its picture")
	var logged: int = events.entries().size()
	toasts.show_message("Game saved.")
	_expect(events.entries().size() == logged and toasts.get_child(0).get_theme_stylebox("panel") == UITheme.toast_frame(UITheme.TAG_TONES.fine[0])
		and _picture(toasts.get_child(0)) == null, "the player's own message is a moss toast, never logged")
	toasts.show_message("Save failed: the disk is full.", true)
	await process_frame
	_expect(toasts.get_child_count() == events.toast_limit() and _words(toasts.get_child(events.toast_limit() - 1))[0] == "2 dwarves cannot find reachable food.",
		"at most toast_limit toasts; the oldest leaves first")
	_expect(toasts.mouse_filter == Control.MOUSE_FILTER_IGNORE and toasts.get_child(0).mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"the mouse passes through toasts")
	var rect: Rect2 = toasts.get_child(0).get_global_rect()
	_expect(absf(rect.get_center().x - root.size.x * 0.5) < 2.0 and rect.position.y >= 20.0 and rect.position.y < 60.0,
		"toasts sit at the top centre")
	toasts.show_message("Short.", false, 0.2)
	await create_timer(0.6).timeout
	_expect(not _texts(toasts).has("Short."), "a toast goes after its time")
	root.size = Vector2i(960, 540)
	await process_frame
	_expect(toasts.size_key == "small", "small screens take the small toasts")
	layer.queue_free()
	await process_frame


func _words(toast: Node) -> Array:
	return toast.find_children("*", "Label", true, false).map(func(label: Label) -> String: return label.text)


func _picture(toast: Node) -> Texture2D:
	var art: Array = toast.find_children("*", "TextureRect", true, false)
	return art[0].texture if not art.is_empty() else null


func _texts(toasts: Node) -> Array:
	return toasts.get_children().map(func(toast: Node) -> String: return _words(toast)[0])


## The same values, numbers compared to JSON's precision.
func _same(a: Variant, b: Variant) -> bool:
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size(): return false
		for key: Variant in a:
			if not b.has(key) or not _same(a[key], b[key]): return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size(): return false
		for index in range(a.size()):
			if not _same(a[index], b[index]): return false
		return true
	if (a is int or a is float) and (b is int or b is float): return absf(float(a) - float(b)) < 0.0001
	return a == b


func _expect(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
