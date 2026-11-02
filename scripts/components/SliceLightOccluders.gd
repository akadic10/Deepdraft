extends Node3D

## Shadow-only rock for lights the slice has cut away (doc 287). The slice draws nothing above
## its plane, so rock up there no longer shades anything: a torch on a sliced wall would light
## the next room and the cut rock past it. These meshes put that rock back into the shadow pass
## only. They follow the renderer's own picture of solid ground (the generated surface, open
## where a cell is cut, solid where a block is built; a cave nobody has found stays rock) as if
## the slice were off, so a chunk stays right at every slice height and only edits rebuild it.
## Only chunks a sliced light asks for (SlicedFurnitureLights) are built and shown. The sun never
## sees them (TerrainLighting.configure_sun), or the sliced-off mountain would shade every cut
## plate of the slice view.

## More chunks are built: a sliced light whose reach they complete may come on.
signal chunks_ready

const TerrainLighting = preload("res://scripts/components/TerrainLighting.gd")
const SIZE := 16                  # WorldData chunks
const WINDOW := SIZE + 1          # the chunk's columns plus the border at -x / -z; its cells plus the one below
const PLANES := (1 << SIZE) - 1   # the 16 planes a chunk owns along each axis
const BUILD_BUDGET_USEC := 3000
const WORLD_SIZE_X: int = WorldData.WORLD_SIZE_X
const WORLD_SIZE_Y: int = WorldData.WORLD_SIZE_Y
const WORLD_SIZE_Z: int = WorldData.WORLD_SIZE_Z

var renderer: Node3D
var _chunks: Dictionary = {}   # Vector3i chunk -> MeshInstance3D, or null when it has no faces
var _stale: Dictionary = {}    # built chunks an edit has changed since
var _wanted: Dictionary = {}   # chunks inside a sliced light's reach; only these are shown
var _ahead: Dictionary = {}    # chunks a step down would need: built early, kept hidden
var _queue: Array[Vector3i] = []
var _material := StandardMaterial3D.new()
var _bit: Dictionary = {}      # 1 << n -> n


func _init(owner: Node3D) -> void:
	renderer = owner
	name = "SliceLightOccluders"
	# Both sides cast, so a face's winding never lets light through.
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	for n in SIZE + 2: _bit[1 << n] = n


## The chunks the shown boxes touch become the shown set; those the ahead boxes touch are built
## too but stay hidden. Missing or changed ones queue, shown before ahead, nearest the camera
## first. Built chunks outside both stay cached, hidden, until an edit drops them.
func request(boxes: Array[AABB], ahead: Array[AABB] = []) -> void:
	_wanted = _keys_of(boxes)
	_ahead = _keys_of(ahead)
	for key: Vector3i in _chunks:
		if _chunks[key] != null: (_chunks[key] as MeshInstance3D).visible = _wanted.has(key)
	_queue.clear()
	for key: Vector3i in _wanted.keys() + _ahead.keys():
		if not _chunks.has(key) or _stale.has(key): _queue.append(key)
	_sort_queue()


## True once every chunk the box touches is built. A chunk an edit has touched still counts while
## it rebuilds, so a light does not blink off when someone digs beside it.
func covers(box: AABB) -> bool:
	for key: Vector3i in _keys_in(box):
		if not _chunks.has(key): return false
	return true


## Cells whose solidity may have changed (digging, building, plans, found caves): their chunks,
## and the chunks beyond that read them as a border, rebuild if shown and are dropped if not.
func invalidate_cells(cells: Array[Vector3i]) -> void:
	var touched := {}
	for cell: Vector3i in cells:
		var key := Vector3i(cell.x >> 4, cell.y >> 4, cell.z >> 4)
		touched[key] = true
		if cell.x & 15 == 15: touched[key + Vector3i(1, 0, 0)] = true
		if cell.y & 15 == 15: touched[key + Vector3i(0, 1, 0)] = true
		if cell.z & 15 == 15: touched[key + Vector3i(0, 0, 1)] = true
	for key: Vector3i in touched: _restale(key)
	_sort_queue()


func invalidate_all() -> void:
	for key: Vector3i in _chunks.keys(): _restale(key)
	_sort_queue()


func _process(_delta: float) -> void:
	if _queue.is_empty(): return
	var deadline := Time.get_ticks_usec() + BUILD_BUDGET_USEC
	var built := false
	while not _queue.is_empty() and (not built or Time.get_ticks_usec() < deadline):
		var key: Vector3i = _queue.pop_back()
		if not (_wanted.has(key) or _ahead.has(key)) or (_chunks.has(key) and not _stale.has(key)): continue
		_build(key)
		built = true
	if built: chunks_ready.emit()


func _restale(key: Vector3i) -> void:
	if not _chunks.has(key): return
	if not (_wanted.has(key) or _ahead.has(key)):
		if _chunks[key] != null: (_chunks[key] as MeshInstance3D).queue_free()
		_chunks.erase(key)
		_stale.erase(key)
	elif not _stale.has(key):
		_stale[key] = true
		_queue.append(key)


## Ahead chunks before shown ones and farthest first, so pop_back takes the shown chunk
## nearest the camera.
func _sort_queue() -> void:
	if _queue.size() < 2: return
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	var eye := Vector2(camera.global_position.x, camera.global_position.z) / SIZE if camera != null else Vector2.ZERO
	_queue.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		if _wanted.has(a) != _wanted.has(b): return _wanted.has(b)
		return eye.distance_squared_to(Vector2(a.x, a.z)) > eye.distance_squared_to(Vector2(b.x, b.z)))


func _keys_of(boxes: Array[AABB]) -> Dictionary:
	var keys := {}
	for box: AABB in boxes:
		for key: Vector3i in _keys_in(box): keys[key] = true
	return keys


func _keys_in(box: AABB) -> Array[Vector3i]:
	var top := Vector3i(WORLD_SIZE_X, WORLD_SIZE_Y, WORLD_SIZE_Z) - Vector3i.ONE
	var low := Vector3i(box.position.floor()).clamp(Vector3i.ZERO, top)
	var high := Vector3i((box.end - Vector3.ONE * .001).floor()).clamp(Vector3i.ZERO, top)
	var keys: Array[Vector3i] = []
	for cx in range(low.x >> 4, (high.x >> 4) + 1):
		for cy in range(low.y >> 4, (high.y >> 4) + 1):
			for cz in range(low.z >> 4, (high.z >> 4) + 1):
				keys.append(Vector3i(cx, cy, cz))
	return keys


## Faces wherever solid meets open, from per-column bit masks: floors and ceilings where a
## column changes, walls where neighbouring columns differ, one quad per run of wall cells. The
## chunk owns the planes on the low side of its cells, so every face is built exactly once.
func _build(key: Vector3i) -> void:
	var x0 := key.x * SIZE
	var y0 := key.y * SIZE
	var z0 := key.z * SIZE
	var masks := _masks(x0, y0, z0)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var indices := PackedInt32Array()
	for i in range(1, WINDOW):
		for j in range(1, WINDOW):
			var here: int = masks[i * WINDOW + j]
			var corner := Vector3(x0 + i - 1, y0, z0 + j - 1)
			var flips := (here ^ (here >> 1)) & PLANES
			while flips != 0:
				var low := flips & -flips
				var at := corner + Vector3.UP * int(_bit[low])
				_quad(at, at + Vector3.RIGHT, at + Vector3(1, 0, 1), at + Vector3.BACK, Vector3.UP, verts, norms, indices)
				flips ^= low
			_walls(((here ^ masks[(i - 1) * WINDOW + j]) >> 1) & PLANES, corner, Vector3.BACK, Vector3.RIGHT, verts, norms, indices)
			_walls(((here ^ masks[i * WINDOW + j - 1]) >> 1) & PLANES, corner, Vector3.RIGHT, Vector3.BACK, verts, norms, indices)
	_store(key, verts, norms, indices)


func _walls(runs: int, corner: Vector3, along: Vector3, normal: Vector3,
		verts: PackedVector3Array, norms: PackedVector3Array, indices: PackedInt32Array) -> void:
	while runs != 0:
		var low := runs & -runs
		var past := runs + low   # carries through the run: its lowest bit is the first cell after it
		var end := past & -past
		var bottom := corner + Vector3.UP * int(_bit[low])
		var top := corner + Vector3.UP * int(_bit[end])
		_quad(bottom, bottom + along, top + along, top, normal, verts, norms, indices)
		runs &= ~(end - 1)


## Solid cells of the chunk's columns and the border columns at -x and -z, one bit per cell from
## the cell under the chunk up through its top. Outside the world counts as rock, so the world's
## edge has no faces.
func _masks(x0: int, y0: int, z0: int) -> PackedInt64Array:
	var masks := PackedInt64Array()
	masks.resize(WINDOW * WINDOW)
	var cut: Dictionary = renderer.visual_cut_blocks()
	var cut_columns := {}
	for i in WINDOW:
		var x := x0 - 1 + i
		for j in WINDOW:
			var z := z0 - 1 + j
			if x < 0 or z < 0 or x >= WORLD_SIZE_X or z >= WORLD_SIZE_Z:
				masks[i * WINDOW + j] = (1 << WINDOW) - 1
				continue
			var mask := (1 << clampi(WorldGenerator.get_surface_y(x, z) - y0 + 2, 0, WINDOW)) - 1
			var column := Vector2i(x >> 4, z >> 4)
			if not cut_columns.has(column): cut_columns[column] = renderer.cavity_shell.has_cut_cells(column)
			if cut_columns[column]:
				for k in WINDOW:
					var cell := Vector3i(x, y0 - 1 + k, z)
					if not cut.has(cell): continue
					if WorldData.has_solid_override(cell): mask |= 1 << k
					else: mask &= ~(1 << k)
			masks[i * WINDOW + j] = mask
	return masks


func _store(key: Vector3i, verts: PackedVector3Array, norms: PackedVector3Array, indices: PackedInt32Array) -> void:
	_stale.erase(key)
	var node: MeshInstance3D = _chunks.get(key)
	if verts.is_empty():
		if node != null: node.queue_free()
		_chunks[key] = null
		return
	if node == null:
		node = MeshInstance3D.new()
		node.name = "Chunk_%d_%d_%d" % [key.x, key.y, key.z]
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		node.layers = TerrainLighting.SLICE_OCCLUDER_LAYER
		node.material_override = _material
		add_child(node)
		_chunks[key] = node
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	node.mesh = mesh
	node.visible = _wanted.has(key)


static func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3,
		verts: PackedVector3Array, norms: PackedVector3Array, indices: PackedInt32Array) -> void:
	var base := verts.size()
	verts.append(a); verts.append(b); verts.append(c); verts.append(d)
	for n in 4: norms.append(normal)
	indices.append(base); indices.append(base + 1); indices.append(base + 2)
	indices.append(base); indices.append(base + 2); indices.append(base + 3)
