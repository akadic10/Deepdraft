extends SceneTree

const Shadows = preload("res://scripts/components/VoxelShadowSetup.gd")
var failures: Array[String] = []
var checks := 0

func _init() -> void: _run.call_deferred()

func _run() -> void:
	for node in root.get_children(): node.set_process(false)
	var scene := Node3D.new()
	root.add_child(scene); current_scene=scene
	var servings=load("res://scripts/components/DwarfMealVisual.gd")
	for shape in ["berries","apple"]:
		for color in ["643d7a","506dad","ca4342","67728c","b34d35"]:
			var a: Node3D=servings.create({"serving":{"shape":shape,"color":color}})
			var b: Node3D=servings.create({"serving":{"shape":shape,"color":color}})
			var meshes := Shadows.visual_meshes(a)
			_expect(meshes.size()==1,"one baked serving draw instead of separate cube nodes")
			_expect(meshes[0].mesh==Shadows.visual_meshes(b)[0].mesh,"repeated serving reuses cached colored mesh")
			_expect(meshes[0].material_override==Shadows.visual_meshes(b)[0].material_override,"servings share material")
			_expect(meshes[0].cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,"tiny serving does not cast")
			var arrays := meshes[0].mesh.surface_get_arrays(0)
			var found := false
			var expected_color := Color(color).srgb_to_linear()
			for vertex_color: Color in arrays[Mesh.ARRAY_COLOR]:
				# Native ArrayMesh stores vertex colors in 8-bit normalized channels.
				if maxf(absf(vertex_color.r-expected_color.r),maxf(absf(vertex_color.g-expected_color.g),absf(vertex_color.b-expected_color.b)))<=1.0/255.0+.00001: found=true
			_expect(found,"existing food tint survives baked geometry: actual %s, expected %s"%[arrays[Mesh.ARRAY_COLOR][0],Color(color).srgb_to_linear()])
			for vertex: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
				_expect((vertex*16-(vertex*16).round()).length()<.025,"serving uses exact source cell size")
			a.free(); b.free()
	var factory=load("res://scripts/entities/DwarfFactory.gd").new()
	var actor=factory.spawn(factory.generate(47,{}),47)
	scene.add_child(actor); actor.set_process(false)
	actor.get_node("Readability").set_process(false)
	actor._rest_behavior.pose="sitting"; actor._rest_behavior.blend=1
	actor._rest_behavior._apply_pose()
	_expect(not actor._head.get_node("MeshEyes").visible,"sleep hides open eyes")
	var lids: Node3D=actor._rest_behavior._eyelids
	var lid_meshes := Shadows.visual_meshes(lids).filter(func(mesh): return mesh.name!="OccludedSilhouette")
	_expect(lids.visible and lid_meshes.size()==1,"closed lids share one baked overlay, plus the existing occlusion outline")
	for mesh in Shadows.visual_meshes(lids):
		_expect(mesh.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,"eyelids never cast")
	actor._rest_behavior.cancel()
	_expect(not lids.visible and actor._head.get_node("MeshEyes").visible,"waking restores eyes")
	actor.free()
	for failure in failures: push_error(failure)
	print("VOXEL_PRESENTATION_PASS " if failures.is_empty() else "VOXEL_PRESENTATION_FAIL ",checks)
	quit(0 if failures.is_empty() else 1)

func _expect(ok: bool, message: String) -> void:
	checks+=1
	if not ok: failures.append(message)
