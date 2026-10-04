extends SceneTree

class LocatorOverlay extends Control:
	var camera: Camera3D
	var points: Array[Vector3] = []
	func _draw() -> void:
		var font := ThemeDB.fallback_font
		draw_style_box(_box(),Rect2(24,24,870,100))
		draw_string(font,Vector2(48,64),"New mature apple trees - naturally spawned",HORIZONTAL_ALIGNMENT_LEFT,-1,30,Color.WHITE)
		draw_string(font,Vector2(48,100),"Recreated seed 1388941899  |  Summer  |  Original forest placement",HORIZONTAL_ALIGNMENT_LEFT,-1,21,Color("ccd4dc"))
		for i in range(points.size()):
			var point := camera.unproject_position(points[i])
			var label_x := 245.0 if i == 0 else 1010.0
			var label_y := 800.0
			var center := Vector2(label_x+155,label_y)
			draw_arc(point,82,0,TAU,96,Color("ffe083"),4,true)
			draw_line(point+Vector2(0,82),center,Color("ffe083"),3,true)
			draw_style_box(_box(),Rect2(label_x,label_y,310,72))
			draw_string(font,Vector2(label_x+18,label_y+30),"NEW APPLE / summer",HORIZONTAL_ALIGNMENT_LEFT,-1,23,Color("ffe083"))
			draw_string(font,Vector2(label_x+18,label_y+57),"X %d, Z %d" % [points[i].x-1.5,points[i].z-1.5],HORIZONTAL_ALIGNMENT_LEFT,-1,20,Color.WHITE)
	func _box() -> StyleBoxFlat:
		var box := StyleBoxFlat.new()
		box.bg_color = Color(.035,.045,.05,.94)
		box.corner_radius_top_left = 8
		box.corner_radius_top_right = 8
		box.corner_radius_bottom_left = 8
		box.corner_radius_bottom_right = 8
		return box


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	create_timer(90.0).timeout.connect(func(): push_error("Apple locator timed out"); quit(1))
	root.get_node("SaveManager").set_process(false)
	root.get_node("WorldClock").set_paused(true)
	var scene: Node3D = load("res://scenes/main/debug_world.tscn").instantiate()
	scene.get_node("Renderer").world_seed = 1388941899
	root.add_child(scene)
	current_scene = scene
	var world := root.get_node("WorldGenerator")
	var flora: Node3D = scene.get_node("SurfaceFloraSpawner")
	while not bool(world.get_streaming_stats().get("maps_ready",false)) or world.is_generating() or not flora._ready_to_spawn or not flora._pending.is_empty():
		await process_frame
	assert(world.world_seed == 1388941899)
	root.get_node("SkyController").rebind_to_current_scene()
	for node in scene.find_children("*","CanvasLayer",true,false):
		node.hide()
	scene.get_node("CameraRig").set_process(false)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 52
	camera.far = 500
	scene.add_child(camera)
	var target := Vector3(539,33,537)
	camera.position = target+Vector3(0,90,55)
	camera.look_at(target)
	camera.current = true
	var layer := CanvasLayer.new()
	scene.add_child(layer)
	var overlay := LocatorOverlay.new()
	overlay.camera = camera
	for name in ["apple_mature_531_534","apple_mature_544_537"]:
		var tree: Node3D = flora.get_node(name)
		assert(tree.get_child(0).scene_file_path == "res://assets/models/flora/trees/apple/apple_mature.glb")
		overlay.points.append(tree.global_position+Vector3(0,10,0))
	layer.add_child(overlay)
	# Let the terrain and grass-band meshes settle before capturing.
	for i in range(360):
		await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png("res://tmp/apple_redesign_preview/renders/natural_apples_located.png") == OK)
	print("APPLE_WORLD_LOCATOR_OK: two naturally spawned approved models; no placement edits")
	quit(0)
