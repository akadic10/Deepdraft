extends MeshInstance3D

## Damp soil in the ordinary world; an optional soil-only coverage overlay.
## Sampling is read-only and cannot change the saved moisture history.
var terrain: Node3D
var _stamp := ""

func _ready() -> void:
	terrain.visible_volume_changed.connect(func(): _stamp = "")
	var base := StandardMaterial3D.new()
	base.vertex_color_use_as_albedo = true
	material_override = terrain.underground_lighting.make_material(base)
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _process(_delta: float) -> void:
	if not WaterManager.initialized: return
	var stamp := "%d:%d:%d:%s" % [WaterManager.revision,int(WaterManager.elapsed),terrain.slice_y,WaterManager.show_moisture]
	if stamp == _stamp: return
	_stamp = stamp
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var ground: Dictionary = WaterManager.moisture.soils.duplicate()
	# A surface film keeps its finite volume, but looks like damp ground. It
	# neither paints a blue lake nor creates a waterfall/splash/audio source.
	for key: Vector3i in WaterManager.flow.mass:
		var amount: float = WaterManager.flow.volume(key)
		if amount>WaterManager.flow.epsilon and amount<WaterManager.standing_depth:
			ground[key-Vector3i.UP] = true
	for cell: Vector3i in ground:
		if cell.y>terrain.slice_y or WaterManager.has_standing_water(cell+Vector3i.UP): continue
		if cell.y<WorldGenerator.get_surface_y(cell.x,cell.z) and not terrain.is_revealed_air(cell+Vector3i.UP): continue
		var block := WorldData.get_terrain_block(cell.x,cell.y,cell.z)
		var kind: String = BlockRegistry.get_def(BlockRegistry.get_key(block)).get("kind","")
		if kind not in ["dirt","grass"]: continue
		var moisture := maxf(WaterManager.soil_moisture_at(cell),clampf(WaterManager.depth_at(cell+Vector3i.UP)/WaterManager.standing_depth,0.0,1.0))
		if moisture<0.005 and not WaterManager.show_moisture: continue
		var color := Color("#AB8661").lerp(Color("#378FCE"),moisture) if WaterManager.show_moisture else BlockRegistry.get_color(block,WorldClock.season).darkened(moisture*0.25)
		var x := cell.x
		var z := cell.z
		var y := cell.y+1.012
		ChunkMesher._add_quad(verts,norms,colors,indices,Vector3(x,y,z),Vector3(x,y,z+1),Vector3(x+1,y,z+1),Vector3(x+1,y,z),Vector3.UP,color)
	if verts.is_empty():
		mesh = null
		return
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var built := ArrayMesh.new()
	built.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	mesh = built
