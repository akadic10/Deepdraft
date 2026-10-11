extends Node

## X0 — Interior region tracker (doc 11 §Phase X0, piggybacked on mining
## execution per doc 16 Phase 4). DATA ONLY: the future X-Ray render mode
## (X1/X2) consumes these sets read-only; nothing renders from here.
##
## Autoload, registered after TaskManager. Producers: real mining execution
## and the DEV instant-mine button (same pipeline minus the dwarf) — both call
## on_blocks_mined().
##
## COLUMN RULE: on every mined block, walk air UPWARD from the mined position
## (capped at INTERIOR_HEIGHT = 4 — one dig cell: floor + the 3-block nav
## clearance envelope) and add those cells to the per-chunk interior set.
## Mining adjacent to natural cave air discovers its connected finite system.
## That air joins the interior set and emits caves_discovered for rendering
## and lighting. Block placement (future) subtracts and locally recomputes.
##
## PERSISTENCE (doc 11 X0): the interior set is DERIVABLE from the mined set.
## The save system persists mined blocks only and rebuilds interiors on load —
## never serialise these tables.

const INTERIOR_HEIGHT := 4
const NEIGHBORS := [Vector3i.LEFT, Vector3i.RIGHT, Vector3i.UP, Vector3i.DOWN, Vector3i.FORWARD, Vector3i.BACK]
signal caves_discovered(cells: Array[Vector3i])
var _discovered_caves: Dictionary = {}

var _interior: Dictionary = {}      # chunk Vector3i -> Dictionary[cell Vector3i -> true]
var _xray_dirty: Dictionary = {}    # chunk Vector3i -> true (X1 consumer drains; 3×3×3 rule)
var _cell_count: int = 0


func _ready() -> void:
	print("InteriorTracker: ready (X0 data-only).")


## Registers freshly mined blocks. Call AFTER the void has been written to
## WorldData (the air walk reads world truth).
func on_blocks_mined(blocks: Array[Vector3i]) -> void:
	var discovered: Array[Vector3i] = []
	for block: Vector3i in blocks:
		_add_column(block)
		_mark_dirty_neighbourhood(block)
		for direction: Vector3i in NEIGHBORS:
			var cave_id := WorldGenerator.get_cave_id(block + direction)
			if cave_id < 0 or _discovered_caves.has(cave_id): continue
			_discovered_caves[cave_id] = true
			var cells := WorldGenerator.get_cave_air_cells(cave_id)
			for cell: Vector3i in cells: _add_cell(cell)
			discovered.append_array(cells)
	if not discovered.is_empty(): caves_discovered.emit(discovered)


func is_cave_discovered(cave_id: int) -> bool:
	return _discovered_caves.has(cave_id)


## Surface-connected caves are exposed by generation, not by a fictional
## mining edit. Re-derived on each new world/load; enclosed caves stay hidden.
func reveal_surface_caves() -> void:
	for cave: Dictionary in WorldGenerator.get_cave_catalog():
		if not cave.get("surface_open",false) or _discovered_caves.has(cave.id): continue
		_discovered_caves[cave.id] = true
		var cells := WorldGenerator.get_cave_air_cells(cave.id)
		for cell: Vector3i in cells: _add_cell(cell)
		caves_discovered.emit(cells)


func discovered_cave_count() -> int:
	return _discovered_caves.size()


func interior_cell_count() -> int:
	return _cell_count


func get_stats() -> Dictionary:
	return {
		"interior_cells": _cell_count,
		"interior_chunks": _interior.size(),
		"xray_dirty_chunks": _xray_dirty.size(),
		"discovered_caves": _discovered_caves.size(),
	}


## X1 hook (future): the dirty chunk set, cleared on read.
func take_dirty_chunks() -> Array:
	var keys := _xray_dirty.keys()
	_xray_dirty.clear()
	return keys


## Interior cells are derived from mined blocks and rebuilt during restore.
func clear_runtime_state() -> void:
	_interior.clear()
	_xray_dirty.clear()
	_cell_count = 0
	_discovered_caves.clear()


# ── Internals ─────────────────────────────────────────────────────────────────

func _add_column(pos: Vector3i) -> void:
	for k in range(INTERIOR_HEIGHT):
		var cell := Vector3i(pos.x, pos.y + k, pos.z)
		if cell.y >= WorldData.WORLD_SIZE_Y:
			break
		if not _is_air(cell):
			break
		_add_cell(cell)


func _add_cell(cell: Vector3i) -> void:
	var chunk_key := Vector3i(cell.x >> 4, cell.y >> 4, cell.z >> 4)
	if not _interior.has(chunk_key):
		_interior[chunk_key] = {}
		_mark_dirty_neighbourhood(cell)
	var cells: Dictionary = _interior[chunk_key]
	if not cells.has(cell):
		cells[cell] = true
		_cell_count += 1


## World truth: WorldData where the chunk exists (mining materialises chunks
## before writing void), the deterministic generated block elsewhere.
func _is_air(pos: Vector3i) -> bool:
	if WorldData.chunk_exists(pos.x >> 4, pos.y >> 4, pos.z >> 4):
		return BlockRegistry.is_transparent(WorldData.get_block(pos.x, pos.y, pos.z))
	return BlockRegistry.is_transparent(WorldGenerator.get_generated_block_id(pos.x, pos.y, pos.z))


## 3×3×3 chunk neighbourhood goes x-ray-dirty (shell inflation crosses chunk
## borders — doc 11 X0).
func _mark_dirty_neighbourhood(pos: Vector3i) -> void:
	var c := Vector3i(pos.x >> 4, pos.y >> 4, pos.z >> 4)
	for dx: int in [-1, 0, 1]:
		for dy: int in [-1, 0, 1]:
			for dz: int in [-1, 0, 1]:
				_xray_dirty[Vector3i(c.x + dx, c.y + dy, c.z + dz)] = true
