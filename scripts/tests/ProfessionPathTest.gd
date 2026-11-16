extends "res://scripts/tests/WorkerCraftingTest.gd"

## The profession path (doc 306). The owner, 2026-11-13: "I am not sure it feels great that all of
## them can start right away … it doesn't feel rewarding at all", then the picks: the Miner, the
## Carpenter and the Stonemason wait for a copper pick, saw and chisel that only a Blacksmith makes
## (and the Farmer for a copper hoe, doc 309); the crude carpentry and masonry kits and the
## stone hoe are gone; the log bed and every log door are a Worker's again; copper melts over a coal
## or two logs. Here: who needs which tool and who makes it, the pages, a Worker's bed and door, how
## a batch chooses its fuel and its haft, and the career map. BasicSmelterTest makes
## a tool and melts over logs; ToolPromotionTest and MinerProfessionTest collect the tools.
## Also (owner, 2026-11-13, in a new game: "carpenter for example is lit up even though I cannot build
## it, same with others"): the crafting screen lights a trade only when the colony has a dwarf of it.
## And (owner, 2026-11-13, of the career map as a tree with the copper trades under the Blacksmith: "it
## would seem as if the Dwarf has to be a blacksmith first before becoming a farmer"): every trade
## stands in one row under the Worker, and who makes its tool is said under the tiles.
const P := "base:profession:"
const WORKER := "base:profession:worker"
const TOOL := "base:item:"
const RECIPE := "base:recipe:"
const COAL := "base:item:coal"
const COPPER := "base:item:copper_ore"
const OAK := "base:item:oak_log"


func _run() -> void:
	create_timer(100).timeout.connect(func(): push_error("Profession path test timed out"); quit(1))
	await _setup_crafting_fixture()
	var assets := root.get_node("DwarfAssets")
	worker.sleep = 1.0
	# Who needs what, and who makes it.
	var needs := {"ranger": "ranger_kit", "blacksmith": "stone_hammer", "miner": "copper_pick", "carpenter": "copper_saw", "stonemason": "copper_chisel"}
	for career: String in needs:
		_expect(assets.profession_tool(P + career) == TOOL + String(needs[career]), "the %s needs the %s" % [career, needs[career]])
	for tool: String in ["ranger_kit", "stone_hammer"]:
		_expect(assets.tool_maker(TOOL + tool) == WORKER, "a Worker makes the " + tool)
	for tool: String in ["copper_pick", "copper_saw", "copper_chisel", "copper_hoe"]:
		_expect(assets.tool_maker(TOOL + tool) == P + "blacksmith", "a Blacksmith makes the " + tool)
	_expect(assets.tool_source_text(TOOL + "copper_saw") == "A Blacksmith makes it at the anvil stone."
		and assets.tool_source_text(TOOL + "ranger_kit") == "A Worker makes it at the crude workbench.",
		"a tool's maker and bench are worded from its recipe: %s / %s" % [assets.tool_source_text(TOOL + "copper_saw"), assets.tool_source_text(TOOL + "ranger_kit")])
	for gone: String in ["carpentry_kit", "masonry_kit", "stone_hoe"]:
		_expect(not crafting.recipes.has(RECIPE + gone) and not drops.get_item_defs().has(TOOL + gone), "the %s is retired" % gone)
	for key: String in drops.get_item_defs():
		if "tool" in drops.get_item_def(key).get("material_tags", []):
			_expect(ResourceLoader.exists(String(drops.get_item_def(key).model)) and ResourceLoader.exists(preload("res://scripts/components/Pictures.gd").item(key)),
				"every tool has its model and its picture: " + key)
	# Rudimentary is the first camp: the bed and every door are a Worker's again.
	for name: String in ["log_bed", "door_2", "door_3", "door_4"]:
		var recipe: Dictionary = crafting.recipes[RECIPE + name]
		_expect(not recipe.has("section") and recipe.workshop == BENCH and String(recipe.category) == "Rooms", "a Worker makes the %s at the crude workbench" % name)
	var pages := {"rudimentary": [], "carpenter": [], "stonemason": [], "blacksmith": []}
	for recipe: Dictionary in crafting.recipes.values():
		var page := String(recipe.get("section", "rudimentary"))
		if pages.has(page): pages[page].append(String(recipe.id).trim_prefix(RECIPE))
	_expect(pages.rudimentary == ["crude_workbench", "torch", "crude_ladder", "campfire", "log_stool", "log_bed", "door_2", "door_3", "door_4", "ranger_kit", "stone_hammer"],
		"Rudimentary: the camp's goods and the first two trades' tools: %s" % [pages.rudimentary])
	_expect(pages.carpenter == ["carpenter_bench", "pine_plank", "oak_plank", "juniper_plank", "apple_plank", "tool_rack", "raw_materials_crate", "finished_goods_pallet", "food_shelf",
		"dining_table", "bench", "log_fence", "log_gate", "board_game_table"],
		"the Carpenter saws planks (doc 308) and keeps storage, tables, fences and games: %s" % [pages.carpenter])
	_expect(pages.stonemason == ["mason_bench", "stone_stool", "hearth"], "the Stonemason keeps the stool and the hearth: %s" % [pages.stonemason])
	_expect(pages.blacksmith == ["basic_smelter", "anvil_stone", "copper_bar", "copper_pick", "copper_saw", "copper_chisel", "copper_hoe", "copper_nail"], "the Blacksmith makes its two stations, copper, the trades' tools and nails (doc 313): %s" % [pages.blacksmith])
	# A Worker makes a bed and a door at the crude workbench.
	furniture._install(BENCH, furniture.get_defs()[BENCH], Vector3i(45, 20, 42), 0)
	drops.spawn_drop(PINE, 5, Vector3i(42, 21, 42))
	var bed: int = crafting.queue_order(RECIPE + "log_bed", 1)
	_expect(await _completed(bed) and _count("base:item:log_bed") == 1 and _count(PINE) == 1, "a Worker makes a log bed from four logs at the crude workbench")
	var door: int = crafting.queue_order(RECIPE + "door_2", 1)
	_expect(await _completed(door) and _count("base:item:door_2") == 1 and _count(PINE) == 0, "and a log door from one")
	# A batch's choice of fuel and of haft: the first the colony can supply whole.
	var bar: Dictionary = crafting.recipes[RECIPE + "copper_bar"]
	var pick: Dictionary = crafting.recipes[RECIPE + "copper_pick"]
	_expect(Array(crafting.choice_keys(bar, _have({COAL: 1, PINE: 2}))) == [COAL], "a coal is burnt before logs")
	_expect(Array(crafting.choice_keys(bar, _have({PINE: 2, OAK: 2}))) == [PINE, PINE], "with no coal, two pine logs")
	_expect(Array(crafting.choice_keys(bar, _have({PINE: 1, OAK: 2}))) == [OAK, OAK], "two logs of one wood: a lone pine log is passed over for two oak")
	_expect(crafting.choice_keys(bar, _have({PINE: 1, OAK: 1})).is_empty(), "one log of each wood is no fuel")
	_expect(Array(crafting.choice_keys(pick, _have({OAK: 1}))) == [OAK] and crafting.choice_keys(crafting.recipes[RECIPE + "campfire"], _have({OAK: 1})).is_empty(),
		"a tool's haft is a log of any wood; a recipe with no choice takes none")
	var one_log: Array[String] = [PINE]
	var nothing: Array[String] = []
	_expect(Array(crafting.choice_matching(bar, one_log, _have({COAL: 3}))) == [PINE, PINE] and Array(crafting.choice_matching(bar, nothing, _have({COAL: 3}))) == [COAL],
		"a saved batch with a log beside its smelter goes on burning logs; one with nothing staged chooses afresh")
	var ore: Array[String] = [COPPER]
	_expect(crafting.recipe_waiting_reason(bar, ore, _have({COPPER: 2})) == "Waiting for a coal or two logs",
		"a bar with ore and nothing to burn says what it waits for: %s" % crafting.recipe_waiting_reason(bar, ore, _have({COPPER: 2})))
	await _review_crafters()
	await _review_map()
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("PROFESSION_PATH_OK: who needs which tool and who makes it, the retired kits, the pages, a Worker's bed and door, fuel and haft choices, the career map with every trade under the Worker")
	quit(0 if failures.is_empty() else 1)


## The crafting screen: a trade's tile is lit only while the colony has a dwarf of that trade. The
## others are dimmed and say the way to one, in the crafting window's Crafters row and on the dock's
## Craft menu alike; their pages still open.
func _review_crafters() -> void:
	var carpenter_need: Dictionary = crafting.section_need("carpenter")
	_expect(crafting.section_need("rudimentary").is_empty() and crafting.section_need("farmer").is_empty()
		and String(carpenter_need.get("tag", "")) == "No Carpenter yet"
		and String(carpenter_need.get("how", "")) == "A dwarf becomes one by collecting a copper saw. A Blacksmith makes it at the anvil stone."
		and String(crafting.section_need("ranger").get("how", "")) == "A dwarf becomes one by collecting a ranger's kit. A Worker makes it at the crude workbench.",
		"a page nobody can craft from says the way to its trade; Rudimentary and planned pages say nothing: %s / %s" % [carpenter_need, crafting.section_need("ranger")])
	dock.open_crafting()
	await _frames(6)
	_expect(_lit_tiles() == {"rudimentary": true, "carpenter": false, "stonemason": false, "blacksmith": false, "farmer": false, "ranger": false, "miner": false, "brewer": false},
		"with only Workers, only Rudimentary is lit: %s" % [_lit_tiles()])
	panel.select_section("carpenter")
	await _frames(2)
	_expect(panel._heading.text == "Carpenter · No Carpenter yet" and panel._crafter_tiles.carpenter.tooltip_text.contains("No Carpenter yet. A dwarf becomes one by collecting a copper saw.")
		and not panel.selected.is_empty(),
		"the Carpenter's page still opens, and says nobody can craft from it: %s" % panel._heading.text)
	await _review_shot("crafting_window")
	worker.profession = P + "carpenter"
	tasks.work_policy_changed()
	panel.refresh()
	_expect(_lit_tiles().carpenter and not _lit_tiles().rudimentary and panel._heading.text == "Carpenter"
		and String(crafting.section_need("rudimentary").get("tag", "")) == "No Worker left",
		"a Carpenter lights its page; with no Worker left, Rudimentary dims: %s, %s" % [_lit_tiles(), crafting.section_need("rudimentary")])
	worker.profession = WORKER
	tasks.work_policy_changed()
	manager.close("craft")
	# The dock's Craft menu marks the same trades, and its buttons still open their pages.
	_click(dock._button_by_target.craft.get_global_rect().get_center())
	await _frames(6)
	var buttons := {}
	for button in dock._panel_body.get_children(): buttons[String(button.name).trim_prefix("Crafter").to_lower()] = [button.locked, button.planned, button.disabled]
	_expect(buttons == {"rudimentary": [false, false, false], "carpenter": [true, false, false], "stonemason": [true, false, false], "blacksmith": [true, false, false],
		"farmer": [false, true, false], "ranger": [true, false, false], "miner": [false, true, false], "brewer": [false, true, false]},
		"the Craft menu locks the trades the colony has no dwarf of, apart from the planned ones: %s" % [buttons])
	var locked_button = dock._panel_body.get_node("CrafterCarpenter")
	_expect(locked_button.status_label == "No Carpenter yet" and locked_button.description.contains("A Blacksmith makes it at the anvil stone."),
		"its hover card says the way to a Carpenter: %s / %s" % [locked_button.status_label, locked_button.description])
	locked_button.grab_focus()   # its hover card, for the picture
	await create_timer(.5).timeout
	await _review_shot("craft_menu")
	_click(locked_button.get_global_rect().get_center())
	await _frames(6)
	_expect(manager.is_open("craft") and panel.section_id == "carpenter", "a locked trade's page still opens from the dock")
	manager.close("craft")


## Each Crafters tile, by whether its picture is drawn at full strength.
func _lit_tiles() -> Dictionary:
	var lit := {}
	for key: String in panel._crafter_tiles: lit[key] = (panel._crafter_tiles[key] as Button).get_theme_color("icon_normal_color").v > 0.9
	return lit


## A stock snapshot holding these counts, as ColonyInventory gives one.
func _have(counts: Dictionary) -> Dictionary:
	var totals := {}
	for key: String in counts: totals[key] = {"available": int(counts[key]), "total": int(counts[key])}
	return totals


## The career map: every trade one step under the Worker, grouped by who makes its tool; a trade
## whose tool the colony lacks says so, and its card names the tool's maker.
func _review_map() -> void:
	var director = load("res://scripts/entities/DwarfDirector.gd").new()
	director.name = "Dwarves"
	director.window_manager_path = NodePath("../Windows")
	scene.add_child(director)
	director._agents.append(worker)
	director.open_professions(worker)
	var map = director._profession_panel
	await _frames(4)
	_expect(map._selected == P + "blacksmith", "a Worker's map opens on the Blacksmith, whose copper opens the other trades")
	_expect(map._fit_row.visible and String(map._fit_text.text).ends_with("fit · Strength, then Wits"), "the card names the trade's two stats: %s" % map._fit_text.text)
	# A line is what a dwarf is promoted from, so no trade hangs under another: under the Blacksmith
	# the copper trades read as "be a Blacksmith first".
	var parents := {}
	for key: String in map._entries: parents[key.trim_prefix(P)] = String(map._map_parent(key)).trim_prefix(P)
	_expect(parents == {"worker": "", "ranger": "worker", "blacksmith": "worker", "miner": "worker", "carpenter": "worker", "stonemason": "worker", "farmer": "worker"},
		"every trade hangs under the Worker, none under another trade: %s" % [parents])
	var groups := {}
	for group: Dictionary in map._groups:
		groups[String(group.maker).trim_prefix(P)] = [group.trades.map(func(key: String) -> String: return key.trim_prefix(P)), String(group.caption.text)]
	_expect(groups == {"worker": [["ranger", "blacksmith"], "A Worker makes their tools"], "blacksmith": [["miner", "carpenter", "stonemason", "farmer"], "A Blacksmith makes their tools"]},
		"the trades are grouped by who makes their tool, and each group says who: %s" % [groups])
	_review_layout(map, "at 1280 x 720")
	root.size = Vector2i(960, 540)   # the narrow, compact map
	await _frames(8)
	_expect(is_equal_approx(map._nodes[P + "ranger"].button.size.x, 90.0), "at 960 x 540 the map is its narrow self: %s" % map._nodes[P + "ranger"].button.size.x)
	_review_layout(map, "at 960 x 540")
	root.size = Vector2i(1280, 720)
	await _frames(8)
	map.refresh()
	var states := {}
	for key: String in map._nodes: states[key.trim_prefix(P)] = String(map._nodes[key].state.text)
	_expect(states == {"worker": "Current", "ranger": "Needs tool", "blacksmith": "Needs tool", "miner": "Needs tool", "carpenter": "Needs tool", "stonemason": "Needs tool", "farmer": "Needs tool"},
		"with no tools yet every trade says it needs its tool: %s" % [states])
	map.select_profession(P + "miner")
	await _frames(2)
	_expect(map._status.text == "TOOL REQUIRED" and map._promote.disabled and map._requirements.text.contains("Copper pick · 0 available")
		and map._requirements.text.contains("A Blacksmith makes it at the anvil stone.") and map._requirements.text.contains("No spare copper pick."),
		"the Miner's card says what it waits for and who makes it: %s / %s" % [map._status.text, map._requirements.text])
	drops.spawn_drop(TOOL + "copper_saw", 1, Vector3i(41, 21, 41))
	await _frames(2)
	map.select_profession(P + "carpenter")
	await _frames(2)
	_expect(String(map._nodes[P + "carpenter"].state.text) == "Available" and String(map._nodes[P + "miner"].state.text) == "Needs tool"
		and not map._promote.disabled and map._requirements.text.contains("Copper saw · 1 available"),
		"a saw in the colony opens the Carpenter and nothing else: %s / %s" % [map._nodes[P + "carpenter"].state.text, map._requirements.text])
	for shot: Array in [["miner", "career_map_miner"], ["blacksmith", "career_map_blacksmith"]]:
		map.select_profession(P + String(shot[0]))
		await _frames(6)
		await _review_shot(String(shot[1]))
	manager.close("professions")


## Where the map's tiles, brackets and names stand: the trades in one row below the Worker, each
## group's tiles side by side with its name under them, nothing covering anything else.
func _review_layout(map, size: String) -> void:
	var area := Rect2(Vector2.ZERO, map._tree.custom_minimum_size)
	var worker_tile: Button = map._nodes[WORKER].button
	var tiles := {}
	for key: String in map._nodes:
		var tile: Button = map._nodes[key].button
		var rect := Rect2(tile.position, tile.size)
		for other: String in tiles: _expect(not (tiles[other] as Rect2).intersects(rect), "no tile covers another %s: %s and %s" % [size, key, other])
		tiles[key] = rect
		_expect(area.encloses(rect), "the map holds the tile of %s %s" % [key, size])
		if key == WORKER: continue
		_expect(is_equal_approx(tile.position.y, map._nodes[P + "ranger"].button.position.y) and tile.position.y >= worker_tile.position.y + worker_tile.size.y,
			"%s stands in the one row of trades below the Worker %s" % [key, size])
	var names: Array[Rect2] = []
	for group: Dictionary in map._groups:
		var span: Rect2 = map._group_span(group)
		for key: String in tiles:
			_expect(key in group.trades or not span.intersects(tiles[key]), "the tiles of a group stand side by side %s: %s is among %s" % [size, key, group.trades])
		var caption: Label = group.caption
		var rect := Rect2(caption.position, caption.size)
		_expect(area.encloses(rect) and rect.position.y >= span.end.y and absf(rect.get_center().x - span.get_center().x) <= 1.0,
			"a group's name stands under the middle of its tiles, on the map %s: %s at %s under %s in %s" % [size, caption.text, rect, span, area])
		for other: Rect2 in names: _expect(not other.intersects(rect), "no group's name covers another %s: %s" % [size, caption.text])
		names.append(rect)


## With --capture on the hidden screen (tools/run_offscreen.py), a picture of the screen for review.
func _review_shot(label: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	await _frames(3)
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tmp/profession_path_20261113"))
	root.get_texture().get_image().save_png("res://tmp/profession_path_20261113/%s.png" % label)
