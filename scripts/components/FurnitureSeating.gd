extends RefCounted

## Table slot geometry and chair preview/clearance, using definitions owned by
## FurniturePlacementController. Slots describe separate optional build items.
var controller
var snap: Dictionary = {}
var guides: Array[Node3D] = []
var dirty := true
var aim := Vector3i(-1, -1, -1)

func _init(owner) -> void:
	controller = owner


## Rotate a footprint-local box about its bounding rectangle, with no drift.
static func rotate_box(def: Dictionary, lo: Vector3, hi: Vector3, yaw: int) -> AABB:
	var w := float(def.footprint.width)
	var d := float(def.footprint.depth)
	match posmod(yaw, 4):
		1: return AABB(Vector3(lo.z, lo.y, w-hi.x), Vector3(hi.z-lo.z, hi.y-lo.y, hi.x-lo.x))
		2: return AABB(Vector3(w-hi.x, lo.y, d-hi.z), hi-lo)
		3: return AABB(Vector3(d-hi.z, lo.y, lo.x), Vector3(hi.z-lo.z, hi.y-lo.y, hi.x-lo.x))
	return AABB(lo, hi-lo)


func slots_for(piece) -> Array[Dictionary]:
	return slots_for_layout(piece.def, piece.origin_cell, piece.yaw_steps)


func slots_for_layout(def: Dictionary, origin: Vector3i, table_yaw: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var seating: Dictionary = def.get("seating", {})
	var key := String(seating.get("chair_key", ""))
	var chair: Dictionary = controller._defs.get(key, {})
	if chair.is_empty():
		return result
	for slot: Dictionary in seating.get("slots", []):
		var yaw := int(slot.yaw)
		var size := Vector3(float(chair.footprint.width), 0, float(chair.footprint.depth))
		if yaw % 2 == 1:
			size = Vector3(size.z, 0, size.x)
		var lo := Vector3(float(slot.chair_origin[0]), 0, float(slot.chair_origin[1]))
		var box := rotate_box(def, lo, lo+size, table_yaw)
		result.append({"id": String(slot.id), "key": key,
			"origin": origin + Vector3i(box.position),
			"yaw": posmod(table_yaw+yaw, 4),
			"snap_radius": float(seating.get("snap_radius", 1.5))})
	return result


static func is_chair(def: Dictionary) -> bool:
	return not (def.get("seating_chair", {}) as Dictionary).is_empty()


static func clearance(def: Dictionary, origin: Vector3i, yaw: int) -> AABB:
	var region: Dictionary = def.seating_chair.clearance
	var lo := Vector3(region.min[0], region.min[1], region.min[2])
	var hi := Vector3(region.max[0], region.max[1], region.max[2])
	var box := rotate_box(def, lo, hi, yaw)
	box.position += Vector3(origin + Vector3i.UP)
	return box


static func access_cells(def: Dictionary, origin: Vector3i, yaw: int) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	for offset: Array in def.seating_chair.access_cells:
		var lo := Vector3(offset[0], 0, offset[1])
		var box := rotate_box(def, lo, lo+Vector3(1, 0, 1), yaw)
		result.append(origin+Vector3i(box.position))
	return result


## Preserve seated head room both when placing a chair and when adding furniture
## beside it later. This does not enlarge dwarves' logical navigation footprint.
func placement_reason(def: Dictionary, origin: Vector3i, yaw: int, skip = null) -> String:
	if exceeds_capacity(def, origin, yaw, skip):
		return "seat_capacity"
	var chair := is_chair(def)
	var bounds: AABB = controller._visual_bounds(def, origin, yaw)
	var space := clearance(def, origin, yaw) if chair else AABB()
	var furniture_handles: Array[int] = []
	for piece in controller._installed.values():
		furniture_handles.append_array(piece.occupancy_ids)
	for pieces: Dictionary in [controller._ghosts, controller._installed]:
		for piece in pieces.values():
			if piece == skip:
				continue
			if chair and space.intersects(controller._visual_bounds(piece.def, piece.origin_cell, piece.yaw_steps).grow(-.0001)):
				return "seat_clearance"
			if is_chair(piece.def):
				var other := clearance(piece.def, piece.origin_cell, piece.yaw_steps).grow(-.0001)
				if other.intersects(bounds) or (chair and other.intersects(space)):
					return "seat_clearance"
	if not chair:
		return ""
	for cell: Vector3i in controller._bounds_cells(space):
		if cell.x < 0 or cell.z < 0 or cell.x >= WorldGenerator.WORLD_SIZE_X or cell.z >= WorldGenerator.WORLD_SIZE_Z \
				or cell.y >= WorldData.WORLD_SIZE_Y or controller._block_id(cell.x, cell.y, cell.z) != BlockRegistry.AIR_ID \
				or PlacedEntityRegistry.occupies(cell, furniture_handles):
			return "seat_clearance"
	for cell in access_cells(def, origin, yaw):
		if NavGrid.is_walkable(cell) and not controller._cell_to_ghost.has(cell):
			return ""
	return "seat_access"


## Chair plans reserve a table's capacity immediately. Derive this from furniture
## maps, so cancellation/removal and save restore cannot leave stale reservations.
func _chair_count(slots: Array[Dictionary], skip = null) -> int:
	var count := 0
	for slot in slots:
		var installed = controller._installed.get(int(controller._cell_to_installed.get(slot.origin, -1)))
		var ghost = controller._ghosts.get(int(controller._cell_to_ghost.get(slot.origin, -1)))
		for chair in [installed, ghost]:
			if chair == skip or not matches_slot(chair, slot):
				continue
			# Older saves could contain several previously standalone chair plans.
			# Built chairs win; otherwise the first queued plan may still finish.
			if skip is FurnitureGhostComponent and chair is FurnitureGhostComponent \
					and chair.ghost_id > skip.ghost_id:
				continue
			count += 1
	return count


func exceeds_capacity(def: Dictionary, origin: Vector3i, yaw: int, skip = null) -> bool:
	if is_chair(def):
		for pieces: Dictionary in [controller._installed, controller._ghosts]:
			for table in pieces.values():
				var seating: Dictionary = table.def.get("seating", {})
				if seating.is_empty() or table.origin_cell.y != origin.y:
					continue
				var slots := slots_for(table)
				for slot in slots:
					if slot.key == def.furniture_key and slot.origin == origin and slot.yaw == posmod(yaw, 4):
						if _chair_count(slots, skip) >= int(seating.get("max_chairs", slots.size())):
							return true
	elif def.has("seating"):
		# Placing the table after its chairs must obey the same limit.
		var slots := slots_for_layout(def, origin, yaw)
		return _chair_count(slots) > int(def.seating.get("max_chairs", slots.size()))
	return false


## Associations are derived, so removing a table cannot strand a saved chair ID.
func installed_seats(table_id: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var table = controller._installed.get(table_id)
	if table == null:
		return result
	var limit := int(table.def.get("seating", {}).get("max_chairs", 2147483647))
	for slot in slots_for(table):
		if result.size() >= limit:
			break
		var id := int(controller._cell_to_installed.get(slot.origin, -1))
		var chair = controller._installed.get(id)
		if matches_slot(chair, slot):
			slot["chair_id"] = id
			result.append(slot)
	return result


static func matches_slot(chair, slot: Dictionary) -> bool:
	return chair != null and is_chair(chair.def) and chair.furniture_key == slot.key \
		and chair.origin_cell == slot.origin and chair.yaw_steps == slot.yaw


func clear_guides() -> void:
	for guide in guides:
		guide.visible = false
		guide.queue_free()
	guides.clear()
	snap.clear()


func reset() -> void:
	clear_guides()
	aim = Vector3i(-1, -1, -1)
	dirty = true


func resolve(cell: Vector3i) -> void:
	clear_guides()
	aim = cell
	dirty = false
	var def: Dictionary = controller._defs.get(controller._active_key, {})
	if not is_chair(def):
		return
	var nearby: Array[Dictionary] = []
	var nearest_table = null
	var nearest_distance := INF
	var cursor := Vector3(cell) + Vector3(.5, 0, .5)
	# Pick by nearest seat, so adjacent tables do not steal one another's slots.
	for pieces: Dictionary in [controller._installed, controller._ghosts]:
		for piece in pieces.values():
			if piece.origin_cell.y != cell.y or not controller._piece_visible(piece.def, piece.origin_cell, piece.yaw_steps):
				continue
			for slot in slots_for(piece):
				if slot.key != controller._active_key:
					continue
				var center: Vector3 = controller._world_pos(def, slot.origin, slot.yaw) - Vector3.UP
				var distance := cursor.distance_to(center)
				if distance < nearest_distance and distance <= 4.0:
					nearest_distance = distance
					nearest_table = piece
	if nearest_table == null:
		return
	nearby = slots_for(nearest_table)
	var closest := INF
	for slot in nearby:
		var center: Vector3 = controller._world_pos(def, slot.origin, slot.yaw) - Vector3.UP
		var distance := cursor.distance_to(center)
		if distance <= slot.snap_radius and distance < closest:
			closest = distance
			snap = slot.duplicate()
	for slot in nearby:
		# A real/planned chair already depicts its occupied position.
		var ghost = controller._ghosts.get(int(controller._cell_to_ghost.get(slot.origin, -1)))
		var installed = controller._installed.get(int(controller._cell_to_installed.get(slot.origin, -1)))
		if matches_slot(ghost, slot) or matches_slot(installed, slot):
			continue
		var reason: String = controller._floor_placement_reason(def, slot.origin, slot.yaw)
		if reason == "seat_capacity":
			continue # Full personal tables stop advertising alternative chair guides.
		var material: StandardMaterial3D = controller._make_ghost_material()
		var tint: Color = controller.TINT_VALID if reason.is_empty() else controller.TINT_INVALID
		material.albedo_color = Color(tint.r, tint.g, tint.b, .18)
		var guide: Node3D = controller._instance_model(slot.key, material)
		if guide != null:
			controller.add_child(guide)
			guide.position = controller._world_pos(def, slot.origin, slot.yaw)
			guide.rotation.y = float(slot.yaw)*PI*.5
			# Avoid layering two translucent models at the selected position.
			guide.visible = snap.is_empty() or snap.id != slot.id
			guides.append(guide)
