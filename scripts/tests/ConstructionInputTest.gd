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
	await _check_shelf_card()
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
	_expect(builder.orders.size()==1 and builder.orders.values()[0].cells.size()==2,"Ctrl + click takes one block out of a plan")
	var first := camera.unproject_position(Vector3(44.5,21.5,42.5))
	var last := camera.unproject_position(Vector3(46.5,21.5,42.5))
	_mouse_button(first,true,true); _move(last); _mouse_button(last,false,true)
	_expect(builder.orders.is_empty(),"Ctrl + drag takes the rest out, and the plan is gone")
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
	await _check_copy_wall()
	for resolution in [Vector2i(1280,720),Vector2i(960,540)]:
		root.size = resolution
		await _frames(6)
		_expect(dock._dock_panel.get_global_rect().position.x>=0 and dock._dock_panel.get_global_rect().end.x<=resolution.x,"dock fits %s" % resolution)
		var bar: Rect2 = dock._tool_bar._bar.get_global_rect()
		_expect(dock._tool_bar._bar.visible and bar.position.x>=0 and bar.end.x<=resolution.x,"the tool bar fits %s" % resolution)
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
	if not builder.is_active() or builder._kind!="stone":
		builder._on_tool_requested("construct_stone")
	for reverse in [false,true]:
		var start := Vector3(80.5,21,80.5) if not reverse else Vector3(119.5,21,119.5)
		var finish := Vector3(119.5,21,119.5) if not reverse else Vector3(80.5,21,80.5)
		var a := camera.unproject_position(start)
		var b := camera.unproject_position(finish)
		_move(a); _mouse_button(a,true); _move(b)
		var preview: Array = builder._preview_cells.duplicate()
		_expect(preview.size()==32*32,"stone preview spans 32 by 32, reverse=%s" % reverse)
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
	# Asking for the active tool again would toggle it off.
	if not builder.is_active() or builder._kind!="stone": builder._on_tool_requested("construct_stone")
	await _frames(3)


## Copy takes the stone wall (x 43–47, y 21–24, z 42) with the real mouse, and a blueprint is
## placed with a click (owner's playtest, 2026-10-26: the object explorer took those clicks, as
## it knew only the scene's own tools). A drag begun on the wall's face starts on the ground.
func _check_copy_wall() -> void:
	var copy: Node = builder.blueprints
	var library: Node = root.get_node("BlueprintLibrary")
	var saved: Array[String] = []
	copy.blueprint_saved.connect(func(id: String): saved.append(id))
	explorer.clear_selection()
	dock.tool_requested.emit("construct_copy")
	await _frames(2)
	_expect(copy.is_active() and not builder.is_active() and explorer._click_tool_active(),"Copy is on, and the object explorer leaves its clicks to it")
	_expect(not bool(copy.tool_bar_state().get("undo", true)),"Copy makes no orders, so its bar has no Undo")
	var wheel := InputEventMouseButton.new()
	wheel.position = camera.unproject_position(Vector3(42.5,21,43.5)); wheel.button_index = MOUSE_BUTTON_WHEEL_UP; wheel.pressed = true; wheel.alt_pressed = true
	root.push_input(wheel,true)
	_expect(copy._height==4,"Alt + wheel raises Copy's box to the wall's height")
	# From the ground in front of the wall, then from the wall's own face.
	for start: Vector3 in [Vector3(42.5,21,43.5),Vector3(43.5,22.5,43)]:
		var a := camera.unproject_position(start)
		var b := camera.unproject_position(Vector3(47.5,21,41.5))
		_move(a); _mouse_button(a,true)
		_expect(copy._anchor.y==21,"the box stands on the ground from %s: %s" % [start,copy._anchor])
		_move(b); _mouse_button(b,false)
		var blueprint: Dictionary = library.get_blueprint(saved.back()) if not saved.is_empty() else {}
		_expect(not blueprint.is_empty() and blueprint.size==Vector3i(5,4,1) and (blueprint.blocks.get("stone",[]) as Array).size()==20,
			"a real drag copies the whole wall from %s: %s" % [start,blueprint.get("size","nothing")])
		for id: String in saved: library.delete(id)
		saved.clear()
		manager.close("blueprints")
		root.gui_release_focus()
		await _frames(2)
	# Placing: a click plans the stone hut on open ground; one Undo takes it back.
	var receipts: Array = []
	copy.order_created.connect(func(receipt: Dictionary): receipts.append(receipt))
	dock.tool_requested.emit("blueprint_place")
	copy.place("starter:stone_hut")
	_expect(copy.is_placing() and explorer._click_tool_active(),"placing is on, and the object explorer leaves its clicks to it")
	var spot := camera.unproject_position(Vector3(44.5,21,45.5))
	_move(spot); _mouse_button(spot,true); _mouse_button(spot,false)
	_expect(receipts.size()==1 and copy.order_is_pending(receipts[0]),"a real click plans the blueprint")
	if not receipts.is_empty(): _expect(copy.undo_order(receipts[0])==39,"one Undo takes the stone hut's 39 blocks back")
	copy.deactivate()
	builder._on_tool_requested("construct_stone")
	await _frames(2)


## On a shelf of two rows, a button's hover card stands above the whole shelf, never over the
## row above it (doc 23, "Copy and Blueprints").
func _check_shelf_card() -> void:
	var layer := CanvasLayer.new()
	scene.add_child(layer)
	var shelf := Control.new()
	shelf.position = Vector2(200, 300)
	shelf.size = Vector2(300, 140)
	layer.add_child(shelf)
	var button := preload("res://scripts/ui/DockIconButton.gd").new()
	button.setup({"label": "Copy", "tooltip": "Drag a box round what to copy."}, null)
	button.shelf = shelf
	shelf.add_child(button)
	button.position = Vector2(40, 72)
	button.size = Vector2(64, 64)
	await _frames(2)
	button._hovered = true
	button._show_info()
	await _frames(3)
	_expect(button._info != null and button._info.visible and button._info.get_global_rect().end.y <= shelf.get_global_rect().position.y,
		"a shelf's hover card never covers the shelf")
	layer.queue_free()
	await _frames(1)


func _check_construction_menu() -> void:
	var original_size := root.size
	for resolution in [Vector2i(960,540), Vector2i(1280,720), Vector2i(2560,1440)]:
		root.size = resolution
		await _frames(8)
		var bounds := Rect2(Vector2.ZERO, Vector2(resolution))
		_expect(not dock._panel_header.visible and not dock._panel_rail_back.visible, "Construction uses an icon-only root rail")
		_expect(dock._panel_body.get_child_count() == 4, "Construction keeps Build, Shapes, Copy and Blueprints")
		_expect(is_equal_approx(dock._panel_container.position.x + 8, dock._button_by_target.construction.get_global_rect().position.x), "Construction anchors above its dock icon")
		_expect(bounds.encloses(dock._panel_container.get_global_rect()) and dock._panel_container.get_global_rect().end.y <= dock._dock_panel.position.y - 8, "Construction fits above dock")
		for button in dock._panel_body.get_children():
			_expect(button.text.is_empty() and button.icon.resource_path.begins_with("res://assets/ui/icons/") and not button.planned, "live Construction entries use Hearthblock icons (doc 259)")
			_expect(is_equal_approx(button.size.x, button.size.y) and button.size.x >= 56, "Construction icons stay square")
		# The menu fits its icons: no room kept aside for a scrollbar (owner, 2026-10-26).
		var menu_rect: Rect2 = dock._panel_container.get_global_rect()
		var left: float = dock._panel_body.get_child(0).get_global_rect().position.x - menu_rect.position.x
		var right: float = menu_rect.end.x - dock._panel_body.get_child(dock._panel_body.get_child_count() - 1).get_global_rect().end.x
		_expect(absf(left - right) <= 1.0, "Construction's icons sit evenly in the menu at %s: %.1f px left, %.1f px right" % [resolution, left, right])
		await _capture_menu_art("construction_%d" % resolution.x)
		var stone = dock._panel_body.get_child(0)
		_move(Vector2(12,120))
		await _frames(3)
		_move(stone.get_global_rect().get_center())
		await create_timer(.4).timeout
		_expect(stone._info != null and stone._info.visible and stone.description.contains("1 rough stone"), "stone hover explains real material cost")
		await _capture_menu_art("stone_hover_%d" % resolution.x)
	root.size = original_size
	await _frames(8)
	_expect(builder.orders.is_empty(), "browsing the menu alone never creates construction work")


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
	var compact: Control = explorer.get_compact_panel()
	_expect(explorer.is_object_selected(builder,id) and compact.visible,"active construction tool opens clicked plan")
	_expect(builder.orders.size()==1 and not builder._dragging,"inspecting a plan does not start another designation")
	_expect(compact._status.text.ends_with("0 / 3 rough stone delivered"),"panel shows delivered stone")
	_expect(explorer._outline.visible and explorer._outline_bounds.size.is_equal_approx(Vector3(3,1,1)),"selected area has a visible outline")
	await _capture_ui("construction_inspector")
	var frame: Rect2 = compact._frame.get_global_rect()
	_click(Vector2(frame.position.x+40,frame.end.y-12))
	_expect(builder.orders.size()==1 and explorer._object_id==id,"panel consumes UI clicks")
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
	# A roof in front of the ray blocks selection and Ctrl erasing.
	var direction := camera.project_ray_normal(point)
	var roof := Vector3i((Vector3(45.5,21.5,42.5)-direction*4).floor())
	world.set_block(roof.x,roof.y,roof.z,blocks.get_id("base:terrain:rock:rock01"))
	explorer.clear_selection()
	_expect(not explorer.select_at_screen(point),"terrain occludes construction plans")
	builder._on_tool_requested("construct_build")
	_mouse_button(point,true,true)
	_mouse_button(point,false,true)
	builder._on_tool_requested("")
	_expect(builder.orders.has(id) and builder.orders[id].cells.size()==3,"terrain protects hidden plans from Ctrl erasing")
	world.set_block(roof.x,roof.y,roof.z,blocks.AIR_ID)
	# Lowering the slice hides and closes the selected plan.
	_click(point)
	renderer.slice_y = 20
	explorer._on_slice_changed(20)
	_expect(not compact.visible and not explorer.select_at_screen(point),"hidden plans cannot be selected and close their panel")
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
		_expect(Rect2(Vector2.ZERO,Vector2(size)).encloses(compact.get_global_rect()),"construction panel fits %s" % size)
		await _capture_ui("construction_inspector_%d" % size.x)
	_click(compact.get_action_button("cancel").get_global_rect().get_center())
	await _frames(3)
	_expect(builder.orders.is_empty() and not compact.visible,"Cancel construction removes the selected order and closes the panel")
	# A disappearing/completed area also closes automatically, without a click.
	var finishing: int = builder.create_order(cells)
	explorer.select_object(builder,finishing)
	builder.cancel_order(finishing)
	# Headless frame throughput is not a clock; explicitly cross the UI timer.
	explorer._process(explorer.REFRESH_SECONDS+.01)
	_expect(not compact.visible,"removed plan closes on periodic refresh")
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
