extends "res://scripts/tests/HaulingAnimationTest.gd"

const ORE := "base:resources:ore:iron"
const COAL := "base:resources:ore:coal"
const PACKED := "base:resources:furniture:barrel"
const OWNER := 901


func _run() -> void:
	create_timer(80).timeout.connect(func(): push_error("Hauling capacity test timed out"); quit(1))
	await _setup_fixture()
	_expect(zone.carry_capacity == 4, "ground storage receives JSON carry capacity")
	# More destination slots than cargo: limits must come from carrying capacity.
	for spec in [[STONE,5,4,1], [ORE,5,4,1], [COAL,5,4,1], [LOG,3,2,1],
			[ACORN,2,1,1], [ACORN,2,1,24], [PACKED,2,1,1]]:
		await _new_trip(spec[0], spec[3])
		_expand_zone()
		for i in range(1, spec[1]):
			drops.restore_loose_item(spec[0], Vector3(40.5+i*.2,21,40.65), 0, spec[3])
		var pull: Dictionary = zone.reserve_haul(OWNER, worker.current_cell(), {})
		_expect(pull.get("items", []).size() == spec[2], "%s carries %d physical objects" % [spec[0], spec[2]])
		if not pull.is_empty():
			_expect(_cost(pull.items) == 4, "single-type load fills four-point budget")
			var expected_speed: float = 1.0 if spec[0] in [ACORN, COAL] else zone.carry_speed_mult_heavy
			_expect(is_equal_approx(pull.carry_mult, expected_speed), "carry cost preserves independent light/heavy speed")
			_expect(drops._reserved.size() == spec[2], "only fitting items receive claims")
		zone.cancel_haul(OWNER)
		_expect(_loose_units() == spec[1]*spec[3] and drops._reserved.is_empty() and zone.reserved_cells.is_empty(), "cancel preserves goods and releases both claims")

	# A capped candidate list would miss these cheaper items beyond bulky crates.
	await _new_trip(STONE, 1)
	_expand_zone()
	for i in range(5): drops.restore_loose_item(PACKED, Vector3(40.5+(i+1)*.2,21,40.65))
	for i in range(3): drops.restore_loose_item(STONE, Vector3(42.5+i,21,40.65))
	var pull: Dictionary = zone.reserve_haul(OWNER, worker.current_cell(), {})
	_expect(pull.get("items", []).size() == 4 and _cost(pull.get("items", [])) == 4, "search skips five nearby crates to find three fitting rocks")
	for item in pull.get("items", []): _expect(drops.item_key_of(item) == STONE, "bulky candidate is not reserved")
	zone.cancel_haul(OWNER)

	await _test_data_driven_limits()
	await _test_container_budget()
	await _test_mixed_trip()
	await _new_trip(LOG, 1)
	for i in range(2): drops.restore_loose_item(LOG, Vector3(40.5+i,21,41.5))
	if await _until(worker.TaskPhase.HAUL_TO_ZONE):
		_expect(worker._carried_entries.size() == 2 and _snapshot_units() == 3, "real dwarf carries two logs and leaves the third")
		tasks.cancel_task(worker.current_task_id)
		_expect(_loose_units() == 3 and drops._reserved.is_empty() and zone.reserved_cells.is_empty(), "cancelled two-log trip restores all goods")
	else:
		_expect(false, "two-log trip reaches carry phase")
	for failure in failures: push_error(failure)
	if failures.is_empty():
		print("HAULING_CAPACITY_OK: JSON budget/costs, rocks/ore/logs/crates, mixed loads, candidate skipping, claims, custom capacity, containers, cancellation")
	quit(0 if failures.is_empty() else 1)


func _expand_zone() -> void:
	for x in range(44,48): zone.tile_cells.append(Vector3i(x,20,44))


func _cost(items: Array) -> int:
	var total := 0
	for item in items: total += int(drops.get_item_def(drops.item_key_of(item)).get("carry_cost", 1))
	return total


func _test_data_driven_limits() -> void:
	await _new_trip(STONE, 1)
	drops.restore_loose_item(STONE, Vector3(41.5,21,40.65))
	var def: Dictionary = drops.get_item_def(STONE)
	def.carry_cost = 3
	var pull: Dictionary = zone.reserve_haul(OWNER, worker.current_cell(), {})
	_expect(pull.get("items", []).size() == 1, "registry cost change controls selection without item-type branches")
	zone.cancel_haul(OWNER)
	# Registration uses the coordinator's loaded setting for both storage families.
	stockpiles._carry_capacity = 6
	stockpiles.register_zone(zone)
	_expect(zone.carry_capacity == 6, "zone receives changed carry capacity")
	pull = zone.reserve_haul(OWNER, worker.current_cell(), {})
	_expect(pull.get("items", []).size() == 2, "six-point budget fits two three-point objects")
	zone.cancel_haul(OWNER)
	stockpiles._carry_capacity = 4
	stockpiles.register_zone(zone)
	def.erase("carry_cost")
	pull = zone.reserve_haul(OWNER, worker.current_cell(), {})
	_expect(pull.get("items", []).size() == 2, "future definitions without a carry cost default to one")
	zone.cancel_haul(OWNER)
	def.carry_cost = 0
	zone.carry_capacity = 1
	pull = zone.reserve_haul(OWNER, worker.current_cell(), {})
	_expect(pull.get("items", []).size() == 1, "invalid zero cost cannot create a free load")
	zone.cancel_haul(OWNER)

	await _new_trip(LOG, 1)
	drops.get_item_def(LOG).carry_cost = 9
	zone.update_leases()
	_expect(zone._lease_ids.is_empty(), "oversized goods alone do not post impossible hauling work")
	drops.restore_loose_item(STONE, Vector3(42.5,21,40.65))
	pull = zone.reserve_haul(OWNER, worker.current_cell(), {})
	_expect(pull.get("items", []).size() == 1, "oversized nearest item does not block a fitting main item")
	if not pull.is_empty(): _expect(drops.item_key_of(pull.items[0]) == STONE, "fitting main item is chosen")
	zone.cancel_haul(OWNER)


func _test_container_budget() -> void:
	await _new_trip(LOG, 1)
	for i in range(2): drops.restore_loose_item(LOG, Vector3(40.5+i,21,41.5))
	stockpiles.deregister_zone(zone)
	var container = load("res://scripts/components/ContainerStorageComponent.gd").new()
	var cells: Array[Vector3i] = [Vector3i(40,20,44)]
	container.setup_container({"storage": {"capacity": 8}}, cells)
	container.source_id = tasks.allocate_source_id()
	stockpiles.register_container(container)
	_expect(container.carry_capacity == 4, "container receives JSON carry capacity")
	var pull: Dictionary = container.reserve_haul(OWNER, worker.current_cell(), {})
	_expect(pull.get("items", []).size() == 2, "container haul obeys same two-log limit")
	var carried: Array = []
	for i in range(pull.get("items", []).size()):
		var item: Node3D = container.take_item(OWNER, i)
		carried.append([item, drops.item_key_of(item)])
	_expect(container.commit_haul(OWNER, carried), "container commits reserved budgeted cargo")
	_expect(container.stored_count() == 2 and _loose_units() == 1 and container._reserved_slots == 0, "container delivery leaves third log available")


func _test_mixed_trip() -> void:
	await _new_trip(STONE, 1)
	drops.restore_loose_item(LOG, Vector3(40.5,21,41.5))
	drops.restore_loose_item(STONE, Vector3(41.5,21,40.5))
	drops.restore_loose_item(ACORN, Vector3(41.5,21,41.5), 0, 7)
	if not await _until(worker.TaskPhase.HAUL_TO_ZONE):
		_expect(false, "mixed load reaches carry phase")
		return
	var keys: Array = []
	for entry in worker._carried_entries: keys.append(entry[1])
	_expect(keys.count(STONE) == 2 and keys.count(LOG) == 1 and keys.size() == 3, "real dwarf lifts two rocks and one log")
	_expect(_loose_units() == 7 and _snapshot_units() == 10, "crate left behind and carried goods are both included in save snapshot")
	_expect(await _until(worker.TaskPhase.HAUL_DEPOSIT), "mixed load reaches stockpile handoff")
	worker._process(1)
	_expect(zone.stored_count() == 3 and _loose_units() == 7, "mixed load commits without moving the excluded crate")
	# Each completed load returns to matching; a solo hauler can still take
	# the remaining crate on a new trip without keeping private reservations.
	_expect(worker.current_task_id < 0 and drops._reserved.is_empty() and zone.reserved_cells.is_empty(), "completed load frees all claims before the next trip is assigned")
	_expect(await _until(worker.TaskPhase.HAUL_DEPOSIT), "remaining crate arrives on a second trip")
	worker._process(1)
	_expect(zone.stored_count() == 10 and _loose_units() == 0, "two trips deliver every good exactly once")
	_expect(zone.reserved_cells.is_empty() and drops._reserved.is_empty(), "finished deliveries release all claims")
