extends Node3D

## Stable seeded identities + saved edits, including transplanted shrub locations.
## Logical occupancy is installed
## for the whole layout before visual spawning, and never depends on the camera.
const Placement = preload("res://scripts/components/SurfaceDetailPlacement.gd")
const ClearingSource = preload("res://scripts/components/TreeFellingComponent.gd")
const Picking = preload("res://scripts/components/ObjectPicking.gd")
const Lighting = preload("res://scripts/components/UndergroundLighting.gd")
const Shrub = preload("res://scripts/components/ShrubSeason.gd")
@export var flora_path: NodePath
@export var slice_controller_path: NodePath
@export var visual_budget := 12
var _placement := Placement.new()
var _picking := Picking.new()
var _flora: Node
var _slice_y := 127
var _initialized := false
var _records: Dictionary = {}
var _changes: Dictionary = {}
var _sources: Dictionary = {}
var _source_ids: Dictionary = {}
var _columns: Dictionary = {}
var _visual_queue: Array[String] = []
var _models: Dictionary = {}
var _markers: Dictionary = {}
var _marker_layer: CanvasLayer
var _material: StandardMaterial3D
var _initializing := false
var _registering_id := ""
var _dev_cursors: Dictionary = {}
var diagnostics: Dictionary = {}
var _next_plant_id := 1
var _growing: Dictionary = {} # Only player-created young shrubs; no world-wide tick scan.


func _ready() -> void:
	add_to_group("surface_details")
	add_to_group("object_explorer_provider")
	add_to_group(SaveManager.OWNER_GROUP)
	_flora = get_node_or_null(flora_path) if not flora_path.is_empty() else get_tree().get_first_node_in_group("surface_flora")
	_marker_layer = CanvasLayer.new()
	_marker_layer.layer = 19
	add_child(_marker_layer)
	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true
	_material.roughness = 1.0
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	TaskManager.task_released.connect(_on_released)
	TaskManager.task_completed.connect(_on_task_gone)
	TaskManager.task_cancelled.connect(_on_task_gone)
	TaskManager.task_failed.connect(func(task: Task, _reason: String): _on_task_gone(task))
	WorldData.block_changed.connect(_on_block_changed)
	WorldClock.season_changed.connect(_on_season_changed)
	WorldClock.hour_changed.connect(_on_growth_tick)
	PlacedEntityRegistry.occupancy_changed.connect(_on_occupancy_changed)
	var slice := get_node_or_null(slice_controller_path) if not slice_controller_path.is_empty() else null
	if slice != null:
		slice.connect("slice_changed", apply_slice)
		_slice_y = int(slice.call("get_slice_y"))


func _process(_delta: float) -> void:
	if not _initialized:
		if _flora == null or not bool(WorldGenerator.get_streaming_stats().get("maps_ready", false)):
			return
		initialize_layout()
	for i in range(mini(visual_budget, _visual_queue.size())):
		_spawn_visual(_visual_queue.pop_back())
	_update_markers()


func initialize_layout(reverse_order := false) -> void:
	if _initialized or _flora == null:
		return
	var started := Time.get_ticks_usec()
	_initializing = true
	var keys: Array = SurfaceDetailRegistry.definitions.keys()
	keys.sort()
	var candidates: Array[Dictionary] = []
	for key: String in keys:
		var definition := SurfaceDetailRegistry.get_definition(key)
		var size := int(definition.placement.cell_size)
		var cells: Array[Vector2i] = []
		for x in range(ceili(float(WorldData.WORLD_SIZE_X) / size)):
			for z in range(ceili(float(WorldData.WORLD_SIZE_Z) / size)):
				cells.append(Vector2i(x, z))
		if reverse_order: cells.reverse()
		for cell: Vector2i in cells:
			var record := _placement.candidate(key, definition, cell, _flora)
			if not record.is_empty(): candidates.append(record)
	# Arbitrate immutable candidates before applying player removals. Clearing a
	# boulder must never create a previously rejected scree clump on reload.
	candidates.sort_custom(func(a: Dictionary, b: Dictionary):
		var ap := int(SurfaceDetailRegistry.get_definition(a.definition).get("placement_priority", 0))
		var bp := int(SurfaceDetailRegistry.get_definition(b.definition).get("placement_priority", 0))
		return ap > bp if ap != bp else a.id < b.id)
	var occupied_base: Dictionary = {}
	var plant_areas: Dictionary = {}
	for record: Dictionary in candidates:
		var definition := SurfaceDetailRegistry.get_definition(record.definition)
		var width := int(definition.footprint)
		var margin := int(definition.placement.get("detail_margin", 0))
		var overlap := false
		for x in range(record.origin.x - margin, record.origin.x + width + margin):
			for z in range(record.origin.z - margin, record.origin.z + width + margin):
				if occupied_base.has(Vector2i(x,z)): overlap = true
		var area := Placement.planting_area(definition, record.origin)
		if definition.has("planting_radius"):
			for x in range(int(area.position.x), int(area.end.x)):
				for z in range(int(area.position.z), int(area.end.z)):
					for other: AABB in plant_areas.get(Vector2i(x,z), []):
						if area.intersects(other): overlap = true
		if overlap:
			_placement._reject("detail_overlap")
			continue
		for x in range(record.origin.x, record.origin.x + width):
			for z in range(record.origin.z, record.origin.z + width): occupied_base[Vector2i(x,z)] = true
		if definition.has("planting_radius"):
			for x in range(int(area.position.x), int(area.end.x)):
				for z in range(int(area.position.z), int(area.end.z)):
					var col := Vector2i(x,z)
					if not plant_areas.has(col): plant_areas[col] = []
					plant_areas[col].append(area)
		register_record(record)
	_initialized = true
	_initializing = false
	diagnostics = {"seed": WorldGenerator.world_seed, "accepted": _records.size(),
		"rejections": _placement.rejection_counts.duplicate(), "layout_ms": (Time.get_ticks_usec() - started) / 1000.0}
	var counts: Dictionary = {}
	for record: Dictionary in _records.values():
		var category := String(SurfaceDetailRegistry.get_definition(record.definition).category)
		counts[category] = int(counts.get(category, 0)) + 1
	diagnostics["categories"] = counts
	print("Surface details: ", diagnostics)


func register_record(record: Dictionary) -> void:
	var id := String(record.id)
	if _records.has(id): return
	var definition := SurfaceDetailRegistry.get_definition(record.definition)
	var width := int(definition.footprint)
	record["generated_origin"] = record.origin
	if _changes.get(id, {}).has("origin"):
		record.origin = SaveManager.unpack_v3i(_changes[id].origin)
		record.yaw = int(_changes[id].get("yaw", record.yaw))
	var origin: Vector3i = record.origin
	record["occupancy"] = -1
	record["node"] = null
	_records[id] = record
	for x in range(origin.x, origin.x + width):
		for z in range(origin.z, origin.z + width):
			var col := Vector2i(x, z)
			if not _columns.has(col): _columns[col] = []
			_columns[col].append(id)
	if bool(_changes.get(id, {}).get("removed", false)): return
	if not _supported(record) or _occupied(record):
		_remove(id, "terrain_or_structure")
		return
	if bool(definition.get("blocking", true)):
		_install_occupancy(record, definition)
	_visual_queue.append(id)
	if bool(_changes.get(id, {}).get("designated", false)): _ensure_source(id)


func _install_occupancy(record: Dictionary, definition: Dictionary) -> void:
	_registering_id = String(record.id)
	var width := int(definition.footprint)
	record.occupancy = PlacedEntityRegistry.register_box(record.origin + Vector3i.UP, Vector3i(width, int(definition.height), width))
	_registering_id = ""


func _block(pos: Vector3i) -> int:
	if WorldData.get_chunk_if_exists(pos.x >> 4, pos.y >> 4, pos.z >> 4) != null:
		return WorldData.get_block(pos.x, pos.y, pos.z)
	return WorldData.get_live_block(pos.x, pos.y, pos.z)


func _supported(record: Dictionary) -> bool:
	var definition := SurfaceDetailRegistry.get_definition(record.definition)
	var o: Vector3i = record.origin
	for x in range(o.x, o.x + int(definition.footprint)):
		for z in range(o.z, o.z + int(definition.footprint)):
			if not BlockRegistry.is_solid(_block(Vector3i(x, o.y, z))): return false
			for y in range(o.y + 1, o.y + int(definition.height) + 1):
				# Flood damage is not enabled. Water blocks new planting but must
				# not delete existing plants during a later support check/load.
				if BlockRegistry.is_solid(_block(Vector3i(x, y, z))): return false
	return true


func _occupied(record: Dictionary) -> bool:
	var definition := SurfaceDetailRegistry.get_definition(record.definition)
	var o: Vector3i = record.origin
	var exclude: Array[int] = [int(record.occupancy)]
	for x in range(o.x, o.x + int(definition.footprint)):
		for z in range(o.z, o.z + int(definition.footprint)):
			for y in range(o.y + 1, o.y + int(definition.height) + 1):
				if PlacedEntityRegistry.occupies(Vector3i(x, y, z), exclude): return true
	return false


func _spawn_visual(id: String) -> void:
	if not _records.has(id) or bool(_changes.get(id, {}).get("removed", false)): return
	var record: Dictionary = _records[id]
	var definition := SurfaceDetailRegistry.get_definition(record.definition)
	var path := Shrub.model(definition, _changes.get(id, {})) if _is_shrub(id) else String(definition.models[int(record.variant)])
	if _is_decorative_plant(id): path = String(definition.seasonal_models[WorldClock.season][int(record.variant)])
	if is_instance_valid(record.node):
		if String(record.get("model_path", "")) == path: return
		record.node.visible = false
		record.node.queue_free()
		record.node = null
	record["model_path"] = path
	if not _models.has(path): _models[path] = load(path)
	var packed := _models[path] as PackedScene
	if packed == null: return
	var blocking := bool(definition.get("blocking", true))
	var body: Node3D = StaticBody3D.new() if blocking else Node3D.new()
	body.name = String(definition.display_name).replace(" ", "")
	if body is StaticBody3D:
		body.collision_layer = 2 # Terrain/camera layer 1 remains untouched.
		body.collision_mask = 0
	var width := int(definition.footprint)
	body.position = Vector3(record.origin) + Vector3(width * .5, 1, width * .5)
	var visual := packed.instantiate() as Node3D
	visual.rotation.y = int(record.yaw) * PI * .5
	body.add_child(visual)
	for mesh: MeshInstance3D in body.find_children("*", "MeshInstance3D", true, false): mesh.material_override = _material
	if blocking:
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(width, float(definition.height), width)
		shape.shape = box
		shape.position.y = box.size.y * .5
		body.add_child(shape)
	add_child(body)
	record.node = body
	record["bounds"] = Picking.world_bounds(visual)
	body.visible = record.origin.y <= _slice_y
	Lighting.bind_world_tree(body)
	_sync_marker(id)


func apply_slice(y: int) -> void:
	_slice_y = y
	for record: Dictionary in _records.values():
		if is_instance_valid(record.node): record.node.visible = record.origin.y <= y
	_update_markers()


func pick_explorer_object(start: Vector3, end: Vector3) -> Dictionary:
	var result := {}
	var nearest := start.distance_to(end)
	for id: String in _records:
		var bounds := get_explorer_bounds(id)
		if bounds.size == Vector3.ZERO or bounds.intersects_segment(start, end) == null: continue
		var distance := _picking.hit_distance(_records[id].node, start, end)
		if distance < nearest:
			nearest = distance
			result = {"id": id, "distance": distance}
	return result


## Locate only: no clearing, rewards or terrain edits. Cycle in stable order.
func dev_locate_next(category := "boulder") -> String:
	var ids: Array = _records.keys()
	ids.sort()
	for i in range(ids.size()):
		var cursor := int(_dev_cursors.get(category, 0))
		var id := String(ids[cursor % ids.size()])
		_dev_cursors[category] = cursor + 1
		if String(SurfaceDetailRegistry.get_definition(_records[id].definition).category) != category: continue
		if bool(_changes.get(id, {}).get("removed", false)): continue
		_spawn_visual(id)
		var scene := get_tree().current_scene
		if scene != null:
			var slice := scene.get_node_or_null("SliceController")
			if slice != null and slice.call("is_active"): slice.call("deactivate")
			var camera := scene.get_node_or_null("CameraRig")
			if camera != null: camera.call("focus_world_position", Vector3(_records[id].origin) + Vector3(1,1,1), 42.0)
		var explorer := get_tree().get_first_node_in_group("object_explorer")
		if explorer != null: explorer.call("select_object", self, id)
		return id
	return ""


func get_explorer_bounds(id: Variant) -> AABB:
	var record: Dictionary = _records.get(id, {})
	var node: Node3D = record.get("node")
	return record.get("bounds", AABB()) if is_instance_valid(node) and node.is_visible_in_tree() else AABB()


func get_explorer_data(id: Variant) -> Dictionary:
	if get_explorer_bounds(id).size == Vector3.ZERO: return {}
	var record: Dictionary = _records[id]
	var definition := SurfaceDetailRegistry.get_definition(record.definition)
	var state: Dictionary = _changes.get(id, {})
	if _is_shrub(String(id)): return _shrub_explorer(String(id), definition, state)
	if definition.get("kind") == "flower": return _flower_explorer(String(id), definition, state)
	var marked := bool(state.get("designated", false))
	var gathering := String(definition.clearing.get("method", "break")) == "gather"
	var plant := _is_decorative_plant(String(id))
	var status := "Marked for gathering" if marked and gathering else "Marked for clearing" if marked else "Available" if gathering else "Standing"
	if plant: status = "Marked for clearing" if marked else "Partial work kept" if float(state.get("work_seconds",0)) > 0 else "Not marked"
	var source: RefCounted = _sources.get(id)
	if source != null:
		var task := TaskManager.get_task(int(source.get("lease_id")))
		if task != null:
			if task.retry_at > Time.get_ticks_msec(): status = "Awaiting reachable route"
			elif task.status == Task.Status.ASSIGNED: status = "Worker approaching"
			elif task.status == Task.Status.IN_PROGRESS: status = "Gathering stones" if gathering else "Breaking stone"
			if plant and task.status == Task.Status.IN_PROGRESS: status = definition.clearing_activity
	if float(state.get("work_seconds", 0)) > 0:
		status += " · %d%%" % mini(99, floori(float(state.work_seconds) / float(definition.clearing.work_seconds) * 100))
	if plant:
		return {"title": definition.display_name, "kind": "Shore plant" if definition.kind == "reed" else "Wildflowers", "rows": [
			["Appearance", definition.seasonal_labels[WorldClock.season]], ["Clearing", status]],
			"details": definition.description,
			"actions": [{"id": "cancel" if marked else "clear", "text": "Cancel clearing" if marked else definition.clear_label}]}
	return {"title": definition.display_name, "kind": "Surface stone", "rows": [
		["Clearing", status], ["Yield", "%d × Rough Stone" % int(definition.clearing.count)]],
		"details": "Walkable loose stones. A worker can gather this clump. Construction displaces it without a yield. Partial work is kept if cancelled." if gathering else "Blocks movement and construction. A worker can break it from an open side. Partial work is kept if cancelled.",
		"actions": [{"id": "cancel" if marked else "clear", "text": "Cancel gathering" if marked and gathering else "Cancel clearing" if marked else "Gather stones" if gathering else "Clear boulder"}]}


func perform_explorer_action(id: Variant, action: String) -> void:
	if action == "clear": designate_clearing(String(id))
	elif action == "harvest": designate_detail(String(id), "harvest_plants")
	elif action == "cancel": cancel_clearing(String(id))
	elif action == "uproot": designate_uproot(String(id))
	elif action == "move":
		var placer := get_tree().get_first_node_in_group("furniture_controller")
		if placer != null: placer.begin_shrub_move(String(id))
	elif action == "dev_mature": dev_mature_shrub(String(id))


func _state(id: String) -> Dictionary:
	if not _changes.has(id):
		_changes[id] = {"removed": false, "designated": false, "work_seconds": 0.0}
	return _changes[id]


func designate_clearing(id: String) -> bool:
	return designate_detail(id, "clear_shrubs" if _is_shrub(id) or _is_decorative_plant(id) else "clear_stones")


func _is_shrub(id: String) -> bool:
	return _records.has(id) and String(SurfaceDetailRegistry.get_definition(_records[id].definition).get("kind", "")) == "shrub"


func _is_transplantable(id: String) -> bool:
	return _records.has(id) and SurfaceDetailRegistry.get_definition(_records[id].definition).has("transplant")


func _is_decorative_plant(id: String) -> bool:
	return _records.has(id) and String(SurfaceDetailRegistry.get_definition(_records[id].definition).get("kind", "")) in ["flower", "reed"]


func accepts_tool(id: String, tool: String) -> bool:
	if not _records.has(id) or bool(_changes.get(id, {}).get("removed", false)): return false
	if _is_decorative_plant(id):
		return tool == "clear_shrubs" and not (bool(_changes.get(id, {}).get("designated", false)) and _changes[id].get("action") == "uproot")
	var shrub := _is_shrub(id)
	if tool == "clear_stones": return not shrub
	if not shrub or tool not in ["harvest_plants", "clear_shrubs"]: return false
	var state: Dictionary = _changes.get(id, {})
	var action := "harvest" if tool == "harvest_plants" else "clear"
	if bool(state.get("designated", false)) and String(state.get("action", "clear")) != action: return false
	return tool == "clear_shrubs" or Shrub.available(SurfaceDetailRegistry.get_definition(_records[id].definition), state)


func designate_detail(id: String, tool: String) -> bool:
	if not accepts_tool(id, tool): return false
	var state := _state(id)
	if _is_transplantable(id):
		var action := "harvest" if tool == "harvest_plants" else "clear"
		if String(state.get("action", "clear")) != action:
			state[String(state.get("action", "clear")) + "_work_seconds"] = state.work_seconds
			state.work_seconds = float(state.get(action + "_work_seconds", 0))
		state["action"] = action
	state.designated = true
	_ensure_source(id)
	_sync_marker(id)
	return true


func cancel_clearing(id: String) -> void:
	if not _changes.has(id): return
	_changes[id].designated = false
	_retire_source(id, true)
	_sync_marker(id)
	var placer := get_tree().get_first_node_in_group("furniture_controller")
	if placer != null: placer.cancel_shrub_moves(id)


func get_slice_y() -> int:
	return _slice_y


## The live source is an opaque order token. Cancelling/reissuing or restoring
## a save creates a different source, so an old Undo cannot cancel new work.
func get_clearing_order_token(id: String) -> RefCounted:
	return _sources.get(id)


func stones_in_clearing_rect(rect: Rect2i) -> Array[String]:
	return details_in_rect(rect, "clear_stones")


func details_in_rect(rect: Rect2i, tool: String) -> Array[String]:
	var result: Array[String] = []
	for id: String in _records:
		if get_explorer_bounds(id).size == Vector3.ZERO: continue
		if not accepts_tool(id, tool): continue
		var record: Dictionary = _records[id]
		var definition := SurfaceDetailRegistry.get_definition(record.definition)
		var half := float(definition.footprint) * .5
		var center := Vector2i(floori(record.origin.x + half), floori(record.origin.z + half))
		if rect.has_point(center): result.append(id)
	return result


func marked_stones_in_screen_rect(rect: Rect2, camera: Camera3D) -> Array[String]:
	var result: Array[String] = []
	for id: String in _sources:
		var bounds := get_explorer_bounds(id)
		if bounds.size == Vector3.ZERO: continue
		var center := bounds.get_center()
		if not camera.is_position_behind(center) and rect.has_point(camera.unproject_position(center)):
			result.append(id)
	return result


func _ensure_source(id: String) -> void:
	if _sources.has(id): return
	var record: Dictionary = _records[id]
	var definition := SurfaceDetailRegistry.get_definition(record.definition)
	var source := ClearingSource.new()
	source.task_type = Task.Type.GATHER_SCREE if String(definition.clearing.get("method", "break")) == "gather" else Task.Type.CLEAR_BOULDER
	source.removed_key = "removed"
	source.source_id = TaskManager.allocate_source_id()
	source.origin = record.origin
	source.footprint = int(definition.footprint)
	source.duration = float(definition.clearing.work_seconds)
	source.state = _state(id)
	source.state["feedback_block"] = definition.clearing.feedback_block
	source.state["plant_kind"] = definition.get("kind", "")
	source.state["display_name"] = definition.display_name
	source.complete_callback = _complete_clearing.bind(id)
	if _is_transplantable(id):
		var harvest := String(source.state.get("action", "clear")) == "harvest"
		var uproot := String(source.state.get("action", "")) == "uproot"
		source.task_type = Task.Type.HARVEST_SHRUB if harvest else Task.Type.UPROOT_SHRUB if uproot else Task.Type.CLEAR_SHRUB
		source.duration = float(definition.harvest.work_seconds if harvest else definition.transplant.uproot_seconds if uproot else definition.clearing.work_seconds)
		source.complete_callback = _complete_shrub.bind(id)
	if _is_decorative_plant(id) and String(source.state.get("action", "clear")) != "uproot":
		source.task_type = Task.Type.CLEAR_PLANT
		source.state["display_name"] = definition.display_name
		source.state["clearing_activity"] = definition.clearing_activity
	source.contact_distance_callback = _contact_distance.bind(id)
	if source.task_type in [Task.Type.GATHER_SCREE, Task.Type.HARVEST_SHRUB, Task.Type.CLEAR_SHRUB, Task.Type.CLEAR_PLANT, Task.Type.UPROOT_SHRUB]: source.work_contact_callback = _gather_contact.bind(id)
	source.feedback_visible_callback = func(): return get_explorer_bounds(id).size != Vector3.ZERO
	_sources[id] = source
	_source_ids[source.source_id] = id
	TaskManager.register_work_source(source.source_id, source)
	source.ensure_lease()


func _gather_contact(from: Vector3, id: String) -> Vector3:
	var record: Dictionary = _records[id]
	var width := float(SurfaceDetailRegistry.get_definition(record.definition).footprint)
	var center := Vector3(record.origin) + Vector3(width * .5, 1.2, width * .5)
	if _is_shrub(id) or _is_decorative_plant(id):
		var height := float(SurfaceDetailRegistry.get_definition(record.definition).height)
		center.y = record.origin.y + 1.0 + minf(1.25, height * .4)
	var toward := Vector3(center.x - from.x, 0, center.z - from.z).normalized()
	return Vector3(from.x, center.y, from.z) + toward * minf(1.15, Vector2(center.x - from.x, center.z - from.z).length())


func _contact_distance(start: Vector3, end: Vector3, id: String) -> float:
	var node: Node3D = _records[id].node
	return _picking.hit_distance(node, start, end) if is_instance_valid(node) else INF


func _retire_source(id: String, cancel_task: bool) -> void:
	var source: RefCounted = _sources.get(id)
	if source == null: return
	var source_id := int(source.get("source_id"))
	_sources.erase(id)
	_source_ids.erase(source_id)
	if cancel_task: TaskManager.cancel_source_tasks(source_id)
	TaskManager.unregister_work_source(source_id)


func _on_released(task: Task, dwarf: int, _reason: int) -> void:
	if _source_ids.has(task.source_id): _sources[_source_ids[task.source_id]].release_worker(dwarf)


func _on_task_gone(task: Task) -> void:
	if _source_ids.has(task.source_id): _sources[_source_ids[task.source_id]].on_task_gone(task)


func _complete_clearing(dwarf: int, id: String) -> bool:
	var source: RefCounted = _sources.get(id)
	if source == null or int(source.get("reserved_by")) != dwarf: return false
	var state := _state(id)
	if bool(state.removed) or not bool(state.designated) or float(state.work_seconds) < float(source.get("duration")): return false
	var record: Dictionary = _records[id]
	var definition := SurfaceDetailRegistry.get_definition(record.definition)
	var drops := get_tree().get_first_node_in_group("item_drop_manager")
	var has_yield := int(definition.clearing.count) > 0 and not String(definition.clearing.item).is_empty()
	if has_yield and drops == null: return false
	var origin: Vector3i = record.origin
	var visible := get_explorer_bounds(id).size != Vector3.ZERO
	_remove(id, "cleared", false) # Tombstone before rewards; finishing worker owns lease completion.
	if visible and String(definition.clearing.get("method", "break")) != "gather":
		WorkFeedback.block_mined(origin + Vector3i.UP, BlockRegistry.get_id(definition.clearing.feedback_block))
	if has_yield: drops.call("spawn_drop", definition.clearing.item, int(definition.clearing.count), origin + Vector3i.UP)
	return true


func _complete_shrub(dwarf: int, id: String) -> bool:
	var source: RefCounted = _sources.get(id)
	if source == null or int(source.get("reserved_by")) != dwarf: return false
	var state := _state(id)
	if bool(state.removed) or not bool(state.designated) or float(state.work_seconds) < float(source.get("duration")): return false
	var definition := SurfaceDetailRegistry.get_definition(_records[id].definition)
	var drops := get_tree().get_first_node_in_group("item_drop_manager")
	if drops == null: return false
	if String(state.get("action", "clear")) == "uproot":
		var cargo: Node3D = drops.create_item_visual(SurfaceDetailRegistry.packed_item(_records[id].definition, int(_records[id].variant)), 1, id)
		if cargo == null: return false
		state["packed"] = true
		state["uproot_work_seconds"] = 0.0
		state.work_seconds = 0.0
		_remove(id, "uprooted", false)
		drops.drop_loose(cargo, _records[id].origin)
		var placer := get_tree().get_first_node_in_group("furniture_controller")
		if placer != null: placer.claim_moved_shrub(id, dwarf)
		return true
	if String(state.get("action", "clear")) == "clear":
		var origin: Vector3i = _records[id].origin
		_remove(id, "cleared", false)
		# Like tree seeds: one stable position/seed roll, after permanent removal.
		# Cancelling, seasons and loading cannot reroll or replay a cutting drop.
		var yields: Array = definition.clearing.get("yields", [])
		for i in range(yields.size()):
			var drop: Dictionary = yields[i]
			var roll := float(Placement.hash_cell(WorldGenerator.world_seed, origin.x, origin.z, int(definition.salt) + 17001 + i)) / 2147483648.0
			if roll < float(drop.get("chance", 1.0)):
				drops.call("spawn_drop", String(drop.item), int(drop.get("count", 1)), origin + Vector3i.UP)
		return true
	if not Shrub.available(definition, state): return false
	# Stamp the crop and retire its source before rewards. The finishing worker
	# completes its lease; stale callbacks cannot grant another crop.
	state["harvested_cycle"] = Shrub.cycle()
	state.designated = false
	state.work_seconds = 0.0
	state["harvest_work_seconds"] = 0.0
	_retire_source(id, false)
	_visual_queue.append(id)
	_sync_marker(id)
	drops.call("spawn_drop", definition.harvest.item, int(definition.harvest.count), _records[id].origin + Vector3i.UP)
	return true


func _on_season_changed(_season: String) -> void:
	_on_growth_tick(0)
	# Preserve pending order while checking membership once per plant. Scanning
	# the growing Array for every record makes a full-world season change quadratic.
	var queued: Dictionary = {}
	for queued_id: String in _visual_queue: queued[queued_id] = true
	for id: String in _records:
		if (not _is_shrub(id) and not _is_decorative_plant(id)) or bool(_changes.get(id, {}).get("removed", false)): continue
		var state: Dictionary = _changes.get(id, {})
		if bool(state.get("designated", false)) and String(state.get("action", "clear")) == "harvest":
			if not Shrub.available(SurfaceDetailRegistry.get_definition(_records[id].definition), state): cancel_clearing(id)
		if not queued.has(id):
			_visual_queue.append(id)
			queued[id] = true


func _shrub_explorer(id: String, definition: Dictionary, state: Dictionary) -> Dictionary:
	if Shrub.is_young(definition, state):
		var fraction := clampf(Shrub.grown_days(definition, state) / float(definition.growth_days), 0, 1)
		var marked_young := bool(state.get("designated", false))
		return {"title": definition.display_name, "kind": "Young planted shrub", "rows": [
			["Growth", "%d%% · %.1f growth days remaining" % [floori(fraction * 100), maxf(0, float(definition.growth_days) - Shrub.grown_days(definition, state))]],
			["Season", "Dormant · growth paused" if float(definition.planting.seasonal_growth[WorldClock.season]) <= 0 else WorldClock.season.capitalize()],
			["Order", "Clearing" if marked_young else "Growing"]],
			"details": "Grown from one cutting. Berries, Move and Uproot become available at maturity. Clearing recovers one cutting; construction removes it without a drop. Winter preserves the plant and pauses growth.",
			"actions": [{"id":"cancel" if marked_young else "clear", "text":"Cancel clearing" if marked_young else "Clear plant"},
				{"id":"dev_mature", "text":"DEV: Grow to maturity", "variant":"dev"}]}
	var ripe := Shrub.available(definition, state)
	var marked := bool(state.get("designated", false))
	var harvest := String(state.get("action", "clear")) == "harvest"
	var uproot := String(state.get("action", "")) == "uproot"
	var status := "Ready to harvest" if ripe else "Picked this season" if String(state.get("harvested_cycle", "")) == Shrub.cycle() else "Out of season"
	if marked:
		status = "Marked for harvest" if harvest else "Marked for uprooting" if uproot else "Marked for clearing"
		var source: RefCounted = _sources.get(id)
		var task := TaskManager.get_task(int(source.get("lease_id"))) if source != null else null
		if task != null:
			if task.retry_at > Time.get_ticks_msec(): status = "Awaiting reachable route"
			elif task.status == Task.Status.ASSIGNED: status = "Worker approaching"
			elif task.status == Task.Status.IN_PROGRESS: status = "Harvesting berries" if harvest else "Uprooting shrub" if uproot else "Clearing plant"
		var duration := float(definition.harvest.work_seconds if harvest else definition.transplant.uproot_seconds if uproot else definition.clearing.work_seconds)
		if float(state.get("work_seconds", 0)) > 0: status += " · %d%%" % mini(99, floori(float(state.work_seconds) / duration * 100))
	var actions: Array = []
	if marked: actions.append({"id": "cancel", "text": "Cancel harvest" if harvest else "Cancel uprooting / move" if uproot else "Cancel clearing"})
	else:
		if ripe: actions.append({"id": "harvest", "text": "Harvest berries"})
		actions.append({"id": "move", "text": "Move"})
		actions.append({"id": "uproot", "text": "Uproot"})
		actions.append({"id": "clear", "text": "Clear plant"})
	var seasons: Array[String] = []
	for season: String in definition.harvest.seasons: seasons.append(season.capitalize())
	var clearing_yields: Array[String] = []
	var items := get_tree().get_first_node_in_group("item_drop_manager")
	for drop: Dictionary in definition.clearing.get("yields", []):
		var item_key := String(drop.item)
		var item: Dictionary = items.call("get_item_def", item_key) if items != null else {}
		var label := String(item.get("display_name", item_key.get_slice(":", item_key.get_slice_count(":") - 1).capitalize()))
		clearing_yields.append("%d × %s (%d%% chance)" % [int(drop.get("count", 1)), label, roundi(float(drop.get("chance", 1.0)) * 100)])
	return {"title": definition.display_name, "kind": "Transplanted shrub" if state.has("origin") else "Wild shrub", "rows": [
		["Crop", status], ["Harvest", "%d berries · %s" % [int(definition.harvest.count), " / ".join(seasons)]]],
		"details": "One crop per harvest season. Move replants this mature shrub. Uproot packs it for storage and later placement. Both preserve its crop; neither grants berries or a cutting. Clearing removes it permanently.\n\nPossible clearing yield: " + ", ".join(clearing_yields) + ".\nPlant cuttings through Place → Plants. Construction removes plants without a drop.",
		"actions": actions}


func _remove(id: String, reason: String, cancel_task := true) -> void:
	_growing.erase(id)
	var state := _state(id)
	state.removed = true
	state.designated = false
	state["reason"] = reason
	_retire_source(id, cancel_task)
	var record: Dictionary = _records[id]
	var handle := int(record.occupancy)
	record.occupancy = -1
	if handle >= 0: PlacedEntityRegistry.unregister(handle)
	var node: Node3D = record.node
	record.node = null
	if is_instance_valid(node):
		node.visible = false
		if node is CollisionObject3D: node.collision_layer = 0
		node.queue_free()
	_sync_marker(id)
	if not bool(state.get("packed", false)):
		var placer := get_tree().get_first_node_in_group("furniture_controller")
		if placer != null: placer.cancel_shrub_moves(id)


func _on_block_changed(pos: Vector3i, _old: int, _new: int) -> void:
	for id: String in _columns.get(Vector2i(pos.x, pos.z), []):
		if bool(_changes.get(id, {}).get("removed", false)): continue
		if not _supported(_records[id]): _remove(id, "support_changed")


func _on_occupancy_changed(box_min: Vector3i, box_size: Vector3i) -> void:
	if _initializing: return
	for x in range(box_min.x, box_min.x + box_size.x):
		for z in range(box_min.z, box_min.z + box_size.z):
			for id: String in _columns.get(Vector2i(x, z), []):
				if id == _registering_id: continue
				if bool(_changes.get(id, {}).get("removed", false)): continue
				if _occupied(_records[id]): _remove(id, "structure")


func _sync_marker(id: String) -> void:
	if _markers.has(id):
		_markers[id].queue_free()
		_markers.erase(id)
	if not bool(_changes.get(id, {}).get("designated", false)): return
	var marker := Label.new()
	marker.text = "+" if String(SurfaceDetailRegistry.get_definition(_records[id].definition).category) == "scree" else "⛏"
	if _is_shrub(id): marker.text = "+" if String(_changes[id].get("action", "clear")) == "harvest" else "↑" if String(_changes[id].get("action", "")) == "uproot" else "×"
	if _is_decorative_plant(id): marker.text = "↑" if _changes[id].get("action") == "uproot" else "×"
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marker.add_theme_font_size_override("font_size", 24)
	marker.add_theme_color_override("font_color", Color(1, .76, .38))
	marker.add_theme_constant_override("outline_size", 4)
	marker.visible = false
	_marker_layer.add_child(marker)
	_markers[id] = marker


func _update_markers() -> void:
	var camera := get_viewport().get_camera_3d()
	for id: String in _markers:
		var marker: Label = _markers[id]
		var bounds := get_explorer_bounds(id)
		var above := bounds.get_center() + Vector3.UP * (bounds.size.y * .5 + .5)
		marker.visible = camera != null and bounds.size != Vector3.ZERO and not camera.is_position_behind(above)
		if marker.visible: marker.position = camera.unproject_position(above) - marker.size * .5


func save_section_key() -> String:
	return "surface_details"


func save_restore_priority() -> int:
	return 16 # Mined terrain/trees first, then furniture/items and dwarf reconstruction.


func serialize_state() -> Dictionary:
	var entries: Array = []
	var planted: Array = []
	for id: String in _records:
		if not bool(_records[id].get("player_created", false)): continue
		planted.append({"id": id, "definition": _records[id].definition,
			"origin": SaveManager.pack_v3i(_records[id].generated_origin), "yaw": int(_records[id].yaw)})
	planted.sort_custom(func(a: Dictionary, b: Dictionary): return a.id < b.id)
	var ids: Array = _changes.keys()
	ids.sort()
	for id: String in ids:
		var state: Dictionary = _changes[id]
		entries.append({"id": id, "removed": bool(state.removed), "designated": bool(state.designated),
			"work_seconds": float(state.work_seconds), "reason": String(state.get("reason", ""))})
		if _is_shrub(id): entries.back().merge(Shrub.restore(state, SurfaceDetailRegistry.get_definition(_records[id].definition)), true)
		elif _is_transplantable(id): entries.back().merge(_restore_flower_work(state, SurfaceDetailRegistry.get_definition(_records[id].definition)), true)
		for field: String in ["origin", "yaw", "packed", "planted_at", "growth_credit"]:
			if state.has(field): entries.back()[field] = state[field]
	return {"changes": entries, "planted": planted, "next_plant_id": _next_plant_id}


func restore_state(saved: Dictionary) -> void:
	for id: String in _sources.keys(): _retire_source(id, true)
	_growing.clear()
	for id: String in _records.keys():
		if not bool(_records[id].get("player_created", false)): continue
		var record: Dictionary = _records[id]
		if is_instance_valid(record.node): record.node.queue_free()
		if _markers.has(id):
			_markers[id].queue_free()
			_markers.erase(id)
		var col := Vector2i(record.origin.x, record.origin.z)
		if _columns.has(col): _columns[col].erase(id)
		_records.erase(id)
	var planted: Dictionary = {}
	_next_plant_id = maxi(1, int(saved.get("next_plant_id", 1)))
	for raw in saved.get("planted", []):
		if not raw is Dictionary: continue
		var id := String(raw.get("id", ""))
		var key := String(raw.get("definition", ""))
		if not id.begins_with("planted:%d:" % WorldGenerator.world_seed) or SurfaceDetailRegistry.get_definition(key).get("kind") != "shrub": continue
		planted[id] = {"id": id, "definition": key, "origin": SaveManager.unpack_v3i(raw.origin),
			"yaw": int(raw.get("yaw", 0)), "variant": 0, "player_created": true}
		_next_plant_id = maxi(_next_plant_id, int(id.get_slice(":", 2)) + 1)
	_changes.clear()
	for raw in saved.get("changes", []):
		if not raw is Dictionary: continue
		var id := String(raw.get("id", ""))
		# Stable IDs include the world seed. Reject cross-world/unknown categories.
		var definition: Dictionary = {}
		if planted.has(id): definition = SurfaceDetailRegistry.get_definition(planted[id].definition)
		for value: Dictionary in SurfaceDetailRegistry.definitions.values():
			if id.begins_with("%s:%d:" % [value.category, WorldGenerator.world_seed]):
				definition = value
				break
		if definition.is_empty(): continue
		var duration := float(definition.clearing.work_seconds)
		_changes[id] = {"removed": bool(raw.get("removed", false)),
			"designated": bool(raw.get("designated", false)) and not bool(raw.get("removed", false)),
			"work_seconds": clampf(float(raw.get("work_seconds", 0)), 0, duration), "reason": String(raw.get("reason", ""))}
		if String(definition.get("kind", "")) == "shrub": _changes[id].merge(Shrub.restore(raw, definition), true)
		elif definition.get("kind") == "flower": _changes[id].merge(_restore_flower_work(raw, definition), true)
		for field: String in ["origin", "yaw", "packed", "planted_at", "growth_credit"]:
			if raw.has(field): _changes[id][field] = raw[field]
	initialize_layout()
	for record: Dictionary in planted.values(): register_record(record)
	for id: String in _records:
		var state: Dictionary = _changes.get(id, {})
		var origin: Vector3i = SaveManager.unpack_v3i(state.origin) if state.has("origin") else _records[id].generated_origin
		_relocate_record(id, origin, int(state.get("yaw", _records[id].yaw)))
		if bool(state.get("removed", false)): _remove(id, String(state.get("reason", "restored")))
		elif not _supported(_records[id]) or _occupied(_records[id]): _remove(id, "terrain_or_structure")
		else:
			var definition := SurfaceDetailRegistry.get_definition(_records[id].definition)
			if int(_records[id].occupancy) < 0 and bool(definition.get("blocking", true)):
				_install_occupancy(_records[id], definition)
			_visual_queue.append(id)
			if bool(state.get("designated", false)): _ensure_source(id)
		_sync_marker(id)
	# Restore occurs before WorldClock. Keep every planted candidate until the
	# clock's final signals reconcile age; never infer maturity from the old clock.
	for id: String in planted:
		if not bool(_changes.get(id, {}).get("removed", false)): _growing[id] = true


func _exit_tree() -> void:
	_initializing = true
	for id: String in _sources.keys(): _retire_source(id, true)
	for record: Dictionary in _records.values():
		if int(record.occupancy) >= 0: PlacedEntityRegistry.unregister(int(record.occupancy))


func can_uproot(id: String) -> bool:
	return _is_transplantable(id) and not Shrub.is_young(SurfaceDetailRegistry.get_definition(_records[id].definition), _changes.get(id, {})) and not bool(_changes.get(id, {}).get("removed", false)) and not bool(_changes.get(id, {}).get("designated", false))


func designate_uproot(id: String) -> bool:
	if not can_uproot(id): return false
	var state := _state(id)
	state[String(state.get("action", "clear")) + "_work_seconds"] = state.work_seconds
	state.action = "uproot"
	state.work_seconds = float(state.get("uproot_work_seconds", 0))
	state.designated = true
	_ensure_source(id)
	_sync_marker(id)
	return true


## Cultivated plants ignore wild altitude/noise but retain soil and space rules.
## Both planted and queued 3x3 areas protect visual overhang without collision.
func planting_reason(key: String, origin: Vector3i, ignore_id := "", ignore_ghost := -1) -> String:
	var definition := SurfaceDetailRegistry.get_definition(key)
	if not definition.has("transplant"): return "plant_soil"
	if origin.y <= 0 or origin.y + int(definition.height) >= WorldData.WORLD_SIZE_Y: return "plant_soil"
	for x in range(origin.x - 1, origin.x + 2):
		for z in range(origin.z - 1, origin.z + 2):
			if x < 1 or z < 1 or x >= WorldData.WORLD_SIZE_X - 1 or z >= WorldData.WORLD_SIZE_Z - 1: return "plant_soil"
			if not BlockRegistry.is_solid(_block(Vector3i(x, origin.y, z))): return "plant_soil"
			for y in range(origin.y + 1, origin.y + maxi(3, int(definition.height)) + 1):
				if _block(Vector3i(x,y,z)) != BlockRegistry.AIR_ID or PlacedEntityRegistry.occupies(Vector3i(x,y,z)): return "plant_clearance"

	var area := Placement.planting_area(definition, origin)
	# Roots two cells away still overlap this plant's outer planting ring.
	for x in range(origin.x - 2, origin.x + 3):
		for z in range(origin.z - 2, origin.z + 3):
			for id: String in _columns.get(Vector2i(x,z), []):
				if id == ignore_id or bool(_changes.get(id, {}).get("removed", false)): continue
				var other := SurfaceDetailRegistry.get_definition(_records[id].definition)
				if area.intersects(Placement.planting_area(other, _records[id].origin)):
					return "plant_spacing" if other.has("planting_radius") else "plant_clearance"
	var placer := get_tree().get_first_node_in_group("furniture_controller")
	if placer != null and placer.plant_area_reserved(area, ignore_ghost): return "plant_spacing"
	var ground := _block(origin)
	var ground_key := String(BlockRegistry.get_key(ground))
	if String(BlockRegistry.get_def(ground_key).get("kind", "")) not in definition.transplant.ground_kinds: return "plant_soil"
	for y in range(origin.y + 1, WorldData.WORLD_SIZE_Y):
		if _block(Vector3i(origin.x,y,origin.z)) != BlockRegistry.AIR_ID: return "plant_sky"
	return ""


func can_plant(id: String, key: String, origin: Vector3i, ignore_ghost := -1) -> bool:
	return _is_transplantable(id) and _records[id].definition == key and bool(_changes.get(id, {}).get("packed", false)) and planting_reason(key, origin, "", ignore_ghost).is_empty()


func plant_cutting(key: String, origin: Vector3i, yaw: int) -> String:
	assert(planting_reason(key, origin).is_empty())
	var id := "planted:%d:%d" % [WorldGenerator.world_seed, _next_plant_id]
	_next_plant_id += 1
	_changes[id] = {"removed": false, "designated": false, "work_seconds": 0.0,
		"planted_at": WorldClock.elapsed_days(), "reason": "planted_cutting"}
	register_record({"id": id, "definition": key, "origin": origin, "yaw": yaw,
		"variant": 0, "player_created": true})
	_growing[id] = true
	return id


func _on_growth_tick(_hour: int) -> void:
	for id: String in _growing.keys():
		if not _records.has(id) or bool(_changes.get(id, {}).get("removed", false)):
			_growing.erase(id)
			continue
		var definition := SurfaceDetailRegistry.get_definition(_records[id].definition)
		if not Shrub.is_young(definition, _changes[id]):
			_growing.erase(id)
			if not id in _visual_queue: _visual_queue.append(id)


func dev_mature_shrub(id: String) -> void:
	if not _is_shrub(id) or bool(_changes.get(id, {}).get("removed", false)): return
	var definition := SurfaceDetailRegistry.get_definition(_records[id].definition)
	if not Shrub.is_young(definition, _changes.get(id, {})): return
	_changes[id]["growth_credit"] = float(definition.growth_days)
	_on_growth_tick(0)
	_spawn_visual(id)


func plant_shrub(id: String, key: String, origin: Vector3i, yaw: int) -> void:
	assert(can_plant(id, key, origin))
	var state := _state(id)
	state.removed = false
	state.packed = false
	state.designated = false
	state.work_seconds = 0.0
	state.action = "clear"
	state.reason = "transplanted"
	state["origin"] = SaveManager.pack_v3i(origin)
	state["yaw"] = yaw
	_relocate_record(id, origin, yaw)
	_visual_queue.append(id)


func _relocate_record(id: String, origin: Vector3i, yaw: int) -> void:
	var record: Dictionary = _records[id]
	if record.origin == origin and int(record.yaw) == yaw: return
	var old_col := Vector2i(record.origin.x, record.origin.z)
	if _columns.has(old_col): _columns[old_col].erase(id)
	var col := Vector2i(origin.x, origin.z)
	if not _columns.has(col): _columns[col] = []
	_columns[col].append(id)
	record.origin = origin
	record.yaw = yaw
	if is_instance_valid(record.node):
		record.node.visible = false
		record.node.queue_free()
		record.node = null


func packed_model(id: String) -> String:
	if not _is_transplantable(id): return ""
	var definition := SurfaceDetailRegistry.get_definition(_records[id].definition)
	if definition.get("kind") == "flower":
		return String(definition.transplant.models[WorldClock.season][int(_records[id].variant)])
	var state: Dictionary = _changes.get(id, {}).duplicate()
	state.removed = false # Packing does not change ripe/picked state.
	var season := WorldClock.season
	var variant := season + "_picked" if not Shrub.available(definition, state) and definition.picked_models.has(season) else season
	return String(definition.transplant.models[variant])


func _restore_flower_work(raw: Dictionary, definition: Dictionary) -> Dictionary:
	var action := "uproot" if raw.get("action") == "uproot" else "clear"
	var duration := float(definition.transplant.uproot_seconds if action == "uproot" else definition.clearing.work_seconds)
	return {"action": action, "work_seconds": clampf(float(raw.get("work_seconds", 0)), 0, duration),
		"uproot_work_seconds": clampf(float(raw.get("uproot_work_seconds", 0)), 0, float(definition.transplant.uproot_seconds)),
		"clear_work_seconds": clampf(float(raw.get("clear_work_seconds", 0)), 0, float(definition.clearing.work_seconds))}


func _flower_explorer(id: String, definition: Dictionary, state: Dictionary) -> Dictionary:
	var marked := bool(state.get("designated", false))
	var uproot: bool = state.get("action") == "uproot"
	var actions: Array = [{"id":"cancel", "text":"Cancel uprooting / move" if uproot else "Cancel clearing"}] if marked else [
		{"id":"move", "text":"Move"}, {"id":"uproot", "text":"Uproot"}, {"id":"clear", "text":definition.clear_label}]
	var status := "Not marked"
	if marked:
		var duration := float(definition.transplant.uproot_seconds if uproot else definition.clearing.work_seconds)
		status = ("Uprooting" if uproot else "Clearing") + " · %d%%" % floori(float(state.get("work_seconds", 0)) / duration * 100)
	return {"title": definition.transplant.variants[int(_records[id].variant)].display_name, "kind":"Transplanted flowers" if state.has("origin") else "Wildflowers",
		"rows":[["Appearance", definition.seasonal_labels[WorldClock.season]], ["Bloom", "Blooming" if flower_blooming(id) else "Out of bloom"], ["Order", status]],
		"details": definition.description, "actions": actions}


## Future hive forage reads living, planted clumps at their current locations.
## No timers are reset by transplanting and packed/storage plants never qualify.
func flower_blooming(id: String) -> bool:
	if not _records.has(id): return false
	var definition := SurfaceDetailRegistry.get_definition(_records[id].definition)
	var state: Dictionary = _changes.get(id, {})
	return definition.has("bloom") and not bool(state.get("removed", false)) and not bool(state.get("packed", false)) and WorldClock.season in definition.bloom.seasons


func flowering_clumps(center: Vector3, radius: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id: String in _records:
		if not flower_blooming(id): continue
		var position := Vector3(_records[id].origin) + Vector3(.5,1,.5)
		if position.distance_squared_to(center) <= radius * radius:
			result.append({"id":id, "position":position, "definition":_records[id].definition, "variant":int(_records[id].variant)})
	return result
