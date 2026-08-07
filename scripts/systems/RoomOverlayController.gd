class_name RoomOverlayController
extends Node3D

## The Rooms tool (🚪 dock entry, Alen's ask 2026-08-07) — makes sealed rooms
## visible and clickable instead of hunting them with the Block Inspector.
##
## While active, every sealed room `RoomManager` tracks gets a translucent
## floor overlay (fill + exterior outline, drawn at the room's floor cells —
## the lowest air cell per column). Overlays render with NO depth test (the
## mining ghost-layer treatment): a room reads through the mountain whether
## or not the slice is cut down to it — that IS the point of the tool. Amber
## = sealed; icy blue = Frozen Vault.
##
## Clicking marches the mouse ray through the world and selects the first
## room whose interior air it crosses (cells above the slice plane are
## skipped; solid rock does NOT stop the march — clicks are as x-ray as the
## overlays, so a room visible through rock is also clickable through rock).
## Selection opens a compact info window: sealed/frozen state, depth-zone
## name, temperature, volume, heat units (+computed bonus), door count,
## seasonal influence — everything doc 34's "UI — Room Temperature Display"
## specifies, fed by RoomManager.get_room_at()/get_rooms().
##
## Tool conventions (the StockpileDesignationController shape): dock announce
## via tool_requested — this controller self-toggles on its own id and
## deactivates on any other; ESC deactivates; right-mouse is never consumed
## (camera orbit contract, 21_camera.md). Scene node, not an autoload
## (presentation — doc 13 dividing line). Overlays and selection are derived
## presentation state: never saved, rebuilt from RoomManager on activation
## and on room_updated/room_removed.

signal tool_active_changed(active: bool)

const TOOL_ID := "rooms"
const RAY_STEP := 0.25
const RAY_MAX := 700.0
const SLICE_OFF_Y := 127
const _FACE_NORMALS: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 1, 0), Vector3i(0, -1, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]
const REBUILD_THROTTLE_S := 0.3      # RoomManager fires room_updated per room per rebuild
const WINDOW_REFRESH_S := 0.5        # temp drifts hourly at most — 2 Hz is plenty

## Green — deliberately distinct from every other overlay family: mining
## zones own yellow, stockpile zones own blue-cyan, furniture ghosts own
## cyan/red validity tints. Frozen Vaults stay icy blue.
const SEALED_FILL := Color(0.30, 0.80, 0.45, 0.14)
const SEALED_LINE := Color(0.45, 1.00, 0.60, 0.95)
const FROZEN_FILL := Color(0.42, 0.68, 0.95, 0.14)
const FROZEN_LINE := Color(0.62, 0.86, 1.00, 0.95)
const SELECTED_FILL_ALPHA := 0.28    # fill alpha bump on the selected room
const SHELL_INSET := 0.04            # pull shell faces inside the cell boundary
                                     # (they'd otherwise sit exactly on the wall
                                     # faces and z-fight where depth applies)

@export var dock_ui_path: NodePath
@export var slice_controller_path: NodePath

var _active: bool = false
var _slice_y: int = SLICE_OFF_Y
var _overlay_root: Node3D = null
var _overlays: Dictionary = {}       # room_id -> { "root": Node3D, "base_y": int }
var _overlays_dirty: bool = false
var _rebuild_accum: float = 0.0
var _material: StandardMaterial3D = null

var _selected_room_id: int = -1
var _selected_cell: Vector3i = Vector3i(-1, -1, -1)   # re-resolves the id across RoomManager rebuilds

var _window_layer: CanvasLayer = null
var _window_panel: PanelContainer = null
var _window_title: Label = null
var _window_info: Label = null
var _window_accum: float = 0.0


func _ready() -> void:
	var dock := get_node_or_null(dock_ui_path)
	if dock != null:
		if dock.has_method("register_room_controller"):
			dock.call("register_room_controller", self)
		if dock.has_signal("tool_requested"):
			dock.connect("tool_requested", _on_tool_requested)
	var slice_controller := get_node_or_null(slice_controller_path)
	if slice_controller != null:
		if slice_controller.has_signal("slice_changed"):
			slice_controller.connect("slice_changed", _on_slice_changed)
		if slice_controller.has_method("get_slice_y"):
			_slice_y = int(slice_controller.call("get_slice_y"))
	# Autoload → safe to reference directly (scene→autoload direction).
	RoomManager.room_updated.connect(_on_room_changed)
	RoomManager.room_removed.connect(_on_room_changed)
	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.no_depth_test = true    # the through-rock ghost read (see header)
	_material.render_priority = 10
	_build_window()


func _process(delta: float) -> void:
	if _window_panel != null and _window_panel.visible:
		_window_accum += delta
		if _window_accum >= WINDOW_REFRESH_S:
			_window_accum = 0.0
			_refresh_window()
	if not _active:
		return
	if _overlays_dirty:
		_rebuild_accum += delta
		if _rebuild_accum >= REBUILD_THROTTLE_S:
			_rebuild_accum = 0.0
			_overlays_dirty = false
			_rebuild_overlays()


func _unhandled_input(event: InputEvent) -> void:
	if not _active:
		return
	if event is InputEventKey and (event as InputEventKey).pressed \
			and (event as InputEventKey).keycode == KEY_ESCAPE:
		deactivate()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_pick_room_at_screen(mb.position)
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
	_active = true
	_rebuild_overlays()
	tool_active_changed.emit(true)


func deactivate() -> void:
	if not _active:
		return
	_active = false
	_clear_overlays()
	_close_window()
	_selected_room_id = -1
	_selected_cell = Vector3i(-1, -1, -1)
	tool_active_changed.emit(false)


func _on_tool_requested(tool_id: String) -> void:
	# One active click-tool at a time: our id toggles us; any other closes us.
	if tool_id == TOOL_ID:
		toggle_active()
	elif _active:
		deactivate()


func _on_slice_changed(new_slice_y: int) -> void:
	_slice_y = new_slice_y
	if _active:
		_apply_slice_visibility()


func _on_room_changed(_room_id: int) -> void:
	if _active:
		_overlays_dirty = true


# ── Overlays ──────────────────────────────────────────────────────────────────

func _clear_overlays() -> void:
	if _overlay_root != null and is_instance_valid(_overlay_root):
		_overlay_root.queue_free()
	_overlay_root = null
	_overlays.clear()


## Full rebuild from RoomManager (room ids are reassigned on every manager
## rebuild, so per-room diffing would buy nothing — room counts are small).
func _rebuild_overlays() -> void:
	_clear_overlays()
	_overlay_root = Node3D.new()
	_overlay_root.name = "RoomOverlays"
	add_child(_overlay_root)
	# Re-resolve the selection across the id churn (see _selected_cell).
	if _selected_cell.x >= 0:
		_selected_room_id = int(RoomManager.get_room_id_at(_selected_cell))
		if _selected_room_id < 0:
			_close_window()   # the clicked room no longer exists (seal broke)
	var rooms: Dictionary = RoomManager.get_rooms()
	for room_id: int in rooms.keys():
		var room: Dictionary = rooms[room_id]
		_overlays[room_id] = _build_room_overlay(room_id, room)
	_apply_slice_visibility()
	_refresh_window()


## Volume shell (Alen, 2026-08-07 second Rooms session — "make the volume of
## the room more obvious, draw it similar to a mining zone"): instead of a
## flat floor quad, emit every EXTERIOR face of the room's air-cell volume
## (a face whose neighbour cell is outside the room), inset by SHELL_INSET,
## plus outline edges. Interior edges shared by two coplanar emitted faces
## are deduped away so the outline traces the volume's silhouette, not a
## per-block grid (the mining-zone exterior-lines lesson).
func _build_room_overlay(room_id: int, room: Dictionary) -> Dictionary:
	var cells: Dictionary = room.get("cells", {})
	var is_frozen: bool = bool(room.get("is_frozen_vault", false))
	var fill_color: Color = FROZEN_FILL if is_frozen else SEALED_FILL
	var line_color: Color = FROZEN_LINE if is_frozen else SEALED_LINE
	if room_id == _selected_room_id:
		fill_color.a = SELECTED_FILL_ALPHA

	var fill_verts := PackedVector3Array()
	var fill_colors := PackedColorArray()
	var fill_indices := PackedInt32Array()
	var edge_count: Dictionary = {}     # edge key -> [count, Vector3 a, Vector3 b]
	var base_y := SLICE_OFF_Y
	for cell: Vector3i in cells.keys():
		if cell.y < base_y:
			base_y = cell.y
		for face: int in range(6):
			var normal: Vector3i = _FACE_NORMALS[face]
			if cells.has(cell + normal):
				continue   # interior face — the volume continues
			var corners := _face_corners(cell, face, SHELL_INSET)
			var i0 := fill_verts.size()
			for corner: Vector3 in corners:
				fill_verts.append(corner)
				fill_colors.append(fill_color)
			# Winding both ways is irrelevant — material is CULL_DISABLED.
			fill_indices.append_array(PackedInt32Array([i0, i0 + 1, i0 + 2, i0, i0 + 2, i0 + 3]))
			# Outline edges are counted at the TRUE cell boundary (inset 0),
			# so the two perpendicular faces meeting at a corner contribute
			# IDENTICAL endpoints and merge into ONE drawn line (Alen,
			# 2026-08-07 third Rooms session: the inset edge positions drew
			# visible double lines at every corner).
			var line_corners := _face_corners(cell, face, 0.0)
			for e: int in range(4):
				_count_edge(edge_count, line_corners[e], line_corners[(e + 1) % 4], face)

	var line_verts := PackedVector3Array()
	var line_colors := PackedColorArray()
	for key: String in edge_count.keys():
		var entry: Array = edge_count[key]
		var faces: Dictionary = entry[2]
		# Skip only FLAT-WALL CONTINUATIONS: every contribution from one face
		# orientation (two coplanar faces sharing the edge). A crease — two
		# different orientations meeting (corner), with or without a flat run
		# through it — and a single-face rim (e.g. a doorway border) draw.
		if faces.size() == 1 and int(faces.values()[0]) >= 2:
			continue
		line_verts.append(entry[0])
		line_verts.append(entry[1])
		line_colors.append(line_color)
		line_colors.append(line_color)

	var root := Node3D.new()
	root.name = "Room%d" % room_id
	_overlay_root.add_child(root)
	if not fill_verts.is_empty():
		var fill_mesh := ArrayMesh.new()
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = fill_verts
		arrays[Mesh.ARRAY_COLOR] = fill_colors
		arrays[Mesh.ARRAY_INDEX] = fill_indices
		fill_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var fill_node := MeshInstance3D.new()
		fill_node.mesh = fill_mesh
		fill_node.material_override = _material
		root.add_child(fill_node)
	if not line_verts.is_empty():
		var line_mesh := ArrayMesh.new()
		var line_arrays: Array = []
		line_arrays.resize(Mesh.ARRAY_MAX)
		line_arrays[Mesh.ARRAY_VERTEX] = line_verts
		line_arrays[Mesh.ARRAY_COLOR] = line_colors
		line_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, line_arrays)
		var line_node := MeshInstance3D.new()
		line_node.mesh = line_mesh
		line_node.material_override = _material
		root.add_child(line_node)
	return { "root": root, "base_y": base_y }


## Four corners of `face` of the unit cell at `cell`, pulled `inset` inward
## along the face NORMAL only — tangent extents stay full-cell, so adjacent
## coplanar faces share exact edge endpoints and the outline dedupe in
## _build_room_overlay works by string key. Fill uses SHELL_INSET (avoids
## z-fighting the walls); outline edges use 0.0 (single line per corner).
func _face_corners(cell: Vector3i, face: int, inset: float) -> Array[Vector3]:
	var x0 := float(cell.x)
	var y0 := float(cell.y)
	var z0 := float(cell.z)
	var x1 := x0 + 1.0
	var y1 := y0 + 1.0
	var z1 := z0 + 1.0
	if face == 0:
		var xa := x1 - inset
		return [Vector3(xa, y0, z0), Vector3(xa, y1, z0), Vector3(xa, y1, z1), Vector3(xa, y0, z1)]
	if face == 1:
		var xb := x0 + inset
		return [Vector3(xb, y0, z0), Vector3(xb, y1, z0), Vector3(xb, y1, z1), Vector3(xb, y0, z1)]
	if face == 2:
		var ya := y1 - inset
		return [Vector3(x0, ya, z0), Vector3(x1, ya, z0), Vector3(x1, ya, z1), Vector3(x0, ya, z1)]
	if face == 3:
		var yb := y0 + inset
		return [Vector3(x0, yb, z0), Vector3(x1, yb, z0), Vector3(x1, yb, z1), Vector3(x0, yb, z1)]
	if face == 4:
		var za := z1 - inset
		return [Vector3(x0, y0, za), Vector3(x1, y0, za), Vector3(x1, y1, za), Vector3(x0, y1, za)]
	var zb := z0 + inset
	return [Vector3(x0, y0, zb), Vector3(x1, y0, zb), Vector3(x1, y1, zb), Vector3(x0, y1, zb)]


## Undirected edge counter keyed on quantised endpoints (the mining
## controller's string-key edge dedupe, at 1/100 precision). Tracks which
## FACE ORIENTATION (0..5) contributed each occurrence, so the draw pass can
## tell a flat-wall continuation (same orientation twice → skip) from a
## crease or rim (draw).
func _count_edge(edges: Dictionary, a: Vector3, b: Vector3, face: int) -> void:
	var ka := "%d,%d,%d" % [roundi(a.x * 100.0), roundi(a.y * 100.0), roundi(a.z * 100.0)]
	var kb := "%d,%d,%d" % [roundi(b.x * 100.0), roundi(b.y * 100.0), roundi(b.z * 100.0)]
	var key := ka + "|" + kb if ka < kb else kb + "|" + ka
	if edges.has(key):
		var faces: Dictionary = edges[key][2]
		faces[face] = int(faces.get(face, 0)) + 1
	else:
		edges[key] = [a, b, { face: 1 }]


## Coarse per-room slice culling (the SurfaceFloraSpawner convention): a room
## whose floor sits above the cut plane hides; slice off (Y127) shows all.
func _apply_slice_visibility() -> void:
	for room_id: int in _overlays.keys():
		var entry: Dictionary = _overlays[room_id]
		var root_node: Node3D = entry["root"]
		if root_node != null and is_instance_valid(root_node):
			root_node.visible = int(entry["base_y"]) <= _slice_y


# ── Picking ───────────────────────────────────────────────────────────────────

## March the mouse ray through the grid; select the first room whose interior
## air it crosses. Cells above the slice are skipped; solid rock does NOT stop
## the march (x-ray clicks, matching the no-depth overlays — see header).
func _pick_room_at_screen(screen_pos: Vector2) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var origin := camera.project_ray_origin(screen_pos)
	var direction := camera.project_ray_normal(screen_pos).normalized()
	var last_cell := Vector3i(-999999, -999999, -999999)
	var distance := 0.0
	while distance <= RAY_MAX:
		var sample := origin + direction * distance
		var cell := Vector3i(floori(sample.x), floori(sample.y), floori(sample.z))
		if cell != last_cell:
			last_cell = cell
			if cell.y <= _slice_y:
				var room_id := int(RoomManager.get_room_id_at(cell))
				if room_id >= 0:
					_select_room(room_id, cell)
					return
		distance += RAY_STEP
	# Clicked empty space: keep the current selection (closing is the ✕'s job).


func _select_room(room_id: int, cell: Vector3i) -> void:
	var previous := _selected_room_id
	_selected_room_id = room_id
	_selected_cell = cell
	if previous != room_id:
		_overlays_dirty = true   # retint selected/deselected fills on the throttle
	_open_window()
	_refresh_window()


# ── Info window (doc 34 "UI — Room Temperature Display") ─────────────────────

func _build_window() -> void:
	_window_layer = CanvasLayer.new()
	_window_layer.name = "RoomInfoWindow"
	_window_layer.layer = 22
	add_child(_window_layer)

	_window_panel = PanelContainer.new()
	_window_panel.position = Vector2(24.0, 432.0)   # below the slice palette
	_window_panel.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.065, 0.070, 0.075, 0.94)
	style.border_color = Color(1, 1, 1, 0.12)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(10.0)
	_window_panel.add_theme_stylebox_override("panel", style)
	_window_layer.add_child(_window_panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	_window_panel.add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	column.add_child(header)

	_window_title = Label.new()
	_window_title.text = "🚪 Room"
	_window_title.add_theme_font_size_override("font_size", 14)
	_window_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_window_title)

	var close := Button.new()
	close.text = "✕"
	close.flat = true
	close.pressed.connect(func() -> void: _close_window())
	header.add_child(close)

	_window_info = Label.new()
	_window_info.add_theme_font_size_override("font_size", 13)
	_window_info.text = ""
	column.add_child(_window_info)


func _open_window() -> void:
	_window_accum = 0.0
	if _window_panel != null:
		_window_panel.visible = true


func _close_window() -> void:
	if _window_panel != null:
		_window_panel.visible = false


## EXPLICIT TYPES at every Dictionary read — the RoomManager/WorldClock
## Variant-inference trap (see RoomManager._recompute_temp header note).
func _refresh_window() -> void:
	if _window_panel == null or not _window_panel.visible:
		return
	if _selected_room_id < 0:
		_close_window()
		return
	var room: Dictionary = RoomManager.get_rooms().get(_selected_room_id, {})
	if room.is_empty():
		_window_title.text = "🚪 Room %d" % _selected_room_id
		_window_info.text = "No longer sealed —\nthe seal was broken."
		return
	var temp_c: float = float(room.get("temp_c", 0.0))
	var volume: int = int(room.get("volume", 0))
	var heat_units: int = int(room.get("heat_units", 0))
	var mean_floor_y: float = float(room.get("mean_floor_y", 0.0))
	var seasonal: float = float(room.get("seasonal_influence", 0.0))
	var is_frozen: bool = bool(room.get("is_frozen_vault", false))
	var doors: int = room.get("door_cells", {}).size()
	var heat_bonus: float = float(heat_units) / float(max(volume, 1))
	_window_title.text = "🚪 Room %d" % _selected_room_id
	var status := "FROZEN VAULT ❄" if is_frozen else "Sealed (%s)" % _zone_name(mean_floor_y)
	_window_info.text = "\n".join([
		status,
		"Temperature: %.1f°C" % temp_c,
		"Volume: %d blocks" % volume,
		"Heat sources: %d units (+%.1f°C)" % [heat_units, heat_bonus],
		"Doors: %d" % doors,
		"Seasonal influence: %d%%" % roundi(seasonal * 100.0),
		"Mean floor Y: %.1f" % mean_floor_y,
	])


## Depth-zone label from mean floor Y (doc 34 "Depth–Temperature Gradient").
func _zone_name(mean_floor_y: float) -> String:
	if mean_floor_y >= 65.0:
		return "Cool Cave"
	if mean_floor_y >= 50.0:
		return "Cold Cave"
	if mean_floor_y >= 37.0:
		return "Deep Cold"
	return "Frozen Zone"
