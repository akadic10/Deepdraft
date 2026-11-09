extends "res://scripts/tests/WorkerCraftingTest.gd"

## The finished goods pallet (doc 62, A, log skids; owner, 2026-11-02): split poles on two log
## runners that hold the colony's finished goods, which today are its packed furniture.
## - only a Carpenter makes it, from two logs at the carpenter's bench; Place files it under
##   Storage;
## - it keeps packed furniture and nothing else, one piece to each of its four quarters, at
##   priority 4: new pieces go to it ahead of the ground;
## - each filled quarter shows its piece standing on the deck;
## - placing a piece takes it off the pallet;
## - a save keeps its pieces;
## - a Move cancelled once its piece is packed may leave that piece on the pallet, and saves still
##   pass (colony check 2026-11-09: the save check skipped goods in storage furniture).
const PALLET := "base:furniture:finished_goods_pallet"
const PALLET_ITEM := "base:resources:furniture:finished_goods_pallet"
const PALLET_RECIPE := "base:recipe:worker:finished_goods_pallet"
const STOOL := "base:furniture:log_chair"
const STOOL_ITEM := "base:resources:furniture:log_chair"
const HOE := "base:resources:tools:stone_hoe"
const ORIGIN := Vector3i(36, 20, 40)   # its back-left floor cell
const DECK := 7.0 / 16                 # the top of its split poles
const DROP := Vector3(41.5, 21, 40.5)  # where new goods turn up
const MOVE_TO := Vector3i(53, 20, 44)  # a Move's destination, cancelled once the stool is packed


func _run() -> void:
	create_timer(200).timeout.connect(func(): push_error("Finished goods pallet test timed out"); quit(1))
	await _setup_crafting_fixture()
	var recipe: Dictionary = crafting.recipes[PALLET_RECIPE]
	_expect(String(recipe.get("section", "")) == "carpenter" and recipe.workshop == "base:furniture:carpenter_bench" and String(recipe.category) == "Storage"
		and int(recipe.ingredient_count) == 2 and PINE in crafting.ingredient_keys(recipe), "the pallet: two logs at the carpenter's bench, on the Carpenter's page")
	var placed: Array = root.get_node("UIRegistry").get_place_catalog().get("items", []).filter(func(entry): return entry.key == PALLET)
	_expect(placed.size() == 1 and placed[0].category == "storage", "Place files it under Storage")
	# A Carpenter makes it at their bench.
	_carpenter_bench_at(Vector3i(44, 20, 41))
	drops.spawn_drop(PINE, 2, Vector3i(42, 21, 40))
	var id: int = crafting.queue_order(PALLET_RECIPE, 1)
	_expect(await _completed(id) and _count(PALLET_ITEM) == 1 and _count(PINE) == 0, "two logs make one packed pallet")
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
	_expect(pallet.accepts_key(STOOL_ITEM) and pallet.accepts_key(PALLET_ITEM) and not pallet.accepts_key(STONE) and not pallet.accepts_key(PINE) and not pallet.accepts_key(HOE),
		"it keeps packed furniture and nothing else")
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
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("FINISHED_GOODS_PALLET_OK: Carpenters make it, packed furniture only, one to a quarter at priority 4, shown on the deck, placed from it, saves, and saves with a cancelled Move's piece on it")
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
