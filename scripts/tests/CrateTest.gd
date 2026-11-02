extends "res://scripts/tests/WorkerCraftingTest.gd"

## The raw materials crate (doc 294, step 4): a log crib on the floor that holds raw goods.
## - only a Carpenter makes it, from two logs at the carpenter's bench; Place files it under
##   Storage;
## - it keeps Rough Stone, the ores and coal, and soil, three of a good to each of its four
##   quarters, at priority 4: stones on the ground move up to it, two sharing a quarter;
## - new goods top up their own quarter before taking another, and a fifth kind finds no
##   quarter;
## - each filled quarter shows one of its goods on the ground inside it, over the rim;
## - its window counts goods ("Used 8 / 12 goods") and lists only its kind;
## - a craft takes a stone out of it, one good at a time;
## - narrowed to one good its title names it, and the goods it stops keeping move out one at a
##   time, a quarter of stones included;
## - a save keeps a quarter of three, its goods and its priority;
## - marked for uninstall it takes nothing more, and uninstalled its goods drop beside it.
const CRATE := "base:furniture:raw_materials_crate"
const CRATE_ITEM := "base:resources:furniture:raw_materials_crate"
const CRATE_RECIPE := "base:recipe:worker:raw_materials_crate"
const CARPENTER := "base:profession:carpenter"
const CARPENTER_BENCH := "base:furniture:carpenter_bench"
const HOE := "base:resources:tools:stone_hoe"
const HOE_RECIPE := "base:recipe:worker:stone_hoe"
const IRON := "base:resources:ore:iron"
const TIN := "base:resources:ore:tin"
const COAL := "base:resources:ore:coal"
const SOIL := "base:resources:soil:soil"
const ORIGIN := Vector3i(36, 20, 40)   # its back-left floor cell
const RIM := 9.0 / 16                  # the top of its upper logs
const DROP := Vector3(41.5, 21, 40.5)  # where new goods turn up
var storage_ui


func _run() -> void:
	create_timer(200).timeout.connect(func(): push_error("Crate test timed out"); quit(1))
	await _setup_crafting_fixture()
	var recipe: Dictionary = crafting.recipes[CRATE_RECIPE]
	_expect(String(recipe.get("section", "")) == "carpenter" and recipe.workshop == CARPENTER_BENCH and String(recipe.category) == "Storage"
		and int(recipe.ingredient_count) == 2 and PINE in crafting.ingredient_keys(recipe), "the crate: two logs at the carpenter's bench, on the Carpenter's page")
	var placed: Array = root.get_node("UIRegistry").get_place_catalog().get("items", []).filter(func(entry): return entry.key == CRATE)
	_expect(placed.size() == 1 and placed[0].category == "storage", "Place files it under Storage")
	# The hoe the craft below makes stays loose, so the zone keeps its four cells for raw goods.
	zone.set_item_accepted(HOE, false)
	# A Carpenter makes it at their bench.
	worker.profession = CARPENTER
	tasks.work_policy_changed()
	furniture._install(CARPENTER_BENCH, furniture.get_defs()[CARPENTER_BENCH], Vector3i(44, 20, 41), 0, "base:material:pine")
	drops.spawn_drop(PINE, 2, Vector3i(42, 21, 40))
	var id: int = crafting.queue_order(CRATE_RECIPE, 1)
	_expect(await _completed(id) and _count(CRATE_ITEM) == 1 and _count(PINE) == 0, "two logs make one packed crate")
	# With no crate yet, stones go to ground storage.
	drops.restore_loose_item(STONE, DROP, 0, 2)
	_expect(await _until_true(func(): return int(zone.contents().get(STONE, 0)) == 2), "with no crate, two stones go to ground storage")
	furniture.activate_for(CRATE, true)
	furniture._hover_cell = ORIGIN
	furniture._yaw = 0
	_expect(furniture._placement_valid(ORIGIN), "the crate may stand on open floor")
	furniture._confirm_ghost()
	furniture.deactivate()
	_expect(await _installed(CRATE) and _count(CRATE_ITEM) == 0, "a dwarf sets the crate down")
	var piece = _crate_piece()
	var crate = piece.storage
	_expect(crate != null and stockpiles.is_registered(crate) and crate.priority == 4 and crate.storage_capacity() == 12 and crate.per_slot == 3
		and crate.slot_word == "quarters" and piece.cells.size() == 4, "it is a store of twelve goods in four quarters, at priority 4")
	# The stones on the ground move up to it, both into one quarter.
	_expect(await _until_true(func(): return int(crate.contents().get(STONE, 0)) == 2 and not zone.contents().has(STONE)),
		"the stones move up from ground storage to the crate")
	_expect(crate.stored_entries().size() == 1 and int(crate.stored_entries().values()[0].count) == 2, "two stones share a quarter")
	# New goods top up their own quarter before taking another.
	for key: String in [STONE, IRON, COAL, SOIL]: drops.restore_loose_item(key, DROP, 0, 1)
	_expect(await _until_true(func(): return crate.storage_used() == 6), "a stone, an iron ore, a coal and a soil go to it ahead of the ground: %s" % [crate.contents()])
	_expect(crate.stored_entries().size() == 4 and _quarter(crate, STONE) == 3, "the stone tops up the stones' quarter, the others take one each")
	_expect(not crate.has_room_for(TIN) and crate.has_room_for(IRON), "with its four quarters in use, a tin ore finds no room, an iron ore does")
	drops.restore_loose_item(IRON, DROP, 0, 2)
	_expect(await _until_true(func(): return _quarter(crate, IRON) == 3), "two more iron ores join the first")
	var allowed: Array = crate.allowed_keys()
	_expect(crate.storage_used() == 8 and allowed.size() == 8 and STONE in allowed and IRON in allowed and SOIL in allowed and not PINE in allowed
		and not HOE in allowed and not crate.accepts_key(PINE), "it keeps only raw goods: %s" % [allowed])
	_expect(crate.stored_entries().keys().all(func(slot): return _shows(crate, slot)), "each filled quarter shows one of its goods on the ground inside it, over the rim")
	await _windows(piece, crate)
	# A craft takes one stone out of its quarter.
	furniture._install(BENCH, furniture.get_defs()[BENCH], Vector3i(44, 20, 36), 0, "base:material:pine")
	drops.spawn_drop(PINE, 1, Vector3i(42, 21, 38))
	id = crafting.queue_order(HOE_RECIPE, 1)
	_expect(await _completed(id) and _quarter(crate, STONE) == 2 and crate.stored_entries().size() == 4 and _shows(crate, _slot_of(crate, STONE)),
		"a stone hoe takes one stone out of the crate's quarter: %s" % [crate.contents()])
	# Narrowed to iron ore, its title names it, and the rest moves out one good at a time.
	crate.set_all_accepted(false)
	crate.set_item_accepted(IRON, true)
	var title: String = furniture.get_furniture_storage().title(piece)
	_expect(crate.chosen_key() == IRON and title.ends_with("Raw Materials Crate · Iron Ore"), "narrowed to iron ore, its title names it: %s" % title)
	_expect(await _until_true(func(): return crate.contents() == {IRON: 3} and int(zone.contents().get(STONE, 0)) == 2 and zone.contents().has(COAL) and zone.contents().has(SOIL)),
		"the stones, the coal and the soil move out to the ground: crate %s, ground %s" % [crate.contents(), zone.contents()])
	# A save keeps its quarter of three, its goods and its priority.
	var held: Dictionary = crate.contents()
	var saved: Dictionary = JSON.parse_string(JSON.stringify(furniture.serialize_state()))
	var validator = load("res://scripts/components/SaveSnapshotValidator.gd")
	var catalogs: Dictionary = root.get_node("SaveManager")._capture_catalogs()
	_expect(validator._validate(saved, validator.SCENE.furniture, "save.scene.furniture", catalogs).is_empty(), "the crate's save keeps the save's rules")
	for installed_id: int in furniture._installed.keys(): furniture._teardown_installed(installed_id, false)
	for node in drops._loose.keys():
		drops.take(node)
		node.free()
	furniture.restore_state(saved)
	piece = _crate_piece()
	var restored = piece.storage if piece != null else null
	_expect(restored != null and restored.contents() == held and _quarter(restored, IRON) == 3 and restored.priority == 2 and restored.chosen_key() == IRON
		and restored._shown.size() == 1 and _shows(restored, _slot_of(restored, IRON)) and int(stockpiles.get_inventory_totals().get(IRON, 0)) == 3,
		"a save keeps its quarter of three iron ores, its goods and its priority: %s" % [restored.contents() if restored != null else {}])
	# Marked for uninstall it takes nothing more; uninstalled, its ores drop beside it.
	furniture.perform_explorer_action("installed:%d" % piece.installed_id, "uninstall")
	_expect(piece.flagged_uninstall and restored.suspended and not restored.has_any_room() and not restored.has_room_for(IRON),
		"marked for uninstall, it takes nothing more")
	var stands: Array[Vector3i] = restored.stand_cells()
	_expect(await _until_true(func(): return _crate_piece() == null), "a dwarf packs the crate up")
	var loose: Array = drops._loose.keys().filter(func(node): return drops.item_key_of(node) == IRON)
	_expect(not stockpiles.is_registered(restored) and loose.size() == 3 and loose.all(func(node): return drops.item_floor_cell(node) in stands) and _count(CRATE_ITEM) == 1,
		"its three iron ores and the packed crate are left beside it: %d ores" % loose.size())
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("CRATE_OK: Carpenters make it, raw goods only, three to a quarter at priority 4 ahead of the ground, moving up, its windows, a craft, one chosen good, saves and uninstall")
	quit(0 if failures.is_empty() else 1)


## Its furniture window, and the storage window it opens.
func _windows(piece, crate) -> void:
	var object_id := "installed:%d" % piece.installed_id
	var data: Dictionary = furniture.get_explorer_data(object_id)
	_expect(data.rows.has(["Holds", "8 / 12 goods"]) and data.rows.has(["Priority", "4 · 1 is filled first"]) and data.actions.any(func(action): return action.id == "storage"),
		"its window counts its goods and shows its priority, with a Storage button: %s" % [data.rows])
	storage_ui = load("res://scripts/systems/StockpileDesignationController.gd").new()
	storage_ui.window_manager_path = NodePath("../Windows")
	scene.add_child(storage_ui)
	storage_ui.set_process(false)
	await _frames(2)
	furniture.perform_explorer_action(object_id, "storage")
	await _frames(8)
	var window = storage_ui._storage_panel
	var tile: Button = window._goods_grid.get_tile(IRON)
	_expect(manager.is_open(storage_ui.ZONE_WINDOW_ID) and window.storage == crate and tile != null and tile.is_visible_in_tree() and window._goods_grid.get_tile(PINE) == null,
		"Storage opens the storage window on the crate's own goods")
	_expect(window.info_label.text == "Used 8 / 12 goods" and window._capacity.value == 8 and window._capacity.max_value == 12
		and window._capacity.tooltip_text == "3 goods to each of its quarters." and window._priority_buttons[3].button_pressed,
		"it counts goods, three to a quarter, with its 4 pressed: %s" % window.info_label.text)
	_click(window._priority_buttons[1].get_global_rect().get_center())
	await _frames(4)
	_expect(crate.priority == 2 and window._priority_buttons[1].button_pressed, "a click on 2 ranks the crate 2")
	manager.close(storage_ui.ZONE_WINDOW_ID)


## How many of `key` share its quarter.
func _quarter(crate, key: String) -> int:
	var slot = _slot_of(crate, key)
	return -1 if slot == null else int(crate.stored_entries()[slot].count)


func _slot_of(crate, key: String) -> Variant:
	for slot in crate.stored_entries():
		if String(crate.stored_entries()[slot].item) == key: return slot
	return null


## A quarter shows one of its goods, sitting on the ground at its anchor and rising over the rim.
func _shows(crate, slot) -> bool:
	var node: Node3D = crate._shown.get(slot)
	if not is_instance_valid(node) or node.get_parent() != crate.display_parent or drops.quantity_of(node) != 1: return false
	var box: AABB = node.global_transform * crate._bounds(node)
	var floor_y: float = crate.display_parent.global_position.y
	return node.global_position.is_equal_approx(crate.anchor_position(int(slot))) and absf(box.position.y - floor_y) < .01 and box.end.y > floor_y + RIM


func _crate_piece():
	for piece in furniture._installed.values():
		if piece.furniture_key == CRATE: return piece
	return null


func _until_true(condition: Callable, limit := 1500) -> bool:
	for i in range(limit):
		if condition.call(): return true
		stockpiles._process(.25)
		await _tick()
	return false
