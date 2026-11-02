extends "res://scripts/tests/WorkerCraftingTest.gd"

## The Temperature view (doc 23 "The Temperature view"; doc 282). Its button sits between
## Appeal and X-ray at the dock's end, lights while on and brings up its scale (each word with
## its colour and range, hottest first). Nothing is built while it is off. While on, the world
## dims and floors are built in tiles round the point the camera looks at, a little each
## frame: each floor's numbers, with the shader's clock values, give RoomManager's temperature
## for it. A game hour passing and a change of weather only move the shader's values; an edit
## builds again only the tiles within reach; moving the slice builds every tile again at the
## new cut. A cave the colony has not found stays rock until found (Hard Rule 11). The hover
## card names the spot, its temperature and word, what sets it and its year; a click on a
## room's floor opens the room window. The Appeal view and this one take turns, and turning it
## off takes everything away.
## The places: a hut with a hearth on the plain, and a stone hill east of it with a tunnel into
## its west face, a room behind a door and a cave nobody has found.
const HUT_FLOOR := Vector3i(62, 21, 62)
const HILL_ROOM := Vector3i(90, 21, 48)
const TUNNEL := Vector3i(85, 21, 75)   # 6 steps in from the hill's face, 10 blocks under its top
const OPEN := Vector3i(30, 21, 30)
const CAVE := Vector2i(100, 60)         # its air at Y25 to Y28, inside the hill
const CAVE_ID := 77
var rooms
var interior
var view
var appeal
var room_tool
var stub_slice
var stone: int
var air_id: int


func _run() -> void:
	create_timer(240).timeout.connect(func(): push_error("Temperature view timeout"); quit(1))
	await _setup_crafting_fixture()
	clock_node.set_paused(true)
	rooms = root.get_node("RoomManager")
	interior = root.get_node("InteriorTracker")
	stone = blocks.get_id("base:terrain:rock:rock01")
	air_id = blocks.AIR_ID
	root.get_node("WeatherManager").set_weather("base:weather:clear")
	_build_places()
	stub_slice = _stub_slice()
	scene.add_child(stub_slice)
	room_tool = load("res://scripts/systems/RoomOverlayController.gd").new()
	room_tool.name = "RoomTool"
	room_tool.window_manager_path = NodePath("../Windows")
	room_tool.dock_ui_path = NodePath("../Dock")
	scene.add_child(room_tool)
	appeal = load("res://scripts/systems/AppealViewController.gd").new()
	appeal.name = "AppealView"
	appeal.dock_path = NodePath("../Dock")
	appeal.slice_path = NodePath("../Slice")
	appeal.rooms_tool_path = NodePath("../RoomTool")
	scene.add_child(appeal)
	view = load("res://scripts/systems/TemperatureViewController.gd").new()
	view.name = "TemperatureView"
	view.dock_path = NodePath("../Dock")
	view.slice_path = NodePath("../Slice")
	view.rooms_tool_path = NodePath("../RoomTool")
	var tools: Array[NodePath] = [NodePath("../RoomTool")]
	view.tool_paths = tools
	scene.add_child(view)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 48
	camera.position = Vector3(72.5, 80, 64.5)
	camera.look_at(Vector3(72.5, 20, 64.5), Vector3.FORWARD)
	_at("summer", 14.0)
	await _frames(3)
	await _button_and_scale()
	await _filling()
	await _numbers()
	await _quiet_clock()
	await _edit_nearby()
	await _slice_and_cave()
	await _hover_and_click()
	await _taking_turns()
	for failure: String in failures: push_error(failure)
	print("TEMPERATURE_VIEW_OK: button, scale, budgeted tiles, numbers, quiet clock, nearby edits, slice, hidden cave, card, click, turns and off"
		if failures.is_empty() else "TEMPERATURE_VIEW_FAIL")
	quit(0 if failures.is_empty() else 1)


func _build_places() -> void:
	rooms.clear_runtime_state()
	# The hill, laid straight into the fixture's chunks as the plain is: x 80..111, z 40..95, up to Y33.
	for x in range(80, 112):
		for z in range(40, 96):
			for y in range(21, 34): _lay(Vector3i(x, y, z), stone)
	# A cave inside it the colony has not found: generated air, rock to the climate.
	for y in range(25, 29): _lay(Vector3i(CAVE.x, y, CAVE.y), air_id)
	root.get_node("WorldGenerator")._cave_layout["columns"][CAVE.x * world.WORLD_SIZE_Z + CAVE.y] = Vector3i(24, 28, CAVE_ID)
	rooms.climate.clear()
	# The hut: stone walls and a roof round the floor 61..68 x 61..68, its doorway shut by a door.
	for x in range(60, 70):
		for z in range(60, 70):
			for y in range(21, 26):
				if x in [63, 64] and z == 60 and y < 25: continue
				if x in [60, 69] or z in [60, 69] or y == 25: world.set_block(x, y, z, stone)
	_put("door", Vector3i(63, 20, 60))
	var hearth: Array[Vector3i] = [Vector3i(66, 20, 66)]
	rooms.on_furniture_changed("base:furniture:hearth", hearth, {"heat_source": {"heat_units": 1600}}, true)
	# A tunnel into the hill's west face, and a room behind a door in its north face.
	_dig(Vector3i(80, 21, 75), Vector3i(97, 23, 75))
	_dig(Vector3i(90, 21, 40), Vector3i(91, 24, 45))
	_dig(Vector3i(87, 21, 46), Vector3i(94, 24, 51))
	_put("door", Vector3i(90, 20, 40))
	rooms._rebuild_all_rooms()
	_expect(rooms.get_room_id_at(HUT_FLOOR) >= 0 and rooms.get_room_id_at(HILL_ROOM) >= 0 and rooms.get_room_id_at(TUNNEL) < 0
		and int(rooms.get_room_at(HUT_FLOOR).heat_units) > 0, "the hut and the hill room are sealed, the hut heated; the tunnel is open")


func _button_and_scale() -> void:
	var hud = dock._time_slice_hud
	_expect(hud.temperature_button.visible and hud.appeal_button.get_index() < hud.temperature_button.get_index()
		and hud.temperature_button.get_index() < hud.xray_button.get_index() and not hud.temperature_button.button_pressed,
		"the Temperature button sits between Appeal and X-ray, off")
	await _frames(5)
	_expect(not view.active and view.tiles.is_empty() and not view.is_processing(), "nothing is built or run while the view is off")
	hud.temperature_button.pressed.emit()
	await _frames(2)
	_expect(view.active and hud.temperature_button.button_pressed and hud.temperature_panel.visible, "the button turns the view on and lights")
	var texts: Array = hud._temperature_labels.map(func(label: Label) -> String: return label.text)
	_expect(texts.slice(0, 10) == ["Hot", "above 26°C", "Comfortable", "16 to 26°C", "Chilly", "8 to 16°C", "Cold", "0 to 8°C", "Frozen", "0°C and below"],
		"the scale lists each word with its range, hottest first: %s" % [texts])
	var panel: Rect2 = hud.temperature_panel.get_global_rect()
	_expect(panel.end.y <= dock._dock_panel.get_global_rect().position.y and panel in hud.occupied_rects(),
		"the scale stands above the dock, and other panels keep clear of it")
	var material: ShaderMaterial = view._material
	_expect(is_instance_valid(view._dim) and is_equal_approx(float(material.get_shader_parameter("comfortable_min")), 16.0)
		and (material.get_shader_parameter("frozen_colour") as Color).is_equal_approx(Color("#e6f4ff")),
		"the world dims, and the floors' shader has the words' edges and colours")


## The tiles round the camera's focus come a little each frame, nearest first.
func _filling() -> void:
	var budget := float(view._config.budget_ms)
	var frames := 0
	var spent := 0.0
	var first := Vector2i(-1, -1)
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 60000:
		await process_frame
		if view.builds == 1 and first.x < 0: first = view.tiles.keys()[0]
		frames += 1
		spent += view.last_work_usec / 1000.0
		if _idle(): break
	_expect(view.tiles.size() == 81 and first == Vector2i(4, 4), "the 9 x 9 tiles round the focus are built, its own first: %d, first %s" % [view.tiles.size(), first])
	_expect(frames >= 10 and spent / frames <= budget + 2.0,
		"building is spread over frames within the budget: %d frames, %.2f ms a frame" % [frames, spent / frames])
	print("TEMPERATURE_VIEW fill: %d tiles in %d frames, %.2f ms a frame (budget %.1f)" % [view.tiles.size(), frames, spent / frames, budget])


## Each floor's numbers give the temperature RoomManager gives it, at the year's extremes and
## in rain. A jump between seasons may move the heated hut between its tended forms (held
## at the cap in summer, rock plus fire in winter), so the view builds its tile again first.
func _numbers() -> void:
	var cells: Array[Vector3i] = [OPEN, TUNNEL, HUT_FLOOR, HILL_ROOM, Vector3i(100, 34, 50)]
	for setting: Array in [["summer", 14.0, "clear"], ["winter", 2.0, "clear"], ["winter", 2.0, "rain"]]:
		_at(setting[0], setting[1])
		root.get_node("WeatherManager").set_weather("base:weather:" + setting[2])
		await _settled()
		for cell: Vector3i in cells:
			_expect(absf(_shown(cell) - float(rooms.temperature_at(cell))) < 0.01, "%s at %s %s %s: the view shows %.2f°C, RoomManager %.2f°C"
				% [cell, setting[0], setting[1], setting[2], _shown(cell), rooms.temperature_at(cell)])
	root.get_node("WeatherManager").set_weather("base:weather:clear")
	_at("summer", 14.0)
	var tile: Dictionary = view.tiles[Vector2i(1, 1)]
	_expect(tile.node.multimesh.instance_count == 16, "open ground of one height merges into a quad a row: %d" % tile.node.multimesh.instance_count)


## A game hour passing and a change of weather move only the shader's two values. The jump
## back from winter may move the hut between its tended forms, so that settles first.
func _quiet_clock() -> void:
	_at("summer", 14.0)
	root.get_node("WeatherManager").set_weather("base:weather:clear")
	await _settled()
	var builds: int = view.builds
	_at("summer", 15.0)
	root.get_node("WeatherManager").set_weather("base:weather:rain")
	await _settled()
	var material: ShaderMaterial = view._material
	_expect(view.builds == builds and is_equal_approx(float(material.get_shader_parameter("season_c")), rooms.climate.season_c())
		and is_equal_approx(float(material.get_shader_parameter("day_weather_c")), rooms.climate.day_and_weather_c()),
		"an hour passing and rain set the shader's values and build nothing (%d builds)" % (view.builds - builds))
	root.get_node("WeatherManager").set_weather("base:weather:clear")


## A block set on the hill above the tunnel builds again only the tiles within the outside
## air's reach of it.
func _edit_nearby() -> void:
	var meshes := {}
	for tile: Vector2i in view.tiles: meshes[tile] = view.tiles[tile].node.multimesh
	world.set_block(88, 34, 75, stone)
	await _settled()
	var rebuilt: Array = view.tiles.keys().filter(func(tile: Vector2i) -> bool: return view.tiles[tile].node.multimesh != meshes[tile])
	var near := rebuilt.all(func(tile: Vector2i) -> bool: return tile.x >= 4 and tile.x <= 6 and tile.y >= 3 and tile.y <= 5)
	_expect(not rebuilt.is_empty() and rebuilt.size() <= 9 and near, "an edit builds again only the tiles within reach: %s" % [rebuilt])
	var cell := Vector3i(88, 21, 75)
	_expect(absf(_shown(cell) - float(rooms.temperature_at(cell))) < 0.01 and int(rooms.climate_at(cell).cover) == 11,
		"the tunnel under the new block shows its new temperature")


## The slice cuts every tile again; a cave nobody has found shows as rock until it is found.
func _slice_and_cave() -> void:
	var builds: int = view.builds
	stub_slice.on = true
	stub_slice.y = 27
	stub_slice.slice_active_changed.emit(true)
	_expect(view.tiles.values().all(func(tile: Dictionary) -> bool: return not tile.node.visible), "a slice change hides the tiles until each is built again")
	await _settled()
	_expect(view.builds - builds == 81 and view.tiles.values().all(func(tile: Dictionary) -> bool: return tile.node.visible),
		"every tile is built again at the new cut")
	_expect(not _has_floor(Vector3i(100, 34, 50)) and _has_floor(TUNNEL) and _has_floor(HUT_FLOOR),
		"the cut hill top stays dim; the tunnel and the hut under the cut keep their floors")
	var hidden: bool = view.tiles.values().all(func(tile: Dictionary) -> bool:
		return (tile.values as Dictionary).keys().all(func(cell: Vector3i) -> bool: return Vector2i(cell.x, cell.z) != CAVE or cell.y < 25 or cell.y > 29))
	_expect(hidden, "a cave nobody has found shows no floor")
	view.fill_card({"cell": Vector3i(CAVE.x, 27, CAVE.y), "rock": true})
	_expect(view._card._title.text == "Rock" and view._card._body.text.begins_with("6 blocks overhead: a sealed room dug here")
		and view._card._body.text.contains("Blueberries would keep about ") and view._card._body.text.ends_with(" in a room dug here."),
		"over it the card reads rock, and how long food would keep there: %s / %s" % [view._card._title.text, view._card._body.text])
	var cells: Array[Vector3i] = []
	for y in range(25, 29): cells.append(Vector3i(CAVE.x, y, CAVE.y))
	interior._discovered_caves[CAVE_ID] = true
	interior.caves_discovered.emit(cells)
	await _settled()
	_expect(_has_floor(Vector3i(CAVE.x, 25, CAVE.y)), "once found, the cave's floor takes its colour")


func _hover_and_click() -> void:
	# On a winter night the hut's fire warms it; by a summer day its rock is past the tended cap.
	_at("winter", 2.0)
	stub_slice.y = 24
	stub_slice.slice_changed.emit(24)
	await _settled()
	var floor_point: Vector2 = camera.unproject_position(Vector3(62.5, 21.0, 62.5))
	var spot: Dictionary = view.spot_under(floor_point)
	_expect(spot.get("cell") == HUT_FLOOR and not bool(spot.get("rock", true)), "a screen point over the hut's floor finds the air on it: %s" % [spot])
	var cut_point: Vector2 = camera.unproject_position(Vector3(100.5, 25.0, 50.5))
	_expect(bool(view.spot_under(cut_point).get("rock", false)), "a screen point on the cut hill finds its rock")
	var id: int = rooms.get_room_id_at(HUT_FLOOR)
	var place: Dictionary = rooms.climate_at(HUT_FLOOR)
	# The hut's door to the plain lets in a little of the outside (doc 34 "Heat and cold spreading").
	var heat := float(place.heat_c)
	var doors := float(place.door_c)
	var hut: Dictionary = rooms.get_rooms()[id]
	var rock: float = rooms.climate.form_temperature(hut.own_form) - float(hut.heat_bonus_c)
	_expect(heat > 0.0 and heat < float(hut.heat_bonus_c) and absf(float(place.temperature_c) - rock - heat - doors) < 0.001,
		"the hut is its rock's temperature, plus what it keeps of its fire, plus its door: %.2f + %.2f + %.2f" % [rock, heat, doors])
	view.fill_card(spot)
	var body: String = view._card._body.text
	var unheated := "Over a year without its fires: %d to %d°C in clear weather." % [floori(float(place.low_c) - heat), ceili(float(place.high_c) - heat)]
	_expect(view._card._title.text == room_tool.room_title(hut, id)
		and view._card._status.text == "%.1f°C · %s" % [float(place.temperature_c), String(place.word)]
		and body.begins_with("A sealed room: 89% of the season reaches it, and 5% of the day and weather through its doors.")
		and body.contains("Its fires add %.1f°C." % heat) and body.contains("Its doors make it %.1f°C %s." % [absf(doors), "warmer" if doors > 0.0 else "colder"])
		and body.contains(unheated) and body.ends_with("Click for the room."),
		"the card names the room, its temperature and word, its fires, its doors and its year without the fires: %s / %s / %s" % [view._card._title.text, view._card._status.text, body])
	view.fill_card({"cell": TUNNEL, "rock": false})
	_expect(view._card._title.text == "Underground" and view._card._body.text.begins_with("6 steps from open air, 10 blocks overhead."),
		"in the tunnel it gives the steps from open air and the rock overhead: %s" % view._card._body.text)
	view.fill_card({"cell": OPEN, "rock": false})
	var year: Vector2 = rooms.climate.year_range(21.0, 1.0, 1.0)
	var days: float = root.get_node("StockpileManager").spoilage.keeps_days_at(drops.food_definition("base:resources:flora:blueberry"), OPEN)
	var keeping := "Blueberries keep %s here." % ("less than a day" if days < 1.0 else ("about a day" if days < 1.5 else "about %d days" % roundi(days)))
	_expect(view._card._title.text == "Open ground" and view._card._body.text.contains("Over a year: %d to %d°C in clear weather." % [floori(year.x), ceili(year.y)])
		and view._card._body.text.ends_with(keeping), "on open ground it gives its year and how long blueberries keep there: %s" % view._card._body.text)
	# A campfire on the plain: the floors round it show its warmth, and the card names it.
	var fire: Array[Vector3i] = [Vector3i(40, 20, 30)]
	var campfire := {"heat_source": {"heat_units": 900, "radius": 5}}
	rooms.set_fire_lit(fire, campfire, true)
	await _settled()
	var warm := Vector3i(41, 21, 30)
	_expect(absf(float(rooms.climate_at(warm).fire_c) - 4.8) < 0.001 and absf(_shown(warm) - float(rooms.temperature_at(warm))) < 0.01,
		"the floor a step from a campfire shows its warmth: %.2f°C shown, %.2f°C" % [_shown(warm), rooms.temperature_at(warm)])
	view.fill_card({"cell": warm, "rock": false})
	_expect(view._card._body.text.contains("A fire nearby adds 4.8°C.") and view._card._body.text.contains("Over a year without the fire: %d to %d°C in clear weather." % [floori(year.x), ceili(year.y)]),
		"by a fire the card says what it adds, and gives the year without it: %s" % view._card._body.text)
	rooms.set_fire_lit(fire, campfire, false)
	await _settled()
	_expect(absf(_shown(warm) - float(rooms.temperature_at(warm))) < 0.01 and float(rooms.climate_at(warm).fire_c) == 0.0, "the warmth goes with the fire")
	room_tool.activate()
	_expect(view._hover_blocked(), "no card while a click tool works")
	room_tool.deactivate()
	_expect(view.try_select_zone_at_screen(floor_point), "a click on a room's floor is the view's")
	await _frames(3)
	_expect(room_tool._window_panel.visible, "it opens the room window")
	room_tool._close_window()
	_expect(not view.try_select_zone_at_screen(cut_point), "a click on the cut rock is not the view's")


func _taking_turns() -> void:
	var hud = dock._time_slice_hud
	appeal.set_active(true)
	await _frames(2)
	_expect(appeal.active and not view.active and view.tiles.is_empty() and not hud.temperature_panel.visible and hud.appeal_panel.visible,
		"turning the Appeal view on turns this one off")
	view.set_active(true)
	await _frames(2)
	_expect(view.active and not appeal.active and not hud.appeal_panel.visible, "and the other way round")
	view.set_active(false)
	await _frames(2)
	_expect(not view.is_processing() and view.tiles.is_empty() and view._dim == null and view._card == null
		and view.get_children().is_empty(), "turning the view off takes the dim, the tiles and the card away")


## The temperature a floor shows now: its numbers with the shader's clock values.
func _shown(cell: Vector3i) -> float:
	var tile := Vector2i(cell.x >> 4, cell.z >> 4)
	if not view.tiles.has(tile) or not view.tiles[tile].values.has(cell): return NAN
	var numbers: Vector4 = view.tiles[tile].values[cell]
	var material: ShaderMaterial = view._material
	return numbers.x + numbers.y * float(material.get_shader_parameter("season_c")) + numbers.z * float(material.get_shader_parameter("day_weather_c"))


func _has_floor(cell: Vector3i) -> bool:
	var tile := Vector2i(cell.x >> 4, cell.z >> 4)
	return view.tiles.has(tile) and view.tiles[tile].values.has(cell)


## Nothing queued, waiting or being built.
func _idle() -> bool:
	var stats: Dictionary = view.get_stats()
	return stats.queued == 0 and stats.waiting == 0 and view._build.is_empty() and view._rooms_left < 0.0


## Frames until changes have settled and every tile they touched is built.
func _settled() -> void:
	var started := Time.get_ticks_msec()
	await _frames(2)
	while not _idle() and Time.get_ticks_msec() - started < 30000: await process_frame


func _at(season: String, hour: float) -> void:
	clock_node.season = season
	clock_node.day = 1
	clock_node.hour = hour
	clock_node.hour_changed.emit(int(hour))


## Digs a box as mining does: air written, then the interior told.
func _dig(from: Vector3i, to: Vector3i) -> void:
	var cells: Array[Vector3i] = []
	for x in range(from.x, to.x + 1):
		for y in range(from.y, to.y + 1):
			for z in range(from.z, to.z + 1):
				world.set_block(x, y, z, air_id)
				cells.append(Vector3i(x, y, z))
	interior.on_blocks_mined(cells)


## Writes a block straight into its chunk, as the fixture lays its plain.
func _lay(cell: Vector3i, id: int) -> void:
	var chunk = world.get_chunk(cell.x >> 4, cell.y >> 4, cell.z >> 4)
	chunk.blocks[(cell.x & 15) + 16 * (cell.z & 15) + 256 * (cell.y & 15)] = id


func _put(short_key: String, cell: Vector3i, yaw := 0):
	var key := "base:furniture:" + short_key
	furniture._install(key, furniture.get_defs()[key], cell, yaw)
	return furniture._installed[furniture._next_installed_id - 1]


## A stand-in for the SliceController: its height and whether it is on.
func _stub_slice() -> Node:
	var script := GDScript.new()
	script.source_code = "extends Node\nsignal slice_changed(height: int)\nsignal slice_active_changed(active: bool)\nvar y := 127\nvar on := false\nfunc get_slice_y() -> int: return y\nfunc is_active() -> bool: return on\n"
	script.reload()
	var node: Node = script.new()
	node.name = "Slice"
	return node
