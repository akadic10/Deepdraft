extends "res://scripts/tests/WorkerCraftingTest.gd"

## The food shelf (doc 299, A, the lean-to rack; owner, 2026-11-06), the first storage furniture to
## hold food, on the fixture's open plain at Y20:
## - only a Carpenter makes it, from two logs at the carpenter's bench; Place files it under Storage;
## - it keeps the ten foods dwarves eat and nothing else, one crate to each of six places, at
##   priority 4: food moves up from the ground and new food goes to it first, the upper deck first;
## - a crate stands straight on its deck at its anchor; a dwarf stands beside the place goods go to,
##   and the hands reach for it;
## - its window counts places and goods, and its Keeping list reads its own spot, empty or not;
## - dwarves eat from it, reaching up to the upper deck, and a portion leaves with its crate's spoil;
## - its food spoils as on the floor beside it, warns and rots in Events, and claimed portions stay;
## - fresh food keeps apart from a stale crate while a place is free;
## - a save keeps each crate and its spoil, and taking the piece away drops crates with theirs;
## - a room counts the shelf's appeal, and no stocked storage for the food on it.
const SHELF := "base:furniture:food_shelf"
const SHELF_ITEM := "base:resources:furniture:food_shelf"
const SHELF_RECIPE := "base:recipe:worker:food_shelf"
const APPLE := "base:resources:flora:apple"
const BLUEBERRY := "base:resources:flora:blueberry"
const ELDERBERRY := "base:resources:flora:elderberry"
const JUNIPER := "base:resources:flora:juniper_berry"
const PERCH := "base:resources:fish:perch"
const TROUT := "base:resources:fish:trout"
const DRIED := "base:resources:fish:dried_fish"
const HOPS := "base:resources:flora:hops"
const GRAPE := "base:resources:flora:grape"
const HELMET := "base:resources:flora:plump_helmet"
const PIG_TAIL := "base:resources:flora:pig_tail"
const ORIGIN := Vector3i(36, 20, 40)   # its back-left floor cell; it covers X 36..38 at Z 40
const UPPER := 31.0 / 16               # the top of its upper deck's poles
const LOWER := 12.0 / 16               # the top of its lower deck's poles
const DROP := Vector3(41.5, 21, 40.5)  # where new goods turn up
var spoilage
var events
var watched = null            # the shelf whose deliveries _until_true watches
var delivered := {}           # its places seen filled
var longest_reach := 0.0      # the furthest a dwarf stood from a place as a crate landed on it


func _run() -> void:
	create_timer(200).timeout.connect(func(): push_error("Food shelf test timed out"); quit(1))
	await _setup_crafting_fixture()
	spoilage = stockpiles.spoilage
	events = root.get_node("EventLog")
	root.get_node("WeatherManager").set_weather("base:weather:clear")
	var recipe: Dictionary = crafting.recipes[SHELF_RECIPE]
	_expect(String(recipe.get("section", "")) == "carpenter" and recipe.workshop == "base:furniture:carpenter_bench" and String(recipe.category) == "Storage"
		and int(recipe.ingredient_count) == 2 and PINE in crafting.ingredient_keys(recipe), "the shelf: two logs at the carpenter's bench, on the Carpenter's page")
	var placed: Array = root.get_node("UIRegistry").get_place_catalog().get("items", []).filter(func(entry): return entry.key == SHELF)
	_expect(placed.size() == 1 and placed[0].category == "storage", "Place files it under Storage")
	_carpenter_bench_at(Vector3i(44, 20, 41))
	drops.spawn_drop(PINE, 2, Vector3i(42, 21, 40))
	var id: int = crafting.queue_order(SHELF_RECIPE, 1)
	_expect(await _completed(id) and _count(SHELF_ITEM) == 1 and _count(PINE) == 0, "two logs make one packed shelf")
	# With no shelf yet, food goes to ground storage.
	drops.restore_loose_item(APPLE, DROP, 0, 24)
	_expect(await _until_true(func(): return int(zone.contents().get(APPLE, 0)) == 24), "with no shelf, a crate of apples goes to ground storage")
	furniture.activate_for(SHELF, true)
	furniture._hover_cell = ORIGIN
	furniture._yaw = 0
	_expect(furniture._placement_valid(ORIGIN), "the shelf may stand on open floor")
	furniture._confirm_ghost()
	furniture.deactivate()
	_expect(await _installed(SHELF) and _count(SHELF_ITEM) == 0, "a dwarf sets the shelf up")
	var piece = _shelf_piece()
	var shelf = piece.storage
	_expect(shelf != null and stockpiles.is_registered(shelf) and shelf.priority == 4 and shelf.storage_capacity() == 6 and shelf.per_slot == 1
		and shelf.slot_word == "places" and piece.cells.size() == 3 and piece.material_id == "base:material:pine", "it is a pine store of six places, at priority 4")
	_kinds(shelf)
	_expect(_place_of(shelf) == Vector3i(37, 21, 40), "an empty shelf's Keeping list reads its own spot")
	_expect(shelf.usage_text() == "0 / 6 places" or shelf.usage_text() == "1 / 6 places · 24 goods", "its window counts places: %s" % shelf.usage_text())
	await _fills(shelf)
	await _meal(shelf)
	await _spoils(shelf)
	_rots(shelf)
	_keeps_apart(shelf)
	_appeal(shelf)
	await _saves()
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("FOOD_SHELF_OK: Carpenters make it, food only, six crates on two decks at priority 4, meals, spoilage, rot, keeping apart, appeal, saves and dropped crates")
	quit(0 if failures.is_empty() else 1)


## Its filter lists the ten foods dwarves eat, and narrowing it names the one it keeps.
func _kinds(shelf) -> void:
	var allowed: Array = shelf.allowed_keys()
	_expect(allowed.size() == 10 and APPLE in allowed and JUNIPER in allowed and TROUT in allowed and DRIED in allowed, "its filter lists the ten foods: %s" % [allowed])
	for key: String in [HOPS, GRAPE, HELMET, PIG_TAIL, STONE, PINE]:
		_expect(not key in allowed and not shelf.accepts_key(key), "it refuses %s" % key)
	for key: String in allowed:
		if key != APPLE: shelf.set_item_accepted(key, false)
	_expect(shelf.chosen_key() == APPLE and furniture.get_furniture_storage().title(_shelf_piece()) == "Pine food shelf · Apple", "narrowed to apples, its title names them")
	for key: String in allowed: shelf.set_item_accepted(key, true)
	_expect(shelf.chosen_key().is_empty() and allowed.all(shelf.accepts_key), "opened again, it keeps them all")


## Food moves up from the ground and new food comes to it first, until its six places are full.
func _fills(shelf) -> void:
	watched = shelf
	_expect(await _until_true(func(): return int(shelf.contents().get(APPLE, 0)) == 24 and not zone.contents().has(APPLE)), "the apples move up from ground storage to the shelf")
	_expect(_stands(shelf, 0, UPPER) and shelf.stored_entries().size() == 1, "the crate stands straight on the upper deck, which fills first")
	# The hands reach for the place goods are going to, whichever deck is nearest.
	var token: Dictionary = shelf._reserve_deposit(BLUEBERRY, ORIGIN, worker.dwarf_id, 4, "", 0.0)
	_expect(token.slot == 1 and shelf.delivery_contact(Vector3i(37, 20, 41)).is_equal_approx(shelf.anchor_position(1)), "the hands reach for the place on the upper deck that goods go to")
	shelf._release_deposit(token)
	for food: Array in [[BLUEBERRY, 14], [JUNIPER, 6], [PERCH, 20], [DRIED, 24], [ELDERBERRY, 24]]:
		drops.restore_loose_item(food[0], DROP, 0, food[1])
	_expect(await _until_true(func(): return shelf.storage_used() == 6), "five more crates go to it ahead of the ground: %s" % [shelf.contents()])
	watched = null
	_expect(delivered.size() == 6 and longest_reach < 1.3, "each time a dwarf stands beside the place the crate goes to: %.2f blocks at most" % longest_reach)
	_expect(zone.contents().is_empty(), "nothing is left on the ground: %s" % [zone.contents()])
	drops.restore_loose_item(TROUT, DROP, 0, 10)
	_expect(await _until_true(func(): return int(zone.contents().get(TROUT, 0)) == 10), "with its six places taken, a seventh food goes to the ground")
	_clear_ground()
	for slot: int in range(6): _expect(_stands(shelf, slot, UPPER if slot < 3 else LOWER), "the crate in place %d stands straight on its deck" % slot)
	_expect(shelf.usage_text() == "6 / 6 places · 112 goods" and shelf.storage_used() == 6, "its window counts places and goods: %s" % shelf.usage_text())
	_expect(shelf.capacity_hint() == "One crate of food to each of its places.", "its capacity bar says what a place takes: %s" % shelf.capacity_hint())
	_expect(_count(APPLE) == 24 and _count(ELDERBERRY) == 24, "the colony's counts include it")


## A hungry dwarf eats from it, reaching up to the upper deck. The portion leaves with its spoil.
func _meal(shelf) -> void:
	shelf.stored_entries()[0]["spoil"] = 0.5
	worker.force_interrupt()
	if worker.is_sleeping(): worker._wake_up()
	worker._idle_behavior.cancel()
	worker.stop_walking()
	worker.sleep = 1.0
	worker._food.value = .3
	worker._food.retry_hours = 0
	_expect(await _food_phase("pickup"), "a hungry dwarf walks to the shelf")
	_expect(worker._food._quote.key == APPLE and absf(worker._food._reach.y - UPPER) < .01, "they take the oldest food, reaching up to the upper deck: %s at %.2f" % [worker._food._quote.key, worker._food._reach.y])
	_expect(await _food_phase("eating"), "they take a portion")
	_expect(is_equal_approx(drops.spoil_of(worker._food.portion), 0.5), "the portion keeps its crate's spoil: %.2f" % drops.spoil_of(worker._food.portion))
	for i in range(600):
		if not worker.is_eating(): break
		worker._process(.05)
		await process_frame
	_expect(not worker.is_eating(), "the meal finishes")
	_expect(int(shelf.contents().get(APPLE, 0)) == 23 and drops.quantity_of(shelf._shown[0]) == 23 and _count(APPLE) == 23, "one portion left the crate, which shows the lower fill")
	worker._food.value = 1.0


## Its food spoils as on the floor beside it, and its crates show their spoil.
func _spoils(shelf) -> void:
	var slot: int = _slot_of(shelf, PERCH)
	var stack: Dictionary = shelf.stored_entries()[slot]
	var cell := Vector3i(40, 20, 44)
	zone.cell_stacks[cell] = {"item": TROUT, "count": 10}
	drops.restore_stored_item(TROUT, cell, 10)
	stockpiles.rebuild_totals()
	var hours := 6.0
	var expected: float = hours * spoilage.speed_at(shelf.slot_cell(slot) + Vector3i.UP) / (24.0 * 2.0)
	spoilage.run(hours)
	_expect(is_equal_approx(float(stack.spoil), expected), "perch on the shelf gains %.4f in %d hours, as the rule says: %.4f" % [expected, int(hours), float(stack.spoil)])
	_expect(absf(float(stack.spoil) - float(zone.cell_stacks[cell].get("spoil", 0.0))) < .001, "and as a fish of the same keeping on the floor beside it: %.4f" % float(zone.cell_stacks[cell].get("spoil", 0.0)))
	_expect(is_equal_approx(drops.spoil_of(shelf._shown[slot]), float(stack.spoil)), "its crate shows its spoil")
	var keeping = load("res://scripts/ui/StorageKeeping.gd").new()
	keeping.sizes = {"heading": 20, "hint": 16, "exact": 48, "heading_width": 150, "bar": 10, "gap": 8}
	_expect(keeping.show_storage(shelf) and keeping.rows.any(func(row: Dictionary) -> bool: return row.key == PERCH and is_equal_approx(float(row.spoil), float(stack.spoil)))
		and String(keeping.heading).ends_with("under the open sky"), "the Keeping list has its rows: %s" % keeping.heading)
	keeping.free()
	_clear_ground()


## It warns and rots in Events by its own name; claimed portions stay until used.
func _rots(shelf) -> void:
	var slot: int = _slot_of(shelf, ELDERBERRY)
	shelf.stored_entries()[slot]["spoil"] = 0.99
	shelf.stored_entries()[_slot_of(shelf, DRIED)]["spoil"] = 0.7495
	spoilage.run(1.0)
	var lines: Array = events.entries().slice(0, 2).map(func(entry: Dictionary) -> String: return String(entry.text))
	_expect(not shelf.stored_entries().has(slot) and not shelf._shown.has(slot) and stockpiles.get_total(ELDERBERRY) == 0, "a rotten crate goes, model and count")
	_expect(lines.has("24 elderberries rotted on the food shelf.") and lines.any(func(line: String) -> bool: return line.begins_with("Dried fish on the food shelf are going bad")),
		"Events tells of the rot and warns of a crate passing 75%%: %s" % [lines])
	var berries: int = _slot_of(shelf, BLUEBERRY)
	shelf.stored_entries()[berries]["spoil"] = 0.99
	var claim: Dictionary = shelf.reserve_portion(berries, BLUEBERRY, worker.dwarf_id)
	spoilage.run(1.0)
	_expect(not claim.is_empty() and int(shelf.stored_entries()[berries].count) == 1 and drops.quantity_of(shelf._shown[berries]) == 1
		and String(events.entries()[0].text) == "13 blueberries rotted on the food shelf.", "a portion claimed for a meal stays; the rest of the crate rots")
	shelf.release_outgoing(claim)
	spoilage.run(1.0)
	_expect(not shelf.stored_entries().has(berries) and String(events.entries()[0].text) == "1 blueberry rotted on the food shelf.", "released, it rots at the next hour")


## Fresh food starts a place of its own rather than joining a stale crate while one is free.
func _keeps_apart(shelf) -> void:
	var slot: int = _slot_of(shelf, APPLE)
	shelf.stored_entries()[slot]["spoil"] = 0.9
	var fresh: Dictionary = shelf._reserve_deposit(APPLE, ORIGIN, worker.dwarf_id, 1, "", 0.0)
	_expect(fresh.slot != slot and not shelf.stored_entries().has(fresh.slot), "fresh apples take an empty place, not a crate close to rotting")
	shelf._release_deposit(fresh)
	var like: Dictionary = shelf._reserve_deposit(APPLE, ORIGIN, worker.dwarf_id, 1, "", 0.8)
	_expect(like.slot == slot, "apples of like freshness top it up")
	shelf._release_deposit(like)


## A room counts the shelf's appeal, and no stocked storage for the food on it.
func _appeal(shelf) -> void:
	var air := {}
	for x in range(30, 50):
		for z in range(34, 50): air[Vector3i(x, 21, z)] = true
	zone.cell_stacks[Vector3i(40, 20, 44)] = {"item": TROUT, "count": 10}
	var rooms: Node = root.get_node("RoomManager")
	var score: Dictionary = load("res://scripts/components/RoomAppeal.gd").score({"cells": air, "door_cells": {}, "floor_tiles": air.size()}, rooms)
	var stocked: Array = score.parts.filter(func(part: Dictionary) -> bool: return part.key == "stocked")
	var mine: Array = score.parts.filter(func(part: Dictionary) -> bool: return part.key == SHELF)
	_expect(stocked.size() == 1 and int(stocked[0].count) == 1 and mine.size() == 1 and is_equal_approx(float(mine[0].value), 1.0), "the crate on the floor counts as stocked storage, those on the shelf don't, and a pine shelf adds 1: %s" % [score.parts])
	zone.cell_stacks.clear()
	_expect(shelf.storage_used() > 0, "the shelf still holds its food")


## A save keeps each crate and its spoil; taking the piece away drops crates with theirs.
func _saves() -> void:
	var shelf = _shelf_piece().storage
	var held: Dictionary = shelf.contents()
	var spoil_of_apples := float(shelf.stored_entries()[_slot_of(shelf, APPLE)].spoil)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(furniture.serialize_state()))
	var validator = load("res://scripts/components/SaveSnapshotValidator.gd")
	var catalogs: Dictionary = root.get_node("SaveManager")._capture_catalogs()
	_expect(validator._validate(saved, validator.SCENE.furniture, "save.scene.furniture", catalogs).is_empty(), "the shelf's save keeps the save's rules")
	for installed_id: int in furniture._installed.keys(): furniture._teardown_installed(installed_id, false)
	for node in drops._loose.keys():
		drops.take(node)
		node.free()
	furniture.restore_state(saved)
	var restored = _shelf_piece().storage if _shelf_piece() != null else null
	_expect(restored != null and restored.contents() == held and restored._shown.size() == held.size(), "a save keeps its crates: %s" % [restored.contents() if restored != null else {}])
	var slot: int = _slot_of(restored, APPLE)
	_expect(is_equal_approx(float(restored.stored_entries()[slot].get("spoil", 0.0)), spoil_of_apples) and is_equal_approx(drops.spoil_of(restored._shown[slot]), spoil_of_apples),
		"and their spoil, on the crate shown too")
	_expect(_stands(restored, slot, UPPER if slot < 3 else LOWER), "and they stand on their decks")
	var count: int = int(held[APPLE])
	_expect(restored.dump_contents() > 0 and restored.stored_entries().is_empty() and restored._shown.is_empty(), "taken away, its crates drop in front of it")
	var dropped: Array = drops.loose_items().filter(func(node: Node3D) -> bool: return drops.item_key_of(node) == APPLE)
	_expect(dropped.size() == 1 and drops.quantity_of(dropped[0]) == count and is_equal_approx(drops.spoil_of(dropped[0]), spoil_of_apples), "and a dropped crate keeps its spoil")


## The crate in a place stands straight on its deck at its anchor, inside the shelf's footprint.
func _stands(shelf, slot: int, deck: float) -> bool:
	var node: Node3D = shelf._shown.get(slot)
	if not is_instance_valid(node) or node.get_parent() != shelf.display_parent: return false
	var box: AABB = node.global_transform * shelf._bounds(node)
	var floor_y: float = shelf.display_parent.global_position.y
	return node.global_position.is_equal_approx(shelf.anchor_position(slot)) and node.basis.is_equal_approx(Basis.IDENTITY) and absf(box.position.y - floor_y - deck) < .01 \
		and box.position.x >= ORIGIN.x and box.end.x <= ORIGIN.x + 3 and box.position.z >= ORIGIN.z and box.end.z <= ORIGIN.z + 1


## StorageKeeping's spot for a store: its middle cell's air.
func _place_of(shelf) -> Vector3i:
	return load("res://scripts/ui/StorageKeeping.gd")._place(shelf)


func _clear_ground() -> void:
	for cell: Vector3i in zone.cell_stacks.keys():
		var node: Node3D = drops.stored_node_at(cell)
		if node != null: node.free()
	zone.cell_stacks.clear()
	stockpiles.rebuild_totals()


func _slot_of(shelf, key: String) -> Variant:
	for slot in shelf.stored_entries():
		if String(shelf.stored_entries()[slot].item) == key: return slot
	return -1


func _food_phase(target: String, limit := 600) -> bool:
	for i in limit:
		if worker._food.state == target: return true
		worker._process(.05)
		await process_frame
	return false


func _shelf_piece():
	for piece in furniture._installed.values():
		if piece.furniture_key == SHELF: return piece
	return null


func _until_true(condition: Callable, limit := 2000) -> bool:
	for i in range(limit):
		if condition.call(): return true
		stockpiles._process(.25)
		await _tick()
		if watched != null:
			for slot in watched.stored_entries():
				if delivered.has(slot): continue
				delivered[slot] = true
				var at: Vector3 = watched.anchor_position(int(slot))
				longest_reach = maxf(longest_reach, Vector2(at.x - worker.global_position.x, at.z - worker.global_position.z).length())
	return false
