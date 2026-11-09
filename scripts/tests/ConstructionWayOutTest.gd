extends "res://scripts/tests/ConstructionTest.gd"

## A builder that starts inside a doorless room, its crate inside too, walks out and finishes it
## from outside rather than walling itself in (doc 31, "Way out").
const SEARCHING := 0
const REACHABLE := 1
const OUTSIDE := Vector3i(40,20,39)
const ShapeCells = preload("res://scripts/components/ConstructionShapes.gd")

func _run() -> void:
	create_timer(170).timeout.connect(func(): push_error("Way out test timed out"); quit(1))
	await _setup_fixture()
	await _new_trip(STONE,12)
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
	construction.set_process_unhandled_input(false)
	_terrain_before = world.terrain_overrides()
	for item in drops._loose.keys():
		drops.take(item)
		item.free()
	var low := Vector3i(52,21,40)
	var high := Vector3i(57,21,45)
	var center := Vector3i(54,20,42)
	worker.global_position = Vector3(center.x+1.5,21,center.z+1.5)
	drops.restore_loose_item(STONE,Vector3(center.x+1.5,21,center.z+.5),0,40)
	var cells: Array[Vector3i] = ShapeCells.rectangle(low,high,2,false,0,[])
	var id: int = construction.create_order(cells)
	var order = construction.orders[id]
	_expect(cells.size()==40,"a doorless room of 40 blocks is planned")
	var open: Dictionary = order._open_side()
	_expect(open.has(Vector3i(50,20,39)) and open.has(Vector3i(51,20,42)) and not open.has(center),"the room's inside counts as sealed, the ground around it as open")
	var floors: Array[Vector3i] = order._work_floors(Vector3i(52,21,42),order.depths())
	_expect(floors.has(Vector3i(51,20,42)) and not floors.has(Vector3i(53,20,42)),"a wall block is worked from outside: %s" % [floors])
	order.materials.remove_visual()
	order.materials.crate_cell = center
	construction.place_materials_crate(order.materials)
	_expect(order.materials.crate_cell==center,"the crate stands inside the room")
	var idle := 0
	for tick in range(9000):
		await _tick()
		if not construction.orders.has(id): break
		idle = idle+1 if worker.current_task_id < 0 else 0
		if idle > 800: break
	var at: Vector3i = worker.current_cell()
	_expect(not construction.orders.has(id),"all 40 blocks are built, with %d left" % (construction.orders[id].cells.size() if construction.orders.has(id) else 0))
	_expect(not nav.find_path(at,OUTSIDE,20000).is_empty(),"the builder ends outside and can walk away: %s" % [at])
	_expect(not (at.x>low.x and at.x<high.x and at.z>low.z and at.z<high.z),"the builder isn't inside the finished room")
	_expect(tasks.lifecycle_errors().is_empty(),"walking out keeps valid work ownership")
	# With a doorway the inside stays open, so a builder may work from either side.
	var with_door: Array[Vector3i] = []
	for cell: Vector3i in ShapeCells.rectangle(Vector3i(62,21,40),Vector3i(66,21,44),2,false,0,[]):
		if cell.x==64 and cell.z==40: continue
		with_door.append(cell)
	var door_id: int = construction.create_order(with_door)
	var door_order = construction.orders[door_id]
	var door_open: Dictionary = door_order._open_side()
	_expect(door_open.has(Vector3i(64,20,42)),"a room with a doorway stays open inside")
	construction.cancel_order(door_id)
	for failure: String in failures: push_error(failure)
	print("CONSTRUCTION_WAY_OUT_OK" if failures.is_empty() else "CONSTRUCTION_WAY_OUT_FAIL")
	quit(0 if failures.is_empty() else 1)
