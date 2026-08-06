extends Node

## Sealed-room detection and temperature — doc 34, doc 22 (doors prerequisite).
## Autoload. Registered after InteriorTracker in project.godot.
##
## ROOM MODEL: a room is DERIVED state, never saved directly (the InteriorTracker
## precedent, doc 11 X0) — it is rebuilt from door placements + terrain on load,
## because furniture restore re-installs every door through the normal _install()
## path, which calls on_furniture_changed() below exactly as it would live.
##
## ALGORITHM (doc 34 "Sealing Rules"): flood-fill outward from every door cell
## through AIR ONLY. A cell that is BlockRegistry.is_solid() OR itself a door
## stops the fill (doors act as walls for sealing purposes, "regardless of
## animation state" — doc 34). If the fill terminates as a finite, bounded set
## of air cells, the room is sealed. If it exceeds MAX_ROOM_CELLS before
## terminating, the fill is presumed to have escaped into open/ungenerated
## space and the room is treated as UNSEALED — this is a deliberate approximation
## (the NavGrid 1200-node reachability cap is the same kind of tuning call):
## flood-filling the entire open world to *prove* a leak is computationally
## infeasible, but any leak grows past a generously-sized real room quickly.
##
## DOOR / HEAT-SOURCE TRACKING: this script does NOT listen to
## FurniturePlacementController signals (that controller is a scene node, not
## an autoload, so it is not guaranteed to exist yet when this autoload's
## _ready() runs — the established pattern in this codebase is the opposite
## direction, scene nodes calling INTO autoloads). Instead
## FurniturePlacementController calls RoomManager.on_furniture_changed()
## directly at both its install and uninstall sites.
##
## PERFORMANCE: geometry-affecting triggers (door add/remove, a mined/placed
## block) mark _rooms_dirty and a full rebuild runs at most once per
## REBUILD_THROTTLE_S in _process() — full rebuild (re-flood-fill from every
## known door) rather than incremental per-room diffing, which is simpler and
## correct at the door counts a colony will realistically have. WorldClock's
## hourly tick is cheap by contrast (formula only, no flood-fill) and runs
## directly against already-tracked rooms.

const MAX_ROOM_CELLS := 4096          # ~ a generous 16x16x16 hall; tuning constant
const REBUILD_THROTTLE_S := 0.5
const NEIGHBOR_OFFSETS: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 1, 0), Vector3i(0, -1, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]

const DOOR_KEY := "base:furniture:door"

## Emitted whenever a tracked room's computed state changes (new room, removed
## room, or temp_c recomputed). UI (world info / future inspect panel) listens.
signal room_updated(room_id: int)
signal room_removed(room_id: int)

var _door_cells: Dictionary = {}          # Vector3i -> true
var _heat_cells: Dictionary = {}          # Vector3i -> int (heat_units)

var _rooms: Dictionary = {}               # room_id -> RoomData-shaped Dictionary
var _cell_to_room: Dictionary = {}        # Vector3i (interior air cell) -> room_id
var _next_room_id: int = 1

var _rooms_dirty: bool = false
var _rebuild_accum: float = 0.0


func _ready() -> void:
	print("RoomManager: ready (doc 34/22).")
	WorldData.chunk_dirtied.connect(_on_chunk_dirtied)
	WorldClock.hour_changed.connect(_on_hour_changed)


func _process(delta: float) -> void:
	if not _rooms_dirty:
		return
	_rebuild_accum += delta
	if _rebuild_accum >= REBUILD_THROTTLE_S:
		_rebuild_accum = 0.0
		_rooms_dirty = false
		_rebuild_all_rooms()


# ── Public API — called directly by FurniturePlacementController ─────────────

## `installed` true on install, false on uninstall/teardown. `cells` is
## every footprint cell the piece occupies (FurniturePlacementController's
## component.cells, already computed by its own _footprint_cells(def,
## origin, yaw) — doc 22b, 2026-08-06: doors widened to a 2x1 footprint,
## so a single origin cell is no longer enough to seal a gap. EVERY
## footprint cell of a door is registered as a sealing boundary —
## _flood_fill_from_door() below already treats each _door_cells entry as
## an independent boundary cell and dedupes physically-adjacent cells of
## the same door via its claimed_doors set, so no other change was needed
## there. Heat sources stay keyed to cells[0] (the origin) only, even for
## a multi-cell piece — registering heat_units at every footprint cell
## would double-count it in _sum_heat(). `def` is the furniture def
## dictionary (already loaded by FurniturePlacementController — RoomManager
## never reads data/furniture/*.json itself, per the registry ownership
## rule).
func on_furniture_changed(key: String, cells: Array[Vector3i], def: Dictionary, installed: bool) -> void:
	var changed := false
	if key == DOOR_KEY:
		for cell: Vector3i in cells:
			if installed:
				if not _door_cells.has(cell):
					_door_cells[cell] = true
					changed = true
			else:
				if _door_cells.has(cell):
					_door_cells.erase(cell)
					changed = true
	var heat: Dictionary = def.get("heat_source", {})
	if not heat.is_empty() and not cells.is_empty():
		var origin_cell: Vector3i = cells[0]
		if installed:
			_heat_cells[origin_cell] = int(heat.get("heat_units", 0))
			changed = true
		else:
			if _heat_cells.has(origin_cell):
				_heat_cells.erase(origin_cell)
				changed = true
	if changed:
		_mark_dirty()


func get_stats() -> Dictionary:
	var sealed := 0
	var frozen := 0
	for room_id: int in _rooms:
		var room: Dictionary = _rooms[room_id]
		sealed += 1
		if float(room.get("temp_c", 99.0)) <= 0.0:
			frozen += 1
	return {
		"doors": _door_cells.size(),
		"rooms": sealed,
		"frozen_vaults": frozen,
	}


## Returns the RoomData dict for the room containing `cell`, or {} if the
## cell is not part of any currently-sealed room. Read-only consumers only
## (aging cellar / dwarf-comfort hooks land here per doc 34 — not built yet).
func get_room_at(cell: Vector3i) -> Dictionary:
	var room_id: int = _cell_to_room.get(cell, -1)
	if room_id < 0:
		return {}
	return _rooms.get(room_id, {})


# ── Triggers ──────────────────────────────────────────────────────────────────

func _on_chunk_dirtied(_cx: int, _cy: int, _cz: int) -> void:
	# Any block edit can open or close a room perimeter. Worldgen chunk
	# streaming also fires this signal, so this is a coarse trigger — the
	# throttle in _process() keeps a burst of edits (e.g. mining a corridor)
	# from re-running the flood-fill on every single block.
	_mark_dirty()


func _on_hour_changed(_new_hour: int) -> void:
	# Cheap path (doc 34 "Recalculation Triggers"): no geometry changed, so no
	# flood-fill — just re-run the formula for rooms whose seasonal_influence
	# is nonzero (shallow rooms only; deep rooms are skipped exactly as doc 34
	# specifies).
	for room_id: int in _rooms.keys():
		var room: Dictionary = _rooms[room_id]
		if float(room.get("seasonal_influence", 0.0)) <= 0.0:
			continue
		_recompute_temp(room)
		room_updated.emit(room_id)


func _mark_dirty() -> void:
	_rooms_dirty = true


# ── Detection ─────────────────────────────────────────────────────────────────

## Full rebuild: re-flood-fills from every known door cell, skipping doors
## already claimed by a room found earlier in this same pass (a room can have
## more than one door). Simple and correct; see file header for the perf note.
func _rebuild_all_rooms() -> void:
	var old_ids: Array = _rooms.keys()
	_rooms.clear()
	_cell_to_room.clear()

	var claimed_doors: Dictionary = {}     # Vector3i -> true (already part of a found room)
	for door_cell: Vector3i in _door_cells.keys():
		if claimed_doors.has(door_cell):
			continue
		var result := _flood_fill_from_door(door_cell)
		for d: Vector3i in result.get("door_cells", {}).keys():
			claimed_doors[d] = true
		if result.is_empty():
			continue   # unsealed — leaked past MAX_ROOM_CELLS, or no interior air at all
		var room_id := _next_room_id
		_next_room_id += 1
		var room := _build_room_data(result)
		_rooms[room_id] = room
		for cell: Vector3i in room["cells"].keys():
			_cell_to_room[cell] = room_id

	for room_id: int in _rooms.keys():
		room_updated.emit(room_id)
	for old_id: int in old_ids:
		if not _rooms.has(old_id):
			room_removed.emit(old_id)


## Doc 34 Sealing Rules 1-3. Returns {} if unsealed (no interior, or the fill
## exceeded MAX_ROOM_CELLS). Returns {"cells": Dictionary, "door_cells": Dictionary}
## on success — `cells` are the interior AIR cells only (doors are boundary,
## not interior).
func _flood_fill_from_door(door_cell: Vector3i) -> Dictionary:
	var visited: Dictionary = {}          # interior air cells found
	var door_cells_found: Dictionary = { door_cell: true }
	var queue: Array[Vector3i] = [door_cell]
	var head := 0
	while head < queue.size():
		var cur: Vector3i = queue[head]
		head += 1
		for offset: Vector3i in NEIGHBOR_OFFSETS:
			var n := cur + offset
			if visited.has(n) or door_cells_found.has(n):
				continue
			if _door_cells.has(n):
				door_cells_found[n] = true
				continue
			if BlockRegistry.is_solid(_block_id(n)):
				continue
			visited[n] = true
			if visited.size() > MAX_ROOM_CELLS:
				return {}   # presumed leak into open space — see file header
			queue.append(n)
	if visited.is_empty():
		return {}
	return { "cells": visited, "door_cells": door_cells_found }


func _block_id(pos: Vector3i) -> int:
	# The InteriorTracker world-truth pattern (X0): materialised chunks are
	# authoritative once mining has touched them; ungenerated chunks fall back
	# to the deterministic generator so unmined rock still reads as solid.
	if WorldData.chunk_exists(pos.x >> 4, pos.y >> 4, pos.z >> 4):
		return WorldData.get_block(pos.x, pos.y, pos.z)
	return WorldGenerator.get_generated_block_id(pos.x, pos.y, pos.z)


# ── Temperature (doc 34, formula ported verbatim) ─────────────────────────────

func _build_room_data(fill_result: Dictionary) -> Dictionary:
	var cells: Dictionary = fill_result["cells"]
	var mean_floor_y := _mean_floor_y(cells)
	var heat_units := _sum_heat(cells)
	var room := {
		"cells": cells,
		"door_cells": fill_result["door_cells"],
		"volume": cells.size(),
		"mean_floor_y": mean_floor_y,
		"heat_units": heat_units,
		"seasonal_influence": clampf(inverse_lerp(30.0, 75.0, mean_floor_y), 0.0, 1.0),
		"temp_c": 0.0,
		"is_frozen_vault": false,
	}
	_recompute_temp(room)
	return room


## mean_floor_y = average Y of the LOWEST air cell in each (x,z) column of the
## room's footprint (doc 34 Agent note) — not the geometric centre.
func _mean_floor_y(cells: Dictionary) -> float:
	var lowest_by_column: Dictionary = {}     # Vector2i(x,z) -> lowest y seen
	for cell: Vector3i in cells.keys():
		var col := Vector2i(cell.x, cell.z)
		if not lowest_by_column.has(col) or cell.y < int(lowest_by_column[col]):
			lowest_by_column[col] = cell.y
	if lowest_by_column.is_empty():
		return 0.0
	var total := 0
	for col: Vector2i in lowest_by_column.keys():
		total += int(lowest_by_column[col])
	return float(total) / float(lowest_by_column.size())


func _sum_heat(cells: Dictionary) -> int:
	var total := 0
	for cell: Vector3i in _heat_cells.keys():
		if cells.has(cell):
			total += int(_heat_cells[cell])
	return total


## doc 34 "Full Temperature Formula", ported verbatim.
##
## EXPLICIT TYPES THROUGHOUT (not `:=` inference): WorldClock.day / .season /
## .hour read as Variant when accessed from another script — the same reason
## WorldRenderer.gd writes `var season: String = WorldClock.season` instead of
## `:=` everywhere it touches WorldClock. Left as inference, a single Variant
## read taints every downstream `:=` in the expression chain (Godot 4.7
## "warnings as errors": "Cannot infer the type... because the value doesn't
## have a set type"). Every var below is either an explicit type with an
## explicit int()/float() cast at the WorldClock read, or built from vars that
## already are.
func _recompute_temp(room: Dictionary) -> void:
	var mean_floor_y: float = room["mean_floor_y"]
	var room_volume: int = room["volume"]
	var total_heat_units: int = room["heat_units"]

	var base_temp: float = lerp(10.0, -8.0, inverse_lerp(75.0, 1.0, mean_floor_y))
	var heat_bonus: float = float(total_heat_units) / float(max(room_volume, 1))

	var seasonal_influence: float = room["seasonal_influence"]
	var season_index := { "spring": 0, "summer": 1, "autumn": 2, "winter": 3 }
	var clock_day: int = WorldClock.day
	var clock_season: String = WorldClock.season
	var clock_hour: float = WorldClock.hour
	var day_of_year: int = (clock_day - 1) + (int(season_index.get(clock_season, 0)) * 28)
	var s_angle: float = (float(day_of_year) - 28.0) / 112.0 * TAU
	var seasonal_offset: float = 1.5 * cos(s_angle) * seasonal_influence

	var daily_offset: float = 0.5 * sin((clock_hour - 8.0) / 24.0 * TAU) * seasonal_influence

	var temp_c: float = base_temp + heat_bonus + seasonal_offset + daily_offset
	room["temp_c"] = temp_c
	room["is_frozen_vault"] = temp_c <= 0.0
