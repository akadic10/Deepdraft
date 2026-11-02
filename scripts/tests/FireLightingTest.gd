extends "res://scripts/tests/WorkerCraftingTest.gd"

## Nightly fires (doc 279): cold by day; at dusk a real worker brings any log, the
## fire burns it until dawn and the log is gone. Heat, light, the log in the fire,
## the inspector, saves and a dawn interruption all follow that state.
const CAMPFIRE := "base:furniture:campfire"
const HEARTH := "base:furniture:hearth"
const FIRE_ORIGIN := Vector3i(44,20,44)

func _run() -> void:
	create_timer(120).timeout.connect(func(): push_error("Fire lighting timed out"); quit(1))
	await _setup_crafting_fixture()
	var rooms := root.get_node("RoomManager")
	var fires = furniture.get_fires()
	var fire = _install(CAMPFIRE, FIRE_ORIGIN)
	var anchor: Vector3i = furniture.room_cells(fire)[0]
	_set_hour(12.0)
	fires.tick()
	_expect(fire.fire_log.is_empty() and fires.work.size() == 0, "a campfire installs cold and posts nothing by day")
	_expect(not _lit_visuals(fire) and fire.node.get_node_or_null("FireLog") == null, "a cold fire shows no flame, light or log")
	_expect(not rooms._heat_cells.has(anchor), "a cold fire gives no heat")
	_expect(rooms.count_room_lights({anchor + Vector3i.UP: true}) == 1, "a cold fire is still its room's light fixture, so a bedroom keeps its kind by day")
	_expect(_fire_row(fire) == "Cold · lit at dusk", "the inspector says when it will be lit")
	# Night without any log: the job exists but waits, and says why.
	_set_hour(23.0)
	fires.tick()
	_expect(fires.work.size() == 1 and fires.work.get_source(fire.installed_id).lease_id() < 0, "at dusk a cold fire posts a job that waits for a log")
	_expect(_fire_row(fire) == "No log to light it", "the inspector explains the missing log")
	# A log appears: a real worker fetches it, sets it in the fire and lights it.
	drops.spawn_drop(PINE, 1, Vector3i(50,21,41))
	fires.update_leases()
	var carried := false
	for i in 900:
		if not fire.fire_log.is_empty(): break
		carried = carried or worker._task_phase == worker.TaskPhase.FETCH_TO_GHOST
		await _fire_tick()
	_expect(carried and fire.fire_log == PINE, "a worker carries the log to the fire and lights it")
	_expect(_loose(PINE) == 0 and fires.work.size() == 0 and worker.current_task_id < 0, "the log is used, the job is done and the worker is free")
	var log_node: Node3D = fire.node.get_node_or_null("FireLog")
	_expect(_lit_visuals(fire) and log_node != null and String(log_node.get_meta("item_key", "")) == PINE, "a lit fire shows its flame, light and the pine log it burns")
	_expect(log_node != null and Vector2(log_node.global_position.x, log_node.global_position.z).distance_to(Vector2(45.5,45.5)) < .05, "the log lies in the middle of the ring")
	_expect(int(rooms._heat_cells.get(anchor, 0)) == int(fire.def.heat_source.heat_units) and rooms.count_room_lights({anchor + Vector3i.UP: true}) == 1, "a lit fire counts its heat and light once")
	_expect(_fire_row(fire) == "Burning until dawn" and _rows(fire).get("Burning") == "Pine Log", "the inspector names the burning log")
	_expect(load("res://scripts/components/FurnitureFires.gd").burning(fire), "the crackle and the panel treat it as burning")
	# Saves keep the burning log; restoring counts its heat once.
	var saved: Dictionary = JSON.parse_string(JSON.stringify(furniture.serialize_state()))
	for id in furniture._installed.keys(): furniture._teardown_installed(id, false)
	_expect(not rooms._heat_cells.has(anchor), "removing a lit fire takes its heat away")
	furniture.restore_state(saved)
	fire = furniture._installed.values().filter(func(piece): return piece.furniture_key == CAMPFIRE)[0]
	fires.tick()
	_expect(fire.fire_log == PINE and _lit_visuals(fire) and fire.node.get_node_or_null("FireLog") != null, "a loaded night fire is still burning its log")
	_expect(int(rooms._heat_cells.get(anchor, 0)) == int(fire.def.heat_source.heat_units) and fires.work.size() == 0, "a loaded fire counts its heat once and posts no job")
	# Dawn: the fire goes out and the log is gone.
	_set_hour(8.0)
	fires.tick()
	_expect(fire.fire_log.is_empty() and not _lit_visuals(fire) and fire.node.get_node_or_null("FireLog") == null, "at dawn the fire goes out and its log is gone")
	_expect(not rooms._heat_cells.has(anchor) and _loose(PINE) == 0, "a spent fire gives no heat and returns no log")
	# Dawn while a worker is on the way: the job ends and the log drops intact.
	_set_hour(23.0)
	fires.tick()
	drops.spawn_drop(PINE, 1, Vector3i(50,21,41))
	fires.update_leases()
	var on_way := false
	for i in 900:
		if worker._task_phase == worker.TaskPhase.FETCH_TO_GHOST: on_way = true; break
		await _fire_tick()
	_expect(on_way, "the next night's worker picks up a log")
	_set_hour(8.0)
	fires.tick()
	await _fire_tick()
	_expect(fires.work.size() == 0 and worker.current_task_id < 0 and _loose(PINE) == 1 and fire.fire_log.is_empty(), "dawn ends the job and the carried log drops intact")
	# A hearth is fed from in front of its fire-back: its worker stands there.
	for id in furniture._installed.keys(): furniture._teardown_installed(id, false)
	var hearth = _install(HEARTH, FIRE_ORIGIN)
	_set_hour(23.0)
	fires.tick()
	var source = fires.work.get_source(hearth.installed_id)
	var stands: Array[Vector3i] = source.work_stands(worker.current_cell())
	_expect(not stands.is_empty() and stands.all(func(cell: Vector3i) -> bool: return cell.z == FIRE_ORIGIN.z + 2), "a hearth's worker stands in front of the fire")
	var at: Array = hearth.def.nightly_fire.log_position
	_expect(source.placement_contact(Vector3.ZERO).distance_to(Vector3(45 + at[0], 21 + at[1], 45 + at[2])) < .05, "the hearth's log goes on its ash before the fire-back")
	_test_warm_rooms(rooms, fires)
	await _test_bedtime(rooms, fires)
	for failure in failures: push_error(failure)
	print("FIRE_LIGHTING_OK: cold by day, dusk job, worker lights with a real log, heat/light/log shown, inspector, save, dawn, interrupted delivery, hearth front, warm rooms, bedtime fires" if failures.is_empty() else "FIRE_LIGHTING_FAIL")
	quit(0 if failures.is_empty() else 1)


## A fire in a sealed room burns only while the room is below Comfortable without it
## (owner, 2026-10-29). A 6 x 6 x 4 hut under a one-block roof: about 19°C on a summer night,
## 9°C in spring (one hearth makes it 20°C) and -2°C in winter.
func _test_warm_rooms(rooms: Node, fires: RefCounted) -> void:
	for id in furniture._installed.keys(): furniture._teardown_installed(id, false)
	var stone: int = blocks.get_id("base:terrain:rock:rock01")
	for x in range(80,88):
		for z in range(60,68):
			for y in range(21,26):
				if x in [83,84] and z == 60 and y < 25: continue
				if x in [80,87] or z in [60,67] or y == 25: world.set_block(x,y,z,stone)
	_install("base:furniture:door", Vector3i(83,20,60))
	var first = _install(HEARTH, Vector3i(81,20,62))
	var second = _install(HEARTH, Vector3i(85,20,62))
	rooms._rebuild_all_rooms()
	_expect(not rooms.get_room_at(Vector3i(81,21,62)).is_empty(), "the hut is a sealed room")
	_night("summer", rooms, fires)
	_expect(not fires.work.has(first.installed_id) and not fires.work.has(second.installed_id), "on a warm summer night the hut's hearths stay unlit")
	_expect(_fire_row(first) == "Unlit · the room is warm enough", "the inspector says why a hearth is unlit")
	_night("spring", rooms, fires)
	_expect(fires.work.has(first.installed_id) and fires.work.has(second.installed_id), "on a cool spring night both hearths are wanted at dusk")
	fires.light(first, PINE, "base:material:pine")
	rooms._rebuild_all_rooms()
	fires.tick()
	_expect(not fires.work.has(second.installed_id) and _fire_row(second) == "Unlit · the room is warm enough", "once one hearth warms the room the other stands down")
	_expect(not fires.work.has(first.installed_id) and rooms.comfort_label(rooms.get_room_at(Vector3i(81,21,62)).temp_c) == "Comfortable", "one hearth makes the spring hut comfortable")
	# Fires are tended to 18°C before the door leaks (owner, 2026-10-30): on a winter night the
	# first hearth already holds the hut there, so the second would add nothing and stays unlit.
	_night("winter", rooms, fires)
	_expect(not fires.work.has(second.installed_id) and _fire_row(second) == "Unlit · another fire already heats the room",
		"on a winter night the first hearth heats the hut fully and the second stays unlit: %s" % _fire_row(second))


## The owner's report (2026-10-30): Furin went to bed before dusk in a cold bedroom, its
## hearth unlit. A tired dwarf lights its bedroom's fire before bed, by day too. By day
## the fire then burns while someone sleeps there and goes out when the last one wakes.
func _test_bedtime(rooms: Node, fires: RefCounted) -> void:
	for id in furniture._installed.keys(): furniture._teardown_installed(id, false)
	for node in drops._loose.keys():
		drops.take(node)
		node.free()
	_install("base:furniture:door", Vector3i(83,20,60))
	var hearth = _install(HEARTH, Vector3i(85,20,61))
	var bed = _install("base:furniture:log_bed", Vector3i(82,20,64))
	clock_node.season = "winter"
	clock_node.day = 1
	clock_node.hour = 12.0
	rooms._rebuild_all_rooms()
	rooms._on_hour_changed(12)
	fires.tick()
	_expect(not clock_node.is_night() and fires.work.size() == 0 and _fire_row(hearth) == "Cold · lit at dusk or at bedtime",
		"by day a bedroom's hearth waits cold for dusk or a sleeper")
	# No log anywhere: the tired dwarf goes straight to bed and leaves no job behind.
	worker.position = Vector3(83.5,21,56.5)
	worker.sleep = worker.SLEEP_THRESHOLD
	await _fire_tick()
	_expect(worker.is_sleeping() and fires.work.size() == 0 and hearth.fire_log.is_empty(), "with no log a tired dwarf just goes to bed")
	worker._wake_up()
	# A log by the door: the tired dwarf lights the hearth with it first, then goes to bed.
	drops.spawn_drop(PINE, 1, Vector3i(86,21,57))
	worker.position = Vector3(83.5,21,56.5)
	worker.sleep = worker.SLEEP_THRESHOLD
	var lit_awake := false
	for i in 900:
		if worker.is_sleeping() and worker._rest_behavior.state == "sleeping": break
		lit_awake = lit_awake or (not hearth.fire_log.is_empty() and not worker.is_sleeping())
		await _fire_tick()
	_expect(lit_awake and hearth.fire_log == PINE and _loose(PINE) == 0, "a tired dwarf lights the cold bedroom's hearth with a real log before bed")
	_expect(worker.is_sleeping() and worker._rest_behavior.state == "sleeping" and worker._rest_behavior.bed_rest.bed == bed, "then sleeps in the bed beside it")
	fires.rooms_changed()
	fires.tick()
	_expect(hearth.fire_log == PINE and _fire_row(hearth) == "Burning while a dwarf sleeps here", "by day the fire burns on while its sleeper sleeps")
	worker.sleep = 1.0 # a whole night's rest: waking keeps the meter it filled
	worker._wake_up()
	fires.tick()
	_expect(hearth.fire_log.is_empty() and fires.work.size() == 0 and _loose(PINE) == 0, "by day it goes out when its sleeper wakes, the log spent")


func _night(season: String, rooms: Node, fires: RefCounted) -> void:
	clock_node.season = season
	clock_node.day = 1
	clock_node.hour = 23.0
	rooms._on_hour_changed(23)
	fires.tick()


func _install(key: String, origin: Vector3i, yaw := 0):
	furniture._install(key, furniture.get_defs()[key], origin, yaw)
	return furniture._installed[furniture._next_installed_id - 1]


func _set_hour(hour: float) -> void:
	clock_node.season = "summer"
	clock_node.day = 1
	clock_node.hour = hour


func _fire_tick() -> void:
	furniture.get_fires().tick()
	furniture.get_fires().update_leases()
	tasks._run_scheduler()
	worker._process(.05)
	await process_frame


func _lit_visuals(piece) -> bool:
	var light: Light3D = piece.node.get_node_or_null("FurnitureLight")
	var flame: Node3D = piece.node.find_child(String(piece.def.light_source.emissive_mesh), true, false)
	return light != null and light.visible and flame != null and flame.visible


func _rows(piece) -> Dictionary:
	var result := {}
	for row in furniture.get_explorer_data("installed:%d" % piece.installed_id).get("rows", []): result[row[0]] = row[1]
	return result


func _fire_row(piece) -> String:
	return String(_rows(piece).get("Fire", ""))


func _loose(key: String) -> int:
	return drops._loose.values().count(key)
