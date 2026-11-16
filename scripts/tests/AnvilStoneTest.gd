extends "res://scripts/tests/BasicSmelterTest.gd"

## The anvil stone (doc 310; the owner, 2026-11-14: "I think the smelter should not be that
## workstation, does the blacksmith need another workstation?"). The Blacksmith's second station:
## only a Blacksmith makes it, at the crude workbench from three Rough stones, and all four copper
## tools are hammered on it, a bar and a log each. So a tool is made while the basic smelter melts
## the next bar, which the smelter's casting stone never allowed. The bar lies at the middle of the
## stone's left cell, at the casting stone's height, and the Blacksmith stands beside that cell.
const ANVIL_ITEM := "base:item:anvil_stone"
const ANVIL_RECIPE := "base:recipe:anvil_stone"


func _run() -> void:
	create_timer(150).timeout.connect(func(): push_error("Anvil stone test timed out"); quit(1))
	await _setup_crafting_fixture()
	worker.sleep = 1.0
	# The data: the stone itself, where it is placed from, and the four tools that moved to it.
	var recipe: Dictionary = crafting.recipes[ANVIL_RECIPE]
	_expect(String(recipe.get("section", "")) == "blacksmith" and String(recipe.category) == "Workshops" and recipe.workshop == BENCH
		and crafting.ingredient_keys(recipe) == [STONE] and int(recipe.ingredient_count) == 3 and not recipe.has("additional_ingredients")
		and String(recipe.furniture) == ANVIL, "the anvil stone: three Rough stones at the crude workbench, on the Blacksmith's page")
	var def: Dictionary = furniture.get_defs()[ANVIL]
	_expect(int(def.footprint.width) == 2 and int(def.footprint.depth) == 1 and int(def.crafting_cell[0]) == 0 and int(def.crafting_cell[1]) == 0
		and is_equal_approx(float(def.crafting_surface_height), float(furniture.get_defs()[SMELTER].crafting_surface_height))
		and not def.has("material_palette") and not def.has("batch_cell"),
		"it is 2 by 1, worked at its left cell at the casting stone's height, takes no wood and melts nothing")
	for name: String in TOOLS:
		_expect(crafting.recipes["base:recipe:" + name].workshop == ANVIL, "the %s is hammered on the anvil stone" % name.replace("_", " "))
	_expect(crafting.recipes.values().all(func(entry): return entry.workshop != SMELTER or entry.has("batch_hours")), "the smelter only melts: no recipe is hammered at it")
	var placed: Array = root.get_node("UIRegistry").get_place_catalog().get("items", []).filter(func(entry): return entry.key == ANVIL)
	_expect(placed.size() == 1 and placed[0].category == "workshops", "Place files the anvil stone under Workshops")
	_expect(crafting.with_article("anvil stone") == "an anvil stone" and crafting.with_article("mason's bench") == "a mason's bench", "a bench is named with its own article")
	# Only a Blacksmith makes it: with none its order waits for one.
	furniture._install(BENCH, furniture.get_defs()[BENCH], Vector3i(45, 20, 42), 0, "base:material:pine")
	drops.spawn_drop(STONE, 3, Vector3i(44, 21, 46))
	var id: int = crafting.queue_order(ANVIL_RECIPE, 1)
	for i in range(40): await _tick()
	var order = crafting.get_order(id)
	var status: String = crafting.status(order, inventory_script.snapshot(drops, furniture))
	_expect(status == "Needs a Blacksmith" and order.worker_id < 0 and _count(STONE) == 3, "only Blacksmiths make the anvil stone: with none, its order needs one: %s" % status)
	drops.spawn_drop(HAMMER, 1, Vector3i(41, 21, 44))
	_expect(worker.change_profession(BLACKSMITH), "with a stone hammer in the colony, the promotion starts")
	for i in range(1500):
		await _tick()
		if worker.profession == BLACKSMITH and not worker.promotion_pending(): break
	_expect(worker.profession == BLACKSMITH, "the Worker collects the stone hammer and is a Blacksmith")
	_expect(await _completed(id) and _count(ANVIL_ITEM) == 1 and _count(STONE) == 0, "the Blacksmith makes the anvil stone from three Rough stones")
	_expect(int(worker.profession_experience.get(BLACKSMITH, 0)) == 1, "and it counts toward the Blacksmith's practice")
	# Installed beside a smelter. Its window offers Hammer tools; it is worked beside its left cell only.
	furniture._install(SMELTER, furniture.get_defs()[SMELTER], Vector3i(38, 20, 44), 0, "")
	var smelter = furniture._installed[furniture._next_installed_id - 1]
	furniture._install(ANVIL, def, Vector3i(38, 20, 48), 0, "")
	var anvil = furniture._installed[furniture._next_installed_id - 1]
	var face: Vector3i = anvil.work_cells(false)[0]
	var stands: Array[Vector3i] = anvil.work_stands(false)
	_expect(anvil.cells.size() == 2 and face in anvil.cells and stands.size() == 3 and stands.all(func(stand): return _beside(stand, face) and not stand in anvil.cells),
		"the Blacksmith stands in one of the three free cells beside the stone's left cell: %s" % [stands])
	var window: Dictionary = furniture.get_explorer_data("installed:%d" % anvil.installed_id)
	_expect(window.actions.any(func(action): return action.id == "craft" and action.text == "Hammer tools"), "the anvil stone's window offers Hammer tools")
	# The point of it: a tool is hammered while copper melts in the smelter.
	drops.spawn_drop(COPPER_ORE, 2, Vector3i(41, 21, 47))
	drops.spawn_drop(COAL, 1, Vector3i(43, 21, 47))
	var melt: int = crafting.queue_order(BAR_RECIPE, 1)
	for i in range(1500):
		if crafting.hanging.has(smelter.installed_id): break
		await _tick()
	_expect(crafting.hanging.has(smelter.installed_id) and not crafting.bench_valid(smelter.installed_id), "the charge is in and melting: the smelter is taken")
	_expect(crafting.get_order(melt) == null and _count(BAR) == 0, "and its bar is hours away")
	drops.spawn_drop(BAR, 1, Vector3i(42, 21, 46))
	drops.spawn_drop(OAK, 1, Vector3i(43, 21, 46))
	id = crafting.queue_order(PICK_RECIPE, 1)
	var hammered := await _worked(id)
	_expect(not hammered.has("timeout") and _count(PICK) == 1 and _count(BAR) == 0 and _count(OAK) == 0 and crafting.hanging.has(smelter.installed_id),
		"a pick is hammered from a bar and a log while the smelter still melts: %s" % [hammered])
	var middle := Vector3(face.x + .5, anvil.node.global_position.y + .9375, face.z + .5)
	_expect(String(hammered.get("motion", "")) == "hew" and hammered.get("stand", Vector3i.ZERO) in stands and String(hammered.get("worked", "")) == BAR
		and (hammered.surface as Vector3).distance_to(middle) < .01,
		"the bar lies at the middle of the stone's left cell, at the casting stone's height, and is hammered from beside it: %s" % [hammered])
	var pick: Node3D = drops.nearest_loose_of_key(PICK, worker.current_cell())
	_expect(pick != null and root.get_node("CraftMaterials").of_item(pick) == "base:material:oak", "the pick keeps its haft's wood")
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("ANVIL_STONE_OK: three Rough stones at the crude workbench by a Blacksmith alone, the four copper tools on it and none at the smelter, its stands and its window, and a pick hammered at the middle of its left cell while copper melts")
	quit(0 if failures.is_empty() else 1)
