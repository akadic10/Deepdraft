extends RefCounted

## A sealed room's appeal (doc 23 "Room appeal"), worked out when asked and never saved.
## Everything the room holds adds up: each piece by its design and wood (CraftMaterials),
## each pile of loose goods and each storage cell holding goods by appeal.json's amounts.
## A room with more than `full_room_tiles` floor tiles counts that share of its total.
## RoomManager owns the data and answers for rooms.

## The room's parts, largest first ({key, name, value each, count, material}), what they add up to,
## its floor tiles, the share its size counts, the score and its word.
static func score(room: Dictionary, manager: Node) -> Dictionary:
	var config: Dictionary = manager.appeal_config
	var cells: Dictionary = room.get("cells", {})
	var doors: Dictionary = room.get("door_cells", {})   # door origin -> true
	var parts := {}
	var tree := manager.get_tree()
	var furniture := tree.get_first_node_in_group("furniture_controller")
	if furniture != null:
		for piece in furniture.get_installed_pieces():
			if not piece.def.has("appeal"): continue
			var anchors: Array[Vector3i] = furniture.room_cells(piece)
			if anchors.is_empty(): continue
			# A piece is the room's as RoomManager.room_furniture counts it.
			if doors.has(anchors[0]) or anchors.any(func(cell: Vector3i): return cells.has(cell + Vector3i.UP)):
				_add_piece(parts, piece)
	var drops := ItemDropManager.find(tree)
	if drops != null:
		for node: Node3D in drops.loose_items():
			if cells.has(drops.item_floor_cell(node) + Vector3i.UP): _add(parts, "loose", "Loose goods", float(config.loose_pile))
	for zone in StockpileManager.get_zones():
		var stacks: Variant = zone.get("cell_stacks")
		if not stacks is Dictionary: continue
		for cell: Vector3i in stacks:
			if cells.has(cell + Vector3i.UP): _add(parts, "stocked", "Stocked storage", float(config.stocked_cell))
	return _finish(room, parts, manager)


## Every sealed room's appeal in one pass (the Appeal view): room id -> as score() gives it,
## with the nodes it counts for the view's glow: `warm` (the pieces that add) and `cool`
## (loose goods and stocked storage).
static func score_all(manager: Node) -> Dictionary:
	var config: Dictionary = manager.appeal_config
	var rooms: Dictionary = manager.get_rooms()
	var parts := {}
	var warm := {}
	var cool := {}
	var door_rooms := {}   # door origin -> the rooms it seals
	for id: int in rooms:
		parts[id] = {}
		warm[id] = []
		cool[id] = []
		for origin: Vector3i in (rooms[id] as Dictionary).get("door_cells", {}):
			(door_rooms.get_or_add(origin, []) as Array).append(id)
	var tree := manager.get_tree()
	var furniture := tree.get_first_node_in_group("furniture_controller")
	if furniture != null:
		for piece in furniture.get_installed_pieces():
			if not piece.def.has("appeal"): continue
			var anchors: Array[Vector3i] = furniture.room_cells(piece)
			if anchors.is_empty(): continue
			var ids: Array = (door_rooms.get(anchors[0], []) as Array).duplicate()
			if ids.is_empty():
				for cell: Vector3i in anchors:
					var id: int = manager.get_room_id_at(cell + Vector3i.UP)
					if id >= 0:
						ids.append(id)
						break
			for id: int in ids:
				_add_piece(parts[id], piece)
				if piece.node != null: (warm[id] as Array).append(piece.node)
	var drops := ItemDropManager.find(tree)
	var stored := {}   # storage cell -> its goods' node
	if drops != null:
		for node: Node3D in drops.loose_items():
			var id: int = manager.get_room_id_at(drops.item_floor_cell(node) + Vector3i.UP)
			if id < 0: continue
			_add(parts[id], "loose", "Loose goods", float(config.loose_pile))
			(cool[id] as Array).append(node)
		for child: Node in drops.get_children():
			if child is Node3D and bool(child.get_meta("stored", false)): stored[drops.item_floor_cell(child)] = child
	for zone in StockpileManager.get_zones():
		var stacks: Variant = zone.get("cell_stacks")
		if not stacks is Dictionary: continue
		for cell: Vector3i in stacks:
			var id: int = manager.get_room_id_at(cell + Vector3i.UP)
			if id < 0: continue
			_add(parts[id], "stocked", "Stocked storage", float(config.stocked_cell))
			if stored.has(cell): (cool[id] as Array).append(stored[cell])
	var result := {}
	for id: int in rooms:
		result[id] = _finish(rooms[id], parts[id], manager)
		result[id]["warm"] = warm[id]
		result[id]["cool"] = cool[id]
	return result


## An appeal as the game writes it: one decimal at most, and a true minus sign.
static func number(value: float) -> String:
	return ("−" if value <= -0.05 else "") + ("%.1f" % absf(value)).trim_suffix(".0")


## A part's contribution: "+3", "−1".
static func signed(value: float) -> String:
	return ("+" if value > -0.05 else "") + number(value)


static func _finish(room: Dictionary, parts: Dictionary, manager: Node) -> Dictionary:
	var config: Dictionary = manager.appeal_config
	var listed: Array = parts.values()
	listed.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.value) * int(a.count) > float(b.value) * int(b.count))
	var total := 0.0
	for part: Dictionary in listed: total += float(part.value) * int(part.count)
	var tiles := int(room.get("floor_tiles", 0))
	var share := minf(1.0, float(config.full_room_tiles) / maxf(1.0, float(tiles)))
	var appeal := total * share
	return {"parts": listed, "total": total, "tiles": tiles, "share": share, "score": appeal,
		"word": manager.appeal_step(appeal)}


static func _add_piece(parts: Dictionary, piece) -> void:
	_add(parts, String(piece.furniture_key), String(piece.display_name()), float(CraftMaterials.appeal(piece.def, piece.material_id).total),
		String(piece.material_id))


## Parts of the same kind, name and value are counted together ("2 × Applewood log stool");
## a piece's part also names its wood (`material`), for the tastes it may meet.
static func _add(parts: Dictionary, key: String, name: String, value: float, material := "") -> void:
	var id := "%s|%s|%s" % [key, name, value]
	if not parts.has(id): parts[id] = {"key": key, "name": name, "value": value, "count": 0, "material": material}
	parts[id]["count"] = int(parts[id]["count"]) + 1
