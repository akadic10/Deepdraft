class_name ContainerStorageComponent
extends StorageComponent

const ITEM_LAYOUT = preload("res://scripts/components/StorageItemLayout.gd")

## Container storage (doc 19 §3.5) — the density face of the storage
## contract: capacity SLOTS behind one piece of installed furniture (barrel
## 8, chest 24, shelf 8). A produce crate occupies one slot; ordinary items
## remain individual. The saved inventory still records unit totals by key;
## physical stacks and anchors are rebuilt from these counts on restore.
##
## VISUALS (the WYSIWYG split, doc 19 §3.0.5): render_contents false (barrel,
## chest) ABSORBS the deposited node — the window shows counts; true (shelf)
## renders items on the def's anchor points, fitted to optional slot bounds.
##
## Owned by FurniturePlacementController (attached to the piece's
## InstalledFurnitureComponent); registered with StockpileManager like a
## zone. Withdraw spawns the item back into the world pre-reserved for the
## fetching dwarf (containers hold counts, not nodes).

var capacity: int = 8
var render_contents: bool = false
var inventory: Dictionary = {}       # item_key (String) -> count (int)
var cells: Array[Vector3i] = []      # the installed piece's footprint floor cells
var suspended: bool = false          # 📤 flagged — stop accepting (doc 19 §3.4)

# ── Anchor rendering (doc 19 Phase 5 — SH ATTITEM parity) ─────────────────────
var display_parent: Node3D = null    # the installed piece's visual node
var anchors: Array = []              # local block offsets from data/furniture JSON
var anchor_scale: float = 0.5        # maximum display scale; optional slot bounds may shrink an item
var anchor_max_size := Vector3.ZERO # optional per-slot envelope; zero keeps legacy sizing

var _slots = preload("res://scripts/components/StorageStackSlots.gd").new()
var _reserved_slots: int:
	get:
		return _slots.reservations.size()
var _anchor_slots: Array = []        # per-anchor: null | [node: Node3D, item_key: String]


func setup_container(def: Dictionary, footprint_cells: Array[Vector3i]) -> void:
	var storage: Dictionary = def.get("storage", {})
	capacity = int(storage.get("capacity", 8))
	_slots.slots = range(capacity)
	_slots.capacity_for = _item_capacity
	render_contents = bool(storage.get("render_contents", false))
	anchors = storage.get("anchors", [])
	anchor_scale = float(storage.get("anchor_scale", 0.5))
	var size: Array = storage.get("anchor_max_size", [])
	anchor_max_size = Vector3(float(size[0]), float(size[1]), float(size[2])) if size.size() == 3 else Vector3.ZERO
	cells = footprint_cells
	filter_tags = StockpileZoneComponent.DEFAULT_FILTER_TAGS.duplicate()
	_anchor_slots.resize(anchors.size())


func stored_count() -> int:
	var total: int = 0
	for key: String in inventory:
		total += int(inventory[key])
	return total


func restore_inventory(saved: Dictionary, item_manager: Node, instances: Array = []) -> void:
	inventory.clear()
	_slots.entries.clear()
	_slots.reservations.clear()
	drop_manager = item_manager
	var remaining_counts := saved.duplicate()
	for entry: Dictionary in instances:
		var key := String(entry.item)
		if int(remaining_counts.get(key, 0)) <= 0: continue
		remaining_counts[key] = int(remaining_counts[key]) - 1
		var token = _slots.reserve(key, 1, -1, Vector3i.ZERO)
		if token == null:
			item_manager.restore_loose_item(key, Vector3(cells[0]) + Vector3(.5,1,.5), 0.0, 1, String(entry.instance_id))
			continue
		token["instance_id"] = entry.instance_id
		_commit_one(token, key)
		if render_contents:
			_place_visual(item_manager.create_item_visual(key, 1, String(entry.instance_id)), token)
	for item_key in remaining_counts:
		var remaining := maxi(int(remaining_counts[item_key]), 0)
		while remaining > 0:
			var token: Variant = _slots.reserve(String(item_key), remaining, -1, Vector3i.ZERO)
			if token == null:
				# Preserve excess goods from an older or changed furniture capacity.
				if item_manager != null and not cells.is_empty():
					item_manager.call("spawn_drop", String(item_key), remaining, cells[0] + Vector3i.UP)
				break
			_commit_one(token, String(item_key))
			remaining -= int(token.count)
			if render_contents and item_manager != null:
				var node: Node3D = item_manager.call("create_item_visual", String(item_key), int(token.count))
				if node != null:
					_place_visual(node, token)


func occupied_slots() -> int:
	return _slots.entries.size()


# ── Storage contract (doc 19 §3.5 — the abstract surface) ─────────────────────

func _has_any_room() -> bool:
	if suspended:
		return false
	return _slots.has_any_room()


func _has_room_for_key(key: String) -> bool:
	return not suspended and _slots.has_room(key)


func _reserve_deposit(item_key: String, near: Vector3i, dwarf_id: int, amount: int = 1) -> Variant:
	if suspended or not accepts_key(item_key):
		return null
	return _slots.reserve(item_key, amount, dwarf_id, near)


func _release_deposit(token: Variant) -> void:
	_slots.release(token)


func _commit_one(token: Variant, item_key: String) -> void:
	_slots.commit(token, item_key)
	inventory[item_key] = int(inventory.get(item_key, 0)) + int(token.count)


func _deposit_walk_target(_first_token: Variant) -> Vector3i:
	return nearest_stand_target(Vector3i.ZERO)


func delivery_contact(stand: Vector3i) -> Vector3:
	if cells.is_empty():
		return super.delivery_contact(stand)
	var center := Vector3.ZERO
	for cell in cells:
		center += Vector3(cell.x + .5, cell.y + 1.8, cell.z + .5)
	return center / float(cells.size())


## Barrel/chest ABSORB the node; the shelf snaps it onto a free anchor
## (doc 19 Phase 5, art doc 41: scale up to 0.5, varied yaw, fitted slot bounds).
## Anchors are footprint-local block coords (origin = bottom-front-left);
## as children of the rotated piece node they follow its yaw for free, and
## slice culling rides the parent's visibility.
func _place_visual(node: Node3D, token: Variant) -> void:
	if node == null or not is_instance_valid(node):
		return
	if not render_contents or display_parent == null or not is_instance_valid(display_parent):
		node.queue_free()
		return
	var slot := int(token.slot)
	if slot < 0 or slot >= _anchor_slots.size():
		node.queue_free()   # capacity > anchors would land here — WYSIWYG says never
		return
	if _anchor_slots[slot] != null:
		var existing: Node3D = _anchor_slots[slot][0]
		drop_manager.call("set_quantity", existing, int(_slots.entries[slot].count))
		ITEM_LAYOUT.fit(existing, anchor_max_size, anchor_scale)
		node.queue_free()
		return
	var key := String(node.get_meta("item_key", ""))
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	display_parent.add_child(node)
	var fp_w := 1.0
	var fp_d := 1.0
	var offset: Array = anchors[slot]
	node.position = Vector3(
		float(offset[0]) - fp_w * 0.5,
		float(offset[1]),
		float(offset[2]) - fp_d * 0.5)
	node.scale = Vector3.ONE * anchor_scale
	node.set_meta("storage_anchor_position", node.position)
	node.set_meta("storage_anchor_scale", anchor_scale)
	node.set_meta("storage_anchor_max_size", anchor_max_size)
	# Varied per-anchor yaw (SH's scattered hand-placed look) — deterministic.
	node.rotation = Vector3(0.0, float(slot * 2654435761 % 628) / 100.0, 0.0)
	ITEM_LAYOUT.fit(node, anchor_max_size, anchor_scale)
	node.visible = true
	node.set_meta("stored", true)
	_anchor_slots[slot] = [node, key]


## Nearest walkable cell bordering the footprint (the footprint itself is
## occupied — the InstalledFurnitureComponent pattern).
func nearest_stand_target(dwarf_cell: Vector3i) -> Vector3i:
	var best := Vector3i(-1, -1, -1)
	var best_dist: int = 0x7FFFFFFF
	for cell: Vector3i in cells:
		for offset: Vector3i in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
			var stand := cell + offset
			if not NavGrid.is_walkable(stand):
				continue
			var d := stand - dwarf_cell
			var dist := absi(d.x) + absi(d.y) + absi(d.z)
			if dist < best_dist:
				best = stand
				best_dist = dist
	return best


# ── Withdraw (doc 19 §3.3 fetch path) ─────────────────────────────────────────

## Containers hold counts, not nodes: withdrawing spawns the item back into
## the world at the stand cell, pre-reserved for the fetching dwarf.
func withdraw_nearest(item_key: String, _near: Vector3i, dwarf_id: int) -> Node3D:
	if int(inventory.get(item_key, 0)) <= 0:
		return null
	if drop_manager == null or not is_instance_valid(drop_manager):
		return null
	for slot in _slots.entries:
		if drop_manager.instance_promised(String(_slots.entries[slot].get("instance_id", ""))): continue
		if int(_slots.entries[slot].count) > int(_outgoing.get(slot, {}).get("count", 0)) and String(_slots.entries[slot].item) == item_key:
			return withdraw_stack(slot, 1, dwarf_id)
	return null


func stored_entries() -> Dictionary:
	return _slots.entries


func storage_capacity() -> int:
	return capacity


func slot_cell(_slot: Variant) -> Vector3i:
	return cells[0] if not cells.is_empty() else Vector3i(-1, -1, -1)


func withdrawal_stands(_slot: Variant) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	for cell in cells:
		for stand in ground_access_cells(cell):
			if stand not in cells and stand not in result: result.append(stand)
	return result


func withdrawal_contact(_slot: Variant) -> Vector3:
	return delivery_contact(nearest_stand_target(Vector3i.ZERO))


func withdraw_stack(slot: Variant, amount: int, dwarf_id: int) -> Node3D:
	if suspended or not _slots.entries.has(slot): return null
	var stack: Dictionary = _slots.entries[slot]
	var item_key := String(stack.item)
	if amount <= 0 or amount > int(stack.count): return null
	var stand := nearest_stand_target(Vector3i.ZERO)
	if stand.x < 0:
		return null
	var node: Node3D = drop_manager.call("spawn_reserved", item_key, stand, dwarf_id, String(stack.get("instance_id", "")))
	if node == null:
		return null
	drop_manager.set_quantity(node, amount)
	stack.count = int(stack.count) - amount
	if render_contents and int(slot) < _anchor_slots.size() and _anchor_slots[slot] != null:
		var visual: Node3D = _anchor_slots[slot][0]
		if int(stack.count) > 0:
			drop_manager.call("set_quantity", visual, int(stack.count))
			ITEM_LAYOUT.fit(visual, anchor_max_size, anchor_scale)
		else:
			visual.queue_free()
			_anchor_slots[slot] = null
	if int(stack.count) <= 0:
		_slots.entries.erase(slot)
	inventory[item_key] = int(inventory[item_key]) - amount
	if int(inventory[item_key]) <= 0:
		inventory.erase(item_key)
	if changed_callback.is_valid():
		changed_callback.call(item_key, -amount)
	changed.emit()
	return node


## Uninstall teardown (doc 19 §3.4 step 2): every stored item re-enters the
## world as an ordinary loose drop at the container's cell. Returns the
## dumped total (build-log verification).
func dump_contents(at_cell: Vector3i) -> int:
	if drop_manager == null or not is_instance_valid(drop_manager):
		return 0
	# Shelf: clear the anchored visuals first (counts respawn as drops below).
	for i: int in range(_anchor_slots.size()):
		var entry: Variant = _anchor_slots[i]
		if entry != null:
			var node: Node3D = (entry as Array)[0]
			if node != null and is_instance_valid(node):
				node.queue_free()
			_anchor_slots[i] = null
	var dumped := 0
	for stack: Dictionary in _slots.entries.values():
		if not stack.has("instance_id"): continue
		drop_manager.restore_loose_item(String(stack.item), Vector3(at_cell) + Vector3(.5,1,.5), 0.0, 1, String(stack.instance_id))
		inventory[stack.item] = int(inventory[stack.item]) - 1
		if changed_callback.is_valid(): changed_callback.call(String(stack.item), -1)
		dumped += 1
	for item_key: String in inventory.keys():
		var count := int(inventory[item_key])
		if count > 0:
			drop_manager.call("spawn_drop", item_key, count, Vector3i(at_cell.x, at_cell.y + 1, at_cell.z))
			if changed_callback.is_valid():
				changed_callback.call(item_key, -count)
			dumped += count
	inventory.clear()
	_slots.entries.clear()
	return dumped
