extends Node3D

## The zone-drawing tool that Storage, Fishing and Farming zones share (doc 312). A zone is drawn
## the same way whatever it is for: with the tool on, a drag paints a flat rectangle on the plane
## of the cell it began on, a short click takes that one cell, and a click on a zone opens its
## window. With the tool off, a click on a zone still opens its window, so Remove is always in
## reach. Right mouse stays the camera's, and Esc is the dock's (doc 23, "Esc").
##
## The owner says only what is its own:
##   cell_reason(cell) -> String   why the cell can't be taken, or "" when it can
##   zone_at(cell) -> int          the zone standing on the cell, or -1
##   cells_chosen(cells)           a drag or a click was let go over these cells
##   zone_clicked(zone_id)         the player clicked a zone
##   narrow(anchor, cells)         optional: the cells a drag begun at `anchor` keeps
## and reads the rest for its tool-bar line: `dragging`, `preview`, `hover`, `hover_reason`,
## `pointer`, `drag_rect()`.
##
## The owner adds this as a child, so the tool hears input where its owner stands in the scene.
## It also draws the owner's zones (show_zone, hide_zone) and hides those above the slice.
## A new kind of zone needs no line in the others: each tool answers `covers(cell)` and gives
## its `here_words`, and `taken_by_another(cell)` asks them all.

signal active_changed(active: bool)

const Picking = preload("res://scripts/components/ObjectPicking.gd")
const GROUP := "zone_tools"
const WORLD_EDGE_MARGIN := 2         # zones keep this far from the world's edge
const RAY_MAX := 700.0
const OVERLAY_LIFT := 1.04           # the quads' height above the floor's top
const EDGE_INSET := 0.08             # the border strip's width, in blocks
const DRAG_THRESHOLD_PX := 6.0       # a shorter drag is a click (doc 22)
const NOWHERE := Vector3i(-1, -1, -1)
const COLOR_INVALID := Color(1.00, 0.30, 0.25, 0.35)

## The dock's id for this tool: asking for it turns the tool on or off, any other turns it off.
var tool_id := ""
## What the other zone tools say when one of this owner's zones is in the way.
var here_words := ""
## The longest side of one drag, in cells.
var max_extent := 16
## A dragged rectangle's fill and border. A zone's own colours go to show_zone().
var fill := Color(0.25, 0.65, 0.90, 0.30)
var edge := Color(0.35, 0.80, 1.00, 0.85)
var cell_reason: Callable
var zone_at: Callable
var cells_chosen: Callable
var zone_clicked: Callable
var narrow: Callable

var active := false
var dragging := false
var anchor := NOWHERE
var hover := NOWHERE
var hover_reason := ""
var preview: Array[Vector3i] = []
var pointer := Vector2.INF
var slice_y: int = SliceController.MAX_SLICE_Y

var _drag_start := Vector2.ZERO
var _material: StandardMaterial3D
var _preview_mesh: MeshInstance3D
var _zone_meshes: Dictionary = {}   # zone id -> MeshInstance3D
var _zone_planes: Dictionary = {}   # zone id -> the level its cells lie on


func _ready() -> void:
	add_to_group(GROUP)
	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED


func _process(_delta: float) -> void:
	if active: update_hover()


## A drag ends wherever the button comes up: over the world it takes its cells, over a window
## it is dropped.
func _input(event: InputEvent) -> void:
	if event is InputEventMouse: pointer = event.position
	if not dragging: return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		if get_viewport().gui_get_hovered_control() == null:
			update_hover()
			_release(event.position)
		else:
			end_drag()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT and dragging: end_drag()


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT: return
	if not active:
		if event.pressed and select_zone_at(event.position): get_viewport().set_input_as_handled()
		return
	if event.pressed:
		update_hover()
		_press(event.position)
		get_viewport().set_input_as_handled()
	elif dragging:
		_release(event.position)
		get_viewport().set_input_as_handled()


# ── On and off ────────────────────────────────────────────────────────────────

func activate() -> void:
	if active or not bool(WorldGenerator.get_streaming_stats().get("maps_ready", false)): return
	active = true
	active_changed.emit(true)


func deactivate() -> void:
	if not active: return
	active = false
	end_drag()
	active_changed.emit(false)


## The dock asked for a tool (its tool_requested signal): one active tool at a time.
func on_tool_requested(requested: String) -> void:
	if requested == tool_id:
		if active: deactivate()
		else: activate()
	elif active:
		deactivate()


# ── The drag ──────────────────────────────────────────────────────────────────

func _press(screen_pos: Vector2) -> void:
	var zone := _zone(hover)
	if zone >= 0:
		zone_clicked.call(zone)
		return
	if hover == NOWHERE or not hover_reason.is_empty(): return
	dragging = true
	anchor = hover
	_drag_start = screen_pos
	_rebuild_preview()


func _release(screen_pos: Vector2) -> void:
	# A short click takes the one cell. Built by hand: `[x] if c else []` is a plain Array, and
	# fails at run time when it is assigned to Array[Vector3i].
	if screen_pos.distance_to(_drag_start) < DRAG_THRESHOLD_PX:
		var single: Array[Vector3i] = []
		if _reason(anchor).is_empty(): single.append(anchor)
		preview = single
	var chosen: Array[Vector3i] = preview.duplicate()
	end_drag()
	if not chosen.is_empty(): cells_chosen.call(chosen)


func end_drag() -> void:
	dragging = false
	preview.clear()
	if _preview_mesh != null: _preview_mesh.visible = false


## Follows the pointer: the cell under it, why it can't be taken, and the preview. Runs each
## frame while the tool is on.
func update_hover() -> void:
	var hit := surface_cell_for(get_viewport().get_mouse_position() if pointer == Vector2.INF else pointer)
	if hit.is_empty():
		hover = NOWHERE
		hover_reason = ""
		if not dragging and _preview_mesh != null: _preview_mesh.visible = false
		return
	var cell := Vector3i(int(hit.x), int(hit.y), int(hit.z))
	if dragging: cell.y = anchor.y   # the rectangle lives on the anchor's plane
	if cell == hover and _preview_mesh != null and _preview_mesh.visible: return
	hover = cell
	hover_reason = _reason(cell)
	_rebuild_preview()


func _rebuild_preview() -> void:
	if _preview_mesh == null:
		_preview_mesh = MeshInstance3D.new()
		_preview_mesh.name = "Preview"
		add_child(_preview_mesh)
	if dragging:
		preview = _rectangle_cells()
		_draw_cells(_preview_mesh, preview, fill, edge, anchor.y)
	else:
		var free := hover_reason.is_empty() and _zone(hover) < 0
		var cells: Array[Vector3i] = [hover]
		_draw_cells(_preview_mesh, cells, fill if free else COLOR_INVALID, edge if free else COLOR_INVALID, hover.y)
	_preview_mesh.visible = hover.x >= 0


## The dragged rectangle in x and z, no longer than max_extent a side, growing away from the
## anchor.
func drag_rect() -> Rect2i:
	var low := Vector2i(mini(anchor.x, hover.x), mini(anchor.z, hover.z))
	var high := Vector2i(maxi(anchor.x, hover.x), maxi(anchor.z, hover.z))
	if anchor.x == low.x: high.x = mini(high.x, low.x + max_extent - 1)
	else: low.x = maxi(low.x, high.x - max_extent + 1)
	if anchor.z == low.y: high.y = mini(high.y, low.y + max_extent - 1)
	else: low.y = maxi(low.y, high.y - max_extent + 1)
	return Rect2i(low, high - low + Vector2i.ONE)


## The rectangle's cells the owner takes: what the player sees is what the zone gets.
func _rectangle_cells() -> Array[Vector3i]:
	var rect := drag_rect()
	var cells: Array[Vector3i] = []
	for x in range(rect.position.x, rect.end.x):
		for z in range(rect.position.y, rect.end.y):
			var cell := Vector3i(x, anchor.y, z)
			if _zone(cell) < 0 and _reason(cell).is_empty(): cells.append(cell)
	if not narrow.is_valid(): return cells
	var kept: Array[Vector3i] = []
	kept.assign(narrow.call(anchor, cells))
	return kept


func _reason(cell: Vector3i) -> String:
	return String(cell_reason.call(cell))


func _zone(cell: Vector3i) -> int:
	return int(zone_at.call(cell)) if cell != NOWHERE else -1


# ── What every zone refuses ───────────────────────────────────────────────────

## Too near the world's edge, or in the bedrock, for any zone.
static func near_edge(cell: Vector3i) -> bool:
	return cell.x < WORLD_EDGE_MARGIN or cell.x >= WorldData.WORLD_SIZE_X - WORLD_EDGE_MARGIN \
		or cell.z < WORLD_EDGE_MARGIN or cell.z >= WorldData.WORLD_SIZE_Z - WORLD_EDGE_MARGIN \
		or cell.y <= WorldGenerator.BEDROCK_MAX_Y


## Whether one of this owner's zones stands on the cell.
func covers(cell: Vector3i) -> bool:
	return _zone(cell) >= 0


## Another kind of zone on the cell, in that zone's words ("A field is here"), or "".
func taken_by_another(cell: Vector3i) -> String:
	for other: Node in get_tree().get_nodes_in_group(GROUP):
		if other != self and other.covers(cell): return other.here_words
	return ""


# ── Zones on the ground ───────────────────────────────────────────────────────

## Draws a zone's mat over its cells, or draws it again in other colours. It hides while its
## level is above the slice.
func show_zone(zone_id: int, cells: Array[Vector3i], zone_fill: Color, zone_edge: Color) -> void:
	var mesh: MeshInstance3D = _zone_meshes.get(zone_id)
	if mesh == null:
		mesh = MeshInstance3D.new()
		mesh.name = "Zone_%d" % zone_id
		add_child(mesh)
		_zone_meshes[zone_id] = mesh
	_zone_planes[zone_id] = cells[0].y
	_draw_cells(mesh, cells, zone_fill, zone_edge, cells[0].y)
	mesh.visible = cells[0].y <= slice_y


func hide_zone(zone_id: int) -> void:
	if not _zone_meshes.has(zone_id): return
	(_zone_meshes[zone_id] as Node).queue_free()
	_zone_meshes.erase(zone_id)
	_zone_planes.erase(zone_id)


## The slice moved (SliceController.slice_changed): zones above it hide.
func set_slice(new_slice_y: int) -> void:
	slice_y = new_slice_y
	for zone_id: int in _zone_meshes:
		(_zone_meshes[zone_id] as Node3D).visible = int(_zone_planes[zone_id]) <= slice_y


## Opens the zone under a screen point through zone_clicked, and says whether there was one.
func select_zone_at(screen_pos: Vector2) -> bool:
	var hit := surface_cell_for(screen_pos)
	if hit.is_empty(): return false
	var zone := _zone(Vector3i(int(hit.x), int(hit.y), int(hit.z)))
	if zone < 0: return false
	zone_clicked.call(zone)
	return true


## The first slice-visible solid block under a screen point, as the slice shows it (a cave not
## yet found is rock): the floor cell, NavGrid's convention. {} when the ray finds none.
func surface_cell_for(screen_pos: Vector2) -> Dictionary:
	var camera := get_viewport().get_camera_3d()
	if camera == null: return {}
	return Picking.terrain_hit(camera.project_ray_origin(screen_pos), camera.project_ray_normal(screen_pos).normalized(),
		slice_y, RAY_MAX, Picking.concealed_block)


## Flat quads over the cells' floor, with a strip along the outside edges.
func _draw_cells(target: MeshInstance3D, cells: Array[Vector3i], cell_fill: Color, cell_edge: Color, plane_y: int) -> void:
	var mesh := ImmediateMesh.new()
	if not cells.is_empty():
		var y := float(plane_y) + OVERLAY_LIFT
		var cell_set := {}
		for cell: Vector3i in cells: cell_set[cell] = true
		mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		for cell: Vector3i in cells:
			var x := float(cell.x)
			var z := float(cell.z)
			_quad(mesh, x, z, 1.0, 1.0, y, cell_fill)
			if not cell_set.has(cell + Vector3i(-1, 0, 0)): _quad(mesh, x, z, EDGE_INSET, 1.0, y + .005, cell_edge)
			if not cell_set.has(cell + Vector3i(1, 0, 0)): _quad(mesh, x + 1.0 - EDGE_INSET, z, EDGE_INSET, 1.0, y + .005, cell_edge)
			if not cell_set.has(cell + Vector3i(0, 0, -1)): _quad(mesh, x, z, 1.0, EDGE_INSET, y + .005, cell_edge)
			if not cell_set.has(cell + Vector3i(0, 0, 1)): _quad(mesh, x, z + 1.0 - EDGE_INSET, 1.0, EDGE_INSET, y + .005, cell_edge)
		mesh.surface_end()
	target.mesh = mesh
	target.material_override = _material


func _quad(mesh: ImmediateMesh, x: float, z: float, w: float, d: float, y: float, color: Color) -> void:
	for corner: Vector2 in [Vector2(x, z), Vector2(x + w, z), Vector2(x + w, z + d), Vector2(x, z), Vector2(x + w, z + d), Vector2(x, z + d)]:
		mesh.surface_set_color(color)
		mesh.surface_add_vertex(Vector3(corner.x, y, corner.y))
