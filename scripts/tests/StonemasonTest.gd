extends "res://scripts/tests/WorkerCraftingTest.gd"

## The Stonemason (doc 293, step 2). A Worker makes a crude masonry kit from a log and a Rough Stone
## at the crude workbench and becomes a Stonemason by collecting it. Only a Stonemason makes the
## mason's bench, their own workbench, from a log and three Rough Stones at the crude workbench,
## with the maul in hand, which knocks as a builder's hammer does; Strength sets the pace, not Wits.
## One experience a batch; the roster's note, the sheet's line and rewards; the bench installs, and
## a save keeps the kit and the experience. The Carpenter's side is CarpenterTest.
const WORKER := "base:profession:worker"
const STONEMASON := "base:profession:stonemason"
const KIT := "base:resources:tools:masonry_kit"
const KIT_RECIPE := "base:recipe:worker:masonry_kit"
const MASON_BENCH := "base:furniture:mason_bench"
const MASON_ITEM := "base:resources:furniture:mason_bench"
const MASON_RECIPE := "base:recipe:worker:mason_bench"
const MAUL := "res://assets/models/characters/dwarves/tools/stone_maul.glb"
const STRENGTH := "base:stat:strength"
const WITS := "base:stat:wits"

class SliceStub extends Node:
	func get_slice_y() -> int: return 127

var sounds: Array = []


func _run() -> void:
	create_timer(120).timeout.connect(func(): push_error("Stonemason test timed out"); quit(1))
	await _setup_crafting_fixture()
	var assets := root.get_node("DwarfAssets")
	worker.sleep = 1.0
	var kit_recipe: Dictionary = crafting.recipes[KIT_RECIPE]
	_expect(String(kit_recipe.get("section", "rudimentary")) == "rudimentary" and String(kit_recipe.category) == "Starter tools" and kit_recipe.workshop == BENCH
		and int(kit_recipe.ingredient_count) == 1 and kit_recipe.additional_ingredients == [STONE], "the masonry kit: a Worker's starter tool from a log and a Rough Stone")
	var recipe: Dictionary = crafting.recipes[MASON_RECIPE]
	_expect(String(recipe.get("section", "")) == "stonemason" and String(recipe.category) == "Workshops" and recipe.workshop == BENCH
		and int(recipe.ingredient_count) == 1 and recipe.additional_ingredients == [STONE, STONE, STONE], "the mason's bench: a log and three Rough Stones at the crude workbench")
	_expect(not worker.change_profession(STONEMASON) and worker.profession == WORKER, "without a kit there is no Stonemason")
	# A Worker makes the kit.
	furniture._install(BENCH, furniture.get_defs()[BENCH], Vector3i(45, 20, 42), 0, "base:material:pine")
	drops.spawn_drop(PINE, 2, Vector3i(42, 21, 40))
	drops.spawn_drop(STONE, 4, Vector3i(44, 21, 44))
	var id: int = crafting.queue_order(KIT_RECIPE, 1)
	_expect(await _completed(id) and _count(KIT) == 1 and _count(PINE) == 1 and _count(STONE) == 3, "a Worker makes the kit from a log and a Rough Stone")
	_expect(int(worker.profession_experience.get(WORKER, 0)) == 0, "a Worker's crafting earns no experience")
	# With no Stonemason, the bench's order waits for one and the Worker never takes it.
	id = crafting.queue_order(MASON_RECIPE, 1)
	for i in range(40): await _tick()
	var order = crafting.get_order(id)
	var status: String = crafting.status(order, inventory_script.snapshot(drops, furniture))
	_expect(status == "Needs a Stonemason" and order.worker_id < 0 and _count(STONE) == 3, "only Stonemasons make their bench: with none, its order needs one: %s" % status)
	# The Worker collects the kit and is a Stonemason.
	_expect(worker.change_profession(STONEMASON), "with a kit in the colony, the promotion starts")
	var promoted := false
	for i in range(1500):
		await _tick()
		if worker.profession == STONEMASON and not worker.promotion_pending():
			promoted = true
			break
	_expect(promoted and worker.get_equipment().tool_key() == KIT, "the Worker collects the kit and is a Stonemason")
	var details: Dictionary = load("res://scripts/components/DwarfInspection.gd").equipment_details(worker)
	_expect(String(details.name) == "Pine crude masonry kit" and String(details.benefit).contains("maul") and ResourceLoader.exists(String(details.icon)),
		"the Equipment view shows the kit by its wood, its picture and its maul: %s" % [details])
	var types: Array = tasks._scheduler.types_for(worker)
	_expect(Task.Type.CRAFT in types and Task.Type.HAUL in types and Task.Type.MINE in types and Task.Type.FETCH_BUILD in types, "a Stonemason crafts and still takes the common work")
	# The maul in hand knocks as a builder's hammer does, never the axe's chop.
	var feedback = root.get_node("WorkFeedback")
	feedback.set_process(false)
	feedback._sync_scene()
	feedback.sound_started.connect(func(kind, _position, _variant): if kind in ["chop", "hammer"]: sounds.append(kind))
	camera.set_meta("work_focus", Vector3(42, 21, 41))
	camera.set_meta("work_zoom", 24.0)
	var slice := SliceStub.new()
	slice.add_to_group("work_feedback_slice")
	scene.add_child(slice)
	_expect(await _phase(worker.TaskPhase.FETCH_WORKING), "the Stonemason carries the log and stones to the workbench and starts")
	sounds.clear()
	for i in range(30):
		feedback._process(.05)
		worker._process(.05)
	var held: Node3D = worker._felling_pose.axe
	_expect(is_instance_valid(held) and held.visible and held.scene_file_path == MAUL, "the Stonemason works with the maul in hand")
	_expect(not sounds.is_empty() and sounds.all(func(kind): return kind == "hammer"), "the maul knocks like a builder's hammer: %s" % [sounds])
	# Strength sets the pace of stonework; Wits doesn't.
	var stats: Dictionary = worker.stats.duplicate()
	var steps: Array = []
	for pair: Array in [[5, 1], [1, 1], [1, 5]]:
		worker.stats[STRENGTH] = pair[0]
		worker.stats[WITS] = pair[1]
		var before: float = order.progress
		worker._process(.25)
		steps.append(order.progress - before)
	worker.stats = stats
	_expect(steps[1] > 0.0 and is_equal_approx(steps[0] / steps[1], 1.12 / .88) and is_equal_approx(steps[1], steps[2]),
		"Strength sets a Stonemason's pace and Wits doesn't: %s" % [steps])
	# One experience for the batch, and the bench.
	_expect(await _completed(id), "the Stonemason finishes the bench")
	_expect(_count(MASON_ITEM) == 1 and _count(STONE) == 0 and _count(PINE) == 0 and int(worker.profession_experience.get(STONEMASON, 0)) == 1,
		"a log and three Rough Stones make one packed bench and one experience")
	furniture.activate_for(MASON_BENCH, true)
	furniture._hover_cell = Vector3i(38, 20, 44)
	furniture._confirm_ghost()
	furniture.deactivate()
	_expect(furniture._ghosts.size() == 1, "the bench can be placed from real stock")
	_expect(await _installed(MASON_BENCH) and _count(MASON_ITEM) == 0 and crafting.has_bench(MASON_BENCH), "the Stonemason installs their bench")
	# The roster's note, the sheet's line and the rewards.
	var roster = load("res://scripts/ui/DwarfRosterPanel.gd")
	_expect(roster._work_note(worker) == "Masonry focus", "the roster's note: Masonry focus")
	worker.set_work_permission("craft", false)
	_expect(roster._work_note(worker) == "Crafting disabled" and not Task.Type.CRAFT in tasks._scheduler.types_for(worker), "with Craft unticked, a Stonemason doesn't craft")
	worker.set_work_permission("craft", true)
	var inspection = load("res://scripts/components/DwarfInspection.gd")
	var first: String = inspection.experience(worker).line
	_expect(first == "10% to level 2 · 1 batch made" and assets.experience_words(STONEMASON, "to_go", 1) == "more batch"
		and assets.experience_words(STONEMASON, "to_go", 9) == "more batches", "one batch reads in the singular: %s" % first)
	worker.profession_experience[STONEMASON] = 12
	var experience: Dictionary = inspection.experience(worker)
	_expect(experience.earns and experience.level == 2 and experience.line == "5% to level 3 · 12 batches made", "the bar's line: %s" % experience.line)
	_expect(String(inspection.describe(worker).profession) == "Stonemason · Lv 2", "the compact panel reads Stonemason · Lv 2")
	var rewards: Array = experience.rewards.map(func(reward): return reward.text)
	_expect(rewards == ["Masonry focus", "5% less work time crafting", "10% less work time crafting", "15% less work time crafting", "20% less work time crafting"],
		"the rewards: %s" % [rewards])
	# Saves: the kit and the experience ride with the dwarf.
	var state: Dictionary = JSON.parse_string(JSON.stringify(worker.serialize_state()))
	var validator = load("res://scripts/components/SaveSnapshotValidator.gd")
	_expect(validator._validate(state, validator.SCENE.dwarves.roster[0], "save.scene.dwarves.roster[0]", {}).is_empty(), "a Stonemason's state matches the save's rules")
	_expect(state.profession == STONEMASON and state.equipment.tool == KIT and int(state.profession_experience[STONEMASON]) == 12, "the save keeps the career, the kit and the experience")
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("STONEMASON_OK: the kit and its promotion, Stonemasons only, the mason's bench, the maul and its knock, Strength, one experience a batch, install, the roster, the sheet and saves")
	quit(0 if failures.is_empty() else 1)
