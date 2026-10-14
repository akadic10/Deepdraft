extends SceneTree

## Repeatable production-scene comparison. Runs only with an isolated profile.
var output := "res://tmp/terrain_art_20261013/baseline_1600/"
var resolution := Vector2i(1600, 1000)
var extended := false
var profile_builds := false
var report := {"seed":1234, "captures":{}, "failures":[]}
var generator: Node
var renderer: Node
var camera: Camera3D
var last_tick := 0

func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=").trim_suffix("/")+"/"
		if arg == "--large": resolution = Vector2i(2560,1440)
		if arg == "--extended": extended = true
		if arg == "--profile": profile_builds = true
	_run.call_deferred()

func _run() -> void:
	if not "/terrain_art_20261013/" in OS.get_user_data_dir().replace("\\","/"):
		push_error("Terrain capture requires an isolated terrain_art_20261013 profile")
		quit(2)
		return
	create_timer(300).timeout.connect(func(): push_error("Terrain capture timeout"); quit(1))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.size = resolution
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	root.get_node("SaveManager").configure_storage_for_testing("user://terrain_capture")
	root.get_node("SaveManager").set_process(false)
	root.get_node("WorldClock").set_paused(true)
	var scene = load("res://scenes/main/debug_world.tscn").instantiate()
	scene.get_node("Renderer").world_seed = 1234
	scene.get_node("Renderer").overview_profile = profile_builds
	var publish = func(node: Node):
		if node == scene: current_scene = scene
	node_added.connect(publish)
	root.add_child(scene)
	node_added.disconnect(publish)
	generator = root.get_node("WorldGenerator")
	renderer = scene.get_node("Renderer")
	while not generator._maps_ready or generator.is_generating(): await process_frame
	await _settle()
	while not scene.get_node("SurfaceFloraSpawner")._pending.is_empty(): await process_frame
	report["startup"] = renderer.get_render_stats()
	report["generation"] = generator.get_streaming_stats()
	report["fingerprints"] = _fingerprints()
	report["adapter"] = RenderingServer.get_video_adapter_name()
	report["resolution"] = [resolution.x,resolution.y]
	var sky = root.get_node("SkyController")
	root.get_node("WeatherManager").set_weather("base:weather:clear")
	sky.rebind_to_current_scene()
	sky.set_process(false)
	sky._update(12.0)
	var rig = scene.get_node("CameraRig")
	rig.set_process(false)
	camera = rig.camera_node
	camera.reparent(scene)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.current = true
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	var peak: Array = generator._macro_layout.metrics.summit_center
	var peak_target := Vector3((float(peak[0])+.5)*32,75,(float(peak[1])+.5)*32)
	_view(peak_target,330,Vector3(.5,.9,1))
	await _capture("mountain")
	var cliff := _find_cliff()
	if cliff.x < 0:
		push_error("No terrain capture cliff")
		quit(1)
		return
	report["cliff"] = [cliff.x,cliff.y,cliff.z]
	_view(Vector3(cliff)+Vector3(5,4,2),55,Vector3(-1,1,1))
	await _capture("terrain_rts")
	_view(Vector3(cliff)+Vector3(3,4,2),20,Vector3(-1,.8,1))
	await _capture("terrain_close")
	var spring: Vector3i = generator.spring_cave.mouth
	_view(Vector3(spring),34,Vector3(-1,1,1))
	await _capture("cave_entrance")
	# Real edits exercise local overview invalidation and cavity exposure.
	var mined: Array[Vector3i] = []
	for x in range(cliff.x+1,cliff.x+18):
		for z in range(cliff.z,cliff.z+4):
			for y in range(cliff.y+1,cliff.y+5): mined.append(Vector3i(x,y,z))
	var builds: int = renderer._overview_build_count
	var start := Time.get_ticks_usec()
	var single: Array[Vector3i] = [mined[0]]
	scene.get_node("MiningDesignationController")._mine_blocks_world(single)
	var single_dispatch := (Time.get_ticks_usec()-start)/1000.0
	var single_wait := await _settle()
	start = Time.get_ticks_usec()
	scene.get_node("MiningDesignationController")._mine_blocks_world(mined)
	var batch_dispatch := (Time.get_ticks_usec()-start)/1000.0
	var batch_wait := await _settle()
	report["edits"] = {"single_dispatch_ms":single_dispatch,"single_settle":single_wait,
		"batch_dispatch_ms":batch_dispatch,"batch_settle":batch_wait,"tile_rebuilds":renderer._overview_build_count-builds}
	scene.get_node("SliceController")._set_slice_y(cliff.y+4)
	report["slice_settle"] = await _settle()
	_view(Vector3(cliff)+Vector3(8,1,2),34,Vector3(-1,2,1))
	await _capture("mined_slice")
	var furniture = scene.get_node("FurniturePlacementController")
	var torch := "base:furniture:wall_torch"
	furniture._install(torch,furniture.get_defs()[torch],cliff+Vector3i(7,0,0),0)
	furniture._install(torch,furniture.get_defs()[torch],cliff+Vector3i(14,0,0),0)
	await _capture("room_torches")
	sky._update(23.0)
	await _capture("room_night")
	sky._update(12.0)
	scene.get_node("SliceController").deactivate()
	await _settle()
	# Live agents/wildlife remain in the real scene for the final workload sample.
	var director = scene.get_node("DwarfDirector")
	for i in range(5): director._spawn_one(cliff.x-3,cliff.z+i)
	root.get_node("WorldClock").set_paused(false)
	_view(Vector3(cliff)+Vector3(5,4,2),75,Vector3(-1,1,1))
	await _capture("active_world")
	report["dwarves"] = director._agents.size()
	report["wildlife_children"] = scene.get_node("WildlifeManager").get_child_count()
	if extended: await _extended_checks(cliff)
	report["final_renderer"] = renderer.get_render_stats()
	if profile_builds:
		report["build_profile"] = {"tiles":renderer._ovp_tiles,
			"loop_ms":renderer._ovp_loop_usec/1000.0,"sides_ms":renderer._ovp_sides_usec/1000.0,
			"merge_ms":renderer._ovp_merge_usec/1000.0,"upload_ms":renderer._ovp_mesh_usec/1000.0,
			"slowest_tile_total_ms":renderer._ovp_max_tile_usec/1000.0,"slowest_tile":renderer._ovp_max_breakdown}
	FileAccess.open(output+"report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("TERRAIN_CAPTURE_PASS " if report.failures.is_empty() else "TERRAIN_CAPTURE_FAIL ",output)
	generator.prepare_for_world_reload()
	quit(0 if report.failures.is_empty() else 1)

func _extended_checks(cliff: Vector3i) -> void:
	# The original paired route directly sets the slice plane while the tool is
	# inactive. Its active_world sample is therefore a sliced view in both
	# baseline and comparison. Explicitly use the tool lifecycle for this extra
	# full-world workload and subsequent construction/season checks.
	current_scene.get_node("SliceController").activate()
	current_scene.get_node("SliceController").deactivate()
	await _settle()
	if renderer.slice_y != 127: report.failures.append("Full-world slice did not restore")
	await _capture("active_full_world")
	var pan_times: Array[float] = []
	for i in range(180):
		var t := float(i)/179.0
		_view(Vector3(cliff)+Vector3(sin(t*TAU)*70,8,cos(t*TAU)*70),75,Vector3(-1,1,1))
		var tick := Time.get_ticks_usec()
		await process_frame
		pan_times.append((Time.get_ticks_usec()-tick)/1000.0)
	report["fast_pan_frame_ms"] = _percentiles(pan_times)
	root.get_node("WorldClock").set_paused(true)
	# Build a small contact sample through the production construction owner.
	var construction = current_scene.get_node("ConstructionController")
	for y in range(cliff.y+1,cliff.y+4):
		construction._place_block(cliff+Vector3i(1,y-cliff.y,1),"base:terrain:rock:rock01")
	await _settle()
	_view(Vector3(cliff)+Vector3(3,2,2),18,Vector3(-1,1,1))
	await _capture("constructed_contact")
	current_scene.get_node("SliceController").activate()
	current_scene.get_node("SliceController")._set_slice_y(cliff.y+2)
	await _settle()
	await _capture("constructed_cut")
	current_scene.get_node("SliceController").deactivate()
	await _settle()
	var grass := Vector3i(-1,-1,-1)
	var registry = root.get_node("BlockRegistry")
	for x in range(256,768,7):
		for z in range(256,768,7):
			var y: int = generator.get_surface_y(x,z)
			var id: int = generator.get_generated_block_id(x,y,z)
			if registry.get_def(registry.get_key(id)).get("kind","") == "grass":
				grass = Vector3i(x,y,z)
				break
		if grass.x >= 0: break
	if grass.x < 0:
		report.failures.append("No seasonal grass sample")
		return
	_view(Vector3(grass),25,Vector3(-1,1,1))
	# A diagnostic ground view removes tree occlusion only for these captures;
	# the mountain/RTS/active-world measurements above retain all vegetation.
	var flora = current_scene.get_node("SurfaceFloraSpawner")
	flora.visible = false
	report["season_views_hide_trees"] = true
	report["season_refresh"] = {}
	for season in ["spring","summer","autumn","winter"]:
		root.get_node("WorldClock").season = season
		root.get_node("WorldClock").season_changed.emit(season)
		report.season_refresh[season] = await _settle()
		await _capture("grass_"+season)
	flora.visible = true

func _fingerprints() -> Dictionary:
	var ids := PackedInt32Array()
	var families := PackedStringArray()
	var registry = root.get_node("BlockRegistry")
	for x in range(7,1024,31):
		for z in range(11,1024,29):
			for y in range(0,128,7):
				var id: int = generator.get_generated_block_id(x,y,z)
				ids.append(id)
				var key: StringName = registry.get_key(id)
				var kind: String = registry.get_def(key).kind
				families.append(kind if kind in ["rock","dirt","grass"] else String(key))
	return {"height":_digest(generator.heightmap),"water":_digest(generator.waterline_map),
		"domain":_digest(generator.domain_map),"sample_ids":_digest(ids),"sample_materials_resources":_digest(families),
		"sample_count":ids.size(),"caves":_digest(generator.get_cave_catalog())}

func _digest(value: Variant) -> String:
	return var_to_bytes(value).hex_encode().sha256_text()

func _find_cliff() -> Vector3i:
	for z in range(256,768,4):
		for x in range(256,768):
			var y: int = generator.get_surface_y(x,z)
			if y < 8 or y > 100 or generator.get_surface_y(x+1,z) < y+7: continue
			var valid := true
			for dx in range(1,19):
				for dz in range(4):
					if generator.get_surface_y(x+dx,z+dz) < y+7: valid = false
			if valid: return Vector3i(x,y,z)
	return Vector3i(-1,-1,-1)

func _view(target: Vector3, size: float, direction: Vector3) -> void:
	camera.size = size
	camera.position = target+direction.normalized()*maxf(size*1.4,45)
	camera.look_at(target)

func _settle() -> Dictionary:
	var samples: Array[float] = []
	var start := Time.get_ticks_usec()
	for i in range(4): await process_frame
	while not renderer._overview_built or not renderer._dirty_overview_tiles.is_empty() or renderer._cavity_shell_dirty or renderer.underground_lighting.is_updating():
		var tick := Time.get_ticks_usec()
		await process_frame
		samples.append((Time.get_ticks_usec()-tick)/1000.0)
	return {"elapsed_ms":(Time.get_ticks_usec()-start)/1000.0,"frames":samples.size(),"frame_ms":_percentiles(samples)}

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
	var result := root.get_texture().get_image().save_png(output+label+".png")
	if result != OK: report.failures.append("Screenshot "+label)
	report.captures[label] = {"gpu_ms":_percentiles(gpu),"render_cpu_ms":_percentiles(cpu),"frame_ms":_percentiles(frame),
		"slice_y":renderer.slice_y,
		"draws":RenderingServer.viewport_get_render_info(rid,RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
		"primitives":RenderingServer.viewport_get_render_info(rid,RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME),
		"video_memory_bytes":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED),
		"static_memory_bytes":OS.get_static_memory_usage(),"camera_position":str(camera.position),"camera_rotation":str(camera.rotation),"camera_size":camera.size}
	print("TERRAIN_CAPTURE ",label," ",JSON.stringify(report.captures[label]))

func _percentiles(values: Array[float]) -> Dictionary:
	if values.is_empty(): return {}
	values.sort()
	return {"p50":values[values.size()/2],"p95":values[mini(values.size()-1,floori(values.size()*.95))],
		"p99":values[mini(values.size()-1,floori(values.size()*.99))],"max":values.back()}
