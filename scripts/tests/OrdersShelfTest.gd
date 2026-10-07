extends "res://scripts/tests/FurniturePlaceTest.gd"

var mining
var storage
var chop
var rig
var orders


func _run() -> void:
	create_timer(90).timeout.connect(func(): push_error("Orders test timed out"); quit(1))
	root.get_node("SaveManager").set_process(false)
	root.get_node("WorldClock").set_paused(true)
	root.get_node("TaskManager").set_process(false)
	root.get_node("RoomManager").set_process(false)
	world = root.get_node("WorldData")
	blocks = root.get_node("BlockRegistry")
	_build_floor()
	var generator = root.get_node("WorldGenerator")
	generator._maps_ready = true
	generator.world_seed = 1234
	generator.heightmap.resize(1024 * 1024)
	generator.heightmap.fill(20)
	root.size = Vector2i(1280,720)
	scene = Node3D.new()
	root.add_child(scene)
	current_scene = scene
	manager = load("res://scripts/ui/UIWindowManager.gd").new()
	manager.name = "Windows"
	scene.add_child(manager)
	manager._layout_loaded = false
	manager._layout.clear()
	rig = load("res://scripts/systems/Camera.gd").new()
	rig.name = "Rig"
	scene.add_child(rig)
	rig.set_process(false)
	camera = rig.camera_node
	camera.reparent(scene)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 36
	camera.current = true
	camera.global_position = Vector3(40.1,86,40.1)
	camera.look_at(Vector3(40,22,40), Vector3.FORWARD)
	dock = load("res://scripts/ui/DockUI.gd").new()
	dock.name = "Dock"
	dock.window_manager_path = NodePath("../Windows")
	scene.add_child(dock)
	orders = dock._orders
	items = load("res://scripts/systems/ItemDropManager.gd").new()
	scene.add_child(items)
	mining = load("res://scripts/systems/MiningDesignationController.gd").new()
	mining.name = "Mining"
	mining.camera_path = NodePath("../Rig")
	mining.dock_ui_path = NodePath("../Dock")
	mining.window_manager_path = NodePath("../Windows")
	scene.add_child(mining)
	storage = load("res://scripts/systems/StockpileDesignationController.gd").new()
	storage.dock_ui_path = NodePath("../Dock")
	storage.window_manager_path = NodePath("../Windows")
	scene.add_child(storage)
	flora = load("res://scripts/systems/SurfaceFloraSpawner.gd").new()
	flora.name = "Flora"
	scene.add_child(flora)
	flora.set_process(false)
	explorer = load("res://scripts/ui/ObjectExplorerController.gd").new()
	explorer.name = "Explorer"
	explorer.window_manager_path = NodePath("../Windows")
	scene.add_child(explorer)
	chop = load("res://scripts/systems/TreeFellingController.gd").new()
	chop.dock_ui_path = NodePath("../Dock")
	chop.flora_path = NodePath("../Flora")
	chop.explorer_path = NodePath("../Explorer")
	scene.add_child(chop)
	explorer._tools.assign([mining, storage, chop])
	_build_review_world()
	_spawn_order_tree(Vector2i(43,34))
	_spawn_order_tree(Vector2i(48,39))
	await _settle()
	_click(dock._button_by_target.orders.get_global_rect().get_center())
	await _settle()
	_expect(orders.is_open() and dock._button_by_target.orders.button_pressed, "Orders opens the shelf")
	_expect(orders._buttons.size() == 4 and not orders._buttons.storage_zone.visible, "Orders shows work tools and keeps stockpiles in Zones")
	_click(orders._buttons.mine_precision.get_global_rect().get_center())
	await _settle()
	_expect(mining.is_active() and orders._banner.visible and not mining._hint_window.visible, "mining uses the shared banner")
	_expect(orders.is_open() and orders._buttons.mine_precision.button_pressed, "shelf stays open and marks the active tool")
	_click(orders._buttons.mine_precision.get_global_rect().get_center())
	_expect(mining.is_active(), "reselecting mining does not toggle it off")
	_test_mining_zoom()
	_click(dock._button_by_target.zones.get_global_rect().get_center())
	await _settle()
	_expect(orders.is_open("zones") and not mining.is_active(), "switching to Zones ends the previous drawing mode")
	_expect(orders._buttons.storage_zone.visible and not orders._buttons.chop.visible
		and dock._button_by_target.zones.button_pressed and not dock._button_by_target.orders.button_pressed, "Zones owns the stockpile tile and dock highlight")
	_click(orders._buttons.storage_zone.get_global_rect().get_center())
	_click(dock._button_by_target.zones.get_global_rect().get_center())
	await _settle()
	_expect(not orders.is_open() and storage.is_active() and orders._banner.visible
		and dock._button_by_target.zones.button_pressed, "closing Zones retains its active mode and highlight")
	_expect(orders._banner.get_global_rect().end.y <= dock._dock_panel.position.y - 8, "closed-shelf mode remains above dock")
	_click(_find_button(orders._banner, "Done  ·  Esc").get_global_rect().get_center())
	await _settle()
	_expect(not storage.is_active() and not orders._banner.visible and not dock._button_by_target.zones.button_pressed, "Done ends a tool whose shelf is closed")
	_click(dock._button_by_target.zones.get_global_rect().get_center())
	await _settle()
	_click(orders._buttons.storage_zone.get_global_rect().get_center())
	_key(KEY_ESCAPE)
	_expect(not storage.is_active() and orders.is_open("zones"), "first Escape ends stockpile mode and keeps Zones open")
	_key(KEY_ESCAPE)
	_expect(not orders.is_open() and not dock._button_by_target.zones.button_pressed, "second Escape closes Zones and clears its highlight")
	_click(dock._button_by_target.orders.get_global_rect().get_center())
	await _settle()
	_expect(orders.is_open("orders") and not storage.is_active(), "returning to Orders ends stockpile mode")
	_click(orders._buttons.mine_precision.get_global_rect().get_center())
	var a := camera.unproject_position(Vector3(33.5,21,36.5))
	var b := camera.unproject_position(Vector3(35.5,21,38.5))
	_motion(a)
	_mouse(a,true)
	var drag_anchor: Dictionary = mining._anchor_hit.duplicate()
	var drag_zoom: float = rig._target_zoom
	_wheel(a, MOUSE_BUTTON_WHEEL_UP)
	_expect(rig._target_zoom < drag_zoom and mining._state == mining.ToolState.DRAGGING
		and mining._anchor_hit == drag_anchor, "zoom during mining drag preserves its anchor and gesture")
	_motion(b); _mouse(b,false)
	_expect(mining._zones.size() == 1 and orders._history.size() == 1, "world drag commits one mining order and undo receipt")
	if orders._last_order.is_empty():
		push_error("Mine drag failed: %s -> %s, hover %s, state %s, GUI %s" % [a,b,mining._hover_hit,mining._state,root.gui_get_hovered_control()])
		quit(1)
		return
	var mining_receipt: Dictionary = orders._last_order.receipt
	_expect(mining._zones[mining_receipt.zone_id].blocks.size() == 9, "mine rectangle matches preview")
	orders.refresh()
	await _settle()
	_click(orders._view.get_global_rect().get_center())
	_expect(not mining.is_active() and mining._zone_window.visible, "View order finishes tool and opens real mining inspector")
	manager.close(mining.ZONE_WINDOW_ID)
	_click(orders._buttons.mine_precision.get_global_rect().get_center())
	# UI release cancels an unfinished mining drag, including its input state.
	a = camera.unproject_position(Vector3(31.5,21,36.5))
	_motion(a); mining._update_hover_preview(true); _mouse(a,true)
	var ui: Vector2 = orders._buttons.mine_precision.get_global_rect().get_center()
	_motion(ui); _mouse(ui,false)
	_expect(mining._zones.size() == 1 and mining._state == mining.ToolState.HOVER, "release over shelf discards mining gesture")
	_key(KEY_ESCAPE)
	_expect(not mining.is_active() and orders.is_open(), "first Escape ends mining, keeps shelf")
	var idle_zoom: float = rig._target_zoom
	_wheel(Vector2(160,200), MOUSE_BUTTON_WHEEL_DOWN)
	_expect(rig._target_zoom > idle_zoom, "zoom remains available after mining ends")
	_key(KEY_ESCAPE)
	_expect(not orders.is_open(), "second Escape closes shelf")
	_click(dock._button_by_target.orders.get_global_rect().get_center())
	await _settle()
	_click(orders._buttons.chop.get_global_rect().get_center())
	await _settle()
	var tree_id := Vector2i(43,34)
	var tree_screen := camera.unproject_position(flora.get_explorer_bounds(tree_id).get_center())
	_expect(not orders._banner.get_global_rect().has_point(tree_screen), "fixture tree stays in exposed world above the lower mode banner")
	_click(tree_screen)
	_expect(flora.get_felling_order_token(tree_id) != null, "one click on tree starts real felling work")
	var before: int = orders._history.size()
	chop.designate_at_screen(tree_screen)
	_expect(orders._history.size() == before, "repeat mark does not add undo entries")
	explorer.clear_selection()
	orders.refresh()
	await _settle()
	_click(orders._undo.get_global_rect().get_center())
	_expect(flora.get_felling_order_token(tree_id) == null, "Undo cancels only new chopping marks")
	# Receipt identity guards cancel/re-mark and same-ID reloads.
	chop.designate_at_screen(tree_screen)
	var stale_tree: Dictionary = orders._last_order.receipt
	flora.cancel_felling(tree_id)
	flora.designate_felling(tree_id)
	_expect(not chop.order_is_pending(stale_tree) and chop.undo_order(stale_tree) == 0, "stale tree receipt cannot cancel a new designation")
	flora._tree_changes[tree_id].work_seconds = 1.25
	explorer.clear_selection()
	_click(orders._buttons.cancel_orders.get_global_rect().get_center())
	_expect(chop.is_active() and chop.get_order_tool_id() == "cancel_orders" and not mining.is_active(), "Cancel is an exclusive tool")
	_click(tree_screen)
	_expect(flora.get_felling_order_token(tree_id) == null and is_equal_approx(flora._tree_changes[tree_id].work_seconds, 1.25), "cancel tool removes tree job and preserves work")
	# Mixed screen rectangle: exact pending block centres and visible tree centres.
	flora.designate_felling(tree_id)
	var source = flora.get_felling_order_token(tree_id)
	var task_id: int = source.lease_id
	var rect := Rect2(Vector2(390,180),Vector2(500,150))
	_motion(rect.position); _mouse(rect.position,true); _motion(rect.end)
	chop._process(.1)
	_expect(chop._preview_mining.size() > 0 and chop._preview_trees.has(tree_id), "cancellation previews both block and tree work")
	_mouse(rect.end,false)
	_expect(flora.get_felling_order_token(tree_id) == null, "mixed cancellation releases felling source")
	var task = root.get_node("TaskManager").get_task(task_id)
	_expect(task == null or task.status == Task.Status.CANCELLED, "cancellation retires scheduler lease")
	# A stockpile is outside the cancel brush; only explicit zone undo removes it.
	_click(dock._button_by_target.zones.get_global_rect().get_center())
	await _settle()
	_click(orders._buttons.storage_zone.get_global_rect().get_center())
	var stock_cell := Vector3i(35,20,32)
	a = camera.unproject_position(Vector3(stock_cell)+Vector3(.5,1,.5))
	_motion(a); storage._update_hover(); _click(a)
	_expect(storage._zones.size() == 1 and not chop.is_active(), "direct stockpile tool creates real zone and excludes chop")
	if orders._last_order.is_empty():
		for failure in failures: push_error(failure)
		quit(1)
		return
	var stock_receipt: Dictionary = orders._last_order.receipt
	_click(dock._button_by_target.orders.get_global_rect().get_center())
	await _settle()
	_click(orders._buttons.cancel_orders.get_global_rect().get_center())
	_motion(rect.position); _mouse(rect.position,true); _motion(rect.end); chop._process(.1); _mouse(rect.end,false)
	_expect(storage._zones.size() == 1, "cancel work does not remove stockpiles")
	orders.refresh(); await _settle()
	_click(orders._undo.get_global_rect().get_center())
	_expect(storage._zones.is_empty(), "Undo last stockpile uses its real removal path")
	var same_cells: Array[Vector3i] = [stock_cell]
	storage._create_zone(same_cells, stock_receipt.zone_id)
	_expect(not storage.order_is_pending(stock_receipt), "old receipt cannot remove a reused zone ID")
	# UI drag release also cancels storage gestures.
	_click(dock._button_by_target.zones.get_global_rect().get_center())
	await _settle()
	_click(orders._buttons.storage_zone.get_global_rect().get_center())
	a = camera.unproject_position(Vector3(40.5,21,34.5))
	_motion(a); storage._update_hover(); _mouse(a,true)
	ui = orders._buttons.storage_zone.get_global_rect().get_center()
	_motion(ui); _mouse(ui,false)
	_expect(not storage._dragging and storage._zones.size() == 1, "release over shelf discards storage gesture")
	# Undo never recreates completed terrain, even after work begins.
	mining._preview_blocks.assign([Vector3i(38,20,36),Vector3i(39,20,36)])
	mining._confirm_preview()
	var partial: Dictionary = orders._last_order.receipt
	mining.execute_zone_block_mined(partial.zone_id,Vector3i(38,20,36),-1)
	_expect(mining.undo_order(partial) == 1, "undo removes only the unfinished part of mining")
	_expect(world.get_block(38,20,36) == blocks.AIR_ID and world.get_block(39,20,36) != blocks.AIR_ID,
		"mining undo leaves completed terrain and unmined terrain intact")
	await _check_layouts()
	if failures.is_empty(): print("ORDERS_SHELF_OK: Orders/Zones routing and highlights, lower mode stack, closed-shelf Done, two-step Escape, real input, mining zoom/modifier resize, UI wheel isolation, mine/chop/storage, exclusivity, mixed cancel, source leases/progress, safe undo, UI release, native responsive layouts")
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)


func _check_layouts() -> void:
	for viewport_size in [Vector2i(960,540),Vector2i(1280,720),Vector2i(2560,1440)]:
		root.size = viewport_size
		dock._request_order_tool("mine_precision")
		orders.set_open(true, "orders")
		await _settle()
		var bounds := Rect2(Vector2.ZERO, Vector2(viewport_size))
		for control: Control in [orders._shelf, orders._banner, dock._dock_panel]:
			_expect(bounds.encloses(control.get_global_rect()), "Orders control fits " + str(viewport_size))
		_expect(orders._shelf.get_global_rect().end.y <= dock._dock_panel.position.y - 8, "shelf leaves gap above dock")
		_expect(not orders._shelf.get_global_rect().intersects(orders._banner.get_global_rect()), "shelf and mode banner do not overlap")
		_expect(orders._banner.get_global_rect().end.y <= orders._shelf.position.y - 8, "mode banner stays attached above the tool shelf")
		_expect(is_equal_approx(orders._shelf.get_global_rect().get_center().x,viewport_size.x*.5), "shelf centers above dock")
		if "--capture" in OS.get_cmdline_user_args():
			await RenderingServer.frame_post_draw
			DirAccess.make_dir_recursive_absolute("res://tmp/orders_review")
			root.get_texture().get_image().save_png("res://tmp/orders_review/orders_%d.png" % viewport_size.x)
		explorer.select_object(flora, Vector2i(43,34))
		explorer._window.position = Vector2(viewport_size.x - explorer._window.size.x - 24,24)
		orders.refresh()
		await _settle()
		for panel: Control in [orders._shelf,orders._banner]:
			_expect(not panel.get_global_rect().intersects(explorer._window.get_global_rect()), "order controls leave inspector accessible at " + str(viewport_size))
		_expect(not dock._dock_panel.get_global_rect().intersects(explorer._window.get_global_rect()), "compact tree inspector clears the dock")
		if "--capture" in OS.get_cmdline_user_args():
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://tmp/orders_review/orders_inspector_%d.png" % viewport_size.x)
		explorer.clear_selection()
		orders.set_open(true, "zones")
		dock._request_order_tool("storage_zone")
		await _settle()
		for control: Control in [orders._shelf, orders._banner, dock._dock_panel]:
			_expect(bounds.encloses(control.get_global_rect()), "Zones control fits " + str(viewport_size))
		_expect(orders._banner.get_global_rect().end.y <= orders._shelf.position.y - 8, "Zones uses the same mode stack")
		if "--capture" in OS.get_cmdline_user_args():
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://tmp/orders_review/zones_%d.png" % viewport_size.x)


func _test_mining_zoom() -> void:
	var world_point := Vector2(160, 200)
	var camera_index: int = rig.get_index()
	var zoom: float = rig._target_zoom
	var pivot: Vector3 = rig._target_pos
	var width: int = mining._horizontal_size
	var depth: int = mining._vertical_size
	# Input propagation must work regardless of which node sees unhandled input first.
	for index in [0, scene.get_child_count() - 1]:
		scene.move_child(rig, index)
		var before: float = rig._target_zoom
		_wheel(world_point, MOUSE_BUTTON_WHEEL_UP)
		_expect(rig._target_zoom < before and mining.is_active(), "plain wheel zooms in with mining selected")
		before = rig._target_zoom
		_wheel(world_point, MOUSE_BUTTON_WHEEL_DOWN)
		_expect(rig._target_zoom > before, "plain wheel zooms out with mining selected")
		_expect(mining._horizontal_size == width and mining._vertical_size == depth, "zoom leaves brush dimensions unchanged")
		before = rig._target_zoom
		_hold_modifier(KEY_SHIFT, true)
		_wheel(world_point, MOUSE_BUTTON_WHEEL_UP)
		_expect(mining._horizontal_size == width + 1 and rig._target_zoom == before, "Shift wheel resizes width without zoom")
		_wheel(world_point, MOUSE_BUTTON_WHEEL_DOWN)
		_hold_modifier(KEY_SHIFT, false)
		_hold_modifier(KEY_ALT, true)
		_wheel(world_point, MOUSE_BUTTON_WHEEL_UP)
		_expect(mining._vertical_size == depth + 1 and rig._target_zoom == before, "Alt wheel resizes depth without zoom")
		_wheel(world_point, MOUSE_BUTTON_WHEEL_DOWN)
		_hold_modifier(KEY_ALT, false)
		_wheel(orders._shelf.get_global_rect().get_center(), MOUSE_BUTTON_WHEEL_DOWN)
		_expect(rig._target_zoom == before, "wheel over Orders does not zoom through UI")
		_hold_modifier(KEY_SHIFT, true)
		_wheel(orders._banner.get_global_rect().get_center(), MOUSE_BUTTON_WHEEL_UP)
		_hold_modifier(KEY_SHIFT, false)
		_expect(mining._horizontal_size == width and rig._target_zoom == before, "wheel over banner cannot resize or zoom")
	scene.move_child(rig, camera_index)
	rig._target_zoom = zoom
	rig._target_pos = pivot


func _hold_modifier(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _wheel(point: Vector2, button: MouseButton) -> void:
	_motion(point)
	var event := InputEventMouseButton.new()
	event.position = point
	event.button_index = button
	event.pressed = true
	event.shift_pressed = Input.is_key_pressed(KEY_SHIFT)
	event.alt_pressed = Input.is_key_pressed(KEY_ALT)
	root.push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event, true)


func _find_button(parent: Node, label: String) -> Button:
	for child in parent.get_children():
		if child is Button and child.text == label: return child
		var nested := _find_button(child, label)
		if nested != null: return nested
	return null


func _spawn_order_tree(id: Vector2i) -> void:
	var species: Dictionary = flora._species_for_key("base:flora:oak_tree")
	var stage: Dictionary = species.stages.mature
	var cell := Vector3i(id.x,20,id.y)
	var path: String = flora.resolve_tree_model_for_season(stage, flora._season, cell)
	flora._instance_tree("oak",path,"mature",stage,id.x,id.y,20,3)


func _motion(position: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position
	root.push_input(event,true)


func _mouse(position: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	root.push_input(event,true)
