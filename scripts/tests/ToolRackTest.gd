extends "res://scripts/tests/WorkerCraftingTest.gd"

## The tool rack (doc 294, step 3): the Carpenter's first piece and the first furniture store.
## - only a Carpenter makes it, from one log at the carpenter's bench, for one experience; Place
##   files it under Storage;
## - it hangs only on a wall standing behind it to its full height;
## - it keeps tools and nothing else, one on each of its three hooks, hung upright from the hook;
## - it starts at priority 4: tools go to it ahead of ground storage, a tool already on the ground
##   moves up to it, and a full rack leaves the rest to the ground;
## - its window lists only tools and counts its hooks; it sets the rack's priority and goods, and
##   a tool it stops keeping moves out while one waiting on the ground takes the hook; Locate in
##   storage opens it;
## - a promotion takes its kit off the rack;
## - marked for uninstall it takes nothing more;
## - a save keeps its tools, its goods and its priority, and so does a move;
## - with its wall mined it falls, its tools dropped in front of it.
const RACK := "base:furniture:tool_rack"
const RACK_ITEM := "base:resources:furniture:tool_rack"
const RACK_RECIPE := "base:recipe:worker:tool_rack"
const CARPENTER := "base:profession:carpenter"
const STONEMASON := "base:profession:stonemason"
const CARPENTER_BENCH := "base:furniture:carpenter_bench"
const HOE := "base:resources:tools:stone_hoe"
const HAMMER := "base:resources:tools:stone_hammer"
const KIT := "base:resources:tools:carpentry_kit"
const MASONRY := "base:resources:tools:masonry_kit"
const RANGER := "base:resources:tools:ranger_kit"
const ORIGIN := Vector3i(46, 20, 46)   # its wall at z 45
const MOVED := Vector3i(50, 20, 46)    # further along the wall
var storage_ui


func _run() -> void:
	create_timer(200).timeout.connect(func(): push_error("Tool rack test timed out"); quit(1))
	await _setup_crafting_fixture()
	var recipe: Dictionary = crafting.recipes[RACK_RECIPE]
	_expect(String(recipe.get("section", "")) == "carpenter" and recipe.workshop == CARPENTER_BENCH and String(recipe.category) == "Storage"
		and int(recipe.ingredient_count) == 1 and PINE in crafting.ingredient_keys(recipe), "the tool rack: one log at the carpenter's bench, on the Carpenter's page")
	var placed: Array = root.get_node("UIRegistry").get_place_catalog().get("items", []).filter(func(entry): return entry.key == RACK)
	_expect(placed.size() == 1 and placed[0].category == "storage", "Place files it under Storage")
	# A Carpenter makes it at their bench.
	worker.profession = CARPENTER
	tasks.work_policy_changed()
	drops.spawn_drop(PINE, 1, Vector3i(42, 21, 40))
	var id: int = crafting.queue_order(RACK_RECIPE, 1)
	for i in range(20): await _tick()
	var status: String = crafting.status(crafting.get_order(id), inventory_script.snapshot(drops, furniture))
	_expect(status == "Needs a carpenter's bench", "without a carpenter's bench the rack waits for one: %s" % status)
	furniture._install(CARPENTER_BENCH, furniture.get_defs()[CARPENTER_BENCH], Vector3i(44, 20, 41), 0, "base:material:pine")
	_expect(await _completed(id) and _count(RACK_ITEM) == 1 and _count(PINE) == 0 and int(worker.profession_experience.get(CARPENTER, 0)) == 1,
		"one log makes one packed tool rack, and one experience")
	# With no rack yet, a hammer goes to ground storage.
	drops.restore_loose_item(HAMMER, Vector3(41.5, 21, 40.5), 0, 1)
	_expect(await _until_true(func(): return int(zone.contents().get(HAMMER, 0)) == 1), "with no rack, the hammer goes to ground storage")
	# It hangs only on a wall standing behind it to its full height.
	var definition: Dictionary = furniture.get_defs()[RACK]
	_expect(furniture._rules.floor_placement_reason(definition, ORIGIN, 0, "", "") == "wall", "with no wall behind it, the rack can't be placed")
	var rock: int = blocks.get_id("base:terrain:rock:rock01")
	for x in range(45, 50): world.set_block(x, 21, 45, rock)
	_expect(furniture._rules.floor_placement_reason(definition, ORIGIN, 0, "", "") == "wall", "nor on a wall one block high, below where it hangs")
	for x in range(45, 50):
		for y in range(22, 24): world.set_block(x, y, 45, rock)
	_expect(furniture._rules.floor_placement_reason(definition, ORIGIN, 0, "", "").is_empty(), "on a wall as high as it is, it can")
	furniture.activate_for(RACK, true)
	furniture._hover_cell = ORIGIN
	furniture._yaw = 0
	furniture._confirm_ghost()
	furniture.deactivate()
	# A planned rack whose wall is mined before it is built waits for its wall.
	var ghost = furniture._ghosts.values()[0]
	world.set_block(47, 22, 45, blocks.AIR_ID)
	_expect(not furniture._can_build_ghost(ghost), "a planned rack is not built once its wall is mined")
	world.set_block(47, 22, 45, rock)
	_expect(furniture._can_build_ghost(ghost), "and can be built again once the wall stands")
	_expect(await _installed(RACK) and _count(RACK_ITEM) == 0, "a dwarf hangs it on the wall")
	var piece = _rack_piece()
	var rack = piece.storage
	_expect(rack != null and stockpiles.is_registered(rack) and rack.priority == 4 and rack.storage_capacity() == 3 and rack.slot_word == "hooks",
		"it is a store of three hooks, at priority 4")
	# A tool on the ground moves up to it; new tools go to it first, and when it is full, to the ground.
	_expect(await _until_true(func(): return int(rack.contents().get(HAMMER, 0)) == 1 and not zone.contents().has(HAMMER)),
		"the hammer moves up from ground storage to the rack")
	for key: String in [HOE, MASONRY]: drops.restore_loose_item(key, Vector3(41.5, 21, 40.5), 0, 1)
	_expect(await _until_true(func(): return rack.stored_count() == 3), "a hoe and a masonry kit go to the rack ahead of ground storage")
	drops.restore_loose_item(KIT, Vector3(41.5, 21, 40.5), 0, 1)
	drops.restore_loose_item(STONE, Vector3(42.5, 21, 40.5), 0, 1)
	_expect(await _until_true(func(): return zone.contents().has(KIT) and zone.contents().has(STONE)), "with the rack full, the carpentry kit and the stone go to the ground")
	var allowed: Array = rack.allowed_keys()
	_expect(rack.stored_count() == 3 and allowed.size() == 5 and HOE in allowed and KIT in allowed and not STONE in allowed and not rack.accepts_key(STONE),
		"it keeps only tools: %s" % [allowed])
	var hung: bool = rack.stored_entries().keys().all(func(slot): return _hangs(rack, slot))
	_expect(hung, "each tool hangs upright from its hook, its back to the rack")
	await _windows(piece, rack)
	# A promotion takes its kit off the rack.
	_expect(worker.change_profession(STONEMASON), "a Stonemason's promotion finds the masonry kit on the rack")
	_expect(await _until_true(func(): return worker.profession == STONEMASON), "and the dwarf collects it")
	_expect(not rack.contents().has(MASONRY) and worker._equipment.tool_key() == MASONRY, "the kit leaves the rack with them")
	# Marked for uninstall, it takes nothing more.
	var object_id := "installed:%d" % piece.installed_id
	furniture.perform_explorer_action(object_id, "uninstall")
	_expect(piece.flagged_uninstall and rack.suspended and not rack.has_any_room() and not stockpiles.better_store_takes(RANGER, zone),
		"marked for uninstall, it takes nothing more")
	furniture.perform_explorer_action(object_id, "uninstall")
	_expect(not piece.flagged_uninstall and not rack.suspended and rack.has_any_room() and stockpiles.better_store_takes(RANGER, zone),
		"with the uninstall cancelled, it takes tools again")
	# A save keeps its tools, its goods and its priority.
	var held: Dictionary = rack.contents()
	var saved: Dictionary = JSON.parse_string(JSON.stringify(furniture.serialize_state()))
	var validator = load("res://scripts/components/SaveSnapshotValidator.gd")
	var catalogs: Dictionary = root.get_node("SaveManager")._capture_catalogs()
	_expect(validator._validate(saved, validator.SCENE.furniture, "save.scene.furniture", catalogs).is_empty(), "the rack's save keeps the save's rules")
	for installed_id: int in furniture._installed.keys(): furniture._teardown_installed(installed_id, false)
	for node in drops._loose.keys():
		drops.take(node)
		node.free()
	furniture.restore_state(saved)
	piece = _rack_piece()
	var restored = piece.storage if piece != null else null
	_expect(restored != null and restored.contents() == held and restored.priority == 2 and not restored.accepts_key(HOE) and restored.accepts_key(RANGER)
		and restored._shown.size() == held.size() and int(stockpiles.get_inventory_totals().get(KIT, 0)) == 1,
		"a save keeps its tools on their hooks, its goods and its priority: %s" % [restored.contents() if restored != null else {}])
	# A move keeps its goods and its priority. Its tools drop as it is packed, and go back to it.
	for x in range(50, 54):
		for y in range(21, 24): world.set_block(x, y, 45, rock)
	furniture.begin_furniture_move(piece.installed_id)
	furniture._yaw = 0
	furniture._hover_cell = MOVED
	_expect(furniture._placement_valid(MOVED), "the rack may move along its wall")
	furniture._confirm_ghost()
	_expect(await _until_true(func(): return _rack_piece() != null and _rack_piece().origin_cell == MOVED), "a dwarf moves the rack")
	piece = _rack_piece()
	var moved = piece.storage
	_expect(moved != restored and moved.priority == 2 and not moved.accepts_key(HOE) and moved.accepts_key(KIT), "a move keeps its goods and its priority")
	_expect(await _until_true(func(): return moved.contents() == held), "its tools go back onto it: %s" % [moved.contents()])
	# With its wall mined it falls, its tools dropped in front of it.
	var count: int = moved.stored_count()
	world.set_block(51, 22, 45, blocks.AIR_ID)
	await _frames(2)
	furniture._process(0)
	var loose: Array = drops._loose.keys().filter(func(node): return "tool" in drops.get_item_def(drops.item_key_of(node)).get("material_tags", []))
	_expect(_rack_piece() == null and not stockpiles.is_registered(moved) and loose.size() == count and count == 2 and _count(RACK_ITEM) == 1,
		"with its wall mined the rack falls: its %d tools and the packed rack are dropped" % loose.size())
	_expect(loose.all(func(node): return drops.item_floor_cell(node) in moved.stand_cells()), "its tools lie in front of it")
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("TOOL_RACK_OK: Carpenters make it, it hangs on a wall, tools only, three hooks at priority 4 ahead of the ground, moving up, its windows, Locate, promotions, uninstall, saves, moves and its wall mined")
	quit(0 if failures.is_empty() else 1)


## Its furniture window, and the storage window it opens.
func _windows(piece, rack) -> void:
	var object_id := "installed:%d" % piece.installed_id
	var data: Dictionary = furniture.get_explorer_data(object_id)
	_expect(data.rows.has(["Holds", "3 / 3 hooks"]) and data.rows.has(["Priority", "4 · 1 is filled first"]) and data.actions.any(func(action): return action.id == "storage"),
		"its window shows its hooks in use and its priority, with a Storage button: %s" % [data.rows])
	storage_ui = load("res://scripts/systems/StockpileDesignationController.gd").new()
	storage_ui.window_manager_path = NodePath("../Windows")
	scene.add_child(storage_ui)
	storage_ui.set_process(false)
	await _frames(2)
	# Inventory's Locate in storage opens the rack's window.
	dock._locate_inventory_item(HAMMER, true)
	await _frames(8)
	var window = storage_ui._storage_panel
	_expect(manager.is_open(storage_ui.ZONE_WINDOW_ID) and window.storage == rack, "Locate in storage finds the hammer on the rack and opens its window")
	manager.close(storage_ui.ZONE_WINDOW_ID)
	await _frames(2)
	furniture.perform_explorer_action(object_id, "storage")
	await _frames(8)
	var tile: Button = window._goods_grid.get_tile(HOE)
	_expect(manager.is_open(storage_ui.ZONE_WINDOW_ID) and window.storage == rack and window._goods_grid.visible and tile != null and tile.is_visible_in_tree(),
		"Storage opens the storage window on the rack's own goods")
	_expect(window.info_label.text.begins_with("Used 3 / 3 hooks") and window._priority_buttons[3].button_pressed, "it counts hooks, with its 4 pressed: %s" % window.info_label.text)
	_click(window._priority_buttons[1].get_global_rect().get_center())
	await _frames(4)
	_expect(rack.priority == 2 and window._priority_buttons[1].button_pressed, "a click on 2 ranks the rack 2")
	# A tool it stops keeping moves out, and the carpentry kit waiting on the ground takes its hook.
	_click(tile.get_global_rect().get_center())
	await _frames(4)
	_expect(not rack.accepts_key(HOE) and rack.accepts_key(KIT), "a click on the hoe stops keeping it")
	_expect(await _until_true(func(): return zone.contents().has(HOE) and rack.contents().has(KIT) and not rack.contents().has(HOE)),
		"the hoe moves out to ground storage, and the carpentry kit takes its hook: rack %s, ground %s" % [rack.contents(), zone.contents()])
	manager.close(storage_ui.ZONE_WINDOW_ID)


## A tool hangs from its hook: turned upright, its top at the hook and its back on the rack's face.
func _hangs(rack, slot) -> bool:
	var node: Node3D = rack._shown.get(slot)
	if not is_instance_valid(node) or node.get_parent() != rack.display_parent or not node.basis.is_equal_approx(rack.HANG): return false
	var box: AABB = node.global_transform * rack._bounds(node)
	var hook: Vector3 = rack.anchor_position(int(slot))
	return absf(box.end.y - hook.y) < .01 and absf(box.position.z - hook.z) < .01 and absf(box.get_center().x - hook.x) < .01


func _rack_piece():
	for piece in furniture._installed.values():
		if piece.furniture_key == RACK: return piece
	return null


func _until_true(condition: Callable, limit := 1500) -> bool:
	for i in range(limit):
		if condition.call(): return true
		stockpiles._process(.25)
		await _tick()
	return false
