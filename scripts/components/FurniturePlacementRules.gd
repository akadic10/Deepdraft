extends RefCounted

## Placement rules for FurniturePlacementController (doc 258 step 8): whether a
## floor, wall, fence, plant or water-stone piece may stand at an origin, and
## the footprint, wall-mount and visual-bounds geometry those checks share.
## The controller keeps the tool state (key, yaw, hover, the reason shown) and
## the piece tables; this helper reads the shared tables it is handed and asks
## the controller's public lookups for everything else.

const WallMount = preload("res://scripts/components/WallFurnitureMount.gd")
const GridFence = preload("res://scripts/components/GridFence.gd")
const WORLD_EDGE_MARGIN := 2

var controller
var fences
var ghosts: Dictionary              # ghost_id -> FurnitureGhostComponent
var installed: Dictionary           # id -> InstalledFurnitureComponent
var cell_to_ghost: Dictionary       # Vector3i -> ghost_id
var cell_to_installed: Dictionary   # Vector3i -> installed id
var wall_to_ghost: Dictionary       # Vector4i(placement reference x,y,z,yaw) -> ghost id
var wall_to_installed: Dictionary   # separate from floor reservations
var _model_bounds: Dictionary = {}  # model path -> cached root-local visual AABB


func _init(owner_controller, fence_grid, tables: Dictionary) -> void:
	controller = owner_controller
	fences = fence_grid
	ghosts = tables.ghosts
	installed = tables.installed
	cell_to_ghost = tables.cell_to_ghost
	cell_to_installed = tables.cell_to_installed
	wall_to_ghost = tables.wall_to_ghost
	wall_to_installed = tables.wall_to_installed


## Saved origins stay minimum-corner floor cells. Centered placement only
## converts the cursor's tile to that origin; models still use world_pos.
static func cursor_origin(def: Dictionary, cell: Vector3i, yaw: int) -> Vector3i:
	if String(def.get("placement_anchor", "corner")) != "center":
		return cell
	var fp: Dictionary = def.get("footprint", {})
	var w := int(fp.get("width", 1))
	var d := int(fp.get("depth", 1))
	if yaw % 2 == 1:
		var t := w
		w = d
		d = t
	return cell - Vector3i(floori(float(w) * .5), 0, floori(float(d) * .5))


func floor_placement_reason(def: Dictionary, origin: Vector3i, yaw: int,
		moving_water_stone: String, moving_shrub: String) -> String:
	var bridges: Node3D = controller.get_bridges()
	var ladders: Node3D = controller.get_ladders()
	if GridFence.applies(def): return fences.placement_reason(def,origin,yaw)
	if fences.reserves(visual_bounds(def,origin,yaw)): return "overlap"
	if is_instance_valid(bridges) and bridges.reserves(visual_bounds(def,origin,yaw)): return "overlap"
	if def.has("water_stone"):
		if cell_to_ghost.has(origin) or cell_to_installed.has(origin): return "overlap"
		if is_instance_valid(ladders) and ladders.reserves(visual_bounds(def,origin,yaw)): return "overlap"
		if intersects_wall_piece(visual_bounds(def,origin,yaw)): return "overlap"
		var zones: Node = controller.get_tree().get_first_node_in_group("stockpile_controller")
		if zones != null and zones.is_zone_cell(origin): return "overlap"
		if not piece_visible(def,origin,yaw,controller.get_slice_y()): return "slice"
		var stones: Node = controller.get_tree().get_first_node_in_group("water_stones")
		return stones.placement_reason(origin,moving_water_stone) if stones != null else "cell"
	if is_instance_valid(ladders) and ladders.reserves(visual_bounds(def, origin, yaw)):
		return "overlap"
	if not piece_visible(def, origin, yaw, controller.get_slice_y()):
		return "slice"
	for cell: Vector3i in footprint_cells(def, origin, yaw):
		if not is_valid_cell(cell):
			return "cell"
	if String(def.get("placement", "floor")) == "floor_wall" and not has_wall_behind(def, origin, yaw):
		return "wall"
	if (not wall_to_ghost.is_empty() or not wall_to_installed.is_empty()) \
			and intersects_wall_piece(visual_bounds(def, origin, yaw)):
		return "overlap"
	if bool(def.get("plant", false)):
		var plants: Node = controller.get_tree().get_first_node_in_group("surface_details")
		return plants.planting_reason(String(def.plant_definition), origin, moving_shrub) if plants != null else "plant_soil"
	return controller.get_seating().placement_reason(def, origin, yaw)


static func wall_key(origin: Vector3i, yaw: int) -> Vector4i:
	return Vector4i(origin.x, origin.y, origin.z, posmod(yaw, 4))


static func bounds_cells(bounds: AABB) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	var low := bounds.position + Vector3.ONE * .0001
	var high := bounds.end - Vector3.ONE * .0001
	for x in range(floori(low.x), ceili(high.x)):
		for y in range(floori(low.y), ceili(high.y)):
			for z in range(floori(low.z), ceili(high.z)):
				result.append(Vector3i(x, y, z))
	return result


func wall_structure_valid(def: Dictionary, origin: Vector3i, yaw: int) -> bool:
	return wall_structure_reason(def,origin,yaw).is_empty()


func wall_structure_reason(def: Dictionary, origin: Vector3i, yaw: int) -> String:
	var mount_cell: Vector3i = WallMount.mount_cell(def,origin)
	if origin.x < WORLD_EDGE_MARGIN or origin.x >= WorldData.WORLD_SIZE_X - WORLD_EDGE_MARGIN \
			or origin.z < WORLD_EDGE_MARGIN or origin.z >= WorldData.WORLD_SIZE_Z - WORLD_EDGE_MARGIN \
			or mount_cell.y <= 3 or mount_cell.y >= WorldData.WORLD_SIZE_Y:
		return "wall_support"
	for support: Vector3i in WallMount.supports(def, origin, yaw):
		if not BlockRegistry.is_solid(controller.terrain_block_id(support.x, support.y, support.z)):
			return "wall_support"
	for cell: Vector3i in bounds_cells(WallMount.bounds_for(def, origin, yaw)):
		if cell.y >= WorldData.WORLD_SIZE_Y or controller.terrain_block_id(cell.x, cell.y, cell.z) != BlockRegistry.AIR_ID \
				or InteriorTracker.is_hidden_cave(cell):
			return "wall_clearance"
	return ""


## Why a wall-mounted piece may not go here, or "" when it may.
func wall_placement_reason(def: Dictionary, origin: Vector3i, yaw: int) -> String:
	var bridges: Node3D = controller.get_bridges()
	var ladders: Node3D = controller.get_ladders()
	if is_instance_valid(bridges) and bridges.reserves(visual_bounds(def,origin,yaw)):
		return "overlap"
	if is_instance_valid(ladders) and ladders.reserves(visual_bounds(def, origin, yaw)):
		return "overlap"
	var reason := wall_structure_reason(def,origin,yaw)
	if not reason.is_empty():
		return reason
	if not piece_visible(def, origin, yaw, controller.get_slice_y()):
		return "slice"
	var key := wall_key(origin, yaw)
	var bounds: AABB = WallMount.bounds_for(def, origin, yaw)
	if wall_to_ghost.has(key) or wall_to_installed.has(key) or intersects_wall_piece(bounds):
		return "overlap"
	for cell: Vector3i in bounds_cells(bounds):
		if PlacedEntityRegistry.occupies(cell):
			return "overlap"
	for ghost: FurnitureGhostComponent in ghosts.values():
		if WallMount.is_wall(ghost.def):
			continue
		if bounds.intersects(visual_bounds(ghost.def, ghost.origin_cell, ghost.yaw_steps)):
			return "overlap"
	for piece: InstalledFurnitureComponent in installed.values():
		if not WallMount.is_wall(piece.def) and bounds.intersects(visual_bounds(piece.def, piece.origin_cell, piece.yaw_steps)):
			return "overlap"
	var seat_reason: String = controller.get_seating().placement_reason(def, origin, yaw)
	if not seat_reason.is_empty():
		return seat_reason
	if WallMount.work_stands(def,origin,yaw).is_empty():
		return "access"
	return ""


## Visual overlap is separate from NavGrid occupancy: a four-high door is
## walkable but still cannot pass through an elevated torch. Cache per asset.
func visual_bounds(def: Dictionary, origin: Vector3i, yaw: int) -> AABB:
	if GridFence.applies(def): return fences.bounds_for(def,origin,yaw)
	var path := String(def.get("model", ""))
	if bool(def.get("plant", false)):
		path = SurfaceDetailRegistry.place_model(def, WorldClock.season)
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
	return Transform3D(Basis(Vector3.UP, float(yaw)*PI*.5), world_pos(def, origin, yaw)) * (_model_bounds[path] as AABB)


static func _collect_mesh_bounds(node: Node, parent_transform: Transform3D, boxes: Array[AABB]) -> void:
	if preload("res://scripts/components/VoxelShadowSetup.gd").is_proxy(node): return
	var mesh_transform := parent_transform
	if node is Node3D:
		mesh_transform = parent_transform * (node as Node3D).transform
	if node is MeshInstance3D:
		boxes.append(mesh_transform * (node as MeshInstance3D).get_aabb())
	for child in node.get_children():
		_collect_mesh_bounds(child, mesh_transform, boxes)


func intersects_wall_piece(bounds: AABB) -> bool:
	for id: int in wall_to_ghost.values():
		var ghost: FurnitureGhostComponent = ghosts[id]
		if bounds.intersects(WallMount.bounds_for(ghost.def, ghost.origin_cell, ghost.yaw_steps).grow(-.0001)):
			return true
	for id: int in wall_to_installed.values():
		var piece: InstalledFurnitureComponent = installed[id]
		if bounds.intersects(WallMount.bounds_for(piece.def, piece.origin_cell, piece.yaw_steps).grow(-.0001)):
			return true
	return false


## The mount never moves with the floor. A temporarily inaccessible plan waits
## for a usable work position; the final build rechecks both reach and support.
func wall_work_support_valid(def: Dictionary, origin: Vector3i, yaw: int) -> bool:
	return wall_structure_valid(def, origin, yaw) and not WallMount.work_stands(def,origin,yaw).is_empty()


func is_valid_cell(cell: Vector3i) -> bool:
	if cell.x < WORLD_EDGE_MARGIN or cell.x >= WorldData.WORLD_SIZE_X - WORLD_EDGE_MARGIN \
			or cell.z < WORLD_EDGE_MARGIN or cell.z >= WorldData.WORLD_SIZE_Z - WORLD_EDGE_MARGIN:
		return false
	if cell.y <= 3:
		return false
	var col := Vector2i(cell.x, cell.z)
	if WorldGenerator.lake_columns.has(col) or WorldGenerator.tarn_columns.has(col):
		return false
	if cell_to_ghost.has(cell) or cell_to_installed.has(cell):
		return false
	# Zones and furniture never overlap (mutual — the zone tool checks us too).
	var zone_controller: Node = controller.get_tree().get_first_node_in_group("stockpile_controller")
	if zone_controller != null and zone_controller.has_method("is_zone_cell") \
			and bool(zone_controller.call("is_zone_cell", cell)):
		return false
	# A cave not yet found is rock to every tool: nothing stands in it (Hard Rule 11).
	if InteriorTracker.is_hidden_cave(cell + Vector3i.UP):
		return false
	# Walkable = solid floor + 3-air clearance + no entity footprint (NavGrid).
	return NavGrid.is_walkable(cell)


## floor_wall pieces (the shelf): every BACK-row cell needs a solid block
## directly behind the back face at standing height. Back = local -Z rotated
## by yaw (yaw 0 backs onto north/-Z).
func has_wall_behind(def: Dictionary, origin: Vector3i, yaw: int) -> bool:
	var back: Vector3i = [Vector3i(0,0,-1), Vector3i(-1,0,0), Vector3i(0,0,1), Vector3i(1,0,0)][posmod(yaw,4)]
	for cell: Vector3i in footprint_cells(def, origin, yaw):
		var wall := cell + back
		if not BlockRegistry.is_solid(controller.terrain_block_id(wall.x, wall.y + 1, wall.z)):
			return false
	return true


static func footprint_cells(def: Dictionary, origin: Vector3i, yaw: int) -> Array[Vector3i]:
	if GridFence.applies(def): return []
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


## Convert footprint-local regions to grid occupancy. Quarter-turn formulas
## avoid floating-point drift at cell edges and match positive Godot Y rotation.
## Round outward only after rotation so thin headboards and raised bedding
## cover every touched cell without losing their offset within the footprint.
static func region_occupancy_box(def: Dictionary, region: Dictionary, origin: Vector3i, yaw: int) -> Dictionary:
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


## Node position for a footprint: the footprint centre on the floor top
## (models are authored centred on X=Z=0 with base at Y=0).
static func world_pos(def: Dictionary, origin: Vector3i, yaw: int) -> Vector3:
	if GridFence.applies(def): return GridFence.position(def,origin,yaw)
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


## Slice culling (doc 11 Phase 5 hook).
static func piece_visible(def: Dictionary, origin: Vector3i, yaw: int, slice_y: int) -> bool:
	# Keep the local emitter below the cut plane, where the visible terrain
	# still encloses it. Otherwise it would shine over a sliced-away wall.
	if WallMount.is_wall(def):
		return ceili(WallMount.bounds_for(def, origin, yaw).end.y - .0001) - 1 <= slice_y
	return floori(world_pos(def, origin, yaw).y + .0001) <= slice_y
