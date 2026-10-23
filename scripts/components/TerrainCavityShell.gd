extends RefCounted

## The mined-cavity shell for WorldRenderer (doc 11 Phase SO-2b): faces of solid
## blocks around enclosed cut cells (designations, mined holes and discovered
## caves), one MeshInstance3D per 16x16 block column. Also owns the per-column
## index of cut cells and the column-mesh helpers the added terrain shares.
## Main thread only.

const WORLD_SIZE_X: int = WorldData.WORLD_SIZE_X
const WORLD_SIZE_Y: int = WorldData.WORLD_SIZE_Y
const WORLD_SIZE_Z: int = WorldData.WORLD_SIZE_Z
const TerrainLighting = preload("res://scripts/components/TerrainLighting.gd")

const SHELL_DIRS: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 1, 0), Vector3i(0, -1, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]

var renderer: Node3D

var _cavity_shell_node: Node3D = null   # container: one MeshInstance3D per column
## Coalesced FULL-rebuild flag for events that change every column (slice moves,
## season turns, world restores); _process drains it into at most ONE
## rebuild_all() per frame. Cut/mined block edits instead mark only the
## columns they touch in dirty_columns: a full rebuild per mining commit
## cost O(all cut blocks) — ~80 ms in a 50k-cut colony — on every swing.
var dirty: bool = false
## The shell is split into 16×16 block columns (all heights: a column's
## open-from-above test reads its whole (x, z) column). Vector2i column keys.
var _cut_cells_by_column: Dictionary = {}   # column -> Dictionary(cell -> true)
var _shell_meshes: Dictionary = {}          # column -> MeshInstance3D
var dirty_columns: Dictionary = {}   # column -> true
## Memoised WorldGenerator id lookups for shell neighbour blocks. Generated ids
## are deterministic and immutable for the lifetime of a world (the seed never
## changes within a scene; a load reloads the scene and this node with it).
## Entries never go stale. Steady-state shell rebuilds use dictionary hits
## instead of repeating 3D-noise sampling for every face.
var _shell_exact_ids: Dictionary = {}    # Vector3i -> int (exact generated id)
var _shell_strata_ids: Dictionary = {}   # Vector3i -> int (authored strata id)


func _init(owner: Node3D) -> void:
	renderer = owner


## Any number of same-frame shell mutations (mining commits, slice moves,
## restore batches) collapse to one build per frame.
func flush() -> void:
	if dirty:
		dirty = false
		rebuild_all()
	elif not dirty_columns.is_empty():
		var columns := dirty_columns.keys()
		dirty_columns.clear()
		rebuild_columns(columns)


## Cut cells at these blocks changed: rebuild the columns they touch.
func invalidate_cells(blocks: Array[Vector3i]) -> void:
	mark_columns_touching(dirty_columns, blocks)


## Generated ids are memoised per cell; an edited cell drops its entry.
func forget_generated_id(cell: Vector3i) -> void:
	_shell_exact_ids.erase(cell)


func clear_cut_index() -> void:
	_cut_cells_by_column.clear()


## Rebuilds the cavity-shell mesh (doc 11 SO-2b + defect fixes 2026-06-05):
## for every ENCLOSED cavity block — designated or mined — render the faces of
## adjacent SOLID blocks (floor/ceiling/back walls).
##
## Defect-1 rule: a cavity block ABOVE its column's cut-aware effective top is
## open-from-above — the overview already expresses it (lowered top plate +
## side bands) and drawing it again z-fights. The shell renders only blocks
## with solid rock above (true interiors).
##
## Defect-2 / Option A rule: colour per cavity-block source — MINED → exact
## generated id (mining legitimately reveals, Hard Rule 11); DESIGNATED →
## authored strata id (a plan reveals nothing; reads as a ghost preview under
## the yellow zone overlay).
##
## Skips cavity continuations, faces above the slice plane and world edges.
## Discovered natural cave air shares the exposure rules of mined openings;
## undiscovered cave air remains concealed behind designation faces.
## Full rebuild: every column that has cut blocks or still owns a mesh. Slice
## moves, season turns and restores land here; edits rebuild only the columns
## they touch (rebuild_columns, fed by dirty_columns).
func rebuild_all() -> void:
	dirty_columns.clear()
	var columns: Dictionary = {}
	for column: Vector2i in _cut_cells_by_column: columns[column] = true
	for column: Vector2i in _shell_meshes: columns[column] = true
	rebuild_columns(columns.keys())


func rebuild_columns(columns: Array) -> void:
	var season: String = WorldClock.season
	var col_tops: Dictionary = {}   # per-rebuild cache: Vector2i -> effective top
	var slice_y: int = renderer.slice_y
	var visual_cut: Dictionary = renderer.visual_cut_blocks()
	var debug_caves: Dictionary = renderer.debug_cave_blocks()
	for column: Vector2i in columns:
		var verts: PackedVector3Array = []
		var norms: PackedVector3Array = []
		var cols: PackedColorArray = []
		var indices: PackedInt32Array = []
		for block: Vector3i in _cut_cells_by_column.get(column, {}):
			if WorldData.has_solid_override(block): continue
			if block.y > slice_y:
				continue   # cavity above the plane — hidden with everything else
			if block.y > _cavity_column_top(block.x, block.z, col_tops):
				continue   # open-from-above — the overview's job (defect 1)
			var mined: bool = renderer.is_revealed_air(block) or debug_caves.has(block)
			for dir: Vector3i in SHELL_DIRS:
				var n: Vector3i = block + dir
				if WorldData.has_solid_override(n): continue # Current terrain mesh owns overrides.
				if visual_cut.has(n):
					continue   # open continuation of the cavity (plan or hole)
				if n.y > slice_y:
					continue   # never draw above the plane
				if n.x < 0 or n.x >= WORLD_SIZE_X \
						or n.y < 0 or n.y >= WORLD_SIZE_Y \
						or n.z < 0 or n.z >= WORLD_SIZE_Z:
					continue   # world edge
				# Memoised: generated ids are deterministic per world (see the
				# _shell_exact_ids declaration), so repeat rebuilds hit the dict
				# instead of re-sampling 3D noise per face.
				var exact_id: int
				if _shell_exact_ids.has(n):
					exact_id = _shell_exact_ids[n]
				else:
					exact_id = WorldGenerator.get_generated_block_id(n.x, n.y, n.z)
					_shell_exact_ids[n] = exact_id
				if not BlockRegistry.is_solid(exact_id):
					# An undiscovered cave touching a designation still looks solid.
					# Actual mining discovers connected natural air in InteriorTracker.
					if WorldGenerator.get_cave_id(n) < 0: continue
					exact_id = WorldGenerator.get_overview_strata_block_id(n.x, n.y, n.z)
				var display_id: int
				if mined:
					display_id = exact_id
				elif _shell_strata_ids.has(n):
					display_id = _shell_strata_ids[n]
				else:
					display_id = WorldGenerator.get_overview_strata_block_id(n.x, n.y, n.z)
					_shell_strata_ids[n] = display_id
				add_face(n, dir, BlockRegistry.get_terrain_color(display_id, season), verts, norms, cols, indices)
		apply_column_mesh(_shell_meshes, _shell_container(), column, verts, norms, cols, indices)


func _shell_container() -> Node3D:
	if _cavity_shell_node == null:
		_cavity_shell_node = Node3D.new()
		_cavity_shell_node.name = "CavityShell"
		renderer.add_child(_cavity_shell_node)
	return _cavity_shell_node


## One MeshInstance3D per column with faces; a column left without faces frees
## its node. Shared by the cavity shell and the added terrain.
func apply_column_mesh(meshes: Dictionary, container: Node3D, column: Vector2i,
		verts: PackedVector3Array, norms: PackedVector3Array, cols: PackedColorArray,
		indices: PackedInt32Array) -> void:
	var node: MeshInstance3D = meshes.get(column)
	if verts.is_empty():
		if node != null:
			node.queue_free()
			meshes.erase(column)
		return
	if node == null:
		node = MeshInstance3D.new()
		node.name = "Column_%d_%d" % [column.x, column.y]
		node.material_override = renderer.terrain_material()
		TerrainLighting.configure_mesh(node)
		container.add_child(node)
		meshes[column] = node
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	node.mesh = mesh


## Cut-aware effective top of a column (cached per shell rebuild): walk down
## from min(visible surface, slice plane) through cut blocks — the first solid
## block is the floor of the open pocket. Cavity blocks ABOVE this value are
## open-from-above (overview territory); blocks BELOW it are enclosed and get
## shell faces. Returns -1 while the generator maps are not ready (everything
## then counts as open — there can be no cavities before maps exist).
func _cavity_column_top(wx: int, wz: int, col_tops: Dictionary) -> int:
	var key := Vector2i(wx, wz)
	if col_tops.has(key):
		return col_tops[key]
	var wy := WorldData.visible_top_y(wx, wz, WorldGenerator.get_surface_y(wx, wz), renderer.slice_y, renderer.visual_cut_blocks())
	col_tops[key] = wy
	return wy


## Emits solid block n's face pointing back toward the cavity (normal = -dir,
## where dir is cavity→n). Corner tables and reversed winding match
## ChunkMesher.add_quad so the face renders from inside the cavity.
static func add_face(
		n: Vector3i,
		dir: Vector3i,
		color: Color,
		verts: PackedVector3Array,
		norms: PackedVector3Array,
		cols: PackedColorArray,
		indices: PackedInt32Array) -> void:

	var ox := float(n.x)
	var oy := float(n.y)
	var oz := float(n.z)
	var v0: Vector3
	var v1: Vector3
	var v2: Vector3
	var v3: Vector3

	# dir points cavity→n, so the face we draw is n's face with normal -dir.
	if dir == Vector3i(-1, 0, 0):      # n is -X of cavity → n's +X face
		v0 = Vector3(ox + 1, oy, oz)
		v1 = Vector3(ox + 1, oy + 1, oz)
		v2 = Vector3(ox + 1, oy + 1, oz + 1)
		v3 = Vector3(ox + 1, oy, oz + 1)
	elif dir == Vector3i(1, 0, 0):     # n's -X face
		v0 = Vector3(ox, oy, oz + 1)
		v1 = Vector3(ox, oy + 1, oz + 1)
		v2 = Vector3(ox, oy + 1, oz)
		v3 = Vector3(ox, oy, oz)
	elif dir == Vector3i(0, -1, 0):    # n below cavity → n's +Y face (the floor)
		v0 = Vector3(ox, oy + 1, oz)
		v1 = Vector3(ox, oy + 1, oz + 1)
		v2 = Vector3(ox + 1, oy + 1, oz + 1)
		v3 = Vector3(ox + 1, oy + 1, oz)
	elif dir == Vector3i(0, 1, 0):     # n above cavity → n's -Y face (the ceiling)
		v0 = Vector3(ox + 1, oy, oz)
		v1 = Vector3(ox + 1, oy, oz + 1)
		v2 = Vector3(ox, oy, oz + 1)
		v3 = Vector3(ox, oy, oz)
	elif dir == Vector3i(0, 0, -1):    # n's +Z face
		v0 = Vector3(ox + 1, oy, oz + 1)
		v1 = Vector3(ox + 1, oy + 1, oz + 1)
		v2 = Vector3(ox, oy + 1, oz + 1)
		v3 = Vector3(ox, oy, oz + 1)
	else:                              # n's -Z face
		v0 = Vector3(ox, oy, oz)
		v1 = Vector3(ox, oy + 1, oz)
		v2 = Vector3(ox + 1, oy + 1, oz)
		v3 = Vector3(ox + 1, oy, oz)

	var normal := Vector3(-dir.x, -dir.y, -dir.z)
	var base := verts.size()
	verts.push_back(v0); verts.push_back(v1)
	verts.push_back(v2); verts.push_back(v3)
	for i in range(4):
		norms.push_back(normal)
		cols.push_back(color)
	# Reversed winding (see ChunkMesher.add_quad).
	indices.push_back(base); indices.push_back(base + 2); indices.push_back(base + 1)
	indices.push_back(base); indices.push_back(base + 3); indices.push_back(base + 2)


func track_cut(block: Vector3i, delta: int) -> void:
	var column := column_of(block)
	var cells: Dictionary = _cut_cells_by_column.get(column, {})
	if delta > 0:
		cells[block] = true
		_cut_cells_by_column[column] = cells
	elif cells.erase(block) and cells.is_empty():
		_cut_cells_by_column.erase(column)


## 16×16 column key (chunk x, z) for the per-column shell and added-terrain meshes.
static func column_of(cell: Vector3i) -> Vector2i:
	return Vector2i(cell.x >> 4, cell.z >> 4)


## Columns whose meshes an edit at `cell` can change: its own column (every
## height, for the open-from-above test) plus a neighbour column when the cell
## sits on a column edge, since faces toward the cell belong to that neighbour.
static func mark_columns_touching(out: Dictionary, cells: Array[Vector3i]) -> void:
	for cell: Vector3i in cells:
		var column := column_of(cell)
		out[column] = true
		var lx := cell.x & 15
		var lz := cell.z & 15
		if lx == 0: out[column + Vector2i(-1, 0)] = true
		elif lx == 15: out[column + Vector2i(1, 0)] = true
		if lz == 0: out[column + Vector2i(0, -1)] = true
		elif lz == 15: out[column + Vector2i(0, 1)] = true
