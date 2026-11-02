extends RefCounted

## A Ranger's catch log (doc 292, concept C): what they have landed and dried. It lives on the
## dwarf as a Dictionary and saves with them while it holds anything:
##   {"caught": {fish item: catches}, "big": catches, "dried": dried fish,
##    "day": the day of "today", "today": its catches, "best": the best day's catches, "best_day": it}
## Days are whole elapsed_days(). A big fish is one catch worth two fish.
const Inventory = preload("res://scripts/components/ColonyInventory.gd")


## One catch of `item`, big or not, on `day`.
static func record_catch(log: Dictionary, item: String, big: bool, day: int) -> void:
	var caught: Dictionary = log.get_or_add("caught", {})
	caught[item] = int(caught.get(item, 0)) + 1
	if big: log.big = int(log.get("big", 0)) + 1
	if int(log.get("day", -1)) != day:
		log.day = day
		log.today = 0
	log.today = int(log.today) + 1
	if int(log.today) > int(log.get("best", 0)):
		log.best = int(log.today)
		log.best_day = day


## Dried fish a Ranger took off the rack (the recipe's `catch_log`: "dried").
static func add(log: Dictionary, field: String, count: int) -> void:
	log[field] = int(log.get(field, 0)) + count


## What the Profession tab shows in place of the list of rewards: each water's fish with its
## catches, the big fish, the best day and the fish dried, and the next reward with the catches
## still to go ({} at level 5).
static func describe(agent: DwarfAgent) -> Dictionary:
	var log: Dictionary = agent.catch_log
	var caught: Dictionary = log.get("caught", {})
	var fish: Array = []
	var total := 0
	for water: Dictionary in (TaskManager.get_config_section("fishing").get("waters", {}) as Dictionary).values():
		var item := String(water.get("item", ""))
		var count := int(caught.get(item, 0))
		total += count
		fish.append({"item": item, "count": count, "picture": Inventory.thumbnail_path(item), "order": fish.size(),
			"name": String(ContentRegistry.item_def(item).get("display_name", "Fish"))})
	# The Ranger's own catch first, then the waters' order.
	fish.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.count > b.count if a.count != b.count else a.order < b.order)
	var big := int(log.get("big", 0))
	var best := int(log.get("best", 0))
	var dried := int(log.get("dried", 0))
	var day := ""
	if best > 0:
		var date: Dictionary = WorldClock.date_at(float(log.get("best_day", 0)))
		day = "%d fish · day %d of %s%s" % [best, int(date.day), date.season, "" if int(date.year) == 1 else ", year %d" % int(date.year)]
	var facts: Array = [
		["Big fish", "%d · about one catch in %d" % [big, roundi(float(total) / big)] if big > 0 else "None yet"],
		["Best day", day if best > 0 else "None yet"],
		["Dried", "%d dried fish off the rack" % dried if dried > 0 else "None yet"],
	]
	var key := agent.profession
	var level := DwarfAssets.profession_level(key, agent.profession_experience)
	var next := {}
	for reward: Dictionary in DwarfAssets.level_rewards(key):
		if int(reward.level) != level + 1: continue
		var to_go := DwarfAssets.experience_threshold(level + 1, key) - maxi(0, int(agent.profession_experience.get(key, 0)))
		next = {"level": level + 1, "text": "%s · %d catch%s to go" % [reward.text, to_go, "" if to_go == 1 else "es"]}
	return {"fish": fish, "facts": facts, "next": next}
