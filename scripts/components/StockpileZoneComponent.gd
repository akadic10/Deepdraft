class_name StockpileZoneComponent
extends StorageComponent

## Ground storage: one visible item or produce crate per floor cell.
## Compatible crates refill before empty cells are claimed; all counts are
## individual goods, while cell_stacks.size() reports occupied physical cells.
##
## Owned by StockpileDesignationController; StockpileManager registers it
## with TaskManager, injects drop_manager/config, routes task events back.
## Cells are FLOOR block coordinates; zones are flat by designation rule.
## Item identity is the namespaced String key, never a runtime int.

## New storage and older saves accept every existing stockpile category.
## StorageComponent adds exact item choices and per-category exceptions.
const DEFAULT_FILTER_TAGS: Array[String] = [
	"stockpile_stone", "stockpile_ore", "stockpile_gem", "stockpile_soil",
	"stockpile_wood", "stockpile_food", "stockpile_drink", "stockpile_seed",
	"stockpile_misc", "stockpile_currency", "stockpile_furniture",
]

var zone_id: int = -1
var tile_cells: Array[Vector3i] = []          # floor cells, all at floor_y
var floor_y: int = 0                          # the zone's single floor Y
var cell_stacks: Dictionary = {}              # Vector3i -> { "item": String, "count": int }
var _slots = preload("res://scripts/components/StorageStackSlots.gd").new()
var reserved_cells: Dictionary:
	get:
		return _slots.reservations

var _cell_set: Dictionary = {}                # Vector3i -> true (O(1) membership)


func setup(id: int, cells: Array[Vector3i]) -> void:
	zone_id = id
	tile_cells = cells
	_slots.slots = cells
	_slots.entries = cell_stacks
	_slots.capacity_for = _item_capacity
	filter_tags = DEFAULT_FILTER_TAGS.duplicate()
	if not cells.is_empty():
		floor_y = cells[0].y
	for cell: Vector3i in cells:
		_cell_set[cell] = true


# ── Queries ───────────────────────────────────────────────────────────────────

func has_cell(cell: Vector3i) -> bool:
	return _cell_set.has(cell)


func cell_count() -> int:
	return tile_cells.size()


## Total stored goods, including every unit inside crates.
func stored_count() -> int:
	var total: int = 0
	for cell: Vector3i in cell_stacks:
		total += int((cell_stacks[cell] as Dictionary).get("count", 0))
	return total


func has_room_for(item_key: String, _stack_max: int = 1) -> bool:
	return accepts_key(item_key) and _has_room_for_key(item_key)


func _has_room_for_key(key: String) -> bool:
	return _slots.has_room(key)


# ── Storage contract (doc 19 §3.5 — the abstract surface) ─────────────────────

## An empty cell or room in an existing compatible crate.
func _has_any_room() -> bool:
	return _slots.has_any_room()


func _reserve_deposit(item_key: String, near: Vector3i, dwarf_id: int, amount: int = 1) -> Variant:
	if not accepts_key(item_key): return null
	return _slots.reserve(item_key, amount, dwarf_id, near)


func _release_deposit(token: Variant) -> void:
	_slots.release(token)


func _commit_one(token: Variant, item_key: String) -> void:
	_slots.commit(token, item_key)


func _deposit_walk_target(first_token: Variant) -> Vector3i:
	return first_token.slot as Vector3i


func delivery_stand_cells(target: Vector3i, dwarf_id: int = -1) -> Array[Vector3i]:
	var stands := ground_access_cells(target)
	# A bundle may fill several neighbouring cells. None of those deliveries
	# may appear under the worker's boots when the atomic commit spreads them.
	if _pulls.has(dwarf_id):
		for token: Dictionary in _pulls[dwarf_id].cargo.values():
			stands.erase(token.slot)
	return stands


## WYSIWYG: the deposited node stays visible, snapped to its cell.
func _place_visual(node: Node3D, token: Variant) -> void:
	if node != null and is_instance_valid(node) \
			and drop_manager != null and is_instance_valid(drop_manager):
		var existing: Node3D = drop_manager.call("stored_node_at", token.slot)
		if existing != null:
			drop_manager.call("set_quantity", existing, int(cell_stacks[token.slot].count))
			node.queue_free()
		else:
			drop_manager.call("place_stored", node, token.slot)


## Scheduler probe / hauler walk target: the zone floor cell nearest this
## dwarf. Vector3i(-1,..) if the zone is empty.
func nearest_stand_target(dwarf_cell: Vector3i) -> Vector3i:
	var best := Vector3i(-1, -1, -1)
	var best_dist: int = 0x7FFFFFFF
	for cell: Vector3i in tile_cells:
		var d := cell - dwarf_cell
		var dist := absi(d.x) + absi(d.y) + absi(d.z)
		if dist < best_dist:
			best = cell
			best_dist = dist
	return best


# ── Cell-level deposit machinery (doc 18 §2.3 steps 2/4) ──────────────────────

## Withdraw one stored unit of `item_key` (doc 19 §3.3 fetch path): the
## stored node nearest `near` supplies one unit, reserved for the fetching
## dwarf. A partial crate remains stored. Null if the zone holds none.
func withdraw_nearest(item_key: String, near: Vector3i, dwarf_id: int) -> Node3D:
	if drop_manager == null or not is_instance_valid(drop_manager):
		return null
	var best := Vector3i(-1, -1, -1)
	var best_dist: int = 0x7FFFFFFF
	for cell: Vector3i in cell_stacks:
		if int(cell_stacks[cell].count) <= int(_outgoing.get(cell, {}).get("count", 0)): continue
		if drop_manager.instance_promised(String(cell_stacks[cell].get("instance_id", ""))): continue
		if String((cell_stacks[cell] as Dictionary).get("item", "")) != item_key:
			continue
		var d := cell - near
		var dist := absi(d.x) + absi(d.y) + absi(d.z)
		if dist < best_dist:
			best = cell
			best_dist = dist
	if best == Vector3i(-1, -1, -1):
		return null
	return withdraw_stack(best, 1, dwarf_id)


func stored_entries() -> Dictionary:
	return cell_stacks


func storage_capacity() -> int:
	return tile_cells.size()


func slot_cell(slot: Variant) -> Vector3i:
	return slot as Vector3i


func withdraw_stack(slot: Variant, amount: int, dwarf_id: int) -> Node3D:
	var best: Vector3i = slot
	if not cell_stacks.has(best): return null
	var item_key := String(cell_stacks[best].item)
	var node: Node3D = drop_manager.call("stored_node_at", best)
	if node == null:
		return null
	var count := int(cell_stacks[best].count)
	if amount <= 0 or amount > count: return null
	if count > amount:
		var single: Node3D = drop_manager.call("spawn_reserved", item_key, best, dwarf_id)
		if single == null:
			return null
		drop_manager.set_quantity(single, amount)
		cell_stacks[best].count = count - amount
		drop_manager.call("set_quantity", node, count - amount)
		node = single
	else:
		cell_stacks.erase(best)
		drop_manager.call("withdraw_stored", node, dwarf_id)
	if changed_callback.is_valid():
		changed_callback.call(item_key, -amount)
	changed.emit()
	return node
