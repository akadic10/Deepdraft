extends SceneTree

## The climate (doc 34; doc 282 phases 1 and 3) in a carved world: a valley floor at Y19, a
## shelf at Y35 and a summit at Y115. Each place in doc 282's targets table is measured at the
## year's extremes (summer's first day at 14:00, winter's first day at 02:00, clear weather)
## and must hold to 1°C. Then the rules behind them: weather, a built roof, a door stopping
## outside air and letting a tenth of it into its room, a new skylight reaching an old tunnel,
## hidden caves counting as rock until found, the words, climate_at's year range and the
## DEV block inspector's climate line. Last, heat spreading: a campfire warming open air by
## walking steps and stopped by a wall, and a hearth room warming a chain of rooms through
## their doors.
## The table is written to tmp/climate_20261029/ for tuning.
const OUT := "res://tmp/climate_20261029/"
const SHELF_X := 64
const SUMMIT_X := 160
var failures: Array[String] = []
var readings: Array[Dictionary] = []
var generator: Node
var world: Node
var rooms: Node
var clock: Node
var weather: Node
var air: int
var stone: int


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	create_timer(120).timeout.connect(func(): push_error("ClimateTest timed out"); quit(1))
	await process_frame
	generator = root.get_node("WorldGenerator")
	world = root.get_node("WorldData")
	rooms = root.get_node("RoomManager")
	clock = root.get_node("WorldClock")
	weather = root.get_node("WeatherManager")
	for node in ["SaveManager", "TaskManager", "WeatherManager"]: root.get_node(node).set_process(false)
	clock.set_paused(true)
	_build_terrain()
	air = root.get_node("BlockRegistry").AIR_ID
	stone = root.get_node("BlockRegistry").get_id("base:terrain:rock:rock01")
	rooms.clear_runtime_state()
	weather.set_weather("base:weather:clear")
	_test_targets()
	_test_rules()
	_test_hidden_cave()
	_test_inspector()
	await _test_open_air_fire()
	_test_door_chain()
	DirAccess.make_dir_recursive_absolute(OUT)
	var file := FileAccess.open(OUT + "temperatures.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(readings, "\t"))
	file.close()
	for failure in failures: push_error(failure)
	print("CLIMATE_OK" if failures.is_empty() else "CLIMATE_FAIL")
	quit(0 if failures.is_empty() else 1)


func _build_terrain() -> void:
	var size_z: int = world.WORLD_SIZE_Z
	generator._maps_ready = true
	generator.world_seed = 1234
	var heights := PackedInt32Array()
	heights.resize(world.WORLD_SIZE_X * size_z)
	heights.fill(19)
	for x in range(SHELF_X, world.WORLD_SIZE_X):
		for z in 128: heights[x * size_z + z] = 35 if x < SUMMIT_X else 115
	generator.heightmap = heights
	var water := PackedInt32Array()
	water.resize(world.WORLD_SIZE_X * size_z)
	water.fill(-1)
	generator.waterline_map = water
	generator._cache_block_ids()
	# Carving deep rock fills its chunks with the real generator, ore noise included.
	generator._build_noise_instances()


## Doc 282's targets: each place's year at its extremes, to 1°C.
func _test_targets() -> void:
	# A tunnel from the valley into the Y35 shelf, three blocks high.
	_carve(Vector3i(SHELF_X, 20, 30), Vector3i(90, 22, 30))
	# A 6 x 6 x 4 larder in the shelf behind a door, 12 blocks of rock over its ceiling.
	_carve(Vector3i(65, 20, 40), Vector3i(70, 23, 45))
	_carve(Vector3i(SHELF_X, 20, 42), Vector3i(SHELF_X, 23, 42))
	_door(Vector3i(SHELF_X, 19, 42))
	# The same cellar just under the summit, its floor at Y100, its door into rock.
	_carve(Vector3i(170, 100, 40), Vector3i(175, 103, 45))
	_carve(Vector3i(169, 100, 42), Vector3i(169, 103, 42))
	_door(Vector3i(169, 99, 42))
	# Closed pockets: deep in the mountain at the valley's height, and near bedrock under the valley.
	_carve(Vector3i(200, 20, 30), Vector3i(200, 22, 30))
	_carve(Vector3i(30, 6, 60), Vector3i(30, 8, 60))
	rooms._rebuild_all_rooms()
	_expect(not rooms.get_room_at(Vector3i(67, 20, 42)).is_empty() and not rooms.get_room_at(Vector3i(172, 100, 42)).is_empty(),
		"the larder and the summit cellar are sealed rooms")
	_target("Valley, open sky", Vector3i(30, 20, 30), -8.0, 26.0)
	_target("Summit, open sky", Vector3i(200, 116, 30), -16.0, 18.0)
	_target("Tunnel, 6 blocks from open air", Vector3i(SHELF_X + 5, 20, 30), 0.0, 17.0)
	_target("The same tunnel 12 or more blocks in", Vector3i(SHELF_X + 12, 20, 30), 7.0, 11.0)
	# The larder's door opens onto the valley and lets in 9% of its swing (doc 34 "Heat and cold
	# spreading"): 6 to 12°C without it.
	_target("Sealed valley larder", Vector3i(67, 20, 42), 5.0, 13.0)
	var cellar := _target("Sealed cellar just under the summit", Vector3i(172, 100, 42), -1.0, 5.0)
	_expect(bool(cellar.winter_room.get("is_frozen_vault", false)) and not bool(cellar.summer_room.get("is_frozen_vault", true)),
		"the summit cellar freezes on the coldest day and thaws by summer")
	_target("Deep under the mountain at the valley's height", Vector3i(200, 20, 30), 9.0, 9.0)
	_target("Near bedrock under the valley", Vector3i(30, 6, 60), 7.0, 13.0)
	_heat(Vector3i(67, 19, 42), true)
	# Its hearth holds it at the tended 18°C all year (owner, 2026-10-30); through the same door it
	# loses about 2°C on the coldest night and gains a little on the hottest day.
	var larder := _target("One-hearth 6 x 6 x 4 bedroom in the valley", Vector3i(67, 20, 42), 16.0, 19.0)
	_expect(rooms.comfort_label(larder.low) == "Chilly" and rooms.comfort_label(larder.high) == "Comfortable",
		"with its door straight onto the valley, one hearth leaves a 6 x 6 x 4 cellar Chilly on the coldest night")
	# Behind a door into the rock one hearth holds it at 18°C all year, and a second adds nothing.
	_heat(Vector3i(172, 99, 42), true)
	_target("The same bedroom just under the summit, one hearth", Vector3i(172, 100, 42), 18.0, 18.0)
	_heat(Vector3i(174, 99, 44), true)
	_target("The same bedroom just under the summit, two hearths", Vector3i(172, 100, 42), 18.0, 18.0)


## The rules behind the targets.
func _test_rules() -> void:
	var tunnel := Vector3i(SHELF_X + 5, 20, 30)
	_at("summer", 14.0)
	var valley := Vector3i(30, 20, 30)
	var clear: float = rooms.temperature_at(valley)
	weather.set_weather("base:weather:rain")
	_expect(is_equal_approx(rooms.temperature_at(valley), clear - 1.0 - 5.0 * 0.6), "rain cools open air by 1°C and keeps 40% of the day's swing")
	_expect(bool(rooms.climate_at(valley).wet), "rain wets what lies under open sky")
	weather.set_weather("base:weather:clear")
	# Higher is colder: a degree for every 12 blocks.
	_expect(is_equal_approx(rooms.climate.mean_c(19.0), 9.0) and is_equal_approx(rooms.climate.mean_c(115.0), 1.0),
		"the year's mean is 9°C at the valley floor and 1°C at the summit")
	# A built roof keeps the weather off, not the cold.
	world.set_block(40, 24, 30, stone)
	var roofed: Dictionary = rooms.climate_at(Vector3i(40, 20, 30))
	_expect(roofed.kind == "sheltered" and int(roofed.steps) == 1 and int(roofed.cover) == 1, "a roofed spot is one step from open air under one block")
	_expect(absf(float(roofed.temperature_c) - clear) < 1.5, "a roof next to open air keeps nearly the outside temperature")
	# Outside air fades into a tunnel; a door at the mouth stops it.
	var place: Dictionary = rooms.climate_at(tunnel)
	_expect(place.kind == "sheltered" and int(place.steps) == 6 and is_equal_approx(float(place.air_share), 0.5), "6 steps in, a tunnel feels half the outside air")
	_expect(is_equal_approx(float(place.low_c), _reading("Tunnel, 6 blocks from open air").low)
		and is_equal_approx(float(place.high_c), _reading("Tunnel, 6 blocks from open air").high), "climate_at gives the spot's range over a year")
	_door(Vector3i(SHELF_X, 19, 30))
	rooms._rebuild_all_rooms()
	var sealed: Dictionary = rooms.climate_at(tunnel)
	var day: float = rooms.temperature_at(tunnel)
	_at("summer", 2.0)
	# The door leaks a tenth of the way to the open valley (the tunnel is under 128 cells).
	_expect(sealed.kind == "room" and is_equal_approx(float(sealed.air_share), 0.1) and absf(day - rooms.temperature_at(tunnel) - 0.1 * 10.0) < 0.001,
		"behind a door the tunnel keeps a tenth of the day and night: %.2f by day, %.2f by night" % [day, rooms.temperature_at(tunnel)])
	_expect(day < clear - 10.0, "behind a door the summer afternoon stays outside")
	_door(Vector3i(SHELF_X, 19, 30), false)
	rooms._rebuild_all_rooms()
	_expect(rooms.climate_at(tunnel).kind == "sheltered" and int(rooms.climate_at(tunnel).steps) == 6, "removing the door lets the outside air back in")
	# A skylight dug from the shelf top reaches cells that were out of reach.
	var deep := Vector3i(SHELF_X + 12, 20, 30)
	_expect(int(rooms.climate_at(deep).steps) == -1, "12 steps in, no open air reaches")
	for y in range(23, 36): world.set_block(80, y, 30, air)
	_expect(int(rooms.climate_at(deep).steps) == 4, "a new skylight 4 steps away reaches the old tunnel")
	_expect(rooms.climate.is_open_sky(Vector3i(80, 20, 30)), "the tunnel floor under the skylight is open sky")
	# Words.
	_expect(["Frozen", "Frozen", "Cold", "Chilly", "Comfortable", "Hot"] == [-1.0, 0.0, 5.0, 10.0, 20.0, 30.0].map(func(c: float) -> String: return rooms.temperature_word(c)),
		"temperature words: Frozen, Cold, Chilly, Comfortable, Hot")


## A cave the colony has not found counts as rock, and then as air.
func _test_hidden_cave() -> void:
	var column := Vector2i(100, 50)
	var cells: Array[Vector3i] = [Vector3i(100, 26, 50), Vector3i(100, 27, 50), Vector3i(100, 28, 50)]
	generator._cave_layout["columns"][column.x * world.WORLD_SIZE_Z + column.y] = Vector3i(25, 28, 77)
	rooms.climate.clear()
	var below := Vector3i(100, 20, 50)
	_expect(rooms.climate.cover_above(below) == 15 and rooms.climate_at(cells[1]).kind == "rock", "a hidden cave counts as rock")
	var interior: Node = root.get_node("InteriorTracker")
	interior._discovered_caves[77] = true
	interior.caves_discovered.emit(cells)
	_expect(rooms.climate.cover_above(below) == 12 and rooms.climate_at(cells[1]).kind == "sheltered", "a found cave's air stops counting as rock")
	generator._cave_layout["columns"].erase(column.x * world.WORLD_SIZE_Z + column.y)
	interior._discovered_caves.erase(77)


## The DEV block inspector prints the climate of the inspected air.
func _test_inspector() -> void:
	var renderer := Node3D.new()
	root.add_child(renderer)
	var inspector = load("res://scripts/components/BlockInspector.gd").new(renderer)
	var lines: Array = inspector._room_inspect_lines(Vector3i(SHELF_X + 5, 20, 30))
	_expect(lines.size() == 2 and lines[0] == "room: none (not sealed)" and String(lines[1]).begins_with("climate: ")
		and String(lines[1]).contains("6 steps from open air"), "the DEV inspector prints a tunnel's climate: %s" % [lines])
	var room_lines: Array = inspector._room_inspect_lines(Vector3i(67, 20, 42))
	_expect(String(room_lines.back()).contains("sealed room"), "the DEV inspector prints a room's climate: %s" % [room_lines])
	renderer.free()


## A campfire on the valley floor warms the open air round it by walking steps: 900 heat
## units give 6°C at the fire, fading to nothing 5 steps out, and a wall stops it.
func _test_open_air_fire() -> void:
	var fire := Vector3i(20, 19, 90)
	var at_fire := fire + Vector3i.UP
	var def := {"heat_source": {"heat_units": 900, "radius": 5}}
	var cells: Array[Vector3i] = [fire]
	var warmed: Array[Vector3i] = []
	rooms.warmth_changed.connect(func(changed: Array[Vector3i]): warmed.append_array(changed))
	_at("winter", 2.0)
	var cold: float = rooms.temperature_at(at_fire)
	rooms.set_fire_lit(cells, def, true)
	await process_frame
	_expect(warmed.has(at_fire), "lighting a fire tells the Temperature view which air it warms")
	_expect(is_equal_approx(float(rooms.climate_at(at_fire).fire_c), 6.0) and absf(rooms.temperature_at(at_fire) - cold - 6.0) < 0.001,
		"a campfire warms the air at it by 6°C: %.2f" % float(rooms.climate_at(at_fire).fire_c))
	var steps: Array = [2, 4, 5].map(func(step: int) -> float: return rooms.heat.warmth_at(at_fire + Vector3i(step, 0, 0)))
	_expect(absf(steps[0] - 3.6) < 0.001 and absf(steps[1] - 1.2) < 0.001 and steps[2] == 0.0, "the warmth fades over 5 steps: %s at 2, 4 and 5 steps" % [steps])
	var behind := at_fire + Vector3i(3, 0, 0)
	_expect(absf(rooms.heat.warmth_at(behind) - 2.4) < 0.001, "3 steps from the fire the air is 2.4°C warmer")
	# A wall 2 steps out: round it or over it is more than 5 steps.
	for z in range(86, 95):
		for y in range(20, 25): world.set_block(22, y, z, stone)
	_expect(rooms.heat.warmth_at(behind) == 0.0, "a wall stops the fire's warmth")
	rooms.set_fire_lit(cells, def, false)
	_expect(rooms.heat.warmth_at(at_fire) == 0.0, "a fire going out takes its warmth with it")
	for z in range(86, 95):
		for y in range(20, 25): world.set_block(22, y, z, air)
	await process_frame


## A fire warms a row of three 4 x 4 x 4 rooms through their doors. Each door pulls a room a
## tenth of the way toward its other side, over two passes: the fire's room keeps all but
## 0.1 x 0.9 of its 6.25°C, the next room gains as much and the one beyond a tenth of a tenth.
## The fire is a small one, so the tended cap leaves its heat whole.
func _test_door_chain() -> void:
	var probes: Array[Vector3i] = []
	for i in 3:
		var x := 100 + i * 5
		_carve(Vector3i(x, 20, 60), Vector3i(x + 3, 23, 63))
		probes.append(Vector3i(x + 1, 20, 61))
		if i > 0:
			_carve(Vector3i(x - 1, 20, 61), Vector3i(x - 1, 23, 61))
			_door(Vector3i(x - 1, 19, 61))
	rooms._rebuild_all_rooms()
	_at("winter", 2.0)
	_expect(probes.all(func(cell: Vector3i) -> bool: return int(rooms.get_room_at(cell).get("volume", 0)) == 64), "three sealed 4 x 4 x 4 rooms in a row")
	var before: Array = probes.map(func(cell: Vector3i) -> float: return rooms.temperature_at(cell))
	var hearth: Array[Vector3i] = [Vector3i(101, 19, 61)]
	rooms.on_furniture_changed("base:furniture:hearth", hearth, {"heat_source": {"heat_units": 800, "radius": 4}}, true)
	rooms._rebuild_all_rooms()
	var gains: Array = []
	for i in 3: gains.append(rooms.temperature_at(probes[i]) - float(before[i]))
	_expect(absf(gains[0] - 5.6875) < 0.001 and absf(gains[1] - 0.5625) < 0.001 and absf(gains[2] - 0.0625) < 0.001,
		"a fire's room keeps 5.69 of its 6.25°C and warms the next room by 0.56 and the one beyond by 0.06: %s" % [gains])
	var hearth_room: Dictionary = rooms.climate_at(probes[0])
	var next_room: Dictionary = rooms.climate_at(probes[1])
	_expect(absf(float(hearth_room.heat_c) - 5.6875) < 0.001 and absf(float(hearth_room.door_c)) < 0.001 and absf(rooms.heat_kept(probes[0], 800) - 5.6875) < 0.001,
		"the fire's room adds what it keeps of its heat: %.3f" % float(hearth_room.heat_c))
	_expect(absf(float(next_room.door_c) - 0.5625) < 0.001 and float(next_room.heat_c) == 0.0, "the next room's doors make it 0.56°C warmer")
	_expect(rooms.heat.warmth_at(probes[0]) == 0.0, "a fire in a sealed room warms the room, not open air")


## Measures a place at the year's extremes and checks it against its target, to 1°C.
func _target(name: String, cell: Vector3i, low: float, high: float) -> Dictionary:
	_at("winter", 2.0)
	var coldest: float = rooms.temperature_at(cell)
	var winter_room: Dictionary = rooms.get_room_at(cell).duplicate()
	_at("summer", 14.0)
	var warmest: float = rooms.temperature_at(cell)
	var summer_room: Dictionary = rooms.get_room_at(cell).duplicate()
	readings.append({"place": name, "low": coldest, "high": warmest, "target_low": low, "target_high": high})
	_expect(absf(coldest - low) <= 1.0 and absf(warmest - high) <= 1.0,
		"%s: %.1f to %.1f°C, target %.0f to %.0f" % [name, coldest, warmest, low, high])
	return {"low": coldest, "high": warmest, "winter_room": winter_room, "summer_room": summer_room}


func _reading(name: String) -> Dictionary:
	for reading: Dictionary in readings:
		if reading.place == name: return reading
	return {}


func _at(season: String, hour: float) -> void:
	clock.season = season
	clock.day = 1
	clock.hour = hour
	rooms._on_hour_changed(int(hour))


func _carve(from: Vector3i, to: Vector3i) -> void:
	for x in range(from.x, to.x + 1):
		for y in range(from.y, to.y + 1):
			for z in range(from.z, to.z + 1): world.set_block(x, y, z, air)


func _door(floor_cell: Vector3i, installed := true) -> void:
	var cells: Array[Vector3i] = [floor_cell]
	rooms.on_furniture_changed("base:furniture:door", cells, {"furniture_category": "door"}, installed)


func _heat(floor_cell: Vector3i, installed: bool) -> void:
	var cells: Array[Vector3i] = [floor_cell]
	rooms.on_furniture_changed("base:furniture:hearth", cells, {"heat_source": {"heat_units": 9600}}, installed)
	rooms._rebuild_all_rooms()


func _expect(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
