extends SceneTree

var output_dir := "res://tmp/water_review/"

func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output_dir=arg.trim_prefix("--output=").trim_suffix("/")+"/"
	_run.call_deferred()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output_dir)
	create_timer(180).timeout.connect(func(): push_error("Water presentation timeout"); quit(1))
	root.get_node("WorldClock").paused = true
	root.get_node("SaveManager").set_process(false)
	node_added.connect(func(node: Node):
		if node.name=="Renderer" and node.get_script()!=null: node.set("world_seed",1234))
	change_scene_to_file("res://scenes/main/debug_world.tscn")
	await process_frame
	await process_frame
	var generator = root.get_node("WorldGenerator")
	while not generator._maps_ready: await process_frame
	var water = root.get_node("WaterManager")
	water.initialize()
	await _wait_for_meshes()
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 48
	current_scene.add_child(camera)
	camera.make_current()
	root.size = Vector2i(1440,1000)
	for node in current_scene.find_children("*","CanvasLayer",true,false): node.visible = false
	var source: Vector3i = generator.river_layout.spring
	var back: Vector2i = generator.river_layout.spring_back
	var sites := {"spring":Vector3(source)+Vector3(0.5,0.8,0.5),"lake":Vector3(generator.river_layout.outlet)}
	var offsets := {"spring":Vector3(-back.x*22-back.y*14,18,-back.y*22+back.x*14),"lake":Vector3(35,35,45)}
	var route: Array = generator.river_layout.route
	for i in range(1,route.size()):
		var a: Vector2i = route[i-1]
		var b: Vector2i = route[i]
		var high: int = generator.get_surface_y(a.x,a.y)+2
		var low: int = generator.get_surface_y(b.x,b.y)+2
		if high-low<6: continue
		var dir := Vector3(b.x-a.x,0,b.y-a.y)
		sites["falls"] = Vector3(a.x+0.5,(high+low)*0.5,a.y+0.5)+dir*0.5
		offsets["falls"] = dir*25+Vector3(-dir.z,0,dir.x)*15+Vector3(0,17,0)
		break
	for label: String in sites:
		var center: Vector3 = sites[label]
		camera.size = 14 if label=="spring" else 34
		camera.position = center+offsets[label]
		camera.look_at(center)
		for _i in 120: await process_frame
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output_dir+label+".png")
	var dam: Vector3i = water.dev_toggle_dam()
	for i in 6000:
		water.step(0.1)
		if i%100==0: await process_frame
	camera.size = 30
	var dam_center := Vector3(dam)+Vector3(0,1,0)
	camera.position = dam_center+Vector3(25,28,35)
	camera.look_at(dam_center)
	for _i in 60: await process_frame
	await _wait_for_meshes()
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output_dir+"flood.png")
	water.show_moisture = true
	var moist_cell := Vector3i.ZERO
	for cell: Vector3i in water.moisture.soils:
		if water.soil_moisture_at(cell)>0.6:
			moist_cell = cell
			break
	if moist_cell!=Vector3i.ZERO:
		camera.size = 22
		camera.position = Vector3(moist_cell)+Vector3(18,25,25)
		camera.look_at(Vector3(moist_cell))
		for _i in 30: await process_frame
		await _wait_for_meshes()
		if DisplayServer.get_name()!="headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output_dir+"moisture.png")
	water.show_moisture = false
	current_scene.get_node("UIWindowManager").open("water_dev")
	for node in current_scene.find_children("*","CanvasLayer",true,false):
		if node.name in ["UIWindowManager","DockUI","WaterDebugPanel"]: node.visible = true
	for _i in 15: await process_frame
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output_dir+"controls.png")
	print("WaterPresentationTest: PASS")
	quit()

func _wait_for_meshes() -> void:
	var terrain = current_scene.get_node("Renderer")
	var water_view = terrain.get_node("Water")
	var water = root.get_node("WaterManager")
	var moisture: Node
	for child in terrain.get_children():
		if child.get_script()!=null and child.get_script().resource_path=="res://scripts/components/MoistureRenderer.gd": moisture=child
	# Frame counts alone can capture floating water before asynchronous terrain
	# startup finishes. Wait for the actual work, including after the test dam.
	while not terrain._overview_built or not terrain._dirty_overview_tiles.is_empty() \
		or terrain._cavity_shell_dirty or terrain.underground_lighting.is_updating() \
		or not water.dirty_tiles.is_empty() or not water_view._pending.is_empty() or not water_view._jobs.is_empty() \
		or not current_scene.get_node("SurfaceFloraSpawner")._pending.is_empty() \
		or not current_scene.get_node("SurfaceDetailManager")._visual_queue.is_empty() \
		or water_view.motion.is_updating() or (moisture!=null and moisture.is_updating()):
		await process_frame
