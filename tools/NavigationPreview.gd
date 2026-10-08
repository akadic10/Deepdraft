extends "res://tools/HearthThemePreview.gd"

## Exercises the real grouped navigation after the shared UI fixture. Run natively
## with -- --capture. Layout writes are disabled by the inherited fixture; save/load
## buttons are observed as signals here, with the persistence backend disconnected.
func _capture_inspector() -> void:
	await super._capture_inspector()
	var dock = scene.get_node("Dock")
	dock._mining_controller._hint_window.hide()
	_expect(dock._button_by_target.keys() == ["orders", "zones", "rooms", "place", "craft", "colony", "stocks", "system"],
		"Rooms and Craft have dedicated named dock entries")
	var rooms = load("res://scripts/systems/RoomOverlayController.gd").new()
	rooms.dock_ui_path = NodePath("../Dock")
	rooms.window_manager_path = NodePath("../Windows")
	scene.add_child(rooms)
	for button: Button in dock._button_by_target.values():
		_expect(not button.text.is_empty() and button.icon != null, "groups have labels and copper icons")
	var requests: Array[String] = []
	dock.tool_requested.connect(func(id: String): requests.append(id))
	_click(dock._button_by_target.orders.get_global_rect().get_center())
	await _settle()
	_expect(dock._orders.is_open() and dock._button_by_target.orders.button_pressed,
		"Orders opens its shelf and highlights its group")
	_expect(not dock._orders._buttons.has("farm") and not dock._orders._buttons.storage_zone.visible, "Orders contains current work tools")
	_click(dock._orders._buttons.mine_precision.get_global_rect().get_center())
	_expect(requests == ["mine_precision"] and dock._mining_controller.is_active(),
		"Mine starts the real mining tool exactly once")
	_expect(dock._orders.is_open(), "choosing a tool keeps its shelf open")
	_click(dock._button_by_target.stocks.get_global_rect().get_center())
	await _settle()
	_expect(manager.is_open("inventory") and not dock._mining_controller.is_active(), "Inventory opens directly and exits mining")
	_click(dock._button_by_target.zones.get_global_rect().get_center())
	await _settle()
	_click(dock._orders._buttons.storage_zone.get_global_rect().get_center())
	_expect(requests == ["mine_precision", "", "storage_zone"] and dock._stockpile_controller.is_active()
		and not dock._mining_controller.is_active(), "new orders deactivate the previous designation tool")
	dock._stockpile_controller.deactivate()
	dock._orders.set_open(false)
	_click(dock._button_by_target.orders.get_global_rect().get_center())
	await _settle()
	_click(dock._orders._buttons.chop.get_global_rect().get_center())
	_expect(requests[-1] == "chop", "Chop trees routes the existing tool signal")
	dock._request_order_tool("mine_precision")
	_click(dock._button_by_target.rooms.get_global_rect().get_center())
	await _settle()
	_expect(rooms.is_active() and dock._button_by_target.rooms.button_pressed,
		"Rooms starts inspection directly and stays highlighted")
	_expect(not dock._mining_controller.is_active() and not dock._orders.is_open(),
		"Rooms closes the tool shelf and ends mining")
	_click(dock._button_by_target.rooms.get_global_rect().get_center())
	_expect(not rooms.is_active() and not dock._button_by_target.rooms.button_pressed,
		"Rooms toggles off on a second click")
	_click(dock._button_by_target.rooms.get_global_rect().get_center())
	var room_escape := InputEventKey.new()
	room_escape.keycode = KEY_ESCAPE
	room_escape.pressed = true
	root.push_input(room_escape, true)
	_expect(not rooms.is_active() and not dock._button_by_target.rooms.button_pressed,
		"Escape exits Rooms and clears the dock highlight")
	_click(dock._button_by_target.rooms.get_global_rect().get_center())

	_click(dock._button_by_target.system.get_global_rect().get_center())
	await _settle()
	_expect(not rooms.is_active() and not dock._button_by_target.rooms.button_pressed,
		"switching to another dock group exits room inspection")
	_click(_find_button(dock._panel_body, "Save / Load").get_global_rect().get_center())
	await _settle()
	_expect(dock._panel_back.visible and dock._button_by_target.system.button_pressed,
		"submenu retains its parent group and offers Back")
	_click(dock._panel_back.get_global_rect().get_center())
	await _settle()
	_expect(dock._active_panel_target == "system", "Back returns to Menu")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	root.push_input(escape, true)
	_expect(not dock._panel_container.visible, "Escape closes an open menu")

	_click(dock._button_by_target.colony.get_global_rect().get_center())
	await _settle()
	_expect(_find_button(dock._panel_body, "Inspect rooms") == null, "Rooms is no longer nested in Colony")
	_click(_find_button(dock._panel_body, "Dwarves").get_global_rect().get_center())
	_expect(manager.is_open("dwarves") and not dock._panel_container.visible,
		"Colony opens the existing Dwarves window")
	manager.close("dwarves")
	var saved := [0,0,0]
	for binding in [["save_game_requested", "request_save"], ["load_game_requested", "request_load"],
		["load_autosave_requested", "request_load_autosave"]]:
		dock.disconnect(binding[0], Callable(root.get_node("SaveManager"), binding[1]))
	dock.save_game_requested.connect(func(): saved[0] += 1)
	dock.load_game_requested.connect(func(): saved[1] += 1)
	dock.load_autosave_requested.connect(func(): saved[2] += 1)
	for label in ["💾 Save Game", "📂 Load Game", "🕒 Load Autosave"]:
		_click(dock._button_by_target.system.get_global_rect().get_center())
		await _settle()
		_click(_find_button(dock._panel_body, "Save / Load").get_global_rect().get_center())
		await _settle()
		_click(_find_button(dock._panel_body, label).get_global_rect().get_center())
	_expect(saved == [1,1,1], "all persistence actions remain accessible and emit once")

	_click(dock._speed_buttons[0].get_global_rect().get_center())
	_expect(clock_node.paused, "Pause controls the authoritative clock")
	_click(dock._speed_buttons[2].get_global_rect().get_center())
	_expect(not clock_node.paused and clock_node.speed == 2, "2x resumes at double speed")
	_click(dock._speed_buttons[1].get_global_rect().get_center())
	_expect(clock_node.speed == 1 and dock._speed_buttons[1].button_pressed, "1x updates the clock and selection")

	var piece = furniture._installed.values()[0]
	explorer._inspector_positioned = false # fresh layout preference
	explorer.select_object(furniture, "installed:%d" % piece.installed_id)
	_expect(is_equal_approx(explorer._window.position.x, 1280 - explorer._window.size.x - 24),
		"furniture starts in the same right-hand inspector column as dwarves")
	explorer._window.position = Vector2(800,80)
	explorer._window.drag_ended.emit(explorer._window)
	explorer.select_object(director, worker)
	_expect(explorer._window.position == Vector2(800,80), "subject changes preserve the player's placement")
	for viewport_size in [Vector2i(1280,720), Vector2i(960,540), Vector2i(2560,1440)]:
		root.size = viewport_size
		await _settle()
		_expect(is_equal_approx(dock._dock_panel.get_global_rect().get_center().x, viewport_size.x * 0.5),
			"bottom navigation stays centered after resizing")
		_expect(Rect2(Vector2.ZERO, Vector2(viewport_size)).encloses(dock._dock_panel.get_global_rect()),
			"all eight dock entries fit at " + str(viewport_size))
		explorer.clear_selection()
		for target in ["colony", "system"]:
			dock._close_action_panel()
			_click(dock._button_by_target[target].get_global_rect().get_center())
			await _settle()
			_expect(is_equal_approx(dock._panel_container.get_global_rect().get_center().x, viewport_size.x * 0.5),
				"submenus center over the dock without an inspector at " + str(viewport_size))
			if target == "orders":
				await _save_capture("centered_%s_%d.png" % [target, viewport_size.x])
		explorer.select_object(director, worker)
		explorer._window.position = Vector2(viewport_size.x - explorer._window.size.x - 24,32)
		for target in ["place", "colony", "system"]:
			dock._close_action_panel()
			_click(dock._button_by_target[target].get_global_rect().get_center())
			await _settle()
			var bounds := Rect2(Vector2.ZERO, Vector2(viewport_size))
			var menu_rect: Rect2 = dock._place_window.get_global_rect() if target == "place" else dock._panel_container.get_global_rect()
			_expect(bounds.encloses(menu_rect), "menu fits " + str(viewport_size))
			if target != "place": _expect(dock._panel_scroll.scroll_vertical == 0, "new menus open at the top")
			_expect(menu_rect.end.y <= dock._dock_panel.position.y - dock.PANEL_DOCK_GAP,
				"menu leaves a gap above the dock at " + str(viewport_size))
			_expect(not menu_rect.intersects(explorer._window.get_global_rect()),
				"menu leaves inspector accessible at " + str(viewport_size))
			_expect(not dock._dock_panel.get_global_rect().intersects(explorer._window.get_global_rect()),
				"inspector leaves every navigation group accessible")
			if target in ["orders", "place"]:
				await _save_capture("navigation_%s_%d.png" % [target, viewport_size.x])
			if target == "place" and viewport_size.x == 960:
				var scroll = dock._place_catalog._scroll
				explorer._perform_dwarf_action("follow")
				var zoom: float = rig._target_zoom
				var wheel := InputEventMouseButton.new()
				wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
				wheel.position = scroll.get_global_rect().get_center()
				wheel.pressed = true
				root.push_input(wheel, true)
				await _settle()
				_expect(scroll.scroll_vertical > 0 and rig._target_zoom == zoom and rig.is_following(worker),
					"compact menu scrolls without zooming or stopping Follow")
				scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
				await _settle()
				_expect(scroll.get_global_rect().has_point(
					dock._place_catalog._tiles["base:furniture:aging_rack"].button.get_global_rect().get_center()),
					"last furniture design is reachable by scrolling")
				explorer._perform_dwarf_action("stop_follow")
		explorer.clear_selection()
		await _settle()
		_expect(is_equal_approx(dock._panel_container.get_global_rect().get_center().x, viewport_size.x * 0.5),
			"closing the inspector recenters the open submenu")
	print("NAVIGATION_OK: grouped commands, tool exclusivity, submenu Back/Escape, all save signals, live clock, inspector placement, 960/1280/2560 layouts")


func _save_capture(filename: String) -> void:
	await _settle()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tmp/navigation_review/" + filename)
