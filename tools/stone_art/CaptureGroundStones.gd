extends "res://tools/vegetation_art/CaptureVegetation.gd"

## Six exact registry models and paired stone-dense production views.
func _init() -> void:
	output = "res://tmp/ground_stones_20261013/final/"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=").trim_suffix("/")+"/"
		if arg == "--baseline":
			push_error("Legacy exports were retired; see the dated art reports for historical comparisons")
			quit(2); return
		if arg == "--gallery-only": gallery_only = true
	_run.call_deferred()

func _run() -> void:
	if not "/ground_stones_20261013/" in OS.get_user_data_dir().replace("\\","/"):
		push_error("Stone capture requires its isolated profile")
		quit(2)
		return
	create_timer(240).timeout.connect(func(): push_error("Stone capture timeout"); quit(1))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.get_node("SaveManager").configure_storage_for_testing("user://stone_capture")
	root.get_node("SaveManager").set_process(false)
	root.get_node("WorldClock").set_paused(true)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	if not gallery_only: await _world_views()
	await _sheets()
	FileAccess.open(output+("gallery_report.json" if gallery_only else "report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("GROUND_STONES_CAPTURE_PASS " if report.failures.is_empty() else "GROUND_STONES_CAPTURE_FAIL ",output)
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
		if not record.definition in ["base:detail:boulder","base:detail:scree"]: continue
		var key := Vector2i(record.origin.x/64,record.origin.z/64)
		buckets[key] = int(buckets.get(key,0))+1
	identities.sort()
	report["detail_identity_sha256"] = "|".join(identities).sha256_text()
	report["detail_counts"] = counts
	var densest := Vector2i.ZERO
	for key: Vector2i in buckets:
		if int(buckets[key]) > int(buckets.get(densest,0)): densest = key
	var target := Vector3(densest.x*64+32,0,densest.y*64+32)
	target.y = generator.get_surface_y(int(target.x),int(target.z))+3
	for size in [Vector2i(1600,1000),Vector2i(2560,1440)]:
		root.size = size
		_plant_view(target,75)
		await _capture("stone_neighborhood_%d"%size.x)
		_plant_view(target,210)
		await _capture("overview_%d"%size.x)
	root.size = Vector2i(1600,1000)
	for category: String in ["boulder","scree"]:
		for variant in range(3):
			var best := INF
			var selected: Dictionary = {}
			for record: Dictionary in detail_owner._records.values():
				if record.definition != "base:detail:"+category or record.variant != variant or not is_instance_valid(record.node): continue
				var distance: float = record.node.position.distance_squared_to(target)
				if distance < best: best = distance; selected = record
			if selected.is_empty(): report.failures.append("Missing "+category); continue
			var width := 2.0 if category == "boulder" else 3.0
			# Logical placement determines camera, independently of the art's bounds.
			var center := Vector3(selected.origin)+Vector3(width*.5,1.5,width*.5)
			_stone_view(center)
			await _capture("%s_%d_in_world"%[category,variant+1])
	scene.visible = false

func _stone_view(target: Vector3) -> void:
	# Cliff-foot props need a clear approach. Choose from terrain only so before
	# and after retain the same camera regardless of a model's shape or triangle count.
	var best := INF
	var direction := Vector3(-.7,1,1).normalized()
	for elevation: float in [1.0,1.8]:
		for turn in range(8):
			var candidate := Vector3(-.7,elevation,1).rotated(Vector3.UP,turn*PI*.25).normalized()
			var occlusion := 0.0
			for step in range(1,21):
				var point := target+candidate*12.6*(step/20.0)
				occlusion += maxf(0,generator.get_surface_y(int(point.x),int(point.z))+1.05-point.y)
			if occlusion < best: best = occlusion; direction = candidate
	camera.size = 9
	camera.position = target+direction*12.6
	camera.look_at(target)

func _sheets() -> void:
	root.size = Vector2i(1240,870)
	var canvas := Control.new()
	root.add_child(canvas)
	var back := ColorRect.new()
	back.color = Color("263537")
	back.size = Vector2(root.size)
	canvas.add_child(back)
	_label(canvas,"BOULDERS & LOOSE STONES  /  "+"FACETED STONE",Vector2(24,18),25)
	_label(canvas,"Native Godot render · same camera and world scale · all six live variants",Vector2(24,57),18)
	for row in range(2):
		var category := "boulder" if row == 0 else "scree"
		var definition: Dictionary = root.get_node("SurfaceDetailRegistry").get_definition("base:detail:"+category)
		for col in range(3):
			var path: String = definition.models[col]

			var at := Vector2(45+col*400,112+row*360)
			_panel(canvas,path,at,4.0)
			# Use native viewport pixels at a larger display size for the six-up sheet.
			var panel := canvas.get_child(canvas.get_child_count()-1) as SubViewportContainer
			panel.size = Vector2(350,300)
			(panel.get_child(0) as SubViewport).size = Vector2i(350,300)
			_label(canvas,("Boulder" if row == 0 else "Loose stones")+" · Variant %d"%(col+1),at+Vector2(0,307),19)
	for i in range(12): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output+"stone_family.png")
	canvas.free()
