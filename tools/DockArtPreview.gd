extends "res://scripts/tests/DwarfInspectorTest.gd"

## Native art/layout review using real game controls and the existing actor
## fixture. No saves or player layout preferences are written.
func _capture_inspector() -> void:
	await super._capture_inspector()
	explorer.clear_selection()
	var dock = load("res://scripts/ui/DockUI.gd").new()
	dock.name = "Dock"
	dock.window_manager_path = NodePath("../Windows")
	scene.add_child(dock)
	dock.register_furniture_controller(furniture)
	var rooms = load("res://scripts/systems/RoomOverlayController.gd").new()
	rooms.dock_ui_path = NodePath("../Dock")
	rooms.window_manager_path = NodePath("../Windows")
	scene.add_child(rooms)
	_expect(dock._button_by_target.keys() == ["orders", "zones", "rooms", "construction", "place", "craft", "colony", "stocks", "system", "development"],
		"approved ten-command order including Construction and separate Development")
	for button: Button in dock._button_by_target.values():
		_expect(button.text.is_empty() and button.icon is AtlasTexture,
			"caption-free command uses approved illustrated atlas")
		_expect(not button.caption.is_empty() and not button.description.is_empty(), "every command has hover information")
	for viewport_size in [Vector2i(1280,720), Vector2i(960,540), Vector2i(2560,1440)]:
		root.size = viewport_size
		await _settle()
		var bounds := Rect2(Vector2.ZERO, Vector2(viewport_size))
		_expect(bounds.encloses(dock._dock_panel.get_global_rect()), "dock fits " + str(viewport_size))
		for utility: Rect2 in dock._time_slice_hud.occupied_rects():
			_expect(not utility.intersects(dock._dock_panel.get_global_rect()), "dock clears the fixed time/Slice controls")
		for button: Button in dock._button_by_target.values():
			_expect(is_equal_approx(button.size.x, button.size.y) and button.size.x >= 56, "square readable buttons")
		await _save_capture("dock_%d.png" % viewport_size.x)
		for target in ["orders", "zones", "rooms", "construction", "place", "craft", "colony", "stocks", "system", "development"]:
			var button: Button = dock._button_by_target[target]
			_click(button.get_global_rect().get_center())
			await _settle()
			_expect(button.button_pressed, "click opens/highlights " + target)
			_expect(dock._panel_connector.visible == (target in ["construction", "craft", "colony", "system", "development"]), "illustrated action menus show their dock connector")
			var window: Control = dock._panel_container
			if target == "place": window = dock._place_window
			elif target == "stocks": window = dock._inventory_window
			elif target in ["orders", "zones"]: window = dock._orders._shelf
			elif target == "rooms": window = null
			if window != null:
				_expect(bounds.encloses(window.get_global_rect()), "menu fits: " + target)
				_expect(window.get_global_rect().end.y <= dock._dock_panel.position.y - 8, "menu clears dock: " + target)
			if target in ["construction", "craft", "colony", "system", "development", "place", "stocks"]:
				await _save_capture("%s_%d.png" % [target, viewport_size.x])
			_click(button.get_global_rect().get_center())
			await _settle()
			_expect(not button.button_pressed, "second click closes " + target)
			_expect(not dock._panel_connector.visible, "closing any menu clears its connector")
		# Move the pointer as in normal play; the tooltip must appear on its own.
		var colony = dock._button_by_target.colony
		var motion := InputEventMouseMotion.new()
		motion.position = colony.get_global_rect().get_center()
		root.push_input(motion, true)
		await create_timer(.45).timeout
		await _settle()
		_expect(colony._info != null and colony._info.visible, "hover reveals description")
		if colony._info != null:
			_expect(bounds.encloses(colony._info.get_global_rect()), "hover stays inside viewport")
		await _save_capture("hover_%d.png" % viewport_size.x)
		motion = InputEventMouseMotion.new()
		motion.position = Vector2(12, 120)
		root.push_input(motion, true)
		await _settle()
		_expect(not colony._info.visible, "leaving icon hides hover description")
		colony.grab_focus()
		await create_timer(.45).timeout
		_expect(colony._info.visible, "keyboard focus also reveals command")
		colony.release_focus()
		await _settle()
	print("DOCK_ART_OK: all ten real commands, hover/focus, active states, responsive 960/1280/2560 layouts")


func _settle() -> void:
	for i in range(8): await process_frame


func _click(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion, true)
	super._click(point)


func _save_capture(filename: String) -> void:
	await _settle()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tmp/dock_art_20261012/" + filename)
