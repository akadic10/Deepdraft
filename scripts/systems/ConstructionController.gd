extends Node3D

## Owns structural orders, completed terrain provenance and construction data.
const Work = preload("res://scripts/components/ConstructionWork.gd")
const Picking = preload("res://scripts/components/ObjectPicking.gd")
const FloorArt = preload("res://scripts/components/ConstructionFloorArt.gd")
const INVALID := Vector3i(-1,-1,-1)
const DIRECTIONS := [Vector3i.LEFT,Vector3i.RIGHT,Vector3i.UP,Vector3i.DOWN,Vector3i.FORWARD,Vector3i.BACK]
@export var mining_path: NodePath
@export var furniture_path: NodePath
@export var renderer_path: NodePath
@export var dock_path: NodePath
signal tool_active_changed(active: bool)
var definition: Dictionary = {}
var built: Dictionary = {} # cell -> permanent natural-rock or constructed-floor key
var orders: Dictionary = {}
var next_id := 1
var mining: Node
var furniture: Node
var renderer: Node
var dock: Node
var drops: Node
var _sources: Dictionary = {}
var _dirty := true
var _active := false
var _dragging := false
var _anchor := INVALID
var _hover := INVALID
var _hover_plane_y := 0.0
var _drag_plane_y := 0.0
var _height := 1
var _preview: MeshInstance3D
var _plans: MeshInstance3D
var _solid: MeshInstance3D
var _hint_layer: CanvasLayer
var _hint: Label
var _preview_cells: Array[Vector3i] = []
var _feedback := ""
var _preview_elapsed := 0.0
var _kind := "stone"
var _floor_art = FloorArt.new()
var _dev_feedback: Dictionary = {}

func _ready() -> void:
	add_to_group("construction")
	add_to_group("object_explorer_provider")
	add_to_group(SaveManager.OWNER_GROUP)
	definition = BlockRegistry.get_construction_def("stone")
	if not mining_path.is_empty(): mining = get_node(mining_path)
	if not furniture_path.is_empty(): furniture = get_node(furniture_path)
	if not renderer_path.is_empty(): renderer = get_node(renderer_path)
	if not dock_path.is_empty(): dock = get_node(dock_path)
	drops = get_tree().get_first_node_in_group("item_drop_manager")
	if dock != null:
		dock.tool_requested.connect(_on_tool_requested)
		dock.register_construction_controller(self)
	if renderer != null:
		renderer.visible_volume_changed.connect(func(): _dirty = true; _dragging = false)
		renderer.built_blocks = built
	_solid = MeshInstance3D.new()
	_solid.name = "ConstructedBlocks"
	preload("res://scripts/components/TerrainLighting.gd").configure_mesh(_solid)
	add_child(_solid)
	_plans = _make_overlay("ConstructionPlans",Color(.25,.8,1,.26))
	_preview = _make_overlay("ConstructionPreview",Color(.35,1,.55,.4))
	_hint_layer = CanvasLayer.new()
	_hint_layer.layer = 20
	add_child(_hint_layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(24,74)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel",UITheme.hud_panel_style())
	_hint_layer.add_child(panel)
	_hint = Label.new()
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.add_theme_font_size_override("font_size",14)
	panel.add_child(_hint)
	_hint_layer.hide()
	TaskManager.task_completed.connect(func(task: Task): _task_gone(task,-1))
	TaskManager.task_cancelled.connect(func(task: Task): _task_gone(task,task.assigned_to))
	TaskManager.task_failed.connect(func(task: Task,_why: String): _task_gone(task,task.assigned_to))
	TaskManager.task_released.connect(_task_released)
	WorldData.chunk_dirtied.connect(_terrain_changed,CONNECT_DEFERRED)

func _exit_tree() -> void:
	for id: int in orders.keys(): cancel_order(id)

func _make_overlay(label: String, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = label
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	return node

func _terrain_changed(x: int,y: int,z: int) -> void:
	# Only adjoining solid edits change built faces. Water changes neither those
	# faces nor plan geometry; work/preview validation reads current water directly.
	if _dirty: return
	for cell: Vector3i in built:
		if absi((cell.x>>4)-x)<=1 and absi((cell.y>>4)-y)<=1 and absi((cell.z>>4)-z)<=1:
			_dirty = true
			return

func _process(delta: float) -> void:
	if _dirty:
		_dirty = false
		for cell: Vector3i in built.keys():
			if WorldData.get_terrain_block(cell.x,cell.y,cell.z) != BlockRegistry.get_id(built[cell]): built.erase(cell)
		_rebuild_visuals()
	if not SaveManager.is_loading():
		for order in orders.values(): order.update_lease()
	if _active:
		_preview_elapsed += delta
		if _preview_elapsed >= .1: _update_preview()
		if _is_floor(_kind):
			_hint.text = "%s · %s required (planned)\nMine one layer, then click or drag its cleared floor\nClick a blue plan for DEV Build · Esc: done\n%s" % [_tool_definition().display_name,_tool_definition().profession,_feedback]
		else:
			_hint.text = "Stone block · 1 rough stone each · Height %d\nClick or drag to build · Alt + wheel: height\nCtrl + click: cancel area · Esc: done\n%s" % [_height,_feedback]

func is_active() -> bool: return _active

func _tool_definition() -> Dictionary:
	return BlockRegistry.get_construction_def(_kind)

func _is_floor(kind: String) -> bool:
	return BlockRegistry.get_construction_def(kind).get("category","") == "floor"

func _on_tool_requested(tool: String) -> void:
	var kind := tool.trim_prefix("construct_")
	var supported := tool.begins_with("construct_") and not BlockRegistry.get_construction_def(kind).is_empty()
	_active = supported and not (_active and _kind == kind)
	if supported: _kind = kind
	_height = clampi(_height,1,int(_tool_definition().max_height))
	_feedback = ""
	_dragging = false
	_preview.mesh = null
	_hint_layer.visible = _active
	tool_active_changed.emit(_active)

func _unhandled_input(event: InputEvent) -> void:
	if not _active: return
	if event is InputEventMouseMotion:
		_update_preview(event.position)
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_on_tool_requested("")
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		if event.alt_pressed and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			_height = clampi(_height+(1 if event.button_index==MOUSE_BUTTON_WHEEL_UP else -1),1,int(_tool_definition().max_height))
			_update_preview(event.position)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed and event.ctrl_pressed:
				_cancel_at(event.position)
			elif event.pressed:
				if _inspect_at(event.position):
					_dragging = false
					get_viewport().set_input_as_handled()
					return
				_update_preview(event.position)
				_anchor = _hover
				_drag_plane_y = _hover_plane_y
				_dragging = _anchor != INVALID
			else:
				if _dragging:
					_update_preview(event.position)
					var id := create_order(_preview_cells,-1,false,_kind)
					_feedback = ("Planned %d floor tiles · click a blue plan for DEV Build" % orders[id].cells.size() if _is_floor(_kind) else "Queued %d blocks · %d rough stone" % [orders[id].cells.size(),orders[id].cells.size()]) if id >= 0 else "No clear cells to build"
				_dragging = false
			get_viewport().set_input_as_handled()

func _slice_y() -> int: return int(renderer.slice_y) if renderer != null else WorldData.WORLD_SIZE_Y-1

func target_from_hit(hit: Dictionary) -> Vector3i:
	if hit.is_empty(): return INVALID
	if _is_floor(_kind) and Vector3i(hit.normal) != Vector3i.UP: return INVALID
	return Vector3i(hit.x,hit.y,hit.z)+Vector3i(hit.normal)

func _update_preview(mouse := Vector2(-1,-1)) -> void:
	_preview_elapsed = 0.0
	if furniture == null or mining == null: return
	if mouse.x < 0: mouse = get_viewport().get_mouse_position()
	var camera := get_viewport().get_camera_3d()
	if camera == null: return
	var hit: Dictionary = furniture._surface_cell_for(mouse)
	_hover = target_from_hit(hit)
	if not hit.is_empty():
		_hover_plane_y = camera.project_ray_origin(mouse).y+camera.project_ray_normal(mouse).y*float(hit.distance)
	if _dragging:
		var point = Plane(Vector3.UP,_drag_plane_y).intersects_ray(camera.project_ray_origin(mouse),camera.project_ray_normal(mouse))
		if point != null: _hover = Vector3i(floori(point.x),_anchor.y,floori(point.z))
	_preview_cells.clear()
	if _hover == INVALID:
		_preview.mesh = null
		return
	var start := _anchor if _dragging else _hover
	var limit := int(_tool_definition().max_drag_size)-1
	var finish := Vector3i(clampi(_hover.x,start.x-limit,start.x+limit),start.y,clampi(_hover.z,start.z-limit,start.z+limit))
	var reason := ""
	for y in range(start.y,mini(start.y+_height,_slice_y()+1)):
		for x in range(mini(start.x,finish.x),maxi(start.x,finish.x)+1):
			for z in range(mini(start.z,finish.z),maxi(start.z,finish.z)+1):
				var cell := Vector3i(x,y,z)
				var invalid := build_reason(cell,true,false,_kind)
				if invalid.is_empty(): _preview_cells.append(cell)
				else: reason = invalid
	_preview.mesh = mining._build_fill_mesh(_preview_cells,Color.WHITE,.005) if not _preview_cells.is_empty() else null
	_feedback = ("%d floor tiles · worker construction unavailable" % _preview_cells.size() if _is_floor(_kind) else "%d blocks · %d rough stone" % [_preview_cells.size(),_preview_cells.size()]) if not _preview_cells.is_empty() else (reason if not reason.is_empty() else "Raise the slice to build above this face")

func _cancel_at(screen: Vector2) -> void:
	var hit := _plan_at_screen(screen)
	if not hit.is_empty():
		cancel_order(int(hit.id))
		_feedback = "Construction area cancelled; completed blocks remain"

func _inspect_at(screen: Vector2) -> bool:
	var explorer := get_tree().get_first_node_in_group("object_explorer")
	if explorer == null: return false
	var hit: Dictionary = explorer.pick_at_screen(screen)
	return not hit.is_empty() and hit.provider == self and explorer.select_object(self,hit.id)

func _plan_at_screen(screen: Vector2) -> Dictionary:
	# Use shared arbitration when available so terrain and foreground objects
	# protect plans from selection or cancellation through them.
	var explorer := get_tree().get_first_node_in_group("object_explorer")
	if explorer != null:
		var hit: Dictionary = explorer.pick_at_screen(screen)
		return hit if hit.get("provider") == self else {}
	var camera := get_viewport().get_camera_3d()
	if camera == null: return {}
	var origin := camera.project_ray_origin(screen)
	var direction := camera.project_ray_normal(screen)
	var terrain := Picking.terrain_hit(origin,direction,_slice_y())
	return pick_explorer_object(origin,origin+direction*minf(600.0,float(terrain.get("distance",600.0))+.002))

func pick_explorer_object(start: Vector3,end: Vector3) -> Dictionary:
	var result := {}
	var distance := start.distance_to(end)
	for id: int in orders:
		for cell: Vector3i in orders[id].cells:
			if cell.y > _slice_y(): continue
			var point = AABB(Vector3(cell),Vector3.ONE).intersects_segment(start,end)
			if point != null and start.distance_to(point)<distance:
				distance = start.distance_to(point)
				result = {"id":id,"distance":distance}
	return result

func get_explorer_bounds(object_id: Variant) -> AABB:
	var order = orders.get(object_id)
	var bounds := AABB()
	if order == null: return bounds
	for cell: Vector3i in order.cells:
		if cell.y > _slice_y(): continue
		var box := AABB(Vector3(cell),Vector3.ONE)
		bounds = box if bounds.size == Vector3.ZERO else bounds.merge(box)
	return bounds

func get_explorer_data(object_id: Variant) -> Dictionary:
	var order = orders.get(object_id)
	if order == null or get_explorer_bounds(object_id).size == Vector3.ZERO: return {}
	if _is_floor(order.construction_kind):
		return {"title":order.def.display_name,"kind":"Floor construction plan",
			"rows":[["Status","Requires %s" % order.def.profession],["Tiles left",str(order.cells.size())],
				["Worker construction","Not yet available"],["Room appeal","+%.0f when fully floored" % float(RoomManager.appeal_config.complete_floor_bonus)]],
			"details":"Mine one layer deeper, then fill the cleared space. DEV Build instantly builds clear, supported tiles without materials. These preview floors yield no items when mined.\n"+String(_dev_feedback.get(object_id,"")),
			"actions":[{"id":"dev_build","text":"DEV Build","variant":"dev"},{"id":"cancel","text":"Cancel construction","variant":"danger"}]}
	var task := TaskManager.get_task(order._lease_id)
	var worker: DwarfAgent = TaskManager._agents.get(task.assigned_to) if task != null else null
	var status := "Waiting for worker"
	var details := "Each block uses one rough stone. Cancelling removes unfinished plans; completed stone stays."
	if is_instance_valid(worker):
		match worker._task_phase:
			DwarfAgent.TaskPhase.FETCH_TO_GHOST: status = "Carrying stone"
			DwarfAgent.TaskPhase.FETCH_WORKING, DwarfAgent.TaskPhase.FETCH_DEPOSIT: status = "Building"
			_: status = "Collecting stone"
	elif task != null:
		status = "Needs attention" if task.recovery_paused else "Waiting"
		details = task.wait_reason+"\n\n"+details
	var progress := "—"
	if order.cells.has(order.target):
		progress = "%d%%" % roundi(clampf(float(order.work_progress.get(order.target,0.0))/float(definition.work_seconds),0.0,1.0)*100.0)
	return {"title":"Stone block area","kind":"Construction plan",
		"rows":[["Status",status],["Blocks left",str(order.cells.size())],
			["Stone needed","%d rough stone" % order.cells.size()],
			["Worker",worker.dwarf_name if is_instance_valid(worker) else "None assigned"],
			["Current block",progress]],
		"details":details,"actions":[{"id":"cancel","text":"Cancel construction","variant":"danger"}]}

func perform_explorer_action(object_id: Variant,action_id: String) -> void:
	if action_id == "cancel": cancel_order(int(object_id))
	elif action_id == "dev_build": dev_build_order(int(object_id))

## A work-stand pass is synchronous: capture moving actors and loose items
## once for that call, never across frames or while a route search yields.
func obstacle_snapshot() -> Dictionary:
	var actors: Array[AABB] = []
	for actor in TaskManager._agents.values():
		if is_instance_valid(actor): actors.append(AABB(actor.global_position-Vector3(.5,0,.5),Vector3(1,3,1)))
	var loose := {}
	if drops != null:
		for item in drops._loose:
			if is_instance_valid(item): loose[drops.item_floor_cell(item)+Vector3i.UP] = true
	return {"actors":actors,"loose":loose}

func build_reason(cell: Vector3i, planning := true, require_support := true, kind := "stone", obstacles: Dictionary = {}) -> String:
	if cell.x < 0 or cell.z < 0 or cell.y <= 3 or cell.x >= WorldData.WORLD_SIZE_X or cell.z >= WorldData.WORLD_SIZE_Z or cell.y >= WorldData.WORLD_SIZE_Y: return "Outside the buildable world"
	if WorldData.get_live_block(cell.x,cell.y,cell.z) != BlockRegistry.AIR_ID: return "Mine existing terrain before building"
	var cave_id := WorldGenerator.get_cave_id(cell)
	if cave_id >= 0 and not InteriorTracker.is_cave_discovered(cave_id): return "Explore this space before building"
	if WaterManager.has_standing_water(cell): return "Clear water before building"
	if _is_floor(kind) and not BlockRegistry.is_solid(WorldData.get_terrain_block(cell.x,cell.y-1,cell.z)):
		return "Floor tiles need solid support below"
	if PlacedEntityRegistry.occupies(cell): return "A placed object occupies this cell"
	var area := AABB(Vector3(cell)+Vector3.ONE*.001,Vector3.ONE*.998)
	if obstacles.has("actors"):
		for bounds: AABB in obstacles.actors:
			if area.intersects(bounds): return "A dwarf occupies this cell"
	else:
		for actor in TaskManager._agents.values():
			if is_instance_valid(actor) and area.intersects(AABB(actor.global_position-Vector3(.5,0,.5),Vector3(1,3,1))): return "A dwarf occupies this cell"
	if obstacles.has("loose"):
		if obstacles.loose.has(cell): return "Haul loose items clear first"
	elif drops != null:
		for item in drops._loose:
			if is_instance_valid(item) and drops.item_floor_cell(item)+Vector3i.UP == cell: return "Haul loose items clear first"
	if furniture != null:
		for group: Dictionary in [furniture._ghosts,furniture._installed]:
			for piece in group.values():
				if furniture._visual_bounds(piece.def,piece.origin_cell,piece.yaw_steps).intersects(area): return "Furniture or a placement plan occupies this cell"
		if furniture._ladders.reserves(area) or furniture._bridges.reserves(area): return "Keep access structures clear"
	for zone: StockpileZoneComponent in StockpileManager._zones.values():
		if zone.tile_cells.has(cell-Vector3i.UP): return "Remove the storage designation first"
	if planning:
		for order in orders.values():
			if order.cells.has(cell): return "Construction already planned here"
	if require_support:
		var supported := false
		for direction: Vector3i in DIRECTIONS:
			var neighbour := cell+direction
			if BlockRegistry.is_solid(WorldData.get_terrain_block(neighbour.x,neighbour.y,neighbour.z)):
				supported = true
				break
		if not supported: return "Waiting for an adjoining solid block"
	return ""

func stands_for(cell: Vector3i) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	if cell == INVALID: return result
	for side: Vector3i in [Vector3i.LEFT,Vector3i.RIGHT,Vector3i.FORWARD,Vector3i.BACK]:
		for y in range(maxi(3,cell.y-int(definition.reach_up)),mini(WorldData.WORLD_SIZE_Y,cell.y+int(definition.reach_down)+1)):
			var stand := Vector3i(cell.x+side.x,y,cell.z+side.z)
			if NavGrid.is_walkable(stand): result.append(stand)
	return result

func create_order(requested: Array[Vector3i], saved_id := -1, restoring := false, kind := "stone") -> int:
	var def := BlockRegistry.get_construction_def(kind)
	if def.is_empty(): return -1
	var cells: Array[Vector3i] = []
	for cell: Vector3i in requested:
		if cells.has(cell): continue
		if restoring or (cell.y<=_slice_y() and build_reason(cell,true,false,kind).is_empty()): cells.append(cell)
	if cells.is_empty(): return -1
	cells.sort_custom(func(a: Vector3i,b: Vector3i): return a.y<b.y if a.y!=b.y else (a.x<b.x if a.x!=b.x else a.z<b.z))
	var id := saved_id if saved_id > 0 else next_id
	next_id = maxi(next_id,id+1)
	var order = Work.new()
	order.controller = self
	order.construction_kind = kind
	order.setup(id,kind,def,cells[0]-Vector3i.UP,0)
	order.cells = cells
	order.drop_manager = drops
	orders[id] = order
	if bool(def.get("worker_enabled",true)):
		order.source_id = TaskManager.allocate_source_id()
		_sources[order.source_id] = id
		TaskManager.register_work_source(order.source_id,order)
	if not SaveManager.is_loading(): order.update_lease()
	_dirty = true
	return id

func commit_block(order: RefCounted) -> void:
	if not bool(order.def.get("worker_enabled",true)): return
	var cell: Vector3i = order.target
	var key := BlockRegistry.get_key(WorldGenerator.construction_stone_id(cell))
	_place_block(cell,String(key))

func _place_block(cell: Vector3i, key: String) -> void:
	mining._ensure_chunk_real(cell)
	built[cell] = key
	WorldData.set_block(cell.x,cell.y,cell.z,BlockRegistry.get_id(key))
	NavGrid.refresh_mined_block(cell)
	if renderer != null: renderer._cavity_shell_dirty = true
	_dirty = true

func dev_build_order(id: int) -> int:
	var order = orders.get(id)
	if order == null or not _is_floor(order.construction_kind): return 0
	var count := 0
	var reason := ""
	for cell: Vector3i in order.cells.duplicate():
		var invalid := build_reason(cell,false,true,order.construction_kind)
		if cell.y > _slice_y(): invalid = "Raise the slice to show the remaining tiles"
		if not invalid.is_empty():
			reason = invalid
			continue
		_place_block(cell,String(order.def.block_key))
		order.cells.erase(cell)
		count += 1
	_dev_feedback[id] = "Built %d tiles. %s" % [count,reason]
	if order.cells.is_empty(): cancel_order(id)
	_dirty = true
	return count

func cancel_order(id: int) -> void:
	var order = orders.get(id)
	if order == null: return
	orders.erase(id)
	_dev_feedback.erase(id)
	if order.source_id >= 0:
		TaskManager.cancel_source_tasks(order.source_id)
		_sources.erase(order.source_id)
		TaskManager.unregister_work_source(order.source_id)
	order.release_claim()
	_dirty = true

func _task_gone(task: Task, dwarf: int) -> void:
	var order = orders.get(_sources.get(task.source_id,-1))
	if order == null: return
	order.on_task_gone(task.id,dwarf)
	if order.cells.is_empty(): cancel_order(order.ghost_id)
	_dirty = true

func _task_released(task: Task,dwarf: int,_why: int) -> void:
	var order = orders.get(_sources.get(task.source_id,-1))
	if order != null: order.cancel_fetch(dwarf)

func mined_refund(cell: Vector3i) -> bool:
	if not built.has(cell): return false
	var floor_block: bool = BlockRegistry.get_def(built[cell]).get("kind","") == "constructed_floor"
	built.erase(cell)
	# DEV floors have consumed no materials and must not create free inventory.
	if drops != null and not floor_block: drops.spawn_drop(String(definition.item_key),1,cell)
	_dirty = true
	return true

func _rebuild_visuals() -> void:
	if renderer != null:
		renderer._cavity_shell_dirty = true
		_solid.material_override = renderer._material
		var verts := PackedVector3Array()
		var norms := PackedVector3Array()
		var colors := PackedColorArray()
		var indices := PackedInt32Array()
		var visible_y := _slice_y()
		for cell: Vector3i in built:
			if cell.y > visible_y: continue
			var stone_color := BlockRegistry.get_terrain_color(BlockRegistry.get_id(built[cell]),WorldClock.season)
			var block_def := BlockRegistry.get_def(built[cell])
			var floor_def := BlockRegistry.get_construction_def(String(block_def.get("construction","")))
			for direction: Vector3i in DIRECTIONS:
				var neighbour := cell+direction
				var neighbour_solid := BlockRegistry.is_solid(WorldData.get_terrain_block(neighbour.x,neighbour.y,neighbour.z))
				if neighbour.y <= visible_y and neighbour_solid: continue
				if not floor_def.is_empty():
					var patterns: Array = floor_def.get("pattern_models",[floor_def.model])
					_floor_art.append_face(String(patterns[posmod(cell.z,patterns.size())]),cell,direction,
						direction == Vector3i.UP and cell.y == visible_y and neighbour_solid,verts,norms,colors,indices)
					continue
				var face_color := stone_color
				# A hidden solid above makes this an artificial slice cap, just
				# like adjoining natural rock. Real exposed tops stay undimmed.
				if direction == Vector3i.UP and cell.y == visible_y and neighbour_solid:
					face_color = renderer.slice_cut_color(stone_color)
				renderer._add_shell_face(cell,-direction,face_color,verts,norms,colors,indices)
		_solid.mesh = null
		if not verts.is_empty():
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = verts
			arrays[Mesh.ARRAY_NORMAL] = norms
			arrays[Mesh.ARRAY_COLOR] = colors
			arrays[Mesh.ARRAY_INDEX] = indices
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
			_solid.mesh = mesh
	if mining != null:
		var pending: Array[Vector3i] = []
		for order in orders.values():
			for cell: Vector3i in order.cells:
				if cell.y <= _slice_y(): pending.append(cell)
		_plans.mesh = mining._build_fill_mesh(pending,Color.WHITE,.004) if not pending.is_empty() else null

func save_section_key() -> String: return "construction"
func save_restore_priority() -> int: return 15

func serialize_state() -> Dictionary:
	var saved_blocks := []
	for cell: Vector3i in built: saved_blocks.append({"cell":SaveManager.pack_v3i(cell),"block":built[cell]})
	var saved_orders := []
	for order in orders.values():
		var pending := []
		for cell: Vector3i in order.cells: pending.append({"cell":SaveManager.pack_v3i(cell),"work":float(order.work_progress.get(cell,0.0))})
		saved_orders.append({"id":order.ghost_id,"kind":order.construction_kind,"cells":pending})
	return {"built":saved_blocks,"orders":saved_orders,"next_id":next_id}

func restore_state(state: Dictionary) -> void:
	for id: int in orders.keys(): cancel_order(id)
	built.clear()
	next_id = int(state.next_id)
	for entry: Dictionary in state.built:
		var cell := SaveManager.unpack_v3i(entry.cell)
		mining._ensure_chunk_real(cell)
		built[cell] = String(entry.block)
		WorldData.set_block(cell.x,cell.y,cell.z,BlockRegistry.get_id(entry.block))
		NavGrid.refresh_mined_block(cell)
	for entry: Dictionary in state.orders:
		var cells: Array[Vector3i] = []
		for pending: Dictionary in entry.cells: cells.append(SaveManager.unpack_v3i(pending.cell))
		var id := create_order(cells,int(entry.id),true,String(entry.kind))
		if id >= 0:
			for pending: Dictionary in entry.cells: orders[id].work_progress[SaveManager.unpack_v3i(pending.cell)] = float(pending.work)
	_dirty = true
