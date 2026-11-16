extends "res://scripts/tests/WorkerCraftingTest.gd"

## The Blacksmith and the basic smelter (doc 297). A Worker becomes a Blacksmith by collecting a
## stone hammer. Only a Blacksmith makes the smelter, at the crude workbench from a log, four Rough
## Stones and a Soil. At an installed smelter, two copper ore make one copper bar over a coal, or
## over two logs of one wood when there is no coal (owner: "2 to 1"; the fuel, doc 306): charged by
## hand, the batch melts on the world clock, heating the room only while it melts, then the
## Blacksmith (never a Ranger) takes the cast bar off the stone. A bar and a log hammer into one of
## the trades' copper tools (doc 306: the pick, the saw, the chisel, the hoe), which keeps its
## haft's wood; since doc 310 that is done on the anvil stone, never at the smelter (AnvilStoneTest
## has the stone's own checks). Each batch is a Blacksmith's experience: practice for iron.
## Doc 300 (the owner: "the blacksmith is hammering on the copper ore, then it smelts", then "the
## blacksmith just moves in a weird way when adding the ingredients"): the charge is worked from
## before the boulder's fire hole. Each lump is thrown into the pot, then the Blacksmith crouches and
## blows on the fire through a hollow stick; the coals and the melt show once the charge is in, and
## the bar only when it has set. A charge given up half way lies beside the smelter again. Nothing
## is hammered at the smelter. Logs that feed the fire go to the fire hole, never into the pot.
## Its sounds (owner, 2026-11-13: "The basic smelter could use some audio as well when it is in
## action"): each lump is heard landing in the pot and each log going into the fire hole, then each
## breath on the coals, as they are seen and never twice; the fire is heard only while the coals
## show; the bar is heard coming off the casting stone.
const BLACKSMITH := "base:profession:blacksmith"
const RANGER := "base:profession:ranger"
const HAMMER := "base:item:stone_hammer"
const SMELTER := "base:furniture:basic_smelter"
const ANVIL := "base:furniture:anvil_stone"
const SMELTER_ITEM := "base:item:basic_smelter"
const SMELTER_RECIPE := "base:recipe:basic_smelter"
const BAR_RECIPE := "base:recipe:copper_bar"
const TOOLS := ["copper_pick", "copper_saw", "copper_chisel", "copper_hoe"]
const PICK_RECIPE := "base:recipe:copper_pick"
const PICK := "base:item:copper_pick"
const OAK := "base:item:oak_log"
const COPPER_ORE := "base:item:copper_ore"
const IRON_ORE := "base:item:iron_ore"
const COAL := "base:item:coal"
const SOIL := "base:item:soil"
const BAR := "base:item:copper_bar"
const SMELT_KINDS := ["smelt_toss", "smelt_log", "smelt_blow", "smelt_bar"]
const POSE := "res://scripts/components/DwarfSmeltPose.gd"
var _heard: Array = []       # each of the smelter's sounds as it starts: [kind, the work's share then, whether the pose blows, lumps in the air]
var _heard_order := -1       # the order whose work is noted with them


func _run() -> void:
	create_timer(150).timeout.connect(func(): push_error("Basic smelter test timed out"); quit(1))
	await _setup_crafting_fixture()
	_listen()
	var rooms := root.get_node("RoomManager")
	worker.sleep = 1.0
	# The data: the smelter, the bar (2 ore to 1 bar, over a coal or two logs) and the trades' tools (a bar and a log each).
	var recipe: Dictionary = crafting.recipes[SMELTER_RECIPE]
	_expect(String(recipe.get("section", "")) == "blacksmith" and String(recipe.category) == "Workshops" and recipe.workshop == BENCH
		and int(recipe.ingredient_count) == 1 and recipe.additional_ingredients == [STONE, STONE, STONE, STONE, SOIL],
		"the basic smelter: a log, four Rough stones and a Soil at the crude workbench")
	var bar: Dictionary = crafting.recipes[BAR_RECIPE]
	var ores: Array = crafting.ingredient_keys(bar)
	var fuels: Array = crafting.choices(bar)
	_expect(bar.workshop == SMELTER and ores == [COPPER_ORE] and int(bar.ingredient_count) == 2 and not bar.has("additional_ingredients")
		and fuels.size() == 5 and Array(fuels[0]) == [COAL] and Array(fuels[1]) == [PINE, PINE] and Array(fuels[2]) == [OAK, OAK]
		and int(bar.output_count) == 1 and float(bar.batch_hours) > 0.0,
		"a copper bar: two copper ore (never iron), melted at the smelter over a coal, else two logs of one wood, pine first: %s" % [fuels])
	_expect(not crafting.recipes.has("base:recipe:copper_fitting") and not drops.get_item_defs().has("base:item:copper_fitting"),
		"copper fittings are gone (owner, 2026-11-13)")
	for name: String in TOOLS:
		var tool: Dictionary = crafting.recipes["base:recipe:" + name]
		var hafts: Array = crafting.choices(tool)
		_expect(tool.workshop == ANVIL and String(tool.get("section", "")) == "blacksmith" and String(tool.category) == "Tools"
			and crafting.ingredient_keys(tool) == [BAR] and int(tool.ingredient_count) == 1 and int(tool.output_count) == 1
			and hafts.size() == 4 and Array(hafts[0]) == [PINE] and Array(hafts[1]) == [OAK] and String(tool.output) == "base:item:" + name
			and "tool" in drops.get_item_def(String(tool.output)).material_tags,
			"the %s: a Blacksmith hammers it on the anvil stone from one bar and a log of any wood, pine first" % name.replace("_", " "))
	var placed: Array = root.get_node("UIRegistry").get_place_catalog().get("items", []).filter(func(entry): return entry.key == SMELTER)
	_expect(placed.size() == 1 and placed[0].category == "workshops", "Place files the smelter under Workshops")
	_expect("stockpile_metal" in drops.get_item_def(BAR).material_tags, "bars are stored as Metal")
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
		"the Blacksmith makes the smelter from a log, four Rough stones and a Soil")
	_expect(int(worker.profession_experience.get(BLACKSMITH, 0)) == 1, "the smelter is the Blacksmith's first batch")
	# Installed, it is bare and cold, and its window offers Smelt copper.
	furniture._install(SMELTER, furniture.get_defs()[SMELTER], Vector3i(38, 20, 44), 0, "")
	var smelter = furniture._installed[furniture._next_installed_id - 1]
	var anchor: Vector3i = furniture.room_cells(smelter)[0]
	_expect(smelter.node.get_node_or_null("Batch") == null and not rooms.heat_sources().has(anchor), "an idle smelter is bare and gives no heat")
	camera.set_meta("work_focus", smelter.node.global_position)   # heard from where the smelter stands
	camera.set_meta("work_zoom", 12.0)
	_expect(String(smelter.def.get("fire_sound", "")) == "smelter" and not _fire_heard(smelter), "an idle smelter's fire is silent")
	var window: Dictionary = furniture.get_explorer_data("installed:%d" % smelter.installed_id)
	_expect(window.actions.any(func(action): return action.id == "craft" and action.text == "Smelt copper"), "the smelter's window offers Smelt copper")
	# A bar: iron ore is never taken, two copper ore and a coal are. With no coal and no logs it waits for either.
	drops.spawn_drop(COPPER_ORE, 2, Vector3i(41, 21, 47))
	drops.spawn_drop(IRON_ORE, 2, Vector3i(42, 21, 47))
	id = crafting.queue_order(BAR_RECIPE, 1)
	await _frames(2)
	order = crafting.get_order(id)
	status = crafting.status(order, inventory_script.snapshot(drops, furniture))
	_expect(status == "Waiting for a coal or two logs" and _count(PINE) == 0, "with nothing to burn the bar waits for a coal or two logs: %s" % status)
	drops.spawn_drop(COAL, 1, Vector3i(43, 21, 47))
	var boulder: Vector3i = smelter.work_cells(true)[0]
	var casting: Vector3i = smelter.work_cells(false)[0]
	_expect(boulder != casting and boulder in smelter.cells and casting in smelter.cells, "the boulder and the casting stone are the smelter's two cells")
	var before_fire: Vector3i = smelter.fire_stand()
	_expect(before_fire == boulder + Vector3i(0, 0, 1), "the fire hole is in the boulder's front, and a dwarf can stand before it: %s" % before_fire)
	# Given up once a lump has gone into the pot, the whole charge lies beside the smelter again.
	var pose = worker._rig.smelt_pose
	_heard_order = id
	_heard.clear()
	var thrown := false
	for i in range(1500):
		var charging = crafting.get_order(id)
		if charging != null and not pose._gone.is_empty() and charging.work_share() > .15:
			thrown = true
			break
		await _tick()
	crafting.set_paused(id, true)
	for i in range(4): await _tick()
	_expect(thrown and pose._gone.is_empty() and _count(COPPER_ORE) == 2 and _count(COAL) == 1 and _all_drawn() and _copies_carried() == 0,
		"a charge given up half way lies beside the smelter again, every lump drawn and no copy left: thrown %s, undrawn %d, ore %d, coal %d, drawn %s, copies %d"
		% [thrown, pose._gone.size(), _count(COPPER_ORE), _count(COAL), _all_drawn(), _copies_carried()])
	_expect(_kinds() == ["smelt_toss"], "the first lump is heard landing in the pot before the charge is given up: %s" % [_heard])
	crafting.set_paused(id, false)
	var charged := await _charged(id, smelter)
	_expect(not charged.has("timeout") and String(charged.get("motion", "")) == "charge" and charged.get("stand", Vector3i.ZERO) == before_fire
		and absf(float(charged.surface.y) - (smelter.node.global_position.y + float(smelter.def.batch_surface_height))) < .01,
		"the Blacksmith charges the boulder from before its fire hole, never hammering the ore: %s" % [charged])
	_expect(charged.thrown and not charged.early_fire and not charged.early_stick and not charged.hidden,
		"each lump is thrown into the pot, with no fire and no stick yet, and no lump's own visibility is touched: %s" % [charged])
	_expect(charged.fire and charged.blown and charged.crouched,
		"with the charge in, the coals glow and the Blacksmith crouches and blows on them through the stick: %s" % [charged])
	_expect(not (is_instance_valid(pose.tool) and pose.tool.visible) and _copies_carried() == 0, "the stick is put away when the charge is done")
	# Heard as it is seen (DwarfSmeltPose.cues), and a charge taken up again replays nothing.
	var marks: Array = load(POSE).cues(3)
	_expect(_kinds() == ["smelt_toss", "smelt_toss", "smelt_toss", "smelt_blow", "smelt_blow", "smelt_blow"],
		"a charge is heard as three lumps landing in the pot, then three breaths, each once though it was given up half way: %s" % [_heard])
	_expect(_in_step(marks), "each is heard as it is seen: a lump as it lands, before the coals show, and a breath with the stick at the mouth: %s against %s" % [_heard, marks])
	_expect(not charged.early_loop and charged.loop, "the fire is heard once the charge is in and the coals show, not before: %s" % [charged])
	crafting._refresh()
	crafting._show_batches()
	_expect(_count(COPPER_ORE) == 0 and _count(COAL) == 0 and _count(IRON_ORE) == 2 and _count(BAR) == 0 and crafting.hanging.has(smelter.installed_id),
		"two copper ore and the coal are in the pot; the iron ore stays")
	var line: Dictionary = crafting.hanging_status(smelter.installed_id)
	_expect(String(line.text) == "Melting 2 copper ore · about 4 hours left", "the smelter says what melts and for how long: %s" % line)
	window = furniture.get_explorer_data("installed:%d" % smelter.installed_id)
	_expect(window.rows.has(["Crafter", "Any Blacksmith"]) and window.rows.has(["Melting", "2 copper ore · about 4 hours left"]),
		"the window names its Blacksmith and the melt: %s" % [window.rows])
	var charge: Node3D = smelter.node.get_node_or_null("Batch")
	_expect(charge != null and charge.visible, "the charge shows in the smelter while it melts")
	_expect(_fire_heard(smelter), "and its fire is heard while the copper melts")
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
	crafting._show_batches()
	var cast: Node3D = smelter.node.get_node_or_null("BatchDone")
	_expect(cast != null and cast.visible and not charge.visible, "once the copper has set, the coals are out and the bar shows in its mould")
	_expect(not _fire_heard(smelter), "and the fire is silent")
	_heard.clear()
	var took := false
	for i in range(800):
		var held = tasks.get_task(worker.current_task_id)
		if held != null and held.type == Task.Type.COLLECT: took = true
		if _count(BAR) == 1: break
		await _tick()
	crafting._refresh()
	_expect(took and _count(BAR) == 1 and not crafting.hanging.has(smelter.installed_id), "the Blacksmith takes one copper bar off the stone")
	_expect(cast != null and not cast.visible and not charge.visible, "with the bar taken off, the smelter is bare again")
	_expect(_kinds() == ["smelt_bar"], "the bar is heard coming off the casting stone, once: %s" % [_heard])
	# A trade's tool (docs 306, 310): the bar and a log hammered into a copper pick on the anvil stone. With no
	# log it waits for one, and with no anvil stone for that: the smelter's casting stone no longer serves. An
	# oak log gives it an oak haft.
	id = crafting.queue_order(PICK_RECIPE, 1)
	await _frames(2)
	status = crafting.status(crafting.get_order(id), inventory_script.snapshot(drops, furniture))
	_expect(status == "Waiting for a log", "with no log for its haft the pick waits for one: %s" % status)
	drops.spawn_drop(OAK, 1, Vector3i(42, 21, 46))
	await _frames(2)
	status = crafting.status(crafting.get_order(id), inventory_script.snapshot(drops, furniture))
	_expect(status == "Needs an anvil stone" and _count(BAR) == 1, "with a smelter but no anvil stone the pick waits for an anvil stone: %s" % status)
	furniture._install(ANVIL, furniture.get_defs()[ANVIL], Vector3i(38, 20, 48), 0, "")
	var anvil = furniture._installed[furniture._next_installed_id - 1]
	var face: Vector3i = anvil.work_cells(false)[0]
	var hammered := await _worked(id)
	_expect(not hammered.has("timeout") and _count(PICK) == 1 and _count(BAR) == 0 and _count(OAK) == 0, "the Blacksmith hammers the bar and the log into one copper pick")
	_expect(String(hammered.get("motion", "")) == "hew" and _beside(hammered.get("stand", Vector3i.ZERO), face) and not _beside(hammered.get("stand", Vector3i.ZERO), casting)
		and absf(float(hammered.surface.y) - (anvil.node.global_position.y + .9375)) < .01 and String(hammered.get("worked", "")) == BAR,
		"the bar is hammered with the maul on the anvil stone, at bench height, and not at the smelter: %s" % [hammered])
	var pick: Node3D = drops.nearest_loose_of_key(PICK, worker.current_cell())
	_expect(pick != null and root.get_node("CraftMaterials").of_item(pick) == "base:material:oak", "the pick keeps its haft's wood")
	_expect(int(worker.profession_experience.get(BLACKSMITH, 0)) == 3, "a tool counts toward the practice too")
	# With no coal left, a bar is melted over two logs: they go to the fire hole, the ore to the pot.
	drops.spawn_drop(COPPER_ORE, 2, Vector3i(41, 21, 47))
	drops.spawn_drop(PINE, 2, Vector3i(43, 21, 47))
	id = crafting.queue_order(BAR_RECIPE, 1)
	_heard_order = id
	_heard.clear()
	# A batch under way keeps the fuel it chose: a coal that turns up once a dwarf has the order is left alone.
	for i in range(600):
		if crafting.get_order(id) != null and crafting.get_order(id).worker_id >= 0: break
		await _tick()
	drops.spawn_drop(COAL, 1, Vector3i(44, 21, 47))
	var logged := await _charged(id, smelter)
	_expect(not logged.has("timeout") and logged.fed == 2 and logged.thrown and logged.fire and logged.blown and _count(PINE) == 0 and _count(COPPER_ORE) == 0
		and _count(COAL) == 1 and crafting.hanging.has(smelter.installed_id),
		"with no coal the charge burns two pine logs, fed to the fire, and melts as before; the late coal is left: %s, coal %d, pine %d" % [logged, _count(COAL), _count(PINE)])
	_expect(int(worker.profession_experience.get(BLACKSMITH, 0)) == 4, "and it is a batch like any other")
	var kinds := _kinds()
	_expect(kinds.size() == 7 and kinds.slice(0, 4).count("smelt_log") == 2 and kinds.slice(0, 4).count("smelt_toss") == 2
		and kinds.slice(4) == ["smelt_blow", "smelt_blow", "smelt_blow"],
		"over logs, each log is heard going into the fire hole and each lump into the pot, then the three breaths: %s" % [kinds])
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("BASIC_SMELTER_OK: the Blacksmith's promotion and page, the smelter from raw goods, 2 copper ore and a coal to 1 bar thrown into the pot and blown on from before the fire hole, a charge given up lying there again, melting on the clock with heat only while it melts, the bar showing once set, saves, Blacksmith-only take-down, a copper pick hammered on the casting stone with its haft's wood, a bar melted over logs, experience, and its sounds: each lump, log and breath heard as seen, the fire only while the coals show, the bar coming off")
	quit(0 if failures.is_empty() else 1)


## Ticks until the order is done, noting where the Blacksmith stood and how they worked it.
func _worked(id: int) -> Dictionary:
	var seen := {}
	for i in range(800):
		var order = crafting.get_order(id)
		if order == null: return seen
		if worker._task_phase == worker.TaskPhase.FETCH_WORKING and order.worker_id == worker.dwarf_id:
			seen = {"stand": worker.current_cell(), "motion": order.work_motion(), "surface": order.work_surface(),
				"worked": drops.item_key_of(order.item) if is_instance_valid(order.item) else ""}
		await _tick()
	seen["timeout"] = true
	return seen


## Ticks until the charge is in and blown on, noting where the Blacksmith stood and what showed
## before the whole charge was in the pot and after.
func _charged(id: int, smelter) -> Dictionary:
	var seen := {"thrown": false, "early_fire": false, "early_stick": false, "hidden": false, "fire": false, "blown": false, "crouched": false, "fed": 0,
		"early_loop": false, "loop": false}
	var pose = worker._rig.smelt_pose
	for i in range(1500):
		var order = crafting.get_order(id)
		if order == null: return seen
		if worker._task_phase == worker.TaskPhase.FETCH_WORKING and order.worker_id == worker.dwarf_id:
			seen.merge({"stand": worker.current_cell(), "motion": order.work_motion(), "surface": order.work_surface()}, true)
			seen.fed = maxi(int(seen.fed), order.fire_goods().size())   # the logs that feed the fire hole (doc 306)
			crafting._show_batches()
			var fire: Node3D = smelter.node.get_node_or_null("Batch")
			var lit: bool = fire != null and fire.visible
			var stick: bool = is_instance_valid(pose.tool) and pose.tool.visible
			if order.batch_showing():
				seen.fire = seen.fire or lit
				seen.blown = seen.blown or (pose.blowing and stick)
				seen.crouched = seen.crouched or worker._rig.body.position.y < -.2
				seen.loop = seen.loop or _fire_heard(smelter)
			else:
				seen.thrown = seen.thrown or pose._copies.any(func(copy): return is_instance_valid(copy))
				seen.early_fire = seen.early_fire or lit
				seen.early_stick = seen.early_stick or stick
				seen.early_loop = seen.early_loop or _fire_heard(smelter)
			for lump: Node3D in order.staged_items:
				if is_instance_valid(lump) and not lump.visible: seen.hidden = true
		await _tick()
	seen["timeout"] = true
	return seen


## Hears the smelter's sounds as they start, with where the work stood. A test's work runs in a
## blink, so a profile's real-time cooldown or voice cap would swallow sounds that play in the game:
## here the smelter's kinds are heard without them, from a pool the test cannot fill.
func _listen() -> void:
	var feedback: Node = root.get_node("WorkFeedback")
	feedback.config.audio.max_voices = 64
	var profiles: Dictionary = feedback.config.audio.get("profiles", {})
	for kind: String in SMELT_KINDS:
		if not profiles.has(kind): continue
		profiles[kind].erase("cooldown_seconds")
		profiles[kind].erase("max_voices")
	feedback.sound_started.connect(_on_sound)


func _on_sound(kind: String, _at: Vector3, _variant: int) -> void:
	if not kind in SMELT_KINDS: return
	var order = crafting.get_order(_heard_order)
	var pose = worker._rig.smelt_pose
	var flying: int = pose._copies.filter(func(copy) -> bool: return is_instance_valid(copy) and copy.visible).size()
	_heard.append([kind, snappedf(order.work_share(), .001) if order != null else -1.0, bool(pose.blowing), flying])


func _kinds() -> Array:
	return _heard.map(func(entry: Array) -> String: return String(entry[0]))


## Whether each sound heard came within a tick's work of its mark in the pose ([share, kind]): a
## lump as its thrown copy stops being drawn, with none in the air; a breath with the stick at the mouth.
func _in_step(marks: Array) -> bool:
	if _heard.size() != marks.size(): return false
	for i in range(marks.size()):
		var late: float = float(_heard[i][1]) - float(marks[i][0])
		if _heard[i][0] != marks[i][1] or late < -.0005 or late > .02 or bool(_heard[i][2]) != (_heard[i][0] == "smelt_blow") or int(_heard[i][3]) != 0: return false
	return true


## Whether the fire loop pool (FurnitureFireSound) gives the smelter a voice now.
func _fire_heard(smelter) -> bool:
	var pool = furniture.get_node("FireSound")
	for i in range(2): pool._process(.3)   # a scan, and the voices follow
	return pool.voices.any(func(voice: Dictionary) -> bool: return voice.source == smelter.node and float(voice.target_gain) > 0.0)


## Whether every loose lump of the charge is drawn: none of its meshes is left on no layer.
func _all_drawn() -> bool:
	for node: Node3D in drops._loose.keys():
		if not drops.item_key_of(node) in [COPPER_ORE, COAL]: continue
		var meshes: Array = node.find_children("*", "VisualInstance3D", true, false)
		if node is VisualInstance3D: meshes.append(node)
		for mesh: VisualInstance3D in meshes:
			if mesh.layers == 0: return false
	return true


## The copies of lumps the Blacksmith still carries: none once a charge is done or given up.
func _copies_carried() -> int:
	var count := 0
	for child: Node in worker.get_children():
		if String(child.get_meta("item_key", "")) in [COPPER_ORE, COAL] and not child.is_queued_for_deletion(): count += 1
	return count


func _beside(stand: Vector3i, cell: Vector3i) -> bool:
	var gap := stand - cell
	return gap.y == 0 and absi(gap.x) + absi(gap.z) == 1
