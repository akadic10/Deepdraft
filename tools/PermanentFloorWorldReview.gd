extends "res://tools/UndergroundWorldReview.gd"

const FLOOR_OUTPUT := "res://tmp/permanent_floors_20261012/"

func _run() -> void:
	create_timer(150).timeout.connect(func(): push_error("Floor world review timed out"); quit(1))
	root.get_node("SaveManager").configure_storage_for_testing("user://floor_world_review")
	root.get_node("SaveManager").set_process(false)
	root.get_node("WorldClock").set_paused(true)
	root.get_node("TaskManager").set_process(false)
	root.size = Vector2i(1400,900)
	node_added.connect(func(node: Node):
		if node.name=="Renderer" and node.get_script()!=null: node.set("world_seed",1234))
	change_scene_to_file("res://scenes/main/debug_world.tscn")
	while current_scene == null: await process_frame
	generator = root.get_node("WorldGenerator")
	while not generator.get_streaming_stats().get("maps_ready",false) or generator.is_generating(): await process_frame
	renderer = current_scene.get_node("Renderer")
	field = renderer.underground_lighting
	var entrance := _floor_cliff()
	_expect(entrance.x>=0,"find covered room in generated mountain")
	if entrance.x<0: quit(1); return
	var mining = current_scene.get_node("MiningDesignationController")
	var cells: Array[Vector3i] = []
	var wood: Array[Vector3i] = []
	var stone: Array[Vector3i] = []
	for x in range(3,12):
		for z in range(9):
			for y in range(5): cells.append(entrance+Vector3i(x,y,z))
			if x<8: wood.append(entrance+Vector3i(x,0,z))
			else: stone.append(entrance+Vector3i(x,0,z))
	for x in range(3):
		for z in [3,4]:
			for y in range(1,5): cells.append(entrance+Vector3i(x,y,z))
	mining._mine_blocks_world(cells)
	var builder = current_scene.get_node("ConstructionController")
	var furniture = current_scene.get_node("FurniturePlacementController")
	var wood_id: int = builder.create_order(wood,-1,false,"plank_floor")
	var stone_id: int = builder.create_order(stone,-1,false,"stone_floor")
	_expect(builder.dev_build_order(wood_id)==45 and builder.dev_build_order(stone_id)==36,"all 81 tiles build into excavated layer")
	for piece in [["door",Vector3i(2,0,3),1],["log_bed",Vector3i(4,0,5),0],
		["wall_torch",Vector3i(4,0,0),0],["wall_torch",Vector3i(10,0,0),0],
		["wall_torch",Vector3i(10,0,8),2]]:
		var key: String = "base:furniture:"+String(piece[0])
		furniture._install(key,furniture.get_defs()[key],entrance+Vector3i(piece[1]),int(piece[2]))
	var rooms = root.get_node("RoomManager")
	rooms._rebuild_all_rooms()
	var probe := entrance+Vector3i(6,1,4)
	var room: Dictionary = rooms.get_room_at(probe)
	_expect(not room.is_empty() and room.get("flooring_appeal")==5,"production room reports full flooring bonus")
	var slice = current_scene.get_node("SliceController")
	slice.restore_state({"active":true,"seeded":true,"slice_y":entrance.y+4,"last_slice_y":entrance.y+4})
	var rig = current_scene.get_node("CameraRig")
	rig.set_process(false)
	var camera: Camera3D = rig.camera_node
	camera.reparent(current_scene)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 22
	camera.position = Vector3(entrance)+Vector3(28,38,30)
	camera.look_at(Vector3(entrance)+Vector3(7,0,4))
	camera.current = true
	root.get_node("SkyController").set_process(false)
	root.get_node("SkyController")._update(12.0)
	await _settle()
	_expect(builder._solid.material_override is ShaderMaterial,"floor art uses live underground terrain lighting")
	for i in range(15): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(FLOOR_OUTPUT+"mountain_flooring.png")
	var inspector = current_scene.get_node("RoomOverlayController")
	inspector._selected_cell = probe
	inspector._selected_room_id = rooms.get_room_id_at(probe)
	inspector._open_window()
	inspector._refresh_window()
	for i in range(12): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(FLOOR_OUTPUT+"mountain_flooring_inspector.png")
	FileAccess.open(FLOOR_OUTPUT+"world_checks.json",FileAccess.WRITE).store_string(JSON.stringify({"entrance":str(entrance),"built":int(room.get("finished_floor_tiles",0)),"flooring_appeal":room.get("flooring_appeal",0),"failures":failures},"  "))
	for failure: String in failures: push_error(failure)
	print("FLOOR_WORLD_OK" if failures.is_empty() else "FLOOR_WORLD_FAIL")
	quit(0 if failures.is_empty() else 1)

func _floor_cliff() -> Vector3i:
	for z in range(256,768,4):
		for x in range(256,768):
			var y: int = generator.get_surface_y(x,z+3)
			if y<8 or y>105 or generator.get_surface_y(x+1,z+3)<y+7: continue
			var valid := true
			for dx in range(2,13):
				for dz in range(-1,10):
					if generator.get_surface_y(x+dx,z+dz)<y+7: valid=false
			if valid: return Vector3i(x,y,z)
	return Vector3i(-1,-1,-1)
