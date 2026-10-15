extends RefCounted

## Worker-owned geometry only. The snapshot contains copied values, never live
## scene nodes, solver state, textures or materials. GPU upload stays on the main thread.
var snapshot: Dictionary
var result: Dictionary = {}
var falls: Array = []
var splash_sites: Array = []
var _verts := PackedVector3Array()
var _norms := PackedVector3Array()
var _colors := PackedColorArray()
var _indices := PackedInt32Array()
var _uvs := PackedVector2Array()
var _surface_data := PackedVector2Array()

func build() -> void:
	var started := Time.get_ticks_usec()
	var flow = preload("res://scripts/components/WaterFlow.gd").new()
	flow._spans = snapshot.spans
	flow.mass = snapshot.mass
	flow.epsilon = snapshot.epsilon
	var palette: Dictionary = snapshot.palette
	var surface := Color(palette.surface_color)
	var foam := Color(palette.foam_color)
	for key: Vector3i in snapshot.visible:
		var x := key.x
		var z := key.z
		var amount: float = flow.volume(key)
		if amount < float(snapshot.standing_depth) or key.y > int(snapshot.slice): continue
		var top := minf(key.y+amount,int(snapshot.slice)+1.0)
		# One water palette for rivers, lakes and pools. Depth changes the
		# shade subtly, rather than switching between cyan and dark blue.
		var color := surface.darkened(float(palette.depth_shading)*clampf(amount/6.0,0.0,1.0))
		var motion_slot := int(snapshot.visible[key])
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
				falls.append(landing)
				splash_sites.append({"point":landing,"key":key})
				# Small broken foam patches on the wet lip and landing cell.
				var lip := center-normal*0.15+Vector3.UP*0.006
				var across := side*0.9
				var along := normal*0.1
				_quad(lip-across-along,lip+across-along,lip+across+along,lip-across+along,Vector3.UP,color,motion_slot,2.0)
				if receiver.x >= 0 and flow.volume(receiver)>=float(snapshot.standing_depth):
					var pool := Vector3(col.x+0.5,lower+0.006,col.y+0.5)
					var pool_color := surface.darkened(float(palette.depth_shading)*clampf(flow.volume(receiver)/6.0,0.0,1.0))
					_quad(pool+Vector3(-0.45,0,-0.45),pool+Vector3(-0.45,0,0.45),pool+Vector3(0.45,0,0.45),pool+Vector3(0.45,0,-0.45),Vector3.UP,pool_color,motion_slot,2.0)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _verts
	arrays[Mesh.ARRAY_NORMAL] = _norms
	arrays[Mesh.ARRAY_COLOR] = _colors
	arrays[Mesh.ARRAY_INDEX] = _indices
	arrays[Mesh.ARRAY_TEX_UV] = _uvs
	arrays[Mesh.ARRAY_TEX_UV2] = _surface_data
	result = {"arrays":arrays,"falls":falls,"splash_sites":splash_sites,
		"build_usec":Time.get_ticks_usec()-started}

func _quad(a: Vector3,b: Vector3,c: Vector3,d: Vector3,n: Vector3,color: Color,motion_slot := 0,kind := 0.0) -> void:
	var i := _verts.size()
	_verts.append_array(PackedVector3Array([a,b,c,d]))
	for _j in 4:
		_norms.append(n)
		_colors.append(color)
		_surface_data.append(Vector2(motion_slot,kind))
	_uvs.append_array(PackedVector2Array([Vector2.ZERO,Vector2(0,1),Vector2.ONE,Vector2(1,0)]))
	_indices.append_array(PackedInt32Array([i,i+2,i+1,i,i+3,i+2]))
