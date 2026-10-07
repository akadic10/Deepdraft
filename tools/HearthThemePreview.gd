extends "res://scripts/tests/DwarfInspectorTest.gd"

## Native review of real UI controls, layered on the inspector integration fixture.
## Run with -- --capture. Only screenshots are written; player layout is untouched.
## The fixture positions windows for review, without changing game defaults.
func _capture_inspector() -> void:
	await super._capture_inspector()
	root.size = Vector2i(1280, 720)
	explorer._dwarf_panel._show_tab(0)
	explorer._window.position = Vector2(876, 32)
	var dock = load("res://scripts/ui/DockUI.gd").new()
	dock.name = "Dock"
	dock.window_manager_path = NodePath("../Windows")
	scene.add_child(dock)
	dock.register_furniture_controller(furniture)
	manager.open("clock")
	var clock_window = manager.get_ui_window("clock")
	clock_window.position = Vector2(24, 32)
	dock._update_clock_labels()
	await _settle()
	_click(clock_window._close_button.get_global_rect().get_center())
	_expect(not manager.is_open("clock") and not dock._clock_button.button_pressed,
		"shared Close updates the dock indicator")
	_click(dock._clock_button.get_global_rect().get_center())
	_expect(manager.is_open("clock") and dock._clock_button.button_pressed,
		"dock reopens the styled Clock window")
	await _save_capture("hearth_windows_1280.png")
	explorer.clear_selection()
	manager.close("clock")
	furniture._process(0)
	drops.spawn_drop("base:resources:furniture:wooden_table", 2, Vector3i(34,21,34))
	var catalog = dock._place_catalog
	catalog._all_toggle.button_pressed = true

	for viewport_size in [Vector2i(1280, 720), Vector2i(2560, 1440)]:
		root.size = viewport_size
		dock._active_panel_target = ""
		manager.close("place")
		dock._dispatch("open_panel", "place")
		await _settle()
		for button: Button in dock._button_by_target.values():
			_expect(Rect2(Vector2.ZERO, Vector2(viewport_size)).encloses(button.get_global_rect()),
				"Dock command fits %s: %s" % [viewport_size, button.name])
		var panel_rect: Rect2 = dock._place_window.get_global_rect()
		_expect(Rect2(Vector2.ZERO, Vector2(viewport_size)).encloses(panel_rect),
			"Place catalog fits %s" % viewport_size)
		_expect(catalog._tiles.size() == furniture.get_defs().size(), "Place retains every furniture entry")
		_expect(panel_rect.encloses(catalog._place.get_global_rect()), "Place action stays reachable")
		await _save_capture("hearth_place_%d.png" % viewport_size.x)
	# Exercise the actual menu signal after re-theming its controls.
	catalog._select("base:furniture:wooden_table")
	_click(catalog._place.get_global_rect().get_center())
	_expect(furniture._active_key == "base:furniture:wooden_table" and furniture._active,
		"Place click starts existing furniture placement")
	furniture.deactivate()
	root.size = Vector2i(1280, 720)
	dock._dispatch("open_panel", "chop")
	await _settle()
	var forestry := _find_button(dock._panel_body, "Forestry")
	_expect(forestry != null and forestry.disabled, "unavailable forestry action stays disabled")
	await _save_capture("hearth_chop_1280.png")
	dock._panel_container.hide()
	dock._active_panel_target = ""
	dock._refresh_active_buttons()

	# The independent legacy windows use their real controllers and data too.
	var storage = load("res://scripts/systems/StockpileDesignationController.gd").new()
	storage.dock_ui_path = NodePath("../Dock")
	storage.window_manager_path = NodePath("../Windows")
	scene.add_child(storage)
	storage.set_process(false)
	storage._zones[zone.zone_id] = zone
	storage._open_zone_window(zone.zone_id)
	storage._window_panel.position = Vector2(24, 32)
	var mining = load("res://scripts/systems/MiningDesignationController.gd").new()
	mining.dock_ui_path = NodePath("../Dock")
	mining.window_manager_path = NodePath("../Windows")
	scene.add_child(mining)
	mining.set_process(false)
	var mine_blocks: Array[Vector3i] = [Vector3i(52,20,52), Vector3i(53,20,52)]
	var mine_id: int = mining._create_zone(mine_blocks, 998)
	mining._open_zone_window(mine_id)
	mining._zone_window.position = Vector2(24, 254)
	mining._hint_window.show()
	var piece = furniture._installed.values()[0]
	explorer.select_object(furniture, "installed:%d" % piece.installed_id)
	explorer._window.position = Vector2(880, 32)
	await _save_capture("hearth_context_1280.png")
	var saved_zoom: float = rig._target_zoom
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.position = storage._window_panel.get_global_rect().get_center()
	wheel.pressed = true
	root.push_input(wheel, true)
	wheel = wheel.duplicate()
	wheel.pressed = false
	root.push_input(wheel, true)
	_expect(rig._target_zoom == saved_zoom, "storage panel consumes wheel input")
	_click(_find_button(storage._window_panel, "×").get_global_rect().get_center())
	_expect(not storage._window_panel.visible, "storage Close remains functional")
	_click(_find_button(mining._zone_window, "×").get_global_rect().get_center())
	_expect(not mining._zone_window.visible, "legacy mining Close remains functional")
	print("HEARTH_THEME_OK: native menus at 1280/2560, Place activation, disabled actions, close/dock state, wheel isolation")


func _find_button(node: Node, text_part: String) -> Button:
	if node is Button and text_part in node.text:
		return node
	for child: Node in node.get_children():
		var found := _find_button(child, text_part)
		if found != null: return found
	return null


func _click(position: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = position
	root.push_input(motion, true)
	super._click(position)


func _settle() -> void:
	for i in range(8): await process_frame


func _save_capture(filename: String) -> void:
	await _settle()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tmp/hearth_theme_review/" + filename)
