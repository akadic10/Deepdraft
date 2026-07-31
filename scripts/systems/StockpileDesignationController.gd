class_name StockpileDesignationController
extends Node3D

## Stockpile zone designation tool (doc 18 Phase 1). The player toggles the
## tool (dock 'storage_zone' panel → Draw Zone), hovers a validity-tinted
## ghost tile, and click-drags a flat rectangle on walkable floor. Confirmed
## zones render a per-zone ground overlay (never merged — the doc 43
## adjacency lesson) and persist until removed via the zone window.
##
## Tool input contract (doc 21): ESC exits the mode; right-mouse stays camera
## orbit and is never consumed. The tool stays active after each confirm for
## repeated painting (the mining-tool pattern). Clicking an EXISTING zone cell
## (no drag) while the tool is active opens its compact zone window.
##
## Drag rules (doc 18 Phase 1):
##   - The anchor cell fixes the zone's floor Y — the marquee is FLAT; hover
##     cells clamp to the anchor plane (the mining drag-height-lock lesson).
##   - Per-cell validity: walkable floor (NavGrid — solid + 3-air clearance +
##     no entity), exactly at anchor Y, dry, in bounds. Invalid cells drop out
##     of the preview; confirm designates exactly the valid subset (WYSIWYG).
##   - No grid snapping; max extent per drag is MAX_ZONE_EXTENT.
##
## Raycasting: zones are SURFACE designations, so hover marches the camera
## ray against the height field (get_visible_surface_y) — the flag-tool
## approach, map-wide, no streamed chunks required.
##
## Slice rule (doc 11 Phase 5): zone overlays hide when their floor is above
## the cut, same hook as flora/dwarves/drops.

@export var camera_path: NodePath
@export var dock_ui_path: NodePath
@export var slice_controller_path: NodePath

const TOOL_ID := "storage_zone"
const MAX_ZONE_EXTENT := 16          # max cells per axis in one drag
const WORLD_EDGE_MARGIN := 2
const RAY_STEP := 0.5
const RAY_MAX := 700.0
const SLICE_OFF_Y := 127
const OVERLAY_LIFT := 1.04           # overlay quad height above the floor top
const DRAG_THRESHOLD_PX := 6.0       # below this, a click = zone select (doc 22)

const COLOR_VALID := Color(0.25, 0.65, 0.90, 0.30)     # fill, blue-cyan (mining zones own yellow)
const COLOR_VALID_EDGE := Color(0.35, 0.80, 1.00, 0.85)
const COLOR_INVALID := Color(1.00, 0.30, 0.25, 0.35)
const COLOR_ZONE := Color(0.25, 0.65, 0.90, 0.22)      # confirmed zone fill
const COLOR_ZONE_EDGE := Color(0.35, 0.80, 1.00, 0.60)
const EDGE_INSET := 0.08             # perimeter strip width (blocks)

## DEV drop mix (doc 18 Phase 0): item_key -> count, total 20. Keys must match
## resources.json; all have real GLBs so no fallback cubes appear.
const DEV_DROP_MIX: Dictionary = {
	"base:resources:stone:rough_stone": 6,
	"base:resources:ore:copper": 3,
	"base:resources:ore:tin": 3,
	"base:resources:ore:iron": 3,
	"base:resources:ore:coal": 2,
	"base:resources:soil:light_soil": 2,
	"base:resources:soil:cave_soil": 1,
}

## DEV: one packed furniture item of each kind (doc 19 Phase 0 - the v1 item
## source until crafting/trade produce furniture for real).
const DEV_FURNITURE_MIX: Dictionary = {
	"base:resources:furniture:barrel": 1,
	"base:resources:furniture:storage_chest": 1,
	"base:resources:furniture:storage_shelf": 1,
}

signal zone_created(zone_id: int)
signal zone_removed(zone_id: int)

## Fired on every activate/deactivate — DockUI refreshes button pressed-state
## from it (the SliceController slice_active_changed pattern), so Esc-cancel
## no longer leaves the 📦 button lit until the next dock interaction.
signal tool_active_changed(active: bool)

var _dock_ui: Node = null

var _active: bool = false
var _dragging: bool = false
var _anchor_cell: Vector3i = Vector3i(-1, -1, -1)
var _drag_start_px: Vector2 = Vector2.ZERO
var _hover_cell: Vector3i = Vector3i(-1, -1, -1)
var _hover_valid: bool = false
var _preview_cells: Array[Vector3i] = []

var _slice_y: int = SLICE_OFF_Y
var _next_zone_id: int = 1
var _zones: Dictionary = {}          # zone_id -> StockpileZoneComponent
var _zone_overlays: Dictionary = {}  # zone_id -> MeshInstance3D
var _cell_to_zone: Dictionary = {}   # Vector3i -> zone_id (click lookup)

var _preview_mesh: MeshInstance3D = null
var _size_label: Label3D = null
var _overlay_material: StandardMaterial3D = null

var _window_layer: CanvasLayer = null
var _window_panel: PanelContainer = null
var _window_zone_id: int = -1
var _window_info_label: Label = null


func _ready() -> void:
	add_to_group("stockpile_controller")
	add_to_group(SaveManager.OWNER_GROUP)
	_dock_ui = get_node_or_null(dock_ui_path)
	if _dock_ui != null:
		if _dock_ui.has_method("register_stockpile_controller"):
			_dock_ui.call("register_stockpile_controller", self)
		if _dock_ui.has_signal("tool_requested"):
			_dock_ui.connect("tool_requested", _on_tool_requested)
	var slice_controller := get_node_or_null(slice_controller_path)
	if slice_controller != null and slice_controller.has_signal("slice_changed"):
		slice_controller.connect("slice_changed", _on_slice_changed)
	_overlay_material = StandardMaterial3D.new()
	_overlay_material.vertex_color_use_as_albedo = true
	_overlay_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_overlay_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_overlay_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_build_window()


func _process(_delta: float) -> void:
	if not _active:
		return
	_update_hover()


func _unhandled_input(event: InputEvent) -> void:
	if not _active:
		# Mining parity (defect, Alen 2026-07-11: a stocked zone was unremovable
		# with the tool off): zones stay click-selectable while the tool is
		# INACTIVE, exactly like MiningDesignationController's inactive branch —
		# the zone window (and its Remove button) must always be reachable.
		if event is InputEventMouseButton:
			var mb_inactive := event as InputEventMouseButton
			if mb_inactive.pressed and mb_inactive.button_index == MOUSE_BUTTON_LEFT \
					and _try_select_zone_at_screen(mb_inactive.position):
				get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and (event as InputEventKey).pressed \
			and (event as InputEventKey).keycode == KEY_ESCAPE:
		deactivate()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			_on_left_press(mb.position)
			get_viewport().set_input_as_handled()
		elif _dragging:
			_on_left_release(mb.position)
			get_viewport().set_input_as_handled()


# ── Tool state ────────────────────────────────────────────────────────────────

func is_active() -> bool:
	return _active


func toggle_active() -> void:
	if _active:
		deactivate()
	else:
		activate()


func activate() -> void:
	if _active:
		return
	if not bool(WorldGenerator.get_streaming_stats().get("maps_ready", false)):
		push_warning("StockpileDesignationController: maps not ready.")
		return
	_active = true
	_ensure_preview_mesh()
	tool_active_changed.emit(true)


func deactivate() -> void:
	if not _active:
		return
	_active = false
	_dragging = false
	_preview_cells.clear()
	if _preview_mesh != null:
		_preview_mesh.visible = false
	if _size_label != null:
		_size_label.visible = false
	tool_active_changed.emit(false)


func _on_tool_requested(tool_id: String) -> void:
	# One active tool at a time: our id toggles us; any other id closes us.
	if tool_id == TOOL_ID:
		toggle_active()
	elif _active:
		deactivate()


# ── Input flow ────────────────────────────────────────────────────────────────

func _on_left_press(screen_pos: Vector2) -> void:
	if not _hover_valid:
		# Clicking an existing zone opens its window even on invalid hover
		# (a stocked zone cell is not a valid NEW cell, but is selectable).
		if _cell_to_zone.has(_hover_cell):
			_open_zone_window(int(_cell_to_zone[_hover_cell]))
		return
	if _cell_to_zone.has(_hover_cell):
		_open_zone_window(int(_cell_to_zone[_hover_cell]))
		return
	_dragging = true
	_anchor_cell = _hover_cell
	_drag_start_px = screen_pos
	_rebuild_preview()


func _on_left_release(screen_pos: Vector2) -> void:
	_dragging = false
	if _size_label != null:
		_size_label.visible = false
	# Short click on empty valid ground = 1×1 zone (DRAG_THRESHOLD, doc 22).
	# NOTE: built explicitly, never via ternary — `[x] if c else []` yields a
	# plain Array and crashes assigning to Array[Vector3i] (runtime-only error;
	# the 2026-07-06 flag-click crash).
	if screen_pos.distance_to(_drag_start_px) < DRAG_THRESHOLD_PX:
		var single: Array[Vector3i] = []
		if _is_valid_cell(_anchor_cell, _anchor_cell.y):
			single.append(_anchor_cell)
		_preview_cells = single
	if not _preview_cells.is_empty():
		_confirm_zone(_preview_cells.duplicate())
	_preview_cells.clear()
	if _preview_mesh != null:
		_preview_mesh.visible = false


func _update_hover() -> void:
	var hit := _mouse_surface_cell()
	if hit.is_empty():
		_hover_cell = Vector3i(-1, -1, -1)
		_hover_valid = false
		if not _dragging and _preview_mesh != null:
			_preview_mesh.visible = false
		return
	var cell := Vector3i(int(hit["x"]), int(hit["y"]), int(hit["z"]))
	if _dragging:
		# Drag height lock: the marquee lives on the anchor plane.
		cell.y = _anchor_cell.y
	if cell == _hover_cell and _preview_mesh != null and _preview_mesh.visible:
		return
	_hover_cell = cell
	_hover_valid = _is_valid_cell(cell, cell.y) and not _cell_to_zone.has(cell)
	_rebuild_preview()


# ── Preview ───────────────────────────────────────────────────────────────────

func _rebuild_preview() -> void:
	_ensure_preview_mesh()
	if _dragging:
		_preview_cells = _marquee_valid_cells(_anchor_cell, _hover_cell)
		_draw_cells(_preview_mesh, _preview_cells, COLOR_VALID, COLOR_VALID_EDGE, _anchor_cell.y)
		_update_size_label()
	else:
		var color_fill := COLOR_VALID if _hover_valid else COLOR_INVALID
		var color_edge := COLOR_VALID_EDGE if _hover_valid else COLOR_INVALID
		var cells: Array[Vector3i] = [_hover_cell]
		_draw_cells(_preview_mesh, cells, color_fill, color_edge, _hover_cell.y)
	_preview_mesh.visible = _hover_cell.x >= 0


## The extent-clamped marquee rectangle as (min_x, min_z, max_x, max_z).
func _marquee_rect(anchor: Vector3i, current: Vector3i) -> Vector4i:
	var min_x := mini(anchor.x, current.x)
	var max_x := maxi(anchor.x, current.x)
	var min_z := mini(anchor.z, current.z)
	var max_z := maxi(anchor.z, current.z)
	# Clamp extent, growing away from the anchor.
	max_x = mini(max_x, min_x + MAX_ZONE_EXTENT - 1) if anchor.x == min_x else max_x
	min_x = maxi(min_x, max_x - MAX_ZONE_EXTENT + 1) if anchor.x == max_x else min_x
	max_z = mini(max_z, min_z + MAX_ZONE_EXTENT - 1) if anchor.z == min_z else max_z
	min_z = maxi(min_z, max_z - MAX_ZONE_EXTENT + 1) if anchor.z == max_z else min_z
	return Vector4i(min_x, min_z, max_x, max_z)


## The flat rectangle between anchor and current, valid cells only (WYSIWYG).
func _marquee_valid_cells(anchor: Vector3i, current: Vector3i) -> Array[Vector3i]:
	var rect := _marquee_rect(anchor, current)
	var cells: Array[Vector3i] = []
	for x: int in range(rect.x, rect.z + 1):
		for z: int in range(rect.y, rect.w + 1):
			var cell := Vector3i(x, anchor.y, z)
			if _cell_to_zone.has(cell):
				continue   # zones never merge or overlap (doc 43 lesson)
			if _is_valid_cell(cell, anchor.y):
				cells.append(cell)
	return cells


## Live drag readout — "W × D — N cells" floating above the marquee centre
## (Alen playtest note 2026-07-06: never make the player count voxels).
func _update_size_label() -> void:
	if _size_label == null:
		_size_label = Label3D.new()
		_size_label.name = "SizeLabel"
		_size_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_size_label.fixed_size = true
		_size_label.pixel_size = 0.0008
		_size_label.font_size = 96
		_size_label.outline_size = 24
		_size_label.modulate = Color(0.85, 0.95, 1.0)
		_size_label.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
		_size_label.no_depth_test = true
		add_child(_size_label)
	var rect := _marquee_rect(_anchor_cell, _hover_cell)
	var w := rect.z - rect.x + 1
	var d := rect.w - rect.y + 1
	var valid := _preview_cells.size()
	if valid == w * d:
		_size_label.text = "%d × %d — %d cells" % [w, d, valid]
	else:
		_size_label.text = "%d × %d — %d of %d valid" % [w, d, valid, w * d]
	_size_label.position = Vector3(
		(float(rect.x) + float(rect.z) + 1.0) * 0.5,
		float(_anchor_cell.y) + 2.4,
		(float(rect.y) + float(rect.w) + 1.0) * 0.5)
	_size_label.visible = true


# ── Validity ──────────────────────────────────────────────────────────────────

## A designatable stockpile cell: in bounds (with margin), above bedrock, dry,
## the visible surface at exactly the marquee plane, and NavGrid-walkable
## (solid floor + 3-air clearance + no entity footprint).
func _is_valid_cell(cell: Vector3i, plane_y: int) -> bool:
	if cell.x < WORLD_EDGE_MARGIN or cell.x >= WorldGenerator.WORLD_SIZE_X - WORLD_EDGE_MARGIN \
			or cell.z < WORLD_EDGE_MARGIN or cell.z >= WorldGenerator.WORLD_SIZE_Z - WORLD_EDGE_MARGIN:
		return false
	if cell.y <= 3 or cell.y != plane_y:
		return false
	var col := Vector2i(cell.x, cell.z)
	if WorldGenerator.lake_columns.has(col) or WorldGenerator.tarn_columns.has(col):
		return false
	# Zones never overlap furniture ghosts or installed pieces (doc 19 Phase 2;
	# installed occupancy already fails is_walkable, ghosts are non-solid so
	# they need the explicit check).
	var furniture := get_tree().get_first_node_in_group("furniture_controller")
	if furniture != null and furniture.has_method("blocks_zone_cell") \
			and bool(furniture.call("blocks_zone_cell", cell)):
		return false
	return NavGrid.is_walkable(cell)


# ── Zone lifecycle ────────────────────────────────────────────────────────────

func _confirm_zone(cells: Array[Vector3i]) -> void:
	_create_zone(cells)


func _create_zone(cells: Array[Vector3i], requested_id: int = -1) -> StockpileZoneComponent:
	var zone_id := requested_id if requested_id > 0 else _next_zone_id
	var zone := StockpileZoneComponent.new()
	zone.setup(zone_id, cells)
	_zones[zone_id] = zone
	for cell: Vector3i in cells:
		_cell_to_zone[cell] = zone_id
	var overlay := MeshInstance3D.new()
	overlay.name = "StockpileZone_%d" % zone_id
	add_child(overlay)
	_draw_cells(overlay, cells, COLOR_ZONE, COLOR_ZONE_EDGE, zone.floor_y)
	overlay.visible = zone.floor_y <= _slice_y
	_zone_overlays[zone_id] = overlay
	StockpileManager.register_zone(zone)   # work source goes live (doc 18 Phase 3)
	print("StockpileDesignationController: zone %d created (%d cells at Y %d)." % [
		zone_id, cells.size(), zone.floor_y])
	zone_created.emit(zone_id)
	_next_zone_id = maxi(_next_zone_id, zone_id + 1)
	return zone


func remove_zone(zone_id: int) -> void:
	if not _zones.has(zone_id):
		return
	var zone: StockpileZoneComponent = _zones[zone_id]
	StockpileManager.deregister_zone(zone)   # cancels leases, frees stored items
	for cell: Vector3i in zone.tile_cells:
		_cell_to_zone.erase(cell)
	_zones.erase(zone_id)
	if _zone_overlays.has(zone_id):
		(_zone_overlays[zone_id] as MeshInstance3D).queue_free()
		_zone_overlays.erase(zone_id)
	if _window_zone_id == zone_id:
		_close_zone_window()
	zone_removed.emit(zone_id)


## Cross-system lookup (doc 19 Phase 2): the furniture tool must not place
## on zone cells. Mirrored by our own _is_valid_cell rejecting furniture.
func is_zone_cell(cell: Vector3i) -> bool:
	return _cell_to_zone.has(cell)


func get_zone(zone_id: int) -> StockpileZoneComponent:
	return _zones.get(zone_id)


func get_stats() -> Dictionary:
	var cells: int = 0
	var stored: int = 0
	for zone_id: int in _zones:
		var zone: StockpileZoneComponent = _zones[zone_id]
		cells += zone.cell_count()
		stored += zone.stored_count()
	return { "zones": _zones.size(), "cells": cells, "stored": stored }


func save_section_key() -> String:
	return "stockpiles"


func save_restore_priority() -> int:
	return 30


func serialize_state() -> Dictionary:
	var saved_zones: Array = []
	var ids: Array = _zones.keys()
	ids.sort()
	for value in ids:
		var zone_id := int(value)
		var zone: StockpileZoneComponent = _zones[zone_id]
		var cells: Array = []
		for cell: Vector3i in zone.tile_cells:
			cells.append(SaveManager.pack_v3i(cell))
		var stacks: Array = []
		for cell: Vector3i in zone.cell_stacks:
			var stack: Dictionary = zone.cell_stacks[cell]
			stacks.append({
				"cell": SaveManager.pack_v3i(cell),
				"item": String(stack.get("item", "")),
				"count": int(stack.get("count", 0)),
			})
		saved_zones.append({
			"id": zone_id,
			"cells": cells,
			"filter_tags": zone.filter_tags.duplicate(),
			"stacks": stacks,
		})
	return { "zones": saved_zones }


func restore_state(state: Dictionary) -> void:
	var drop_manager := get_tree().get_first_node_in_group("item_drop_manager")
	for raw in state.get("zones", []):
		if not (raw is Dictionary):
			continue
		var entry := raw as Dictionary
		var cells: Array[Vector3i] = []
		for packed in entry.get("cells", []):
			cells.append(SaveManager.unpack_v3i(packed))
		if cells.is_empty():
			continue
		var zone := _create_zone(cells, int(entry.get("id", -1)))
		zone.filter_tags.assign(entry.get("filter_tags", StockpileZoneComponent.DEFAULT_FILTER_TAGS))
		for stack_raw in entry.get("stacks", []):
			if not (stack_raw is Dictionary):
				continue
			var saved_stack := stack_raw as Dictionary
			var cell := SaveManager.unpack_v3i(saved_stack.get("cell", []))
			var item_key := String(saved_stack.get("item", ""))
			var count := maxi(int(saved_stack.get("count", 0)), 0)
			if count <= 0 or item_key.is_empty() or not zone.has_cell(cell):
				continue
			zone.cell_stacks[cell] = { "item": item_key, "count": count }
			if drop_manager != null and drop_manager.has_method("restore_stored_item"):
				drop_manager.call("restore_stored_item", item_key, cell)


# ── DEV: drop spawner (doc 18 Phase 0) ────────────────────────────────────────

## DEV: drops one packed furniture item of each kind at the view centre
## (doc 19 Phase 0). Wired to the dock's Storage Zone panel.
func dev_spawn_furniture() -> void:
	_dev_spawn_mix(DEV_FURNITURE_MIX)


## Spawns the DEV_DROP_MIX (20 mixed drops) around the ground point at the
## screen centre. Wired to the dock's Storage Zone panel.
func dev_spawn_drops() -> void:
	_dev_spawn_mix(DEV_DROP_MIX)


func _dev_spawn_mix(mix: Dictionary) -> void:
	var center := _screen_center_surface_cell()
	if center.x < 0:
		push_warning("StockpileDesignationController: no ground at view centre for DEV drops.")
		return
	var manager := get_tree().get_first_node_in_group("item_drop_manager")
	if manager == null or not manager.has_method("spawn_drop"):
		push_warning("StockpileDesignationController: ItemDropManager not found.")
		return
	for item_key: String in mix:
		var count := int(mix[item_key])
		for i: int in range(count):
			var jitter := Vector3i(randi_range(-3, 3), 0, randi_range(-3, 3))
			var cell := center + jitter
			# spawn_drop expects the MINED block position; its rest scan walks
			# down to the floor, so hand it the air block above the surface.
			manager.call("spawn_drop", item_key, 1, Vector3i(cell.x, center.y + 1, cell.z))


# ── Rendering helpers ─────────────────────────────────────────────────────────

func _ensure_preview_mesh() -> void:
	if _preview_mesh != null:
		return
	_preview_mesh = MeshInstance3D.new()
	_preview_mesh.name = "StockpilePreview"
	add_child(_preview_mesh)


## Builds flat quads (fill + perimeter strips) for `cells` into `target`.
func _draw_cells(target: MeshInstance3D, cells: Array[Vector3i], fill: Color, edge: Color, plane_y: int) -> void:
	var mesh := ImmediateMesh.new()
	if not cells.is_empty():
		var y := float(plane_y) + OVERLAY_LIFT
		var cell_set: Dictionary = {}
		for cell: Vector3i in cells:
			cell_set[cell] = true
		mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		for cell: Vector3i in cells:
			_emit_quad(mesh, float(cell.x), float(cell.z), 1.0, 1.0, y, fill)
			# Perimeter strips where a neighbour is outside the set.
			var fx := float(cell.x)
			var fz := float(cell.z)
			if not cell_set.has(cell + Vector3i(-1, 0, 0)):
				_emit_quad(mesh, fx, fz, EDGE_INSET, 1.0, y + 0.005, edge)
			if not cell_set.has(cell + Vector3i(1, 0, 0)):
				_emit_quad(mesh, fx + 1.0 - EDGE_INSET, fz, EDGE_INSET, 1.0, y + 0.005, edge)
			if not cell_set.has(cell + Vector3i(0, 0, -1)):
				_emit_quad(mesh, fx, fz, 1.0, EDGE_INSET, y + 0.005, edge)
			if not cell_set.has(cell + Vector3i(0, 0, 1)):
				_emit_quad(mesh, fx, fz + 1.0 - EDGE_INSET, 1.0, EDGE_INSET, y + 0.005, edge)
		mesh.surface_end()
	target.mesh = mesh
	target.material_override = _overlay_material


func _emit_quad(mesh: ImmediateMesh, x: float, z: float, w: float, d: float, y: float, color: Color) -> void:
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(Vector3(x, y, z))
	mesh.surface_add_vertex(Vector3(x + w, y, z))
	mesh.surface_add_vertex(Vector3(x + w, y, z + d))
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(Vector3(x, y, z))
	mesh.surface_add_vertex(Vector3(x + w, y, z + d))
	mesh.surface_add_vertex(Vector3(x, y, z + d))


# ── Raycasting (the flag-tool height-field march) ─────────────────────────────

func _mouse_surface_cell() -> Dictionary:
	return _surface_cell_for(get_viewport().get_mouse_position())


func _screen_center_surface_cell() -> Vector3i:
	var hit := _surface_cell_for(get_viewport().get_visible_rect().size * 0.5)
	if hit.is_empty():
		return Vector3i(-1, -1, -1)
	return Vector3i(int(hit["x"]), int(hit["y"]), int(hit["z"]))


func _surface_cell_for(screen_pos: Vector2) -> Dictionary:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return {}
	var origin := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	var t := 0.0
	while t < RAY_MAX:
		var p := origin + dir * t
		var wx := floori(p.x)
		var wz := floori(p.z)
		if wx >= 0 and wx < WorldGenerator.WORLD_SIZE_X \
				and wz >= 0 and wz < WorldGenerator.WORLD_SIZE_Z:
			var sy := int(WorldGenerator.get_visible_surface_y(wx, wz))
			if sy >= 0 and p.y <= float(sy + 1):
				return { "x": wx, "y": sy, "z": wz }
		elif p.y < 0.0:
			return {}
		t += RAY_STEP
	return {}


# ── Slice culling (doc 11 Phase 5 hook) ───────────────────────────────────────

func _on_slice_changed(new_slice_y: int) -> void:
	if new_slice_y == _slice_y:
		return
	_slice_y = new_slice_y
	for zone_id: int in _zone_overlays:
		var zone: StockpileZoneComponent = _zones.get(zone_id)
		if zone != null:
			(_zone_overlays[zone_id] as MeshInstance3D).visible = zone.floor_y <= _slice_y


# ── Zone window (compact — Remove / stored count) ─────────────────────────────

func _build_window() -> void:
	_window_layer = CanvasLayer.new()
	_window_layer.name = "StockpileZoneWindow"
	_window_layer.layer = 22
	_window_layer.visible = false
	add_child(_window_layer)

	_window_panel = PanelContainer.new()
	_window_panel.position = Vector2(18.0, 300.0)
	_window_panel.custom_minimum_size = Vector2(200.0, 0.0)
	_window_panel.add_theme_stylebox_override("panel", _style(Color(0.065, 0.070, 0.075, 0.94), Color(1, 1, 1, 0.12), 1, 8))
	_window_layer.add_child(_window_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	_window_panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	column.add_child(header)

	var title := Label.new()
	title.text = "Storage Zone"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 16)
	header.add_child(title)

	var close := Button.new()
	close.text = "X"
	close.custom_minimum_size = Vector2(30.0, 26.0)
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(_close_zone_window)
	header.add_child(close)

	_window_info_label = Label.new()
	_window_info_label.add_theme_font_size_override("font_size", 14)
	column.add_child(_window_info_label)

	var remove := Button.new()
	remove.text = "Remove zone"
	remove.tooltip_text = "Deletes this storage zone. Stored items stay where they are as loose drops."
	remove.focus_mode = Control.FOCUS_NONE
	remove.custom_minimum_size = Vector2(166.0, 30.0)
	remove.add_theme_font_size_override("font_size", 13)
	remove.pressed.connect(func() -> void:
		remove_zone(_window_zone_id)
	)
	column.add_child(remove)


## Zone click-select at an arbitrary screen position — usable while the tool
## is INACTIVE (the mining controller's _try_select_zone_at_screen pattern).
## Returns true if a zone window was opened (caller consumes the click).
func _try_select_zone_at_screen(screen_pos: Vector2) -> bool:
	var hit := _surface_cell_for(screen_pos)
	if hit.is_empty():
		return false
	var cell := Vector3i(int(hit["x"]), int(hit["y"]), int(hit["z"]))
	if not _cell_to_zone.has(cell):
		return false
	_open_zone_window(int(_cell_to_zone[cell]))
	return true


func _open_zone_window(zone_id: int) -> void:
	var zone: StockpileZoneComponent = _zones.get(zone_id)
	if zone == null:
		return
	_window_zone_id = zone_id
	_window_info_label.text = "Cells: %d\nStored: %d\nFilter: all goods" % [
		zone.cell_count(), zone.stored_count()]
	_window_layer.visible = true


func _close_zone_window() -> void:
	_window_zone_id = -1
	_window_layer.visible = false


func _style(bg: Color, border: Color, border_width: int, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.border_width_left = border_width
	style.border_width_right = border_width
	style.border_width_top = border_width
	style.border_width_bottom = border_width
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	return style
