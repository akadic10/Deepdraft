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
## THREADING (doc 11 Phase 1c/1d): build_arrays() is safe to call from
## WorkerThreadPool tasks. It takes exactly 6 WorldData mutex acquisitions per
## chunk (the neighbour snapshots) — brief, never nested, so concurrent
## generator writes only contend, they cannot deadlock. Block colours and
## transparency come from BlockRegistry LUTs built eagerly at boot and
## read-only afterwards. WorldClock.season is read once per build; callers that
## need a consistent season across a batch must not advance the clock mid-batch
## (the renderer blocks the main thread on the batch, which guarantees this).


## Builds and returns an ArrayMesh for the given chunk (main-thread convenience
## wrapper around build_arrays). Returns null if the chunk contains no visible
## blocks (all-void or all-buried).
## WorldRenderer must handle null — free the MeshInstance3D for that chunk.
static func build_mesh(chunk: Chunk, cx: int, cy: int, cz: int, visual_cut_blocks: Dictionary = {}, slice_y: int = 127) -> ArrayMesh:
	var built := build_arrays(chunk, cx, cy, cz, visual_cut_blocks, slice_y)
	if built.is_empty():
		return null

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = built[0]
	arrays[Mesh.ARRAY_NORMAL] = built[1]
	arrays[Mesh.ARRAY_COLOR]  = built[2]
	arrays[Mesh.ARRAY_INDEX]  = built[3]

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Builds the raw mesh data for one chunk and returns it as
## [verts: PackedVector3Array, norms: PackedVector3Array,
##  cols: PackedColorArray, indices: PackedInt32Array],
## or [] when the chunk produces no geometry. Pure data, no Mesh resource is
## created — safe to run on a WorkerThreadPool task (see THREADING above).
##
## slice_y is the horizontal slice plane: the highest visible block layer,
## INCLUSIVE (wy > slice_y is hidden). Blocks above the plane are skipped and
## treated as transparent neighbours, so blocks AT the plane emit top faces
## (the cut floor) and boundary side faces emit normally (doc 11 Phase 1).
## The default (127 = world top) means "slice off" — identical output to the
## pre-slice mesher, one code path (ref doc 10 rule S1).
static func build_arrays(chunk: Chunk, cx: int, cy: int, cz: int, visual_cut_blocks: Dictionary = {}, slice_y: int = 127) -> Array:
	# Whole chunk above the slice plane — no geometry can survive the clip.
	if cy * 16 > slice_y:
		return []

	var verts:   PackedVector3Array = []
	var norms:   PackedVector3Array = []
	var cols:    PackedColorArray   = []
	var indices: PackedInt32Array   = []

	var local_blocks: PackedByteArray = chunk.blocks   # local ref — no mutex needed

	# Hot-path caches (doc 11 Phase 1d):
	# - colour / transparency LUTs replace per-block get_color() (string splits)
	#   and per-neighbour is_transparent() (dict lookups);
	# - the 6 neighbour chunk snapshots replace per-read WorldData mutex
	#   acquisitions (6 locks per chunk instead of thousands);
	# - has_cuts skips Vector3i construction + dict lookups entirely while no
	#   mining cuts exist (the common case).
	var color_lut: PackedColorArray = BlockRegistry.get_color_lut(WorldClock.season)
	var transparent_lut: PackedByteArray = BlockRegistry.get_transparent_lut()
	var has_cuts := not visual_cut_blocks.is_empty()
	var neighbors: Array = [
		_chunk_blocks_or_empty(cx - 1, cy, cz),   # 0: -X
		_chunk_blocks_or_empty(cx + 1, cy, cz),   # 1: +X
		_chunk_blocks_or_empty(cx, cy - 1, cz),   # 2: -Y
		_chunk_blocks_or_empty(cx, cy + 1, cz),   # 3: +Y
		_chunk_blocks_or_empty(cx, cy, cz - 1),   # 4: -Z
		_chunk_blocks_or_empty(cx, cy, cz + 1),   # 5: +Z
	]

	for ly in range(16):
		var wy := cy * 16 + ly
		if wy > slice_y:
			break   # ly ascends — every later layer is also above the plane
		for lx in range(16):
			for lz in range(16):
				var block_id: int = local_blocks[Chunk.local_index(lx, ly, lz)]
				if has_cuts and visual_cut_blocks.has(Vector3i(cx * 16 + lx, wy, cz * 16 + lz)):
					continue

				# Skip transparent blocks (void) — they produce no geometry.
				if transparent_lut[block_id] == 1:
					continue

				var color := color_lut[block_id]
				var ox    := float(lx)
				var oy    := float(ly)
				var oz    := float(lz)

				# ── +X face (right) ───────────────────────────────────────────
				if _neighbor_transparent(lx + 1, ly, lz, cx, cy, cz, local_blocks, neighbors, transparent_lut, has_cuts, visual_cut_blocks, slice_y):
					_add_quad(verts, norms, cols, indices,
						Vector3(ox+1, oy,   oz  ),
						Vector3(ox+1, oy+1, oz  ),
						Vector3(ox+1, oy+1, oz+1),
						Vector3(ox+1, oy,   oz+1),
						Vector3(1, 0, 0), color)

				# ── -X face (left) ────────────────────────────────────────────
				if _neighbor_transparent(lx - 1, ly, lz, cx, cy, cz, local_blocks, neighbors, transparent_lut, has_cuts, visual_cut_blocks, slice_y):
					_add_quad(verts, norms, cols, indices,
						Vector3(ox,   oy,   oz+1),
						Vector3(ox,   oy+1, oz+1),
						Vector3(ox,   oy+1, oz  ),
						Vector3(ox,   oy,   oz  ),
						Vector3(-1, 0, 0), color)

				# ── +Y face (top) ─────────────────────────────────────────────
				if _neighbor_transparent(lx, ly + 1, lz, cx, cy, cz, local_blocks, neighbors, transparent_lut, has_cuts, visual_cut_blocks, slice_y):
					_add_quad(verts, norms, cols, indices,
						Vector3(ox,   oy+1, oz  ),
						Vector3(ox,   oy+1, oz+1),
						Vector3(ox+1, oy+1, oz+1),
						Vector3(ox+1, oy+1, oz  ),
						Vector3(0, 1, 0), color)

				# ── -Y face (bottom) ──────────────────────────────────────────
				if _neighbor_transparent(lx, ly - 1, lz, cx, cy, cz, local_blocks, neighbors, transparent_lut, has_cuts, visual_cut_blocks, slice_y):
					_add_quad(verts, norms, cols, indices,
						Vector3(ox+1, oy,   oz  ),
						Vector3(ox+1, oy,   oz+1),
						Vector3(ox,   oy,   oz+1),
						Vector3(ox,   oy,   oz  ),
						Vector3(0, -1, 0), color)

				# ── +Z face (back) ────────────────────────────────────────────
				if _neighbor_transparent(lx, ly, lz + 1, cx, cy, cz, local_blocks, neighbors, transparent_lut, has_cuts, visual_cut_blocks, slice_y):
					_add_quad(verts, norms, cols, indices,
						Vector3(ox+1, oy,   oz+1),
						Vector3(ox+1, oy+1, oz+1),
						Vector3(ox,   oy+1, oz+1),
						Vector3(ox,   oy,   oz+1),
						Vector3(0, 0, 1), color)

				# ── -Z face (front) ───────────────────────────────────────────
				if _neighbor_transparent(lx, ly, lz - 1, cx, cy, cz, local_blocks, neighbors, transparent_lut, has_cuts, visual_cut_blocks, slice_y):
					_add_quad(verts, norms, cols, indices,
						Vector3(ox,   oy,   oz  ),
						Vector3(ox,   oy+1, oz  ),
						Vector3(ox+1, oy+1, oz  ),
						Vector3(ox+1, oy,   oz  ),
						Vector3(0, 0, -1), color)

	# All-void or fully buried chunk — no geometry.
	if verts.is_empty():
		return []

	return [verts, norms, cols, indices]


# ── Helpers ───────────────────────────────────────────────────────────────────

## Returns an empty PackedByteArray when the chunk does not exist. One mutex
## acquisition per call; build_arrays calls this exactly 6 times per chunk.
static func _chunk_blocks_or_empty(cx: int, cy: int, cz: int) -> PackedByteArray:
	var chunk := WorldData.get_chunk_if_exists(cx, cy, cz)
	if chunk == null:
		return PackedByteArray()
	return chunk.blocks


## Returns true if the block at local position (dlx, dly, dlz) is transparent.
##
## In-chunk neighbours are read from the cached local_blocks array; out-of-chunk
## neighbours from the 6 snapshot arrays fetched at build start (no per-read
## mutex). Ungenerated neighbour chunks (empty snapshot) are treated as opaque
## so streaming boundaries do not render as fake vertical cut walls; positions
## outside the world bounds are treated as transparent (the world edge).
##
## Neighbours above the slice plane (wy > slice_y) count as transparent: this is
## what makes the block AT the plane emit its top face (the visible cut floor).
static func _neighbor_transparent(
		dlx: int, dly: int, dlz: int,
		cx: int, cy: int, cz: int,
		local_blocks: PackedByteArray,
		neighbors: Array,
		transparent_lut: PackedByteArray,
		has_cuts: bool,
		visual_cut_blocks: Dictionary,
		slice_y: int) -> bool:

	var wy := cy * 16 + dly
	if wy > slice_y:
		return true

	if dlx >= 0 and dlx < 16 and dly >= 0 and dly < 16 and dlz >= 0 and dlz < 16:
		# In-chunk: cached local array + LUT.
		if has_cuts and visual_cut_blocks.has(Vector3i(cx * 16 + dlx, wy, cz * 16 + dlz)):
			return true
		return transparent_lut[local_blocks[Chunk.local_index(dlx, dly, dlz)]] == 1

	var wx := cx * 16 + dlx
	var wz := cz * 16 + dlz
	if wx < 0 or wx >= WorldData.WORLD_SIZE_X \
			or wy < 0 or wy >= WorldData.WORLD_SIZE_Y \
			or wz < 0 or wz >= WorldData.WORLD_SIZE_Z:
		return true

	if has_cuts and visual_cut_blocks.has(Vector3i(wx, wy, wz)):
		return true

	# Exactly one axis is out of the 0–15 range for an axis-aligned face.
	var nb: PackedByteArray
	if dlx < 0:
		nb = neighbors[0]
	elif dlx > 15:
		nb = neighbors[1]
	elif dly < 0:
		nb = neighbors[2]
	elif dly > 15:
		nb = neighbors[3]
	elif dlz < 0:
		nb = neighbors[4]
	else:
		nb = neighbors[5]

	if nb.is_empty():
		return false   # ungenerated neighbour chunk = opaque (no fake cut walls)

	return transparent_lut[nb[Chunk.local_index((dlx + 16) % 16, (dly + 16) % 16, (dlz + 16) % 16)]] == 1


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
