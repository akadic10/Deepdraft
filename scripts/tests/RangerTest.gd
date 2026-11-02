extends "res://scripts/tests/FishingTest.gd"

## The Ranger (doc 292, step 2), in the fishing test's world: Labor's boxes by career; a Worker
## beside a zone never fishes, and its window says the colony has no Ranger; a Worker becomes a
## Ranger by collecting a Ranger's kit; the Ranger fishes, one experience a catch on the Ranger's
## own scale; a big catch lands two fish for one off the stock and hangs its own model on the line;
## patience in winter; the roster's note; the sheet's line and catch log; and saves. Drying as the
## Ranger's work is FishDryingTest's.
const RANGER := "base:profession:ranger"
const WORKER := "base:profession:worker"
const KIT := "base:resources:tools:ranger_kit"


func _run() -> void:
	create_timer(150).timeout.connect(func(): push_error("Ranger test timed out"); quit(1))
	_setup_fixture()
	root.get_node("StockpileManager").set_process(false)
	_pond()
	fishing = load("res://scripts/systems/FishingSystem.gd").new()
	fishing.name = "Fishing"
	fishing.window_manager_path = NodePath("../Windows")
	scene.add_child(fishing)
	fishing.set_process(false)
	fishing.config.waters.lake.stock_per_cell = 3.0   # the pond's 64 columns hold 192 fish
	fishing.config.catch_hours = 0.1
	await process_frame
	var assets := root.get_node("DwarfAssets")
	# Labor: each career's own work.
	_expect(assets.profession_allows(RANGER, "fish") and assets.profession_allows(RANGER, "craft") and assets.profession_allows(RANGER, "haul")
		and not assets.profession_allows(RANGER, "mine") and not assets.profession_allows(RANGER, "gather") and not assets.profession_allows(RANGER, "build"),
		"a Ranger fishes, dries and hauls, and nothing else")
	_expect(assets.profession_allows(WORKER, "craft") and not assets.profession_allows(WORKER, "fish")
		and not assets.profession_allows("base:profession:miner", "fish") and not assets.profession_allows("base:profession:miner", "craft"),
		"Workers craft and no longer fish; Miners do neither")
	_expect(assets.craft_section(RANGER) == "ranger" and assets.craft_section(WORKER) == "rudimentary" and assets.craft_section("base:profession:blacksmith").is_empty(),
		"Rangers make the Ranger's page and Workers Rudimentary; the Blacksmith's is still planned")
	# A Worker beside a zone never fishes, and the window says the colony has no Ranger.
	var cells: Array[Vector3i] = []
	for z in range(31, 35): cells.append(Vector3i(SHORE_X, 20, z))
	var zone_id: int = fishing.create_zone(cells)
	worker = _spawn(601, Vector3i(SHORE_X - 6, 20, 33), WORKER)
	var fished := false
	for i in range(300):
		tasks._run_scheduler()
		worker._process(.1)
		var task: Task = tasks.get_task(worker.current_task_id)
		if task != null and task.type == Task.Type.FISH: fished = true
		if i % 30 == 0: await process_frame
	_expect(not fished and _pending_fish() == 4, "a Worker beside the zone never takes its fishing")
	_expect(bool(fishing.zone_data(zone_id).no_fisher), "the zone knows the colony has no Ranger")
	var window = load("res://scripts/ui/FishingZonePanel.gd").new()
	scene.add_child(window)
	window.show_zone(fishing.zone_data(zone_id))
	var said: Array = window._fishers.get_children().filter(func(child): return child is Label and not child.is_queued_for_deletion()).map(func(label): return label.text)
	_expect("No Ranger yet: promote one to fish here." in said, "its window says to promote a Ranger: %s" % [said])
	# A Ranger's kit makes a Ranger: the Worker collects it.
	_expect(not worker.change_profession(RANGER) and worker.profession == WORKER, "without a kit there is no Ranger")
	drops.spawn_drop(KIT, 1, Vector3i(SHORE_X - 4, 21, 37))
	_expect(worker.change_profession(RANGER), "with a kit in the colony, the promotion starts")
	var promoted := false
	for i in range(1500):
		tasks._run_scheduler()
		worker._process(.1)
		if worker.profession == RANGER and not worker.promotion_pending():
			promoted = true
			break
		if i % 30 == 0: await process_frame
	_expect(promoted and worker.get_equipment().tool_key() == KIT, "the Worker collects the kit and is a Ranger")
	# The kit binds the spear to the rod they fish with (owner, 2026-11-01): the Equipment view says so.
	var details: Dictionary = load("res://scripts/components/DwarfInspection.gd").equipment_details(worker)
	_expect(String(details.name).contains("Ranger's Kit") and String(details.benefit).contains("fish with its rod")
		and ResourceLoader.exists(String(details.icon)), "the Equipment view shows the Ranger's kit, its picture and its rod: %s" % [details])
	_expect(not bool(fishing.zone_data(zone_id).no_fisher), "the zone has its Ranger")
	var types: Array = tasks._scheduler.types_for(worker)
	_expect(Task.Type.FISH in types and Task.Type.CRAFT in types and Task.Type.HAUL in types and not Task.Type.MINE in types
		and not Task.Type.FELL_TREE in types and not Task.Type.FETCH_BUILD in types, "a Ranger takes fishing, drying and hauling, and no mining, felling or building")
	# The Ranger fishes: one experience a catch, and the catch in their log.
	_expect(await _until_fishing(), "the Ranger walks to a spot and casts")
	_expect(await _until_perch(1), "the catch lands")
	_expect(int(worker.profession_experience[RANGER]) == 1 and int(worker.catch_log.caught[PERCH]) == 1 and not worker.catch_log.has("big"),
		"one experience and one perch in the Ranger's log")
	# Levels at 10, 50, 150 and 400 catches; the Miner keeps the shared scale.
	for pair: Array in [[9, 1], [10, 2], [49, 2], [50, 3], [149, 3], [150, 4], [400, 5], [5000, 5]]:
		_expect(assets.profession_level(RANGER, {RANGER: pair[0]}) == pair[1], "%d catches make level %d" % pair)
	_expect(assets.profession_level("base:profession:miner", {"base:profession:miner": 100}) == 3, "the Miner's levels stay at 10, 100, 500 and 2,500")
	var chances: Array = []
	for count: int in [0, 10, 50, 150, 400]: chances.append(float(assets.level_reward(RANGER, {RANGER: count}, "big_chance", 0.0)))
	_expect(chances == [0.0, 0.15, 0.15, 0.3, 0.45], "big fish: none at level 1, 15%% at 2 and 3, 30%% at 4, 45%% at 5: %s" % [chances])
	# A big catch: two perch land, the lake loses one, and its own model hangs on the line.
	worker.profession_experience[RANGER] = 400
	for cell: Vector3i in cells: fishing.spot_at(cell).roll = 0.1   # under level 5's 45%
	var before: float = fishing.stock("lake")
	var perch := _perch_units()
	_expect(await _until_fishing(), "the Ranger casts again")
	_expect(worker._rig.fishing_pose.catch_big, "the cast knows its fish is big")
	_expect(await _until_units(perch + 2) and _perch_units() == perch + 2, "a big catch lands two perch")
	_expect(absf(fishing.stock("lake") - (before - 1.0)) < 0.01, "and the lake loses one fish")
	_expect(int(worker.catch_log.big) == 1 and int(worker.catch_log.caught[PERCH]) == 2 and int(worker.profession_experience[RANGER]) == 401,
		"the log counts one big fish among two catches")
	var line: Node3D = worker._rig.fishing_pose._catch
	var hung: Node3D = line.get_child(line.get_child_count() - 1) if line.get_child_count() > 0 else null
	_expect(worker._rig.fishing_pose._catch_shown == PERCH + ":big" and hung != null and hung.scene_file_path == assets.big_fish[PERCH].resource_path,
		"the big perch's own model hung on the line")
	# Patience: from level 3, winter slows a Ranger half as much.
	clock_node.season = "winter"
	worker.profession_experience[RANGER] = 49
	var slow: float = fishing.patience(worker.dwarf_id)
	worker.profession_experience[RANGER] = 50
	var patient: float = fishing.patience(worker.dwarf_id)
	var asked: float = fishing.spot_at(cells[0]).rate_for(worker.dwarf_id)
	clock_node.season = "summer"
	var summer: float = fishing.patience(worker.dwarf_id)
	_expect(is_equal_approx(slow, 1.0) and is_equal_approx(patient, 1.5) and is_equal_approx(asked, 1.5) and is_equal_approx(summer, 1.0),
		"winter's half speed becomes three quarters from level 3, and only in winter: %.2f, %.2f, %.2f" % [slow, patient, summer])
	# The roster: Fishing focus, or Fishing disabled with Fish unticked.
	var roster = load("res://scripts/ui/DwarfRosterPanel.gd")
	_expect(roster._work_note(worker) == "Fishing focus", "the roster's note: Fishing focus")
	worker.set_work_permission("fish", false)
	_expect(roster._work_note(worker) == "Fishing disabled" and not Task.Type.FISH in tasks._scheduler.types_for(worker), "with Fish unticked, a Ranger doesn't fish")
	worker.set_work_permission("fish", true)
	# The sheet: the level line, the compact line and the catch log with the next reward.
	var inspection = load("res://scripts/components/DwarfInspection.gd")
	worker.profession_experience[RANGER] = 112
	var experience: Dictionary = inspection.experience(worker)
	_expect(experience.earns and experience.level == 3 and experience.line == "62% to level 4 · 112 fish caught", "the bar's line: %s" % experience.line)
	_expect(String(inspection.describe(worker).profession) == "Ranger · Lv 3", "the compact panel reads Ranger · Lv 3")
	var log: Dictionary = experience.catch_log
	_expect(log.fish[0].item == PERCH and int(log.fish[0].count) == 2 and log.fish.slice(1).all(func(fish): return int(fish.count) == 0),
		"the log: two perch first, no other fish yet")
	_expect(String(log.facts[0][1]) == "1 · about one catch in 2" and String(log.facts[1][1]).contains(" fish · day ") and String(log.facts[2][1]) == "None yet",
		"big fish, the best day and nothing dried yet: %s" % [log.facts])
	_expect(String(log.next.text) == "One catch in three is big · 38 catches to go", "the next reward: %s" % [log.next])
	var view = load("res://scripts/ui/CatchLogView.gd").new()
	scene.add_child(view)
	view.show_log(log, load("res://scripts/ui/DwarfInspectorPanel.gd").SIZES.medium)
	var words: Array = view.find_children("*", "Label", true, false).map(func(label): return label.text)
	_expect("CATCH LOG" in words and "Perch · 2" in words and "NEXT REWARD" in words and "Lv 4" in words, "the tab draws the log: %s" % [words])
	worker.profession_experience[RANGER] = 400
	experience = inspection.experience(worker)
	_expect(experience.line == "Master Ranger · 400 fish caught" and (experience.catch_log.next as Dictionary).is_empty(), "at level 5: Master Ranger, and no next reward")
	# Saves: the log rides with the dwarf; a dwarf who never fished saves none.
	var bystander = _spawn(602, Vector3i(30, 20, 40), WORKER)
	var state: Dictionary = JSON.parse_string(JSON.stringify(worker.serialize_state()))
	var validator = load("res://scripts/components/SaveSnapshotValidator.gd")
	var rule: Dictionary = validator.SCENE.dwarves.roster[0]
	_expect(state.has("catch_log") and validator._validate(state, rule, "save.scene.dwarves.roster[0]", {}).is_empty(), "the catch log matches the save's rules")
	_expect(not bystander.serialize_state().has("catch_log"), "a dwarf who never fished saves no log")
	var factory = load("res://scripts/entities/DwarfFactory.gd").new()
	var data: Dictionary = factory.generate(603, {})
	data.catch_log = state.catch_log
	var copy = factory.spawn(data, 603)
	_expect(int(copy.catch_log.caught[PERCH]) == 2 and int(copy.catch_log.big) == 1, "the log comes back from a save")
	copy.free()
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("RANGER_OK: Labor by career, no Worker fishing, the kit's promotion, experience and levels, a big catch on the line, patience, the roster, the sheet and saves")
	quit(0 if failures.is_empty() else 1)


## Perch lying loose, counting each in a crate (the fishing test counts the crates).
func _perch_units() -> int:
	var count := 0
	for node: Node3D in drops._loose:
		if drops._loose[node] == PERCH: count += drops.quantity_of(node)
	return count


func _until_units(count: int) -> bool:
	for i in range(1500):
		tasks._run_scheduler()
		worker._process(.1)
		if _perch_units() >= count: return true
		if i % 30 == 0: await process_frame
	return false


func _spawn(id: int, cell: Vector3i, profession: String) -> Node3D:
	var factory = load("res://scripts/entities/DwarfFactory.gd").new()
	var data: Dictionary = factory.generate(id, {})
	data.profession = profession
	var agent = factory.spawn(data, id)
	scene.add_child(agent)
	agent.position = Vector3(cell) + Vector3(.5, 1, .5)
	agent.set_process(false)
	tasks.register_dwarf(agent)
	return agent
