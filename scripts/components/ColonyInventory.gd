extends RefCounted

## A derived read model, never a second inventory owner. Physical totals do
## not include installed furniture or unfulfilled requests for nonexistent goods.
static func snapshot(items: ItemDropManager, furniture: FurniturePlacementController) -> Dictionary:
	var result := {}
	if not is_instance_valid(items): return result
	var stored := StockpileManager.get_inventory_totals()
	var outgoing := StockpileManager.get_outgoing_totals()
	var physical := items.get_inventory_items()
	for key: String in stored:
		if int(stored[key]) > 0: _row(result, key).stored = int(stored[key])
	for entry: Dictionary in physical.loose:
		var row := _row(result, entry.key)
		row.loose += int(entry.count)
		if not entry.reserved: row.available += int(entry.count)
	for entry: Dictionary in physical.carried:
		_row(result, entry.key).carried += int(entry.count)
	var catalog := furniture.get_catalog_stock() if is_instance_valid(furniture) else {}
	var furniture_by_item := {}
	if is_instance_valid(furniture):
		for key: String in furniture.get_defs():
			furniture_by_item[String(furniture.get_defs()[key].item_key)] = key
	for key: String in result:
		var row: Dictionary = result[key]
		row.total = row.stored + row.loose + row.carried
		row.available += maxi(0, row.stored - int(outgoing.get(key, 0)))
		row.furniture_key = String(furniture_by_item.get(key, ""))
		if catalog.has(row.furniture_key):
			row.available = mini(row.total, int(catalog[row.furniture_key].available))
			row.requests = int(catalog[row.furniture_key].reserved)
		row.reserved = row.total - row.available
	return result


static func _row(rows: Dictionary, key: String) -> Dictionary:
	if not rows.has(key):
		rows[key] = {"stored": 0, "loose": 0, "carried": 0, "total": 0,
			"reserved": 0, "available": 0, "requests": 0, "furniture_key": ""}
	return rows[key]


static func thumbnail_path(key: String) -> String:
	return "res://assets/ui/items/%s.png" % key.replace(":", "_")
