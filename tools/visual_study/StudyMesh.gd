extends RefCounted

## Small authored mesh builder for this study only. Vertex palettes are linear.
var vertices := PackedVector3Array()
var normals := PackedVector3Array()
var colors := PackedColorArray()
var tags := PackedVector2Array()
var uvs := PackedVector2Array()
var indices := PackedInt32Array()

func triangle(a: Vector3, b: Vector3, c: Vector3, normal: Vector3, color: Color, tag := Vector2.ZERO) -> void:
	if (b-a).cross(c-a).dot(normal) < 0:
		var swap := b; b = c; c = swap
	var first := vertices.size()
	vertices.append_array(PackedVector3Array([a,b,c]))
	for i in range(3):
		normals.append(normal); colors.append(color); tags.append(tag); uvs.append(Vector2.ZERO)
	indices.append_array(PackedInt32Array([first,first+2,first+1]))

func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3, color: Color, tag := Vector2.ZERO) -> void:
	triangle(a,b,c,normal,color,tag)
	triangle(a,c,d,normal,color,tag)

func box(at: Vector3, size: Vector3, color: Color, bevel := 0.06, yaw := 0.0) -> void:
	var axes := [Vector3.RIGHT,Vector3.UP,Vector3.BACK]
	var half := size*.5
	var radius := minf(bevel,minf(half.x,minf(half.y,half.z))*.7)
	var rotation := Basis(Vector3.UP,yaw)
	for i in range(3):
		var j := (i+1)%3; var k := (i+2)%3
		for sign_value in [-1.0,1.0]:
			var n: Vector3 = axes[i]*sign_value
			var p := n*half[i]
			var u: Vector3 = axes[j]*(half[j]-radius)
			var v: Vector3 = axes[k]*(half[k]-radius)
			quad(at+rotation*(p-u-v),at+rotation*(p+u-v),at+rotation*(p+u+v),at+rotation*(p-u+v),rotation*n,color)
	# Twelve chamfers joining the six inset faces, plus eight corner triangles.
	for i in range(3):
		for j in range(i+1,3):
			var k := 3-i-j
			for a in [-1.0,1.0]:
				for b in [-1.0,1.0]:
					var p: Vector3 = axes[i]*a*half[i]+axes[j]*b*(half[j]-radius)
					var q: Vector3 = axes[i]*a*(half[i]-radius)+axes[j]*b*half[j]
					var along: Vector3 = axes[k]*(half[k]-radius)
					var normal: Vector3 = (axes[i]*a+axes[j]*b).normalized()
					quad(at+rotation*(p-along),at+rotation*(p+along),at+rotation*(q+along),at+rotation*(q-along),rotation*normal,color)
	for x in [-1.0,1.0]:
		for y in [-1.0,1.0]:
			for z in [-1.0,1.0]:
				var direction := Vector3(x,y,z)
				var inner := direction*(half-Vector3.ONE*radius)
				triangle(at+rotation*(inner+Vector3(x*radius,0,0)),at+rotation*(inner+Vector3(0,y*radius,0)),at+rotation*(inner+Vector3(0,0,z*radius)),rotation*direction.normalized(),color)

func log_between(a: Vector3, b: Vector3, radius: float, color: Color) -> void:
	var axis := (b-a).normalized()
	var side := axis.cross(Vector3.RIGHT if absf(axis.y)>.9 else Vector3.UP).normalized()
	var other := axis.cross(side)
	for i in range(8):
		var angle := TAU*i/8.0
		var next := TAU*(i+1)/8.0
		var u := (side*cos(angle)+other*sin(angle))*radius
		var v := (side*cos(next)+other*sin(next))*radius
		quad(a+u,a+v,b+v*.72,b+u*.72,(u+v).normalized(),color*(.88+.12*(i%3)))
		triangle(b,b+u*.72,b+v*.72,axis,color)
		triangle(a,a+v,a+u,-axis,color)

## Recessed joint + real chamfer, kept inside the block footprint. Slice caps
## use the same uniform stone family; they never sample a concealed resource.
func stone_face(corners: Array, normal: Vector3, color: Color, seed_value: float) -> void:
	var centre: Vector3 = (corners[0]+corners[2])*.5
	var rim := .05+.035*seed_value
	var inner: Array[Vector3] = []
	var outer: Array[Vector3] = []
	for corner: Vector3 in corners:
		inner.append(centre+(corner-centre)*(1.0-2.0*rim)-normal*.004)
		outer.append(centre+(corner-centre)*.988-normal*(.045+.01*seed_value))
	quad(inner[0],inner[1],inner[2],inner[3],normal,color,Vector2(3,0))
	for i in range(4):
		var j := (i+1)%4
		var n: Vector3 = (normal+((corners[i]+corners[j])*.5-centre).normalized()*.65).normalized()
		quad(outer[i],outer[j],inner[j],inner[i],n,color*.93,Vector2(3,0))
	# A dark backing covers hairline gaps, including at corner intersections.
	quad(corners[0]-normal*.06,corners[1]-normal*.06,corners[2]-normal*.06,corners[3]-normal*.06,normal,color*.48,Vector2(3,0))

## Softer earth edges and a turf cap. Every vertex stays inside the logical
## block; support heights and mining still use WorldData's original cube.
func ground_face(corners: Array, normal: Vector3, turf: bool, seed_value: float) -> void:
	var centre: Vector3 = (corners[0]+corners[2])*.5
	var rim := .045+.03*seed_value
	var depth := .036+.014*seed_value
	var soil := Color("503c2d").lerp(Color("6a5038"),seed_value*.75).srgb_to_linear()
	var grass := Color(.045,.075,.027)*(0.91+.20*seed_value)
	var top_turf := turf and normal.y > .5
	var color := grass if top_turf else soil
	var tag := Vector2(5 if top_turf else 4,0)
	var inner: Array[Vector3] = []
	var outer: Array[Vector3] = []
	for corner: Vector3 in corners:
		inner.append(centre+(corner-centre)*(1.0-2.0*rim)-normal*.004)
		outer.append(centre+(corner-centre)*.984-normal*depth)
	if turf and absf(normal.y) < .5:
		# Four uneven turf fingers break the green/brown boundary. Fill each
		# strip once, rather than overlapping a green decal on a brown face.
		var along := Vector3(normal.z,0,-normal.x)
		var bottom := centre.y-.5+rim
		var top := centre.y+.5-rim
		for i in range(4):
			var left := centre+along*(-.5+rim+(1.0-2.0*rim)*i/4.0)-normal*.004
			var right := centre+along*(-.5+rim+(1.0-2.0*rim)*(i+1)/4.0)-normal*.004
			var edge := centre.y+.5-(.18+.045*posmod(int(seed_value*101)+i*7,4))
			quad(Vector3(left.x,bottom,left.z),Vector3(right.x,bottom,right.z),Vector3(right.x,edge,right.z),Vector3(left.x,edge,left.z),normal,soil,Vector2(4,0))
			quad(Vector3(left.x,edge,left.z),Vector3(right.x,edge,right.z),Vector3(right.x,top,right.z),Vector3(left.x,top,left.z),normal,grass*.91,Vector2(5,0))
	else:
		quad(inner[0],inner[1],inner[2],inner[3],normal,color,tag)
	for i in range(4):
		var j := (i+1)%4
		var edge_centre: Vector3 = (corners[i]+corners[j])*.5
		var n: Vector3 = (normal+(edge_centre-centre).normalized()*.5).normalized()
		var grassy_edge := top_turf or (turf and edge_centre.y > centre.y+.4)
		var edge_color := grass if grassy_edge else soil
		quad(outer[i],outer[j],inner[j],inner[i],n,edge_color*.94,Vector2(5 if grassy_edge else 4,0))
		# Close the recessed perimeter at the true cell boundary. Neighbour
		# faces are culled, so leaving this open exposes the background at steps.
		quad(corners[i],corners[j],outer[j],outer[i],normal,edge_color*.72,Vector2(5 if grassy_edge else 4,0))
	quad(corners[0]-normal*.06,corners[1]-normal*.06,corners[2]-normal*.06,corners[3]-normal*.06,normal,color*.7,tag)

func append_arrays(arrays: Array, transform: Transform3D, tag: Vector2) -> void:
	var first := vertices.size()
	for i in range(arrays[Mesh.ARRAY_VERTEX].size()):
		vertices.append(transform*arrays[Mesh.ARRAY_VERTEX][i])
		normals.append(transform.basis*arrays[Mesh.ARRAY_NORMAL][i])
		colors.append(Color.WHITE)
		tags.append(tag)
		uvs.append(arrays[Mesh.ARRAY_TEX_UV][i])
	for index in arrays[Mesh.ARRAY_INDEX]: indices.append(first+index)

func to_mesh() -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV2] = tags
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var result := ArrayMesh.new()
	if not vertices.is_empty(): result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return result
