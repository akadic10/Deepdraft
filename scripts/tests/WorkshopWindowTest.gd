extends "res://scripts/tests/WorkerCraftingTest.gd"

## A workshop's window is worked out from the recipes made at it (doc 44, "Its window's action").
## The owner, 2026-11-15, of the crude workbench's `crafting_recipe` line, which named the torch:
## "but it can make more things". The line is gone from every piece:
## - a piece is a workshop when a recipe names it as its `workshop`, and every workshop a recipe
##   names is a piece;
## - its action opens crafting at the first recipe made there, on that recipe's page;
## - its line says who crafts there, from the careers of all those recipes: one career by name, and
##   the crude workbench's five as Workers and four trades, each named in its Crafter row and after
##   its description, which the panel shows on hover;
## - a piece nothing is made at has no such action.
const RECIPE := "base:recipe:"
const FURNITURE := "base:furniture:"
# The piece, its action's words, the recipe crafting opens at and its page, the Crafter row, the line.
const WORKSHOPS := [
	["crude_workbench", "Craft items", "torch", "rudimentary", "Any Worker, Ranger, Carpenter, Stonemason or Blacksmith", "Workers and 4 trades craft here"],
	["carpenter_bench", "Craft items", "pine_plank", "carpenter", "Any Carpenter", "Any Carpenter crafts here"],
	["mason_bench", "Craft items", "stone_stool", "stonemason", "Any Stonemason", "Any Stonemason crafts here"],
	["drying_rack", "Dry fish", "dried_fish", "ranger", "Any Ranger", "Any Ranger crafts here"],
	["basic_smelter", "Smelt copper", "copper_bar", "blacksmith", "Any Blacksmith", "Any Blacksmith crafts here"],
	["anvil_stone", "Hammer tools", "copper_pick", "blacksmith", "Any Blacksmith", "Any Blacksmith crafts here"],
]


func _run() -> void:
	create_timer(100).timeout.connect(func(): push_error("Workshop window test timed out"); quit(1))
	await _setup_crafting_fixture()
	var content := root.get_node("ContentRegistry")
	var defs: Dictionary = furniture.get_defs()
	# The data: no piece names a recipe, and the pieces recipes are made at are these six.
	var naming: Array = defs.keys().filter(func(key: String) -> bool: return defs[key].has("crafting_recipe"))
	_expect(naming.is_empty(), "no piece's file names a recipe: " + str(naming))
	var named := {}
	for recipe: Dictionary in content.recipes.values():
		if not String(recipe.get("workshop", "")).is_empty(): named[String(recipe.workshop)] = true
	var expected: Array = WORKSHOPS.map(func(row: Array) -> String: return FURNITURE + String(row[0]))
	var unknown: Array = named.keys().filter(func(key: String) -> bool: return not defs.has(key))
	_expect(unknown.is_empty() and named.size() == expected.size() and expected.all(func(key: String) -> bool: return named.has(key)),
		"every workshop a recipe names is a piece, and they are the six: %s" % [named.keys()])
	_expect(content.recipes_at(FURNITURE + "crude_workbench").size() == 15 and content.recipes_at(FURNITURE + "log_stool").is_empty()
		and content.recipes_at("").size() == 1, "fifteen recipes are made at the crude workbench, none at a stool, and only the workbench itself by hand")
	# Each workshop's window: its action, where the action opens crafting, and who crafts there.
	for index in WORKSHOPS.size():
		var row: Array = WORKSHOPS[index]
		var key: String = FURNITURE + String(row[0])
		furniture._install(key, defs[key], Vector3i(24, 20, 20 + index * 5), 0, "base:material:pine" if String(defs[key].get("material_group", "")) == "wood" else "")
		var piece = furniture._installed[furniture._next_installed_id - 1]
		var id := "installed:%d" % piece.installed_id
		var window: Dictionary = furniture.get_explorer_data(id)
		_expect(window.actions.any(func(action: Dictionary) -> bool: return action.id == "craft" and action.text == String(row[1])),
			"the %s's window offers %s" % [String(row[0]).replace("_", " "), row[1]])
		_expect(window.rows.has(["Crafter", String(row[4])]) and String(window.get("status", {}).get("text", "")) == String(row[5]),
			"it says who crafts there: %s | %s" % [window.rows.filter(func(entry: Array) -> bool: return entry[0] == "Crafter"), window.get("status", {})])
		_expect(String(content.recipes_at(key)[0].id) == RECIPE + String(row[2]), "the first recipe made there is the %s" % String(row[2]).replace("_", " "))
		# Several careers are named in full after the description, which the panel shows on hover.
		var named_all := String(window.details).ends_with(" Workers, Rangers, Carpenters, Stonemasons and Blacksmiths craft here.")
		_expect(named_all == (index == 0) and String(window.details).begins_with(String(defs[key].description)) and (index == 0 or window.details == String(defs[key].description)),
			"the workbench's description ends with its five careers, and a one-career workshop's is its own: %s" % String(window.details).right(80))
		furniture.perform_explorer_action(id, "craft")
		await _frames(5)
		_expect(manager.is_open("craft") and panel.section_id == String(row[3]) and panel.selected == RECIPE + String(row[2]),
			"its action opens the %s page at the %s: %s, %s" % [row[3], String(row[2]).replace("_", " "), panel.section_id, panel.selected])
		manager.close("craft")
		await _frames(2)
	# The line fits the compact panel's tag on a small screen too (CompactObjectPanel.METRICS[false]:
	# 260 wide less the tag's own edges, at size 15).
	var tag: StyleBox = UITheme.cell_style("tag_fine", 2)
	for row: Array in WORKSHOPS:
		var width: float = UITheme.body_font().get_string_size(String(row[5]), HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		_expect(width <= 260.0 - tag.content_margin_left - tag.content_margin_right, "\"%s\" fits the small panel's tag: %.0f wide" % [row[5], width])
	# A piece nothing is made at offers no crafting, and the action does nothing on it.
	furniture._install(FURNITURE + "log_stool", defs[FURNITURE + "log_stool"], Vector3i(24, 20, 52), 0, "base:material:pine")
	var stool = furniture._installed[furniture._next_installed_id - 1]
	var plain: Dictionary = furniture.get_explorer_data("installed:%d" % stool.installed_id)
	furniture.perform_explorer_action("installed:%d" % stool.installed_id, "craft")
	await _frames(3)
	_expect(not plain.actions.any(func(action: Dictionary) -> bool: return action.id == "craft") and not plain.rows.any(func(entry: Array) -> bool: return entry[0] == "Crafter")
		and not manager.is_open("craft"), "a log stool is no workshop: no Craft items, no Crafter, and nothing opens")
	# A workshop being taken down offers no crafting either.
	var bench = furniture._installed.values().filter(func(piece) -> bool: return piece.furniture_key == BENCH)[0]
	bench.flagged_uninstall = true
	var leaving: Dictionary = furniture.get_explorer_data("installed:%d" % bench.installed_id)
	_expect(not leaving.actions.any(func(action: Dictionary) -> bool: return action.id == "craft"), "a workbench marked for uninstall offers no crafting")
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("WORKSHOP_WINDOW_OK: no piece names a recipe; six workshops by their recipes; each action opens at the first recipe made there; who crafts there, five at the workbench; a stool is no workshop")
	quit(0 if failures.is_empty() else 1)
