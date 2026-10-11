extends SceneTree

## Native visual regression for the reported terrace spill (isolated APPDATA).
func _init() -> void: _run.call_deferred()

func _run() -> void:
	create_timer(120).timeout.connect(func(): push_error("Flood presentation timeout"); quit(1))
	root.get_node("WorldClock").paused = true
	root.get_node("SaveManager").set_process(false)
	var test_seed := 474028005
	var args := OS.get_cmdline_user_args()
	if not args.is_empty(): test_seed = int(args[0])
	node_added.connect(func(node: Node):
		if node.name=="Renderer" and node.get_script()!=null: node.set("world_seed",test_seed))
	change_scene_to_file("res://scenes/main/debug_world.tscn")
	await process_frame
	await process_frame
	var generator = root.get_node("WorldGenerator")
	while not generator._maps_ready: await process_frame
	var water = root.get_node("WaterManager")
	water.initialize()
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 52
	current_scene.add_child(camera)
	camera.make_current()
	root.size = Vector2i(1440,1000)
	for node in current_scene.find_children("*","CanvasLayer",true,false): node.visible = false
	var focus := Vector3(530,44,420)
	if test_seed==1630876908:
		focus = Vector3(551,28,462)
		camera.size = 72
	elif test_seed!=474028005:
		for point: Vector3i in generator.river_layout.falls:
			if point.y<54 and point.y>25:
				focus = Vector3(point)
				break
	camera.position = focus+Vector3(28,48,35)
	camera.look_at(focus)
	for i in 900:
		water.step(0.1)
		if i%10==0: await process_frame
	# Let dirty water/terrain tiles catch up before capturing the finished view.
	for _i in 240: await process_frame
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tmp/water_review/fixed_%d.png" % test_seed)
	print("WaterFloodPresentationTest: PASS seed %d focus %s" % [test_seed,focus])
	quit()
