extends RefCounted

## Cached X reflection for rigid parts; source resources stay immutable.
static var _meshes: Dictionary = {}

static func mirrored(source: Mesh) -> ArrayMesh:
	if _meshes.has(source): return _meshes[source]
	var result := ArrayMesh.new()
	for surface in source.get_surface_count():
		var arrays := source.surface_get_arrays(surface).duplicate(true)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for i in vertices.size(): vertices[i].x = -vertices[i].x
		for i in normals.size(): normals[i].x = -normals[i].x
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		if arrays[Mesh.ARRAY_TANGENT] != null:
			var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
			for i in range(0,tangents.size(),4):
				tangents[i] = -tangents[i]
				tangents[i+3] = -tangents[i+3]
			arrays[Mesh.ARRAY_TANGENT] = tangents
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if indices.is_empty():
			for i in vertices.size(): indices.append(i)
		for i in range(0,indices.size(),3):
			var swap := indices[i+1]
			indices[i+1] = indices[i+2]
			indices[i+2] = swap
		arrays[Mesh.ARRAY_INDEX] = indices
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		result.surface_set_material(surface,source.surface_get_material(surface))
	_meshes[source] = result
	return result
