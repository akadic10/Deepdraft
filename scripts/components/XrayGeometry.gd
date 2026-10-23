extends RefCounted

## Incremental, discovered-air-only shell. Geometry is presentation; the real
## terrain keeps collision, support and shadow ownership.
const SIDES := [Vector3i.LEFT,Vector3i.RIGHT,Vector3i.FORWARD,Vector3i.BACK]
var floor_art := preload("res://scripts/components/ConstructionFloorArt.gd").new()

func arrays() -> Array:
	return [PackedVector3Array(),PackedVector3Array(),PackedColorArray(),PackedInt32Array()]

func append_air(cell: Vector3i, level: int, renderer: Node, full: Array, flat: Array,
		floors: Dictionary, full_cells: Dictionary, flat_cells: Dictionary) -> void:
	if cell.y>level or not InteriorTracker.contains_air(cell): return
	var below := cell+Vector3i.DOWN
	var supported := _solid(below)
	var headroom := has_floor_headroom(cell)
	if supported:
		floors[below] = true
		_face(below,Vector3i.UP,renderer,full)
		full_cells[below] = true
		if headroom:
			_face(below,Vector3i.UP,renderer,flat)
			flat_cells[below] = true
	for direction: Vector3i in SIDES:
		var solid := cell+direction
		if not _solid(solid): continue
		_face(solid,-direction,renderer,full)
		full_cells[solid] = true
		if headroom:
			_face(solid,-direction,renderer,flat)
			flat_cells[solid] = true

func has_floor_headroom(cell: Vector3i) -> bool:
	return _solid(cell+Vector3i.DOWN) and not _solid(cell+Vector3i.UP) and not _solid(cell+Vector3i(0,2,0))

## Inspection water is a clipped, still surface at the live solver height.
## Broad outdoor water batches must never reveal unexplored pools.
func append_water(cell: Vector3i, level: int, data: Array) -> void:
	if cell.y>level or not InteriorTracker.contains_air(cell) or not WaterManager.initialized: return
	var flow = WaterManager.flow
	var key: Vector3i = flow.space_at(cell)
	if key.x<0: return
	var amount: float = flow.volume(key)
	if amount<WaterManager.standing_depth: return
	var top := minf(key.y+amount,level+1.0)
	if floori(top-.00001)!=cell.y: return
	var palette: Dictionary = WorldGenerator.water_profile.rendering
	var color := Color(palette.surface_color).darkened(float(palette.depth_shading)*clampf(amount/6,0,1))
	_quad(data,Vector3(cell.x,top,cell.z),Vector3(cell.x+1,top,cell.z),
		Vector3(cell.x+1,top,cell.z+1),Vector3(cell.x,top,cell.z+1),color)

func _solid(cell: Vector3i) -> bool:
	return cell.x>=0 and cell.x<WorldData.WORLD_SIZE_X and cell.z>=0 and cell.z<WorldData.WORLD_SIZE_Z and cell.y>=0 and cell.y<WorldData.WORLD_SIZE_Y \
		and BlockRegistry.is_solid(WorldData.get_terrain_block(cell.x,cell.y,cell.z))

func _face(cell: Vector3i, direction: Vector3i, renderer: Node, data: Array) -> void:
	var id := WorldData.get_terrain_block(cell.x,cell.y,cell.z)
	var definition := BlockRegistry.get_def(BlockRegistry.get_key(id))
	var floor_def := BlockRegistry.get_construction_def(String(definition.get("construction","")))
	if not floor_def.is_empty():
		var patterns: Array = floor_def.get("pattern_models",[floor_def.model])
		floor_art.append_face(String(patterns[posmod(cell.z,patterns.size())]),cell,direction,false,data[0],data[1],data[2],data[3])
	else:
		renderer.add_shell_face(cell,-direction,BlockRegistry.get_terrain_color(id,WorldClock.season),data[0],data[1],data[2],data[3])

func mesh(data: Array) -> ArrayMesh:
	if data[0].is_empty(): return null
	var surface := []
	surface.resize(Mesh.ARRAY_MAX)
	surface[Mesh.ARRAY_VERTEX] = data[0]
	surface[Mesh.ARRAY_NORMAL] = data[1]
	surface[Mesh.ARRAY_COLOR] = data[2]
	surface[Mesh.ARRAY_INDEX] = data[3]
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,surface)
	return result

## Dashed perimeter/step boundaries, projected vertically to the work slice.
## Adjacent same-height floor cells share no line, avoiding a per-voxel grid.
func reference_mesh(columns: Dictionary, level: int, width: float) -> ArrayMesh:
	var data := arrays()
	for column: Vector2i in columns:
		append_reference(column,columns,level,width,data)
	return mesh(data)

func append_reference(column: Vector2i, columns: Dictionary, level: int, width: float, data: Array) -> void:
	var x := float(column.x)
	var z := float(column.y)
	var y := float(level+1)+.025
	for direction: Vector2i in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
		if columns.get(column+direction,-999)==columns[column]: continue
		var start := Vector3(x,y,z)
		var along := Vector3.RIGHT
		if direction==Vector2i.DOWN: start.z += 1
		elif direction==Vector2i.LEFT: along = Vector3.BACK
		elif direction==Vector2i.RIGHT:
			start.x += 1
			along = Vector3.BACK
		var across := Vector3(-along.z,0,along.x)*width*.5
		for dash in [0.0,.55]:
			_quad(data,start+along*dash-across,start+along*(dash+.4)-across,
				start+along*(dash+.4)+across,start+along*dash+across)

func _quad(data: Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3, color := Color.WHITE) -> void:
	var base: int = data[0].size()
	data[0].append_array(PackedVector3Array([a,b,c,d]))
	for i in range(4):
		data[1].append(Vector3.UP)
		data[2].append(color)
	data[3].append_array(PackedInt32Array([base,base+1,base+2,base,base+2,base+3]))
