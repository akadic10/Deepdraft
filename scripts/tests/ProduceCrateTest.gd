extends "res://scripts/tests/ObjectExplorerTest.gd"

const ACORN := "base:resources:seed:oak_acorn"
const BERRY := "base:resources:flora:juniper_berry"
const LOG := "base:resources:wood:oak_log"
var drops


func _run() -> void:
	create_timer(60).timeout.connect(func(): push_error("Crate test timed out"); quit(1))
	for name in ["SaveManager", "TaskManager", "WorldClock", "RoomManager", "StockpileManager"]:
		root.get_node(name).set_process(false)
	root.get_node("WorldClock").set_paused(false)
	root.get_node("WorldGenerator").world_seed = 1234
	world = root.get_node("WorldData")
	blocks = root.get_node("BlockRegistry")
	_build_floor()
	scene = Node3D.new()
	root.add_child(scene)
	current_scene = scene
	_fresh_drops()
	drops.spawn_drop(ACORN, 27, Vector3i(10,21,10))
	_expect(drops._loose.size() == 2 and _units(ACORN) == 27, "27 loose goods become two crates")
	var zone = _zone([Vector3i(20,20,20), Vector3i(21,20,20)])
	var changed := [0]
	zone.changed_callback = func(_key, amount): changed[0] += amount
	_deliver(zone, 1)
	_expect(zone.stored_count() == 27 and zone.cell_stacks.size() == 2 and changed[0] == 27, "two cells hold 24+3, aggregates count goods")
	var counts: Array = []
	for cell in zone.cell_stacks:
		counts.append(zone.cell_stacks[cell].count)
		_expect(drops.quantity_of(drops.stored_node_at(cell)) == int(zone.cell_stacks[cell].count), "stored art tracks stack quantity")
	counts.sort()
	_expect(counts == [3,24], "full crate precedes partial crate")
	drops.release_stored_cells(zone.cell_stacks)
	_expect(_units(ACORN) == 27 and drops._loose.size() == 2, "zone removal releases crates without duplicating their contents")

	_fresh_drops()
	drops.spawn_drop(ACORN,5,Vector3i(10,21,10))
	var claimed: Node3D = drops._loose.keys()[0]
	drops.reserve(claimed,77)
	drops.spawn_drop(ACORN,4,Vector3i(10,21,10))
	_expect(drops.quantity_of(claimed) == 5 and drops._loose.size() == 2, "spawning cannot mutate a claimed crate")
	drops.unreserve(claimed,77)
	drops.spawn_drop(ACORN,3,Vector3i(10,21,10))
	_expect(_units(ACORN) == 12 and drops._loose.size() == 2, "new loose goods top up nearby available crates")

	_fresh_drops()
	zone = _zone([Vector3i(20,20,20)])
	zone.cell_stacks[Vector3i(20,20,20)] = {"item": ACORN, "count": 21}
	drops.restore_stored_item(ACORN, Vector3i(20,20,20), 21)
	drops.restore_loose_item(BERRY, Vector3(19.5,21,20.5), 0, 8)
	drops.restore_loose_item(ACORN, Vector3(25.5,21,20.5), 0, 7)
	var pull: Dictionary = zone.reserve_haul(2, Vector3i(19,20,20), {})
	_expect(pull.items.size() == 1 and drops.item_key_of(pull.items[0]) == ACORN, "full zone finds compatible refill past a nearer wrong type")
	var cargo: Node3D = zone.take_item(2,0)
	_expect(drops.quantity_of(cargo) == 3 and _units(ACORN) == 4, "pickup splits only the three units that fit")
	_expect(zone.commit_haul(2, [[cargo,ACORN]]) and zone.stored_count() == 24, "partial refill reaches 24 without needing an empty tile")
	var withdrawn: Node3D = zone.withdraw_nearest(ACORN, Vector3i.ZERO,3)
	_expect(drops.quantity_of(withdrawn) == 1 and zone.stored_count() == 23, "withdraw one unit retains the remaining crate")
	_expect(drops.quantity_of(drops.stored_node_at(Vector3i(20,20,20))) == 23, "withdraw updates visible fill")
	drops.take(withdrawn)
	withdrawn.free()
	var first: Variant = zone._reserve_deposit(ACORN, Vector3i.ZERO,4,24)
	_expect(first != null and int(first.count) == 1, "reserve remaining space only")
	_expect(zone._reserve_deposit(ACORN,Vector3i.ZERO,5,1) == null, "second hauler cannot overbook a crate")
	zone._release_deposit(first)
	var second: Variant = zone._reserve_deposit(ACORN,Vector3i.ZERO,5,1)
	zone._release_deposit(first)
	_expect(zone.reserved_cells.size() == 1, "stale release cannot remove a new owner's reservation")
	zone._release_deposit(second)

	_fresh_drops()
	zone = _zone([Vector3i(20,20,20)])
	# Larger test-only budget stresses identical tokens within one pull.
	zone.carry_capacity = 16
	for x in range(4):
		drops.restore_loose_item(ACORN,Vector3(10.5+x,21,10.5))
	_deliver(zone,20)
	_expect(zone.stored_count() == 4 and zone.cell_stacks.size() == 1, "identical one-unit tokens stay paired with four distinct pickups")
	drops.restore_loose_item(ACORN,Vector3(11.5,21,12.5),0,5)
	drops.restore_loose_item(ACORN,Vector3(13.5,21,12.5),0,6)
	zone.carry_capacity = 4
	var pull_a: Dictionary = zone.reserve_haul(21,Vector3i(11,20,12),{})
	var pull_b: Dictionary = zone.reserve_haul(22,Vector3i(13,20,12),{})
	_expect(not pull_a.is_empty() and not pull_b.is_empty(), "two haulers share remaining crate capacity")
	var cargo_a: Node3D = zone.take_item(21,0)
	var cargo_b: Node3D = zone.take_item(22,0)
	_expect(zone.commit_haul(22,[[cargo_b,ACORN]]) and zone.commit_haul(21,[[cargo_a,ACORN]]), "concurrent refills commit in either order")
	_expect(zone.stored_count() == 15 and zone.cell_stacks.size() == 1, "parallel haulers fill one crate without wasting another slot")

	# Different item types, path skips and reordered pickup must retain their
	# own deposit/quantity rather than consuming the next arbitrary token.
	_fresh_drops()
	zone = _zone([Vector3i(30,20,30),Vector3i(31,20,30),Vector3i(32,20,30),Vector3i(33,20,30)])
	# Test token pairing with three crates and a log in a custom-capacity load.
	zone.carry_capacity = 14
	drops.restore_loose_item(ACORN, Vector3(10.5,21,10.5),0,5)
	drops.restore_loose_item(BERRY, Vector3(12.5,21,10.5),0,9)
	drops.restore_loose_item(LOG, Vector3(7.5,21,10.5))
	drops.restore_loose_item(ACORN, Vector3(13.5,21,10.5),0,7)
	pull = zone.reserve_haul(6,Vector3i(10,20,10),{})
	zone.skip_item(6,1)
	var carried: Array = []
	for i in [2,0,3]:
		cargo = zone.take_item(6,i)
		carried.append([cargo,drops.item_key_of(cargo)])
	_expect(zone.commit_haul(6,carried), "reordered cargo and a skipped berry deliver successfully")
	_expect(zone.stored_count() == 13 and zone.cell_stacks.size() == 2, "matching acorns merge while log stays individual")
	_expect(_units(BERRY) == 9 and zone.reserved_cells.is_empty() and drops._reserved.is_empty(), "skipped crate and reservations remain safe")

	_fresh_drops()
	zone = _zone([Vector3i(20,20,20)])
	drops.restore_loose_item(ACORN, Vector3(10.5,21,10.5),0,17)
	pull = zone.reserve_haul(7,Vector3i(10,20,10),{})
	cargo = zone.take_item(7,0)
	scene.add_child(cargo)
	zone.cancel_haul(7)
	zone.cancel_haul(7)
	drops.drop_loose(cargo,Vector3i(12,20,12))
	_expect(_units(ACORN) == 17 and zone.reserved_cells.is_empty(), "interrupted haul drops all 17 contents and releases storage")
	var dwarf = load("res://scripts/entities/DwarfAgent.gd").new()
	dwarf._carried_entries = [[cargo,ACORN]]
	_expect(dwarf.serialize_state().carried_items[0].count == 17, "carrier snapshot records crate quantity")
	dwarf._carried_entries.clear()
	dwarf.free()
	var saved: Dictionary = JSON.parse_string(JSON.stringify(drops.serialize_state()))
	_fresh_drops()
	drops.restore_state(saved)
	_expect(_units(ACORN) == 17, "loose crate quantity round trips through JSON")
	drops.restore_state({"loose":[{"item_key":ACORN,"position":[1.5,21,1.5]}]})
	_expect(_units(ACORN) == 18, "old uncounted item saves restore as one unit")
	var node: Node3D = drops._loose.keys()[0]
	var info: Dictionary = drops.get_explorer_data(node)
	_expect(info.title == drops.get_item_def(ACORN).display_name and info.rows[1][1] == "17 / 24", "explorer shows exact count and item name")
	var center: Vector3 = drops.get_explorer_bounds(node).get_center()
	_expect(not drops.pick_explorer_object(center + Vector3(0,5,0), center - Vector3(0,5,0)).is_empty(), "crate mesh is clickable")
	drops._on_slice_changed(19)
	_expect(drops.get_explorer_data(node).is_empty(), "slice hides crate inspection")
	drops._on_slice_changed(127)

	_fresh_drops()
	var furniture = load("res://scripts/systems/FurniturePlacementController.gd").new()
	scene.add_child(furniture)
	var def: Dictionary = furniture.get_defs()["base:furniture:storage_shelf"]
	furniture.free()
	var shelf = load("res://scripts/components/ContainerStorageComponent.gd").new()
	var shelf_cells: Array[Vector3i] = [Vector3i(50,20,50)]
	shelf.setup_container(def,shelf_cells)
	shelf.drop_manager = drops
	shelf.display_parent = Node3D.new()
	scene.add_child(shelf.display_parent)
	shelf.restore_inventory({ACORN:27,BERRY:17},drops)
	_expect(shelf.occupied_slots() == 3 and shelf.stored_count() == 44, "shelf counts three crates and 44 goods")
	drops.restore_loose_item(ACORN,Vector3(48.5,21,48.5),0,6)
	_deliver(shelf,8)
	_expect(shelf.occupied_slots() == 3 and shelf.inventory[ACORN] == 33, "shelf tops up its existing partial crate")
	var visual_count := 0
	for entry in shelf._anchor_slots:
		if entry != null:
			visual_count += drops.quantity_of(entry[0])
	_expect(visual_count == 50, "shelf visuals represent all stored units")
	withdrawn = shelf.withdraw_nearest(ACORN,Vector3i.ZERO,9)
	_expect(withdrawn != null and drops.quantity_of(withdrawn) == 1 and shelf.inventory[ACORN] == 32, "shelf withdrawal decrements one unit")
	drops.take(withdrawn)
	withdrawn.free()
	_expect(shelf.dump_contents(Vector3i(50,20,50)) == 49 and _units(ACORN) == 32 and _units(BERRY) == 17, "uninstall returns all crate contents")

	await _worker_haul()
	for failure in failures:
		push_error(failure)
	if failures.is_empty():
		print("PRODUCE_CRATES_OK: loose packing, partial refill, split pickup, reservations, skipped/reordered cargo, interruption, JSON, explorer, shelf, withdraw, uninstall, real dwarf hauling")
	quit(0 if failures.is_empty() else 1)


func _fresh_drops() -> void:
	if is_instance_valid(drops):
		drops.free()
	drops = load("res://scripts/systems/ItemDropManager.gd").new()
	scene.add_child(drops)


func _zone(cells: Array[Vector3i]):
	var zone = load("res://scripts/components/StockpileZoneComponent.gd").new()
	zone.setup(900,cells)
	zone.drop_manager = drops
	return zone


func _units(key: String) -> int:
	var total := 0
	for node in drops._loose:
		if drops.item_key_of(node) == key:
			total += drops.quantity_of(node)
	return total


func _deliver(storage, owner: int) -> void:
	for trip in range(32):
		var pull: Dictionary = storage.reserve_haul(owner,Vector3i(10,20,10),{})
		if trip == 0: _expect(not pull.is_empty(), "haul reserves available crates")
		if pull.is_empty(): return
		var carried: Array = []
		for i in range(pull.items.size()):
			var node: Node3D = storage.take_item(owner,i)
			carried.append([node,drops.item_key_of(node)])
		_expect(storage.commit_haul(owner,carried), "reserved crates commit")
	_expect(false, "crate delivery finishes within 32 trips")


func _worker_haul() -> void:
	_fresh_drops()
	var stockpiles = root.get_node("StockpileManager")
	stockpiles.reset_runtime_state()
	stockpiles._process(0)
	var zone = _zone([Vector3i(60,20,60),Vector3i(61,20,60)])
	stockpiles.register_zone(zone)
	drops.spawn_drop(ACORN,27,Vector3i(56,21,60))
	var factory = load("res://scripts/entities/DwarfFactory.gd").new()
	var worker = factory.spawn(factory.generate(991,{}),991)
	scene.add_child(worker)
	worker.position = Vector3(54.5,21,60.5)
	worker.set_process(false)
	var tasks = root.get_node("TaskManager")
	tasks.register_dwarf(worker)
	for i in range(1800):
		stockpiles._process(.3)
		tasks._run_scheduler()
		worker._process(.1)
		if zone.stored_count() == 27:
			break
		if i % 30 == 0:
			await process_frame
	_expect(zone.stored_count() == 27 and zone.cell_stacks.size() == 2, "actual dwarf picks up and delivers two crates")
	_expect(stockpiles.get_total(ACORN) == 27, "colony aggregate reports 27 goods")
