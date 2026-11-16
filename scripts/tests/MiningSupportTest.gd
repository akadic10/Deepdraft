extends "res://scripts/tests/WorkerCraftingTest.gd"

## Mining the floor under furniture or a storage cell leaves nothing floating (doc 31, doc 43).
const BED := "base:furniture:log_bed"
const CRATE := "base:furniture:raw_materials_crate"
const STONE_KEY := "base:item:rough_stone"
var zones

func _run() -> void:
	create_timer(90).timeout.connect(func(): push_error("Mining support test timed out"); quit(1))
	await _setup_crafting_fixture()
	furniture.set_process(true)
	zones = load("res://scripts/systems/StockpileDesignationController.gd").new()
	scene.add_child(zones)
	await _pieces_fall()
	await _storage_cells_fall()
	for failure in failures: push_error(failure)
	print("MINING_SUPPORT_OK" if failures.is_empty() else "MINING_SUPPORT_FAIL")
	quit(0 if failures.is_empty() else 1)

func _mine(cell: Vector3i) -> void:
	world.set_block(cell.x,cell.y,cell.z,blocks.AIR_ID)
	await _frames(3)

func _loose_of(key: String) -> Array:
	return drops._loose.keys().filter(func(node): return String(drops._loose[node])==key)

## Something solid directly under it, in the column it stands in.
func _resting(node: Node3D) -> bool:
	return blocks.is_solid(world.get_block(floori(node.position.x),floori(node.position.y)-1,floori(node.position.z)))

func _pieces_fall() -> void:
	var bed_id: int = furniture._next_installed_id
	furniture._install(BED,furniture.get_defs()[BED],Vector3i(33,20,45),1)
	var bed = furniture.get_installed(bed_id)
	var item: String = bed.item_key
	var far_cell: Vector3i = bed.cells.back()
	world.set_block(far_cell.x,far_cell.y,far_cell.z,blocks.get_id("base:terrain:rock:rock01"))
	await _frames(3)
	_expect(furniture.get_installed(bed_id)==bed,"swapping the floor for another solid block leaves the piece")
	await _mine(far_cell)
	_expect(furniture.get_installed(bed_id)==null and not furniture._cell_to_installed.has(far_cell),"mining one floor block under a bed takes the bed down")
	var packed: Array = _loose_of(item)
	_expect(packed.size()==1,"the fallen bed is one packed item")
	if packed.size()==1:
		_expect(_resting(packed[0]),"the packed bed rests on the ground, not in the air")
		drops.take(packed[0]); packed[0].free()
	var second_id: int = furniture._next_installed_id
	furniture._install(BED,furniture.get_defs()[BED],Vector3i(33,20,50),1)
	await _mine(Vector3i(33,20,50))
	packed = _loose_of(item)
	_expect(furniture.get_installed(second_id)==null and packed.size()==1 and packed[0].position.y<21.0 and _resting(packed[0]),"mined under its own spot, the packed bed drops into the hole")
	for node: Node3D in packed:
		drops.take(node); node.free()
	# A stocked crate falls with its goods.
	var crate_id: int = furniture._next_installed_id
	furniture._install(CRATE,furniture.get_defs()[CRATE],Vector3i(30,20,36),0)
	var crate = furniture.get_installed(crate_id)
	crate.storage._slots.entries[0] = {"item":STONE_KEY,"count":2,"material_id":""}
	var crate_cell: Vector3i = crate.cells[0]
	await _mine(crate_cell)
	_expect(furniture.get_installed(crate_id)==null,"mining under a crate takes the crate down")
	var stones: Array = _loose_of(STONE_KEY)
	var units := 0
	for stone: Node3D in stones:
		units += drops.quantity_of(stone)
		_expect(_resting(stone),"the crate's goods rest on solid ground")
		drops.take(stone); stone.free()
	_expect(units==2,"the crate's goods come out loose")

func _storage_cells_fall() -> void:
	var cells: Array[Vector3i] = [Vector3i(36,20,36),Vector3i(37,20,36),Vector3i(38,20,36)]
	var plot = zones._create_zone(cells.duplicate())
	var id: int = plot.zone_id
	for cell: Vector3i in [cells[0],cells[1]]:
		plot.cell_stacks[cell] = {"item":STONE_KEY,"count":1,"material_id":"","disallowed":false}
		drops.restore_stored_item(STONE_KEY,cell,1)
	stockpiles._totals[STONE_KEY] = int(stockpiles._totals.get(STONE_KEY,0))+2
	var total: int = stockpiles.get_total(STONE_KEY)
	await _mine(cells[0])
	_expect(not plot.has_cell(cells[0]) and not zones.is_zone_cell(cells[0]) and plot.cell_count()==2,"the mined cell leaves the zone and the rest stays")
	_expect(not plot.cell_stacks.has(cells[0]) and plot.cell_stacks.has(cells[1]) and is_instance_valid(drops.stored_node_at(cells[1])),"only the mined cell's goods leave storage")
	_expect(stockpiles.get_total(STONE_KEY)==total-1,"stored totals drop by the goods that fell")
	var fallen: Array = _loose_of(STONE_KEY)
	_expect(fallen.size()==1 and fallen[0].position.y<21.0 and _resting(fallen[0]),"the mined cell's goods fall into the hole")
	var saved: Array = zones.serialize_state().zones[0].cells
	_expect(saved.size()==2,"a save keeps only the cells that are left")
	# A hauler bound for a cell that goes is released, and later loads go to the cells left.
	drops.spawn_drop(STONE_KEY,1,Vector3i(39,21,39))
	plot.update_leases()
	var claimed := Vector3i(-1,-1,-1)
	for i in 400:
		tasks._process(.05)
		worker._process(.05)
		await process_frame
		if not plot.reserved_cells.is_empty():
			claimed = plot.reserved_cells.keys()[0]
			break
	_expect(claimed.x>=0,"a hauler claims a storage cell")
	if claimed.x>=0:
		await _mine(claimed)
		_expect(not plot.has_cell(claimed) and plot.reserved_cells.is_empty() and plot._pulls.is_empty(),"no claim outlives the mined cell")
		_expect(tasks.lifecycle_errors().is_empty(),"the released hauler keeps valid work ownership")
		for i in 40:
			worker._process(.05)
			await process_frame
		_expect(not plot.cell_stacks.has(claimed),"nothing is delivered to the mined cell")
	# The last cell takes the zone with it.
	var left: Array[Vector3i] = plot.tile_cells.duplicate()
	for cell: Vector3i in left: world.set_block(cell.x,cell.y,cell.z,blocks.AIR_ID)
	await _frames(3)
	_expect(zones.get_zone(id)==null,"mining the last cell removes the zone")
	for node: Node3D in _loose_of(STONE_KEY):
		_expect(_resting(node),"no goods float over the lost cells")
