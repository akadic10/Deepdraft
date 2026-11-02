extends Node3D

## Fishing zones (doc 289): the Zones menu's Fishing tool, the zones it paints along a shore,
## each generated water's fish stock, and the work they post. A zone's cells are floor cells
## (NavGrid's convention) with fishable water in front of them, and each is a spot for one
## fisher (FishingSpot.gd, a surface work source). A zone wants fish while the colony keeps
## fewer than its Keep and its water is not Fished out; while it does, every free spot posts
## one FISH lease. A catch lands at the fisher's feet and comes off the water's stock, which
## regrows a share of its maximum each day. Zones and stocks save as the `fishing` section.
##
## The tool behaves as Storage's does (StockpileDesignationController): Esc exits, a drag
## paints a flat rectangle on the anchor's plane, a click on a zone opens its window (with the
## tool off too), and right mouse stays the camera's.

@export var dock_ui_path: NodePath
@export var slice_controller_path: NodePath
@export var window_manager_path: NodePath

const TOOL_ID := "fishing_zone"
const WINDOW_ID := "fishing_zone_info"
const Picking = preload("res://scripts/components/ObjectPicking.gd")
const Spot = preload("res://scripts/components/FishingSpot.gd")
const Sources = preload("res://scripts/components/WorkSourceTable.gd")
const Inventory = preload("res://scripts/components/ColonyInventory.gd")
const ZonePanel = preload("res://scripts/ui/FishingZonePanel.gd")
const CatchLog = preload("res://scripts/components/CatchLog.gd")
const WORLD_EDGE_MARGIN := 2
const RAY_MAX := 700.0
const OVERLAY_LIFT := 1.04
const EDGE_INSET := 0.08
const DRAG_THRESHOLD_PX := 6.0
const REFRESH_SECONDS := 1.0
const NOWHERE := Vector3i(-1, -1, -1)
const DIRECTIONS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
# Teal, so a fishing zone never reads as storage (blue) or mining (yellow).
const COLOR_VALID := Color(0.30, 0.78, 0.74, 0.30)
const COLOR_VALID_EDGE := Color(0.45, 0.92, 0.86, 0.85)
const COLOR_INVALID := Color(1.00, 0.30, 0.25, 0.35)
const COLOR_ZONE := Color(0.30, 0.78, 0.74, 0.22)
const COLOR_ZONE_EDGE := Color(0.45, 0.92, 0.86, 0.60)

signal tool_active_changed(active: bool)
signal order_created(receipt: Dictionary)
signal zone_created(zone_id: int)
signal zone_removed(zone_id: int)

var config: Dictionary = {}
var _dock_ui: Node
var _window_manager: UIWindowManager
var _window: UIWindow
var _panel: Control
var _window_zone := -1
var _active := false
var _dragging := false
var _anchor := NOWHERE
var _drag_start := Vector2.ZERO
var _hover := NOWHERE
var _hover_reason := ""
var _preview: Array[Vector3i] = []
var _pointer := Vector2.INF
var _slice_y: int = SliceController.MAX_SLICE_Y
var _material: StandardMaterial3D
var _preview_mesh: MeshInstance3D
var _next_id := 1
## Zone id -> {"id": int, "cells": Array[Vector3i], "keep": int, "water": String}.
var _zones: Dictionary = {}
var _overlays: Dictionary = {}       # zone id -> MeshInstance3D
var _cell_to_zone: Dictionary = {}   # floor cell -> zone id
## Water id -> {"fish": float, "day": float}: the stock when last counted, on that day.
var _stocks: Dictionary = {}
var _maximum: Dictionary = {}        # water id -> its full stock
var _pool: Dictionary = {}           # the spring cave's pool: column -> Vector2i(lowest, highest)
var _spots: RefCounted               # WorkSourceTable keyed by floor cell
var _refresh_left := 0.0


func _ready() -> void:
	add_to_group("fishing_system")
	add_to_group(SaveManager.OWNER_GROUP)
	config = TaskManager.get_config_section("fishing")
	_spots = Sources.new()
	_dock_ui = get_node_or_null(dock_ui_path)
	_window_manager = get_node_or_null(window_manager_path) as UIWindowManager
	if _dock_ui != null:
		if _dock_ui.has_method("register_fishing_controller"): _dock_ui.call("register_fishing_controller", self)
		if _dock_ui.has_signal("tool_requested"): _dock_ui.connect("tool_requested", _on_tool_requested)
	var slice := get_node_or_null(slice_controller_path)
	if slice != null and slice.has_signal("slice_changed"): slice.connect("slice_changed", _on_slice_changed)
	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_build_window()


func _process(delta: float) -> void:
	if _active: _update_hover()
	_refresh_left -= delta
	if _refresh_left > 0.0: return
	_refresh_left = REFRESH_SECONDS
	refresh_work()
	if _window_zone > 0 and _window != null and _window.visible: _panel.show_zone(zone_data(_window_zone))


func _input(event: InputEvent) -> void:
	if event is InputEventMouse: _pointer = event.position
	if not _dragging: return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		if get_viewport().gui_get_hovered_control() == null:
			_update_hover()
			_on_left_release(event.position)
		else:
			_end_drag()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT and _dragging: _end_drag()


func _unhandled_input(event: InputEvent) -> void:
	if not _active:
		# A zone stays click-selectable with the tool off, so its window (and Remove) is
		# always reachable, as Storage's is.
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT \
				and try_select_zone_at_screen(event.position):
			get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		deactivate()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_update_hover()
			_on_left_press(event.position)
			get_viewport().set_input_as_handled()
		elif _dragging:
			_on_left_release(event.position)
			get_viewport().set_input_as_handled()


# ── The tool ──────────────────────────────────────────────────────────────────

func is_active() -> bool:
	return _active


func activate() -> void:
	if _active or not bool(WorldGenerator.get_streaming_stats().get("maps_ready", false)): return
	_active = true
	_ensure_preview_mesh()
	tool_active_changed.emit(true)


func deactivate() -> void:
	if not _active: return
	_active = false
	_end_drag()
	tool_active_changed.emit(false)


func _on_tool_requested(tool_id: String) -> void:
	if tool_id == TOOL_ID:
		if _active: deactivate()
		else: activate()
	elif _active:
		deactivate()


## What the tool bar shows (doc 23, "The tool bar"): the cells a drag takes, or why the cell
## under the pointer can't be fished from.
func tool_bar_state() -> Dictionary:
	var state := {"tool": TOOL_ID}
	if _dragging:
		state.selection = {"count": "%d spot%s" % [_preview.size(), "" if _preview.size() == 1 else "s"],
			"detail": "Each spot takes one fisher", "at": _pointer}
	elif _hover != NOWHERE and not _hover_reason.is_empty() and not _cell_to_zone.has(_hover):
		state.selection = {"count": "Can't fish here", "detail": _hover_reason, "short": true, "at": _pointer}
	return state


## The tool bar's last order (View and Undo): the zone a drag made, while it stands.
func order_is_pending(receipt: Dictionary) -> bool:
	return _zones.has(int(receipt.get("zone_id", -1)))


func undo_order(receipt: Dictionary) -> int:
	if not order_is_pending(receipt): return 0
	var count: int = _zones[int(receipt.zone_id)].cells.size()
	remove_zone(int(receipt.zone_id))
	return count


func inspect_order(receipt: Dictionary) -> void:
	if order_is_pending(receipt): _open_window(int(receipt.zone_id))


func _on_left_press(screen_pos: Vector2) -> void:
	if _cell_to_zone.has(_hover):
		_open_window(int(_cell_to_zone[_hover]))
		return
	if not _hover_reason.is_empty() or _hover == NOWHERE: return
	_dragging = true
	_anchor = _hover
	_drag_start = screen_pos
	_rebuild_preview()


func _on_left_release(screen_pos: Vector2) -> void:
	_dragging = false
	if screen_pos.distance_to(_drag_start) < DRAG_THRESHOLD_PX:
		var single: Array[Vector3i] = []
		if spot_reason(_anchor).is_empty(): single.append(_anchor)
		_preview = single
	if not _preview.is_empty():
		var zone_id := create_zone(_preview.duplicate())
		if zone_id > 0:
			order_created.emit({"zone_id": zone_id, "message": "Fishing zone · %d spot%s" % [_preview.size(), "" if _preview.size() == 1 else "s"]})
	_end_drag()


func _end_drag() -> void:
	_dragging = false
	_preview.clear()
	if _preview_mesh != null: _preview_mesh.visible = false


func _update_hover() -> void:
	var hit := _surface_cell_for(get_viewport().get_mouse_position() if _pointer == Vector2.INF else _pointer)
	if hit.is_empty():
		_hover = NOWHERE
		_hover_reason = ""
		if not _dragging and _preview_mesh != null: _preview_mesh.visible = false
		return
	var cell := Vector3i(int(hit.x), int(hit.y), int(hit.z))
	if _dragging: cell.y = _anchor.y   # the marquee lives on the anchor's plane
	if cell == _hover and _preview_mesh != null and _preview_mesh.visible: return
	_hover = cell
	_hover_reason = spot_reason(cell)
	_rebuild_preview()


func _rebuild_preview() -> void:
	_ensure_preview_mesh()
	if _dragging:
		_preview = _marquee_cells(_anchor, _hover)
		_draw_cells(_preview_mesh, _preview, COLOR_VALID, COLOR_VALID_EDGE, _anchor.y)
	else:
		var valid := _hover_reason.is_empty() and not _cell_to_zone.has(_hover)
		var cells: Array[Vector3i] = [_hover]
		_draw_cells(_preview_mesh, cells, COLOR_VALID if valid else COLOR_INVALID, COLOR_VALID_EDGE if valid else COLOR_INVALID, _hover.y)
	_preview_mesh.visible = _hover.x >= 0


## The flat rectangle between the anchor and the pointer, its fishable cells only.
func _marquee_cells(anchor: Vector3i, current: Vector3i) -> Array[Vector3i]:
	var extent := int(config.get("max_zone_extent", 16))
	var low := Vector2i(mini(anchor.x, current.x), mini(anchor.z, current.z))
	var high := Vector2i(maxi(anchor.x, current.x), maxi(anchor.z, current.z))
	if anchor.x == low.x: high.x = mini(high.x, low.x + extent - 1)
	else: low.x = maxi(low.x, high.x - extent + 1)
	if anchor.z == low.y: high.y = mini(high.y, low.y + extent - 1)
	else: low.y = maxi(low.y, high.y - extent + 1)
	var water := water_of_spot(anchor)
	var cells: Array[Vector3i] = []
	for x in range(low.x, high.x + 1):
		for z in range(low.y, high.y + 1):
			var cell := Vector3i(x, anchor.y, z)
			if spot_reason(cell).is_empty() and water_of_spot(cell) == water: cells.append(cell)
	return cells


# ── Spots and water ───────────────────────────────────────────────────────────

## Why a floor cell can't be a fishing spot, or "" when it can: a dwarf can stand on it, and a
## generated water lies in front, deep enough, at its feet or below.
func spot_reason(cell: Vector3i) -> String:
	if cell.x < WORLD_EDGE_MARGIN or cell.x >= WorldData.WORLD_SIZE_X - WORLD_EDGE_MARGIN \
			or cell.z < WORLD_EDGE_MARGIN or cell.z >= WorldData.WORLD_SIZE_Z - WORLD_EDGE_MARGIN or cell.y <= 3:
		return "Too near the world's edge"
	if _cell_to_zone.has(cell): return "Already a fishing spot"
	# A cave not yet found is rock to every tool (Hard Rule 11).
	if InteriorTracker.is_hidden_cave(cell + Vector3i.UP): return "Nobody has found this place"
	var column := Vector2i(cell.x, cell.z)
	if WorldGenerator.lake_columns.has(column) or WorldGenerator.tarn_columns.has(column) or WaterManager.depth_at(cell + Vector3i.UP) > 0.0:
		return "Fishers stand on the shore, not in the water"
	var stockpiles := get_tree().get_first_node_in_group("stockpile_controller")
	if stockpiles != null and stockpiles.is_zone_cell(cell): return "A storage zone is here"
	var furniture := get_tree().get_first_node_in_group("furniture_controller")
	if furniture != null and furniture.has_method("blocks_zone_cell") and bool(furniture.call("blocks_zone_cell", cell)):
		return "Furniture stands here"
	if not NavGrid.is_walkable(cell): return "A dwarf can't stand here"
	if water_in_front(cell) == NOWHERE:
		return "This water has no fish" if _cast_cell(cell, false) != NOWHERE else "No water in front"
	return ""


## The water cell a fisher on `cell` casts into: the farthest within reach, straight out from
## the shore, that is deep enough and in a generated water; NOWHERE if there is none.
func water_in_front(cell: Vector3i) -> Vector3i:
	return _cast_cell(cell, true)


## With `fishing_only` false, any water deep enough counts, for the tool's reason.
func _cast_cell(cell: Vector3i, fishing_only: bool) -> Vector3i:
	var reach := int(config.get("reach", 2))
	for step: Vector2i in DIRECTIONS:
		var found := NOWHERE
		for distance in range(1, reach + 1):
			var column := Vector2i(cell.x, cell.z) + step * distance
			var wet := _wet_cell(Vector3i(column.x, cell.y, column.y))
			# A cave not yet found is rock to every tool (Hard Rule 11).
			if wet == NOWHERE or InteriorTracker.is_hidden_cave(wet): break
			if fishing_only and water_of_cell(wet).is_empty(): break
			found = wet
		if found != NOWHERE: return found
	return NOWHERE


## Water deep enough in the column of `at`, from the fisher's feet down to bank_drop blocks below
## them (rivers run in channels); the line can't reach it through ground.
func _wet_cell(at: Vector3i) -> Vector3i:
	var depth := float(config.get("min_depth", 0.5))
	for y in range(at.y + 1, at.y - int(config.get("bank_drop", 4)) - 1, -1):
		var cell := Vector3i(at.x, y, at.z)
		if WaterManager.depth_at(cell) >= depth: return cell
		if BlockRegistry.is_solid(WorldData.get_live_block(cell.x, cell.y, cell.z)): return NOWHERE
	return NOWHERE


## Which generated water a cast cell belongs to: the lake, then the tarn, the spring cave's pool
## and the river, so where two meet the first wins. "" for water the colony made.
func water_of_cell(cell: Vector3i) -> String:
	var waters: Dictionary = config.get("waters", {})
	var column := Vector2i(cell.x, cell.z)
	if waters.has("lake") and WorldGenerator.lake_columns.has(column): return "lake"
	if waters.has("tarn") and WorldGenerator.tarn_columns.has(column): return "tarn"
	if waters.has("spring_cave") and _cave_pool().has(column):
		var span: Vector2i = _cave_pool()[column]
		if cell.y >= span.x - 1 and cell.y <= span.y + 1: return "spring_cave"
	if waters.has("river") and WorldGenerator.river_layout.get("columns", {}).has(column): return "river"
	return ""


## The spring cave's pool by column: the lowest and highest cell its water was seeded in.
func _cave_pool() -> Dictionary:
	if _pool.is_empty():
		for cell: Vector3i in WorldGenerator.spring_cave.get("water", {}):
			var column := Vector2i(cell.x, cell.z)
			var span: Vector2i = _pool.get(column, Vector2i(cell.y, cell.y))
			_pool[column] = Vector2i(mini(span.x, cell.y), maxi(span.y, cell.y))
	return _pool


func water_of_spot(cell: Vector3i) -> String:
	var wet := water_in_front(cell)
	return "" if wet == NOWHERE else water_of_cell(wet)


## Where the float rests: on the water's surface above the cast cell.
func _float_point(spot: RefCounted) -> Vector3:
	var top: Vector3i = spot.water
	while WaterManager.depth_at(top + Vector3i.UP) > 0.0: top += Vector3i.UP
	return Vector3(top.x + .5, top.y + WaterManager.depth_at(top), top.z + .5)


# ── Stocks ────────────────────────────────────────────────────────────────────

## A water's full stock: its cells times stock_per_cell.
func maximum(water: String) -> int:
	if not _maximum.has(water):
		var per_cell := float(config.get("waters", {}).get(water, {}).get("stock_per_cell", 0.0))
		_maximum[water] = maxi(1, roundi(_size_of(water) * per_cell))
	return int(_maximum[water])


## The lake's and tarn's surface columns, the river's columns, the spring cave's water cells.
func _size_of(water: String) -> int:
	match water:
		"lake": return WorldGenerator.lake_columns.size()
		"tarn": return WorldGenerator.tarn_columns.size()
		"river": return WorldGenerator.river_layout.get("columns", {}).size()
		"spring_cave": return WorldGenerator.spring_cave.get("water", {}).size()
	return 0


## Fish in a water now: the last count plus what has regrown since, never above its maximum.
func stock(water: String) -> float:
	var full := float(maximum(water))
	var today := WorldClock.elapsed_days()
	var entry: Dictionary = _stocks.get(water, {"fish": full, "day": today})
	var fish := minf(full, float(entry.fish) + full * float(config.get("regrowth_per_day", 0.03)) * maxf(0.0, today - float(entry.day)))
	_stocks[water] = {"fish": fish, "day": today}
	return fish


func fished_out(water: String) -> bool:
	return stock(water) < float(config.get("fished_out_share", 0.1)) * maximum(water)


## Plenty, Some, Few or Fished out, for the zone's window.
func stock_word(water: String) -> String:
	var share := stock(water) / float(maximum(water))
	if share < float(config.get("fished_out_share", 0.1)): return "Fished out"
	return "Plenty" if share >= 0.7 else ("Some" if share >= 0.35 else "Few")


func water_item(water: String) -> String:
	return String(config.get("waters", {}).get(water, {}).get("item", ""))


func water_name(water: String) -> String:
	return String(config.get("waters", {}).get(water, {}).get("name", "Water"))


## Fish of a water's kind the colony keeps now, stored or lying loose.
func kept_fish(water: String) -> int:
	return Inventory.available(ItemDropManager.find(get_tree()), water_item(water))


# ── Zones and their work ──────────────────────────────────────────────────────

## Paints a zone over `cells` (every one a spot, all on one water). Returns its id, or -1.
func create_zone(cells: Array[Vector3i], requested_id := -1, keep := -1) -> int:
	var kept: Array[Vector3i] = []
	var water := ""
	for cell: Vector3i in cells:
		if _cell_to_zone.has(cell) or water_in_front(cell) == NOWHERE: continue
		var cell_water := water_of_spot(cell)
		if water.is_empty(): water = cell_water
		if cell_water == water: kept.append(cell)
	if kept.is_empty(): return -1
	var zone_id := requested_id if requested_id > 0 else _next_id
	_next_id = maxi(_next_id, zone_id + 1)
	_zones[zone_id] = {"id": zone_id, "cells": kept, "water": water,
		"keep": keep if keep >= 0 else int(config.get("keep_default", 20))}
	for cell: Vector3i in kept:
		_cell_to_zone[cell] = zone_id
		_add_spot(zone_id, cell)
	var overlay := MeshInstance3D.new()
	overlay.name = "FishingZone_%d" % zone_id
	add_child(overlay)
	_draw_cells(overlay, kept, COLOR_ZONE, COLOR_ZONE_EDGE, kept[0].y)
	overlay.visible = kept[0].y <= _slice_y
	_overlays[zone_id] = overlay
	zone_created.emit(zone_id)
	refresh_work()
	return zone_id


func remove_zone(zone_id: int) -> void:
	if not _zones.has(zone_id): return
	for cell: Vector3i in _zones[zone_id].cells:
		_spots.retire(cell, true)   # a fisher at work stops; nothing is lost (Hard Rule 12)
		_cell_to_zone.erase(cell)
	_zones.erase(zone_id)
	if _overlays.has(zone_id):
		(_overlays[zone_id] as Node).queue_free()
		_overlays.erase(zone_id)
	if _window_zone == zone_id: _close_window()
	zone_removed.emit(zone_id)


## Changes how many fish a zone keeps, by whole steps, within 0 and keep_max.
func step_keep(zone_id: int, steps: int) -> void:
	if not _zones.has(zone_id): return
	var step := int(config.get("keep_step", 5))
	_zones[zone_id].keep = clampi(int(_zones[zone_id].keep) + steps * step, 0, int(config.get("keep_max", 200)))
	refresh_work()
	if _window_zone == zone_id: _panel.show_zone(zone_data(zone_id))


func _add_spot(zone_id: int, cell: Vector3i) -> void:
	var spot := Spot.new()
	spot.zone_id = zone_id
	spot.origin = cell
	spot.water = water_in_front(cell)
	spot.item = water_item(String(_zones[zone_id].water))
	spot.duration = _catch_seconds(spot)
	spot.roll = _big_roll(spot)
	spot.complete_callback = _land.bind(spot)
	spot.float_callback = _float_point.bind(spot)
	spot.feedback_visible_callback = func() -> bool: return spot.origin.y <= _slice_y
	spot.big_callback = func(dwarf_id: int) -> bool: return big_catch(spot, TaskManager.get_agent(dwarf_id))
	spot.rate_callback = patience
	_spots.add(cell, spot)


## A zone wants fish while its water isn't Fished out and the colony keeps fewer than its Keep.
func wants_fish(zone_id: int) -> bool:
	var zone: Dictionary = _zones.get(zone_id, {})
	if zone.is_empty() or fished_out(zone.water): return false
	return kept_fish(zone.water) < int(zone.keep)


## Every spot of a zone that wants fish posts one lease; the others withdraw theirs. A spot whose
## water has gone (drained) or whose ground no longer holds a dwarf waits.
func refresh_work() -> void:
	for zone_id: int in _zones:
		var wants := wants_fish(zone_id)
		for cell: Vector3i in _zones[zone_id].cells:
			var spot: RefCounted = _spots.get_source(cell)
			if spot == null: continue
			var water := water_in_front(cell) if wants else NOWHERE
			if water != NOWHERE and spot.reserved_by < 0: spot.water = water
			spot.state.designated = water != NOWHERE and NavGrid.is_walkable(cell)
			if spot.state.designated: spot.ensure_lease()
			else: spot.withdraw_lease()


## The catch: one fish of the water's kind at the fisher's feet, or two for a Ranger's big one
## (doc 292), one fewer in the water either way; the Ranger's experience and catch log; and the
## next catch's time and roll.
func _land(dwarf_id: int, spot: RefCounted) -> bool:
	var zone: Dictionary = _zones.get(spot.zone_id, {})
	if zone.is_empty(): return false
	var water: String = zone.water
	var fish := stock(water)
	var big := false
	if fish >= 1.0:
		var agent := TaskManager.get_agent(dwarf_id)
		big = big_catch(spot, agent)   # at the level the catch was made, before its award
		_stocks[water].fish = fish - 1.0
		var drops := ItemDropManager.find(get_tree())
		if drops != null: drops.spawn_drop(water_item(water), 2 if big else 1, spot.origin + Vector3i.UP)
		# Awarded before the lease can end, as a Miner's last block counts.
		if is_instance_valid(agent) and DwarfAssets.earns_by(agent.profession, "FISH"):
			agent.profession_experience[agent.profession] = maxi(0, int(agent.profession_experience.get(agent.profession, 0))) + 1
			CatchLog.record_catch(agent.catch_log, water_item(water), big, floori(WorldClock.elapsed_days()))
	spot.state.work_seconds = 0.0
	spot.duration = _catch_seconds(spot)
	spot.roll = _big_roll(spot)
	print("FishingSystem: dwarf %d landed a %s%s at %s; %s has %.1f." % [dwarf_id, "big " if big else "", water_item(water), spot.origin, water, stock(water)])
	spot.state.designated = wants_fish(spot.zone_id)
	return true


## Whether a spot's catch is this fisher's big fish: its seeded roll under the chance their
## level gives (doc 292). Never for a dwarf whose career has none.
func big_catch(spot: RefCounted, agent: DwarfAgent) -> bool:
	if not is_instance_valid(agent): return false
	return spot.roll < float(DwarfAssets.level_reward(agent.profession, agent.profession_experience, "big_chance", 0.0))


## A catch's roll for a big fish, seeded as its time is.
func _big_roll(spot: RefCounted) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([WorldGenerator.world_seed, spot.origin, int(stock(String(_zones.get(spot.zone_id, {}).get("water", "lake"))) * 10.0), "big"])
	return rng.randf()


## How much faster a Ranger's patience makes this season's catches: the season's speed their
## level gives (winter 0.75 from level 3) over the water's own, never slower; 1 without.
func patience(dwarf_id: int) -> float:
	var agent := TaskManager.get_agent(dwarf_id)
	if not is_instance_valid(agent): return 1.0
	var season := String(WorldClock.season)
	var own := maxf(0.05, float(config.get("season_speed", {}).get(season, 1.0)))
	var patient: Dictionary = DwarfAssets.level_reward(agent.profession, agent.profession_experience, "season_speed", {})
	return maxf(1.0, float(patient.get(season, own)) / own)


## Whether the colony has a dwarf whose career fishes (a Ranger), busy or not.
func has_fisher() -> bool:
	for agent: DwarfAgent in TaskManager.get_agents():
		if is_instance_valid(agent) and Task.Type.FISH in DwarfAssets.profession_task_types(agent.profession): return true
	return false


## Work seconds for a spot's next catch: catch_hours on a full water in spring, slower in the
## other seasons (season_speed), up to low_stock_factor times as long near Fished out, with a
## seeded spread. Wisdom speeds the work itself (DwarfWorkExecution, "fishing").
func _catch_seconds(spot: RefCounted) -> float:
	var zone: Dictionary = _zones.get(spot.zone_id, {})
	var water: String = zone.get("water", "lake")
	var low := float(config.get("fished_out_share", 0.1))
	var plenty := clampf((stock(water) / float(maximum(water)) - low) / maxf(0.001, 1.0 - low), 0.0, 1.0)
	var season := maxf(0.05, float(config.get("season_speed", {}).get(String(WorldClock.season), 1.0)))
	var hours := float(config.get("catch_hours", 1.0)) * lerpf(float(config.get("low_stock_factor", 3.0)), 1.0, plenty) / season
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([WorldGenerator.world_seed, spot.origin, int(stock(water) * 10.0)])
	var spread := float(config.get("catch_spread", 0.2))
	return hours * WorldClock.get_real_seconds_per_game_hour() * rng.randf_range(1.0 - spread, 1.0 + spread)


func is_zone_cell(cell: Vector3i) -> bool:
	return _cell_to_zone.has(cell)


func zone_ids() -> Array:
	var ids := _zones.keys()
	ids.sort()
	return ids


func spot_at(cell: Vector3i) -> RefCounted:
	return _spots.get_source(cell)


## What a zone's window shows.
func zone_data(zone_id: int) -> Dictionary:
	var zone: Dictionary = _zones.get(zone_id, {})
	if zone.is_empty(): return {}
	var water: String = zone.water
	var item := water_item(water)
	var definition: Dictionary = ItemDropManager.find(get_tree()).get_item_def(item) if ItemDropManager.find(get_tree()) != null else {}
	var fishers: Array = []
	for cell: Vector3i in zone.cells:
		var spot: RefCounted = _spots.get_source(cell)
		var task := TaskManager.get_task(spot.lease_id) if spot != null and spot.lease_id >= 0 else null
		if task == null or task.assigned_to < 0: continue
		var agent := TaskManager.get_agent(task.assigned_to)
		if agent == null: continue
		var casting: bool = agent.current_cell() == cell and not agent.is_walking()
		fishers.append({"name": agent.dwarf_name, "doing": "casting" if casting else "walking to the shore"})
	return {"id": zone_id, "title": "Fishing Zone %d" % zone_id, "water": water_name(water),
		"item": item, "fish_name": String(definition.get("display_name", "Fish")),
		"keeps_days": float(definition.get("food", {}).get("keeps_days", 0.0)),
		"picture": Inventory.thumbnail_path(item), "stock": int(stock(water)), "maximum": maximum(water),
		"word": stock_word(water), "regrowth": float(config.get("regrowth_per_day", 0.03)) * maximum(water),
		"fished_out_below": ceili(float(config.get("fished_out_share", 0.1)) * maximum(water)),
		"keep": int(zone.keep), "kept": kept_fish(water), "wants": wants_fish(zone_id),
		"spots": zone.cells.size(), "fishers": fishers, "no_fisher": not has_fisher()}


# ── Saving ────────────────────────────────────────────────────────────────────

func save_section_key() -> String:
	return "fishing"


func save_restore_priority() -> int:
	return 35   # after storage (30), so kept fish are counted from restored stores


func serialize_state() -> Dictionary:
	var zones: Array = []
	for zone_id: int in zone_ids():
		var cells: Array = []
		for cell: Vector3i in _zones[zone_id].cells: cells.append(SaveManager.pack_v3i(cell))
		zones.append({"id": zone_id, "cells": cells, "keep": int(_zones[zone_id].keep)})
	var stocks := {}
	for water: String in _stocks:
		stocks[water] = {"fish": stock(water), "day": float(_stocks[water].day)}
	return {"next_id": _next_id, "zones": zones, "stocks": stocks}


func restore_state(state: Dictionary) -> void:
	for zone_id: int in zone_ids(): remove_zone(zone_id)
	_stocks.clear()
	for water: String in state.get("stocks", {}):
		var entry: Dictionary = state.stocks[water]
		_stocks[water] = {"fish": float(entry.fish), "day": float(entry.day)}
	_next_id = maxi(1, int(state.get("next_id", 1)))
	for entry: Dictionary in state.get("zones", []):
		var cells: Array[Vector3i] = []
		for packed: Variant in entry.cells: cells.append(SaveManager.unpack_v3i(packed))
		create_zone(cells, int(entry.id), int(entry.keep))


# ── The zone's window ─────────────────────────────────────────────────────────

func _build_window() -> void:
	if _window_manager == null: return   # simulation fixtures may omit the presentation layer
	_panel = ZonePanel.new()
	_panel.keep_step_requested.connect(func(steps: int): step_keep(_window_zone, steps))
	_panel.remove_requested.connect(func(): remove_zone(_window_zone))
	_window = _window_manager.register_window(WINDOW_ID, "Fishing", "", _panel,
		{"default_pos": Vector2(18, 48), "min_size": Vector2(420, 0), "family": "work", "flush": true})
	_window.keep_body_on_screen = true
	_window_manager.window_state_changed.connect(func(id: String, shown: bool):
		if id == WINDOW_ID and not shown: _window_zone = -1)


func try_select_zone_at_screen(screen_pos: Vector2) -> bool:
	var hit := _surface_cell_for(screen_pos)
	if hit.is_empty(): return false
	var cell := Vector3i(int(hit.x), int(hit.y), int(hit.z))
	if not _cell_to_zone.has(cell): return false
	_open_window(int(_cell_to_zone[cell]))
	return true


func open_zone_window(zone_id: int) -> void:
	_open_window(zone_id)


func _open_window(zone_id: int) -> void:
	if not _zones.has(zone_id) or _window == null: return
	_window_zone = zone_id
	_window.set_window_title("Fishing Zone %d" % zone_id, "")
	_panel.show_zone(zone_data(zone_id))
	_window_manager.open(WINDOW_ID)
	_settle_window.call_deferred()


## Wrapped lines settle only once the window has its width; shrink to the content then, as the
## Professions window does.
func _settle_window() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if _window != null and _window.visible: _window.reset_size()


func _close_window() -> void:
	_window_zone = -1
	if _window_manager != null: _window_manager.close(WINDOW_ID)


# ── Drawing and picking ───────────────────────────────────────────────────────

func _ensure_preview_mesh() -> void:
	if _preview_mesh != null: return
	_preview_mesh = MeshInstance3D.new()
	_preview_mesh.name = "FishingPreview"
	add_child(_preview_mesh)


## Flat quads over the cells' floor, with a strip along the outside edges.
func _draw_cells(target: MeshInstance3D, cells: Array[Vector3i], fill: Color, edge: Color, plane_y: int) -> void:
	var mesh := ImmediateMesh.new()
	if not cells.is_empty():
		var y := float(plane_y) + OVERLAY_LIFT
		var cell_set := {}
		for cell: Vector3i in cells: cell_set[cell] = true
		mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		for cell: Vector3i in cells:
			var x := float(cell.x)
			var z := float(cell.z)
			_quad(mesh, x, z, 1.0, 1.0, y, fill)
			if not cell_set.has(cell + Vector3i(-1, 0, 0)): _quad(mesh, x, z, EDGE_INSET, 1.0, y + .005, edge)
			if not cell_set.has(cell + Vector3i(1, 0, 0)): _quad(mesh, x + 1.0 - EDGE_INSET, z, EDGE_INSET, 1.0, y + .005, edge)
			if not cell_set.has(cell + Vector3i(0, 0, -1)): _quad(mesh, x, z, 1.0, EDGE_INSET, y + .005, edge)
			if not cell_set.has(cell + Vector3i(0, 0, 1)): _quad(mesh, x, z + 1.0 - EDGE_INSET, 1.0, EDGE_INSET, y + .005, edge)
		mesh.surface_end()
	target.mesh = mesh
	target.material_override = _material


func _quad(mesh: ImmediateMesh, x: float, z: float, w: float, d: float, y: float, color: Color) -> void:
	for corner: Vector2 in [Vector2(x, z), Vector2(x + w, z), Vector2(x + w, z + d), Vector2(x, z), Vector2(x + w, z + d), Vector2(x, z + d)]:
		mesh.surface_set_color(color)
		mesh.surface_add_vertex(Vector3(corner.x, y, corner.y))


## The first slice-visible solid block under a screen point, as the slice shows it (a cave not
## yet found is rock): the floor cell, NavGrid's convention.
func _surface_cell_for(screen_pos: Vector2) -> Dictionary:
	var camera := get_viewport().get_camera_3d()
	if camera == null: return {}
	return Picking.terrain_hit(camera.project_ray_origin(screen_pos), camera.project_ray_normal(screen_pos).normalized(),
		_slice_y, RAY_MAX, Picking.concealed_block)


func _on_slice_changed(new_slice_y: int) -> void:
	_slice_y = new_slice_y
	for zone_id: int in _overlays:
		(_overlays[zone_id] as Node3D).visible = int((_zones[zone_id].cells as Array)[0].y) <= _slice_y
