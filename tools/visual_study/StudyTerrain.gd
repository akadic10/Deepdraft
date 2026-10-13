extends Node3D

## Bounded native voxel fixture. Real block IDs, live WorldData, ChunkMesher and
## ConstructionFloorArt; no heightmaps or production world-generation changes.
const ORIGIN := Vector3i(32,0,32)
const SIZE := 32
const FLOOR_Y := 20
var floor_cells: Dictionary = {}
var original_sample: Dictionary = {}
var mesh_nodes: Array[MeshInstance3D] = []
var slice_y := 24
var stone_id: int
var grass_id: int
var dirt_id: int
var blocks
var world
var floor_art := preload("res://scripts/components/ConstructionFloorArt.gd").new()
const DetailMesh = preload("StudyMesh.gd")


func create_world() -> void:
	blocks = get_node("/root/BlockRegistry")
	world = get_node("/root/WorldData")
	stone_id = blocks.get_id("base:terrain:rock:rock01")
	grass_id = blocks.get_id("base:terrain:surface:grass_01")
	dirt_id = blocks.get_id("base:terrain:surface:dirt_01")
	# Only eight real chunks are allocated. Rows 0–3 retain bedrock identity;
	# these initial chunks are submitted through the generator's bulk API.
	for cx in range(2,4):
		for cz in range(2,4):
			for cy in range(2):
				var chunk := Chunk.new()
				for x in range(16):
					for z in range(16):
						var local := Vector2i((cx-2)*16+x,(cz-2)*16+z)
						var top := surface_height(local.x,local.y)
						for y in range(16):
							var wy := cy*16+y
							var id: int = blocks.AIR_ID
							if wy <= 3: id = blocks.get_id("base:terrain:bedrock")
							elif wy <= top:
								id = grass_id if wy == top else (dirt_id if wy >= top-1 else stone_id)
							chunk.blocks[Chunk.local_index(x,y,z)] = id
				chunk.has_void = true
				world.submit_chunk(cx,cy,cz,chunk)
	# Explicit empty border: the production mesher correctly treats unloaded
	# neighbors as opaque. A bounded diorama needs known air at its four edges.
	for cx in range(1,5):
		for cz in range(1,5):
			for cy in range(1,3):
				if world.chunk_exists(cx,cy,cz): continue
				world.submit_chunk(cx,cy,cz,Chunk.new())


func surface_height(x: int, z: int) -> int:
	var river := river_bounds(z)
	if x >= river.x and x <= river.y: return 20 if z < 13 else 15
	# Small real recesses break the stream-side cliff into shoulders, leaving
	# the room's enclosing wall intact. Both comparison modes share this data.
	if x == 24 and z < 16: return 22 + int(z%7>3)*2
	if x == 23 and z in [2,3,10,11,12]: return 25
	if z < 16 and x < 25: return 27 + int(x >= 6 and x <= 16 and z < 6)
	if z < 14: return 22
	var contour := int(sin(x*.43)*1.6)
	if z < 18+contour: return 20
	if z < 20+contour: return 19
	if z < 22+contour: return 18
	return 17


func river_bounds(z: int) -> Vector2i:
	if z < 13: return Vector2i(25,27 + int(z>=5 and z<=8))
	var left := 24 if z>=18 and z<=25 else 25
	return Vector2i(left,28 if z>=15 and z<=23 else 27)


func excavate_rooms() -> void:
	var floor_defs := {"plank_floor": blocks.get_construction_def("plank_floor"), "stone_floor": blocks.get_construction_def("stone_floor")}
	for x in range(3,22):
		for z in range(4,16):
			var room := (x <= 10 or x >= 13) and z <= 12
			var corridor := x >= 10 and x <= 13 and z >= 8 and z <= 10
			var doorway := x in [7,8,17,18] and z >= 12
			if not room and not corridor and not doorway: continue
			for y in range(21,25): _set_cell(Vector3i(x,y,z),blocks.AIR_ID)
			var kind := "plank_floor" if x <= 10 else "stone_floor"
			if room:
				floor_cells[ORIGIN+Vector3i(x,20,z)] = kind
				_set_cell(Vector3i(x,20,z),blocks.get_id(floor_defs[kind].block_key))
	# A reusable three-block-high opening in the left exterior wall.
	for y in range(21,24):
		for x in range(0,3):
			var cell := ORIGIN+Vector3i(x,y,8)
			original_sample[cell] = world.get_block(cell.x,cell.y,cell.z)


func _set_cell(cell: Vector3i, id: int) -> void:
	cell += ORIGIN
	world.set_block(cell.x,cell.y,cell.z,id)


func set_sample_open(open: bool) -> void:
	for cell: Vector3i in original_sample:
		world.set_block(cell.x,cell.y,cell.z,blocks.AIR_ID if open else original_sample[cell])


func rebuild(material: Material, floor_material: Material, art_mode := false, detailed_ground := false) -> void:
	for node in mesh_nodes:
		remove_child(node)
		node.queue_free()
	mesh_nodes.clear()
	for cx in range(2,4):
		for cz in range(2,4):
			for cy in range(2):
				var chunk: Chunk = world.get_chunk(cx,cy,cz)
				var raw := ChunkMesher.build_arrays(chunk,cx,cy,cz,{},slice_y)
				if raw.is_empty(): continue
				var verts := PackedVector3Array()
				var norms := PackedVector3Array()
				var colors := PackedColorArray()
				var tags := PackedVector2Array()
				var indices := PackedInt32Array()
				var detail = DetailMesh.new()
				var offset := Vector3(cx*16,cy*16,cz*16)
				for start in range(0,raw[0].size(),4):
					var normal: Vector3 = raw[1][start]
					var centre: Vector3 = (raw[0][start]+raw[0][start+2])*.5 + offset
					var cell := Vector3i((centre-normal*.01).floor())
					# Crop only the display plinth. The live data retains its bedrock.
					if cell.y < 14: continue
					if floor_cells.has(cell) and normal == Vector3.UP: continue
					var id: int = world.get_block(cell.x,cell.y,cell.z)
					var cut: bool = normal == Vector3.UP and cell.y == slice_y and world.get_block(cell.x,cell.y+1,cell.z) != blocks.AIR_ID
					if art_mode and (id == stone_id or cut):
						var value := float(posmod((cell.x*73856093) ^ (cell.y*19349663) ^ (cell.z*83492791),101))/100.0
						var color := Color("444c53").lerp(Color("696f70"),value*.7).srgb_to_linear()
						var corners: Array = []
						for i in range(4): corners.append(raw[0][start+i]+offset)
						detail.stone_face(corners,normal,color,value)
						continue
					if art_mode and detailed_ground and id in [grass_id,dirt_id]:
						var value := float(posmod((cell.x*73856093) ^ (cell.y*19349663) ^ (cell.z*83492791),101))/100.0
						var corners: Array = []
						for i in range(4): corners.append(raw[0][start+i]+offset)
						var turf: bool = id == grass_id and world.get_block(cell.x,cell.y+1,cell.z) == blocks.AIR_ID
						detail.ground_face(corners,normal,turf,value)
						continue
					var base := verts.size()
					for i in range(4):
						verts.append(raw[0][start+i]+offset)
						norms.append(normal)
						colors.append(raw[2][start+i]*Color(.5,.5,.5,1) if cut else raw[2][start+i])
						tags.append(Vector2(1 if id == stone_id else (2 if id == grass_id else 0),1 if cut else 0))
					# Preserve ChunkMesher's clockwise face winding.
					var source_index: int = start/4*6
					for i in range(6): indices.append(base+raw[3][source_index+i]-start)
				_mesh(verts,norms,colors,indices,tags,material,false)
				if not detail.vertices.is_empty():
					_mesh(detail.vertices,detail.normals,detail.colors,detail.indices,detail.tags,material,false)
	var fv := PackedVector3Array()
	var fn := PackedVector3Array()
	var fc := PackedColorArray()
	var fi := PackedInt32Array()
	var defs := {"plank_floor": blocks.get_construction_def("plank_floor"), "stone_floor": blocks.get_construction_def("stone_floor")}
	for cell: Vector3i in floor_cells:
		if cell.y > slice_y: continue
		var def: Dictionary = defs[floor_cells[cell]]
		var path: String = def.model
		if def.has("pattern_models"): path = def.pattern_models[cell.z%2]
		floor_art.append_face(path,cell,Vector3i.UP,false,fv,fn,fc,fi)
	if not fv.is_empty(): _mesh(fv,fn,fc,fi,PackedVector2Array(),floor_material,true)


func _mesh(verts: PackedVector3Array, norms: PackedVector3Array, colors: PackedColorArray,
		indices: PackedInt32Array, tags: PackedVector2Array, material: Material, is_floor: bool) -> void:
	if verts.is_empty(): return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	if not tags.is_empty(): arrays[Mesh.ARRAY_TEX_UV2] = tags
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.set_meta("study_floor",is_floor)
	preload("res://scripts/components/TerrainLighting.gd").configure_mesh(node)
	add_child(node)
	mesh_nodes.append(node)
