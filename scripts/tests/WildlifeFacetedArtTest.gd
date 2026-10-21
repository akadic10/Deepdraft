extends "res://scripts/tests/DeerPilotArtTest.gd"
const VoxelShadows = preload("res://scripts/components/VoxelShadowSetup.gd")

func _run() -> void:
	create_timer(60).timeout.connect(func(): push_error("Wildlife art timeout"); quit(1))
	for id in ["SaveManager","TaskManager","WorldClock","RoomManager","StockpileManager","SkyController","WeatherManager"]:
		root.get_node(id).set_process(false)
	root.get_node("WorldGenerator").world_seed=1234
	var scene := Node3D.new(); root.add_child(scene); current_scene=scene
	var wildlife=load("res://scripts/systems/WildlifeManager.gd").new()
	scene.add_child(wildlife); wildlife.set_process(false)
	if "--staged" in OS.get_cmdline_user_args(): preload("res://tools/voxel_assets/WildlifeGallery.gd").stage_models(wildlife)
	var count := 0
	for table in [wildlife._models,wildlife._deer_models,wildlife._wolf_models,wildlife._duck_models]:
		for part: PackedScene in table.values():
			count+=1
			expect(part.resource_path.begins_with("res://assets/models/animals/"),"production model path")
			var asset := part.instantiate() as Node3D
			expect(asset.transform.is_equal_approx(Transform3D.IDENTITY),"unit root")
			expect(asset.find_children("*","CollisionObject3D",true,false).is_empty(),"no embedded collision")
			var pairs:=2 if part.resource_path.ends_with("/leg.glb") else 1
			expect(VoxelShadows.configure(asset)==pairs,"one visual/proxy pair per rigid segment")
			var meshes := VoxelShadows.visual_meshes(asset)
			expect(meshes.size()==pairs,"one visual mesh per rigid segment")
			for mesh: MeshInstance3D in meshes:
				expect(mesh.transform.is_equal_approx(Transform3D.IDENTITY),"baked part origin")
				expect(mesh.mesh.get_surface_count()==1,"one surface")
				var colors: PackedColorArray=mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
				var opaque := not colors.is_empty()
				for color in colors:
					if color.a<.999: opaque=false
				expect(opaque,"opaque vertex colors")
			asset.free()
	expect(count==23,"all 23 parts")
	for species in ["rabbit","deer","wolf","duck"]:
		var actor: Node3D=wildlife.call("add_"+species,species+":geometry",Vector3i(40,21,40),155)
		if species in ["deer","wolf"]:
			for leg: Node3D in actor.legs:
				expect(leg.get_node("Knee").get_child_count()==1,species+" movable lower leg")
		var before: Dictionary=actor.serialize_state()
		for activity in ["Idle","Wandering","Grazing" if species!="wolf" else "Eating","Sleeping"]:
			var low := INF
			var high := -INF
			for i in 64:
				actor.activity=activity; actor.hop_progress=float(i)/64 if activity=="Wandering" else 1.0
				actor.pose_time=float(i)*TAU/64
				if species=="duck": actor.mode="land"
				actor._pose()
				var meshes: Array[Node]=[]
				for mesh in VoxelShadows.visual_meshes(actor.visual):
					if mesh.is_visible_in_tree(): meshes.append(mesh)
				for part: Node3D in actor.visual.find_children("*","Node3D",true,false):
					expect(part.scale.is_equal_approx(Vector3.ONE),species+" rigid part "+String(part.name))
				# Squash and stretch (doc 256) scales only the root, keeping its volume.
				var root_scale: Vector3=actor.visual.scale
				expect(absf(root_scale.x*root_scale.y*root_scale.z-1.0)<.002 and is_equal_approx(root_scale.x,root_scale.z) and absf(root_scale.y-1.0)<=.2,species+" volume-kept squash")
				if activity!="Wandering": expect(root_scale.is_equal_approx(Vector3.ONE),species+" unit visual root at rest")
				var bounds := _local_bounds(actor,meshes)
				low=minf(low,bounds.position.y); high=maxf(high,bounds.end.y)
			expect(low>=-.025,species+" ground clearance "+activity+" %.4f"%low)
			expect(high<float(actor.definition.navigation.clearance),species+" headroom "+activity)
		actor.restore_state(before)
		expect(actor.serialize_state()==before,species+" exact current-state restore")
	for error in failures: push_error(error)
	print("WILDLIFE_VOXEL_ART_OK: %d imported and sampled live-pose checks"%checks if failures.is_empty() else "WILDLIFE_VOXEL_ART_FAIL")
	quit(0 if failures.is_empty() else 1)
