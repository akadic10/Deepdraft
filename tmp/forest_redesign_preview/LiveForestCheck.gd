extends SceneTree

var expected_bounds: Dictionary
var definitions: Dictionary = {}
var report: Dictionary = {}

func _init() -> void:
	_run.call_deferred()

func _variant(path: String) -> int:
	var last: String = path.get_file().get_basename().split("_")[-1]
	return int(last) if last.is_valid_int() else 1

func _run() -> void:
	create_timer(180.0).timeout.connect(func(): push_error("Live forest check timed out"); quit(1))
	root.get_node("SaveManager").set_process(false)
	root.get_node("WorldClock").call("set_paused", true)
	expected_bounds = load("res://tmp/forest_redesign_preview/ExpectedBounds.gd").BOUNDS
	var flora: Node3D = load("res://scripts/systems/SurfaceFloraSpawner.gd").new()
	root.add_child(flora)
	flora.set_process(false)
	var registry := root.get_node("PlacedEntityRegistry")
	var resolved := 0
	var instances := 0
	for definition in flora._species:
		definitions[definition.name] = definition
		for stage_name in ["sapling", "mature", "ancient"]:
			var stage: Dictionary = definition.stages[stage_name]
			var footprint: int = definition.placement.footprint[stage_name]
			for i in range(64):
				var pos := Vector3i(i*13,20+i%60,i*7)
				var variant := 0
				for season in ["spring", "summer", "autumn", "winter"]:
					var path: String = flora.resolve_tree_model_for_season(stage,season,pos)
					assert(ResourceLoader.exists(path) and load(path) is PackedScene,path)
					assert(path.get_file().get_basename() in expected_bounds,path)
					if variant == 0:
						variant = _variant(path)
					assert(_variant(path) == variant,"Season changed variant: "+path)
					resolved += 1
			for season in stage.models:
				var paths = stage.models[season]
				if paths is String:
					paths = [paths]
				for path: String in paths:
					var tree: Node3D = flora._instance_tree(definition.name,path,stage_name,stage,30,40,20,footprint)
					assert(tree.position == Vector3(30+.5*footprint,21,40+.5*footprint))
					assert(tree.get_child(0).scale == Vector3.ONE)
					var meshes := tree.find_children("*","MeshInstance3D",true,false)
					assert(meshes.size() == 1)
					var material: StandardMaterial3D = meshes[0].material_override
					assert(material.vertex_color_use_as_albedo and not material.vertex_color_is_srgb)
					assert(material.cull_mode == BaseMaterial3D.CULL_DISABLED)
					var bounds: AABB = meshes[0].get_aabb()
					var expected: Array = expected_bounds[path.get_file().get_basename()]
					assert(bounds.position.is_equal_approx(Vector3(expected[0][0],expected[0][1],expected[0][2])),path)
					assert(bounds.end.is_equal_approx(Vector3(expected[1][0],expected[1][1],expected[1][2])),path)
					var shapes := tree.find_children("*","CollisionShape3D",true,false)
					if stage_name == "sapling":
						assert(not tree is StaticBody3D and shapes.is_empty())
						assert(not tree.has_meta("occupancy_id") and registry.get_stats().entities == 0)
					else:
						assert(tree is StaticBody3D and tree.collision_layer == 2)
						assert(shapes.size() == 1 and shapes[0].shape.size == Vector3(footprint,stage.clearance_height,footprint))
						for dx in range(footprint):
							for dz in range(footprint):
								assert(registry.occupies(Vector3i(30+dx,21,40+dz)))
						assert(not registry.occupies(Vector3i(30+footprint,21,40)))
						assert(not registry.occupies(Vector3i(30,21+int(stage.clearance_height),40)))
						registry.unregister(int(tree.get_meta("occupancy_id")))
					tree.free()
					instances += 1
	flora.free()
	assert(registry.get_stats().entities == 0 and instances == 86 and resolved == 3072)
	report = {"live_instances_checked":instances,"seasonal_resolutions_checked":resolved,"bounds_material_scale_collision_occupancy_valid":true}
	print("LIVE_FOREST_IMPORT_OK: ",instances," models; ",resolved," seasonal resolutions")
	await _world_check()
	var output := FileAccess.open("res://tmp/forest_redesign_preview/runtime_checks.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(report,"  ")+"\n")
	output.close()
	quit(0)

func _world_check() -> void:
	var scene: Node3D = load("res://scenes/main/debug_world.tscn").instantiate()
	scene.get_node("Renderer").world_seed = 1388941899
	var configured := PackedScene.new()
	assert(configured.pack(scene) == OK)
	scene.free()
	assert(change_scene_to_packed(configured) == OK)
	await process_frame
	var world := root.get_node("WorldGenerator")
	while not bool(world.call("get_streaming_stats").get("maps_ready",false)) or world.call("is_generating"):
		await process_frame
	root.get_node("SkyController").call("rebind_to_current_scene")
	for node in current_scene.find_children("*","CanvasLayer",true,false):
		node.hide()
	var flora: Node3D = current_scene.get_node("SurfaceFloraSpawner")
	var baseline: Dictionary = {}
	var seasons: Dictionary = {}
	var camera: Camera3D
	for season in ["summer","autumn","winter","spring"]:
		root.get_node("WorldClock").call("restore_state",{"year":1,"season":season,"day":1,"hour":12.0,"speed":1.0,"paused":true})
		await process_frame
		while not flora._ready_to_spawn or not flora._pending.is_empty():
			await process_frame
		await process_frame
		var counts: Dictionary = {}
		var model_counts: Dictionary = {}
		for tree: Node3D in flora.get_children():
			var parts := String(tree.name).split("_")
			var species: String = parts[0]
			var age: String = parts[1]
			var definition: Dictionary = definitions[species]
			var stage: Dictionary = definition.stages[age]
			var pos := Vector3i(int(parts[2]),int(tree.get_meta("base_y")),int(parts[3]))
			var path: String = tree.get_child(0).scene_file_path
			assert(path == flora.resolve_tree_model_for_season(stage,season,pos),path)
			assert(path.get_file().get_basename() in expected_bounds,path)
			var identity: Array = [tree.position,_variant(path)]
			if season == "summer":
				baseline[String(tree.name)] = identity
			else:
				assert(baseline[String(tree.name)] == identity,"Tree moved or changed variant")
			var key := species+"_"+age
			counts[key] = int(counts.get(key,0))+1
			model_counts[path] = int(model_counts.get(path,0))+1
		assert(counts.size() == 12 and model_counts.size() == 26)
		assert(flora.get_child_count() == baseline.size())
		if season == "summer":
			camera = _forest_camera(flora,world)
			# Give terrain around the chosen view time to stream and upload.
			for i in range(180):
				await RenderingServer.frame_post_draw
		seasons[season] = {"count":flora.get_child_count(),"stages":counts,"model_counts":model_counts}
		for i in range(30):
			await RenderingServer.frame_post_draw
		assert(root.get_texture().get_image().save_png("res://tmp/forest_redesign_preview/renders/live_forest_"+season+".png") == OK)
		print("LIVE_FOREST_SEASON_OK: ",season," ",flora.get_child_count()," trees; ",model_counts.size()," distinct models")
	report["natural_spawn_seed"] = world.world_seed
	report["natural_seasons"] = seasons
	report["natural_positions_and_variants_stable"] = true
	print("LIVE_FOREST_WORLD_OK")

func _forest_camera(flora: Node3D,world: Node) -> Camera3D:
	var best_score := -INF
	var centre := Vector3(512,40,512)
	for x in range(160,865,64):
		for z in range(160,865,64):
			var types: Dictionary = {}
			var ages: Dictionary = {}
			var count := 0
			for tree: Node3D in flora.get_children():
				if Vector2(tree.position.x-x,tree.position.z-z).length() < 62:
					var parts := String(tree.name).split("_")
					types[parts[0]] = true
					ages[parts[0]+"_"+parts[1]] = true
					count += 1
			var score: int = types.size()*100+ages.size()*8-absi(count-40)
			if score > best_score:
				best_score = score
				centre = Vector3(x,float(world.call("get_surface_y",x,z))+5,z)
	var rig: Node3D = current_scene.get_node("CameraRig")
	rig.set_process(false)
	rig.set_physics_process(false)
	rig.position = centre
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 115
	camera.far = 1000
	current_scene.add_child(camera)
	camera.position = centre+Vector3(50,82,75)
	camera.look_at(centre)
	camera.current = true
	report["capture_centre"] = [centre.x,centre.y,centre.z]
	return camera
