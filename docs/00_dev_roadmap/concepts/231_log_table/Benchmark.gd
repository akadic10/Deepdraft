extends SceneTree

## Render-only detailed/proxy log-table shadow comparison. Recovery files never replace production.
const Shadows = preload("res://scripts/components/VoxelShadowSetup.gd")
var output := "res://tmp/settlement_art_20261013/mined_benchmark/"
var stage: Node3D
var content: Node3D
var libraries := []

func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=").trim_suffix("/")+"/"
	_run.call_deferred()

func _run() -> void:
	for node in root.get_children(): node.set_process(false)
	root.size=Vector2i(1600,1000)
	root.mesh_lod_threshold=0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	stage=Node3D.new();root.add_child(stage);current_scene=stage
	content=Node3D.new();stage.add_child(content)
	var env:=WorldEnvironment.new();env.environment=Environment.new()
	env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color("263234")
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_energy=.65
	stage.add_child(env)
	var light:=DirectionalLight3D.new();stage.add_child(light)
	light.rotation_degrees=Vector3(-50,-30,0);light.shadow_enabled=true;light.directional_shadow_max_distance=70
	var ground:=MeshInstance3D.new();ground.mesh=PlaneMesh.new();ground.mesh.size=Vector2(35,35)
	ground.position=Vector3(0,-.01,0);stage.add_child(ground)
	var camera:=Camera3D.new();stage.add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=31;camera.position=Vector3(20,25,30);camera.look_at(Vector3.ZERO);camera.current=true
	var material:=StandardMaterial3D.new();material.vertex_color_use_as_albedo=true;material.roughness=1
	var paths: Array[String]=["assets/models/furniture/log_table.glb"]
	for prefix in ["res://","res://"]:
		var packed_models:=[]
		for path in paths:
			var document:=GLTFDocument.new();var state:=GLTFState.new()
			assert(document.append_from_file(prefix+path,state)==OK)
			var model:=document.generate_scene(state)
			Shadows.configure(model)
			for mesh in Shadows.visual_meshes(model): mesh.material_override=material
			var packed:=PackedScene.new();assert(packed.pack(model)==OK)
			packed_models.append(packed);model.free()
		libraries.append(packed_models)
	DirAccess.make_dir_recursive_absolute(output)
	var results:=[]
	for pass_index in 4:
		var revision:=pass_index%2
		for child in content.get_children(): child.free()
		for i in 64:
			var model: Node3D=libraries[revision][i%paths.size()].instantiate();content.add_child(model)
			Shadows.configure(model,revision==1)
			model.position=Vector3((i%8-3.5)*3.5,0,(i/8-3.5)*3.5)
		for frame in 60: await process_frame
		var gpu:=[];var cpu:=[];var wall:=[]
		for frame in 180:
			var tick:=Time.get_ticks_usec();await process_frame
			wall.append((Time.get_ticks_usec()-tick)/1000.0)
			gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
			cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()))
		gpu.sort();cpu.sort();wall.sort()
		results.append({"revision":"detailed" if revision==0 else "proxy","gpu_p50_ms":gpu[90],"gpu_p95_ms":gpu[171],"render_cpu_p50_ms":cpu[90],"frame_p95_ms":wall[171],"draws":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)})
		if pass_index<2:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output+("detailed" if revision==0 else "proxy")+".png")
	var report={"objects":64,"forms":1,"resolution":[1600,1000],"adapter":RenderingServer.get_video_adapter_name(),"results":results,"limits":"Render-only matched camera/material/light; no simulation or terrain. Same GLB decoded identically; only shadow caster changes with LOD disabled. Not a full-game benchmark."}
	FileAccess.open(output+"report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("LOG_TABLE_BENCHMARK_OK ",JSON.stringify(report));quit()
