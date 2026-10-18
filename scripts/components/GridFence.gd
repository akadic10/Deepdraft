extends RefCounted

## Scene-owned corner posts and derived rails. Plans reserve geometry but do
## not block routes. Only finished posts create physical connecting rails.
var controller: Node3D
var links: Dictionary = {}
var post_handles: Dictionary = {}
var suspended := false
var _cached_pieces: Array = []
var _cached_vertices: Dictionary = {}
var _gate_segments: Dictionary = {}

func _init(owner: Node3D) -> void:
	controller = owner

static func applies(def: Dictionary) -> bool:
	return def.has("grid_fence")

static func is_post(def: Dictionary) -> bool:
	return def.get("grid_fence",{}).get("kind","") == "post"

static func ends(def: Dictionary, origin: Vector3i, yaw: int) -> Array[Vector3i]:
	var result: Array[Vector3i] = [origin]
	if not is_post(def):
		var span := int(def.grid_fence.span)
		result.append(origin+(Vector3i(span,0,0) if yaw%2==0 else Vector3i(0,0,span)))
	return result

static func position(def: Dictionary, origin: Vector3i, yaw: int) -> Vector3:
	var points := ends(def,origin,yaw)
	return (Vector3(points[0])+Vector3(points[-1]))*.5+Vector3.UP

static func support_cells(def: Dictionary, origin: Vector3i, yaw: int) -> Array[Vector3i]:
	var points := ends(def,origin,yaw)
	var result: Array[Vector3i] = []
	for x in range(points[0].x-1,points[-1].x+1):
		for z in range(points[0].z-1,points[-1].z+1): result.append(Vector3i(x,origin.y,z))
	return result

static func work_stands(def: Dictionary, origin: Vector3i, yaw: int) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	for cell in support_cells(def,origin,yaw):
		if NavGrid.is_walkable(cell): result.append(cell)
	return result

static func nearest_stand(def: Dictionary, origin: Vector3i, yaw: int, from: Vector3i) -> Vector3i:
	var best := Vector3i(-1,-1,-1)
	var distance := INF
	for cell in work_stands(def,origin,yaw):
		var d := Vector3(cell-from).length_squared()
		if d < distance: best = cell; distance = d
	return best

static func post_box(def: Dictionary, vertex: Vector3i) -> AABB:
	var r := float(def.grid_fence.post_radius)
	return AABB(Vector3(vertex)+Vector3(-r,1,-r),Vector3(2*r,float(def.grid_fence.height),2*r))

static func rail_box(a: Vector3i, b: Vector3i) -> AABB:
	return AABB(Vector3(a.min(b))+Vector3(-.1,1,-.1),Vector3((b-a).abs())+Vector3(.2,1.1,.2))

func _pieces() -> Array:
	return _cached_pieces

func _refresh_index() -> void:
	_cached_pieces.clear()
	_cached_vertices.clear()
	_gate_segments.clear()
	for pieces: Dictionary in [controller._installed,controller._ghosts]:
		for piece in pieces.values():
			if not applies(piece.def): continue
			_cached_pieces.append(piece)
			if is_post(piece.def): continue
			var axis := Vector3i.RIGHT if piece.yaw_steps%2==0 else Vector3i.BACK
			for i in int(piece.def.grid_fence.span):
				var a: Vector3i = piece.origin_cell+axis*i
				_gate_segments[_edge_key(a,a+axis)] = piece
	_cached_vertices = _collect_vertices()

func _vertices() -> Dictionary:
	return _cached_vertices

func _collect_vertices() -> Dictionary:
	var result := {}
	# A separately built post owns the shared visual before a gate end post.
	for solid in [true,false]:
		var pieces: Dictionary = controller._installed if solid else controller._ghosts
		for posts in [true,false]:
			for piece in pieces.values():
				if not applies(piece.def) or is_post(piece.def) != posts: continue
				var points := ends(piece.def,piece.origin_cell,piece.yaw_steps)
				for i in points.size():
					if not result.has(points[i]):
						var mesh_name := "post" if posts else "post_left" if (i==0)==(piece.yaw_steps%4 in [0,3]) else "post_right"
						result[points[i]] = {"piece":piece,"solid":solid,"mesh":mesh_name}
	return result

func _gate_covers(a: Vector3i, b: Vector3i, skip = null) -> bool:
	var key := _edge_key(a,b)
	return _gate_segments.has(key) and _gate_segments[key]!=skip

static func _edge_key(a: Vector3i, b: Vector3i) -> Vector4i:
	var low := a.min(b)
	return Vector4i(low.x,low.y,low.z,0 if a.z==b.z else 1)

func obstacles(def: Dictionary, origin: Vector3i, yaw: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var vertices := _vertices()
	var points := ends(def,origin,yaw)
	for point in points:
		result.append({"bounds":post_box(def,point)})
		for offset in [Vector3i.LEFT,Vector3i.RIGHT,Vector3i.FORWARD,Vector3i.BACK]:
			if vertices.has(point+offset) and not _gate_covers(point,point+offset): result.append({"bounds":rail_box(point,point+offset)})
	if points.size()>1: result.append({"bounds":rail_box(points[0],points[-1])})
	return result

func bounds_for(def: Dictionary, origin: Vector3i, yaw: int) -> AABB:
	var result := AABB()
	for shape in obstacles(def,origin,yaw): result = shape.bounds if result.size==Vector3.ZERO else result.merge(shape.bounds)
	return result

func reserves(bounds: AABB) -> bool:
	for piece in _pieces():
		for shape in obstacles(piece.def,piece.origin_cell,piece.yaw_steps):
			if bounds.intersects(shape.bounds.grow(-.001)): return true
	return false

func support_valid(def: Dictionary, origin: Vector3i, yaw: int) -> bool:
	for cell in support_cells(def,origin,yaw):
		if cell.x<2 or cell.z<2 or cell.x>=WorldData.WORLD_SIZE_X-2 or cell.z>=WorldData.WORLD_SIZE_Z-2 or cell.y<=3: return false
		if not BlockRegistry.is_solid(controller._block_id(cell.x,cell.y,cell.z)): return false
	return true

func _space_reason(bounds: AABB, skip = null) -> String:
	var handles: Array[int] = []
	for piece in controller._installed.values(): handles.append_array(piece.occupancy_ids)
	for cell in controller._bounds_cells(bounds.grow(-.001)):
		if cell.y>=WorldData.WORLD_SIZE_Y or controller._block_id(cell.x,cell.y,cell.z)!=BlockRegistry.AIR_ID or PlacedEntityRegistry.occupies(cell,handles): return "fence_clearance"
	for pieces: Dictionary in [controller._installed,controller._ghosts]:
		for piece in pieces.values():
			if piece==skip or applies(piece.def): continue
			if bounds.intersects(controller._visual_bounds(piece.def,piece.origin_cell,piece.yaw_steps)): return "fence_clearance"
			if controller._seating.is_chair(piece.def):
				for space in controller._seating.clearance_regions(piece.def,piece.origin_cell,piece.yaw_steps):
					if controller._seating.regions_intersect(space,{"bounds":bounds}): return "seat_clearance"
	if is_instance_valid(controller._ladders) and controller._ladders.reserves(bounds): return "fence_clearance"
	if is_instance_valid(controller._bridges) and controller._bridges.reserves(bounds): return "fence_clearance"
	return ""

func placement_reason(def: Dictionary, origin: Vector3i, yaw: int, skip = null) -> String:
	if not support_valid(def,origin,yaw): return "fence_support"
	if not controller._piece_visible(def,origin,yaw): return "slice"
	var points := ends(def,origin,yaw)
	for piece in _pieces():
		if piece==skip: continue
		var other := ends(piece.def,piece.origin_cell,piece.yaw_steps)
		if is_post(def) and origin in other: return "overlap"
		# Shared gate endpoints are legal; nothing can occupy its opening.
		if other.size()>1:
			for point in points:
				if point!=other[0] and point!=other[-1] and rail_box(other[0],other[-1]).has_point(Vector3(point)+Vector3.UP*1.1): return "overlap"
		if points.size()>1:
			for point in other:
				if point!=points[0] and point!=points[-1] and rail_box(points[0],points[-1]).has_point(Vector3(point)+Vector3.UP*1.1): return "overlap"
			if other.size()>1 and points==other: return "overlap"
	for shape in obstacles(def,origin,yaw):
		var reason := _space_reason(shape.bounds,skip)
		if not reason.is_empty(): return reason
	return "" if not work_stands(def,origin,yaw).is_empty() else "fence_access"

func _rail_visual(a: Vector3i, b: Vector3i, owner, solid: bool) -> Node3D:
	var node: Node3D = load(String(controller._defs["base:furniture:log_fence"].grid_fence.rail_model)).instantiate()
	var material = controller._make_solid_material() if solid else controller._make_ghost_material()
	controller._apply_material(node,material)
	owner.node.add_child(node)
	node.global_position = (Vector3(a)+Vector3(b))*.5+Vector3.UP
	node.global_rotation = Vector3(0,0 if a.z==b.z else PI*.5,0)
	CraftMaterials.apply_palette(node,owner.def,owner.material_id if solid else owner.required_material_id)
	if solid: preload("res://scripts/components/UndergroundLighting.gd").bind_world_tree(node)
	return node

func sync() -> void:
	if suspended: return
	_refresh_index()
	var vertices := _vertices()
	for piece in _pieces():
		for name in ["post","post_left","post_right"]:
			var mesh = piece.node.find_child(name,true,false) if is_instance_valid(piece.node) else null
			if mesh!=null: mesh.visible = false
	for vertex in vertices:
		var entry: Dictionary = vertices[vertex]
		var mesh = entry.piece.node.find_child(entry.mesh,true,false)
		if mesh!=null: mesh.visible = true
		if entry.solid and not post_handles.has(vertex): post_handles[vertex] = PlacedEntityRegistry.register_barrier(post_box(entry.piece.def,vertex))
	for vertex in post_handles.keys():
		if not vertices.has(vertex) or not vertices[vertex].solid:
			PlacedEntityRegistry.unregister(post_handles[vertex]); post_handles.erase(vertex)
	var desired := {}
	for a in vertices:
		for offset in [Vector3i.RIGHT,Vector3i.BACK]:
			var b: Vector3i = a+offset
			if not vertices.has(b) or _gate_covers(a,b): continue
			var key := Vector4i(a.x,a.y,a.z,0 if offset.x else 1)
			var solid: bool = vertices[a].solid and vertices[b].solid
			var owner = vertices[a].piece
			if not solid and vertices[a].solid: owner = vertices[b].piece
			desired[key] = true
			if links.has(key) and links[key].owner==owner and links[key].solid==solid: continue
			_remove_link(key)
			links[key] = {"owner":owner,"solid":solid,"node":_rail_visual(a,b,owner,solid),"handle":PlacedEntityRegistry.register_barrier(rail_box(a,b)) if solid else -1}
	for key in links.keys():
		if not desired.has(key): _remove_link(key)

func _remove_link(key: Vector4i) -> void:
	if not links.has(key): return
	var link: Dictionary = links[key]
	if link.handle>=0: PlacedEntityRegistry.unregister(link.handle)
	if is_instance_valid(link.node): link.node.hide(); link.node.queue_free()
	links.erase(key)

func clear() -> void:
	for key in links.keys(): _remove_link(key)
	for handle in post_handles.values(): PlacedEntityRegistry.unregister(handle)
	post_handles.clear()
	_cached_pieces.clear()
	_cached_vertices.clear()
	_gate_segments.clear()

func revalidate_support() -> void:
	for piece in _pieces().duplicate():
		if support_valid(piece.def,piece.origin_cell,piece.yaw_steps): continue
		if piece is InstalledFurnitureComponent: controller._teardown_installed(piece.installed_id,true)
		else: controller.cancel_ghost(piece.ghost_id)

func preview(def: Dictionary, origin: Vector3i, yaw: int, node: Node3D, material: Material) -> void:
	for child in node.get_children():
		if child.has_meta("fence_preview"): child.hide(); child.queue_free()
	var vertices := _vertices()
	for point in ends(def,origin,yaw):
		for offset in [Vector3i.LEFT,Vector3i.RIGHT,Vector3i.FORWARD,Vector3i.BACK]:
			if not vertices.has(point+offset) or _gate_covers(point,point+offset): continue
			var rail: Node3D = load(String(controller._defs["base:furniture:log_fence"].grid_fence.rail_model)).instantiate()
			controller._apply_material(rail,material)
			node.add_child(rail)
			rail.set_meta("fence_preview",true)
			rail.global_position = Vector3(point)+Vector3(offset)*.5+Vector3.UP
			rail.global_rotation = Vector3(0,0 if offset.x else PI*.5,0)
