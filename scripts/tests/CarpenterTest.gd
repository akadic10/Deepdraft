extends "res://scripts/tests/WorkerCraftingTest.gd"

## The Carpenter (doc 293, step 2). The carpenter's bench is the Carpenter's own workbench, on their
## own page: only a Carpenter makes it, from three matching logs at the crude workbench, with the
## stone adze in hand. A Carpenter crafts before the common work, but an order on another page never
## holds them from it; one experience a batch, and each level takes 5% off the work time. The bench
## installs through Place and a save keeps it. The Stonemason's side is StonemasonTest.
const CARPENTER := "base:profession:carpenter"
const CARPENTER_BENCH := "base:furniture:carpenter_bench"
const CARPENTER_ITEM := "base:resources:furniture:carpenter_bench"
const CARPENTER_RECIPE := "base:recipe:worker:carpenter_bench"
const ADZE := "res://assets/models/characters/dwarves/tools/stone_adze.glb"


func _run() -> void:
	create_timer(100).timeout.connect(func(): push_error("Carpenter test timed out"); quit(1))
	await _setup_crafting_fixture()
	var assets := root.get_node("DwarfAssets")
	var scheduler = tasks._scheduler
	var recipe: Dictionary = crafting.recipes[CARPENTER_RECIPE]
	_expect(String(recipe.get("section", "")) == "carpenter" and String(recipe.category) == "Workshops" and recipe.workshop == BENCH
		and int(recipe.ingredient_count) == 3 and not recipe.has("additional_ingredients"), "the carpenter's bench: three logs at the crude workbench")
	var placed: Array = root.get_node("UIRegistry").get_place_catalog().get("items", []).filter(func(entry): return entry.key == CARPENTER_BENCH)
	_expect(placed.size() == 1 and placed[0].category == "workshops", "Place files it under Workshops")
	# The page looks like Rudimentary (owner, 2026-11-01): the bench, real orders, nothing planned.
	dock.open_crafting(CARPENTER_RECIPE)
	await _frames(4)
	var tile: Button = panel._recipes.get_tile(CARPENTER_RECIPE)
	_expect(manager.is_open("craft") and panel.section_id == "carpenter" and panel.selected == CARPENTER_RECIPE and tile != null and tile.is_visible_in_tree(),
		"the bench is on the Carpenter's own page")
	_expect(not panel._planned.visible and not panel._later.visible and panel._queue_button.is_visible_in_tree(), "the page queues real orders, with no planned or later box")
	manager.close("craft")
	# With only a Worker, the bench's order waits for a Carpenter and the Worker never takes it.
	furniture._install(BENCH, furniture.get_defs()[BENCH], Vector3i(45, 20, 42), 0, "base:material:pine")
	drops.spawn_drop(PINE, 3, Vector3i(42, 21, 40))
	var id: int = crafting.queue_order(CARPENTER_RECIPE, 1)
	for i in range(40): await _tick()
	var order = crafting.get_order(id)
	var status: String = crafting.status(order, inventory_script.snapshot(drops, furniture))
	_expect(status == "Needs a Carpenter" and order.worker_id < 0 and _count(PINE) == 3, "only Carpenters make their bench: with none, its order needs one: %s" % status)
	# The Worker becomes a Carpenter (ToolPromotionTest collects the kit): crafting first.
	worker.profession = CARPENTER
	tasks.work_policy_changed()
	var types: Array = scheduler.types_for(worker)
	_expect(Task.Type.CRAFT in types and Task.Type.HAUL in types and Task.Type.MINE in types and Task.Type.FELL_TREE in types and Task.Type.FETCH_BUILD in types,
		"a Carpenter crafts and still takes the common work")
	crafting._refresh()
	_expect(order.lease_id >= 0 and scheduler.takes(worker, Task.Type.CRAFT) and not scheduler.takes(worker, Task.Type.HAUL) and not scheduler.takes(worker, Task.Type.MINE),
		"with their order waiting, a Carpenter crafts before hauling or digging")
	# The adze in hand, and each level takes 5% off the work time.
	_expect(await _phase(worker.TaskPhase.FETCH_WORKING), "the Carpenter carries the logs to the workbench and starts")
	worker._process(.3)
	var held: Node3D = worker._felling_pose.axe
	_expect(is_instance_valid(held) and held.visible and held.scene_file_path == ADZE, "the Carpenter works with the stone adze in hand")
	var speeds: Array = [0, 10, 50, 150, 400].map(func(count): return assets.craft_duration_multiplier(CARPENTER, {CARPENTER: count}))
	var levels := range(5).all(func(index): return is_equal_approx(speeds[index], 1.0 - index * .05))
	_expect(levels and is_equal_approx(assets.craft_duration_multiplier("base:profession:worker", {CARPENTER: 400}), 1.0),
		"levels 1 to 5 leave 100%%, 95%%, 90%%, 85%% and 80%% of the work time; a Worker's crafting has no levels: %s" % [speeds])
	var before: float = order.progress
	worker._process(.25)
	var plain: float = order.progress - before
	worker.profession_experience[CARPENTER] = 400
	before = order.progress
	worker._process(.25)
	var master: float = order.progress - before
	worker.profession_experience[CARPENTER] = 0
	_expect(plain > 0.0 and is_equal_approx(master * .8, plain), "a master Carpenter needs a fifth less work time: %.4f against %.4f" % [master, plain])
	# One experience for the batch, and the bench.
	_expect(await _completed(id), "the Carpenter finishes the bench")
	_expect(_count(CARPENTER_ITEM) == 1 and _count(PINE) == 0 and int(worker.profession_experience.get(CARPENTER, 0)) == 1,
		"three logs make one packed bench and one experience")
	# Felling, the same hands hold the axe again.
	worker._felling_pose.apply(.3, Vector3(0, 1, 1))
	_expect(worker._felling_pose.axe.scene_file_path == assets.felling_axe.resource_path, "the adze is only for crafting: felling holds the axe")
	worker._felling_pose.reset()
	# An order on another page never holds a Carpenter from the common work.
	var factory = load("res://scripts/entities/DwarfFactory.gd").new()
	extra_worker = factory.spawn(factory.generate(142, {}), 142)
	scene.add_child(extra_worker)
	extra_worker.position = Vector3(43.5, 21, 42.5)
	extra_worker.set_process(false)
	extra_worker.sleep = 1.0
	tasks.register_dwarf(extra_worker)
	drops.spawn_drop(PINE, 1, Vector3i(43, 21, 41))
	var torch_id: int = crafting.queue_order(TORCH_RECIPE, 1)
	crafting._refresh()
	_expect(crafting.get_order(torch_id).lease_id >= 0 and not scheduler.crafts(worker, tasks.get_task(crafting.get_order(torch_id).lease_id))
		and scheduler.takes(worker, Task.Type.HAUL), "a Worker's torch order leaves the Carpenter free to haul")
	_expect(await _completed(torch_id), "the Worker makes the torches")
	# Placed and installed, and a save keeps the bench and its wood.
	furniture.activate_for(CARPENTER_BENCH, true)
	furniture._hover_cell = Vector3i(38, 20, 44)
	furniture._confirm_ghost()
	furniture.deactivate()
	_expect(furniture._ghosts.size() == 1, "the bench can be placed from real stock")
	_expect(await _installed(CARPENTER_BENCH) and _count(CARPENTER_ITEM) == 0 and crafting.has_bench(CARPENTER_BENCH), "the bench is installed")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(furniture.serialize_state()))
	for installed_id: int in furniture._installed.keys(): furniture._teardown_installed(installed_id, false)
	furniture.restore_state(saved)
	var benches: Array = furniture._installed.values().filter(func(piece): return piece.furniture_key == CARPENTER_BENCH)
	_expect(benches.size() == 1 and benches[0].material_id == "base:material:pine" and benches[0].cells.size() == 3, "a save keeps the installed bench, its three cells and its pine")
	var state: Dictionary = JSON.parse_string(JSON.stringify(worker.serialize_state()))
	_expect(state.profession == CARPENTER and int(state.profession_experience[CARPENTER]) == 1, "and the Carpenter's experience")
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("CARPENTER_OK: the bench recipe, Place and the page, Carpenters only, crafting first, the adze, levels, one experience a batch, other pages never hold them, install and saves")
	quit(0 if failures.is_empty() else 1)
