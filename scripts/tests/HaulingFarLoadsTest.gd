extends "res://scripts/tests/HaulingSelectionTest.gd"

## Regression for the owner's 2026-10-30 save: four dwarves stood Ready for work beside the
## stockpile for over a minute while two dozen logs lay on a shelf whose only way up was a
## long detour. Each dwarf searched a separate route to every log, and the scheduler's turns
## went round all of those searches before any one finished. One pickup search per dwarf now
## covers the loads that lie the same way, and the dwarf takes the load it reached.
const NODES_PER_WAKE := 40   # about what one 1 ms wake expands in play (measured on that save)
# The old per-log rotation first assigned at wake 1427 and had all three working at 1476.
const FIRST_LIMIT := 300
const WAKE_LIMIT := 700
const STAIR_LOG := Vector3i(59,26,68)


func _run() -> void:
	create_timer(120).timeout.connect(func(): push_error("Hauling far loads timed out"); quit(1))
	await _setup_fixture()
	await _fresh()
	for node in drops._loose.keys():
		drops.take(node); node.free()
	_build_shelf()
	await process_frame; await process_frame
	var cells: Array[Vector3i] = []
	for x in range(56,64):
		for z in range(40,42): cells.append(Vector3i(x,20,z))
	_zone_at(cells)
	worker.position = Vector3(57.5,21,44.5)
	var crew: Array = [worker, _other(230,Vector3i(60,20,44)), _other(231,Vector3i(63,20,44))]
	# Eleven logs along the shelf's near edge, close as the crow flies, and one beside the
	# top of the stairs: farther in a straight line, but the nearest by the only route.
	for x in range(46,68,2): drops.restore_loose_item(LOG, Vector3(x+.5,27,52.5))
	drops.restore_loose_item(LOG, Vector3(STAIR_LOG)+Vector3(.5,1,.5))
	for dwarf in crew: dwarf._food.value = 1.0
	await process_frame; await process_frame
	tasks._probe_node_cap = NODES_PER_WAKE
	tasks._max_probes_per_wake = 8
	tasks._budget_usec = 100000
	var first_wake := -1
	var all_wake := -1
	var first_dwarf = null
	for wake in WAKE_LIMIT:
		stockpiles._process(.25)
		tasks._run_scheduler()
		for dwarf in crew:
			if dwarf.current_task_id >= 0 and first_dwarf == null:
				first_dwarf = dwarf
				first_wake = wake
		if crew.all(func(dwarf) -> bool: return dwarf.current_task_id >= 0):
			all_wake = wake
			break
	print("HAULING_FAR_LOADS first_wake=", first_wake, " all_wake=", all_wake)
	_expect(first_wake >= 0 and first_wake < FIRST_LIMIT, "a dwarf takes a shelf load within %d wakes" % FIRST_LIMIT)
	_expect(all_wake >= 0, "every dwarf by the stockpile takes a shelf load within %d wakes" % WAKE_LIMIT)
	if first_dwarf != null and zone._pulls.has(first_dwarf.dwarf_id):
		_expect(drops.item_floor_cell(zone._pulls[first_dwarf.dwarf_id].items[0]) == STAIR_LOG,
			"the first dwarf takes the log its route search reached, not the one nearest in a straight line")
	_expect(drops._reserved.size() <= 12 and zone.reserved_cells.size() == drops._reserved.size(),
		"one storage claim for each claimed log")
	# Later dwarves' searches also reached the stair log; once it was claimed they must go on
	# to logs that are still free, never be sent off with the claimed log's route.
	for dwarf in crew:
		var task = tasks.get_task(dwarf.current_task_id)
		if task == null or not zone._pulls.has(dwarf.dwarf_id): continue
		var path: Array = task.payload.get("haul_pickup_path", [])
		var stand: Vector3i = path.back() if not path.is_empty() else dwarf.current_cell()
		_expect((zone._pulls[dwarf.dwarf_id].items as Array).any(func(item) -> bool: return stand in zone.ground_access_cells(drops.item_floor_cell(item))),
			"dwarf %d claims a log at the end of its proven route" % dwarf.dwarf_id)
	if first_dwarf != null:
		for tick in 2400:
			if zone.stored_count() > 0: break
			for dwarf in crew: dwarf._process(.05)
			await process_frame
		_expect(zone.stored_count() > 0, "a shelf log reaches storage by the stairs")
	_expect(_loose_units() + zone.stored_count() + _carried_units(crew) == 12, "no log is lost or duplicated")
	_expect(tasks.lifecycle_errors().is_empty(), "far loads keep valid task ownership")
	for failure: String in failures: push_error(failure)
	print("HAULING_FAR_LOADS_OK" if failures.is_empty() else "HAULING_FAR_LOADS_FAIL")
	quit(0 if failures.is_empty() else 1)


## A walled yard (x 38..82, z 36..80) around a six-high shelf (x 44..76, z 50..70). The only
## way up is a stair on the shelf's far side, so every route from the stockpile in front
## walks round the shelf, climbs and walks back.
func _build_shelf() -> void:
	var rock: int = blocks.get_id("base:terrain:rock:rock01")
	world.begin_edit_batch()
	for y in range(21,24):
		for i in range(37,84):
			for cell: Vector2i in [Vector2i(i,35), Vector2i(i,81), Vector2i(37,i-2), Vector2i(83,i-2)]:
				world.set_block(cell.x,y,cell.y,rock)
	for x in range(44,77):
		for z in range(50,71):
			for y in range(21,27): world.set_block(x,y,z,rock)
	for x in range(58,61):
		for z in range(71,76):
			for y in range(21,97-z): world.set_block(x,y,z,rock)
	world.end_edit_batch()


func _carried_units(crew: Array) -> int:
	var units := 0
	for dwarf in crew: units += dwarf._carried_entries.size()
	return units
