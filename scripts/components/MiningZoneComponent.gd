class_name MiningZoneComponent
extends RefCounted

## A mining zone as a WORK SOURCE (doc 16 §2.7 — the block-state split, closing
## the doc 43 backlog). The zone posts at most MAX_WORKERS intent-sized MINE
## leases; the per-block work NEVER exists as queued Task objects (§2.1:
## O(intents), not O(blocks)).
##
## Block states per zone:
##   region      — all designated blocks (shrinks only via player subtract)
##   completed   — mined blocks (zone-level progress; NEVER lost on release)
##   reserved    — Vector3i -> dwarf_id, at most one block per working dwarf
##   destination — derived lazily: in region, not completed, not reserved, and
##                 with at least one WALKABLE stand cell. Full path reachability
##                 is the dwarf's job at pull time (path fail -> next block,
##                 3 fails -> release lease w/ backoff — §2.7 step 2).
##
## OWNERSHIP: created and owned by MiningDesignationController's zone
## bookkeeping. World mutation (WorldData writes, renderer promotion, drops,
## interior tracking) happens in the CONTROLLER via commit_mined() — this
## component only manages zone state. Registered with TaskManager as a work
## source so DwarfAgents can reach it by zone_id (scene-decoupled).
##
## RELEASE RULE (doc 16 §2.8): releasing a worker only frees its reservation —
## the completed set is untouched and the block keeps full durability (partial
## swing progress is discarded by the agent, never stored here).

var zone_id: int = -1

## The owning controller. Plain Object reference — the controller is a scene
## Node and outlives every component it owns (it frees them with the zone).
var _controller: Object = null

var region: Dictionary = {}        # Vector3i -> true
var completed: Dictionary = {}     # Vector3i -> true
var reserved: Dictionary = {}      # Vector3i -> dwarf_id
var _reserved_by_dwarf: Dictionary = {}   # dwarf_id -> Vector3i

## Active lease task ids (maintained by the controller's signal routing).
var lease_ids: Dictionary = {}     # task_id -> true

var _destination_dirty: bool = true
var _destination: Array[Vector3i] = []

## Throttle for the controller's terrain-change refresh (stuck zones only).
var last_refresh_msec: int = 0

## Chunk-bounds cache for the controller's zero-lease revival hook.
var _chunk_min: Vector3i = Vector3i.ZERO
var _chunk_max: Vector3i = Vector3i.ZERO

## Stand-cell candidate offsets around a target block B: stand ON the block
## itself (dig under your feet — the top-face downward flow), or on any of the
## four lateral neighbours within the REACH envelope. All candidates are FLOOR
## cells in NavGrid terms.
const _LATERAL: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
]

## Vertical mining reach from a stand cell (Alen, 2026-06-10: dwarves work a
## wall face up to 5 blocks above their floor — pick-on-a-long-haft fantasy,
## and it lets a 4-block dig cell be cleared from its own pit floor). Values
## are set by the controller from mining_config.json execution.* — these are
## fallbacks only.
##   reach_up   — block may sit up to N blocks ABOVE the stand floor
##   reach_down — block may sit up to N blocks BELOW the stand floor (beside it)
var reach_up: int = 5
var reach_down: int = 1


func _init(controller: Object, p_zone_id: int, blocks: Array[Vector3i]) -> void:
	_controller = controller
	zone_id = p_zone_id
	for block: Vector3i in blocks:
		region[block] = true
	_recompute_chunk_bounds()


# ── Counts ────────────────────────────────────────────────────────────────────

func remaining_count() -> int:
	return region.size() - completed.size()


func total_count() -> int:
	return region.size()


func is_empty() -> bool:
	return remaining_count() <= 0


## Remaining blocks not currently reserved (lease top-up sizing).
func unreserved_remaining() -> int:
	return remaining_count() - reserved.size()


# ── Region edits (player subtract / partial remove) ──────────────────────────

## Removes blocks from the region outright (Ctrl-subtract). Reserved blocks
## being subtracted are force-unreserved — the working dwarf notices at its
## next commit/pull (commit_mined fails safe on a lost reservation).
func subtract_blocks(blocks: Array[Vector3i]) -> void:
	for block: Vector3i in blocks:
		if not region.has(block):
			continue
		region.erase(block)
		completed.erase(block)
		if reserved.has(block):
			var dwarf_id := int(reserved[block])
			reserved.erase(block)
			_reserved_by_dwarf.erase(dwarf_id)
	_destination_dirty = true
	_recompute_chunk_bounds()


# ── Worker API (called by DwarfAgent) ────────────────────────────────────────

## Pulls the next block for a dwarf: nearest destination block to `from_cell`,
## with its walkable stand cells sorted nearest-first. Reserves the block.
## `exclude` is the dwarf's own this-round blacklist (blocks it failed to path
## to). Returns {} when nothing is pullable — the lease completes early.
func reserve_next(dwarf_id: int, from_cell: Vector3i, exclude: Dictionary = {}) -> Dictionary:
	if _destination_dirty:
		_recompute_destination()

	var best_block := Vector3i(-1, -1, -1)
	var best_dist := 1 << 30
	for block: Vector3i in _destination:
		if completed.has(block) or reserved.has(block) or exclude.has(block):
			continue
		if not region.has(block):
			continue
		var d := absi(block.x - from_cell.x) + absi(block.y - from_cell.y) \
				+ absi(block.z - from_cell.z)
		if d < best_dist:
			best_dist = d
			best_block = block

	if best_block.y < 0:
		return {}

	var stand_cells := _walkable_stand_cells(best_block, from_cell)
	if stand_cells.is_empty():
		# Destination list was stale for this block — recompute next pull.
		_destination_dirty = true
		return {}

	# One reservation per dwarf (§2.7) — drop any stale one first.
	unreserve(dwarf_id)
	reserved[best_block] = dwarf_id
	_reserved_by_dwarf[dwarf_id] = best_block
	return { "block": best_block, "stand_cells": stand_cells }


## Frees a dwarf's reservation (idempotent). The block returns to the
## destination set; completed progress is never touched.
func unreserve(dwarf_id: int) -> void:
	if not _reserved_by_dwarf.has(dwarf_id):
		return
	var block: Vector3i = _reserved_by_dwarf[dwarf_id]
	_reserved_by_dwarf.erase(dwarf_id)
	if reserved.get(block, -1) == dwarf_id:
		reserved.erase(block)


## Release-protocol entry (controller routes task_released here).
func release_worker(dwarf_id: int) -> void:
	unreserve(dwarf_id)


## The dwarf's reserved block, or Vector3i(-1,-1,-1).
func reserved_block_of(dwarf_id: int) -> Vector3i:
	return _reserved_by_dwarf.get(dwarf_id, Vector3i(-1, -1, -1))


## Swing parameters for the dwarf's reserved block (doc 43 formula via the
## controller's mining config). {} if the dwarf holds no valid reservation.
func get_block_work(dwarf_id: int) -> Dictionary:
	var block := reserved_block_of(dwarf_id)
	if block.y < 0 or not region.has(block) or completed.has(block):
		return {}
	return _controller.call("get_zone_block_work", block)


## Finalises a mined block: validates the reservation, then hands the WORLD
## mutation to the controller (WorldData void write, renderer promotion,
## drops, interior tracking, zone bookkeeping). Returns false if the
## reservation was lost (zone subtract / cancel race) — fail-safe, no write.
func commit_mined(dwarf_id: int) -> bool:
	var block := reserved_block_of(dwarf_id)
	if block.y < 0 or not region.has(block) or completed.has(block):
		unreserve(dwarf_id)
		return false
	return bool(_controller.call("execute_zone_block_mined", zone_id, block, dwarf_id))


## Controller callback target — marks a block done after the world mutation.
func mark_completed(block: Vector3i, dwarf_id: int) -> void:
	completed[block] = true
	unreserve(dwarf_id)
	_destination_dirty = true


func mark_destination_dirty() -> void:
	_destination_dirty = true


## Count of currently workable blocks (≥1 walkable stand cell) — the zone
## window's "how stuck is this zone" diagnostic.
func destination_count() -> int:
	if _destination_dirty:
		_recompute_destination()
	return _destination.size()


# ── Destination derivation (lazy, local — §2.7) ──────────────────────────────

func _recompute_destination() -> void:
	_destination_dirty = false
	_destination.clear()
	for block: Vector3i in region.keys():
		if completed.has(block):
			continue
		if _has_walkable_stand_cell(block):
			_destination.append(block)


## Floor-cell Y offsets beside the block that keep it inside the reach
## envelope: floor at block.y + dy ⇒ block sits (-dy) above the floor, so
## dy runs from +reach_down (standing above, digging beside-below) down to
## -reach_up (standing below, swinging up the wall face).
func _stand_dy_range() -> Array[int]:
	var dys: Array[int] = []
	for dy in range(reach_down, -reach_up - 1, -1):
		dys.append(dy)
	return dys


func _has_walkable_stand_cell(block: Vector3i) -> bool:
	# Stand on the block itself (dig under your feet)…
	if NavGrid.is_walkable(block):
		return true
	# …or beside it, anywhere in the reach envelope.
	for dir: Vector2i in _LATERAL:
		for dy: int in _stand_dy_range():
			if NavGrid.is_walkable(Vector3i(block.x + dir.x, block.y + dy, block.z + dir.y)):
				return true
	return false


## All walkable stand cells for a block, nearest to the dwarf first.
func _walkable_stand_cells(block: Vector3i, from_cell: Vector3i) -> Array[Vector3i]:
	var cells: Array[Vector3i] = []
	if NavGrid.is_walkable(block):
		cells.append(block)
	for dir: Vector2i in _LATERAL:
		for dy: int in _stand_dy_range():
			var cell := Vector3i(block.x + dir.x, block.y + dy, block.z + dir.y)
			if NavGrid.is_walkable(cell):
				cells.append(cell)
	cells.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		var da := absi(a.x - from_cell.x) + absi(a.y - from_cell.y) + absi(a.z - from_cell.z)
		var db := absi(b.x - from_cell.x) + absi(b.y - from_cell.y) + absi(b.z - from_cell.z)
		return da < db)
	return cells


# ── Representative target & bounds ───────────────────────────────────────────

## Representative position for lease tasks (doc 16 §2.2). The probe's
## early-out accepts the target cell or a cell laterally adjacent within ±1 Y
## — narrower than the mining reach envelope — so for destination blocks the
## target is one of the block's actual STAND CELLS (walkable; the probe can
## land on it directly). The raw top-center of a side dig into a wall is
## interior rock with no adjacent floor and would probe unreachable forever
## even when the face is perfectly workable (caught 2026-06-10, first
## in-engine session of step 5/6). Falls back to a remaining region block
## only when no destination exists (zone currently unworkable — probes
## failing is then the truth).
func representative_target() -> Vector3i:
	if _destination_dirty:
		_recompute_destination()
	var use_destination := not _destination.is_empty()
	var pool: Array[Vector3i] = _destination
	if not use_destination:
		pool = []
		for block: Vector3i in region.keys():
			if not completed.has(block):
				pool.append(block)
	if pool.is_empty():
		return Vector3i(-1, -1, -1)
	var sum_x := 0
	var sum_z := 0
	var max_y := -1
	for block: Vector3i in pool:
		sum_x += block.x
		sum_z += block.z
		max_y = maxi(max_y, block.y)
	@warning_ignore("integer_division")
	var cx := sum_x / pool.size()
	@warning_ignore("integer_division")
	var cz := sum_z / pool.size()
	var best := Vector3i(-1, -1, -1)
	var best_d := 1 << 30
	for block: Vector3i in pool:
		if block.y != max_y:
			continue
		var d := absi(block.x - cx) + absi(block.z - cz)
		if d < best_d:
			best_d = d
			best = block
	if not use_destination:
		return best
	# Destination block — aim the probe at where a worker would STAND.
	var stand := _walkable_stand_cells(best, best)
	if stand.is_empty():
		return best   # stale destination; next recompute corrects it
	return stand[0]


## True if a dirtied chunk could affect this zone's reachability (±1 chunk
## margin) — the controller's zero-lease revival hook.
func intersects_chunk(chunk: Vector3i) -> bool:
	return chunk.x >= _chunk_min.x - 1 and chunk.x <= _chunk_max.x + 1 \
		and chunk.y >= _chunk_min.y - 1 and chunk.y <= _chunk_max.y + 1 \
		and chunk.z >= _chunk_min.z - 1 and chunk.z <= _chunk_max.z + 1


func _recompute_chunk_bounds() -> void:
	if region.is_empty():
		_chunk_min = Vector3i.ZERO
		_chunk_max = Vector3i(-1, -1, -1)
		return
	var first := true
	for block: Vector3i in region.keys():
		var c := Vector3i(block.x >> 4, block.y >> 4, block.z >> 4)
		if first:
			_chunk_min = c
			_chunk_max = c
			first = false
			continue
		_chunk_min = Vector3i(mini(_chunk_min.x, c.x), mini(_chunk_min.y, c.y), mini(_chunk_min.z, c.z))
		_chunk_max = Vector3i(maxi(_chunk_max.x, c.x), maxi(_chunk_max.y, c.y), maxi(_chunk_max.z, c.z))
