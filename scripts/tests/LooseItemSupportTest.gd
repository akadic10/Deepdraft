extends "res://scripts/tests/HaulingAnimationTest.gd"

## Mining removes a drop's supporting ledge after the drop has already spawned.
## Exercise actual loose ownership, a claimed pickup, and old-save restoration.
func _run() -> void:
	create_timer(40).timeout.connect(func(): push_error("Loose support test timed out"); quit(1))
	await _setup_fixture()
	await _new_trip(STONE, 1)
	var stone: int = blocks.get_id("base:terrain:rock:rock01")
	world.set_block(50, 26, 40, stone)
	drops.spawn_drop(STONE, 1, Vector3i(50, 27, 40))
	var item: Node3D = drops._loose.keys()[-1]
	_expect(item.position.y == 27, "drop starts on the upper ledge")
	var xz := Vector2(item.position.x, item.position.z)
	var yaw := item.rotation.y
	world.set_block(50, 26, 40, blocks.AIR_ID)
	await process_frame
	await process_frame
	_expect(item.position.y == 21, "removing support settles an existing drop to the pit floor")
	var bounds: AABB = load("res://scripts/components/ObjectPicking.gd").world_bounds(item)
	_expect(is_equal_approx(bounds.position.y, 21), "actual rough-stone mesh rests on the floor")
	_expect(Vector2(item.position.x, item.position.z) == xz and item.rotation.y == yaw,
		"settling preserves position within the column and yaw")
	_expect(drops.quantity_of(item) == 1 and drops._loose.has(item), "settling preserves goods and ownership")
	drops._on_slice_changed(22)
	_expect(item.visible, "slice visibility follows the new floor")
	drops.restore_loose_item(ACORN, Vector3(52.35, 31, 40.7), .4, 17)
	var restored: Node3D = drops._loose.keys()[-1]
	_expect(restored.position == Vector3(52.35,21,40.7) and drops.quantity_of(restored) == 17,
		"old hovering saves settle without changing crate quantity or horizontal position")
	_expect(is_equal_approx(restored.rotation.y, .4), "save repair preserves rotation")
	world.set_block(54,21,40,stone)
	drops.restore_loose_item(STONE, Vector3(54.5,21.6,40.5))
	_expect(is_equal_approx(drops._loose.keys()[-1].position.y, 21.6), "fractional carrier position is never lowered into a step")
	for y in range(4,21): world.set_block(52,y,40,blocks.AIR_ID)
	await process_frame
	await process_frame
	_expect(restored.position.y == 4, "deep columns settle above protected bedrock")
	_expect(item.position.y == 21, "unrelated column remains unchanged")

	# A miner removes support during a worker's reach, before pickup contact.
	await _new_trip(STONE, 1)
	_expect(await _until(worker.TaskPhase.HAUL_PICKUP), "real worker reaches the reserved drop")
	item = drops._loose.keys()[0]
	var reserved_cell: Vector3i = drops.item_floor_cell(item)
	world.set_block(reserved_cell.x,reserved_cell.y,reserved_cell.z,blocks.AIR_ID)
	await process_frame
	await process_frame
	_expect(item.position.y == 20, "claimed item also settles")
	_expect(worker.current_task_id == -1 and worker._task_phase == worker.TaskPhase.NONE,
		"stale pickup is released before it can reach to the old height")
	_expect(drops._reserved.is_empty() and zone.reserved_cells.is_empty(), "both pickup and delivery claims are freed")
	_expect(_snapshot_units() == 1, "interrupted pickup neither loses nor duplicates goods")
	_expect(await _until(worker.TaskPhase.HAUL_TO_ZONE), "settled goods can be claimed and hauled again")
	var cargo: Node3D = worker._carried_entries[0][0]
	var cargo_parent := cargo.get_parent()
	world.set_block(reserved_cell.x,reserved_cell.y-1,reserved_cell.z,blocks.AIR_ID)
	await process_frame
	_expect(cargo.get_parent() == cargo_parent and not drops._loose.has(cargo), "terrain settling never touches carried goods")
	if failures.is_empty():
		print("LOOSE_ITEM_SUPPORT_OK: mined support, deep floor, old saves, quantities, slice, reserved pickup, rehaul and carried ownership")
	else:
		for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
