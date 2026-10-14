extends "res://scripts/tests/HaulingAnimationTest.gd"

const COPPER := "base:resources:ore:copper"


func _ledge_trip(height := 2, count := 1) -> void:
	await _new_trip(COPPER, 1)
	for node in drops._loose.keys():
		drops.take(node)
		node.free()
	var stone: int = blocks.get_id("base:terrain:rock:rock01")
	for x in range(40, 43):
		for y in range(21, 25):
			world.set_block(x, y, 41, stone if x < 40 + count and y <= 20 + height else blocks.AIR_ID)
	for x in range(40, 40 + count):
		drops.restore_loose_item(COPPER, Vector3(x + .5, 21 + height, 41.5))
	await process_frame


func _run() -> void:
	create_timer(90).timeout.connect(func(): push_error("Ledge pickup timed out"); quit(1))
	await _setup_fixture()
	await _ledge_trip(2, 3)
	# Match the saved room: ore has space above the lip, but there is no
	# three-block headroom on the ledge itself. Only the lower stands are valid.
	for x in range(40,43): world.set_block(x,25,41,blocks.get_id("base:terrain:rock:rock01"))
	_expect(not root.get_node("NavGrid").is_walkable(Vector3i(40,22,41)), "fixture ledge lacks standing headroom")
	var saw_contact := false
	for i in 1800:
		zone.update_leases()
		tasks._run_scheduler()
		worker._process(.04)
		if worker._task_phase == worker.TaskPhase.HAUL_PICKUP:
			saw_contact = true
			_expect(worker.current_cell().y == 20, "worker reaches from room floor without climbing ledge")
			if not worker._handling_lifted:
				_expect(worker._handling_item.get_parent() == drops, "ore remains loose until contact")
		if zone.stored_count() == 3: break
		await process_frame
	_expect(saw_contact and zone.stored_count() == 3 and _loose_units() == 0, "scheduler collects all three elevated copper chunks")
	_expect(worker._carried_entries.is_empty() and drops._reserved.is_empty() and zone.reserved_cells.is_empty(), "delivery conserves ore and releases claims")
	for x in range(40,43): world.set_block(x,25,41,blocks.AIR_ID)

	# Three blocks is beyond raised-hand reach, even though the top of the
	# isolated column is itself walkable. There is no climb or diagonal pickup.
	await _ledge_trip(3)
	var item_floor := Vector3i(40,23,41)
	var storage = load("res://scripts/components/StorageComponent.gd")
	for stand: Vector3i in storage.ground_access_cells(item_floor):
		_expect(stand.y > 20, "three-block ledge offers no room-floor pickup")
	_expect(not storage.ledge_reach_clear(Vector3i(40,22,41), Vector3i(39,20,40)), "cannot reach diagonally around a corner")
	for i in 120:
		zone.update_leases(); tasks._run_scheduler(); worker._process(.04)
		await process_frame
	_expect(_loose_units() == 1 and zone.stored_count() == 0, "unreachable high ore stays loose")

	# A wall built after arrival must abort contact, not teleport ore through it.
	await _ledge_trip()
	_expect(await _until(worker.TaskPhase.HAUL_PICKUP), "worker reaches ledge again")
	var item: Node3D = drops._loose.keys()[0]
	var before: Transform3D = item.global_transform
	world.set_block(40,23,41,blocks.get_id("base:terrain:rock:rock01"))
	worker._process(.35)
	_expect(item.get_parent() == drops and item.global_transform.is_equal_approx(before), "new obstruction prevents pickup at contact")
	_expect(_loose_units() == 1 and worker._carried_entries.is_empty() and drops._reserved.is_empty(), "aborted reach leaves ore and releases reservation")
	world.set_block(40,23,41,blocks.AIR_ID)
	await process_frame
	# A placed entity can block the lip even when the terrain remains air.
	var registry = root.get_node("PlacedEntityRegistry")
	var handle: int = registry.register_box(Vector3i(40,23,41), Vector3i.ONE)
	_expect(not storage.ledge_reach_clear(Vector3i(40,22,41), worker.current_cell()), "placed occupancy blocks raised reach")
	registry.unregister(handle)
	for failure in failures: push_error(failure)
	print("LedgePickupTest: ", "PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
