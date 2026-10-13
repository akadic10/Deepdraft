extends SceneTree

const OUT := "res://tmp/development_menu_20261012/"
var failures: Array[String] = []
var dock

func _init() -> void: _run.call_deferred()

func _run() -> void:
	create_timer(120).timeout.connect(func(): push_error("Development menu review timed out"); quit(1))
	root.get_node("SaveManager").configure_storage_for_testing("user://development_menu_review")
	root.get_node("SaveManager").set_process(false)
	root.get_node("WorldClock").set_paused(true)
	root.get_node("TaskManager").set_process(false)
	node_added.connect(func(node: Node):
		if node.name=="Renderer" and node.get_script()!=null: node.set("world_seed",1234)
		if node is UIWindowManager:
			node.ready.connect(func(): node._layout_loaded=false; node._layout.clear()))
	change_scene_to_file("res://scenes/main/debug_world.tscn")
	await process_frame
	while current_scene == null: await process_frame
	dock = current_scene.get_node("DockUI")
	var manager = current_scene.get_node("UIWindowManager")
	while not current_scene.get_node("Renderer")._overview_built: await process_frame
	var data = root.get_node("UIRegistry")
	_expect(data.get_dock_items().back().target=="development","Development is the final dock item")
	_expect(String(data.get_menu("development").get("parent","")).is_empty(),"Development is a top-level menu")
	_expect(not current_scene.get_node("WildlifeManager").has_method("dev_locate_next"),"wildlife cycling handler removed")
	_expect(not current_scene.get_node("SurfaceDetailManager").has_method("dev_locate_next"),"surface cycling handler removed")
	for size in [Vector2i(960,540),Vector2i(1280,720),Vector2i(2560,1440)]:
		root.size = size
		await _frames(8)
		_click(dock._button_by_target.development.get_global_rect().get_center())
		await _frames(8)
		_expect(dock._active_panel_target=="development" and dock._panel_container.visible,"Development dock button opens its own panel")
		_expect(not dock._panel_back.visible and dock._button_by_target.development.button_pressed and not dock._button_by_target.system.button_pressed,"top-level back/active state")
		_expect(Rect2(Vector2.ZERO,Vector2(size)).encloses(dock._dock_panel.get_global_rect()),"dock fits %s" % size)
		_expect(dock._panel_container.get_global_rect().end.y<=dock._dock_panel.position.y-8,"panel stays above dock")
		_expect(dock._panel_body.get_child_count()==6,"six development actions remain")
		for button in dock._panel_body.get_children():
			_expect(not button.text.begins_with("DEV: Next"),"no cycling command remains")
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OUT+"development_%d.png" % size.x)
		_click(dock._button_by_target.system.get_global_rect().get_center())
		await _frames(6)
		_expect(dock._active_panel_target=="system","Menu opens independently")
		for button in dock._panel_body.get_children(): _expect(button.text!="Development","Menu has no nested Development entry")
		_click(dock._panel_body.get_child(0).get_global_rect().get_center())
		await _frames(6)
		_expect(dock._active_panel_target=="save_load" and dock._panel_back.visible,"Save / Load keeps its Menu parent")
		_click(dock._panel_back.get_global_rect().get_center())
		await _frames(5)
		_expect(dock._active_panel_target=="system","Save / Load back returns to Menu")
		dock._close_action_panel()
	# Retained inspector entries dispatch to their real scene owners.
	for pair in [["DEV: Dwarf tools","dwarves_dev"],["DEV: Water","water_dev"],["DEV: Cave explorer","caves_dev"]]:
		_click(dock._button_by_target.development.get_global_rect().get_center())
		await _frames(5)
		for button in dock._panel_body.get_children():
			if button.text==pair[0]: _click(button.get_global_rect().get_center()); break
		await _frames(5)
		_expect(manager.is_open(pair[1]),pair[0]+" opens its real window")
		manager.close(pair[1])
	_click(dock._button_by_target.development.get_global_rect().get_center())
	await _frames(5)
	for button in dock._panel_body.get_children():
		if button.text=="DEV: Arrival status": _click(button.get_global_rect().get_center()); break
	_expect(dock._persistence_toast.visible,"arrival status remains usable")
	for failure in failures: push_error(failure)
	print("DEVELOPMENT_MENU_OK" if failures.is_empty() else "DEVELOPMENT_MENU_FAIL")
	quit(0 if failures.is_empty() else 1)

func _frames(count: int) -> void:
	for i in range(count): await process_frame

func _click(point: Vector2) -> void:
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.position=point; event.button_index=MOUSE_BUTTON_LEFT; event.pressed=pressed
		root.push_input(event,true)

func _expect(ok: bool,message: String) -> void:
	if not ok: failures.append(message)
