extends SceneTree

const Assets = preload("res://tools/dwarf_pilot/DwarfPilotAssets.gd")
var failures: Array[String] = []
var checks := 0

func _init() -> void: _run.call_deferred()

func expect(value: bool, message: String) -> void:
	checks+=1
	if not value: failures.append(message)

func _run() -> void:
	create_timer(30).timeout.connect(func(): push_error("Dwarf pilot asset check timeout"); quit(1))
	for id in ["SaveManager","WorldClock","TaskManager","RoomManager","StockpileManager"]:
		root.get_node(id).set_process(false)
	root.get_node("WorldGenerator").world_seed=1234
	var registry := root.get_node("DwarfAssets")
	var scene := Node3D.new()
	root.add_child(scene); current_scene=scene
	for part: String in Assets.PARTS:
		var asset := load(Assets.DIRECTORY+Assets.PARTS[part]+".glb").instantiate() as Node3D
		expect(asset.transform.is_equal_approx(Transform3D.IDENTITY),part+" unit origin")
		expect(asset.find_children("*","CollisionObject3D",true,false).is_empty(),part+" no embedded physics")
		var meshes := asset.find_children("*","MeshInstance3D",true,false)
		expect(meshes.size()==1,part+" single mesh")
		for mesh: MeshInstance3D in meshes:
			expect(mesh.transform.is_equal_approx(Transform3D.IDENTITY),part+" baked shared frame")
			expect(mesh.mesh.get_surface_count()==1,part+" one surface")
			var colors: PackedColorArray = mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
			var opaque := not colors.is_empty()
			for color in colors:
				if color.a<.999: opaque=false
			expect(opaque,part+" opaque vertex colors")
			var bounds := mesh.get_aabb()
			expect(bounds.position.y>=-.001 and bounds.end.y<=3.375,part+" visual height")
			if part=="hand": expect(bounds.has_point(Vector3(1.0625,1.25,.1875)),"palm anchor stays inside mitten")
			if part=="foot": expect(absf(bounds.position.y)<.001,"boot sole at ground")
		asset.free()
	var factory = load("res://scripts/entities/DwarfFactory.gd").new()
	var data: Dictionary = factory.generate(141,{})
	data.gender="male"
	var appearance := DwarfAppearanceData.new()
	appearance.hair_style="short_back"; appearance.beard_style="forked"
	data.appearance=appearance
	var saved := Assets.install(registry)
	var actor = factory.spawn(data,950)
	Assets.restore(registry,saved)
	for key in saved: expect(registry.get(key)==saved[key],"owner restored: "+key)
	scene.add_child(actor); actor.position=Vector3(40,21,40)
	actor.set_process(false); actor.get_node("Readability").set_process(false)
	var logical := actor.get_node("LogicalBox") as CollisionShape3D
	expect(logical.shape.size==Vector3(1,3,1),"unchanged logical 1x1x3 box")
	expect(actor._hand_r.scale==Vector3(-1,1,1) and actor._foot_r.scale==Vector3(-1,1,1),"mirrored right parts")
	for color: String in registry.SKIN_TONES:
		appearance.skin_tone=color; actor._apply_tints()
		expect(_material(actor._head).albedo_color==registry.SKIN_TONES[color],"skin tint "+color)
		expect(_material(actor._body).albedo_color==Color.WHITE,"clothing avoids skin tint")
	for color: String in registry.HAIR_COLORS:
		appearance.hair_color=color; actor._apply_tints()
		for part in ["MeshHair","MeshBeard","MeshBrows"]:
			expect(_material(actor._head.get_node(part)).albedo_color==registry.HAIR_COLORS[color],part+" tint "+color)
	for color: String in registry.EYE_COLORS:
		appearance.eye_color=color; actor._apply_tints()
		expect(_material(actor._head.get_node("MeshEyes")).albedo_color==registry.EYE_COLORS[color],"eye tint "+color)
	for phase in [0.0,.2,.4,.55,.75,.93]:
		for rig in [actor._mining_pose,actor._felling_pose]:
			actor._reset_part_offsets()
			rig.apply(phase,Vector3(0,1.2,1.4))
			expect((actor._hand_r.global_transform*rig.PALM).distance_to(rig.tool.global_position)<.001,"lower tool grip")
			expect((actor._hand_l.global_transform*rig.PALM).distance_to(rig.tool.global_transform*rig.SUPPORT_GRIP)<.001,"upper tool grip")
			actor._reset_part_offsets()
			expect(actor._hand_r.scale.is_equal_approx(Vector3(-1,1,1)),"interruption restores hand reflection")
		actor._walk_cycle=phase; actor._walk_bob(0)
		for foot in [actor._foot_l,actor._foot_r]:
			expect(_lowest(actor,foot)>=-.065,"walk sole does not visibly sink")
	actor._reset_part_offsets()
	for pose in ["lying","sitting"]:
		actor._rest_behavior.pose=pose; actor._rest_behavior.blend=1
		actor._rest_behavior._apply_pose()
		expect(not actor._head.get_node("MeshEyes").visible,"closed sleeping eyes "+pose)
		for part in [actor._head,actor._body,actor._hand_l,actor._hand_r,actor._foot_l,actor._foot_r]:
			expect(_lowest(actor,part)>=-.025,"ground clearance for "+pose+" "+part.name)
	actor._rest_behavior.cancel(); actor._reset_part_offsets()
	var before: Dictionary = actor.serialize_state()
	actor.restore_saved_runtime(before)
	expect(actor.appearance.hair_style=="short_back" and actor.appearance.beard_style=="forked","appearance save IDs unchanged")
	actor.apply_slice(20); expect(not actor.visible,"slice conceals pilot")
	actor.apply_slice(127); expect(actor.visible,"slice restores pilot")
	for error in failures: push_error(error)
	print("DWARF_PILOT_ART_OK: %d imported, tint, grip, gait, rest, slice and save checks" % checks if failures.is_empty() else "DWARF_PILOT_ART_FAIL")
	quit(0 if failures.is_empty() else 1)

func _material(part: Node3D) -> StandardMaterial3D:
	return part.find_children("*","MeshInstance3D",true,false)[0].material_override as StandardMaterial3D

func _lowest(actor: Node3D, part: Node3D) -> float:
	var low := INF
	for mesh: MeshInstance3D in part.find_children("*","MeshInstance3D",true,false):
		if mesh.name=="OccludedSilhouette" or not mesh.is_visible_in_tree(): continue
		var transform := actor.global_transform.affine_inverse()*mesh.global_transform
		for vertex: Vector3 in mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			low=minf(low,(transform*vertex).y)
	return low
