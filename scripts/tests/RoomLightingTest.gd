extends "res://tools/UndergroundWorldReview.gd"

## Native generated-world regression: a 4x4x4 room off a lit corridor,
## installed walkable door, real slice/room windows and local-light shadows.
const REVIEW := "res://tmp/room_lighting_review/entrance_fix/"
var camera: Camera3D
var room_tool
var furniture
var room_cell: Vector3i
var measures := {}

func _run() -> void:
	create_timer(180).timeout.connect(func(): push_error("Room lighting test timed out"); quit(1))
	if not "/room_lighting_review/" in OS.get_user_data_dir().replace("\\", "/"):
		push_error("Room test requires isolated APPDATA"); quit(1); return
	root.get_node("SaveManager").configure_storage_for_testing("user://room_review")
	root.get_node("SaveManager").set_process(false)
	root.get_node("WorldClock").set_paused(true)
	root.get_node("TaskManager").set_process(false)
	root.size = Vector2i(1600, 1000)
	node_added.connect(func(node: Node):
		if node.name == "Renderer" and node.get_script() != null:
			node.set("world_seed", 1234))
	change_scene_to_file("res://scenes/main/debug_world.tscn")
	await process_frame
	generator = root.get_node("WorldGenerator")
	while not generator.get_streaming_stats().get("maps_ready", false) or generator.is_generating(): await process_frame
	renderer = current_scene.get_node("Renderer")
	field = renderer.underground_lighting
	await _settle()
	var entrance := _find_cliff()
	_expect(entrance.x >= 0, "suitable cliff exists")
	if entrance.x < 0: quit(1); return
	var mined: Array[Vector3i] = []
	for dx in range(1, 18):
		for dz in range(9):
			if dz >= 4 and not (dx >= 10 and dx <= 13 and dz >= 5) and not (dz == 4 and dx in [11, 12]): continue
			for dy in range(1, 5): mined.append(entrance + Vector3i(dx, dy, dz))
	current_scene.get_node("MiningDesignationController")._mine_blocks_world(mined)
	await _settle()
	var slice = current_scene.get_node("SliceController")
	slice.restore_state({"active":true,"seeded":true,"slice_y":entrance.y+4,"last_slice_y":entrance.y+4})
	await _settle()
	var rig = current_scene.get_node("CameraRig")
	rig.set_process(false)
	camera = rig.camera_node
	camera.reparent(current_scene)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 30
	camera.position = Vector3(entrance) + Vector3(4, 44, 20)
	camera.look_at(Vector3(entrance) + Vector3(10, 1, 4))
	camera.current = true
	root.get_node("SkyController").set_process(false)
	root.get_node("SkyController")._update(12.0)
	_expect(current_scene.get_node("WorldEnvironment").environment.fog_enabled, "native scene fog stays enabled")
	furniture = current_scene.get_node("FurniturePlacementController")
	room_tool = current_scene.get_node("RoomOverlayController")
	room_cell = entrance + Vector3i(12, 1, 6)
	var door_id := _install("base:furniture:door", entrance + Vector3i(11, 0, 4))
	await _rooms_settle()
	var manager = root.get_node("RoomManager")
	var room: Dictionary = manager.get_room_at(room_cell)
	_expect(int(room.get("volume", 0)) == 64, "door seals exactly 64 air blocks")
	_expect(field.sky_at(room_cell) == 0, "sealed room has no daylight")
	_expect(furniture._installed[door_id].occupancy_ids.is_empty(), "door remains walkable")
	await _measure("closed_unlit")
	_expect(measures.closed_unlit < .025, "sealed unlit room remains near black with scene fog")
	_expect(float(field._fog_parameters.get("fog_density", 0)) > 0, "lighting materials receive the active scene fog")
	await _check_fog(entrance)
	_install("base:furniture:wall_torch", entrance + Vector3i(10, 0, 3), 2)
	await _rooms_settle()
	await _measure("closed_corridor_torch")
	_expect(measures.closed_corridor_torch <= measures.closed_unlit + .02, "door blocks the corridor torch")
	room_tool.activate()
	room_tool._select_room(manager.get_room_id_at(room_cell), room_cell)
	await _rooms_settle()
	_expect(room_tool._window_content._lighting.text == "No light sources", "room excludes the corridor light")
	await _measure("selected_room")
	_expect(measures.selected_room <= measures.closed_corridor_torch + .055, "selection keeps darkness readable")
	room_tool._window_content._show_tab(1)
	await _review_capture("details")
	room_tool._window_content._show_tab(0)
	# GUI regression: real title drag and remembered position.
	var window: UIWindow = room_tool._window_panel
	var original := window.position
	var center := window._title_bar.get_global_rect().get_center()
	var hover := InputEventMouseMotion.new()
	hover.position = center
	root.push_input(hover, true)
	_mouse(center, true)
	var motion := InputEventMouseMotion.new()
	motion.position = center + Vector2(-45, 25)
	motion.relative = Vector2(-45, 25)
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(motion, true)
	_mouse(motion.position, false)
	_expect(window.position.is_equal_approx(original + Vector2(-45, 25)), "room title drag uses shared window behavior")
	_expect(not window._dragging, "drag ends on release")
	var wm = current_scene.get_node("UIWindowManager")
	_expect(wm.has_saved_position("room_inspector"), "room position is remembered")
	room_tool.deactivate()
	furniture._teardown_installed(door_id, true)
	await _rooms_settle()
	await _measure("open_corridor_torch")
	_expect(measures.open_corridor_torch > measures.closed_corridor_torch + .004, "removing door admits corridor light")
	_expect(manager.get_room_at(room_cell).is_empty(), "removing door breaks the room seal")
	_install("base:furniture:door", entrance + Vector3i(11, 0, 4))
	await _rooms_settle()
	var brazier_id := _install("base:furniture:brazier", entrance + Vector3i(10, 0, 6))
	await _rooms_settle()
	room_tool.activate()
	room_tool._select_room(manager.get_room_id_at(room_cell), room_cell)
	await _rooms_settle()
	_expect(room_tool._window_content._lighting.text == "1 light source", "installed room light is counted separately from heat")
	await _measure("lit_room")
	_expect(measures.lit_room > measures.selected_room + .06, "inside brazier lights selected room")
	furniture._teardown_installed(brazier_id, true)
	await _rooms_settle()
	room_tool._refresh_window()
	_expect(room_tool._window_content._lighting.text == "No light sources", "uninstall refreshes room light count")
	# Slice controls retain their original snap, bounds and remembered-height contract.
	slice._set_slice_y(59)
	slice.step_cell_down(); _expect(slice.get_slice_y() == 55, "cell down snaps four blocks")
	slice.step_single_up(); _expect(slice.get_slice_y() == 56, "fine step moves one block")
	slice.step_cell_up(); _expect(slice.get_slice_y() == 59, "cell up snaps to top")
	slice._set_slice_y(4)
	_expect(slice._down_buttons[0].disabled and slice._down_buttons[1].disabled, "lower bound disables both down controls")
	slice._set_slice_y(127)
	_expect(slice._up_buttons[0].disabled and slice._readout_label.text == "Full world", "upper bound displays full world")
	slice._set_slice_y(entrance.y + 4)
	var remembered: int = slice.get_slice_y()
	slice.deactivate(); slice.activate()
	_expect(slice.get_slice_y() == remembered, "slice remembers its previous level")
	for resolution in [Vector2i(1280,720), Vector2i(960,540)]:
		root.size = resolution
		await _rooms_settle()
		await _review_capture("panels_%d" % resolution.x)
		for id in ["room_inspector", "slice_palette"]:
			var panel: UIWindow = wm.get_ui_window(id)
			_expect(panel.get_global_rect().end.x <= resolution.x and panel.get_global_rect().end.y <= resolution.y, "panel fits " + id + " at " + str(resolution))
	var report := {"failures":failures,"luminance":measures,"entrance":str(entrance)}
	FileAccess.open(REVIEW + "checks.json", FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print("ROOM_LIGHTING_TEST: ", JSON.stringify(report))
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _find_cliff() -> Vector3i:
	for z in range(256,768,4):
		for x in range(256,768):
			var y: int = generator.get_surface_y(x,z)
			if y < 8 or y > 105 or generator.get_surface_y(x+1,z) < y+7: continue
			var valid := true
			for dx in range(1,19):
				for dz in range(10):
					if generator.get_surface_y(x+dx,z+dz) < y+7: valid = false
			if valid: return Vector3i(x,y,z)
	return Vector3i(-1,-1,-1)

func _install(key: String, origin: Vector3i, yaw: int = 0) -> int:
	var id: int = furniture._next_installed_id
	furniture._install(key, furniture.get_defs()[key], origin, yaw)
	var node: Node3D = furniture._installed[id].node
	for animation in node.find_children("FlameAnimation", "Node", true, false): animation.set_process(false)
	return id

func _rooms_settle() -> void:
	await _settle()
	root.get_node("RoomManager")._rebuild_all_rooms()
	if room_tool != null and room_tool.is_active(): room_tool._rebuild_overlays()
	for i in range(8): await process_frame

func _review_capture(label: String) -> Image:
	for i in range(8): await process_frame
	await RenderingServer.frame_post_draw
	var capture := root.get_texture().get_image()
	capture.save_png(REVIEW + label + ".png")
	return capture

func _measure(label: String) -> void:
	var capture := await _review_capture(label)
	measures[label] = _sample(capture, Vector3(room_cell) + Vector3(.5,.02,.5))

func _sample(capture: Image, point: Vector3) -> float:
	var screen := Vector2i(camera.unproject_position(point))
	var total := 0.0
	for dx in range(-2,3):
		for dy in range(-2,3): total += capture.get_pixel(screen.x+dx,screen.y+dy).get_luminance()
	return total / 25.0

func _check_fog(entrance: Vector3i) -> void:
	var production: Shader = field.SHADER
	var automatic_fog := Shader.new()
	automatic_fog.code = production.code.replace("FOG = atmosphere(VERTEX,normalize((INV_VIEW_MATRIX*vec4(VERTEX,0.0)).xyz));", "")
	var outside := Vector3(entrance) + Vector3(16.5, 5.02, 9.5)
	var capture := await _review_capture("fog_current")
	measures.outdoor_fog_current = _sample(capture, outside)
	for material: ShaderMaterial in field._material_cache.values():
		material.shader = automatic_fog
		material.set_shader_parameter("readability_floor", .05)
	await _measure("legacy_fog_room")
	capture = await _review_capture("fog_legacy")
	measures.outdoor_fog_legacy = _sample(capture, outside)
	_expect(absf(measures.outdoor_fog_current - measures.outdoor_fog_legacy) < .025, "outdoor fog retains its appearance")
	for material: ShaderMaterial in field._material_cache.values():
		material.shader = production
		material.set_shader_parameter("readability_floor", field.readability)
	# The camera is outside the mountain in slice view. Moving it back must
	# not add more atmospheric light to the physical room below the hidden roof.
	var original := camera.position
	var target := Vector3(entrance) + Vector3(10, 1, 4)
	camera.position = target + (original - target) * 2.0
	await _measure("closed_unlit_far_camera")
	_expect(absf(measures.closed_unlit_far_camera - measures.closed_unlit) < .01, "camera distance cannot brighten sealed rooms")
	for hour in [12.0, 0.0]:
		root.get_node("SkyController")._update(hour)
		field._sync_fog()
		var label := "far_day" if hour == 12.0 else "far_night"
		capture = await _review_capture(label)
		var current_fog := _sample(capture, outside)
		for material: ShaderMaterial in field._material_cache.values(): material.shader = automatic_fog
		capture = await _review_capture(label + "_legacy")
		var legacy_fog := _sample(capture, outside)
		measures[label + "_outdoor_delta"] = absf(current_fog - legacy_fog)
		_expect(absf(current_fog - legacy_fog) < .025, "exposed terrain retains atmosphere " + label)
		for material: ShaderMaterial in field._material_cache.values(): material.shader = production
	root.get_node("SkyController")._update(12.0)
	field._sync_fog()
	camera.position = original

func _mouse(point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	root.push_input(event, true)
