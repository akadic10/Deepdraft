extends Node3D

## Opaque, fractionally filled voxel water. One mesh per 32×32 tile; no nodes
## per cell. The ordinary terrain mesh renders the actual bed underneath.
var terrain: Node3D
var material: ShaderMaterial
var _tiles: Dictionary = {}
var _revision := -1
var _slice := -1
var _verts := PackedVector3Array()
var _norms := PackedVector3Array()
var _colors := PackedColorArray()
var _indices := PackedInt32Array()
var _uvs := PackedVector2Array()
var _surface_data := PackedVector2Array()
var motion := preload("res://scripts/components/WaterSurfaceMotion.gd").new()
var _motion_time := -1.0
var _motion_flow: RefCounted
var _falls: Dictionary = {}
var _splash_sites: Dictionary = {}
var _splash: MultiMeshInstance3D
var _sound: Node3D

func _ready() -> void:
	terrain.visible_volume_changed.connect(func(): _revision = -1)
	var base := StandardMaterial3D.new()
	base.vertex_color_use_as_albedo = true
	base.roughness = 0.65
	base.metallic_specular = 0.12
	material = terrain.underground_lighting.make_material(base,true)
	material.set_shader_parameter("water_surface",true)
	material.set_shader_parameter("water_motion",motion.upload())
	_splash = MultiMeshInstance3D.new()
	_splash.multimesh = MultiMesh.new()
	_splash.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_splash.multimesh.mesh = BoxMesh.new()
	_splash.multimesh.instance_count = 512
	_splash.multimesh.visible_instance_count = 0
	var foam := StandardMaterial3D.new()
	foam.albedo_color = Color("#C6EDF0")
	_splash.material_override = terrain.underground_lighting.make_material(foam)
	_splash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_splash)
	var stones := preload("res://scripts/components/WaterStones.gd").new()
	stones.name = "Stones"
	stones.terrain = terrain
	add_child(stones)

func _process(_delta: float) -> void:
	visible = WaterManager.initialized
	if not WaterManager.initialized: return
	if _sound == null:
		_sound = preload("res://scripts/components/WaterSound.gd").new()
		_sound.water_view = self
		add_child(_sound)
	if _motion_flow != WaterManager.flow or WaterManager.elapsed < _motion_time or _revision != WaterManager.revision:
		_motion_flow = WaterManager.flow
		_motion_flow.track_surface_motion = true
		_motion_flow.surface_flux.clear()
		_motion_time = WaterManager.elapsed
		motion.reset()
	material.set_shader_parameter("water_time",WaterManager.elapsed)
	var motion_delta: float = WaterManager.elapsed-_motion_time
	if motion_delta >= 0.2:
		motion.gain = float(WorldGenerator.water_profile.rendering.surface_speed)*2.0
		motion.update(WaterManager.flow,motion_delta)
		_motion_time = WaterManager.elapsed
	if _revision != WaterManager.revision or _slice != terrain.slice_y:
		for tile: Vector2i in _tiles: WaterManager.dirty_tiles[tile] = true
		for key: Vector3i in WaterManager.flow.mass: WaterManager.dirty_tiles[Vector2i(key.x/32,key.z/32)] = true
		_revision = WaterManager.revision
		_slice = terrain.slice_y
	var budget := int(WorldGenerator.water_profile.rendering.tiles_per_frame)
	for tile: Vector2i in WaterManager.dirty_tiles.keys():
		WaterManager.dirty_tiles.erase(tile)
		_build(tile)
		budget -= 1
		if budget <= 0: break
	material.set_shader_parameter("water_motion",motion.upload())
	_animate_splash()

func _animate_splash() -> void:
	var index := 0
	var camera := get_viewport().get_camera_3d()
	for sites: Array in _splash_sites.values():
		for site: Dictionary in sites:
			var origin: Vector3 = site.point
			var strength := clampf(motion.velocity(site.key).length()/0.3,0.0,1.0)
			if strength < 0.1 or (camera != null and camera.global_position.distance_squared_to(origin)>6400): continue
			var seed_value := fposmod(origin.x*0.754877+origin.z*0.56984,1.0)
			for j in 3:
				if index >= 512: break
				var phase := fposmod(WaterManager.elapsed*(0.7+seed_value*0.3)+j*0.371+seed_value,1.0)
				var height := sin(phase*PI)*(0.2+strength*0.3)
				var angle := seed_value*TAU+j*2.39996
				var direction := Vector3(cos(angle),0,sin(angle))
				var pos := origin+direction*phase*0.38+Vector3(0,height,0)
				var size := (0.07+0.035*seed_value)*sin(phase*PI)*strength
				_splash.multimesh.set_instance_transform(index,Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*size),pos))
				index += 1
	_splash.multimesh.visible_instance_count = index

func _build(tile: Vector2i) -> void:
	_verts.clear()
	_norms.clear()
	_colors.clear()
	_indices.clear()
	_uvs.clear()
	_surface_data.clear()
	_falls[tile] = []
	_splash_sites[tile] = []
	var flow = WaterManager.flow
	var palette: Dictionary = WorldGenerator.water_profile.rendering
	var surface := Color(palette.surface_color)
	var foam := Color(palette.foam_color)
	for x in range(maxi(0,tile.x*32),mini(1024,tile.x*32+32)):
		for z in range(maxi(0,tile.y*32),mini(1024,tile.y*32+32)):
			for span: Vector2i in flow.spans(Vector2i(x,z)):
				var key := Vector3i(x,span.x,z)
				var amount: float = flow.volume(key)
				if amount < WaterManager.standing_depth or key.y > terrain.slice_y: continue
				var top := minf(key.y+amount,terrain.slice_y+1.0)
				# Hidden underground water must not disclose a cave through a cut.
				if key.y <= WorldGenerator.get_surface_y(x,z) and not terrain.is_revealed_air(Vector3i(x,mini(int(ceil(top))-1,terrain.slice_y),z)): continue
				# One water palette for rivers, lakes and pools. Depth changes the
				# shade subtly, rather than switching between cyan and dark blue.
				var color := surface.darkened(float(palette.depth_shading)*clampf(amount/6.0,0.0,1.0))
				var motion_slot := motion.slot(key)
				_quad(Vector3(x,top,z),Vector3(x,top,z+1),Vector3(x+1,top,z+1),Vector3(x+1,top,z),Vector3.UP,color,motion_slot)
				var outfall: float = flow.lowest_receiving_level(key)
				for dir: Vector2i in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
					var col := Vector2i(x,z)+dir
					var lower := float(key.y)
					var falling := false
					var receiver := Vector3i(-1,-1,-1)
					for next: Vector2i in flow.spans(col):
						if next.x >= top or next.y <= key.y: continue
						var next_key := Vector3i(col.x,next.x,col.y)
						receiver = next_key
						lower = minf(top,flow.level(next_key))
						falling = next.x < key.y and top-lower > 1.0
						if falling and outfall<key.y-flow.epsilon and lower>outfall+flow.epsilon:
							falling = false
							lower = float(key.y)
						break
					# Even sub-pixel steps need a closed face: skipping <.002 left
					# cracks showing the dark river bed between neighboring tops.
					if top<=lower: continue
					var normal := Vector3(dir.x,0,dir.y)
					var center := Vector3(x+0.5,top,z+0.5)+normal*0.5
					if falling: center += normal*0.025 # Avoid coplanar cliff-face flicker.
					var side := Vector3(-dir.y,0,dir.x)*0.5
					var down := Vector3(0,lower-top,0)
					# Tiny level differences are part of the surface, not dark cliff
					# walls. Keep real drops directional and retain their fall foam.
					var shading_normal := Vector3.UP if top-lower<float(palette.small_step_height) else normal
					_quad(center-side,center+side,center+side+down,center-side+down,shading_normal,color.lerp(foam,0.22) if falling else color,motion_slot,1.0 if falling else 0.0)
					if falling:
						var landing := center+down+normal*0.25
						_falls[tile].append(landing)
						_splash_sites[tile].append({"point":landing,"key":key})
						# Small broken foam patches on the wet lip and landing cell.
						var lip := center-normal*0.15+Vector3.UP*0.006
						var across := side*0.9
						var along := normal*0.1
						_quad(lip-across-along,lip+across-along,lip+across+along,lip-across+along,Vector3.UP,color,motion_slot,2.0)
						if receiver.x >= 0 and flow.volume(receiver)>=WaterManager.standing_depth:
							var pool := Vector3(col.x+0.5,lower+0.006,col.y+0.5)
							var pool_color := surface.darkened(float(palette.depth_shading)*clampf(flow.volume(receiver)/6.0,0.0,1.0))
							_quad(pool+Vector3(-0.45,0,-0.45),pool+Vector3(-0.45,0,0.45),pool+Vector3(0.45,0,0.45),pool+Vector3(0.45,0,-0.45),Vector3.UP,pool_color,motion_slot,2.0)
	if not _tiles.has(tile):
		var node := MeshInstance3D.new()
		node.name = "Water_%d_%d" % [tile.x,tile.y]
		node.material_override = material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
		_tiles[tile] = node
	if _verts.is_empty():
		_tiles[tile].mesh = null
		return
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _verts
	arrays[Mesh.ARRAY_NORMAL] = _norms
	arrays[Mesh.ARRAY_COLOR] = _colors
	arrays[Mesh.ARRAY_INDEX] = _indices
	arrays[Mesh.ARRAY_TEX_UV] = _uvs
	arrays[Mesh.ARRAY_TEX_UV2] = _surface_data
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	_tiles[tile].mesh = mesh

func _quad(a: Vector3,b: Vector3,c: Vector3,d: Vector3,n: Vector3,color: Color,motion_slot := 0,kind := 0.0) -> void:
	var i := _verts.size()
	_verts.append_array(PackedVector3Array([a,b,c,d]))
	for _j in 4:
		_norms.append(n)
		_colors.append(color)
		_surface_data.append(Vector2(motion_slot,kind))
	_uvs.append_array(PackedVector2Array([Vector2.ZERO,Vector2(0,1),Vector2.ONE,Vector2(1,0)]))
	_indices.append_array(PackedInt32Array([i,i+2,i+1,i,i+3,i+2]))
