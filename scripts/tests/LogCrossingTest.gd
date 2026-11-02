extends "res://scripts/tests/ConstructionTest.gd"

## Rivers are crossed on built logs (doc 32, "River crossings"); the log bridge was retired
## on 2026-10-27:
## - logs never go into standing water;
## - a real hauler and builder lay a two-wide deck of horizontal logs out from the bank, the
##   builder standing on the last finished log, and dwarves then walk across;
## - building the deck leaves the river's water alone;
## - a deck a block above its banks is reached by a log step at each end.
const PINE := "base:resources:wood:pine_log"
var water
var bank := Vector3i(45,20,40)
var far_bank := Vector3i(51,20,40)

func _run() -> void:
	create_timer(150).timeout.connect(func(): push_error("Log crossing test timed out"); quit(1))
	await _setup_fixture()
	await _new_trip(PINE,10)
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
	await _river()
	_expect(nav.find_path(bank,far_bank).is_empty(),"the river blocks an ordinary crossing")
	_expect(not construction.build_reason(Vector3i(48,19,40),true,false,"log_horizontal").is_empty(),"logs never go into standing water")
	var baseline: Dictionary = water.flow.mass.duplicate()
	var deck: Array[Vector3i] = []
	var directions := {}
	for x in range(46,51):
		for z in [40,41]:
			deck.append(Vector3i(x,20,z))
			directions[Vector3i(x,20,z)] = "x"
	var id: int = construction.create_order(deck,-1,false,"log_horizontal","pine",directions)
	_expect(id>0 and construction.orders[id].cells.size()==10,"a deck of logs is planned over the river")
	for tick in range(6000):
		await _tick()
		if construction.orders.is_empty(): break
	var built: Array = deck.map(func(cell: Vector3i) -> String: return String(blocks.get_key(world.get_terrain_block(cell.x,cell.y,cell.z))))
	_expect(built.all(func(key: String) -> bool: return key=="base:construction:log:pine:x"),"a real builder lays every log of the deck: %s" % [built])
	_expect(not nav.find_path(bank,far_bank).is_empty(),"dwarves walk across the finished deck")
	_expect(water.flow.mass==baseline,"building the deck leaves the river's water alone")
	_raised_deck()
	_expect(tasks.lifecycle_errors().is_empty(),"building the crossing leaves no orphan tasks or claims")
	for failure: String in failures: push_error(failure)
	print("LOG_CROSSING_OK" if failures.is_empty() else "LOG_CROSSING_FAIL")
	quit(0 if failures.is_empty() else 1)

## A river five blocks wide and three deep across the arena, two blocks of water in it, so
## its surface is a block below the banks.
func _river() -> void:
	# Enclose the loaded arena so a failed route cannot wander into the procedural world
	# outside this fixture.
	var rock: int = blocks.get_id("base:terrain:rock:rock01")
	for edge in range(128):
		for y in range(18,26):
			for cell: Vector3i in [Vector3i(0,y,edge),Vector3i(127,y,edge),Vector3i(edge,y,0),Vector3i(edge,y,127)]:
				world.set_block(cell.x,cell.y,cell.z,rock)
	for x in range(46,51):
		for z in range(1,127):
			for y in range(18,21): world.set_block(x,y,z,blocks.AIR_ID)
	await process_frame
	water = root.get_node("WaterManager")
	water.set_process(false)
	water._config = root.get_node("WorldGenerator").load_water_profile()
	water.moisture = load("res://scripts/components/SoilMoisture.gd").new()
	water.flow = load("res://scripts/components/WaterFlow.gd").new()
	water.flow.spans_at = func(col: Vector2i): return [Vector2i(18,128)] if col.x>=46 and col.x<=50 else [Vector2i(21,128)]
	water._water_id = blocks.get_id("base:terrain:water:source")
	water.initialized = true
	for x in range(46,51):
		for z in range(128): water.flow.seed_column(Vector3i(x,18,z),2.0)
	nav._walkable_cache.clear()
	nav._path_cache.clear()

## Where a river is level with its banks the deck goes a block higher: a log on each bank is
## the step up and down.
func _raised_deck() -> void:
	var cells: Array[Vector3i] = []
	var directions := {}
	for x in range(45,52):
		for z in [60,61]:
			cells.append(Vector3i(x,21,z))
			directions[Vector3i(x,21,z)] = "x"
	var id: int = construction.create_order(cells,-1,false,"log_horizontal","pine",directions)
	_expect(construction.dev_build_order(id)==cells.size(),"the raised deck and its bank steps are built")
	var path: Array[Vector3i] = nav.find_path(Vector3i(44,20,60),Vector3i(52,20,60))
	_expect(not path.is_empty() and path.any(func(cell: Vector3i) -> bool: return cell.y==21),"a step at each end reaches a deck a block above its banks: %s" % [path])
