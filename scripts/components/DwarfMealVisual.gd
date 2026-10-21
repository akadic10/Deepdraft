extends RefCounted

## Offline-baked, non-casting servings. Colored geometry is cached by shape/tint;
## eating creates one shared mesh instance and never meshes a volume.
static var _meshes: Dictionary = {}
static var _material: StandardMaterial3D

static func create(food: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name="MealServing"
	preload("res://scripts/components/VoxelShadowSetup.gd").set_casting(root,false)
	var serving: Dictionary=food.get("serving",{})
	var shape := String(serving.get("shape","berries"))
	if not DwarfAssets.meal_servings.has(shape): shape="berries"
	var color := Color(String(serving.get("color","b98b50")))
	var key := shape+":"+color.to_html()
	if not _meshes.has(key):
		var model: Node3D=DwarfAssets.meal_servings[shape].instantiate()
		var source: Mesh=preload("res://scripts/components/VoxelShadowSetup.gd").visual_meshes(model)[0].mesh
		var arrays := source.surface_get_arrays(0).duplicate(true)
		var colors: PackedColorArray=arrays[Mesh.ARRAY_COLOR]
		for i in colors.size():
			# White is the food swatch. Apple stalk/leaf retain their own palette.
			if colors[i].r>.999 and colors[i].g>.999 and colors[i].b>.999: colors[i]=color.srgb_to_linear()
		arrays[Mesh.ARRAY_COLOR]=colors
		var baked := ArrayMesh.new()
		baked.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		_meshes[key]=baked
		model.free()
	if _material==null:
		_material=StandardMaterial3D.new()
		_material.vertex_color_use_as_albedo=true
		_material.roughness=.9
	var mesh := MeshInstance3D.new()
	mesh.mesh=_meshes[key]
	mesh.material_override=_material
	mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.gi_mode=GeometryInstance3D.GI_MODE_DISABLED
	root.add_child(mesh)
	return root
