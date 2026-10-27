extends "res://scripts/tests/WorkerCraftingTest.gd"

## A cave the colony has not found is rock to every placement tool (Hard Rule 11; the todo's
## "Placement tools see through undiscovered caves", fixed 2026-10-26):
## - with the slice through the cave, the pointer for furniture, storage, construction and Copy
##   stops on the cut, never falling into the cave;
## - construction refuses the cave's air with rock's own reason, and furniture and storage
##   refuse its floor.
## Once the cave is found, the same cells take the pointer and are allowed. Copy takes what the
## colony has not seen as the slice shows it: a buried deposit of cave soil and a pocket of
## water copy as stone until a dug cell beside them shows them (owner's playtest, 2026-10-26).
const CAVE := 4242
var stock
var builder
var tracker

func _run() -> void:
	create_timer(60).timeout.connect(func(): push_error("Hidden cave placement timed out"); quit(1))
	await _setup_crafting_fixture()
	tracker = root.get_node("InteriorTracker")
	var generator = root.get_node("WorldGenerator")
	# The rock a hidden cave reads as comes from the strata, which need the noise.
	generator._build_noise_instances()
	var nav = root.get_node("NavGrid")
	# A cave under columns x 44–46, z 40–42: its floor at y 13, air from 14 to 18, rock above.
	for x in range(44,47):
		for z in range(40,43):
			for y in range(14,19): world.set_block(x,y,z,blocks.AIR_ID)
			generator._cave_layout.columns[x*world.WORLD_SIZE_Z+z] = Vector3i(13,18,CAVE)
			nav.refresh_mined_block(Vector3i(x,13,z))
	stock = load("res://scripts/systems/StockpileDesignationController.gd").new()
	scene.add_child(stock)
	stock.set_process(false)
	var mining = load("res://scripts/systems/MiningDesignationController.gd").new()
	scene.add_child(mining)
	mining.set_process(false)
	builder = load("res://scripts/systems/ConstructionController.gd").new()
	builder.furniture = furniture
	builder.mining = mining
	builder.dock = dock
	scene.add_child(builder)
	builder.set_process(false)
	await _frames(2)
	_pointer_test()
	_rules_test()
	_copy_test()
	for failure: String in failures: push_error(failure)
	print("HIDDEN_CAVE_PLACEMENT_OK" if failures.is_empty() else "HIDDEN_CAVE_PLACEMENT_FAIL")
	quit(0 if failures.is_empty() else 1)


## With the slice at y 16, through the cave, every placement pointer stops on the cut.
func _pointer_test() -> void:
	var furniture_slice: int = furniture._slice_y
	var stock_slice: int = stock._slice_y
	furniture._slice_y = 16
	stock._slice_y = 16
	var point := camera.unproject_position(Vector3(45.5,17,41.5))
	var hit: Dictionary = furniture.surface_cell_for(point)
	_expect(not hit.is_empty() and Vector3i(hit.x,hit.y,hit.z)==Vector3i(45,16,41) and hit.normal==Vector3i.UP,
		"furniture, construction and Copy aim at the cut, not into the cave: %s" % hit)
	var zone_hit: Dictionary = stock._surface_cell_for(point)
	_expect(not zone_hit.is_empty() and Vector3i(zone_hit.x,zone_hit.y,zone_hit.z)==Vector3i(45,16,41),"storage aims at the cut: %s" % zone_hit)
	# The cave's water reads as its rock too.
	world.set_block(45,16,41,blocks.get_id("base:terrain:water:source"))
	hit = furniture.surface_cell_for(point)
	_expect(not hit.is_empty() and Vector3i(hit.x,hit.y,hit.z)==Vector3i(45,16,41),"a hidden cave's water stops the pointer as rock does: %s" % hit)
	world.set_block(45,16,41,blocks.AIR_ID)
	dock.tool_requested.emit("construct_copy")
	builder.blueprints._update(point)
	_expect(builder.blueprints._hover==Vector3i(45,17,41),"Copy's box stands on the cut: %s" % builder.blueprints._hover)
	builder.blueprints.deactivate()
	tracker._discovered_caves[CAVE] = true
	hit = furniture.surface_cell_for(point)
	_expect(not hit.is_empty() and int(hit.y)<16,"once found, the pointer goes into the cave: %s" % hit)
	tracker._discovered_caves.erase(CAVE)
	furniture._slice_y = furniture_slice
	stock._slice_y = stock_slice


## Construction refuses the cave's air as it refuses rock, so its reason gives nothing away;
## furniture and storage refuse the cave's floor.
func _rules_test() -> void:
	var air := Vector3i(45,14,41)
	var floor := Vector3i(45,13,41)
	var rock_reason: String = builder.build_reason(Vector3i(47,14,41))
	_expect(rock_reason=="Mine existing terrain before building" and builder.build_reason(air)==rock_reason,
		"construction refuses a hidden cave as it refuses rock: %s" % builder.build_reason(air))
	_expect(not furniture._rules.is_valid_cell(floor),"furniture refuses a hidden cave's floor")
	_expect(not stock._is_valid_cell(floor,floor.y),"storage refuses a hidden cave's floor")
	tracker._discovered_caves[CAVE] = true
	_expect(builder.build_reason(air).is_empty(),"a found cave can be built in: %s" % builder.build_reason(air))
	_expect(furniture._rules.is_valid_cell(floor),"a found cave's floor takes furniture")
	_expect(stock._is_valid_cell(floor,floor.y),"a found cave's floor takes storage")
	tracker._discovered_caves.erase(CAVE)


## A box of unexplored rock copies whole, as stone, though a deposit of cave soil and a pocket of
## water lie in it as the world made them; a cell dug beside the deposit shows it as dirt, while
## the pocket stays stone. A hidden cave copies as solid.
func _copy_test() -> void:
	var low := Vector3i(35,7,35)
	var deposit := Vector3i(36,8,36)
	var pocket := Vector3i(37,8,36)
	# Written into the generated chunk, as generation places them, not as a player's edit.
	var chunk = world._chunks[Vector3i(2,0,2)]
	for placed: Array in [[deposit,"base:terrain:soil:cave"],[pocket,"base:terrain:water:source"]]:
		var cell: Vector3i = placed[0]
		chunk.blocks[cell.x%16+16*(cell.z%16)+256*(cell.y%16)] = blocks.get_id(placed[1])
	var copy: Dictionary = builder.blueprints.capture(low,Vector3i(4,3,3))
	_expect(copy.blocks.keys()==["stone"] and (copy.blocks.stone as Array).size()==36,
		"unexplored rock copies whole, as stone: %s" % [copy.blocks.keys()])
	world.set_block(deposit.x,deposit.y+1,deposit.z,blocks.AIR_ID)
	copy = builder.blueprints.capture(low,Vector3i(4,3,3))
	_expect(str(copy.blocks.get("dirt",[]))==str([deposit-low]) and (copy.blocks.stone as Array).size()==34,
		"a deposit beside a dug cell copies as dirt; the water beyond stays stone: %s" % [copy.blocks.get("dirt",[])])
	_expect(not builder.blueprints.material_at(Vector3i(45,15,41)).is_empty(),"a hidden cave copies as solid")
