extends "res://scripts/tests/ObjectExplorerTest.gd"

const ACORN := "base:resources:seed:oak_acorn"
const LOG := "base:resources:wood:oak_log"
const STONE := "base:resources:stone:rough_stone"
var worker
var drops
var tasks
var clock_node
var stockpiles
var zone


func _setup_fixture() -> void:
	for id in ["SaveManager", "RoomManager", "TaskManager", "StockpileManager", "WorldClock"]:
		root.get_node(id).set_process(false)
	tasks = root.get_node("TaskManager")
	stockpiles = root.get_node("StockpileManager")
	clock_node = root.get_node("WorldClock")
	clock_node.set_paused(false)
	clock_node.set_speed(1)
	root.get_node("WorldGenerator").world_seed = 1234
	world = root.get_node("WorldData")
	blocks = root.get_node("BlockRegistry")
	_build_floor()
	scene = Node3D.new()
	root.add_child(scene)
	current_scene = scene
	await _new_trip()


func _new_trip(key := ACORN, amount := 12) -> void:
	tasks.reset_runtime_state()
	stockpiles.reset_runtime_state()
	if is_instance_valid(worker): worker.free()
	if is_instance_valid(drops): drops.free()
	drops = load("res://scripts/systems/ItemDropManager.gd").new()
	scene.add_child(drops)
	stockpiles._process(0)
	var factory = load("res://scripts/entities/DwarfFactory.gd").new()
	var data: Dictionary = factory.generate(141, {})
	if key in [LOG, STONE]:
		data.gender = "male"
		data.appearance.gender = "male"
		data.appearance.beard_style = "full_long"
		data.appearance.hair_style = "short_back"
		data.appearance.age_tier = "elder"
	worker = factory.spawn(data, 141)
	scene.add_child(worker)
	worker.position = Vector3(40.5, 21, 39.5)
	worker.set_process(false)
	worker.sleep = 1.0
	tasks.register_dwarf(worker)
	zone = load("res://scripts/components/StockpileZoneComponent.gd").new()
	var cells: Array[Vector3i] = [Vector3i(40,20,44), Vector3i(41,20,44), Vector3i(42,20,44), Vector3i(43,20,44)]
	zone.setup(1, cells)
	stockpiles.register_zone(zone)
	drops.restore_loose_item(key, Vector3(40.5,21,40.65), 0, amount)
	await process_frame


func _until(phase: int, limit := 600) -> bool:
	for i in range(limit):
		if worker._task_phase == phase: return true
		zone.update_leases()
		tasks._run_scheduler()
		worker._process(.04)
		await process_frame
	return false


func _loose_units() -> int:
	var total := 0
	for node in drops._loose: total += drops.quantity_of(node)
	return total


func _snapshot_units() -> int:
	var total := 0
	for entry in drops.serialize_state().loose: total += int(entry.count)
	for entry in worker.serialize_state().carried_items: total += int(entry.count)
	return total


func _check_grip() -> void:
	var pose = worker._carry_pose
	var node: Node3D = worker._carried_entries[0][0]
	var box: AABB = node.transform * pose.item_bounds(node)
	if worker._carried_entries.size() > 1:
		var second: Node3D = worker._carried_entries[1][0]
		box = box.merge(second.transform * pose.item_bounds(second))
	var left: Vector3 = worker._hand_l.transform * pose.PALM
	var right: Vector3 = worker._hand_r.transform * pose.PALM
	_expect(is_equal_approx(left.x, box.end.x + .27) and is_equal_approx(right.x, box.position.x - .27), "fists bracket actual item width")
	_expect(is_equal_approx(left.z, box.get_center().z) and is_equal_approx(right.z, left.z), "both fists travel with the load")
	_expect(box.position.z >= 1.14, "load clears beard while carrying")


func _check_empty_pose() -> void:
	_expect(worker._carried_entries.is_empty(), "no cargo remains attached after interruption")
	_expect(worker._hand_r.scale.is_equal_approx(Vector3(-1,1,1)), "interruption preserves mirrored fist scale")
	for part in [worker._head, worker._body, worker._hand_l, worker._hand_r, worker._foot_l, worker._foot_r]:
		_expect(part.position.is_zero_approx() and part.rotation.is_zero_approx(), "interruption restores resting parts")


func _run() -> void:
	create_timer(80).timeout.connect(func(): push_error("Hauling animation test timed out"); quit(1))
	await _setup_fixture()
	_expect(await _until(worker.TaskPhase.HAUL_PICKUP), "real scheduler starts reach at loose item")
	var item: Node3D = drops._loose.keys()[0]
	var before: Transform3D = item.global_transform
	_expect(worker.current_cell() != drops.item_floor_cell(item), "pickup stands beside the item, not on it")
	worker._process(.1)
	_expect(item.get_parent() == drops and item.global_transform.is_equal_approx(before), "reach leaves source untouched before contact")
	_expect(_snapshot_units() == 12, "save before contact records goods once")
	var time: float = worker._handling_elapsed
	var hand: Transform3D = worker._hand_l.transform
	clock_node.set_paused(true)
	worker._process(5)
	_expect(worker._handling_elapsed == time and worker._hand_l.transform.is_equal_approx(hand), "pause freezes reach")
	clock_node.set_paused(false)
	clock_node.set_speed(2)
	worker._process(.02)
	_expect(is_equal_approx(worker._handling_elapsed, time + .04), "handling follows clock speed")
	clock_node.set_speed(1)
	worker._process(.2)
	_expect(worker.to_local(before.origin).z > .7, "pickup faces the item in front of the boots")
	_expect(worker._foot_l.position.is_zero_approx() and worker._foot_r.position.is_zero_approx(), "pickup keeps boots planted")
	_expect(item.get_parent() == worker and drops._loose.is_empty(), "contact takes item exactly once")
	_expect(_snapshot_units() == 12 and item.position.y < 1.0, "mid-lift save owns all goods without finishing lift")
	_expect(await _until(worker.TaskPhase.HAUL_TO_ZONE), "lift finishes before walking")
	worker._process(.1)
	_check_grip()
	var walk_position: Vector3 = worker.position
	clock_node.set_paused(true)
	worker._process(2)
	_expect(worker.position == walk_position, "pause freezes carried travel")
	clock_node.set_paused(false)
	worker.apply_slice(19)
	_expect(not item.is_visible_in_tree(), "slice hides carried item with dwarf")
	worker.apply_slice(127)
	_expect(await _until(worker.TaskPhase.HAUL_DEPOSIT), "arrival starts lowering")
	_expect(worker.current_cell() != Vector3i(40,20,44), "delivery stands beside the reserved storage cell")
	worker._process(.3)
	_expect(worker.to_local(worker._handling_target).z > .9, "ground delivery lowers the load in front of the boots")
	_expect(zone.stored_count() == 0 and _snapshot_units() == 12, "lowering retains cargo until commit")
	worker._process(.5)
	_expect(zone.stored_count() == 12 and worker._carried_entries.is_empty(), "set-down commits correct quantity once")
	_expect(drops.stored_node_at(Vector3i(40,20,44)) != null, "ground deposit uses reserved physical cell")

	# Every new interrupt boundary must conserve goods and release reservations.
	for stage in ["reach", "lift", "carry", "lower"]:
		await _new_trip()
		_expect(await _until(worker.TaskPhase.HAUL_PICKUP), stage + " begins")
		if stage == "reach": worker._process(.08)
		if stage == "lift": worker._process(.35)
		if stage == "carry": await _until(worker.TaskPhase.HAUL_TO_ZONE)
		if stage == "lower":
			await _until(worker.TaskPhase.HAUL_DEPOSIT)
			worker._process(.3)
		tasks.cancel_task(worker.current_task_id)
		_check_empty_pose()
		_expect(_loose_units() == 12 and drops._reserved.is_empty() and zone.reserved_cells.is_empty(), stage + " cancellation conserves goods and frees claims")

	await _new_trip()
	await _until(worker.TaskPhase.HAUL_PICKUP)
	worker._process(.35)
	worker.dev_make_tired()
	worker._process(.01)
	_expect(worker.is_sleeping() and _loose_units() == 12, "sleep interrupts mid-lift safely")
	_check_empty_pose()

	# Four one-point rocks fill the configured carry budget.
	await _new_trip(STONE, 1)
	for i in range(3): drops.restore_loose_item(STONE, Vector3(40.5+i,21,41.5))
	_expect(await _until(worker.TaskPhase.HAUL_TO_ZONE), "four separate pickups reach carrying phase")
	_expect(worker._carried_entries.size() == 4 and _snapshot_units() == 4, "bundle contains all four physical items")
	_check_grip()
	# Approach from the occupied side of this four-cell row; the nearest
	# neighbour of the first slot is another item destination, not a safe stand.
	worker._clear_path()
	worker.position = Vector3(42.5,21,44.5)
	worker._haul_walk_current()
	await _until(worker.TaskPhase.HAUL_DEPOSIT)
	for token in zone._pulls[worker.dwarf_id].cargo.values():
		_expect(worker.current_cell() != token.slot, "delivery stand excludes every destination in the bundle")
	worker._process(2)
	_expect(zone.stored_count() == 4 and zone.cell_stacks.size() == 4, "bundle delivery uses four reserved cells")

	await _new_trip(ACORN, 7)
	zone.tile_cells.resize(1)
	zone.cell_stacks[Vector3i(40,20,44)] = {"item": ACORN, "count": 22}
	drops.restore_stored_item(ACORN, Vector3i(40,20,44), 22)
	await _until(worker.TaskPhase.HAUL_PICKUP)
	worker._process(.35)
	_expect(_loose_units() == 5 and worker.serialize_state().carried_items[0].count == 2, "contact splits only reserved crate quantity")
	await _until(worker.TaskPhase.HAUL_DEPOSIT)
	worker._process(1)
	_expect(zone.stored_count() == 24 and _loose_units() == 5, "partial refill preserves remainder")

	await _test_fetch_from_stockpile()
	await _test_container_deposit()
	await _test_blocked_approach()
	for failure in failures: push_error(failure)
	if failures.is_empty():
		print("HAULING_ANIMATION_OK: contact ownership, bounds grips, pickup/carry/lower, pause/speed, slice, cancel/sleep, save counts, four-item bundle, partial crates, stockpile fetch")
	quit(0 if failures.is_empty() else 1)


func _test_fetch_from_stockpile() -> void:
	await _new_trip(LOG, 1)
	for node in drops._loose.keys():
		drops.take(node)
		node.free()
	# Use the real furniture ghost's storage-withdraw path.
	var key := "base:resources:furniture:barrel"
	var loader = load("res://scripts/systems/FurniturePlacementController.gd").new()
	loader._load_defs()
	var defs: Dictionary = loader.get_defs()
	loader.free()
	if not defs.has("base:furniture:barrel"):
		_expect(false, "barrel definition available")
		return
	key = String(defs["base:furniture:barrel"].item_key)
	zone.cell_stacks[Vector3i(40,20,44)] = {"item": key, "count": 1}
	drops.restore_stored_item(key, Vector3i(40,20,44))
	stockpiles._totals[key] = 1
	var ghost = load("res://scripts/components/FurnitureGhostComponent.gd").new()
	ghost.setup(1, "base:furniture:barrel", defs["base:furniture:barrel"], Vector3i(45,20,44), 0)
	ghost.source_id = tasks.allocate_source_id()
	ghost.drop_manager = drops
	tasks.register_work_source(ghost.source_id, ghost)
	var built := [false]
	ghost.install_callback = func(_ghost): built[0] = true
	ghost.update_lease()
	_expect(await _until(worker.TaskPhase.FETCH_PICKUP), "builder reaches item withdrawn from stockpile")
	_expect(worker.current_cell() != Vector3i(40,20,44), "withdrawn stockpile item is picked up from beside its cell")
	worker._process(.35)
	_expect(worker._fetch_picked_up and _snapshot_units() == 1 and zone.stored_count() == 0, "fetch contact transfers withdrawn item once")
	_expect(await _until(worker.TaskPhase.FETCH_TO_GHOST), "builder carries with same lift")
	_check_grip()
	_expect(await _until(worker.TaskPhase.FETCH_DEPOSIT), "builder lowers item before installation")
	worker._process(1)
	_expect(built[0] and worker._carried_entries.is_empty(), "construction consumes held item after set-down")


func _test_container_deposit() -> void:
	await _new_trip(LOG, 1)
	stockpiles.deregister_zone(zone)
	var container = load("res://scripts/components/ContainerStorageComponent.gd").new()
	var cells: Array[Vector3i] = [Vector3i(40,20,44)]
	container.setup_container({"storage": {"capacity": 8}}, cells)
	container.source_id = tasks.allocate_source_id()
	stockpiles.register_container(container)
	zone = container
	_expect(await _until(worker.TaskPhase.HAUL_DEPOSIT), "container starts visible handoff")
	worker._process(.3)
	_expect(container.stored_count() == 0 and _snapshot_units() == 1, "container waits for handoff before absorbing goods")
	worker._process(1)
	_expect(container.stored_count() == 1 and worker._carried_entries.is_empty(), "container deposit commits once")
	# Removing the destination during reach must leave the reserved item loose.
	await _new_trip()
	await _until(worker.TaskPhase.HAUL_PICKUP)
	stockpiles.deregister_zone(zone)
	_expect(_loose_units() == 12 and drops._reserved.is_empty(), "destination deletion during reach releases item")
	_check_empty_pose()


func _test_blocked_approach() -> void:
	await _new_trip()
	worker.position = Vector3(40.5,21,37.5)
	# Block the nearest side. A different cardinal approach must still work.
	for y in range(21,24): world.set_block(40,y,39,blocks.get_id("base:terrain:rock:rock01"))
	await process_frame
	_expect(await _until(worker.TaskPhase.HAUL_PICKUP), "pickup finds another side when the nearest one is blocked")
	var stand: Vector3i = worker.current_cell()
	_expect(stand != Vector3i(40,20,39) and stand != Vector3i(40,20,40), "alternate approach keeps the worker off the item cell")
	worker._process(.3)
	_expect(worker.to_local(worker._handling_world_start.origin).z > .7, "alternate approach turns toward the item before contact")
	tasks.cancel_task(worker.current_task_id)
	for y in range(21,24): world.set_block(40,y,39,blocks.AIR_ID)
	await process_frame
