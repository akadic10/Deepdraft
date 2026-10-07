extends RefCounted

## Read-only presentation of an agent's existing state. No task, reservation or
## inventory mutation belongs here; the inspector is safe even while paused.
const Phase = DwarfAgent.TaskPhase


static func roster_state(agent: DwarfAgent) -> Dictionary:
	var data := describe(agent)
	data.group = "resting" if agent.is_sleeping() else "working" if agent.current_task_id >= 0 or agent._task_phase != Phase.NONE or agent.is_walking() else "idle"
	# Short labels for the overview; the existing inspector retains the exact
	# phase and destination. Classification never changes the underlying task.
	data.summary = data.activity
	match agent._task_phase:
		Phase.HAUL_TO_ITEM, Phase.HAUL_PICKUP, Phase.HAUL_TO_ZONE, Phase.HAUL_DEPOSIT:
			data.summary = "Hauling"
		Phase.FETCH_TO_ITEM, Phase.FETCH_PICKUP, Phase.FETCH_TO_GHOST, Phase.FETCH_WORKING, Phase.FETCH_DEPOSIT:
			data.summary = "Placing furniture"
		Phase.UNINSTALL_MOVING, Phase.UNINSTALL_WORKING:
			data.summary = "Removing furniture"
		Phase.ZONE_MOVING, Phase.ZONE_SWINGING:
			data.summary = "Mining"
		Phase.FELL_FINDING, Phase.FELL_MOVING, Phase.FELL_WORKING:
			data.summary = "Chopping"
	if data.group == "idle": data.summary = "Idle"
	if data.group == "resting": data.summary = "Resting"
	return data


static func describe(agent: DwarfAgent) -> Dictionary:
	var task := TaskManager.get_task(agent.current_task_id)
	var activity := "Ready for work"
	var explanation := "Waiting for an available job."
	var destination := "No destination"
	var phase := agent._task_phase
	if agent.is_sleeping():
		activity = "Sleeping"
		explanation = "Resting here · %.1f game hours remaining" % agent._sleep_hours_left
	elif phase != Phase.NONE:
		match phase:
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
				activity = "Finding a chopping position"
				explanation = "Checking access around the tree."
			Phase.FELL_MOVING:
				activity = "Going to chop"
				explanation = "Walking to the tree."
			Phase.FELL_WORKING:
				activity = "Chopping a tree"
				explanation = "Felling progress stays with the tree."
			_:
				activity = "Going to work" if agent.is_walking() else "Working"
				explanation = "Completing the assigned job."
		destination = _destination(agent, task)
	elif agent.is_walking():
		activity = "Walking"
		explanation = "Moving to the requested position."
		destination = location(agent._move_path.back())
	var items := _cargo(agent)
	var load_used := 0
	for entry: Dictionary in items:
		load_used += int(entry.cost)
	var capacity := int(TaskManager.get_config_section("hauling").get("carry_capacity", 4))
	var source := agent._haul_source()
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
		"kind": "Dwarf", "profession": agent.profession.get_slice(":", 2).capitalize(),
		"activity": activity, "explanation": explanation, "destination": destination,
		"location": location(agent.current_cell()), "rest": clampf(agent.sleep, 0.0, 1.0),
		"sleeping": agent.is_sleeping(), "cargo": items, "load": load_used,
		"capacity": capacity, "traits": ", ".join(trait_names) if not trait_names.is_empty() else "No distinctive traits",
		"trait_details": trait_details,
	}


static func location(cell: Vector3i) -> String:
	return "X %d · Z %d · Level %d" % [cell.x, cell.z, cell.y]


static func _destination(agent: DwarfAgent, task: Task) -> String:
	var phase := agent._task_phase
	if phase in [Phase.HAUL_TO_ITEM, Phase.HAUL_PICKUP, Phase.FETCH_TO_ITEM, Phase.FETCH_PICKUP]:
		var item: Node3D = agent._fetch_item
		if phase in [Phase.HAUL_TO_ITEM, Phase.HAUL_PICKUP] and agent._haul_index < agent._haul_items.size():
			item = agent._haul_items[agent._haul_index]
		if is_instance_valid(item):
			return "%s\n%s" % [_item_name(agent, String(item.get_meta("item_key", ""))), location(agent._item_floor_cell(item))]
	if phase in [Phase.HAUL_TO_ZONE, Phase.HAUL_DEPOSIT]:
		var source := agent._haul_source()
		var label := "Storage"
		if source is StockpileZoneComponent:
			label = "Stockpile %d" % source.zone_id
		elif source is ContainerStorageComponent:
			label = "Storage container"
		return "%s\n%s" % [label, location(agent._haul_deposit)]
	if task != null:
		var source: Object = TaskManager.get_work_source(task.source_id)
		var label := "Work site"
		if is_instance_valid(source) and source.has_method("display_name"):
			label = String(source.call("display_name"))
		elif phase in [Phase.ZONE_MOVING, Phase.ZONE_SWINGING]:
			return "Mining site\n%s" % location(agent._zone_block)
		elif phase in [Phase.FELL_FINDING, Phase.FELL_MOVING, Phase.FELL_WORKING]:
			label = "Marked tree"
		return "%s\n%s" % [label, location(task.target_pos)]
	return "Work site"


static func _item_name(agent: DwarfAgent, key: String) -> String:
	var manager := agent.get_tree().get_first_node_in_group("item_drop_manager")
	if manager != null:
		var definition: Dictionary = manager.call("get_item_def", key)
		return String(definition.get("display_name", key.get_slice(":", key.get_slice_count(":") - 1).capitalize()))
	return key.get_slice(":", key.get_slice_count(":") - 1).capitalize()


static func _cargo(agent: DwarfAgent) -> Array[Dictionary]:
	var grouped: Dictionary = {}
	var manager := agent.get_tree().get_first_node_in_group("item_drop_manager")
	for entry: Array in agent._carried_entries:
		if not is_instance_valid(entry[0]):
			continue
		var key := String(entry[1])
		var definition: Dictionary = manager.call("get_item_def", key) if manager != null else {}
		if not grouped.has(key):
			grouped[key] = {"key": key, "name": _item_name(agent, key), "count": 0, "objects": 0,
				"cost": 0, "crate": int(definition.get("crate_capacity", 1)) > 1}
		var row: Dictionary = grouped[key]
		row.count += int(entry[0].get_meta("quantity", 1))
		row.objects += 1
		row.cost += maxi(1, int(definition.get("carry_cost", 1)))
	var result: Array[Dictionary] = []
	for key: String in grouped:
		result.append(grouped[key])
	return result
