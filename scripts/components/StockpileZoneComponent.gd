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
## Phase 1 ships the data model + cell bookkeeping. The work-source half
## (HAUL lease posting, doc 18 Phase 3) lands with StockpileManager — this
## component never talks to TaskManager directly in Phase 1.
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
	"stockpile_misc", "stockpile_currency",
]

var zone_id: int = -1
var tile_cells: Array[Vector3i] = []          # floor cells, all at floor_y
var floor_y: int = 0                          # the zone's single floor Y
var filter_tags: Array[String] = []
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


## Total stored items across all cell stacks.
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


# ── Internals ─────────────────────────────────────────────────────────────────

func _find_deposit_cell(item_key: String, stack_max: int, near: Vector3i, use_distance: bool) -> Vector3i:
	var best := Vector3i(-1, -1, -1)
	var best_key := Vector3i(2, 0x7FFFFFFF, 0)   # (stack-first rank, distance, unused)
	for cell: Vector3i in tile_cells:
		if reserved_cells.has(cell):
			continue
		var rank: int
		if cell_stacks.has(cell):
			var stack: Dictionary = cell_stacks[cell]
			if String(stack.get("item", "")) != item_key:
				continue
			if int(stack.get("count", 0)) >= stack_max:
				continue
			rank = 0   # same-item stack — preferred
		else:
			rank = 1   # empty cell
		var dist: int = 0
		if use_distance:
			var d := cell - near
			dist = absi(d.x) + absi(d.y) + absi(d.z)
		if rank < best_key.x or (rank == best_key.x and dist < best_key.y):
			best = cell
			best_key = Vector3i(rank, dist, 0)
	return best
