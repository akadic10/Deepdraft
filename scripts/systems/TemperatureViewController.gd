extends Node3D

## The Temperature view (doc 23 "The Temperature view"; doc 282): a view toggle between Appeal
## and X-ray at the dock's end. While it is on:
## - the world dims and greys (the Appeal view's appeal_dim.gdshader pass);
## - every floor in view takes its temperature word's colour: each column's top floor at or
##   under the slice, and the floors of sealed rooms and of dug tunnels below it, which X-ray
##   shows. The cut rock stays dim, and caves the colony has not found count as rock (Hard
##   Rule 11);
## - hovering a spot shows a card: its temperature and word, what sets it (steps from open
##   air, blocks overhead, a room's fires) and its range over a year; over the cut rock, what a
##   room dug there would be. Clicking a room's floor opens the room window
##   (ObjectExplorerController's terrain clicks reach it as they reach zones).
## The Appeal view and this one take turns: turning one on turns the other off.
## Nothing heavy runs each frame. Floors are built in 16 x 16-column tiles round the point the
## camera looks at, nearest first, a column or a floor at a time within a small budget a
## frame. Each floor quad carries its base temperature and its shares of the season and of
## the day and weather, and the shader turns them into a colour from two values set once a
## game hour and when the weather changes. A tile is built again only when it comes into
## range or the slice moves (keeping its floors' numbers), or when blocks, doors or a room's
## heat change near it, gathered for a moment first. Presentation only, never saved:
## RoomManager's climate works out every temperature (doc 34).
const Xray = preload("res://scripts/systems/XrayController.gd")
const Picking = preload("res://scripts/components/ObjectPicking.gd")
const DIM_SHADER := preload("res://scripts/shaders/appeal_dim.gdshader")
const TINT_SHADER := preload("res://scripts/shaders/temperature_view.gdshader")
## Seen by the normal camera and by X-ray's, as the Appeal view's pieces.
const LAYERS := 1 | Xray.XRAY_LAYER | Xray.TERRAIN_LAYER
const TILE := 16
const RAY_MAX := 600.0
const NO_TILE := Vector2i.MIN
## The card sits over the dock and the clock, under menus and toasts (DockUI's layers).
const CARD_LAYER := 22
## The words' colours in time_slice.json, coldest first.
const WORDS := ["frozen", "cold", "chilly", "comfortable", "hot"]
@export var dock_path: NodePath
@export var slice_path: NodePath
@export var rooms_tool_path: NodePath
## Click tools: while one is on, the view shows no hover card.
@export var tool_paths: Array[NodePath] = []
signal changed
var active := false
var dock: Node
var slice: Node
var rooms_tool: Node
## Built tiles: Vector2i -> {node: MultiMeshInstance3D, values: {floor air cell: Vector4},
## rooms: the cells of those floors that are sealed rooms'}. A floor's numbers are its base
## temperature, its season share, its day-and-weather share and 1 on a sealed room's floor.
var tiles := {}
var builds := 0            # tiles built since the view came on
var last_work_usec := 0    # the last frame's building, for the budget's tests
var _tools: Array[Node] = []
var _config: Dictionary = {}
var _dim: MeshInstance3D
var _material: ShaderMaterial
var _plane := PlaneMesh.new()
var _queued := {}          # tiles to build, nearest the focus first
var _stale := {}           # queued tiles whose floors' numbers must be worked out again
var _waiting := {}         # tiles a change touched, queued once things settle
var _settle_left := 0.0
var _rooms_left := -1.0    # counts down to comparing room floors after room updates
var _room_floors := {}     # tile -> the lowest air cells of sealed rooms in it
var _room_floors_fresh := false
var _range_left := 0.0
var _focus := NO_TILE
var _build := {}           # the tile being built: {tile, column, floors, cells, values, known}
var _card_layer: CanvasLayer
var _card: Control
var _card_text := []       # what the card shows, so the same words are not set again
var _hover_left := 0.0


func _ready() -> void:
	add_to_group("temperature_view")
	dock = get_node_or_null(dock_path)
	slice = get_node_or_null(slice_path)
	rooms_tool = get_node_or_null(rooms_tool_path)
	_config = UIRegistry.get_time_slice().get("temperature", {})
	_plane.size = Vector2.ONE
	WorldData.block_changed.connect(_on_block_changed)
	RoomManager.door_boundaries_changed.connect(_on_cells_changed)
	RoomManager.warmth_changed.connect(_on_cells_changed)
	InteriorTracker.caves_discovered.connect(_on_cells_changed)
	RoomManager.room_updated.connect(_on_room_changed)
	RoomManager.room_removed.connect(_on_room_changed)
	WorldClock.hour_changed.connect(func(_hour: int) -> void: update_clock())
	WeatherManager.weather_changed.connect(func(_id: String) -> void: update_clock())
	if slice != null:
		slice.slice_changed.connect(func(_height: int) -> void: _rebuild_all())
		slice.slice_active_changed.connect(func(_on: bool) -> void: _rebuild_all())
	set_process(false)
	# Siblings may not have entered the tree yet.
	_bind_tools.call_deferred()
	if dock != null: dock.register_temperature_view(self)


func _bind_tools() -> void:
	for path: NodePath in tool_paths:
		var tool := get_node_or_null(path)
		if tool != null: _tools.append(tool)


func toggle() -> void:
	set_active(not active)


func set_active(value: bool) -> void:
	if value == active: return
	active = value
	if active:
		for view: Node in get_tree().get_nodes_in_group("appeal_view"): view.set_active(false)
		_build_view()
	else:
		_teardown()
	set_process(active)
	changed.emit()


## The object explorer's terrain clicks (as zones take theirs): while the view is on, a click
## on a room's floor opens the room window.
func try_select_zone_at_screen(screen_pos: Vector2) -> bool:
	if not active or rooms_tool == null: return false
	var spot := spot_under(screen_pos)
	return not spot.is_empty() and not bool(spot.rock) and bool(rooms_tool.open_room_at(spot.cell))


## The spot a screen point shows: {cell, rock}. The air on the side the ray came from (above a
## floor, beside a wall), or on the cut plane the rock itself; {} over nothing.
func spot_under(screen_pos: Vector2) -> Dictionary:
	var camera := get_viewport().get_camera_3d()
	if camera == null: return {}
	var origin := camera.project_ray_origin(screen_pos)
	var direction := camera.project_ray_normal(screen_pos).normalized()
	var visible_face := Callable()
	var underground := get_tree().get_first_node_in_group("underground_view")
	if underground != null and underground.is_inspecting(): visible_face = underground.is_terrain_face_visible
	var hit := Picking.terrain_hit(origin, direction, _cut(), RAY_MAX, Callable(), visible_face)
	if hit.is_empty(): return {}
	var block := Vector3i(int(hit.x), int(hit.y), int(hit.z))
	var air := block + Vector3i(hit.normal)
	if air.y > _cut() or not RoomManager.climate.is_air(air): return {"cell": block, "rock": true}
	return {"cell": air, "rock": false}


## The season's and the day and weather's offsets, set on the shader once a game hour and when
## the weather changes: the only thing the clock changes.
func update_clock() -> void:
	if _material == null: return
	_material.set_shader_parameter("season_c", RoomManager.climate.season_c())
	_material.set_shader_parameter("day_weather_c", RoomManager.climate.day_and_weather_c())


func get_stats() -> Dictionary:
	return {"tiles": tiles.size(), "queued": _queued.size(), "waiting": _waiting.size(), "builds": builds,
		"main_ms": last_work_usec / 1000.0}


func _process(delta: float) -> void:
	var started := Time.get_ticks_usec()
	_range_left -= delta
	if _range_left <= 0.0:
		_range_left = float(_config.get("range_seconds", 0.25))
		_follow_camera()
	if not _waiting.is_empty():
		_settle_left -= delta
		if _settle_left <= 0.0:
			_queued.merge(_waiting)
			_stale.merge(_waiting)
			_waiting.clear()
	if _rooms_left >= 0.0:
		_rooms_left -= delta
		if _rooms_left < 0.0: _check_rooms()
	var budget := int(float(_config.get("budget_ms", 2.0)) * 1000.0)
	while Time.get_ticks_usec() - started < budget and _advance(): pass
	last_work_usec = Time.get_ticks_usec() - started
	_update_hover(delta)


# ── Drawing ───────────────────────────────────────────────────────────────────

func _build_view() -> void:
	_dim = MeshInstance3D.new()
	_dim.name = "TemperatureDim"
	var quad := QuadMesh.new()
	quad.size = Vector2(2, 2)
	_dim.mesh = quad
	var dim := ShaderMaterial.new()
	dim.shader = DIM_SHADER
	dim.render_priority = -100   # first of the see-through passes
	dim.set_shader_parameter("keep_colour", float(_config.get("dim_keep_colour", 0.35)))
	dim.set_shader_parameter("brightness", float(_config.get("dim_brightness", 0.62)))
	_dim.material_override = dim
	_dim.extra_cull_margin = 16384.0   # it covers the screen wherever the camera looks
	_dim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_dim.layers = LAYERS
	add_child(_dim)
	_material = ShaderMaterial.new()
	_material.shader = TINT_SHADER
	_material.render_priority = 10   # over the dim
	var edges: Dictionary = RoomManager.temperature_config
	for edge: String in ["frozen_at", "cold_below", "comfortable_min", "comfortable_max"]:
		_material.set_shader_parameter(edge, float(edges.get(edge + "_c", 0.0)))
	var colours: Dictionary = _config.get("colours", {})
	for word: String in WORDS: _material.set_shader_parameter(word + "_colour", Color(String(colours.get(word, "#ffffff"))))
	_material.set_shader_parameter("alpha", float(_config.get("tint_alpha", 0.6)))
	update_clock()
	_card_layer = CanvasLayer.new()
	_card_layer.name = "TemperatureCard"
	_card_layer.layer = CARD_LAYER
	add_child(_card_layer)
	_card = preload("res://scripts/ui/HoverCard.gd").new()
	_card.hide()
	_card_layer.add_child(_card)
	_card_text = []
	builds = 0
	_focus = NO_TILE
	_range_left = 0.0
	_room_floors_fresh = false


func _teardown() -> void:
	for tile: Vector2i in tiles.keys(): _drop(tile)
	for node: Node in [_dim, _card_layer]:
		if is_instance_valid(node): node.queue_free()
	_dim = null
	_material = null
	_card_layer = null
	_card = null
	_queued.clear()
	_stale.clear()
	_waiting.clear()
	_room_floors.clear()
	_build = {}
	_rooms_left = -1.0


## The tiles within range of the point the camera looks at; tiles well out of range go.
func _follow_camera() -> void:
	var focus := _focus_tile()
	if focus == _focus: return
	_focus = focus
	var reach := int(_config.get("range_tiles", 4))
	for dx in range(-reach, reach + 1):
		for dz in range(-reach, reach + 1):
			var tile := focus + Vector2i(dx, dz)
			if tile.x < 0 or tile.y < 0 or tile.x * TILE >= WorldData.WORLD_SIZE_X or tile.y * TILE >= WorldData.WORLD_SIZE_Z: continue
			if not tiles.has(tile): _queued[tile] = true
	for tile: Vector2i in tiles.keys():
		if _distance(tile) > reach + 2: _drop(tile)
	for tile: Vector2i in _queued.keys():
		if _distance(tile) > reach and not tiles.has(tile): _queued.erase(tile)


func _focus_tile() -> Vector2i:
	var camera := get_viewport().get_camera_3d()
	if camera == null: return _focus
	var centre := get_viewport().get_visible_rect().size * 0.5
	var origin := camera.project_ray_origin(centre)
	var direction := camera.project_ray_normal(centre).normalized()
	var hit := Picking.terrain_hit(origin, direction, _cut(), RAY_MAX)
	var point := Vector3(float(hit.x), float(hit.y), float(hit.z)) if not hit.is_empty() else origin + direction * 60.0
	return Vector2i(floori(point.x) >> 4, floori(point.z) >> 4)


func _distance(tile: Vector2i) -> int:
	return maxi(absi(tile.x - _focus.x), absi(tile.y - _focus.y))


## One step of building: a tile's start, one column's top floor, one floor's numbers or the
## tile's quads. False when there is nothing to build.
func _advance() -> bool:
	if _build.is_empty():
		if _queued.is_empty(): return false
		var next: Vector2i = _queued.keys()[0]
		for other: Vector2i in _queued:
			if _distance(other) < _distance(next): next = other
		_queued.erase(next)
		# Moving the slice keeps the floors' numbers, which never depend on it.
		var known: Dictionary = {} if _stale.has(next) or not tiles.has(next) else tiles[next].values
		_stale.erase(next)
		_build = {"tile": next, "column": 0, "floors": _sunk_floors(next), "cells": [], "values": {}, "known": known}
		return true
	var tile: Vector2i = _build.tile
	var column := int(_build.column)
	if column < TILE * TILE:
		_top_floor(tile.x * TILE + (column & 15), tile.y * TILE + (column >> 4), _build.floors)
		_build.column = column + 1
		if column + 1 == TILE * TILE: _build.cells = (_build.floors as Dictionary).keys()
		return true
	var values: Dictionary = _build.values
	var cells: Array = _build.cells
	if values.size() < cells.size():
		var cell: Vector3i = cells[values.size()]
		values[cell] = _build.known[cell] if (_build.known as Dictionary).has(cell) else _values(cell)
		return true
	_finish(tile, values)
	_build = {}
	return true


## The floors under the top one that X-ray shows: sealed rooms' and dug tunnels' (dug air over
## a solid block), at or under the cut. Elsewhere the terrain in front hides them.
func _sunk_floors(tile: Vector2i) -> Dictionary:
	var floors := {}
	var cut := _cut()
	var climate = RoomManager.climate
	for chunk: Vector3i in InteriorTracker.get_interior_chunks():
		if chunk.x != tile.x or chunk.z != tile.y: continue
		for cell: Vector3i in InteriorTracker.get_interior_cells(chunk):
			if cell.y - 1 <= cut and climate.is_air(cell) and not climate.is_air(cell + Vector3i.DOWN): floors[cell] = true
	for cell: Vector3i in _room_floors_in(tile):
		if cell.y - 1 <= cut: floors[cell] = true
	return floors


## The lowest air of each column of each sealed room, by tile, gathered again after rooms change.
func _room_floors_in(tile: Vector2i) -> Array:
	if not _room_floors_fresh:
		_room_floors_fresh = true
		_room_floors.clear()
		for room: Dictionary in RoomManager.get_rooms().values():
			var cells: Dictionary = room.cells
			for cell: Vector3i in cells:
				if cells.has(cell + Vector3i.DOWN): continue
				var key := Vector2i(cell.x >> 4, cell.z >> 4)
				if not _room_floors.has(key): _room_floors[key] = []
				_room_floors[key].append(cell)
	return _room_floors.get(tile, [])


## A column's top floor at or under the cut, unless the cut plane there is rock, which stays dim.
func _top_floor(x: int, z: int, floors: Dictionary) -> void:
	var climate = RoomManager.climate
	var cut := _cut()
	var top: int = climate.highest_solid(x, z, cut)
	var air := Vector3i(x, top + 1, z)
	if air.y > WorldData.MAX_Y or (top == cut and not climate.is_air(air)): return
	floors[air] = true


## One quad per run of neighbouring floors along x with the same height and numbers.
func _finish(tile: Vector2i, values: Dictionary) -> void:
	var cells: Array = values.keys()
	cells.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		if a.z != b.z: return a.z < b.z
		if a.y != b.y: return a.y < b.y
		return a.x < b.x)
	var runs: Array = []   # [first cell, length, numbers]
	var room_cells: Array[Vector3i] = []
	for cell: Vector3i in cells:
		if (values[cell] as Vector4).w > 0.5: room_cells.append(cell)
		if not runs.is_empty():
			var last: Array = runs.back()
			if (last[0] as Vector3i) + Vector3i(int(last[1]), 0, 0) == cell and (last[2] as Vector4) == values[cell]:
				last[1] = int(last[1]) + 1
				continue
		runs.append([cell, 1, values[cell]])
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = _plane
	multimesh.instance_count = runs.size()
	for i in range(runs.size()):
		var first: Vector3i = runs[i][0]
		var length := float(runs[i][1])
		var numbers: Vector4 = runs[i][2]
		multimesh.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(length, 1.0, 1.0)),
			Vector3(first.x + length * 0.5, first.y + 0.02, first.z + 0.5)))
		multimesh.set_instance_custom_data(i, Color(numbers.x, numbers.y, numbers.z, numbers.w))
	var node: MultiMeshInstance3D = tiles[tile].node if tiles.has(tile) else null
	if node == null:
		node = MultiMeshInstance3D.new()
		node.name = "TemperatureTile_%d_%d" % [tile.x, tile.y]
		node.material_override = _material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.layers = LAYERS
		add_child(node)
	node.multimesh = multimesh
	node.visible = true
	tiles[tile] = {"node": node, "values": values, "rooms": room_cells}
	builds += 1


## A floor's numbers: its base temperature (its height's mean, plus a sealed room's heat and
## doors, or an open-air fire's warmth), its shares of the season and of the day and weather,
## and w 1 on a sealed room's floor.
func _values(cell: Vector3i) -> Vector4:
	var climate = RoomManager.climate
	var room: Dictionary = RoomManager.get_room_at(cell)
	if not room.is_empty():
		var form: Vector3 = room.temp_form
		return Vector4(form.x, form.y, form.z, 1.0)
	var place: Dictionary = climate.exposure(cell)
	return Vector4(climate.mean_c(float(cell.y)) + RoomManager.heat.warmth_at(cell), float(place.season_share), float(place.air_share), 0.0)


func _drop(tile: Vector2i) -> void:
	var node: Node = tiles[tile].node
	if is_instance_valid(node): node.queue_free()
	tiles.erase(tile)


func _cut() -> int:
	return mini(int(slice.get_slice_y()), WorldData.MAX_Y) if slice != null and bool(slice.is_active()) else WorldData.MAX_Y


# ── Changes ───────────────────────────────────────────────────────────────────

func _on_block_changed(cell: Vector3i, _old_id: int, _new_id: int) -> void:
	if active: _touch([cell])


func _on_cells_changed(cells: Array[Vector3i]) -> void:
	if active: _touch(cells)


## Built tiles within reach of changed cells are built again once things settle (counted from
## the first change, so steady digging still shows): a change reaches as far as the outside
## air does.
func _touch(cells: Array) -> void:
	if _waiting.is_empty(): _settle_left = float(_config.get("settle_seconds", 0.5))
	var reach := int(RoomManager.temperature_config.outside_air_reach_blocks)
	var seen := {}
	for cell: Vector3i in cells:
		var key := Vector2i(cell.x >> 4, cell.z >> 4)
		if seen.has(key): continue
		seen[key] = true
		for tile_x in range((cell.x - reach) >> 4, ((cell.x + reach) >> 4) + 1):
			for tile_z in range((cell.z - reach) >> 4, ((cell.z + reach) >> 4) + 1):
				if tiles.has(Vector2i(tile_x, tile_z)): _waiting[Vector2i(tile_x, tile_z)] = true


func _on_room_changed(_id: int) -> void:
	if not active: return
	_room_floors_fresh = false
	if _rooms_left < 0.0: _rooms_left = float(_config.get("settle_seconds", 0.5))


## After rooms change: a tile is built again where a room floor's heat or share moved, where a
## room went, or where a room's floor is new to it. An hour passing changes none of these.
func _check_rooms() -> void:
	var changed_tiles := {}
	for tile: Vector2i in tiles:
		var known: Dictionary = tiles[tile].values
		for cell: Vector3i in tiles[tile].rooms:
			if not _values(cell).is_equal_approx(known[cell]):
				changed_tiles[tile] = true
				break
	var cut := _cut()
	for tile: Vector2i in tiles:
		if changed_tiles.has(tile): continue
		var known: Dictionary = tiles[tile].values
		for cell: Vector3i in _room_floors_in(tile):
			if cell.y - 1 <= cut and (not known.has(cell) or (known[cell] as Vector4).w < 0.5):
				changed_tiles[tile] = true
				break
	_queued.merge(changed_tiles)
	_stale.merge(changed_tiles)


## The slice moved: every tile is built again at the new cut, hidden until it is.
func _rebuild_all() -> void:
	if not active: return
	for tile: Vector2i in tiles:
		_queued[tile] = true
		tiles[tile].node.visible = false
	if not _build.is_empty():
		_queued[_build.tile] = true
		if (_build.known as Dictionary).is_empty() and tiles.has(_build.tile): _stale[_build.tile] = true
	_build = {}


# ── The hover card ────────────────────────────────────────────────────────────

## The card follows the cursor each frame; what it says is worked out a few times a second.
func _update_hover(delta: float) -> void:
	if _card == null: return
	if _hover_blocked():
		_card.hide()
		return
	var mouse := get_viewport().get_mouse_position()
	_hover_left -= delta
	if _hover_left <= 0.0:
		_hover_left = float(_config.get("hover_seconds", 0.1))
		var spot := spot_under(mouse)
		if spot.is_empty(): _card.hide()
		else: fill_card(spot)
	if _card.visible: _card.point_at(Rect2(mouse - Vector2(10, 10), Vector2(20, 20)), "above")


## No card over the interface, or while a click tool is working.
func _hover_blocked() -> bool:
	if get_viewport().gui_get_hovered_control() != null: return true
	for tool: Node in _tools:
		if is_instance_valid(tool) and tool.has_method("is_active") and bool(tool.call("is_active")): return true
	return false


## A spot's temperature and word, what sets it, and its range over a year in clear weather (a
## heated room's without its fires, which burn only while the room is cold).
func fill_card(spot: Dictionary) -> void:
	var place: Dictionary = RoomManager.climate_at(spot.cell)
	var lines: PackedStringArray = []
	var title := "Rock"
	var room_kind := String(place.kind) == "room"
	# What fires add here, left out of the year's range: they burn only while it is cold.
	var fires := float(place.heat_c) if room_kind else float(place.fire_c)
	match String(place.kind):
		"room":
			var id := int(place.room_id)
			var room: Dictionary = RoomManager.get_rooms().get(id, {})
			title = rooms_tool.room_title(room, id) if rooms_tool != null else RoomManager.room_label(room)
			var season := roundi(float(place.season_share) * 100.0)
			var air := roundi(float(place.air_share) * 100.0)
			lines.append("A sealed room: day, night and weather stay out, and %d%% of the season reaches it." % season if air == 0
				else "A sealed room: %d%% of the season reaches it, and %d%% of the day and weather through its doors." % [season, air])
			if fires >= 0.05: lines.append("Its fires add %.1f°C." % fires)
			var doors := float(place.door_c)
			if absf(doors) >= 0.05: lines.append("Its doors make it %.1f°C %s." % [absf(doors), "warmer" if doors > 0.0 else "colder"])
		"open_sky":
			title = "Open ground"
			lines.append("Open sky: the day, the season and the weather all reach it.")
		"sheltered":
			title = "Underground" if int(place.cover) >= 3 else "Under a roof"
			var steps := int(place.steps)
			lines.append(("%d steps from open air" % steps if steps > 0 else "No open air within %d steps" % int(RoomManager.temperature_config.outside_air_reach_blocks))
				+ ", %d blocks overhead." % int(place.cover))
		_:
			lines.append("%d blocks overhead: a sealed room dug here would be about this warm." % int(place.cover))
	if not room_kind and fires >= 0.05: lines.append("A fire nearby adds %.1f°C." % fires)
	if fires < 0.05: fires = 0.0
	var year := "Over a year" if fires == 0.0 else "Over a year without its fires" if room_kind else "Over a year without the fire"
	lines.append("%s: %d to %d°C in clear weather." % [year, floori(float(place.low_c) - fires), ceili(float(place.high_c) - fires)])
	lines.append(_keeping_line(spot))
	if String(place.kind) == "room": lines.append("Click for the room.")
	var text := [title, "\n".join(lines), "%.1f°C · %s" % [float(place.temperature_c), String(place.word)],
		get_viewport().get_visible_rect().size.x >= 1200.0]
	if text != _card_text:
		_card_text = text
		_card.show_card(text[0], text[1], "", text[2], text[3], UIRegistry.get_icon_family_color("system"))
	_card.show()


## How long the reference food (keeping_food, blueberries) keeps at the spot as it is now
## (doc 42 "Spoilage"); over cut rock, in a room dug there.
func _keeping_line(spot: Dictionary) -> String:
	var drops := ItemDropManager.find(get_tree())
	var key := String(_config.get("keeping_food", ""))
	if drops == null or drops.food_definition(key).is_empty(): return ""
	var days: float = StockpileManager.spoilage.keeps_days_at(drops.food_definition(key), spot.cell)
	var definition := drops.get_item_def(key)
	var name := String(definition.get("plural_name", String(definition.get("display_name", key)).to_lower()))
	name = name.left(1).to_upper() + name.substr(1)
	return ("%s would keep %s in a room dug here." if bool(spot.rock) else "%s keep %s here.") % [name, StockpileManager.spoilage.days_text(days)]


func _exit_tree() -> void:
	if active: _teardown()
