extends "res://scripts/tests/WorkerCraftingTest.gd"

## The Blacksmith and the basic smelter (doc 297). A Worker becomes a Blacksmith by collecting a
## stone hammer. Only a Blacksmith makes the smelter, at the crude workbench from a log, four Rough
## Stones and a Soil. At an installed smelter, two copper ore and a coal make one copper bar
## (owner: "2 to 1"): charged by hand, the batch melts on the world clock, heating the room only
## while it melts, then the Blacksmith (never a Ranger) takes the cast bar off the stone. A bar
## hammers into four copper fittings. Each batch is a Blacksmith's experience: practice for iron.
const BLACKSMITH := "base:profession:blacksmith"
const RANGER := "base:profession:ranger"
const HAMMER := "base:resources:tools:stone_hammer"
const SMELTER := "base:furniture:basic_smelter"
const SMELTER_ITEM := "base:resources:furniture:basic_smelter"
const SMELTER_RECIPE := "base:recipe:worker:basic_smelter"
const BAR_RECIPE := "base:recipe:worker:copper_bar"
const FITTING_RECIPE := "base:recipe:worker:copper_fitting"
const COPPER_ORE := "base:resources:ore:copper"
const IRON_ORE := "base:resources:ore:iron"
const COAL := "base:resources:ore:coal"
const SOIL := "base:resources:soil:soil"
const BAR := "base:resources:metal:copper_bar"
const FITTING := "base:resources:metal:copper_fitting"


func _run() -> void:
	create_timer(150).timeout.connect(func(): push_error("Basic smelter test timed out"); quit(1))
	await _setup_crafting_fixture()
	var rooms := root.get_node("RoomManager")
	worker.sleep = 1.0
	# The data: the smelter, the bar (2 ore and a coal to 1 bar) and the fittings (1 bar to 4).
	var recipe: Dictionary = crafting.recipes[SMELTER_RECIPE]
	_expect(String(recipe.get("section", "")) == "blacksmith" and String(recipe.category) == "Workshops" and recipe.workshop == BENCH
		and int(recipe.ingredient_count) == 1 and recipe.additional_ingredients == [STONE, STONE, STONE, STONE, SOIL],
		"the basic smelter: a log, four Rough Stones and a Soil at the crude workbench")
	var bar: Dictionary = crafting.recipes[BAR_RECIPE]
	var ores: Array = crafting.ingredient_keys(bar)
	_expect(bar.workshop == SMELTER and ores == [COPPER_ORE] and int(bar.ingredient_count) == 2 and bar.additional_ingredients == [COAL]
		and int(bar.output_count) == 1 and float(bar.batch_hours) > 0.0, "a copper bar: two copper ore (never iron) and a coal, melted at the smelter")
	var fitting: Dictionary = crafting.recipes[FITTING_RECIPE]
	_expect(fitting.workshop == SMELTER and crafting.ingredient_keys(fitting) == [BAR] and int(fitting.output_count) == 4,
		"copper fittings: one bar hammered into four at the smelter")
	var placed: Array = root.get_node("UIRegistry").get_place_catalog().get("items", []).filter(func(entry): return entry.key == SMELTER)
	_expect(placed.size() == 1 and placed[0].category == "workshops", "Place files the smelter under Workshops")
	_expect("stockpile_metal" in drops.get_item_def(BAR).material_tags and "stockpile_metal" in drops.get_item_def(FITTING).material_tags,
		"bars and fittings are stored as Metal")
	# No Blacksmith: the smelter's order waits for one, and no hammer means no Blacksmith.
	furniture._install(BENCH, furniture.get_defs()[BENCH], Vector3i(45, 20, 42), 0, "base:material:pine")
	drops.spawn_drop(PINE, 1, Vector3i(42, 21, 40))
	drops.spawn_drop(STONE, 4, Vector3i(44, 21, 44))
	drops.spawn_drop(SOIL, 1, Vector3i(43, 21, 44))
	var id: int = crafting.queue_order(SMELTER_RECIPE, 1)
	for i in range(40): await _tick()
	var order = crafting.get_order(id)
	var status: String = crafting.status(order, inventory_script.snapshot(drops, furniture))
	_expect(status == "Needs a Blacksmith" and order.worker_id < 0 and _count(STONE) == 4, "only Blacksmiths make the smelter: with none, its order needs one: %s" % status)
	_expect(not worker.change_profession(BLACKSMITH), "without a stone hammer there is no Blacksmith")
	# The Worker collects a stone hammer and is a Blacksmith.
	drops.spawn_drop(HAMMER, 1, Vector3i(41, 21, 44))
	_expect(worker.change_profession(BLACKSMITH), "with a stone hammer in the colony, the promotion starts")
	var promoted := false
	for i in range(1500):
		await _tick()
		if worker.profession == BLACKSMITH and not worker.promotion_pending():
			promoted = true
			break
	_expect(promoted and worker.get_equipment().tool_key() == HAMMER, "the Worker collects the stone hammer and is a Blacksmith")
	# The Equipment view shows the hammer as the kits are shown, never as a tool still missing
	# (the project review, 2026-11-09: "A stone hammer is required" while it was equipped).
	var details: Dictionary = load("res://scripts/components/DwarfInspection.gd").equipment_details(worker)
	_expect(String(details.tier) == "Crude" and String(details.benefit).begins_with("Enables the Blacksmith profession"),
		"the Equipment view shows the stone hammer equipped: %s / %s" % [details.tier, details.benefit])
	_expect(await _completed(id) and _count(SMELTER_ITEM) == 1 and _count(STONE) == 0 and _count(SOIL) == 0 and _count(PINE) == 0,
		"the Blacksmith makes the smelter from a log, four Rough Stones and a Soil")
	_expect(int(worker.profession_experience.get(BLACKSMITH, 0)) == 1, "the smelter is the Blacksmith's first batch")
	# Installed, it is bare and cold, and its window offers Smelt copper.
	furniture._install(SMELTER, furniture.get_defs()[SMELTER], Vector3i(38, 20, 44), 0, "")
	var smelter = furniture._installed[furniture._next_installed_id - 1]
	var anchor: Vector3i = furniture.room_cells(smelter)[0]
	_expect(smelter.node.get_node_or_null("Batch") == null and not rooms.heat_sources().has(anchor), "an idle smelter is bare and gives no heat")
	var window: Dictionary = furniture.get_explorer_data("installed:%d" % smelter.installed_id)
	_expect(window.actions.any(func(action): return action.id == "craft" and action.text == "Smelt copper"), "the smelter's window offers Smelt copper")
	# A bar: iron ore is never taken, two copper ore and a coal are.
	drops.spawn_drop(COPPER_ORE, 2, Vector3i(41, 21, 47))
	drops.spawn_drop(IRON_ORE, 2, Vector3i(42, 21, 47))
	id = crafting.queue_order(BAR_RECIPE, 1)
	await _frames(2)
	order = crafting.get_order(id)
	status = crafting.status(order, inventory_script.snapshot(drops, furniture))
	_expect(status == "Waiting for Coal", "without coal the bar waits for it: %s" % status)
	drops.spawn_drop(COAL, 1, Vector3i(43, 21, 47))
	_expect(await _completed(id), "the Blacksmith charges the crucible")
	crafting._refresh()
	crafting._show_batches()
	_expect(_count(COPPER_ORE) == 0 and _count(COAL) == 0 and _count(IRON_ORE) == 2 and _count(BAR) == 0 and crafting.hanging.has(smelter.installed_id),
		"two copper ore and the coal are in the crucible; the iron ore stays")
	var line: Dictionary = crafting.hanging_status(smelter.installed_id)
	_expect(String(line.text) == "Melting 2 copper ore · about 4 hours left", "the smelter says what melts and for how long: %s" % line)
	window = furniture.get_explorer_data("installed:%d" % smelter.installed_id)
	_expect(window.rows.has(["Crafter", "Any Blacksmith"]) and window.rows.has(["Melting", "2 copper ore · about 4 hours left"]),
		"the window names its Blacksmith and the melt: %s" % [window.rows])
	var charge: Node3D = smelter.node.get_node_or_null("Batch")
	_expect(charge != null and charge.visible, "the charge shows in the smelter while it melts")
	_expect(int(rooms.heat_sources().get(anchor, {}).get("units", 0)) == 2400, "it heats its room while it melts")
	_expect(crafting.section_batch_heading("blacksmith") == "MELTING", "the crafting window's list says MELTING")
	_expect(int(worker.profession_experience.get(BLACKSMITH, 0)) == 2, "the bar counts toward the Blacksmith's practice")
	# A save keeps the melt and its heat, once.
	crafting.restore_state(crafting.serialize_state())
	_expect(crafting.hanging.has(smelter.installed_id) and int(rooms.heat_sources().get(anchor, {}).get("units", 0)) == 2400,
		"a save keeps the copper melting and the heat counted once")
	# Only the Blacksmith takes it down: a Ranger never does.
	var factory = load("res://scripts/entities/DwarfFactory.gd").new()
	var ranger = factory.spawn(factory.generate(143, {}), 143)
	scene.add_child(ranger)
	ranger.set_process(false)
	ranger.profession = RANGER
	_expect(not crafting.hanging[smelter.installed_id].allows_worker(ranger) and crafting.hanging[smelter.installed_id].allows_worker(worker),
		"a Ranger never takes the copper down; the Blacksmith does")
	ranger.queue_free()
	# Set: the heat goes, and the Blacksmith takes the bar off the stone.
	crafting.hanging[smelter.installed_id].started -= 1.0
	crafting._update_hanging()
	_expect(not rooms.heat_sources().has(anchor), "once the copper has set, the smelter gives no more heat")
	_expect(crafting.hanging_status(smelter.installed_id).text == "1 copper bar · waiting for a Blacksmith", "set, the bar waits for a Blacksmith")
	var took := false
	for i in range(800):
		var held = tasks.get_task(worker.current_task_id)
		if held != null and held.type == Task.Type.COLLECT: took = true
		if _count(BAR) == 1: break
		await _tick()
	crafting._refresh()
	_expect(took and _count(BAR) == 1 and not crafting.hanging.has(smelter.installed_id), "the Blacksmith takes one copper bar off the stone")
	# Fittings: the bar hammered into four.
	id = crafting.queue_order(FITTING_RECIPE, 1)
	_expect(await _completed(id) and _count(FITTING) == 4 and _count(BAR) == 0, "the Blacksmith hammers the bar into four copper fittings")
	_expect(int(worker.profession_experience.get(BLACKSMITH, 0)) == 3, "fittings count toward the practice too")
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("BASIC_SMELTER_OK: the Blacksmith's promotion and page, the smelter from raw goods, 2 copper ore and a coal to 1 bar, melting on the clock with heat only while it melts, saves, Blacksmith-only take-down, fittings, experience")
	quit(0 if failures.is_empty() else 1)
