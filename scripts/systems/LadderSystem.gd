extends Node3D

## Scene-owned by FurniturePlacementController, which owns the JSON definition.
## Routes consist only of paid, installed sections. The next job works from the
## previous section; unfinished plans never grant access to the upper landing.
const KEY := "base:furniture:crude_ladder"
const BuildSource = preload("res://scripts/components/LadderBuildComponent.gd")
const RemoveSource = preload("res://scripts/components/LadderRemovalComponent.gd")
var definition: Dictionary
var routes: Dictionary = {}
var work := preload("res://scripts/components/WorkSourceTable.gd").new() # route id -> section source
var _next_id := 1
var _tick := 0.0
var _terrain_dirty := false
var _picking := preload("res://scripts/components/ObjectPicking.gd").new()

func _ready() -> void:
	add_to_group("ladders")
	add_to_group("object_explorer_provider")
	add_to_group(SaveManager.OWNER_GROUP)
	definition = get_parent().get_defs().get(KEY, {})
	if not NavGrid.ladder_routes_changed.is_connected(TaskManager.ladder_routes_changed):
		NavGrid.ladder_routes_changed.connect(TaskManager.ladder_routes_changed)
	WorldData.chunk_dirtied.connect(func(_x: int, _y: int, _z: int): _terrain_dirty = true)

func _exit_tree() -> void:
	for id: int in routes:
		_retire(routes[id], true)
		NavGrid.remove_ladder(id)

func section_height() -> int:
	return int(definition.ladder.section_height)

func sections(height: int) -> int:
	return ceili(float(height) / section_height())

func facing(yaw: int) -> Vector3i:
	return [Vector3i(0,0,-1), Vector3i(-1,0,0), Vector3i(0,0,1), Vector3i(1,0,0)][posmod(yaw,4)]

## Aim at a cliff face, its top edge, or the ground next to its base.
func from_hit(hit: Dictionary, yaw: int) -> Dictionary:
	if hit.is_empty(): return {}
	var cell := Vector3i(hit.x, hit.y, hit.z)
	var normal: Vector3i = hit.get("normal", Vector3i.ZERO)
	var column := cell
	if normal.y == 0 and normal != Vector3i.ZERO:
		column += normal
		for i in range(4):
			if facing(i) == -normal: yaw = i
	elif NavGrid.is_walkable(cell) and not BlockRegistry.is_solid(_block(cell + facing(yaw) + Vector3i.UP)):
		column -= facing(yaw) # Top edge: search its outside column downward.
	for y in range(column.y, 0, -1):
		var base := Vector3i(column.x, y, column.z)
		if BlockRegistry.is_solid(_block(base)):
			return {"base":base, "yaw":yaw}
	return {}

func describe(base: Vector3i, yaw: int, ignore := -1) -> Dictionary:
	var result := {"base":base, "yaw":yaw, "height":0, "reason":"Needs a clear floor beside a continuous cliff face"}
	if not NavGrid.is_walkable(base) or not NavGrid.clear_for_climbing(base): return result
	var wall := base + facing(yaw)
	for y in range(base.y + 1, WorldData.WORLD_SIZE_Y - NavGrid.CLEARANCE):
		var rung := Vector3i(base.x, y, base.z)
		if not NavGrid.clear_for_climbing(rung):
			result.reason = "Leave three blocks of clear climbing space"
			return result
		var support := Vector3i(wall.x, y, wall.z)
		if not BlockRegistry.is_solid(_block(support)): return result
		if NavGrid.is_walkable(support):
			if y - base.y < 2: return result # Ordinary one-block steps need no ladder.
			result.height = sections(y - base.y) * section_height()
			break
	if result.height == 0: return result
	# Uneven cliffs still use a complete final section. Check its whole height,
	# including the usual body clearance above the last installed rung.
	for offset in range(1, int(result.height) + 1):
		if not NavGrid.clear_for_climbing(base + Vector3i.UP * offset):
			result.reason = "Leave three blocks of clear climbing space"
			return result
	var area := _clearance_bounds(result)
	for id: int in routes:
		if id != ignore and _clearance_bounds(routes[id]).intersects(area):
			result.reason = "Another ladder occupies this space"
			return result
	var parent := get_parent()
	if is_instance_valid(parent.get_bridges()) and parent.get_bridges().reserves(area):
		result.reason = "Keep the ladder clear of bridges and bridge plans"
		return result
	var plants := get_tree().get_first_node_in_group("surface_details")
	if plants != null:
		for x in range(base.x - 1, base.x + 2):
			for z in range(base.z - 1, base.z + 2):
				for id: String in plants.ids_in_column(Vector2i(x,z)):
					if bool(plants.get_change(id).get("removed", false)): continue
					var record: Dictionary = plants.get_record(id)
					var plant := SurfaceDetailRegistry.get_definition(record.definition)
					if area.intersects(preload("res://scripts/components/SurfaceDetailPlacement.gd").planting_area(plant, record.origin)):
						result.reason = "Clear or move nearby plants and stones first"
						return result
	for zone: StockpileZoneComponent in StockpileManager.get_zones():
		for cell: Vector3i in zone.tile_cells:
			if area.intersects(AABB(Vector3(cell) + Vector3.UP, Vector3.ONE)):
				result.reason = "Keep the climbing column clear of storage zones"
				return result
	for group: Array in [parent.get_ghost_pieces(), parent.get_installed_pieces()]:
		for piece in group:
			if parent.visual_bounds(piece.def, piece.origin_cell, piece.yaw_steps).intersects(area):
				result.reason = "Clear nearby furniture or queued placements first"
				return result
	result.reason = ""
	return result

func placement_reason(base: Vector3i, yaw: int) -> String:
	var spec := describe(base, yaw)
	if not String(spec.reason).is_empty(): return spec.reason
	var available := int(get_parent().placement_available(KEY))
	var required := sections(spec.height)
	if available < required:
		return "%d-block ladder · Needs %d sections · %d available · Craft %d more at the crude workbench" % [spec.height, required, available, required - available]
	if base.y + int(spec.height) > get_parent().get_slice_y(): return "Raise the slice to show the upper landing"
	return ""

func place(base: Vector3i, yaw: int) -> int:
	if not placement_reason(base, yaw).is_empty(): return -1
	var spec := describe(base, yaw)
	var id := _next_id
	_next_id += 1
	var route := {"id":id, "base":base, "yaw":yaw, "height":int(spec.height), "built":0,
		"required_material_id":String(get_parent().material_choices.get(KEY, "")),"mode":"build", "progress":0.0, "node":null, "materials":[]}
	routes[id] = route
	_refresh(route)
	return id

func pending_sections() -> Dictionary:
	var pending := 0
	var requested := 0
	for route: Dictionary in routes.values():
		if route.mode != "build": continue
		var count := sections(route.height) - sections(route.built)
		requested += count
		var source = work.get_source(route.id)
		pending += count - (1 if source != null and source.has_committed_item() else 0)
	return {"pending":pending, "requested":requested}

func reserves(area: AABB) -> bool:
	for route: Dictionary in routes.values():
		if _clearance_bounds(route).intersects(area): return true
	return false

func _process(delta: float) -> void:
	_tick += delta
	if _tick < .25: return
	_tick = 0.0
	for route: Dictionary in routes.values().duplicate():
		if _terrain_dirty:
			var spec := describe(route.base, route.yaw, route.id)
			if not String(spec.reason).is_empty() or int(spec.height) != int(route.height):
				# Close access immediately. Keep installed supports until occupants
				# have left; recover paid sections once the route is empty.
				if route.mode != "damaged":
					_retire(route, true)
					route.mode = "damaged"
					_register(route)
		if route.mode == "damaged":
			if _safe_to_remove(route, -1):
				var drops := ItemDropManager.find(get_tree())
				if drops != null:
					for index in range(sections(route.built)):
						drops.spawn_drop(definition.item_key, 1, route.base + Vector3i.UP, String(route.get("materials", [])[index]) if index < route.get("materials", []).size() else "")
				_erase(route)
			continue
		if not work.has(route.id): _make_source(route)
		var source = work.get_source(route.id)
		if source is FurnitureGhostComponent: source.update_lease()
		if is_instance_valid(route.node): route.node.visible = route.base.y + 1 <= get_parent().get_slice_y()
	_terrain_dirty = false

func _make_source(route: Dictionary) -> void:
	var drops := ItemDropManager.find(get_tree())
	if drops == null: return
	var source: RefCounted
	if route.mode == "build" and route.built < route.height:
		source = BuildSource.new()
		source.setup(route.id, KEY, definition, route.base + Vector3i.UP * int(route.built), route.yaw)
		source.drop_manager = drops
		source.required_material_id = String(route.get("required_material_id", ""))
		source.build_valid_callback = func(_s): return routes.has(route.id) and route.mode == "build" and String(describe(route.base, route.yaw, route.id).reason).is_empty()
		source.install_callback = func(_s): _installed(route)
	elif route.mode == "remove" and route.built > 0:
		source = RemoveSource.new()
		var remaining := maxi(0, (sections(route.built) - 1) * section_height())
		source.setup(route.id, KEY, definition, route.base + Vector3i.UP * remaining, route.yaw)
		source.safe_callback = func(dwarf: int): return _safe_to_remove(route, dwarf)
		source.uninstall_callback = func(_s, _worker_id): _removed(route)
	else: return
	source.progress = route.progress
	work.add(route.id, source)
	if source is FurnitureGhostComponent: source.update_lease()
	else: source.set_uninstall(true)

func _installed(route: Dictionary) -> void:
	if not route.has("materials"): route.materials = []
	route.materials.append(work.get_source(route.id).material_id)
	_retire(route, false)
	route.built = mini(route.height, route.built + section_height())
	route.progress = 0.0
	if route.built == route.height: route.mode = "ready"
	_refresh(route)

func _removed(route: Dictionary) -> void:
	var material_id := String(route.materials.pop_back()) if not route.get("materials", []).is_empty() else ""
	var origin: Vector3i = work.get_source(route.id).origin_cell
	_retire(route, false)
	route.built = maxi(0, (sections(route.built) - 1) * section_height())
	route.progress = 0.0
	ItemDropManager.find(get_tree()).spawn_drop(definition.item_key, 1, origin + Vector3i.UP, material_id)
	if route.built == 0: _erase(route)
	else: _refresh(route)

func _safe_to_remove(route: Dictionary, worker: int) -> bool:
	for agent in TaskManager.get_agents():
		if not is_instance_valid(agent) or agent.dwarf_id == worker: continue
		var cell: Vector3i = agent.current_cell()
		if cell.x == route.base.x and cell.z == route.base.z and cell.y > route.base.y and cell.y <= route.base.y + route.built:
			return false
	return true

func _retire(route: Dictionary, cancel: bool) -> void:
	var source = work.get_source(route.id)
	if source == null: return
	route.progress = source.progress
	work.retire(route.id, cancel)

func _register(route: Dictionary) -> void:
	if route.built <= 0: NavGrid.remove_ladder(route.id)
	else: NavGrid.set_ladder(route.id, route.base, route.built, facing(route.yaw), float(definition.ladder.climb_speed_multiplier), route.mode in ["remove", "damaged"])

func _refresh(route: Dictionary) -> void:
	_register(route)
	_rebuild_visual(route)
	_make_source(route)
	get_parent().mark_catalog_dirty()

func _erase(route: Dictionary) -> void:
	_retire(route, true)
	NavGrid.remove_ladder(route.id)
	if is_instance_valid(route.node): route.node.queue_free()
	routes.erase(route.id)
	get_parent().mark_catalog_dirty()

func make_visual(height: int, built: int, ghost_material: Material = null, materials: Array = []) -> Node3D:
	var root_node := Node3D.new()
	for offset in range(0, height, section_height()):
		var packed: PackedScene = load(String(definition.ladder.models[str(section_height())]))
		var mesh: Node3D = packed.instantiate()
		preload("res://scripts/components/VoxelShadowSetup.gd").set_casting(mesh,offset<built)
		mesh.position.y = offset
		root_node.add_child(mesh)
		if offset >= built:
			get_parent().apply_material(mesh, ghost_material if ghost_material != null else get_parent().make_ghost_material())
		else:
			get_parent().apply_material(mesh, get_parent().make_solid_material())
			var index := floori(float(offset) / section_height())
			if index < materials.size(): CraftMaterials.apply_palette(mesh, definition, String(materials[index]))
	return root_node

func _rebuild_visual(route: Dictionary) -> void:
	if is_instance_valid(route.node): route.node.queue_free()
	var height: int = route.height if route.mode == "build" else route.built
	route.node = make_visual(height, route.built, null, route.get("materials", []))
	add_child(route.node)
	route.node.position = Vector3(route.base) + Vector3(.5, 1, .5)
	route.node.rotation.y = route.yaw * PI * .5
	preload("res://scripts/components/UndergroundLighting.gd").bind_world_tree(route.node)

func _bounds(route: Dictionary) -> AABB:
	var height: int = route.height if route.mode == "build" else route.built
	return AABB(Vector3(route.base) + Vector3(0,1,0), Vector3(1, height, 1))

func _clearance_bounds(route: Dictionary) -> AABB:
	return AABB(Vector3(route.base) + Vector3(0,1,0), Vector3(1, int(route.height) + NavGrid.CLEARANCE, 1))

func _block(cell: Vector3i) -> int:
	return get_parent().terrain_block_id(cell.x, cell.y, cell.z)

func pick_explorer_object(start: Vector3, end: Vector3) -> Dictionary:
	var result := {}
	var nearest := start.distance_to(end)
	for route: Dictionary in routes.values():
		if not is_instance_valid(route.node) or not route.node.is_visible_in_tree(): continue
		var distance: float = _picking.hit_distance(route.node, start, end)
		if distance < nearest:
			nearest = distance
			result = {"id":route.id, "distance":distance}
	return result

func get_explorer_bounds(id: Variant) -> AABB:
	return _bounds(routes[int(id)]) if routes.has(int(id)) else AABB()

func get_explorer_data(id: Variant) -> Dictionary:
	var route: Dictionary = routes.get(int(id), {})
	if route.is_empty(): return {}
	var status := {"build":"Installing from below", "ready":"Open for climbing and hauling", "paused":"Construction stopped", "remove":"Dismantling from the top", "damaged":"Support damaged — clearing the route"}
	var actions: Array = []
	if route.mode == "build": actions.append({"id":"pause", "text":"Pause construction" if route.built > 0 else "Cancel placement"})
	if route.mode == "paused" and route.built < route.height: actions.append({"id":"resume", "text":"Resume construction"})
	if route.built > 0:
		actions.append({"id":"pause" if route.mode == "remove" else "remove", "text":"Cancel dismantling" if route.mode == "remove" else "Dismantle and recover sections"})
	return {"title":"Rough wooden ladder", "kind":"Access", "rows":[["Status",status[route.mode]],
		["Height", "%d / %d blocks installed" % [route.built, route.height]], ["Sections", "%d installed · %d total" % [sections(route.built), sections(route.height)]]] + _material_rows(route),
		"details":"Workers carry each four-block section here and install it from below. Dismantling waits for climbers to leave and recovers one section at a time.", "actions":actions}

func perform_explorer_action(id: Variant, action: String) -> void:
	var route: Dictionary = routes.get(int(id), {})
	if route.is_empty(): return
	var old_mode: String = route.mode
	_retire(route, true)
	if action == "pause":
		if route.built == 0: _erase(route); return
		route.mode = "ready" if route.built == route.height else "paused"
		if old_mode == "remove": route.progress = 0.0
	elif action == "resume": route.mode = "build"
	elif action == "remove":
		route.mode = "remove"
		route.progress = 0.0
	_refresh(route)

func save_section_key() -> String: return "ladders"
func save_restore_priority() -> int: return 41

func serialize_state() -> Dictionary:
	var entries: Array = []
	for route: Dictionary in routes.values():
		entries.append({"id":route.id, "key":KEY, "base":SaveManager.pack_v3i(route.base), "yaw":route.yaw,
			"height":route.height, "built":route.built, "materials":route.get("materials", []).duplicate(), "required_material_id":String(route.get("required_material_id", "")),"mode":route.mode, "progress":work.get_source(route.id).progress if work.has(route.id) else route.progress})
	return {"routes":entries, "next_id":_next_id}

func restore_state(state: Dictionary) -> void:
	for route: Dictionary in routes.values().duplicate(): _erase(route)
	_next_id = maxi(1, int(state.get("next_id", 1)))
	for entry: Dictionary in state.get("routes", []):
		if String(entry.get("key", "")) != KEY: continue
		var route := entry.duplicate(true)
		route.base = SaveManager.unpack_v3i(entry.base)
		for key in ["id", "yaw", "height", "built"]: route[key] = int(route[key])
		route.node = null
		routes[route.id] = route
		_refresh(route)
	_terrain_dirty = true

func _material_rows(route: Dictionary) -> Array:
	var names: Array[String] = []
	var total := 0.0
	for id: String in route.get("materials", []):
		var label := CraftMaterials.material_name(id)
		if label not in names: names.append(label)
		total += float(CraftMaterials.appeal(definition, id).total)
	return [["Materials", ", ".join(names)], ["Appeal", str(total)]] if not names.is_empty() else []
