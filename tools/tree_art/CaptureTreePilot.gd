extends SceneTree

## Matched production-light/seed comparisons; isolated profile, no player saves.
var output := "res://tmp/tree_pilot_20261013/pilot/"
var fruit_trees := false
var species_names := ["pine","oak"]
var report := {"seed":1234,"captures":{},"failures":[]}
var camera: Camera3D
var generator: Node
var flora: Node

func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=").trim_suffix("/")+"/"
		if arg == "--baseline":
			push_error("Legacy exports were retired; see the dated art reports for historical comparisons")
			quit(2); return
		if arg == "--fruit-trees": fruit_trees = true
	if fruit_trees: species_names = ["apple","juniper"]
	_run.call_deferred()

func _run() -> void:
	if not "/tree_pilot_20261013/" in OS.get_user_data_dir().replace("\\","/"):
		push_error("Tree capture requires an isolated tree_pilot_20261013 profile")
		quit(2)
		return
	create_timer(300).timeout.connect(func(): push_error("Tree capture timeout"); quit(1))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.size = Vector2i(1600,1000)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	root.get_node("SaveManager").configure_storage_for_testing("user://tree_capture")
	root.get_node("SaveManager").set_process(false)
	root.get_node("WorldClock").set_paused(true)
	var scene = load("res://scenes/main/debug_world.tscn").instantiate()
	scene.get_node("Renderer").world_seed = 1234
	var publish = func(node: Node):
		if node == scene: current_scene = scene
	node_added.connect(publish)
	root.add_child(scene)
	node_added.disconnect(publish)
	generator = root.get_node("WorldGenerator")
	flora = scene.get_node("SurfaceFloraSpawner")

	var renderer = scene.get_node("Renderer")
	while not generator._maps_ready or not renderer._overview_built: await process_frame
	while not flora._pending.is_empty(): await process_frame
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
	report["focus_species"] = species_names
	report["adapter"] = RenderingServer.get_video_adapter_name()
	report["tree_count"] = flora._trees.size()
	var identities: Array[String] = []
	for id: Vector2i in flora._trees:
		var tree: Dictionary = flora._trees[id]
		identities.append("%s:%s:%s:%s"%[id,tree.name,tree.stage,tree.cell])
	identities.sort()
	report["tree_identity_sha256"] = "|".join(identities).sha256_text()
	# Densest 64-unit neighborhood of each pilot species, independent of art.
	var buckets := {}
	for id: Vector2i in flora._trees:
		var tree: Dictionary = flora._trees[id]
		if tree.name not in species_names: continue
		var key := Vector2i(id.x/64,id.y/64)
		buckets[key] = int(buckets.get(key,0))+1
	var densest := Vector2i.ZERO
	for key: Vector2i in buckets:
		if int(buckets[key]) > int(buckets.get(densest,0)): densest = key
	var target := Vector3(densest.x*64+32,0,densest.y*64+32)
	target.y = generator.get_surface_y(int(target.x),int(target.z))+10
	report["forest_bucket_count"] = buckets[densest]
	for size in [Vector2i(1600,1000),Vector2i(2560,1440)]:
		root.size = size
		_view(target,110)
		await _capture("forest_%d"%size.x)
		_view(target,310)
		await _capture("overview_%d"%size.x)
	root.size = Vector2i(1600,1000)
	for species_name in species_names:
		var best := INF
		var selected: Dictionary = {}
		for tree: Dictionary in flora._trees.values():
			if tree.name != species_name or tree.stage != "mature": continue
			var distance: float = tree.node.position.distance_squared_to(target)
			if distance < best: best = distance; selected = tree
		_view(selected.bounds.get_center(),32)
		await _capture(species_name+"_in_world")
	# Six stage specimens use the production spawner/material under the same sky.
	# A neutral isolated platform makes silhouettes legible; it is capture-only.
	flora.visible = false
	var gallery = load("res://scripts/systems/SurfaceFloraSpawner.gd").new()
	scene.add_child(gallery)
	gallery.set_process(false)
	gallery._slice_y = 10000 # Display platform is above the simulation's world height.

	var floor_mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(116,1,74)
	floor_mesh.mesh = box
	floor_mesh.position = Vector3(-1150,139.5,-1178)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("68765b")
	material.roughness = 1
	floor_mesh.material_override = material
	scene.add_child(floor_mesh)
	for season in ["spring","summer","autumn","winter"]:
		gallery._season = season
		for tree: Dictionary in gallery._trees.values():
			if tree.occupancy_id >= 0: root.get_node("PlacedEntityRegistry").unregister(tree.occupancy_id)
			tree.node.free()
		gallery._trees.clear()
		for species: Dictionary in gallery._species:
			if species.name not in species_names: continue
			var row := species_names.find(species.name)
			for index in range(3):
				var stage: String = ["sapling","mature","ancient"][index]
				var data: Dictionary = species.stages[stage]
				gallery._instance_tree(species.name,"",stage,data,-1190+index*36,-1200+row*37,139,gallery._footprint_for(species.placement,stage))
		_view(Vector3(-1153,151,-1182),68,Vector3(.22,1,1.65))
		await _capture("stages_"+season)
		if season == "summer" or (fruit_trees and season in ["spring","autumn"]):
			for tree: Dictionary in gallery._trees.values():
				tree.node.visible = tree.stage == "mature"
				if tree.stage == "mature":
					tree.node.position = Vector3(-1162 if tree.name == species_names[0] else -1144,140,-1182)
			_view(Vector3(-1153,147 if fruit_trees else 150,-1182),27 if fruit_trees else 31,Vector3(.3,.85,1.8))
			await _capture("mature_pair" if season == "summer" else "mature_"+season)
			if season == "summer":
				sky._update(19.0)
				await _capture("mature_dusk")
				sky._update(12.0)
			if fruit_trees and season == "autumn":
				for id: Vector2i in gallery._trees:
					if gallery._trees[id].name == "juniper":
						gallery._tree_changes[id] = {"harvested_cycle":gallery._fruit_cycle()}
						gallery._refresh_tree_crop_visual(id)
				await _capture("juniper_picked")
	report["final_static_memory_bytes"] = OS.get_static_memory_usage()
	FileAccess.open(output+"report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("TREE_PILOT_CAPTURE_PASS " if report.failures.is_empty() else "TREE_PILOT_CAPTURE_FAIL ",output)
	generator.prepare_for_world_reload()
	quit(0 if report.failures.is_empty() else 1)

func _view(target: Vector3, size: float, direction := Vector3(-.7,1,1)) -> void:
	camera.size = size
	camera.position = target+direction.normalized()*maxf(size*1.4,45)
	camera.look_at(target)

func _capture(label: String) -> void:
	for i in range(30): await process_frame
	var gpu: Array[float] = []
	var cpu: Array[float] = []
	var frame: Array[float] = []
	var rid := root.get_viewport_rid()
	for i in range(120):
		var tick := Time.get_ticks_usec()
		await process_frame
		frame.append((Time.get_ticks_usec()-tick)/1000.0)
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
		cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(rid))
	await RenderingServer.frame_post_draw
	if root.get_texture().get_image().save_png(output+label+".png") != OK: report.failures.append(label)
	report.captures[label] = {"gpu_ms":_percentiles(gpu),"render_cpu_ms":_percentiles(cpu),"frame_ms":_percentiles(frame),
		"draws":RenderingServer.viewport_get_render_info(rid,RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
		"primitives":RenderingServer.viewport_get_render_info(rid,RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME),
		"video_memory_bytes":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED),"static_memory_bytes":OS.get_static_memory_usage(),
		"camera_position":str(camera.position),"camera_rotation":str(camera.rotation),"camera_size":camera.size}
	print("TREE_CAPTURE ",label)

func _percentiles(values: Array[float]) -> Dictionary:
	values.sort()
	return {"p50":values[values.size()/2],"p95":values[floori(values.size()*.95)],"max":values.back()}
