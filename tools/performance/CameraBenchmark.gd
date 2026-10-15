extends SceneTree

## Rendered, real-time diagnostic. Run via Run.ps1 to isolate player storage.
## No fixed-fps delta; no production configuration or simulation algorithm changes.
var output := ""
var saved := false
var markers := true
var weather_override := ""
var ablations := true
var room_rebuilds := false
var seconds := 8.0
var resolution := Vector2i(2560,1440)
var scene: Node
var rig: Node3D
var renderer: Node
var water_view: Node
var moisture_view: Node
var clock_node: Node
var generator: Node
var probe: Node
var origin := Vector3.ZERO
var measurements := {}
var starts := {}
var report := {}

func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=").trim_suffix("/")+"/"
		if arg=="--saved": saved=true
		if arg=="--no-markers": markers=false
		if arg=="--no-ablations": ablations=false
		if arg=="--room-rebuilds": room_rebuilds=true
		if arg.begins_with("--weather="): weather_override=arg.trim_prefix("--weather=")
		if arg.begins_with("--seconds="): seconds=maxf(3,float(arg.trim_prefix("--seconds=")))
		if arg=="--small": resolution=Vector2i(1280,720)
	_run.call_deferred()

func _run() -> void:
	if output.is_empty() or not "/performance_20261014/" in OS.get_user_data_dir().replace("\\","/"):
		push_error("Benchmark requires an isolated performance_20261014 profile and output")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.size=resolution
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps=0
	clock_node=root.get_node("WorldClock")
	generator=root.get_node("WorldGenerator")
	clock_node.set_paused(true)
	var saves=root.get_node("SaveManager")
	saves.set_process(false)
	node_added.connect(func(node: Node):
		if node.name=="Renderer" and node.get_script()!=null: node.set("world_seed",1234))
	if saved:
		# A lightweight scene with the real reload path avoids generating a throwaway world.
		var placeholder:=Node3D.new()
		placeholder.scene_file_path="res://scenes/main/debug_world.tscn"
		root.add_child(placeholder)
		current_scene=placeholder
		saves.set_process(true)
		if not saves.request_load(): quit(2); return
		while saves.is_loading(): await process_frame
		saves.set_process(false)
	else:
		change_scene_to_file("res://scenes/main/debug_world.tscn")
		await process_frame
		await process_frame
	scene=current_scene
	renderer=scene.get_node("Renderer")
	moisture_view=_find_script(scene,"res://scripts/components/MoistureRenderer.gd")
	rig=scene.get_node("CameraRig")
	root.get_node("SkyController").rebind_to_current_scene()
	clock_node.set_paused(true)
	clock_node.set_speed(1)
	if not weather_override.is_empty(): root.get_node("WeatherManager").set_weather(weather_override)
	var setup_start:=Time.get_ticks_msec()
	while not _ready_for_sampling():
		if Time.get_ticks_msec()-setup_start>120000: push_error("Benchmark world did not settle"); quit(2); return
		await process_frame
	await _prepare_workload()
	water_view=_find_script(scene,"res://scripts/components/WaterRenderer.gd")
	_set_sampling_camera()
	rig.stop_following()
	probe=load("res://tools/settlement_art/FrameProbe.gd").new()
	scene.add_child(probe)
	if markers: _install_markers()
	scene.get_node("WildlifeManager").profile_updates = markers
	root.get_node("WaterManager").profile_updates = markers
	water_view.profile_updates = markers
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	report={"engine":Engine.get_version_info(),"cpu":OS.get_processor_name(),"gpu":RenderingServer.get_video_adapter_name(),
		"room_manager_sha256":FileAccess.get_sha256("res://scripts/systems/RoomManager.gd"),
		"room_rebuild_sha256":FileAccess.get_sha256("res://scripts/components/RoomRebuild.gd") if FileAccess.file_exists("res://scripts/components/RoomRebuild.gd") else "",
		"scheduled_room_rebuilds":room_rebuilds,
		"water_renderer_sha256":FileAccess.get_sha256("res://scripts/components/WaterRenderer.gd"),
		"water_motion_sha256":FileAccess.get_sha256("res://scripts/components/WaterSurfaceMotion.gd"),
		"water_builder_sha256":FileAccess.get_sha256("res://scripts/components/WaterMeshBuilder.gd"),
		"water_manager_sha256":FileAccess.get_sha256("res://scripts/systems/WaterManager.gd"),
		"water_flow_sha256":FileAccess.get_sha256("res://scripts/components/WaterFlow.gd"),
		"soil_moisture_sha256":FileAccess.get_sha256("res://scripts/components/SoilMoisture.gd"),
		"moisture_renderer_sha256":FileAccess.get_sha256("res://scripts/components/MoistureRenderer.gd"),
		"animal_navigation_sha256":FileAccess.get_sha256("res://scripts/components/AnimalNavigation.gd"),
		"duck_navigation_sha256":FileAccess.get_sha256("res://scripts/components/DuckNavigation.gd"),
		"duck_agent_sha256":FileAccess.get_sha256("res://scripts/entities/DuckAgent.gd"),
		"wildlife_manager_sha256":FileAccess.get_sha256("res://scripts/systems/WildlifeManager.gd"),
		"occupancy_registry_sha256":FileAccess.get_sha256("res://scripts/registries/PlacedEntityRegistry.gd"),
		"driver":RenderingServer.get_current_rendering_driver_name(),"resolution":[resolution.x,resolution.y],
		"saved":saved,"seed":generator.world_seed,"markers":markers,"vsync":"disabled","fixed_fps":false,
		"weather":root.get_node("WeatherManager").current_weather_id(),"weather_override":weather_override,
		"ablations":ablations,
		"sample_seconds_min":seconds,"camera_origin":str(origin),"camera_zoom":rig._target_zoom,
		"slice_y":renderer.slice_y,"counts":_counts(),"phases":{},"ready_renderer":renderer.get_render_stats(),
		"note":"Same-priority process brackets include descendants; do not sum nested groups. GPU timestamps can lag. Ablations freeze a subsystem for diagnosis, not a gameplay solution. Sequential phases advance the same world."}
	for mode: String in _benchmark_modes():
		await _sample(mode)
	report["final_renderer"]=renderer.get_render_stats()
	_save_report()
	print("CAMERA_BENCHMARK_PASS ",output)
	generator.prepare_for_world_reload()
	quit(0)

func _prepare_workload() -> void:
	pass

func _set_sampling_camera() -> void:
	if not saved:
		origin=Vector3(512,generator.get_surface_y(512,512)+3,512)
		rig._target_pos=origin
		rig.global_position=origin
	else:
		origin=rig._target_pos

func _benchmark_modes() -> Array[String]:
	var modes: Array[String] = ["paused_static","paused_pan","active_static","active_pan"]
	if ablations:
		modes.append_array(["active_pan_no_water_sim","active_pan_no_water_render","active_pan_no_wildlife",
			"active_pan_no_audio","active_pan_no_hud","active_pan_no_water_and_wildlife"])
	modes.append("active_pan_repeat")
	return modes

func _ready_for_sampling() -> bool:
	if not generator._maps_ready or generator.is_generating(): return false
	if not renderer._overview_built or not renderer._dirty_overview_tiles.is_empty() or renderer._cavity_shell_dirty: return false
	if renderer.underground_lighting.is_updating(): return false
	if moisture_view!=null and moisture_view.has_method("is_updating") and moisture_view.is_updating(): return false
	if not scene.get_node("SurfaceFloraSpawner")._pending.is_empty(): return false
	var details=scene.get_node("SurfaceDetailManager")
	if not details._initialized or not details._visual_queue.is_empty(): return false
	return scene.get_node("WildlifeManager").duck_initialized

func _find_script(node: Node, path: String) -> Node:
	if node.get_script()!=null and node.get_script().resource_path==path: return node
	for child in node.get_children():
		var found:=_find_script(child,path)
		if found!=null: return found
	return null

func _all_nodes(node: Node) -> Array[Node]:
	var nodes: Array[Node]=[node]
	for child in node.get_children(): nodes.append_array(_all_nodes(child))
	return nodes

func _install_markers() -> void:
	var targets: Array[Node]=[]
	for node in root.get_children():
		if node!=scene and node.is_processing(): targets.append(node)
	for node in scene.get_children():
		if node.is_processing(): targets.append(node)
	if water_view!=null: targets.append(water_view)
	for node in _all_nodes(scene):
		if node.get_script()==null: continue
		if node.get_script().resource_path in ["res://scripts/components/WaterSound.gd","res://scripts/components/UndergroundLighting.gd","res://scripts/components/MoistureRenderer.gd"] and node.is_processing(): targets.append(node)
	for target in targets:
		var label:=str(target.get_path()).trim_prefix("/root/")
		if target.get_script().resource_path == "res://scripts/components/MoistureRenderer.gd": label="MoistureRenderer"
		var parent:=target.get_parent()
		for before: bool in [true,false]:
			var marker=load("res://tools/performance/ProcessMarker.gd").new()
			marker.label=label
			marker.before=before
			marker.measurements=measurements
			marker.starts=starts
			marker.process_priority=target.process_priority
			parent.add_child(marker)
			parent.move_child(marker,target.get_index() if before else target.get_index()+1)

func _sample(mode: String) -> void:
	var pan: bool=mode.contains("pan")
	clock_node.set_paused(mode.begins_with("paused"))
	var frozen: Array[Node]=[]
	if mode.ends_with("no_water_sim"): frozen.append(root.get_node("WaterManager"))
	if mode.ends_with("no_water_render") and water_view!=null: frozen.append(water_view)
	if mode.ends_with("no_wildlife"): frozen.append(scene.get_node("WildlifeManager"))
	if mode.ends_with("no_water_and_wildlife"):
		frozen.append(root.get_node("WaterManager"))
		frozen.append(scene.get_node("WildlifeManager"))
	if mode.ends_with("no_audio"):
		for node in _all_nodes(root):
			if node.get_script()==null or not node.is_processing(): continue
			if node.get_script().resource_path in ["res://scripts/systems/WorkFeedback.gd","res://scripts/systems/AmbientAudio.gd","res://scripts/components/WaterSound.gd","res://scripts/components/FurnitureFireSound.gd"]: frozen.append(node)
	var hud: Array[Node]=[]
	if mode.ends_with("no_hud"):
		for node in scene.get_children():
			if node is CanvasLayer: hud.append(node); node.process_mode=Node.PROCESS_MODE_DISABLED
	for node in frozen: node.set_process(false)
	var phase_start:=Time.get_ticks_usec()
	while Time.get_ticks_usec()-phase_start<1500000:
		_drive_camera(pan,(Time.get_ticks_usec()-phase_start)/1000000.0)
		await process_frame
	var rows: Array=[]
	var rid:=root.get_viewport_rid()
	var sample_start:=Time.get_ticks_usec()
	var previous_frame:=sample_start
	var room_triggers := 0
	var rooms := root.get_node("RoomManager")
	var water_start: Dictionary=water_view.get_mesh_stats() if water_view.has_method("get_mesh_stats") else {}
	var navigation=load("res://scripts/components/AnimalNavigation.gd")
	var navigation_start: Dictionary=navigation.get_cache_stats() if navigation.has_method("get_cache_stats") else {}
	while Time.get_ticks_usec()-sample_start<int(seconds*1000000) or rows.size()<240:
		# Explicit stress scenario: identical geometry, one invalidation per second.
		# Ordinary benchmarks retain natural triggers only.
		if room_rebuilds and pan and (Time.get_ticks_usec()-sample_start)/1000000.0>=room_triggers:
			rooms._mark_dirty()
			room_triggers += 1
		_drive_camera(pan,(Time.get_ticks_usec()-sample_start)/1000000.0)
		await process_frame
		var current_frame:=Time.get_ticks_usec()
		var row: Dictionary={"frame_ms":(current_frame-previous_frame)/1000.0,"scene_ms":probe.last_ms,
			"gpu_ms":RenderingServer.viewport_get_measured_render_time_gpu(rid),
			"render_cpu_ms":RenderingServer.viewport_get_measured_render_time_cpu(rid),
			"water_dirty_tiles":root.get_node("WaterManager").dirty_tiles.size(),"process":measurements.duplicate()}
		if water_view.has_method("get_mesh_stats"): row["water_mesh"]=water_view.get_mesh_stats()
		if rooms.has_method("get_rebuild_stats"): row["rooms"]=rooms.get_rebuild_stats()
		if water_view.motion.has_method("get_stats"): row["water_motion"]=water_view.motion.get_stats()
		if markers and water_view.is_processing():
			for stage: String in water_view.last_update_ms:
				row.process["water_render/"+stage]=water_view.last_update_ms[stage]
		if moisture_view!=null and moisture_view.has_method("get_mesh_stats"): row["moisture_mesh"]=moisture_view.get_mesh_stats()
		if markers and root.get_node("WaterManager").is_processing() and not clock_node.paused:
			for stage: String in root.get_node("WaterManager").last_update_ms:
				row.process["water_sim/"+stage]=root.get_node("WaterManager").last_update_ms[stage]
		if markers and scene.get_node("WildlifeManager").is_processing() and not clock_node.paused:
			for species: String in scene.get_node("WildlifeManager").last_update_ms:
				row.process["wildlife/"+species]=scene.get_node("WildlifeManager").last_update_ms[species]
			if scene.get_node("WildlifeManager").has_method("get_duck_profile"):
				row["duck_profile"]=scene.get_node("WildlifeManager").get_duck_profile()
		rows.append(row)
		previous_frame=current_frame
	var summary: Dictionary={"frames":rows.size(),"seconds":(Time.get_ticks_usec()-sample_start)/1000000.0,
		"scheduled_room_rebuilds":room_triggers,
		"weather":root.get_node("WeatherManager").current_weather_id(),
		"draw_calls":RenderingServer.viewport_get_render_info(rid,RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
		"primitives":RenderingServer.viewport_get_render_info(rid,RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME),
		"process":{},"water_dirty_tiles":root.get_node("WaterManager").dirty_tiles.size()}
	if not navigation_start.is_empty():
		summary["navigation_cache_start"]=navigation_start
		summary["navigation_cache_end"]=navigation.get_cache_stats()
	if not water_start.is_empty():
		summary["water_mesh_start"]=water_start
		summary["water_mesh_end"]=water_view.get_mesh_stats()
		summary["water_mesh"]={}
		for key: String in ["main_ms","snapshot_ms","upload_ms","pending","oldest_ms"]:
			var values: Array=[]
			for row: Dictionary in rows: values.append(row.water_mesh[key])
			summary.water_mesh[key]=_stats(values)
	for key: String in ["frame_ms","scene_ms","gpu_ms","render_cpu_ms"]:
		var values: Array=[]
		for row: Dictionary in rows: values.append(row[key])
		summary[key]=_stats(values)
	var process_keys: Dictionary={}
	for row: Dictionary in rows:
		for key: String in row.process: process_keys[key]=true
	for key: String in process_keys:
		var values: Array=[]
		for row: Dictionary in rows: values.append(row.process.get(key,0.0))
		summary.process[key]=_stats(values)
	FileAccess.open(output+mode+"_frames.json",FileAccess.WRITE).store_string(JSON.stringify(rows))
	report.phases[mode]=summary
	_save_report()
	print("CAMERA_SAMPLE ",mode," ",JSON.stringify({"wall":summary.frame_ms,"scene":summary.scene_ms,"gpu":summary.gpu_ms}))
	for node in frozen: node.set_process(true)
	for node in hud: node.process_mode=Node.PROCESS_MODE_INHERIT

func _drive_camera(pan: bool, time: float) -> void:
	rig._target_pos=origin+(Vector3(sin(time*TAU/8)*18,0,cos(time*TAU/8)*18) if pan else Vector3.ZERO)

func _stats(values: Array) -> Dictionary:
	values.sort()
	var total:=0.0
	var over16:=0
	var over33:=0
	var over50:=0
	var over100:=0
	for value: float in values:
		total+=value
		if value>1000.0/60: over16+=1
		if value>1000.0/30: over33+=1
		if value>50: over50+=1
		if value>100: over100+=1
	var n:=values.size()
	return {"mean":total/n,"p50":values[int((n-1)*.5)],"p95":values[int((n-1)*.95)],"p99":values[int((n-1)*.99)],"max":values.back(),"over_16_7":over16,"over_33_3":over33,"over_50":over50,"over_100":over100}

func _counts() -> Dictionary:
	var wildlife=scene.get_node("WildlifeManager")
	var in_frustum:=0
	var near_colony:=0
	for animal in wildlife.animals:
		if rig.camera_node.is_position_in_frustum(animal.global_position): in_frustum+=1
		if animal.global_position.distance_to(origin)<100: near_colony+=1
	return {"dwarves":scene.get_node("DwarfDirector").get_roster().size(),"wildlife":wildlife.animals.size(),
		"wildlife_points_in_camera_frustum":in_frustum,"wildlife_within_100_units_of_camera_target":near_colony,
		"furniture":scene.get_node("FurniturePlacementController")._installed.size(),"trees":scene.get_node("SurfaceFloraSpawner")._trees.size(),
		"surface_details":scene.get_node("SurfaceDetailManager")._records.size(),"nodes":get_node_count(),
		"water_columns":root.get_node("WaterManager").flow.mass.size()}

func _save_report() -> void:
	FileAccess.open(output+"report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
