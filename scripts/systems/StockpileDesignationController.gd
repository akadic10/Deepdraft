class_name StockpileDesignationController
extends Node3D

## Storage zones (doc 18): the Zones menu's Storage tool, the zones it paints, and their window.
## The tool is the one every zone shares (ZoneTool.gd): a drag paints a flat rectangle on the
## plane of the cell it began on, a click on a zone opens its window, and Esc is the dock's.
## Zones never merge (the doc 43 adjacency lesson) and stay until removed from their window.
## A zone takes floor a dwarf can stand on (`cell_reason`), and hides above the slice.

@export var camera_path: NodePath
@export var dock_ui_path: NodePath
@export var slice_controller_path: NodePath
@export var window_manager_path: NodePath

const TOOL_ID := "storage_zone"
const ZONE_WINDOW_ID := "storage_zone_info"
const ZoneTool = preload("res://scripts/components/ZoneTool.gd")
const COLOR_VALID := Color(0.25, 0.65, 0.90, 0.30)     # fill, blue-cyan (mining zones own yellow)
const COLOR_VALID_EDGE := Color(0.35, 0.80, 1.00, 0.85)
const COLOR_ZONE := Color(0.25, 0.65, 0.90, 0.22)      # confirmed zone fill
const COLOR_ZONE_EDGE := Color(0.35, 0.80, 1.00, 0.60)

var _lost_floors := {}   # zone cells whose floor block was removed this frame

## Fired on every activate/deactivate — DockUI refreshes button pressed-state
## from it (the SliceController slice_active_changed pattern), so Esc-cancel
## no longer leaves the 📦 button lit until the next dock interaction.
signal tool_active_changed(active: bool)
signal order_created(receipt: Dictionary)

var _dock_ui: Node = null
var _tool: ZoneTool                  # the drag, its preview and the zones on the ground
var _next_zone_id: int = 1
var _zones: Dictionary = {}          # zone_id -> StockpileZoneComponent
var _cell_to_zone: Dictionary = {}   # Vector3i -> zone_id (click lookup)

var _window_manager: UIWindowManager = null
var _window_panel: UIWindow = null
var _window_zone_id: int = -1
var _window_info_label: Label = null
var _storage_panel: MarginContainer


func _ready() -> void:
	add_to_group("stockpile_controller")
	add_to_group(SaveManager.OWNER_GROUP)
	# A container's window closes with its furniture, rather than edit a store no longer there
	# (its edits were lost).
	StockpileManager.container_removed.connect(func(container: StorageComponent) -> void:
		if _storage_panel != null and _storage_panel.storage == container: _close_zone_window())
	_window_manager = get_node_or_null(window_manager_path) as UIWindowManager
	_tool = ZoneTool.new()
	_tool.name = "ZoneTool"
	_tool.tool_id = TOOL_ID
	_tool.here_words = "A storage zone is here"
	_tool.fill = COLOR_VALID
	_tool.edge = COLOR_VALID_EDGE
	_tool.cell_reason = cell_reason
	_tool.zone_at = func(cell: Vector3i) -> int: return int(_cell_to_zone.get(cell, -1))
	_tool.cells_chosen = _confirm_zone
	_tool.zone_clicked = _open_zone_window
	_tool.active_changed.connect(func(on: bool) -> void: tool_active_changed.emit(on))
	add_child(_tool)
	var dock := get_node_or_null(dock_ui_path) as DockUI
	_dock_ui = dock
	if dock != null:
		dock.register_stockpile_controller(self)
		dock.tool_requested.connect(_tool.on_tool_requested)
	var slice_controller := get_node_or_null(slice_controller_path)
	if slice_controller != null and slice_controller.has_signal("slice_changed"):
		slice_controller.connect("slice_changed", _tool.set_slice)
	SkyController.hearthblock_lighting_changed.connect(_on_hearthblock_lighting_changed)
	WorldData.block_changed.connect(_on_block_changed)
	_build_window()


## A zone's cells are its floor blocks: a mined one leaves the zone, its goods falling (doc 31).
func _on_block_changed(cell: Vector3i, old_id: int, new_id: int) -> void:
	if _cell_to_zone.has(cell) and BlockRegistry.is_solid(old_id) and not BlockRegistry.is_solid(new_id):
		_lost_floors[cell] = true


func _drop_lost_floors() -> void:
	var by_zone := {}
	for cell: Vector3i in _lost_floors:
		if _cell_to_zone.has(cell) and not BlockRegistry.is_solid(WorldData.get_block(cell.x, cell.y, cell.z)):
			var lost: Array[Vector3i] = by_zone.get(_cell_to_zone[cell], [] as Array[Vector3i])
			lost.append(cell)
			by_zone[_cell_to_zone[cell]] = lost
	_lost_floors.clear()
	for zone_id: int in by_zone:
		var lost: Array[Vector3i] = by_zone[zone_id]
		var zone: StockpileZoneComponent = _zones[zone_id]
		if lost.size() == zone.cell_count():
			remove_zone(zone_id)
		else:
			StockpileManager.remove_zone_cells(zone, lost)
			for cell: Vector3i in lost: _cell_to_zone.erase(cell)
			var colors := _zone_colors()
			_tool.show_zone(zone_id, zone.tile_cells, colors[0], colors[1])
		var drops: ItemDropManager = ItemDropManager.find(get_tree())
		if drops != null: drops.settle_cells(lost)


func _process(_delta: float) -> void:
	if not _lost_floors.is_empty(): _drop_lost_floors()


# ── The tool (ZoneTool) ───────────────────────────────────────────────────────

func is_active() -> bool:
	return _tool.active


func activate() -> void:
	_tool.activate()


func deactivate() -> void:
	_tool.deactivate()


# ── Which cells a zone takes ──────────────────────────────────────────────────

## A click on one of our zones opens its window. ObjectExplorerController asks every click tool
## this by name before it selects the bare ground under the pointer, so the name must stay.
func try_select_zone_at_screen(screen_pos: Vector2) -> bool:
	return _tool.select_zone_at(screen_pos)


## Why a floor cell can't hold storage, or "" when it can: clear of the world's edge and of
## water, with no furniture on it, in a place the colony has found, in no other zone, and
## ground a dwarf can stand on (NavGrid: solid floor, 3 clear blocks, nothing in the way).
func cell_reason(cell: Vector3i) -> String:
	if ZoneTool.near_edge(cell): return "Too near the world's edge"
	if _cell_to_zone.has(cell): return "Already a storage zone"
	var col := Vector2i(cell.x, cell.z)
	if WorldGenerator.lake_columns.has(col) or WorldGenerator.tarn_columns.has(col): return "Storage can't stand in water"
	# Zones never overlap furniture plans or installed pieces (doc 19 Phase 2). An installed
	# piece already fails is_walkable; a plan is not solid, so it needs its own check.
	var furniture := get_tree().get_first_node_in_group("furniture_controller")
	if furniture != null and furniture.has_method("blocks_zone_cell") and bool(furniture.call("blocks_zone_cell", cell)):
		return "Furniture stands here"
	# A cave not yet found is rock to every tool: no stockpile stands in it (Hard Rule 11).
	if InteriorTracker.is_hidden_cave(cell + Vector3i.UP): return "Nobody has found this place"
	var taken := _tool.taken_by_another(cell)
	if not taken.is_empty(): return taken
	if not NavGrid.is_walkable(cell): return "A dwarf can't stand here"
	return ""


# ── Zone lifecycle ────────────────────────────────────────────────────────────

func _confirm_zone(cells: Array[Vector3i]) -> void:
	var zone := _create_zone(cells)
	order_created.emit({"zone_id": zone.zone_id, "source": zone,
		"message": "Stockpile created · %d cells" % cells.size()})


## What the tool bar shows (doc 23, "The tool bar"): while a zone is dragged, its cells and its
## size, never making the player count blocks (Alen's playtest note, 2026-07-06); otherwise why
## the cell under the pointer can't hold storage, as the other zone tools say it.
func tool_bar_state() -> Dictionary:
	var state := {"tool": TOOL_ID}
	if _tool.dragging:
		var size := _tool.drag_rect().size
		var blocked := size.x * size.y - _tool.preview.size()
		state.selection = {"count": "%d cell%s" % [_tool.preview.size(), "" if _tool.preview.size() == 1 else "s"],
			"detail": "%d × %d%s" % [size.x, size.y, ", %d blocked" % blocked if blocked > 0 else ""], "at": _tool.pointer}
	elif _tool.hover != ZoneTool.NOWHERE and not _tool.hover_reason.is_empty() and not _cell_to_zone.has(_tool.hover):
		state.selection = {"count": "Can't store here", "detail": _tool.hover_reason, "short": true, "at": _tool.pointer}
	return state


func order_is_pending(receipt: Dictionary) -> bool:
	return _zones.get(receipt.zone_id) == receipt.source


func undo_order(receipt: Dictionary) -> int:
	if not order_is_pending(receipt): return 0
	var count: int = receipt.source.cell_count()
	remove_zone(receipt.zone_id) # Existing removal releases haulers and stored goods.
	return count


func inspect_order(receipt: Dictionary) -> void:
	if order_is_pending(receipt): _open_zone_window(receipt.zone_id)


func inspect_storage(zone: StockpileZoneComponent) -> bool:
	if zone == null or _zones.get(zone.zone_id) != zone or zone.floor_y > _tool.slice_y: return false
	_open_zone_window(zone.zone_id)
	return true


func _create_zone(cells: Array[Vector3i], requested_id: int = -1) -> StockpileZoneComponent:
	var zone_id := requested_id if requested_id > 0 else _next_zone_id
	var zone := StockpileZoneComponent.new()
	zone.setup(zone_id, cells)
	_zones[zone_id] = zone
	for cell: Vector3i in cells:
		_cell_to_zone[cell] = zone_id
	var colors := _zone_colors()
	_tool.show_zone(zone_id, cells, colors[0], colors[1])
	StockpileManager.register_zone(zone)   # work source goes live (doc 18 Phase 3)
	print("StockpileDesignationController: zone %d created (%d cells at Y %d)." % [
		zone_id, cells.size(), zone.floor_y])
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
	_tool.hide_zone(zone_id)
	if _window_zone_id == zone_id:
		_close_zone_window()


## Cross-system lookup (doc 19 Phase 2): the furniture tool must not place
## on zone cells. Mirrored by our own cell_reason refusing furniture.
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
			stacks.back()["disallowed"] = bool(stack.get("disallowed", false))
			if stack.has("instance_id"): stacks.back()["instance_id"] = stack.instance_id
			stacks.back()["material_id"] = String(stack.get("material_id", ""))
			if float(stack.get("spoil", 0.0)) > 0.0: stacks.back()["spoil"] = float(stack.spoil)
		saved_zones.append({
			"id": zone_id,
			"cells": cells,
			"storage_filter": zone.serialize_filter(),
			"priority": zone.priority,
			"stacks": stacks,
		})
	return { "zones": saved_zones }


func restore_state(state: Dictionary) -> void:
	var drop_manager := ItemDropManager.find(get_tree())
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
		zone.restore_filter(entry.storage_filter)
		zone.priority = clampi(int(entry.get("priority", StorageComponent.LAST_PRIORITY)), StorageComponent.FIRST_PRIORITY, StorageComponent.LAST_PRIORITY)
		for stack_raw in entry.get("stacks", []):
			if not (stack_raw is Dictionary):
				continue
			var saved_stack := stack_raw as Dictionary
			var cell := SaveManager.unpack_v3i(saved_stack.get("cell", []))
			var item_key := String(saved_stack.get("item", ""))
			var count := maxi(int(saved_stack.get("count", 0)), 0)
			if count <= 0 or item_key.is_empty() or not zone.has_cell(cell):
				continue
			if drop_manager != null:
				var kept := mini(count, drop_manager.item_capacity(item_key))
				if count > kept:
					drop_manager.spawn_drop(item_key, count - kept, cell + Vector3i.UP)
				count = kept
			zone.cell_stacks[cell] = { "item": item_key, "count": count }
			zone.cell_stacks[cell]["disallowed"] = false
			if saved_stack.has("instance_id"): zone.cell_stacks[cell]["instance_id"] = saved_stack.instance_id
			zone.cell_stacks[cell]["material_id"] = String(saved_stack.get("material_id", ""))
			var spoil := clampf(float(saved_stack.get("spoil", 0.0)), 0.0, 1.0)
			if spoil > 0.0: zone.cell_stacks[cell]["spoil"] = spoil
			if drop_manager != null:
				drop_manager.restore_stored_item(item_key, cell, count, String(saved_stack.get("instance_id", "")), bool(saved_stack.get("disallowed", false)), String(saved_stack.get("material_id", "")), spoil)


# ── Zone colours ──────────────────────────────────────────────────────────────


## Confirmed zones read as a quiet burlap mat with a rope-coloured border under
## Hearthblock lighting; the previous blue overlay otherwise. Drawing feedback
## while designating keeps its own valid/invalid colours.
func _zone_colors() -> Array[Color]:
	if SkyController.hearthblock_active():
		var look := SkyController.hearthblock_settings()
		var fill: Array = look.get("stockpile_fill", [])
		var edge: Array = look.get("stockpile_edge", [])
		if fill.size() == 4 and edge.size() == 4:
			# Authored in sRGB; the overlay treats vertex colours as linear.
			return [Color(float(fill[0]), float(fill[1]), float(fill[2])).srgb_to_linear() * Color(1, 1, 1, float(fill[3])),
				Color(float(edge[0]), float(edge[1]), float(edge[2])).srgb_to_linear() * Color(1, 1, 1, float(edge[3]))]
	return [COLOR_ZONE, COLOR_ZONE_EDGE]


func _on_hearthblock_lighting_changed(_lit: bool) -> void:
	var colors := _zone_colors()
	for zone_id: int in _zones:
		_tool.show_zone(zone_id, (_zones[zone_id] as StockpileZoneComponent).tile_cells, colors[0], colors[1])


# ── Storage inspector ────────────────────────────────────────────────────────

func _build_window() -> void:
	# Simulation fixtures may omit the presentation layer.
	if _window_manager == null:
		return

	# The storage window (doc 261) brings its own margins; its band names the zone.
	_storage_panel = preload("res://scripts/ui/StorageInspectorPanel.gd").new()
	_storage_panel.action_requested.connect(func(action: String):
		if action == "remove": remove_zone(_window_zone_id))
	_window_panel = _window_manager.register_window(ZONE_WINDOW_ID, "Storage", "", _storage_panel,
		{"default_pos": Vector2(18, 48), "min_size": Vector2(420, 0), "family": "work", "flush": true})
	_storage_panel.window = _window_panel
	_storage_panel.dock = _dock_ui
	_window_info_label = _storage_panel.info_label
	_window_panel.keep_body_on_screen = true
	_window_manager.window_state_changed.connect(_on_zone_window_state_changed)


func _on_zone_window_state_changed(id: String, shown: bool) -> void:
	if id == ZONE_WINDOW_ID and not shown:
		_window_zone_id = -1
		_storage_panel.clear_subject()


func _open_zone_window(zone_id: int) -> void:
	var zone: StockpileZoneComponent = _zones.get(zone_id)
	if zone == null or _window_panel == null:
		return
	_window_zone_id = zone_id
	_storage_panel.show_storage(zone, [{"id": "remove", "text": "Remove zone", "variant": "danger"}], "Storage zone %d" % zone_id)
	_window_manager.open(ZONE_WINDOW_ID)


## A furniture container's storage window (doc 294): the zones' window, for its goods.
func open_container_window(container: StorageComponent, title: String) -> void:
	if _window_panel == null: return
	_window_zone_id = -1
	_storage_panel.show_storage(container, [], title)
	_window_manager.open(ZONE_WINDOW_ID)


func _close_zone_window() -> void:
	_window_zone_id = -1
	if _window_manager != null:
		_window_manager.close(ZONE_WINDOW_ID)
