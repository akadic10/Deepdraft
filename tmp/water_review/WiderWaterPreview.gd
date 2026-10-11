extends SceneTree

func _init() -> void: _run.call_deferred()

func _run() -> void:
	create_timer(120).timeout.connect(func(): push_error("Water preview timeout"); quit(1))
	root.get_node("WorldClock").paused = true
	root.get_node("SaveManager").set_process(false)
	node_added.connect(func(node: Node):
		if node.name=="Renderer" and node.get_script()!=null: node.set("world_seed",2544080684))
	change_scene_to_file("res://scenes/main/debug_world.tscn")
	await process_frame
	await process_frame
	var generator = root.get_node("WorldGenerator")
	while not generator._maps_ready: await process_frame
	var water = root.get_node("WaterManager")
	water.initialize()
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	current_scene.add_child(camera)
	camera.make_current()
	root.size = Vector2i(1440,1000)
	for node in current_scene.find_children("*","CanvasLayer",true,false): node.visible = false
	var route: Array = generator.river_layout.route
	var mouth := Vector2i.ZERO
	for i in range(route.size()-1,-1,-1):
		if generator.river_layout.columns.has(route[i]):
			mouth = route[i]
			break
	var middle: Vector2i = route[route.size()/2]
	var sites := {"junction":Vector3(mouth.x,19,mouth.y),"reach":Vector3(middle.x,generator.get_surface_y(middle.x,middle.y)+1,middle.y)}
	for i in 900:
		water.step(0.1)
		if i%20==0: await process_frame
	for label: String in sites:
		var focus: Vector3 = sites[label]
		camera.size = 66 if label=="junction" else 44
		var offset := Vector3(30,45,35)
		if label=="junction":
			var away := Vector3(mouth.x-generator.lake_center.x,0,mouth.y-generator.lake_center.y).normalized()
			offset = away*50+Vector3(-away.z,0,away.x)*18+Vector3(0,48,0)
		camera.position = focus+offset
		camera.look_at(focus)
		for _i in 150: await process_frame
		if DisplayServer.get_name()!="headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://tmp/water_review/wider_"+label+".png")
		print("Water preview ",label," focus ",focus)
	print("WiderWaterPreview: PASS; columns ",generator.river_layout.columns.size())
	quit()
