class_name FlagPlacementController
extends Node3D

## Settlement Flag placement — the Stonehearth-embark slice of doc 06, built
## as doc 16 step 2b. The player toggles the tool (dock 'flag' entry), hovers
## a ghost flag tinted green/red by validity, and left-clicks to place. On
## confirm: the flag spawns as a placed entity (PlacedEntityRegistry's second
## customer after trees), the settlement anchor is recorded, and the starter
## squad spawns around it via DwarfDirector.
##
## Tool input contract (doc 21): ESC cancels the mode; right-mouse stays
## camera orbit and is never consumed. One flag per world (re-placement is out
## of scope, doc 16). State is session-only until the save system.
##
## Raycasting: the flag is a SURFACE placement, so the hover test marches the
## camera ray against the height field (`get_visible_surface_y`) — the
## camera's cursor-zoom approach — rather than the mining controller's full
## voxel DDA. Works map-wide, no streamed chunks required.

@export var camera_path: NodePath
@export var dock_ui_path: NodePath
@export var dwarf_director_path: NodePath

## Visual scale for the flag GLB. The placeholder model is authored one-tile /
## three-blocks-tall (doc 06); tune here if the import reads off-size.
@export var flag_scale: float = 1.0

const FLAG_MODEL := "res://assets/models/items/misc/settlement_flag.glb"
const FLAG_HEIGHT_BLOCKS := 3      # registry box: 1×3×1 (doc 06 footprint)
const WORLD_EDGE_MARGIN := 2       # reject placement hugging the world border
const RAY_STEP := 0.5
const RAY_MAX := 700.0

const GHOST_VALID := Color(0.35, 1.0, 0.45, 0.55)
const GHOST_INVALID := Color(1.0, 0.30, 0.25, 0.55)

signal flag_placed(cell: Vector3i)

var _camera_rig: Node3D = null
var _dock_ui: Node = null
var _director: Node = null

var _active: bool = false
var _ghost: Node3D = null
var _ghost_material: StandardMaterial3D = null
var _hover_cell: Vector3i = Vector3i(-1, -1, -1)
var _hover_valid: bool = false
var _flag_node: Node3D = null
var _flag_occupancy_id: int = -1


func _ready() -> void:
	_camera_rig = get_node_or_null(camera_path) as Node3D
	_dock_ui = get_node_or_null(dock_ui_path)
	_director = get_node_or_null(dwarf_director_path)
	if _dock_ui != null and _dock_ui.has_method("register_flag_controller"):
		_dock_ui.call("register_flag_controller", self)


func _process(_delta: float) -> void:
	if not _active:
		return
	_update_ghost()


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
			if _hover_valid:
				_place_flag(_hover_cell)
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
	if _flag_node != null:
		push_warning("FlagPlacementController: settlement flag already placed (one per world).")
		return
	if not bool(WorldGenerator.get_streaming_stats().get("maps_ready", false)):
		push_warning("FlagPlacementController: maps not ready.")
		return
	_active = true
	_ensure_ghost()
	_ghost.visible = false   # shown on first valid hover update


func deactivate() -> void:
	if not _active:
		return
	_active = false
	if _ghost != null:
		_ghost.visible = false


# ── Hover ghost ───────────────────────────────────────────────────────────────

func _ensure_ghost() -> void:
	if _ghost != null:
		return
	_ghost = Node3D.new()
	_ghost.name = "FlagGhost"
	var visual := _instance_flag_visual()
	if visual != null:
		_ghost_material = StandardMaterial3D.new()
		_ghost_material.vertex_color_use_as_albedo = true
		_ghost_material.albedo_color = GHOST_VALID
		_ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_ghost_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_ghost_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_ghost_material.no_depth_test = false
		_apply_material(visual, _ghost_material)
		_ghost.add_child(visual)
	add_child(_ghost)


func _update_ghost() -> void:
	var hit := _mouse_surface_cell()
	if hit.is_empty():
		_hover_cell = Vector3i(-1, -1, -1)
		_hover_valid = false
		if _ghost != null:
			_ghost.visible = false
		return
	var cell := Vector3i(hit["x"], hit["y"], hit["z"])
	_hover_cell = cell
	_hover_valid = _is_valid_cell(cell)
	if _ghost != null:
		_ghost.visible = true
		_ghost.position = Vector3(float(cell.x) + 0.5, float(cell.y + 1), float(cell.z) + 0.5)
		if _ghost_material != null:
			_ghost_material.albedo_color = GHOST_VALID if _hover_valid else GHOST_INVALID


## Marches the mouse ray against the visible-surface height field (the camera
## zoom approach, doc 21) and returns { x, y (surface block), z } or {}.
func _mouse_surface_cell() -> Dictionary:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return {}
	var mouse := get_viewport().get_mouse_position()
	var origin := camera.project_ray_origin(mouse)
	var dir := camera.project_ray_normal(mouse)
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


## Validity (doc 16 Phase 1): in-bounds with edge margin, dry standable
## surface, cell not occupied by a placed entity (tree trunk).
func _is_valid_cell(cell: Vector3i) -> bool:
	if cell.x < WORLD_EDGE_MARGIN or cell.x >= WorldGenerator.WORLD_SIZE_X - WORLD_EDGE_MARGIN \
			or cell.z < WORLD_EDGE_MARGIN or cell.z >= WorldGenerator.WORLD_SIZE_Z - WORLD_EDGE_MARGIN:
		return false
	var col := Vector2i(cell.x, cell.z)
	if WorldGenerator.lake_columns.has(col) or WorldGenerator.tarn_columns.has(col):
		return false
	if cell.y <= 3:   # Bedrock Protocol sanity — never anchor on the bedrock slab
		return false
	if PlacedEntityRegistry.occupies(Vector3i(cell.x, cell.y + 1, cell.z)):
		return false
	return true


# ── Placement ─────────────────────────────────────────────────────────────────

func _place_flag(cell: Vector3i) -> void:
	_flag_node = Node3D.new()
	_flag_node.name = "SettlementFlag"
	var visual := _instance_flag_visual()
	if visual != null:
		_flag_node.add_child(visual)
	_flag_node.position = Vector3(float(cell.x) + 0.5, float(cell.y + 1), float(cell.z) + 0.5)
	add_child(_flag_node)

	_flag_occupancy_id = PlacedEntityRegistry.register_box(
		Vector3i(cell.x, cell.y + 1, cell.z),
		Vector3i(1, FLAG_HEIGHT_BLOCKS, 1))

	if _director != null:
		_director.call("set_settlement_anchor", cell)
		_director.call("spawn_squad_at", cell.x, cell.z)

	print("FlagPlacementController: settlement founded at %s." % str(cell))
	flag_placed.emit(cell)
	deactivate()


func _instance_flag_visual() -> Node3D:
	if not ResourceLoader.exists(FLAG_MODEL):
		push_error("FlagPlacementController: missing %s" % FLAG_MODEL)
		return null
	var packed := load(FLAG_MODEL) as PackedScene
	if packed == null:
		return null
	var visual := packed.instantiate() as Node3D
	if visual == null:
		return null
	visual.scale = Vector3.ONE * flag_scale
	# Project-standard world-object material (vertex colour, lit, double-sided)
	# for the PLACED flag; the ghost overrides this with its tinted material.
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mat.metallic = 0.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	_apply_material(visual, mat)
	return visual


func _apply_material(node: Node, mat: Material) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = mat
	for child in node.get_children():
		_apply_material(child, mat)
