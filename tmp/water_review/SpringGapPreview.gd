extends SceneTree

func _init() -> void: _run.call_deferred()

func _run() -> void:
	create_timer(180).timeout.connect(func(): push_error("SpringGapPreview: timeout"); quit(1))
	root.get_node("WorldClock").paused = true
	root.get_node("SaveManager").set_process(false)
	node_added.connect(func(node: Node):
		if node.name=="Renderer" and node.get_script()!=null: node.set("world_seed",1675083273))
	change_scene_to_file("res://scenes/main/debug_world.tscn")
	await process_frame
	await process_frame
	var terrain = current_scene.get_node("Renderer")
	var gen = root.get_node("WorldGenerator")
	var water = root.get_node("WaterManager")
	while not terrain._overview_built or terrain._overview_tile_nodes.size()!=1024: await process_frame
	while not water.initialized or not water.dirty_tiles.is_empty(): await process_frame
	root.size = Vector2i(1400,1000)
	root.get_node("SkyController").rebind_to_current_scene()
	root.get_node("WorldClock").hour = 9.4
	root.get_node("SkyController")._update(9.4)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	current_scene.add_child(camera)
	camera.make_current()
	var back2: Vector2i = gen.river_layout.spring_back
	var back := Vector3(back2.x,0,back2.y)
	var side := Vector3(-back2.y,0,back2.x)
	var point := Vector3(gen.spring_cave.mouth)-back*2+Vector3(.5,0,.5)
	camera.size = 26
	camera.position = point-back*18-side*9+Vector3(0,28,0)
	camera.look_at(point)
	var slices = current_scene.get_node("SliceController")
	slices.restore_state({"active":true,"slice_y":107})
	await process_frame
	while not terrain._dirty_overview_tiles.is_empty(): await process_frame
	var label := "before" if "--before" in OS.get_cmdline_user_args() else "after"
	await picture(label+"_initial")
	for angle in [0.0,0.25,0.5]:
		camera.position = point-back*24-side*24*angle+Vector3(0,19,0)
		camera.look_at(point)
		await picture(label+"_angle_"+str(angle))
	for i in 1000: water.step(.1)
	await picture(label+"_running")
	slices.deactivate()
	await process_frame
	while not terrain._dirty_overview_tiles.is_empty(): await process_frame
	await picture(label+"_full")
	print("SpringGapPreview: DONE ",label)
	quit()

func picture(label: String) -> void:
	for i in 30: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tmp/water_review/spring_gap_"+label+".png")
