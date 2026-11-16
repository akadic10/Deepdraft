extends "res://scripts/tests/WorkerCraftingTest.gd"

## The finished goods pallet (doc 62, A, log skids; owner, 2026-11-02): split poles on two log
## runners that hold the colony's finished goods: its packed furniture, and since 2026-11-12 its
## metal goods (owner: "the copper bars, a finished good, is not able to be stored on the finished
## goods pallet").
## - only a Carpenter makes it, from four planks (two logs until doc 308) at the carpenter's bench; Place files it under
##   Storage;
## - it keeps packed furniture, one piece to each of its four quarters, and metal goods (copper
##   bars), three to a quarter, at priority 4: they go to it ahead of the ground;
##   it takes nothing else, and a quarter keeps one kind of good;
## - each filled quarter shows its piece standing on the deck;
## - placing a piece takes it off the pallet;
## - a save keeps its pieces;
## - a Move cancelled once its piece is packed may leave that piece on the pallet, and saves still
##   pass (colony check 2026-11-09: the save check skipped goods in storage furniture).
const PALLET := "base:furniture:finished_goods_pallet"
const PALLET_ITEM := "base:item:finished_goods_pallet"
const PALLET_RECIPE := "base:recipe:finished_goods_pallet"
const STOOL := "base:furniture:log_stool"
const STOOL_ITEM := "base:item:log_stool"
const HOE := "base:item:stone_hammer"
const BAR := "base:item:copper_bar"
const OAK_PLANK := "base:item:oak_plank"
const PINE_PLANK := "base:item:pine_plank"
const COPPER_ORE := "base:item:copper_ore"
const SECOND := Vector3i(36, 20, 46)   # a second pallet's back-left floor cell, for the metal
const ORIGIN := Vector3i(36, 20, 40)   # its back-left floor cell
const DECK := 7.0 / 16                 # the top of its split poles
const DROP := Vector3(41.5, 21, 40.5)  # where new goods turn up
const MOVE_TO := Vector3i(53, 20, 44)  # a Move's destination, cancelled once the stool is packed


func _run() -> void:
	create_timer(200).timeout.connect(func(): push_error("Finished goods pallet test timed out"); quit(1))
	await _setup_crafting_fixture()
	var recipe: Dictionary = crafting.recipes[PALLET_RECIPE]
	_expect(String(recipe.get("section", "")) == "carpenter" and recipe.workshop == "base:furniture:carpenter_bench" and String(recipe.category) == "Storage"
		and int(recipe.ingredient_count) == 4 and PINE_PLANK in crafting.ingredient_keys(recipe) and not PINE in crafting.ingredient_keys(recipe),
		"the pallet: four planks, never logs, at the carpenter's bench, on the Carpenter's page")
	var placed: Array = root.get_node("UIRegistry").get_place_catalog().get("items", []).filter(func(entry): return entry.key == PALLET)
	_expect(placed.size() == 1 and placed[0].category == "storage", "Place files it under Storage")
	# A Carpenter makes it at their bench.
	_carpenter_bench_at(Vector3i(44, 20, 41))
	drops.spawn_drop(PINE_PLANK, 4, Vector3i(42, 21, 40))
	var id: int = crafting.queue_order(PALLET_RECIPE, 1)
	_expect(await _completed(id) and _count(PALLET_ITEM) == 1 and _count(PINE_PLANK) == 0, "four planks make one packed pallet")
	furniture.activate_for(PALLET, true)
	furniture._hover_cell = ORIGIN
	furniture._yaw = 0
	_expect(furniture._placement_valid(ORIGIN), "the pallet may stand on open floor")
	furniture._confirm_ghost()
	furniture.deactivate()
	_expect(await _installed(PALLET) and _count(PALLET_ITEM) == 0, "a dwarf sets the pallet down")
	var piece = _pallet_piece()
	var pallet = piece.storage
	_expect(pallet != null and stockpiles.is_registered(pallet) and pallet.priority == 4 and pallet.storage_capacity() == 4 and pallet.per_slot == 1
		and pallet.slot_word == "quarters" and piece.cells.size() == 4 and piece.material_id == "base:material:pine", "it is a pine store of four quarters, at priority 4")
	_expect(pallet.accepts_key(STOOL_ITEM) and pallet.accepts_key(PALLET_ITEM) and pallet.accepts_key(BAR),
		"it keeps packed furniture and metal goods")
	_expect(not pallet.accepts_key(STONE) and not pallet.accepts_key(PINE) and not pallet.accepts_key(HOE) and not pallet.accepts_key(COPPER_ORE),
		"and nothing else: no stone, log, tool or ore")
	# Four packed stools go to it, one to each quarter, each standing on the deck.
	for i in range(4): drops.restore_loose_item(STOOL_ITEM, DROP, 0, 1, "", false, "base:material:pine")
	_expect(await _until_true(func(): return pallet.stored_count() == 4), "four packed stools go to the pallet: %d" % pallet.stored_count())
	_expect(pallet.stored_entries().size() == 4 and pallet.stored_entries().values().all(func(stack): return int(stack.count) == 1) and not pallet.has_any_room(),
		"one to each quarter, and then it is full")
	_expect(pallet.stored_entries().keys().all(func(slot): return _on_deck(pallet, slot)), "each quarter shows its packed stool standing on the deck")
	# Placing a stool takes one off the pallet.
	furniture.activate_for(STOOL, true)
	furniture._hover_cell = Vector3i(48, 20, 36)
	_expect(furniture._placement_valid(furniture._hover_cell), "a stool may be planned on open floor")
	furniture._confirm_ghost()
	furniture.deactivate()
	_expect(await _installed(STOOL), "a dwarf fetches a stool from the pallet and places it")
	_expect(pallet.stored_count() == 3 and _count(STOOL_ITEM) == 3 and pallet._shown.size() == 3, "the pallet has three stools left: %d" % pallet.stored_count())
	# A save keeps its pieces.
	var held: Dictionary = pallet.contents()
	var saved: Dictionary = JSON.parse_string(JSON.stringify(furniture.serialize_state()))
	var validator = load("res://scripts/components/SaveSnapshotValidator.gd")
	var catalogs: Dictionary = root.get_node("SaveManager")._capture_catalogs()
	_expect(validator._validate(saved, validator.SCENE.furniture, "save.scene.furniture", catalogs).is_empty(), "the pallet's save keeps the save's rules")
	for installed_id: int in furniture._installed.keys(): furniture._teardown_installed(installed_id, false)
	for node in drops._loose.keys():
		drops.take(node)
		node.free()
	furniture.restore_state(saved)
	piece = _pallet_piece()
	var restored = piece.storage if piece != null else null
	_expect(restored != null and restored.contents() == held and restored._shown.size() == 3 and restored.stored_entries().keys().all(func(slot): return _on_deck(restored, slot)),
		"a save keeps its three stools on the deck: %s" % [restored.contents() if restored != null else {}])
	if restored != null: await _cancelled_move_on_pallet(restored, validator)
	await _metal_on_a_pallet()
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("FINISHED_GOODS_PALLET_OK: Carpenters make it, packed furniture one to a quarter at priority 4, shown on the deck, placed from it, saves, saves with a cancelled Move's piece on it, and metal goods three to a quarter with a save")
	quit(0 if failures.is_empty() else 1)


## The colony check's case (2026-11-09). A Move cancelled once its stool is packed keeps its record
## with the packed stool (FurnitureMoves.cancel); haulers store that stool on the pallet's free
## quarter; the save's goods checks must find it there.
func _cancelled_move_on_pallet(pallet, validator) -> void:
	var stool = null
	for piece in furniture._installed.values():
		if piece.furniture_key == STOOL: stool = piece
	if stool == null:
		_expect(false, "the placed stool is still installed after the save")
		return
	var stool_id: int = stool.installed_id
	furniture.begin_furniture_move(stool_id)
	furniture._yaw = 0
	furniture._hover_cell = MOVE_TO
	_expect(furniture._placement_valid(MOVE_TO), "the stool's Move may go to open floor")
	var ghost_id: int = furniture._next_ghost_id
	furniture._confirm_ghost()
	furniture.deactivate()
	var id: String = furniture._moves.for_source(stool_id)
	_expect(not id.is_empty() and furniture._ghosts.has(ghost_id), "the stool's Move is planned")
	_expect(await _until_true(func(): return furniture.get_installed(stool_id) == null), "a dwarf packs the stool")
	furniture.cancel_ghost(ghost_id)
	_expect(furniture._moves.records.has(id), "cancelling the destination once packed keeps the Move's record")
	_expect(await _until_true(func(): return pallet.stored_entries().values().any(func(stack): return String(stack.get("instance_id", "")) == id)),
		"haulers store the packed stool on the pallet's free quarter: %s" % [pallet.contents()])
	var scene := {"items": drops.serialize_state(), "stockpiles": {"zones": []}, "dwarves": {"roster": []}, "furniture": furniture.serialize_state()}
	scene = JSON.parse_string(JSON.stringify(scene))
	var error: String = validator._validate_furniture_moves(scene, validator.saved_goods(scene))
	_expect(error.is_empty(), "a save passes with the packed Move stool on the pallet: %s" % error)
	for piece: Dictionary in scene.furniture.installed:
		if piece.has("storage"): piece.storage.stacks = piece.storage.stacks.filter(func(stack): return String(stack.get("instance_id", "")) != id)
	_expect(not validator._validate_furniture_moves(scene, validator.saved_goods(scene)).is_empty(), "a save that has lost the packed stool still fails")


## Copper bars on a pallet of their own (owner, 2026-11-12): three to a quarter, one of them shown
## on the deck; ore stays off it; a save keeps them. Fittings went on 2026-11-13 (doc 306).
func _metal_on_a_pallet() -> void:
	furniture._install(PALLET, furniture.get_defs()[PALLET], SECOND, 0, "base:material:pine")
	var piece = furniture._installed[furniture._next_installed_id - 1]
	var pallet = piece.storage
	_expect(pallet != null and pallet.capacity_hint() == "One packed piece, three metal goods or four planks to each of its quarters.",
		"its bar says what a quarter takes: %s" % (pallet.capacity_hint() if pallet != null else ""))
	if pallet == null: return
	var beside := Vector3(SECOND) + Vector3(-1.5, 1, .5)
	for i in range(5): drops.restore_loose_item(BAR, beside, 0, 1)
	drops.restore_loose_item(COPPER_ORE, beside, 0, 1)
	_expect(await _until_true(func(): return pallet.stored_count() == 5), "five copper bars go to the pallet: %s" % [pallet.contents()])
	var bars: Array = []
	for stack: Dictionary in pallet.stored_entries().values():
		if String(stack.item) == BAR: bars.append(int(stack.count))
	bars.sort()
	_expect(bars == [2, 3] and pallet.stored_entries().size() == 2, "three bars fill a quarter and the next two take the next: %s" % [pallet.contents()])
	_expect(_count(COPPER_ORE) == 1 and not pallet.contents().has(COPPER_ORE), "the ore stays off it")
	_expect(pallet.usage_text() == "2 / 4 quarters · 5 goods", "it counts its quarters and its goods: %s" % pallet.usage_text())
	_expect(pallet.stored_entries().keys().all(func(slot): return _on_deck(pallet, slot)), "each filled quarter shows one of its goods on the deck")
	# Planks join it, four to a quarter (doc 308, 2026-11-13); logs stay off it.
	_expect(pallet.accepts_key(OAK_PLANK) and not pallet.accepts_key("base:item:oak_log"), "the pallet takes planks and never logs")
	for i in range(5): drops.restore_loose_item(OAK_PLANK, beside, 0, 1)
	_expect(await _until_true(func(): return pallet.stored_count() == 10), "five oak planks go to the pallet: %s" % [pallet.contents()])
	var planks: Array = []
	for stack: Dictionary in pallet.stored_entries().values():
		if String(stack.item) == OAK_PLANK: planks.append(int(stack.count))
	planks.sort()
	_expect(planks == [1, 4] and pallet.usage_text() == "4 / 4 quarters · 10 goods", "four planks fill a quarter and the fifth takes the last: %s, %s" % [pallet.contents(), pallet.usage_text()])
	var held: Dictionary = pallet.contents()
	var saved: Dictionary = JSON.parse_string(JSON.stringify(furniture.serialize_state()))
	for installed_id: int in furniture._installed.keys(): furniture._teardown_installed(installed_id, false)
	for node in drops._loose.keys():
		drops.take(node)
		node.free()
	furniture.restore_state(saved)
	var restored = null
	for other in furniture._installed.values():
		if other.furniture_key == PALLET and other.origin_cell == SECOND: restored = other.storage
	_expect(restored != null and restored.contents() == held and _count(BAR) == 5 and _count(OAK_PLANK) == 5,
		"a save keeps the bars three to a quarter and the planks four: %s" % [restored.contents() if restored != null else {}])


## A quarter shows its piece standing on the deck at its anchor.
func _on_deck(pallet, slot) -> bool:
	var node: Node3D = pallet._shown.get(slot)
	if not is_instance_valid(node) or node.get_parent() != pallet.display_parent: return false
	var box: AABB = node.global_transform * pallet._bounds(node)
	var deck_y: float = pallet.display_parent.global_position.y + DECK
	return node.global_position.is_equal_approx(pallet.anchor_position(int(slot))) and absf(box.position.y - deck_y) < .01


func _pallet_piece():
	for piece in furniture._installed.values():
		if piece.furniture_key == PALLET: return piece
	return null


func _until_true(condition: Callable, limit := 1500) -> bool:
	for i in range(limit):
		if condition.call(): return true
		stockpiles._process(.25)
		await _tick()
	return false
