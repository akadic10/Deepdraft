extends "res://scripts/tests/WorkerCraftingTest.gd"

const BED := "base:furniture:log_bed"
const BED_ITEM := "base:resources:furniture:log_bed"
var rooms
var bed
var door
var lamp
var room_probe := Vector3i(62,21,62)
var room_meshes: Array[Node3D] = []

func _run() -> void:
	create_timer(150).timeout.connect(func(): push_error("Bedroom timeout"); quit(1))
	await _setup_crafting_fixture()
	rooms = root.get_node("RoomManager")
	rooms.clear_runtime_state()
	furniture._install(BENCH,furniture.get_defs()[BENCH],Vector3i(45,20,42),0)
	drops.spawn_drop(PINE,4,Vector3i(42,21,42))
	_expect(await _completed(crafting.queue_order("base:recipe:worker:log_bed",1)),"starter worker crafts log bed")
	_expect(_count(BED_ITEM)==1 and _count(PINE)==0,"four timber become one packed bed")
	_expect(dock._place_catalog._tiles.has(BED),"log bed available in Place catalog")
	_build_bedroom()
	door = _put("door",Vector3i(63,20,60))
	_expect(_room_data().get("room_type")=="room","sealed door alone is a room")
	furniture.activate_for(BED,true)
	furniture._yaw = 0
	furniture._hover_cell = Vector3i(62,20,64)
	_expect(furniture._placement_valid(furniture._hover_cell),"log bed fits clear floor")
	furniture._confirm_ghost()
	furniture.deactivate()
	_expect(await _installed(BED),"worker physically delivers and installs bed")
	bed = furniture._installed.values().filter(func(p): return p.furniture_key==BED)[0]
	_expect(bed.material_id=="base:material:pine" and _count(BED_ITEM)==0,"installed bed retains timber and consumes crate")
	_expect(_room_data().get("room_type")=="room","bed without light does not create bedroom")
	var outside = _put("wooden_torch",Vector3i(62,20,58))
	_expect(_room_data().get("room_type")=="room","outside light does not qualify")
	furniture._teardown_installed(outside.installed_id,false)
	lamp = _put("wooden_torch",Vector3i(68,20,64))
	var room := _room_data()
	_expect(room.get("room_type")=="bedroom" and room.bed_count==1 and room.light_count==1 and room.door_cells.size()==1,"bed + door + light + sealed enclosure creates bedroom")
	for key in ["wooden_torch","wall_torch","campfire"]:
		var def: Dictionary = furniture.get_defs()["base:furniture:"+key]
		_expect(is_equal_approx(float(def.light_source.energy),2.6 if key=="wooden_torch" else 3.2),"doubled firelight: "+key)
	# Every required component must remain present.
	furniture._teardown_installed(lamp.installed_id,false)
	_expect(_room_data().get("room_type")=="room","light removal revokes bedroom")
	lamp = _put("wooden_torch",Vector3i(68,20,64))
	furniture._teardown_installed(door.installed_id,false)
	_expect(_room_data().is_empty(),"door removal unseals bedroom")
	door = _put("door",Vector3i(63,20,60))
	world.set_block(64,25,64,blocks.AIR_ID)
	_expect(_room_data().is_empty(),"roof breach unseals bedroom")
	world.set_block(64,25,64,blocks.get_id("base:terrain:rock:rock01"))
	_expect(_room_data().get("room_type")=="bedroom","repair restores bedroom")
	worker.stop_walking()
	worker.position = Vector3(63.5,21,58.5)
	worker._begin_sleep()
	var remaining: float = worker._sleep_hours_left
	worker._process(.1)
	_expect(worker._sleep_hours_left==remaining,"bed search does not refill sleep")
	_expect(await _sleep_in_bed(worker),"dwarf reaches and sleeps in bed")
	_expect(bed.sleep_owner==worker.dwarf_id and not worker.current_cell() in bed.cells,"exclusive claim with real access floor")
	_expect(root.get_node("NavGrid").is_walkable(worker.current_cell()),"sleep root remains navigable")
	_expect(worker._head.rotation.x< -1.3,"bed sleeper lies down")
	var saved: Dictionary = worker.serialize_state()
	worker.restore_saved_runtime(saved)
	_expect(worker.is_resting() and bed.sleep_owner==worker.dwarf_id and worker._sleep_hours_left==float(saved.sleep_hours_left),"saved sleeper reconstructs bed pose and claim")
	var factory = load("res://scripts/entities/DwarfFactory.gd").new()
	extra_worker = factory.spawn(factory.generate(142,{}),142)
	scene.add_child(extra_worker)
	extra_worker.position = Vector3(66.5,21,62.5)
	extra_worker.set_process(false)
	tasks.register_dwarf(extra_worker)
	extra_worker._begin_sleep()
	for i in 150:
		extra_worker._process(.1)
		if extra_worker.is_resting(): break
	_expect(extra_worker._rest_behavior.bed_rest.bed==null and bed.sleep_owner==worker.dwarf_id,"second dwarf cannot share claimed bed")
	extra_worker._wake_up()
	extra_worker.visible = false
	if "--capture" in OS.get_cmdline_user_args(): await _capture_bed()
	worker._rest_behavior.begin_waking()
	for i in 15: worker._process(.1)
	_expect(not worker.is_sleeping() and bed.sleep_owner<0,"wake releases bed")
	worker._begin_sleep()
	_expect(await _sleep_in_bed(worker),"bed reused after waking")
	bed.set_uninstall(true)
	for i in 8: worker._process(.1)
	_expect(bed.sleep_owner<0 and worker._rest_behavior.bed_rest.bed==null,"uninstall designation releases sleeper safely")
	worker._wake_up()
	furniture._teardown_installed(bed.installed_id,false)
	_expect(_room_data().get("room_type")=="room","bed removal revokes bedroom")
	# Rotation and reload use current definitions and reconstruct derived rooms.
	for yaw in 4:
		bed = _put("log_bed",Vector3i(80+yaw*9,20,60),yaw)
		worker.position = Vector3(bed.origin_cell)+Vector3(1.5,1,-2.5)
		worker._begin_sleep()
		_expect(await _sleep_in_bed(worker),"all bed rotations reachable: %d" % yaw)
		_expect(is_equal_approx(fposmod(worker.rotation.y,TAU),fposmod(float(yaw+1)*PI*.5,TAU)),"sleeper follows headboard rotation")
		if "--capture" in OS.get_cmdline_user_args(): await _capture_rotation(yaw)
		worker._wake_up()
		furniture._teardown_installed(bed.installed_id,false)
	bed = _put("log_bed",Vector3i(62,20,64))
	var state: Dictionary = JSON.parse_string(JSON.stringify(furniture.serialize_state()))
	for id in furniture._installed.keys(): furniture._teardown_installed(id,false)
	rooms.clear_runtime_state()
	furniture.restore_state(state)
	_expect(_room_data().get("room_type")=="bedroom","furniture restore reconstructs bedroom registration")
	var camp_bed = _put("log_bed",Vector3i(80,20,64))
	worker.position = Vector3(81.5,21,62.5)
	worker._begin_sleep()
	_expect(await _sleep_in_bed(worker) and worker._rest_behavior.bed_rest.bed.origin_cell==Vector3i(62,20,64),"a reachable bedroom is preferred over a closer camp bed")
	worker._wake_up()
	# Block every approach to the bedroom; the available camp bed must still win.
	furniture._teardown_installed(furniture._cell_to_installed[Vector3i(63,20,60)],false)
	for x in [63,64]:
		for y in range(21,25): world.set_block(x,y,60,blocks.get_id("base:terrain:rock:rock01"))
	_room_data()
	worker.position = Vector3(70.5,21,58.5)
	worker._begin_sleep()
	_expect(await _sleep_in_bed(worker) and worker._rest_behavior.bed_rest.bed==camp_bed,"unreachable bed does not prevent using another reachable bed")
	# Live removal while sleeping must not retain a freed instance or reset need.
	remaining = worker._sleep_hours_left
	furniture._teardown_installed(camp_bed.installed_id,false)
	await _frames(2)
	worker._process(.1)
	_expect(worker._rest_behavior.bed_rest.bed==null and is_equal_approx(worker._sleep_hours_left,remaining),"removed bed safely restarts search with remaining rest")
	worker._wake_up()
	for failure: String in failures: push_error(failure)
	print("BEDROOM_OK: crafting, installation, material, four requirements, sleep, exclusive claims, wake, removal, rotation and restore" if failures.is_empty() else "BEDROOM_FAIL")
	quit(0 if failures.is_empty() else 1)

func _put(short_key: String, cell: Vector3i, yaw := 0):
	var key := "base:furniture:"+short_key
	furniture._install(key,furniture.get_defs()[key],cell,yaw)
	return furniture._installed[furniture._next_installed_id-1]

func _room_data() -> Dictionary:
	rooms._rebuild_all_rooms()
	return rooms.get_room_at(room_probe)

func _sleep_in_bed(dwarf) -> bool:
	for i in 400:
		dwarf._process(.1)
		if dwarf.is_resting(): return dwarf._rest_behavior.bed_rest.bed!=null
		await process_frame
	return false

func _build_bedroom() -> void:
	var stone: int = blocks.get_id("base:terrain:rock:rock01")
	for x in range(60,70):
		for z in range(60,70):
			for y in range(21,26):
				if x in [63,64] and z==60 and y<25: continue
				if x in [60,69] or z in [60,69] or y==25: world.set_block(x,y,z,stone)

func _capture_bed() -> void:
	for environment: WorldEnvironment in scene.find_children("*","WorldEnvironment",true,false):
		environment.environment.ambient_light_color = Color.WHITE
	for node in [dock,manager]: node.visible = false
	_box(Vector3(65,20.5,65),Vector3(12,1,12),Color("6c7665"))
	_box(Vector3(65,23,69.5),Vector3(10,4,1),Color("57544b"))
	_box(Vector3(60.5,23,65),Vector3(1,4,8),Color("57544b"))
	camera.size = 13
	camera.position = Vector3(77,33,51)
	camera.look_at(Vector3(65,22,64.5))
	await _frames(5)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tmp/bedroom_20261011/bedroom.png")
	manager.visible = true
	var room_tool = load("res://scripts/systems/RoomOverlayController.gd").new()
	room_tool.window_manager_path = NodePath("../Windows")
	room_tool.dock_ui_path = NodePath("../Dock")
	scene.add_child(room_tool)
	room_tool.activate()
	room_tool._select_room(rooms.get_room_id_at(room_probe),room_probe)
	for resolution in [Vector2i(1280,720),Vector2i(960,540)]:
		root.size = resolution
		await _frames(8)
		var rect: Rect2 = room_tool._window_panel.get_global_rect()
		_expect(rect.position.x>=0 and rect.position.y>=0 and rect.end.x<=resolution.x and rect.end.y<=resolution.y,"bedroom inspector fits %s" % resolution)
		_expect(room_tool._window_content._status.text=="BEDROOM · SEALED" and room_tool._window_content._beds.text=="1","room inspector explains bedroom classification")
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tmp/bedroom_20261011/room_ui_%d.png" % resolution.x)
	room_tool.deactivate()
	room_tool.free()
	manager.visible = false
	root.size = Vector2i(1280,720)

func _capture_rotation(yaw: int) -> void:
	_box(Vector3(bed.origin_cell)+Vector3(2,.5,2),Vector3(8,1,8),Color("6c7665"))
	camera.size = 8
	camera.position = bed.node.global_position+Vector3(8,8,10)
	camera.look_at(bed.node.global_position+Vector3.UP)
	await _frames(4)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tmp/bedroom_20261011/rotation_%d.png" % yaw)
	if yaw==0:
		for mesh in worker.find_children("OccludedSilhouette","MeshInstance3D",true,false): mesh.visible = false
		await _frames(3)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tmp/bedroom_20261011/rotation_no_silhouette.png")
		for mesh in worker.find_children("OccludedSilhouette","MeshInstance3D",true,false): mesh.visible = true

func _box(pos: Vector3, size: Vector3, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	mesh.mesh.size = size
	mesh.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mesh.material_override = mat
	scene.add_child(mesh)
	room_meshes.append(mesh)
