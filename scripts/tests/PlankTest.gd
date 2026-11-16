extends "res://scripts/tests/WorkerCraftingTest.gd"

## Planks (doc 308). The owner, 2026-11-13: "the carpenter starts with a saw, therefore I think the
## initial set of items the carpenter can make don't need to be rudimentary anymore", then "agree
## with planks". A Carpenter saws one log into two planks of its wood at the carpenter's bench, each
## wood by its own recipe. A plank is a good of its own: it gives the furniture made from it its
## wood, no fire burns it, it is stored as Planks on the ground and on the finished goods pallet
## (FinishedGoodsPalletTest stores them, four to a quarter), and only a Carpenter saws it.
## The first plank pieces (the owner's pick, 2026-11-13: "Dining Table, B / Bench, A"): the plank dining
## table takes four planks of one wood and the plank bench two, never logs, and each is that wood's.
const CARPENTER := "base:profession:carpenter"
const CARPENTER_BENCH := "base:furniture:carpenter_bench"
const WOOD := "base:item:"
const RECIPE := "base:recipe:"
# plank, its log, its wood
const WOODS := [["pine", "pine_log", "base:material:pine"], ["oak", "oak_log", "base:material:oak"],
	["juniper", "juniper_log", "base:material:juniper"], ["apple", "apple_log", "base:material:applewood"]]


func _run() -> void:
	create_timer(100).timeout.connect(func(): push_error("Plank test timed out"); quit(1))
	await _setup_crafting_fixture()
	var materials := root.get_node("CraftMaterials")
	var registry := root.get_node("UIRegistry")
	worker.sleep = 1.0
	# The data: one sawing recipe a wood, that log alone into two of its planks.
	for wood: Array in WOODS:
		var plank := WOOD + String(wood[0]) + "_plank"
		var log := WOOD + String(wood[1])
		var recipe: Dictionary = crafting.recipes.get(RECIPE + String(wood[0]) + "_plank", {})
		_expect(not recipe.is_empty() and String(recipe.get("section", "")) == "carpenter" and String(recipe.category) == "Timber" and recipe.workshop == CARPENTER_BENCH
			and int(recipe.ingredient_count) == 1 and int(recipe.output_count) == 2 and String(recipe.output) == plank and not recipe.has("furniture"),
			"%s planks: one log sawn into two at the carpenter's bench, on the Carpenter's page" % wood[0])
		if recipe.is_empty(): continue
		_expect(Array(crafting.ingredient_keys(recipe)) == [log], "%s planks come from that log alone: %s" % [wood[0], crafting.ingredient_keys(recipe)])
		var tags: Array = drops.get_item_def(plank).get("material_tags", [])
		_expect("plank" in tags and "stockpile_plank" in tags and not "timber" in tags and not "fuel" in tags and not "stockpile_wood" in tags,
			"the %s plank is a plank, stored as Planks, and no fire's fuel: %s" % [wood[0], tags])
		_expect(materials.from_ingredient(plank) == String(wood[2]) and materials.from_ingredient(log) == String(wood[2]),
			"the %s plank gives what is made from it its wood, as its log does" % wood[0])
		_expect(ResourceLoader.exists(String(drops.get_item_def(plank).model)) and ResourceLoader.exists("res://assets/ui/items/base_item_%s_plank.png" % wood[0]),
			"the %s plank has its model and its menu picture" % wood[0])
	# A nightly fire burns timber, and a plank is not timber: a camp never burns its boards.
	var timber: Array = []
	for key: String in drops.get_item_defs():
		if "timber" in drops.get_item_def(key).get("material_tags", []): timber.append(key)
	_expect(timber.size() == 4 and timber.all(func(key: String) -> bool: return not key.ends_with("_plank")), "the four logs are the only timber: %s" % [timber])
	# Storage: Planks is a category of its own, and new ground storage takes every category there is.
	var categories: Array = registry.get_storage_categories().map(func(entry: Dictionary) -> String: return String(entry.tag))
	_expect("stockpile_plank" in categories, "Planks is a storage category: %s" % [categories])
	var defaults: Array = load("res://scripts/components/StockpileZoneComponent.gd").DEFAULT_FILTER_TAGS
	var missing: Array = categories.filter(func(tag: String) -> bool: return not tag in defaults)
	_expect(missing.is_empty(), "new storage accepts every storage category, the newer ones too: missing %s" % [missing])
	var pallet: Dictionary = furniture.get_defs()["base:furniture:finished_goods_pallet"].storage
	_expect("stockpile_plank" in pallet.accepts and int(pallet.per_slot_of.get("stockpile_plank", 0)) == 4, "the finished goods pallet takes planks, four to a quarter")
	# The page: Timber comes first after the bench, and its planks can be ordered.
	dock.open_crafting(RECIPE + "oak_plank")
	await _frames(4)
	var tile: Button = panel._recipes.get_tile(RECIPE + "oak_plank")
	_expect(manager.is_open("craft") and panel.section_id == "carpenter" and panel.selected == RECIPE + "oak_plank" and tile != null and tile.is_visible_in_tree(),
		"oak planks are on the Carpenter's page")
	manager.close("craft")
	# The work. With only a Worker the order waits for a Carpenter.
	furniture._install(CARPENTER_BENCH, furniture.get_defs()[CARPENTER_BENCH], Vector3i(45, 20, 42), 0, "base:material:pine")
	var oak := WOOD + "oak_log"
	var oak_plank := WOOD + "oak_plank"
	drops.spawn_drop(oak, 2, Vector3i(42, 21, 40))
	drops.spawn_drop(PINE, 1, Vector3i(42, 21, 41))
	var id: int = crafting.queue_order(RECIPE + "oak_plank", 2)
	for i in range(40): await _tick()
	var order = crafting.get_order(id)
	var status: String = crafting.status(order, inventory_script.snapshot(drops, furniture))
	_expect(status == "Needs a Carpenter" and order.worker_id < 0 and _count(oak) == 2, "only a Carpenter saws planks: with none the order needs one: %s" % status)
	worker.profession = CARPENTER
	tasks.work_policy_changed()
	crafting._refresh()
	_expect(await _completed(id), "the Carpenter saws both batches")
	_expect(_count(oak_plank) == 4 and _count(oak) == 0 and _count(PINE) == 1 and _count(WOOD + "pine_plank") == 0,
		"two oak logs make four oak planks, and the pine log is left alone: %d planks, %d oak, %d pine" % [_count(oak_plank), _count(oak), _count(PINE)])
	_expect(int(worker.profession_experience.get(CARPENTER, 0)) == 2, "each batch sawn is one Carpenter experience")
	var planks: Array = drops._loose.keys().filter(func(node: Node3D) -> bool: return drops.item_key_of(node) == oak_plank)
	_expect(not planks.is_empty() and planks.all(func(node: Node3D) -> bool: return materials.of_item(node).is_empty()),
		"a plank's wood is its kind, as a log's is: it carries no material of its own")
	# The first plank pieces: the dining table and the bench are made from planks of one wood.
	var table: Dictionary = crafting.recipes[RECIPE + "dining_table"]
	var bench: Dictionary = crafting.recipes[RECIPE + "bench"]
	var table_goods: Array = Array(crafting.ingredient_keys(table))
	_expect(String(table.ingredient_tag) == "plank" and int(table.ingredient_count) == 4 and String(bench.ingredient_tag) == "plank" and int(bench.ingredient_count) == 2
		and table_goods.size() == 4 and table_goods.all(func(key: String) -> bool: return key.ends_with("_plank")),
		"the plank table takes four planks and the plank bench two, of the four woods' planks and never logs: %s" % [table_goods])
	var defs: Dictionary = furniture.get_defs()
	_expect(String(defs["base:furniture:dining_table"].display_name) == "Plank dining table" and is_equal_approx(float(defs["base:furniture:dining_table"].appeal.design), 2.0)
		and String(defs["base:furniture:bench"].display_name) == "Plank bench" and is_equal_approx(float(defs["base:furniture:bench"].appeal.design), 3.0),
		"both carry their plank names and one more point of appeal than their log forms had")
	# The pieces picked from the second sheets (owner, 2026-11-13): the tool rack, the pallet, the game table,
	# the crate and the food shelf. The fence and the gate stay logs (a rail fence is split, not sawn), and so
	# does the carpenter's bench, which is made before any plank exists.
	var costs := {"tool_rack": [2, 2.0], "finished_goods_pallet": [4, 2.0], "board_game_table": [4, 3.0], "raw_materials_crate": [4, 2.0], "food_shelf": [4, 2.0]}
	for piece: String in costs:
		var made: Dictionary = crafting.recipes[RECIPE + piece]
		_expect(String(made.ingredient_tag) == "plank" and int(made.ingredient_count) == int(costs[piece][0])
			and is_equal_approx(float(defs["base:furniture:" + piece].appeal.design), float(costs[piece][1])),
			"%s takes %d planks and carries one more point of appeal than its log form: %s" % [piece, costs[piece][0], defs["base:furniture:" + piece].appeal])
	_expect(Array(crafting.recipes[RECIPE + "board_game_table"].get("additional_ingredients", [])) == ["base:item:rough_stone"], "the game table still takes a Rough stone for its counters")
	for piece: String in ["log_fence", "log_gate", "carpenter_bench"]:
		_expect(String(crafting.recipes[RECIPE + piece].ingredient_tag) == "timber", "%s is still made from logs" % piece)
	_expect(crafting.ingredient_label(oak_plank) == "Oak" and crafting.ingredient_label(WOOD + "apple_plank") == "Applewood", "a plank's wood is named as a log's is: %s" % crafting.ingredient_label(oak_plank))
	var pine_table: int = crafting.queue_order(RECIPE + "dining_table", 1, false, [WOOD + "pine_plank"])
	for i in range(30): await _tick()
	var waiting: String = crafting.status(crafting.get_order(pine_table), inventory_script.snapshot(drops, furniture))
	_expect(waiting == "Waiting for 4 pine planks" and _count(PINE) == 1, "a pine plank table waits for pine planks, whatever logs and oak planks lie about: %s" % waiting)
	var oak_table: int = crafting.queue_order(RECIPE + "dining_table", 1, false, [oak_plank])
	_expect(await _completed(oak_table), "the Carpenter makes a table from the four oak planks")
	var tables: Array = drops._loose.keys().filter(func(node: Node3D) -> bool: return drops.item_key_of(node) == "base:item:dining_table")
	_expect(tables.size() == 1 and materials.of_item(tables[0]) == "base:material:oak" and _count(oak_plank) == 0,
		"four oak planks make one oak table: %d tables, %d planks left" % [tables.size(), _count(oak_plank)])
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("PLANK_OK: four sawing recipes, a log into two planks of its wood, never fuel, their own storage category and the pallet, the Carpenter's page, Carpenters only, experience, a plank table from four planks of one wood")
	quit(0 if failures.is_empty() else 1)
