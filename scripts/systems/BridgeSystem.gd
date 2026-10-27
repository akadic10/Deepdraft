extends Node3D

## Scene-owned access structures. Terrain and water never contain bridge blocks.
## One kit becomes a complete deck; workers can construct from either bank.
const KEY := "base:furniture:log_bridge"
const BuildSource = preload("res://scripts/components/BridgeBuildComponent.gd")
const RemoveSource = preload("res://scripts/components/BridgeRemovalComponent.gd")
var definition: Dictionary
var routes: Dictionary = {}
var work := preload("res://scripts/components/WorkSourceTable.gd").new() # route id -> kit source
var _next_id := 1
var _tick := 0.0
var _terrain_dirty := false
var _picking := preload("res://scripts/components/ObjectPicking.gd").new()

func _ready() -> void:
	add_to_group("bridges")
	add_to_group("object_explorer_provider")
	add_to_group(SaveManager.OWNER_GROUP)
	definition = get_parent().get_defs()[KEY]
	WorldData.chunk_dirtied.connect(func(_x: int, _y: int, _z: int): _terrain_dirty = true)
	WaterManager.levels_changed.connect(func(_cells: Array): _terrain_dirty = true)
	PlacedEntityRegistry.occupancy_changed.connect(func(_lo: Vector3i, _size: Vector3i): _terrain_dirty = true)

func _exit_tree() -> void:
	for route: Dictionary in routes.values():
		_retire(route, true)
		NavGrid.remove_bridge(route.id)
		for handle: int in route.handles: PlacedEntityRegistry.unregister(handle)

func facing(yaw: int) -> Vector3i:
	return [Vector3i.FORWARD, Vector3i.LEFT, Vector3i.BACK, Vector3i.RIGHT][posmod(yaw,4)]

func side(yaw: int) -> Vector3i:
	var dir := facing(yaw)
	return Vector3i(-dir.z,0,dir.x)

func cells(route: Dictionary, banks := true) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	for step in range(0 if banks else 1, int(route.span) + (2 if banks else 1)):
		for lane in int(definition.bridge.width):
			result.append(route.base + facing(route.yaw)*step + side(route.yaw)*lane)
	return result

func landings(route: Dictionary, near_only := false) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	for lane in int(definition.bridge.width):
		result.append(route.base + side(route.yaw)*lane)
		if not near_only: result.append(route.base + facing(route.yaw)*(int(route.span)+1) + side(route.yaw)*lane)
	return result

func _bounds(route: Dictionary, clearance := false) -> AABB:
	var lo: Vector3i = route.base
	var hi := lo
	for cell: Vector3i in cells(route):
		lo = Vector3i(mini(lo.x,cell.x),lo.y,mini(lo.z,cell.z))
		hi = Vector3i(maxi(hi.x,cell.x),hi.y,maxi(hi.z,cell.z))
	return AABB(Vector3(lo)+Vector3(0,.375,0), Vector3(hi-lo)+Vector3(1,3.625 if clearance else .625,1))

func reserves(area: AABB) -> bool:
	for route: Dictionary in routes.values():
		if _bounds(route,true).intersects(area): return true
	return false

## Furniture's terrain ray can hit the bank wall or the submerged riverbed.
## Lift wall hits to the lip, and resolve wet hits to the nearest bank within
## one possible span. Either landing tile can be under the cursor. All resulting
## candidates still go through describe(), including obstruction/height checks.
func from_hit(hit: Dictionary, preferred_yaw: int) -> Dictionary:
	if hit.is_empty(): return {}
	var aimed := Vector3i(hit.x,hit.y,hit.z)
	var top := _bank_top(aimed)
	if top.x < 0: return describe(aimed,preferred_yaw)
	var banks: Array[Vector3i] = []
	if _wet(top+Vector3i.UP):
		for yaw in range(4):
			for distance in range(1,int(definition.bridge.max_span)+2):
				var bank := _bank_top(aimed+facing(yaw)*distance)
				if bank.x >= 0 and not _wet(bank+Vector3i.UP):
					banks.append(bank)
					break
		banks.sort_custom(func(a: Vector3i, b: Vector3i): return aimed.distance_squared_to(a)<aimed.distance_squared_to(b))
	else:
		banks.append(top)
	var best := describe(top,preferred_yaw)
	var best_score := -1
	for bank: Vector3i in banks:
		for turn in range(4):
			var yaw := posmod(preferred_yaw+turn,4)
			for lane in int(definition.bridge.width):
				var base := bank-side(yaw)*lane
				var spec := describe(base,yaw)
				if String(spec.reason).is_empty(): return spec
				# Keep the useful rejection across the water, rather than the
				# last attempted orientation that happened to point inland.
				var score := int(spec.span)*10
				if _solid(base) and not _solid(base+facing(yaw)): score += 1
				if score > best_score:
					best = spec
					best_score = score
	return best

func _bank_top(cell: Vector3i) -> Vector3i:
	if not _solid(cell): return Vector3i(-1,-1,-1)
	var top := cell
	while top.y < mini(get_parent().get_slice_y(),WorldData.WORLD_SIZE_Y-1) and _solid(top+Vector3i.UP):
		top.y += 1
	return top

func _wet(cell: Vector3i) -> bool:
	return WaterManager.has_standing_water(cell) or get_parent().terrain_block_id(cell.x,cell.y,cell.z)==BlockRegistry.get_id("base:terrain:water:source")

## Hover on either bank. Both lanes must encounter
## their first opposite solid floor at exactly the same distance and elevation.
func describe(base: Vector3i, yaw: int, ignore := -1, require_water := true) -> Dictionary:
	var result := {"base":base, "yaw":yaw, "span":0, "reason":"Aim at the riverbank edge; the bridge aligns across the water"}
	for lane in int(definition.bridge.width):
		var bank := base + side(yaw)*lane
		if not _solid(bank):
			result.reason = "Both landing tiles need solid ground at the same height"
			return result
		if not NavGrid.clear_for_climbing(bank):
			result.reason = "Clear the landing: needs three empty blocks above each bank tile"
			return result
	var max_span := int(definition.bridge.max_span)
	for step in range(1,max_span+2):
		var solid_count := 0
		for lane in int(definition.bridge.width):
			var cell := base + facing(yaw)*step + side(yaw)*lane
			if _solid(cell): solid_count += 1
			if not NavGrid.clear_for_climbing(cell):
				result.reason = "Banks must be the same height, with three clear blocks above the deck"
				return result
		if solid_count > 0:
			if solid_count != int(definition.bridge.width):
				result.reason = "Both sides of the two-block deck need an opposite bank at the same distance"
				return result
			if step == 1:
				result.reason = "Move to the riverbank edge so the bridge points over water"
				return result
			result.span = step-1
			break
		if step > max_span: break
		if require_water:
			for lane in int(definition.bridge.width):
				if not _water_below(base+facing(yaw)*step+side(yaw)*lane):
					result.reason = "Needs water below the gap and solid, matching-height banks"
					return result
	if int(result.span) == 0:
		result.reason = "Opposite bank is too far or too low — maximum gap %d blocks" % max_span
		return result
	var area := _bounds(result,true)
	var excluded: Array[int] = []
	if routes.has(ignore): excluded.assign(routes[ignore].handles)
	for cell: Vector3i in cells(result):
		if PlacedEntityRegistry.occupies(cell,excluded):
			result.reason = "Clear trees, stones and structures from the crossing first"
			return result
	for id: int in routes:
		if id != ignore and _bounds(routes[id],true).intersects(area):
			result.reason = "Another bridge or bridge plan occupies this crossing"
			return result
	var parent := get_parent()
	if parent.get_ladders().reserves(area):
		result.reason = "Keep the crossing clear of ladders"
		return result
	for group: Array in [parent.get_ghost_pieces(),parent.get_installed_pieces()]:
		for piece in group:
			if parent.visual_bounds(piece.def,piece.origin_cell,piece.yaw_steps).intersects(area):
				result.reason = "Clear furniture and queued placements from the crossing first"
				return result
	for zone: StockpileZoneComponent in StockpileManager.get_zones():
		for cell: Vector3i in zone.tile_cells:
			if area.intersects(AABB(Vector3(cell)+Vector3.UP,Vector3.ONE)):
				result.reason = "Keep both bridge landings clear of storage zones"
				return result
	var plants := get_tree().get_first_node_in_group("surface_details")
	if plants != null:
		for cell: Vector3i in cells(result):
			for dx in range(-1,2):
				for dz in range(-1,2):
					for id: String in plants.ids_in_column(Vector2i(cell.x+dx,cell.z+dz)):
						if bool(plants.get_change(id).get("removed",false)): continue
						var record: Dictionary = plants.get_record(id)
						var plant := SurfaceDetailRegistry.get_definition(record.definition)
						if area.intersects(preload("res://scripts/components/SurfaceDetailPlacement.gd").planting_area(plant,record.origin)):
							result.reason = "Clear or move plants and stones from the landings first"
							return result
	result.reason = ""
	return result

func _solid(cell: Vector3i) -> bool:
	return BlockRegistry.is_solid(get_parent().terrain_block_id(cell.x,cell.y,cell.z))

func _water_below(cell: Vector3i) -> bool:
	for y in range(cell.y,0,-1):
		var probe := Vector3i(cell.x,y,cell.z)
		if WaterManager.has_standing_water(probe) or get_parent().terrain_block_id(probe.x,probe.y,probe.z) == BlockRegistry.get_id("base:terrain:water:source"): return true
		if _solid(probe): return false
	return false

func placement_reason(base: Vector3i, yaw: int) -> String:
	var spec := describe(base,yaw)
	if not String(spec.reason).is_empty(): return spec.reason
	if base.y+1 > get_parent().get_slice_y(): return "Raise the slice to show both bridge landings"
	if get_parent().placement_available(KEY) < 1: return "Craft a log bridge kit at the crude workbench first"
	return ""

func place(base: Vector3i, yaw: int) -> int:
	if not placement_reason(base,yaw).is_empty(): return -1
	var spec := describe(base,yaw)
	var id := _next_id
	_next_id += 1
	var route := {"id":id,"base":base,"yaw":yaw,"span":int(spec.span),"built":false,
		"required_material_id":String(get_parent().material_choices.get(KEY, "")),"mode":"build","progress":0.0,"node":null,"handles":[],"material_id":""}
	routes[id] = route
	_refresh(route)
	return id

func pending_kits() -> Dictionary:
	var pending := 0
	var requested := 0
	for route: Dictionary in routes.values():
		if route.mode != "build": continue
		requested += 1
		var source = work.get_source(route.id)
		if source == null or not source.has_committed_item(): pending += 1
	return {"pending":pending,"requested":requested}

func _process(delta: float) -> void:
	_tick += delta
	if _tick < .25: return
	_tick = 0.0
	var check := _terrain_dirty
	_terrain_dirty = false
	for route: Dictionary in routes.values().duplicate():
		if check and route.mode != "damaged":
			var spec := describe(route.base,route.yaw,route.id,false)
			if not String(spec.reason).is_empty() or spec.span != route.span:
				_retire(route,true)
				if not route.built: _erase(route); continue
				route.mode = "damaged"
				_register(route)
		if route.mode == "damaged":
			if _safe_to_remove(route): _recover(route)
			continue
		if not work.has(route.id): _make_source(route)
		var source = work.get_source(route.id)
		if source is FurnitureGhostComponent: source.update_lease()
		if is_instance_valid(route.node): route.node.visible = route.base.y+1 <= get_parent().get_slice_y()

func _make_source(route: Dictionary) -> void:
	var drops := ItemDropManager.find(get_tree())
	if drops == null: return
	var source: RefCounted
	if route.mode == "build":
		source = BuildSource.new()
		source.setup(route.id,KEY,definition,route.base,route.yaw)
		# Preview orientation does not choose the builder's bank. A plan aimed
		# from across the river must also be deliverable from the colony side.
		source.stands = landings(route)
		source.drop_manager = drops
		source.required_material_id = String(route.get("required_material_id", ""))
		source.build_valid_callback = func(_s): return routes.has(route.id) and route.mode == "build" and String(describe(route.base,route.yaw,route.id,false).reason).is_empty()
		source.install_callback = func(_s): _installed(route)
	elif route.mode == "remove":
		source = RemoveSource.new()
		source.setup(route.id,KEY,definition,route.base,route.yaw)
		source.stands = landings(route)
		source.safe_callback = func(): return _safe_to_remove(route)
		source.uninstall_callback = func(_s, _worker_id): _recover(route)
	else: return
	source.progress = route.progress
	work.add(route.id,source)
	if source is FurnitureGhostComponent: source.update_lease()
	else: source.set_uninstall(true)

func _installed(route: Dictionary) -> void:
	route.material_id = work.get_source(route.id).material_id
	_retire(route,false)
	route.built = true
	route.mode = "ready"
	route.progress = 0.0
	_refresh(route)

func _recover(route: Dictionary) -> void:
	var bank: Vector3i = route.base
	for cell: Vector3i in landings(route):
		if _solid(cell) and NavGrid.is_walkable(cell): bank = cell; break
	_retire(route,false)
	ItemDropManager.find(get_tree()).spawn_drop(definition.item_key,1,bank+Vector3i.UP,String(route.get("material_id", "")))
	_erase(route)

func _safe_to_remove(route: Dictionary) -> bool:
	for agent in TaskManager.get_agents():
		if not is_instance_valid(agent): continue
		for cell: Vector3i in cells(route,false):
			if AABB(Vector3(cell)+Vector3(-.3,.5,-.3),Vector3(1.6,4,1.6)).has_point(agent.global_position): return false
	return true

func _retire(route: Dictionary, cancel: bool) -> void:
	var source = work.get_source(route.id)
	if source == null: return
	route.progress = source.progress
	work.retire(route.id,cancel)

func _register(route: Dictionary) -> void:
	if not route.built: return
	if route.handles.is_empty():
		for cell: Vector3i in cells(route,false): route.handles.append(PlacedEntityRegistry.register_box(cell,Vector3i.ONE))
	NavGrid.set_bridge(route.id,cells(route,false),landings(route),route.mode in ["remove","damaged"])

func _refresh(route: Dictionary) -> void:
	_register(route)
	if is_instance_valid(route.node): route.node.queue_free()
	route.node = make_visual(route.span, null if route.built else get_parent().make_ghost_material())
	add_child(route.node)
	if route.built: CraftMaterials.apply_palette(route.node, definition, String(route.get("material_id", "")))
	route.node.position = Vector3(route.base)+Vector3(.5,1,.5)
	route.node.rotation.y = route.yaw*PI*.5
	preload("res://scripts/components/UndergroundLighting.gd").bind_world_tree(route.node)
	_make_source(route)
	get_parent().mark_catalog_dirty()

func make_visual(span: int, material: Material = null) -> Node3D:
	var path := String(definition.model).get_base_dir().path_join("log_bridge_%d.glb" % clampi(span,1,int(definition.bridge.max_span)))
	var model: Node3D = load(path).instantiate()
	preload("res://scripts/components/VoxelShadowSetup.gd").set_casting(model,not (material is BaseMaterial3D and material.transparency!=BaseMaterial3D.TRANSPARENCY_DISABLED))
	get_parent().apply_material(model,material if material != null else get_parent().make_solid_material())
	return model

func _erase(route: Dictionary) -> void:
	_retire(route,true)
	NavGrid.remove_bridge(route.id)
	for handle: int in route.handles: PlacedEntityRegistry.unregister(handle)
	if is_instance_valid(route.node): route.node.queue_free()
	routes.erase(route.id)
	var drops := ItemDropManager.find(get_tree())
	if drops != null and route.built: drops.bridge_support_removed(cells(route,false))
	get_parent().mark_catalog_dirty()

func pick_explorer_object(start: Vector3, end: Vector3) -> Dictionary:
	var result := {}
	var nearest := start.distance_to(end)
	for route: Dictionary in routes.values():
		if not is_instance_valid(route.node) or not route.node.is_visible_in_tree(): continue
		var distance: float = _picking.hit_distance(route.node,start,end)
		if distance < nearest:
			nearest = distance
			result = {"id":route.id,"distance":distance}
	return result

func get_explorer_bounds(id: Variant) -> AABB:
	return _bounds(routes[int(id)]) if routes.has(int(id)) else AABB()

func get_explorer_data(id: Variant) -> Dictionary:
	var route: Dictionary = routes.get(int(id),{})
	if route.is_empty(): return {}
	var status := {"build":"Awaiting kit / installing from this bank","ready":"Open for walking and hauling",
		"remove":"Closed — waiting for walkers, then dismantling","damaged":"Support damaged — waiting for walkers to leave"}
	var actions: Array = []
	if route.mode == "build": actions.append({"id":"cancel","text":"Cancel placement"})
	if route.mode == "ready": actions.append({"id":"remove","text":"Dismantle and recover kit"})
	if route.mode == "remove": actions.append({"id":"reopen","text":"Cancel dismantling"})
	# The compact panel (doc 260): the bridge's picture and its state.
	return {"title":CraftMaterials.product_name("Log bridge", String(route.get("material_id", ""))),
		"family":"settlement", "picture":"res://assets/ui/furniture/log_bridge.png",
		"status":{"text":status[route.mode], "tone":{"build":"waiting","ready":"fine","remove":"waiting","damaged":"blocked"}[route.mode]},
		"rows":[["Status",status[route.mode]],
		["Crossing","2 wide · %d-block gap" % route.span],["Kit","Installed" if route.built else "1 reserved"]] + (CraftMaterials.inspection_rows(definition, String(route.get("material_id", ""))) if route.built else []),
		"details":"Built from the selected bank. Water flows underneath. Dismantling closes entry and waits for the deck to clear.","actions":actions}

func perform_explorer_action(id: Variant, action: String) -> void:
	var route: Dictionary = routes.get(int(id),{})
	if route.is_empty(): return
	if action == "cancel" and route.mode == "build": _erase(route); return
	if not (action == "remove" and route.mode == "ready" or action == "reopen" and route.mode == "remove"): return
	_retire(route,true)
	route.mode = "remove" if action == "remove" else "ready"
	route.progress = 0.0
	_refresh(route)

func save_section_key() -> String: return "bridges"
func save_restore_priority() -> int: return 42

func serialize_state() -> Dictionary:
	var entries: Array = []
	for route: Dictionary in routes.values():
		entries.append({"id":route.id,"key":KEY,"base":SaveManager.pack_v3i(route.base),"yaw":route.yaw,
			"span":route.span,"built":route.built,"material_id":String(route.get("material_id", "")),"required_material_id":String(route.get("required_material_id", "")),"mode":route.mode,"progress":work.get_source(route.id).progress if work.has(route.id) else route.progress})
	return {"routes":entries,"next_id":_next_id}

func restore_state(state: Dictionary) -> void:
	for route: Dictionary in routes.values().duplicate(): _erase(route)
	_next_id = maxi(1,int(state.get("next_id",1)))
	for entry: Dictionary in state.get("routes",[]):
		var route := entry.duplicate(true)
		route.base = SaveManager.unpack_v3i(entry.base)
		for key in ["id","yaw","span"]: route[key] = int(route[key])
		route.node = null
		route.handles = []
		routes[route.id] = route
		_refresh(route)
	_terrain_dirty = true
