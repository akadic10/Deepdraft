extends Node3D

## Read-only damp ground, refreshed in small tiles within a main-thread budget.
## Simulation changes feed a disposable index; no whole-world scan each second.
const TILE_SIZE := 16
const CHECK_INTERVAL := 16
var terrain: Node3D
var material: ShaderMaterial
var _moisture: RefCounted
var _flow: RefCounted
var _revision := -1
var _view_stamp := ""
var _last_second := -1
var _cells: Dictionary = {} # Tile -> candidate ground cells (soil or surface film).
var _films: Dictionary = {}
var _nodes: Dictionary = {}
var _arrays: Dictionary = {}
var _changing: Dictionary = {} # Tiles whose analytic moisture has not settled.
var _dirty: Dictionary = {}
var _pending: Dictionary = {} # Tile -> first queued wall-clock time.
var _soil_changes: Dictionary = {}
var _water_changes: Dictionary = {}
var _index_soils: Array = []
var _index_water: Array = []
var _soil_head := 0
var _water_head := 0
var _building := Vector2i(-1,-1)
var _build_cells: Array = []
var _build_head := 0
var _build_time := 0
var _build_changing := false
var _verts := PackedVector3Array()
var _norms := PackedVector3Array()
var _colors := PackedColorArray()
var _indices := PackedInt32Array()
var _dispatches := 0
var _built := 0
var _unchanged := 0
var last_work_usec := 0
var last_cells := 0

func _ready() -> void:
	terrain.visible_volume_changed.connect(_invalidate_view)
	WaterManager.surface_changed.connect(_on_water_changed)
	WorldData.block_changed.connect(_on_block_changed)
	var base := StandardMaterial3D.new()
	base.vertex_color_use_as_albedo = true
	material = terrain.underground_lighting.make_material(base)
	BlockRegistry.configure_terrain_material(material)

func _process(_delta: float) -> void:
	last_work_usec = 0
	last_cells = 0
	visible = WaterManager.initialized
	if not visible: return
	var started := Time.get_ticks_usec()
	if _moisture != WaterManager.moisture or _flow != WaterManager.flow or _revision != WaterManager.revision:
		_reset_index()
	var stamp := "%d:%s:%s" % [terrain.slice_y,WaterManager.show_moisture,WorldClock.season]
	if stamp != _view_stamp:
		_view_stamp = stamp
		_invalidate_view()
	var second := int(WaterManager.elapsed)
	if second != _last_second or (WorldClock.paused and not _dirty.is_empty()):
		_last_second = second
		for tile: Vector2i in _changing: _queue(tile)
		for tile: Vector2i in _dirty: _queue(tile)
		_dirty.clear()
	var budget := maxi(1,roundi(float(WorldGenerator.water_profile.get("rendering",{}).get("moisture_budget_ms",1.0))*1000.0))
	# Initial key snapshots happen once per owner/reload. Both indexing and
	# geometry sampling resume across frames; notifications coalesce in between.
	if _soil_head >= _index_soils.size() and not _soil_changes.is_empty():
		_index_soils = _soil_changes.keys()
		_soil_head = 0
		_soil_changes.clear()
	if _water_head >= _index_water.size() and not _water_changes.is_empty():
		_index_water = _water_changes.keys()
		_water_head = 0
		_water_changes.clear()
	while Time.get_ticks_usec()-started < budget:
		if _soil_head < _index_soils.size():
			for i in CHECK_INTERVAL:
				if _soil_head >= _index_soils.size(): break
				_track_soil(_index_soils[_soil_head])
				_soil_head += 1
		elif _water_head < _index_water.size():
			for i in CHECK_INTERVAL:
				if _water_head >= _index_water.size(): break
				_track_water(_index_water[_water_head])
				_water_head += 1
		else:
			if _building.x < 0 and not _begin_tile(): break
			for i in CHECK_INTERVAL:
				if _build_head >= _build_cells.size(): break
				_append_cell(_build_cells[_build_head])
				_build_head += 1
				last_cells += 1
			if _build_head >= _build_cells.size(): _finish_tile()
	last_work_usec = Time.get_ticks_usec()-started

func _reset_index() -> void:
	if _moisture != null and _moisture.cells_changed.is_connected(_on_soils_changed):
		_moisture.cells_changed.disconnect(_on_soils_changed)
	_moisture = WaterManager.moisture
	_flow = WaterManager.flow
	_revision = WaterManager.revision
	_moisture.cells_changed.connect(_on_soils_changed)
	for node: MeshInstance3D in _nodes.values():
		node.visible = false
		node.queue_free()
	_nodes.clear()
	_arrays.clear()
	_cells.clear()
	_films.clear()
	_changing.clear()
	_dirty.clear()
	_pending.clear()
	_soil_changes.clear()
	_water_changes.clear()
	_index_soils = _moisture.soils.keys()
	_index_water = _flow.mass.keys()
	_soil_head = 0
	_water_head = 0
	_building = Vector2i(-1,-1)
	_last_second = -1

func _tile(cell: Vector3i) -> Vector2i:
	return Vector2i(floori(cell.x/float(TILE_SIZE)),floori(cell.z/float(TILE_SIZE)))

func _track_soil(cell: Vector3i) -> void:
	if not _moisture.soils.has(cell): return
	var tile := _tile(cell)
	if not _cells.has(tile): _cells[tile] = {}
	var is_new: bool = not _cells[tile].has(cell)
	_cells[tile][cell] = true
	_dirty[tile] = true
	var state: Dictionary = _moisture.soils[cell]
	if int(state.value) != int(state.target): _changing[tile] = true
	if is_new or WorldClock.paused: _queue(tile)

func _track_water(key: Vector3i) -> void:
	var cell := key-Vector3i.UP
	var tile := _tile(cell)
	var amount: float = _flow.volume(key)
	var film: bool = amount>_flow.epsilon and amount<WaterManager.standing_depth
	if film:
		if not _cells.has(tile): _cells[tile] = {}
		var is_new: bool = not _cells[tile].has(cell)
		_cells[tile][cell] = true
		_films[cell] = true
		if is_new: _queue(tile)
	elif _films.has(cell):
		_films.erase(cell)
		if not _moisture.soils.has(cell): _cells[tile].erase(cell)
		_dirty[tile] = true
	if _cells.has(tile) and _cells[tile].has(cell): _dirty[tile] = true
	if WorldClock.paused and _dirty.has(tile): _queue(tile)

func _on_soils_changed(cells: Dictionary) -> void:
	for cell: Vector3i in cells: _soil_changes[cell] = true

func _on_water_changed(cells: Array) -> void:
	for key: Vector3i in cells: _water_changes[key] = true

func _on_block_changed(cell: Vector3i, _old: int, _new: int) -> void:
	var tile := _tile(cell)
	if _nodes.has(tile): _nodes[tile].visible = false
	_queue(tile)
	if _building == tile: _building = Vector2i(-1,-1)

func _invalidate_view() -> void:
	# Conceal synchronously, even while paused or a partial tile is in flight.
	for node: MeshInstance3D in _nodes.values(): node.visible = false
	_building = Vector2i(-1,-1)
	for tile: Vector2i in _cells: _queue(tile)

func _queue(tile: Vector2i) -> void:
	if not _pending.has(tile): _pending[tile] = Time.get_ticks_usec()

func _begin_tile() -> bool:
	var camera := get_viewport().get_camera_3d()
	var best := Vector2i(-1,-1)
	var score := INF
	var oldest := camera == null or _dispatches%8 == 7
	for tile: Vector2i in _pending:
		var value := float(_pending[tile])
		if not oldest:
			var x := tile.x*TILE_SIZE+8
			var z := tile.y*TILE_SIZE+8
			var point := Vector3(x,mini(terrain.slice_y,WorldGenerator.get_surface_y(x,z))+1,z)
			value = camera.global_position.distance_squared_to(point)
			if not camera.is_position_in_frustum(point): value += 1048576.0
		if value < score: score=value; best=tile
	if best.x < 0: return false
	_pending.erase(best)
	_building = best
	_dispatches += 1
	_build_cells = _cells.get(best,{}).keys()
	_build_head = 0
	_build_time = WaterManager.elapsed_usec
	_build_changing = false
	_verts = PackedVector3Array()
	_norms = PackedVector3Array()
	_colors = PackedColorArray()
	_indices = PackedInt32Array()
	return true

func _append_cell(cell: Vector3i) -> void:
	if not _moisture.soils.has(cell) and not _films.has(cell): return
	var value: int = _moisture.value_units(cell,_build_time)
	var wet: float = float(value)/_moisture.SCALE
	if _moisture.soils.has(cell) and value != int(_moisture.soils[cell].target): _build_changing = true
	if cell.y>terrain.slice_y or WaterManager.has_standing_water(cell+Vector3i.UP): return
	if cell.y<WorldGenerator.get_surface_y(cell.x,cell.z) and not terrain.is_revealed_air(cell+Vector3i.UP): return
	var block := WorldData.get_terrain_block(cell.x,cell.y,cell.z)
	var kind: String = BlockRegistry.get_def(BlockRegistry.get_key(block)).get("kind","")
	if kind not in ["dirt","grass"]: return
	var amount := maxf(wet,clampf(WaterManager.depth_at(cell+Vector3i.UP)/WaterManager.standing_depth,0.0,1.0))
	if amount<0.005 and not WaterManager.show_moisture: return
	var color := BlockRegistry.get_terrain_color(block,WorldClock.season).darkened(amount*0.25)
	if WaterManager.show_moisture:
		color = Color("#AB8661").lerp(Color("#378FCE"),amount).srgb_to_linear()
	var x := cell.x
	var z := cell.z
	var y := cell.y+1.012
	ChunkMesher._add_quad(_verts,_norms,_colors,_indices,Vector3(x,y,z),Vector3(x,y,z+1),Vector3(x+1,y,z+1),Vector3(x+1,y,z),Vector3.UP,color)

func _finish_tile() -> void:
	if _build_changing: _changing[_building] = true
	else: _changing.erase(_building)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _verts
	arrays[Mesh.ARRAY_NORMAL] = _norms
	arrays[Mesh.ARRAY_COLOR] = _colors
	arrays[Mesh.ARRAY_INDEX] = _indices
	if not _nodes.has(_building) and not _verts.is_empty():
		var node := MeshInstance3D.new()
		node.name = "Moisture_%d_%d" % [_building.x,_building.y]
		node.material_override = material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
		_nodes[_building] = node
	if _nodes.has(_building):
		var node: MeshInstance3D = _nodes[_building]
		if _arrays.has(_building) and _arrays[_building] == arrays:
			_unchanged += 1
		elif _verts.is_empty(): node.mesh = null
		else:
			var built := ArrayMesh.new()
			built.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
			node.mesh = built
			_built += 1
		node.visible = true
	_arrays[_building] = arrays
	_building = Vector2i(-1,-1)

func is_updating() -> bool:
	return _revision != WaterManager.revision or _soil_head < _index_soils.size() or _water_head < _index_water.size() or not _soil_changes.is_empty() or not _water_changes.is_empty() or not _pending.is_empty() or _building.x >= 0

func get_mesh_stats() -> Dictionary:
	return {"pending":_pending.size(),"index_pending":_index_soils.size()-_soil_head+_index_water.size()-_water_head+_soil_changes.size()+_water_changes.size(),
		"building":_building.x>=0,"tiles":_nodes.size(),"built":_built,"unchanged":_unchanged,"main_ms":last_work_usec/1000.0,"sampled_cells":last_cells}

func _exit_tree() -> void:
	if _moisture != null and _moisture.cells_changed.is_connected(_on_soils_changed): _moisture.cells_changed.disconnect(_on_soils_changed)
