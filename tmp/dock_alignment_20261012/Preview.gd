extends SceneTree

func _init() -> void: _run.call_deferred()

func _run() -> void:
	root.get_node("SaveManager").set_process(false)
	root.get_node("WorldClock").set_paused(true)
	root.get_node("TaskManager").set_process(false)
	var scene := Node.new()
	root.add_child(scene)
	current_scene = scene
	var windows = load("res://scripts/ui/UIWindowManager.gd").new()
	windows.name = "Windows"
	scene.add_child(windows)
	var dock = load("res://scripts/ui/DockUI.gd").new()
	dock.window_manager_path = NodePath("../Windows")
	scene.add_child(dock)
	for width in [1280, 960]:
		root.size = Vector2i(width, 240)
		for i in 8: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tmp/dock_alignment_20261012/dock_%d.png" % width)
	print("DOCK_PREVIEW_OK")
	quit()
