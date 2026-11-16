extends "res://scripts/tests/BasicSmelterTest.gd"

## Copper nails (doc 313). The owner, 2026-11-16: "I want to introduce copper nails that are made
## from a copper bar. Copper nails should be needed for carpenter or other recipes where it makes
## sense. 1 copper bar perhaps makes 12 nails. nails should follow the crate approach just like
## most food."
## - The good: kept 24 to a crate at three fills, stored as Metal, with its menu picture.
## - The recipe: a Blacksmith hammers one bar into twelve on the anvil stone, and a batch lands
##   as one crate that the next batch joins.
## - The Carpenter's seven plank pieces take a nail to each plank, and nothing else takes nails.
## - A plank bench waits for its nails by name and count, then takes exactly two out of a crate,
##   which stays a crate with the rest.
## - Nails fetched second (the game table's, after its stone) are found in a crate that holds
##   more than one, without the order waiting for a route.
## - A crate of nails takes one quarter of the finished goods pallet, whatever it holds, and a
##   piece made afterwards takes its nails from there.
const Pictures = preload("res://scripts/components/Pictures.gd")
const NAIL := "base:item:copper_nail"
const NAIL_RECIPE := "base:recipe:copper_nail"
const CARPENTER := "base:profession:carpenter"
const CARPENTER_BENCH := "base:furniture:carpenter_bench"
const PALLET := "base:furniture:finished_goods_pallet"
const OAK_PLANK := "base:item:oak_plank"
const BENCH_PIECE := "base:item:bench"
const PIECES := {"tool_rack": 2, "bench": 2, "raw_materials_crate": 4, "finished_goods_pallet": 4,
	"food_shelf": 4, "dining_table": 4, "board_game_table": 4}


func _run() -> void:
	create_timer(150).timeout.connect(func(): push_error("Copper nail test timed out"); quit(1))
	await _setup_crafting_fixture()
	worker.sleep = 1.0
	_check_data()
	await _check_bench_takes_nails()
	await _check_later_nails()
	await _check_blacksmith_makes_nails()
	await _check_pallet()
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("COPPER_NAIL_OK: 24 to a crate and stored as Metal, twelve from a bar on the anvil stone as one crate, a nail to each plank in the seven plank pieces, a bench that waits for two and takes two, a crate to a pallet quarter and nails taken from it")
	quit(0 if failures.is_empty() else 1)


func _nail_crates() -> Array:
	return drops._loose.keys().filter(func(node: Node3D) -> bool: return drops.item_key_of(node) == NAIL)


func _check_data() -> void:
	var def: Dictionary = drops.get_item_def(NAIL)
	var crates: Array = def.get("crate_models", [])
	_expect(drops.item_capacity(NAIL) == 24 and crates.size() == 3 and crates.all(func(path: String) -> bool: return ResourceLoader.exists(path))
		and String(def.model) == String(crates[0]), "nails are kept 24 to a crate, with low, half and full crates of their own")
	_expect("stockpile_metal" in def.material_tags and "metal" in def.material_tags and ResourceLoader.exists(Pictures.item(NAIL)),
		"nails are stored as Metal and have their menu picture: %s" % [def.material_tags])
	var recipe: Dictionary = crafting.recipes.get(NAIL_RECIPE, {})
	_expect(not recipe.is_empty() and String(recipe.get("section", "")) == "blacksmith" and String(recipe.category) == "Metal" and recipe.workshop == ANVIL
		and Array(crafting.ingredient_keys(recipe)) == [BAR] and int(recipe.ingredient_count) == 1 and String(recipe.output) == NAIL and int(recipe.output_count) == 12
		and not recipe.has("one_of") and not recipe.has("additional_ingredients"),
		"copper nails: one bar hammered into twelve on the anvil stone, on the Blacksmith's page")
	for piece: String in PIECES:
		var made: Dictionary = crafting.recipes["base:recipe:" + piece]
		var extras: Array = Array(made.get("additional_ingredients", []))
		_expect(String(made.ingredient_tag) == "plank" and extras.count(NAIL) == int(PIECES[piece]) and int(made.ingredient_count) == int(PIECES[piece])
			and "copper nails" in String(made.description),
			"%s takes a nail to each of its %d planks, and says so: %s" % [piece, PIECES[piece], extras])
	var others: Array = []
	for id: String in crafting.recipes:
		var extras: Array = Array(crafting.recipes[id].get("additional_ingredients", []))
		if NAIL in extras and not id.trim_prefix("base:recipe:") in PIECES: others.append(id)
		if String(crafting.recipes[id].get("ingredient_tag", "")) == "plank" and not NAIL in extras: others.append(id)
	_expect(others.is_empty(), "the plank pieces take nails, every one, and nothing else does: %s" % [others])
	_expect(crafting.goods_words(NAIL, 1) == "1 copper nail" and crafting.goods_words(NAIL, 4) == "4 copper nails", "a count of nails reads as words")
	# A recipe's own good is counted the same way where the good names its plural: rough stone gained one.
	var stone: Array[String] = ["base:item:rough_stone"]
	var three: String = crafting.recipe_waiting_reason(crafting.recipes["base:recipe:anvil_stone"], stone, {})
	var one: String = crafting.recipe_waiting_reason(crafting.recipes["base:recipe:stone_stool"], stone, {})
	_expect(three == "Waiting for 3 rough stones" and one == "Waiting for 1 rough stone", "a stone piece waits for rough stones by their own name, one or several: %s | %s" % [three, one])


## A plank bench, with planks to hand and no nail in the colony, waits for its two nails. With a
## crate of twelve it is made, and the crate keeps the other ten.
func _check_bench_takes_nails() -> void:
	worker.profession = CARPENTER
	tasks.work_policy_changed()
	furniture._install(CARPENTER_BENCH, furniture.get_defs()[CARPENTER_BENCH], Vector3i(45, 20, 42), 0, "base:material:pine")
	drops.spawn_drop(OAK_PLANK, 1, Vector3i(42, 21, 40))
	drops.spawn_drop(OAK_PLANK, 1, Vector3i(42, 21, 41))
	var id: int = crafting.queue_order("base:recipe:bench", 1, false, [OAK_PLANK])
	for i in range(40): await _tick()
	var order = crafting.get_order(id)
	var status: String = crafting.status(order, inventory_script.snapshot(drops, furniture)) if order != null else "made"
	_expect(status == "Waiting for 2 copper nails" and _count(OAK_PLANK) == 2 and _count(BENCH_PIECE) == 0,
		"with planks and no nails the bench waits for its nails, by name and count: %s" % status)
	dock.open_crafting("base:recipe:bench")
	await _frames(4)
	_expect(panel._ingredients_heading.text == "INGREDIENTS · 2 planks · 2 copper nails" and panel._woods.get_tile("extra:" + NAIL) != null
		and "2 copper nails · 0 available" in panel._requirements.text,
		"the bench's board asks for two planks and two copper nails: %s" % panel._ingredients_heading.text)
	manager.close("craft")
	drops.spawn_drop(NAIL, 12, Vector3i(43, 21, 40))
	_expect(_nail_crates().size() == 1 and _count(NAIL) == 12, "twelve nails lie as one crate")
	_expect(await _completed(id), "with nails in the colony the Carpenter makes the bench")
	var crates := _nail_crates()
	_expect(_count(BENCH_PIECE) == 1 and _count(OAK_PLANK) == 0 and _count(NAIL) == 10 and crates.size() == 1 and drops.quantity_of(crates[0]) == 10,
		"the bench took its two planks and exactly two nails, and the crate keeps ten: %d nails in %d crates" % [_count(NAIL), crates.size()])
	var made: Array = drops._loose.keys().filter(func(node: Node3D) -> bool: return drops.item_key_of(node) == BENCH_PIECE)
	_expect(made.size() == 1 and root.get_node("CraftMaterials").of_item(made[0]) == "base:material:oak", "and the bench is its planks' wood, not its nails'")
	for crate: Node3D in crates:
		drops.take(crate)
		crate.free()


## The board-game table takes its Rough stone first and its nails second. A later ingredient is
## planned by another step than the first (CraftIngredientPlanner), which saw only single goods:
## nails in a crate holding more than one were "unreachable", and the order waited out a retry
## before the scheduler planned it again. The table is now made without that wait.
func _check_later_nails() -> void:
	for plank in range(4): drops.spawn_drop(OAK_PLANK, 1, Vector3i(42, 21, 40))
	drops.spawn_drop("base:item:rough_stone", 1, Vector3i(42, 21, 41))
	drops.spawn_drop(NAIL, 12, Vector3i(43, 21, 41))
	var id: int = crafting.queue_order("base:recipe:board_game_table", 1, false, [OAK_PLANK])
	var waited: Array[String] = []
	var done := false
	for i in range(1200):
		var order = crafting.get_order(id)
		if order == null:
			done = true
			break
		var said: String = crafting.status(order, inventory_script.snapshot(drops, furniture))
		if said.begins_with("Waiting") and i > 2 and said not in waited: waited.append(said)
		await _tick()
	var crates := _nail_crates()
	_expect(done and waited.is_empty(), "the game table's nails, fetched after its stone, are found in their crate at once: made %s, waited on %s" % [done, waited])
	_expect(_count("base:item:board_game_table") == 1 and _count(NAIL) == 8 and crates.size() == 1 and _count("base:item:rough_stone") == 0 and _count(OAK_PLANK) == 0,
		"it took its stone, four planks and four nails, and the crate keeps eight: %d nails in %d crates" % [_count(NAIL), crates.size()])
	for crate: Node3D in crates:
		drops.take(crate)
		crate.free()


## A Blacksmith hammers a bar into twelve nails on the anvil stone. They land as one crate, the
## next batch joins it, and each batch is practice.
func _check_blacksmith_makes_nails() -> void:
	worker.profession = BLACKSMITH
	tasks.work_policy_changed()
	furniture._install(ANVIL, furniture.get_defs()[ANVIL], Vector3i(38, 20, 48), 0, "")
	var before := int(worker.profession_experience.get(BLACKSMITH, 0))
	var id: int = crafting.queue_order(NAIL_RECIPE, 1)
	for i in range(20): await _tick()
	var waiting: String = crafting.status(crafting.get_order(id), inventory_script.snapshot(drops, furniture))
	_expect(waiting == "Waiting for 1 copper bar", "with no bar in the colony the nails wait for one, named as one: %s" % waiting)
	drops.spawn_drop(BAR, 1, Vector3i(42, 21, 46))
	var hammered := await _worked(id)
	var crates := _nail_crates()
	_expect(not hammered.has("timeout") and _count(NAIL) == 12 and _count(BAR) == 0 and crates.size() == 1 and drops.quantity_of(crates[0]) == 12,
		"a bar is hammered into twelve nails, which land as one crate: %d nails in %d crates (%s)" % [_count(NAIL), crates.size(), hammered])
	_expect(String(hammered.get("worked", "")) == BAR and String(hammered.get("motion", "")) == "hew", "the bar is hammered on the anvil stone as a tool's is: %s" % [hammered])
	_expect(int(worker.profession_experience.get(BLACKSMITH, 0)) == before + 1, "and the batch counts toward the Blacksmith's practice")
	if crates.size() == 1:
		_expect(String(crates[0].get_meta("visual_path", "")).ends_with("copper_nail_half.glb"), "twelve nails show a half crate: %s" % crates[0].get_meta("visual_path", ""))
	drops.spawn_drop(BAR, 1, Vector3i(42, 21, 46))
	id = crafting.queue_order(NAIL_RECIPE, 1)
	_expect(await _completed(id), "a second bar is hammered")
	crates = _nail_crates()
	_expect(_count(NAIL) == 24 and crates.size() == 1 and drops.quantity_of(crates[0]) == 24 and String(crates[0].get_meta("visual_path", "")).ends_with("copper_nail_full.glb"),
		"the second batch joins the first: one full crate of 24: %d nails in %d crates" % [_count(NAIL), crates.size()])


## The finished goods pallet takes a crate of nails in a quarter: 24 nails where three bars go.
## The full crate is carried onto it, and a bench made afterwards takes its two nails from there.
func _check_pallet() -> void:
	var storage: Dictionary = furniture.get_defs()[PALLET].storage
	_expect("stockpile_metal" in storage.accepts, "the finished goods pallet takes metal goods")
	furniture._install(PALLET, furniture.get_defs()[PALLET], Vector3i(48, 20, 46), 0, "base:material:pine")
	var pallet = furniture._installed[furniture._next_installed_id - 1].storage
	_expect(pallet != null and pallet.accepts_key(NAIL) and pallet._slot_capacity(NAIL) == 24 and pallet._slot_capacity(BAR) == 3,
		"a quarter holds one crate of 24 nails, where it holds three bars: %d and %d" % [pallet._slot_capacity(NAIL), pallet._slot_capacity(BAR)])
	_expect(await _until_true(func() -> bool: return int(pallet.contents().get(NAIL, 0)) == 24), "the full crate is carried onto the pallet: %s" % [pallet.contents()])
	var quarters: Array = pallet.stored_entries().values().filter(func(stack: Dictionary) -> bool: return String(stack.item) == NAIL)
	_expect(quarters.size() == 1 and int(quarters[0].count) == 24 and _nail_crates().is_empty() and _count(NAIL) == 24,
		"and it takes one quarter, all 24 of it: %s" % [quarters.map(func(stack: Dictionary) -> int: return int(stack.count))])
	worker.profession = CARPENTER
	tasks.work_policy_changed()
	drops.spawn_drop(OAK_PLANK, 1, Vector3i(42, 21, 40))
	drops.spawn_drop(OAK_PLANK, 1, Vector3i(42, 21, 41))
	var benches := _count(BENCH_PIECE)
	var id: int = crafting.queue_order("base:recipe:bench", 1, false, [OAK_PLANK])
	_expect(await _completed(id) and _count(BENCH_PIECE) == benches + 1, "a bench is made with nails kept on the pallet")
	_expect(_count(NAIL) == 22 and int(pallet.contents().get(NAIL, 0)) == 22 and _nail_crates().is_empty(),
		"its two nails came off the pallet, which keeps the other 22: %d nails, %s" % [_count(NAIL), pallet.contents()])


func _until_true(condition: Callable, limit := 1500) -> bool:
	for i in range(limit):
		if condition.call(): return true
		stockpiles._process(.25)
		await _tick()
	return condition.call()
