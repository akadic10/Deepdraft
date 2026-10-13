extends RefCounted

## The same authored GLBs serve previews and the culled terrain batch. Cache
## their six boundary faces; no scene node or collider is allocated per tile.
var _faces: Dictionary = {}

func append_face(path: String, cell: Vector3i, direction: Vector3i, cut: bool,
		verts: PackedVector3Array, norms: PackedVector3Array,
		colors: PackedColorArray, indices: PackedInt32Array) -> void:
	if not _faces.has(path): _load_faces(path)
	var face: Array = _faces[path][direction]
	var base := verts.size()
	for vertex: Vector3 in face[0]: verts.append(vertex+Vector3(cell))
	norms.append_array(face[1])
	for color: Color in face[2]:
		colors.append(color*Color(.5,.5,.5,1) if cut else color)
	for index: int in face[3]: indices.append(base+index)

func _load_faces(path: String) -> void:
	var faces := {}
	for direction in [Vector3i.LEFT,Vector3i.RIGHT,Vector3i.UP,Vector3i.DOWN,Vector3i.FORWARD,Vector3i.BACK]:
		faces[direction] = [PackedVector3Array(),PackedVector3Array(),PackedColorArray(),PackedInt32Array()]
	var instance: Node3D = (load(path) as PackedScene).instantiate()
	_collect(instance,Transform3D.IDENTITY,faces)
	instance.free()
	_faces[path] = faces

func _collect(node: Node3D, parent: Transform3D, faces: Dictionary) -> void:
	var transform := parent*node.transform
	if node is MeshInstance3D:
		for surface in range(node.mesh.get_surface_count()):
			var arrays: Array = node.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			for offset in range(0,indices.size(),3):
				var normal: Vector3 = (transform.basis*normals[indices[offset]]).normalized()
				var direction := Vector3i(normal.round())
				var face: Array = faces[direction]
				for index in range(offset,offset+3):
					face[3].append(face[0].size())
					face[0].append(transform*vertices[indices[index]])
					face[1].append(normal)
					face[2].append(colors[indices[index]])
	for child in node.get_children():
		if child is Node3D: _collect(child,transform,faces)
