extends SceneTree

const OUTPUT := "res://tmp/terrain_art_20261013/material_pilot/"
var report := {"captures":{},"checks":[],"failures":[]}

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	if not "/terrain_art_20261013/" in OS.get_user_data_dir().replace("\\","/"):
		push_error("Material pilot requires isolated terrain profile")
		quit(2)
		return
	create_timer(180).timeout.connect(func(): push_error("Material pilot timeout"); quit(1))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	root.size = Vector2i(1600,1000)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	change_scene_to_file("res://scenes/studies/visual_study.tscn")
	while current_scene == null: await process_frame
	var study = current_scene
	while not study.ready_for_review: await process_frame
	study.capture_mode = true
	study.apply_look(false,"Day")
	var source := StandardMaterial3D.new()
	source.vertex_color_use_as_albedo = true
	var material: ShaderMaterial = study.field.make_material(source)
	var registry = root.get_node("BlockRegistry")
	registry.configure_terrain_material(material)
	var world = root.get_node("WorldData")
	var before := {}
	for coord in world._chunks: before[coord] = hash(world._chunks[coord].blocks)
	for treatment in ["palette","shading","geometry"]:
		material.set_shader_parameter("terrain_detail_enabled",treatment == "shading")
		var start := Time.get_ticks_usec()
		study.terrain.rebuild(material,study.floor_pair.current,false,false,treatment)
		var build_ms := (Time.get_ticks_usec()-start)/1000.0
		for view in ["Ground","Rooms","Scene"]:
			study.set_view(view)
			study.summary.text = "Base terrain · "+treatment+" · Production lighting"
			study.metrics.text = "Full grass voxels · Coherent grey stone"
			await _capture(study,treatment+"_"+view.to_lower(),build_ms)
	material.set_shader_parameter("terrain_detail_enabled",true)
	study.set_view("Ground")
	var clock = root.get_node("WorldClock")
	for season in ["spring","summer","autumn","winter"]:
		clock.season = season
		study.terrain.rebuild(material,study.floor_pair.current,false,false,"shading")
		study.summary.text = "Full grass voxels · "+season+" · Production lighting"
		await _capture(study,"season_"+season,0)
	clock.season = "summer"
	study.set_view("Rooms")
	for phase in ["Dusk","Night"]:
		study.apply_look(false,phase)
		study.terrain.rebuild(material,study.floor_pair.current,false,false,"shading")
		study.summary.text = "Base terrain · "+phase+" · Production lighting"
		await _capture(study,"rooms_"+phase.to_lower(),0)
	var after := {}
	for coord in world._chunks: after[coord] = hash(world._chunks[coord].blocks)
	_check(before == after,"All treatment and season comparisons preserve the voxel data")
	for light in study.bounce_lights: _check(not light.visible,"Study fill light disabled")
	_check(not study.environment.ssao_enabled,"Production comparison does not depend on study SSAO")
	report["adapter"] = RenderingServer.get_video_adapter_name()
	report["resolution"] = [1600,1000]
	FileAccess.open(OUTPUT+"report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("TERRAIN_MATERIAL_PILOT_PASS" if report.failures.is_empty() else "TERRAIN_MATERIAL_PILOT_FAIL")
	quit(0 if report.failures.is_empty() else 1)

func _capture(study: Node, label: String, build_ms: float) -> void:
	for i in range(20): await process_frame
	var readings: Array[float] = []
	for i in range(90):
		await process_frame
		readings.append(study.render_metrics().gpu_ms)
	readings.sort()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUTPUT+label+".png")
	var metrics: Dictionary = study.render_metrics()
	metrics["gpu_median_ms"] = readings[readings.size()/2]
	metrics["gpu_p95_ms"] = readings[floori(readings.size()*.95)]
	metrics["rebuild_ms"] = build_ms
	report.captures[label] = metrics
	print("MATERIAL_CAPTURE ",label," ",JSON.stringify(metrics))

func _check(ok: bool, message: String) -> void:
	report.checks.append(message)
	if not ok: report.failures.append(message)
