extends "res://scripts/tests/RoomLightingTest.gd"

const BEDROOM_OUTPUT := "res://tmp/personal_bedroom_20261011/"

func _run() -> void:
	create_timer(170).timeout.connect(func(): push_error("Bedroom lighting timeout"); quit(1))
	DirAccess.make_dir_recursive_absolute(BEDROOM_OUTPUT)
	root.get_node("SaveManager").configure_storage_for_testing("user://bedroom_lighting")
	root.get_node("SaveManager").set_process(false)
	root.get_node("WorldClock").set_paused(true)
	root.get_node("TaskManager").set_process(false)
	root.size = Vector2i(1280,900)
	node_added.connect(func(node: Node):
		if node.name=="Renderer" and node.get_script()!=null: node.set("world_seed",1234))
	change_scene_to_file("res://scenes/main/debug_world.tscn")
	await process_frame
	generator = root.get_node("WorldGenerator")
	while not generator.get_streaming_stats().get("maps_ready",false) or generator.is_generating(): await process_frame
	renderer = current_scene.get_node("Renderer")
	field = renderer.underground_lighting
	await _settle()
	var entrance := _find_cliff()
	_expect(entrance.x>=0,"fixture has underground cliff")
	if entrance.x<0: quit(1); return
	var mined: Array[Vector3i] = []
	for dx in range(1,18):
		for dz in range(12):
			if dz>=4 and not (dx>=10 and dx<=13 and dz>=5) and not (dz==4 and dx in [11,12]): continue
			for dy in range(1,5): mined.append(entrance+Vector3i(dx,dy,dz))
	current_scene.get_node("MiningDesignationController")._mine_blocks_world(mined)
	await _settle()
	current_scene.get_node("SliceController").restore_state({"active":true,"seeded":true,"slice_y":entrance.y+4,"last_slice_y":entrance.y+4})
	await _settle()
	var rig = current_scene.get_node("CameraRig")
	rig.set_process(false)
	camera = rig.camera_node
	camera.reparent(current_scene)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 13
	camera.position = Vector3(entrance)+Vector3(13,35,-8)
	camera.look_at(Vector3(entrance)+Vector3(12,1,8))
	camera.current = true
	root.get_node("SkyController").set_process(false)
	root.get_node("SkyController")._update(12.0)
	furniture = current_scene.get_node("FurniturePlacementController")
	room_tool = current_scene.get_node("RoomOverlayController")
	room_cell = entrance+Vector3i(10,1,8)
	_install("base:furniture:door",entrance+Vector3i(11,0,4))
	_install("base:furniture:log_bed",entrance+Vector3i(11,0,8),1)
	await _rooms_settle()
	var room: Dictionary = root.get_node("RoomManager").get_room_at(room_cell)
	_expect(int(room.get("volume",0))==112,"4 by 7 bedroom matches the reported 112-block volume")
	var torch_id := _install("base:furniture:wooden_torch",entrance+Vector3i(10,0,5),1)
	await _rooms_settle()
	var light: OmniLight3D = furniture._installed[torch_id].node.get_node("FurnitureLight")
	var current_range := light.omni_range
	var current_attenuation := light.omni_attenuation
	light.omni_range = 6.0
	light.omni_attenuation = 1.2
	await _light_capture("before",entrance)
	light.omni_range = current_range
	light.omni_attenuation = current_attenuation
	await _light_capture("after",entrance)
	_expect(measures.after_far>measures.before_far+.06,"one torch visibly brightens the far end beside the bed")
	_expect(measures.after_far>.10 and measures.after_middle>.14,"small bedroom stays readable beyond the bed")
	_expect(measures.after_outside<.025,"closed door still blocks torch light into the corridor")
	_expect(light.shadow_enabled,"bedroom fix preserves physical shadows")
	light.visible = false
	await _light_capture("unlit",entrance)
	_expect(measures.unlit_far<.025,"room without its torch stays dark")
	FileAccess.open(BEDROOM_OUTPUT+"lighting.json",FileAccess.WRITE).store_string(JSON.stringify({"measures":measures,"failures":failures},"  "))
	for failure in failures: push_error(failure)
	print("BedroomLightingTest: ","PASS" if failures.is_empty() else str(failures)," ",measures)
	quit(0 if failures.is_empty() else 1)

func _light_capture(label: String, entrance: Vector3i) -> void:
	await _rooms_settle()
	await RenderingServer.frame_post_draw
	var capture := root.get_texture().get_image()
	capture.save_png(BEDROOM_OUTPUT+label+".png")
	for probe: String in ["far","middle","outside"]:
		var offset := Vector3(10.5,1.02,11.5) if probe=="far" else Vector3(10.5,1.02,8.5) if probe=="middle" else Vector3(11.5,1.02,3.5)
		measures[label+"_"+probe] = _sample(capture,Vector3(entrance)+offset)
