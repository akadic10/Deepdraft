extends "res://scripts/tests/ConstructionTest.gd"

## Boxed-in blocks (doc 276): a block whose four sides are all its plan's unbuilt blocks is built
## before the blocks around it, from the middle outward, its builder standing under the plan's
## own unbuilt blocks nearer the edge.
## - a real builder finishes a plus two layers tall, the shape of a log corner, its centre first;
## - the scheduler's own choices (route search, floors and continuation, each block placed at
##   once) finish the starter Log cabin, its crossed corners first, and the starter Garden
##   terrace, its inside first, each placed as one plan;
## - they finish a thick Build platform, 6 × 6 and two layers, from the middle outward;
## - the blocks around a boxed-in block wait while it can't be built just now (a dwarf stands in
##   it, or its good is not all in), then it is built first.
## Before, these corners and insides were never built.
const Shapes = preload("res://scripts/components/ConstructionShapes.gd")
const SEARCHING := 0   # NavGrid.ProbeResult: a test script compiles before the autoloads exist
const REACHABLE := 1
var blueprints: Node

func _run() -> void:
	create_timer(170).timeout.connect(func(): push_error("Construction enclosed test timed out"); quit(1))
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
	blueprints = construction.blueprints
	await _real_plus()
	await _guards()
	await _starter("starter:log_cabin",Vector3i(60,21,20),106,16,"the starter Log cabin")
	await _starter("starter:garden_terrace",Vector3i(60,21,40),48,16,"the starter Garden terrace")
	var platform: Array[Vector3i] = Shapes.rectangle(Vector3i(60,21,52),Vector3i(65,21,57),2,true,0,[])
	var id: int = construction.create_order(platform)
	await _finish(id,72,32,"a thick Build platform")
	_expect(tasks.lifecycle_errors().is_empty(),"boxed-in building leaves no orphan tasks or claims")
	for failure: String in failures: push_error(failure)
	print("CONSTRUCTION_ENCLOSED_OK" if failures.is_empty() else "CONSTRUCTION_ENCLOSED_FAIL")
	quit(0 if failures.is_empty() else 1)

## A centre with a block on each side, two layers: the shape of a log corner.
func _plus(center: Vector3i) -> Array[Vector3i]:
	var cells: Array[Vector3i] = []
	for y in range(2):
		for offset: Vector3i in [Vector3i.ZERO,Vector3i.LEFT,Vector3i.RIGHT,Vector3i.FORWARD,Vector3i.BACK]:
			cells.append(center+offset+Vector3i(0,y,0))
	return cells

## A real builder, hauling and hammering: the centre of a plus is boxed in at both layers.
func _real_plus() -> void:
	var center := Vector3i(50,21,34)
	var cells := _plus(center)
	var id: int = construction.create_order(cells)
	var order = construction.orders[id]
	var built: Array[Vector3i] = []
	for tick in range(6000):
		await _tick()
		for cell: Vector3i in cells:
			if not order.cells.has(cell) and not built.has(cell): built.append(cell)
		if not construction.orders.has(id): break
	_expect(not construction.orders.has(id),"a real builder finishes a plus whose centre is boxed in: %d of 10 built" % built.size())
	_expect(str(built.slice(0,2))==str([center,center+Vector3i.UP]),"the centre is built first, standing in an arm not yet built: %s" % [built.slice(0,2)])
	for tick in range(5): await _tick()

## The arms of a plus wait while its boxed-in centre can't be built just now, so they never
## close it off; once it can, it is built first.
func _guards() -> void:
	var center := Vector3i(56,21,34)
	var id: int = construction.create_order(_plus(center))
	var order = construction.orders[id]
	_stage(order,order.needs().keys())
	var factory = load("res://scripts/entities/DwarfFactory.gd").new()
	var idler = factory.spawn(factory.generate(143,{}),143)
	scene.add_child(idler)
	idler.set_process(false)
	tasks.register_dwarf(idler)
	idler.global_position = Vector3(center.x+.5,center.y,center.z+.5)
	_expect((await _oracle(order)).is_empty(),"the arms wait while a dwarf stands in the boxed-in centre")
	idler.global_position = Vector3(40.5,21,36.5)
	var built := await _oracle(order)
	_expect(order.cells.is_empty() and str(built.slice(0,2))==str([center,center+Vector3i.UP]),"once the dwarf leaves, the centre is built first: %s" % [built.slice(0,2)])
	construction.cancel_order(id)
	tasks.deregister_dwarf(idler.dwarf_id)
	idler.free()
	# Stone arms round a centre of dirt: the stone waits for the soil.
	center = Vector3i(56,21,40)
	var own := {center: ["dirt",""], center+Vector3i.UP: ["dirt",""]}
	id = construction.create_order(_plus(center),-1,false,"stone","",{},own)
	order = construction.orders[id]
	_stage(order,[STONE])
	_expect((await _oracle(order)).is_empty(),"stone arms wait while the boxed-in centre's soil is not all in")
	_stage(order,["base:resources:soil:soil"])
	built = await _oracle(order)
	_expect(order.cells.is_empty() and str(built.slice(0,2))==str([center,center+Vector3i.UP]),"once the soil is in, the dirt centre is built first: %s" % [built.slice(0,2)])
	construction.cancel_order(id)
	worker.global_position = Vector3(40.5,21,39.5)
	await process_frame

## A starter placed as one plan, then finished by the scheduler's own choices.
func _starter(blueprint: String, origin: Vector3i, planned: int, boxed: int, label: String) -> void:
	blueprints.place(blueprint)
	blueprints.ghost_at(origin)
	_expect(blueprints.place_here()==planned and construction.orders.size()==1,"%s is placed as one plan of %d blocks" % [label,planned])
	await _finish(construction.orders.keys()[0],planned,boxed,label)
	blueprints.deactivate()

## Finishes a plan with all its goods in, by the scheduler's own choices (`_oracle`). Every block
## must be built, and never before a deeper one (middle outward).
func _finish(id: int, planned: int, boxed: int, label: String) -> void:
	var order = construction.orders[id]
	var start: Dictionary = order.depths().duplicate()
	_expect(start.values().filter(func(depth: int) -> bool: return depth >= 2).size()==boxed,"%s has %d boxed-in blocks" % [label,boxed])
	_stage(order,order.needs().keys())
	var built := await _oracle(order)
	_expect(order.cells.is_empty(),"%s is finished: %d of %d built, left %s" % [label,built.size(),planned,order.cells.slice(0,12)])
	var outward := true
	for i in range(1,built.size()):
		if int(start[built[i]]) > int(start[built[i-1]]): outward = false
	_expect(outward,"%s is built from the middle outward, its boxed-in blocks first" % label)
	construction.cancel_order(id)
	worker.global_position = Vector3(40.5,21,39.5)
	await process_frame

## Puts all of each named good the plan needs in its crate.
func _stage(order, goods: Array) -> void:
	for good: String in goods: order.materials.staged[good] = {"": int(order.needs()[good])}

## The scheduler's own choices: each time the floor a route search reaches first and its block,
## then every block the builder keeps on with from that floor, each placed at once. The builder
## is moved to each floor it would walk to. Gives the blocks in the order they were built.
func _oracle(order) -> Array[Vector3i]:
	var built: Array[Vector3i] = []
	var progressed := true
	while progressed and not order.cells.is_empty():
		progressed = false
		var context := {}
		var result := SEARCHING
		for attempt in range(80):
			result = order.advance_fetch_plan(worker,context,24000,Time.get_ticks_usec()+5000000)
			if result != SEARCHING: break
		if result != REACHABLE or order.reserve_fetch(worker.dwarf_id,worker.current_cell()).is_empty(): break
		var stand: Vector3i = order._delivery_stands[worker.dwarf_id]
		worker.global_position = Vector3(stand.x+.5,stand.y+1,stand.z+.5)
		while true:
			var cell: Vector3i = order.target
			order.advance_install(order.remaining_work())
			if not order.commit_staged_build(worker.dwarf_id): break
			built.append(cell)
			progressed = true
			if order.cells.is_empty() or not order.continue_staged_build(worker.dwarf_id): break
		order.cancel_fetch(worker.dwarf_id)
		await process_frame
	return built
