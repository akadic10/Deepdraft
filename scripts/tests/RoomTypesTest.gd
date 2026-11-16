extends "res://scripts/tests/BedroomTest.gd"

## Room types (doc 34 "Room types"; the room window, doc 23). The owner's report (2026-11-12):
## a cool room holding two food shelves was told "one step from a bedroom: add a bed".
## - A room is typed by what it holds and how warm it is: a food shelf in a cool room makes a
##   pantry, in a frozen one a freezer; a dining table, a seat, a fire and a light make a
##   dining room; a bed's types come first.
## - A type that needs a temperature follows the clock: the pantry is a plain room while it
##   is too warm, and says the one step back.
## - A plain room is measured against a type only when it holds that type's key piece; else
##   the window shows what it could be, and never a bedroom's needs.
## - The window's Types tab lists every type, what it needs and what it is for.
## godot --headless --path . --script res://scripts/tests/RoomTypesTest.gd
const Kinds = preload("res://scripts/components/RoomKinds.gd")
var view   # the room window's content
var updates := {}   # room id -> room_updated signals seen


func _run() -> void:
	create_timer(150).timeout.connect(func(): push_error("Room types timeout"); quit(1))
	await _setup_crafting_fixture()
	rooms = root.get_node("RoomManager")
	rooms.clear_runtime_state()
	rooms.room_updated.connect(func(id: int) -> void: updates[id] = int(updates.get(id, 0)) + 1)
	_pieces()
	_words()
	_build_bedroom()
	_put("door_2", Vector3i(63, 20, 60))
	_clock("spring", 14.0)
	await _plain_room()
	await _pantry_and_freezer()
	await _dining_room()
	await _beds_come_first()
	_reload()
	for failure: String in failures: push_error(failure)
	print("ROOM_TYPES_OK: pieces, words, what a plain room could be, pantry, freezer, the clock, dining room, beds first, the Types tab and reload" if failures.is_empty() else "ROOM_TYPES_FAIL")
	quit(0 if failures.is_empty() else 1)


## What each piece counts as, from its definition.
func _pieces() -> void:
	var defs: Dictionary = furniture.get_defs()
	var counted := {}
	for key: String in ["dining_table", "log_stool", "stone_stool", "bench", "hearth", "campfire", "torch", "food_shelf",
			"raw_materials_crate", "board_game_table", "log_bed"]:
		counted[key] = Kinds.piece_things(defs["base:furniture:" + key])
	_expect(counted.dining_table == ["tables"] and counted.board_game_table.is_empty(), "a dining table is a table; the board-game table is not")
	_expect(counted.log_stool == ["seats"] and counted.stone_stool == ["seats"] and counted.bench == ["seats"], "stools and the bench are seats")
	_expect(counted.hearth == ["fires"] and counted.campfire == ["fires"] and counted.torch.is_empty(), "the hearth and the campfire are fires; a torch is a light only")
	_expect(counted.food_shelf == ["food_stores"] and counted.raw_materials_crate.is_empty() and counted.log_bed.is_empty(),
		"only storage that takes food is a food store")


## The types' words come from their needs.
func _words() -> void:
	var kinds = rooms.kinds
	var said := {}
	for kind: Dictionary in kinds.listed(): said[String(kind.id)] = kinds.needs_sentence(kind)
	_expect(said.keys() == ["bedroom", "barracks", "dining_room", "pantry", "freezer"], "the window lists five types, a personal bedroom under the bedroom: %s" % [said.keys()])
	_expect(said.bedroom == "One bed, a light and a door." and said.barracks == "2 or more beds, a light and a door.", "beds: %s / %s" % [said.bedroom, said.barracks])
	_expect(said.dining_room == "A dining table, a stool or bench, a hearth or campfire, a light and a door.", "dining room: %s" % said.dining_room)
	_expect(said.pantry == "A food shelf and a door, between 0 and 16 °C." and said.freezer == "A food shelf and a door, at 0 °C or below.",
		"pantry and freezer: %s / %s" % [said.pantry, said.freezer])
	_expect(kinds.temperature_met({"above": "frozen_at_c", "below": "comfortable_min_c"}, 15.9) and not kinds.temperature_met({"above": "frozen_at_c", "below": "comfortable_min_c"}, 16.0)
		and not kinds.temperature_met({"above": "frozen_at_c", "below": "comfortable_min_c"}, 0.0) and kinds.temperature_met({"at_most": "frozen_at_c"}, 0.0),
		"a pantry is above freezing and below Comfortable; a freezer is Frozen")
	var complete := true
	for kind: Dictionary in kinds.listed():
		complete = complete and not String(kind.get("gives", "")).is_empty() and kinds.things.has(String(kind.key)) and root.get_node("UIRegistry").get_room_symbol(String(kind.symbol)) != null
	_expect(complete, "each listed type says what it is for, and has a key piece and a picture")


## A sealed room holding no type's key piece: the window shows what it could be, each type
## with its steps, and its warmth as facts.
func _plain_room() -> void:
	var room := _room_data()
	_expect(room.room_type == "room" and rooms.nearest_kind(room).is_empty(), "a door alone makes a plain room, on its way to no type")
	await _open_window()
	_expect(view._kind.text == "Room" and view._needs_heading.text == "WHAT IT COULD BE" and not view._needs_heading.text.contains("BEDROOM"),
		"a plain room is shown what it could be, not a bedroom's needs: %s" % view._needs_heading.text)
	var said := _could_be()
	_expect(said.keys() == ["bedroom", "barracks", "dining_room", "pantry", "freezer"], "each type has its row: %s" % [said.keys()])
	_expect(said.bedroom == "Add a bed and a light" and said.barracks == "Add 2 beds and a light" and said.dining_room == "Add a dining table, a seat, a fire and a light"
		and said.pantry == "Add a food shelf" and said.freezer == "Add a food shelf and get it to 0 °C or below", "each row says the steps to its type: %s" % [said])
	var bedroom_row: Dictionary = view._need_rows["type:bedroom"]
	_expect(not bedroom_row.mark.visible and not bedroom_row.count.visible and bedroom_row.row.tooltip_text.contains("One bed, a light and a door."),
		"a type's row carries no mark, and its tooltip says what the type needs")
	_expect(view._short.visible and view._short.text.contains("The Types tab"), "the line under the rows points at the Types tab")
	_expect(view._comfort_heading.text == "TEMPERATURE" and view._comfort.temperature.row.visible and not view._comfort.temperature.mark.visible
		and view._comfort.temperature.goal.text.is_empty() and view._comfort.heating.count.text == "None" and not view._comfort.heating.mark.visible,
		"a plain room's warmth is given as facts, with no goal to miss")
	_expect(view._comfort.keeping.row.visible and view._comfort.keeping.count.text.begins_with("About ") and view._comfort.keeping.goal.text == "Blueberries · 4 days at 20 °C",
		"and how long food keeps there: %s · %s" % [view._comfort.keeping.count.text, view._comfort.keeping.goal.text])
	_put("torch", Vector3i(68, 20, 64))
	room = _room_data()
	await _refresh()
	_expect(room.room_type == "room" and _could_be().bedroom == "Add a bed" and _could_be().pantry == "Add a food shelf", "a light is one step less for the types that need one: %s" % [_could_be()])
	# The Types tab: every type, what it needs and what it is for, and the steps from here.
	_expect(view._tabs.map(func(tab: Button) -> String: return tab.text) == ["Overview", "Appeal", "Details", "Types"], "the room window has a Types tab")
	view.show_tab_named("types")
	await _frames(3)
	var entries: Dictionary = view._types.entries
	_expect(view._types.visible and not view._overview.visible and entries.keys() == ["bedroom", "barracks", "dining_room", "pantry", "freezer"],
		"the Types tab shows its page alone, a type to an entry: %s" % [entries.keys()])
	_expect(entries.pantry.name == "Pantry" and entries.pantry.needs == "A food shelf and a door, between 0 and 16 °C." and entries.pantry.gives.begins_with("Food keeps longer in the cool.")
		and entries.pantry.steps == "add a food shelf" and not entries.pantry.mine, "an entry names the type, its needs, what it is for and the steps from this room")
	var window_rect: Rect2 = room_window_tool._window_panel.get_global_rect()
	_expect(view._tabs.all(func(tab: Button) -> bool: return window_rect.encloses(tab.get_global_rect())), "four tabs fit the window")
	view.show_tab_named("overview")


## A food shelf makes a cool room a pantry and a frozen one a freezer; too warm, it is a plain
## room one step from a pantry. The type follows the clock.
func _pantry_and_freezer() -> void:
	_put("food_shelf", Vector3i(61, 20, 68))
	var room := _room_data()
	var id: int = rooms.get_room_id_at(room_probe)
	_expect(room.room_type == "pantry" and int(room.things.food_stores) == 1 and float(room.temp_c) > 0.0 and float(room.temp_c) < 16.0,
		"a food shelf in a cool sealed room makes a pantry: %s at %.1f°C" % [room.room_type, float(room.temp_c)])
	await _refresh()
	_expect(view._kind.text == "Pantry" and room_window_tool._window_panel.get_title_label().text == "Pantry %d" % id and view._needs_heading.text == "WHAT MAKES IT A PANTRY",
		"the window names the pantry on its header and band")
	_expect(view._need_rows.keys() == ["food_stores", "doors", "temperature", "walls"] and view._need_rows.food_stores.title.text == "Food storage"
		and view._need_rows.food_stores.count.text == "1" and view._need_rows.temperature.goal.text == "0 to 16 °C"
		and view._need_rows.temperature.count.text == "%.1f °C · %s" % [float(room.temp_c), rooms.temperature_word(float(room.temp_c))]
		and view._need_rows.values().all(func(row: Dictionary) -> bool: return row.glyph.text == "✓") and not view._short.visible,
		"its needs are its food storage, its door and its cool, each ticked: %s" % [view._need_rows.keys()])
	_expect(view._comfort_heading.text == "KEEPING" and not view._comfort.temperature.row.visible and view._comfort.keeping.row.visible
		and view._comfort.heating.row.visible and view._comfort.heating.goal.text == "1 heat source warming it" and not view._comfort.heating.mark.visible,
		"a pantry reads its warmth as keeping: how long food keeps, and the torch that warms it a little")
	_expect(not view._owner_row.visible and view._furniture.get_tile("base:furniture:food_shelf") != null, "no bed, so no sleeper; the shelf shows in the room")
	_expect(view._types.entries.pantry.mine and not view._types.entries.bedroom.mine and view._types.entries.bedroom.steps.is_empty(), "the Types tab tags the pantry as this room")
	# Summer warms the hut past Comfortable: a plain room, one step from a pantry.
	updates.clear()
	_clock("summer", 14.0)
	room = rooms.get_room_at(room_probe)
	_expect(room.room_type == "room" and float(room.temp_c) >= 16.0 and int(updates.get(id, 0)) > 0, "too warm, it is a plain room again, and listeners are told: %.1f°C" % float(room.temp_c))
	_expect(String(rooms.nearest_kind(room).id) == "pantry", "holding a food shelf, it is measured against the pantry, not the freezer or the bedroom")
	await _refresh()
	_expect(view._kind.text == "Room" and view._needs_heading.text == "WHAT MAKES IT A PANTRY" and view._need_rows.temperature.glyph.text == "!"
		and view._need_rows.food_stores.glyph.text == "✓" and view._short.visible and view._short.text == "One step from a pantry: get it below 16 °C.",
		"the window says the one step missing: %s" % view._short.text)
	_expect(view._comfort_heading.text == "KEEPING" and view._types.entries.pantry.steps == "get it below 16 °C" and not view._types.entries.pantry.mine,
		"and still reads its warmth as keeping")
	# Winter freezes it: a freezer.
	_clock("winter", 2.0)
	room = rooms.get_room_at(room_probe)
	_expect(room.room_type == "freezer" and float(room.temp_c) <= 0.0 and bool(room.is_frozen_vault), "frozen, it is a freezer: %.1f°C" % float(room.temp_c))
	await _refresh()
	_expect(view._kind.text == "Freezer" and room_window_tool._window_panel.get_title_label().text == "Freezer %d" % id and view._needs_heading.text == "WHAT MAKES IT A FREEZER"
		and view._need_rows.temperature.goal.text == "0 °C or below" and view._need_rows.temperature.count.text.ends_with("Frozen") and view._need_rows.temperature.glyph.text == "✓",
		"the window names the freezer and its need: %s" % view._need_rows.temperature.count.text)
	var tags: Array = view._tags.get_children().map(func(tag: Node) -> String: return (tag.get_child(0) as Label).text)
	_expect(tags == ["Sealed"], "a freezer's cold is among its needs, so it carries no Frozen vault tag: %s" % [tags])
	_clock("spring", 14.0)
	_expect(rooms.get_room_at(room_probe).room_type == "pantry", "spring makes it a pantry again")


## A dining table, a seat, a fire and a light make a dining room, whatever else the room
## holds; a cold hearth still counts.
func _dining_room() -> void:
	_put("dining_table", Vector3i(65, 20, 61))
	var room := _room_data()
	_expect(room.room_type == "pantry" and int(room.things.tables) == 1, "a table alone leaves the pantry a pantry")
	var stool = _put("log_stool", Vector3i(66, 20, 64), 2)
	var hearth = _put("hearth", Vector3i(67, 20, 67))
	room = _room_data()
	_expect(room.room_type == "dining_room" and int(room.things.seats) == 1 and int(room.things.fires) == 1 and int(room.light_count) == 2,
		"a table, a stool and a hearth make a dining room; the hearth is a light as well: %s" % room.room_type)
	await _refresh()
	_expect(view._kind.text == "Dining room" and view._needs_heading.text == "WHAT MAKES IT A DINING ROOM"
		and view._need_rows.keys() == ["tables", "seats", "fires", "lights", "doors", "walls"] and view._need_rows.fires.title.text == "Fire"
		and view._need_rows.lights.count.text == "2 sources" and view._need_rows.values().all(func(row: Dictionary) -> bool: return row.glyph.text == "✓"),
		"the window lists a dining room's needs, each ticked: %s" % [view._need_rows.keys()])
	_expect(view._comfort_heading.text == "COMFORT" and view._comfort.temperature.row.visible and not view._comfort.keeping.row.visible
		and view._comfort.heating.goal.text == "2 heat sources" and view._comfort.heating.glyph.text == "✓", "a dining room reads its warmth as comfort")
	furniture.get_fires().extinguish(hearth)
	room = _room_data()
	_expect(room.room_type == "dining_room" and int(room.heat_units) < int(hearth.def.heat_source.heat_units), "a cold hearth still counts, so it is a dining room by day")
	furniture.get_fires().light(hearth, PINE, "base:material:pine")
	furniture._teardown_installed(stool.installed_id, false)
	room = _room_data()
	_expect(room.room_type == "room" and String(rooms.nearest_kind(room).id) == "dining_room", "without a seat it is a plain room, measured against the dining room")
	await _refresh()
	_expect(view._short.visible and view._short.text == "One step from a dining room: add a seat." and view._need_rows.seats.glyph.text == "!" and view._need_rows.seats.count.text == "0",
		"the window says the seat is missing: %s" % view._short.text)
	_put("stone_stool", Vector3i(66, 20, 64), 2)
	_expect(_room_data().room_type == "dining_room", "a stone stool is a seat as well")


## A bed's types come first: a bedroom stays one with a table and a food shelf in it.
func _beds_come_first() -> void:
	_put("log_bed", Vector3i(61, 20, 64))
	var room := _room_data()
	_expect(room.room_type == "bedroom" and int(room.bed_count) == 1, "a bed makes it a bedroom, whatever else it holds: %s" % room.room_type)
	await _refresh()
	_expect(view._kind.text == "Bedroom" and view._needs_heading.text == "WHAT MAKES IT A BEDROOM" and view._owner_row.visible and view._types.entries.bedroom.mine,
		"the window shows the bedroom, and Types tags it")


## Types are derived: a reload finds them again from the furniture, and a new world starts
## with none of the old one's pieces.
func _reload() -> void:
	var state: Dictionary = JSON.parse_string(JSON.stringify(furniture.serialize_state()))
	for id in furniture._installed.keys(): furniture._teardown_installed(id, false)
	rooms.clear_runtime_state()
	_expect(rooms.thing_anchors().is_empty() and _room_data().is_empty(), "a new world keeps none of the old one's pieces")
	furniture.restore_state(state)
	var room := _room_data()
	_expect(room.room_type == "bedroom" and int(room.things.tables) == 1 and int(room.things.seats) == 1 and int(room.things.fires) == 1 and int(room.things.food_stores) == 1,
		"furniture restore counts each piece once and finds the type again: %s %s" % [room.room_type, room.things])


## The steps each type's row gives, by type id, where a plain room is shown what it could be.
func _could_be() -> Dictionary:
	var said := {}
	for key: String in view._need_rows:
		if key.begins_with("type:"): said[key.trim_prefix("type:")] = String(view._need_rows[key].goal.text)
	return said


func _open_window() -> void:
	room_window_tool = load("res://scripts/systems/RoomOverlayController.gd").new()
	room_window_tool.window_manager_path = NodePath("../Windows")
	room_window_tool.dock_ui_path = NodePath("../Dock")
	scene.add_child(room_window_tool)
	room_window_tool._select_room(rooms.get_room_id_at(room_probe), room_probe)
	await _frames(4)
	view = room_window_tool._window_content


func _refresh() -> void:
	room_window_tool._refresh_window()
	await _frames(3)


func _clock(season: String, hour: float) -> void:
	clock_node.season = season
	clock_node.day = 1
	clock_node.hour = hour
	rooms._on_hour_changed(int(hour))
