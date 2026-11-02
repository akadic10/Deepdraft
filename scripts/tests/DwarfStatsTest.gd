extends "res://scripts/tests/WorkerCraftingTest.gd"

## Dwarf stats (doc 41 "Stats"). A new dwarf's six stats share one total, 18, in a shape of its own,
## each a step from Poor (1) to Excellent (5), the same from the same seed. Iron Constitution
## keeps Toughness at Good or better and Frail at Fair or worse, with the total kept, and no
## dwarf holds both. A profession's fit is its main stat twice and its second once, rounded to
## a step. A dwarf saves its stats; one built without them is Average. The character sheet's
## Traits tab shows Body and Mind, each stat's word, its pips and what it will do.

const STRONG := {"base:stat:strength": 5, "base:stat:agility": 1, "base:stat:toughness": 4,
	"base:stat:wits": 3, "base:stat:wisdom": 3, "base:stat:charisma": 2}


func _run() -> void:
	create_timer(150).timeout.connect(func(): push_error("DwarfStats timeout"); quit(1))
	await _setup_crafting_fixture()
	var assets: Node = root.get_node("DwarfAssets")
	var factory = load("res://scripts/entities/DwarfFactory.gd").new()
	_rolls(assets, factory)
	_shapes(factory)
	_fits(assets)
	_rates(assets)
	_kept(factory)
	await _sheet()
	for failure: String in failures: push_error(failure)
	print("DWARF_STATS_OK: rolls, shapes, fits, saves and sheet" if failures.is_empty() else "DWARF_STATS_FAIL")
	quit(0 if failures.is_empty() else 1)


## Six stats, 18 in all, each from 1 to 5; the same from the same seed; dwarves differ, and
## nearly every one is Good or better at something.
func _rolls(assets: Node, factory) -> void:
	var ids: Array = assets.stat_ids()
	var shapes := {}
	var good := 0
	for index in range(60):
		var stats: Dictionary = factory.generate(index, {}).stats
		var total := 0
		var bounded := stats.size() == ids.size()
		for id: String in ids:
			bounded = bounded and stats.has(id) and int(stats[id]) >= 1 and int(stats[id]) <= 5
			total += int(stats.get(id, 0))
		_expect(bounded and total == 18, "dwarf %d has six stats from Poor to Excellent, 18 in all: %s" % [index, stats])
		shapes[str(stats)] = true
		if int(stats.values().max()) >= 4: good += 1
	_expect(factory.generate(7, {}).stats == factory.generate(7, {}).stats, "the same seed gives the same stats")
	_expect(shapes.size() > 20, "dwarves differ in shape: %d shapes in 60" % shapes.size())
	_expect(good >= 55, "nearly every dwarf is Good or better at something: %d of 60" % good)


## Iron Constitution keeps Toughness at Good or better and Frail at Fair or worse, with the
## total kept; the two share an exclusion group, so no dwarf holds both.
func _shapes(factory) -> void:
	for trait_id: String in ["base:trait:iron_constitution", "base:trait:frail"]:
		var shaped := true
		for seed_value in range(1, 41):
			var rng := RandomNumberGenerator.new()
			rng.seed = seed_value
			var traits: Array[String] = [trait_id]
			var stats: Dictionary = factory._roll_stats(rng, traits)
			var total := 0
			for id: String in stats: total += int(stats[id])
			var tough := int(stats["base:stat:toughness"])
			shaped = shaped and total == 18 and (tough >= 4 if trait_id.ends_with("iron_constitution") else tough <= 2)
		_expect(shaped, "%s shapes Toughness and keeps the total" % trait_id)
	var both := 0
	for index in range(300):
		var traits: Array = factory.generate(index, {}).traits
		if "base:trait:iron_constitution" in traits and "base:trait:frail" in traits: both += 1
	_expect(both == 0, "no dwarf is both Iron Constitution and Frail (%d were)" % both)


## The main stat twice and the second once, rounded to a step; every profession names two.
func _fits(assets: Node) -> void:
	_expect(assets.profession_fit("base:profession:miner", STRONG) == 5, "Strength 5 and Toughness 4 make an Excellent Miner")
	_expect(assets.profession_fit("base:profession:carpenter", STRONG) == 4, "Wits 3 and Strength 5 make a Good Carpenter")
	_expect(assets.profession_fit("base:profession:ranger", STRONG) == 2, "Wisdom 3 and Agility 1 make a Fair Ranger")
	_expect(assets.profession_fit("base:profession:no_such_job", STRONG) == 0, "a profession naming no stats has no fit")
	for key: String in assets.profession_ids():
		var pair: Array = assets.profession_stats(key)
		_expect(pair.size() == 2 and assets.stat_ids().has(pair[0]) and assets.stat_ids().has(pair[1]), "%s names a main and a second stat" % key)
	for id: String in assets.stat_ids():
		_expect(ResourceLoader.exists(String(assets.stat_definition(id).get("icon", ""))), "%s has its picture" % id)


## 6% of work speed a step from Average (step 3): Strength digs and fells, Wits crafts and
## builds, and no stat speeds other work.
func _rates(assets: Node) -> void:
	_expect(is_equal_approx(assets.work_rate("mining", STRONG), 1.12) and is_equal_approx(assets.work_rate("felling", STRONG), 1.12), "Excellent Strength digs and fells 12% faster")
	_expect(is_equal_approx(assets.work_rate("crafting", STRONG), 1.0) and is_equal_approx(assets.work_rate("building", STRONG), 1.0), "Average Wits crafts and builds at the usual speed")
	var clumsy := STRONG.duplicate()
	clumsy["base:stat:wits"] = 1
	_expect(is_equal_approx(assets.work_rate("crafting", clumsy), 0.88), "Poor Wits crafts 12% slower")
	_expect(is_equal_approx(assets.work_rate("planting", STRONG), 1.0) and is_equal_approx(assets.work_rate("", STRONG), 1.0), "no stat speeds other work")


## A dwarf saves its stats; one built without them is Average.
func _kept(factory) -> void:
	worker.stats = STRONG.duplicate()
	_expect(worker.serialize_state().stats == STRONG, "a dwarf saves its stats")
	var data: Dictionary = factory.generate(2, {})
	data.erase("stats")
	var bare = factory.spawn(data, 900)
	_expect(bare.stats.size() == 6 and bare.stats.values().all(func(step) -> bool: return int(step) == 3), "a dwarf built without stats is Average: %s" % bare.stats)
	bare.free()


## The Traits tab: Body and Mind under their headings, each stat's word, its pips filled to
## the step, and what it will do.
func _sheet() -> void:
	worker.stats = STRONG.duplicate()
	var sheet = load("res://scripts/ui/DwarfInspectorPanel.gd").new()
	scene.add_child(sheet)
	await _frames(2)
	sheet.show_data(load("res://scripts/components/DwarfInspection.gd").describe(worker), false)
	sheet._show_tab(2)
	await _frames(2)
	var strength: Dictionary = sheet._stat_rows["base:stat:strength"]
	var agility: Dictionary = sheet._stat_rows["base:stat:agility"]
	_expect(strength.word.text == "Excellent" and agility.word.text == "Poor", "each stat shows its step's word")
	var fill: StyleBox = UITheme.cell_style("fill", int(sheet._size.pip_cell))
	var filled := (agility.marks as Array).filter(func(mark: PanelContainer) -> bool: return mark.get_theme_stylebox("panel") == fill).size()
	_expect(filled == 1 and int(strength.step) == 5, "the pips fill to the step (%d filled for Poor)" % filled)
	_expect(String(strength.effect.text) == "Digs, fells, clears and shapes stone 12% faster", "a stat at work says how much: %s" % strength.effect.text)
	_expect(String(agility.effect.text) == "Not active yet: hunting, aim and dodging", "a stat that does nothing yet says so: %s" % agility.effect.text)
	var columns: Array = sheet._stat_columns.get_children()
	_expect(columns.size() == 2 and columns[0].get_child_count() == 4 and columns[1].get_child_count() == 4
		and (columns[0].get_child(0) as Label).text == "BODY", "Body and Mind, three stats each under a heading")
	sheet.queue_free()
