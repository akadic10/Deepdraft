extends "res://scripts/tests/TreeFellingTest.gd"

## Fishing (doc 289), in the flat test world: a pond marked as the lake, a channel marked as the
## river with its water two blocks below the bank, and a pool the colony dug. Step 1: the spot
## rules, a zone and its leases, a real dwarf's catch landing at its feet and coming off the
## stock, the fishing pose and its sounds, Keep pausing the work, a fished-out water, regrowth
## by the day, a release mid-cast losing nothing, the zone's window, saves and a real drag.
## Step 2: each water's fish, the bank's reach, honest refusals, seasons and Wisdom.
const PERCH := "base:resources:fish:perch"
const TROUT := "base:resources:fish:trout"
const SHORE_X := 49
var fishing: Node
var water: Node


func _run() -> void:
	create_timer(120).timeout.connect(func(): push_error("Fishing test timed out"); quit(1))
	_setup_fixture()
	root.get_node("StockpileManager").set_process(false)
	_pond()
	fishing = load("res://scripts/systems/FishingSystem.gd").new()
	fishing.name = "Fishing"
	fishing.window_manager_path = NodePath("../Windows")
	scene.add_child(fishing)
	fishing.set_process(false)
	fishing.config.waters.lake.stock_per_cell = 3.0   # the pond's 64 columns hold 192 fish
	fishing.config.catch_hours = 0.1
	await process_frame
	# The spot rules.
	_expect(fishing.spot_reason(Vector3i(SHORE_X, 20, 33)) == "", "a dry shore cell beside the lake is a spot")
	_expect(fishing.spot_reason(Vector3i(40, 20, 33)) == "No water in front", "a cell away from the water is refused")
	_expect(fishing.spot_reason(Vector3i(69, 20, 30)) == "This water has no fish", "water the colony dug has no fish, and the tool says so")
	_expect(fishing.spot_reason(Vector3i(61, 22, 33)) == "" and fishing.water_of_spot(Vector3i(61, 22, 33)) == "river"
		and fishing.water_in_front(Vector3i(61, 22, 33)) == Vector3i(63, 20, 33), "a river bank reaches water two blocks below it")
	var generator := root.get_node("WorldGenerator")
	generator.tarn_columns[Vector2i(100, 100)] = true
	generator.spring_cave = {"water": {Vector3i(101, 30, 100): 1000}}
	_expect(fishing.water_of_cell(Vector3i(100, 25, 100)) == "tarn" and fishing.water_of_cell(Vector3i(101, 30, 100)) == "spring_cave"
		and fishing.water_of_cell(Vector3i(101, 40, 100)) == "" and fishing.water_of_cell(Vector3i(52, 20, 33)) == "lake",
		"a cast cell's water: the tarn, the cave's pool at its own depth only, the lake")
	generator.tarn_columns.erase(Vector2i(100, 100))
	generator.spring_cave = {}
	fishing._pool.clear()
	_expect(fishing.water_item("river") == TROUT and fishing.water_item("tarn") == "base:resources:fish:char"
		and fishing.water_item("spring_cave") == "base:resources:fish:cave_fish", "each water has its own fish")
	_expect(fishing.spot_reason(Vector3i(52, 19, 33)) == "Fishers stand on the shore, not in the water", "the lake's own cells are refused")
	_expect(fishing.water_in_front(Vector3i(SHORE_X, 20, 33)) == Vector3i(51, 20, 33), "the float lands two blocks out, in water deep enough")
	# A zone of four spots posts four leases.
	var cells: Array[Vector3i] = []
	for z in range(31, 35): cells.append(Vector3i(SHORE_X, 20, z))
	var zone_id: int = fishing.create_zone(cells)
	_expect(zone_id == 1 and fishing.maximum("lake") == 192 and fishing.stock_word("lake") == "Plenty", "a zone on the lake, its stock from the lake's size")
	_expect(_pending_fish() == 4, "every spot of a zone that wants fish posts one lease: %d" % _pending_fish())
	_expect(not fishing.create_zone(cells) > 0, "spots never belong to two zones")
	# A real dwarf fishes a perch.
	worker = _worker(501, Vector3i(SHORE_X - 6, 20, 33))
	_expect(await _until_fishing(), "a Ranger walks to a spot and casts")
	var inspection = load("res://scripts/components/DwarfInspection.gd")
	_expect(inspection.describe(worker).activity == "Fishing" and inspection.roster_state(worker).summary == "Fishing", "the inspector says Fishing")
	var rod: Node3D = worker._rig.fishing_pose.tool if worker._rig.get("fishing_pose") != null else null
	_expect(is_instance_valid(rod) and rod.visible and rod.get_parent() == worker._hand_r, "the rod is in the right hand")
	var spot = fishing.spot_at(worker.current_cell())
	var before: float = fishing.stock("lake")
	var sounds: Array = []
	camera.set_meta("work_focus", Vector3(spot.origin) + Vector3(.5, 1, .5))
	camera.set_meta("work_zoom", 12.0)
	root.get_node("WorkFeedback").sound_started.connect(func(kind, _at, _voice): sounds.append(kind))
	_expect(await _until_perch(1), "the catch lands")
	_expect("fish_plop" in sounds and "fish_bite" in sounds and "fish_land" in sounds, "the float plops; the bite and the landing splash: %s" % [sounds])
	_expect(_perch_at(spot.origin + Vector3i.UP) == 1, "the perch lies at the fisher's feet")
	_expect(absf(fishing.stock("lake") - (before - 1.0)) < 0.01, "the catch comes off the lake's stock")
	# A release mid-cast loses nothing and frees the spot.
	_expect(await _until_fishing(), "the Ranger casts again")
	spot = fishing.spot_at(worker.current_cell())
	worker._process(.5)
	var partial: float = spot.state.work_seconds
	worker.force_interrupt()
	_expect(spot.reserved_by < 0 and spot.state.work_seconds == partial and _perch_count() == 1, "a release keeps the cast's progress and lands nothing")
	_expect(not is_instance_valid(rod) or not rod.visible, "the rod is put away")
	# Keep: once the colony keeps enough fish, the zone stops posting work.
	fishing.step_keep(zone_id, -4)   # 20 -> 0
	fishing.step_keep(zone_id, 1)    # -> 5
	_expect(int(fishing.zone_data(zone_id).keep) == 5, "Keep steps by five")
	for i in range(5): drops.spawn_drop(PERCH, 1, Vector3i(30, 21, 30 + i))
	fishing.refresh_work()
	_expect(not fishing.wants_fish(zone_id) and _pending_fish() == 0, "with Keep met the zone withdraws its waiting leases")
	fishing.step_keep(zone_id, 2)
	fishing.refresh_work()
	_expect(fishing.wants_fish(zone_id) and _pending_fish() > 0, "a higher Keep starts the work again")
	# A fished-out water posts nothing; it regrows by the day.
	fishing._stocks.lake.fish = 10.0
	_expect(fishing.fished_out("lake") and fishing.stock_word("lake") == "Fished out" and not fishing.wants_fish(zone_id), "below a tenth the water is fished out")
	var day: float = clock_node.elapsed_days()
	fishing._stocks.lake.day = day - 2.0
	_expect(absf(fishing.stock("lake") - (10.0 + 192 * 0.03 * 2.0)) < 0.05, "it regrows 3% of its maximum a day")
	# The window shows the zone.
	fishing._stocks.lake = {"fish": 150.0, "day": clock_node.elapsed_days()}
	var data: Dictionary = fishing.zone_data(zone_id)
	_expect(data.water == "Lowland lake" and data.fish_name == "Perch" and data.word == "Plenty" and data.stock == 150 and data.maximum == 192 and data.spots == 4, "the zone's window data")
	var panel = load("res://scripts/ui/FishingZonePanel.gd").new()
	scene.add_child(panel)
	panel.show_zone(data)
	_expect(panel._water.text == "Lowland lake" and panel._word.text == "Plenty · 150 of 192" and panel._keep.text == "15 fish", "the window reads the zone")
	# Saves.
	var saved: Dictionary = JSON.parse_string(JSON.stringify(fishing.serialize_state()))
	var Validator = load("res://scripts/components/SaveSnapshotValidator.gd")
	_expect(Validator._validate(saved, Validator.SCENE.fishing, "save.scene.fishing", {}).is_empty(), "the section matches the save's rules")
	fishing.restore_state(saved)
	_expect(fishing.zone_ids() == [zone_id] and int(fishing.zone_data(zone_id).keep) == 15 and absf(fishing.stock("lake") - 150.0) < 0.01, "zones, Keep and stock survive a save")
	_expect(_pending_fish() > 0, "a restored zone posts its work again")
	_expect(fishing.order_is_pending({"zone_id": zone_id}) and fishing.undo_order({"zone_id": zone_id}) == 4, "the tool bar's Undo takes the zone back")
	_expect(fishing.zone_ids().is_empty() and _pending_fish() == 0 and not fishing.is_zone_cell(cells[0]), "removing a zone takes its spots and leases")
	_expect(bool(drops.get_item_def(PERCH).food.edible), "perch are food")
	# Step 2: a river zone gives trout; winter halves the bite rate; Wisdom speeds the work.
	fishing.config.waters.river.stock_per_cell = 4.0   # the channel's 16 columns hold 64 trout
	var river_cells: Array[Vector3i] = [Vector3i(61, 22, 32), Vector3i(61, 22, 33)]
	var river_zone: int = fishing.create_zone(river_cells)
	_expect(river_zone > 0 and fishing.zone_data(river_zone).water == "River" and fishing.zone_data(river_zone).fish_name == "Trout"
		and fishing.maximum("river") == 64 and fishing.spot_at(river_cells[0]).item == TROUT, "a river zone fishes trout from the river's own stock")
	clock_node.season = "spring"
	var spring_time: float = fishing._catch_seconds(fishing.spot_at(river_cells[0]))
	clock_node.season = "winter"
	var winter_time: float = fishing._catch_seconds(fishing.spot_at(river_cells[0]))
	clock_node.season = "summer"
	_expect(absf(winter_time / spring_time - 2.0) < 0.01, "winter bites come at half speed: %.1f s against %.1f s" % [winter_time, spring_time])
	worker.stats["base:stat:wisdom"] = 5
	_expect(is_equal_approx(worker.work_rate("fishing"), 1.12), "Excellent Wisdom fishes 12% faster")
	worker.stats["base:stat:wisdom"] = 3
	fishing.remove_zone(river_zone)
	# A real drag past the object explorer, which takes any world click unless it knows the tool
	# (the doc 23 Copy lesson): the main scene lists the tool, and the tool takes the drag.
	var state: SceneState = (load("res://scenes/main/debug_world.tscn") as PackedScene).get_state()
	_expect(_explorer_lists(state, NodePath("../FishingSystem")), "the main scene lists FishingSystem among the explorer's click tools")
	explorer._tools.append(fishing)
	_aim_above(Vector3(SHORE_X, 20, 36))
	await process_frame
	fishing.activate()
	var from: Vector2 = camera.unproject_position(Vector3(SHORE_X + .5, 21, 35.5))
	var to: Vector2 = camera.unproject_position(Vector3(SHORE_X + .5, 21, 37.5))
	_mouse_motion(from)
	_mouse_button(from, true)
	_mouse_motion(to)
	_mouse_button(to, false)
	await process_frame
	var painted: Array = fishing.zone_ids()
	_expect(painted.size() == 1 and fishing.zone_data(painted[0]).spots == 3, "a real drag along the shore paints a zone of three spots")
	fishing.deactivate()
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("FISHING_OK: spots, zone leases, a real catch, the pose, release, Keep, fished out, regrowth, the window and saves")
	quit(0 if failures.is_empty() else 1)


## A pond 8 × 8, its water 0.75 deep in the top layer, marked as the lowland lake; a channel two
## wide in the top layer, marked as the river, under a bank built two blocks above its water; and
## a pool two by two in the top layer that no generated water claims. (The fixture has no
## terrain noise, so it carves only the top layer and builds upward.)
func _pond() -> void:
	var generator := root.get_node("WorldGenerator")
	var stone: int = blocks.get_id("base:terrain:rock:rock01")
	var geometry := {}
	for x in range(50, 58):
		for z in range(30, 38):
			world.set_block(x, 20, z, blocks.AIR_ID)
			geometry[Vector2i(x, z)] = [Vector2i(20, 128)]
			generator.lake_columns[Vector2i(x, z)] = true
	generator.river_layout = {"columns": {}}
	for x in range(62, 64):
		for z in range(30, 38):
			world.set_block(x, 20, z, blocks.AIR_ID)
			geometry[Vector2i(x, z)] = [Vector2i(20, 128)]
			generator.river_layout.columns[Vector2i(x, z)] = true
	for z in range(30, 38):
		for y in range(21, 23): world.set_block(61, y, z, stone)
	for x in range(70, 72):
		for z in range(30, 32):
			world.set_block(x, 20, z, blocks.AIR_ID)
			geometry[Vector2i(x, z)] = [Vector2i(20, 128)]
	water = root.get_node("WaterManager")
	water.flow = load("res://scripts/components/WaterFlow.gd").new()
	water.flow.spans_at = func(column: Vector2i): return geometry.get(column, [Vector2i(21, 128)])
	water.initialized = true
	water.set_process(false)   # the fixture owns fixed water, as DuckWildlifeTest's does
	for column: Vector2i in geometry: water.flow.seed_column(Vector3i(column.x, int(geometry[column][0].x), column.y), .75)


func _explorer_lists(state: SceneState, path: NodePath) -> bool:
	for i in range(state.get_node_count()):
		if state.get_node_name(i) != "ObjectExplorerController": continue
		for p in range(state.get_node_property_count(i)):
			if state.get_node_property_name(i, p) == "click_tool_paths": return path in (state.get_node_property_value(i, p) as Array)
	return false


## A Ranger: fishing is the Ranger's work (doc 292).
func _worker(id: int, cell: Vector3i) -> Node3D:
	var factory = load("res://scripts/entities/DwarfFactory.gd").new()
	var data: Dictionary = factory.generate(id, {})
	data.profession = "base:profession:ranger"
	var agent = factory.spawn(data, id)
	scene.add_child(agent)
	agent.position = Vector3(cell) + Vector3(.5, 1, .5)
	agent.set_process(false)
	tasks.register_dwarf(agent)
	return agent


func _pending_fish() -> int:
	var count := 0
	for cell: Vector3i in [Vector3i(SHORE_X, 20, 31), Vector3i(SHORE_X, 20, 32), Vector3i(SHORE_X, 20, 33), Vector3i(SHORE_X, 20, 34)]:
		var spot = fishing.spot_at(cell)
		if spot == null or spot.lease_id < 0: continue
		var task: Task = tasks.get_task(spot.lease_id)
		if task != null and task.status == Task.Status.PENDING: count += 1
	return count


func _until_fishing() -> bool:
	for i in range(1500):
		tasks._run_scheduler()
		worker._process(.1)
		if worker._task_phase == worker.TaskPhase.FELL_WORKING:
			var task: Task = tasks.get_task(worker.current_task_id)
			if task != null and task.type == Task.Type.FISH: return true
		if i % 30 == 0: await process_frame
	return false


func _until_perch(count: int) -> bool:
	for i in range(1500):
		tasks._run_scheduler()
		worker._process(.1)
		if _perch_count() >= count: return true
		if i % 30 == 0: await process_frame
	return false


func _perch_count() -> int:
	return _item_count(PERCH)


func _perch_at(cell: Vector3i) -> int:
	var count := 0
	for node: Node3D in drops._loose:
		if drops._loose[node] == PERCH and Vector3i(node.global_position.floor()) == cell: count += 1
	return count
