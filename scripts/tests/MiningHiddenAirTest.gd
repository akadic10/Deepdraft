extends "res://scripts/tests/MiningAnimationTest.gd"

## Zone pulls must terminate when a planned block is not solid in the live
## world (review doc 254 §4.1). Before the fix the worker re-pulled the same
## air block from its own stand forever (_begin_swinging -> _zone_pull_next ->
## _zone_try_stand -> _begin_swinging) until the stack overflowed.
##   A. Known air (e.g. a cave revealed by the previous commit, still planned
##      until the deferred cleanup) is skipped; the next block is worked.
##   B. Undiscovered cave air is worked as the strata the slice shows, and the
##      commit breaks into the cave and reveals it. No goods come from air.

const LATERAL: Array[Vector3i] = [Vector3i(1,0,0), Vector3i(-1,0,0), Vector3i(0,0,1), Vector3i(0,0,-1)]


func _run() -> void:
	create_timer(150).timeout.connect(func(): push_error("Mining hidden air test timed out"); quit(1))
	await _setup_mining_fixture()
	await _check_known_air_is_skipped()
	await _check_hidden_cave_air_is_mined()
	for failure in failures:
		push_error(failure)
	if failures.is_empty():
		print("MINING_HIDDEN_AIR_OK: known planned air skipped without recursion, hidden cave air mined as strata and revealed, no drop from air")
	quit(0 if failures.is_empty() else 1)


func _check_known_air_is_skipped() -> void:
	worker.position = Vector3(41.5,21,40.5)
	var rock: int = blocks.get_id("base:terrain:rock:rock01")
	var opened := Vector3i(42,21,40)   # nearest block workable from the stand
	var solid := Vector3i(42,22,40)
	world.set_block(opened.x,opened.y,opened.z,rock)
	world.set_block(solid.x,solid.y,solid.z,rock)
	var planned: Array[Vector3i] = [opened, solid]
	var zone: int = mining._create_zone(planned)
	world.set_block(opened.x,opened.y,opened.z,blocks.AIR_ID)
	_expect(await _until_mining(),"worker moves past the opened cell and starts mining")
	_expect(worker._zone_block == solid,"the remaining solid block is the one being worked")
	var source: RefCounted = worker._zone_source()
	_expect(source != null and not source.reserved.has(opened),"the opened cell keeps no reservation")
	mining._remove_zone(zone)
	world.set_block(solid.x,solid.y,solid.z,blocks.AIR_ID)
	for i in 2: await process_frame


func _check_hidden_cave_air_is_mined() -> void:
	var gen = root.get_node("WorldGenerator")
	var tracker = root.get_node("InteriorTracker")
	var nav = root.get_node("NavGrid")
	gen.generate(1234)
	while not gen._maps_ready: await process_frame
	var site := _hidden_cave_site(gen, tracker)
	_expect(not site.is_empty(),"seed 1234 has an enclosed cave cell beside a realistic stand")
	if not site.is_empty():
		var cell: Vector3i = site.cell
		var stand: Vector3i = site.stand
		for k in range(1,4):
			world.set_block(stand.x,stand.y+k,stand.z,blocks.AIR_ID)
		await process_frame
		worker.position = Vector3(stand.x+.5,stand.y+1,stand.z+.5)
		_expect(nav.is_walkable(stand) and worker.current_cell() == stand,"worker stands beside the hidden cave cell")
		_expect(not tracker.is_cave_discovered(site.cave_id) and not tracker.is_known(cell),"the cave is still undiscovered")
		_expect(not blocks.is_solid(world.get_terrain_block(cell.x,cell.y,cell.z)),"the planned cell is cave air in the live world")
		var loose_before: int = drops._loose.size()
		var planned: Array[Vector3i] = [cell]
		var zone: int = mining._create_zone(planned)
		_expect(await _until_mining(),"concealed air is worked like the rock the slice shows")
		_expect(worker._zone_block == cell,"the hidden cell is the block being worked")
		var total: float = (worker._swings_left-1)*worker._swing_time+worker._swing_timer
		worker._process(total+.02)
		await process_frame
		_expect(tracker.is_cave_discovered(site.cave_id),"breaking into the cell reveals its cave")
		_expect(not mining._zones.has(zone),"the zone completes instead of stalling on air")
		_expect(worker.current_task_id < 0,"the lease ends with the zone")
		_expect(drops._loose.size() == loose_before,"mining air yields no goods")
	gen.prepare_for_world_reload()
	world.clear_world()
	tracker.clear_runtime_state()
	nav.clear_runtime_state()
	for i in 3: await process_frame


## An undiscovered cave's top air cell beside a solid floor block whose
## three-high standing column touches no cave face-on, so real mining of that
## column would not already have revealed the cave. Clear of the fixture floor.
func _hidden_cave_site(gen, tracker) -> Dictionary:
	for cave: Dictionary in gen.get_cave_catalog():
		if cave.get("surface_open",false) or tracker.is_cave_discovered(cave.id):
			continue
		for cell: Vector3i in gen.get_cave_air_cells(cave.id):
			if cell.x < 136 and cell.z < 136:
				continue
			if gen.get_cave_id(cell+Vector3i.DOWN) != cave.id:
				continue   # needs a cave neighbour for the reveal walk
			for dir: Vector3i in LATERAL:
				if _usable_stand(gen, cell+dir):
					return {"cell":cell, "stand":cell+dir, "cave_id":cave.id}
	return {}


func _usable_stand(gen, stand: Vector3i) -> bool:
	if stand.y <= 5 or stand.y+5 >= 128:
		return false
	if gen.get_cave_id(stand) >= 0 or not blocks.is_solid(world.get_terrain_block(stand.x,stand.y,stand.z)):
		return false
	for k in range(1,5):
		var column := stand+Vector3i(0,k,0)
		if gen.get_cave_id(column) >= 0:
			return false
		if k <= 3:
			for side: Vector3i in LATERAL:
				if gen.get_cave_id(column+side) >= 0:
					return false
	return true
