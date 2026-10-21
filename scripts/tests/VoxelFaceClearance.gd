extends RefCounted
## Whether any posed visual face under `part` enters `box` (world space). Seating
## tests use it where a combined bounding box is too coarse: a long beard hangs in
## front of a table edge, below the top, without touching it (doc 256).

static func meets(part: Node3D, box: AABB) -> bool:
	for mesh: MeshInstance3D in preload("res://scripts/components/VoxelShadowSetup.gd").visual_meshes(part):
		if mesh.mesh == null or not mesh.is_visible_in_tree(): continue
		var frame := mesh.global_transform
		for surface in mesh.mesh.get_surface_count():
			var arrays := mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var raw: Variant = arrays[Mesh.ARRAY_INDEX]
			var indices: PackedInt32Array = raw if raw != null else PackedInt32Array()
			var count := vertices.size() if indices.is_empty() else indices.size()
			for i in range(0, count - 2, 3):
				var corners: Array[Vector3] = []
				for k in 3: corners.append(frame * vertices[i + k if indices.is_empty() else indices[i + k]])
				if AABB(corners[0], Vector3.ZERO).expand(corners[1]).expand(corners[2]).intersects(box): return true
	return false
