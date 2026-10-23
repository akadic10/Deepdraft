extends SceneTree
## Every dwarf appearance part on the 1:16 grid: imports, pairs, contacts, poses and tints.

const Shadows = preload("res://scripts/components/VoxelShadowSetup.gd")
var failures: Array[String] = []
var checks := 0

func _init() -> void: _run.call_deferred()

func expect(value: bool, message: String) -> void:
	checks+=1
	if not value: failures.append(message)

func _run() -> void:
	create_timer(90).timeout.connect(func(): push_error("Dwarf roster art timeout"); quit(1))
	for id in ["SaveManager","WorldClock","TaskManager","RoomManager","StockpileManager","SkyController","WeatherManager"]:
		root.get_node(id).set_process(false)
	root.get_node("WorldGenerator").world_seed=1234
	var registry := root.get_node("DwarfAssets")
	var scene := Node3D.new()
	root.add_child(scene); current_scene=scene
	var packed_parts := []
	for key in ["heads","hair_male","hair_female","beards","brows_male","brows_female","scars"]:
		for packed in registry.get(key).values():
			if packed != null: packed_parts.append(packed)
	for key in ["eyes","body","hand","foot"]: packed_parts.append(registry.get(key))
	expect(packed_parts.size()==41,"all 41 appearance models")
	for packed: PackedScene in packed_parts:
		expect(packed.resource_path.begins_with("res://assets/models/characters/dwarves/"),"production registry uses dwarf part")
		var part := packed.instantiate() as Node3D
		expect(part.transform.is_equal_approx(Transform3D.IDENTITY),"part has baked unit origin")
		expect(part.find_children("*","CollisionObject3D",true,false).is_empty(),"art adds no collision")
		var meshes := Shadows.visual_meshes(part)
		var pairs := 2 if packed == registry.hand else 1   # the Hearthblock mitten and its tunic cuff (doc 256)
		expect(meshes.size()==pairs and Shadows.configure(part)==pairs,"one visual and paired proxy per part")
		for mesh: MeshInstance3D in meshes:
			expect(mesh.transform.is_equal_approx(Transform3D.IDENTITY),"shared frame")
			expect(mesh.mesh.get_surface_count()==1,"one surface per part")
			expect(mesh.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,"detailed part never casts")
			expect(Shadows.proxy_for_visual(mesh).cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY,"coarse part only casts")
			var colors: PackedColorArray=mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
			var opaque := not colors.is_empty()
			for color in colors:
				if color.a<.999: opaque=false
			expect(opaque,"opaque vertex colors")
			expect(mesh.get_aabb().position.y>=-.001 and mesh.get_aabb().end.y<=3.375,"shared height envelope")
		part.free()
	var factory = load("res://scripts/entities/DwarfFactory.gd").new()
	var pools: Dictionary=registry.get_appearance_pools()
	var combinations := 0
	for gender in ["male","female"]:
		var beards := [""]
		if gender=="male": beards.append_array(registry.beards.keys())
		for age in registry.heads:
			for hair in pools[gender].hair_style:
				for brow in pools[gender].eyebrow_style:
					for beard in beards:
						var a := DwarfAppearanceData.new()
						a.gender=gender; a.age_tier=age; a.hair_style=hair.id; a.eyebrow_style=brow.id; a.beard_style=beard
						var actor = factory.spawn({"name":"Roster QA","gender":gender,"appearance":a},5000+combinations)
						if combinations==0: _check_mirrored_limb_geometry(actor,registry)
						expect(actor.has_node("MeshHead/MeshHair")== (hair.id!="bald"),"optional hair "+hair.id)
						expect(actor.has_node("MeshHead/MeshBeard")== (beard!=""),"optional beard "+beard)
						expect(actor.has_node("MeshHead/MeshBrows") and actor.has_node("MeshHead/MeshEyes"),"face slots")
						expect(not actor.has_node("MeshHead/MeshScar"),"scar excluded from world actor")
						expect(actor.get_node("LogicalBox").shape.size==Vector3(1,3,1),"logical footprint")
						expect(actor._head.scale==Vector3.ONE and actor._body.scale==Vector3.ONE,"baked proportions preserve cubic cells")
						expect(actor._hand_r.scale.x==-1 and actor._foot_r.scale.x==-1,"right-side mirrors")
						var saved: Dictionary=actor.serialize_state().appearance
						expect(saved.hair_style==hair.id and saved.beard_style==beard and saved.age_tier==age and saved.eyebrow_style==brow.id,"save appearance IDs")
						actor.free(); combinations+=1
	expect(combinations==800,"all current map combinations")
	# Each dwarf's own tunic colour (doc 256): one shared recoloured torso per colour,
	# kept in the saved appearance.
	var torsos := {}
	for id in range(6100,6106):
		var actor = factory.spawn({"name":"Tunic QA","gender":"male","appearance":DwarfAppearanceData.new()},id)
		torsos[actor.appearance.clothing]=Shadows.visual_meshes(actor._body)[0].mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
		expect(actor.serialize_state().appearance.clothing==actor.appearance.clothing,"clothing is saved")
		actor.free()
	expect(torsos.size()==6,"six dwarves in a row wear six tunic colours")
	var colors: Array = torsos.values()
	var distinct := true
	for i in colors.size():
		for j in range(i+1,colors.size()):
			if colors[i]==colors[j]: distinct=false
	expect(distinct,"every tunic colour recolours the torso")
	var cases := []
	for gender in ["male","female"]:
		for entry in pools[gender].hair_style: cases.append([gender,entry.id,""])
	for beard in registry.beards: cases.append(["male","short_back",beard])
	for spec in cases:
		var a := DwarfAppearanceData.new()
		a.gender=spec[0]; a.hair_style=spec[1]; a.beard_style=spec[2]
		var actor = factory.spawn({"name":"Pose QA","gender":a.gender,"appearance":a},6000)
		scene.add_child(actor); actor.position=Vector3(40,21,40)
		actor.set_process(false); actor.get_node("Readability").set_process(false)
		for phase in [.0,.2,.55,.93]:
			for rig in [actor._mining_pose,actor._felling_pose]:
				actor._reset_part_offsets(); rig.apply(phase,Vector3(0,1.2,1.4))
				expect((actor._hand_r.global_transform*rig.PALM).distance_to(rig.tool.global_position)<.001,"lower work grip")
				expect((actor._hand_l.global_transform*rig.PALM).distance_to(rig.tool.global_transform*rig.SUPPORT_GRIP)<.001,"upper work grip")
			actor._reset_part_offsets(); actor._walk_cycle=phase; actor._movement.walk_bob(0)
			for foot in [actor._foot_l,actor._foot_r]: expect(_lowest(actor,foot)>=-.065,"walking sole")
		actor._reset_part_offsets()
		for pose in ["lying","sitting"]:
			actor._rest_behavior.pose=pose; actor._rest_behavior.blend=1; actor._rest_behavior._apply_pose()
			expect(not actor._head.get_node("MeshEyes").visible,"sleep closes eyes")
			for part in [actor._head,actor._body,actor._hand_l,actor._hand_r,actor._foot_l,actor._foot_r]:
				expect(_lowest(actor,part)>=-.025,"rest clearance "+str(spec)+" "+pose+" "+str(part.name))
		actor._rest_behavior.cancel(); actor._reset_part_offsets()
		actor.apply_slice(20); expect(not actor.visible,"slice concealment")
		actor.apply_slice(127); expect(actor.visible,"slice restore")
		if spec==cases[0]:
			for scar in registry.scars:
				a.scar=scar
				var texture := TextureRect.new(); scene.add_child(texture)
				var portrait=load("res://scripts/ui/DwarfPortrait.gd")
				var viewport: SubViewport=portrait.create_viewport(texture)
				var model: Node3D=portrait.create_model(viewport,actor)
				expect(model.has_node("MeshScar"),"portrait scar "+scar)
				expect(not actor.has_node("MeshHead/MeshScar"),"portrait does not alter source")
				texture.free()
		actor.free()
	for error in failures: push_error(error)
	print("DWARF_VOXEL_ART_OK: %d checks, 41 imported models, 800 appearances, 22 pose cases"%checks if failures.is_empty() else "DWARF_VOXEL_ART_FAIL")
	quit(0 if failures.is_empty() else 1)

func _check_mirrored_limb_geometry(actor: Node3D, registry: Node) -> void:
	for pair in [[actor._hand_l,actor._hand_r],[actor._foot_l,actor._foot_r]]:
		var left: MeshInstance3D=pair[0].find_children("*","MeshInstance3D",true,false)[0]
		var right: MeshInstance3D=pair[1].find_children("*","MeshInstance3D",true,false)[0]
		var source: Array=left.mesh.surface_get_arrays(0)
		var mirrored: Array=right.mesh.surface_get_arrays(0)
		expect(left.mesh!=right.mesh,"right geometry leaves shared left asset immutable")
		expect(right.mesh==registry.mirrored_limb_mesh(left.mesh),"right geometry is cached across dwarves")
		expect(source[Mesh.ARRAY_COLOR]==mirrored[Mesh.ARRAY_COLOR],"reflection preserves skin/leather vertex colors")
		var left_frame: Transform3D=pair[0].transform*left.transform
		var right_frame: Transform3D=pair[1].transform*right.transform
		expect(left_frame.basis.determinant()>0 and right_frame.basis.determinant()>0,"rendered limb transforms retain outward facing")
		var same_shape := true
		for i in source[Mesh.ARRAY_VERTEX].size():
			var point: Vector3=left_frame*source[Mesh.ARRAY_VERTEX][i]
			point.x=-point.x
			if not point.is_equal_approx(right_frame*mirrored[Mesh.ARRAY_VERTEX][i]): same_shape=false
		expect(same_shape,"render correction keeps exact mirrored limb shape and anchors")


func _lowest(actor: Node3D, part: Node3D) -> float:
	var low := INF
	for mesh: MeshInstance3D in part.find_children("*","MeshInstance3D",true,false):
		if mesh.name=="OccludedSilhouette" or not mesh.is_visible_in_tree(): continue
		var transform := actor.global_transform.affine_inverse()*mesh.global_transform
		for vertex: Vector3 in mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			low=minf(low,(transform*vertex).y)
	return low
