class_name FurniturePlacementController
extends Node3D

## Furniture placement tool — doc 19 §3.2 (Phase 2 scope).
##
## The FlagPlacementController generalised and made data-driven: the Build
## panel's 📥 entries activate this tool for one furniture def; the player
## aims a translucent placed-form ghost (validity-tinted, R rotates 90°),
## and confirming plants a persistent FurnitureGhostComponent — the SH
## "ghost form as standing task marker". Fulfilment (FETCH_BUILD leases) and
## 📤 uninstall are Phase 3; the ghost window's DEV: Instant Build stands in
## until then (the DEV-mine precedent) so storage work can proceed.
##
## REGISTRY PATTERN: this node is the ONE owner of data/furniture/*.json.
## Defs are placeable iff they carry both `placement` and `item_key`
## (trade_counter.json predates doc 19 and has neither — correctly skipped).
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

var _defs: Dictionary = {}            # furniture_key -> def Dictionary
var _dock_ui: Node = null
var _slice_y: int = SLICE_OFF_Y

var _active: bool = false
var _active_key: String = ""          # def being placed while the tool is on
var _yaw: int = 0
var _hover_cell: Vector3i = Vector3i(-1, -1, -1)
var _hover_valid: bool = false
var _invalid_reason: String = ""     # "" | "cell" | "wall" (hint label text)
var _hint_label: Label3D = null

var _preview: Node3D = null           # cursor ghost (one per activation)
var _preview_material: StandardMaterial3D = null

var _next_ghost_id: int = 1
var _ghosts: Dictionary = {}          # ghost_id -> FurnitureGhostComponent
var _cell_to_ghost: Dictionary = {}   # Vector3i -> ghost_id

var _next_installed_id: int = 1
var _installed: Dictionary = {}       # id -> InstalledFurnitureComponent
var _cell_to_installed: Dictionary = {}   # Vector3i -> installed id

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
	add_to_group("furniture_controller")
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
	_build_window()


## Sole reader of data/furniture/*.json (registry pattern). Placeable defs
## must carry the doc 19 fields; older schema files (trade_counter) skip.
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
			continue   # pre-doc-19 schema (trade_counter) — not placeable yet
		_defs[key] = def
	print("FurniturePlacementController: %d placeable defs loaded." % _defs.size())


func get_defs() -> Dictionary:
	return _defs


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


func activate_for(furniture_key: String) -> void:
	if not _defs.has(furniture_key):
		push_warning("FurniturePlacementController: unknown def '%s'." % furniture_key)
		return
	if not bool(WorldGenerator.get_streaming_stats().get("maps_ready", false)):
		push_warning("FurniturePlacementController: maps not ready.")
		return
	deactivate()   # clean swap if a different def was active
	_active = true
	_active_key = furniture_key
	_yaw = 0
	_ensure_preview()


func deactivate() -> void:
	if not _active:
		return
	_active = false
	_active_key = ""
	_free_preview()


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
			_wakes_connected = true
			for ghost_id: int in _ghosts:
				(_ghosts[ghost_id] as FurnitureGhostComponent).drop_manager = _drop_manager
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
	# Released leases return to PENDING — only the dwarf's reservations free.
	if _source_to_ghost.has(task.source_id):
		var ghost: FurnitureGhostComponent = _ghosts.get(int(_source_to_ghost[task.source_id]))
		if ghost != null:
			ghost.cancel_fetch(dwarf_id)


func _unhandled_input(event: InputEvent) -> void:
	if not _active:
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
		if _try_select_at_screen(mb.position):
			get_viewport().set_input_as_handled()
			return
		if _hover_valid:
			_confirm_ghost()
			get_viewport().set_input_as_handled()


# ── Hover / validity ──────────────────────────────────────────────────────────

func _update_hover(force: bool = false) -> void:
	var hit := _surface_cell_for(get_viewport().get_mouse_position())
	if hit.is_empty():
		_hover_cell = Vector3i(-1, -1, -1)
		_hover_valid = false
		if _preview != null:
			_preview.visible = false
		return
	var cell := Vector3i(int(hit["x"]), int(hit["y"]), int(hit["z"]))
	if cell == _hover_cell and not force:
		return
	_hover_cell = cell
	_hover_valid = _placement_valid(cell)
	_position_preview(cell)


func _placement_valid(origin: Vector3i) -> bool:
	_invalid_reason = ""
	var def: Dictionary = _defs.get(_active_key, {})
	for cell: Vector3i in _footprint_cells(def, origin, _yaw):
		if not _is_valid_cell(cell):
			_invalid_reason = "cell"
			return false
	if String(def.get("placement", "floor")) == "floor_wall" and not _has_wall_behind(def, origin):
		_invalid_reason = "wall"
		return false
	return true


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
func _has_wall_behind(def: Dictionary, origin: Vector3i) -> bool:
	var back := _yaw_dir(Vector3i(0, 0, -1))
	for cell: Vector3i in _footprint_cells(def, origin, _yaw):
		var wall := cell + back
		if not BlockRegistry.is_solid(_block_id(wall.x, wall.y + 1, wall.z)):
			return false
	return true


func _yaw_dir(local: Vector3i) -> Vector3i:
	match _yaw % 4:
		1: return Vector3i(-local.z, local.y, local.x)
		2: return Vector3i(-local.x, local.y, -local.z)
		3: return Vector3i(local.z, local.y, -local.x)
	return local


func _footprint_cells(def: Dictionary, origin: Vector3i, yaw: int) -> Array[Vector3i]:
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
	_preview.visible = origin.x >= 0
	_preview.position = _world_pos(_defs.get(_active_key, {}), origin, _yaw)
	_preview.rotation = Vector3(0.0, float(_yaw) * PI * 0.5, 0.0)
	var tint := TINT_VALID if _hover_valid else TINT_INVALID
	_preview_material.albedo_color = Color(tint.r, tint.g, tint.b, GHOST_ALPHA)
	_update_hint(origin)


## Why-invalid hint (the mining-ruler lesson: never make the player guess).
## Shown only for the wall requirement — plain cell blockage is self-evident.
func _update_hint(origin: Vector3i) -> void:
	if _hint_label == null:
		_hint_label = Label3D.new()
		_hint_label.name = "PlacementHint"
		_hint_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_hint_label.fixed_size = true
		_hint_label.pixel_size = 0.0008
		_hint_label.font_size = 84
		_hint_label.outline_size = 22
		_hint_label.modulate = Color(1.0, 0.75, 0.6)
		_hint_label.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
		_hint_label.no_depth_test = true
		add_child(_hint_label)
	if _invalid_reason == "wall":
		_hint_label.text = "Needs a solid wall behind — R rotates"
		_hint_label.position = Vector3(float(origin.x) + 0.5, float(origin.y) + 3.4, float(origin.z) + 0.5)
		_hint_label.visible = true
	else:
		_hint_label.visible = false


## Node position for a footprint: the footprint centre on the floor top
## (models are authored centred on X=Z=0 with base at Y=0).
func _world_pos(def: Dictionary, origin: Vector3i, yaw: int) -> Vector3:
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


func _instance_model(furniture_key: String, override: Material) -> Node3D:
	var def: Dictionary = _defs.get(furniture_key, {})
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

func _confirm_ghost() -> void:
	var def: Dictionary = _defs.get(_active_key, {})
	var ghost := FurnitureGhostComponent.new()
	ghost.setup(_next_ghost_id, _active_key, def, _hover_cell, _yaw)
	var mat := _make_ghost_material()
	mat.albedo_color = Color(TINT_PLACED.r, TINT_PLACED.g, TINT_PLACED.b, GHOST_ALPHA)
	var node := _instance_model(_active_key, mat)
	if node != null:
		add_child(node)
		node.position = _world_pos(def, _hover_cell, _yaw)
		node.rotation = Vector3(0.0, float(_yaw) * PI * 0.5, 0.0)
		node.visible = _hover_cell.y + 1 <= _slice_y
	ghost.node = node
	# Work source (doc 19 §3.3): allocator id, ONE fetch-and-build lease.
	ghost.source_id = TaskManager.allocate_source_id()
	ghost.drop_manager = _drop_manager
	ghost.install_callback = Callable(self, "_on_ghost_build_complete")
	TaskManager.register_work_source(ghost.source_id, ghost)
	_source_to_ghost[ghost.source_id] = ghost.ghost_id
	_ghosts[ghost.ghost_id] = ghost
	for cell: Vector3i in ghost.footprint_cells():
		_cell_to_ghost[cell] = ghost.ghost_id
	_mark_lease_dirty()
	print("FurniturePlacementController: ghost %d (%s) at %s yaw %d." % [
		ghost.ghost_id, _active_key, str(_hover_cell), _yaw])
	ghost_placed.emit(ghost.ghost_id)
	_next_ghost_id += 1
	_update_hover(true)   # own footprint now invalid — retint immediately


func cancel_ghost(ghost_id: int) -> void:
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
	if ghost.node != null and is_instance_valid(ghost.node):
		ghost.node.queue_free()
	_ghosts.erase(ghost.ghost_id)
	if _window_ghost_id == ghost.ghost_id:
		_close_window()
	_install(ghost.furniture_key, ghost.def, ghost.origin_cell, ghost.yaw_steps)


## DEV: materialise a ghost without a dwarf (the DEV-mine precedent) —
## unblocks Phase 4 storage work before the Phase 3 fetch pipeline lands.
func dev_instant_build(ghost_id: int) -> void:
	if not _ghosts.has(ghost_id):
		return
	var ghost: FurnitureGhostComponent = _ghosts[ghost_id]
	var key := ghost.furniture_key
	var def := ghost.def
	var origin := ghost.origin_cell
	var yaw := ghost.yaw_steps
	cancel_ghost(ghost_id)
	_install(key, def, origin, yaw)


## Installation proper — Phase 3's fetch executor lands here too, so the
## DEV path and the real path share one implementation.
func _install(key: String, def: Dictionary, origin: Vector3i, yaw: int) -> void:
	var node := _instance_model(key, _make_solid_material())
	if node != null:
		add_child(node)
		node.position = _world_pos(def, origin, yaw)
		node.rotation = Vector3(0.0, float(yaw) * PI * 0.5, 0.0)
		node.visible = origin.y + 1 <= _slice_y
	# Occupancy: one box per collision region (footprint-local block coords;
	# origin (0,0,0) = bottom-front-left at floor+1). NavGrid invalidates on
	# occupancy_changed (the flag precedent). Yaw swaps X/Z extents.
	var occupancy_ids: Array[int] = []
	for region in def.get("collision_regions", []):
		var rmin: Array = region.get("min", [0, 0, 0])
		var rmax: Array = region.get("max", [1, 1, 1])
		var size := Vector3i(
			int(rmax[0]) - int(rmin[0]),
			int(rmax[1]) - int(rmin[1]),
			int(rmax[2]) - int(rmin[2]))
		if yaw % 2 == 1:
			size = Vector3i(size.z, size.y, size.x)
		var box_min := Vector3i(origin.x + int(rmin[0]), origin.y + 1 + int(rmin[1]), origin.z + int(rmin[2]))
		occupancy_ids.append(PlacedEntityRegistry.register_box(box_min, size))
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
	print("FurniturePlacementController: installed %s at %s." % [key, str(origin)])
	furniture_installed.emit(key, origin)
	# doc 22: RoomManager tracks door/heat-source cells by direct call, not by
	# subscribing to this signal — it's an autoload and this is a scene node,
	# so the call has to go this direction (see RoomManager's file header).
	RoomManager.on_furniture_changed(key, component.cells, def, true)
	_next_installed_id += 1


## The real uninstall path (doc 19 §3.4): the dwarf finished the teardown
## swing. The dwarf's complete_dwarf_task resolves the lease; contents (Phase
## 4) and the packed item re-enter the world as ordinary loose drops.
func _on_uninstall_complete(component: InstalledFurnitureComponent) -> void:
	_teardown_installed(component.installed_id, false)


## Shared teardown. `cancel_lease` true on the DEV path (a live 📤 lease may
## exist); false when the uninstalling dwarf itself is finishing (its lease
## completes normally).
func _teardown_installed(installed_id: int, cancel_lease: bool) -> void:
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
	if component.node != null and is_instance_valid(component.node):
		component.node.queue_free()
	_installed.erase(installed_id)
	furniture_uninstalled.emit(component.furniture_key, component.origin_cell)
	RoomManager.on_furniture_changed(component.furniture_key, component.cells, component.def, false)
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
			"flagged_uninstall": component.flagged_uninstall,
		}
		if component.storage != null:
			entry["inventory"] = component.storage.inventory.duplicate(true)
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
		_install(key, _defs[key], SaveManager.unpack_v3i(entry.get("origin", [])),
			int(entry.get("yaw", 0)))
		var component: InstalledFurnitureComponent = _installed.get(requested_id)
		_next_installed_id = maxi(_next_installed_id, prior_next)
		if component == null:
			continue
		if component.storage != null:
			component.storage.restore_inventory(
				entry.get("inventory", {}) as Dictionary, _drop_manager)
		if bool(entry.get("flagged_uninstall", false)):
			component.set_uninstall(true)


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
	_confirm_ghost()
	_next_ghost_id = maxi(_next_ghost_id, prior_next)
	_active_key = prior_key
	_hover_cell = prior_cell
	_yaw = prior_yaw


# ── Click-select (tool on or off — the A3 lesson) ─────────────────────────────

func _try_select_at_screen(screen_pos: Vector2) -> bool:
	var hit := _surface_cell_for(screen_pos)
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

	while travelled <= RAY_MAX:
		if pos.x >= 0 and pos.x < WorldGenerator.WORLD_SIZE_X \
				and pos.z >= 0 and pos.z < WorldGenerator.WORLD_SIZE_Z:
			if pos.y >= 0 and pos.y <= _slice_y:
				var block_id := _block_id(pos.x, pos.y, pos.z)
				if BlockRegistry.is_solid(block_id):
					return { "x": pos.x, "y": pos.y, "z": pos.z }
		elif pos.y < 0:
			return {}

		if t_max.x <= t_max.y and t_max.x <= t_max.z:
			pos.x += step.x
			travelled = t_max.x
			t_max.x += t_delta.x
		elif t_max.y <= t_max.z:
			pos.y += step.y
			travelled = t_max.y
			t_max.y += t_delta.y
		else:
			pos.z += step.z
			travelled = t_max.z
			t_max.z += t_delta.z

	return {}


func _axis_t_max(origin_axis: float, direction_axis: float, pos_axis: int) -> float:
	if is_zero_approx(direction_axis):
		return INF
	var boundary := float(pos_axis + 1) if direction_axis > 0.0 else float(pos_axis)
	return (boundary - origin_axis) / direction_axis


# ── Slice culling (doc 11 Phase 5 hook) ───────────────────────────────────────

func _on_slice_changed(new_slice_y: int) -> void:
	if new_slice_y == _slice_y:
		return
	_slice_y = new_slice_y
	for ghost_id: int in _ghosts:
		var ghost: FurnitureGhostComponent = _ghosts[ghost_id]
		if ghost.node != null and is_instance_valid(ghost.node):
			ghost.node.visible = ghost.origin_cell.y + 1 <= _slice_y
	for installed_id: int in _installed:
		var component: InstalledFurnitureComponent = _installed[installed_id]
		if component.node != null and is_instance_valid(component.node):
			component.node.visible = component.origin_cell.y + 1 <= _slice_y


# ── Windows (compact — the stockpile zone window pattern) ─────────────────────

func _build_window() -> void:
	_window_layer = CanvasLayer.new()
	_window_layer.name = "FurnitureWindow"
	_window_layer.layer = 22
	_window_layer.visible = false
	add_child(_window_layer)

	_window_panel = PanelContainer.new()
	_window_panel.position = Vector2(18.0, 470.0)
	_window_panel.custom_minimum_size = Vector2(220.0, 0.0)
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

	_window_title = Label.new()
	_window_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_window_title.add_theme_font_size_override("font_size", 16)
	header.add_child(_window_title)

	var close := Button.new()
	close.text = "X"
	close.custom_minimum_size = Vector2(30.0, 26.0)
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(_close_window)
	header.add_child(close)

	_window_info = Label.new()
	_window_info.add_theme_font_size_override("font_size", 14)
	column.add_child(_window_info)

	_window_build_btn = Button.new()
	_window_build_btn.text = "DEV: Instant Build"
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
	_window_build_btn.visible = true
	_window_remove_btn.text = "Cancel 📥"
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
		var lines := "%s\nStored: %d / %d" % [
			status_line, component.storage.stored_count(), component.storage.capacity]
		for item_key: String in component.storage.inventory:
			lines += "\n  %s × %d" % [item_key.get_slice(":", item_key.get_slice_count(":") - 1),
					int(component.storage.inventory[item_key])]
		_window_info.text = lines
	_window_build_btn.text = "📤 Cancel uninstall" if component.flagged_uninstall else "📤 Uninstall"
	_window_build_btn.visible = true
	_window_remove_btn.text = "DEV: Remove (drops item)"
	_window_layer.visible = true


func _close_window() -> void:
	_window_ghost_id = -1
	_window_installed_id = -1
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
