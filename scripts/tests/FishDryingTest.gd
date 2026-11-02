extends "res://scripts/tests/WorkerCraftingTest.gd"

## The drying rack (doc 289, step 3): the Ranger's own workbench (owner, 2026-11-01), which
## Rangers make at the crude workbench from two logs; at an installed rack Rangers (doc 292) hang
## fresh fish two of a kind at a time. They dry there for a day, one batch a rack, then a Ranger
## takes them down as dried fish that keep about thirty days (real drying, owner 2026-11-01). The order's words name fish, never wood; the fish are hung by hand, with no axe;
## the rack's window offers Dry fish.
const RACK := "base:furniture:drying_rack"
const RACK_ITEM := "base:resources:furniture:drying_rack"
const RACK_RECIPE := "base:recipe:worker:drying_rack"
const DRIED_RECIPE := "base:recipe:worker:dried_fish"
const PERCH := "base:resources:fish:perch"
const TROUT := "base:resources:fish:trout"
const DRIED := "base:resources:fish:dried_fish"


func _run() -> void:
	create_timer(100).timeout.connect(func(): push_error("Fish drying timed out"); quit(1))
	await _setup_crafting_fixture()
	var recipe: Dictionary = crafting.recipes[DRIED_RECIPE]
	var keys: Array = crafting.ingredient_keys(recipe)
	_expect(recipe.workshop == RACK and keys.size() == 4 and PERCH in keys and not DRIED in keys, "dried fish are made at the rack from the four fresh fish, never from dried ones")
	_expect(int(drops.get_item_def(DRIED).food.keeps_days) == 30 and bool(drops.get_item_def(DRIED).food.edible), "dried fish keep thirty days")
	# The owner (2026-11-01): the rack is the Ranger's workbench, on their page; Place still files
	# it under Food (2026-10-31: "the drying rack is not a workshop").
	var rack_recipe: Dictionary = crafting.recipes[RACK_RECIPE]
	var placed: Array = root.get_node("UIRegistry").get_place_catalog().get("items", []).filter(func(entry): return entry.key == RACK)
	_expect(String(rack_recipe.get("section", "")) == "ranger" and String(rack_recipe.category) == "Workshops" and placed.size() == 1 and placed[0].category == "food",
		"the rack is the Ranger's workbench in Craft and sits under Food in Place")
	# With only a Worker, the rack's order waits for a Ranger and no Worker takes it.
	furniture._install(BENCH, furniture.get_defs()[BENCH], Vector3i(45, 20, 42), 0, "base:material:pine")
	drops.spawn_drop(PINE, 2, Vector3i(42, 21, 40))
	var id: int = crafting.queue_order(RACK_RECIPE, 1)
	for i in range(40): await _tick()
	var rack_order = crafting.get_order(id)
	var rack_status: String = crafting.status(rack_order, inventory_script.snapshot(drops, furniture))
	_expect(rack_status == "Needs a Ranger" and rack_order.worker_id < 0 and _count(PINE) == 2, "only Rangers make the rack: with none, its order needs one: %s" % rack_status)
	crafting.remove_order(id)
	furniture._install(RACK, furniture.get_defs()[RACK], Vector3i(38, 20, 44), 0, "base:material:pine")
	var rack = furniture._installed[furniture._next_installed_id - 1]
	_expect(rack.node.get_node_or_null("Batch") == null, "an idle rack is bare: no fish hang on it")
	var window: Dictionary = furniture.get_explorer_data("installed:%d" % rack.installed_id)
	_expect(window.actions.any(func(action): return action.id == "craft" and action.text == "Dry fish"), "the rack's window offers Dry fish")
	# Dried fish is the Ranger's (doc 292): the rack's Dry fish opens the Ranger's page.
	_expect(String(recipe.get("section", "")) == "ranger", "Dried fish sits on the Ranger's page, not Rudimentary")
	furniture.perform_explorer_action("installed:%d" % rack.installed_id, "craft")
	await _frames(4)
	_expect(manager.is_open("craft") and panel.section_id == "ranger" and panel.selected == DRIED_RECIPE, "the rack's Dry fish opens the Ranger's page")
	var rack_tile: Button = panel._recipes.get_tile(RACK_RECIPE)
	_expect(rack_tile != null and rack_tile.is_visible_in_tree() and rack_tile.global_position.y < panel._recipes.get_tile(DRIED_RECIPE).global_position.y,
		"the page lists its workbench, the rack, above the dried fish made on it")
	_expect(panel._later.visible and panel._later_heading.text == "WITH HUNTING", "the page says what joins it with hunting")
	# Drying: the order waits for fish, not wood; one perch and one trout are no batch.
	id = crafting.queue_order(DRIED_RECIPE, 1)
	await _frames(2)
	var order = crafting.get_order(id)
	var status: String = crafting.status(order, inventory_script.snapshot(drops, furniture))
	_expect(status == "Waiting for 2 matching fish", "the order waits for fish, not wood: %s" % status)
	drops.spawn_drop(PERCH, 1, Vector3i(41, 21, 47))
	drops.spawn_drop(TROUT, 1, Vector3i(42, 21, 47))
	await _frames(2)
	status = crafting.status(order, inventory_script.snapshot(drops, furniture))
	_expect(status == "Waiting for 2 matching fish" and order.lease_id < 0, "a perch and a trout are no batch of one kind: %s" % status)
	# With a batch ready and only a Worker, the order waits for a Ranger and no Worker takes it.
	drops.spawn_drop(PERCH, 1, Vector3i(43, 21, 47))
	for i in range(40): await _tick()
	status = crafting.status(order, inventory_script.snapshot(drops, furniture))
	_expect(status == "Needs a Ranger" and order.lease_id < 0 and order.worker_id < 0, "only Rangers dry fish: with none, the order needs one: %s" % status)
	panel.refresh()
	_expect(panel._shown_tags.any(func(tag): return tag[0] == "Needs a Ranger"), "the board's tag says it needs a Ranger")
	# A fishing spot at the Ranger's feet (owner, 2026-11-01: "our ranger keeps fishing and not
	# making the dried fish"). A drying search spans several wakes in a real colony, one route
	# probe a wake here, and the spot used to win the Ranger between them every time.
	var spots = load("res://scripts/components/WorkSourceTable.gd").new()
	var spot = load("res://scripts/components/FishingSpot.gd").new()
	spot.origin = worker.current_cell()
	spot.water = spot.origin + Vector3i(2, 0, 0)
	spot.item = PERCH
	spot.state.designated = true
	spots.add(spot.origin, spot)
	spot.ensure_lease()
	var probes: int = tasks._scheduler.max_probes_per_wake
	tasks._scheduler.max_probes_per_wake = 1
	# The Worker becomes a Ranger.
	worker.profession = "base:profession:ranger"
	tasks.work_policy_changed()
	panel.refresh()
	_expect(panel._shown_tags.any(func(tag): return tag[0] == "✓ A Ranger · " + worker.dwarf_name), "the tag names the colony's Ranger")
	var fished := false
	var started := false
	for i in range(800):
		var held = tasks.get_task(worker.current_task_id)
		if held != null and held.type == Task.Type.FISH: fished = true
		if worker._task_phase == worker.TaskPhase.FETCH_WORKING:
			started = true
			break
		await _tick()
	_expect(started and not fished, "a Ranger carries the perch to the rack and starts, leaving the fishing spot at their feet (fished: %s)" % fished)
	tasks._scheduler.max_probes_per_wake = probes
	spot.state.designated = false
	spot.withdraw_lease()
	crafting._refresh()
	var batch: Node3D = rack.node.get_node_or_null("Batch")
	_expect(batch != null and batch.visible, "the fish hang on the rack while the Ranger hangs them")
	_expect(order.work_motion() == "hands" and (not is_instance_valid(worker._felling_pose.axe) or not worker._felling_pose.axe.visible), "the fish are hung by hand, with no axe")
	_expect(await _completed(id), "the order is done once the fish hang on the rack")
	# Real drying (owner, 2026-11-01: "the fish dried instantly"): they stay a day on the rack.
	crafting._refresh()
	_expect(_count(DRIED) == 0 and _count(PERCH) == 0 and _count(TROUT) == 1 and crafting.hanging.has(rack.installed_id),
		"the two perch hang on the rack, not yet dried; the lone trout waits")
	_expect(batch != null and batch.visible, "they stay on show while they dry")
	var line: Dictionary = crafting.hanging_status(rack.installed_id)
	_expect(String(line.text) == "Drying 2 perch · about 24 hours left" and line.tone == "fine", "the rack says what dries and for how long: %s" % line)
	window = furniture.get_explorer_data("installed:%d" % rack.installed_id)
	_expect(window.rows.has(["Crafter", "Any Ranger"]) and window.rows.has(["Drying", "2 perch · about 24 hours left"]),
		"the rack's window names its Ranger and the drying: %s" % [window.rows])
	_expect(crafting.batch_output(DRIED) == 2 and crafting.crafting_count(DRIED) == 2, "the fish on the rack count as two dried fish to come")
	# A save keeps the batch, its hours and the rack's claim.
	var hung_at: float = crafting.hanging[rack.installed_id].started
	crafting.restore_state(crafting.serialize_state())
	_expect(crafting.hanging.has(rack.installed_id) and is_equal_approx(crafting.hanging[rack.installed_id].started, hung_at)
		and not crafting.bench_valid(rack.installed_id), "a save keeps the batch drying and the rack taken")
	crafting.hanging[rack.installed_id].started -= 0.5
	_expect(String(crafting.hanging_status(rack.installed_id).text).ends_with("about 12 hours left"), "half a day later, half the time is left")
	# One batch a rack: a second waits for it to come free. A fisher's catch lands in one crate
	# at the shore, and it dries without hauling: one fish at a time leaves the crate.
	drops.spawn_drop(TROUT, 3, Vector3i(42, 21, 47))
	var crate: Node3D = drops.nearest_loose_of_key(TROUT, Vector3i(42, 20, 47))
	_expect(drops.quantity_of(crate) == 4, "the trout lie in one crate of four")
	id = crafting.queue_order(DRIED_RECIPE, 1)
	order = crafting.get_order(id)
	for i in range(30): await _tick()
	status = crafting.status(order, inventory_script.snapshot(drops, furniture))
	_expect(order.worker_id < 0 and status == "Waiting for a free drying rack · about 12 hours", "the rack takes one batch at a time: %s" % status)
	# Dry: the rack posts the take-down, and the Ranger takes the fish down before hanging more.
	crafting.hanging[rack.installed_id].started -= 0.5
	crafting._update_hanging()
	_expect(crafting.hanging_status(rack.installed_id).text == "2 dried fish · waiting for a Ranger", "dry, the fish wait for a Ranger")
	var took := false
	for i in range(800):
		var held = tasks.get_task(worker.current_task_id)
		if held != null and held.type == Task.Type.COLLECT: took = true
		if _count(DRIED) == 2: break
		await _tick()
	crafting._refresh()
	_expect(took and _count(DRIED) == 2 and not crafting.hanging.has(rack.installed_id) and int(worker.catch_log.get("dried", 0)) == 2,
		"a Ranger takes them down: two dried fish beside the rack, and the log counts them")
	_expect(batch == null or not batch.visible or crafting.hanging.has(rack.installed_id), "the rack is bare once they are down")
	var most := 0
	for i in range(800):
		if crafting.get_order(id) == null: break
		most = maxi(most, order.carried.size())
		await _tick()
	_expect(crafting.get_order(id) == null and is_instance_valid(crate) and drops.quantity_of(crate) == 2,
		"the free rack takes the trout: two leave the crate one at a time, two stay in it")
	_expect(most == 2, "both fish go in one trip, as a hauler carries a crate (carried at most %d)" % most)
	_expect(await _dry_and_take_down() and _count(DRIED) == 4 and int(worker.catch_log.get("dried", 0)) == 4,
		"a day later the Ranger takes the trout down too, and the log counts four")
	# A drying order no idle Ranger can take never holds up the Workers' orders below it.
	var factory = load("res://scripts/entities/DwarfFactory.gd").new()
	extra_worker = factory.spawn(factory.generate(142, {}), 142)
	scene.add_child(extra_worker)
	extra_worker.position = Vector3(43.5, 21, 42.5)
	extra_worker.set_process(false)
	extra_worker.sleep = 1.0
	tasks.register_dwarf(extra_worker)
	worker.set_work_permission("craft", false)
	var dry_id: int = crafting.queue_order(DRIED_RECIPE, 1)
	drops.spawn_drop(PINE, 1, Vector3i(43, 21, 41))
	var torch_id: int = crafting.queue_order(TORCH_RECIPE, 1)
	_expect(await _completed(torch_id), "a Worker makes torches below a drying order the Ranger can't take now")
	_expect(crafting.get_order(dry_id) != null and crafting.get_order(dry_id).worker_id < 0, "the drying order waits for its Ranger")
	worker.set_work_permission("craft", true)
	_expect(await _completed(dry_id) and await _dry_and_take_down() and _count(DRIED) == 6, "allowed again, the Ranger dries the last two trout")
	# The Ranger makes their own rack at the workbench; the Worker beside it never takes it.
	var rack_id: int = crafting.queue_order(RACK_RECIPE, 1)
	rack_order = crafting.get_order(rack_id)
	var maker := -1
	for i in range(800):
		if crafting.get_order(rack_id) == null: break
		if rack_order.worker_id >= 0: maker = rack_order.worker_id
		await _tick()
	_expect(crafting.get_order(rack_id) == null and maker == worker.dwarf_id and _count(RACK_ITEM) == 1 and _count(PINE) == 0,
		"the Ranger makes a drying rack from two logs at the workbench (made by %d)" % maker)
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("FISH_DRYING_OK: the rack as the Ranger's workbench and its window, the Ranger's page, fish words, a batch of one kind, Rangers only, hands, a day on the rack, one batch a rack, saves, the take-down, fish taken from a crate, Workers' orders not held up")
	quit(0 if failures.is_empty() else 1)


## The batch on the test's rack dries at once, and a Ranger takes it down.
func _dry_and_take_down() -> bool:
	var rack_ids: Array = crafting.hanging.keys()
	if rack_ids.is_empty(): return false
	crafting.hanging[rack_ids[0]].started -= 1.0
	crafting._update_hanging()
	for i in range(800):
		if crafting.hanging.is_empty(): return true
		await _tick()
	return false
