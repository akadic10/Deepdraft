extends SceneTree

## Native game-scene review; isolated state, real terrain/flora/materials.
var _output := "res://tmp/boulder_review/"


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var scree := "--scree" in OS.get_cmdline_user_args()
	_output = "res://tmp/scree_review/" if scree else "res://tmp/boulder_review/"
	var profile := OS.get_environment("APPDATA").replace("\\", "/")
	if not profile.contains("/tmp/boulder_review/") and not profile.contains("/tmp/scree_review/"):
		printerr("Use isolated APPDATA below tmp/boulder_review or tmp/scree_review.")
		quit(2)
		return
	root.get_node("SaveManager").configure_storage_for_testing("user://boulder_preview")
	var scene: Node = load("res://scenes/main/debug_world.tscn").instantiate()
	scene.get_node("Renderer").world_seed = 1234
	var publish := func(node: Node):
		if node == scene: current_scene = scene
	node_added.connect(publish)
	root.add_child(scene)
	node_added.disconnect(publish)
	var generator := root.get_node("WorldGenerator")
	var renderer := scene.get_node("Renderer")
	var flora := scene.get_node("SurfaceFloraSpawner")
	var details := scene.get_node("SurfaceDetailManager")
	var deadline := Time.get_ticks_msec() + 120000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if generator._maps_ready and renderer._overview_built and details._initialized and flora._pending.is_empty() and details._visual_queue.is_empty(): break
	if not details._initialized or not renderer._overview_built:
		printerr("Boulder preview timed out")
		quit(1)
		return
	root.get_node("WorldClock").set_paused(true)
	# Exercise the public development-menu route and normal shared inspector.
	scene.get_node("DockUI")._dispatch_panel_action("surface_details", "DEV: Next scree" if scree else "DEV: Next boulder")
	var explorer := scene.get_node("ObjectExplorerController")
	if explorer._provider != details:
		printerr("Development locator failed")
		quit(1)
		return
	var id := String(explorer._object_id)
	var boulder: Node3D = details._records[id].node
	var target := boulder.position
	# Terrain at a far-away DEV target must finish streaming before capture.
	for i in range(120): await process_frame
	# Canopies/cliffs legitimately occlude some targets at this camera angle.
	# Cycle the real locator to find an exposed example for click/capture review.
	if scree:
		for attempt in range(16):
			if _pick_point(details, explorer, id).x >= 0: break
			scene.get_node("DockUI")._dispatch_panel_action("surface_details", "DEV: Next scree")
			id = String(explorer._object_id)
			target = details._records[id].node.position
			for i in range(100): await process_frame
	if "--orders" in OS.get_cmdline_user_args():
		var dock := scene.get_node("DockUI")
		var controller := scene.get_node("TreeFellingController")
		dock._dispatch("open_panel", "orders")
		dock._orders._buttons.clear_stones.pressed.emit()
		var point := _pick_point(details, explorer, id)
		if controller._details != details or not controller.designate_at_screen(point):
			await _shot("unpickable")
			print("PICK_FAILURE ", id, " point=", point, " bounds=", details.get_explorer_bounds(id))
			printerr("Main-scene boulder tool wiring or picking failed")
			quit(1)
			return
		for i in range(8): await process_frame
		await _shot("world_orders")
		dock._orders._buttons.cancel_orders.pressed.emit()
		controller._begin_drag(point)
		controller._finish_drag(point)
		if details.get_clearing_order_token(id) != null:
			printerr("Main-scene cancel failed to retire boulder work")
			quit(1)
			return
		print("BOULDER_ORDERS_LIVE_PASS ", id)
		dock._request_order_tool("")
		dock._orders.set_open(false)
	await _shot("world_close")
	scene.get_node("CameraRig").focus_world_position(target, 100.0)
	for i in range(100): await process_frame
	await _shot("world_play_zoom")
	print("SURFACE_DETAIL_LIVE_PREVIEW_PASS ", id, " ", details.diagnostics)
	generator.prepare_for_world_reload()
	quit(0)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_output + name + ".png")


func _pick_point(details: Node, explorer: Node, id: String) -> Vector2:
	var bounds: AABB = details.get_explorer_bounds(id)
	for x in range(1,10):
		for z in range(1,10):
			var point := root.get_camera_3d().unproject_position(bounds.position + bounds.size * Vector3(x/10.0,.5,z/10.0))
			var hit: Dictionary = explorer.pick_at_screen(point)
			if hit.get("provider") == details and hit.get("id", "") == id: return point
	return Vector2(-1,-1)
