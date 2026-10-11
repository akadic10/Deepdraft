extends SceneTree

class Terrain:
	extends Node3D
	var slice_y := 127
	func is_revealed_air(_cell: Vector3i) -> bool: return true

func _init() -> void: _run.call_deferred()
func _run() -> void:
	var gen = root.get_node("WorldGenerator")
	gen.water_profile = gen.load_water_profile()
	var owner = root.get_node("WaterManager")
	var flow = preload("res://scripts/components/WaterFlow.gd").new()
	var cells := {Vector2i(31,8):120,Vector2i(32,8):120,Vector2i(33,8):117}
	flow.spans_at = func(p: Vector2i) -> Array: return [Vector2i(cells[p],128)] if cells.has(p) else []
	flow.seed_column(Vector3i(31,120,8),0.75)
	flow.seed_column(Vector3i(32,120,8),0.7499)
	flow.seed_column(Vector3i(33,117,8),0.75)
	owner.flow = flow
	var original: Dictionary = flow.serialize()
	var renderer = load("res://scripts/components/WaterRenderer.gd").new()
	renderer.terrain = Terrain.new()
	var closed := false
	var small_normal := false
	var real_fall := false
	for tile in [Vector2i(0,0),Vector2i(1,0)]:
		renderer._build(tile)
		var mesh: ArrayMesh = renderer._tiles[tile].mesh
		var arrays: Array = mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for i in range(0,vertices.size(),4):
			var a := vertices[i]
			var c := vertices[i+2]
			if a.x==32 and c.x==32 and a.y>c.y:
				closed = absf(a.y-120.75)<0.00001 and absf(c.y-120.7499)<0.00001
				small_normal = normals[i].dot(Vector3.UP)>0.9999
			if a.x>33 and a.x<33.1 and a.y-c.y>2 and normals[i].x>0.9: real_fall = true
	var ok := closed and small_normal and real_fall and flow.serialize()==original
	print("WaterSurfaceMeshTest: ","PASS" if ok else "FAIL"," watertight tile edge=",closed," surface shading=",small_normal," waterfall=",real_fall)
	renderer.terrain.free()
	renderer.free()
	quit(0 if ok else 1)
