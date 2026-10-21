extends RefCounted

## Pure save migration. SaveManager supplies the data-owned retirement policy;
## callers validate the save first. Never reinterpret an unknown/modded key.
static func cleaned_copy(snapshot: Dictionary, retired: Dictionary, retired_items: Dictionary = {}) -> Dictionary:
	var result := snapshot.duplicate()
	result.scene = snapshot.scene.duplicate()
	# Terrain and world state are large and untouched. Only copy mutable owners.
	for section in ["furniture", "items", "stockpiles", "dwarves"]:
		result.scene[section] = snapshot.scene[section].duplicate(true)
	apply(result, retired, retired_items)
	return result


static func apply(snapshot: Dictionary, retired: Dictionary, retired_items: Dictionary = {}) -> Dictionary:
	var report := {"installed":0, "ghosts":0, "moves":0, "packed_units":0, "spilled_units":0, "filter_entries":0}
	# Standalone goods share the existing loose/stored/carried cleanup. They must
	# never be treated as installed furniture or interpreted through a prefix.
	var items := retired_items.duplicate()
	for key: String in retired:
		items[key.replace("base:furniture:", "base:resources:furniture:")] = true
	var scene: Dictionary = snapshot.scene
	var furniture: Dictionary = scene.furniture
	scene.items.loose = _keep_items(scene.items.loose, "item_key", items, report)
	for zone: Dictionary in scene.stockpiles.zones:
		zone.stacks = _keep_items(zone.stacks, "item", items, report)
		_clean_filter(zone.get("storage_filter", {}), items, report)
	for dwarf: Dictionary in scene.dwarves.roster:
		dwarf.carried_items = _keep_items(dwarf.carried_items, "item_key", items, report)
	var kept: Array = []
	var removed_ids := {}
	for entry: Dictionary in furniture.installed:
		if retired.has(entry.key):
			removed_ids[int(entry.id)] = true
			report.installed += 1
			_spill_container(entry, scene.items.loose, items, report)
		else:
			_clean_container(entry, items, report)
			kept.append(entry)
	furniture.installed = kept
	var removed_moves := {}
	var records: Dictionary = furniture.moves.records
	for id in records.keys():
		var record: Dictionary = records[id]
		if retired.has(record.key) or removed_ids.has(int(record.installed_id)):
			removed_moves[id] = true
			records.erase(id)
			report.moves += 1
		else:
			_clean_filter(record.get("storage_filter", {}), items, report)
	kept = []
	for entry: Dictionary in furniture.ghosts:
		if retired.has(entry.key) or removed_moves.has(entry.get("move_id", "")):
			report.ghosts += 1
		else:
			kept.append(entry)
	furniture.ghosts = kept
	return report


static func _keep_items(entries: Array, field: String, retired: Dictionary, report: Dictionary) -> Array:
	var kept: Array = []
	for entry: Dictionary in entries:
		if retired.has(entry[field]): report.packed_units += int(entry.count)
		else: kept.append(entry)
	return kept


static func _clean_filter(filter: Dictionary, retired: Dictionary, report: Dictionary) -> void:
	for field in ["items", "excluded_items"]:
		if not filter.has(field): continue
		var kept: Array = []
		for key: String in filter[field]:
			if retired.has(key): report.filter_entries += 1
			else: kept.append(key)
		filter[field] = kept


static func _clean_container(entry: Dictionary, retired: Dictionary, report: Dictionary) -> void:
	var inventory: Dictionary = entry.get("inventory", {})
	# Inventory includes the instance counts; never count or spill them twice.
	if entry.has("instances"):
		var kept: Array = []
		for instance: Dictionary in entry.instances:
			if not retired.has(instance.item): kept.append(instance)
			elif not inventory.has(instance.item): report.packed_units += int(instance.count)
		entry.instances = kept
	for key: String in inventory.keys():
		if retired.has(key):
			report.packed_units += int(inventory[key])
			inventory.erase(key)
	_clean_filter(entry.get("storage_filter", {}), retired, report)


static func _spill_container(entry: Dictionary, loose: Array, retired: Dictionary, report: Dictionary) -> void:
	var remaining: Dictionary = entry.get("inventory", {}).duplicate()
	for instance: Dictionary in entry.get("instances", []):
		var key: String = instance.item
		remaining[key] = maxi(0, int(remaining.get(key, 0)) - int(instance.count))
		_spill(entry.origin, key, int(instance.count), instance, loose, retired, report)
	for key: String in remaining:
		if int(remaining[key]) > 0:
			_spill(entry.origin, key, int(remaining[key]), {}, loose, retired, report)


static func _spill(origin: Array, key: String, count: int, metadata: Dictionary, loose: Array, retired: Dictionary, report: Dictionary) -> void:
	if retired.has(key):
		report.packed_units += count
		return
	var drop := {"item_key":key, "count":count, "disallowed":bool(metadata.get("disallowed", false)),
		"position":[origin[0]+0.5, origin[1]+1.0, origin[2]+0.5], "rotation_y":0.0}
	for field in ["instance_id", "material_id"]:
		if metadata.has(field): drop[field] = metadata[field]
	loose.append(drop)
	report.spilled_units += count
