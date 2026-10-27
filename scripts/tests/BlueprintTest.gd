extends "res://scripts/tests/ConstructionTest.gd"

## Blueprints (doc 273, Phase 3):
## - the four starters load, and a shared file is untrusted: another format, too large, an
##   unknown material, a block outside its size or two in one cell each refuse the file;
## - a blueprint kept as a file survives a restart; a friend's file dropped in is read, a bad
##   one named with why; rename moves the file, delete removes it;
## - Copy takes every solid block as the material that builds it, plans as their own, trimmed
##   to its blocks, and unexplored space as rock (Hard Rule 11);
## - placed turned, a copy lays the same blocks; blocks in the way are left out; one Undo takes
##   the placement back whole.
## Loaded at run time: they name autoloads, which a test script does not see as it compiles.
var Library: GDScript
var Controller: GDScript
var blueprints: Node
var library: Node

func _run() -> void:
	create_timer(90).timeout.connect(func(): push_error("Blueprint test timed out"); quit(1))
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
	Library = load("res://scripts/systems/BlueprintLibrary.gd")
	Controller = load("res://scripts/systems/BlueprintController.gd")
	blueprints = construction.blueprints
	library = root.get_node("BlueprintLibrary")
	_starter_test()
	_file_test()
	await _restart_test()
	_copy_test()
	_place_test()
	for failure: String in failures: push_error(failure)
	print("BLUEPRINT_OK" if failures.is_empty() else "BLUEPRINT_FAIL")
	quit(0 if failures.is_empty() else 1)

## Whether two lists hold the same cells in the same order, typed or not.
func _same(a: Array, b: Array) -> bool:
	return str(a) == str(b)

func _count(blocks: Dictionary) -> int:
	var total := 0
	for kind: String in blocks: total += (blocks[kind] as Array).size()
	return total

func _starter_test() -> void:
	var names: Array = library.blueprints().filter(func(b: Dictionary) -> bool: return b.starter).map(func(b: Dictionary) -> String: return b.name)
	_expect(names==["Stone hut","Log cabin","Stair flight","Garden terrace"],"the four starters load: %s" % [names])
	var cabin: Dictionary = library.get_blueprint("starter:log_cabin")
	_expect(not cabin.is_empty() and (cabin.blocks["log:pine:x"] as Array).size()==52 and (cabin.blocks["log:pine:z"] as Array).size()==48
		and (cabin.blocks["log:pine:up"] as Array).size()==6,"the log cabin starter lays pine logs both ways, with upright logs at its door")
	var hut: Dictionary = library.get_blueprint("starter:stone_hut")
	_expect(hut.size==Vector3i(5,3,5) and _count(hut.blocks)==39 and hut.blocks.has("stone"),"the stone hut is 39 stone blocks, 5 × 5, 3 tall")

func _file_test() -> void:
	var good := {"deepdraft_blueprint": 1, "name": "Good", "size": [2, 1, 1], "blocks": {"stone": [[0, 0, 0], [1, 0, 0]]}}
	_expect(Library.parse(good, "").has("blueprint"),"a good file is read")
	var cases := {
		"not a blueprint": [],
		"another version": {"deepdraft_blueprint": 2, "size": [1, 1, 1], "blocks": {"stone": [[0, 0, 0]]}},
		"too large": {"deepdraft_blueprint": 1, "size": [40, 1, 1], "blocks": {"stone": [[0, 0, 0]]}},
		"material the game does not know": {"deepdraft_blueprint": 1, "size": [1, 1, 1], "blocks": {"marble": [[0, 0, 0]]}},
		"outside its size": {"deepdraft_blueprint": 1, "size": [1, 1, 1], "blocks": {"stone": [[1, 0, 0]]}},
		"share a cell": {"deepdraft_blueprint": 1, "size": [1, 1, 1], "blocks": {"stone": [[0, 0, 0]], "dirt": [[0, 0, 0]]}},
		"not three whole numbers": {"deepdraft_blueprint": 1, "size": [1, 1, 1], "blocks": {"stone": [[0.5, 0, 0]]}},
	}
	for why: String in cases:
		var outcome: Dictionary = Library.parse(cases[why], "x")
		_expect(outcome.has("error") and String(outcome.error).contains(why.trim_prefix("not a ").trim_prefix("a ")),
			"a file is refused (%s): %s" % [why, outcome.get("error", "read")])
	var text: String = Library.to_text({"name": "Round \"trip\"", "size": Vector3i(2, 1, 1), "blocks": {"stone": [Vector3i(0, 0, 0)]}})
	var back: Dictionary = Library.parse(JSON.parse_string(text), "")
	_expect(back.has("blueprint") and back.blueprint.name=="Round \"trip\"" and _same(back.blueprint.blocks.stone, [Vector3i(0, 0, 0)]),"a file reads back as written")

func _restart_test() -> void:
	var cells: Array[Vector3i] = [Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(1, 1, 0)]
	var saved: Dictionary = library.save("Test wall", Vector3i(2, 2, 1), {"log:pine:x": cells})
	_expect(not saved.is_empty() and FileAccess.file_exists(String(saved.path)),"a blueprint is kept as its own file")
	var file := FileAccess.open(Library.FOLDER + "friends_tower.json", FileAccess.WRITE)
	file.store_string(Library.to_text({"name": "Friend's tower", "size": Vector3i(1, 2, 1), "blocks": {"stone": [Vector3i(0, 0, 0), Vector3i(0, 1, 0)]}}))
	file = null
	file = FileAccess.open(Library.FOLDER + "broken.json", FileAccess.WRITE)
	file.store_string("{\"deepdraft_blueprint\": 1, \"size\": [1, 1, 1], \"blocks\": {\"marble\": [[0, 0, 0]]}}")
	file = null
	# A fresh library, as after a restart, reads the folder.
	var fresh: Node = Library.new()
	root.add_child(fresh)
	await process_frame
	var again: Dictionary = fresh.get_blueprint(String(saved.id))
	_expect(not again.is_empty() and again.name=="Test wall" and _same(again.blocks["log:pine:x"], cells),"the blueprint, logs and all, survives a restart")
	_expect(not fresh.get_blueprint("own:friends_tower").is_empty(),"a friend's file dropped in is read")
	_expect(fresh.refused().size()==1 and String(fresh.refused()[0]).begins_with("broken.json: it uses a material"),"a bad file is named with why: %s" % [fresh.refused()])
	fresh.queue_free()
	library.rescan()
	var old_path := String(saved.path)
	var renamed: String = library.rename(String(saved.id), "Garden wall")
	_expect(renamed=="own:garden_wall" and FileAccess.file_exists(Library.FOLDER + "garden_wall.json") and not FileAccess.file_exists(old_path),
		"rename moves the file")
	_expect(library.delete(renamed) and not FileAccess.file_exists(Library.FOLDER + "garden_wall.json"),"delete removes the file")
	_expect(not library.delete("starter:stone_hut"),"a starter cannot be deleted")
	for name: String in ["friends_tower.json", "broken.json"]: DirAccess.remove_absolute(Library.FOLDER + name)
	library.rescan()

func _copy_test() -> void:
	var base := Vector3i(44, 21, 50)
	world.set_block(base.x, base.y, base.z, blocks.get_id("base:terrain:rock:rock01"))
	world.set_block(base.x+1, base.y, base.z, blocks.get_id("base:terrain:surface:dirt"))
	world.set_block(base.x+2, base.y, base.z, blocks.get_id("base:construction:log:pine:z"))
	var plan := base+Vector3i(0, 1, 0)
	var id: int = construction.create_order(_cells([plan]), -1, false, "grass")
	var copy: Dictionary = blueprints.capture(base-Vector3i(2, 0, 2), Vector3i(6, 4, 5))
	_expect(copy.size==Vector3i(3, 2, 1),"a copy is trimmed to its blocks: %s" % copy.size)
	_expect(_same(copy.blocks.stone, [Vector3i(0, 0, 0)]) and _same(copy.blocks.dirt, [Vector3i(1, 0, 0)]) and _same(copy.blocks["log:pine:z"], [Vector3i(2, 0, 0)]) and _same(copy.blocks.grass, [Vector3i(0, 1, 0)]),
		"rock copies as stone, dirt as itself, a log as its wood lying its way, a plan as its own: %s" % copy.blocks)
	var turned: Dictionary = Controller.turned(copy, 1)
	_expect(turned.has("log:pine:x") and not turned.has("log:pine:z") and turned.has("stone"),"a quarter turn turns a lying log with the blueprint: %s" % turned.keys())
	construction.cancel_order(id)
	for x in range(3): world.set_block(base.x+x, base.y, base.z, blocks.AIR_ID)
	# Unexplored space copies as rock, never as air.
	var generator = root.get_node("WorldGenerator")
	var ready: bool = generator._maps_ready
	var column: int = base.x*world.WORLD_SIZE_Z+base.z
	# Ready maps have a surface: this fixture's ground is at y 20.
	if generator.heightmap.is_empty():
		generator.heightmap.resize(world.WORLD_SIZE_X*world.WORLD_SIZE_Z)
		generator.heightmap.fill(20)
		generator.waterline_map.resize(world.WORLD_SIZE_X*world.WORLD_SIZE_Z)
		generator.waterline_map.fill(-1)
	generator._maps_ready = true
	generator._cave_layout.columns[column] = Vector3i(base.y-1, base.y+2, 4242)
	_expect(Controller.material_at(base)=="stone" and Controller.material_at(base+Vector3i.RIGHT)=="","an unexplored cave copies as rock; open air copies as nothing")
	generator._cave_layout.columns.erase(column)
	generator._maps_ready = ready

func _place_test() -> void:
	var cells: Array[Vector3i] = [Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(2, 0, 0), Vector3i(2, 1, 0)]
	var saved: Dictionary = library.save("Ell", Vector3i(3, 2, 1), {"stone": cells})
	blueprints.place(String(saved.id))
	_expect(blueprints.is_active() and blueprints.tool_bar_state().tool=="blueprint_place","Place starts placing")
	var origin := Vector3i(40, 21, 54)
	blueprints._turns = 1
	blueprints.ghost_at(origin)
	var expected: Array[Vector3i] = []
	for cell: Vector3i in Controller.turned(saved, 1).stone: expected.append(origin+cell)
	var planned: Array = blueprints._ghost_cells.stone.duplicate()
	planned.sort()
	expected.sort()
	_expect(_same(planned, expected) and Controller.turned_size(saved.size, 1)==Vector3i(1, 2, 3),"turned a quarter, the ghost lays the same blocks: %s" % [planned])
	world.set_block(expected[0].x, expected[0].y, expected[0].z, blocks.get_id("base:terrain:rock:rock01"))
	blueprints.ghost_at(origin)
	_expect(blueprints._ghost_cells.stone.size()==3 and _same(blueprints._clashes, [expected[0]]),"rock in the way is left out, shown in the way")
	var receipts: Array = []
	blueprints.order_created.connect(func(receipt: Dictionary): receipts.append(receipt))
	_expect(blueprints.place_here()==3 and receipts.size()==1,"a click plans the placement")
	_expect(blueprints.order_is_pending(receipts[0]) and blueprints.undo_order(receipts[0])==3 and construction.orders.is_empty(),"one Undo takes the placement back whole")
	world.set_block(expected[0].x, expected[0].y, expected[0].z, blocks.AIR_ID)
	blueprints.deactivate()
	library.delete(String(saved.id))
	# Logs: placed turned a quarter, each plan keeps its wood and every log lies the new way.
	var logs: Array[Vector3i] = [Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(2, 0, 0)]
	var posts: Array[Vector3i] = [Vector3i(0, 1, 0)]
	var timber: Dictionary = library.save("Rail", Vector3i(3, 2, 1), {"log:oak:x": logs, "log:oak:up": posts})
	blueprints.place(String(timber.id))
	blueprints._turns = 1
	blueprints.ghost_at(origin)
	_expect(blueprints.place_here()==4 and construction.orders.size()==2,"logs plan as one plan a kind and wood")
	var lying := 0
	var standing := 0
	for order in construction.orders.values():
		for cell: Vector3i in order.cells:
			_expect(order.wood=="oak","a placed log keeps its wood")
			if order.directions[cell]=="z": lying += 1
			if order.directions[cell]=="up": standing += 1
	_expect(lying==3 and standing==1,"turned a quarter, logs along x lie along z and upright ones stay up")
	for id: int in construction.orders.keys(): construction.cancel_order(id)
	blueprints.deactivate()
	library.delete(String(timber.id))
