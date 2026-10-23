class_name ChunkMesher
extends RefCounted

## Shared quad helper for block-face meshes (MoistureRenderer and the cavity
## shell faces in WorldRenderer follow the same winding).
##
## All methods are static — ChunkMesher is never instantiated.


## Appends one quad (two triangles) to the mesh arrays.
##
## Vertices v0→v1→v2→v3 are supplied counter-clockwise as seen from the normal
## direction. Godot's default backface culling treats CLOCKWISE winding (in view
## space) as front-facing, so the indices below emit the triangles in REVERSED
## order (v0,v2,v1 / v0,v3,v2). This makes the outward face render and the hidden
## interior face cull — without this reversal only inside faces show.
## All four vertices share the same normal and color.
static func add_quad(
		verts:   PackedVector3Array, norms:   PackedVector3Array,
		cols:    PackedColorArray,   indices: PackedInt32Array,
		v0: Vector3, v1: Vector3, v2: Vector3, v3: Vector3,
		normal: Vector3, color: Color) -> void:

	var base: int = verts.size()

	verts.push_back(v0);  verts.push_back(v1)
	verts.push_back(v2);  verts.push_back(v3)

	norms.push_back(normal);  norms.push_back(normal)
	norms.push_back(normal);  norms.push_back(normal)

	cols.push_back(color);  cols.push_back(color)
	cols.push_back(color);  cols.push_back(color)

	# Reversed winding so the outward-facing side renders (see note above).
	# Triangle 1: base, base+2, base+1
	indices.push_back(base);    indices.push_back(base + 2);  indices.push_back(base + 1)
	# Triangle 2: base, base+3, base+2
	indices.push_back(base);    indices.push_back(base + 3);  indices.push_back(base + 2)
