extends "res://tools/tree_art/CaptureTreePilot.gd"

## Native asset sheets and paired production-world views, isolated from saves.
var gallery_only := false
var detail_owner: Node

func _init() -> void:
	output = "res://tmp/vegetation_art_20261013/final/"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=").trim_suffix("/")+"/"
		if arg == "--baseline":
			push_error("Legacy exports were retired; see the dated art reports for historical comparisons")
			quit(2); return
		if arg == "--gallery-only": gallery_only = true
	_run.call_deferred()

func _run() -> void:
	if not "/vegetation_art_20261013/" in OS.get_user_data_dir().replace("\\","/"):
		push_error("Vegetation capture requires its isolated profile")
		quit(2)
		return
	create_timer(360).timeout.connect(func(): push_error("Vegetation capture timeout"); quit(1))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.get_node("SaveManager").configure_storage_for_testing("user://vegetation_capture")
	root.get_node("SaveManager").set_process(false)
	root.get_node("WorldClock").set_paused(true)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	if not gallery_only: await _world_views()
	await _sheets()
	FileAccess.open(output+("gallery_report.json" if gallery_only else "report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("VEGETATION_CAPTURE_PASS " if report.failures.is_empty() else "VEGETATION_CAPTURE_FAIL ",output)
	if is_instance_valid(generator): generator.prepare_for_world_reload()
	quit(0 if report.failures.is_empty() else 1)

func _world_views() -> void:
	root.size = Vector2i(1600,1000)

	var scene = load("res://scenes/main/debug_world.tscn").instantiate()
	scene.get_node("Renderer").world_seed = 1234
	var publish = func(node: Node):
		if node == scene: current_scene = scene
	node_added.connect(publish)
	root.add_child(scene)
	node_added.disconnect(publish)
	generator = root.get_node("WorldGenerator")
	flora = scene.get_node("SurfaceFloraSpawner")
	detail_owner = scene.get_node("SurfaceDetailManager")
	var renderer = scene.get_node("Renderer")
	while not generator._maps_ready or not renderer._overview_built: await process_frame
	while not flora._pending.is_empty() or not detail_owner._initialized or not detail_owner._visual_queue.is_empty(): await process_frame
	while not renderer._dirty_overview_tiles.is_empty() or renderer.underground_lighting.is_updating(): await process_frame
	root.get_node("WeatherManager").set_weather("base:weather:clear")
	var sky = root.get_node("SkyController")
	sky.rebind_to_current_scene()
	sky.set_process(false)
	sky._update(12.0)
	scene.get_node("CameraRig").set_process(false)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	scene.add_child(camera)
	camera.make_current()
	for layer in scene.find_children("*","CanvasLayer",true,false): layer.visible = false
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	report["art"] = "production"
	report["adapter"] = RenderingServer.get_video_adapter_name()
	report["tree_count"] = flora._trees.size()
	var identities: Array[String] = []
	var counts := {}
	var buckets := {}
	for id: String in detail_owner._records:
		var record: Dictionary = detail_owner._records[id]
		identities.append("%s:%s:%s:%s:%s"%[id,record.definition,record.origin,record.variant,record.yaw])
		counts[record.definition] = int(counts.get(record.definition,0))+1
		if not is_instance_valid(record.node) or root.get_node("SurfaceDetailRegistry").get_definition(record.definition).get("kind") not in ["shrub","flower","reed"]: continue
		var key := Vector2i(record.origin.x/32,record.origin.z/32)
		buckets[key] = int(buckets.get(key,0))+1
	identities.sort()
	report["detail_identity_sha256"] = "|".join(identities).sha256_text()
	report["detail_counts"] = counts
	var densest := Vector2i.ZERO
	for key: Vector2i in buckets:
		if int(buckets[key]) > int(buckets.get(densest,0)): densest = key
	var target := Vector3(densest.x*32+16,0,densest.y*32+16)
	target.y = generator.get_surface_y(int(target.x),int(target.z))+2
	for size in [Vector2i(1600,1000),Vector2i(2560,1440)]:
		root.size = size
		_plant_view(target,48)
		await _capture("vegetation_%d"%size.x)
		_plant_view(target,180)
		await _capture("overview_%d"%size.x)
	root.size = Vector2i(1600,1000)
	for category: String in ["blueberry","elderberry","wild_strawberry","flowers","reeds"]:
		var best := INF
		var selected: Dictionary = {}
		for record: Dictionary in detail_owner._records.values():
			if not category in String(record.definition) or not is_instance_valid(record.node): continue
			var distance: float = record.node.position.distance_squared_to(target)
			if distance < best: best = distance; selected = record
		if selected.is_empty(): report.failures.append("Missing "+category); continue
		_plant_view(selected.bounds.get_center(),7)
		await _capture(category+"_in_world")
	# Hide only for studio sheets; the full production views above are unchanged.
	scene.visible = false

func _plant_view(target: Vector3, size: float) -> void:
	camera.size = size
	camera.position = target+Vector3(-.7,1,1).normalized()*maxf(size*1.4,7)
	camera.look_at(target)

func _sheets() -> void:
	for kind: String in ["shrubs","young","packed_shrubs","flowers","packed_flowers","reeds"]:
		var shrubs := kind in ["shrubs","young","packed_shrubs"]
		var columns := 5 if shrubs else 4
		var rows := 2 if kind == "reeds" else 3
		root.size = Vector2i(columns*300+40,rows*300+115)
		var canvas := Control.new()
		root.add_child(canvas)
		var back := ColorRect.new()
		back.color = Color("263537")
		back.size = Vector2(root.size)
		canvas.add_child(back)
		_label(canvas,kind.replace("_"," ").to_upper()+"  /  "+"CLUSTERED VEGETATION",Vector2(24,14),23)
		_label(canvas,"Native Godot render · identical scale in every panel · spring / summer / autumn / winter" ,Vector2(24,48),16)
		for row in range(rows):
			var species: String = ["blueberry","elderberry","wild_strawberry"][row] if shrubs else "reeds" if kind == "reeds" else "flowers"
			var key := "base:flora:%s_bush"%species if shrubs else "base:detail:"+species
			var definition: Dictionary = root.get_node("SurfaceDetailRegistry").get_definition(key)
			for col in range(columns):
				var season: String = ["spring","summer","autumn","winter","summer"][col]
				if col == 4 and row == 1: season = "autumn"
				var path: String
				if shrubs:
					path = String(definition.picked_models[season]) if col == 4 else String(definition.seasonal_models[season])
					if kind == "young": path = String(definition.seasonal_models.summer if col == 4 else definition.young_models[season])
					if kind == "packed_shrubs": path = String(definition.transplant.models[season+("_picked" if col == 4 else "")])
				else:
					path = String(definition.transplant.models[season][row]) if kind == "packed_flowers" else String(definition.seasonal_models[season][row])

				var at := Vector2(20+col*300,83+row*300)
				_panel(canvas,path,at,3.8 if shrubs else 2.8 if kind == "reeds" else 1.85)
				var name_label: String = species.replace("wild_","").capitalize() if shrubs else ["Cream","Heather","Gold"][row] if species == "flowers" else ["Short reeds","Tall reeds"][row]
				_label(canvas,name_label+" · "+("Mature summer" if col == 4 and kind == "young" else "Picked "+season if col == 4 else season.capitalize()),at+Vector2(0,263),16)
		for i in range(12): await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output+kind+".png")
		canvas.free()
		await process_frame

func _panel(canvas: Control, path: String, at: Vector2, size: float) -> void:
	var box := SubViewportContainer.new()
	box.position = at
	box.size = Vector2(280,255)
	canvas.add_child(box)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(280,255)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	box.add_child(viewport)
	var stage := Node3D.new()
	viewport.add_child(stage)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("425657")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_energy = .7
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	stage.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55,-35,0)
	sun.shadow_enabled = true
	stage.add_child(sun)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = size
	stage.add_child(cam)
	cam.position = Vector3(4,4.2,6)
	cam.look_at(Vector3(0,size*.24,0))
	var plant := load(path).instantiate() as Node3D
	stage.add_child(plant)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1
	for mesh: MeshInstance3D in plant.find_children("*","MeshInstance3D",true,false): mesh.material_override = mat
	if plant is MeshInstance3D: plant.material_override = mat
	var floor_mesh := MeshInstance3D.new()
	var floor_box := BoxMesh.new()
	floor_box.size = Vector3(size,.10,size)
	floor_mesh.mesh = floor_box
	floor_mesh.position.y = -.05
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color("68765B")
	floor_mesh.material_override = floor_mat
	stage.add_child(floor_mesh)

func _label(parent: Node, value: String, at: Vector2, size: int) -> void:
	var label := Label.new()
	label.text = value
	label.position = at
	label.add_theme_font_size_override("font_size",size)
	label.add_theme_color_override("font_color",Color("E0D9C6"))
	parent.add_child(label)
