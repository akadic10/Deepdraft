extends Node3D

## Farming (doc 309): the Zones menu's Farming tool, the fields it lays out, the plants on their
## tiles and the work they post. A field is a farming zone: floor cells (NavGrid's convention)
## of grass or dirt under the open sky, on one level. Its plan names a crop for each season, or
## rest. A Farmer (FarmFieldWork.gd, a surface work source) hoes a tile into tilled soil, sows
## the season's crop, pulls it when ripe and hoes under what the plan has moved on from. Plants
## grow by the game hour: faster in damp soil, not at all in winter. Bushes and fruit trees that
## stand in a field are picked by its Farmers with no order. Fields save as the `farming`
## section; the crops are ContentRegistry's.
##
## The tool is the one every zone shares (ZoneTool.gd): a drag paints a flat rectangle on the
## anchor's plane, a click on a field opens its window (with the tool off too), right mouse
## stays the camera's and Esc is the dock's. This script says which cells can be tilled
## (`tile_reason`) and makes the field.

@export var dock_ui_path: NodePath
@export var slice_controller_path: NodePath
@export var window_manager_path: NodePath

const TOOL_ID := "farming_zone"
const WINDOW_ID := "farm_field_info"
const Work = preload("res://scripts/components/FarmFieldWork.gd")
const Sources = preload("res://scripts/components/WorkSourceTable.gd")
const Visuals = preload("res://scripts/components/FarmFieldVisuals.gd")
const Pictures = preload("res://scripts/components/Pictures.gd")
const FieldPanel = preload("res://scripts/ui/FarmFieldPanel.gd")
const ZoneTool = preload("res://scripts/components/ZoneTool.gd")
const REFRESH_SECONDS := 1.0
const UNREACHED_MSEC := 30000   # a tile nobody can stand beside is left alone this long
const NOWHERE := Vector3i(-1, -1, -1)
const REST := ""                # a season with nothing sown
const ANY_LEVEL := 99
## The task a career earns its experience by, to be a Farmer (professions.json).
const TRADE := "FARM"
## What a crop's first growth gains in each season: nothing grows in winter.
const GROWING := {"spring": 1.0, "summer": 1.0, "autumn": 1.0, "winter": 0.0}
## A job's place in a Farmer's order of work: ripe food first, new ground last.
const JOB_ORDER := {"harvest": 0, "clear": 1, "sow": 2, "till": 3}
const JOB_SECONDS := {"harvest": "harvest_seconds", "clear": "clear_seconds", "sow": "sow_seconds", "till": "till_seconds"}
# Leaf green, so a field never reads as storage (blue), mining (yellow) or fishing (teal).
const COLOR_VALID := Color(0.56, 0.80, 0.30, 0.30)
const COLOR_VALID_EDGE := Color(0.72, 0.94, 0.42, 0.85)
const COLOR_ZONE := Color(0.56, 0.80, 0.30, 0.07)
const COLOR_ZONE_EDGE := Color(0.72, 0.94, 0.42, 0.60)

signal tool_active_changed(active: bool)
signal order_created(receipt: Dictionary)

var config: Dictionary = {}
var _window_manager: UIWindowManager
var _window: UIWindow
var _panel: Control
var _window_zone := -1
var _tool: ZoneTool                  # the drag, its preview and the fields on the ground
var _next_id := 1
## Field id -> {"id", "cells": Array[Vector3i], "plan": {season: crop
## key or ""}, "tiles": {cell: tile}, "roofed": {cell: true}, "taken": {cell: true}, "stale": bool,
## "level": the lowest Farmer level its open work needs, "bushes": int, "trees": int, "crate": {}}.
## A tile is {"crop", "credit" (days grown), "ripe", "picked", "regrow" (days since a picking),
## "work" and "job" (work seconds done on the tile's job, kept across a release)}. Only tiles
## that hold a plant or work begun have one; a tile's ground is the block itself.
var _zones: Dictionary = {}
var _cell_to_zone: Dictionary = {}   # floor cell -> field id
var _work: RefCounted                # WorkSourceTable keyed by Vector2i(field id, place)
var _visuals: Node3D                 # FarmFieldVisuals
var _unreached: Dictionary = {}      # tile cell -> the tick (msec) it may be tried again
var _ground: Dictionary = {}         # a field's tile cell -> its ground now ("tilled", "untilled" or "")
var _tilled_id := -1
var _grown_at := -1.0                # elapsed days the plants were last grown to; below 0 after a load
var _best_level := 0                 # the highest Farmer level in the colony, counted with the work
var _refreshing := false
var _refresh_left := 0.0


func _ready() -> void:
	add_to_group("farming_system")
	add_to_group(SaveManager.OWNER_GROUP)
	config = TaskManager.get_config_section("farming")
	_tilled_id = BlockRegistry.get_id(StringName(String(config.get("tilled_block", "base:terrain:soil:tilled"))))
	_work = Sources.new()
	# A job done: the field counts what is left and posts the next lease.
	_work.on_gone = func(key: Variant, _task: Task) -> void: _refresh_zone(int((key as Vector2i).x))
	_visuals = Visuals.new()
	_visuals.name = "FieldPlants"
	add_child(_visuals)
	_window_manager = get_node_or_null(window_manager_path) as UIWindowManager
	_tool = ZoneTool.new()
	_tool.name = "ZoneTool"
	_tool.tool_id = TOOL_ID
	_tool.here_words = "A field is here"
	_tool.max_extent = int(config.get("max_zone_extent", 16))
	_tool.fill = COLOR_VALID
	_tool.edge = COLOR_VALID_EDGE
	_tool.cell_reason = tile_reason
	_tool.zone_at = func(cell: Vector3i) -> int: return int(_cell_to_zone.get(cell, -1))
	_tool.cells_chosen = _on_cells_chosen
	_tool.zone_clicked = _open_window
	_tool.active_changed.connect(func(on: bool) -> void: tool_active_changed.emit(on))
	add_child(_tool)
	var dock := get_node_or_null(dock_ui_path) as DockUI
	if dock != null:
		dock.register_tool(self, [TOOL_ID])
		dock.tool_requested.connect(_tool.on_tool_requested)
	var slice := get_node_or_null(slice_controller_path)
	if slice != null and slice.has_signal("slice_changed"): slice.connect("slice_changed", _on_slice_changed)
	WorldClock.hour_changed.connect(_on_hour)
	WorldClock.day_changed.connect(_on_hour)   # a jump of whole days changes no hour
	WorldClock.season_changed.connect(_on_season)
	WorldData.block_changed.connect(_on_block_changed)
	PlacedEntityRegistry.occupancy_changed.connect(_on_occupancy_changed)
	TaskManager.task_completed.connect(_on_task_completed)
	_build_window()


func _process(delta: float) -> void:
	_refresh_left -= delta
	if _refresh_left > 0.0: return
	_refresh_left = REFRESH_SECONDS
	refresh_work()
	if _window_zone > 0 and _window != null and _window.visible: _panel.show_field(zone_data(_window_zone))


# ── The tool (ZoneTool) ───────────────────────────────────────────────────────

func is_active() -> bool:
	return _tool.active


func activate() -> void:
	_tool.activate()


func deactivate() -> void:
	_tool.deactivate()


## A click on one of our zones opens its window. ObjectExplorerController asks every click tool
## this by name before it selects the bare ground under the pointer, so the name must stay.
func try_select_zone_at_screen(screen_pos: Vector2) -> bool:
	return _tool.select_zone_at(screen_pos)


## What the tool bar shows (doc 23, "The tool bar"): the tiles a drag takes, or why the cell
## under the pointer can't be farmed.
func tool_bar_state() -> Dictionary:
	var state := {"tool": TOOL_ID}
	if _tool.dragging:
		state.selection = {"count": "%d tile%s" % [_tool.preview.size(), "" if _tool.preview.size() == 1 else "s"],
			"detail": "A Farmer hoes and sows them", "at": _tool.pointer}
	elif _tool.hover != NOWHERE and not _tool.hover_reason.is_empty() and not _cell_to_zone.has(_tool.hover):
		state.selection = {"count": "Can't farm here", "detail": _tool.hover_reason, "short": true, "at": _tool.pointer}
	return state


## The tool bar's last order (View and Undo): the field a drag made, while it stands.
func order_is_pending(receipt: Dictionary) -> bool:
	return _zones.has(int(receipt.get("zone_id", -1)))


func undo_order(receipt: Dictionary) -> int:
	if not order_is_pending(receipt): return 0
	var count: int = _zones[int(receipt.zone_id)].cells.size()
	remove_zone(int(receipt.zone_id))
	return count


func inspect_order(receipt: Dictionary) -> void:
	if order_is_pending(receipt): _open_window(int(receipt.zone_id))


# ── Ground ────────────────────────────────────────────────────────────────────

## A drag or a click was let go over these cells (ZoneTool): they become a field.
func _on_cells_chosen(cells: Array[Vector3i]) -> void:
	var zone_id := create_zone(cells)
	if zone_id > 0:
		order_created.emit({"zone_id": zone_id, "message": "Field · %d tile%s" % [cells.size(), "" if cells.size() == 1 else "s"]})


## Why a floor cell can't be part of a field, or "" when it can: grass, dirt or tilled soil under
## the open sky, in no other zone. A cell that holds a bush, a tree or a stone may join: it is
## left alone, and a bush or fruit tree on it is picked.
func tile_reason(cell: Vector3i) -> String:
	if ZoneTool.near_edge(cell): return "Too near the world's edge"
	if _cell_to_zone.has(cell): return "Already a field"
	# A cave not yet found is rock to every tool (Hard Rule 11).
	if InteriorTracker.is_hidden_cave(cell + Vector3i.UP): return "Nobody has found this place"
	var taken := _tool.taken_by_another(cell)
	if not taken.is_empty(): return taken
	if ground_of(cell).is_empty(): return "Fields need grass or dirt"
	# Standing water only: a film thinner than that is damp ground (doc 33), the best ground a field has.
	if WaterManager.has_standing_water(cell + Vector3i.UP): return "This ground is under water"
	if not _open_sky(cell): return "Fields need the open sky"
	return ""


## A cell's ground for a field: "tilled", "untilled" (grass or dirt a hoe can break), or "".
## Read from the terrain itself: ground the colony has not touched has no chunk of its own, and
## WorldData.get_block reads it as air. A field's own tiles are remembered, since untouched
## ground is read from the generator, and kept true by every block change.
func ground_of(cell: Vector3i) -> String:
	if _ground.has(cell): return _ground[cell]
	var id := WorldData.get_terrain_block(cell.x, cell.y, cell.z)
	if id == _tilled_id: return "tilled"
	var kind := String(BlockRegistry.get_def(BlockRegistry.get_key(id)).get("kind", ""))
	return "untilled" if kind in config.get("tillable_kinds", []) else ""


## Nothing solid within sky_clearance blocks over the cell, and air to stand a plant in.
func _open_sky(cell: Vector3i) -> bool:
	for y in range(cell.y + 1, mini(cell.y + 1 + int(config.get("sky_clearance", 10)), WorldData.WORLD_SIZE_Y)):
		if BlockRegistry.is_solid(WorldData.get_terrain_block(cell.x, y, cell.z)): return false
	return true


## Whether a tile's soil is damp now: within reach of water (doc 33), or under a wet sky.
func is_damp(cell: Vector3i) -> bool:
	return wet_sky() or WaterManager.soil_moisture_at(cell) >= float(config.get("damp_from", 0.3))


## Rain or a storm outside winter: every open field is damp while it lasts.
func wet_sky() -> bool:
	return WorldClock.season != "winter" and bool(WeatherManager.current_definition().get("temperature", {}).get("wet", false))


# ── Fields ────────────────────────────────────────────────────────────────────

## Lays a field over `cells` (every one farmable, all on one level). Returns its id, or -1. A
## new field takes the starter crops for its plan; a load (`restoring`) keeps every saved cell.
func create_zone(cells: Array[Vector3i], requested_id := -1, plan: Dictionary = {}, restoring := false) -> int:
	var kept: Array[Vector3i] = []
	for cell: Vector3i in cells:
		if _cell_to_zone.has(cell) or cell in kept: continue
		if restoring or tile_reason(cell).is_empty(): kept.append(cell)
	if kept.is_empty(): return -1
	var zone_id := requested_id if requested_id > 0 else _next_id
	_next_id = maxi(_next_id, zone_id + 1)
	var zone := {"id": zone_id, "cells": kept, "plan": default_plan(), "tiles": {},
		"roofed": {}, "taken": {}, "stale": true, "level": ANY_LEVEL, "bushes": 0, "trees": 0, "crate": {}}
	for season: String in plan:
		if zone.plan.has(season): zone.plan[season] = String(plan[season])
	_zones[zone_id] = zone
	for cell: Vector3i in kept:
		_ground[cell] = ground_of(cell)
		_cell_to_zone[cell] = zone_id
		if not _open_sky(cell): zone.roofed[cell] = true
		_show_tile(zone, cell)
	for place in range(maxi(1, int(config.get("max_farmers_per_field", 2)))): _add_place(zone_id, place)
	_tool.show_zone(zone_id, kept, COLOR_ZONE, COLOR_ZONE_EDGE)
	if not restoring:
		_pick_standing()
		_refresh_zone(zone_id)
	return zone_id


## A field's plan when it is laid out: for each season, the first crop a new Farmer may sow in it.
func default_plan() -> Dictionary:
	var plan := {}
	for season: String in WorldClock.season_order():
		plan[season] = REST
		for key: String in ContentRegistry.crops:
			var crop: Dictionary = ContentRegistry.crops[key]
			if int(crop.get("farmer_level", 1)) <= 1 and season in crop.sow_seasons:
				plan[season] = key
				break
	return plan


## Unmarks a field. Its plants go with it; the tilled soil stays, and nothing else is lost
## (Hard Rule 12): a Farmer at work there stops.
func remove_zone(zone_id: int) -> void:
	if not _zones.has(zone_id): return
	for place in range(maxi(1, int(config.get("max_farmers_per_field", 2)))): _work.retire(Vector2i(zone_id, place), true)
	for cell: Vector3i in _zones[zone_id].cells:
		_visuals.set_tile(cell, "")
		_cell_to_zone.erase(cell)
		_unreached.erase(cell)
		_ground.erase(cell)
	_zones.erase(zone_id)
	_tool.hide_zone(zone_id)
	if _window_zone == zone_id: _close_window()
	_claim_pickers()


func is_zone_cell(cell: Vector3i) -> bool:
	return _cell_to_zone.has(cell)


func zone_ids() -> Array:
	var ids := _zones.keys()
	ids.sort()
	return ids


## A tile's record, or {}: its plant, how far it has grown, and work begun on it.
func tile_at(cell: Vector3i) -> Dictionary:
	var zone: Dictionary = _zones.get(int(_cell_to_zone.get(cell, -1)), {})
	return {} if zone.is_empty() else zone.tiles.get(cell, {})


## A Farmer's place in a field (FarmFieldWork), for the inspector and the tests.
func place_of(zone_id: int, place: int) -> RefCounted:
	return _work.get_source(Vector2i(zone_id, place))


func _add_place(zone_id: int, index: int) -> void:
	var place := Work.new()
	place.zone_id = zone_id
	place.origin = (_zones[zone_id].cells as Array)[0]
	place.job_callback = _find_job
	place.allows_callback = func(agent: DwarfAgent) -> bool: return level_of(agent) >= int(_zones.get(zone_id, {}).get("level", ANY_LEVEL))
	place.progress_callback = _note_progress
	place.complete_callback = _complete
	place.feedback_visible_callback = func() -> bool: return place.origin.y <= _tool.slice_y
	_work.add(Vector2i(zone_id, index), place)


func _places(zone_id: int) -> Array:
	var places: Array = []
	for index in range(maxi(1, int(config.get("max_farmers_per_field", 2)))):
		var place: RefCounted = _work.get_source(Vector2i(zone_id, index))
		if place != null: places.append(place)
	return places


# ── The plan ──────────────────────────────────────────────────────────────────

## Names a season's crop (REST for none). A crop goes only in a season it is sown in; one that
## takes two seasons holds the next one too. Returns false for a crop that can't go there.
func set_plan(zone_id: int, season: String, crop_key: String) -> bool:
	if not _zones.has(zone_id) or not season in WorldClock.season_order(): return false
	if not crop_key.is_empty() and not season in ContentRegistry.crop(crop_key).get("sow_seasons", []): return false
	var plan: Dictionary = _zones[zone_id].plan
	var order := WorldClock.season_order()
	var at := order.find(season)
	var before: String = order[(at - 1 + order.size()) % order.size()]
	var after: String = order[(at + 1) % order.size()]
	# The season before held a two-season crop that this season carried: it can't be sown without it.
	if String(plan[before]) != crop_key and _spans(String(plan[before]), before): plan[before] = REST
	plan[season] = crop_key
	if _spans(crop_key, season): plan[after] = crop_key
	# A season that only carried a crop sown the season before falls to rest with it.
	for step in range(1, order.size() + 1):
		var later: String = order[(at + step) % order.size()]
		var earlier: String = order[(at + step - 1) % order.size()]
		var held := String(plan[later])
		if held.is_empty() or later in ContentRegistry.crop(held).get("sow_seasons", []): continue
		if String(plan[earlier]) != held or not _spans(held, earlier): plan[later] = REST
	_refresh_zone(zone_id)
	if _window_zone == zone_id: _panel.show_field(zone_data(zone_id))
	return true


## Whether a crop sown in `season` is still in the ground the season after.
func _spans(crop_key: String, season: String) -> bool:
	var crop := ContentRegistry.crop(crop_key)
	return int(crop.get("plan_seasons", 1)) > 1 and season in crop.get("sow_seasons", [])


## Growing days from now until a field's plan moves on from a crop: what is left of this
## season, and each season after it that still names the crop. Winter adds nothing.
func growing_days_left(zone_id: int, crop_key: String, from_day := -1.0) -> float:
	var plan: Dictionary = _zones.get(zone_id, {}).get("plan", {})
	var order := WorldClock.season_order()
	var at := order.find(WorldClock.season)
	if plan.is_empty() or String(plan[order[at]]) != crop_key: return 0.0
	var day := from_day if from_day >= 0.0 else float(WorldClock.day) + WorldClock.hour / float(WorldClock.hours_per_day())
	var left := 0.0 if order[at] == "winter" else float(WorldClock.days_per_season()) + 1.0 - day
	for step in range(1, order.size()):
		var later: String = order[(at + step) % order.size()]
		if String(plan[later]) != crop_key: break
		if later != "winter": left += float(WorldClock.days_per_season())
	return left


## Whether the season's crop may be sown now: it is this season's to sow, and it will be ripe
## sow_margin_days before the plan moves on, so a Farmer never sows what cannot ripen.
func can_sow(zone_id: int, crop_key: String, from_day := -1.0) -> bool:
	var crop := ContentRegistry.crop(crop_key)
	if crop.is_empty() or not WorldClock.season in crop.sow_seasons: return false
	return growing_days_left(zone_id, crop_key, from_day) >= float(crop.grow_days) + float(config.get("sow_margin_days", 2.0))


## The last day of this season a crop is still sown on, 0 when it is too late or not this
## season's: "Sown until Summer 13."
func sow_until(zone_id: int, crop_key: String) -> int:
	for day in range(WorldClock.days_per_season(), 0, -1):
		if can_sow(zone_id, crop_key, float(day)): return day
	return 0


# ── Work ──────────────────────────────────────────────────────────────────────

## A dwarf's Farmer level: 0 for every other career.
func level_of(agent: DwarfAgent) -> int:
	if not is_instance_valid(agent) or not DwarfAssets.earns_by(agent.profession, TRADE): return 0
	return DwarfAssets.profession_level(agent.profession, agent.profession_experience)


## Whether the colony has a Farmer, busy or not.
func has_farmer() -> bool:
	return best_level() > 0


func best_level() -> int:
	var best := 0
	for agent: DwarfAgent in TaskManager.get_agents(): best = maxi(best, level_of(agent))
	return best


## The job a tile has now: {"job", "crop", "level"} with the Farmer level it needs, or {}.
## Ripe plants are pulled, plants the plan has moved on from are hoed under, tilled tiles are
## sown with the season's crop while it can still ripen, and new ground is hoed.
func tile_job(zone_id: int, cell: Vector3i) -> Dictionary:
	var zone: Dictionary = _zones.get(zone_id, {})
	if zone.is_empty(): return {}
	var tile: Dictionary = zone.tiles.get(cell, {})
	var held := String(tile.get("crop", ""))
	var wanted := String(zone.plan.get(WorldClock.season, REST))
	if not held.is_empty():
		if bool(tile.get("ripe", false)): return {"job": "harvest", "crop": held, "level": 1}
		return {"job": "clear", "crop": held, "level": 1} if held != wanted else {}
	if zone.roofed.has(cell) or zone.taken.has(cell): return {}
	var ground := ground_of(cell)
	if ground == "tilled":
		if wanted.is_empty() or not can_sow(zone_id, wanted): return {}
		var crop := ContentRegistry.crop(wanted)
		if bool(crop.get("needs_damp", false)) and not is_damp(cell): return {}
		return {"job": "sow", "crop": wanted, "level": int(crop.get("farmer_level", 1))}
	# New ground is hoed for a field that sows something in some season; an orchard's is left.
	if ground == "untilled" and (zone.plan.values() as Array).any(func(planned: Variant) -> bool: return not String(planned).is_empty()):
		return {"job": "till", "crop": "", "level": 1}
	return {}


## Posts the fields' leases: one for each place a field has work for, by the best Farmer the
## colony has. With no Farmer a field waits.
func refresh_work() -> void:
	_best_level = best_level()
	_claim_pickers()
	for zone_id: int in _zones: _refresh_zone(zone_id)


func _refresh_zone(zone_id: int) -> void:
	if _refreshing or not _zones.has(zone_id): return
	_refreshing = true
	var zone: Dictionary = _zones[zone_id]
	if bool(zone.stale): _survey(zone)
	var places := _places(zone_id)
	var claimed := {}
	for place: RefCounted in places:
		if place.reserved_by >= 0: claimed[place.origin] = true
	var open := 0
	var lowest := ANY_LEVEL
	for cell: Vector3i in zone.cells:
		if claimed.has(cell): continue
		var found := tile_job(zone_id, cell)
		if found.is_empty(): continue
		lowest = mini(lowest, int(found.level))
		if int(found.level) <= _best_level: open += 1
	zone.level = lowest
	for place: RefCounted in places:
		if place.reserved_by >= 0:
			place.state.designated = true
			continue
		place.state.designated = open > 0
		if open > 0:
			open -= 1
			place.ensure_lease()
		else:
			place.withdraw_lease()
	_refreshing = false


## The nearest job in a place's field for a dwarf standing at `from`: the kind that comes first
## in a Farmer's order, then the nearest tile. For the scheduler's quote (`agent` null) any job a
## Farmer of the colony may do.
func _find_job(agent: DwarfAgent, from: Vector3i, place: RefCounted) -> Dictionary:
	var zone: Dictionary = _zones.get(place.zone_id, {})
	if zone.is_empty(): return {}
	var level := level_of(agent) if agent != null else _best_level
	var claimed := {}
	for other: RefCounted in _places(place.zone_id):
		if other != place and other.reserved_by >= 0: claimed[other.origin] = true
	for attempt in range(8):
		var best := {}
		var best_rank := INF
		var now := Time.get_ticks_msec()
		for cell: Vector3i in zone.cells:
			if claimed.has(cell) or int(_unreached.get(cell, 0)) > now: continue
			var found := tile_job(place.zone_id, cell)
			if found.is_empty() or int(found.level) > level: continue
			var rank := float(JOB_ORDER[found.job]) * 1.0e6 + Vector3(cell - from).length_squared()
			if rank < best_rank:
				best_rank = rank
				best = found
				best.cell = cell
		if best.is_empty(): return {}
		if Work.stands_for(best.cell, from).is_empty():
			_unreached[best.cell] = now + UNREACHED_MSEC   # nobody can stand beside it: try the next
			continue
		var tile: Dictionary = zone.tiles.get(best.cell, {})
		best.seconds = float(config.get(JOB_SECONDS[best.job], 2.0))
		best.work = float(tile.get("work", 0.0)) if String(tile.get("job", "")) == String(best.job) else 0.0
		best.block = String(BlockRegistry.get_key(WorldData.get_terrain_block(best.cell.x, best.cell.y, best.cell.z)))
		return best
	return {}


## Work done on a tile stays on the tile, so a Farmer called away loses none (Hard Rule 12).
func _note_progress(place: RefCounted) -> void:
	var zone: Dictionary = _zones.get(place.zone_id, {})
	if zone.is_empty(): return
	if not zone.tiles.has(place.origin): zone.tiles[place.origin] = {"crop": "", "credit": 0.0, "ripe": false}
	zone.tiles[place.origin]["work"] = float(place.state.work_seconds)
	zone.tiles[place.origin]["job"] = String(place.job)


## A job's last stroke. The tile is checked again as it is now, so work begun before the plan or
## the ground changed never sows or pulls the wrong thing; the lease ends either way.
func _complete(dwarf_id: int, place: RefCounted) -> bool:
	var zone: Dictionary = _zones.get(place.zone_id, {})
	if zone.is_empty(): return true
	var cell: Vector3i = place.origin
	var now := tile_job(place.zone_id, cell)
	var tile: Dictionary = zone.tiles.get(cell, {})
	if now.is_empty() or String(now.job) != String(place.job) or String(now.crop) != String(place.crop):
		if String(tile.get("crop", "")).is_empty(): zone.tiles.erase(cell)
		else:
			tile.erase("work")
			tile.erase("job")
		return true
	match String(place.job):
		"till":
			zone.tiles.erase(cell)
			WorldData.set_block(cell.x, cell.y, cell.z, _tilled_id)
		"sow":
			zone.tiles[cell] = {"crop": String(place.crop), "credit": 0.0, "ripe": false}
		"clear":
			zone.tiles.erase(cell)
		"harvest":
			_harvest(zone, cell, TaskManager.get_agent(dwarf_id))
	_show_tile(zone, cell)
	return true


## A ripe tile is pulled: its vegetables into the field's open crate, the Farmer's experience,
## and the tile bare again, or left to regrow for a crop that is picked more than once.
func _harvest(zone: Dictionary, cell: Vector3i, agent: DwarfAgent) -> void:
	var tile: Dictionary = zone.tiles[cell]
	var key := String(tile.crop)
	var crop := ContentRegistry.crop(key)
	var item := String(crop.item)
	var count := int(crop.tile_yield)
	var drops := ItemDropManager.find(get_tree())
	if drops != null:
		# One crate takes the pulls until it is full, where the Farmer stood when it was begun.
		var crate: Dictionary = zone.crate
		if String(crate.get("item", "")) != item or int(crate.get("count", 0)) + count > drops.item_capacity(item):
			crate = {"item": item, "count": 0, "cell": agent.current_cell() if is_instance_valid(agent) else cell}
		crate.count = int(crate.count) + count
		zone.crate = crate
		drops.spawn_drop(item, count, (crate.cell as Vector3i) + Vector3i.UP)
	_award(agent)
	if float(crop.get("regrow_days", 0.0)) > 0.0 and String(zone.plan.get(WorldClock.season, REST)) == key:
		zone.tiles[cell] = {"crop": key, "credit": float(crop.grow_days), "ripe": false, "picked": true, "regrow": 0.0}
	else:
		zone.tiles.erase(cell)
	print("FarmingSystem: field %d gave %d %s at %s." % [int(zone.id), count, item, cell])


## One experience for a tile harvested, or a bush or tree picked in a field (doc 41).
func _award(agent: DwarfAgent) -> void:
	if is_instance_valid(agent) and DwarfAssets.earns_by(agent.profession, TRADE):
		agent.profession_experience[agent.profession] = maxi(0, int(agent.profession_experience.get(agent.profession, 0))) + 1


# ── Growth ────────────────────────────────────────────────────────────────────

## Grows every plant up to now, from when it was last grown: a first growth by the growing days
## since (none in winter), a quarter faster in damp soil, and only in damp soil for a crop that
## needs it; a picked crop's regrowth by the days since, in winter too. Dampness is read as it is
## now for the whole span, which is an hour in play.
func grow() -> void:
	var now := WorldClock.elapsed_days()
	if _grown_at < 0.0 or now < _grown_at:
		_grown_at = now   # a load, or a new game: the hours start afresh
		return
	var days := now - _grown_at
	var growing := WorldClock.seasonal_days_between(_grown_at, now, GROWING)
	_grown_at = now
	if days <= 0.0: return
	var faster := float(config.get("damp_growth", 1.25))
	for zone: Dictionary in _zones.values():
		for cell: Vector3i in zone.tiles:
			var tile: Dictionary = zone.tiles[cell]
			var key := String(tile.get("crop", ""))
			if key.is_empty() or bool(tile.get("ripe", false)): continue
			var crop := ContentRegistry.crop(key)
			if bool(tile.get("picked", false)):
				tile["regrow"] = float(tile.get("regrow", 0.0)) + days
				if float(tile.regrow) >= float(crop.get("regrow_days", 0.0)):
					tile.ripe = true
					tile.picked = false
			else:
				var damp := is_damp(cell)
				var rate := (1.0 if damp else 0.0) if bool(crop.get("needs_damp", false)) else (faster if damp else 1.0)
				tile.credit = minf(float(crop.grow_days), float(tile.get("credit", 0.0)) + growing * rate)
				if float(tile.credit) >= float(crop.grow_days): tile.ripe = true
			_show_tile(zone, cell)


## What a tile shows: its plant's stage, the bare tilled soil, or nothing on untilled ground.
func stage_of(cell: Vector3i) -> String:
	var tile := tile_at(cell)
	var key := String(tile.get("crop", ""))
	if key.is_empty(): return "bare" if ground_of(cell) == "tilled" else ""
	if bool(tile.get("ripe", false)): return "ripe"
	if bool(tile.get("picked", false)): return "picked"
	var crop := ContentRegistry.crop(key)
	return "sprout" if float(tile.get("credit", 0.0)) < float(config.get("growing_from", 0.4)) * float(crop.grow_days) else "growing"


func _show_tile(zone: Dictionary, cell: Vector3i) -> void:
	var stage := stage_of(cell)
	var model := ""
	if stage == "bare": model = String(config.get("bare_model", ""))
	elif not stage.is_empty(): model = String(ContentRegistry.crop(String(zone.tiles[cell].crop)).models.get(stage, ""))
	_visuals.set_tile(cell, model)


func _on_hour(_hour: int) -> void:
	grow()
	for zone: Dictionary in _zones.values(): zone.stale = true
	_pick_standing()
	refresh_work()


## A new season: the plan moves on. Events names what was not ripe in time; a Farmer hoes it
## under and sows the new crop.
func _on_season(season: String) -> void:
	grow()
	if not WorldClock.restoring_state:
		for zone_id: int in zone_ids():
			var zone: Dictionary = _zones[zone_id]
			var late := {}
			for cell: Vector3i in zone.tiles:
				var tile: Dictionary = zone.tiles[cell]
				var key := String(tile.get("crop", ""))
				if not key.is_empty() and not bool(tile.get("ripe", false)) and key != String(zone.plan.get(season, REST)):
					late[key] = int(late.get(key, 0)) + 1
			for key: String in late:
				var crop := ContentRegistry.crop(key)
				var tiles := int(late[key])
				EventLog.post("warning", "crop_late", {"count": tiles, "crop": key, "field": zone_id, "season": season},
					{"place": (zone.cells as Array)[0], "picture": Pictures.item(String(crop.item))})
	refresh_work()


## A block set on a tile buries its plant, and a tile whose soil is dug or built over has none.
func _on_block_changed(pos: Vector3i, _old: int, new_id: int) -> void:
	if _ground.has(pos):
		_ground.erase(pos)
		_ground[pos] = ground_of(pos)
	for cell: Vector3i in [pos, pos + Vector3i.DOWN]:
		if not _cell_to_zone.has(cell): continue
		var zone: Dictionary = _zones[int(_cell_to_zone[cell])]
		var buried := (cell == pos and new_id != _tilled_id) or (cell != pos and BlockRegistry.is_solid(new_id))
		if buried and zone.tiles.has(cell): zone.tiles.erase(cell)
		_show_tile(zone, cell)
	# The sky over a field's column may have changed.
	for dy in range(1, int(config.get("sky_clearance", 10)) + 1):
		var under := pos - Vector3i(0, dy, 0)
		if not _cell_to_zone.has(under): continue
		var zone: Dictionary = _zones[int(_cell_to_zone[under])]
		if _open_sky(under): zone.roofed.erase(under)
		else: zone.roofed[under] = true


func _on_occupancy_changed(box_min: Vector3i, box_size: Vector3i) -> void:
	for zone: Dictionary in _zones.values():
		var first: Vector3i = (zone.cells as Array)[0]
		if box_min.y > first.y + 4 or box_min.y + box_size.y < first.y: continue
		zone.stale = true


## What stands on a field's tiles, counted afresh: a tile under furniture, a trunk or a stone,
## within a bush's or a flower's planting area, or under water is left alone; and the bushes
## and fruit trees the field's Farmers pick.
func _survey(zone: Dictionary) -> void:
	zone.stale = false
	var taken := {}
	var bushes := 0
	var details := get_tree().get_first_node_in_group("surface_details")
	var low := Vector3i(WorldData.WORLD_SIZE_X, 0, WorldData.WORLD_SIZE_Z)
	var high := Vector3i.ZERO
	for cell: Vector3i in zone.cells:
		low = Vector3i(mini(low.x, cell.x), cell.y, mini(low.z, cell.z))
		high = Vector3i(maxi(high.x, cell.x), cell.y, maxi(high.z, cell.z))
		if PlacedEntityRegistry.occupies(cell + Vector3i.UP) or WaterManager.has_standing_water(cell + Vector3i.UP): taken[cell] = true
	if details != null:
		var seen := {}
		for x in range(low.x - 2, high.x + 3):
			for z in range(low.z - 2, high.z + 3):
				for id: String in details.ids_in_column(Vector2i(x, z)):
					if seen.has(id): continue
					seen[id] = true
					var record: Dictionary = details.get_record(id)
					var change: Dictionary = details.get_change(id)
					if record.is_empty() or bool(change.get("removed", false)) or bool(change.get("packed", false)): continue
					var origin: Vector3i = record.origin
					if origin.y != low.y: continue
					var definition := SurfaceDetailRegistry.get_definition(String(record.definition))
					var reach := int(definition.get("planting_radius", 0))
					var width := int(definition.get("footprint", 1))
					for dx in range(-reach, width + reach):
						for dz in range(-reach, width + reach):
							var covered := origin + Vector3i(dx, 0, dz)
							if _cell_to_zone.get(covered, -1) == zone.id: taken[covered] = true
					if String(definition.get("kind", "")) == "shrub" and _cell_to_zone.get(origin, -1) == zone.id: bushes += 1
	zone.taken = taken
	zone.bushes = bushes
	# A tree stands in a field when its trunk's centre is inside the field's rectangle.
	var flora := get_tree().get_first_node_in_group("surface_flora")
	zone.trees = flora.trees_in_felling_rect(Rect2i(low.x, low.z, high.x - low.x + 1, high.z - low.z + 1)).size() \
		if flora != null and flora.has_method("trees_in_felling_rect") else 0


# ── Bushes and fruit trees in a field ─────────────────────────────────────────

## From the owner (2026-11-06): bushes in a farming zone are picked by the Farmer. Every ripe
## bush and fruit tree that stands in a field is marked for picking, as Harvest plants marks
## one, while the colony has a Farmer.
func _pick_standing() -> void:
	if _zones.is_empty() or not has_farmer(): return
	var details := get_tree().get_first_node_in_group("surface_details")
	var flora := get_tree().get_first_node_in_group("surface_flora")
	for zone: Dictionary in _zones.values():
		var low := Vector2i(WorldData.WORLD_SIZE_X, WorldData.WORLD_SIZE_Z)
		var high := Vector2i.ZERO
		for cell: Vector3i in zone.cells:
			low = Vector2i(mini(low.x, cell.x), mini(low.y, cell.z))
			high = Vector2i(maxi(high.x, cell.x), maxi(high.y, cell.z))
			if details == null: continue
			for id: String in details.ids_in_column(Vector2i(cell.x, cell.z)):
				var record: Dictionary = details.get_record(id)
				if record.is_empty() or record.origin != cell or bool(details.get_change(id).get("designated", false)): continue
				if details.accepts_tool(id, "harvest_plants"): details.designate_detail(id, "harvest_plants")
		if flora != null and flora.has_method("trees_in_harvest_rect"):
			for tree_id: Vector2i in flora.trees_in_harvest_rect(Rect2i(low, high - low + Vector2i.ONE)):
				flora.designate_harvest(tree_id)
	_claim_pickers()


## Picking in a field is its Farmers' work: every such lease takes only a Farmer, while the
## colony has one. A plant outside a field is anyone's again.
func _claim_pickers() -> void:
	for group: String in ["surface_details", "surface_flora"]:
		var holder := get_tree().get_first_node_in_group(group)
		var table: Variant = holder.get("work") if holder != null else null
		if not table is RefCounted: continue
		for key: Variant in table.sources:
			var source: RefCounted = table.sources[key]
			if int(source.get("task_type")) not in [Task.Type.HARVEST_SHRUB, Task.Type.HARVEST_TREE]: continue
			source.worker_filter = may_pick if _cell_to_zone.has(source.origin) else Callable()


func may_pick(agent: DwarfAgent) -> bool:
	return level_of(agent) > 0 or _best_level < 1


func _on_task_completed(task: Task) -> void:
	if task.type not in [Task.Type.HARVEST_SHRUB, Task.Type.HARVEST_TREE] or not _cell_to_zone.has(task.target_pos): return
	if task.attempt != null: _award(TaskManager.get_agent(int(task.attempt.worker_id)))
	_zones[int(_cell_to_zone[task.target_pos])].stale = true


# ── The field's window ────────────────────────────────────────────────────────

## What a field's window shows.
func zone_data(zone_id: int) -> Dictionary:
	var zone: Dictionary = _zones.get(zone_id, {})
	if zone.is_empty(): return {}
	if bool(zone.stale): _survey(zone)
	var order := WorldClock.season_order()
	var best := best_level()
	var plan: Array = []
	for index in range(order.size()):
		var season: String = order[index]
		var key := String(zone.plan[season])
		var crop := ContentRegistry.crop(key)
		var before: String = order[(index - 1 + order.size()) % order.size()]
		var carried: bool = not key.is_empty() and not season in crop.sow_seasons
		var note := "Nothing grows in winter" if season == "winter" else "Rest"
		if carried: note = "Sown in %s" % before
		elif not key.is_empty():
			note = "%d days, %d a tile" % [roundi(float(crop.grow_days)), int(crop.tile_yield)]
			if float(crop.get("regrow_days", 0.0)) > 0.0: note = "Picked until %s" % order[(index + int(crop.plan_seasons)) % order.size()]
			elif _spans(key, season): note = "Ripe in %s" % order[(index + 1) % order.size()]
			if season == WorldClock.season:
				var last := sow_until(zone_id, key)
				note = "Sown until %s %d" % [season.capitalize(), last] if last >= WorldClock.day else "Too late to sow more"
		var choices: Array = [{"crop": REST, "name": "Rest", "picture": "", "locked": "", "words": "Nothing is sown."}]
		for candidate: String in ContentRegistry.crops:
			var entry: Dictionary = ContentRegistry.crops[candidate]
			if not season in entry.sow_seasons: continue
			var needs := int(entry.get("farmer_level", 1))
			var keeps := float(ContentRegistry.item_def(String(entry.item)).get("food", {}).get("keeps_days", 0.0))
			choices.append({"crop": candidate, "name": String(entry.display_name), "picture": Pictures.item(String(entry.item)),
				"locked": "" if best >= needs else ("Needs a level %d Farmer" % needs if best > 0 or needs > 1 else "Needs a Farmer"),
				"words": "%d days · %d a tile · keeps %d days%s" % [roundi(float(entry.grow_days)), int(entry.tile_yield), roundi(keeps),
					" · needs damp soil" if bool(entry.get("needs_damp", false)) else ""], "idea": String(entry.get("idea", ""))})
		plan.append({"season": season, "now": season == WorldClock.season, "crop": key, "name": String(crop.get("display_name", "Rest")),
			"picture": Pictures.item(String(crop.item)) if not key.is_empty() else "", "note": note,
			"locked": "" if key.is_empty() or best >= int(crop.get("farmer_level", 1)) else "Needs a level %d Farmer" % int(crop.get("farmer_level", 1)),
			"choices": choices})
	var counts := {"tiles": zone.cells.size(), "tilled": 0, "sown": 0, "ripe": 0, "damp": 0, "alone": 0}
	var soonest := INF
	var growing_name := ""
	for cell: Vector3i in zone.cells:
		var tile: Dictionary = zone.tiles.get(cell, {})
		var key := String(tile.get("crop", ""))
		if ground_of(cell) == "tilled": counts.tilled += 1
		if is_damp(cell): counts.damp += 1
		if key.is_empty():
			if zone.roofed.has(cell) or zone.taken.has(cell): counts.alone += 1
			continue
		if bool(tile.get("ripe", false)):
			counts.ripe += 1
			continue
		counts.sown += 1
		var crop := ContentRegistry.crop(key)
		var left := float(crop.get("regrow_days", 0.0)) - float(tile.get("regrow", 0.0)) if bool(tile.get("picked", false)) \
			else float(crop.grow_days) - float(tile.get("credit", 0.0))
		if left < soonest:
			soonest = left
			growing_name = String(crop.plural_name)
	var farmers: Array = []
	for place: RefCounted in _places(zone_id):
		var agent: DwarfAgent = TaskManager.get_agent(place.reserved_by) if place.reserved_by >= 0 else null
		if agent != null: farmers.append({"name": agent.dwarf_name, "doing": Work.job_words(String(place.job), String(place.crop))})
	return {"id": zone_id, "title": "Field %d" % zone_id, "plan": plan, "counts": counts,
		"growing": "" if growing_name.is_empty() else "%s: ripe in about %d day%s" % [growing_name.capitalize(), maxi(1, ceili(soonest)), "" if ceili(soonest) <= 1 else "s"],
		"bushes": int(zone.bushes), "trees": int(zone.trees), "wet_sky": wet_sky(), "farmers": farmers, "no_farmer": best < 1}


func _build_window() -> void:
	if _window_manager == null: return   # simulation fixtures may omit the presentation layer
	_panel = FieldPanel.new()
	_panel.plan_requested.connect(func(season: String, crop_key: String): set_plan(_window_zone, season, crop_key))
	_panel.remove_requested.connect(func(): remove_zone(_window_zone))
	_window = _window_manager.register_window(WINDOW_ID, "Field", "", _panel,
		{"default_pos": Vector2(18, 48), "min_size": Vector2(420, 0), "family": "work", "flush": true})
	_window.keep_body_on_screen = true
	_window_manager.window_state_changed.connect(func(id: String, shown: bool):
		if id == WINDOW_ID and not shown: _window_zone = -1)


func open_zone_window(zone_id: int) -> void:
	_open_window(zone_id)


func _open_window(zone_id: int) -> void:
	if not _zones.has(zone_id) or _window == null: return
	_window_zone = zone_id
	_window.set_window_title("Field %d" % zone_id, "")
	_panel.show_field(zone_data(zone_id))
	_window_manager.open(WINDOW_ID)
	_settle_window.call_deferred()


## Wrapped lines settle only once the window has its width; shrink to the content then, as the
## Fishing zone's window does.
func _settle_window() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if _window != null and _window.visible: _window.reset_size()


func _close_window() -> void:
	_window_zone = -1
	if _window_manager != null: _window_manager.close(WINDOW_ID)


# ── Saving ────────────────────────────────────────────────────────────────────

func save_section_key() -> String:
	return "farming"


func save_restore_priority() -> int:
	return 36   # after terrain, storage (30) and fishing (35): the tilled soil is in place


func serialize_state() -> Dictionary:
	var zones: Array = []
	for zone_id: int in zone_ids():
		var zone: Dictionary = _zones[zone_id]
		var cells: Array = []
		for cell: Vector3i in zone.cells: cells.append(SaveManager.pack_v3i(cell))
		var tiles: Array = []
		for cell: Vector3i in zone.tiles:
			var tile: Dictionary = zone.tiles[cell]
			if String(tile.get("crop", "")).is_empty() and float(tile.get("work", 0.0)) <= 0.0: continue
			var entry := {"cell": SaveManager.pack_v3i(cell), "crop": String(tile.get("crop", "")),
				"credit": float(tile.get("credit", 0.0)), "ripe": bool(tile.get("ripe", false))}
			if bool(tile.get("picked", false)):
				entry["picked"] = true
				entry["regrow"] = float(tile.get("regrow", 0.0))
			if float(tile.get("work", 0.0)) > 0.0:
				entry["work"] = float(tile.work)
				entry["job"] = String(tile.get("job", ""))
			tiles.append(entry)
		zones.append({"id": zone_id, "cells": cells, "plan": (zone.plan as Dictionary).duplicate(), "tiles": tiles})
	return {"next_id": _next_id, "zones": zones}


func restore_state(state: Dictionary) -> void:
	for zone_id: int in zone_ids(): remove_zone(zone_id)
	_next_id = maxi(1, int(state.get("next_id", 1)))
	_grown_at = -1.0   # the clock is restored after this: growth starts afresh at the next hour
	for entry: Dictionary in state.get("zones", []):
		var cells: Array[Vector3i] = []
		for packed: Variant in entry.cells: cells.append(SaveManager.unpack_v3i(packed))
		var zone_id := create_zone(cells, int(entry.id), entry.get("plan", {}), true)
		if zone_id < 0: continue
		var zone: Dictionary = _zones[zone_id]
		for saved: Dictionary in entry.get("tiles", []):
			var cell := SaveManager.unpack_v3i(saved.cell)
			if not _cell_to_zone.get(cell, -1) == zone_id: continue
			var tile := {"crop": String(saved.crop), "credit": float(saved.credit), "ripe": bool(saved.ripe)}
			if bool(saved.get("picked", false)):
				tile["picked"] = true
				tile["regrow"] = float(saved.get("regrow", 0.0))
			if float(saved.get("work", 0.0)) > 0.0:
				tile["work"] = float(saved.work)
				tile["job"] = String(saved.get("job", ""))
			zone.tiles[cell] = tile
			_show_tile(zone, cell)


func _on_slice_changed(new_slice_y: int) -> void:
	_tool.set_slice(new_slice_y)
	_visuals.apply_slice(new_slice_y)
