class_name FurniturePlacementController
extends Node3D

## Furniture placement tool — doc 19 §3.2 (Phase 2 scope).
##
## The FlagPlacementController generalised and made data-driven: the Place
## catalog activates this tool for one furniture def with available stock; the player
## aims a translucent placed-form ghost (validity-tinted, R rotates 90°),
## and confirming plants a persistent FurnitureGhostComponent — the SH
## "ghost form as standing task marker". FETCH_BUILD leases fetch the finished
## item and install it. Uninstall and the legacy DEV build path remain separate.
## The catalog is presentation only; this controller owns inventory availability
## and the final-click stock guard (doc 54).
##
## REGISTRY PATTERN: this node is the ONE owner of data/furniture/*.json.
## Defs are placeable iff they carry both `placement` and `item_key`
## (art doc 37 adds these fields to the formerly unplaceable trade counter).
##
## TOOL CONTRACT (docs 21/43, the 2026-07-06 exclusion fix): ESC-only
## cancel; RMB stays camera orbit; announces via tool_requested("furniture")
## and deactivates when any other click-tool announces. Ghost/installed
## pieces stay click-SELECTABLE while the tool is off (the doc 18 A3 lesson,
## built in from day one).
##
## GHOSTS ARE NON-SOLID (SH parity): no occupancy, no nav impact. Installed
## pieces register their collision_regions boxes with PlacedEntityRegistry —
## NavGrid invalidates via occupancy_changed (the flag/tree precedent).
##
## DOC 22 (doors + sealed rooms): base:furniture:door ships with EMPTY
## collision_regions on purpose — it must stay walkable, only NavGrid-blocking
## furniture uses collision boxes. Every install/uninstall calls
## RoomManager.on_furniture_changed() directly (see that autoload's header for
## why this isn't a signal subscription).

@export var dock_ui_path: NodePath
@export var slice_controller_path: NodePath

const TOOL_ID := "furniture"
const FURNITURE_DIR := "res://data/furniture"
const SLICE_OFF_Y := 127
const RAY_MAX := 600.0
const WORLD_EDGE_MARGIN := 2
const WallMount = preload("res://scripts/components/WallFurnitureMount.gd")
const Lighting = preload("res://scripts/components/FurnitureLighting.gd")
const Picking = preload("res://scripts/components/ObjectPicking.gd")
var _picking := Picking.new()
const Seating = preload("res://scripts/components/FurnitureSeating.gd")
var _seating := Seating.new(self)

## Ghost material: the real model, translucent (SH ghost_item parity —
## alpha 0.3, doc 19 decision 7). Validity modulates the tint.
const GHOST_ALPHA := 0.30
const TINT_VALID := Color(0.65, 1.0, 0.9)
const TINT_INVALID := Color(1.0, 0.4, 0.35)
const TINT_PLACED := Color(0.8, 0.95, 1.0)

signal ghost_placed(ghost_id: int)
signal ghost_cancelled(ghost_id: int)
signal furniture_installed(furniture_key: String, origin_cell: Vector3i)
signal furniture_uninstalled(furniture_key: String, origin_cell: Vector3i)
signal catalog_changed()
signal tool_active_changed(active: bool)
var _catalog_pending := false
var _require_stock := false

var _defs: Dictionary = {}            # furniture_key -> def Dictionary
var _model_bounds: Dictionary = {}    # model path -> cached root-local visual AABB
var _dock_ui: Node = null
var _slice_y: int = SLICE_OFF_Y

var _active: bool = false
var _active_key: String = ""          # def being placed while the tool is on
var _yaw: int = 0
var _hover_cell: Vector3i = Vector3i(-1, -1, -1)
var _hover_valid: bool = false
var _invalid_reason: String = ""     # "" | "cell" | "wall" (hint label text)
var _hint_label: Label = null

var _preview: Node3D = null           # cursor ghost (one per activation)
var _preview_material: StandardMaterial3D = null

var _next_ghost_id: int = 1
var _ghosts: Dictionary = {}          # ghost_id -> FurnitureGhostComponent
var _cell_to_ghost: Dictionary = {}   # Vector3i -> ghost_id

var _next_installed_id: int = 1
var _installed: Dictionary = {}       # id -> InstalledFurnitureComponent
var _cell_to_installed: Dictionary = {}   # Vector3i -> installed id
var _wall_to_ghost: Dictionary = {}      # Vector4i(floor x,y,z,yaw) -> ghost id
var _wall_to_installed: Dictionary = {}  # separate from floor reservations
var _wall_dirty: bool = false

# ── Work-source plumbing (doc 19 Phase 3) ─────────────────────────────────────
const LEASE_REFRESH_S := 0.25         # the StockpileManager throttle pattern
var _source_to_ghost: Dictionary = {}     # source_id -> ghost_id
var _source_to_installed: Dictionary = {} # source_id -> installed_id
var _drop_manager: Node3D = null
var _wakes_connected: bool = false
var _lease_dirty: bool = false
var _lease_accum: float = 0.0

var _window_layer: CanvasLayer = null
var _window_panel: PanelContainer = null
var _window_title: Label = null
var _window_info: Label = null
var _window_build_btn: Button = null
var _window_remove_btn: Button = null
var _window_ghost_id: int = -1
var _window_installed_id: int = -1


func _ready() -> void:
	ghost_placed.connect(func(_id: int): _mark_catalog_dirty())
	ghost_cancelled.connect(func(_id: int): _mark_catalog_dirty())
	furniture_installed.connect(func(_key: String, _cell: Vector3i): _mark_catalog_dirty())
	furniture_uninstalled.connect(func(_key: String, _cell: Vector3i): _mark_catalog_dirty())
	add_to_group("furniture_controller")
	add_to_group("object_explorer_provider")
	add_to_group(SaveManager.OWNER_GROUP)
	_load_defs()
	_dock_ui = get_node_or_null(dock_ui_path)
	if _dock_ui != null:
		if _dock_ui.has_method("register_furniture_controller"):
			_dock_ui.call("register_furniture_controller", self)
		if _dock_ui.has_signal("tool_requested"):
			_dock_ui.connect("tool_requested", _on_tool_requested)
	var slice_controller := get_node_or_null(slice_controller_path)
	if slice_controller != null and slice_controller.has_signal("slice_changed"):
		slice_controller.connect("slice_changed", _on_slice_changed)
	# Task-event routing for our two work-source families (doc 19 Phase 3).
	TaskManager.task_completed.connect(func(task: Task) -> void: _route_task_gone(task, -1))
	TaskManager.task_cancelled.connect(func(task: Task) -> void: _route_task_gone(task, task.assigned_to))
	TaskManager.task_failed.connect(func(task: Task, _reason: String) -> void: _route_task_gone(task, task.assigned_to))
	TaskManager.task_released.connect(_on_task_released)
	StockpileManager.stockpile_changed.connect(func(_k: String, _d: int) -> void: _mark_lease_dirty())
	WorldData.chunk_dirtied.connect(_on_terrain_changed, CONNECT_DEFERRED)
	PlacedEntityRegistry.occupancy_changed.connect(func(_lo: Vector3i, _size: Vector3i): _seating.dirty = true)
	_build_window()


## Sole reader of data/furniture/*.json (registry pattern). Placeable defs
## must carry the doc 19 fields; incomplete definitions are skipped.
func _load_defs() -> void:
	var dir := DirAccess.open(FURNITURE_DIR)
	if dir == null:
		push_error("FurniturePlacementController: cannot open %s." % FURNITURE_DIR)
		return
	for file_name in dir.get_files():
		if not file_name.ends_with(".json"):
			continue
		var path := "%s/%s" % [FURNITURE_DIR, file_name]
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			continue
		var json := JSON.new()
		if json.parse(file.get_as_text()) != OK:
			push_error("FurniturePlacementController: parse error in %s — %s" % [path, json.get_error_message()])
			file.close()
			continue
		file.close()
		var def: Dictionary = json.data
		var key := String(def.get("furniture_key", ""))
		if key.is_empty():
			continue
		if not def.has("placement") or not def.has("item_key"):
			continue   # incomplete placement definition
		_defs[key] = def
	print("FurniturePlacementController: %d placeable defs loaded." % _defs.size())


func get_defs() -> Dictionary:
	return _defs


## Requests without a committed item reserve shared loose/storage availability
## by item_key, including older saved plans. Claimed/fetched/carrying plans have
## already removed their unit from that pool and must not subtract it again.
func get_catalog_stock() -> Dictionary:
	var loose: Dictionary = _drop_manager.get_unreserved_counts() if is_instance_valid(_drop_manager) else {}
	var outgoing := StockpileManager.get_outgoing_totals()
	var pending := {}
	var requested := {}
	for ghost: FurnitureGhostComponent in _ghosts.values():
		requested[ghost.furniture_key] = int(requested.get(ghost.furniture_key, 0)) + 1
		if not ghost.has_committed_item():
			pending[ghost.item_key] = int(pending.get(ghost.item_key, 0)) + 1
	var result := {}
	for key: String in _defs:
		var item_key := String(_defs[key].item_key)
		result[key] = {"available": maxi(0, int(loose.get(item_key, 0)) + StockpileManager.get_total(item_key)
			- int(outgoing.get(item_key, 0)) - int(pending.get(item_key, 0))), "reserved": int(requested.get(key, 0))}
	return result


func active_furniture_key() -> String:
	return _active_key if _active else ""


func has_pending_placement(ghost_id: int) -> bool:
	return _ghosts.has(ghost_id)


func _mark_catalog_dirty() -> void:
	if _catalog_pending: return
	_catalog_pending = true
	_emit_catalog_changed.call_deferred()


func _emit_catalog_changed() -> void:
	_catalog_pending = false
	if _active and _require_stock and int(get_catalog_stock().get(_active_key, {}).get("available", 0)) <= 0:
		deactivate()
	catalog_changed.emit()


func get_stats() -> Dictionary:
	var uninstalling := 0
	for installed_id: int in _installed:
		if (_installed[installed_id] as InstalledFurnitureComponent).flagged_uninstall:
			uninstalling += 1
	return { "ghosts": _ghosts.size(), "installed": _installed.size(), "uninstalling": uninstalling }


## Zone/furniture mutual exclusion (doc 19 Phase 2 acceptance): the zone
## tool rejects cells covered by any ghost footprint or installed piece.
func blocks_zone_cell(cell: Vector3i) -> bool:
	return _cell_to_ghost.has(cell) or _cell_to_installed.has(cell)


# ── Tool state ────────────────────────────────────────────────────────────────

func is_active() -> bool:
	return _active


func activate_for(furniture_key: String, require_stock: bool = false) -> void:
	if not _defs.has(furniture_key):
		push_warning("FurniturePlacementController: unknown def '%s'." % furniture_key)
		return
	if not bool(WorldGenerator.get_streaming_stats().get("maps_ready", false)):
		push_warning("FurniturePlacementController: maps not ready.")
		return
	if require_stock and int(get_catalog_stock().get(furniture_key, {}).get("available", 0)) <= 0:
		return
	deactivate()   # clean swap if a different def was active
	_require_stock = require_stock
	_active = true
	_active_key = furniture_key
	_yaw = 0
	_ensure_preview()
	tool_active_changed.emit(true)


func deactivate() -> void:
	if not _active:
		return
	_active = false
	_active_key = ""
	_free_preview()
	_require_stock = false
	tool_active_changed.emit(false)


func _on_tool_requested(tool_id: String) -> void:
	# One active click-tool at a time (2026-07-06 contract). Our own id is
	# announced by DockUI right before activate_for — deactivating here is
	# harmless (activate_for re-arms with the chosen def).
	if _active:
		deactivate()
	if tool_id == TOOL_ID:
		pass   # DockUI calls activate_for(key) immediately after this signal


# ── Input ─────────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	# Lazy sibling hookup (the StockpileManager pattern) + throttled lease pass.
	if not _wakes_connected:
		_drop_manager = get_tree().get_first_node_in_group("item_drop_manager") as Node3D
		if _drop_manager != null:
			_drop_manager.connect("drop_spawned", func(_key: String) -> void: _mark_lease_dirty())
			_drop_manager.connect("loose_items_changed", _mark_catalog_dirty)
			_mark_catalog_dirty()
			_wakes_connected = true
			for ghost_id: int in _ghosts:
				(_ghosts[ghost_id] as FurnitureGhostComponent).drop_manager = _drop_manager
	if _wall_dirty:
		_wall_dirty = false
		_revalidate_wall_mounts()
	if _lease_dirty:
		_lease_accum += delta
		if _lease_accum >= LEASE_REFRESH_S:
			_lease_accum = 0.0
			_lease_dirty = false
			for ghost_id: int in _ghosts:
				(_ghosts[ghost_id] as FurnitureGhostComponent).update_lease()
	if not _active:
		return
	_update_hover()


func _mark_lease_dirty() -> void:
	_lease_dirty = true
	_mark_catalog_dirty()


# ── Task-event routing (doc 19 Phase 3 — the StockpileManager shape) ──────────

func _route_task_gone(task: Task, dwarf_id: int) -> void:
	if _source_to_ghost.has(task.source_id):
		var ghost: FurnitureGhostComponent = _ghosts.get(int(_source_to_ghost[task.source_id]))
		if ghost != null:
			ghost.on_task_gone(task.id, dwarf_id)
		_mark_lease_dirty()
	elif _source_to_installed.has(task.source_id):
		var installed: InstalledFurnitureComponent = _installed.get(int(_source_to_installed[task.source_id]))
		if installed != null:
			installed.on_task_gone(task.id, dwarf_id)


func _on_task_released(task: Task, dwarf_id: int, _reason: int) -> void:
	_mark_catalog_dirty()
	# Released leases return to PENDING — only the dwarf's reservations free.
	if _source_to_ghost.has(task.source_id):
		var ghost: FurnitureGhostComponent = _ghosts.get(int(_source_to_ghost[task.source_id]))
		if ghost != null:
			ghost.cancel_fetch(dwarf_id)


func _unhandled_input(event: InputEvent) -> void:
	if not _active:
		# The shared explorer arbitrates the nearest tree/furniture hit in the main
		# scene. Standalone art fixtures keep the legacy selection entry point.
		if get_tree().get_first_node_in_group("object_explorer") != null:
			return
		# Ghost/installed pieces stay selectable with the tool off (A3 lesson).
		if event is InputEventMouseButton:
			var mb_off := event as InputEventMouseButton
			if mb_off.pressed and mb_off.button_index == MOUSE_BUTTON_LEFT \
					and _try_select_at_screen(mb_off.position):
				get_viewport().set_input_as_handled()
		return
	if event is InputEventKey:
		var key := event as InputEventKey
		if not key.pressed:
			return
		if key.keycode == KEY_ESCAPE:
			deactivate()
			get_viewport().set_input_as_handled()
		elif key.keycode == KEY_R:
			_yaw = (_yaw + 1) % 4
			_update_hover(true)
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
			return
		_update_hover(true, mb.position) # Recheck obstruction at the actual click.
		if _seating.snap.is_empty() and _try_select_at_screen(mb.position):
			get_viewport().set_input_as_handled()
			return
		if _hover_valid:
			_confirm_ghost()
			get_viewport().set_input_as_handled()


# ── Hover / validity ──────────────────────────────────────────────────────────

func _update_hover(force: bool = false, screen_pos: Vector2 = Vector2.INF) -> void:
	var pointer := get_viewport().get_mouse_position() if screen_pos == Vector2.INF else screen_pos
	var hit := _surface_cell_for(pointer)
	if WallMount.is_wall(_defs.get(_active_key, {})):
		var prior_yaw := _yaw
		hit = _wall_floor_hit(hit)
		force = force or _yaw != prior_yaw
	if hit.is_empty():
		_seating.reset()
		_hover_cell = Vector3i(-1, -1, -1)
		_hover_valid = false
		if _preview != null:
			_preview.visible = false
		if _hint_label != null:
			_hint_label.visible = false
		return
	var cell := Vector3i(int(hit["x"]), int(hit["y"]), int(hit["z"]))
	if cell == _seating.aim and not force and not _seating.dirty:
		return
	_seating.resolve(cell)
	if not _seating.snap.is_empty():
		cell = _seating.snap.origin
		_yaw = _seating.snap.yaw
	_hover_cell = cell
	_hover_valid = _placement_valid(cell)
	_position_preview(cell)


func _placement_valid(origin: Vector3i) -> bool:
	_invalid_reason = ""
	var def: Dictionary = _defs.get(_active_key, {})
	if WallMount.is_wall(def):
		return _wall_placement_valid(def, origin, _yaw)
	_invalid_reason = _floor_placement_reason(def, origin, _yaw)
	return _invalid_reason.is_empty()


func _floor_placement_reason(def: Dictionary, origin: Vector3i, yaw: int) -> String:
	if not _piece_visible(def, origin, yaw):
		return "slice"
	for cell: Vector3i in _footprint_cells(def, origin, yaw):
		if not _is_valid_cell(cell):
			return "cell"
	if String(def.get("placement", "floor")) == "floor_wall" and not _has_wall_behind(def, origin, yaw):
		return "wall"
	if (not _wall_to_ghost.is_empty() or not _wall_to_installed.is_empty()) \
			and _intersects_wall_piece(_visual_bounds(def, origin, yaw)):
		return "overlap"
	return _seating.placement_reason(def, origin, yaw)


func get_dining_seats(table_id: int) -> Array[Dictionary]:
	return _seating.installed_seats(table_id)


func _wall_key(origin: Vector3i, yaw: int) -> Vector4i:
	return Vector4i(origin.x, origin.y, origin.z, posmod(yaw, 4))


func _bounds_cells(bounds: AABB) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	var low := bounds.position + Vector3.ONE * .0001
	var high := bounds.end - Vector3.ONE * .0001
	for x in range(floori(low.x), ceili(high.x)):
		for y in range(floori(low.y), ceili(high.y)):
			for z in range(floori(low.z), ceili(high.z)):
				result.append(Vector3i(x, y, z))
	return result


func _wall_structure_valid(def: Dictionary, origin: Vector3i, yaw: int) -> bool:
	if origin.x < WORLD_EDGE_MARGIN or origin.x >= WorldGenerator.WORLD_SIZE_X - WORLD_EDGE_MARGIN \
			or origin.z < WORLD_EDGE_MARGIN or origin.z >= WorldGenerator.WORLD_SIZE_Z - WORLD_EDGE_MARGIN \
			or origin.y <= 3:
		return false
	if not BlockRegistry.is_solid(_block_id(origin.x, origin.y, origin.z)):
		return false
	for support: Vector3i in WallMount.supports(def, origin, yaw):
		if not BlockRegistry.is_solid(_block_id(support.x, support.y, support.z)):
			return false
	for cell: Vector3i in _bounds_cells(WallMount.bounds_for(def, origin, yaw)):
		if cell.y >= WorldData.WORLD_SIZE_Y or _block_id(cell.x, cell.y, cell.z) != BlockRegistry.AIR_ID:
			return false
	return true


func _wall_placement_valid(def: Dictionary, origin: Vector3i, yaw: int) -> bool:
	if not _wall_structure_valid(def, origin, yaw):
		_invalid_reason = "wall"
		return false
	if not _piece_visible(def, origin, yaw):
		_invalid_reason = "slice"
		return false
	var key := _wall_key(origin, yaw)
	var bounds: AABB = WallMount.bounds_for(def, origin, yaw)
	if _wall_to_ghost.has(key) or _wall_to_installed.has(key) or _intersects_wall_piece(bounds):
		_invalid_reason = "overlap"
		return false
	for cell: Vector3i in _bounds_cells(bounds):
		if PlacedEntityRegistry.occupies(cell):
			_invalid_reason = "overlap"
			return false
	for ghost: FurnitureGhostComponent in _ghosts.values():
		if WallMount.is_wall(ghost.def):
			continue
		if bounds.intersects(_visual_bounds(ghost.def, ghost.origin_cell, ghost.yaw_steps)):
			_invalid_reason = "overlap"
			return false
	for piece: InstalledFurnitureComponent in _installed.values():
		if not WallMount.is_wall(piece.def) and bounds.intersects(_visual_bounds(piece.def, piece.origin_cell, piece.yaw_steps)):
			_invalid_reason = "overlap"
			return false
	var seat_reason := _seating.placement_reason(def, origin, yaw)
	if not seat_reason.is_empty():
		_invalid_reason = seat_reason
		return false
	if WallMount.nearest_stand(origin, origin).x < 0:
		_invalid_reason = "access"
		return false
	return true


## Visual overlap is separate from NavGrid occupancy: a four-high door is
## walkable but still cannot pass through an elevated torch. Cache per asset.
func _visual_bounds(def: Dictionary, origin: Vector3i, yaw: int) -> AABB:
	var path := String(def.get("model", ""))
	if not _model_bounds.has(path):
		var packed := load(path) as PackedScene
		if packed == null:
			return AABB()
		var model := packed.instantiate() as Node3D
		var boxes: Array[AABB] = []
		_collect_mesh_bounds(model, Transform3D.IDENTITY, boxes)
		model.free()
		var combined := AABB()
		for i in range(boxes.size()):
			combined = boxes[i] if i == 0 else combined.merge(boxes[i])
		_model_bounds[path] = combined
	return Transform3D(Basis(Vector3.UP, float(yaw)*PI*.5), _world_pos(def, origin, yaw)) * (_model_bounds[path] as AABB)


func _collect_mesh_bounds(node: Node, parent_transform: Transform3D, boxes: Array[AABB]) -> void:
	var transform := parent_transform
	if node is Node3D:
		transform = parent_transform * (node as Node3D).transform
	if node is MeshInstance3D:
		boxes.append(transform * (node as MeshInstance3D).get_aabb())
	for child in node.get_children():
		_collect_mesh_bounds(child, transform, boxes)


func _intersects_wall_piece(bounds: AABB) -> bool:
	for id: int in _wall_to_ghost.values():
		var ghost: FurnitureGhostComponent = _ghosts[id]
		if bounds.intersects(WallMount.bounds_for(ghost.def, ghost.origin_cell, ghost.yaw_steps).grow(-.0001)):
			return true
	for id: int in _wall_to_installed.values():
		var piece: InstalledFurnitureComponent = _installed[id]
		if bounds.intersects(WallMount.bounds_for(piece.def, piece.origin_cell, piece.yaw_steps).grow(-.0001)):
			return true
	return false


func _on_terrain_changed(_cx: int, _cy: int, _cz: int) -> void:
	_seating.dirty = true
	if not _wall_to_ghost.is_empty() or not _wall_to_installed.is_empty():
		_wall_dirty = true
	if _active:
		_hover_cell = Vector3i(-1, -1, -1) # refresh stationary cursor after mining


func _revalidate_wall_mounts() -> void:
	for id: int in _wall_to_ghost.values():
		var ghost: FurnitureGhostComponent = _ghosts[id]
		if not _wall_structure_valid(ghost.def, ghost.origin_cell, ghost.yaw_steps):
			cancel_ghost(id)
	for id: int in _wall_to_installed.values():
		var piece: InstalledFurnitureComponent = _installed[id]
		if not _wall_structure_valid(piece.def, piece.origin_cell, piece.yaw_steps):
			_teardown_installed(id, true)


## Aim at a vertical terrain face to choose its orientation automatically.
## Floor aiming still supports R, including slice views that cut the wall away.
func _wall_floor_hit(hit: Dictionary) -> Dictionary:
	if hit.is_empty():
		return {}
	var normal: Vector3i = hit.get("normal", Vector3i.ZERO)
	if normal.y != 0 or normal == Vector3i.ZERO:
		return hit
	var cell := Vector3i(int(hit.x), int(hit.y), int(hit.z)) + normal
	for yaw in range(4):
		if WallMount.back(yaw) == -normal:
			_yaw = yaw
			break
	for y in range(cell.y, 3, -1):
		if BlockRegistry.is_solid(_block_id(cell.x, y, cell.z)):
			return {"x":cell.x, "y":y, "z":cell.z}
	return {}


func _is_valid_cell(cell: Vector3i) -> bool:
	if cell.x < WORLD_EDGE_MARGIN or cell.x >= WorldGenerator.WORLD_SIZE_X - WORLD_EDGE_MARGIN \
			or cell.z < WORLD_EDGE_MARGIN or cell.z >= WorldGenerator.WORLD_SIZE_Z - WORLD_EDGE_MARGIN:
		return false
	if cell.y <= 3:
		return false
	var col := Vector2i(cell.x, cell.z)
	if WorldGenerator.lake_columns.has(col) or WorldGenerator.tarn_columns.has(col):
		return false
	if _cell_to_ghost.has(cell) or _cell_to_installed.has(cell):
		return false
	# Zones and furniture never overlap (mutual — the zone tool checks us too).
	var zone_controller := get_tree().get_first_node_in_group("stockpile_controller")
	if zone_controller != null and zone_controller.has_method("is_zone_cell") \
			and bool(zone_controller.call("is_zone_cell", cell)):
		return false
	# Walkable = solid floor + 3-air clearance + no entity footprint (NavGrid).
	return NavGrid.is_walkable(cell)


## floor_wall pieces (the shelf): every BACK-row cell needs a solid block
## directly behind the back face at standing height. Back = local -Z rotated
## by yaw (yaw 0 backs onto north/-Z).
func _has_wall_behind(def: Dictionary, origin: Vector3i, yaw: int) -> bool:
	var back: Vector3i = [Vector3i(0,0,-1), Vector3i(-1,0,0), Vector3i(0,0,1), Vector3i(1,0,0)][posmod(yaw,4)]
	for cell: Vector3i in _footprint_cells(def, origin, yaw):
		var wall := cell + back
		if not BlockRegistry.is_solid(_block_id(wall.x, wall.y + 1, wall.z)):
			return false
	return true


func _yaw_dir(local: Vector3i) -> Vector3i:
	match _yaw % 4:
		1: return Vector3i(local.z, local.y, -local.x)
		2: return Vector3i(-local.x, local.y, -local.z)
		3: return Vector3i(-local.z, local.y, local.x)
	return local


func _footprint_cells(def: Dictionary, origin: Vector3i, yaw: int) -> Array[Vector3i]:
	if WallMount.is_wall(def):
		return []
	var fp: Dictionary = def.get("footprint", {})
	var w := int(fp.get("width", 1))
	var d := int(fp.get("depth", 1))
	if yaw % 2 == 1:
		var t := w
		w = d
		d = t
	var cells: Array[Vector3i] = []
	for dx: int in range(w):
		for dz: int in range(d):
			cells.append(origin + Vector3i(dx, 0, dz))
	return cells


func _block_id(wx: int, wy: int, wz: int) -> int:
	if WorldData.chunk_exists(wx >> 4, wy >> 4, wz >> 4):
		return WorldData.get_block(wx, wy, wz)
	return WorldGenerator.get_generated_block_id(wx, wy, wz)


# ── Ghost visuals ─────────────────────────────────────────────────────────────

func _ensure_preview() -> void:
	_free_preview()
	_preview_material = _make_ghost_material()
	_preview = _instance_model(_active_key, _preview_material)
	if _preview != null:
		add_child(_preview)
		_preview.visible = false
	_update_hover(true)


func _free_preview() -> void:
	_seating.reset()
	if _preview != null:
		_preview.queue_free()
		_preview = null
	if _hint_label != null:
		_hint_label.visible = false
	_hover_cell = Vector3i(-1, -1, -1)
	_hover_valid = false


func _position_preview(origin: Vector3i) -> void:
	if _preview == null:
		return
	_preview.visible = origin.x >= 0 and _piece_visible(_defs.get(_active_key, {}), origin, _yaw)
	_preview.position = _world_pos(_defs.get(_active_key, {}), origin, _yaw)
	_preview.rotation = Vector3(0.0, float(_yaw) * PI * 0.5, 0.0)
	var tint := TINT_VALID if _hover_valid else TINT_INVALID
	_preview_material.albedo_color = Color(tint.r, tint.g, tint.b, GHOST_ALPHA)
	_update_hint(origin)


## Why-invalid hint (the mining-ruler lesson: never make the player guess).
## Shown only for the wall requirement — plain cell blockage is self-evident.
func _update_hint(_origin: Vector3i) -> void:
	if _hint_label == null:
		var layer := CanvasLayer.new()
		layer.layer = 21
		add_child(layer)
		_hint_label = Label.new()
		_hint_label.name = "PlacementHint"
		_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hint_label.add_theme_font_size_override("font_size", 16)
		UITheme.apply_surface(_hint_label)
		_hint_label.add_theme_color_override("font_color", UITheme.HEARTH_TEXT)
		_hint_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, .9))
		_hint_label.add_theme_constant_override("outline_size", 6)
		layer.add_child(_hint_label)
	var wall := WallMount.is_wall(_defs.get(_active_key, {}))
	var hints := {"wall":"Needs a solid wall and four blocks of room height — R rotates",
		"overlap":"Another piece occupies this space", "access":"A dwarf needs room to reach this wall",
		"slice":"Raise the slice to show this furniture",
		"seat_clearance":"Leave room for a seated dwarf’s head",
		"seat_access":"Leave an open tile beside or behind the chair",
		"seat_capacity":"Table chair limit reached — cancel or remove a chair to choose another side",
		"cell":"This position is occupied or has no clear floor"}
	_hint_label.text = String(hints.get(_invalid_reason, "Point at a wall, or aim beside it and press R" if wall else ""))
	if _hover_valid and not _seating.snap.is_empty():
		_hint_label.text = "Table seat — chair faces inward. Click to place; Esc to finish."
	_hint_label.visible = not _hint_label.text.is_empty()
	_hint_label.position = Vector2(20, get_viewport().get_visible_rect().size.y - 180)


## Node position for a footprint: the footprint centre on the floor top
## (models are authored centred on X=Z=0 with base at Y=0).
func _world_pos(def: Dictionary, origin: Vector3i, yaw: int) -> Vector3:
	if WallMount.is_wall(def):
		return WallMount.position_for(def, origin, yaw)
	var fp: Dictionary = def.get("footprint", {})
	var w := int(fp.get("width", 1))
	var d := int(fp.get("depth", 1))
	if yaw % 2 == 1:
		var t := w
		w = d
		d = t
	return Vector3(
		float(origin.x) + float(w) * 0.5,
		float(origin.y + 1),
		float(origin.z) + float(d) * 0.5)


func _make_ghost_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 1.0, 1.0, GHOST_ALPHA)
	mat.roughness = 1.0
	mat.metallic = 0.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = false
	return mat


## Project-standard solid material (doc 61 — lit per-pixel, double-sided).
func _make_solid_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mat.metallic = 0.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	return mat


func _instance_model(furniture_key: String, override: Material, definition: Dictionary = {}) -> Node3D:
	var def: Dictionary = _defs.get(furniture_key, {}) if definition.is_empty() else definition
	var path := String(def.get("model", ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		push_error("FurniturePlacementController: missing model '%s' for %s." % [path, furniture_key])
		return null
	var scene := load(path) as PackedScene
	if scene == null:
		return null
	var node := scene.instantiate() as Node3D
	_apply_material(node, override)
	return node


func _apply_material(node: Node, mat: Material) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = mat
	for child in node.get_children():
		_apply_material(child, mat)


# ── Ghost lifecycle ───────────────────────────────────────────────────────────

func _confirm_ghost(definition: Dictionary = {}) -> void:
	# Enforce the catalog contract at the actual click too. Restore/legacy art
	# fixtures still create standing requests through the unrestricted path.
	if _require_stock and definition.is_empty() and int(get_catalog_stock().get(_active_key, {}).get("available", 0)) <= 0:
		deactivate()
		return
	_seating.dirty = true
	var def: Dictionary = _defs.get(_active_key, {}) if definition.is_empty() else definition
	var ghost := FurnitureGhostComponent.new()
	ghost.setup(_next_ghost_id, _active_key, def, _hover_cell, _yaw)
	var mat := _make_ghost_material()
	mat.albedo_color = Color(TINT_PLACED.r, TINT_PLACED.g, TINT_PLACED.b, GHOST_ALPHA)
	var node := _instance_model(_active_key, mat, def)
	if node != null:
		add_child(node)
		node.position = _world_pos(def, _hover_cell, _yaw)
		node.rotation = Vector3(0.0, float(_yaw) * PI * 0.5, 0.0)
		node.visible = _piece_visible(def, _hover_cell, _yaw)
	ghost.node = node
	# Work source (doc 19 §3.3): allocator id, ONE fetch-and-build lease.
	ghost.source_id = TaskManager.allocate_source_id()
	ghost.drop_manager = _drop_manager
	ghost.install_callback = Callable(self, "_on_ghost_build_complete")
	ghost.build_valid_callback = Callable(self, "_can_build_ghost")
	TaskManager.register_work_source(ghost.source_id, ghost)
	_source_to_ghost[ghost.source_id] = ghost.ghost_id
	_ghosts[ghost.ghost_id] = ghost
	for cell: Vector3i in ghost.footprint_cells():
		_cell_to_ghost[cell] = ghost.ghost_id
	if WallMount.is_wall(def):
		_wall_to_ghost[_wall_key(ghost.origin_cell, ghost.yaw_steps)] = ghost.ghost_id
		_wall_dirty = true
	_mark_lease_dirty()
	print("FurniturePlacementController: ghost %d (%s) at %s yaw %d." % [
		ghost.ghost_id, _active_key, str(_hover_cell), _yaw])
	ghost_placed.emit(ghost.ghost_id)
	_next_ghost_id += 1
	_update_hover(true)   # own footprint now invalid — retint immediately


func cancel_ghost(ghost_id: int) -> void:
	_seating.dirty = true
	if not _ghosts.has(ghost_id):
		return
	var ghost: FurnitureGhostComponent = _ghosts[ghost_id]
	if ghost.source_id >= 0:
		TaskManager.cancel_source_tasks(ghost.source_id)
		TaskManager.unregister_work_source(ghost.source_id)
		_source_to_ghost.erase(ghost.source_id)
	# After cancel_source_tasks: task-gone routing may have re-claimed the
	# fetch item for the ghost — release it back to ordinary hauling now
	# that the request is gone (2026-08-07 item-claim pass).
	ghost.release_claim()
	for cell: Vector3i in ghost.footprint_cells():
		_cell_to_ghost.erase(cell)
	if WallMount.is_wall(ghost.def):
		_wall_to_ghost.erase(_wall_key(ghost.origin_cell, ghost.yaw_steps))
	if ghost.node != null and is_instance_valid(ghost.node):
		ghost.node.queue_free()
	_ghosts.erase(ghost_id)
	if _window_ghost_id == ghost_id:
		_close_window()
	ghost_cancelled.emit(ghost_id)


## The real build path (doc 19 §3.3 step 4): the fetching dwarf finished the
## work swing. Retire the ghost WITHOUT cancelling its lease — the dwarf's
## own complete_dwarf_task resolves it — then run the shared install.
func _on_ghost_build_complete(ghost: FurnitureGhostComponent) -> void:
	if not _ghosts.has(ghost.ghost_id):
		return
	if ghost.source_id >= 0:
		TaskManager.unregister_work_source(ghost.source_id)
		_source_to_ghost.erase(ghost.source_id)
	# Defensive: the claim was normally handed to the builder at reserve_fetch
	# time, but release any stale one (2026-08-07 item-claim pass).
	ghost.release_claim()
	for cell: Vector3i in ghost.footprint_cells():
		_cell_to_ghost.erase(cell)
	if WallMount.is_wall(ghost.def):
		_wall_to_ghost.erase(_wall_key(ghost.origin_cell, ghost.yaw_steps))
	if ghost.node != null and is_instance_valid(ghost.node):
		ghost.node.queue_free()
	_ghosts.erase(ghost.ghost_id)
	if _window_ghost_id == ghost.ghost_id:
		_close_window()
	_install(ghost.furniture_key, ghost.def, ghost.origin_cell, ghost.yaw_steps)


## Checked by the dwarf before consuming its carried item, including the frame
## between a support edit and the controller's deferred terrain notification.
func _can_build_ghost(ghost: FurnitureGhostComponent) -> bool:
	if not _ghosts.has(ghost.ghost_id):
		return false
	if not _seating.placement_reason(ghost.def, ghost.origin_cell, ghost.yaw_steps, ghost).is_empty():
		return false
	if not WallMount.is_wall(ghost.def):
		if Seating.is_chair(ghost.def):
			for cell: Vector3i in ghost.footprint_cells():
				if not NavGrid.is_walkable(cell):
					return false
		return true
	if not _wall_structure_valid(ghost.def, ghost.origin_cell, ghost.yaw_steps):
		return false
	for cell: Vector3i in _bounds_cells(WallMount.bounds_for(ghost.def, ghost.origin_cell, ghost.yaw_steps)):
		if PlacedEntityRegistry.occupies(cell):
			return false
	return true


## DEV: materialise a ghost without a dwarf (the DEV-mine precedent) —
## unblocks Phase 4 storage work before the Phase 3 fetch pipeline lands.
func dev_instant_build(ghost_id: int) -> void:
	if not _ghosts.has(ghost_id):
		return
	var ghost: FurnitureGhostComponent = _ghosts[ghost_id]
	if not _can_build_ghost(ghost):
		cancel_ghost(ghost_id)
		return
	var key := ghost.furniture_key
	var def := ghost.def
	var origin := ghost.origin_cell
	var yaw := ghost.yaw_steps
	cancel_ghost(ghost_id)
	_install(key, def, origin, yaw)


## Convert footprint-local regions to grid occupancy. Quarter-turn formulas
## avoid floating-point drift at cell edges and match positive Godot Y rotation.
## Round outward only after rotation so thin headboards and raised bedding
## cover every touched cell without losing their offset within the footprint.
func _region_occupancy_box(def: Dictionary, region: Dictionary, origin: Vector3i, yaw: int) -> Dictionary:
	var rmin: Array = region.get("min", [0, 0, 0])
	var rmax: Array = region.get("max", [1, 1, 1])
	var lo := Vector3(float(rmin[0]), float(rmin[1]), float(rmin[2]))
	var hi := Vector3(float(rmax[0]), float(rmax[1]), float(rmax[2]))
	var fp: Dictionary = def.get("footprint", {})
	var w := float(fp.get("width", 1))
	var d := float(fp.get("depth", 1))
	var rotated_lo := lo
	var rotated_hi := hi
	match posmod(yaw, 4):
		1:
			rotated_lo = Vector3(lo.z, lo.y, w - hi.x)
			rotated_hi = Vector3(hi.z, hi.y, w - lo.x)
		2:
			rotated_lo = Vector3(w - hi.x, lo.y, d - hi.z)
			rotated_hi = Vector3(w - lo.x, hi.y, d - lo.z)
		3:
			rotated_lo = Vector3(d - hi.z, lo.y, lo.x)
			rotated_hi = Vector3(d - lo.z, hi.y, hi.x)
	var grid_min := Vector3i(floori(rotated_lo.x), floori(rotated_lo.y), floori(rotated_lo.z))
	var grid_max := Vector3i(ceili(rotated_hi.x), ceili(rotated_hi.y), ceili(rotated_hi.z))
	return {"min": origin + Vector3i.UP + grid_min, "size": grid_max - grid_min}


## Installation proper — Phase 3's fetch executor lands here too, so the
## DEV path and the real path share one implementation.
func _install(key: String, def: Dictionary, origin: Vector3i, yaw: int) -> void:
	_seating.dirty = true
	var node := _instance_model(key, _make_solid_material(), def)
	if node != null:
		add_child(node)
		node.position = _world_pos(def, origin, yaw)
		node.rotation = Vector3(0.0, float(yaw) * PI * 0.5, 0.0)
		Lighting.attach(node, def)
		preload("res://scripts/components/UndergroundLighting.gd").bind_world_tree(node)
		node.visible = _piece_visible(def, origin, yaw)
	# Occupancy: one box per collision region (footprint-local block coords;
	# origin (0,0,0) = bottom-front-left at floor+1). NavGrid invalidates on
	# occupancy_changed (the flag precedent). Offset regions rotate with the model.
	var occupancy_ids: Array[int] = []
	for region in def.get("collision_regions", []):
		var box := _region_occupancy_box(def, region, origin, yaw)
		occupancy_ids.append(PlacedEntityRegistry.register_box(box.min, box.size))
	var component := InstalledFurnitureComponent.new()
	component.setup(_next_installed_id, key, def, origin, yaw)
	component.node = node
	component.occupancy_ids = occupancy_ids
	component.cells = _footprint_cells(def, origin, yaw)
	component.source_id = TaskManager.allocate_source_id()
	component.uninstall_callback = Callable(self, "_on_uninstall_complete")
	TaskManager.register_work_source(component.source_id, component)
	# Storage pieces get a container (doc 19 Phase 4): its OWN work source —
	# the piece has two: UNINSTALL (this component) + HAUL (the container).
	if def.has("storage"):
		var container := ContainerStorageComponent.new()
		container.setup_container(def, component.cells)
		container.display_parent = node   # shelf anchors render under the piece
		container.source_id = TaskManager.allocate_source_id()
		StockpileManager.register_container(container)
		component.storage = container
	_source_to_installed[component.source_id] = component.installed_id
	_installed[component.installed_id] = component
	for cell: Vector3i in component.cells:
		_cell_to_installed[cell] = component.installed_id
	if WallMount.is_wall(def):
		_wall_to_installed[_wall_key(origin, yaw)] = component.installed_id
		_wall_dirty = true
	print("FurniturePlacementController: installed %s at %s." % [key, str(origin)])
	furniture_installed.emit(key, origin)
	# doc 22: RoomManager tracks door/heat-source cells by direct call, not by
	# subscribing to this signal — it's an autoload and this is a scene node,
	# so the call has to go this direction (see RoomManager's file header).
	RoomManager.on_furniture_changed(key, _room_cells(component), def, true)
	_next_installed_id += 1


func _room_cells(component: InstalledFurnitureComponent) -> Array[Vector3i]:
	# A wall light contributes heat at its service-floor anchor, reserving no floor.
	if WallMount.is_wall(component.def):
		return [component.origin_cell]
	return component.cells


## The real uninstall path (doc 19 §3.4): the dwarf finished the teardown
## swing. The dwarf's complete_dwarf_task resolves the lease; contents (Phase
## 4) and the packed item re-enter the world as ordinary loose drops.
func _on_uninstall_complete(component: InstalledFurnitureComponent) -> void:
	_teardown_installed(component.installed_id, false)


## Shared teardown. `cancel_lease` true on the DEV path (a live 📤 lease may
## exist); false when the uninstalling dwarf itself is finishing (its lease
## completes normally).
func _teardown_installed(installed_id: int, cancel_lease: bool) -> void:
	_seating.dirty = true
	if not _installed.has(installed_id):
		return
	var component: InstalledFurnitureComponent = _installed[installed_id]
	if component.storage != null:
		# Contents dump first (doc 19 §3.4 step 2) — every stored item
		# re-enters the world loose, then the container's slots are freed.
		component.storage.dump_contents(component.origin_cell)
		StockpileManager.deregister_container(component.storage)
		component.storage = null
	if component.source_id >= 0:
		component.flagged_uninstall = false   # stop on_task_gone re-posting
		if cancel_lease:
			TaskManager.cancel_source_tasks(component.source_id)
		TaskManager.unregister_work_source(component.source_id)
		_source_to_installed.erase(component.source_id)
	for occupancy_id: int in component.occupancy_ids:
		PlacedEntityRegistry.unregister(occupancy_id)
	for cell: Vector3i in component.cells:
		_cell_to_installed.erase(cell)
	if WallMount.is_wall(component.def):
		_wall_to_installed.erase(_wall_key(component.origin_cell, component.yaw_steps))
	if component.node != null and is_instance_valid(component.node):
		component.node.visible = false # switch light off immediately, before queue_free
		component.node.queue_free()
	_installed.erase(installed_id)
	furniture_uninstalled.emit(component.furniture_key, component.origin_cell)
	RoomManager.on_furniture_changed(component.furniture_key, _room_cells(component), component.def, false)
	if _drop_manager != null and is_instance_valid(_drop_manager) and not component.item_key.is_empty():
		var cell := component.origin_cell
		_drop_manager.call("spawn_drop", component.item_key, 1, Vector3i(cell.x, cell.y + 1, cell.z))
	if _window_installed_id == installed_id:
		_close_window()


## DEV: instant teardown, no dwarf (kept alongside the real 📤 path).
func dev_remove_installed(installed_id: int) -> void:
	_teardown_installed(installed_id, true)


func save_section_key() -> String:
	return "furniture"


func save_restore_priority() -> int:
	return 40


func serialize_state() -> Dictionary:
	var saved_ghosts: Array = []
	var ghost_ids: Array = _ghosts.keys()
	ghost_ids.sort()
	for value in ghost_ids:
		var ghost: FurnitureGhostComponent = _ghosts[int(value)]
		saved_ghosts.append({
			"id": ghost.ghost_id,
			"key": ghost.furniture_key,
			"origin": SaveManager.pack_v3i(ghost.origin_cell),
			"yaw": ghost.yaw_steps,
			"layout_version": int(ghost.def.get("layout_version", 1)),
		})
	var saved_installed: Array = []
	var installed_ids: Array = _installed.keys()
	installed_ids.sort()
	for value in installed_ids:
		var component: InstalledFurnitureComponent = _installed[int(value)]
		var entry := {
			"id": component.installed_id,
			"key": component.furniture_key,
			"origin": SaveManager.pack_v3i(component.origin_cell),
			"yaw": component.yaw_steps,
			"layout_version": int(component.def.get("layout_version", 1)),
			"flagged_uninstall": component.flagged_uninstall,
		}
		if component.storage != null:
			entry["inventory"] = component.storage.inventory.duplicate(true)
			entry["storage_filter"] = component.storage.serialize_filter()
		saved_installed.append(entry)
	return { "ghosts": saved_ghosts, "installed": saved_installed }


func restore_state(state: Dictionary) -> void:
	_drop_manager = get_tree().get_first_node_in_group("item_drop_manager") as Node3D
	for raw in state.get("ghosts", []):
		if raw is Dictionary:
			_restore_ghost(raw as Dictionary)
	for raw in state.get("installed", []):
		if not (raw is Dictionary):
			continue
		var entry := raw as Dictionary
		var key := String(entry.get("key", ""))
		if not _defs.has(key):
			continue
		var requested_id := maxi(int(entry.get("id", _next_installed_id)), 1)
		var prior_next := _next_installed_id
		_next_installed_id = requested_id
		_install(key, _definition_for_saved(key, entry), SaveManager.unpack_v3i(entry.get("origin", [])),
			int(entry.get("yaw", 0)))
		var component: InstalledFurnitureComponent = _installed.get(requested_id)
		_next_installed_id = maxi(_next_installed_id, prior_next)
		if component == null:
			continue
		if component.storage != null:
			component.storage.restore_filter(entry.get("storage_filter", {}))
			component.storage.restore_inventory(
				entry.get("inventory", {}) as Dictionary, _drop_manager)
		if bool(entry.get("flagged_uninstall", false)):
			component.set_uninstall(true)


## Unversioned saves predate wide chairs. Preserve their model and footprint;
## rebuilding their refunded item uses the current definition.
func _definition_for_saved(key: String, entry: Dictionary) -> Dictionary:
	var def: Dictionary = _defs[key]
	var version := int(entry.get("layout_version", 1))
	var legacy: Dictionary = def.get("legacy_layouts", {})
	if version != int(def.get("layout_version", 1)) and legacy.has(str(version)):
		def = def.duplicate(true)
		def.merge(legacy[str(version)], true)
		def["layout_version"] = version
	return def


func _restore_ghost(entry: Dictionary) -> void:
	var key := String(entry.get("key", ""))
	if not _defs.has(key):
		return
	var requested_id := maxi(int(entry.get("id", _next_ghost_id)), 1)
	var prior_next := _next_ghost_id
	var prior_key := _active_key
	var prior_cell := _hover_cell
	var prior_yaw := _yaw
	_next_ghost_id = requested_id
	_active_key = key
	_hover_cell = SaveManager.unpack_v3i(entry.get("origin", []))
	_yaw = int(entry.get("yaw", 0))
	_confirm_ghost(_definition_for_saved(key, entry))
	_next_ghost_id = maxi(_next_ghost_id, prior_next)
	_active_key = prior_key
	_hover_cell = prior_cell
	_yaw = prior_yaw


# ── Click-select (tool on or off — the A3 lesson) ─────────────────────────────

func _try_select_at_screen(screen_pos: Vector2) -> bool:
	var hit := _surface_cell_for(screen_pos)
	if _try_select_wall(screen_pos, hit):
		return true
	if hit.is_empty():
		return false
	var cell := Vector3i(int(hit["x"]), int(hit["y"]), int(hit["z"]))
	if _cell_to_ghost.has(cell):
		_open_ghost_window(int(_cell_to_ghost[cell]))
		return true
	if _cell_to_installed.has(cell):
		_open_installed_window(int(_cell_to_installed[cell]))
		return true
	return false


func _try_select_wall(screen_pos: Vector2, terrain_hit: Dictionary) -> bool:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return false
	var start := camera.project_ray_origin(screen_pos)
	var direction := camera.project_ray_normal(screen_pos).normalized()
	var nearest := float(terrain_hit.get("distance", RAY_MAX)) + .001
	var selected_id := -1
	var selected_ghost := false
	for ghost_pass: bool in [true, false]:
		var pieces: Dictionary = _ghosts if ghost_pass else _installed
		var ids: Array = _wall_to_ghost.values() if ghost_pass else _wall_to_installed.values()
		for id: int in ids:
			var piece = pieces[id]
			if piece.node == null or not piece.node.is_visible_in_tree():
				continue
			var bounds: AABB = WallMount.bounds_for(piece.def, piece.origin_cell, piece.yaw_steps)
			var intersection: Variant = bounds.intersects_segment(start, start + direction * RAY_MAX)
			if intersection == null:
				continue
			var distance := start.distance_to(intersection as Vector3)
			if distance < nearest:
				nearest = distance
				selected_id = id
				selected_ghost = ghost_pass
	if selected_id < 0:
		return false
	if selected_ghost:
		_open_ghost_window(selected_id)
	else:
		_open_installed_window(selected_id)
	return true


# ── Raycasting (slice-aware voxel DDA, 2026-08-06) ─────────────────────────────

## Voxel DDA raycast from the camera through the mouse, returning the first
## SLICE-VISIBLE solid block the ray hits (the floor cell itself -- NavGrid's
## convention; see the off-by-one note below).
##
## 2026-08-06 bugfix: this used to march the ray against
## WorldGenerator.get_visible_surface_y() — the STATIC world-gen heightmap,
## set once at generation and never updated by mining. That made every
## placement resolve to the original, unmined ground height for the column
## under the cursor no matter what the slice tool had cut away or what
## mining had exposed underground, so furniture could only ever be placed at
## the natural surface — reported as "can't place the door on a sliced
## part". This ports MiningDesignationController._raycast_voxel()'s proven
## DDA + slice-visibility gate (pos.y <= _slice_y is "culled, keep marching
## through it", the same rule DwarfAgent/ItemDropManager use for slice
## visibility elsewhere) but resolves against the REAL, live block grid
## (_block_id — WorldData first, WorldGenerator fallback for unmaterialised
## chunks) instead of the heightmap, so it correctly finds a mined tunnel's
## floor once the slice plane exposes it. Above-ground placement is
## unaffected: the first solid cell hit for an untouched column is still the
## natural terrain surface.
##
## OFF-BY-ONE FOLLOW-UP FIX (2026-08-06, same day): this first shipped
## returning `pos.y + 1` ("one above the hit block"), on the wrong
## assumption that cell.y meant the walkable AIR cell. It doesn't --
## NavGrid._compute_walkable(cell) requires cell.y ITSELF to be solid, with
## clearance checked at cell.y+1..+CLEARANCE. WorldGenerator.get_visible_
## surface_y() (the old raycast's source) returns that same solid-floor
## convention -- confirmed via get_visible_surface_block_id(), which
## generates the SURFACE block at exactly that Y. Returning pos.y + 1 meant
## every returned cell was air, so is_walkable() rejected literally
## everything and placement broke outright -- reported as "lost the ability
## to draw storage zones". Fixed to return pos.y (the solid block itself).
func _surface_cell_for(screen_pos: Vector2) -> Dictionary:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return {}
	var origin := camera.project_ray_origin(screen_pos)
	var direction := camera.project_ray_normal(screen_pos).normalized()

	var pos := Vector3i(floori(origin.x), floori(origin.y), floori(origin.z))
	var step := Vector3i(
		1 if direction.x > 0.0 else -1,
		1 if direction.y > 0.0 else -1,
		1 if direction.z > 0.0 else -1)
	var t_delta := Vector3(
		abs(1.0 / direction.x) if not is_zero_approx(direction.x) else INF,
		abs(1.0 / direction.y) if not is_zero_approx(direction.y) else INF,
		abs(1.0 / direction.z) if not is_zero_approx(direction.z) else INF)
	var t_max := Vector3(
		_axis_t_max(origin.x, direction.x, pos.x),
		_axis_t_max(origin.y, direction.y, pos.y),
		_axis_t_max(origin.z, direction.z, pos.z))
	var travelled := 0.0
	var normal := Vector3i.ZERO

	while travelled <= RAY_MAX:
		if pos.x >= 0 and pos.x < WorldGenerator.WORLD_SIZE_X \
				and pos.z >= 0 and pos.z < WorldGenerator.WORLD_SIZE_Z:
			if pos.y >= 0 and pos.y <= _slice_y:
				var block_id := _block_id(pos.x, pos.y, pos.z)
				if BlockRegistry.is_solid(block_id):
					return { "x": pos.x, "y": pos.y, "z": pos.z, "normal":normal, "distance":travelled }
		elif pos.y < 0:
			return {}

		if t_max.x <= t_max.y and t_max.x <= t_max.z:
			pos.x += step.x
			travelled = t_max.x
			t_max.x += t_delta.x
			normal = Vector3i(-step.x, 0, 0)
		elif t_max.y <= t_max.z:
			pos.y += step.y
			travelled = t_max.y
			t_max.y += t_delta.y
			normal = Vector3i(0, -step.y, 0)
		else:
			pos.z += step.z
			travelled = t_max.z
			t_max.z += t_delta.z
			normal = Vector3i(0, 0, -step.z)

	return {}


func _axis_t_max(origin_axis: float, direction_axis: float, pos_axis: int) -> float:
	if is_zero_approx(direction_axis):
		return INF
	var boundary := float(pos_axis + 1) if direction_axis > 0.0 else float(pos_axis)
	return (boundary - origin_axis) / direction_axis


# ── Slice culling (doc 11 Phase 5 hook) ───────────────────────────────────────

func _piece_visible(def: Dictionary, origin: Vector3i, yaw: int) -> bool:
	# Keep the local emitter below the cut plane, where the visible terrain
	# still encloses it. Otherwise it would shine over a sliced-away wall.
	if WallMount.is_wall(def):
		return ceili(WallMount.bounds_for(def, origin, yaw).end.y - .0001) - 1 <= _slice_y
	return floori(_world_pos(def, origin, yaw).y + .0001) <= _slice_y

func _on_slice_changed(new_slice_y: int) -> void:
	if new_slice_y == _slice_y:
		return
	_slice_y = new_slice_y
	for ghost_id: int in _ghosts:
		var ghost: FurnitureGhostComponent = _ghosts[ghost_id]
		if ghost.node != null and is_instance_valid(ghost.node):
			ghost.node.visible = _piece_visible(ghost.def, ghost.origin_cell, ghost.yaw_steps)
	for installed_id: int in _installed:
		var component: InstalledFurnitureComponent = _installed[installed_id]
		if component.node != null and is_instance_valid(component.node):
			component.node.visible = _piece_visible(component.def, component.origin_cell, component.yaw_steps)
	if _active:
		_update_hover(true)


# ── Windows (compact — the stockpile zone window pattern) ─────────────────────

func _build_window() -> void:
	_window_layer = CanvasLayer.new()
	_window_layer.name = "FurnitureWindow"
	_window_layer.layer = 22
	_window_layer.visible = false
	add_child(_window_layer)

	_window_panel = PanelContainer.new()
	UITheme.apply_surface(_window_panel)
	_window_panel.position = Vector2(18.0, 470.0)
	_window_panel.custom_minimum_size = Vector2(220.0, 0.0)
	_window_panel.add_theme_stylebox_override("panel", UITheme.window_style())
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

	_window_title = Label.new()
	_window_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.apply_title(_window_title)
	header.add_child(_window_title)

	var close := Button.new()
	UITheme.apply_close_button(close)
	close.pressed.connect(_close_window)
	header.add_child(close)

	_window_info = Label.new()
	_window_info.add_theme_font_size_override("font_size", 14)
	column.add_child(_window_info)

	_window_build_btn = Button.new()
	_window_build_btn.text = "DEV: Instant Build"
	UITheme.apply_button_variant(_window_build_btn, "dev")
	_window_build_btn.focus_mode = Control.FOCUS_NONE
	_window_build_btn.custom_minimum_size = Vector2(186.0, 30.0)
	_window_build_btn.add_theme_font_size_override("font_size", 13)
	_window_build_btn.pressed.connect(_on_primary_pressed)
	column.add_child(_window_build_btn)

	_window_remove_btn = Button.new()
	_window_remove_btn.focus_mode = Control.FOCUS_NONE
	_window_remove_btn.custom_minimum_size = Vector2(186.0, 30.0)
	_window_remove_btn.add_theme_font_size_override("font_size", 13)
	_window_remove_btn.pressed.connect(_on_remove_pressed)
	column.add_child(_window_remove_btn)


## Primary button: ghost window = DEV Instant Build; installed window = the
## 📤 uninstall TOGGLE (SH parity — clicking again cancels).
func _on_primary_pressed() -> void:
	if _window_ghost_id >= 0:
		dev_instant_build(_window_ghost_id)
		return
	if _window_installed_id >= 0:
		var component: InstalledFurnitureComponent = _installed.get(_window_installed_id)
		if component != null:
			component.set_uninstall(not component.flagged_uninstall)
			_open_installed_window(_window_installed_id)   # refresh labels


func _on_remove_pressed() -> void:
	if _window_ghost_id >= 0:
		cancel_ghost(_window_ghost_id)
	elif _window_installed_id >= 0:
		dev_remove_installed(_window_installed_id)


func _open_ghost_window(ghost_id: int) -> void:
	var ghost: FurnitureGhostComponent = _ghosts.get(ghost_id)
	if ghost == null:
		return
	_window_ghost_id = ghost_id
	_window_installed_id = -1
	_window_title.text = "Ghost — %s" % ghost.display_name()
	if ghost.has_lease():
		_window_info.text = "Waiting for a dwarf to fetch:\n%s" % ghost.item_key
	else:
		_window_info.text = "Needs: %s\n(none in the colony)" % ghost.item_key
	_window_build_btn.text = "DEV: Instant Build"
	UITheme.apply_button_variant(_window_build_btn, "dev")
	_window_build_btn.visible = true
	_window_remove_btn.text = "Cancel 📥"
	UITheme.apply_button_variant(_window_remove_btn, "danger")
	_window_layer.visible = true


func _open_installed_window(installed_id: int) -> void:
	var component: InstalledFurnitureComponent = _installed.get(installed_id)
	if component == null:
		return
	_window_installed_id = installed_id
	_window_ghost_id = -1
	_window_title.text = component.display_name()
	var status_line := "Marked for uninstall — a dwarf is coming." if component.flagged_uninstall else "Installed."
	if component.storage == null:
		_window_info.text = status_line
	else:
		var lines := "%s\nSlots used: %d / %d\nGoods stored: %d" % [
			status_line, component.storage.occupied_slots(), component.storage.capacity, component.storage.stored_count()]
		for item_key: String in component.storage.inventory:
			lines += "\n  %s × %d" % [item_key.get_slice(":", item_key.get_slice_count(":") - 1),
					int(component.storage.inventory[item_key])]
		_window_info.text = lines
	_window_build_btn.text = "📤 Cancel uninstall" if component.flagged_uninstall else "📤 Uninstall"
	UITheme.apply_button_variant(_window_build_btn)
	_window_build_btn.visible = true
	_window_remove_btn.text = "DEV: Remove (drops item)"
	UITheme.apply_button_variant(_window_remove_btn, "dev")
	_window_layer.visible = true


func _close_window() -> void:
	_window_ghost_id = -1
	_window_installed_id = -1
	_window_layer.visible = false


# ── Object explorer provider ──────────────────────────────────────────────────

func pick_explorer_object(start: Vector3, end: Vector3) -> Dictionary:
	var result := {}
	var nearest := start.distance_to(end)
	for ghost_pass: bool in [true, false]:
		var pieces: Dictionary = _ghosts if ghost_pass else _installed
		for id: int in pieces:
			var piece = pieces[id]
			if not is_instance_valid(piece.node) or not piece.node.is_visible_in_tree():
				continue
			if _visual_bounds(piece.def, piece.origin_cell, piece.yaw_steps).intersects_segment(start, end) == null:
				continue
			var distance := _picking.hit_distance(piece.node, start, end)
			if distance < nearest:
				nearest = distance
				result = {"id": "%s:%d" % ["ghost" if ghost_pass else "installed", id], "distance": distance}
	return result


func _explorer_piece(object_id: Variant) -> Variant:
	var id := String(object_id)
	if id.begins_with("ghost:"):
		return _ghosts.get(int(id.get_slice(":", 1)))
	if id.begins_with("installed:"):
		return _installed.get(int(id.get_slice(":", 1)))
	return null


func inspect_storage(storage: ContainerStorageComponent) -> bool:
	var explorer := get_tree().get_first_node_in_group("object_explorer")
	if explorer == null: return false
	for id: int in _installed:
		if _installed[id].storage == storage:
			return explorer.select_object(self, "installed:%d" % id)
	return false


func get_explorer_bounds(object_id: Variant) -> AABB:
	var piece = _explorer_piece(object_id)
	if piece == null or not is_instance_valid(piece.node) or not piece.node.is_visible_in_tree():
		return AABB()
	return _visual_bounds(piece.def, piece.origin_cell, piece.yaw_steps)


func get_explorer_data(object_id: Variant) -> Dictionary:
	var piece = _explorer_piece(object_id)
	if piece == null or not is_instance_valid(piece.node) or not piece.node.is_visible_in_tree():
		return {}
	var rows: Array = []
	var actions: Array = []
	var details := String(piece.def.get("description", ""))
	if piece is FurnitureGhostComponent:
		rows.append(["Status", "Awaiting delivery" if piece.has_lease() else "Awaiting packed item"])
		rows.append(["Required item", _explorer_item_name(piece.item_key)])
		actions = [
			{"id": "cancel", "text": "Cancel placement", "variant": "danger"},
			{"id": "build", "text": "DEV: Instant Build", "variant": "dev"},
		]
	else:
		rows.append(["Status", "Marked for uninstall" if piece.flagged_uninstall else "Installed"])
		if piece.storage != null:
			rows.append(["Storage", "%d / %d slots" % [piece.storage.occupied_slots(), piece.storage.capacity]])
			var contents: Array[String] = []
			for item_key: String in piece.storage.inventory:
				contents.append("%d × %s" % [int(piece.storage.inventory[item_key]), _explorer_item_name(item_key)])
			if not contents.is_empty():
				details += "\n\nContents:\n" + "\n".join(contents)
		actions = [
			{"id": "uninstall", "text": "Cancel uninstall" if piece.flagged_uninstall else "Uninstall"},
			{"id": "remove", "text": "DEV: Remove (drops item)", "variant": "dev"},
		]
	if piece is InstalledFurnitureComponent and piece.storage != null:
		return {"title": piece.display_name(), "presentation": "storage", "storage": piece.storage, "actions": actions}
	return {"title": piece.display_name(), "kind": "Furniture plan" if piece is FurnitureGhostComponent else "Furniture",
		"rows": rows, "details": details, "actions": actions}


func perform_explorer_action(object_id: Variant, action_id: String) -> void:
	var piece = _explorer_piece(object_id)
	if piece == null:
		return
	if piece is FurnitureGhostComponent:
		if action_id == "cancel":
			cancel_ghost(piece.ghost_id)
		elif action_id == "build":
			dev_instant_build(piece.ghost_id)
	elif action_id == "uninstall":
		piece.set_uninstall(not piece.flagged_uninstall)
	elif action_id == "remove":
		dev_remove_installed(piece.installed_id)


func _explorer_item_name(item_key: String) -> String:
	if is_instance_valid(_drop_manager):
		var definition: Dictionary = _drop_manager.call("get_item_def", item_key)
		if definition.has("display_name"):
			return String(definition["display_name"])
	return item_key.get_slice(":", item_key.get_slice_count(":") - 1).capitalize()
