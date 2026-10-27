extends Node3D

## The Appeal view (doc 23 "The Appeal view"): a view toggle at the dock's end, before X-ray.
## While it is on:
## - the world dims and greys (a full-screen pass, appeal_dim.gdshader);
## - each sealed room's floor takes its appeal word's tint (appeal.json); a room whose floor
##   is above the slice hides, and the open ground stays dim, as only rooms count;
## - the pieces a room counts glow warm, and its loose goods and stocked storage cool;
## - hovering a room's floor shows a card with its word, number and parts, and clicking it
##   opens the room window on its Appeal tab (ObjectExplorerController's terrain clicks reach
##   it as they reach zones).
## It redraws when rooms change and on each refresh while it is on. Presentation only, never
## saved: RoomManager works out the appeal (RoomAppeal).
const Xray = preload("res://scripts/systems/XrayController.gd")
const Picking = preload("res://scripts/components/ObjectPicking.gd")
const Appeal = preload("res://scripts/components/RoomAppeal.gd")
const DIM_SHADER := preload("res://scripts/shaders/appeal_dim.gdshader")
## Seen by the normal camera and by X-ray's; X-ray's own scan leaves terrain-layer nodes alone.
const LAYERS := 1 | Xray.XRAY_LAYER | Xray.TERRAIN_LAYER
const RAY_MAX := 600.0
## How many parts the hover card lists before "and 3 more".
const HOVER_PARTS := 6
## The card sits over the dock and the clock, under menus and toasts (DockUI's layers).
const CARD_LAYER := 22
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
var _tools: Array[Node] = []
var _config: Dictionary = {}
var _dim: MeshInstance3D
var _tints: MultiMeshInstance3D
var _plane := PlaneMesh.new()
var _glow_materials := {}   # "warm" or "cool" -> the overlay
var _glows := {}            # MeshInstance3D -> its overlay before the view
var _appeals := {}          # room id -> RoomManager.all_room_appeals()'s entry
var _tinted := {}           # what the tints last showed: the slice, and each room's word
var room_tints := {}        # room id -> {colour, count}: what the floor quads show
var _dirty := true
var _refresh_left := 0.0
var _card_layer: CanvasLayer
var _card: Control
var _hovered := -1


func _ready() -> void:
	add_to_group("appeal_view")
	dock = get_node_or_null(dock_path)
	slice = get_node_or_null(slice_path)
	rooms_tool = get_node_or_null(rooms_tool_path)
	_config = UIRegistry.get_time_slice().get("appeal", {})
	_plane.size = Vector2.ONE
	var tones := {"warm": String(_config.get("warm_glow", "#ffcf6a80")), "cool": String(_config.get("cool_glow", "#7d8cff99"))}
	for tone: String in tones:
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = Color(tones[tone])
		material.render_priority = 20   # after the dim and the tints
		_glow_materials[tone] = material
	RoomManager.room_updated.connect(_mark_dirty)
	RoomManager.room_removed.connect(_mark_dirty)
	if slice != null: slice.slice_changed.connect(_mark_dirty)
	set_process(false)
	# Siblings may not have entered the tree yet.
	_bind_tools.call_deferred()
	if dock != null: dock.register_appeal_view(self)


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
		_build()
		_refresh()
	else:
		_teardown()
	set_process(active)
	changed.emit()


## The object explorer's terrain clicks (as zones take theirs): while the view is on, a click
## on a room's floor opens the room window on its Appeal tab.
func try_select_zone_at_screen(screen_pos: Vector2) -> bool:
	if not active or rooms_tool == null: return false
	var hit := room_under(screen_pos)
	return not hit.is_empty() and bool(rooms_tool.open_room_at(hit.cell, "appeal"))


## The sealed room whose floor (or wall) the screen point shows: {id, cell}, or {}.
func room_under(screen_pos: Vector2) -> Dictionary:
	var camera := get_viewport().get_camera_3d()
	if camera == null: return {}
	var origin := camera.project_ray_origin(screen_pos)
	var direction := camera.project_ray_normal(screen_pos).normalized()
	var visible_face := Callable()
	var underground := get_tree().get_first_node_in_group("underground_view")
	if underground != null and underground.is_inspecting(): visible_face = underground.is_terrain_face_visible
	var hit := Picking.terrain_hit(origin, direction, _cut(), RAY_MAX, Callable(), visible_face)
	if hit.is_empty(): return {}
	# The air on the side the ray came from: above a floor, inside a wall.
	var cell := Vector3i(int(hit.x), int(hit.y), int(hit.z)) + Vector3i(hit.normal)
	var id := int(RoomManager.get_room_id_at(cell))
	return {} if id < 0 else {"id": id, "cell": cell}


func _process(delta: float) -> void:
	_refresh_left -= delta
	if _dirty or _refresh_left <= 0.0: _refresh()
	_update_hover()


func _mark_dirty(_value := 0) -> void:
	_dirty = true


# ── Drawing ───────────────────────────────────────────────────────────────────

func _build() -> void:
	_dim = MeshInstance3D.new()
	_dim.name = "AppealDim"
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
	_tints = MultiMeshInstance3D.new()
	_tints.name = "AppealTints"
	var tint := StandardMaterial3D.new()
	tint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tint.vertex_color_use_as_albedo = true
	tint.vertex_color_is_srgb = true
	tint.cull_mode = BaseMaterial3D.CULL_DISABLED
	tint.render_priority = 10   # over the dim, under the glow
	_tints.material_override = tint
	_tints.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_tints.layers = LAYERS
	add_child(_tints)
	_card_layer = CanvasLayer.new()
	_card_layer.name = "AppealCard"
	_card_layer.layer = CARD_LAYER
	add_child(_card_layer)
	_card = preload("res://scripts/ui/HoverCard.gd").new()
	_card.hide()
	_card_layer.add_child(_card)
	_tinted.clear()
	_dirty = true


func _teardown() -> void:
	for mesh: MeshInstance3D in _glows:
		if is_instance_valid(mesh): mesh.material_overlay = _glows[mesh]
	_glows.clear()
	for node: Node in [_dim, _tints, _card_layer]:
		if is_instance_valid(node): node.queue_free()
	_dim = null
	_tints = null
	_card_layer = null
	_card = null
	_appeals.clear()
	_tinted.clear()
	room_tints.clear()
	_hovered = -1


func _refresh() -> void:
	_dirty = false
	_refresh_left = float(_config.get("refresh_seconds", 1.0))
	_appeals = RoomManager.all_room_appeals()
	_draw_tints()
	_draw_glows()
	if _hovered >= 0 and _appeals.has(_hovered): _fill_card(_hovered)


## One quad over each floor cell of each room, in its word's tint; a room whose floor is
## above the slice is left out, as the floor itself is.
func _draw_tints() -> void:
	var cut := _cut()
	var shown := {"cut": cut}
	for id: int in _appeals: shown[id] = String((_appeals[id].word as Dictionary).get("word", ""))
	if shown == _tinted and _tints.multimesh != null: return
	_tinted = shown
	var alpha := float(_config.get("tint_alpha", 0.6))
	var rooms: Dictionary = RoomManager.get_rooms()
	var spots: Array[Vector3i] = []
	var colours: Array[Color] = []
	room_tints.clear()
	for id: int in _appeals:
		var cells: Dictionary = (rooms.get(id, {}) as Dictionary).get("cells", {})
		var colour := Color(String((_appeals[id].word as Dictionary).get("tint", "#9a978b")), alpha)
		var count := 0
		for cell: Vector3i in cells:
			# The lowest air of each column stands on the floor.
			if cell.y - 1 > cut or cells.has(cell + Vector3i.DOWN): continue
			spots.append(cell)
			colours.append(colour)
			count += 1
		if count > 0: room_tints[id] = {"colour": colour, "count": count}
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = _plane
	multimesh.instance_count = spots.size()
	for i in range(spots.size()):
		multimesh.set_instance_transform(i, Transform3D(Basis(), Vector3(spots[i].x + 0.5, spots[i].y + 0.02, spots[i].z + 0.5)))
		multimesh.set_instance_color(i, colours[i])
	_tints.multimesh = multimesh


## The pieces each room counts glow warm, its loose goods and stocked storage cool; what no
## room counts any more gets its own overlay back.
func _draw_glows() -> void:
	var wanted := {}
	for id: int in _appeals:
		for tone: String in ["warm", "cool"]:
			for node: Variant in _appeals[id].get(tone, []):
				if not is_instance_valid(node): continue
				for mesh: MeshInstance3D in _meshes(node): wanted[mesh] = _glow_materials[tone]
	for mesh: Variant in _glows.keys():
		if is_instance_valid(mesh) and wanted.has(mesh): continue
		if is_instance_valid(mesh): mesh.material_overlay = _glows[mesh]
		_glows.erase(mesh)
	for mesh: MeshInstance3D in wanted:
		if not _glows.has(mesh): _glows[mesh] = mesh.material_overlay
		mesh.material_overlay = wanted[mesh]


func _meshes(node: Node) -> Array[MeshInstance3D]:
	var meshes: Array[MeshInstance3D] = []
	if node is MeshInstance3D: meshes.append(node)
	for child: Node in node.find_children("*", "MeshInstance3D", true, false): meshes.append(child)
	return meshes


func _cut() -> int:
	return int(slice.get_slice_y()) if slice != null and bool(slice.is_active()) else 1 << 20


# ── The hover card ────────────────────────────────────────────────────────────

func _update_hover() -> void:
	var hit := {} if _hover_blocked() else room_under(get_viewport().get_mouse_position())
	var id := int(hit.get("id", -1))
	if id < 0 or not _appeals.has(id):
		_hovered = -1
		_card.hide()
		return
	if id != _hovered: _fill_card(id)
	var mouse := get_viewport().get_mouse_position()
	_card.point_at(Rect2(mouse - Vector2(10, 10), Vector2(20, 20)), "above")


## No card over the interface, or while a click tool is working.
func _hover_blocked() -> bool:
	if get_viewport().gui_get_hovered_control() != null: return true
	for tool: Node in _tools:
		if is_instance_valid(tool) and tool.has_method("is_active") and bool(tool.call("is_active")): return true
	return false


## The room's name, its word and number, and its parts as the Appeal tab lists them.
func _fill_card(id: int) -> void:
	_hovered = id
	var room: Dictionary = RoomManager.get_rooms().get(id, {})
	var appeal: Dictionary = _appeals[id]
	var parts: Array = appeal.parts
	var lines: PackedStringArray = []
	for i in range(mini(HOVER_PARTS, parts.size())):
		var part: Dictionary = parts[i]
		var count := int(part.count)
		lines.append("%s%s  %s" % ["%d × " % count if count > 1 else "", part.name, Appeal.signed(float(part.value) * count)])
	if parts.size() > HOVER_PARTS: lines.append("and %d more" % (parts.size() - HOVER_PARTS))
	if parts.is_empty(): lines.append("Nothing here adds appeal yet.")
	if float(appeal.share) < 1.0: lines.append("%d floor tiles: counts %d%%" % [int(appeal.tiles), roundi(float(appeal.share) * 100.0)])
	lines.append("Click for the room's appeal.")
	var title: String = rooms_tool.room_title(room, id) if rooms_tool != null else RoomManager.room_label(room)
	_card.show_card(title, "\n".join(lines), "", "%s · %s" % [(appeal.word as Dictionary).get("word", ""), Appeal.number(float(appeal.score))],
		get_viewport().get_visible_rect().size.x >= 1200.0, UIRegistry.get_icon_family_color("system"))
	_card.show()


func _exit_tree() -> void:
	if active: _teardown()
