extends Node3D

## Shared surface-order gestures: Chop trees, Clear stones and Cancel orders.
## Each owner retains its jobs/progress; this controller only designates work.
@export var dock_ui_path: NodePath
@export var flora_path: NodePath
@export var details_path: NodePath
@export var explorer_path: NodePath

const Picking = preload("res://scripts/components/ObjectPicking.gd")
const SelectionOverlay = preload("res://scripts/ui/TreeFellingOverlay.gd")
const DRAG_THRESHOLD_PX := 6.0
signal tool_active_changed(active: bool)
signal order_created(receipt: Dictionary)
signal order_feedback(message: String)
var _shared_order_ui := false
var _cancel_mode := false
var _stone_mode := false # Any surface-detail tool; trees retain their owner.
var _detail_tool := "clear_stones"
var _mining: Node
var _preview_mining: Array[Vector3i] = []
var _active := false
var _flora: SurfaceFloraSpawner
var _details: Node
var _explorer: ObjectExplorerController
var _hint_layer: CanvasLayer
var _hover: MeshInstance3D
var _hover_bounds := AABB()
var _hover_elapsed := 0.0
var _hint: Label
var _selection: Control
var _dragging := false
var _box_select := false
var _drag_start := Vector2.ZERO
var _drag_screen := Vector2.ZERO
var _anchor := Vector3i(-1, -1, -1)
var _selection_rect := Rect2i()
var _preview_trees: Array[Vector2i] = []
var _preview_stones: Array[String] = []
const HINT := "Chop trees · Click a tree or drag an area · Esc to finish"


func _ready() -> void:
	process_priority = 100 # Project UI after the camera has moved this frame.
	_flora = get_node_or_null(flora_path) as SurfaceFloraSpawner
	_details = get_node_or_null(details_path) if not details_path.is_empty() else get_tree().get_first_node_in_group("surface_details")
	_explorer = get_node_or_null(explorer_path) as ObjectExplorerController
	var dock := get_node_or_null(dock_ui_path)
	if dock != null:
		dock.call("register_chop_controller", self)
		dock.connect("tool_requested", _on_tool_requested)
	_hover = MeshInstance3D.new()
	_hover.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hover.visible = false
	add_child(_hover)
	_hint_layer = CanvasLayer.new()
	_hint_layer.layer = 24
	_hint_layer.visible = false
	add_child(_hint_layer)
	_selection = SelectionOverlay.new()
	_selection.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_layer.add_child(_selection)
	_hint = Label.new()
	UITheme.apply_surface(_hint)
	_hint.text = HINT
	_hint.position = Vector2(24, 100)
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
	_hint.add_theme_stylebox_override("normal", UITheme.hud_panel_style())
	_hint_layer.add_child(_hint)
	_hint.visible = not _shared_order_ui


func is_active() -> bool:
	return _active


func _on_tool_requested(tool_id: String) -> void:
	if tool_id in ["chop", "clear_stones", "harvest_plants", "clear_shrubs", "cancel_orders"] and bool(WorldGenerator.get_streaming_stats().get("maps_ready", false)):
		_cancel_drag()
		_cancel_mode = tool_id == "cancel_orders"
		_stone_mode = tool_id in ["clear_stones", "harvest_plants", "clear_shrubs"]
		_detail_tool = tool_id
		if _stone_mode and _details == null:
			deactivate()
			return
		_hint.text = _idle_hint()
		_hover_bounds = AABB()
		_hover.hide()
		_selection.fill_color = Color(.85, .35, .25, .16) if _cancel_mode else Color(1.0, .65, .2, .16)
		_selection.edge_color = UITheme.DANGER_RED if _cancel_mode else Color(1.0, .73, .3, .95)
		_active = true
		_hint_layer.visible = true
		tool_active_changed.emit(true)
	else:
		deactivate()


func deactivate() -> void:
	if not _active:
		return
	_active = false
	_cancel_drag()
	_hint_layer.visible = false
	_hover.visible = false
	tool_active_changed.emit(false)


func _unhandled_input(event: InputEvent) -> void:
	if not _active:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		deactivate()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_begin_drag(event.position)
		get_viewport().set_input_as_handled()


## Capture only an already-started world gesture. Releasing over UI cancels it,
## so a window cannot swallow mouse-up and leave a stuck selection behind.
func _input(event: InputEvent) -> void:
	if not _dragging:
		return
	if event is InputEventMouseMotion:
		_drag_screen = event.position
		if not _box_select and _drag_start.distance_to(_drag_screen) >= DRAG_THRESHOLD_PX:
			_box_select = true
			_explorer.clear_selection()
			_update_drag_preview()
		# Later motion is sampled by _process, not once per high-rate mouse event.
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		if get_viewport().gui_get_hovered_control() == null:
			_finish_drag(event.position)
		else:
			_cancel_drag()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		deactivate()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT and _dragging:
		_cancel_drag()


func _begin_drag(screen_pos: Vector2) -> void:
	_dragging = true
	_box_select = false
	_drag_start = screen_pos
	_drag_screen = screen_pos
	if _cancel_mode: return
	_anchor = Vector3i(-1, -1, -1)
	var camera := get_viewport().get_camera_3d()
	var owner := _designation_owner()
	if camera != null and owner != null:
		var hit := Picking.terrain_hit(camera.project_ray_origin(screen_pos),
			camera.project_ray_normal(screen_pos), int(owner.call("get_slice_y")))
		if not hit.is_empty():
			_anchor = Vector3i(hit.x, hit.y, hit.z)


func _cancel_drag() -> void:
	_dragging = false
	_box_select = false
	_preview_trees.clear()
	_preview_stones.clear()
	_preview_mining.clear()
	_selection.set_polygon(PackedVector2Array())
	_hint.text = _idle_hint()


func _finish_drag(screen_pos: Vector2) -> void:
	_drag_screen = screen_pos
	_box_select = _box_select or _drag_start.distance_to(screen_pos) >= DRAG_THRESHOLD_PX
	if _cancel_mode:
		_update_cancel_preview()
		var tree_count := _preview_trees.size()
		var boulder_count := _preview_stones.size()
		var block_count := 0
		if _mining != null: block_count = _mining.cancel_order_blocks(_preview_mining)
		for id: Vector2i in _preview_trees: _flora.cancel_felling(id)
		for id: String in _preview_stones: _details.cancel_clearing(id)
		_cancel_drag()
		order_feedback.emit("Cancelled · %d blocks, %d trees, %d stones/plants" % [block_count, tree_count, boulder_count]
			if block_count + tree_count + boulder_count > 0 else "No marked work in this area")
		return
	if _box_select:
		_update_drag_preview()
		var added: Array[Dictionary] = []
		var owner := _designation_owner()
		var candidates: Array = _preview_stones if _stone_mode else _preview_trees
		for id in candidates:
			var previous := _order_token(owner, id)
			if _designate(owner, id) and previous == null:
				added.append({"id": id, "source": _order_token(owner, id)})
		if _stone_mode and _detail_tool == "harvest_plants":
			for id: Vector2i in _preview_trees:
				var previous := _order_token(_flora, id)
				if _designate(_flora, id) and previous == null:
					added.append({"id": id, "source": _order_token(_flora, id)})
		_emit_order(added)
	else:
		designate_at_screen(screen_pos)
	_cancel_drag()


func _update_drag_preview(refresh_candidates: bool = true) -> void:
	if _cancel_mode:
		_update_cancel_preview(refresh_candidates)
		return
	_selection.set_polygon(PackedVector2Array())
	if not _box_select or _anchor.y < 0:
		_preview_trees.clear()
		_preview_stones.clear()
		return
	_hover.visible = false
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		_preview_trees.clear()
		_preview_stones.clear()
		return
	# A fixed ground plane prevents tall canopies or cliffs from jumping the end
	# point. The rectangle includes visible objects at any terrain height inside it.
	var plane := Plane(Vector3.UP, float(_anchor.y) + 1.02)
	var hit: Variant = plane.intersects_ray(camera.project_ray_origin(_drag_screen), camera.project_ray_normal(_drag_screen))
	if hit == null:
		_preview_trees.clear()
		_preview_stones.clear()
		return
	var current := Vector2i(clampi(floori(hit.x), 0, WorldData.WORLD_SIZE_X - 1),
		clampi(floori(hit.z), 0, WorldData.WORLD_SIZE_Z - 1))
	var start := Vector2i(_anchor.x, _anchor.z)
	_selection_rect = Rect2i(start.min(current), (start - current).abs() + Vector2i.ONE)
	var corners := PackedVector2Array()
	var lo := _selection_rect.position
	var hi := _selection_rect.end
	for corner in [Vector2i(lo.x, lo.y), Vector2i(hi.x, lo.y), Vector2i(hi.x, hi.y), Vector2i(lo.x, hi.y)]:
		var point := Vector3(corner.x, plane.d, corner.y)
		if camera.is_position_behind(point):
			_preview_trees.clear() # Never commit a rectangle that could not be shown.
			_preview_stones.clear()
			return
		corners.append(camera.unproject_position(point))
	# Reprojection is cheap and runs every frame. Scan objects only on the
	# count timer or at input/commit boundaries, even during rapid camera pans.
	if refresh_candidates:
		if _stone_mode: _preview_stones = _details.details_in_rect(_selection_rect, _detail_tool)
		else: _preview_trees = _flora.trees_in_felling_rect(_selection_rect)
		if _stone_mode and _detail_tool == "harvest_plants": _preview_trees = _flora.trees_in_harvest_rect(_selection_rect)
	_selection.set_polygon(corners)
	_hint.text = "%s · %d %s in area · Release to mark · Esc to cancel" % [
		_detail_title() if _stone_mode else "Chop trees", _preview_count(), ((_detail_noun()) if _stone_mode else "tree") + ("" if _preview_count() == 1 else "s")]


func designate_at_screen(screen_pos: Vector2) -> bool:
	var owner := _designation_owner()
	if owner == null or _explorer == null:
		return false
	var hit := _explorer.pick_at_screen(screen_pos)
	if not _accepts_hit(hit):
		return false
	owner = hit.provider
	var previous := _order_token(owner, hit["id"])
	if not _designate(owner, hit["id"]):
		return false
	if previous == null: _emit_order([{"id": hit["id"], "source": _order_token(owner, hit["id"])}])
	_explorer.select_object(owner, hit["id"])
	return true


func _process(delta: float) -> void:
	if not _active or _explorer == null:
		return
	_hover_elapsed += delta
	if _dragging and _box_select:
		var refresh_candidates := _hover_elapsed >= .08
		_update_drag_preview(refresh_candidates)
		if refresh_candidates:
			_hover_elapsed = 0.0
		return
	if _hover_elapsed < .08:
		return
	_hover_elapsed = 0.0
	var mouse := get_viewport().get_mouse_position()
	if not get_viewport().get_visible_rect().has_point(mouse) or get_viewport().gui_get_hovered_control() != null:
		_hover.visible = false
		return
	if _cancel_mode:
		_drag_screen = mouse
		_update_cancel_preview()
		_hover.visible = false
		var bounds := AABB()
		if not _preview_trees.is_empty(): bounds = _flora.get_explorer_bounds(_preview_trees[0])
		elif not _preview_stones.is_empty(): bounds = _details.get_explorer_bounds(_preview_stones[0])
		elif not _preview_mining.is_empty(): bounds = AABB(Vector3(_preview_mining[0]), Vector3.ONE)
		if bounds.size != Vector3.ZERO:
			_hover.visible = true
			_hover.mesh = Picking.outline_mesh(bounds.grow(.12), UITheme.DANGER_RED)
		return
	var hit := _explorer.pick_at_screen(mouse)
	if not _accepts_hit(hit):
		_hover.visible = false
		return
	var owner: Node = hit.provider
	var bounds: AABB = owner.get_explorer_bounds(hit["id"])
	_hover.visible = bounds.size != Vector3.ZERO
	if _hover.visible and bounds != _hover_bounds:
		_hover_bounds = bounds
		_hover.mesh = Picking.outline_mesh(bounds.grow(.12), Color(1.0, .85, .40))


func set_mining_controller(controller: Node) -> void:
	_mining = controller


func set_shared_order_ui(enabled: bool) -> void:
	_shared_order_ui = enabled
	if _hint != null: _hint.visible = not enabled


func get_order_tool_id() -> String:
	return "cancel_orders" if _cancel_mode else _detail_tool if _stone_mode else "chop"


func get_order_hint() -> String:
	if _cancel_mode:
		if _dragging: return "%d blocks · %d trees · %d stones/plants · Release to cancel.\nOnly marked work is removed." % [_preview_mining.size(), _preview_trees.size(), _preview_stones.size()]
		return "Click marked work, or drag across blocks, trees, stones and plants.\nStockpiles and placed furniture are kept."
	if _stone_mode and _detail_tool != "clear_stones":
		if _dragging and _box_select: return "%d plant%s in area · Release to mark.\nEsc cancels the selection." % [_preview_count(), "" if _preview_count() == 1 else "s"]
		return "Click ripe shrubs or junipers, or drag an area.\nWorkers pick berries and keep the plants." if _detail_tool == "harvest_plants" else "Click shrubs, flowers or reeds, or drag an area.\nShrubs yield a cutting; flowers and reeds yield no items."
	if _stone_mode:
		if _dragging and _box_select: return "%d stone%s in area · Release to mark.\nEsc cancels the selection." % [_preview_stones.size(), "" if _preview_stones.size() == 1 else "s"]
		return "Click a boulder or loose-stone clump, or drag an area.\nWorkers break boulders and gather loose stones."
	if _dragging and _box_select: return "%d trees in area · Release to mark.\nEsc cancels the selection." % _preview_trees.size()
	return "Click a tree, or drag around several.\nMarked trees stay queued after you finish."


func _update_cancel_preview(refresh_candidates: bool = true) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null or _flora == null: return
	if _dragging and _box_select:
		var rect := Rect2(_drag_start, _drag_screen - _drag_start).abs()
		_selection.set_polygon(PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]))
		if not refresh_candidates: return
		_preview_trees = _flora.marked_trees_in_screen_rect(rect, camera)
		if _details != null: _preview_stones = _details.marked_stones_in_screen_rect(rect, camera)
		if _mining != null: _preview_mining = _mining.marked_blocks_in_screen_rect(rect, camera)
	else:
		_preview_trees.clear()
		_preview_stones.clear()
		_preview_mining.clear()
		var hit := _explorer.pick_at_screen(_drag_screen)
		if not hit.is_empty() and hit.provider == _flora:
			if _flora.get_felling_order_token(hit.id) != null: _preview_trees.append(hit.id)
		elif not hit.is_empty() and hit.provider == _details:
			if _details.get_clearing_order_token(hit.id) != null: _preview_stones.append(hit.id)
		elif _mining != null:
			_preview_mining = _mining.marked_block_at_screen(_drag_screen)


func _designation_owner() -> Node:
	return _details if _stone_mode else _flora


func _accepts_hit(hit: Dictionary) -> bool:
	if hit.is_empty(): return false
	if _stone_mode and _detail_tool == "harvest_plants" and hit.provider == _flora:
		return _flora.can_harvest_tree(hit.id)
	return hit.provider == _designation_owner() and (not _stone_mode or _details.accepts_tool(String(hit.id), _detail_tool))


func _order_token(owner: Node, id: Variant) -> RefCounted:
	return owner.call("get_clearing_order_token" if owner == _details else "get_felling_order_token", id)


func _designate(owner: Node, id: Variant) -> bool:
	if owner == _details: return bool(owner.call("designate_detail", String(id), _detail_tool))
	if _stone_mode and _detail_tool == "harvest_plants": return _flora.designate_harvest(id)
	return bool(owner.call("designate_felling", id))


func _cancel_designation(owner: Node, id: Variant) -> void:
	owner.call("cancel_clearing" if owner == _details else "cancel_felling", id)


func _preview_count() -> int:
	return _preview_stones.size() + _preview_trees.size() if _stone_mode and _detail_tool == "harvest_plants" else _preview_stones.size() if _stone_mode else _preview_trees.size()


func _idle_hint() -> String:
	return "%s · Click or drag an area · Esc to finish" % _detail_title() if _stone_mode else HINT


func _emit_order(objects: Array[Dictionary]) -> void:
	if objects.is_empty(): return
	var receipt := {"message": "%s · %d %s%s marked" % [_detail_title(), objects.size(), _detail_noun(), "" if objects.size() == 1 else "s"] if _stone_mode else "%d trees marked for chopping" % objects.size()}
	for entry: Dictionary in objects:
		var key := "trees" if entry.id is Vector2i else "stones"
		if not receipt.has(key): receipt[key] = []
		receipt[key].append(entry)
	order_created.emit(receipt)


func _receipt_entries(receipt: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for key: String in ["trees", "stones"]:
		var owner: Node = _flora if key == "trees" else _details
		if owner == null: continue
		for entry: Dictionary in receipt.get(key, []):
			result.append({"owner": owner, "id": entry.id, "source": entry.source})
	return result


func order_is_pending(receipt: Dictionary) -> bool:
	for entry: Dictionary in _receipt_entries(receipt):
		if _order_token(entry.owner, entry.id) == entry.source: return true
	return false


func undo_order(receipt: Dictionary) -> int:
	var count := 0
	for entry: Dictionary in _receipt_entries(receipt):
		if _order_token(entry.owner, entry.id) == entry.source:
			_cancel_designation(entry.owner, entry.id)
			count += 1
	return count


func inspect_order(receipt: Dictionary) -> void:
	for entry: Dictionary in _receipt_entries(receipt):
		if _order_token(entry.owner, entry.id) == entry.source:
			_explorer.select_object(entry.owner, entry.id)
			return


func _detail_title() -> String:
	return "Harvest plants" if _detail_tool == "harvest_plants" else "Clear plants" if _detail_tool == "clear_shrubs" else "Clear stones"


func _detail_noun() -> String:
	return "stone" if _detail_tool == "clear_stones" else "plant"
