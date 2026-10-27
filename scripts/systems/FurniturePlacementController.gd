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
const SLICE_OFF_Y := SliceController.MAX_SLICE_Y
const RAY_MAX := 600.0
const WallMount = preload("res://scripts/components/WallFurnitureMount.gd")
const Inventory = preload("res://scripts/components/ColonyInventory.gd")
const Lighting = preload("res://scripts/components/FurnitureLighting.gd")
const Picking = preload("res://scripts/components/ObjectPicking.gd")
var _ladders: Node3D
var _bridges: Node3D
var _bridge_aim_revision := -1
const Seating = preload("res://scripts/components/FurnitureSeating.gd")
var _seating := Seating.new(self)
var _games: RefCounted
const GridFence = preload("res://scripts/components/GridFence.gd")
var _fences := GridFence.new(self)
var _fence_support_dirty := false

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
## A piece was placed by the player: its receipt for the tool bar's Undo (doc 23).
signal order_created(receipt: Dictionary)
var _catalog_pending := false
var _require_stock := false
var _moving_shrub := ""
var _moving_furniture := -1
var _moves := preload("res://scripts/components/FurnitureMoves.gd").new(self)
const MovePlan = preload("res://scripts/components/FurnitureMovePlan.gd")
const PlantPlan = preload("res://scripts/components/ShrubPlantingComponent.gd")

var _moving_water_stone := ""
var _defs: Dictionary = ContentRegistry.furniture.duplicate(true) # own copy: furniture_key -> def
var _dock_ui: Node = null
var _slice_y: int = SLICE_OFF_Y

var _active: bool = false
var _active_key: String = ""          # def being placed while the tool is on
var _yaw: int = 0
var _wall_height_offset := 0
var _stock_words: Array = []   # ready and on their way, for the tool bar
var _hover_cell: Vector3i = Vector3i(-1, -1, -1)
var _hover_valid: bool = false
var _invalid_reason: String = ""     # "" | "cell" | "wall" (hint label text)

var _next_ghost_id: int = 1
var _ghosts: Dictionary = {}          # ghost_id -> FurnitureGhostComponent
var _cell_to_ghost: Dictionary = {}   # Vector3i -> ghost_id

var _next_installed_id: int = 1
var _installed: Dictionary = {}       # id -> InstalledFurnitureComponent
var _cell_to_installed: Dictionary = {}   # Vector3i -> installed id
var _wall_to_ghost: Dictionary = {}      # Vector4i(placement reference x,y,z,yaw) -> ghost id
var _wall_to_installed: Dictionary = {}  # separate from floor reservations
var _wall_dirty: bool = false

# ── Work-source plumbing (doc 19 Phase 3) ─────────────────────────────────────
const LEASE_REFRESH_S := 0.25         # the StockpileManager throttle pattern
var ghost_work := preload("res://scripts/components/WorkSourceTable.gd").new()     # ghost id -> fetch-and-build lease
var installed_work := preload("res://scripts/components/WorkSourceTable.gd").new() # installed id -> uninstall lease
var _drop_manager: ItemDropManager = null
var _wakes_connected: bool = false
var _lease_dirty: bool = false
var _lease_accum: float = 0.0

var material_choices: Dictionary = {} # Per-design Place preference; plans save their own choice.

## Helpers (doc 258 step 8): placement rules, ghost visuals and the furniture
## window with the explorer data. No class_name — preloaded here only.
const Rules = preload("res://scripts/components/FurniturePlacementRules.gd")
const Visuals = preload("res://scripts/components/FurnitureGhostVisuals.gd")
var _rules := Rules.new(self, _fences, {"ghosts": _ghosts, "installed": _installed,
	"cell_to_ghost": _cell_to_ghost, "cell_to_installed": _cell_to_installed,
	"wall_to_ghost": _wall_to_ghost, "wall_to_installed": _wall_to_installed})
var _visuals := Visuals.new(self)
var _window := preload("res://scripts/components/FurnitureWindow.gd").new(self, _rules)


func _ready() -> void:
	_games = preload("res://scripts/components/BoardGameRecreation.gd").new(self)
	ghost_placed.connect(func(_id: int): mark_catalog_dirty())
	ghost_cancelled.connect(func(_id: int): mark_catalog_dirty())
	furniture_installed.connect(func(_key: String, _cell: Vector3i): mark_catalog_dirty())
	furniture_uninstalled.connect(func(_key: String, _cell: Vector3i): mark_catalog_dirty())
	add_to_group("furniture_controller")
	add_to_group("object_explorer_provider")
	add_to_group(SaveManager.OWNER_GROUP)
	var fire_sound := preload("res://scripts/components/FurnitureFireSound.gd").new()
	fire_sound.name = "FireSound"
	fire_sound.furniture = self
	add_child(fire_sound)
	_ladders = preload("res://scripts/systems/LadderSystem.gd").new()
	add_child(_ladders)
	_bridges = preload("res://scripts/systems/BridgeSystem.gd").new()
	add_child(_bridges)
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
	ghost_work.on_gone = func(_id: Variant, _task: Task) -> void: _mark_lease_dirty()
	TaskManager.task_released.connect(func(_task: Task, _dwarf: int, _reason: int) -> void: mark_catalog_dirty())
	StockpileManager.stockpile_changed.connect(func(_k: String, _d: int) -> void: _mark_lease_dirty())
	WorldData.chunk_dirtied.connect(_on_terrain_changed, CONNECT_DEFERRED)
	WorldClock.season_changed.connect(_refresh_plant_models)
	PlacedEntityRegistry.occupancy_changed.connect(func(_lo: Vector3i, _size: Vector3i): _seating.dirty = true)
	_window.build()


func get_defs() -> Dictionary:
	return _defs


# ── Read-only lookups for other systems; never mutate what these return ──
func get_installed(id: int) -> InstalledFurnitureComponent: return _installed.get(id)
func get_ghost(id: int) -> FurnitureGhostComponent: return _ghosts.get(id)
func get_installed_pieces() -> Array: return _installed.values()
func get_ghost_pieces() -> Array: return _ghosts.values()
func get_installed_ids() -> Array: return _installed.keys()
func get_installed_at(cell: Vector3i) -> InstalledFurnitureComponent: return _installed.get(int(_cell_to_installed.get(cell, -1)))
func get_ghost_at(cell: Vector3i) -> FurnitureGhostComponent: return _ghosts.get(int(_cell_to_ghost.get(cell, -1)))
func get_seating() -> Seating: return _seating
func get_slice_y() -> int: return _slice_y
func get_ladders() -> Node3D: return _ladders
func get_bridges() -> Node3D: return _bridges
func install_now(key: String, origin: Vector3i, yaw: int) -> void: _install(key, _defs[key], origin, yaw)
func get_moves() -> RefCounted: return _moves
func get_board_games() -> RefCounted: return _games
func get_drop_manager() -> Variant: return _drop_manager # may be a freed node; callers check
func get_dock_ui() -> Node: return _dock_ui
## The cursor's tool state, for the ghost visuals.
func placement_state() -> Dictionary:
	return {"key": _active_key, "yaw": _yaw, "valid": _hover_valid, "reason": _invalid_reason,
		"cell": _hover_cell, "moving_shrub": _moving_shrub}


## The furniture a packed item installs as, or {} for ordinary goods. Appeal and
## other piece facts live only in the furniture definition.
func def_for_item(item_key: String) -> Dictionary:
	for def: Dictionary in _defs.values():
		if String(def.get("item_key", "")) == item_key: return def
	return {}


## Requests without a committed item reserve shared loose/storage availability
## by item_key, including older saved plans. Claimed/fetched/carrying plans have
## already removed their unit from that pool and must not subtract it again.
func get_catalog_stock() -> Dictionary:
	var loose: Dictionary = _drop_manager.get_unreserved_counts() if is_instance_valid(_drop_manager) else {}
	# Automatic storage hauling must not hide owned stock from placement.
	# Outgoing stored claims are added back here and subtracted below once.
	for offer: Dictionary in TaskManager.placement_haul_offers():
		loose[offer.key] = int(loose.get(offer.key, 0)) + int(offer.count)
	var outgoing := StockpileManager.get_outgoing_totals()
	var promised := StockpileManager.get_promised_totals()
	var pending := {}
	var requested := {}
	for ghost: FurnitureGhostComponent in _ghosts.values():
		if ghost.has_method("spare_claimed_units"):
			loose[ghost.item_key] = int(loose.get(ghost.item_key, 0)) + ghost.spare_claimed_units()
		requested[ghost.furniture_key] = int(requested.get(ghost.furniture_key, 0)) + 1
		if not ghost.has_committed_item() and ghost.required_instance_id.is_empty():
			pending[ghost.item_key] = int(pending.get(ghost.item_key, 0)) + 1
	var result := {}
	if is_instance_valid(_ladders):
		var ladder_stock: Dictionary = _ladders.pending_sections()
		pending[_ladders.definition.item_key] = ladder_stock.pending
		requested[_ladders.KEY] = ladder_stock.requested
	if is_instance_valid(_bridges):
		var bridge_stock: Dictionary = _bridges.pending_kits()
		pending[_bridges.definition.item_key] = bridge_stock.pending
		requested[_bridges.KEY] = bridge_stock.requested
	for key: String in _defs:
		var item_key := String(_defs[key].item_key)
		result[key] = {"available": maxi(0, int(loose.get(item_key, 0)) + StockpileManager.get_available_total(item_key)
			- int(outgoing.get(item_key, 0)) - int(promised.get(item_key, 0)) - int(pending.get(item_key, 0))), "reserved": int(requested.get(key, 0))}
	return result

func active_furniture_key() -> String:
	return _active_key if _active else ""

## Current physical destination for catalog navigation; this never grants stock.
func get_catalog_location(key: String) -> Dictionary:
	for id: int in _installed:
		var piece: InstalledFurnitureComponent = _installed[id]
		if piece.furniture_key == key:
			var state := "installed"
			if piece.flagged_uninstall: state = "packing" if _moves.for_source(id).is_empty() else "moving"
			return {"state": state,
				"object_id": "installed:%d" % id, "position": piece.node.global_position}
	for id: int in _ghosts:
		var ghost: FurnitureGhostComponent = _ghosts[id]
		if ghost.furniture_key == key:
			return {"state": "placing" if ghost.required_instance_id.is_empty() else "moving", "object_id": "ghost:%d" % id,
				"position": ghost.node.global_position}
	if int(get_catalog_stock().get(key, {}).get("available", 0)) > 0:
		return {"state": "packed"}
	if is_instance_valid(_drop_manager) and _defs.has(key):
		var physical: Dictionary = _drop_manager.get_inventory_items()
		for entry: Dictionary in physical.carried:
			if entry.key == _defs[key].item_key:
				return {"state": "carried", "position": entry.node.global_position}
	return {"state": "unavailable"}

func has_pending_placement(ghost_id: int) -> bool:
	if ghost_id < -1_000_000:
		return is_instance_valid(_bridges) and _bridges.routes.get(-ghost_id-1_000_000,{}).get("mode","") == "build"
	return _ghosts.has(ghost_id)

func mark_catalog_dirty() -> void:
	if _catalog_pending: return
	_catalog_pending = true
	_emit_catalog_changed.call_deferred()

func _emit_catalog_changed() -> void:
	_catalog_pending = false
	_seating.dirty = true # Refresh stock-dependent validity even when the mouse is still.
	if _active and _require_stock and placement_available(_active_key) <= 0:
		deactivate()
	_count_stock()
	catalog_changed.emit()


## What the tool bar shows (doc 23, "The tool bar"): the piece being placed or moved with
## its picture, how many are ready and on their way, a wall piece's mount level as a
## stepper, and the ghost's hint ("Needs a clear, level 3 × 3 area").
func tool_bar_state() -> Dictionary:
	var def: Dictionary = _defs.get(_active_key, {})
	var moving := _moving_furniture >= 0 or not _moving_shrub.is_empty() or not _moving_water_stone.is_empty()
	var picture := "res://assets/ui/furniture/%s.png" % _active_key.get_slice(":", 2)
	if not ResourceLoader.exists(picture): picture = Inventory.thumbnail_path(String(def.get("item_key", "")))
	var state := {"tool": TOOL_ID, "family": "settlement", "picture": picture, "message": _visuals.hint_text,
		"name": ("Move · %s" if moving else "Place · %s") % String(def.get("display_name", _active_key))}
	if _require_stock and not _stock_words.is_empty(): state.standing = _stock_words
	if WallMount.is_wall(def) and _hover_valid:
		var level := WallMount.mount_cell(def, _hover_cell).y
		state.settings = [{"id": "mount", "label": "Mount level", "value": level, "min": level - 1 if _wall_height_offset > -WorldData.WORLD_SIZE_Y else level,
			"max": level + 1, "keys": "Alt + Wheel", "tooltip": "The level the bracket is fixed at, on the wall you point at."}]
	return state


func set_tool_setting(id: String, value: Variant) -> void:
	if id != "mount" or not WallMount.is_wall(_defs.get(_active_key, {})) or not _hover_valid: return
	var step := signi(int(value) - WallMount.mount_cell(_defs[_active_key], _hover_cell).y)
	_wall_height_offset = clampi(_wall_height_offset + step, -WorldData.WORLD_SIZE_Y, WorldData.WORLD_SIZE_Y)
	_update_hover(true)


## How many of the piece being placed are ready, and on their way, for the tool bar.
func _count_stock() -> void:
	_stock_words = []
	if not _active or not _require_stock: return
	var coming := int(get_catalog_stock().get(_active_key, {}).get("reserved", 0))
	_stock_words = ["%d ready" % placement_available(_active_key), "%d on %s way" % [coming, "its" if coming == 1 else "their"]]


func order_is_pending(receipt: Dictionary) -> bool:
	return has_pending_placement(int(receipt.ghost_id))


func undo_order(receipt: Dictionary) -> int:
	if not order_is_pending(receipt): return 0
	cancel_ghost(int(receipt.ghost_id))
	return 1


func inspect_order(receipt: Dictionary) -> void:
	var explorer := get_tree().get_first_node_in_group("object_explorer")
	if order_is_pending(receipt) and int(receipt.ghost_id) > 0 and explorer != null:
		explorer.select_object(self, "ghost:%d" % int(receipt.ghost_id))


## A placement the player made, for the tool bar's Undo.
func _placed(ghost_id: int) -> void:
	var def: Dictionary = _defs.get(_active_key, {})
	var left := placement_available(_active_key) if _require_stock else -1
	order_created.emit({"ghost_id": ghost_id, "message": "Placed %s%s" % [String(def.get("display_name", _active_key)).to_lower(),
		" · %d left" % left if left >= 0 else ""]})

func get_stats() -> Dictionary:
	var uninstalling := 0
	for installed_id: int in _installed:
		if (_installed[installed_id] as InstalledFurnitureComponent).flagged_uninstall:
			uninstalling += 1
	return { "ghosts": _ghosts.size(), "installed": _installed.size(), "uninstalling": uninstalling }

## Zone/furniture mutual exclusion (doc 19 Phase 2 acceptance): the zone
## tool rejects cells covered by any ghost footprint or installed piece.
func blocks_zone_cell(cell: Vector3i) -> bool:
	if is_instance_valid(_bridges) and _bridges.reserves(AABB(Vector3(cell)+Vector3.UP,Vector3.ONE)): return true
	return _cell_to_ghost.has(cell) or _cell_to_installed.has(cell) \
		or (is_instance_valid(_ladders) and _ladders.reserves(AABB(Vector3(cell) + Vector3.UP, Vector3.ONE)))

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
	if require_stock and placement_available(furniture_key) <= 0:
		return
	deactivate()   # clean swap if a different def was active
	_wall_height_offset = 0
	_require_stock = require_stock
	_active = true
	_active_key = furniture_key
	_yaw = 0
	_ensure_preview()
	_count_stock()
	tool_active_changed.emit(true)

func deactivate() -> void:
	if not _active:
		return
	_active = false
	_active_key = ""
	_moving_shrub = ""
	_moving_water_stone = ""
	_moving_furniture = -1
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

func _exit_tree() -> void:
	_fences.clear()
	if _games != null:
		for game in _games.games.values(): game.cancel()

func _process(delta: float) -> void:
	if _fence_support_dirty:
		_fence_support_dirty = false
		_fences.revalidate_support()
	if _games != null: _games.tick(delta * WorldClock.speed)
	# Lazy sibling hookup (the StockpileManager pattern) + throttled lease pass.
	if not _wakes_connected:
		_drop_manager = ItemDropManager.find(get_tree())
		if _drop_manager != null:
			_drop_manager.drop_spawned.connect(func(_key: String) -> void: _mark_lease_dirty())
			_drop_manager.loose_items_changed.connect(mark_catalog_dirty)
			mark_catalog_dirty()
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
	mark_catalog_dirty()

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
					and _window.try_select_at_screen(mb_off.position):
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
			_yaw = 0 if GridFence.is_post(_defs.get(_active_key,{})) else (_yaw + 1) % 4
			_update_hover(true)
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if WallMount.is_wall(_defs.get(_active_key,{})) and mb.pressed and mb.alt_pressed \
				and mb.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			_wall_height_offset = clampi(_wall_height_offset+(1 if mb.button_index==MOUSE_BUTTON_WHEEL_UP else -1),-WorldData.WORLD_SIZE_Y,WorldData.WORLD_SIZE_Y)
			_update_hover(true,mb.position)
			get_viewport().set_input_as_handled()
			return
		if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
			return
		_update_hover(true, mb.position) # Recheck obstruction at the actual click.
		if _seating.snap.is_empty() and _window.try_select_at_screen(mb.position):
			get_viewport().set_input_as_handled()
			return
		if _hover_valid:
			_confirm_ghost()
			get_viewport().set_input_as_handled()


# ── Hover / validity ──────────────────────────────────────────────────────────

func _update_hover(force: bool = false, screen_pos: Vector2 = Vector2.INF) -> void:
	var pointer := get_viewport().get_mouse_position() if screen_pos == Vector2.INF else screen_pos
	var hit := surface_cell_for(pointer)
	if GridFence.applies(_defs.get(_active_key,{})):
		if hit.is_empty():
			_hover_cell = Vector3i(-1,-1,-1)
			_hover_valid = false
			if _visuals.preview!=null: _visuals.preview.hide()
			_visuals.hint_text = ""
			return
		var camera := get_viewport().get_camera_3d()
		var point := camera.project_ray_origin(pointer)+camera.project_ray_normal(pointer)*float(hit.distance)
		var vertex := Vector3i(roundi(point.x),int(hit.y),roundi(point.z))
		if vertex==_hover_cell and not force and not _seating.dirty: return
		_seating.dirty = false
		_hover_cell = vertex
		_hover_valid = _placement_valid(vertex)
		_position_preview(vertex)
		if _visuals.preview!=null: _fences.preview(_defs[_active_key],vertex,_yaw,_visuals.preview,_visuals.material)
		return
	if _active_key == _bridges.KEY and not hit.is_empty():
		var raw_cell := Vector3i(hit.x,hit.y,hit.z)
		if raw_cell == _seating.aim and not force and not _seating.dirty and _bridge_aim_revision == NavGrid.navigation_revision:
			return
		_seating.resolve(raw_cell)
		_bridge_aim_revision = NavGrid.navigation_revision
		var aim: Dictionary = _bridges.from_hit(hit,_yaw)
		_yaw = aim.yaw
		_hover_cell = aim.base
		_hover_valid = _placement_valid(_hover_cell)
		_position_preview(_hover_cell)
		return
	if _active_key == _ladders.KEY:
		var aim: Dictionary = _ladders.from_hit(hit, _yaw)
		if not aim.is_empty():
			_yaw = aim.yaw
			hit = {"x":aim.base.x, "y":aim.base.y, "z":aim.base.z}
		else: hit = {}
	if WallMount.is_wall(_defs.get(_active_key, {})):
		var prior_yaw := _yaw
		hit = _wall_mount_hit(hit)
		force = force or _yaw != prior_yaw
	if hit.is_empty():
		_seating.reset()
		_hover_cell = Vector3i(-1, -1, -1)
		_hover_valid = false
		if _visuals.preview != null:
			_visuals.preview.visible = false
		_visuals.hint_text = ""
		return
	var cell := Vector3i(int(hit["x"]), int(hit["y"]), int(hit["z"]))
	if cell == _seating.aim and not force and not _seating.dirty:
		return
	_seating.resolve(cell)
	if not _seating.snap.is_empty():
		cell = _seating.snap.origin
		_yaw = _seating.snap.yaw
	else:
		cell = Rules.cursor_origin(_defs.get(_active_key, {}), cell, _yaw)
	_hover_cell = cell
	_hover_valid = _placement_valid(cell)
	_position_preview(cell)


func _placement_valid(origin: Vector3i) -> bool:
	_invalid_reason = ""
	var def: Dictionary = _defs.get(_active_key, {})
	if _active_key == _bridges.KEY:
		_invalid_reason = _bridges.placement_reason(origin,_yaw)
		return _invalid_reason.is_empty()
	if _active_key == _ladders.KEY:
		_invalid_reason = _ladders.placement_reason(origin, _yaw)
		return _invalid_reason.is_empty()
	if WallMount.is_wall(def):
		_invalid_reason = _rules.wall_placement_reason(def, origin, _yaw)
		return _invalid_reason.is_empty()
	_invalid_reason = _floor_placement_reason(def, origin, _yaw)
	return _invalid_reason.is_empty()


func _floor_placement_reason(def: Dictionary, origin: Vector3i, yaw: int) -> String:
	return _rules.floor_placement_reason(def, origin, yaw, _moving_water_stone, _moving_shrub)


func get_dining_seats(table_id: int) -> Array[Dictionary]:
	return _seating.installed_seats(table_id)


func _bounds_cells(bounds: AABB) -> Array[Vector3i]:
	return Rules.bounds_cells(bounds)


## Visual overlap is separate from NavGrid occupancy: a four-high door is
## walkable but still cannot pass through an elevated torch. Cache per asset.
func visual_bounds(def: Dictionary, origin: Vector3i, yaw: int) -> AABB:
	return _rules.visual_bounds(def, origin, yaw)


func _on_terrain_changed(_cx: int, _cy: int, _cz: int) -> void:
	_fence_support_dirty = true
	_seating.dirty = true
	if not _wall_to_ghost.is_empty() or not _wall_to_installed.is_empty():
		_wall_dirty = true
	if _active:
		_hover_cell = Vector3i(-1, -1, -1) # refresh stationary cursor after mining


func _revalidate_wall_mounts() -> void:
	for id: int in _wall_to_ghost.values():
		var ghost: FurnitureGhostComponent = _ghosts[id]
		if not _rules.wall_structure_valid(ghost.def, ghost.origin_cell, ghost.yaw_steps):
			cancel_ghost(id)
	for id: int in _wall_to_installed.values():
		var piece: InstalledFurnitureComponent = _installed[id]
		if not _rules.wall_structure_valid(piece.def, piece.origin_cell, piece.yaw_steps):
			_teardown_installed(id, true)


## Preserve the clicked wall cell's height. Floor aiming provides a convenient
## default with R for facing; Alt+wheel nudges either mode one block at a time.
func _wall_mount_hit(hit: Dictionary) -> Dictionary:
	if hit.is_empty():
		return {}
	var normal: Vector3i = hit.get("normal", Vector3i.ZERO)
	if normal.y < 0: return {}
	var origin := Vector3i(int(hit.x),int(hit.y),int(hit.z))
	if normal.y == 0 and normal != Vector3i.ZERO:
		for yaw in range(4):
			if WallMount.back(yaw) == -normal:
				_yaw = yaw
				break
		origin = WallMount.origin_for_mount(_defs[_active_key],origin+normal)
	origin.y += _wall_height_offset
	return {"x":origin.x,"y":origin.y,"z":origin.z}


func _is_valid_cell(cell: Vector3i) -> bool:
	return _rules.is_valid_cell(cell)


func terrain_block_id(wx: int, wy: int, wz: int) -> int:
	if WorldData.chunk_exists(wx >> 4, wy >> 4, wz >> 4):
		return WorldData.get_block(wx, wy, wz)
	return WorldData.get_live_block(wx, wy, wz)


# ── Ghost visuals (FurnitureGhostVisuals) ─────────────────────────────────────

func _ensure_preview() -> void:
	_free_preview()
	_visuals.create(_active_key)
	_update_hover(true)


func _free_preview() -> void:
	_visuals.clear()
	_seating.reset()
	_hover_cell = Vector3i(-1, -1, -1)
	_hover_valid = false


func _position_preview(origin: Vector3i) -> void:
	_visuals.place(origin)


func _update_hint(origin: Vector3i) -> void:
	_visuals.update_hint(origin)


func _world_pos(def: Dictionary, origin: Vector3i, yaw: int) -> Vector3:
	return Rules.world_pos(def, origin, yaw)


func make_ghost_material() -> StandardMaterial3D:
	return Visuals.make_ghost_material()


func make_solid_material() -> StandardMaterial3D:
	return Visuals.make_solid_material()


func _instance_model(furniture_key: String, override: Material, definition: Dictionary = {}) -> Node3D:
	return Visuals.instance_model(furniture_key, override, _defs.get(furniture_key, {}) if definition.is_empty() else definition)


func apply_material(node: Node, mat: Material) -> void:
	Visuals.apply_material(node, mat)


# ── Ghost lifecycle ───────────────────────────────────────────────────────────

func _confirm_ghost(definition: Dictionary = {}, restored_move_id: String = "") -> void:
	if _active_key == _bridges.KEY:
		var id: int = _bridges.place(_hover_cell,_yaw)
		if id > 0:
			ghost_placed.emit(-1_000_000-id)
			_placed(-1_000_000-id)
		_update_hover(true)
		return
	if _active_key == _ladders.KEY:
		_ladders.place(_hover_cell, _yaw)
		_update_hover(true)
		return
	# Enforce the catalog contract at the actual click too. Restore/legacy art
	# fixtures still create standing requests through the unrestricted path.
	if _require_stock and definition.is_empty() and placement_available(_active_key) <= 0:
		deactivate()
		return
	_seating.dirty = true
	var def: Dictionary = _defs.get(_active_key, {}) if definition.is_empty() else definition
	if definition.is_empty() and (GridFence.applies(def) or bool(def.get("plant", false)) or def.has("water_stone")) and not _placement_valid(_hover_cell): return
	var move_id := restored_move_id
	var moving: InstalledFurnitureComponent = _installed.get(_moving_furniture) if definition.is_empty() else null
	if definition.is_empty() and _moving_furniture >= 0:
		if moving == null or moving.flagged_uninstall:
			deactivate()
			return
		if not _placement_valid(_hover_cell): return
		move_id = _moves.prepare(moving)
	var ghost: FurnitureGhostComponent = MovePlan.new() if not move_id.is_empty() else PlantPlan.new() if bool(def.get("plant", false)) else FurnitureGhostComponent.new()
	ghost.required_material_id = String(material_choices.get(_active_key, ""))
	ghost.required_instance_id = _moving_water_stone if def.has("water_stone") else _moving_shrub
	if not move_id.is_empty():
		ghost.required_instance_id = move_id
		ghost.required_material_id = moving.material_id if moving != null else ghost.required_material_id
	ghost.setup(_next_ghost_id, _active_key, def, _hover_cell, _yaw)
	if definition.is_empty() and not _moving_water_stone.is_empty():
		var stones := get_tree().get_first_node_in_group("water_stones")
		if WaterManager.stones[_moving_water_stone].placed and not stones.request_pack(_moving_water_stone): return
	if definition.is_empty() and not _moving_shrub.is_empty():
		var plants := get_tree().get_first_node_in_group("surface_details")
		if plants == null or not plants.designate_uproot(_moving_shrub):
			deactivate()
			return
	var mat := make_ghost_material()
	mat.albedo_color = Color(TINT_PLACED.r, TINT_PLACED.g, TINT_PLACED.b, GHOST_ALPHA)
	var node := _instance_model(_active_key, mat, def)
	if node != null:
		add_child(node)
		node.position = _world_pos(def, _hover_cell, _yaw)
		node.rotation = Vector3(0.0, float(_yaw) * PI * 0.5, 0.0)
		node.visible = _piece_visible(def, _hover_cell, _yaw)
	ghost.node = node
	# Work source (doc 19 §3.3): ONE fetch-and-build lease.
	ghost.drop_manager = _drop_manager
	ghost.install_callback = Callable(self, "_on_ghost_build_complete")
	ghost.build_valid_callback = Callable(self, "_can_build_ghost")
	ghost_work.add(ghost.ghost_id, ghost)
	_ghosts[ghost.ghost_id] = ghost
	if GridFence.applies(def): _fences.sync()
	ghost.ensure_claim() # Restore exact-instance promises before loose goods/cargo.
	if moving != null: moving.set_uninstall(true)
	for cell: Vector3i in ghost.footprint_cells():
		_cell_to_ghost[cell] = ghost.ghost_id
	if WallMount.is_wall(def):
		_wall_to_ghost[Rules.wall_key(ghost.origin_cell, ghost.yaw_steps)] = ghost.ghost_id
		_wall_dirty = true
	_mark_lease_dirty()
	print("FurniturePlacementController: ghost %d (%s) at %s yaw %d." % [
		ghost.ghost_id, _active_key, str(_hover_cell), _yaw])
	ghost_placed.emit(ghost.ghost_id)
	if definition.is_empty(): _placed(ghost.ghost_id)
	_next_ghost_id += 1
	if definition.is_empty():
		ghost.update_lease() # Player intent can redirect storage hauling even while paused.
	if definition.is_empty() and (not _moving_shrub.is_empty() or not _moving_water_stone.is_empty() or not move_id.is_empty()):
		deactivate()
		return
	_update_hover(true)   # own footprint now invalid — retint immediately


func cancel_ghost(ghost_id: int) -> void:
	if ghost_id < -1_000_000:
		_bridges.perform_explorer_action(-ghost_id-1_000_000,"cancel")
		ghost_cancelled.emit(ghost_id)
		return
	_seating.dirty = true
	if not _ghosts.has(ghost_id):
		return
	var ghost: FurnitureGhostComponent = _ghosts[ghost_id]
	# Retiring releases the ghost's item claim back to ordinary hauling.
	ghost_work.retire(ghost_id, true)
	_mark_lease_dirty()
	for cell: Vector3i in ghost.footprint_cells():
		_cell_to_ghost.erase(cell)
	if WallMount.is_wall(ghost.def):
		_wall_to_ghost.erase(Rules.wall_key(ghost.origin_cell, ghost.yaw_steps))
	if ghost.node != null and is_instance_valid(ghost.node):
		ghost.node.queue_free()
	_ghosts.erase(ghost_id)
	if GridFence.applies(ghost.def): _fences.sync()
	if _window.ghost_id == ghost_id:
		_window.close()
	ghost_cancelled.emit(ghost_id)
	if ghost.def.has("water_stone") and not ghost.required_instance_id.is_empty():
		var stones := get_tree().get_first_node_in_group("water_stones")
		if stones != null: stones.cancel_pack(ghost.required_instance_id)
	elif _moves.records.has(ghost.required_instance_id):
		_moves.cancel(ghost.required_instance_id)
	elif not ghost.required_instance_id.is_empty():
		var plants := get_tree().get_first_node_in_group("surface_details")
		if plants != null: plants.cancel_clearing(ghost.required_instance_id)


## The real build path (doc 19 §3.3 step 4): the fetching dwarf finished the
## work swing. Retire the ghost WITHOUT cancelling its lease — the dwarf's
## own complete_dwarf_task resolves it — then run the shared install.
func _on_ghost_build_complete(ghost: FurnitureGhostComponent) -> void:
	if not _ghosts.has(ghost.ghost_id):
		return
	# The builder normally holds the item by now; retiring frees any stale claim.
	ghost_work.retire(ghost.ghost_id, false)
	for cell: Vector3i in ghost.footprint_cells():
		_cell_to_ghost.erase(cell)
	if WallMount.is_wall(ghost.def):
		_wall_to_ghost.erase(Rules.wall_key(ghost.origin_cell, ghost.yaw_steps))
	if ghost.node != null and is_instance_valid(ghost.node):
		ghost.node.queue_free()
	_ghosts.erase(ghost.ghost_id)
	if _window.ghost_id == ghost.ghost_id:
		_window.close()
	if ghost.def.has("water_stone"):
		WaterManager.place_stone(ghost.fetched_instance_id,ghost.origin_cell+Vector3i.UP)
		furniture_installed.emit(ghost.furniture_key,ghost.origin_cell)
	elif bool(ghost.def.get("plant", false)):
		var plants := get_tree().get_first_node_in_group("surface_details")
		if bool(ghost.def.get("from_cutting", false)):
			plants.plant_cutting(String(ghost.def.plant_definition), ghost.origin_cell, ghost.yaw_steps)
		else:
			plants.plant_shrub(ghost.fetched_instance_id, String(ghost.def.plant_definition), ghost.origin_cell, ghost.yaw_steps)
		furniture_installed.emit(ghost.furniture_key, ghost.origin_cell)
	else:
		var installed_id := _next_installed_id
		_install(ghost.furniture_key, ghost.def, ghost.origin_cell, ghost.yaw_steps, ghost.material_id)
		_moves.installed(ghost.fetched_instance_id, _installed[installed_id])


## Checked by the dwarf before consuming its carried item, including the frame
## between a support edit and the controller's deferred terrain notification.
func _can_build_ghost(ghost: FurnitureGhostComponent) -> bool:
	if not _ghosts.has(ghost.ghost_id):
		return false
	if GridFence.applies(ghost.def): return _fences.placement_reason(ghost.def,ghost.origin_cell,ghost.yaw_steps,ghost).is_empty()
	if ghost.def.has("water_stone"):
		var stones := get_tree().get_first_node_in_group("water_stones")
		return WaterManager.stones.has(ghost.fetched_instance_id) and not WaterManager.stones[ghost.fetched_instance_id].placed and stones != null and stones.placement_reason(ghost.origin_cell).is_empty()
	elif bool(ghost.def.get("plant", false)):
		var plants := get_tree().get_first_node_in_group("surface_details")
		if plants != null and bool(ghost.def.get("from_cutting", false)):
			return plants.planting_reason(String(ghost.def.plant_definition), ghost.origin_cell, "", ghost.ghost_id).is_empty()
		return plants != null and plants.can_plant(ghost.fetched_instance_id, String(ghost.def.plant_definition), ghost.origin_cell, ghost.ghost_id)
	if not _seating.placement_reason(ghost.def, ghost.origin_cell, ghost.yaw_steps, ghost).is_empty():
		return false
	if not WallMount.is_wall(ghost.def):
		if _moves.records.has(ghost.required_instance_id):
			for cell: Vector3i in ghost.footprint_cells():
				if not NavGrid.is_walkable(cell) or _cell_to_installed.has(cell): return false
			if String(ghost.def.get("placement","floor")) == "floor_wall" and not _rules.has_wall_behind(ghost.def,ghost.origin_cell,ghost.yaw_steps): return false
		if Seating.is_chair(ghost.def):
			for cell: Vector3i in ghost.footprint_cells():
				if not NavGrid.is_walkable(cell):
					return false
		return true
	if not _rules.wall_work_support_valid(ghost.def, ghost.origin_cell, ghost.yaw_steps):
		return false
	for cell: Vector3i in _bounds_cells(WallMount.bounds_for(ghost.def, ghost.origin_cell, ghost.yaw_steps)):
		if PlacedEntityRegistry.occupies(cell):
			return false
	return true


## DEV: materialise a ghost without a dwarf (the DEV-mine precedent). It takes
## one matching item through the ghost's own fetch path, as a dwarf would, and
## installs in that item's material; with no item available it builds free.
func dev_instant_build(ghost_id: int) -> void:
	if not _ghosts.has(ghost_id):
		return
	var ghost: FurnitureGhostComponent = _ghosts[ghost_id]
	if bool(ghost.def.get("plant", false)) or ghost.def.has("water_stone"): return # Requires its real physical item.
	if _moves.records.has(ghost.required_instance_id): return
	if not _can_build_ghost(ghost):
		cancel_ghost(ghost_id)
		return
	var material_id := ghost.required_material_id
	var fetch := ghost.reserve_fetch(ghost.claim_owner_id(), ghost.origin_cell)
	if not fetch.is_empty():
		var item: Node3D = fetch.item
		ghost.cancel_fetch(ghost.claim_owner_id())
		material_id = CraftMaterials.of_item(item)
		ghost.drop_manager.take(item)
		item.queue_free()
	var key := ghost.furniture_key
	var def := ghost.def
	var origin := ghost.origin_cell
	var yaw := ghost.yaw_steps
	cancel_ghost(ghost_id)
	_install(key, def, origin, yaw, material_id)


## Installation proper — Phase 3's fetch executor lands here too, so the
## DEV path and the real path share one implementation.
func _install(key: String, def: Dictionary, origin: Vector3i, yaw: int, material_id: String = "") -> void:
	_seating.dirty = true
	var node := _instance_model(key, make_solid_material(), def)
	if node != null:
		add_child(node)
		node.position = _world_pos(def, origin, yaw)
		node.rotation = Vector3(0.0, float(yaw) * PI * 0.5, 0.0)
		CraftMaterials.apply_palette(node, def, material_id)
		Lighting.attach(node, def)
		if def.has("door_animation"):
			var hinges := preload("res://scripts/components/FurnitureDoorAnimation.gd").new()
			hinges.name = "DoorAnimation"
			node.add_child(hinges)
			hinges.setup(node, def.door_animation)
		if String(def.get("furniture_category", "")) == "door":
			preload("res://scripts/components/UndergroundLighting.gd").bind_door_tree(node, float(def.footprint.width))
		else:
			preload("res://scripts/components/UndergroundLighting.gd").bind_world_tree(node)
		node.visible = _piece_visible(def, origin, yaw)
	# Occupancy: one box per collision region (footprint-local block coords;
	# origin (0,0,0) = bottom-front-left at floor+1). NavGrid invalidates on
	# occupancy_changed (the flag precedent). Offset regions rotate with the model.
	var occupancy_ids: Array[int] = []
	for region in def.get("collision_regions", []):
		var box := Rules.region_occupancy_box(def, region, origin, yaw)
		occupancy_ids.append(PlacedEntityRegistry.register_box(box.min, box.size))
	var component := InstalledFurnitureComponent.new()
	component.setup(_next_installed_id, key, def, origin, yaw)
	component.node = node
	component.material_id = material_id
	component.occupancy_ids = occupancy_ids
	component.cells = Rules.footprint_cells(def, origin, yaw)
	component.uninstall_callback = Callable(self, "_on_uninstall_complete")
	installed_work.add(component.installed_id, component)
	_installed[component.installed_id] = component
	if GridFence.applies(def): _fences.sync()
	for cell: Vector3i in component.cells:
		_cell_to_installed[cell] = component.installed_id
	if WallMount.is_wall(def):
		_wall_to_installed[Rules.wall_key(origin, yaw)] = component.installed_id
		_wall_dirty = true
	print("FurniturePlacementController: installed %s at %s." % [key, str(origin)])
	furniture_installed.emit(key, origin)
	# doc 22: RoomManager tracks door/heat-source cells by direct call, not by
	# subscribing to this signal — it's an autoload and this is a scene node,
	# so the call has to go this direction (see RoomManager's file header).
	RoomManager.on_furniture_changed(key, room_cells(component), def, true)
	_next_installed_id += 1


## The cells RoomManager counts a piece by (anchor + UP inside the room): its footprint,
## or for a wall mount the cell below where it hangs, so it counts in its actual room,
## even above a loft.
func room_cells(component: InstalledFurnitureComponent) -> Array[Vector3i]:
	if WallMount.is_wall(component.def):
		return [WallMount.mount_cell(component.def,component.origin_cell)-Vector3i.UP]
	return component.cells


## The real uninstall path (doc 19 §3.4): the dwarf finished the teardown
## swing. The dwarf's complete_dwarf_task resolves the lease; contents (Phase
## 4) and the packed item re-enter the world as ordinary loose drops.
func _on_uninstall_complete(component: InstalledFurnitureComponent, dwarf_id: int = -1) -> void:
	_teardown_installed(component.installed_id, false, dwarf_id)


## Shared teardown. `cancel_lease` true on the DEV path (a live 📤 lease may
## exist); false when the uninstalling dwarf itself is finishing (its lease
## completes normally).
func _teardown_installed(installed_id: int, cancel_lease: bool, dwarf_id: int = -1) -> void:
	_seating.dirty = true
	if not _installed.has(installed_id):
		return
	var component: InstalledFurnitureComponent = _installed[installed_id]
	component.flagged_uninstall = false
	installed_work.retire(installed_id, cancel_lease)
	for occupancy_id: int in component.occupancy_ids:
		PlacedEntityRegistry.unregister(occupancy_id)
	for cell: Vector3i in component.cells:
		_cell_to_installed.erase(cell)
	if WallMount.is_wall(component.def):
		_wall_to_installed.erase(Rules.wall_key(component.origin_cell, component.yaw_steps))
	if component.node != null and is_instance_valid(component.node):
		component.node.visible = false # switch light off immediately, before queue_free
		component.node.queue_free()
	_installed.erase(installed_id)
	if GridFence.applies(component.def): _fences.sync()
	furniture_uninstalled.emit(component.furniture_key, component.origin_cell)
	RoomManager.on_furniture_changed(component.furniture_key, room_cells(component), component.def, false)
	if _drop_manager != null and is_instance_valid(_drop_manager) and not component.item_key.is_empty():
		var cell := component.origin_cell
		if WallMount.is_wall(component.def): cell = WallMount.mount_cell(component.def,cell)-Vector3i.UP
		if not _moves.packed(component,cell,dwarf_id):
			_drop_manager.spawn_drop(component.item_key, 1, Vector3i(cell.x, cell.y + 1, cell.z), component.material_id)
	if _window.installed_id == installed_id:
		_window.close()


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
			"required_material_id": ghost.required_material_id,
			"key": ghost.furniture_key,
			"origin": SaveManager.pack_v3i(ghost.origin_cell),
			"yaw": ghost.yaw_steps,
		})
		if ghost.def.has("water_stone"): saved_ghosts.back()["stone_id"] = ghost.required_instance_id
		if _moves.records.has(ghost.required_instance_id): saved_ghosts.back()["move_id"] = ghost.required_instance_id
		if bool(ghost.def.get("plant", false)):
			saved_ghosts.back()["plant_work"] = ghost.progress
			saved_ghosts.back()["plant_id"] = ghost.required_instance_id
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
			"material_id": component.material_id,
		}
		if component.def.has("sleep_surface"): entry["assigned_dwarf_id"] = component.assigned_dwarf_id
		saved_installed.append(entry)
	return { "ghosts": saved_ghosts, "installed": saved_installed, "moves": _moves.serialize() }


func restore_state(state: Dictionary) -> void:
	_fences.suspended = true
	_drop_manager = ItemDropManager.find(get_tree())
	_moves.restore(state.get("moves",{}))
	for raw in state.get("ghosts", []):
		if raw is Dictionary:
			_restore_ghost(raw as Dictionary)
	for raw in state.get("installed", []):
		if not (raw is Dictionary):
			continue
		var entry := raw as Dictionary
		var key := String(entry.get("key", ""))
		var requested_id := maxi(int(entry.get("id", _next_installed_id)), 1)
		var prior_next := _next_installed_id
		_next_installed_id = requested_id
		_install(key, _defs[key], SaveManager.unpack_v3i(entry.get("origin", [])),
			int(entry.get("yaw", 0)), String(entry.get("material_id", "")))
		var component: InstalledFurnitureComponent = _installed.get(requested_id)
		_next_installed_id = maxi(_next_installed_id, prior_next)
		if component == null:
			continue
		if component.def.has("sleep_surface"):
			component.assigned_dwarf_id = int(entry.get("assigned_dwarf_id",-1))
			RoomManager.on_bed_assignment_changed(component.origin_cell,component.assigned_dwarf_id)
		if bool(entry.get("flagged_uninstall", false)):
			component.set_uninstall(true)
	_fences.suspended = false
	_fences.sync()


func _restore_ghost(entry: Dictionary) -> void:
	var key := String(entry.get("key", ""))
	var requested_id := maxi(int(entry.get("id", _next_ghost_id)), 1)
	var prior_next := _next_ghost_id
	var prior_key := _active_key
	var prior_material := String(material_choices.get(key, ""))
	material_choices[key] = String(entry.get("required_material_id", ""))
	var prior_cell := _hover_cell
	var prior_yaw := _yaw
	var prior_stone := _moving_water_stone
	_moving_water_stone = String(entry.get("stone_id", ""))
	var prior_plant := _moving_shrub
	_moving_shrub = String(entry.get("plant_id", ""))
	_next_ghost_id = requested_id
	_active_key = key
	_hover_cell = SaveManager.unpack_v3i(entry.get("origin", []))
	_yaw = int(entry.get("yaw", 0))
	_confirm_ghost(_defs[key],String(entry.get("move_id","")))
	material_choices[key] = prior_material
	if _ghosts.has(requested_id) and bool(_defs[key].get("plant", false)):
		_ghosts[requested_id].progress = clampf(float(entry.get("plant_work", 0)), 0, float(_defs[key].planting_seconds))
	_moving_water_stone = prior_stone
	_moving_shrub = prior_plant
	_next_ghost_id = maxi(_next_ghost_id, prior_next)
	_active_key = prior_key
	_hover_cell = prior_cell
	_yaw = prior_yaw


# ── Raycasting ──────────────────────────────────────────────────────────────────

## The first slice-visible solid block under the screen point, as the slice shows
## it (ObjectPicking.terrain_hit with concealed_block: a cave not yet found is
## rock). Construction, Copy and blueprints aim with it too. The cell is the solid
## floor block itself, NavGrid's convention; {} on a miss.
func surface_cell_for(screen_pos: Vector2) -> Dictionary:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return {}
	return Picking.terrain_hit(camera.project_ray_origin(screen_pos),
		camera.project_ray_normal(screen_pos).normalized(), _slice_y, RAY_MAX, Picking.concealed_block)


# ── Slice culling (doc 11 Phase 5 hook) ───────────────────────────────────────

func _piece_visible(def: Dictionary, origin: Vector3i, yaw: int) -> bool:
	return Rules.piece_visible(def, origin, yaw, _slice_y)

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


# ── Object explorer provider (FurnitureWindow) ────────────────────────────────

func pick_explorer_object(start: Vector3, end: Vector3) -> Dictionary:
	return _window.pick_explorer_object(start, end)


func get_explorer_bounds(object_id: Variant) -> AABB:
	return _window.get_explorer_bounds(object_id)


func get_explorer_data(object_id: Variant) -> Dictionary:
	return _window.get_explorer_data(object_id)


func perform_explorer_action(object_id: Variant, action_id: String) -> void:
	_window.perform_explorer_action(object_id, action_id)


func assign_bed(installed_id: int, dwarf_id: int) -> bool:
	var piece: InstalledFurnitureComponent = _installed.get(installed_id)
	return piece != null and preload("res://scripts/components/BedAssignment.gd").assign(self,piece,dwarf_id)


func begin_furniture_move(installed_id: int) -> void:
	var piece: InstalledFurnitureComponent = _installed.get(installed_id)
	if piece == null or piece.flagged_uninstall: return
	if _dock_ui != null: _dock_ui.emit_signal("tool_requested",TOOL_ID)
	activate_for(piece.furniture_key)
	_moving_furniture = installed_id
	_yaw = piece.yaw_steps
	_update_hover(true)


func toggle_uninstall(piece: InstalledFurnitureComponent) -> void:
	var move_id: String = _moves.for_source(piece.installed_id)
	if not move_id.is_empty():
		for ghost: FurnitureGhostComponent in _ghosts.values():
			if ghost.required_instance_id == move_id:
				cancel_ghost(ghost.ghost_id)
				return
	piece.set_uninstall(not piece.flagged_uninstall)


func begin_shrub_move(id: String) -> void:
	var plants := get_tree().get_first_node_in_group("surface_details")
	if plants == null or not plants.can_uproot(id): return
	if _dock_ui != null: _dock_ui.emit_signal("tool_requested", TOOL_ID)
	activate_for(SurfaceDetailRegistry.place_key(String(plants.get_record(id).definition), int(plants.get_record(id).variant)))
	_moving_shrub = id


func begin_water_stone_move(id: String) -> void:
	if not WaterManager.stones.has(id): return
	var record: Dictionary = WaterManager.stones[id]
	if record.placed and record.disallowed: return
	cancel_water_stone_moves(id)
	if _dock_ui != null: _dock_ui.emit_signal("tool_requested",TOOL_ID)
	activate_for("base:water:"+record.kind+"_stone")
	_moving_water_stone = id


func cancel_water_stone_moves(id: String) -> void:
	for ghost_id in _ghosts.keys():
		var ghost: FurnitureGhostComponent = _ghosts[ghost_id]
		if ghost.def.has("water_stone") and ghost.required_instance_id==id: cancel_ghost(ghost_id)
	if _moving_water_stone==id: deactivate()


func cancel_shrub_moves(id: String) -> void:
	for ghost_id: int in _ghosts.keys():
		if _ghosts[ghost_id].required_instance_id == id: cancel_ghost(ghost_id)


func claim_moved_shrub(id: String, dwarf_id: int = -1) -> void:
	for ghost: FurnitureGhostComponent in _ghosts.values():
		if ghost.required_instance_id == id:
			if ghost.has_method("move_worker_quote"): ghost.continuation_worker = dwarf_id
			ghost.update_lease()


func _refresh_plant_models(_season: String) -> void:
	for ghost: FurnitureGhostComponent in _ghosts.values():
		if not bool(ghost.def.get("plant", false)): continue
		if is_instance_valid(ghost.node): ghost.node.queue_free()
		var material := make_ghost_material()
		material.albedo_color = Color(TINT_PLACED, GHOST_ALPHA)
		ghost.node = _instance_model(ghost.furniture_key, material, ghost.def)
		add_child(ghost.node)
		ghost.node.position = _world_pos(ghost.def, ghost.origin_cell, ghost.yaw_steps)
		ghost.node.rotation.y = ghost.yaw_steps * PI * .5
		ghost.node.visible = _piece_visible(ghost.def, ghost.origin_cell, ghost.yaw_steps)
	if _active and bool(_defs.get(_active_key, {}).get("plant", false)):
		_free_preview()
		_ensure_preview()
		_update_hover(true)


## Queued footprints reserve planting space immediately, without nav collision.
## The completing plan may ignore itself; neighbours and other orders still count.
func plant_area_reserved(area: AABB, ignore_ghost := -1) -> bool:
	if is_instance_valid(_ladders) and _ladders.reserves(area): return true
	for ghost: FurnitureGhostComponent in _ghosts.values():
		if ghost.ghost_id == ignore_ghost: continue
		if bool(ghost.def.get("plant", false)):
			var plant := SurfaceDetailRegistry.get_definition(String(ghost.def.plant_definition))
			if area.intersects(preload("res://scripts/components/SurfaceDetailPlacement.gd").planting_area(plant, ghost.origin_cell)): return true
		else:
			for cell: Vector3i in ghost.footprint_cells():
				if area.intersects(AABB(Vector3(cell) + Vector3.UP, Vector3(1, int(ghost.def.get("footprint", {}).get("height", 1)), 1))): return true
	return false

func spare_materials(item_key: String) -> Dictionary:
	var result := StockpileManager.available_materials(item_key)
	if is_instance_valid(_drop_manager):
		for entry: Dictionary in _drop_manager.get_inventory_items().loose:
			if entry.key != item_key or entry.reserved or entry.disallowed: continue
			var id := CraftMaterials.of_item(entry.node)
			result[id] = int(result.get(id, 0)) + int(entry.count)
	for offer: Dictionary in TaskManager.placement_haul_offers():
		if offer.key != item_key: continue
		var id := CraftMaterials.of_item(offer.item)
		result[id] = int(result.get(id, 0)) + int(offer.count)
	return result

func get_material_stock(key: String) -> Dictionary:
	if not _defs.has(key): return {}
	var result := spare_materials(String(_defs[key].item_key))
	for ghost: FurnitureGhostComponent in _ghosts.values():
		if ghost.furniture_key != key or ghost.has_committed_item() or ghost.required_material_id.is_empty(): continue
		var id := ghost.required_material_id
		result[id] = maxi(0, int(result.get(id, 0)) - 1)
	for system in [_ladders, _bridges]:
		if not is_instance_valid(system) or system.KEY != key: continue
		for route: Dictionary in system.routes.values():
			var id := String(route.get("required_material_id", ""))
			if route.mode != "build" or id.is_empty(): continue
			var pending: int = system.sections(route.height) - system.sections(route.built) if system == _ladders else 1
			if system.work.has(route.id) and system.work.get_source(route.id).has_committed_item(): pending -= 1
			result[id] = maxi(0, int(result.get(id, 0)) - pending)
	var total := int(get_catalog_stock().get(key, {}).get("available", 0))
	for id: String in result: result[id] = mini(int(result[id]), total)
	return result

func placement_available(key: String) -> int:
	var id := String(material_choices.get(key, ""))
	if id.is_empty(): return int(get_catalog_stock().get(key, {}).get("available", 0))
	return int(get_material_stock(key).get(id, 0))
