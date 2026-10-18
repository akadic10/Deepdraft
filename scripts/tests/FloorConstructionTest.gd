extends "res://scripts/tests/ConstructionInputTest.gd"

const FLOOR_DIR := "res://tmp/permanent_floors_20261012/"
var rooms
var room_tool
var terrain_visual: MeshInstance3D
var floor_cells: Array[Vector3i] = []
var probe := Vector3i(45,21,44)

func _run() -> void:
	create_timer(120).timeout.connect(func(): push_error("Floor test timed out"); quit(1))
	await _setup_crafting_fixture()
	rooms = root.get_node("RoomManager")
	rooms.clear_runtime_state()
	stockpiles.reset_runtime_state()
	root.get_node("WorldGenerator").waterline_map.resize(1024*1024)
	root.get_node("WorldGenerator").waterline_map.fill(-1)
	clock_node.set_paused(true)
	worker.position = Vector3(36.5,21,36.5)
	mining = load("res://scripts/systems/MiningDesignationController.gd").new()
	scene.add_child(mining)
	mining.set_process(false)
	renderer = load("res://scripts/systems/WorldRenderer.gd").new()
	renderer._material = renderer._create_material()
	renderer.slice_y = 23
	builder = load("res://scripts/systems/ConstructionController.gd").new()
	builder.name = "Construction"
	builder.furniture = furniture
	builder.mining = mining
	builder.renderer = renderer
	builder.dock = dock
	scene.add_child(builder)
	furniture._slice_y = 23
	explorer = load("res://scripts/ui/ObjectExplorerController.gd").new()
	explorer.window_manager_path = NodePath("../Windows")
	explorer.click_tool_paths.append(NodePath("../Construction"))
	scene.add_child(explorer)
	explorer._on_slice_changed(23)
	_prepare_room()
	await _frames(5)
	_click(dock._button_by_target.construction.get_global_rect().get_center())
	await _frames(4)
	_click(dock._panel_body.get_child(1).get_global_rect().get_center())
	await _frames(5)
	_expect(dock._panel_title.text=="Permanent floors" and dock._panel_body.get_child_count()==2,"Floors submenu contains both materials")
	await _capture_ui("floor_menu")
	_click(dock._panel_body.get_child(0).get_global_rect().get_center())
	await _frames(3)
	_expect(builder._kind=="plank_floor" and builder._height==1,"plank menu starts a one-layer floor tool")
	var a := camera.unproject_position(Vector3(42.5,20,41.5))
	var b := camera.unproject_position(Vector3(44.5,20,41.5))
	_move(a); _mouse_button(a,true); _move(b); _mouse_button(b,false)
	_expect(builder.orders.size()==1,"real drag plans floor in the excavation")
	if builder.orders.is_empty(): _finish(); return
	var id: int = builder.orders.keys()[0]
	var planned: Array[Vector3i] = builder.orders[id].cells.duplicate()
	_expect(planned.size()==3 and planned[0].y==20,"floor plans restore original support layer")
	_expect(builder.orders[id].source_id==-1 and builder.orders[id]._lease_id==-1,"unavailable profession creates no work source or worker lease")
	for tick in range(20):
		builder._process(.1); tasks._run_scheduler(); worker._process(.1)
	_expect(_finished_floors().is_empty() and builder.orders.has(id),"workers cannot complete preview flooring")
	_expect(_room().flooring_appeal==0,"blue plans give no appeal")
	var point := camera.unproject_position(Vector3(planned[1])+Vector3(.5,.95,.5))
	_click(point)
	await _frames(5)
	_expect(explorer.is_object_selected(builder,id),"floor plan is clickable")
	_expect(explorer._actions.get_child(0).text=="DEV Build","floor inspector exposes DEV Build")
	await _capture_ui("floor_plan")
	# Revalidate at commit: one late blocker remains pending, the rest finishes.
	var handle: int = root.get_node("PlacedEntityRegistry").register_box(planned[1],Vector3i.ONE)
	_click(explorer._actions.get_child(0).get_global_rect().get_center())
	await _frames(5)
	_expect(_finished_floors().size()==2 and builder.orders[id].cells.size()==1,"DEV Build skips a late obstacle without overwriting it")
	root.get_node("PlacedEntityRegistry").unregister(handle)
	_expect(builder.dev_build_order(id)==1 and not builder.orders.has(id),"retry completes only the remaining clear floor")
	_expect(_room().flooring_appeal==0,"partial finished flooring gives no completion bonus")
	_expect(root.get_node("NavGrid").is_walkable(planned[0]),"built floor supports normal walking at original height")
	# Finish a room of mixed wood and stone; every real floor surface counts once.
	var wood: Array[Vector3i] = []
	var stone: Array[Vector3i] = []
	for cell: Vector3i in floor_cells:
		if _finished_floors().has(cell): continue
		if cell.x<46: wood.append(cell)
		else: stone.append(cell)
	var wood_id: int = builder.create_order(wood,-1,false,"plank_floor")
	var stone_id: int = builder.create_order(stone,-1,false,"stone_floor")
	builder.dev_build_order(wood_id)
	builder.dev_build_order(stone_id)
	var room := _room()
	_expect(room.floor_tiles==81 and room.finished_floor_tiles==81 and room.flooring_appeal==5,"mixed 9x9 room earns one +5 completion bonus")
	var bed_key := "base:furniture:log_bed"
	furniture._install(bed_key,furniture.get_defs()[bed_key],Vector3i(42,20,44),0)
	_expect(_room().flooring_appeal==5,"floor beneath furniture still counts")
	_rebuild_terrain_visual()
	builder._on_tool_requested("")
	await _frames(8)
	room_tool = load("res://scripts/systems/RoomOverlayController.gd").new()
	room_tool.dock_ui_path = NodePath("../Dock")
	room_tool.window_manager_path = NodePath("../Windows")
	scene.add_child(room_tool)
	room_tool._slice_y = 23
	room_tool._selected_cell = probe
	room_tool._selected_room_id = rooms.get_room_id_at(probe)
	room_tool._open_window()
	room_tool._refresh_window()
	await _frames(5)
	await _capture_ui("complete_room")
	for size in [Vector2i(960,540),Vector2i(1280,720)]:
		root.size = size
		await _frames(7)
		_expect(Rect2(Vector2.ZERO,Vector2(size)).encloses(room_tool._window_panel.get_global_rect()),"room flooring inspector fits %s" % size)
		await _capture_ui("room_%d" % size.x)
	_save_and_mine(planned[0])
	_validation_tests()
	await _occupied_floor_recovery()
	_expect(tasks.lifecycle_errors().is_empty(),"floor plans leave no orphan leases")
	_finish()

func _room() -> Dictionary:
	rooms._rebuild_all_rooms()
	return rooms.get_room_at(probe)

func _save_and_mine(cell: Vector3i) -> void:
	var spare := Vector3i(52,21,44)
	var id: int = builder.create_order(_cells([spare]),-1,false,"stone_floor")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(builder.serialize_state()))
	var terrain: Array = world.serialize_edits()
	for built_cell: Vector3i in _finished_floors(): world.set_block(built_cell.x,built_cell.y,built_cell.z,blocks.AIR_ID)
	world.restore_terrain({"edits":terrain})
	builder.restore_state(saved)
	_expect(not saved.has("built"),"floor ownership is absent from construction saves")
	_expect(builder.orders[id].construction_kind=="stone_floor" and builder.orders[id]._lease_id<0,"save restores floor type and its worker lock")
	_expect(_room().flooring_appeal==5,"restored floor terrain reconstructs room appeal")
	builder.cancel_order(id)
	var before := _snapshot_units()
	var zone_id: int = mining._create_zone(_cells([cell]))
	_expect(mining.execute_zone_block_mined(zone_id,cell,worker.dwarf_id),"normal mining removes a completed floor")
	_expect(_snapshot_units()==before and not _finished_floors().has(cell),"free DEV flooring yields no free resources")
	_expect(_room().flooring_appeal==0,"mining one tile revokes completion bonus")
	var repair: int = builder.create_order(_cells([cell]),-1,false,"stone_floor")
	builder.dev_build_order(repair)
	_expect(_room().flooring_appeal==5,"repair restores bonus without stacking it")

func _validation_tests() -> void:
	_expect(builder.create_order(_cells([Vector3i(52,21,44)]),-1,false,"unknown")==-1,"unknown construction kinds rejected")
	_expect(not builder.build_reason(floor_cells[0],true,true,"plank_floor").is_empty(),"existing ground/floor cannot be painted over")
	_expect(not builder.build_reason(Vector3i(52,3,44),true,true,"plank_floor").is_empty(),"DEV flooring respects bedrock")
	_expect(not builder.build_reason(Vector3i(52,23,44),true,true,"plank_floor").is_empty(),"floating flooring cannot be planned")
	var water = root.get_node("WaterManager")
	var wet := Vector3i(53,21,44)
	water.flow = load("res://scripts/components/WaterFlow.gd").new()
	water.flow.spans_at = func(_column: Vector2i): return [Vector2i(21,128)]
	water.initialized = true
	water.flow.seed_column(wet,.5,false)
	_expect(builder.create_order(_cells([wet]),-1,false,"stone_floor")<0,"flooring cannot displace water")
	water.flow._set_mass(wet,0)
	water.initialized = false
	var hidden: int = builder.create_order(_cells([Vector3i(52,21,44)]),-1,false,"stone_floor")
	renderer.slice_y = 20
	_expect(builder.dev_build_order(hidden)==0 and builder.orders.has(hidden),"DEV Build cannot commit hidden floors")
	renderer.slice_y = 23
	builder.cancel_order(hidden)

func _occupied_floor_recovery() -> void:
	var tiles: Array[Vector3i] = []
	for x in range(62,65):
		for z in range(60,63): tiles.append(Vector3i(x,20,z))
	mining._mine_blocks_world(tiles)
	for item in drops._loose.keys(): drops.take(item); item.free()
	var id: int = builder.create_order(tiles,-1,false,"plank_floor")
	worker.abort_task()
	worker.position = Vector3(63.5,20,61.5)
	var occupied := Vector3i(63,20,61)
	_expect(builder.dev_build_order(id)==8 and builder.orders[id].cells==[occupied],"DEV Build leaves the dwarf's occupied floor tile pending")
	_expect(world.get_live_block(63,20,61)==blocks.AIR_ID,"construction never buries a dwarf")
	var config: Dictionary = worker._idle_behavior.config.duplicate(true)
	config.start_delay_min_s = .1
	config.start_delay_max_s = .1
	config.pause_min_s = .1
	config.pause_max_s = .1
	config.seat_chance = 0.0
	worker._idle_behavior.config = config
	clock_node.set_paused(false)
	var stepping := false
	for i in range(160):
		worker._process(.05)
		stepping = stepping or worker._idle_behavior.state=="stepping_up"
		if worker.position.y==21 and not worker.is_walking(): break
	_expect(stepping and worker.position.y==21,"idle dwarf walks up out of the unfinished floor tile")
	_expect(root.get_node("NavGrid").is_walkable(worker.current_cell()),"escape finishes on ordinary walkable ground")
	_expect(builder.dev_build_order(id)==1 and not builder.orders.has(id),"DEV Build can finish the vacated tile")
	clock_node.set_paused(true)

func _prepare_room() -> void:
	for child in scene.get_children():
		if child is MeshInstance3D: child.hide()
	for environment: WorldEnvironment in scene.find_children("*","WorldEnvironment",true,false):
		environment.environment.ambient_light_color = Color.WHITE
	var stone: int = blocks.get_id("base:terrain:rock:rock01")
	for x in range(40,51):
		for z in range(39,50):
			for y in range(21,26):
				if x in [44,45] and z==39 and y<25: continue
				if x in [40,50] or z in [39,49] or y==25: world.set_block(x,y,z,stone)
			if x>40 and x<50 and z>39 and z<49:
				floor_cells.append(Vector3i(x,20,z))
	mining._mine_blocks_world(floor_cells)
	for item in drops._loose.keys(): drops.take(item); item.free()
	furniture._install("base:furniture:door",furniture.get_defs()["base:furniture:door"],Vector3i(44,20,39),0)
	camera.size = 19
	camera.position = Vector3(58,46,62)
	camera.look_at(Vector3(45,20,44))
	terrain_visual = MeshInstance3D.new()
	scene.add_child(terrain_visual)
	_rebuild_terrain_visual()
	_expect(not _room().is_empty(),"excavated 9x9 room remains sealed")

func _rebuild_terrain_visual() -> void:
	renderer._rebuild_added_terrain()
	if renderer._added_terrain != null and not renderer._added_terrain.is_inside_tree():
		renderer._added_terrain.reparent(scene, false)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for x in range(37,54):
		for z in range(36,53):
			for y in range(19,24):
				var cell := Vector3i(x,y,z)
				var id: int = world.get_terrain_block(x,y,z)
				if not blocks.is_solid(id) or _finished_floors().has(cell): continue
				for direction: Vector3i in builder.DIRECTIONS:
					var n := cell+direction
					if n.y<=23 and blocks.is_solid(world.get_terrain_block(n.x,n.y,n.z)): continue
					renderer._add_shell_face(cell,-direction,blocks.get_color(id),verts,norms,colors,indices)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=verts; arrays[Mesh.ARRAY_NORMAL]=norms; arrays[Mesh.ARRAY_COLOR]=colors; arrays[Mesh.ARRAY_INDEX]=indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	terrain_visual.mesh = mesh
	terrain_visual.material_override = renderer._material

func _cells(values: Array) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	result.assign(values)
	return result

func _capture_ui(label: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	await _frames(6)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(FLOOR_DIR+label+".png")

func _finish() -> void:
	builder.renderer = null
	renderer.free()
	for failure: String in failures: push_error(failure)
	print("FLOOR_CONSTRUCTION_OK" if failures.is_empty() else "FLOOR_CONSTRUCTION_FAIL")
	quit(0 if failures.is_empty() else 1)

func _finished_floors() -> Dictionary:
	var result := {}
	for cell: Vector3i in floor_cells:
		var id: int = world.get_terrain_block(cell.x,cell.y,cell.z)
		if blocks.get_def(blocks.get_key(id)).get("kind","")=="constructed_floor": result[cell] = id
	return result
