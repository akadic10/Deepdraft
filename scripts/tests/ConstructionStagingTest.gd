extends "res://scripts/tests/ConstructionTest.gd"

var second
var batch_sizes: Array[int] = []
var saw_full := false
var saw_hammer := false
var peak_haulers := 0
var max_carried := 0

func _run() -> void:
	create_timer(150).timeout.connect(func(): push_error("Construction staging timeout"); quit(1))
	await _setup_fixture()
	await _new_trip(STONE,8)
	stockpiles.reset_runtime_state()
	stockpiles._process(0)
	nav = root.get_node("NavGrid")
	root.get_node("WorldGenerator")._cache_block_ids()
	mine = load("res://scripts/systems/MiningDesignationController.gd").new()
	scene.add_child(mine)
	mine.set_process(false)
	mine.set_process_unhandled_input(false)
	construction = load("res://scripts/systems/ConstructionController.gd").new()
	construction.mining = mine
	scene.add_child(construction)
	construction.set_process(false)
	_terrain_before = world.terrain_overrides()
	var factory = load("res://scripts/entities/DwarfFactory.gd").new()
	second = factory.spawn(factory.generate(142,{}),142)
	scene.add_child(second)
	second.position = Vector3(39.5,21,39.5)
	second.set_process(false)
	second.sleep = 1
	tasks.register_dwarf(second)
	var cells: Array[Vector3i] = []
	for x in range(44,50): cells.append(Vector3i(x,21,40))
	var id: int = construction.create_order(cells)
	var order = construction.orders[id]
	var crate = order.materials
	var crate_floor: Vector3i = crate.crate_cell
	var handle: int = crate.occupancy
	_expect(crate.carry_capacity==4 and crate.pouch_bundle_radius==8,"construction inherits existing carry capacity and bundle radius")
	_expect(crate_floor.x>=0 and not nav.is_walkable(crate_floor),"crate has safe, real occupancy")
	_expect(not cells.has(crate_floor+Vector3i.UP),"crate lies outside the blueprint")
	for tick in range(2400):
		if not construction.orders.has(id): break
		peak_haulers = maxi(peak_haulers,crate._pulls.size())
		for actor in [worker,second]:
			max_carried = maxi(max_carried,actor._carried_entries.size())
			_expect(actor._carried_entries.size()<=crate.carry_capacity,"every construction load respects capacity")
			if actor._task_phase == actor.TaskPhase.FETCH_WORKING:
				saw_hammer = is_instance_valid(actor._construction_pose.tool) and actor._construction_pose.tool.visible
				_expect(not is_instance_valid(actor._mining_pose.tool) or not actor._mining_pose.tool.visible,"pick stowed during hammering")
				_expect(not is_instance_valid(actor._felling_pose.tool) or not actor._felling_pose.tool.visible,"axe stowed during hammering")
		if crate.count()==6: saw_full = true
		_expect(_completed_cells().is_empty() or saw_full,"all six stones arrive before the first block")
		_expect(crate.count()+crate.in_transit()<=order.cells.size(),"concurrent deliveries never overbook")
		var remaining := _all_units()
		_expect(remaining+_completed_cells().size()==8,"stone conserved across loose, carried, staged and built states")
		await _tick()
	_expect(_completed_cells().size()==6 and not construction.orders.has(id),"two haulers and one builder finish six voxels")
	_expect(peak_haulers==2 and max_carried==4,"two haulers supply normal four-unit bundles")
	_expect(saw_full and saw_hammer,"fully funded project switches to a visible hammer")
	_expect(not root.get_node("PlacedEntityRegistry")._boxes.has(handle),"completion removes crate occupancy")
	_expect(_all_units()==2,"only six of eight available stones consumed")
	tasks.deregister_dwarf(second.dwarf_id)
	second.free()
	second = null
	await _staged_resume()
	await _stored_bundle()
	await _missing_supply_cancel()
	await _site_loss()
	_expect(tasks.lifecycle_errors().is_empty(),"no orphan tasks or reservations")
	for failure: String in failures: push_error(failure)
	print("CONSTRUCTION_STAGING_OK" if failures.is_empty() else "CONSTRUCTION_STAGING_FAIL")
	quit(0 if failures.is_empty() else 1)

func _tick() -> void:
	construction._process(.04)
	tasks._run_scheduler()
	worker._process(.04)
	if is_instance_valid(second): second._process(.04)
	await process_frame

func _all_units() -> int:
	var total := _snapshot_units()
	if is_instance_valid(second):
		for entry: Dictionary in second.serialize_state().carried_items: total += int(entry.count)
	for source in stockpiles._zones.values():
		for amount in source.contents().values(): total += int(amount)
	return total

func _staged_resume() -> void:
	drops.spawn_drop(STONE,3,Vector3i(40,21,40))
	var before := _all_units()
	var cell := Vector3i(47,21,45)
	var id: int = construction.create_order(_cells([cell,cell+Vector3i.RIGHT,cell+Vector3i.RIGHT*2]))
	_expect(await _wait_phase(worker.TaskPhase.FETCH_WORKING),"fully staged project starts hammer work")
	var order = construction.orders[id]
	worker._process(.4)
	var target: Vector3i = order.target
	var progress: float = order.work_progress[target]
	var task_id: int = worker.current_task_id
	_expect(progress>0 and progress<3,"each voxel requires three seconds of real work")
	_expect(not _completed_cells().has(target),"partial hammering leaves blueprint intact")
	var inventory: Dictionary = load("res://scripts/components/ColonyInventory.gd").snapshot(drops,null)
	_expect(int(inventory[STONE].total)==before and inventory[STONE].reserved>=3,"staged goods remain counted and reserved in colony inventory")
	clock_node.set_paused(true)
	worker._process(4)
	_expect(is_equal_approx(order.work_progress[target],progress),"pause freezes hammering")
	clock_node.set_paused(false)
	worker._food.value = .2
	_expect(worker._food.begin_if_needed(),"hunger interrupts the active construction job")
	_expect(order.materials.count()==3 and is_equal_approx(order.work_progress[target],progress),"need interruption preserves staged stock and partial work")
	_expect(not worker._construction_pose.tool.visible,"interruption stows the hammer")
	worker._food.cancel()
	worker._food.value = 1.0
	var saved: Dictionary = JSON.parse_string(JSON.stringify(construction.serialize_state()))
	var serialized_loose: Dictionary = drops.serialize_state()
	construction.restore_state(saved)
	order = construction.orders[id]
	_expect(order.materials.count()==3 and is_equal_approx(order.work_progress[target],progress),"save/restore preserves staged materials and partial work")
	_expect(drops.serialize_state()==serialized_loose,"restoring crate does not spawn duplicate loose stone")
	_expect(_all_units()==before,"save round trip conserves goods")
	_expect(tasks.get_task(task_id)==null,"restoring discards old execution lease")
	for tick in range(1600):
		await _tick()
		if not construction.orders.has(id): break
	_expect(not construction.orders.has(id) and _all_units()==before-3,"restored builder completes without fetching more stone")

func _stored_bundle() -> void:
	for item in drops._loose.keys(): drops.take(item); item.free()
	stockpiles.register_zone(zone)
	for x in range(40,44):
		var cell := Vector3i(x,20,44)
		zone.cell_stacks[cell] = {"item":STONE,"count":1}
		drops.restore_stored_item(STONE,cell,1)
	stockpiles.rebuild_totals()
	var cells: Array[Vector3i] = []
	for x in range(47,51): cells.append(Vector3i(x,21,49))
	var id: int = construction.create_order(cells)
	var saw_bundle := false
	for tick in range(1800):
		await _tick()
		if worker._task_phase == worker.TaskPhase.HAUL_TO_ZONE:
			saw_bundle = worker._carried_entries.size()==4
		if not construction.orders.has(id): break
	_expect(saw_bundle,"stored stone is collected as a four-item physical bundle")
	_expect(not construction.orders.has(id) and zone.stored_count()==0,"stored bundle reaches crate and builds all four voxels")
	_expect(zone._outgoing.is_empty(),"stored portion claims released")
	stockpiles.deregister_zone(zone)

func _missing_supply_cancel() -> void:
	drops.spawn_drop(STONE,4,Vector3i(40,21,40))
	var before := _all_units()
	var cells: Array[Vector3i] = []
	for x in range(47,53): cells.append(Vector3i(x,21,53))
	var id: int = construction.create_order(cells)
	var order = construction.orders[id]
	for tick in range(1200):
		await _tick()
		if order.materials.count()==4: break
	_expect(order.materials.count()==4 and order.builder_id<0,"four of six delivered waits for missing supplies")
	_expect(is_equal_approx(order.total_remaining_work(),18),"six planned voxels require eighteen seconds")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(construction.serialize_state()))
	construction.restore_state(saved)
	order = construction.orders[id]
	_expect(order.materials.count()==4,"partly funded crate survives restore")
	construction.cancel_order(id)
	await process_frame
	_expect(_all_units()==before,"cancel refunds staged stock exactly once")
	for cell: Vector3i in cells: _expect(not _completed_cells().has(cell),"unfunded project never builds")

func _site_loss() -> void:
	var cell := Vector3i(51,21,57)
	var id: int = construction.create_order(_cells([cell]))
	var order = construction.orders[id]
	_expect(await _wait_phase(worker.TaskPhase.HAUL_TO_ZONE),"site-loss test has real carried goods")
	var before := _all_units()
	var crate = order.materials
	var old: Vector3i = crate.crate_cell
	var old_handle: int = crate.occupancy
	world.set_block(old.x,old.y,old.z,blocks.AIR_ID)
	nav.refresh_mined_block(old)
	crate.tick_site(1,127)
	_expect(not root.get_node("PlacedEntityRegistry")._boxes.has(old_handle),"lost support removes the floating crate")
	_expect(_all_units()==before,"lost crate access preserves carried stone")
	construction.cancel_order(id)
	await process_frame
