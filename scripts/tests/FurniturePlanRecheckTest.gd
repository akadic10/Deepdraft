extends "res://scripts/tests/WorkerCraftingTest.gd"

## A floor piece rechecks its spot just before the packed item is used (doc 31): a refused install
## leaves no piece and keeps the item, and the plan builds once the spot is good again. A fence
## post rechecks for a dwarf on its tile too.
const BED := "base:furniture:log_bed"
const POST := "base:furniture:log_fence"
const SPOT := Vector3i(33,20,45)

func _run() -> void:
	create_timer(120).timeout.connect(func(): push_error("Plan recheck test timed out"); quit(1))
	await _setup_crafting_fixture()
	var item: String = furniture.get_defs()[BED].item_key
	drops.restore_loose_item(item,Vector3(36.5,21,40.5),0,1)
	furniture.activate_for(BED,true)
	furniture._hover_cell = SPOT
	furniture._yaw = 1
	furniture._confirm_ghost()
	furniture.deactivate()
	_expect(furniture._ghosts.size()==1,"a bed is planned")
	var ghost = furniture._ghosts.values()[0]
	var cell: Vector3i = ghost.footprint_cells().back()
	var floor_id: int = world.get_block(cell.x,cell.y,cell.z)
	_expect(furniture._can_build_ghost(ghost),"the planned spot is good")
	# The floor goes before a dwarf reaches the plan.
	await _set_floor(cell,blocks.AIR_ID)
	_expect(not furniture._can_build_ghost(ghost),"with its floor gone the plan can't be built")
	await _run_for(4.0)
	_expect(furniture.get_installed_pieces().is_empty() and _units(item)==1,"no piece over the hole, and the item is intact")
	await _set_floor(cell,floor_id)
	# The floor goes during the set-down itself.
	_expect(await _working(ghost),"a dwarf starts setting the bed down")
	await _set_floor(cell,blocks.AIR_ID)
	await _run_for(6.0)
	_expect(furniture.get_installed_pieces().is_empty() and _units(item)==1,"a floor lost during the set-down keeps the exact item")
	await _set_floor(cell,floor_id)
	# A dwarf stands in the way.
	_expect(await _working(ghost),"a dwarf starts on it again")
	var factory = load("res://scripts/entities/DwarfFactory.gd").new()
	var other = factory.spawn(factory.generate(142,{}),142)
	scene.add_child(other)
	other.set_process(false)
	tasks.register_dwarf(other)
	other.position = Vector3(cell)+Vector3(.5,1,.5)
	_expect(not furniture._can_build_ghost(ghost),"a dwarf in the footprint holds the plan back")
	await _run_for(6.0)
	_expect(furniture.get_installed_pieces().is_empty() and _units(item)==1,"nothing installs over a dwarf")
	other.position = Vector3(50.5,21,50.5)
	for task in tasks._tasks.values(): task.retry_at = 0
	for i in 800:
		tasks._process(.05)
		worker._process(.05)
		await process_frame
		if not furniture.get_installed_pieces().is_empty(): break
	_expect(furniture.get_installed_pieces().size()==1 and _units(item)==0,"with the spot clear again the plan is built from the same item")
	_expect(tasks.lifecycle_errors().is_empty(),"refusals keep valid work ownership")
	# A fence post rechecks its tile too: one put up on a dwarf walls it in (the project review,
	# 2026-11-09: the dwarf showed "Trapped" with nothing to free it).
	var post_tile := Vector3i(40,20,50)
	furniture.activate_for(POST)
	furniture._hover_cell = post_tile
	furniture._confirm_ghost()
	furniture.deactivate()
	var posts: Array = furniture._ghosts.values().filter(func(planned): return planned.furniture_key == POST)
	_expect(posts.size() == 1, "a fence post is planned")
	if posts.size() == 1:
		other.position = Vector3(post_tile)+Vector3(.5,1,.5)
		_expect(not furniture._can_build_ghost(posts[0]),"a dwarf on a post's tile holds the post back")
		other.position = Vector3(50.5,21,50.5)
		_expect(furniture._can_build_ghost(posts[0]),"with the tile clear the post can go up")
	for failure in failures: push_error(failure)
	print("FURNITURE_PLAN_RECHECK_OK" if failures.is_empty() else "FURNITURE_PLAN_RECHECK_FAIL")
	quit(0 if failures.is_empty() else 1)

func _set_floor(cell: Vector3i, id: int) -> void:
	world.set_block(cell.x,cell.y,cell.z,id)
	await process_frame
	await process_frame
	for task in tasks._tasks.values(): task.retry_at = 0

func _working(_ghost) -> bool:
	for i in 800:
		if worker._task_phase in [worker.TaskPhase.FETCH_WORKING,worker.TaskPhase.FETCH_DEPOSIT]: return true
		tasks._process(.05)
		worker._process(.05)
		await process_frame
	return false

func _units(key: String) -> int:
	return int(inventory_script.snapshot(drops,furniture).get(key,{}).get("total",0))

func _run_for(seconds: float) -> void:
	for i in int(seconds/.05):
		tasks._process(.05)
		worker._process(.05)
		await process_frame
