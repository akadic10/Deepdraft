class_name ChunkMesher
extends RefCounted

## Builds a vertex-colored ArrayMesh from a single chunk's block data.
##
## All methods are static — ChunkMesher is never instantiated.
## Call: ChunkMesher.build_mesh(chunk, cx, cy, cz)
##
## The returned mesh is in local chunk space (block coordinates 0–15 per axis).
## The owning MeshInstance3D must be positioned at Vector3(cx*16, cy*16, cz*16).
##
## Face culling: a face is only emitted when its direct neighbour is transparent
## (void or water). Buried faces are skipped entirely.
##
## IMPORTANT: Call only from the main thread. The cross-chunk neighbour fallback
## calls WorldData.get_block(), which acquires a mutex. Calling from a worker
## thread while WorldGenerator is still running will deadlock.


## Builds and returns an ArrayMesh for the given chunk.
## Returns null if the chunk contains no visible blocks (all-void or all-buried).
## WorldRenderer must handle null — free the MeshInstance3D for that chunk.
static func build_mesh(chunk: Chunk, cx: int, cy: int, cz: int) -> ArrayMesh:
	var verts:   PackedVector3Array = []
	var norms:   PackedVector3Array = []
	var cols:    PackedColorArray   = []
	var indices: PackedInt32Array   = []

	var season:       String          = WorldClock.season
	var local_blocks: PackedByteArray = chunk.blocks   # local ref — no mutex needed

	for ly in range(16):
		for lx in range(16):
			for lz in range(16):
				var block_id: int = local_blocks[Chunk.local_index(lx, ly, lz)]

				# Skip transparent blocks (void, water) — they produce no geometry.
				if BlockRegistry.is_transparent(block_id):
					continue

				var color := BlockRegistry.get_color(block_id, season)
				var ox    := float(lx)
				var oy    := float(ly)
				var oz    := float(lz)

				# ── +X face (right) ───────────────────────────────────────────
				if _neighbor_transparent(lx + 1, ly, lz, cx, cy, cz, local_blocks):
					_add_quad(verts, norms, cols, indices,
						Vector3(ox+1, oy,   oz  ),
						Vector3(ox+1, oy+1, oz  ),
						Vector3(ox+1, oy+1, oz+1),
						Vector3(ox+1, oy,   oz+1),
						Vector3(1, 0, 0), color)

				# ── -X face (left) ────────────────────────────────────────────
				if _neighbor_transparent(lx - 1, ly, lz, cx, cy, cz, local_blocks):
					_add_quad(verts, norms, cols, indices,
						Vector3(ox,   oy,   oz+1),
						Vector3(ox,   oy+1, oz+1),
						Vector3(ox,   oy+1, oz  ),
						Vector3(ox,   oy,   oz  ),
						Vector3(-1, 0, 0), color)

				# ── +Y face (top) ─────────────────────────────────────────────
				if _neighbor_transparent(lx, ly + 1, lz, cx, cy, cz, local_blocks):
					_add_quad(verts, norms, cols, indices,
						Vector3(ox,   oy+1, oz  ),
						Vector3(ox,   oy+1, oz+1),
						Vector3(ox+1, oy+1, oz+1),
						Vector3(ox+1, oy+1, oz  ),
						Vector3(0, 1, 0), color)

				# ── -Y face (bottom) ──────────────────────────────────────────
				if _neighbor_transparent(lx, ly - 1, lz, cx, cy, cz, local_blocks):
					_add_quad(verts, norms, cols, indices,
						Vector3(ox+1, oy,   oz  ),
						Vector3(ox+1, oy,   oz+1),
						Vector3(ox,   oy,   oz+1),
						Vector3(ox,   oy,   oz  ),
						Vector3(0, -1, 0), color)

				# ── +Z face (back) ────────────────────────────────────────────
				if _neighbor_transparent(lx, ly, lz + 1, cx, cy, cz, local_blocks):
					_add_quad(verts, norms, cols, indices,
						Vector3(ox+1, oy,   oz+1),
						Vector3(ox+1, oy+1, oz+1),
						Vector3(ox,   oy+1, oz+1),
						Vector3(ox,   oy,   oz+1),
						Vector3(0, 0, 1), color)

				# ── -Z face (front) ───────────────────────────────────────────
				if _neighbor_transparent(lx, ly, lz - 1, cx, cy, cz, local_blocks):
					_add_quad(verts, norms, cols, indices,
						Vector3(ox,   oy,   oz  ),
						Vector3(ox,   oy+1, oz  ),
						Vector3(ox+1, oy+1, oz  ),
						Vector3(ox+1, oy,   oz  ),
						Vector3(0, 0, -1), color)

	# All-void or fully buried chunk — no mesh needed.
	if verts.is_empty():
		return null

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR]  = cols
	arrays[Mesh.ARRAY_INDEX]  = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# ── Helpers ───────────────────────────────────────────────────────────────────

## Returns true if the block at local position (dlx, dly, dlz) is transparent.
##
## In-chunk neighbours are read from the cached local_blocks array (no mutex).
## Out-of-chunk neighbours fall back to WorldData.get_block(), which is safe on
## the main thread only. Ungenerated in-world neighbour chunks are treated as
## opaque so streaming boundaries do not render as fake vertical cut walls.
static func _neighbor_transparent(
		dlx: int, dly: int, dlz: int,
		cx: int, cy: int, cz: int,
		local_blocks: PackedByteArray) -> bool:

	if dlx >= 0 and dlx < 16 and dly >= 0 and dly < 16 and dlz >= 0 and dlz < 16:
		# In-chunk: use the cached array.
		return BlockRegistry.is_transparent(local_blocks[Chunk.local_index(dlx, dly, dlz)])

	var wx := cx * 16 + dlx
	var wy := cy * 16 + dly
	var wz := cz * 16 + dlz

	if wx < 0 or wx >= WorldData.WORLD_SIZE_X \
			or wy < 0 or wy >= WorldData.WORLD_SIZE_Y \
			or wz < 0 or wz >= WorldData.WORLD_SIZE_Z:
		return true

	var ncx := floori(float(wx) / 16.0)
	var ncy := floori(float(wy) / 16.0)
	var ncz := floori(float(wz) / 16.0)
	if not WorldData.chunk_exists(ncx, ncy, ncz):
		return false

	return BlockRegistry.is_transparent(WorldData.get_block(wx, wy, wz))


## Appends one quad (two triangles) to the mesh arrays.
##
## Vertices v0→v1→v2→v3 are supplied counter-clockwise as seen from the normal
## direction. Godot's default backface culling treats CLOCKWISE winding (in view
## space) as front-facing, so the indices below emit the triangles in REVERSED
## order (v0,v2,v1 / v0,v3,v2). This makes the outward face render and the hidden
## interior face cull — without this reversal only inside faces show.
## All four vertices share the same normal and color.
static func _add_quad(
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
