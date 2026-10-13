extends RefCounted

## Small voxel servings, separate from haulable produce crates. Presentation
## never owns quantity; new foods can supply another serving shape and palette.
static func create(food: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "MealServing"
	var serving: Dictionary = food.get("serving",{})
	var color := Color(String(serving.get("color","b98b50")))
	if serving.get("shape","berries") == "apple":
		_cube(root,Vector3.ZERO,Vector3(.24,.24,.24),color)
		_cube(root,Vector3(0,.13,0),Vector3(.045,.10,.045),Color("63502b"))
		_cube(root,Vector3(.065,.16,0),Vector3(.10,.035,.055),Color("70854a"))
	else:
		for position in [Vector3(-.07,0,0),Vector3(.065,.01,0),Vector3(0,.1,.035)]:
			_cube(root,position,Vector3.ONE*.14,color)
			_cube(root,position+Vector3(-.025,.073,.02),Vector3(.04,.02,.04),color.lightened(.22))
	return root

static func _cube(root: Node3D, position: Vector3, size: Vector3, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = .9
	box.material = material
	mesh.mesh = box
	mesh.position = position
	root.add_child(mesh)
