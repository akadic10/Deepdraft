extends SceneTree

func _init() -> void:
	_run.call_deferred()


func _apple_definition(flora: Node3D) -> Dictionary:
	for definition in flora._species:
		if definition.name == "apple":
			return definition
	assert(false, "Missing apple definition")
	return {}


func _run() -> void:
	create_timer(90.0).timeout.connect(func(): push_error("Live apple check timed out"); quit(1))
	root.get_node("SaveManager").set_process(false)
	root.get_node("WorldClock").call("set_paused", true)
	var flora: Node3D = load("res://scripts/systems/SurfaceFloraSpawner.gd").new()
	root.add_child(flora)
	flora.set_process(false)
	var registry := root.get_node("PlacedEntityRegistry")
	var definition: Dictionary = _apple_definition(flora)
	var resolved_count := 0
	for stage_name in ["sapling", "mature", "ancient"]:
		var stage: Dictionary = definition.stages[stage_name]
		for season in ["spring", "summer", "autumn", "winter"]:
			for i in range(64):
				var pos := Vector3i(i*13,20+i%60,i*7)
				var path: String = flora.resolve_tree_model_for_season(stage,season,pos)
				assert(ResourceLoader.exists(path) and load(path) is PackedScene, path)
				if stage_name == "mature":
					var suffix: String = "" if season == "summer" else ("_autumn_fruiting" if season == "autumn" else "_"+season)
					assert(path == "res://assets/models/flora/trees/apple/apple_mature"+suffix+".glb",path)
				resolved_count += 1
	var stage: Dictionary = definition.stages.mature
	var footprint: int = definition.placement.footprint.mature
	for i in range(64):
		var path: String = flora.resolve_tree_model(stage.models.autumn,Vector3i(i*13,20+i%60,i*7))
		assert(path == "res://assets/models/flora/trees/apple/apple_mature_autumn.glb")
		resolved_count += 1
	for season in ["spring","summer","autumn","autumn_fruiting","winter"]:
		var path: String = flora.resolve_tree_model(stage.models[season],Vector3i(30,20,40))
		var tree: Node3D = flora._instance_tree("apple",path,"mature",stage,30,40,20,footprint)
		assert(tree is StaticBody3D)
		assert(tree.position == Vector3(31.5,21,41.5))
		assert(tree.get_child(0).scale == Vector3.ONE)
		var shapes := tree.find_children("*","CollisionShape3D",true,false)
		assert(shapes.size() == 1 and shapes[0].shape.size == Vector3(3,5,3))
		assert(tree.collision_layer == 2)
		var meshes := tree.find_children("*","MeshInstance3D",true,false)
		assert(meshes.size() == 1)
		var material: StandardMaterial3D = meshes[0].material_override
		assert(material.vertex_color_use_as_albedo and not material.vertex_color_is_srgb)
		assert(material.cull_mode == BaseMaterial3D.CULL_DISABLED)
		var bounds: AABB = meshes[0].get_aabb()
		assert(is_equal_approx(bounds.position.y,0))
		assert(is_equal_approx(bounds.size.y,10 if season == "winter" else 12))
		for dx in range(3):
			for dz in range(3):
				assert(registry.occupies(Vector3i(30+dx,21,40+dz)))
		assert(not registry.occupies(Vector3i(33,21,40)))
		registry.unregister(int(tree.get_meta("occupancy_id")))
		tree.free()
	flora.free()
	assert(registry.get_stats().entities == 0)
	print("LIVE_APPLE_IMPORT_OK: 5 approved models; ",resolved_count," seasonal resolutions; scale/material/collision/occupancy valid")
	if "--capture" in OS.get_cmdline_user_args():
		await _world_capture()
	quit(0)


func _world_capture() -> void:
	assert(change_scene_to_file("res://scenes/main/debug_world.tscn") == OK)
	await process_frame
	var world := root.get_node("WorldGenerator")
	while not bool(world.call("get_streaming_stats").get("maps_ready", false)) or world.call("is_generating"):
		await process_frame
	root.get_node("WorldClock").call("restore_state", {"year":1,"season":"summer","day":1,"hour":12.0,"speed":1.0,"paused":true})
	root.get_node("SkyController").call("rebind_to_current_scene")
	for node in current_scene.find_children("*", "CanvasLayer", true, false):
		node.hide()
	var existing := current_scene.get_node_or_null("SurfaceFloraSpawner")
	if existing is Node3D:
		existing.hide()
	var height := 0
	for x in range(468,557):
		for z in range(477,506):
			height = maxi(height, int(world.call("get_surface_y",x,z))+1)
	var centre := Vector3(512,height,491)
	var platform := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(110,.15,36)
	platform.mesh = box
	platform.position = centre-Vector3(0,.08,0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(.40,.43,.41)
	mat.roughness = 1
	platform.material_override = mat
	current_scene.add_child(platform)
	var flora: Node3D = load("res://scripts/systems/SurfaceFloraSpawner.gd").new()
	current_scene.add_child(flora)
	flora.set_process(false)
	for i in range(5):
		var species := "apple"
		var season: String = ["spring","summer","autumn","autumn_fruiting","winter"][i]
		var definition: Dictionary = _apple_definition(flora)
		var stage: Dictionary = definition.stages.mature
		var footprint: int = definition.placement.footprint.mature
		var x := 469+i*20
		var path: String = flora.resolve_tree_model(stage.models[season],Vector3i(x,height,489))
		var tree: Node3D = flora._instance_tree(species,path,"mature",stage,x,489,height-1,footprint)
		tree.get_child(0).rotation_degrees.y = 25
		var ap := DwarfAppearanceData.new()
		ap.gender = "male"
		ap.hair_style = "short_back"
		ap.beard_style = "short_trimmed"
		ap.eyebrow_style = "arched"
		ap.eye_color = "blue"
		ap.skin_tone = "medium"
		ap.hair_color = "brown"
		var actor: Node3D = load("res://scripts/entities/DwarfAgent.gd").new()
		actor.setup(900+i,{"gender":ap.gender,"appearance":ap})
		current_scene.add_child(actor)
		actor.set_process(false)
		actor.position = Vector3(x+8,height,497)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 67
	camera.far = 500
	current_scene.add_child(camera)
	var target := centre + Vector3(0,6,0)
	camera.position = target+Vector3(0,40,69)
	camera.look_at(target)
	camera.current = true
	for i in range(30):
		await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png("res://tmp/apple_redesign_preview/renders/live_world.png") == OK)
	print("LIVE_APPLE_WORLD_ART_OK")
