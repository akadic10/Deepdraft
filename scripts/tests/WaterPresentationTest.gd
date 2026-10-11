extends SceneTree

func _init() -> void: _run.call_deferred()

func _run() -> void:
	create_timer(110).timeout.connect(func(): push_error("Water presentation timeout"); quit(1))
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
			root.get_texture().get_image().save_png("res://tmp/water_review/"+label+".png")
	var dam: Vector3i = water.dev_toggle_dam()
	for i in 6000:
		water.step(0.1)
		if i%100==0: await process_frame
	camera.size = 30
	var dam_center := Vector3(dam)+Vector3(0,1,0)
	camera.position = dam_center+Vector3(25,28,35)
	camera.look_at(dam_center)
	for _i in 60: await process_frame
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tmp/water_review/flood.png")
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
		if DisplayServer.get_name()!="headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://tmp/water_review/moisture.png")
	water.show_moisture = false
	current_scene.get_node("UIWindowManager").open("water_dev")
	for node in current_scene.find_children("*","CanvasLayer",true,false):
		if node.name in ["UIWindowManager","DockUI","WaterDebugPanel"]: node.visible = true
	for _i in 15: await process_frame
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tmp/water_review/controls.png")
	print("WaterPresentationTest: PASS")
	quit()
