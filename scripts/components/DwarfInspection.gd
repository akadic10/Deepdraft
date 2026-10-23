extends RefCounted

## Read-only presentation of an agent's existing state. No task, reservation or
## inventory mutation belongs here; the inspector is safe even while paused.
const Phase = DwarfAgent.TaskPhase


static func roster_state(agent: DwarfAgent) -> Dictionary:
	var data := describe(agent)
	var leisure: bool = agent.get_idle_behavior() != null and agent.get_idle_behavior().active()
	data.group = "resting" if agent.is_sleeping() else "working" if agent.current_task_id >= 0 or agent.get_task_phase() != Phase.NONE or (agent.is_walking() and not leisure) else "idle"
	# Short labels for the overview; the existing inspector retains the exact
	# phase and destination. Classification never changes the underlying task.
	data.summary = data.activity
	match agent.get_task_phase():
		Phase.HAUL_TO_ITEM, Phase.HAUL_PICKUP, Phase.HAUL_TO_ZONE, Phase.HAUL_DEPOSIT:
			data.summary = "Hauling"
		Phase.FETCH_TO_ITEM, Phase.FETCH_PICKUP, Phase.FETCH_TO_GHOST, Phase.FETCH_WORKING, Phase.FETCH_DEPOSIT:
			data.summary = "Placing furniture"
			var task := TaskManager.get_task(agent.current_task_id)
			if task != null and task.type == Task.Type.CRAFT: data.summary = "Crafting"
		Phase.UNINSTALL_MOVING, Phase.UNINSTALL_WORKING:
			data.summary = "Removing furniture"
		Phase.ZONE_MOVING, Phase.ZONE_SWINGING:
			data.summary = "Mining"
		Phase.FELL_FINDING, Phase.FELL_MOVING, Phase.FELL_WORKING:
			data.summary = "Chopping"
			var task := TaskManager.get_task(agent.current_task_id)
			if task != null and task.type == Task.Type.CLEAR_BOULDER: data.summary = "Clearing stone"
			if task != null and task.type == Task.Type.GATHER_SCREE: data.summary = "Gathering stone"
	if task_is_shrub(agent): data.summary = "Harvesting" if TaskManager.get_task(agent.current_task_id).type == Task.Type.HARVEST_SHRUB else "Clearing shrubs"
	if agent.current_task_id >= 0:
		var plant_task := TaskManager.get_task(agent.current_task_id)
		if plant_task != null and plant_task.type == Task.Type.CLEAR_PLANT: data.summary = "Clearing plants"
	var live_task := TaskManager.get_task(agent.current_task_id)
	if live_task != null and live_task.type == Task.Type.HARVEST_TREE: data.summary = "Harvesting " + _tree_fruit_label(live_task)
	if live_task != null and live_task.type == Task.Type.UPROOT_SHRUB: data.summary = "Uprooting shrub"
	var fetch := agent.fetch_source()
	if fetch != null and fetch.has_method("advance_plant"): data.summary = "Planting cutting" if bool(fetch.def.get("from_cutting", false)) else "Replanting shrub"
	if data.group == "idle" and not leisure: data.summary = "Idle"
	if data.group == "resting": data.summary = "Resting"
	if agent.promotion_pending():
		data.group = "working"
		data.summary = "Collecting profession tool"
	if agent.is_eating():
		data.group = "resting"
		data.summary = "Eating" if agent.get_food().state == "eating" else "Getting food"
	if agent.is_recreating():
		data.group = "resting"
		data.summary = data.activity
	return data


static func describe(agent: DwarfAgent) -> Dictionary:
	var task := TaskManager.get_task(agent.current_task_id)
	var activity := "Ready for work"
	var explanation := "Waiting for an available job."
	var destination := "No destination"
	var phase := agent.get_task_phase()
	var clearing_stone := task != null and task.type == Task.Type.CLEAR_BOULDER
	var gathering_stone := task != null and task.type == Task.Type.GATHER_SCREE
	if agent.is_sleeping():
		var rest: Dictionary = agent.get_rest_behavior().describe()
		activity = rest.activity
		explanation = "%s · %.1f game hours remaining" % [rest.explanation,agent.get_sleep_hours_left()]
		if agent.get_rest_behavior().state in ["travelling","travelling_bed"]: destination = "Resting spot (%d, %d, %d)" % [rest.destination.x,rest.destination.y,rest.destination.z]
	elif phase != Phase.NONE:
		match phase:
			Phase.FETCH_PLANNING:
				activity = "Finding accessible supplies"
				explanation = "Checking the next ingredient and return route."
			Phase.HAUL_TO_ITEM, Phase.FETCH_TO_ITEM:
				activity = "Collecting supplies"
				explanation = "Walking to the next item."
			Phase.HAUL_PICKUP, Phase.FETCH_PICKUP:
				activity = "Picking up supplies"
				explanation = "Lifting the item into their hands."
			Phase.HAUL_TO_ZONE:
				activity = "Delivering supplies"
				explanation = "Carrying goods to storage."
			Phase.HAUL_DEPOSIT:
				activity = "Putting supplies away"
				explanation = "Lowering goods into storage."
			Phase.FETCH_TO_GHOST:
				activity = "Delivering furniture"
				explanation = "Carrying a packed item to its placement."
			Phase.FETCH_WORKING, Phase.FETCH_DEPOSIT:
				activity = "Installing furniture"
				explanation = "Preparing and placing the delivered item."
			Phase.UNINSTALL_MOVING:
				activity = "Going to remove furniture"
				explanation = "Walking to the marked piece."
			Phase.UNINSTALL_WORKING:
				activity = "Packing furniture"
				explanation = "Preparing the piece for storage."
			Phase.ZONE_MOVING:
				activity = "Going to mine"
				explanation = "Walking to the next mining position."
			Phase.ZONE_SWINGING:
				activity = "Mining"
				explanation = "Working the selected block."
			Phase.FELL_FINDING:
				activity = "Finding a stone-clearing position" if clearing_stone else "Finding a chopping position"
				explanation = "Checking access around the boulder." if clearing_stone else "Checking access around the tree."
			Phase.FELL_MOVING:
				activity = "Going to clear stone" if clearing_stone else "Going to chop"
				explanation = "Walking to the boulder." if clearing_stone else "Walking to the tree."
			Phase.FELL_WORKING:
				activity = "Breaking a boulder" if clearing_stone else "Chopping a tree"
				explanation = "Clearing progress stays with the boulder." if clearing_stone else "Felling progress stays with the tree."
			_:
				activity = "Going to work" if agent.is_walking() else "Working"
				explanation = "Completing the assigned job."
		destination = _destination(agent, task)
		if task.type == Task.Type.HARVEST_TREE:
			var fruit_label := _tree_fruit_label(task)
			activity = ("Harvesting " if phase == Phase.FELL_WORKING else "Going to harvest ") + fruit_label
			explanation = "Picking this season's %s; the tree stays standing." % fruit_label
		if gathering_stone:
			activity = "Gathering loose stones" if phase == Phase.FELL_WORKING else "Going to gather stones"
			explanation = "Collecting the clump by hand. Partial work is retained." if phase == Phase.FELL_WORKING else "Walking to an accessible side of the clump."
		if task_is_shrub(agent):
			var harvest := task.type == Task.Type.HARVEST_SHRUB
			activity = ("Harvesting berries" if harvest else "Clearing a shrub") if phase == Phase.FELL_WORKING else ("Going to harvest" if harvest else "Going to clear a shrub")
			explanation = "Picking this season’s crop; the plant remains." if harvest else "Removing the plant with a chance to recover a cutting."
		if task.type == Task.Type.UPROOT_SHRUB:
			var plant_source := TaskManager.get_work_source(task.source_id)
			var label := "flowers" if plant_source != null and plant_source.get("state").get("plant_kind") == "flower" else "a shrub"
			activity = ("Uprooting " if phase == Phase.FELL_WORKING else "Going to uproot ") + label
			explanation = "Lifting the whole plant for storage or replanting. Its seasonal state is preserved."
		var fetch := agent.fetch_source()
		if fetch != null and fetch.has_method("advance_plant"):
			var label := "flowers" if fetch.def.has("plant_variant") else "a shrub"
			activity = ("Replanting " if phase in [Phase.FETCH_WORKING, Phase.FETCH_DEPOSIT] else "Carrying " if phase == Phase.FETCH_TO_GHOST else "Collecting ") + label
			explanation = "Moving the existing mature plant to its reserved location."
			if bool(fetch.def.get("from_cutting", false)):
				activity = "Planting a cutting" if phase in [Phase.FETCH_WORKING, Phase.FETCH_DEPOSIT] else "Carrying a cutting" if phase == Phase.FETCH_TO_GHOST else "Collecting a cutting"
				explanation = "Planting one cutting; the young shrub will grow with the seasons."
		if task.type == Task.Type.CLEAR_PLANT:
			var plant_source := TaskManager.get_work_source(task.source_id)
			var plant_state: Dictionary = plant_source.get("state") if is_instance_valid(plant_source) else {}
			activity = String(plant_state.get("clearing_activity", "Clearing plants")) if phase == Phase.FELL_WORKING else "Going to clear plants"
			explanation = "Removing the clump by hand without a resource yield. Partial work is retained."
	elif agent.is_walking():
		activity = "Walking"
		explanation = "Moving to the requested position."
		destination = location(agent.get_move_path().back())
	var availability := TaskManager.worker_availability(agent)
	if availability.begins_with("Trapped") and task == null and not agent.is_sleeping():
		activity = "Needs accessible footing"
		explanation = "This dwarf cannot start work from here. Restore a safe route or support."
	var items := _cargo(agent)
	if task != null and task.type == Task.Type.CRAFT:
		var craft_source = TaskManager.get_work_source(task.source_id)
		if craft_source != null:
			var material := String(items[0].name) if items.size() == 1 else "crafting materials"
			if phase == Phase.FETCH_TO_GHOST:
				activity = "Carrying " + material
				explanation = "Bringing materials to the crafting position."
			elif phase == Phase.FETCH_DEPOSIT and craft_source.needs_ingredient_delivery():
				activity = "Setting down " + material
				explanation = "Delivering this ingredient before collecting the next one."
			elif phase in [Phase.FETCH_WORKING,Phase.FETCH_DEPOSIT]:
				activity = "Crafting " + String(craft_source.recipe.name).to_lower()
				explanation = "Working with the gathered materials to finish the recipe."
	var ladder_build := agent.fetch_source()
	if task == null and not agent.is_sleeping() and not availability.begins_with("Trapped") and agent.get_idle_behavior() != null and agent.get_idle_behavior().active():
		var leisure: Dictionary = agent.get_idle_behavior().describe()
		activity = leisure.activity
		explanation = leisure.explanation
		destination = location(leisure.destination) if leisure.destination.x >= 0 else "No destination"
	if ladder_build != null and ladder_build.has_method("advance_install"):
		if ladder_build.has_method("commit_staged_build"):
			activity = "Building stone blocks" if phase == Phase.FETCH_WORKING else "Going to build"
			explanation = "Hammering the structure using stone already delivered to its materials crate."
		else:
			activity = "Installing a ladder section" if phase == Phase.FETCH_WORKING else "Carrying a ladder section" if phase == Phase.FETCH_TO_GHOST else "Collecting a ladder section"
	var delivery := agent.haul_source()
	if delivery != null and delivery.has_method("site_supported"):
		activity = "Delivering construction materials" if phase in [Phase.HAUL_TO_ZONE,Phase.HAUL_DEPOSIT] else "Collecting construction materials"
		explanation = "Filling the project's temporary materials crate using the normal carrying limit."
	var ladder_removal := agent.uninstall_source()
	if ladder_removal != null and ladder_removal.has_method("advance_removal"):
		activity = "Dismantling a ladder" if phase == Phase.UNINSTALL_WORKING else "Going to dismantle a ladder"
	if agent.is_climbing():
		activity = "Climbing with supplies" if not agent.get_carried_entries().is_empty() else "Climbing a ladder"
		explanation = "Using the installed rungs to reach another level."
	if agent.is_ladder_exiting():
		activity = "Climbing down to safe ground"
		explanation = "Leaving the ladder before taking another job or resting."
	if agent.promotion_pending():
		activity = "Equipping profession tool" if agent.get_equipment().stage == "pickup" else "Collecting profession tool"
		explanation = "Promotion completes after collecting the reserved starter tool."
		destination = "Finding a reachable starter tool"
		if is_instance_valid(agent.get_equipment().item):
			destination = _item_name(agent, agent.get_equipment().item.get_meta("item_key", "")) + "\n" + location(agent.item_floor_cell(agent.get_equipment().item))
	var load_used := 0
	if agent.is_recreating():
		var game: Dictionary = agent.get_recreation().describe(agent)
		activity = game.activity
		explanation = game.explanation
		destination = location(game.destination)
	var food: Dictionary = agent.get_food().describe()
	if agent.is_eating():
		activity = food.activity
		explanation = food.explanation
		destination = location(food.destination) if food.destination.x >= 0 else "Finding reachable food"
	elif agent.get_food().hungry() and not food.explanation.is_empty():
		explanation += "\n"+String(food.explanation)
	for entry: Dictionary in items:
		load_used += int(entry.cost)
	var capacity := int(TaskManager.get_config_section("hauling").get("carry_capacity", 4))
	var source := agent.haul_source()
	if source is StorageComponent:
		capacity = source.carry_capacity
	var trait_names: Array[String] = []
	var trait_details: Array[Dictionary] = []
	var definitions: Dictionary = DwarfAssets.get_trait_data().get("traits", {})
	for key: String in agent.traits:
		var definition: Dictionary = definitions.get(key, {})
		var name := String(definition.get("display_name", key.get_slice(":", key.get_slice_count(":") - 1).capitalize()))
		trait_names.append(name)
		trait_details.append({"name": name,
			"description": String(definition.get("description", "No description available."))})
	return {
		"presentation": "dwarf", "agent": agent, "title": agent.dwarf_name,
		"kind": "Dwarf", "profession": String(DwarfAssets.profession_definition(agent.profession).get("display_name", "Worker")) + (" · Lv %d" % DwarfAssets.profession_level(agent.profession, agent.profession_experience) if agent.profession == "base:profession:miner" else ""),
		"activity": activity, "explanation": explanation, "destination": destination,
		"equipment": equipment_description(agent),
		"equipment_details": equipment_details(agent),
		"location": location(agent.current_cell()), "rest": clampf(agent.sleep, 0.0, 1.0),
		"food": food,
		"concern": preload("DwarfConcern.gd").describe(agent),
		"sleeping": agent.is_sleeping(), "cargo": items, "load": load_used,
		"capacity": capacity, "traits": ", ".join(trait_names) if not trait_names.is_empty() else "No distinctive traits",
		"trait_details": trait_details,
	}


static func location(cell: Vector3i) -> String:
	return "X %d · Z %d · Level %d" % [cell.x, cell.z, cell.y]


static func equipment_description(agent: DwarfAgent) -> String:
	var key: String = agent.get_equipment().tool_key() if agent.get_equipment() != null else ""
	if not key.is_empty(): return CraftMaterials.product_name(_item_name(agent, key), CraftMaterials.of_item(agent.get_equipment().equipped)) + "\nStarter tool · No work-speed bonus"
	return "Default pickaxe · No crafted upgrade" if agent.profession == "base:profession:miner" else "Default work tools"


static func equipment_details(agent: DwarfAgent) -> Dictionary:
	var preview: Dictionary = DwarfAssets.profession_definition(agent.profession).get("equipment_preview", {})
	var key: String = agent.get_equipment().tool_key() if agent.get_equipment() != null else ""
	var manager := ItemDropManager.find(agent.get_tree())
	var definition: Dictionary = manager.get_item_def(key) if manager != null and not key.is_empty() else {}
	var details: Dictionary = definition.get("equipment", {})
	var material_id := CraftMaterials.of_item(agent.get_equipment().equipped) if agent.get_equipment() != null else ""
	return {
		"name": CraftMaterials.product_name(_item_name(agent, key), material_id) if not key.is_empty() else String(preview.get("default_name", "Basic work tools")),
		"tier": String(details.get("tier", "Standard")),
		"materials": String(details.get("materials", "Included work tools")) + (" · " + CraftMaterials.material_name(material_id) if not material_id.is_empty() else ""),
		"benefit": String(details.get("benefit", preview.get("default_description", "No crafted tool equipped."))),
		"icon": "res://assets/ui/items/%s.png" % key.replace(":", "_") if not key.is_empty() else "res://assets/ui/icons/%s.svg" % preview.get("icon", "colony"),
		"upgrade_name": String(preview.get("upgrade_name", "Future tool upgrades")),
		"upgrade_status": String(preview.get("upgrade_status", "Choose a profession")),
		"upgrade_description": String(preview.get("upgrade_description", "Upgrade details will appear with this profession's gameplay.")),
		"upgrade_method": String(preview.get("upgrade_method", "")),
		"pending": agent.get_equipment().message if agent.promotion_pending() else ""
	}


static func _destination(agent: DwarfAgent, task: Task) -> String:
	var phase := agent.get_task_phase()
	if phase in [Phase.HAUL_TO_ITEM, Phase.HAUL_PICKUP, Phase.FETCH_TO_ITEM, Phase.FETCH_PICKUP]:
		var item: Node3D = agent.target_item()
		if is_instance_valid(item):
			return "%s\n%s" % [_item_name(agent, String(item.get_meta("item_key", ""))), location(agent.item_floor_cell(item))]
	if phase in [Phase.HAUL_TO_ZONE, Phase.HAUL_DEPOSIT]:
		var source := agent.haul_source()
		var label := "Storage"
		if source is StockpileZoneComponent:
			label = "Stockpile %d" % source.zone_id
		return "%s\n%s" % [label, location(agent.get_haul_deposit())]
	if task != null:
		var source: Object = TaskManager.get_work_source(task.source_id)
		if task.type == Task.Type.CRAFT and is_instance_valid(source):
			# Craft leases use a placeholder target; the order owns the live
			# pickup-selected ground spot or the claimed workshop's stand cell.
			return "%s\n%s" % [String(source.call("display_name")), location(source.get("work_cell"))]
		var label := "Work site"
		if is_instance_valid(source) and source.has_method("display_name"):
			label = String(source.call("display_name"))
		elif phase in [Phase.ZONE_MOVING, Phase.ZONE_SWINGING]:
			return "Mining site\n%s" % location(agent.get_zone_block())
		elif phase in [Phase.FELL_FINDING, Phase.FELL_MOVING, Phase.FELL_WORKING]:
			label = "Marked boulder" if task.type == Task.Type.CLEAR_BOULDER else "Marked tree"
			if task.type == Task.Type.GATHER_SCREE: label = "Loose stones"
			if task.type in Task.SHRUB_WORK: label = "Wild shrub"
			if task.type in [Task.Type.CLEAR_PLANT, Task.Type.UPROOT_SHRUB] and is_instance_valid(source): label = String(source.get("state").get("display_name", "Wild plants"))
		return "%s\n%s" % [label, location(task.target_pos)]
	return "Work site"


static func _item_name(agent: DwarfAgent, key: String) -> String:
	var manager := ItemDropManager.find(agent.get_tree())
	if manager != null:
		var definition: Dictionary = manager.get_item_def(key)
		return String(definition.get("display_name", key.get_slice(":", key.get_slice_count(":") - 1).capitalize()))
	return key.get_slice(":", key.get_slice_count(":") - 1).capitalize()


static func _cargo(agent: DwarfAgent) -> Array[Dictionary]:
	var grouped: Dictionary = {}
	var manager := ItemDropManager.find(agent.get_tree())
	for entry: Array in agent.get_carried_entries():
		if not is_instance_valid(entry[0]):
			continue
		var key := String(entry[1])
		var material_id := CraftMaterials.of_item(entry[0])
		var group_key := key + "|" + material_id
		var definition: Dictionary = manager.get_item_def(key) if manager != null else {}
		if not grouped.has(group_key):
			grouped[group_key] = {"key": key, "name": CraftMaterials.product_name(_item_name(agent, key), material_id), "count": 0, "objects": 0,
				"cost": 0, "crate": int(definition.get("crate_capacity", 1)) > 1}
		var row: Dictionary = grouped[group_key]
		row.count += int(entry[0].get_meta("quantity", 1))
		row.objects += 1
		row.cost += maxi(1, int(definition.get("carry_cost", 1)))
	var result: Array[Dictionary] = []
	for key: String in grouped:
		result.append(grouped[key])
	return result


static func task_is_shrub(agent: DwarfAgent) -> bool:
	var task := TaskManager.get_task(agent.current_task_id)
	return task != null and task.type in Task.SHRUB_WORK


static func _tree_fruit_label(task: Task) -> String:
	var source := TaskManager.get_work_source(task.source_id)
	return String(source.fruit_label) if source != null else "fruit"
