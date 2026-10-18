extends "res://scripts/tests/FurniturePlaceTest.gd"

var mining
var storage
var chop
var rig
var orders
var details
const BOULDER_A := "boulder:1234:fixture:a"
const BOULDER_B := "boulder:1234:fixture:b"
const BOULDER_OUTSIDE := "boulder:1234:fixture:outside"

class GuideSlice extends Node:
	var slice_y := 127


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
	generator.waterline_map.resize(1024 * 1024)
	generator.waterline_map.fill(-1)
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
	details = load("res://scripts/systems/SurfaceDetailManager.gd").new()
	details.name = "Details"
	scene.add_child(details)
	details._initialized = true
	details.set_process(false)
	_spawn_order_boulder(BOULDER_A, Vector3i(33,20,32))
	_spawn_order_boulder(BOULDER_B, Vector3i(37,20,30))
	_spawn_order_boulder(BOULDER_OUTSIDE, Vector3i(28,20,43))
	explorer = load("res://scripts/ui/ObjectExplorerController.gd").new()
	explorer.name = "Explorer"
	explorer.window_manager_path = NodePath("../Windows")
	scene.add_child(explorer)
	chop = load("res://scripts/systems/TreeFellingController.gd").new()
	chop.dock_ui_path = NodePath("../Dock")
	chop.flora_path = NodePath("../Flora")
	chop.details_path = NodePath("../Details")
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
	_expect(orders._buttons.size() == 9 and orders._buttons.clear_stones.visible and not orders._buttons.storage_zone.visible, "Orders shows six work tools and keeps three zone entries in Zones")
	_click(orders._buttons.mine_precision.get_global_rect().get_center())
	await _settle()
	_expect(mining.is_active() and orders._banner.visible and not mining._hint_window.visible, "mining uses the shared banner")
	_expect(orders.is_open() and orders._buttons.mine_precision.button_pressed, "shelf stays open and marks the active tool")
	await _test_mining_guide()
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
	details.designate_clearing(BOULDER_A)
	details._changes[BOULDER_A].work_seconds = 2.0
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
	_expect(chop._preview_mining.size() > 0 and chop._preview_trees.has(tree_id) and chop._preview_stones.has(BOULDER_A), "cancellation previews blocks, trees and boulders together")
	_mouse(rect.end,false)
	_expect(flora.get_felling_order_token(tree_id) == null, "mixed cancellation releases felling source")
	_expect(details.get_clearing_order_token(BOULDER_A) == null and details._changes[BOULDER_A].work_seconds == 2.0, "mixed cancellation releases boulder work and keeps progress")
	var task = root.get_node("TaskManager").get_task(task_id)
	_expect(task == null or task.status == Task.Status.CANCELLED, "cancellation retires scheduler lease")
	await _test_boulder_orders()
	await _test_scree_orders()
	await _test_shrub_orders()
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


func _test_boulder_orders() -> void:
	explorer.clear_selection()
	_click(orders._buttons.clear_stones.get_global_rect().get_center())
	await _settle()
	_expect(chop.get_order_tool_id() == "clear_stones" and orders.active_tool_id() == "clear_stones", "Clear stones starts exclusive shared tool")
	_expect(orders._buttons.clear_stones.button_pressed and orders._title.text == "Clear stones", "boulder tile and banner show the active tool")
	var point := camera.unproject_position(details.get_explorer_bounds(BOULDER_A).get_center())
	_click(point)
	_expect(details.get_clearing_order_token(BOULDER_A) != null, "world click creates a boulder job")
	_expect(explorer._provider == details and explorer._object_id == BOULDER_A, "world click opens normal boulder inspection")
	var first: RefCounted = details.get_clearing_order_token(BOULDER_A)
	var count: int = orders._history.size()
	chop.designate_at_screen(point)
	_expect(orders._history.size() == count and details.get_clearing_order_token(BOULDER_A) == first, "repeat click keeps one lease and one receipt")
	orders._view_last()
	_expect(not chop.is_active() and explorer._provider == details, "View order finishes tool and opens boulder inspector")
	explorer.clear_selection()
	dock._request_order_tool("clear_stones")
	orders._undo_last()
	_expect(details.get_clearing_order_token(BOULDER_A) == null and details._changes[BOULDER_A].work_seconds == 2.0, "Undo cancels boulder designation without losing partial work")
	# Stale receipts cannot affect a later re-mark or same-ID restored job.
	chop.designate_at_screen(point)
	var stale: Dictionary = orders._last_order.receipt
	details.cancel_clearing(BOULDER_A)
	details.designate_clearing(BOULDER_A)
	_expect(not chop.order_is_pending(stale) and chop.undo_order(stale) == 0, "stale boulder undo cannot cancel reissued work")
	var state: Dictionary = details.serialize_state()
	var restored_token: RefCounted = details.get_clearing_order_token(BOULDER_A)
	details.restore_state(JSON.parse_string(JSON.stringify(state)))
	_expect(details.get_clearing_order_token(BOULDER_A) != restored_token, "restore creates a fresh boulder order identity")
	_expect(chop.undo_order({"stones": [{"id": BOULDER_A, "source": restored_token}]}) == 0, "old receipt cannot cancel loaded work")
	explorer.clear_selection()
	_click(orders._buttons.cancel_orders.get_global_rect().get_center())
	_click(point)
	_expect(details.get_clearing_order_token(BOULDER_A) == null and details._changes[BOULDER_A].work_seconds == 2.0, "Cancel orders click preserves partial stone work")
	# Two-boulder area; a third outside, trees and ground must remain untouched.
	_click(orders._buttons.clear_stones.get_global_rect().get_center())
	await _settle()
	var a := camera.unproject_position(Vector3(31.2,21,28.2))
	var b := camera.unproject_position(Vector3(40.8,21,35.8))
	_motion(a); _mouse(a,true); _motion(b)
	chop._process(.1)
	orders.refresh()
	_expect(chop._preview_stones.size() == 2 and orders._hint.text.begins_with("2 stones"), "rectangle previews actual boulder count")
	_expect(details._sources.is_empty(), "preview creates no work before release")
	var polygon: PackedVector2Array = chop._selection._polygon.duplicate()
	camera.position.x += .1
	chop._hover_elapsed = 0.0
	chop._process(.01)
	_expect(chop._selection._polygon != polygon, "boulder marquee tracks camera before candidate refresh")
	camera.position.x -= .1
	if "--capture" in OS.get_cmdline_user_args():
		for frame in range(2): await process_frame
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://tmp/boulder_review")
		root.get_texture().get_image().save_png("res://tmp/boulder_review/orders_rectangle.png")
	_mouse(b,false)
	_expect(details._sources.size() == 2 and details.get_clearing_order_token(BOULDER_OUTSIDE) == null, "release marks only stones inside area")
	first = details.get_clearing_order_token(BOULDER_A)
	var receipt: Dictionary = orders._last_order.receipt
	count = orders._history.size()
	_motion(b); _mouse(b,true); _motion(a); _mouse(a,false)
	_expect(details._sources.size() == 2 and details.get_clearing_order_token(BOULDER_A) == first and orders._history.size() == count, "reverse repeated rectangle is idempotent")
	# Undo still resolves the correct owner after switching back to Chop trees.
	dock._request_order_tool("chop")
	_expect(chop.undo_order(receipt) == 2 and details._changes[BOULDER_A].work_seconds == 2.0, "boulder receipt remains safe after changing modes")
	# Preview cancellation on Escape, UI release, tool switch and focus loss.
	dock._request_order_tool("clear_stones")
	_motion(a); _mouse(a,true); _motion(b)
	_key(KEY_ESCAPE)
	_mouse(b,false)
	_expect(not chop.is_active() and details._sources.is_empty(), "Escape discards unfinished boulder area")
	dock._request_order_tool("clear_stones")
	_motion(a); _mouse(a,true); _motion(b)
	chop._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	_mouse(b,false)
	_expect(not chop._dragging and details._sources.is_empty(), "focus loss discards boulder area")
	_motion(a); _mouse(a,true); _motion(b)
	dock._request_order_tool("chop")
	_mouse(b,false)
	_expect(details._sources.is_empty(), "changing tools discards boulder preview")
	dock._request_order_tool("clear_stones")
	_motion(a); _mouse(a,true)
	var ui: Vector2 = orders._buttons.clear_stones.get_global_rect().get_center()
	_motion(ui)
	await _settle()
	_mouse(ui,false)
	_expect(not chop._dragging and details._sources.is_empty(), "release over Orders cancels boulder gesture")
	# Slicing hides rocks from both new selection and cancellation rectangles.
	details.designate_clearing(BOULDER_A)
	details.apply_slice(19)
	_motion(a); _mouse(a,true); _motion(b); chop._process(.1)
	_expect(chop._preview_stones.is_empty(), "sliced-out boulders cannot be designated")
	_mouse(b,false)
	dock._request_order_tool("cancel_orders")
	_motion(a); _mouse(a,true); _motion(b); chop._process(.1)
	_expect(chop._preview_stones.is_empty(), "sliced-out boulder orders are excluded from cancellation")
	_mouse(b,false)
	_expect(details.get_clearing_order_token(BOULDER_A) != null, "hidden boulder keeps its queued work")
	details.apply_slice(127)
	details.cancel_clearing(BOULDER_A)
	dock._request_order_tool("")
	_expect(flora.get_felling_order_token(Vector2i(43,34)) == null and world.get_block(33,20,32) == blocks.get_id("base:terrain:rock:rock01"), "boulder tool does not designate trees or mine ground")


func _test_scree_orders() -> void:
	var id := "scree:1234:fixture:a"
	details.register_record({"id": id, "definition": "base:detail:scree", "origin": Vector3i(37,20,34), "variant": 0, "yaw": 0, "habitat": "fixture"})
	details._spawn_visual(id)
	explorer.clear_selection()
	dock._request_order_tool("clear_stones")
	await _settle()
	var point := camera.unproject_position(Vector3(37.75,21.25,34.875))
	_click(point)
	_expect(details.get_clearing_order_token(id) != null and explorer._object_id == id, "Clear stones click picks and designates an actual scree mesh")
	details._changes[id].work_seconds = .5
	orders._undo_last()
	_expect(details.get_clearing_order_token(id) == null and details._changes[id].work_seconds == .5, "scree Undo keeps gathered work")
	explorer.clear_selection()
	var a := camera.unproject_position(Vector3(31.2,21,28.2))
	var b := camera.unproject_position(Vector3(40.8,21,35.8))
	_motion(a); _mouse(a,true); _motion(b); chop._process(.1)
	_expect(chop._preview_stones.size() == 3 and chop._preview_stones.has(id), "rectangle counts boulders and scree together")
	_mouse(b,false)
	_expect(details._sources.size() == 3, "mixed stone rectangle posts both work types: %s" % str(details._sources.keys()))
	var receipt: Dictionary = orders._last_order.receipt
	dock._request_order_tool("chop")
	_expect(chop.undo_order(receipt) == 3, "mixed receipt undoes all stones even after changing modes")
	details.designate_clearing(id)
	details.apply_slice(19)
	_expect(not details.stones_in_clearing_rect(Rect2i(30,28,14,14)).has(id), "hidden scree excluded from new orders")
	details.apply_slice(127)
	dock._request_order_tool("cancel_orders")
	_click(point)
	_expect(details.get_clearing_order_token(id) == null and details._changes[id].work_seconds == .5, "Cancel orders picks nonblocking scree and retains work")
	dock._request_order_tool("")


func _spawn_order_boulder(id: String, origin: Vector3i) -> void:
	details.register_record({"id": id, "definition": "base:detail:boulder", "origin": origin, "variant": 0, "yaw": 0, "habitat": "fixture"})
	details._spawn_visual(id)


func _test_shrub_orders() -> void:
	var reed := "reeds:1234:fixture:a"
	details.register_record({"id": reed, "definition": "base:detail:reeds", "origin": Vector3i(31,20,33), "variant": 1, "yaw": 0, "habitat": "fixture"})
	details._spawn_visual(reed)
	var flower := "flowers:1234:fixture:a"
	details.register_record({"id": flower, "definition": "base:detail:flowers", "origin": Vector3i(32,20,29), "variant": 0, "yaw": 0, "habitat": "fixture"})
	details._spawn_visual(flower)
	var ids := ["blueberry:1234:fixture:a", "elderberry:1234:fixture:a", "wild_strawberry:1234:fixture:a"]
	var positions := [Vector3i(35,20,29),Vector3i(40,20,31),Vector3i(35,20,35)]
	for i in range(ids.size()):
		details.register_record({"id": ids[i], "definition": "base:flora:%s_bush" % String(ids[i]).get_slice(":",0), "origin": positions[i], "variant": 0, "yaw": 0, "habitat": "fixture"})
		details._spawn_visual(ids[i])
	explorer.clear_selection()
	_click(orders._buttons.harvest_plants.get_global_rect().get_center())
	await _settle()
	_expect(chop.get_order_tool_id() == "harvest_plants" and orders._title.text == "Harvest plants", "Harvest plants has an exclusive tile and banner")
	var point := _detail_pick_point(ids[0])
	_click(point)
	_expect(details.get_clearing_order_token(ids[0]) != null and explorer._object_id == ids[0], "actual plant mesh click creates harvest order and inspector")
	details._changes[ids[0]].work_seconds = .75
	var stale: Dictionary = orders._last_order.receipt
	orders._undo_last()
	_expect(details.get_clearing_order_token(ids[0]) == null and details._changes[ids[0]].work_seconds == .75, "harvest Undo keeps partial work")
	explorer.clear_selection()
	# One rectangle contains stones, ripe plants and an out-of-season elderberry.
	var a := camera.unproject_position(Vector3(31.2,21,28.2))
	var b := camera.unproject_position(Vector3(41.8,21,35.8))
	_motion(a); _mouse(a,true); _motion(b); chop._process(.1)
	_expect(chop._preview_stones.size() == 2 and not chop._preview_stones.has(ids[1]), "harvest area counts only ripe shrubs")
	_mouse(b,false)
	_expect(details._sources.size() == 2, "harvest area creates only two crop jobs")
	_expect(chop.undo_order(stale) == 0, "stale receipt cannot cancel reissued harvest")
	orders._undo_last()
	dock._request_order_tool("clear_stones")
	_expect(not chop.designate_at_screen(point), "Clear stones click cannot clear a shrub")
	_motion(a); _mouse(a,true); _motion(b); chop._process(.1)
	_expect(chop._preview_stones.size() == 3 and not chop._preview_stones.has(ids[0]), "stone area excludes all shrubs")
	chop._cancel_drag(); _mouse(b,false)
	dock._request_order_tool("clear_shrubs")
	await _settle()
	_expect(orders._title.text == "Clear plants", "shared clearing tool names plants")
	var flower_point := _detail_pick_point(flower)
	_expect(flower_point.x >= 0, "fixture flowers have exposed pickable geometry")
	if flower_point.x < 0: return
	_click(flower_point)
	_expect(details.get_clearing_order_token(flower) != null, "actual flower mesh click marks clearing")
	details._changes[flower].work_seconds = .4
	orders._undo_last()
	_expect(details.get_clearing_order_token(flower) == null and details._changes[flower].work_seconds == .4, "flower Undo keeps work")
	var reed_point := _detail_pick_point(reed)
	_expect(reed_point.x >= 0, "fixture reeds have exposed pickable geometry")
	if reed_point.x < 0: return
	_click(reed_point)
	_expect(details.get_clearing_order_token(reed) != null, "actual reed mesh click marks clearing")
	details._changes[reed].work_seconds = .3
	orders._undo_last()
	_expect(details.get_clearing_order_token(reed) == null and details._changes[reed].work_seconds == .3, "reed Undo keeps work")
	explorer.clear_selection()
	_motion(a); _mouse(a,true); _motion(b); chop._process(.1)
	_expect(chop._preview_stones.size() == 5 and chop._preview_stones.has(ids[1]) and chop._preview_stones.has(flower) and chop._preview_stones.has(reed), "plant area includes flowers, reeds and unripe shrubs, excluding stones")
	_mouse(b,false)
	_expect(details._sources.size() == 5 and details._sources[ids[0]].task_type == Task.Type.CLEAR_SHRUB and details._sources[flower].task_type == Task.Type.CLEAR_PLANT and details._sources[reed].task_type == Task.Type.CLEAR_PLANT, "mixed plant area posts correct clearing types")
	var receipt: Dictionary = orders._last_order.receipt
	dock._request_order_tool("chop")
	_expect(chop.undo_order(receipt) == 5, "plant receipt resolves its owner after switching tools")
	details.designate_clearing(flower)
	dock._request_order_tool("cancel_orders")
	_click(flower_point)
	_expect(details.get_clearing_order_token(flower) == null and details._changes[flower].work_seconds == .4, "Cancel orders releases flower work")
	details.designate_clearing(reed)
	_click(reed_point)
	_expect(details.get_clearing_order_token(reed) == null and details._changes[reed].work_seconds == .3, "Cancel orders releases reed work")
	if "--capture" in OS.get_cmdline_user_args():
		dock._request_order_tool("clear_shrubs")
		explorer.select_object(details,reed)
		await _settle()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tmp/reed_review/orders_reeds.png")
	details.designate_detail(ids[0],"harvest_plants")
	dock._request_order_tool("cancel_orders")
	_click(point)
	_expect(details.get_clearing_order_token(ids[0]) == null and details._changes[ids[0]].work_seconds == .75, "Cancel orders releases plant work and preserves progress")
	if "--capture" in OS.get_cmdline_user_args():
		dock._request_order_tool("harvest_plants")
		explorer.select_object(details,ids[0])
		await _settle()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tmp/shrub_review/orders_harvest.png")
	explorer.clear_selection()
	dock._request_order_tool("")


func _detail_pick_point(id: String) -> Vector2:
	var bounds: AABB = details.get_explorer_bounds(id)
	for x in range(1,10):
		for z in range(1,10):
			var point := camera.unproject_position(bounds.position + bounds.size * Vector3(x/10.0,.5,z/10.0))
			var hit: Dictionary = explorer.pick_at_screen(point)
			if hit.get("provider") == details and hit.get("id", "") == id: return point
	return Vector2(-1,-1)


func _test_mining_guide() -> void:
	# The fixture camera is detached from its rig; place the guide's pivot over
	# the same review patch, as it is during actual play.
	var original_pivot: Vector3 = rig.position
	rig.position = Vector3(40,25,40)
	_expect(not mining.is_mining_guide_enabled() and mining._terrain_grid_node.mesh==null and not mining._terrain_grid_node.visible,"mining opens without the old voxel grid or optional guide")
	_expect(orders._mining_guide.visible and not orders._mining_guide.button_pressed,"mining controls expose an off-by-default guide toggle")
	var before: int = mining._zones.size()
	await _capture_guide("off")
	_click(orders._mining_guide.get_global_rect().get_center())
	await _settle()
	_expect(mining.is_mining_guide_enabled() and mining._terrain_grid_node.visible and mining._terrain_grid_node.mesh!=null,"real toggle click enables the guide")
	_expect(mining._zones.size()==before,"clicking guide controls never designates terrain")
	_check_guide_mesh()
	await _capture_guide("on")
	var mesh: Mesh = mining._terrain_grid_node.mesh
	mining._rebuild_terrain_grid()
	_expect(mining._terrain_grid_node.mesh==mesh,"stationary guide reuses mesh")
	var pivot: Vector3 = rig.position
	rig.position += Vector3(16,0,16)
	mining._rebuild_terrain_grid()
	_expect(mining._terrain_grid_node.mesh!=mesh,"panning refreshes nearby coverage")
	_check_guide_mesh()
	var normal_radius: int = mining._terrain_grid_radius()
	root.size = Vector2i(2560,720)
	await _settle()
	_expect(mining._terrain_grid_radius()==normal_radius*2,"32:9 receives wider guide coverage at the same zoom")
	root.size = Vector2i(1280,720)
	await _settle()
	rig.position = pivot
	# The visible slice replaces the natural top, while designated/mined cells
	# lower that top. No single-voxel outlines return in either case.
	var slice := GuideSlice.new()
	mining._renderer = slice
	slice.slice_y = 16
	mining._on_visible_volume_changed()
	var vertices: PackedVector3Array = mining._terrain_grid_node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	_expect(Array(vertices).all(func(v): return is_equal_approx(v.y,17+mining.TERRAIN_GRID_OFFSET)),"guide follows sliced terrain height")
	var cell := Vector3i(32,16,40)
	mining._mined_blocks[cell] = true
	mining._grid_dirty = true
	mining._process(0)
	vertices = mining._terrain_grid_node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	_expect(Array(vertices).any(func(v): return is_equal_approx(v.y,16+mining.TERRAIN_GRID_OFFSET)),"mining updates the guide's newly exposed floor")
	mining._mined_blocks.erase(cell)
	mining._renderer = null
	slice.free()
	# A natural cliff is crossed by a thick continuous vertical stripe.
	var generator = root.get_node("WorldGenerator")
	var index := 32*1024+40
	generator.heightmap[index] = 24
	var stripe: PackedVector3Array = []
	var colors: PackedColorArray = []
	mining._append_area_guide(Vector2i(32,40),true,127,stripe,colors)
	_expect(Array(stripe).any(func(v): return is_equal_approx(v.y,25+mining.TERRAIN_GRID_OFFSET)),"ribbon follows raised terrain")
	_expect(Array(stripe).any(func(v): return is_equal_approx(v.z,41+mining.TERRAIN_GRID_OFFSET) and is_equal_approx(v.y,21)),"cliff stripe joins the two surface heights")
	generator.heightmap[index] = 20
	dock._request_order_tool("chop")
	await _settle()
	_expect(not orders._mining_guide.visible and not mining._terrain_grid_node.visible and mining._terrain_grid_node.mesh==null,"leaving mining hides guide and frees its mesh")
	dock._request_order_tool("mine_precision")
	await _settle()
	_expect(orders._mining_guide.button_pressed and mining._terrain_grid_node.mesh!=null,"reopening mining retains the chosen guide setting")
	_click(orders._mining_guide.get_global_rect().get_center())
	await _settle()
	_expect(not mining.is_mining_guide_enabled() and mining._terrain_grid_node.mesh==null,"toggle off removes all guide geometry")
	mining._rebuild_terrain_grid(true)
	_expect(mining._terrain_grid_node.mesh==null,"terrain notifications cannot rebuild a disabled guide")
	orders._mining_guide.release_focus()
	rig.position = original_pivot


func _check_guide_mesh() -> void:
	var mesh: Mesh = mining._terrain_grid_node.mesh
	_expect(mesh.surface_get_primitive_type(0)==Mesh.PRIMITIVE_TRIANGLES,"guide uses thick ribbons rather than one-pixel lines")
	var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var aligned := true
	for i in range(0,vertices.size(),6):
		var a := vertices[i]
		var b := vertices[i+1]
		var c := vertices[i+2]
		var middle := (a+c)*.5
		var dx := absf(middle.x-roundf(middle.x/32)*32)
		var dz := absf(middle.z-roundf(middle.z/32)*32)
		aligned = aligned and minf(dx,dz)<=.041 and absf(a.distance_to(b)-.08)<.0001
	_expect(aligned,"all ribbons follow exact world 32-block boundaries at the configured thickness")
	_expect(not mining._terrain_grid_material.no_depth_test and mining._terrain_grid_node.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,"guide is occluded by terrain and casts no shadows")


func _capture_guide(state: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args() and "--guide-capture" not in OS.get_cmdline_user_args(): return
	DirAccess.make_dir_recursive_absolute("res://tmp/mining_guide_20261017")
	_motion(Vector2(12,120))
	await _settle()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tmp/mining_guide_20261017/guide_%s.png" % state)


func _check_layouts() -> void:
	for viewport_size in [Vector2i(960,540),Vector2i(1280,720),Vector2i(1680,720),Vector2i(2560,720),Vector2i(2560,1440)]:
		root.size = viewport_size
		dock._request_order_tool("mine_precision")
		orders.set_open(true, "orders")
		await _settle()
		var bounds := Rect2(Vector2.ZERO, Vector2(viewport_size))
		_expect(orders._banner.get_global_rect().encloses(orders._mining_guide.get_global_rect()),"mining guide toggle fits inside controls at " + str(viewport_size))
		for control: Control in [orders._shelf, orders._banner, dock._dock_panel]:
			_expect(bounds.encloses(control.get_global_rect()), "Orders control fits " + str(viewport_size))
		_expect(orders._shelf.get_global_rect().end.y <= dock._dock_panel.position.y - 8, "shelf leaves gap above dock")
		_expect(not orders._shelf.get_global_rect().intersects(orders._banner.get_global_rect()), "shelf and mode banner do not overlap")
		_expect(orders._banner.get_global_rect().end.y <= orders._shelf.position.y - 8, "mode banner stays attached above the tool shelf")
		_expect(is_equal_approx(orders._buttons.mine_precision.get_global_rect().position.x,
			dock._button_by_target.orders.get_global_rect().position.x), "Orders icons anchor above their parent command")
		for id: String in ["mine_precision", "chop", "clear_stones", "harvest_plants", "clear_shrubs", "cancel_orders"]:
			var button: Button = orders._buttons[id]
			_expect(button.text.is_empty() and button.icon is AtlasTexture and not button.caption.is_empty(), "illustrated tool has a hover name instead of a caption")
			_expect(is_equal_approx(button.size.x, button.size.y) and button.size.x >= 56, "Orders art remains square and readable")
		if "--capture" in OS.get_cmdline_user_args():
			await RenderingServer.frame_post_draw
			DirAccess.make_dir_recursive_absolute("res://tmp/orders_review")
			root.get_texture().get_image().save_png("res://tmp/orders_art_20261012/orders_%d.png" % viewport_size.x)
		# Native hover behavior, including keyboard focus and hidden-shelf cleanup.
		var harvest = orders._buttons.harvest_plants
		_motion(harvest.get_global_rect().get_center())
		await create_timer(.4).timeout
		await _settle()
		_expect(harvest._info != null and harvest._info.visible, "hover reveals tool name and preservation rules")
		if "--capture" in OS.get_cmdline_user_args():
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://tmp/orders_art_20261012/hover_%d.png" % viewport_size.x)
		_motion(Vector2(12, 120))
		harvest.grab_focus()
		await create_timer(.4).timeout
		_expect(harvest._info.visible, "keyboard focus reveals tool help")
		var accept := InputEventKey.new()
		accept.keycode = KEY_ENTER
		accept.pressed = true
		root.push_input(accept, true)
		accept = accept.duplicate()
		accept.pressed = false
		root.push_input(accept, true)
		await _settle()
		_expect(chop.get_order_tool_id() == "harvest_plants" and chop.is_active() and not mining.is_active(), "Enter selects the focused tool through normal dispatch")
		_expect(not harvest._info.visible, "activating a focused command dismisses its help")
		harvest.release_focus()
		harvest.grab_focus()
		await create_timer(.4).timeout
		orders.set_open(false)
		_expect(not harvest._info.visible, "closing shelf clears its tooltip")
		harvest.release_focus()
		orders.set_open(true, "orders")
		dock._request_order_tool("mine_precision")
		explorer.select_object(flora, Vector2i(43,34))
		explorer._window.position = Vector2(viewport_size.x - explorer._window.size.x - 24,24)
		orders.refresh()
		await _settle()
		# Inspector content measures asynchronously. Refresh against its final
		# rectangle instead of relying on six native frames reaching the 10 Hz UI tick.
		orders.refresh()
		await _settle()
		for panel: Control in [orders._shelf,orders._banner]:
			_expect(not panel.get_global_rect().intersects(explorer._window.get_global_rect()), "order controls leave inspector accessible at %s: panel %s, inspector %s, tracked %s" % [viewport_size,panel.get_global_rect(),explorer._window.get_global_rect(),orders.inspector==explorer._window])
		_expect(not dock._dock_panel.get_global_rect().intersects(explorer._window.get_global_rect()), "compact tree inspector clears the dock")
		if "--capture" in OS.get_cmdline_user_args():
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://tmp/orders_art_20261012/orders_inspector_%d.png" % viewport_size.x)
		if viewport_size.x == 960:
			explorer._window.position.x = (viewport_size.x - explorer._window.size.x) * .5
			orders.refresh()
			await _settle()
			_expect(orders._grid.columns < 6, "moved inspector makes Orders wrap in the available side space")
			for panel: Control in [orders._shelf, orders._banner]:
				_expect(bounds.encloses(panel.get_global_rect()) and not panel.get_global_rect().intersects(explorer._window.get_global_rect()), "wrapped controls clear the centered inspector")
			for id: String in ["mine_precision", "chop", "clear_stones", "harvest_plants", "clear_shrubs", "cancel_orders"]:
				_expect(is_equal_approx(orders._buttons[id].size.x, orders._buttons[id].size.y), "wrapping keeps artwork square")
			if "--capture" in OS.get_cmdline_user_args():
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("res://tmp/orders_art_20261012/orders_wrapped_960.png")
		explorer.clear_selection()
		orders.set_open(true, "zones")
		dock._request_order_tool("storage_zone")
		await _settle()
		_expect(is_equal_approx(orders._buttons.storage_zone.get_global_rect().position.x, dock._button_by_target.zones.get_global_rect().position.x), "Zones anchors its first icon above its dock button")
		for id: String in ["storage_zone", "farming_zone", "animal_pasture"]:
			var button = orders._buttons[id]
			_expect(button.visible and button.text.is_empty() and button.icon is AtlasTexture, "Zones uses three illustrated icons")
			_expect(is_equal_approx(button.size.x, button.size.y) and button.size.x >= 56, "Zones artwork stays square and legible")
		for control: Control in [orders._shelf, orders._banner, dock._dock_panel]:
			_expect(bounds.encloses(control.get_global_rect()), "Zones control fits " + str(viewport_size))
		_expect(orders._banner.get_global_rect().end.y <= orders._shelf.position.y - 8, "Zones uses the same mode stack")
		if "--capture" in OS.get_cmdline_user_args():
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://tmp/zones_art_20261012/zones_%d.png" % viewport_size.x)
		var requests: Array[String] = []
		var on_request := func(id: String): requests.append(id)
		orders.tool_requested.connect(on_request)
		var zone_count: int = storage._zones.size()
		for id: String in ["farming_zone", "animal_pasture"]:
			var planned = orders._buttons[id]
			_expect(planned.planned and not planned.toggle_mode, "future zone is explicitly planned, not selectable")
			_motion(planned.get_global_rect().get_center())
			await create_timer(.4).timeout
			_expect(planned._info != null and planned._info.visible, "planned zone explains itself on hover")
			_click(planned.get_global_rect().get_center())
			await _settle()
			_expect(planned._info.visible and not planned.button_pressed and storage.is_active(), "planned click shows help and preserves Storage mode")
			_motion(Vector2(12, 120))
			planned.release_focus()
			planned.grab_focus()
			await create_timer(.4).timeout
			_expect(planned._info.visible, "planned help is keyboard accessible")
			var key := InputEventKey.new()
			key.keycode = KEY_ENTER
			key.pressed = true
			root.push_input(key, true)
			key = key.duplicate()
			key.pressed = false
			root.push_input(key, true)
			await _settle()
			_expect(requests.is_empty() and storage._zones.size() == zone_count and storage.is_active(), "planned mouse/keyboard input cannot dispatch work or create a zone")
			_expect(bounds.encloses(planned._info.get_global_rect()), "planned explanation fits the viewport")
			if "--capture" in OS.get_cmdline_user_args():
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("res://tmp/zones_art_20261012/%s_%d.png" % [id, viewport_size.x])
			orders.set_open(false)
			_expect(not planned._info.visible, "closing Zones dismisses planned explanation")
			planned.release_focus()
			orders.set_open(true, "zones")
			await _settle()
		orders.tool_requested.disconnect(on_request)


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
