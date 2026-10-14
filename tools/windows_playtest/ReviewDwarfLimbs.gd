extends "res://scripts/tests/SaveManagerRoundTripTest.gd"

const OUT := "res://tmp/dwarf_limb_lighting_20261013/"

func _run() -> void:
	if not "/dwarf_limb_lighting_20261013/" in OS.get_user_data_dir().replace("\\","/"):
		_fail("Limb review requires isolated APPDATA"); return
	create_timer(180).timeout.connect(func(): _fail("Limb review timeout"))
	root.size=Vector2i(1600,900)
	_save_manager=root.get_node("SaveManager")
	_world_generator=root.get_node("WorldGenerator")
	_world_clock=root.get_node("WorldClock")
	_save_manager.configure_storage_for_testing("user://save_copy")
	_save_manager.set_process(false)
	var read: Dictionary=_save_manager._read_snapshot("user://save_copy/quicksave.json")
	if not read.get("ok",false): _fail("Copied save invalid"); return
	_world_generator.world_seed=int(read.snapshot.world_seed)
	_world_clock.set_paused(true)
	node_added.connect(func(node: Node):
		if node.name=="Renderer" and node.get_script()!=null: node.world_seed=int(read.snapshot.world_seed))
	change_scene_to_file("res://scenes/main/debug_world.tscn")
	await process_frame
	await process_frame
	if not await _wait_for_world_ready(WORLD_TIMEOUT_MSEC): _fail("World timeout"); return
	_save_manager.set_process(true)
	_save_manager.load_finished.connect(func(ok: bool, backup: bool):
		_on_load_finished(ok,backup)
		_world_clock.set_paused(true),CONNECT_ONE_SHOT)
	if not _load_through_dock("load_game") or not await _wait_for_load(LOAD_TIMEOUT_MSEC) or not _load_succeeded:
		_fail("Copied save load failed"); return
	_save_manager.set_process(false)
	_world_clock.set_process(false)
	var tasks=root.get_node("TaskManager")
	tasks.set_process(false)
	var selected
	for actor in tasks._agents.values():
		actor.set_process(false)
		if actor.dwarf_name=="Ulvrek": selected=actor
	if selected==null: _fail("Ulvrek not found in copied save"); return
	selected.stop_walking()
	selected._reset_part_offsets()
	# Face the close-up camera without changing the restored location/appearance.
	selected.rotation.y=0.0
	var rig=current_scene.get_node("CameraRig")
	rig.set_process(false)
	var camera: Camera3D=rig.camera_node
	camera.reparent(current_scene)
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.global_position=selected.global_position+Vector3(0,6,9)
	camera.look_at(selected.global_position+Vector3(0,1.5,0))
	camera.size=8.0
	for i in 240: await process_frame
	var report: Dictionary={"name":selected.dwarf_name,"position":selected.global_position,"skin":selected.appearance.skin_tone,"limbs":[]}
	for part in [selected._hand_l,selected._hand_r,selected._foot_l,selected._foot_r]:
		var mesh: MeshInstance3D=part.find_children("*","MeshInstance3D",true,false)[0]
		var material:=mesh.get_active_material(0) as ShaderMaterial
		if material==null or mesh.global_basis.determinant()<=0.0: _fail("Invalid rendered limb "+str(part.name)); return
		report.limbs.append({"part":part.name,"tint":material.get_shader_parameter("tint"),"determinant":mesh.global_basis.determinant()})
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT+"ulvrek.png")
	var file:=FileAccess.open(OUT+"copied_save_review.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	print("COPIED_SAVE_DWARF_LIMBS_OK ",report)
	quit()
