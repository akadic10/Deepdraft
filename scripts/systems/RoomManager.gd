extends Node

## Sealed rooms, temperature and appeal — docs 34, 22 and 23 ("Room appeal").
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
const RoomAppeal = preload("res://scripts/components/RoomAppeal.gd")
const Climate = preload("res://scripts/components/Climate.gd")
const HeatSpread = preload("res://scripts/components/HeatSpread.gd")

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
## Open-air fires warm different cells now (doc 34 "Heat and cold spreading").
signal warmth_changed(cells: Array[Vector3i])

var _door_cells: Dictionary = {}          # Vector3i -> true
var _heat_cells: Dictionary = {}          # Vector3i -> int (heat_units)
var _heat_reach: Dictionary = {}          # heat anchor -> its widest piece's radius in open air
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
## The climate of every spot, sealed or not (doc 34); rooms add their heat to it.
var climate: Climate
## Fires warming open air and doors leaking between rooms (doc 34).
var heat: HeatSpread
var _heat_refresh_queued := false
var appeal_config: Dictionary = {}
var room_kinds: Array = []   # room_kinds.json: what each kind of room needs, in test order


func _ready() -> void:
	const JsonData = preload("res://scripts/registries/JsonData.gd")
	detection_config = JsonData.read_dict("res://data/rooms/detection.json")
	temperature_config = JsonData.read_dict("res://data/world_gen/temperature.json")
	appeal_config = JsonData.read_dict("res://data/rooms/appeal.json")
	room_kinds = JsonData.read_dict("res://data/rooms/room_kinds.json").get("kinds", [])
	climate = Climate.new(self)
	heat = HeatSpread.new(self)
	print("RoomManager: ready (doc 34/22).")
	WorldData.chunk_dirtied.connect(_on_chunk_dirtied)
	WorldData.block_changed.connect(climate.on_block_changed)
	WorldData.block_changed.connect(_on_block_near_fire)
	InteriorTracker.caves_discovered.connect(climate.on_caves_discovered)
	door_boundaries_changed.connect(climate.on_doors_changed)
	door_boundaries_changed.connect(func(_cells: Array[Vector3i]) -> void: _queue_heat_refresh())
	WorldClock.hour_changed.connect(_on_hour_changed)
	# A door to the open air lets a little of the weather in.
	WeatherManager.weather_changed.connect(func(_id: String) -> void: _on_hour_changed(int(WorldClock.hour)))


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
	var old_ids := _rooms.keys()
	_rooms = _rebuild.rooms
	_cell_to_room = _rebuild.cell_to_room
	_next_room_id = _rebuild.next_room_id
	_rebuild = null
	_completed_rebuilds += 1
	_last_rebuild_frames = _rebuild_frames
	_last_latency_ms = (Time.get_ticks_usec() - _rebuild_started_usec) / 1000.0
	# Fires may now stand in a room or out of one; then the clock-dependent formula, at
	# commit rather than at a room's scan time.
	heat.rebuild()
	_recompute_temps()
	# Both maps are complete before any observer is notified.
	for id: int in _rooms: room_updated.emit(id)
	for id: int in old_ids:
		if not _rooms.has(id): room_removed.emit(id)
	var warmed := heat.take_changed()
	if not warmed.is_empty(): warmth_changed.emit(warmed)


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
	if String(def.get("furniture_category","")) == "bed" and not cells.is_empty():
		if installed: _bed_cells[cells[0]] = cells.duplicate()
		else:
			_bed_cells.erase(cells[0])
			_bed_assignments.erase(cells[0])
		changed = true
	# A nightly fire (doc 279) is its room's light fixture lit or cold, so a bedroom
	# keeps its kind by day; its heat counts only while it burns (set_fire_lit).
	if not def.get("light_source", {}).is_empty() and not cells.is_empty():
		var anchor := cells[0]
		var count := maxi(0, int(_light_cells.get(anchor, 0)) + (1 if installed else -1))
		if count > 0: _light_cells[anchor] = count
		else: _light_cells.erase(anchor)
		changed = true
	if not def.has("nightly_fire") and _count_heat(cells, def, installed):
		changed = true
	if changed:
		_mark_dirty()


## A nightly fire was lit or went out (doc 279), or a lit one was removed.
func set_fire_lit(cells: Array[Vector3i], def: Dictionary, lit: bool) -> void:
	if _count_heat(cells, def, lit):
		_mark_dirty()


## Adds or removes one piece's heat at its anchor (cells[0]).
func _count_heat(cells: Array[Vector3i], def: Dictionary, add: bool) -> bool:
	var source: Dictionary = def.get("heat_source", {})
	if source.is_empty() or cells.is_empty():
		return false
	var origin_cell: Vector3i = cells[0]
	# Wall mounts can share a floor anchor with another heat source.
	# Add/remove only this piece's contribution, never overwrite its neighbor.
	var units := int(source.get("heat_units", 0))
	var remaining := maxi(0, int(_heat_cells.get(origin_cell, 0)) + (units if add else -units))
	if remaining > 0:
		_heat_cells[origin_cell] = remaining
		if add: _heat_reach[origin_cell] = maxi(int(_heat_reach.get(origin_cell, 0)), int(source.get("radius", 0)))
	else:
		_heat_cells.erase(origin_cell)
		_heat_reach.erase(origin_cell)
	_queue_heat_refresh()
	return true


## Every burning heat source at its floor anchor: {units, radius}.
func heat_sources() -> Dictionary:
	var result := {}
	for anchor: Vector3i in _heat_cells:
		result[anchor] = {"units": int(_heat_cells[anchor]), "radius": int(_heat_reach.get(anchor, 0))}
	return result


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
	_heat_reach.clear()
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
	climate.clear()
	heat.clear()
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
	classify(room, int(_bed_assignments.get(beds[0], -1)) if beds.size() == 1 else -1)

## A room's kind (doc 261): the first kind in room_kinds.json whose needs the room meets,
## or a plain room. `bed_owner` is the owner of the room's one bed; only a kind that
## takes an owner keeps it.
func classify(room: Dictionary, bed_owner: int) -> void:
	room.owner_id = bed_owner
	room.room_type = "room"
	for kind: Dictionary in room_kinds:
		if missing_needs(room, kind).is_empty():
			room.room_type = String(kind.id)
			break
	if not bool(room_kind(room).get("owner", false)): room.owner_id = -1

## What a room still lacks to be a kind: its unmet needs (beds, lights, doors, owner).
func missing_needs(room: Dictionary, kind: Dictionary) -> Array[String]:
	var counts := room_counts(room)
	var missing: Array[String] = []
	var needs: Dictionary = kind.get("needs", {})
	for need: String in needs:
		var rule: Dictionary = needs[need]
		var count := int(counts.get(need, 0))
		if count < int(rule.get("least", 0)) or (rule.has("most") and count > int(rule.most)): missing.append(need)
	if bool(kind.get("owner", false)) and int(room.get("owner_id", -1)) < 0: missing.append("owner")
	return missing

## The counts a room's needs are measured in: whole beds, light sources and door pieces.
func room_counts(room: Dictionary) -> Dictionary:
	return {"beds": int(room.get("bed_count", 0)), "lights": int(room.get("light_count", 0)), "doors": room.get("door_cells", {}).size()}

## The room's kind from room_kinds.json, or {} for a plain room.
func room_kind(room: Dictionary) -> Dictionary:
	for kind: Dictionary in room_kinds:
		if String(kind.id) == String(room.get("room_type", "")): return kind
	return {}

## The kind a room is measured against in the room window: its own, or for a plain room
## the kind it is fewest needs away from (the first such, in the data's order).
func nearest_kind(room: Dictionary) -> Dictionary:
	var own := room_kind(room)
	if not own.is_empty(): return own
	var nearest := {}
	var fewest := 1 << 30
	for kind: Dictionary in room_kinds:
		var missing := missing_needs(room, kind).size()
		if missing < fewest:
			nearest = kind
			fewest = missing
	return nearest

func room_label(room: Dictionary) -> String:
	return String(room_kind(room).get("label", "Room"))

## The furniture in a room (doc 261): furniture key -> pieces. A piece is the room's when
## the air above any of its room cells is, as lights and heat are counted (a wall mount by
## the cell it hangs in); a door belongs to each room it seals.
func room_furniture(room: Dictionary) -> Dictionary:
	var counts := {}
	var furniture := get_tree().get_first_node_in_group("furniture_controller")
	if furniture == null: return counts
	var cells: Dictionary = room.get("cells", {})
	var doors: Dictionary = room.get("door_cells", {})   # door origin -> true
	for piece in furniture.get_installed_pieces():
		var anchors: Array[Vector3i] = furniture.room_cells(piece)
		if anchors.is_empty(): continue
		if doors.has(anchors[0]) or anchors.any(func(cell: Vector3i): return cells.has(cell + Vector3i.UP)):
			counts[String(piece.furniture_key)] = int(counts.get(String(piece.furniture_key), 0)) + 1
	return counts

## A room's appeal (RoomAppeal): its parts, what they add up to, the share its size counts,
## the score and its word. Worked out when asked, never saved.
func room_appeal(room: Dictionary) -> Dictionary:
	return RoomAppeal.score(room, self)


## Every sealed room's appeal in one pass, room id -> room_appeal() with the nodes it counts
## (`warm` pieces, `cool` loose and stocked goods): what the Appeal view draws.
func all_room_appeals() -> Dictionary:
	return RoomAppeal.score_all(self)


## The appeal of the sealed room around an air cell, or {} outside rooms: what a dwarf's
## sleep, meal or game there takes in.
func appeal_at(cell: Vector3i) -> Dictionary:
	var room := get_room_at(cell)
	return {} if room.is_empty() else room_appeal(room)


## The word for an appeal score (appeal.json): {word, below, points, tint}, each word holding
## the scores below its `below` and the last the rest.
func appeal_step(appeal: float) -> Dictionary:
	var words: Array = appeal_config.get("words", [])
	for i in range(words.size()):
		if i == words.size() - 1 or appeal < float(words[i].below): return words[i]
	return {}


func appeal_word(appeal: float) -> String:
	return String(appeal_step(appeal).get("word", ""))


## The words a save may name for a dwarf's room memories, lower case, and "" for none.
func appeal_word_ids() -> Dictionary:
	var ids := {"": true}
	for entry: Dictionary in appeal_config.get("words", []): ids[String(entry.word).to_lower()] = true
	return ids


# ── Triggers ──────────────────────────────────────────────────────────────────

func _on_chunk_dirtied(cx: int, cy: int, cz: int) -> void:
	# Unread chunks will be queried live. Distant streaming must not starve a
	# pending scan; any changed chunk already examined requires a fresh scan.
	if _rebuild != null and not _rebuild.read_chunks.has(Vector3i(cx, cy, cz)): return
	_mark_dirty()


func _on_hour_changed(_new_hour: int) -> void:
	# Hourly weather updates reuse room geometry and its precomputed exposure; a room changes
	# with the clock through its rock or through a door to the open air.
	_recompute_temps()
	for room_id: int in _rooms.keys():
		var form: Vector3 = _rooms[room_id].temp_form
		if form.y > 0.0 or form.z > 0.0: room_updated.emit(room_id)


## Open-air warmth and every room's temperature again, once a frame at most: fires lit or
## out, doors placed, blocks changed near a fire (doc 34 "Heat and cold spreading").
func _queue_heat_refresh() -> void:
	heat.mark_dirty()
	if _heat_refresh_queued: return
	_heat_refresh_queued = true
	_refresh_heat.call_deferred()


## A read in between may have walked the warmth already; its changed cells still wait here.
func _refresh_heat() -> void:
	_heat_refresh_queued = false
	if heat.is_dirty(): heat.rebuild()
	var before := {}
	for id: int in _rooms: before[id] = float(_rooms[id].temp_c)
	_recompute_temps()
	for id: int in _rooms:
		if not is_equal_approx(float(_rooms[id].temp_c), float(before[id])): room_updated.emit(id)
	var warmed := heat.take_changed()
	if not warmed.is_empty(): warmth_changed.emit(warmed)


## A block changed within reach of a burning fire: its open-air warmth walks again.
func _on_block_near_fire(cell: Vector3i, _old_id: int, _new_id: int) -> void:
	for anchor: Vector3i in _heat_reach:
		var reach := int(_heat_reach[anchor]) + 1
		var offset := cell - anchor
		if absi(offset.x) <= reach and absi(offset.y) <= reach + 1 and absi(offset.z) <= reach:
			_queue_heat_refresh()
			return


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


# ── Temperature (doc 34: the climate, and a sealed room's heat) ──────────────

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


## A sealed room on its own feels the season through its rock only, at its floor's height,
## plus its heat: `own_form`, Vector3(base, season share, 0). Its doors then pull it toward
## their other sides (`temp_form`; HeatSpread). Its fires are tended (owner, 2026-10-30):
## together they warm it to `tended_fire_c` before its doors leak, and no further. A room they
## can warm past that is held there, a flat form; one already warmer gets nothing from them.
## Each form is fixed while the clock moves; the hourly recompute moves a room between
## them as the season turns. `heat_cap_c` is how far below the cap its rock is now.
func _recompute_temp(room: Dictionary) -> void:
	var rock := Vector3(climate.mean_c(float(room.mean_floor_y)), float(room.seasonal_influence), 0.0)
	var rock_c := climate.form_temperature(rock)
	var tended := float(temperature_config.tended_fire_c)
	var heat := heating_contribution(int(room.heat_units), int(room.volume))
	var own := rock + Vector3(heat, 0.0, 0.0)
	if rock_c + heat > tended: own = rock if rock_c >= tended else Vector3(tended, 0.0, 0.0)
	room["heat_cap_c"] = maxf(0.0, tended - rock_c)
	room["heat_bonus_c"] = climate.form_temperature(own) - rock_c
	room["own_form"] = own
	room["temp_form"] = own
	_finish_temp(room)


## Every room's own temperature, then the doors' leaks between them.
func _recompute_temps() -> void:
	for room: Dictionary in _rooms.values(): _recompute_temp(room)
	heat.apply_door_leaks(_rooms, _cell_to_room)
	for room: Dictionary in _rooms.values(): _finish_temp(room)


func _finish_temp(room: Dictionary) -> void:
	room["temp_c"] = climate.form_temperature(room.temp_form)
	room["is_frozen_vault"] = float(room.temp_c) <= float(temperature_config.frozen_at_c)


## Single source and room totals share the same volume-normalized heating rule.
func heating_contribution(heat_units: int, room_volume: int) -> float:
	return float(heat_units) / maxf(float(room_volume), float(temperature_config.minimum_heated_volume))


## What a heat source adds to the sealed room at an air cell once the room's doors have
## leaked some of it away (HeatSpread.kept_share); 0 outside a sealed room. A burning source
## has its share of the room's tended heat, so two hearths never each claim it all; one not
## burning, what it would add on top of those that burn, up to the tended cap.
func heat_kept(air_cell: Vector3i, heat_units: int, burning := true) -> float:
	var id := get_room_id_at(air_cell)
	if id < 0: return 0.0
	var room: Dictionary = _rooms[id]
	var bonus := float(room.get("heat_bonus_c", 0.0))
	var added := bonus * minf(1.0, float(heat_units) / float(room.heat_units)) if burning and int(room.heat_units) > 0 \
		else minf(heating_contribution(heat_units, int(room.volume)), maxf(0.0, float(room.get("heat_cap_c", INF)) - bonus))
	return added * heat.kept_share(_rooms, id)


## Read-only inspector view. Re-resolve by air cell after every room rebuild.
func heat_source_status(air_cell: Vector3i, heat_units: int, burning := true) -> Dictionary:
	var room := get_room_at(air_cell)
	if room.is_empty(): return {}
	return {"room_id": get_room_id_at(air_cell), "room_label": room_label(room),
		"temperature_c": float(room.temp_c), "comfort": comfort_label(float(room.temp_c)),
		"contribution_c": heat_kept(air_cell, heat_units, burning)}

## Any cell's temperature now: its sealed room's, else the climate's for that spot.
func temperature_at(air_cell: Vector3i) -> float:
	var room := get_room_at(air_cell)
	if not room.is_empty(): return float(room.temp_c)
	var place := climate.exposure(air_cell)
	return climate.temperature(float(air_cell.y), float(place.season_share), float(place.air_share)) + heat.warmth_at(air_cell)


## A cell's temperature with its word, what sets it and its range over a year in clear
## weather: Climate.exposure's fields, or kind "room" in a sealed room (its blended form's
## shares), plus temperature_c, word, room_id, low_c and high_c (today's fires and doors
## included), fire_c (an open-air fire's warmth there), heat_c (what a room's own fires add,
## after its doors leak some away), door_c (what a room's doors add now, its own fires left
## out) and wet. Rooms: temperature_c = the rock's + heat_c + door_c.
func climate_at(cell: Vector3i) -> Dictionary:
	var room := get_room_at(cell)
	var place: Dictionary
	var form: Vector3
	var fire := 0.0
	var kept := 0.0
	var doors := 0.0
	if room.is_empty():
		place = climate.exposure(cell)
		fire = heat.warmth_at(cell)
		form = Vector3(climate.mean_c(float(cell.y)) + fire, float(place.season_share), float(place.air_share))
	else:
		form = room.temp_form
		place = {"kind": "room", "steps": -1, "cover": -1, "season_share": form.y, "air_share": form.z}
		var bonus := float(room.heat_bonus_c)
		kept = bonus * heat.kept_share(_rooms, get_room_id_at(cell))
		doors = climate.form_temperature(form) - climate.form_temperature(room.own_form) + bonus - kept
	var temp_c := climate.form_temperature(form)
	var span := climate.form_range(form)
	place.merge({"temperature_c": temp_c, "word": temperature_word(temp_c), "room_id": get_room_id_at(cell),
		"low_c": span.x, "high_c": span.y, "wet": climate.is_wet(), "fire_c": fire, "heat_c": kept, "door_c": doors})
	return place

func comfort_label(temp_c: float) -> String:
	if temp_c<float(temperature_config.cold_below_c): return "Cold"
	if temp_c<float(temperature_config.comfortable_min_c): return "Chilly"
	if temp_c<=float(temperature_config.comfortable_max_c): return "Comfortable"
	return "Hot"

## The sleep words, with Frozen for 0°C and below: the words temperature is shown in.
func temperature_word(temp_c: float) -> String:
	if temp_c <= float(temperature_config.frozen_at_c): return "Frozen"
	return comfort_label(temp_c)
