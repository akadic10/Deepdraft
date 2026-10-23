extends Node

## Sealed rooms, temperature and finished-floor appeal — docs 34, 22 and 128.
## Autoload. Registered after InteriorTracker in project.godot.
##
## ROOM MODEL: a room is DERIVED state, never saved directly (the InteriorTracker
## precedent, doc 11 X0) — it is rebuilt from door placements + terrain on load,
## because furniture restore re-installs every door through the normal _install()
## path, which calls on_furniture_changed() below exactly as it would live.
##
## ALGORITHM (doc 34 "Sealing Rules", corrected 2026-08-07): every door tile
## seals a vertical COLUMN (its floor cell + DOOR_SEAL_HEIGHT air cells — the
## doorway gap its model visually fills; the door piece is walkable air with
## no terrain identity, so without the column the fill walked straight over
## the door and no room could ever seal). Each air cell ADJACENT to a door
## column starts its own flood-fill through AIR ONLY — per SIDE, because a
## door separates two spaces and seeding from the door itself would merge
## room and corridor into one leaked region. A cell that is
## BlockRegistry.is_solid() OR inside any door column stops the fill (doors
## act as walls, "regardless of animation state" — doc 34). A fill that
## terminates as a finite set of air cells is a sealed room. A fill that
## exceeds MAX_ROOM_CELLS is presumed to have escaped into open/ungenerated
## space and its cells are memoised as open for the rest of the rebuild —
## this is a deliberate approximation (the NavGrid 1200-node reachability
## cap is the same kind of tuning call): flood-filling the entire open world
## to *prove* a leak is computationally infeasible, but any leak grows past
## a generously-sized real room quickly.
##
## DOOR / HEAT-SOURCE TRACKING: this script does NOT listen to
## FurniturePlacementController signals (that controller is a scene node, not
## an autoload, so it is not guaranteed to exist yet when this autoload's
## _ready() runs — the established pattern in this codebase is the opposite
## direction, scene nodes calling INTO autoloads). Instead
## FurniturePlacementController calls RoomManager.on_furniture_changed()
## directly at both its install and uninstall sites.
##
## PERFORMANCE: edits coalesce for 0.5s, then RoomRebuild advances under a
## soft per-frame budget. Readers keep the last complete room map until the
## replacement is ready. Changed chunks already read by a pending job cancel
## it; unvisited chunks are read live when reached. Furniture changes cancel
## pending work. Door light boundaries still update immediately.

const RoomRebuild = preload("res://scripts/components/RoomRebuild.gd")

const MAX_ROOM_CELLS := 4096          # ~ a generous 16x16x16 hall; tuning constant
const DOOR_SEAL_HEIGHT := 4           # air cells above a door's floor cell that seal
									  # (the doc 22b double door stands ~4 blocks tall)
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
## Physical doorway changes, independent of room rebuilds or temperature ticks.
signal door_boundaries_changed(cells: Array[Vector3i])

var _door_cells: Dictionary = {}          # Vector3i -> true
var _heat_cells: Dictionary = {}          # Vector3i -> int (heat_units)
var _light_cells: Dictionary = {}         # floor anchor -> installed light count
var _bed_cells: Dictionary = {}           # bed origin -> complete footprint
var _bed_assignments: Dictionary = {}     # bed origin -> permanent dwarf id

var _rooms: Dictionary = {}               # room_id -> RoomData-shaped Dictionary
var _cell_to_room: Dictionary = {}        # Vector3i (interior air cell) -> room_id
var _next_room_id: int = 1

var _rooms_dirty: bool = false
var _rebuild_accum: float = 0.0
var detection_config: Dictionary = {}
var _rebuild: RefCounted
var _rebuild_started_usec := 0
var _rebuild_frames := 0
var _completed_rebuilds := 0
var _cancelled_rebuilds := 0
var _last_rebuild_frames := 0
var _last_latency_ms := 0.0
var _last_main_ms := 0.0
var temperature_config: Dictionary = {}
var appeal_config: Dictionary = {}


func _ready() -> void:
	const JsonData = preload("res://scripts/registries/JsonData.gd")
	detection_config = JsonData.read_dict("res://data/rooms/detection.json")
	temperature_config = JsonData.read_dict("res://data/world_gen/temperature.json")
	appeal_config = JsonData.read_dict("res://data/rooms/appeal.json")
	print("RoomManager: ready (doc 34/22).")
	WorldData.chunk_dirtied.connect(_on_chunk_dirtied)
	WorldClock.hour_changed.connect(_on_hour_changed)


func _process(delta: float) -> void:
	_last_main_ms = 0.0
	if _rebuild == null:
		if not _rooms_dirty: return
		_rebuild_accum += delta
		if _rebuild_accum < REBUILD_THROTTLE_S: return
	var start := Time.get_ticks_usec()
	if _rebuild == null: _begin_rebuild()
	_rebuild_frames += 1
	_rebuild.advance(start + maxi(1, int(float(detection_config.rebuild_budget_ms) * 1000)),
		maxi(1, int(detection_config.budget_check_operations)))
	if _rebuild.stage == RoomRebuild.Stage.DONE: _publish_rebuild()
	_last_main_ms = (Time.get_ticks_usec() - start) / 1000.0


## True when the cell is a recognised doorway.
func is_door_cell(cell: Vector3i) -> bool:
	return _door_cells.has(cell)


func is_updating() -> bool:
	return _rooms_dirty or _rebuild != null


func get_rebuild_stats() -> Dictionary:
	return {"pending": is_updating(), "active": _rebuild != null,
		"main_ms": _last_main_ms, "completed": _completed_rebuilds,
		"cancelled": _cancelled_rebuilds, "last_frames": _last_rebuild_frames,
		"last_latency_ms": _last_latency_ms}


func _begin_rebuild() -> void:
	_rooms_dirty = false
	_rebuild_accum = 0.0
	_rebuild_started_usec = Time.get_ticks_usec()
	_rebuild_frames = 0
	_rebuild = RoomRebuild.new(self)


func _publish_rebuild() -> void:
	# Refresh the clock-dependent formula at commit, not at a room's scan time.
	for room: Dictionary in _rebuild.rooms.values(): _recompute_temp(room)
	var old_ids := _rooms.keys()
	_rooms = _rebuild.rooms
	_cell_to_room = _rebuild.cell_to_room
	_next_room_id = _rebuild.next_room_id
	_rebuild = null
	_completed_rebuilds += 1
	_last_rebuild_frames = _rebuild_frames
	_last_latency_ms = (Time.get_ticks_usec() - _rebuild_started_usec) / 1000.0
	# Both maps are complete before any observer is notified.
	for id: int in _rooms: room_updated.emit(id)
	for id: int in old_ids:
		if not _rooms.has(id): room_removed.emit(id)


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
func on_furniture_changed(_key: String, cells: Array[Vector3i], def: Dictionary, installed: bool) -> void:
	var changed := false
	var door_changes: Array[Vector3i] = []
	if String(def.get("furniture_category", "")) == "door":
		for cell: Vector3i in cells:
			var was_installed := _door_cells.has(cell)
			if installed:
				if not _door_cells.has(cell):
					# Value = the piece's ORIGIN cell (cells[0]) — the door's
					# identity. Lets every consumer count door PIECES instead
					# of door tiles (a 2-wide door is ONE door — Alen,
					# 2026-08-07, first Rooms-tool session showed "Doors: 2").
					_door_cells[cell] = cells[0]
					changed = true
			else:
				if _door_cells.has(cell):
					_door_cells.erase(cell)
					changed = true
			if was_installed != _door_cells.has(cell):
				for dy in range(DOOR_SEAL_HEIGHT + 1):
					door_changes.append(cell + Vector3i.UP * dy)
	if not door_changes.is_empty():
		door_boundaries_changed.emit(door_changes)
	if not def.get("light_source", {}).is_empty() and not cells.is_empty():
		var anchor := cells[0]
		var count := maxi(0, int(_light_cells.get(anchor, 0)) + (1 if installed else -1))
		if count > 0: _light_cells[anchor] = count
		else: _light_cells.erase(anchor)
		changed = true
	if String(def.get("furniture_category","")) == "bed" and not cells.is_empty():
		if installed: _bed_cells[cells[0]] = cells.duplicate()
		else:
			_bed_cells.erase(cells[0])
			_bed_assignments.erase(cells[0])
		changed = true
	var heat: Dictionary = def.get("heat_source", {})
	if not heat.is_empty() and not cells.is_empty():
		var origin_cell: Vector3i = cells[0]
		# Wall mounts can share a floor anchor with another heat source.
		# Add/remove only this piece's contribution, never overwrite its neighbor.
		var units := int(heat.get("heat_units", 0))
		var remaining := maxi(0, int(_heat_cells.get(origin_cell, 0)) + (units if installed else -units))
		if remaining > 0:
			_heat_cells[origin_cell] = remaining
		else:
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
	# Count door PIECES (distinct origin cells), not footprint tiles — a
	# 2-wide door is one door (2026-08-07).
	var pieces: Dictionary = {}
	for cell: Vector3i in _door_cells.keys():
		pieces[_door_cells[cell]] = true
	return {
		"doors": pieces.size(),
		"rooms": sealed,
		"frozen_vaults": frozen,
	}


## Returns the RoomData dict for the room containing `cell`, or {} if the
## cell is not part of any currently-sealed room. Read-only consumers only
## (sleep comfort is live; future aging/spoilage consumers use this query).
func get_room_at(cell: Vector3i) -> Dictionary:
	var room_id: int = _cell_to_room.get(cell, -1)
	if room_id < 0:
		return {}
	return _rooms.get(room_id, {})


## Room id containing `cell`, or -1. NOTE room ids are reassigned on every
## completed rebuild — treat an id as valid
## only until the next room_updated/room_removed burst; re-resolve by cell.
func get_room_id_at(cell: Vector3i) -> int:
	return int(_cell_to_room.get(cell, -1))


## Read-only view of every currently-sealed room (room_id -> RoomData dict).
## Live internal dictionary — callers must NOT mutate (the DwarfAssets pool
## precedent). Added 2026-08-07 for the 🚪 Rooms overlay tool.
func get_rooms() -> Dictionary:
	return _rooms


## Furniture is restored through installation after a world reload. Discard
## the previous world's derived registrations first, including removed doors.
func clear_runtime_state() -> void:
	var boundaries: Array[Vector3i] = []
	boundaries.assign(_door_boundary_cells().keys())
	var ids := _rooms.keys()
	_door_cells.clear()
	_heat_cells.clear()
	_light_cells.clear()
	_bed_cells.clear()
	_bed_assignments.clear()
	_rooms.clear()
	_cell_to_room.clear()
	_next_room_id = 1
	_rebuild = null
	_completed_rebuilds = 0
	_cancelled_rebuilds = 0
	_last_rebuild_frames = 0
	_last_latency_ms = 0.0
	_last_main_ms = 0.0
	_rooms_dirty = false
	_rebuild_accum = 0.0
	if not boundaries.is_empty(): door_boundaries_changed.emit(boundaries)
	for id: int in ids: room_removed.emit(id)


## Snapshot of the same closed-door boundary used by room sealing. Doors stay
## walkable; presentation systems must not infer them from navigation occupancy.
func get_door_boundaries() -> Dictionary:
	return _door_boundary_cells()


func count_room_lights(cells: Dictionary) -> int:
	var count := 0
	for anchor: Vector3i in _light_cells:
		if cells.has(anchor + Vector3i.UP): count += int(_light_cells[anchor])
	return count


func count_room_beds(cells: Dictionary) -> int:
	return room_beds(cells).size()

func room_beds(cells: Dictionary) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	for origin: Vector3i in _bed_cells:
		if _bed_cells[origin].all(func(cell: Vector3i): return cells.has(cell+Vector3i.UP)): result.append(origin)
	return result

func on_bed_assignment_changed(origin: Vector3i, dwarf_id: int) -> void:
	if _rebuild != null: _mark_dirty()
	if dwarf_id < 0: _bed_assignments.erase(origin)
	else: _bed_assignments[origin] = dwarf_id
	for id: int in _rooms:
		_classify_bedroom(_rooms[id])
		room_updated.emit(id)

func _classify_bedroom(room: Dictionary) -> void:
	var beds := room_beds(room.cells)
	room.bed_count = beds.size()
	room.room_type = "room"
	room.owner_id = -1
	if beds.is_empty() or room.light_count==0 or room.door_cells.is_empty(): return
	if beds.size()>1:
		room.room_type = "barracks"
	else:
		room.owner_id = int(_bed_assignments.get(beds[0],-1))
		room.room_type = "personal_bedroom" if room.owner_id>=0 else "bedroom"

func room_label(room: Dictionary) -> String:
	match String(room.get("room_type","")):
		"personal_bedroom": return "Personal bedroom"
		"barracks": return "Barracks"
		"bedroom": return "Bedroom"
	return "Room"


# ── Triggers ──────────────────────────────────────────────────────────────────

func _on_chunk_dirtied(cx: int, cy: int, cz: int) -> void:
	# Unread chunks will be queried live. Distant streaming must not starve a
	# pending scan; any changed chunk already examined requires a fresh scan.
	if _rebuild != null and not _rebuild.read_chunks.has(Vector3i(cx, cy, cz)): return
	_mark_dirty()


func _on_hour_changed(_new_hour: int) -> void:
	# Hourly weather updates reuse room geometry and its precomputed exposure.
	for room_id: int in _rooms.keys():
		var room: Dictionary = _rooms[room_id]
		if float(room.get("seasonal_influence", 0.0)) <= 0.0:
			continue
		_recompute_temp(room)
		room_updated.emit(room_id)


func _mark_dirty() -> void:
	_rooms_dirty = true
	if _rebuild != null:
		_rebuild = null
		_cancelled_rebuilds += 1
		# Already paid the coalescing delay. Restart once on the next frame.
		_rebuild_accum = REBUILD_THROTTLE_S


# ── Detection ─────────────────────────────────────────────────────────────────

## Synchronous drain for deterministic fixtures/development queries only.
## Runtime scheduling always enters through _process's budgeted path.
func _rebuild_all_rooms() -> void:
	_begin_rebuild()
	while _rebuild.stage != RoomRebuild.Stage.DONE:
		_rebuild.advance(Time.get_ticks_usec() + 1000000, 16)
	_publish_rebuild()


## Every cell a door seals: each registered footprint FLOOR cell plus the
## DOOR_SEAL_HEIGHT air cells above it (the doorway gap the door visually
## fills). Values map back to the owning door PIECE's origin cell so a room
## reports door pieces, not tiles or boundary-column cells.
func _door_boundary_cells() -> Dictionary:
	var result: Dictionary = {}     # boundary cell -> door piece origin cell
	for floor_cell: Vector3i in _door_cells.keys():
		var piece_origin: Vector3i = _door_cells[floor_cell]
		for dy: int in range(0, DOOR_SEAL_HEIGHT + 1):
			result[floor_cell + Vector3i(0, dy, 0)] = piece_origin
	return result


func _block_id(pos: Vector3i) -> int:
	# The InteriorTracker world-truth pattern (X0): materialised chunks are
	# authoritative once mining has touched them; ungenerated chunks fall back
	# to the deterministic generator so unmined rock still reads as solid.
	if WorldData.chunk_exists(pos.x >> 4, pos.y >> 4, pos.z >> 4):
		return WorldData.get_block(pos.x, pos.y, pos.z)
	return WorldGenerator.get_generated_block_id(pos.x, pos.y, pos.z)


# ── Temperature (doc 34, sheltered rock climate) ─────────────────────────────

## Count physical interior walking surfaces, even below furniture. Doorway
## columns are outside room.cells. Mixed floor materials count together; plans
## and natural rock never count. Derive this again on terrain edits and load.
func flooring_stats(cells: Dictionary) -> Dictionary:
	var total := 0
	var finished := 0
	for air: Vector3i in cells:
		if not cells.has(air+Vector3i.UP) or not cells.has(air+Vector3i.UP*2): continue
		var id := _block_id(air+Vector3i.DOWN)
		if not BlockRegistry.is_solid(id): continue
		total += 1
		if BlockRegistry.get_def(BlockRegistry.get_key(id)).get("kind","") == "constructed_floor": finished += 1
	var complete := total > 0 and finished == total
	return {"floor_tiles":total,"finished_floor_tiles":finished,"flooring_complete":complete,
		"flooring_appeal":float(appeal_config.complete_floor_bonus) if complete else 0.0}


## Heat sources register at their footprint FLOOR cell (a SOLID ground
## block), but a room's `cells` are interior AIR — so the membership test
## must look at the air cell directly ABOVE the heat source's floor cell
## (where the piece actually stands). Testing the floor cell itself matched
## nothing, ever: hearths silently contributed 0 heat until the 2026-08-07
## Rooms-tool playtest made the readout visible.
func _sum_heat(cells: Dictionary) -> int:
	var total := 0
	for cell: Vector3i in _heat_cells.keys():
		if cells.has(cell + Vector3i(0, 1, 0)):
			total += int(_heat_cells[cell])
	return total


## Sheltered rock climate and installed heating; tuning is owned by this autoload.
func _recompute_temp(room: Dictionary) -> void:
	var heat_bonus := heating_contribution(int(room.heat_units), int(room.volume))
	room["heat_bonus_c"] = heat_bonus
	room["temp_c"] = ambient_temperature(float(room.seasonal_influence))+heat_bonus
	room["is_frozen_vault"] = float(room.temp_c)<=0.0


## Single source and room totals share the same volume-normalized heating rule.
func heating_contribution(heat_units: int, room_volume: int) -> float:
	return float(heat_units) / maxf(float(room_volume), float(temperature_config.minimum_heated_volume))


## Read-only inspector view. Re-resolve by air cell after every room rebuild.
func heat_source_status(air_cell: Vector3i, heat_units: int) -> Dictionary:
	var room := get_room_at(air_cell)
	if room.is_empty(): return {}
	return {"room_id": get_room_id_at(air_cell), "room_label": room_label(room),
		"temperature_c": float(room.temp_c), "comfort": comfort_label(float(room.temp_c)),
		"contribution_c": heating_contribution(heat_units, int(room.volume))}

func temperature_at(air_cell: Vector3i) -> float:
	var room := get_room_at(air_cell)
	if not room.is_empty(): return float(room.temp_c)
	var cover := maxi(0,WorldGenerator.get_overview_surface_height(air_cell.x,air_cell.z)-air_cell.y)
	return ambient_temperature(exp(-float(cover)/float(temperature_config.cover_damping_blocks)))

func comfort_label(temp_c: float) -> String:
	if temp_c<float(temperature_config.cold_below_c): return "Cold"
	if temp_c<float(temperature_config.comfortable_min_c): return "Chilly"
	if temp_c<=float(temperature_config.comfortable_max_c): return "Comfortable"
	return "Hot"

func ambient_temperature(exposure: float) -> float:
	var season_index := { "spring": 0, "summer": 1, "autumn": 2, "winter": 3 }
	var clock_day: int = WorldClock.day
	var clock_season: String = WorldClock.season
	var clock_hour: float = WorldClock.hour
	var day_of_year: int = (clock_day - 1) + (int(season_index.get(clock_season, 0)) * 28)
	var s_angle: float = (float(day_of_year) - 28.0) / 112.0 * TAU
	var seasonal_offset := float(temperature_config.seasonal_swing_c)*cos(s_angle)*exposure
	var daily_offset := float(temperature_config.daily_swing_c)*sin((clock_hour-8.0)/24.0*TAU)*exposure
	return float(temperature_config.rock_temperature_c)+seasonal_offset+daily_offset
