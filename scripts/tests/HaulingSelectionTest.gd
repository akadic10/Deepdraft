extends "res://scripts/tests/HaulingAnimationTest.gd"

## Regression for a tree cutter losing nearby lumber to dwarves ahead of them
## in the idle queue. Uses real task sources, reservation and worker executors.
var _others: Array[Node3D] = []
var _stages := 0


func _run() -> void:
	create_timer(80).timeout.connect(func(): push_error("Hauling selection test timed out"); quit(1))
	await _setup_fixture()
	await _tree_cutter_gets_nearby_lumber()
	await _returning_hauler_reconsiders_workers()
	await _eligibility_and_priorities()
	await _blocked_worker_and_probe_budget()
	await _resumable_ranking()
	await _relocation_distance()
	_expect(_stages == 6, "all selection tests reached their final assertion")
	if failures.is_empty():
		print("HAULING_SELECTION_OK: real felling handoff, returning-hauler handoff after deposit, pickup proximity, limited capacity, filters, higher priorities, sleeping/claimed workers, blocked nearest, resumable probes and quotes, new idle workers, relocation")
	else:
		for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)


func _fresh(key := LOG, amount := 1) -> void:
	if is_instance_valid(flora): flora.free()
	for other in _others:
		if is_instance_valid(other):
			tasks.cancel_source_tasks(int(other.get("_haul_source_id")))
			other.free()
	_others.clear()
	await _new_trip(key, amount)
	tasks._max_probes_per_wake = 8
	tasks._budget_usec = 1000


func _other(id: int, cell: Vector3i):
	var factory = load("res://scripts/entities/DwarfFactory.gd").new()
	var agent = factory.spawn(factory.generate(id, {}), id)
	scene.add_child(agent)
	agent.position = Vector3(cell) + Vector3(.5,1,.5)
	agent.set_process(false)
	agent.sleep = 1.0
	tasks.register_dwarf(agent)
	_others.append(agent)
	return agent


func _zone_at(cells: Array[Vector3i]) -> void:
	stockpiles.deregister_zone(zone)
	zone = load("res://scripts/components/StockpileZoneComponent.gd").new()
	zone.setup(1, cells)
	stockpiles.register_zone(zone)


func _dispatch(wakes := 60) -> void:
	# Do not advance workers: claims must be chosen correctly before anyone
	# starts walking, and existing trips cannot complete and muddy the result.
	for i in range(wakes):
		stockpiles._process(.25)
		var before: int = tasks._probes_total
		tasks._run_scheduler()
		_expect(tasks._probes_total - before <= tasks._max_probes_per_wake, "scheduler honors its per-wake probe cap")
		await process_frame


func _tree_cutter_gets_nearby_lumber() -> void:
	await _fresh()
	for item in drops._loose.keys():
		drops.take(item)
		item.free()
	_zone_at([Vector3i(60,20,44), Vector3i(61,20,44), Vector3i(62,20,44), Vector3i(63,20,44)])
	zone.set_all_accepted(false)
	zone.set_item_accepted(LOG, true)
	flora = load("res://scripts/systems/SurfaceFloraSpawner.gd").new()
	scene.add_child(flora)
	flora.set_process(false)
	var species: Dictionary = flora._species_for_key("base:flora:oak_tree")
	var stage: Dictionary = species.stages.mature
	var tree_cell := Vector3i(40,20,40)
	var path: String = flora.resolve_tree_model_for_season(stage, "spring", tree_cell)
	var tree: Node3D = flora._instance_tree("oak", path, "mature", stage, 40,40,20, flora._footprint_for(species.placement, "mature"))
	flora._loaded_columns[Vector2i(2,2)] = [tree]
	flora.designate_felling(Vector2i(40,40))
	worker.position = Vector3(39.5,21,40.5)
	var source = flora._felling_sources[Vector2i(40,40)]
	tasks._assign(tasks.get_task(source.lease_id), worker)
	var far = _other(201, Vector3i(59,20,44)) # older idle entry, closer to STORAGE
	var near = _other(202, Vector3i(45,20,40))
	for i in range(100):
		worker._process(.04)
		if worker._task_phase == worker.TaskPhase.FELL_WORKING: break
		await process_frame
	_expect(worker._task_phase == worker.TaskPhase.FELL_WORKING, "cutter reaches the real tree")
	source.state.work_seconds = source.duration - .01
	worker._process(.02)
	_expect(flora._tree_changes[Vector2i(40,40)].felled and worker.current_task_id < 0, "final chop creates logs and makes cutter idle in the same update")
	_expect(tasks._idle_dwarves == [far.dwarf_id, near.dwarf_id, worker.dwarf_id], "regression reproduces cutter at the end of the idle queue")
	await _dispatch()
	_expect(worker.current_task_id >= 0 and near.current_task_id >= 0 and far.current_task_id < 0, "cutter and nearer helper claim lumber instead of older distant idle dwarf")
	_expect(zone._pulls[worker.dwarf_id].items.size() == 2 and zone._pulls[near.dwarf_id].items.size() == 2, "four logs form two carry-budget loads without duplicate claims")
	_expect(drops._reserved.size() == 4 and zone.reserved_cells.size() == 4, "exactly four log and storage claims exist")
	_stages += 1


func _returning_hauler_reconsiders_workers() -> void:
	await _fresh()
	# Saturate the storage's worker limit with an existing delivery. The next
	# load must compare idle workers even though the same source still has room.
	zone.max_haulers = 1
	_expect(await _until(worker.TaskPhase.HAUL_DEPOSIT), "existing hauler reaches storage with its first log")
	var first_lease: int = worker.current_task_id
	flora = load("res://scripts/systems/SurfaceFloraSpawner.gd").new()
	scene.add_child(flora)
	flora.set_process(false)
	var species: Dictionary = flora._species_for_key("base:flora:oak_tree")
	var stage: Dictionary = species.stages.mature
	var tree_cell := Vector3i(58,20,40)
	var path: String = flora.resolve_tree_model_for_season(stage, "spring", tree_cell)
	var tree: Node3D = flora._instance_tree("oak", path, "mature", stage, 58,40,20, flora._footprint_for(species.placement, "mature"))
	flora._loaded_columns[Vector2i(3,2)] = [tree]
	flora.designate_felling(Vector2i(58,40))
	var cutter = _other(210, Vector3i(57,20,40))
	var source = flora._felling_sources[Vector2i(58,40)]
	tasks._assign(tasks.get_task(source.lease_id), cutter)
	for i in range(100):
		cutter._process(.04)
		if cutter._task_phase == cutter.TaskPhase.FELL_WORKING: break
		await process_frame
	_expect(cutter._task_phase == cutter.TaskPhase.FELL_WORKING, "nearby cutter reaches the real tree while the hauler is lowering")
	source.state.work_seconds = source.duration - .01
	cutter._process(.02)
	_expect(cutter.current_task_id < 0 and flora._tree_changes[Vector2i(58,40)].felled, "cutter becomes idle beside the new lumber")
	var goods_before: int = _loose_units() + worker._carried_entries.size()
	# Finish the old load before the next scheduler wake: this used to claim
	# new timber directly, bypassing the closer, newly idle cutter entirely.
	worker._process(worker._handling_duration)
	_expect(zone.stored_count() == 1 and worker._carried_entries.is_empty(), "old load commits before its worker is reconsidered")
	_expect(worker.current_task_id < 0 and tasks.get_task(first_lease) == null
		and drops._reserved.is_empty() and zone._pulls.is_empty(), "delivery finishes its lease without privately claiming another load")
	await _dispatch()
	_expect(cutter.current_task_id >= 0 and worker.current_task_id < 0, "nearby cutter wins the next load instead of the returning distant hauler")
	_expect(zone._lease_ids.size() <= zone.max_haulers and zone._pulls.has(cutter.dwarf_id), "handoff retains bounded leases and correct item ownership")
	_expect(_loose_units() + zone.stored_count() == goods_before, "handoff loses or duplicates no goods")
	_stages += 1


func _eligibility_and_priorities() -> void:
	await _fresh()
	worker.position = Vector3(39.5,21,40.5)
	var far = _other(203, Vector3i(52,20,40))
	worker.dev_make_tired()
	worker._process(.1)
	await _dispatch()
	_expect(worker.is_sleeping() and worker.current_task_id < 0 and far.current_task_id >= 0, "a nearby sleeping dwarf is not eligible")
	await _fresh(ACORN, 12)
	zone.set_all_accepted(false)
	zone.set_item_accepted(LOG, true)
	drops.restore_loose_item(LOG, Vector3(52.5,21,40.5))
	var near_log = _other(204, Vector3i(51,20,40))
	await _dispatch()
	_expect(near_log.current_task_id >= 0 and worker.current_task_id < 0, "distance is measured to accepted goods, not nearer rejected items")
	await _fresh()
	var task_script = load("res://scripts/systems/Task.gd")
	var build_id: int = tasks.add_task(task_script.Type.BUILD, Vector3i(41,20,39))
	var helper = _other(205, Vector3i(48,20,40))
	await _dispatch()
	_expect(worker.current_task_id == build_id and helper.current_task_id >= 0, "higher-priority work is considered before nearby hauling")
	await _fresh()
	_expect(await _until(worker.TaskPhase.HAUL_DEPOSIT), "hauler reaches delivery before new higher-priority work")
	drops.restore_loose_item(LOG, Vector3(42.5,21,40.5))
	build_id = tasks.add_task(task_script.Type.BUILD, Vector3i(41,20,43))
	worker._process(worker._handling_duration)
	await _dispatch()
	_expect(worker.current_task_id == build_id, "returning hauler considers higher-priority work between loads")
	_expect(zone.stored_count() == 1 and _loose_units() == 1 and drops._reserved.is_empty(), "completed cargo is stored and the next load stays unclaimed during higher-priority work")
	await _fresh()
	var committed = _other(206, Vector3i(50,20,40))
	tasks.notify_dwarf_unavailable(worker.dwarf_id)
	await _dispatch()
	var active_id: int = committed.current_task_id
	tasks.notify_dwarf_idle(worker.dwarf_id)
	await _dispatch()
	_expect(active_id >= 0 and committed.current_task_id == active_id and worker.current_task_id < 0, "newly available close worker does not steal an assigned load")
	_stages += 1


func _blocked_worker_and_probe_budget() -> void:
	await _fresh()
	worker.position = Vector3(40.5,21,37.5)
	var helper = _other(207, Vector3i(48,20,40))
	var stone: int = blocks.get_id("base:terrain:rock:rock01")
	var walls: Array[Vector3i] = []
	for offset: Vector3i in [Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK]:
		for y in range(21,25):
			var cell := Vector3i(40,y,37) + offset
			world.set_block(cell.x,cell.y,cell.z,stone)
			walls.append(cell)
	await process_frame
	await process_frame
	tasks._max_probes_per_wake = 1
	await _dispatch()
	_expect(worker.current_task_id < 0 and helper.current_task_id >= 0, "unreachable nearest worker does not block a reachable farther worker")
	for cell in walls: world.set_block(cell.x,cell.y,cell.z,blocks.AIR_ID)
	await process_frame
	await _fresh()
	worker.position = Vector3(37.5,21,40.5)
	# The nearest PILE can also be unreachable; it must not hide farther goods.
	walls.clear()
	for offset: Vector3i in [Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK]:
		for y in range(21,25):
			var cell := Vector3i(40,y,40) + offset
			world.set_block(cell.x,cell.y,cell.z,stone)
			walls.append(cell)
	drops.restore_loose_item(LOG, Vector3(50.5,21,40.5))
	await process_frame
	await process_frame
	await _dispatch()
	_expect(worker.current_task_id >= 0, "blocked nearest pile does not hide other reachable supplies")
	if zone._pulls.has(worker.dwarf_id):
		var first: Node3D = zone._pulls[worker.dwarf_id].items[0]
		_expect(drops.item_floor_cell(first) == Vector3i(50,20,40), "assignment carries failed pickup cells into the actual reservation")
	for cell in walls: world.set_block(cell.x,cell.y,cell.z,blocks.AIR_ID)
	await process_frame
	_stages += 1


func _resumable_ranking() -> void:
	await _fresh()
	var older = _other(208, Vector3i(50,20,40))
	tasks.notify_dwarf_unavailable(worker.dwarf_id)
	tasks._max_probes_per_wake = 1
	stockpiles._process(.25)
	for i in range(30):
		tasks._run_scheduler()
		if bool(tasks._haul_match.get("pickup_ok", false)): break
		await process_frame
	_expect(older.current_task_id < 0 and bool(tasks._haul_match.get("pickup_ok", false)), "pickup and destination probes can span wakes without premature assignment")
	tasks.notify_dwarf_idle(worker.dwarf_id)
	await _dispatch()
	_expect(worker.current_task_id >= 0 and older.current_task_id < 0, "newly idle cutter joins a comparison that was already in progress")
	await _fresh()
	var query := {}
	_expect(not zone.advance_haul_quote(worker.current_cell(), query, Time.get_ticks_usec() - 1), "pickup quote yields when its time budget expires")
	_expect(drops._reserved.is_empty() and zone.reserved_cells.is_empty(), "partial ranking never reserves goods")
	_expect(zone.advance_haul_quote(worker.current_cell(), query, Time.get_ticks_usec() + 100000), "pickup quote resumes to completion")
	_expect(query.cell == Vector3i(40,20,40), "resumed quote identifies actual pickup")
	_stages += 1


func _relocation_distance() -> void:
	await _fresh()
	var item: Node3D = drops._loose.keys()[0]
	drops.take(item)
	item.free()
	zone.cell_stacks[zone.tile_cells[0]] = {"item": LOG, "count": 1}
	drops.restore_stored_item(LOG, zone.tile_cells[0], 1)
	zone.set_all_accepted(false)
	var target = load("res://scripts/components/ContainerStorageComponent.gd").new()
	var cells: Array[Vector3i] = [Vector3i(60,20,44)]
	target.setup_container({"storage": {"capacity": 8}}, cells)
	target.source_id = tasks.allocate_source_id()
	stockpiles.register_container(target)
	stockpiles.rebuild_totals()
	worker.position = Vector3(40.5,21,43.5)
	var far = _other(209, Vector3i(59,20,44))
	tasks.notify_dwarf_unavailable(worker.dwarf_id)
	tasks.notify_dwarf_idle(worker.dwarf_id)
	await _dispatch()
	_expect(worker.current_task_id >= 0 and far.current_task_id < 0, "relocation compares distance to the source stack, not receiving container")
	_expect(zone._outgoing.size() == 1 and zone.stored_count() == 1, "relocation ranking preserves contact-time ownership")
	_stages += 1
