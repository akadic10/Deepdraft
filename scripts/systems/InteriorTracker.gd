extends Node

## Discovered interior regions. DATA ONLY: XrayController consumes these
## sets read-only; nothing renders from here (docs 11 and 210).
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
## and lighting. Block placement subtracts occupied air and dirties nearby shells.
##
## Exploration is saved separately from current terrain. Filling explored space
## never forgets it, and restoring discovery never changes a voxel.

const INTERIOR_HEIGHT := 4
const NEIGHBORS := [Vector3i.LEFT, Vector3i.RIGHT, Vector3i.UP, Vector3i.DOWN, Vector3i.FORWARD, Vector3i.BACK]
signal caves_discovered(cells: Array[Vector3i])
## Caves the colony mined into, after caves_discovered; not the surface caves a new
## world reveals, nor a load. EventLog lists them (doc 23).
signal cavern_found(cells: Array[Vector3i])
var _discovered_caves: Dictionary = {}
var _known_cells: Dictionary = {}

var _interior: Dictionary = {}      # chunk Vector3i -> Dictionary[cell Vector3i -> true]
var _xray_dirty: Dictionary = {}    # chunk Vector3i -> true (X1 consumer drains; 3×3×3 rule)
var _cell_count: int = 0
var revision := 0


func _ready() -> void:
	WorldData.block_changed.connect(_on_block_changed)
	print("InteriorTracker: ready (X0 data-only).")


func contains_air(cell: Vector3i) -> bool:
	return _interior.get(Vector3i(cell.x>>4,cell.y>>4,cell.z>>4),{}).has(cell) and _is_air(cell)


func get_interior_chunks() -> Array:
	return _interior.keys()


func get_interior_cells(chunk: Vector3i) -> Array:
	return _interior.get(chunk,{}).keys()


func _on_block_changed(cell: Vector3i, _old: int, new_id: int) -> void:
	_known_cells[cell] = true
	var chunk := Vector3i(cell.x>>4,cell.y>>4,cell.z>>4)
	if BlockRegistry.is_solid(new_id) and _interior.get(chunk,{}).erase(cell):
		_cell_count -= 1
		if _interior[chunk].is_empty(): _interior.erase(chunk)
		_mark_dirty_neighbourhood(cell)
		return
	# A new step changes adjoining floors/walls even when the edited block
	# itself was never registered as interior (e.g. replacing a natural floor).
	for offset: Vector3i in NEIGHBORS:
		var neighbour := cell+offset
		if _interior.get(Vector3i(neighbour.x>>4,neighbour.y>>4,neighbour.z>>4),{}).has(neighbour):
			_mark_dirty_neighbourhood(cell)
			return
	if _xray_dirty.has(chunk): revision += 1


## Registers freshly mined blocks. Call AFTER the void has been written to
## WorldData (the air walk reads world truth).
func on_blocks_mined(blocks: Array[Vector3i]) -> void:
	var discovered: Array[Vector3i] = []
	for block: Vector3i in blocks:
		_known_cells[block] = true
		_add_column(block)
		_mark_dirty_neighbourhood(block)
		for direction: Vector3i in NEIGHBORS:
			var cave_id := WorldGenerator.get_cave_id(block + direction)
			if cave_id < 0 or _discovered_caves.has(cave_id): continue
			_discovered_caves[cave_id] = true
			var cells := WorldGenerator.get_cave_air_cells(cave_id)
			for cell: Vector3i in cells: _add_cell(cell)
			discovered.append_array(cells)
	if not discovered.is_empty():
		caves_discovered.emit(discovered)
		cavern_found.emit(discovered)


func is_cave_discovered(cave_id: int) -> bool:
	return _discovered_caves.has(cave_id)


## Whether `cell` lies in a cave the colony has not found, in its air or its water. The slice
## shows it as rock, so every tool takes it for rock: rays stop on it, nothing is placed or
## planned in it, and Copy keeps it as the rock (Hard Rule 11).
func is_hidden_cave(cell: Vector3i) -> bool:
	var cave_id := WorldGenerator.get_cave_id(cell)
	return cave_id >= 0 and not _discovered_caves.has(cave_id)


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


## XrayController consumes the dirty chunk set, cleared on read.
func take_dirty_chunks() -> Array:
	var keys := _xray_dirty.keys()
	_xray_dirty.clear()
	return keys


## Interior air is derived from saved exploration and current terrain on restore.
func clear_runtime_state() -> void:
	_interior.clear()
	_xray_dirty.clear()
	_cell_count = 0
	_discovered_caves.clear()
	_known_cells.clear()
	revision += 1


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
	_known_cells[cell] = true
	if not _is_air(cell): return
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
	# Water occupies discovered space without erasing its discovery. Inspect
	# the underlying terrain, not WorldData's live water overlay.
	return BlockRegistry.is_transparent(WorldData.get_terrain_block(pos.x,pos.y,pos.z))


## 3×3×3 chunk neighbourhood goes x-ray-dirty (shell inflation crosses chunk
## borders — doc 11 X0).
func _mark_dirty_neighbourhood(pos: Vector3i) -> void:
	revision += 1
	var c := Vector3i(pos.x >> 4, pos.y >> 4, pos.z >> 4)
	for dx: int in [-1, 0, 1]:
		for dy: int in [-1, 0, 1]:
			for dz: int in [-1, 0, 1]:
				_xray_dirty[Vector3i(c.x + dx, c.y + dy, c.z + dz)] = true

func is_known(cell: Vector3i) -> bool:
	return _known_cells.has(cell)

func serialize_exploration() -> Dictionary:
	var cells: Array = []
	for cell: Vector3i in _known_cells: cells.append([cell.x,cell.y,cell.z])
	cells.sort_custom(func(a: Array,b: Array): return a[0]<b[0] or (a[0]==b[0] and (a[1]<b[1] or (a[1]==b[1] and a[2]<b[2]))))
	var caves := _discovered_caves.keys()
	caves.sort()
	return {"cells":cells,"caves":caves}

func restore_exploration(state: Dictionary) -> void:
	for packed: Array in state.cells: _add_cell(Vector3i(packed[0],packed[1],packed[2]))
	for cave_id in state.caves:
		if _discovered_caves.has(int(cave_id)): continue
		_discovered_caves[int(cave_id)] = true
		var cells := WorldGenerator.get_cave_air_cells(int(cave_id))
		for cell: Vector3i in cells: _add_cell(cell)
		caves_discovered.emit(cells)
