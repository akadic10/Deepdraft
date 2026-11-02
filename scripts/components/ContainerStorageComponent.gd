extends StorageComponent

## A furniture container (doc 294): storage slots behind one installed piece, the tool rack
## first. Its furniture JSON `storage` block says:
## - `accepts`: the material tags of the goods it may hold (the tool rack: `tool`). Its filter
##   lists only those goods; the player may narrow it to one;
## - `capacity`: its slots (the rack's three hooks), `slot_word` for the window ("hooks");
## - `per_slot`: the goods a slot holds (the crate's quarters 3, step 4); 1 when absent. A slot
##   shows one of its goods, and its window counts goods ("Used 9 / 12");
## - `priority`: where it starts in line (4, ahead of ground storage at 5);
## - `anchors`: where each slot's goods show, in footprint-local blocks from the back-left floor
##   corner. With `hang`, goods hang upright from their tops (tools on hooks); else they sit.
## FurnitureStorage creates it on install and registers it with StockpileManager beside the
## zones. Goods leave it reserved on the floor in front of it, at the stand nearest the slot.

const HANG := Basis(Vector3.UP, PI) * Basis(Vector3.RIGHT, -PI * .5)   # old z up, old y out

var capacity := 1
var per_slot := 1                      # goods to a slot
var accepts_tags: Array[String] = []
var slot_word := "places"
var anchors: Array = []
var hang := false
var cells: Array[Vector3i] = []        # the piece's footprint floor cells
var footprint := Vector2(1, 1)         # its width and depth in blocks, for the anchors
var display_parent: Node3D = null      # the piece's node: shown goods are its children
var suspended := false                 # marked for uninstall: it takes nothing more
var window_opener := Callable()        # opens its storage window (FurnitureStorage), for Locate
var _slots = preload("res://scripts/components/StorageStackSlots.gd").new()
var _shown: Dictionary = {}            # slot -> the goods' node shown on the piece


func setup_container(def: Dictionary, footprint_cells: Array[Vector3i], node: Node3D) -> void:
	var storage: Dictionary = def.get("storage", {})
	capacity = int(storage.get("capacity", 1))
	per_slot = maxi(1, int(storage.get("per_slot", 1)))
	accepts_tags.assign(storage.get("accepts", []))
	slot_word = String(storage.get("slot_word", "places"))
	anchors = storage.get("anchors", [])
	hang = bool(storage.get("hang", false))
	priority = clampi(int(storage.get("priority", LAST_PRIORITY - 1)), FIRST_PRIORITY, LAST_PRIORITY)
	footprint = Vector2(float(def.footprint.width), float(def.footprint.depth))
	_slots.slots = range(capacity)
	_slots.capacity_for = _slot_capacity
	cells = footprint_cells
	display_parent = node
	filter_tags = accepts_tags.duplicate()


# ── Its kind of goods ─────────────────────────────────────────────────────────

## Whether `key` is of this container's kind, whatever the player's filter.
func holds_kind(key: String) -> bool:
	if not is_instance_valid(drop_manager): return false
	var tags: Array = drop_manager.get_item_def(key).get("material_tags", [])
	return accepts_tags.any(func(tag: String): return tag in tags)


## Every good of its kind, by name: what its window's filter lists.
func allowed_keys() -> Array[String]:
	var keys: Array[String] = []
	if not is_instance_valid(drop_manager): return keys
	for key: String in drop_manager.get_item_defs():
		if holds_kind(key): keys.append(key)
	keys.sort_custom(func(a: String, b: String): return String(drop_manager.get_item_def(a).get("display_name", a)) < String(drop_manager.get_item_def(b).get("display_name", b)))
	return keys


## The one good it keeps when the player has narrowed it to one, else "".
func chosen_key() -> String:
	var allowed := allowed_keys().filter(accepts_key)
	return String(allowed[0]) if allowed.size() == 1 and allowed_keys().size() > 1 else ""


func accepts_key(key: String) -> bool:
	return holds_kind(key) and super.accepts_key(key)


func set_all_accepted(allowed: bool) -> void:
	filter_tags.assign(accepts_tags if allowed else [])
	filter_items.clear()
	excluded_items.clear()
	_filters_changed()


func stored_count() -> int:
	var total := 0
	for held: Dictionary in _slots.entries.values(): total += int(held.count)
	return total


## A slot holds `per_slot` goods, or one crate of produce.
func _slot_capacity(key: String) -> int:
	return maxi(per_slot, _item_capacity(key))


## How many of a slot's goods its one shown model counts: one good, or a crate's quantity.
func _shown_quantity(slot: Variant) -> int:
	var held: Dictionary = _slots.entries[slot]
	return mini(int(held.count), _item_capacity(String(held.item)))


func storage_used() -> int:
	return stored_count()


## "2 / 3 hooks", "9 / 12 goods": what it holds of what it can (its window, its details).
func usage_text() -> String:
	return "%d / %d %s" % [stored_count(), storage_capacity(), slot_word if per_slot == 1 else "goods"]


## The window's capacity bar: "One good to each of its hooks.", "3 goods to each of its quarters."
func capacity_hint() -> String:
	return "%s to each of its %s." % ["One good" if per_slot == 1 else "%d goods" % per_slot, slot_word]


# ── The storage contract ──────────────────────────────────────────────────────

func has_any_room() -> bool:
	return not suspended and _slots.has_any_room()


func _has_room_for_key(key: String) -> bool:
	return not suspended and _slots.has_room(key)


func _reserve_deposit(item_key: String, near: Vector3i, dwarf_id: int, amount: int = 1, material_id: String = "", _spoil: float = -1.0) -> Variant:
	if suspended or not accepts_key(item_key): return null
	return _slots.reserve(item_key, amount, dwarf_id, near, false, material_id)


func _release_deposit(token: Variant) -> void:
	_slots.release(token)


func _commit_one(token: Variant, item_key: String) -> void:
	_slots.commit(token, item_key)


## The haul's reference cell: the stand nearest the slot its first good goes to.
func _deposit_walk_target(first_token: Variant) -> Vector3i:
	if first_token is Dictionary and first_token.has("slot"): return withdrawal_item_cell(first_token.slot)
	return nearest_stand_target(slot_cell_fallback())


func stored_entries() -> Dictionary:
	return _slots.entries


func storage_capacity() -> int:
	return capacity * per_slot


## The footprint cell under a slot's anchor (its stand and distances start there).
func slot_cell(slot: Variant) -> Vector3i:
	if cells.is_empty(): return Vector3i(-1, -1, -1)
	var at := anchor_position(int(slot))
	var best: Vector3i = cells[0]
	var nearest := INF
	for cell: Vector3i in cells:
		var distance := Vector2(cell.x + .5, cell.z + .5).distance_to(Vector2(at.x, at.z))
		if distance < nearest:
			nearest = distance
			best = cell
	return best


## A slot's anchor in the world: where its goods hang or sit.
func anchor_position(slot: int) -> Vector3:
	if not is_instance_valid(display_parent) or slot < 0 or slot >= anchors.size(): return Vector3(slot_cell_fallback()) + Vector3(.5, 1, .5)
	var offset: Array = anchors[slot]
	return display_parent.to_global(Vector3(float(offset[0]) - footprint.x * .5, float(offset[1]), float(offset[2]) - footprint.y * .5))


func slot_cell_fallback() -> Vector3i:
	return cells[0] if not cells.is_empty() else Vector3i.ZERO


## Walkable floor bordering the footprint: where a dwarf stands to reach it.
func stand_cells() -> Array[Vector3i]:
	var stands: Array[Vector3i] = []
	for cell: Vector3i in cells:
		for offset: Vector3i in [Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK]:
			var stand := cell + offset
			if stand in cells or stand in stands: continue
			if NavGrid.is_walkable(stand): stands.append(stand)
	return stands


func nearest_stand_target(dwarf_cell: Vector3i) -> Vector3i:
	var best := Vector3i(-1, -1, -1)
	var best_distance := 0x7FFFFFFF
	for stand: Vector3i in stand_cells():
		var delta := stand - dwarf_cell
		var distance := absi(delta.x) + absi(delta.y) + absi(delta.z)
		if distance < best_distance:
			best = stand
			best_distance = distance
	return best


func delivery_stand_cells(_target: Vector3i, _dwarf_id: int = -1) -> Array[Vector3i]:
	return stand_cells()


## The hands reach for the anchor nearest the stand: a hook, or a place in the crate.
func delivery_contact(stand: Vector3i) -> Vector3:
	var best := Vector3(stand) + Vector3(.5, 1, .5)
	var nearest := INF
	for slot in range(mini(capacity, anchors.size())):
		var at := anchor_position(slot)
		var distance := Vector2(at.x, at.z).distance_to(Vector2(stand.x + .5, stand.z + .5))
		if distance < nearest:
			nearest = distance
			best = at
	return best


## Where a withdrawn good is set down for its dwarf: the stand nearest its slot.
func withdrawal_item_cell(slot: Variant) -> Vector3i:
	return nearest_stand_target(slot_cell(slot))


func withdrawal_stands(slot: Variant) -> Array[Vector3i]:
	var stand := withdrawal_item_cell(slot)
	return [] as Array[Vector3i] if stand.x < 0 else ground_access_cells(stand)


func withdrawal_contact(slot: Variant) -> Vector3:
	return anchor_position(int(slot))


## A good leaves its slot reserved for its dwarf, set down at the stand in front of it.
func withdraw_stack(slot: Variant, amount: int, dwarf_id: int) -> Node3D:
	if not slot_allowed(slot): return null
	var stack: Dictionary = _slots.entries[slot]
	var key := String(stack.item)
	# One good leaves at a time, or one crate of produce: a quarter of 3 stones gives 1 stone.
	if amount <= 0 or amount > int(stack.count) or amount > _item_capacity(key) or not is_instance_valid(drop_manager): return null
	var stand := withdrawal_item_cell(slot)
	if stand.x < 0: return null
	var node: Node3D = drop_manager.spawn_reserved(key, stand, dwarf_id, String(stack.get("instance_id", "")), String(stack.get("material_id", "")))
	if node == null: return null
	drop_manager.set_quantity(node, amount)
	stack.count = int(stack.count) - amount
	if int(stack.count) <= 0:
		_slots.entries.erase(slot)
		_clear_shown(slot)
	elif _shown.has(slot):
		drop_manager.set_quantity(_shown[slot], _shown_quantity(slot))
	if changed_callback.is_valid(): changed_callback.call(key, -amount)
	changed.emit()
	return node


# ── What it shows ─────────────────────────────────────────────────────────────

## A delivered good joins its slot on the piece: hung from its top on a hook, or set on its place.
func _place_visual(node: Node3D, token: Variant) -> void:
	if node == null or not is_instance_valid(node): return
	var slot := int(token.slot)
	if not is_instance_valid(display_parent) or slot < 0 or slot >= anchors.size():
		node.queue_free()
		return
	if _shown.has(slot) and is_instance_valid(_shown[slot]):
		drop_manager.set_quantity(_shown[slot], _shown_quantity(slot))
		node.queue_free()
		return
	if node.get_parent() != null: node.get_parent().remove_child(node)
	display_parent.add_child(node)
	var offset: Array = anchors[slot]
	var at := Vector3(float(offset[0]) - footprint.x * .5, float(offset[1]), float(offset[2]) - footprint.y * .5)
	if hang:
		# Turned upright, its top at the hook and its back against the wall side.
		var box := _bounds(node)
		node.transform = Transform3D(HANG, at + Vector3((box.position.x + box.end.x) * .5, -box.end.z, -box.position.y))
	else:
		node.transform = Transform3D(Basis(Vector3.UP, float(slot % 2) * PI * .5), at)
	node.visible = true
	node.set_meta("stored", true)
	node.set_meta("disallowed", false)
	_shown[slot] = node


func _clear_shown(slot: Variant) -> void:
	var node: Variant = _shown.get(slot)
	if node != null and is_instance_valid(node): (node as Node3D).queue_free()
	_shown.erase(slot)


## The node's own box, from its meshes at rest.
static func _bounds(node: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		var transform := Transform3D.IDENTITY
		var parent: Node = mesh
		while parent != node and parent is Node3D:
			transform = (parent as Node3D).transform * transform
			parent = parent.get_parent()
		var box: AABB = transform * mesh.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result


# ── Uninstall, saves ──────────────────────────────────────────────────────────

## Its goods drop loose in front of it, each slot's at the stand nearest it, for haulers to put
## away (uninstall, its wall mined).
func dump_contents() -> int:
	var dumped := 0
	for slot in _slots.entries.keys():
		var stack: Dictionary = _slots.entries[slot]
		var at := withdrawal_item_cell(slot)
		if at.x < 0: at = slot_cell_fallback()
		if is_instance_valid(drop_manager):
			drop_manager.restore_loose_item(String(stack.item), Vector3(at) + Vector3(.5, 1, .5), 0.0, int(stack.count),
				String(stack.get("instance_id", "")), false, String(stack.get("material_id", "")))
		if changed_callback.is_valid(): changed_callback.call(String(stack.item), -int(stack.count))
		dumped += int(stack.count)
		_clear_shown(slot)
	_slots.entries.clear()
	return dumped


func serialize() -> Dictionary:
	var stacks: Array = []
	var slots: Array = _slots.entries.keys()
	slots.sort()
	for slot in slots:
		var stack: Dictionary = _slots.entries[slot]
		var entry := {"slot": int(slot), "item": String(stack.item), "count": int(stack.count), "material_id": String(stack.get("material_id", ""))}
		if stack.has("instance_id"): entry["instance_id"] = String(stack.instance_id)
		stacks.append(entry)
	return {"stacks": stacks, "storage_filter": serialize_filter(), "priority": priority}


## Goods that no longer fit (a smaller capacity, a slot taken twice) drop loose in front of it.
func restore(saved: Dictionary) -> void:
	if saved.has("storage_filter"): restore_filter(saved.storage_filter)
	priority = clampi(int(saved.get("priority", priority)), FIRST_PRIORITY, LAST_PRIORITY)
	for entry: Dictionary in saved.get("stacks", []):
		var slot := int(entry.get("slot", -1))
		var key := String(entry.get("item", ""))
		var count := maxi(0, int(entry.get("count", 0)))
		var material_id := String(entry.get("material_id", ""))
		if key.is_empty() or count <= 0: continue
		var kept := 0
		if slot >= 0 and slot < capacity and not _slots.entries.has(slot): kept = mini(count, _slot_capacity(key))
		if kept > 0:
			_slots.entries[slot] = {"item": key, "count": kept, "material_id": material_id, "disallowed": false}
			if entry.has("instance_id"): _slots.entries[slot]["instance_id"] = String(entry.instance_id)
			_place_visual(drop_manager.create_item_visual(key, _shown_quantity(slot), String(entry.get("instance_id", "")), material_id), {"slot": slot})
		if count > kept and is_instance_valid(drop_manager):
			var at := nearest_stand_target(slot_cell_fallback())
			drop_manager.restore_loose_item(key, Vector3(at if at.x >= 0 else slot_cell_fallback()) + Vector3(.5, 1, .5), 0.0, count - kept, "", false, material_id)
