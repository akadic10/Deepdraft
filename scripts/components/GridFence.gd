extends RefCounted

## Scene-owned fence posts and derived rails (doc 277). A post stands in the
## middle of its tile and blocks it; a gate hangs across one open tile between
## posts on the tiles either side. Plans reserve their tiles but block no route.
## Only finished posts occupy their tiles. Rails lie inside post tiles, so they
## are looks only.
var controller: Node3D
var links: Dictionary = {}
var post_handles: Dictionary = {}
var suspended := false
var _cached_pieces: Array = []
var _cached_posts: Dictionary = {}

func _init(owner: Node3D) -> void:
	controller = owner

static func applies(def: Dictionary) -> bool:
	return def.has("grid_fence")

static func is_post(def: Dictionary) -> bool:
	return def.get("grid_fence",{}).get("kind","") == "post"

static func _axis(yaw: int) -> Vector3i:
	return Vector3i.RIGHT if yaw%2==0 else Vector3i.BACK

static func ends(def: Dictionary, origin: Vector3i, yaw: int) -> Array[Vector3i]:
	var result: Array[Vector3i] = [origin]
	if not is_post(def): result.append(origin+_axis(yaw)*int(def.grid_fence.span))
	return result

## A gate's walkable tiles between its end posts.
static func openings(def: Dictionary, origin: Vector3i, yaw: int) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	if not is_post(def):
		for i in range(1,int(def.grid_fence.span)): result.append(origin+_axis(yaw)*i)
	return result

static func tiles(def: Dictionary, origin: Vector3i, yaw: int) -> Array[Vector3i]:
	var result := ends(def,origin,yaw)
	result.append_array(openings(def,origin,yaw))
	return result

## The cursor aims at a post's tile or a gate's opening; origins stay the first end.
static func aim_origin(def: Dictionary, tile: Vector3i, yaw: int) -> Vector3i:
	return tile if is_post(def) else tile-_axis(yaw)*floori(float(def.grid_fence.span)*.5)

static func position(def: Dictionary, origin: Vector3i, yaw: int) -> Vector3:
	var points := ends(def,origin,yaw)
	return (Vector3(points[0])+Vector3(points[-1]))*.5+Vector3(.5,1,.5)

static func work_stands(def: Dictionary, origin: Vector3i, yaw: int) -> Array[Vector3i]:
	var own := tiles(def,origin,yaw)
	var result: Array[Vector3i] = []
	for tile in own:
		for offset in [Vector3i.LEFT,Vector3i.RIGHT,Vector3i.FORWARD,Vector3i.BACK]:
			var stand: Vector3i = tile+offset
			if stand not in own and stand not in result and NavGrid.is_walkable(stand): result.append(stand)
	return result

static func nearest_stand(def: Dictionary, origin: Vector3i, yaw: int, from: Vector3i) -> Vector3i:
	var best := Vector3i(-1,-1,-1)
	var distance := INF
	for cell in work_stands(def,origin,yaw):
		var d := Vector3(cell-from).length_squared()
		if d < distance: best = cell; distance = d
	return best

static func tile_box(def: Dictionary, tile: Vector3i) -> AABB:
	return AABB(Vector3(tile)+Vector3.UP,Vector3(1,float(def.grid_fence.height),1))

static func rail_box(a: Vector3i, b: Vector3i) -> AABB:
	return AABB(Vector3(a.min(b))+Vector3(.4,1,.4),Vector3((b-a).abs())+Vector3(.2,1.1,.2))

func _pieces() -> Array:
	return _cached_pieces

func _posts() -> Dictionary:
	return _cached_posts

func _refresh_index() -> void:
	_cached_pieces.clear()
	for pieces: Array in [controller.get_installed_pieces(),controller.get_ghost_pieces()]:
		for piece in pieces:
			if applies(piece.def): _cached_pieces.append(piece)
	_cached_posts = _collect_posts()

func _collect_posts() -> Dictionary:
	var result := {}
	# A separately built post owns the shared visual before a gate end post.
	for solid in [true,false]:
		var pieces: Array = controller.get_installed_pieces() if solid else controller.get_ghost_pieces()
		for posts in [true,false]:
			for piece in pieces:
				if not applies(piece.def) or is_post(piece.def) != posts: continue
				var points := ends(piece.def,piece.origin_cell,piece.yaw_steps)
				for i in points.size():
					if not result.has(points[i]):
						var mesh_name := "post" if posts else "post_left" if (i==0)==(piece.yaw_steps%4 in [0,3]) else "post_right"
						result[points[i]] = {"piece":piece,"solid":solid,"mesh":mesh_name}
	return result

func obstacles(def: Dictionary, origin: Vector3i, yaw: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for tile in tiles(def,origin,yaw): result.append({"bounds":tile_box(def,tile)})
	return result

## A gate's tiles lie in one line, so their merged box is exact.
func bounds_for(def: Dictionary, origin: Vector3i, yaw: int) -> AABB:
	var result := AABB()
	for shape in obstacles(def,origin,yaw): result = shape.bounds if result.size==Vector3.ZERO else result.merge(shape.bounds)
	return result

## Picking also reaches the rails a piece shows into its neighbours' tiles.
func pick_bounds(def: Dictionary, origin: Vector3i, yaw: int) -> AABB:
	var result := bounds_for(def,origin,yaw)
	for point in ends(def,origin,yaw):
		for offset in [Vector3i.LEFT,Vector3i.RIGHT,Vector3i.FORWARD,Vector3i.BACK]:
			if _posts().has(point+offset): result = result.merge(rail_box(point,point+offset))
	return result

func reserves(bounds: AABB) -> bool:
	for piece in _pieces():
		for shape in obstacles(piece.def,piece.origin_cell,piece.yaw_steps):
			if bounds.intersects(shape.bounds.grow(-.001)): return true
	return false

## The tiles a piece adds to the ground: a gate end on an existing post reuses it.
func new_tiles(def: Dictionary, origin: Vector3i, yaw: int) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	for tile in tiles(def,origin,yaw):
		if not _posts().has(tile): result.append(tile)
	return result

func support_valid(def: Dictionary, origin: Vector3i, yaw: int) -> bool:
	for tile in tiles(def,origin,yaw):
		if tile.x<2 or tile.z<2 or tile.x>=WorldData.WORLD_SIZE_X-2 or tile.z>=WorldData.WORLD_SIZE_Z-2 or tile.y<=3: return false
		if not BlockRegistry.is_solid(controller.terrain_block_id(tile.x,tile.y,tile.z)): return false
	return true

func _space_reason(def: Dictionary, tile: Vector3i, skip = null) -> String:
	var bounds := tile_box(def,tile).grow(-.001)
	# Tile roles settle fence against fence; furniture is checked by its bounds below.
	var handles: Array[int] = []
	handles.assign(post_handles.values())
	for piece in controller.get_installed_pieces(): handles.append_array(piece.occupancy_ids)
	for dy in range(1,ceili(bounds.end.y)-tile.y):
		var cell := tile+Vector3i.UP*dy
		if cell.y>=WorldData.WORLD_SIZE_Y or controller.terrain_block_id(cell.x,cell.y,cell.z)!=BlockRegistry.AIR_ID or PlacedEntityRegistry.occupies(cell,handles): return "fence_clearance"
	for pieces: Array in [controller.get_installed_pieces(),controller.get_ghost_pieces()]:
		for piece in pieces:
			if piece==skip or applies(piece.def): continue
			if bounds.intersects(controller.visual_bounds(piece.def,piece.origin_cell,piece.yaw_steps)): return "fence_clearance"
			if controller.get_seating().is_chair(piece.def):
				for space in controller.get_seating().clearance_regions(piece.def,piece.origin_cell,piece.yaw_steps):
					if controller.get_seating().regions_intersect(space,{"bounds":bounds}): return "seat_clearance"
	if is_instance_valid(controller.get_ladders()) and controller.get_ladders().reserves(bounds): return "fence_clearance"
	return ""

## Each tile has one role: a post, which a post and gate ends may share, or a
## gate opening, which nothing shares.
func placement_reason(def: Dictionary, origin: Vector3i, yaw: int, skip = null) -> String:
	if not support_valid(def,origin,yaw): return "fence_support"
	if not controller._piece_visible(def,origin,yaw): return "slice"
	var own := tiles(def,origin,yaw)
	var gaps := openings(def,origin,yaw)
	for piece in _pieces():
		if piece==skip: continue
		var other := ends(piece.def,piece.origin_cell,piece.yaw_steps)
		var other_gaps := openings(piece.def,piece.origin_cell,piece.yaw_steps)
		if is_post(def) and origin in other: return "overlap"
		for tile in own:
			if tile in other_gaps or (tile in gaps and tile in other): return "overlap"
	for tile in own:
		var reason := _space_reason(def,tile,skip)
		if not reason.is_empty(): return reason
	return "" if not work_stands(def,origin,yaw).is_empty() else "fence_access"

func _rail_visual(a: Vector3i, b: Vector3i, owner, solid: bool) -> Node3D:
	var node: Node3D = load(String(controller.get_defs()["base:furniture:log_fence"].grid_fence.rail_model)).instantiate()
	var material = controller.make_solid_material() if solid else controller.make_ghost_material()
	controller.apply_material(node,material)
	preload("VoxelShadowSetup.gd").set_casting(node,solid)
	owner.node.add_child(node)
	node.global_position = (Vector3(a)+Vector3(b))*.5+Vector3(.5,1,.5)
	node.global_rotation = Vector3(0,0.0 if a.z==b.z else PI*.5,0)
	CraftMaterials.apply_palette(node,owner.def,owner.material_id if solid else owner.required_material_id)
	if solid: preload("res://scripts/components/UndergroundLighting.gd").bind_world_tree(node)
	return node

func sync() -> void:
	if suspended: return
	_refresh_index()
	var posts := _posts()
	for piece in _pieces():
		for name in ["post","post_left","post_right"]:
			var mesh = piece.node.find_child(name,true,false) if is_instance_valid(piece.node) else null
			if mesh!=null: mesh.visible = false
	for tile in posts:
		var entry: Dictionary = posts[tile]
		var mesh = entry.piece.node.find_child(entry.mesh,true,false) if is_instance_valid(entry.piece.node) else null
		if mesh!=null: mesh.visible = true
		if entry.solid and not post_handles.has(tile): post_handles[tile] = PlacedEntityRegistry.register_box(tile+Vector3i.UP,Vector3i(1,ceili(float(entry.piece.def.grid_fence.height)),1))
	for tile in post_handles.keys():
		if not posts.has(tile) or not posts[tile].solid:
			PlacedEntityRegistry.unregister(post_handles[tile]); post_handles.erase(tile)
	var desired := {}
	for a in posts:
		for offset in [Vector3i.RIGHT,Vector3i.BACK]:
			var b: Vector3i = a+offset
			if not posts.has(b): continue
			var key := Vector4i(a.x,a.y,a.z,0 if offset.x else 1)
			var solid: bool = posts[a].solid and posts[b].solid
			var owner = posts[a].piece
			if not solid and posts[a].solid: owner = posts[b].piece
			desired[key] = true
			if links.has(key) and links[key].owner==owner and links[key].solid==solid: continue
			_remove_link(key)
			links[key] = {"owner":owner,"solid":solid,"node":_rail_visual(a,b,owner,solid)}
	for key in links.keys():
		if not desired.has(key): _remove_link(key)

func _remove_link(key: Vector4i) -> void:
	if not links.has(key): return
	var link: Dictionary = links[key]
	if is_instance_valid(link.node): link.node.hide(); link.node.queue_free()
	links.erase(key)

func clear() -> void:
	for key in links.keys(): _remove_link(key)
	for handle in post_handles.values(): PlacedEntityRegistry.unregister(handle)
	post_handles.clear()
	_cached_pieces.clear()
	_cached_posts.clear()

func revalidate_support() -> void:
	for piece in _pieces().duplicate():
		if support_valid(piece.def,piece.origin_cell,piece.yaw_steps): continue
		if piece is InstalledFurnitureComponent: controller._teardown_installed(piece.installed_id,true)
		else: controller.cancel_ghost(piece.ghost_id)

func preview(def: Dictionary, origin: Vector3i, yaw: int, node: Node3D, material: Material) -> void:
	for child in node.get_children():
		if child.has_meta("fence_preview"): child.hide(); child.queue_free()
	var posts := _posts()
	for point in ends(def,origin,yaw):
		for offset in [Vector3i.LEFT,Vector3i.RIGHT,Vector3i.FORWARD,Vector3i.BACK]:
			if not posts.has(point+offset): continue
			var rail: Node3D = load(String(controller.get_defs()["base:furniture:log_fence"].grid_fence.rail_model)).instantiate()
			controller.apply_material(rail,material)
			preload("VoxelShadowSetup.gd").set_casting(rail,false)
			node.add_child(rail)
			rail.set_meta("fence_preview",true)
			rail.global_position = Vector3(point)+Vector3(offset)*.5+Vector3(.5,1,.5)
			rail.global_rotation = Vector3(0,0.0 if offset.x else PI*.5,0)
