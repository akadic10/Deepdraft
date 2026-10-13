extends "res://scripts/tests/HaulingAnimationTest.gd"

var construction
var mine
var nav

func _run() -> void:
	create_timer(100).timeout.connect(func(): push_error("Construction test timed out"); quit(1))
	await _setup_fixture()
	await _new_trip(STONE,8)
	stockpiles.reset_runtime_state()
	stockpiles._process(0)
	nav = root.get_node("NavGrid")
	root.get_node("WorldGenerator")._cache_block_ids()
	mine = load("res://scripts/systems/MiningDesignationController.gd").new()
	scene.add_child(mine)
	mine.set_process(false)
	construction = load("res://scripts/systems/ConstructionController.gd").new()
	construction.mining = mine
	scene.add_child(construction)
	construction.set_process(false)
	var first := Vector3i(44,21,40)
	var upper := first+Vector3i.UP
	var id: int = construction.create_order(_cells([first,upper]))
	_expect(id>0 and construction.orders.size()==1,"one area owns one construction order")
	_expect(not nav.is_walkable(first),"ghost provides no walking support")
	_expect(_snapshot_units()==8,"designation spends no stone")
	var saw_partial_area := false
	for tick in range(1200):
		await _tick()
		if construction.orders.is_empty(): break
		if construction.built.size()==1 and not saw_partial_area:
			var data: Dictionary = construction.get_explorer_data(id)
			_expect(data.rows[1][1]=="1" and data.rows[2][1]=="1 rough stone","inspector counts shrink as actual blocks finish")
			saw_partial_area = true
	_expect(construction.built.size()==2 and construction.orders.is_empty(),"worker constructs both blocks using real routes and delivery")
	_expect(saw_partial_area and construction.get_explorer_data(id).is_empty(),"completed area releases its inspector subject")
	_expect(_snapshot_units()==6,"each block consumes exactly one rough stone")
	_expect(world.get_terrain_block(first.x,first.y,first.z)==root.get_node("WorldGenerator").construction_stone_id(first),"built block uses authored stone layer identity")
	_expect(nav.is_walkable(upper) and not nav.is_walkable(first-Vector3i.UP),"completed blocks support walking and block former floor clearance")
	_expect(not construction.build_reason(first).is_empty(),"cannot build over existing terrain")
	_expect(not construction.build_reason(worker.current_cell()+Vector3i.UP).is_empty(),"cannot build into a dwarf")
	_expect(not construction.build_reason(Vector3i(45,3,40)).is_empty(),"cannot build bedrock")
	var blocker: int = root.get_node("PlacedEntityRegistry").register_box(Vector3i(48,21,40),Vector3i.ONE)
	_expect(construction.create_order(_cells([Vector3i(48,21,40)]))<0,"placed occupancy prevents designation")
	root.get_node("PlacedEntityRegistry").unregister(blocker)
	await _interruption_test()
	await _blocked_commit_test()
	await _mining_test(first)
	await _supply_test()
	await _room_test()
	_save_test()
	_expect(tasks.lifecycle_errors().is_empty(),"construction leaves no orphan tasks or claims")
	for failure: String in failures: push_error(failure)
	print("CONSTRUCTION_OK" if failures.is_empty() else "CONSTRUCTION_FAIL")
	quit(0 if failures.is_empty() else 1)

func _cells(values: Array) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	result.assign(values)
	return result

func _tick() -> void:
	construction._process(.04)
	tasks._run_scheduler()
	worker._process(.04)
	await process_frame

func _wait_phase(phase: int, limit := 700) -> bool:
	for tick in range(limit):
		if worker._task_phase==phase: return true
		await _tick()
	return false

func _interruption_test() -> void:
	var before := _snapshot_units()
	var cell := Vector3i(48,21,42)
	var id: int = construction.create_order(_cells([cell]))
	if await _wait_phase(worker.TaskPhase.FETCH_TO_GHOST):
		var data: Dictionary = construction.get_explorer_data(id)
		_expect(data.rows[0][1]=="Carrying stone" and data.rows[3][1]==worker.dwarf_name,"inspector reflects the real carrier")
		var state: Dictionary = construction.serialize_state()
		_expect(state.orders.size()==1 and worker.serialize_state().carried_items.size()==1,"save records pending area and real cargo separately")
		construction.perform_explorer_action(id,"cancel")
		_expect(_snapshot_units()==before and not construction.built.has(cell),"cancel after pickup preserves all stone and builds nothing")
	else: _expect(false,"construction reaches carry phase")
	await process_frame

func _blocked_commit_test() -> void:
	var before := _snapshot_units()
	var cell := Vector3i(48,21,44)
	var id: int = construction.create_order(_cells([cell]))
	if await _wait_phase(worker.TaskPhase.FETCH_WORKING):
		await _tick()
		var order = construction.orders[id]
		var progress: float = order.work_progress.get(cell,0.0)
		_expect(progress>0,"source owns partial work")
		var data: Dictionary = construction.get_explorer_data(id)
		_expect(data.rows[0][1]=="Building" and data.rows[4][1]=="%d%%" % roundi(progress/float(construction.definition.work_seconds)*100.0),"inspector reports actual work progress")
		var handle: int = root.get_node("PlacedEntityRegistry").register_box(cell,Vector3i.ONE)
		worker._process(3.0)
		_expect(not construction.built.has(cell) and _snapshot_units()==before,"late obstacle rejects commit without consuming stone")
		_expect(is_equal_approx(order.work_progress.get(cell,0.0),progress),"interruption retains partial construction work")
		root.get_node("PlacedEntityRegistry").unregister(handle)
		construction.cancel_order(id)
	else: _expect(false,"construction reaches working phase")
	await process_frame

func _mining_test(cell: Vector3i) -> void:
	var before := _snapshot_units()
	mine._mined_blocks[cell] = true # Original excavation history survives backfill.
	_expect(mine._filter_mineable_blocks(_cells([cell])).has(cell),"rebuilt terrain can be designated for mining")
	var id: int = mine._create_zone(_cells([cell]))
	_expect(mine.execute_zone_block_mined(id,cell,worker.dwarf_id),"normal mining removes a constructed block")
	_expect(not construction.built.has(cell) and _snapshot_units()==before+1,"constructed mining refunds one stone once")
	_expect(world.get_terrain_block(cell.x,cell.y,cell.z)==blocks.AIR_ID,"mined constructed block becomes real air")
	_expect(not construction.mined_refund(cell),"second removal cannot duplicate refund")
	await process_frame

func _save_test() -> void:
	var cell := Vector3i(49,21,43)
	var id: int = construction.create_order(_cells([cell]))
	construction.orders[id].work_progress[cell] = .75
	var saved: Dictionary = JSON.parse_string(JSON.stringify(construction.serialize_state()))
	for built_cell: Vector3i in construction.built: world.set_block(built_cell.x,built_cell.y,built_cell.z,blocks.AIR_ID)
	construction.restore_state(saved)
	_expect(construction.built.size()==saved.built.size(),"constructed terrain restores from permanent keys")
	_expect(is_equal_approx(construction.orders[id].work_progress[cell],.75),"pending work restores without transient reservations")
	_expect(construction.orders[id]._carried_by.is_empty(),"restored plan does not manufacture carried stone")
	construction.cancel_order(id)

func _supply_test() -> void:
	for item in drops._loose.keys(): drops.take(item); item.free()
	var cell := Vector3i(47,21,46)
	var id: int = construction.create_order(_cells([cell]))
	for tick in range(30): await _tick()
	_expect(construction.orders.has(id) and not construction.built.has(cell),"missing stone leaves a persistent unbuilt order")
	drops.restore_loose_item(STONE,Vector3(40.5,21,40.5),0,1)
	var item = drops._loose.keys()[0]
	item.set_meta("disallowed",true)
	for tick in range(30): await _tick()
	_expect(not construction.built.has(cell) and drops.quantity_of(item)==1,"disallowed stone is never consumed")
	construction.cancel_order(id)
	item.set_meta("disallowed",false)
	drops.take(item); item.free()
	# The same source contract withdraws exactly one real unit from storage.
	stockpiles.register_zone(zone)
	var stored := Vector3i(40,20,44)
	zone.cell_stacks[stored] = {"item":STONE,"count":1}
	zone.cell_stacks[stored+Vector3i.RIGHT] = {"item":STONE,"count":1}
	drops.restore_stored_item(STONE,stored,1)
	drops.restore_stored_item(STONE,stored+Vector3i.RIGHT,1)
	stockpiles._totals[STONE] = 2
	id = construction.create_order(_cells([cell]))
	for tick in range(800):
		await _tick()
		if not construction.orders.has(id): break
	_expect(construction.built.has(cell) and zone.stored_count()==1,"stored stone is physically delivered and consumed one unit at a time")
	stockpiles.deregister_zone(zone)

func _room_test() -> void:
	var stone: int = blocks.get_id("base:terrain:rock:rock01")
	for x in range(60,66):
		for z in range(60,66):
			for y in range(21,26):
				if x==62 and z==60 and y<25: continue
				if x in [60,65] or z in [60,65] or y==25: world.set_block(x,y,z,stone)
	var rooms = root.get_node("RoomManager")
	rooms.on_furniture_changed("fixture",_cells([Vector3i(62,20,60)]),{"furniture_category":"door"},true)
	var hole := Vector3i(65,21,62)
	world.set_block(hole.x,hole.y,hole.z,blocks.AIR_ID)
	rooms._rebuild_all_rooms()
	_expect(rooms.get_room_at(Vector3i(62,21,62)).is_empty(),"missing wall leaks room")
	drops.spawn_drop(STONE,1,Vector3i(42,21,42))
	var id: int = construction.create_order(_cells([hole]))
	rooms._rebuild_all_rooms()
	_expect(rooms.get_room_at(Vector3i(62,21,62)).is_empty(),"construction plan does not seal room")
	for tick in range(1400):
		await _tick()
		if not construction.orders.has(id): break
	rooms._rebuild_all_rooms()
	_expect(construction.built.has(hole) and not rooms.get_room_at(Vector3i(62,21,62)).is_empty(),"worker-built terrain seals the real room")
