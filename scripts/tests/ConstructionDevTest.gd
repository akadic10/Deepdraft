extends "res://scripts/tests/ConstructionStagingTest.gd"

func _run() -> void:
	create_timer(90).timeout.connect(func(): push_error("Construction DEV timeout"); quit(1))
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
	construction.set_process_unhandled_input(false)
	var first := Vector3i(45,21,40)
	var id: int = construction.create_order(_cells([first,first+Vector3i.UP,first+Vector3i.UP*2,first+Vector3i.UP*3]))
	var order = construction.orders[id]
	var source: int = order.source_id
	var crate_source: int = order.materials.source_id
	var handle: int = order.materials.occupancy
	var before := _all_units()
	var data: Dictionary = construction.get_explorer_data(id)
	_expect(data.actions[0].text=="DEV: Finish construction", "blueprint and crate inspector expose instant finish")
	clock_node.set_paused(true)
	construction.perform_explorer_action(id,"dev_build")
	_expect(not construction.orders.has(id) and _completed_cells().size()==4,"unfunded four-block column completes instantly while paused")
	_expect(_all_units()==before,"DEV does not fetch or consume remote supplies")
	_expect(tasks.get_work_source(source)==null and tasks.get_work_source(crate_source)==null,"completed DEV project unregisters both work sources")
	_expect(not root.get_node("PlacedEntityRegistry")._boxes.has(handle),"DEV completion removes crate occupancy")
	clock_node.set_paused(false)
	for cell: Vector3i in _completed_cells():
		_expect(world.get_terrain_block(cell.x,cell.y,cell.z)==root.get_node("WorldGenerator").construction_stone_id(cell),"DEV stone keeps authored geology")
	# Active delivery is interrupted normally; cargo returns to the ground.
	id = construction.create_order(_cells([Vector3i(49,21,44),Vector3i(50,21,44)]))
	_expect(await _wait_phase(worker.TaskPhase.HAUL_TO_ZONE),"DEV test reaches real material transport")
	before = _all_units()
	construction.dev_build_order(id)
	_expect(not construction.orders.has(id) and worker.current_task_id<0,"DEV releases an assigned hauler")
	_expect(worker._carried_entries.is_empty() and _all_units()==before,"in-flight cargo is preserved exactly once")
	_expect(drops._reserved.is_empty(),"cancelled delivery releases item reservations")
	# Staged supplies are used first; finishing stops the active hammer.
	id = construction.create_order(_cells([Vector3i(49,21,49),Vector3i(50,21,49)]))
	_expect(await _wait_phase(worker.TaskPhase.FETCH_WORKING),"DEV test reaches real hammer work")
	worker._process(.3)
	before = _all_units()
	construction.dev_build_order(id)
	_expect(not construction.orders.has(id) and _all_units()==before-2,"DEV uses the two delivered stones once")
	_expect(worker.current_task_id<0 and not worker._construction_pose.tool.visible,"DEV stows hammer and releases builder")
	# An obstruction must stay pending, with valid staged counts/save data.
	var blocked := Vector3i(49,21,54)
	id = construction.create_order(_cells([blocked,blocked+Vector3i.RIGHT]))
	order = construction.orders[id]
	order.materials.staged = {"base:resources:stone:rough_stone": {"": 2}}
	handle = root.get_node("PlacedEntityRegistry").register_box(blocked,Vector3i.ONE)
	_expect(construction.dev_build_order(id)==1,"DEV skips occupied cells")
	_expect(order.cells==_cells([blocked]) and order.materials.count()==1,"partial DEV completion retains only required staged stock")
	_expect(construction.get_explorer_data(id).details.contains("A placed object occupies"),"blocked DEV finish explains why it is incomplete")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(construction.serialize_state()))
	construction.restore_state(saved)
	_expect(construction.orders[id].cells==_cells([blocked]) and construction.orders[id].materials.count()==1,"partial DEV project survives save/restore")
	root.get_node("PlacedEntityRegistry").unregister(handle)
	_expect(construction.dev_build_order(id)==1 and not construction.orders.has(id),"retry completes the previously blocked voxel")
	# A suspended run supported at its high-X end resolves in multiple passes.
	var anchor := Vector3i(56,24,56)
	world.set_block(anchor.x,anchor.y,anchor.z,root.get_node("WorldGenerator").construction_stone_id(anchor))
	id = construction.create_order(_cells([anchor+Vector3i.LEFT*3,anchor+Vector3i.LEFT*2,anchor+Vector3i.LEFT]))
	_expect(construction.dev_build_order(id)==3,"DEV fills a supported span regardless of designation order")
	_expect(tasks.lifecycle_errors().is_empty(),"DEV leaves no orphan tasks or reservations")
	for failure: String in failures: push_error(failure)
	print("CONSTRUCTION_DEV_OK" if failures.is_empty() else "CONSTRUCTION_DEV_FAIL")
	quit(0 if failures.is_empty() else 1)
