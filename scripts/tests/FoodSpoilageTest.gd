extends "res://scripts/tests/WorkerCraftingTest.gd"

## Food spoilage (doc 42 "Spoilage"; doc 282 phase 2) on the fixture's open plain at Y20:
## - speed: 1 at 20°C under a roof and x2.5 for every 10°C; frozen nearly stops under a roof;
##   the open sky adds 1, and 1.5 in rain, frozen or not;
## - a pass adds hours x speed / (24 x keeps_days) to stored, loose and carried food, and a
##   stored crate shows its stack's spoil;
## - splitting copies spoil, and putting goods together averages it by count;
## - crates further apart in spoil than 0.25 stay apart: a deposit takes a crate of like
##   freshness, else an empty cell, and only with none left the crate closest in freshness;
##   fresh harvest starts its own loose crate, and a basket collects only like crates;
## - at 1 the unclaimed units rot, with one Events line for each food in each place, and Events
##   warns as a stack passes 75%; claimed portions and food in hand stay until used;
## - spoil saves with loose goods and carried goods (SaveManagerRoundTripTest: stored stacks);
## - a meal takes older food first, within the route margin;
## - the readouts: a food crate's tag says Fresh, Spoiling, Going bad or Frozen with its days
##   left, in its tone; the storage window's Keeping list gives each food's stalest crate;
## - the hourly pass runs over frames when the clock passes an hour, a little each frame.
const BLUEBERRY := "base:resources:flora:blueberry"
const APPLE := "base:resources:flora:apple"
const ELDERBERRY := "base:resources:flora:elderberry"
const YARD := Vector3i(30, 21, 30)
var rooms
var spoilage
var events
var weather
var stone: int
var cells: Array[Vector3i] = [Vector3i(40, 20, 44), Vector3i(41, 20, 44), Vector3i(42, 20, 44), Vector3i(43, 20, 44)]


func _run() -> void:
	create_timer(120).timeout.connect(func(): push_error("Food spoilage timed out"); quit(1))
	await _setup_crafting_fixture()
	for node in drops._loose.keys(): drops.take(node); node.free()
	clock_node.set_paused(true)
	rooms = root.get_node("RoomManager")
	events = root.get_node("EventLog")
	weather = root.get_node("WeatherManager")
	spoilage = stockpiles.spoilage
	stone = blocks.get_id("base:terrain:rock:rock01")
	weather.set_weather("base:weather:clear")
	_at("summer", 14.0)
	_speeds()
	_gains()
	_merging()
	_kept_apart()
	_rotting()
	_saves()
	_eating_order()
	_readouts()
	await _hourly()
	for failure: String in failures: push_error(failure)
	print("FOOD_SPOILAGE_OK: speeds, gains, merging, crates kept apart, rotting, warnings, claims, saves, eating order, readouts and the hourly pass"
		if failures.is_empty() else "FOOD_SPOILAGE_FAIL")
	quit(0 if failures.is_empty() else 1)


func _speeds() -> void:
	var t: float = rooms.temperature_at(YARD)
	_expect(is_equal_approx(spoilage.speed_at(YARD), pow(2.5, (t - 20.0) / 10.0) + 1.0),
		"the open sky adds 1 to the temperature's speed: %.3f at %.1f°C" % [spoilage.speed_at(YARD), t])
	weather.set_weather("base:weather:rain")
	t = rooms.temperature_at(YARD)
	_expect(is_equal_approx(spoilage.speed_at(YARD), pow(2.5, (t - 20.0) / 10.0) + 1.5), "rain adds 1.5")
	weather.set_weather("base:weather:clear")
	world.set_block(50, 24, 50, stone)
	var roofed := Vector3i(50, 21, 50)
	t = rooms.temperature_at(roofed)
	_expect(is_equal_approx(spoilage.speed_at(roofed), pow(2.5, (t - 20.0) / 10.0)), "under a roof only the temperature counts")
	var food: Dictionary = drops.food_definition(BLUEBERRY)
	_expect(is_equal_approx(spoilage.keeps_days_at(food, roofed), 4.0 / spoilage.speed_at(roofed)),
		"blueberries keep 4 days at 20°C, longer where it is cooler: %.1f days at %.1f°C" % [spoilage.keeps_days_at(food, roofed), t])
	_at("winter", 2.0)
	t = rooms.temperature_at(roofed)
	_expect(t <= 0.0 and is_equal_approx(spoilage.speed_at(roofed), 0.05), "frozen under a roof nearly stops: %.1f°C" % t)
	var open: float = spoilage.speed_at(YARD)
	_expect(open > 1.0 and open < 1.2, "the open sky still spoils frozen food: speed %.2f" % open)
	_at("summer", 14.0)
	world.set_block(50, 24, 50, blocks.AIR_ID)


## A pass adds hours x speed / (24 x keeps_days) wherever the food is.
func _gains() -> void:
	_store(cells[0], BLUEBERRY, 24)
	var speed: float = spoilage.speed_at(cells[0] + Vector3i.UP)
	drops.spawn_drop(APPLE, 6, YARD)
	var crate: Node3D = drops.loose_items()[0]
	var portion: Node3D = drops.create_item_visual(BLUEBERRY, 1)
	worker.add_child(portion)
	worker._carried_entries.append([portion, BLUEBERRY])
	drops.set_spoil(portion, 0.9)
	spoilage.run(24.0)
	var stack: Dictionary = zone.cell_stacks[cells[0]]
	_expect(is_equal_approx(float(stack.spoil), speed / 4.0) and float(stack.spoil) > 0.5,
		"a summer day in the yard costs blueberries half their life: %.3f" % float(stack.spoil))
	_expect(is_equal_approx(drops.spoil_of(drops.stored_node_at(cells[0])), float(stack.spoil)), "the stored crate shows its stack's spoil")
	_expect(is_equal_approx(drops.spoil_of(crate), spoilage.speed_at(YARD) / 15.0), "apples keep 15 days")
	_expect(drops.spoil_of(portion) == 1.0 and is_instance_valid(portion) and worker._carried_entries.size() == 1,
		"food in hand spoils but stays until used")
	worker._carried_entries.clear()
	portion.free()
	_clear()


## Splitting copies spoil; goods put together average it by count.
func _merging() -> void:
	drops.spawn_drop(APPLE, 6, YARD)
	var crate: Node3D = drops.loose_items()[0]
	drops.set_spoil(crate, 0.2)
	drops.spawn_drop(APPLE, 6, YARD)
	_expect(drops.quantity_of(crate) == 12 and is_equal_approx(drops.spoil_of(crate), 0.1), "fresh apples halve a crate's spoil when they double it")
	drops.reserve(crate, worker.dwarf_id)
	var part: Node3D = drops.take_quantity(crate, 2, worker.dwarf_id)
	_expect(is_equal_approx(drops.spoil_of(part), 0.1), "taking some copies the spoil")
	part.free()
	_store(cells[1], BLUEBERRY, 12, 0.6)
	var token: Dictionary = zone._reserve_deposit(BLUEBERRY, cells[1], worker.dwarf_id, 12)
	token["spoil"] = 0.0
	zone._commit_one(token, BLUEBERRY)
	_expect(token.slot == cells[1] and int(zone.cell_stacks[cells[1]].count) == 24 and is_equal_approx(float(zone.cell_stacks[cells[1]].spoil), 0.3),
		"a stack topped up with fresh fruit averages its spoil: %s" % [zone.cell_stacks[cells[1]]])
	var single: Node3D = zone.withdraw_stack(cells[1], 3, worker.dwarf_id)
	_expect(single != null and is_equal_approx(drops.spoil_of(single), 0.3), "a portion withdrawn from a stack copies its spoil")
	_clear()


## Crates of different freshness stay apart while room allows (merge_band 0.25).
func _kept_apart() -> void:
	drops.spawn_drop(APPLE, 6, YARD)
	var old: Node3D = drops.loose_items()[0]
	drops.set_spoil(old, 0.5)
	drops.spawn_drop(APPLE, 6, YARD)
	_expect(drops.quantity_of(old) == 6 and drops.loose_items().size() == 2, "fresh apples landing on a half-spoilt loose crate start their own")
	_clear()
	_store(cells[0], APPLE, 7, 0.9)
	var fresh: Dictionary = zone._reserve_deposit(APPLE, cells[0], worker.dwarf_id, 4, "", 0.0)
	_expect(fresh.slot == cells[1], "fresh apples go to an empty cell, not into a crate close to rotting: %s" % [fresh.slot])
	zone._release_deposit(fresh)
	var like: Dictionary = zone._reserve_deposit(APPLE, cells[0], worker.dwarf_id, 4, "", 0.8)
	_expect(like.slot == cells[0], "apples of like freshness top it up")
	zone._release_deposit(like)
	for cell: Vector3i in cells.slice(1): _store(cell, BLUEBERRY, 24)
	var last: Dictionary = zone._reserve_deposit(APPLE, cells[0], worker.dwarf_id, 4, "", 0.0)
	_expect(last.slot == cells[0], "with no empty cell left they top up the crate closest in freshness rather than wait outside")
	zone._release_deposit(last)
	_clear()
	# A hauler's basket collects only crates of like freshness on its way.
	drops.spawn_drop(APPLE, 6, Vector3i(40, 21, 40))
	var plan: Dictionary = zone.reserve_haul(worker.dwarf_id, worker.current_cell(), {})
	var side_cell := Vector3i(41, 20, 42)
	drops.spawn_drop(APPLE, 5, side_cell + Vector3i.UP)
	var side: Node3D = drops.loose_items().filter(func(node: Node3D) -> bool: return drops.item_floor_cell(node) == side_cell)[0]
	drops.set_spoil(side, 0.9)
	var route: Array[Vector3i] = [Vector3i(40, 20, 40), Vector3i(40, 20, 41), Vector3i(40, 20, 42), Vector3i(40, 20, 43)]
	var hauling: Dictionary = tasks.get_config_section("hauling")
	var budget = hauling.get("fruit_planning_budget_usec")
	hauling["fruit_planning_budget_usec"] = 200000
	_expect(not plan.is_empty() and not zone.plan_fruit_haul(worker.dwarf_id, route, {}), "a rotting crate on the way never joins a fresh basket")
	drops.set_spoil(side, 0.1)
	_expect(zone.plan_fruit_haul(worker.dwarf_id, route, {}) and drops.is_claimed(side), "a crate of like freshness does")
	if budget == null: hauling.erase("fruit_planning_budget_usec")
	else: hauling["fruit_planning_budget_usec"] = budget
	zone.cancel_haul(worker.dwarf_id)
	_clear()


## At 1 the unclaimed units rot, with Events lines; claimed ones stay.
func _rotting() -> void:
	_store(cells[0], BLUEBERRY, 24, 0.99)
	_store(cells[1], BLUEBERRY, 24, 0.74)
	spoilage.run(1.0)
	var lines := _new_lines(2)
	_expect(not zone.cell_stacks.has(cells[0]) and drops.stored_node_at(cells[0]) == null and stockpiles.get_total(BLUEBERRY) == 24,
		"a rotten stack goes, crate and count")
	_expect(lines.has("24 blueberries rotted in Stockpile 1.") and lines.has("Blueberries in Stockpile 1 are going bad: less than a day left."),
		"Events tells of the rot and warns of the stack passing 75%%: %s" % [lines])
	_clear()
	_store(cells[0], BLUEBERRY, 24, 0.99)
	var token: Dictionary = zone.reserve_portion(cells[0], BLUEBERRY, worker.dwarf_id)
	spoilage.run(1.0)
	_expect(not token.is_empty() and int(zone.cell_stacks[cells[0]].count) == 1 and drops.quantity_of(drops.stored_node_at(cells[0])) == 1
		and _new_lines(1) == ["23 blueberries rotted in Stockpile 1."], "a portion claimed for a meal stays; the rest of the stack rots")
	zone.release_outgoing(token)
	spoilage.run(1.0)
	_expect(not zone.cell_stacks.has(cells[0]) and _new_lines(1) == ["1 blueberry rotted in Stockpile 1."], "released, it rots at the next hour")
	drops.spawn_drop(APPLE, 5, YARD)
	var crate: Node3D = drops.loose_items()[0]
	drops.set_spoil(crate, 1.0)
	drops.reserve(crate, worker.dwarf_id)
	spoilage.run(1.0)
	_expect(is_instance_valid(crate) and drops.is_loose(crate), "a loose crate claimed for a haul stays")
	drops.unreserve(crate, worker.dwarf_id)
	spoilage.run(1.0)
	_expect(not drops.is_loose(crate) and _new_lines(1) == ["5 apples rotted on the ground."], "unclaimed, it rots where it lies")
	_clear()


## Spoil saves with loose goods and carried goods.
func _saves() -> void:
	drops.spawn_drop(APPLE, 4, YARD)
	var crate: Node3D = drops.loose_items()[0]
	drops.set_spoil(crate, 0.4)
	var saved: Array = JSON.parse_string(JSON.stringify(drops.capture_save_state())).loose
	_clear()
	drops.restore_state({"loose": saved})
	_expect(saved.size() == 1 and is_equal_approx(float(saved[0].spoil), 0.4) and is_equal_approx(drops.spoil_of(drops.loose_items()[0]), 0.4),
		"a loose crate's spoil saves and loads")
	_clear()
	var portion: Node3D = drops.create_item_visual(BLUEBERRY, 1)
	drops.set_spoil(portion, 0.55)
	worker.add_child(portion)
	worker._carried_entries.append([portion, BLUEBERRY])
	var state: Dictionary = JSON.parse_string(JSON.stringify(worker.serialize_state()))
	_expect(is_equal_approx(float(state.carried_items[0].spoil), 0.55), "food in hand saves its spoil")
	worker._carried_entries.clear()
	portion.free()


## A meal takes older food first, if it is not much farther.
func _eating_order() -> void:
	_store(cells[0], BLUEBERRY, 24)
	_store(cells[3], BLUEBERRY, 24, 0.8)
	var from := Vector3i(40, 20, 40)
	var margin := float(tasks.get_config_section("food").spoilage.route_margin_blocks)
	_expect(_quote(from, margin).get("cell") == cells[3], "the older stack three blocks farther is eaten first")
	_expect(_quote(from, 0.0).get("cell") == cells[0], "without the margin the nearest is")
	var far = load("res://scripts/components/StockpileZoneComponent.gd").new()
	var far_cells: Array[Vector3i] = [Vector3i(70, 20, 44)]
	far.setup(2, far_cells)
	stockpiles.register_zone(far)
	zone.cell_stacks.erase(cells[3])
	far.cell_stacks[far_cells[0]] = {"item": BLUEBERRY, "count": 24, "spoil": 0.8}
	_expect(_quote(from, margin).get("cell") == cells[0], "older food far beyond the margin waits")
	stockpiles.deregister_zone(far)
	_clear()


## The readouts (the owner's pick, doc 282): a food crate's status tag gives its freshness in
## its tone; the storage window's Keeping list gives each food's stalest crate, soonest first.
func _readouts() -> void:
	_store(cells[0], APPLE, 9, 0.12)
	_store(cells[1], BLUEBERRY, 17, 0.55)
	_store(cells[2], ELDERBERRY, 9, 0.86)
	_store(cells[3], APPLE, 20, 0.04)
	var tags: Array = [cells[0], cells[1], cells[2]].map(func(cell: Vector3i) -> Dictionary: return drops.get_explorer_data(drops.stored_node_at(cell)).status)
	_expect(String(tags[0].text).begins_with("Fresh · about ") and tags[0].tone == "fine" and String(tags[1].text).begins_with("Spoiling · ")
		and tags[1].tone == "waiting" and tags[2].text == "Going bad · less than a day left" and tags[2].tone == "blocked",
		"a food crate's tag says how fresh it is, in its tone: %s" % [tags])
	drops.spawn_drop(APPLE, 3, YARD)
	var loose: Node3D = drops.loose_items()[0]
	drops.set_disallowed(loose, true)
	_expect(drops.get_explorer_data(loose).status.text == "Disallowed: dwarves leave it here", "a disallowed crate still says so first")
	drops.discard(loose)
	var roofed := Vector3i(50, 21, 50)
	world.set_block(50, 24, 50, stone)
	_at("winter", 2.0)
	var frozen: Dictionary = spoilage.freshness(drops.food_definition(BLUEBERRY), 0.55, roofed)
	_expect(frozen.word == "Frozen" and frozen.tone == "waiting" and float(frozen.days) > 30.0, "under a roof below freezing it reads Frozen, in its spoil's tone: %s" % [frozen])
	_at("summer", 14.0)
	world.set_block(50, 24, 50, blocks.AIR_ID)
	var keeping = load("res://scripts/ui/StorageKeeping.gd").new()
	keeping.sizes = {"heading": 20, "hint": 16, "exact": 48, "heading_width": 150, "bar": 10, "gap": 8}
	var shown: bool = keeping.show_storage(zone)
	var keys: Array = keeping.rows.map(func(row: Dictionary) -> String: return String(row.key))
	var apple: Dictionary = keeping.rows[2] if keeping.rows.size() == 3 else {}
	_expect(shown and keys == [ELDERBERRY, BLUEBERRY, APPLE] and int(apple.get("count", 0)) == 9 and int(apple.get("total", 0)) == 29,
		"the Keeping list has a row a food, the soonest to rot first, each its stalest crate: %s" % [keeping.rows])
	_expect(String(keeping.heading).begins_with("Keeping · ") and String(keeping.heading).ends_with("°C under the open sky"),
		"its heading says how the store keeps food: %s" % keeping.heading)
	_clear()
	keeping.show_storage(zone)
	var last: Label = keeping.get_child(keeping.get_child_count() - 1)
	_expect(keeping.visible and keeping.rows.is_empty() and last.text.begins_with("Nothing here spoils yet. Blueberries would keep about "),
		"an empty store says how long blueberries would keep there: %s" % last.text)
	zone.set_all_accepted(false)
	_expect(not keeping.show_storage(zone) and not keeping.visible, "a store that takes no food shows no Keeping list")
	zone.set_all_accepted(true)
	keeping.free()
	var passes := [0]
	spoilage.passed.connect(func() -> void: passes[0] += 1)
	spoilage.run(1.0)
	_expect(passes[0] == 1, "each pass tells the readouts it is done")


## Passing an hour starts a pass; it goes a little each frame.
func _hourly() -> void:
	drops.spawn_drop(APPLE, 6, YARD)
	var crate: Node3D = drops.loose_items()[0]
	spoilage.clear()
	clock_node.hour_changed.emit(14)
	_expect(not spoilage.busy() and drops.spoil_of(crate) == 0.0, "the first hour after a load only sets the clock")
	clock_node.hour = 17.0
	clock_node.hour_changed.emit(17)
	_expect(spoilage.busy(), "three game hours later a pass starts")
	var frames := 0
	while spoilage.busy() and frames < 100:
		spoilage.tick()
		frames += 1
		await process_frame
	_expect(not spoilage.busy() and is_equal_approx(drops.spoil_of(crate), 3.0 * spoilage.speed_at(YARD) / (24.0 * 15.0)),
		"it adds the three hours: %.4f" % drops.spoil_of(crate))
	_clear()


func _quote(from: Vector3i, margin: float) -> Dictionary:
	var query := {}
	var keys: Array[String] = [BLUEBERRY]
	stockpiles.advance_material_quote(keys, from, query, Time.get_ticks_usec() + 1000000, {}, -1, "", "", margin)
	return query.best


func _store(cell: Vector3i, key: String, count: int, spoil := 0.0) -> void:
	zone.cell_stacks[cell] = {"item": key, "count": count}
	if spoil > 0.0: zone.cell_stacks[cell]["spoil"] = spoil
	drops.restore_stored_item(key, cell, count, "", false, "", spoil)
	stockpiles.rebuild_totals()


## Empties the zone and the ground.
func _clear() -> void:
	for cell: Vector3i in zone.cell_stacks.keys():
		var node: Node3D = drops.stored_node_at(cell)
		if node != null: node.free()
	zone.cell_stacks.clear()
	zone._outgoing.clear()
	for node: Node3D in drops.loose_items(): drops.discard(node)
	stockpiles.rebuild_totals()


## The texts of the newest Events lines, newest first.
func _new_lines(count: int) -> Array:
	return events.entries().slice(0, count).map(func(entry: Dictionary) -> String: return String(entry.text))


func _at(season: String, hour: float) -> void:
	clock_node.season = season
	clock_node.day = 1
	clock_node.hour = hour
	rooms._on_hour_changed(int(hour))
