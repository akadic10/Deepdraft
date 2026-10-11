extends SceneTree

func _init() -> void: _run.call_deferred()
func _run() -> void:
	create_timer(180).timeout.connect(func(): push_error("Cave preview timeout"); quit(1))
	root.get_node("WorldClock").paused = true
	root.get_node("SaveManager").set_process(false)
	node_added.connect(func(node: Node):
		if node.name=="Renderer" and node.get_script()!=null: node.set("world_seed",2544080684))
	change_scene_to_file("res://scenes/main/debug_world.tscn")
	await process_frame
	await process_frame
	var gen = root.get_node("WorldGenerator")
	while not gen._maps_ready: await process_frame
	var water = root.get_node("WaterManager")
	water.initialize()
	root.get_node("SkyController")._bind_to_scene()
	root.get_node("SkyController")._apply_static_base()
	var view = current_scene.get_node("Renderer")
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	current_scene.add_child(camera)
	camera.make_current()
	root.size = Vector2i(1440,1000)
	for node in current_scene.find_children("*","CanvasLayer",true,false): node.visible = false
	var cave: Dictionary = gen.spring_cave
	var b: Vector2i = gen.river_layout.spring_back
	var back := Vector3(b.x,0,b.y)
	var side := Vector3(-b.y,0,b.x)
	var focus := Vector3(cave.mouth)+Vector3(0.5,1,0.5)
	for i in 100:
		water.step(0.1)
		if i%10==0: await process_frame
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(cave.source)-back*2+side*2+Vector3(0.5,2.5,0.5)
	lamp.light_color = Color("#FFD391")
	lamp.light_energy = 1.5
	lamp.omni_range = 9
	lamp.visible = false
	current_scene.add_child(lamp)
	for label in ["entrance","interior","torch","night","water_close","water_wide","water_running"]:
		view.slice_y = 127
		camera.size = 23
		var center := focus+back*2
		var offset := -back*30+side*12+Vector3(0,17,0)
		lamp.visible = label=="torch"
		if label in ["interior","torch","night"]:
			view.slice_y = cave.mouth.y+3
			center = focus+back*5
			offset = -back*15+side*16+Vector3(0,26,0)
		if label=="night": root.get_node("WorldClock").hour = 0.0
		if label.begins_with("water"):
			root.get_node("WorldClock").hour = 10.0
			var p: Vector2i = gen.river_layout.route[gen.river_layout.route.size()/2]
			center = Vector3(p.x,gen.get_surface_y(p.x,p.y)+1,p.y)
			offset = Vector3(30,35,22)
			camera.size = 18 if label=="water_close" else 44
		if label=="water_running": root.get_node("WorldClock").paused = false
		root.get_node("SkyController")._update(root.get_node("WorldClock").hour)
		camera.position = center+offset
		camera.look_at(center)
		for i in 220: await process_frame
		while view.underground_lighting.is_updating(): await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tmp/water_review/cave_"+label+".png")
		print("CavePreview ",label," source sky ",view.underground_lighting.sky_at(cave.source)," mouth sky ",view.underground_lighting.sky_at(cave.mouth))
	print("SpringCavePreview: PASS")
	quit()
