extends RefCounted

## Fit the rotated item inside its authored display slot. anchor_scale remains
## the maximum; large rocks/flags shrink without changing carried or loose items.
## Centering the visible bounds also handles asymmetric origins such as crates.
static func fit(node: Node3D, anchor_max_size: Vector3, anchor_scale: float) -> void:
	if anchor_max_size.x <= 0 or anchor_max_size.y <= 0 or anchor_max_size.z <= 0:
		return
	var meshes: Array[Node] = node.find_children("*", "MeshInstance3D", true, false)
	if node is MeshInstance3D:
		meshes.append(node)
	var bounds := AABB()
	var found := false
	var inverse := node.global_transform.affine_inverse()
	for mesh_node in meshes:
		var mesh := mesh_node as MeshInstance3D
		if mesh.mesh == null:
			continue
		var local: AABB = inverse * mesh.global_transform * mesh.get_aabb()
		bounds = bounds.merge(local) if found else local
		found = true
	if not found:
		return
	var rotated: AABB = Transform3D(Basis(Vector3.UP, node.rotation.y), Vector3.ZERO) * bounds
	var fit_scale := anchor_scale
	for axis in range(3):
		if rotated.size[axis] > 0:
			fit_scale = minf(fit_scale, anchor_max_size[axis] / rotated.size[axis])
	node.scale = Vector3.ONE * fit_scale
	node.position -= Vector3(rotated.get_center().x, rotated.position.y, rotated.get_center().z) * fit_scale
