extends "res://scripts/tests/WorkerCraftingTest.gd"

var builder
var mining
var renderer

func _run() -> void:
	create_timer(80).timeout.connect(func(): push_error("Construction input timed out"); quit(1))
	await _setup_crafting_fixture()
	root.get_node("WorldGenerator").waterline_map.resize(1024*1024)
	root.get_node("WorldGenerator").waterline_map.fill(-1)
	root.get_node("WorldClock").set_paused(true)
	stockpiles.reset_runtime_state()
	mining = load("res://scripts/systems/MiningDesignationController.gd").new()
	scene.add_child(mining)
	mining.set_process(false)
	# Exercise the production mesh builder without starting terrain generation.
	renderer = load("res://scripts/systems/WorldRenderer.gd").new()
	renderer._material = renderer._create_material()
	builder = load("res://scripts/systems/ConstructionController.gd").new()
	builder.name = "Construction"
	builder.furniture = furniture
	builder.mining = mining
	builder.renderer = renderer
	builder.dock = dock
	scene.add_child(builder)
	explorer = load("res://scripts/ui/ObjectExplorerController.gd").new()
	explorer.window_manager_path = NodePath("../Windows")
	explorer.click_tool_paths.append(NodePath("../Construction"))
	scene.add_child(explorer)
	await _frames(5)
	_click(dock._button_by_target.construction.get_global_rect().get_center())
	await _frames(5)
	_expect(dock._panel_container.visible and dock._panel_title.text=="Construction","new dock menu opens")
	await _check_construction_menu()
	await _capture_ui("menu")
	_click(dock._panel_body.get_child(0).get_global_rect().get_center())
	await _frames(3)
	_expect(builder.is_active() and not dock._panel_container.visible,"Stone block menu starts construction")
	var a := camera.unproject_position(Vector3(44.5,21,42.5))
	var b := camera.unproject_position(Vector3(46.5,21,42.5))
	_move(a)
	_mouse_button(a,true)
	_move(b)
	_mouse_button(b,false)
	_expect(builder.orders.size()==1,"real mouse drag creates an area")
	if builder.orders.is_empty():
		for failure: String in failures: push_error(failure)
		quit(1); return
	var id: int = builder.orders.keys()[0]
	_expect(builder.orders[id].cells.size()==3,"drag creates exactly the three previewed cells: %s" % str(builder.orders[id].cells))
	_expect(builder._plans.mesh!=null or builder._dirty,"planned cells have a visible overlay")
	await _capture_ui("plans")
	await _check_plan_inspector(id)
	var cancel := camera.unproject_position(Vector3(45.5,21.5,42.5))
	_mouse_button(cancel,true,true); _mouse_button(cancel,false,true)
	_expect(builder.orders.is_empty(),"Ctrl click cancels an unfinished area")
	await _check_large_drags()
	var wheel := InputEventMouseButton.new()
	wheel.position = a; wheel.button_index = MOUSE_BUTTON_WHEEL_UP; wheel.pressed = true; wheel.alt_pressed = true
	root.push_input(wheel,true)
	_expect(builder._height==2,"Alt wheel adjusts wall height")
	builder.renderer.slice_y = 21
	furniture._slice_y = 21
	_move(a); _mouse_button(a,true); _mouse_button(a,false)
	id = builder.orders.keys()[0]
	_expect(builder.orders[id].cells.size()==1,"slice clips the designation as well as its preview")
	builder.cancel_order(id)
	# A completed sample uses the actual existing stone keys and mesh/material.
	var built := []
	for x in range(43,48):
		for y in range(21,25):
			var cell := Vector3i(x,y,42)
			built.append({"cell":[x,y,42],"block":String(blocks.get_key(root.get_node("WorldGenerator").construction_stone_id(cell)))})
	world.restore_terrain({"edits":built})
	builder.restore_state({"next_id":20,"orders":[]})
	renderer._rebuild_added_terrain()
	builder.renderer.slice_y = 127
	furniture._slice_y = 127
	builder._dirty = true
	renderer._rebuild_added_terrain()
	_expect(renderer._added_terrain!=null and not renderer._added_meshes.is_empty(),"terrain renderer owns completed block faces")
	# This fixture leaves the renderer detached to avoid starting worldgen.
	renderer._added_terrain.reparent(scene, false)
	_move(camera.unproject_position(Vector3(45.5,22.5,43)))
	builder._update_preview(camera.unproject_position(Vector3(45.5,22.5,43)))
	_expect(builder._hover==Vector3i(45,22,43),"wall-side picking targets adjacent cleared air")
	await _capture_ui("stone")
	for resolution in [Vector2i(1280,720),Vector2i(960,540)]:
		root.size = resolution
		await _frames(6)
		_expect(dock._dock_panel.get_global_rect().position.x>=0 and dock._dock_panel.get_global_rect().end.x<=resolution.x,"dock fits %s" % resolution)
		_expect(builder._hint.get_global_rect().end.x<=resolution.x,"construction controls fit %s" % resolution)
		await _capture_ui("controls_%d" % resolution.x)
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE; escape.pressed = true
	root.push_input(escape,true)
	_expect(not builder.is_active(),"Escape ends construction")
	builder.renderer = null
	renderer.free()
	for failure: String in failures: push_error(failure)
	print("CONSTRUCTION_INPUT_OK" if failures.is_empty() else "CONSTRUCTION_INPUT_FAIL")
	quit(0 if failures.is_empty() else 1)


func _check_large_drags() -> void:
	# Use clear terrain away from the furniture fixture. Exercise real preview
	# and release input, including reverse drags and endpoints beyond the cap.
	var original_transform := camera.transform
	var original_projection := camera.projection
	var original_size := camera.size
	explorer.clear_selection()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 56
	camera.position = Vector3(100,80,100)
	camera.rotation_degrees = Vector3(-90,0,0)
	await _frames(3)
	for kind in ["stone","plank_floor","stone_floor"]:
		if not builder.is_active() or builder._kind!=kind:
			builder._on_tool_requested("construct_"+kind)
		for reverse in [false,true]:
			var start := Vector3(80.5,21,80.5) if not reverse else Vector3(119.5,21,119.5)
			var finish := Vector3(119.5,21,119.5) if not reverse else Vector3(80.5,21,80.5)
			var a := camera.unproject_position(start)
			var b := camera.unproject_position(finish)
			_move(a); _mouse_button(a,true); _move(b)
			var preview: Array = builder._preview_cells.duplicate()
			_expect(preview.size()==32*32,"%s preview spans 32 by 32, reverse=%s" % [kind,reverse])
			_mouse_button(b,false)
			_expect(builder.orders.size()==1,"large drag creates one construction order")
			if builder.orders.is_empty(): continue
			var id: int = builder.orders.keys()[0]
			var cells: Array = builder.orders[id].cells
			_expect(cells==preview,"large order matches its capped preview")
			var low := 88 if reverse else 80
			var high := 119 if reverse else 111
			_expect(cells.has(Vector3i(low,21,low)) and cells.has(Vector3i(high,21,high)),"large drag includes both corners")
			_expect(cells.all(func(cell: Vector3i): return cell.x>=low and cell.x<=high and cell.z>=low and cell.z<=high),"oversized drag stops at 32 on both axes")
			builder.cancel_order(id)
	camera.transform = original_transform
	camera.projection = original_projection
	camera.size = original_size
	builder._on_tool_requested("construct_stone")
	await _frames(3)


func _check_construction_menu() -> void:
	var original_size := root.size
	for resolution in [Vector2i(960,540), Vector2i(1280,720), Vector2i(2560,1440)]:
		root.size = resolution
		await _frames(8)
		var bounds := Rect2(Vector2.ZERO, Vector2(resolution))
		_expect(not dock._panel_header.visible and not dock._panel_rail_back.visible, "Construction uses an icon-only root rail")
		_expect(dock._panel_body.get_child_count() == 2, "Construction keeps Stone block and Floors")
		_expect(is_equal_approx(dock._panel_container.position.x + 8, dock._button_by_target.construction.get_global_rect().position.x), "Construction anchors above its dock icon")
		_expect(bounds.encloses(dock._panel_container.get_global_rect()) and dock._panel_container.get_global_rect().end.y <= dock._dock_panel.position.y - 8, "Construction fits above dock")
		for button in dock._panel_body.get_children():
			_expect(button.text.is_empty() and button.icon is AtlasTexture and not button.planned, "live Construction entries use illustrated artwork")
			_expect(is_equal_approx(button.size.x, button.size.y) and button.size.x >= 56, "Construction icons stay square")
		await _capture_menu_art("construction_%d" % resolution.x)
		var stone = dock._panel_body.get_child(0)
		_move(Vector2(12,120))
		await _frames(3)
		_move(stone.get_global_rect().get_center())
		await create_timer(.4).timeout
		_expect(stone._info != null and stone._info.visible and stone.description.contains("1 rough stone"), "stone hover explains real material cost")
		await _capture_menu_art("stone_hover_%d" % resolution.x)
		_click(dock._panel_body.get_child(1).get_global_rect().get_center())
		await _frames(8)
		_expect(dock._active_panel_target == "construction_floors" and dock._panel_rail_back.visible and not dock._panel_header.visible, "Floors opens the illustrated child rail with Back")
		_expect(dock._panel_body.get_child_count() == 2 and bounds.encloses(dock._panel_container.get_global_rect()), "both floor icons fit")
		for button in dock._panel_body.get_children():
			_expect(button.icon is AtlasTexture and button.text.is_empty() and button.preview and not button.planned and not button.disabled, "floor previews remain usable and carry preview metadata")
		await _capture_menu_art("floors_%d" % resolution.x)
		var plank = dock._panel_body.get_child(0)
		_move(Vector2(12,120))
		plank.grab_focus()
		await create_timer(.4).timeout
		_expect(plank._info != null and plank._info.visible and bounds.encloses(plank._info.get_global_rect()), "keyboard focus shows floor preview explanation inside viewport")
		_expect(plank.description.contains("Carpenter") and plank.description.contains("cannot build"), "preview explains unavailable workers")
		await _capture_menu_art("floor_help_%d" % resolution.x)
		_menu_key(KEY_ENTER)
		await _frames(5)
		_expect(builder.is_active() and builder._kind == "plank_floor" and not dock._panel_container.visible and not dock._panel_connector.visible, "Enter on plank starts the real preview tool and closes rail")
		_expect(not plank._info.visible and dock._button_by_target.construction.button_pressed, "selection clears help and retains Construction highlight")
		_menu_key(KEY_ESCAPE)
		_expect(not builder.is_active() and not dock._button_by_target.construction.button_pressed, "Escape ends preview and clears highlight")
		_click(dock._button_by_target.construction.get_global_rect().get_center())
		await _frames(5)
		_click(dock._panel_body.get_child(1).get_global_rect().get_center())
		await _frames(5)
		_click(dock._panel_body.get_child(1).get_global_rect().get_center())
		await _frames(4)
		_expect(builder.is_active() and builder._kind == "stone_floor", "stone floor icon selects the stone preview")
		_menu_key(KEY_ESCAPE)
		_click(dock._button_by_target.construction.get_global_rect().get_center())
		await _frames(5)
		_click(dock._panel_body.get_child(1).get_global_rect().get_center())
		await _frames(5)
		_click(dock._panel_rail_back.get_global_rect().get_center())
		await _frames(5)
		_expect(dock._active_panel_target == "construction" and not dock._panel_rail_back.visible, "Back returns to Construction without activating a tool")
		_click(dock._button_by_target.system.get_global_rect().get_center())
		await _frames(5)
		_expect(not dock._panel_header.visible and not dock._panel_rail_back.visible and dock._panel_connector.visible, "Menu uses its own illustrated root rail")
		_expect(bounds.encloses(dock._panel_container.get_global_rect()), "ordinary Menu still fits after illustrated submenu")
		_click(dock._button_by_target.construction.get_global_rect().get_center())
		await _frames(5)
	root.size = original_size
	await _frames(8)
	_expect(builder.orders.is_empty(), "browsing and preview activation alone never create construction work")


func _menu_key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	root.push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event, true)


func _capture_menu_art(label: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	await _frames(4)
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://tmp/construction_art_20261012/native")
	root.get_texture().get_image().save_png("res://tmp/construction_art_20261012/native/%s.png" % label)

func _check_plan_inspector(id: int) -> void:
	var original_size := root.size
	var cells: Array[Vector3i] = builder.orders[id].cells.duplicate()
	var point := camera.unproject_position(Vector3(45.5,21.5,42.5))
	_click(point)
	await _frames(5)
	_expect(explorer.is_object_selected(builder,id) and manager.is_open("object_explorer"),"active construction tool opens clicked plan")
	_expect(builder.orders.size()==1 and not builder._dragging,"inspecting a plan does not start another designation")
	_expect(explorer._row_values[1].text=="3" and explorer._row_values[2].text=="0 / 3 stone delivered","inspector shows remaining blocks and delivered stone")
	_expect(explorer._outline.visible and explorer._outline_bounds.size.is_equal_approx(Vector3(3,1,1)),"selected area has a visible outline")
	await _capture_ui("construction_inspector")
	_click(explorer._window.position+Vector2(100,16))
	_expect(builder.orders.size()==1 and explorer._object_id==id,"inspector consumes UI clicks")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE; escape.pressed = true
	root.push_input(escape,true)
	_expect(not builder.is_active(),"Escape finishes construction while inspector is open")
	explorer.clear_selection()
	_click(point)
	_expect(explorer.is_object_selected(builder,id),"inactive construction plans are selectable")
	# Nearest occupied cell wins, rather than an area's bounding-box holes.
	var sparse: Array[Vector3i] = [Vector3i(49,21,42),Vector3i(51,21,42)]
	var other: int = builder.create_order(sparse)
	_expect(builder.pick_explorer_object(Vector3(50.5,25,42.5),Vector3(50.5,20,42.5)).is_empty(),"empty space between planned cells is not selectable")
	builder.cancel_order(other)
	# A roof in front of the ray blocks selection and Ctrl cancellation.
	var direction := camera.project_ray_normal(point)
	var roof := Vector3i((Vector3(45.5,21.5,42.5)-direction*4).floor())
	world.set_block(roof.x,roof.y,roof.z,blocks.get_id("base:terrain:rock:rock01"))
	explorer.clear_selection()
	_expect(not explorer.select_at_screen(point),"terrain occludes construction plans")
	builder._cancel_at(point)
	_expect(builder.orders.has(id),"terrain protects hidden plans from Ctrl cancellation")
	world.set_block(roof.x,roof.y,roof.z,blocks.AIR_ID)
	# Lowering the slice hides and closes the selected plan.
	_click(point)
	renderer.slice_y = 20
	explorer._on_slice_changed(20)
	_expect(not manager.is_open("object_explorer") and not explorer.select_at_screen(point),"hidden plans cannot be selected and close their inspector")
	renderer.slice_y = 127
	explorer._on_slice_changed(127)
	_click(point)
	await _frames(5)
	var before := JSON.stringify(builder.serialize_state())
	for i in range(5): explorer._refresh_selected()
	_expect(JSON.stringify(builder.serialize_state())==before,"inspector refresh is observational")
	for size in [Vector2i(960,540),Vector2i(1280,720)]:
		root.size = size
		await _frames(5)
		explorer._refresh_selected()
		await _frames(5)
		_expect(Rect2(Vector2.ZERO,Vector2(size)).encloses(explorer._window.get_global_rect()),"construction inspector fits %s" % size)
		await _capture_ui("construction_inspector_%d" % size.x)
	_click(explorer._actions.get_child(0).get_global_rect().get_center())
	await _frames(3)
	_expect(builder.orders.is_empty() and not manager.is_open("object_explorer"),"Cancel construction removes the selected order and closes inspector")
	# A disappearing/completed area also closes automatically, without a click.
	var finishing: int = builder.create_order(cells)
	explorer.select_object(builder,finishing)
	builder.cancel_order(finishing)
	# Headless frame throughput is not a clock; explicitly cross the UI timer.
	explorer._process(explorer.REFRESH_SECONDS+.01)
	_expect(not manager.is_open("object_explorer"),"removed plan closes on periodic refresh")
	root.size = original_size
	await _frames(5)
	builder.create_order(cells)
	builder._on_tool_requested("construct_stone")

func _move(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion,true)

func _mouse_button(point: Vector2, pressed: bool, ctrl := false) -> void:
	var event := InputEventMouseButton.new()
	event.position = point; event.button_index = MOUSE_BUTTON_LEFT; event.pressed = pressed; event.ctrl_pressed = ctrl
	root.push_input(event,true)

func _capture_ui(label: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	await _frames(5)
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://tmp/construction_20261012/native")
	root.get_texture().get_image().save_png("res://tmp/construction_20261012/native/%s.png" % label)
