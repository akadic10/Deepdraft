extends RefCounted

## Read-only, shared by the overhead indicators and both dwarf inspectors.
## Use actual self-care search outcomes; never launch routes or claim supplies.
static func describe(agent: DwarfAgent) -> Dictionary:
	var config := UIRegistry.get_dwarf_indicators()
	var food = agent.get_food()
	if food != null and food.famished(): return _food_concern(food)
	var rest = agent.get_rest_behavior()
	var recovering: bool = agent.is_sleeping() and rest != null and rest.state in ["settling","sleeping","waking"]
	var unresolved: bool = agent.is_sleeping() and rest != null and rest.elapsed >= float(config.unresolved_rest_seconds)
	if not recovering and (agent.sleep <= float(config.exhausted_threshold) or unresolved):
		if rest != null and agent.is_sleeping():
			if rest.state == "travelling_bed":
				return _issue("rest","Exhausted","Going to bed","A bed is reserved. Rest will recover after sleeping.")
			if rest.state in ["searching","travelling"]:
				return _issue("rest","Exhausted","No available bed found","Provide an accessible bed. This dwarf is finding a place to sleep on the ground.")
		return _issue("rest","Exhausted","Needs sleep","Keep a clear route to a bed or a safe resting spot.")
	if food != null and food.hungry() and food.shortage: return _food_concern(food)
	if agent.get_mood() != null and agent.get_mood().unhappy():
		var thought: Dictionary = agent.get_mood().strongest_negative_thought()
		if not thought.is_empty(): return _issue("mood","Unhappy",thought.reason,thought.help)
	return {}


static func _food_concern(food: RefCounted) -> Dictionary:
	var title := "Famished" if food.famished() else "Hungry"
	if food.state in ["dining","eating"]:
		return _issue("food",title,"Has a meal","Hunger will improve after finishing this meal.")
	if food.state in ["walking","pickup"]:
		return _issue("food",title,"Collecting food","A portion has been found. This dwarf is fetching it.")
	if food.shortage:
		return _issue("food",title,"No reachable food","Harvest berries or make stored food accessible.")
	return _issue("food",title,"Needs a meal","Keep harvested food accessible. This dwarf will look for a portion.")


static func _issue(kind: String, title: String, reason: String, help: String) -> Dictionary:
	return {"kind":kind,"title":title,"reason":reason,"help":help}
