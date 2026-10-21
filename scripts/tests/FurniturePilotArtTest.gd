extends SceneTree

const Assets = preload("res://tools/furniture_pilot/FurniturePilotAssets.gd")
var failures: Array[String] = []
var checks := 0

func _init() -> void: _run.call_deferred()

func expect(value: bool, message: String) -> void:
	checks+=1
	if not value: failures.append(message)

func _run() -> void:
	create_timer(30).timeout.connect(func(): push_error("Furniture art test timed out"); quit(1))
	for id in ["SaveManager","TaskManager","WorldClock","RoomManager","StockpileManager"]:
		root.get_node(id).set_process(false)
	root.get_node("WorldGenerator").world_seed=1234
	var scene := Node3D.new(); root.add_child(scene); current_scene=scene
	var controller = load("res://scripts/systems/FurniturePlacementController.gd").new()
	controller._load_defs()
	var definitions: Dictionary=controller.get_defs().duplicate(true)
	var saved := Assets.install(controller)
	var materials := root.get_node("CraftMaterials")
	var picking = load("res://scripts/components/ObjectPicking.gd").new()
	for part in Assets.PARTS:
		var key: String="base:furniture:"+part
		var definition: Dictionary=controller.get_defs()[key]
		var gameplay: Dictionary=definition.duplicate(true); gameplay.model=definitions[key].model
		expect(gameplay==definitions[key],part+" only model path changes")
		var original: Node3D=controller._instance_model(key,controller._make_solid_material())
		scene.add_child(original)
		expect(original.transform.is_equal_approx(Transform3D.IDENTITY),part+" unit root")
		expect(original.find_children("*","CollisionObject3D",true,false).is_empty(),part+" no embedded physics")
		var meshes := original.find_children("*","MeshInstance3D",true,false)
		expect(meshes.size()==1,part+" one mesh")
		var mesh := meshes[0] as MeshInstance3D
		expect(mesh.transform.is_equal_approx(Transform3D.IDENTITY),part+" baked vertices")
		expect(mesh.mesh.get_surface_count()==1,part+" one surface")
		var bounds: AABB=mesh.get_aabb()
		var fp: Dictionary=definition.footprint
		expect(bounds.position.x>=-float(fp.width)*.5-.001 and bounds.end.x<=float(fp.width)*.5+.001 and bounds.position.z>=-float(fp.depth)*.5-.001 and bounds.end.z<=float(fp.depth)*.5+.001,part+" visual footprint")
		expect(absf(bounds.position.y)<.001,part+" ground contact")
		var arrays := mesh.mesh.surface_get_arrays(0)
		var source_colors: PackedColorArray=arrays[Mesh.ARRAY_COLOR]
		var opaque := true
		for color in source_colors:
			if color.a<.999: opaque=false
		expect(opaque,part+" opaque color")
		var hashes := {}
		for wood in ["pine","oak","juniper","applewood"]:
			var model: Node3D=controller._instance_model(key,controller._make_solid_material())
			materials.apply_palette(model,definition,"base:material:"+wood)
			var target_mesh := model.find_children("*","MeshInstance3D",true,false)[0] as MeshInstance3D
			var target_arrays := target_mesh.mesh.surface_get_arrays(0)
			expect(target_arrays[Mesh.ARRAY_VERTEX]==arrays[Mesh.ARRAY_VERTEX] and target_arrays[Mesh.ARRAY_INDEX]==arrays[Mesh.ARRAY_INDEX],part+" recolor retains geometry "+wood)
			var target_colors: PackedColorArray=target_arrays[Mesh.ARRAY_COLOR]
			var palette: Dictionary=materials.palettes[definition.material_palette].colors
			var targets: Dictionary=materials.definitions["base:material:"+wood].colors
			var swatches: Array[Array] = []
			for role in palette:
				var color := Color(String(palette[role])).srgb_to_linear()
				var packed := Color(floorf(color.r*255)/255,floorf(color.g*255)/255,floorf(color.b*255)/255)
				swatches.append([color,packed,Color(String(targets[role])).srgb_to_linear()])
			var correct := true; var wood_count := 0; var other_count := 0
			for index in source_colors.size():
				var expected := source_colors[index]; var mapped := false
				for swatch in swatches:
					if _close(expected,swatch[0]) or _close(expected,swatch[1]):
						expected=swatch[2]; mapped=true; break
				var packed_expected := Color(floorf(expected.r*255)/255,floorf(expected.g*255)/255,floorf(expected.b*255)/255)
				if not _close(target_colors[index],expected) and not _close(target_colors[index],packed_expected): correct=false
				if mapped: wood_count+=1
				else: other_count+=1
			expect(correct and wood_count>0,part+" exact semantic recoloring "+wood)
			if part=="log_bed": expect(other_count>0,wood+" hay and leaves remain independent of wood")
			hashes[hash(target_colors)]=true
			model.free()
		expect(hashes.size()==4,part+" four distinct wood appearances")
		expect(mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]==source_colors,part+" shared source unchanged")
		if part=="log_chair":
			var hit: float=picking.hit_distance(original,Vector3(0,2,0),Vector3(0,-1,0))
			expect(absf((2-hit)-.875)<.001,"player-authored selectable seat top at .875")
		if part=="log_bed":
			var hit: float=picking.hit_distance(original,Vector3(.2,2,.2),Vector3(.2,-1,.2))
			expect(2-hit>=.70 and 2-hit<=.80,"central bedding supports existing .75 sleep surface")
			expect(bounds.end.y<=1.001,"head hay remains below one block")
		if part=="door":
			expect(original.find_child("leaf_left",true,false)!=null and meshes[0].name=="leaf_left","all door geometry belongs to the named leaf")
			expect(bounds.end.y<4,"uneven door top fits opening")
			var hinges = load("res://scripts/components/FurnitureDoorAnimation.gd").new()
			original.add_child(hinges); hinges.setup(original,definition.door_animation); hinges.set_process(false)
			expect(hinges._hinges.size()==1 and is_equal_approx(hinges._hinges[0].position.x,-1),"outer-edge hinge anchor")
			expect(is_finite(picking.hit_distance(original,Vector3(0,2,3),Vector3(0,2,-3))),"closed door can be picked")
			hinges._hinges[0].rotation.y=PI*.5
			expect(not is_finite(picking.hit_distance(original,Vector3(0,2,3),Vector3(0,2,-3))),"open leaf clears the center of the opening")
		original.free()
	Assets.restore(controller,saved)
	expect(controller.get_defs()==definitions,"study restores all owner definitions")
	controller.free()
	for failure in failures: push_error(failure)
	print("FURNITURE_PILOT_ART_OK: %d imported, palette, contact and hinge checks"%checks if failures.is_empty() else "FURNITURE_PILOT_ART_FAIL")
	quit(0 if failures.is_empty() else 1)

func _close(a: Color,b: Color) -> bool:
	return maxf(absf(a.r-b.r),maxf(absf(a.g-b.g),absf(a.b-b.b)))<.0001
