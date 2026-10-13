extends "res://tools/UndergroundWorldReview.gd"

func _run() -> void:
	create_timer(120).timeout.connect(func(): push_error("Construction world review timed out"); quit(1))
	root.get_node("SaveManager").configure_storage_for_testing("user://construction_world_review")
	root.get_node("SaveManager").set_process(false)
	root.get_node("WorldClock").set_paused(true)
	root.get_node("TaskManager").set_process(false)
	root.size = Vector2i(1400,900)
	node_added.connect(func(node: Node):
		if node.name=="Renderer" and node.get_script()!=null: node.set("world_seed",1234))
	change_scene_to_file("res://scenes/main/debug_world.tscn")
	await process_frame
	generator = root.get_node("WorldGenerator")
	while not generator.get_streaming_stats().get("maps_ready",false) or generator.is_generating(): await process_frame
	renderer = current_scene.get_node("Renderer")
	field = renderer.underground_lighting
	var entrance := _find_cliff()
	_expect(entrance.x>=0,"native cliff fixture exists")
	if entrance.x<0: quit(1); return
	var mining = current_scene.get_node("MiningDesignationController")
	var cells: Array[Vector3i] = []
	for x in range(1,14):
		for z in range(6):
			for y in range(1,5): cells.append(entrance+Vector3i(x,y,z))
	mining._mine_blocks_world(cells)
	var builder = current_scene.get_node("ConstructionController")
	var saved := []
	for z in range(4):
		for y in range(1,5):
			var cell := entrance+Vector3i(5,y,z)
			saved.append({"cell":[cell.x,cell.y,cell.z],"block":String(root.get_node("BlockRegistry").get_key(generator.construction_stone_id(cell)))})
	builder.restore_state({"next_id":1,"built":saved,"orders":[]})
	current_scene.get_node("SliceController").restore_state({"active":true,"seeded":true,"slice_y":entrance.y+4,"last_slice_y":entrance.y+4})
	var rig = current_scene.get_node("CameraRig")
	rig.set_process(false)
	var camera: Camera3D = rig.camera_node
	camera.reparent(current_scene)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 23
	camera.position = Vector3(entrance)+Vector3(-12,32,28)
	camera.look_at(Vector3(entrance)+Vector3(6,1,2))
	camera.current = true
	root.get_node("SkyController").set_process(false)
	root.get_node("SkyController")._update(12.0)
	var furniture = current_scene.get_node("FurniturePlacementController")
	var key := "base:furniture:wall_torch"
	furniture._install(key,furniture.get_defs()[key],entrance+Vector3i(3,0,0),0)
	await _settle()
	_expect(builder._solid.mesh!=null and builder._solid.material_override==renderer._material,"built stone uses live terrain lighting")
	_expect(builder.built.size()==16,"backfill provenance survives live scene updates")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tmp/construction_20261012/native/world.png")
	for failure: String in failures: push_error(failure)
	print("CONSTRUCTION_WORLD_OK" if failures.is_empty() else "CONSTRUCTION_WORLD_FAIL")
	quit(0 if failures.is_empty() else 1)
