extends "res://scripts/tests/HaulingAnimationTest.gd"

## Real actors, task/cargo transitions, native picking and controls. No saves
## or player window preferences are written by this fixture.
var director
var rig


func _run() -> void:
	create_timer(90).timeout.connect(func(): push_error("Dwarf inspector test timed out"); quit(1))
	await _setup_fixture()
	root.size = Vector2i(1280, 720)
	root.get_node("WorldGenerator")._maps_ready = true
	root.get_node("WorldGenerator").heightmap.resize(1024 * 1024)
	root.get_node("WorldGenerator").heightmap.fill(20)
	root.get_node("WorldGenerator").waterline_map.resize(1024 * 1024)
	root.get_node("WorldGenerator").waterline_map.fill(-1)
	manager = load("res://scripts/ui/UIWindowManager.gd").new()
	manager.name = "Windows"
	scene.add_child(manager)
	manager._layout_loaded = false
	manager._layout.clear()
	rig = load("res://scripts/systems/Camera.gd").new()
	rig.name = "Camera"
	scene.add_child(rig)
	rig.set_process(false)
	director = load("res://scripts/entities/DwarfDirector.gd").new()
	director.name = "Dwarves"
	director.camera_path = NodePath("../Camera")
	director.window_manager_path = NodePath("../Windows")
	scene.add_child(director)
	_adopt_worker()
	furniture = load("res://scripts/systems/FurniturePlacementController.gd").new()
	furniture.name = "Furniture"
	scene.add_child(furniture)
	furniture.set_process(false)
	explorer = load("res://scripts/ui/ObjectExplorerController.gd").new()
	explorer.window_manager_path = NodePath("../Windows")
	explorer.dwarf_director_path = NodePath("../Dwarves")
	explorer.click_tool_paths.append(NodePath("../Furniture"))
	scene.add_child(explorer)
	camera = Camera3D.new()
	scene.add_child(camera)
	camera.current = true
	_aim_above(worker.position)
	await process_frame
	await process_frame
	var screen := camera.unproject_position(worker.position + Vector3(0, 2.5, 0))
	_click(screen)
	await process_frame
	_expect(explorer._provider == director and explorer._object_id == worker, "world click selects the dwarf through shared explorer")
	var panel = explorer._dwarf_panel
	_expect(panel.visible and not explorer._standard_content.visible, "dwarf uses the opt-in Hearth panel")
	_expect(panel._name_label.text == worker.dwarf_name, "actual generated identity")
	_expect(panel._portrait_model.get_child_count() == 2, "portrait contains only static head/body visual copies")
	_expect(tasks._agents.size() == 1, "portrait never registers another worker")
	_click(explorer._window.position + Vector2(120, 16))
	_expect(explorer._object_id == worker, "panel clicks cannot pick through UI")

	# Nearest visible geometry, not the logical 1x1 nav box.
	var behind = load("res://scripts/entities/DwarfFactory.gd").new().spawn(
		load("res://scripts/entities/DwarfFactory.gd").new().generate(142, {}), 142)
	director.add_child(behind)
	director._agents.append(behind)
	behind.position = worker.position - Vector3(0, 6, 0)
	behind.set_process(false)
	_expect(explorer.pick_at_screen(screen).id == worker, "front dwarf wins overlapping silhouettes")
	director._agents.erase(behind)
	behind.free()
	var occlusion_cell := Vector3i(40, 32, 39)
	world.set_block(occlusion_cell.x, occlusion_cell.y, occlusion_cell.z, blocks.get_id("base:terrain:rock:rock01"))
	_expect(explorer.pick_at_screen(screen).is_empty(), "solid rock occludes a dwarf")
	world.set_block(occlusion_cell.x, occlusion_cell.y, occlusion_cell.z, blocks.AIR_ID)
	furniture._active = true
	_expect(not explorer.select_at_screen(screen), "placement tools keep ownership of dwarf clicks")
	furniture._active = false
	director._walk_test = true
	_expect(not explorer.select_at_screen(screen), "walk test keeps click ownership")
	director._walk_test = false

	# Locate/follow leave zoom, pitch, tasks and inventory alone.
	var zoom: float = rig._target_zoom
	var pitch: float = rig._pitch
	explorer._perform_dwarf_action("locate")
	_expect(rig._target_pos == worker.global_position + Vector3(0, 1.5, 0), "Locate centers on the dwarf")
	_expect(rig._target_zoom == zoom and rig._pitch == pitch, "Locate preserves framing")
	_click(panel._follow.get_global_rect().get_center())
	_expect(rig.is_following(worker) and panel._follow.text == "Stop following", "Follow toggles and reflects state")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.position = panel._scroll.get_global_rect().get_center()
	wheel.pressed = true
	root.push_input(wheel, true)
	_expect(rig.is_following(worker) and rig._target_zoom == zoom, "wheel over inspector retains Follow and world zoom")
	var original_position: Vector3 = worker.position
	worker.position.x += 2
	rig._update_follow()
	explorer._process(.01)
	_expect(rig._target_pos.x == worker.position.x, "Follow tracks moving target")
	_expect(is_equal_approx(explorer._outline.global_position.x - explorer._outline_offset.x, worker.position.x), "outline moves every frame")
	worker.position = original_position
	var pan_event := InputEventKey.new()
	pan_event.physical_keycode = KEY_W
	pan_event.keycode = KEY_W
	pan_event.pressed = true
	Input.parse_input_event(pan_event)
	Input.flush_buffered_events()
	rig._handle_pan(.1)
	pan_event = pan_event.duplicate()
	pan_event.pressed = false
	Input.parse_input_event(pan_event)
	Input.flush_buffered_events()
	_expect(not rig.is_following(worker), "keyboard pan releases Follow")
	explorer._perform_dwarf_action("follow")
	rig._apply_zoom(true)
	_expect(not rig.is_following(worker), "world zoom releases Follow")
	explorer._perform_dwarf_action("follow")
	rig._orbiting = true
	var orbit := InputEventMouseMotion.new()
	orbit.relative = Vector2(20, 0)
	rig._handle_orbit_motion(orbit)
	_expect(not rig.is_following(worker), "orbit releases Follow")
	rig._orbiting = false
	explorer._perform_dwarf_action("follow")
	rig._start_drag()
	_expect(not rig.is_following(worker), "middle drag releases Follow")
	rig._dragging = false
	explorer._perform_dwarf_action("follow")
	director._on_slice_changed(19)
	explorer._on_slice_changed(19)
	_expect(not manager.is_open("object_explorer") and not rig.is_following(worker), "slice hides inspector and releases Follow")
	_expect(explorer.pick_at_screen(screen).is_empty(), "slice-hidden dwarf cannot be selected")
	director._on_slice_changed(127)
	explorer._on_slice_changed(127)
	explorer.select_object(director, worker)

	# Real crate trip: carry amount changes only at contact, then at deposit.
	_expect(await _until(worker.TaskPhase.HAUL_PICKUP), "scheduler reaches pickup")
	explorer._refresh_selected()
	_expect(panel._activity.text == "Picking up supplies" and panel._cargo.text == "Empty hands", "pickup before contact still has empty hands")
	worker._process(.35)
	explorer._refresh_selected()
	_expect("12 × Oak Acorn (1 crate)" == panel._cargo.text, "crate displays actual contents and physical count")
	_expect(panel._load.value == 4, "one crate uses four carry points")
	_expect(await _until(worker.TaskPhase.HAUL_TO_ZONE), "scheduler reaches delivery")
	explorer._refresh_selected()
	_expect(panel._activity.text == "Delivering supplies" and "Stockpile 1" in panel._destination.text, "live activity and destination")
	var snapshot: Dictionary = worker.serialize_state()
	var reservations: Dictionary = zone.reserved_cells.duplicate(true)
	for i in range(5): explorer._refresh_selected()
	_expect(snapshot == worker.serialize_state() and reservations == zone.reserved_cells, "inspection never mutates goods or reservations")
	_expect(await _until(worker.TaskPhase.HAUL_DEPOSIT), "scheduler reaches set-down")
	worker._process(1)
	explorer._refresh_selected()
	_expect(panel._cargo.text == "Empty hands" and zone.stored_count() == 12, "deposit clears cargo without losing goods")
	worker.dev_make_tired()
	worker._process(.01)
	explorer._refresh_selected()
	_expect(panel._activity.text == "Sleeping" and "game hours remaining" in panel._explanation.text, "real sleep state is visible")
	var original_portrait = panel._portrait_model
	explorer._refresh_selected()
	_expect(panel._portrait_model == original_portrait, "portrait reused across live refreshes")
	var original_name: String = worker.dwarf_name
	worker.dwarf_name = "Borin Copperbeard Stonehammer XVIII"
	for viewport_size in [Vector2i(1280,720), Vector2i(960,540), Vector2i(1920,1080)]:
		root.size = viewport_size
		await process_frame
		await process_frame
		explorer._refresh_selected()
		await process_frame
		_expect(explorer._window.size.x < viewport_size.x and explorer._window.size.y < viewport_size.y, "inspector fits %s" % viewport_size)
		_expect(panel._follow.get_global_rect().end.y <= viewport_size.y, "actions remain reachable at %s" % viewport_size)
		_expect(panel._cargo.get_combined_minimum_size().x < 352, "cargo wraps within panel")
	worker.dwarf_name = original_name

	# Selecting a standard provider restores legacy presentation and stops follow.
	var key := "base:furniture:wooden_table"
	furniture._install(key, furniture.get_defs()[key], Vector3i(48,20,42), 0)
	var piece = furniture._installed.values()[0]
	explorer._perform_dwarf_action("follow")
	explorer.select_object(furniture, "installed:%d" % piece.installed_id)
	_expect(not rig.is_following(worker) and explorer._standard_content.visible, "switching object releases Follow and restores standard inspector")
	explorer.select_object(director, worker)
	explorer._perform_dwarf_action("follow")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	root.push_input(escape, true)
	_expect(not rig.is_following(worker) and not manager.is_open("object_explorer"), "Escape clears inspector and Follow")
	explorer.select_object(director, worker)
	explorer._perform_dwarf_action("follow")
	manager.close("object_explorer")
	_expect(not rig.is_following(worker), "window close releases Follow")
	explorer.select_object(director, worker)
	explorer._perform_dwarf_action("follow")
	tasks.deregister_dwarf(worker.dwarf_id)
	worker.queue_free()
	await process_frame
	explorer._refresh_selected()
	_expect(not manager.is_open("object_explorer") and not rig.is_following(worker), "removed dwarf clears selection safely")
	await _inspect_furniture_trip()

	if "--capture" in OS.get_cmdline_user_args():
		await _capture_inspector()
	if failures.is_empty():
		print("DWARF_INSPECTOR_OK: visual selection, terrain/slice/tool guards, live cargo/sleep, camera controls, cleanup, responsive UI")
	else:
		for failure: String in failures:
			push_error(failure)
	quit(0 if failures.is_empty() else 1)


func _adopt_worker() -> void:
	director._agents.clear()
	worker.reparent(director)
	director._agents.append(worker)


func _inspect_furniture_trip() -> void:
	var definition: Dictionary = furniture.get_defs()["base:furniture:barrel"]
	await _new_trip(String(definition.item_key), 1)
	_adopt_worker()
	explorer.select_object(director, worker)
	var ghost = load("res://scripts/components/FurnitureGhostComponent.gd").new()
	ghost.setup(50, "base:furniture:barrel", definition, Vector3i(45,20,44), 0)
	ghost.source_id = tasks.allocate_source_id()
	ghost.drop_manager = drops
	tasks.register_work_source(ghost.source_id, ghost)
	var built := [false]
	ghost.install_callback = func(_ghost): built[0] = true
	ghost.update_lease()
	_expect(await _until(worker.TaskPhase.FETCH_PICKUP), "builder starts pickup")
	explorer._refresh_selected()
	_expect(explorer._dwarf_panel._cargo.text == "Empty hands", "reserved packed furniture is not yet carried")
	_expect(await _until(worker.TaskPhase.FETCH_TO_GHOST), "builder carries to placement")
	explorer._refresh_selected()
	_expect(explorer._dwarf_panel._activity.text == "Delivering furniture", "fetch activity is distinct from hauling")
	_expect(String(definition.display_name) in explorer._dwarf_panel._destination.text, "destination names the planned furniture")
	_expect(explorer._dwarf_panel._load.value == 4, "packed furniture uses the real carry cost")
	_expect(await _until(worker.TaskPhase.FETCH_DEPOSIT), "builder reaches installation")
	explorer._refresh_selected()
	_expect(explorer._dwarf_panel._activity.text == "Installing furniture", "installation status follows live work")
	worker._process(1)
	explorer._refresh_selected()
	_expect(built[0] and explorer._dwarf_panel._cargo.text == "Empty hands", "installed furniture leaves the cargo readout")
	explorer.clear_selection()
	tasks.unregister_work_source(ghost.source_id)


func _capture_inspector() -> void:
	await _new_trip(STONE, 1)
	_adopt_worker()
	for i in range(2):
		drops.restore_loose_item(STONE, Vector3(41.5 + i, 21, 40.5))
	_expect(await _until(worker.TaskPhase.HAUL_TO_ZONE), "capture real three-stone carry")
	worker.sleep = .78
	worker.rotation.y = -.25
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("667877")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color.WHITE
	settings.ambient_light_energy = .7
	environment.environment = settings
	scene.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.shadow_enabled = true
	scene.add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var floor_box := BoxMesh.new()
	floor_box.size = Vector3(90, 1, 90)
	floor_mesh.mesh = floor_box
	floor_mesh.position = Vector3(40,20.5,40)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("7c9782")
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	floor_mesh.material_override = material
	scene.add_child(floor_mesh)
	root.size = Vector2i(1280,720)
	camera.position = worker.position + Vector3(10, 10, 15)
	camera.look_at(worker.position + Vector3(3, 1.2, 0))
	explorer.select_object(director, worker)
	explorer._window.position = Vector2(876,32)
	await _save_capture("dwarf_inspector_1280.png")
	root.size = Vector2i(960,540)
	await process_frame
	explorer._refresh_selected()
	await _save_capture("dwarf_inspector_960.png")
	explorer._dwarf_panel._show_tab(1)
	await _save_capture("dwarf_details_960.png")


func _save_capture(filename: String) -> void:
	for i in range(8): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tmp/dwarf_inspector_review/" + filename)
