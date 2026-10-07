extends "res://scripts/tests/HaulingAnimationTest.gd"

## Real GUI drags, zone actions, z-order and layout-file reload. Run with APPDATA
## pointing inside tmp/zone_window_review so player preferences are never written.
var mining
var storage

class InputProbe extends Node:
	var clicks := 0
	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			clicks += 1


func _run() -> void:
	if not "/zone_window_review/" in OS.get_user_data_dir().replace("\\", "/"):
		push_error("ZoneWindowTest requires isolated APPDATA under tmp/zone_window_review.")
		quit(1)
		return
	create_timer(30).timeout.connect(func(): push_error("Zone window test timed out"); quit(1))
	await _setup_fixture()
	root.size = Vector2i(1280, 720)
	_build_windows(true)
	var probe := InputProbe.new()
	scene.add_child(probe)
	var cells: Array[Vector3i] = [Vector3i(48,20,45), Vector3i(49,20,45)]
	storage._create_zone(cells, 501)
	var other_cells: Array[Vector3i] = [Vector3i(50,20,45)]
	storage._create_zone(other_cells, 502)
	var mine_cells: Array[Vector3i] = [Vector3i(48,20,48), Vector3i(49,20,48)]
	mining._create_zone(mine_cells, 901)
	var other_mine_cells: Array[Vector3i] = [Vector3i(50,20,48)]
	mining._create_zone(other_mine_cells, 902)
	mining._open_zone_window(901)
	storage._open_zone_window(501)
	await _settle()
	var mine_window: UIWindow = mining._zone_window
	var storage_window: UIWindow = storage._window_panel
	_expect(mine_window.get_parent() == manager and storage_window.get_parent() == manager,
		"both context panels use the shared window layer")
	mine_window.position = Vector2(30, 30)
	storage_window.position = Vector2(500, 40)
	await _settle()
	# With a designation tool armed, UI mouse events must still stay in the UI.
	storage._active = true
	storage._hover_valid = true
	storage._hover_cell = Vector3i(54,20,44)
	for window: UIWindow in [mine_window, storage_window]:
		var before := window.position
		_drag_title(window, Vector2(100, 30))
		_expect(window.position.is_equal_approx(before + Vector2(100,30)),
			"title drag moves " + window.window_id)
		_expect(not window._dragging, "release ends dragging")
		_expect(manager.get_child(-1) == window, "drag brings the window to front")
		var recorded: Dictionary = manager._layout[window.window_id]
		_expect(Vector2(recorded.x, recorded.y) == window.position, "drag position is recorded")
	_expect(probe.clicks == 0 and not storage._dragging and storage._zones.size() == 2,
		"window dragging cannot start a world designation")
	storage._active = false

	# Live mining information must neither steal focus nor move either window.
	storage._open_zone_window(502)
	mining._zone_body.text = "stale"
	mining._process(.6)
	_expect("Blocks left: 2 / 2" in mining._zone_body.text, "mining statistics still refresh")
	_expect(manager.get_child(-1) == storage_window, "mining refresh leaves storage in front")
	_expect("0 / 1 cells used" in storage._window_info_label.text, "selection swaps storage content")
	_expect(storage_window.position == Vector2(600,70), "switching zones keeps placement")
	_click(mine_window._close_button.get_global_rect().get_center())
	_expect(not mine_window.visible and mining._selected_zone_id == -1,
		"Close clears mining selection")
	mining._open_zone_window(902)
	_expect(mine_window.position == Vector2(130,60), "reopening mining retains its position")
	_expect("Blocks left: 1 / 1" in mining._zone_body.text, "selection swaps mining content")
	_click(storage_window._close_button.get_global_rect().get_center())
	_expect(not storage_window.visible and storage._window_zone_id == -1,
		"Close clears storage selection")
	storage._open_zone_window(502)
	_expect(storage_window.position == Vector2(600,70), "reopening storage retains its position")

	_drag_title(mine_window, Vector2(-1600, -1600))
	_expect(mine_window.position == Vector2(4,4), "drag clamps the title bar to the viewport")
	_drag_title(mine_window, Vector2(156,106))
	await _settle()
	# Body drags must not turn an information row into a title bar.
	var before_body := storage_window.position
	_drag_from(storage._window_info_label.get_global_rect().get_center(), Vector2(20,20))
	_expect(storage_window.position == before_body, "dragging the body does not move the window")
	_expect(probe.clicks == 0, "close, title and content clicks never reach the world")

	# Both Remove actions still operate on the selected zone and close the panel.
	_click(_button_named(storage_window, "Remove zone").get_global_rect().get_center())
	_expect(not storage._zones.has(502) and storage._zones.has(501) and not storage_window.visible,
		"storage Remove affects only the selected zone and hides its window")
	_click(_button_named(mine_window, "Remove").get_global_rect().get_center())
	_expect(not mining._zones.has(902) and mining._zones.has(901) and not mine_window.visible,
		"mining Remove affects only the selected zone and hides its window")
	mining._open_zone_window(901)
	storage._open_zone_window(501)
	await _settle()
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tmp/zone_window_review/movable_zones.png")
	var mining_position := mine_window.position
	var storage_position := storage_window.position
	_expect(FileAccess.file_exists(manager.LAYOUT_PATH), "the manager writes the isolated layout file")
	# Recreate the presentation as on scene reload, reading the real settings file.
	mining.free()
	storage.free()
	manager.free()
	_build_windows(false)
	await _settle()
	_expect(mining._zone_window.position == mining_position and storage._window_panel.position == storage_position,
		"both positions survive manager and controller recreation")
	_expect(not mining._zone_window.visible and not storage._window_panel.visible,
		"context windows never reopen without a selected zone on startup")
	if failures.is_empty():
		print("ZONE_WINDOWS_OK: native drags, focus, world-input isolation, clamp, selection, close/remove, disk layout reload")
	else:
		for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)


func _build_windows(clear_layout: bool) -> void:
	manager = load("res://scripts/ui/UIWindowManager.gd").new()
	manager.name = "Windows"
	scene.add_child(manager)
	if clear_layout: manager._layout.clear()
	storage = load("res://scripts/systems/StockpileDesignationController.gd").new()
	storage.window_manager_path = NodePath("../Windows")
	scene.add_child(storage)
	storage.set_process(false)
	mining = load("res://scripts/systems/MiningDesignationController.gd").new()
	mining.window_manager_path = NodePath("../Windows")
	scene.add_child(mining)
	mining.set_process(false)


func _drag_title(window: UIWindow, delta: Vector2) -> void:
	_drag_from(window._title_bar.get_global_rect().position + Vector2(65,16), delta)


func _drag_from(start: Vector2, delta: Vector2) -> void:
	_move(start)
	_mouse_button(start, true)
	_move(start + delta, delta, MOUSE_BUTTON_MASK_LEFT)
	_mouse_button(start + delta, false)


func _click(position: Vector2) -> void:
	_move(position)
	super._click(position)


func _move(position: Vector2, delta := Vector2.ZERO, buttons := 0) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position
	event.relative = delta
	event.button_mask = buttons
	root.push_input(event, true)


func _mouse_button(position: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	root.push_input(event, true)


func _button_named(node: Node, title: String) -> Button:
	if node is Button and node.text == title: return node
	for child: Node in node.get_children():
		var found := _button_named(child, title)
		if found != null: return found
	return null


func _settle() -> void:
	for i in range(4): await process_frame
