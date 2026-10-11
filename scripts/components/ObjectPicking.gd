extends RefCounted

## Visual picking is independent of physics and navigation. Canopies and saplings
## are clickable without gaining collision. Triangle data is cached per shared mesh.
var _triangles: Dictionary = {}


func hit_distance(node: Node3D, start: Vector3, end: Vector3) -> float:
	if not is_instance_valid(node) or not node.is_visible_in_tree():
		return INF
	var nearest := INF
	if node is MeshInstance3D:
		var visual := node as MeshInstance3D
		if visual.mesh != null:
			var inverse := visual.global_transform.affine_inverse()
			var local_start := inverse * start
			var local_end := inverse * end
			if visual.get_aabb().intersects_segment(local_start, local_end) != null:
				var mesh_id := visual.mesh.get_instance_id()
				if not _triangles.has(mesh_id):
					_triangles[mesh_id] = visual.mesh.generate_triangle_mesh()
				var triangles := _triangles[mesh_id] as TriangleMesh
				if triangles != null:
					var hit := triangles.intersect_segment(local_start, local_end)
					if not hit.is_empty():
						nearest = start.distance_to(visual.global_transform * (hit["position"] as Vector3))
	for child in node.get_children():
		if child is Node3D:
			nearest = minf(nearest, hit_distance(child as Node3D, start, end))
	return nearest


static func world_bounds(node: Node3D) -> AABB:
	var boxes: Array[AABB] = []
	_collect_bounds(node, boxes)
	var result := AABB()
	for i in range(boxes.size()):
		result = boxes[i] if i == 0 else result.merge(boxes[i])
	return result


## Animated actors can retain hidden tools. Only visible geometry belongs in
## their selection bounds; collision and navigation boxes remain unchanged.
static func visible_world_bounds(node: Node3D) -> AABB:
	if not node.is_visible_in_tree():
		return AABB()
	var result := AABB()
	if node is MeshInstance3D and node.mesh != null:
		result = node.global_transform * node.get_aabb()
	for child in node.get_children():
		if child is Node3D:
			var box := visible_world_bounds(child)
			if box.size.length_squared() > 0.0:
				result = box if result.size == Vector3.ZERO else result.merge(box)
	return result


static func _collect_bounds(node: Node, boxes: Array[AABB]) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var visual := node as MeshInstance3D
		boxes.append(visual.global_transform * visual.get_aabb())
	for child in node.get_children():
		_collect_bounds(child, boxes)


## Shared slice-aware terrain DDA. Returns the solid FLOOR cell, not its air cell.
static func terrain_hit(origin: Vector3, direction: Vector3, slice_y: int,
		max_distance: float = 600.0) -> Dictionary:
	var pos := Vector3i(floori(origin.x), floori(origin.y), floori(origin.z))
	var step := Vector3i(1 if direction.x > 0 else -1,
		1 if direction.y > 0 else -1, 1 if direction.z > 0 else -1)
	var t_delta := Vector3(
		absf(1.0 / direction.x) if not is_zero_approx(direction.x) else INF,
		absf(1.0 / direction.y) if not is_zero_approx(direction.y) else INF,
		absf(1.0 / direction.z) if not is_zero_approx(direction.z) else INF)
	var t_max := Vector3(_axis_t_max(origin.x, direction.x, pos.x),
		_axis_t_max(origin.y, direction.y, pos.y), _axis_t_max(origin.z, direction.z, pos.z))
	var travelled := 0.0
	var normal := Vector3i.ZERO
	while travelled <= max_distance:
		if pos.y < 0:
			return {}
		if pos.x >= 0 and pos.x < WorldGenerator.WORLD_SIZE_X \
				and pos.z >= 0 and pos.z < WorldGenerator.WORLD_SIZE_Z \
				and pos.y <= mini(slice_y, WorldGenerator.WORLD_SIZE_Y - 1):
			var block_id: int
			if WorldData.chunk_exists(pos.x >> 4, pos.y >> 4, pos.z >> 4):
				block_id = WorldData.get_block(pos.x, pos.y, pos.z)
			else:
				block_id = WorldData.get_live_block(pos.x, pos.y, pos.z)
			if BlockRegistry.is_solid(block_id):
				return {"x": pos.x, "y": pos.y, "z": pos.z, "normal": normal, "distance": travelled}
		if t_max.x <= t_max.y and t_max.x <= t_max.z:
			pos.x += step.x
			travelled = t_max.x
			t_max.x += t_delta.x
			normal = Vector3i(-step.x, 0, 0)
		elif t_max.y <= t_max.z:
			pos.y += step.y
			travelled = t_max.y
			t_max.y += t_delta.y
			normal = Vector3i(0, -step.y, 0)
		else:
			pos.z += step.z
			travelled = t_max.z
			t_max.z += t_delta.z
			normal = Vector3i(0, 0, -step.z)
	return {}


static func _axis_t_max(origin: float, direction: float, cell: int) -> float:
	if is_zero_approx(direction):
		return INF
	return (float(cell + 1 if direction > 0 else cell) - origin) / direction


static func outline_mesh(box: AABB, color: Color) -> ImmediateMesh:
	var mesh := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	for edge: Vector2i in [Vector2i(0,1), Vector2i(0,2), Vector2i(0,4), Vector2i(1,3),
		Vector2i(1,5), Vector2i(2,3), Vector2i(2,6), Vector2i(3,7),
		Vector2i(4,5), Vector2i(4,6), Vector2i(5,7), Vector2i(6,7)]:
		mesh.surface_add_vertex(box.get_endpoint(edge.x))
		mesh.surface_add_vertex(box.get_endpoint(edge.y))
	mesh.surface_end()
	return mesh
