extends "res://scripts/tests/BedroomTest.gd"

## Native geometry, existing room topology, lifecycle and player-facing heating.
const HEARTH := "base:furniture:hearth"
const HEATER_ORIGIN := Vector3i(85,20,65)
const SMALL_PROBE := Vector3i(82,21,62)
const OUT := "res://tmp/hearth_room/"
var readings: Array[Dictionary] = []

func _run() -> void:
	create_timer(120).timeout.connect(func(): push_error("Hearth room timeout"); quit(1))
	await _setup_crafting_fixture()
	rooms = root.get_node("RoomManager")
	rooms.clear_runtime_state()
	DirAccess.make_dir_recursive_absolute(OUT)
	_build_small_room()
	_put("door", Vector3i(83,20,60))
	_put("log_bed", Vector3i(81,20,62))
	var definition: Dictionary = furniture.get_defs()[HEARTH]
	for yaw in 4:
		furniture.activate_for(HEARTH)
		furniture._yaw = yaw
		furniture._hover_cell = HEATER_ORIGIN
		furniture._hover_valid = furniture._placement_valid(HEATER_ORIGIN)
		furniture._update_hint(HEATER_ORIGIN)
		_expect(furniture._hover_valid, "heater fits against room walls in rotation %d" % yaw)
		_expect(furniture._visuals.hint_label.text.contains("2 × 2 room heater"), "placement identifies the compact heater")
		var outline: MeshInstance3D = furniture._visuals.preview.get_node_or_null("PlacementArea")
		_expect(outline != null and outline.get_aabb().size.is_equal_approx(Vector3(2,0,2)), "preview shows the full two-by-two base")
		furniture._confirm_ghost()
		var ghost = furniture._ghosts.values()[0]
		var ghost_data: Dictionary = furniture.get_explorer_data("ghost:%d" % ghost.ghost_id)
		_expect(not _rows(ghost_data).has("Temperature"), "queued hearth does not report installed heat")
		var pending := _small_room()
		_expect(int(pending.heat_units) == 0, "queued heater contributes no heat")
		furniture.cancel_ghost(ghost.ghost_id)
		furniture.deactivate()
		var heater = _put("hearth", HEATER_ORIGIN, yaw)
		var room := _small_room()
		_expect(int(room.heat_units) == int(definition.heat_source.heat_units), "multi-cell hearth heats once per rotation")
		_expect(heater.cells.size() == 4, "heater occupies only four floor cells")
		for cell in heater.cells: _expect(not root.get_node("NavGrid").is_walkable(cell), "stone firebox blocks walking")
		_expect(root.get_node("NavGrid").is_walkable(HEATER_ORIGIN + Vector3i(0,0,-1)), "approach beside hearth stays walkable")
		var bounds: AABB = furniture.visual_bounds(definition, HEATER_ORIGIN, yaw)
		_expect(bounds.size.x <= 2.001 and bounds.size.z <= 2.001 and bounds.size.y > 1.6 and bounds.size.y < 2.0, "taller stone silhouette remains within its collision envelope")
		_expect(heater.node.get_node_or_null("PlacementArea") == null, "installed heater has no preview outline")
		var art = heater.node.find_child("hearth_body", true, false)
		var fire = heater.node.find_child("hearth_flame", true, false)
		var body_mesh: MeshInstance3D = preload("res://scripts/components/VoxelShadowSetup.gd").visual_meshes(art)[0]
		_expect(body_mesh.mesh.get_aabb().end.y > fire.mesh.get_aabb().end.y + .4, "low fire sits below the stone back")
		if yaw == 3: break
		furniture._teardown_installed(heater.installed_id, false)
		_expect(int(_small_room().heat_units) == 0, "removal clears heat once")
	var heater = furniture._installed.values().filter(func(piece): return piece.furniture_key == HEARTH)[0]
	# A real small bedroom stays comfortable at the extremes of the calendar.
	for season in ["spring", "summer", "autumn", "winter"]:
		for hour in [2.0, 14.0]:
			clock_node.season = season
			clock_node.day = 1
			clock_node.hour = hour
			rooms._on_hour_changed(int(hour))
			var room: Dictionary = rooms.get_room_at(SMALL_PROBE)
			_expect(rooms.comfort_label(room.temp_c) == "Comfortable", "one hearth keeps the small bedroom comfortable in %s at %.0f" % [season,hour])
			readings.append({"room":"small bedroom", "volume":room.volume, "season":season, "hour":hour, "temperature_c":room.temp_c})
			var info := _rows(furniture.get_explorer_data("installed:%d" % heater.installed_id))
			_expect(String(info.get("Heating room", "")).begins_with("Bedroom"), "inspector identifies heated bedroom")
			_expect(String(info.get("Temperature", "")) == "%.1f°C · Comfortable" % room.temp_c, "inspector follows live temperature")
			_expect(String(info.get("This hearth", "")) == "+%.1f°C" % room.heat_bonus_c, "single heater reports its actual contribution")
	# Minimum thermal mass must also protect tinier rooms in warm weather.
	var tiny := {"heat_units":int(definition.heat_source.heat_units) + 75, "volume":64, "seasonal_influence":.25}
	clock_node.season = "summer"; clock_node.day = 1; clock_node.hour = 14
	rooms._recompute_temp(tiny)
	_expect(rooms.comfort_label(tiny.temp_c) == "Comfortable", "one heater plus a log torch does not overheat a tiny summer bedroom")
	readings.append({"room":"minimum thermal mass with torch", "volume":64, "season":"summer", "hour":14, "temperature_c":tiny.temp_c})
	# Large room and winter demonstrate why contribution depends on volume.
	_build_bedroom()
	_put("door", Vector3i(63,20,60))
	_put("log_bed", Vector3i(61,20,62))
	_put("log_bed", Vector3i(65,20,62))
	var large_heater = _put("hearth", Vector3i(66,20,66),2)
	clock_node.season = "winter"; clock_node.day = 1; clock_node.hour = 2
	var large := _room_data()
	_expect(large.room_type == "barracks" and rooms.comfort_label(large.temp_c) == "Chilly", "one hearth does not claim to heat a large winter barracks comfortably")
	readings.append({"room":"barracks, one hearth", "volume":large.volume, "season":"winter", "hour":2, "temperature_c":large.temp_c})
	_put("hearth", Vector3i(61,20,66),2)
	large = _room_data()
	_expect(rooms.comfort_label(large.temp_c) == "Comfortable", "two hearths warm the winter barracks")
	var large_info := _rows(furniture.get_explorer_data("installed:%d" % large_heater.installed_id))
	_expect(String(large_info.get("This hearth", "")) == "+%.1f°C" % (float(large.heat_bonus_c) / 2.0), "each inspector reports only its own contribution")
	readings.append({"room":"barracks, two hearths", "volume":large.volume, "season":"winter", "hour":2, "temperature_c":large.temp_c})
	# Heat and inspector association are derived again after a roof breach/repair.
	world.set_block(82,25,62,blocks.AIR_ID)
	_expect(_small_room().is_empty(), "roof breach opens room")
	var outside_info: Dictionary = furniture.get_explorer_data("installed:%d" % heater.installed_id)
	_expect(_rows(outside_info).get("Heating") == "No enclosed room" and outside_info.details.contains("Not inside an enclosed room"), "unsealed room explains why the hearth is not heating")
	world.set_block(82,25,62,blocks.get_id("base:terrain:rock:rock01"))
	_expect(not _small_room().is_empty(), "roof repair restores room heating")
	# Restoring existing furniture uses the new model/balance with no extra heat.
	var saved: Dictionary = JSON.parse_string(JSON.stringify(furniture.serialize_state()))
	for id in furniture._installed.keys(): furniture._teardown_installed(id,false)
	rooms.clear_runtime_state()
	furniture.restore_state(saved)
	_expect(int(_small_room().heat_units) == int(definition.heat_source.heat_units), "save restoration rebuilds the current contribution once")
	_expect(JSON.parse_string(JSON.stringify(furniture.serialize_state())) == saved, "placed IDs, origins and rotations survive unchanged")
	heater = furniture._installed.values().filter(func(piece): return piece.furniture_key == HEARTH and piece.origin_cell == HEATER_ORIGIN)[0]
	# Packing and reinstalling outside switches feedback back to no enclosed room.
	var packed_before := _count("base:resources:furniture:hearth")
	furniture.dev_remove_installed(heater.installed_id)
	_expect(int(_small_room().heat_units) == 0, "packed heater contributes no heat")
	_expect(_count("base:resources:furniture:hearth") == packed_before + 1, "packing returns one hearth")
	heater = _put("hearth", Vector3i(49,20,44))
	_expect(_rows(furniture.get_explorer_data("installed:%d" % heater.installed_id)).get("Heating") == "No enclosed room", "outdoor heater reports no room")
	if "--capture" in OS.get_cmdline_user_args(): await _capture_heaters(heater)
	var result := FileAccess.open(OUT + "temperatures.json", FileAccess.WRITE)
	result.store_string(JSON.stringify(readings, "\t"))
	for failure in failures: push_error(failure)
	print("HEARTH_ROOM_OK: rotation, footprint, seasons, heat accounting, room changes, inspection and restore" if failures.is_empty() else "HEARTH_ROOM_FAIL")
	quit(0 if failures.is_empty() else 1)

func _rows(data: Dictionary) -> Dictionary:
	var result := {}
	for row in data.get("rows", []): result[row[0]] = row[1]
	return result

func _small_room() -> Dictionary:
	rooms._rebuild_all_rooms()
	return rooms.get_room_at(SMALL_PROBE)

func _build_small_room() -> void:
	var stone: int = blocks.get_id("base:terrain:rock:rock01")
	for x in range(80,88):
		for z in range(60,68):
			for y in range(21,26):
				if x in [83,84] and z == 60 and y < 25: continue
				if x in [80,87] or z in [60,67] or y == 25: world.set_block(x,y,z,stone)

func _capture_heaters(outside_heater) -> void:
	for node in drops._loose.keys(): drops.take(node); node.free()
	for environment: WorldEnvironment in scene.find_children("*","WorldEnvironment",true,false):
		environment.environment.ambient_light_color = Color("d5e3ed")
	worker.position = Vector3(52.5,21,42.5)
	worker.rotation.y = PI * .15
	var camp = _put("campfire", Vector3i(43,20,44))
	for origin in [Vector3i(44,20,42),Vector3i(44,20,48)]: _put("log_chair",origin)
	for node in [dock,manager]: node.hide()
	camera.size = 14
	camera.position = Vector3(57,32,59)
	camera.look_at(Vector3(48,21.6,45.5))
	await _frames(5)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + "fires_colony.png")
	worker.hide()
	camera.size = 6
	camera.position = outside_heater.node.global_position + Vector3(6,4,8)
	camera.look_at(outside_heater.node.global_position + Vector3(0,.8,0))
	await _frames(5)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + "hearth_close.png")
	for light: DirectionalLight3D in scene.find_children("*","DirectionalLight3D",true,false): light.light_energy = .05
	for environment: WorldEnvironment in scene.find_children("*","WorldEnvironment",true,false): environment.environment.ambient_light_energy = .18
	await _frames(5)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + "hearth_night.png")
	for light: DirectionalLight3D in scene.find_children("*","DirectionalLight3D",true,false): light.light_energy = 1
	for environment: WorldEnvironment in scene.find_children("*","WorldEnvironment",true,false): environment.environment.ambient_light_energy = .7
	manager.show()
	explorer = load("res://scripts/ui/ObjectExplorerController.gd").new()
	explorer.window_manager_path = NodePath("../Windows")
	scene.add_child(explorer)
	explorer._inspector_positioned = true
	explorer._window.position = Vector2(20,30)
	for size in [Vector2i(960,540),Vector2i(1280,720)]:
		root.size = size
		explorer.select_object(furniture,"installed:%d" % outside_heater.installed_id)
		await _frames(6)
		explorer._refresh_selected()
		await _frames(3)
		var rect: Rect2 = explorer._window.get_global_rect()
		_expect(Rect2(Vector2.ZERO,Vector2(size)).encloses(rect), "heater inspector fits viewport %s" % size)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OUT + "outdoor_inspector_%d.png" % size.x)
	# Normal UI with a real heated room, followed by the two placement cards.
	var inside_heater = _put("hearth",HEATER_ORIGIN,2)
	_small_room()
	_box(Vector3(84,20.5,64),Vector3(8,1,8),Color("73786b"))
	_box(Vector3(84,22.5,67.5),Vector3(8,3,1),Color("696b64"))
	_box(Vector3(87.5,22.5,64),Vector3(1,3,8),Color("696b64"))
	worker.position = Vector3(85.5,21,62.5)
	worker.show()
	camera.size = 14
	camera.position = Vector3(72,32,53)
	camera.look_at(Vector3(84,22,64))
	explorer.select_object(furniture,"installed:%d" % inside_heater.installed_id)
	await _frames(8)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + "heated_bedroom.png")
	explorer.clear_selection()
	dock.show()
	dock._open_place_catalog()
	dock._place_catalog.show_all = true
	dock._place_catalog._all_toggle.set_pressed_no_signal(true)
	dock._place_catalog.category = "all"
	for key in [HEARTH,camp.furniture_key]:
		dock._place_catalog._select(key)
		await _frames(5)
		_expect(dock._place_catalog._spec.text == String(furniture.get_defs()[key].placement_label), "Place card explains the footprint")
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OUT + "place_" + String(key).get_slice(":",2) + ".png")
