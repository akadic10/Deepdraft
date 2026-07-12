class_name StockpileZoneComponent
extends StorageComponent

## Ground stockpile zone — the doc 18 data model, re-based onto the shared
## StorageComponent contract (doc 19 Phase 4, the doc 18 §6.5 extraction).
## All haul-loop machinery lives in the base; this class answers the storage
## questions with floor CELLS: deposit tokens are Vector3i cells, one item
## per tile (Alen, 2026-07-06 — Stonehearth parity, quantity is WYSIWYG).
##
## REGRESSION GATE: this re-base must be behaviour-identical to the doc 18
## verified build — the full doc 18 checklist re-runs before Phase 4's
## container work is trusted (doc 19 §4 Phase 4 acceptance).
##
## Owned by StockpileDesignationController; StockpileManager registers it
## with TaskManager, injects drop_manager/config, routes task events back.
## Cells are FLOOR block coordinates; zones are flat by designation rule.
## Item identity is the namespaced String key, never a runtime int.

## v1 default filter: accept every stockpile_* category (doc 18 Phase 1 —
## the filter panel UI is out of scope; the data model carries the tags).
const DEFAULT_FILTER_TAGS: Array[String] = [
	"stockpile_stone", "stockpile_ore", "stockpile_gem", "stockpile_soil",
	"stockpile_wood", "stockpile_food", "stockpile_drink", "stockpile_seed",
	"stockpile_misc", "stockpile_currency", "stockpile_furniture",
]

var zone_id: int = -1
var tile_cells: Array[Vector3i] = []          # floor cells, all at floor_y
var floor_y: int = 0                          # the zone's single floor Y
var cell_stacks: Dictionary = {}              # Vector3i -> { "item": String, "count": int }
var reserved_cells: Dictionary = {}           # Vector3i -> dwarf_id (deposit reservations)

var _cell_set: Dictionary = {}                # Vector3i -> true (O(1) membership)


func setup(id: int, cells: Array[Vector3i]) -> void:
	zone_id = id
	tile_cells = cells
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


## Total stored items. GROUND RULE (Alen, 2026-07-06 — SH parity): one item
## per tile, no stacking; density comes from containers.
func stored_count() -> int:
	var total: int = 0
	for cell: Vector3i in cell_stacks:
		total += int((cell_stacks[cell] as Dictionary).get("count", 0))
	return total


func has_room_for(item_key: String, stack_max: int) -> bool:
	return _find_deposit_cell(item_key, stack_max, Vector3i.ZERO, false) != Vector3i(-1, -1, -1)


# ── Storage contract (doc 19 §3.5 — the abstract surface) ─────────────────────

## Any empty unreserved cell (one item per tile — SH parity).
func _has_any_room() -> bool:
	for cell: Vector3i in tile_cells:
		if not reserved_cells.has(cell) and not cell_stacks.has(cell):
			return true
	return false


func _reserve_deposit(item_key: String, near: Vector3i, dwarf_id: int) -> Variant:
	var cell := reserve_deposit_cell(item_key, 1, near, dwarf_id)
	if cell == Vector3i(-1, -1, -1):
		return null
	return cell


func _release_deposit(token: Variant) -> void:
	release_deposit_cell(token as Vector3i)


func _commit_one(token: Variant, item_key: String) -> void:
	deposit(token as Vector3i, item_key)


func _deposit_walk_target(first_token: Variant) -> Vector3i:
	return first_token as Vector3i


## WYSIWYG: the deposited node stays visible, snapped to its cell.
func _place_visual(node: Node3D, token: Variant) -> void:
	if node != null and is_instance_valid(node) \
			and drop_manager != null and is_instance_valid(drop_manager):
		drop_manager.call("place_stored", node, token as Vector3i)


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

## Picks and reserves a deposit cell. Policy (doc 18 §6 decision 1): nearest
## empty unreserved cell to `near`. Vector3i(-1,-1,-1) if the zone is full.
func reserve_deposit_cell(item_key: String, stack_max: int, near: Vector3i, dwarf_id: int) -> Vector3i:
	var cell := _find_deposit_cell(item_key, stack_max, near, true)
	if cell != Vector3i(-1, -1, -1):
		reserved_cells[cell] = dwarf_id
	return cell


func release_deposit_cell(cell: Vector3i) -> void:
	reserved_cells.erase(cell)


## Commits one unit into a previously reserved cell and frees the reservation.
func deposit(cell: Vector3i, item_key: String) -> void:
	reserved_cells.erase(cell)
	if cell_stacks.has(cell):
		var stack: Dictionary = cell_stacks[cell]
		stack["count"] = int(stack.get("count", 0)) + 1
	else:
		cell_stacks[cell] = { "item": item_key, "count": 1 }


## Withdraw one stored unit of `item_key` (doc 19 §3.3 fetch path): the
## stored node nearest `near` re-enters the loose index reserved by the
## fetching dwarf; the cell empties and aggregates decrement. Null if this
## zone holds none.
func withdraw_nearest(item_key: String, near: Vector3i, dwarf_id: int) -> Node3D:
	if drop_manager == null or not is_instance_valid(drop_manager):
		return null
	var best := Vector3i(-1, -1, -1)
	var best_dist: int = 0x7FFFFFFF
	for cell: Vector3i in cell_stacks:
		if String((cell_stacks[cell] as Dictionary).get("item", "")) != item_key:
			continue
		var d := cell - near
		var dist := absi(d.x) + absi(d.y) + absi(d.z)
		if dist < best_dist:
			best = cell
			best_dist = dist
	if best == Vector3i(-1, -1, -1):
		return null
	var node: Node3D = drop_manager.call("stored_node_at", best)
	if node == null:
		return null
	cell_stacks.erase(best)
	drop_manager.call("withdraw_stored", node, dwarf_id)
	if changed_callback.is_valid():
		changed_callback.call(item_key, -1)
	return node


## One item per tile (SH parity): only EMPTY unreserved cells qualify.
## `_stack_max` is unused on ground zones — kept in the signature for the
## container path of this contract.
func _find_deposit_cell(_item_key: String, _stack_max: int, near: Vector3i, use_distance: bool) -> Vector3i:
	var best := Vector3i(-1, -1, -1)
	var best_dist: int = 0x7FFFFFFF
	for cell: Vector3i in tile_cells:
		if reserved_cells.has(cell) or cell_stacks.has(cell):
			continue
		var dist: int = 0
		if use_distance:
			var d := cell - near
			dist = absi(d.x) + absi(d.z)
		if dist < best_dist:
			best = cell
			best_dist = dist
	return best
