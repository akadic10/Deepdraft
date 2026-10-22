extends SceneTree

const DIRECTORY := "res://assets/models/furniture/"
const VoxelShadows=preload("res://scripts/components/VoxelShadowSetup.gd")
var staged: Array[PackedScene]=[]
var failures: Array[String] = []
var checks := 0

func _init() -> void: _run.call_deferred()

func expect(value: bool, message: String) -> void:
	checks+=1
	if not value: failures.append(message)

func _run() -> void:
	if "--staged" in OS.get_cmdline_user_args(): staged=preload("res://tools/voxel_assets/StagedAssets.gd").install("furniture")
	create_timer(60).timeout.connect(func(): push_error("Furniture catalogue art timeout"); quit(1))
	for id in ["SaveManager","TaskManager","WorldClock","RoomManager","StockpileManager"]:
		root.get_node(id).set_process(false)
	root.get_node("WorldGenerator").world_seed=1234
	var scene := Node3D.new(); root.add_child(scene); current_scene=scene
	var controller = load("res://scripts/systems/FurniturePlacementController.gd").new()
	controller._load_defs()
	var materials := root.get_node("CraftMaterials")
	var picking = load("res://scripts/components/ObjectPicking.gd").new()
	var count := 0
	for file in DirAccess.get_files_at(DIRECTORY):
		if not file.ends_with(".glb"): continue
		count+=1
		var model: Node3D=load(DIRECTORY+file).instantiate()
		scene.add_child(model)
		expect(VoxelShadows.configure(model)>0,file+" proxy pairs")
		expect(model.transform.is_equal_approx(Transform3D.IDENTITY),file+" unit root")
		expect(model.find_children("*","CollisionObject3D",true,false).is_empty(),file+" no embedded collision")
		for mesh: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
			expect(mesh.transform.is_equal_approx(Transform3D.IDENTITY),file+" baked origin")
			expect(mesh.mesh.get_surface_count()==1,file+" one surface per named part")
			var colors: PackedColorArray=mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
			var opaque := not colors.is_empty()
			for color in colors:
				if color.a<.999: opaque=false
			expect(opaque,file+" opaque colors")
		var bounds := _bounds(model)
		if file.begins_with("log_bridge_"):
			var span := int(file.get_basename().get_slice("_",2))
			expect(bounds.position.x>=-.501 and bounds.end.x<=1.501,file+" bank-relative width")
			expect(bounds.position.z>=-span-1.501 and bounds.end.z<=.501,file+" landing anchors")
			expect(bounds.position.y>=-.626 and absf(bounds.end.y)<.001,file+" walking surface")
		else:
			expect(absf(bounds.position.y)<.001,file+" ground or wall origin %.4f"%bounds.position.y)
		if file.begins_with("crude_ladder_"):
			expect(absf(bounds.end.y-float(file.get_basename().get_slice("_",2)))<.001,file+" section height")
		model.free()
	expect(count==29,"all 29 retained furniture forms")
	var definitions := 0
	for key: String in controller.get_defs():
		if not String(controller.get_defs()[key].model).begins_with(DIRECTORY): continue
		definitions+=1
		var definition: Dictionary=controller.get_defs()[key]
		expect(String(definition.model).begins_with(DIRECTORY),key+" production path")
		var model: Node3D=controller._instance_model(key,controller._make_solid_material())
		scene.add_child(model)
		var bounds := _bounds(model)
		if definition.placement=="floor":
			var fp: Dictionary=definition.footprint
			expect(bounds.position.x>=-float(fp.width)*.5-.001 and bounds.end.x<=float(fp.width)*.5+.001 and bounds.position.z>=-float(fp.depth)*.5-.001 and bounds.end.z<=float(fp.depth)*.5+.001,key+" footprint "+str(bounds))
		if definition.has("material_palette"):
			_palette(controller,materials,key,definition,model)
		if definition.has("door_animation"):
			var hinge = load("res://scripts/components/FurnitureDoorAnimation.gd").new()
			model.add_child(hinge); hinge.setup(model,definition.door_animation); hinge.set_process(false)
			var width := int(definition.footprint.width)
			expect(hinge._hinges.size()==(2 if width==4 else 1),key+" named leaf count")
			expect(is_equal_approx(hinge._hinges[0].position.x,-width*.5+float(definition.door_animation.get("hinge_inset",.125))),key+" authored hinge")
			var hit_height := 1.0 if key=="base:furniture:log_gate" else 2.0
			expect(is_finite(picking.hit_distance(model,Vector3(.1,hit_height,3),Vector3(.1,hit_height,-3))),key+" closed picking")
			for i in hinge._hinges.size(): hinge._hinges[i].rotation.y=PI*.5*(1 if i==0 else -1)
			expect(not is_finite(picking.hit_distance(model,Vector3(.1,hit_height,3),Vector3(.1,hit_height,-3))),key+" clear open doorway")
		if definition.has("light_source"):
			var light: Dictionary=definition.light_source
			var flame := model.find_child(light.emissive_mesh,true,false) as MeshInstance3D
			expect(flame!=null,key+" named flame")
			var clip: Dictionary=load("res://scripts/components/FurnitureFlameAnimation.gd")._load_clip(light.flame_animation.model)
			for frame in light.flame_animation.frames: expect(clip.has(frame),key+" frame "+frame)
		var id := key.get_slice(":",2)
		if id in ["log_chair","bench","log_table","log_bed","crude_workbench","board_game_table"]:
			var point := Vector3(.11,4,.11)
			var height: float=4-picking.hit_distance(model,point,point-Vector3(0,6,0))
			var expected: float=float(definition.crafting_surface_height) if id=="crude_workbench" else float(definition.game_surface_height) if id=="board_game_table" else float(definition.dining_surface_height) if id=="log_table" else {"log_chair":.875,"bench":1.0,"log_bed":.75}[id]
			# Non-grid legacy presentation contacts round by at most half a cell.
			expect(absf(expected-snappedf(expected,1.0/16))<=1.0/32,id+" bounded contact quantization")
			expect(absf(height-snappedf(expected,1.0/16))<(.075 if id=="log_bed" else .001),id+" central contact %.4f"%height)
		model.free()
	expect(definitions==19,"all 19 retained furniture definitions")
	controller.free()
	for failure in failures: push_error(failure)
	print("FURNITURE_VOXEL_ART_OK: %d import, palette, footprint, contact, hinge and flame checks"%checks if failures.is_empty() else "FURNITURE_VOXEL_ART_FAIL")
	quit(0 if failures.is_empty() else 1)

func _bounds(model: Node3D) -> AABB:
	var bounds := AABB(); var first := true
	for mesh: MeshInstance3D in VoxelShadows.visual_meshes(model):
		var box: AABB=model.global_transform.affine_inverse()*mesh.global_transform*mesh.get_aabb()
		bounds=box if first else bounds.merge(box); first=false
	return bounds

func _palette(controller: Node,materials: Node,key: String,definition: Dictionary,original: Node3D) -> void:
	var hashes := {}
	var originals := VoxelShadows.visual_meshes(original)
	for wood in ["pine","oak","juniper","applewood"]:
		var model: Node3D=controller._instance_model(key,controller._make_solid_material())
		materials.apply_palette(model,definition,"base:material:"+wood)
		var meshes := VoxelShadows.visual_meshes(model)
		var swatches: Array=[]
		var profile: Dictionary=materials.palettes[definition.material_palette]
		for role in profile.colors:
			var color := Color(String(profile.colors[role])).srgb_to_linear()
			if int(profile.get("encoding",1))==2: color=color.srgb_to_linear()
			var packed := Color(floorf(color.r*255)/255,floorf(color.g*255)/255,floorf(color.b*255)/255)
			swatches.append([color,packed,Color(String(materials.definitions["base:material:"+wood].colors[role])).srgb_to_linear()])
		var correct := true; var changed := 0; var digest := []
		for i in meshes.size():
			var before: Array=originals[i].mesh.surface_get_arrays(0)
			var after: Array=meshes[i].mesh.surface_get_arrays(0)
			expect(before[Mesh.ARRAY_VERTEX]==after[Mesh.ARRAY_VERTEX] and before[Mesh.ARRAY_INDEX]==after[Mesh.ARRAY_INDEX],key+" unchanged geometry "+wood)
			var shades=before[Mesh.ARRAY_TEX_UV2]
			for j in before[Mesh.ARRAY_COLOR].size():
				var expected: Color=before[Mesh.ARRAY_COLOR][j]
				var shade := 1.0 if shades==null or j>=shades.size() else float(shades[j].x)
				if shade<.999:
					# Baked occlusion (doc 256): a darkened wood swatch becomes the same
					# darkened target wood; every other color stays exactly as authored.
					var best := 1.5/255.0
					var shaded := expected
					for swatch in swatches:
						var source: Color=swatch[0]
						var error := maxf(absf(expected.r-source.r*shade),maxf(absf(expected.g-source.g*shade),absf(expected.b-source.b*shade)))
						if error<best:
							var goal: Color=swatch[2]
							best=error; shaded=Color(goal.r*shade,goal.g*shade,goal.b*shade)
					if shaded!=expected: changed+=1
					expected=shaded
				else:
					for swatch in swatches:
						if _close(expected,swatch[0]) or _close(expected,swatch[1]): expected=swatch[2]; changed+=1; break
				var packed := Color(floorf(expected.r*255)/255,floorf(expected.g*255)/255,floorf(expected.b*255)/255)
				if not _close(after[Mesh.ARRAY_COLOR][j],expected) and not _close(after[Mesh.ARRAY_COLOR][j],packed): correct=false
				digest.append(after[Mesh.ARRAY_COLOR][j])
			expect(originals[i].mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]==before[Mesh.ARRAY_COLOR],key+" source unchanged")
		expect(correct and changed>0,key+" exact wood mapping and preserved non-wood "+wood)
		hashes[hash(digest)]=true
		model.free()
	expect(hashes.size()==4,key+" four wood appearances")


func _close(a: Color,b: Color) -> bool:
	return maxf(absf(a.r-b.r),maxf(absf(a.g-b.g),absf(a.b-b.b)))<.0001
