class_name StockpileZoneComponent
extends RefCounted

## Ground stockpile zone — the data model behind one painted storage region
## (doc 18 §2.2, Phase 1 scope). Owned by StockpileDesignationController's
## zone bookkeeping, the same ownership shape as MiningZoneComponent.
##
## STORAGE CONTRACT (doc 18 §2.5 adoption): this class's public surface —
## accepts / reserve_deposit_cell / deposit / release_deposit_cell — is the
## interface future storage CONTAINERS (barrel, chest, shelf) will implement.
## Keep it clean; it gets extracted as the shared contract when the first
## container ships. Stonehearth-verified: their ground stockpile is just one
## face of a unified storage component.
##
## Phase 3 made this a WORK SOURCE (the MiningZoneComponent pattern): the
## zone posts at most `max_haulers` HAUL leases; a dwarf holding one pulls
## one item at a time (reserve item + deposit cell → walk → pick up → walk →
## deposit → next). StockpileManager registers the zone with TaskManager,
## injects `drop_manager` / config, and routes task events back here.
##
## Cells are FLOOR block coordinates (the solid block dwarves stand on and
## items rest on top of). All cells in a zone share one Y — zones are flat
## by designation rule. Item identity is the namespaced String key, never a
## runtime int (Hard Rule 3).

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
var filter_tags: Array[String] = []
var cell_stacks: Dictionary = {}              # Vector3i -> { "item": String, "count": int }
var reserved_cells: Dictionary = {}           # Vector3i -> dwarf_id (deposit reservations)

# ── Work-source state (doc 18 Phase 3 — injected by StockpileManager) ─────────
var source_id: int = -1                       # TaskManager work-source key (offset range)
var max_haulers: int = 2
var carry_speed_mult_heavy: float = 0.7
var pouch_capacity: int = 4                   # light items per trip (SH backpack = 4)
var pouch_bundle_radius: int = 8              # extras within this radius of the MAIN item
var drop_manager: Node3D = null               # ItemDropManager (guard is_instance_valid)
var changed_callback: Callable = Callable()   # (item_key, delta) -> StockpileManager signal

var _cell_set: Dictionary = {}                # Vector3i -> true (O(1) membership)
var _lease_ids: Dictionary = {}               # task_id -> true (live HAUL leases)
var _pulls: Dictionary = {}                   # dwarf_id -> { "item": Node3D, "key": String, "deposit": Vector3i }


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


## Total stored items across all cells. GROUND RULE (Alen, 2026-07-06 —
## Stonehearth parity): one item per tile, no stacking. Quantity is WYSIWYG;
## density comes later from containers (barrel/chest/shelf), which will
## override per-cell capacity via the storage contract. resources.json
## stack_max is reserved for that container path — ground zones ignore it.
func stored_count() -> int:
	var total: int = 0
	for cell: Vector3i in cell_stacks:
		total += int((cell_stacks[cell] as Dictionary).get("count", 0))
	return total


## Tag acceptance only — capacity is checked by reserve_deposit_cell.
## `item_tags` is the item's material_tags list from resources.json (queried
## through ItemDropManager — the registry pattern; never open the file here).
func accepts(item_tags: Array) -> bool:
	for tag: String in filter_tags:
		if item_tags.has(tag):
			return true
	return false


## True if at least one cell could take one unit of this item: an empty
## unreserved cell, or an unreserved same-item stack below stack_max.
func has_room_for(item_key: String, stack_max: int) -> bool:
	return _find_deposit_cell(item_key, stack_max, Vector3i.ZERO, false) != Vector3i(-1, -1, -1)


# ── Deposit reservations (doc 18 §2.3 worker loop, steps 2/4) ─────────────────

## Picks and reserves a deposit cell for one unit of `item_key`. Policy
## (doc 18 §6 decision 1 lean): same-item stack first, then nearest free
## cell to `near`. Returns Vector3i(-1,-1,-1) if the zone has no room.
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


# ── Work source: scheduler hooks (doc 18 Phase 3) ─────────────────────────────

## Dwarf-relative probe target for the scheduler (the generalised
## nearest_stand_target hook, TaskManager._try_assign): the zone floor cell
## nearest this dwarf. Vector3i(-1,..) if the zone is empty.
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


## Posts/top-ups HAUL leases: min(max_haulers, accepted loose items) while the
## zone has room, minus live leases (doc 16 §2.1 — intent-sized, never
## per-item). Excess leases self-correct by completing early (the mining
## precedent). Called by StockpileManager on wake events, never per frame.
func update_leases() -> void:
	if source_id < 0 or drop_manager == null or not is_instance_valid(drop_manager):
		return
	if not _has_any_room():
		return
	var candidates := int(drop_manager.call("count_loose", filter_tags, max_haulers))
	var wanted := mini(max_haulers, candidates)
	var missing := wanted - _lease_ids.size()
	for i: int in range(missing):
		var target := tile_cells[0] if not tile_cells.is_empty() else Vector3i.ZERO
		var task_id := int(TaskManager.add_task(
			Task.Type.HAUL, target, { "zone_id": source_id }, source_id))
		_lease_ids[task_id] = true


## A lease left the system FOR GOOD (completed / cancelled / failed).
## NOT for releases — a released lease returns to PENDING and still counts
## against max_haulers (erasing it here would make update_leases post
## duplicates). Reservation cleanup is idempotent — the dwarf's own teardown
## may already have freed everything (the mining defensive-unreserve pattern).
func on_task_gone(task_id: int, dwarf_id: int) -> void:
	_lease_ids.erase(task_id)
	if dwarf_id >= 0:
		cancel_haul(dwarf_id)


# ── Work source: the dwarf-facing haul loop (doc 18 §2.3) ─────────────────────

## Step 1+2, POUCH edition (SH backpack parity): reserve a BUNDLE — the
## nearest accepted item (main) plus up to pouch_capacity−1 extras within
## pouch_bundle_radius of it, each with a reserved deposit cell. The pouch
## carries ANYTHING, stone included (Alen 2026-07-06, full SH parity —
## Stonehearth has no weight limit); any heavy item aboard applies the heavy
## carry-speed multiplier for the whole trip. Items are returned in greedy
## nearest-neighbour visit order. Returns {} when there is nothing to haul
## or no room.
func reserve_haul(dwarf_id: int, dwarf_cell: Vector3i, exclude: Dictionary) -> Dictionary:
	if drop_manager == null or not is_instance_valid(drop_manager):
		return {}
	var main := drop_manager.call("nearest_loose", filter_tags, dwarf_cell, exclude) as Node3D
	if main == null:
		return {}
	var main_cell: Vector3i = drop_manager.call("item_floor_cell", main)

	# Candidate list: main first, then nearby extras.
	var items: Array[Node3D] = [main]
	if pouch_capacity > 1:
		var near_exclude := exclude.duplicate()
		near_exclude[main] = true
		var extras: Array[Node3D] = drop_manager.call(
			"loose_near", filter_tags, main_cell, pouch_bundle_radius,
			pouch_capacity - 1, near_exclude)
		for extra: Node3D in extras:
			items.append(extra)

	# Reserve item + deposit cell pairwise; stop bundling when the zone runs
	# out of cells. Zero reservations -> nothing this zone can take.
	var reserved_items: Array[Node3D] = []
	var deposits: Array[Vector3i] = []
	var any_heavy := false
	for item: Node3D in items:
		var key := String(drop_manager.call("item_key_of", item))
		var cell := reserve_deposit_cell(key, 1, main_cell, dwarf_id)
		if cell == Vector3i(-1, -1, -1):
			break   # zone full — take what we have
		if not bool(drop_manager.call("reserve", item, dwarf_id)):
			release_deposit_cell(cell)
			continue   # raced another hauler; try the next candidate
		reserved_items.append(item)
		deposits.append(cell)
		var def: Dictionary = drop_manager.call("get_item_def", key)
		if String(def.get("weight_class", "light")) == "heavy":
			any_heavy = true
	if reserved_items.is_empty():
		return {}

	# Greedy nearest-neighbour visit order starting from the dwarf.
	var ordered := _visit_order(reserved_items, dwarf_cell)
	_pulls[dwarf_id] = { "items": ordered, "deposits": deposits, "taken": 0 }
	return {
		"items": ordered,
		"deposit_target": deposits[0],
		"carry_mult": carry_speed_mult_heavy if any_heavy else 1.0,
	}


## Release protocol: frees every remaining reservation. Safe to call twice.
func cancel_haul(dwarf_id: int) -> void:
	if not _pulls.has(dwarf_id):
		return
	var pull: Dictionary = _pulls[dwarf_id]
	_pulls.erase(dwarf_id)
	for cell: Vector3i in pull["deposits"]:
		release_deposit_cell(cell)
	if drop_manager == null or not is_instance_valid(drop_manager):
		return
	var items: Array = pull["items"]
	for i: int in range(int(pull["taken"]), items.size()):
		var item: Node3D = items[i]
		if item != null and is_instance_valid(item):
			# Owner-guarded: skipped items in this range may have been
			# re-reserved by another hauler since (spam-robustness pass).
			drop_manager.call("unreserve", item, dwarf_id)


## Step 3: pick up the item at `index` in the visit order. The node is handed
## to the dwarf (who reparents it as a carried visual). Null = that item is
## gone; the dwarf skips it via skip_item().
func take_item(dwarf_id: int, index: int) -> Node3D:
	if not _pulls.has(dwarf_id):
		return null
	var pull: Dictionary = _pulls[dwarf_id]
	var items: Array = pull["items"]
	if index < 0 or index >= items.size():
		return null
	var item: Node3D = items[index]
	if item == null or not is_instance_valid(item) \
			or drop_manager == null or not is_instance_valid(drop_manager):
		return null
	var key := String(drop_manager.call("take", item))
	if key.is_empty():
		return null
	pull["taken"] = int(pull["taken"]) + 1
	return item


## An unpickable/unpathable bundle item: free its reservation and one deposit
## cell; the rest of the bundle continues.
func skip_item(dwarf_id: int, index: int) -> void:
	if not _pulls.has(dwarf_id):
		return
	var pull: Dictionary = _pulls[dwarf_id]
	var items: Array = pull["items"]
	if index >= 0 and index < items.size():
		var item: Node3D = items[index]
		if item != null and is_instance_valid(item) \
				and drop_manager != null and is_instance_valid(drop_manager):
			drop_manager.call("unreserve", item, dwarf_id)
	var deposits: Array = pull["deposits"]
	if not deposits.is_empty():
		release_deposit_cell(deposits[deposits.size() - 1])
		deposits.remove_at(deposits.size() - 1)


## Step 4: multi-deposit. Each carried node lands on its own reserved cell
## (one item per tile — WYSIWYG). `carried` = [[node, item_key], ...].
func commit_haul(dwarf_id: int, carried: Array) -> bool:
	if not _pulls.has(dwarf_id):
		return false
	var pull: Dictionary = _pulls[dwarf_id]
	_pulls.erase(dwarf_id)
	var deposits: Array = pull["deposits"]
	var placed := 0
	for entry: Array in carried:
		if placed >= deposits.size():
			break   # should not happen; guarded so extra nodes stay carried
		var node: Node3D = entry[0]
		var key: String = entry[1]
		var cell: Vector3i = deposits[placed]
		placed += 1
		deposit(cell, key)
		if node != null and is_instance_valid(node) \
				and drop_manager != null and is_instance_valid(drop_manager):
			drop_manager.call("place_stored", node, cell)
		if changed_callback.is_valid():
			changed_callback.call(key, 1)
	# Unused reserved cells (skipped items) are freed.
	for i: int in range(placed, deposits.size()):
		release_deposit_cell(deposits[i])
	return placed > 0


## Greedy nearest-neighbour ordering of bundle items starting at `from_cell`.
func _visit_order(items: Array[Node3D], from_cell: Vector3i) -> Array[Node3D]:
	var remaining := items.duplicate()
	var ordered: Array[Node3D] = []
	var here := from_cell
	while not remaining.is_empty():
		var best_idx := 0
		var best_dist: int = 0x7FFFFFFF
		for i: int in range(remaining.size()):
			var cell: Vector3i = drop_manager.call("item_floor_cell", remaining[i])
			var d := cell - here
			var dist := absi(d.x) + absi(d.z)
			if dist < best_dist:
				best_idx = i
				best_dist = dist
		var next: Node3D = remaining[best_idx]
		remaining.remove_at(best_idx)
		ordered.append(next)
		here = drop_manager.call("item_floor_cell", next)
	return ordered


# ── Internals ─────────────────────────────────────────────────────────────────

## Any empty unreserved cell (one item per tile — SH parity).
func _has_any_room() -> bool:
	for cell: Vector3i in tile_cells:
		if not reserved_cells.has(cell) and not cell_stacks.has(cell):
			return true
	return false


## One item per tile (SH parity): only EMPTY unreserved cells qualify.
## `_stack_max` is unused on ground zones — kept in the signature for the
## container extraction of this contract.
func _find_deposit_cell(_item_key: String, _stack_max: int, near: Vector3i, use_distance: bool) -> Vector3i:
	var best := Vector3i(-1, -1, -1)
	var best_dist: int = 0x7FFFFFFF
	for cell: Vector3i in tile_cells:
		if reserved_cells.has(cell) or cell_stacks.has(cell):
			continue
		var dist: int = 0
		if use_distance:
			var d := cell - near
			dist = absi(d.x) + absi(d.y) + absi(d.z)
		if dist < best_dist:
			best = cell
			best_dist = dist
	return best
