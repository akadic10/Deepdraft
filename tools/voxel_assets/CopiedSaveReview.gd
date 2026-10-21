extends "res://scripts/tests/SaveManagerRoundTripTest.gd"

## Load recovery copies only. Each run owns a separate profile and output folder.
var output := "res://tmp/settlement_art_20261013/voxel_save/"
var slot := "quicksave"
var failures: Array[String] = []
var report := {}
var source_directory := "res://tmp/voxel_migration_20261018/recovery/player_saves/"
var roundtrip_only := false

func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=").trim_suffix("/")+"/"
		if arg.begins_with("--slot="): slot=arg.trim_prefix("--slot=")
		if arg.begins_with("--source-directory="): source_directory=arg.trim_prefix("--source-directory=").trim_suffix("/")+"/"
		if arg=="--roundtrip-only": roundtrip_only=true
	if slot not in ["quicksave","autosave","quicksave.backup","autosave.backup"] or not "/settlement_art_20261013/" in OS.get_user_data_dir().replace("\\","/"):
		_fail("isolated recovery-copy profile required"); return
	create_timer(420).timeout.connect(func(): _fail("copied-save review timeout"))
	DirAccess.make_dir_recursive_absolute(output)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	root.size=Vector2i(1600,1000)
	_save_manager=root.get_node("SaveManager")
	_world_generator=root.get_node("WorldGenerator")
	_world_clock=root.get_node("WorldClock")
	_save_manager.configure_storage_for_testing("user://voxel_copy")
	_save_manager.set_process(false)
	DirAccess.make_dir_recursive_absolute("user://voxel_copy")
	var source := source_directory+slot+".json"
	var raw := FileAccess.get_file_as_string(source)
	FileAccess.open("user://voxel_copy/quicksave.json",FileAccess.WRITE).store_string(raw)
	var read: Dictionary=_save_manager._read_snapshot("user://voxel_copy/quicksave.json")
	if not read.get("ok",false): _fail("invalid copied input"); return
	var expected: Dictionary=read.snapshot
	report={"slot":slot,"source_sha256":FileAccess.get_sha256(source),"failures":failures,"states":[]}
	_world_generator.world_seed=int(expected.world_seed)
	_world_clock.set_paused(true)
	node_added.connect(func(node: Node):
		if node.name=="Renderer" and node.get_script()!=null: node.world_seed=int(expected.world_seed))
	change_scene_to_file("res://scenes/main/debug_world.tscn")
	await process_frame
	await process_frame
	if not await _wait_for_world_ready(WORLD_TIMEOUT_MSEC): _fail("initial world timeout"); return
	if not await _load_copy(): _fail("first load failed"); return
	var restored := _snapshot()
	_check_source(expected,restored,"initial")
	report["initial_counts"]={"dwarves":restored.scene.dwarves.roster.size(),"furniture":restored.scene.furniture.installed.size(),"goods":_goods(restored.scene)}
	# Save normalized live owner data, then compare the same persisted contracts.
	_save_manager.set_process(true)
	if not _save_manager.request_save() or not await _wait_for_save(): _fail("copy save failed"); return
	if not await _load_copy(): _fail("copy reload failed"); return
	_check_source(restored,_snapshot(),"reload")
	if roundtrip_only:
		FileAccess.open(output+"report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
		for failure in failures: push_error(failure)
		print("VOXEL_COPIED_SAVE_PASS " if failures.is_empty() else "VOXEL_COPIED_SAVE_FAIL ",slot," ",JSON.stringify(report.initial_counts))
		quit(0 if failures.is_empty() else 1)
		return
	var clock_state: Dictionary=_world_clock.serialize_state()
	var rig=current_scene.get_node("CameraRig")
	rig.set_process(false)
	var camera: Camera3D=rig.camera_node
	var center := Vector3.ZERO
	for value in restored.scene.dwarves.roster:
		var at: Array=value.position
		center+=Vector3(at[0],at[1],at[2])
	center/=maxi(1,restored.scene.dwarves.roster.size())
	camera.reparent(current_scene)
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=42
	camera.global_position=center+Vector3(-25,32,38)
	camera.look_at(center+Vector3.UP*1.5)
	camera.make_current()
	for layer in current_scene.find_children("*","CanvasLayer",true,false): layer.visible=false
	# Calendar restore follows the same seasonal queues as loading a real save.
	for state in [["spring",6.0],["summer",14.0],["autumn",19.0],["winter",2.0]]:
		var setting := clock_state.duplicate()
		setting.season=state[0]; setting.day=12; setting.hour=state[1]; setting.paused=true
		var started := Time.get_ticks_msec()
		_world_clock.restore_state(setting)
		await _settle_visuals()
		await _capture("season_"+state[0])
		report.states.append({"season":state[0],"hour":state[1],"settle_ms":Time.get_ticks_msec()-started})
	_world_clock.restore_state(clock_state)
	var slice=current_scene.get_node("SliceController")
	for height in [roundi(center.y),roundi(center.y)-2,roundi(center.y)+3]:
		slice.activate(); slice._set_slice_y(height)
		await _settle_visuals()
		await _capture("slice_"+str(height))
	slice.deactivate()
	await _settle_visuals()
	await _capture("restored_full")
	FileAccess.open(output+"report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	for failure in failures: push_error(failure)
	print("VOXEL_COPIED_SAVE_PASS " if failures.is_empty() else "VOXEL_COPIED_SAVE_FAIL ",slot," ",JSON.stringify(report.initial_counts))
	quit(0 if failures.is_empty() else 1)

func _load_copy() -> bool:
	_load_completed=false; _load_succeeded=false
	_save_manager.set_process(true)
	_save_manager.load_finished.connect(func(ok: bool, backup: bool):
		_on_load_finished(ok,backup)
		_world_clock.set_paused(true),CONNECT_ONE_SHOT)
	if not _save_manager.request_load(): return false
	if not await _wait_for_load(LOAD_TIMEOUT_MSEC) or not _load_succeeded: return false
	_save_manager.set_process(false)
	_world_clock.set_process(false)
	await _settle_visuals()
	return true

func _snapshot() -> Dictionary:
	return JSON.parse_string(JSON.stringify(_save_manager._build_snapshot()))

func _check_source(expected: Dictionary,actual: Dictionary,phase: String) -> void:
	# Milestone 229 deliberately upgraded old one-block workbenches to the
	# approved three-block layout. This is an existing, exact version transition;
	# keep every other field and every later roundtrip comparison strict.
	if phase=="initial":
		expected=expected.duplicate(true)
		for section in ["installed","ghosts"]:
			for piece: Dictionary in expected.scene.furniture[section]:
				if piece.key=="base:furniture:crude_workbench" and piece.get("layout_version",1)==1:
					piece.layout_version=2
					report["workbench_layout_upgrade"]=true
	if _save_manager._validate_snapshot(actual)!="": failures.append(phase+": invalid snapshot")
	if expected.world_seed!=actual.world_seed: failures.append(phase+": changed seed")
	for section in ["terrain","furniture","construction","ladders","bridges","mining","worker_crafting","settlement_flag"]:
		var difference := _deep_diff(expected.scene[section],actual.scene[section],phase+"."+section)
		if difference!="": failures.append(difference)
	var original := {}
	for dwarf in expected.scene.dwarves.roster: original[dwarf.id]=dwarf
	if original.size()!=actual.scene.dwarves.roster.size(): failures.append(phase+": dwarf count")
	for dwarf in actual.scene.dwarves.roster:
		if not original.has(dwarf.id): failures.append(phase+": missing dwarf ID"); continue
		for field in ["name","gender","appearance","profession","profession_experience","traits","work_permissions"]:
			var difference := _deep_diff(original[dwarf.id][field],dwarf[field],phase+".dwarf."+str(dwarf.id)+"."+field)
			if difference!="": failures.append(difference)
	var goods_diff := _deep_diff(_goods(expected.scene),_goods(actual.scene),phase+".goods")
	if goods_diff!="": failures.append(goods_diff)
	for field in ["day","season","year","hour"]:
		if expected.clock[field]!=actual.clock[field]: failures.append(phase+": clock "+field)
	for species in ["rabbits","deer","wolves","ducks"]:
		var ids_before: Array=[]; var ids_after: Array=[]
		for actor in expected.scene.wildlife[species]: ids_before.append(actor.id)
		for actor in actual.scene.wildlife[species]: ids_after.append(actor.id)
		ids_before.sort(); ids_after.sort()
		if ids_before!=ids_after: failures.append(phase+": wildlife "+species)

func _goods(value: Variant,totals: Dictionary={}) -> Dictionary:
	if value is Dictionary:
		var item: String=String(value.get("item",value.get("item_key","")))
		if item.begins_with("base:") and (value.has("count") or value.has("quantity")):
			var key := item+"|"+String(value.get("material_id",""))
			totals[key]=totals.get(key,0)+int(value.get("count",value.get("quantity",1)))
		for child in value.values(): _goods(child,totals)
	elif value is Array:
		for child in value: _goods(child,totals)
	return totals

func _settle_visuals() -> void:
	var renderer=current_scene.get_node("Renderer")
	var started := Time.get_ticks_msec()
	for i in 8: await process_frame
	while not renderer.is_loading_complete():
		if Time.get_ticks_msec()-started>90000: _fail("visual settle timeout"); return
		await process_frame

func _capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output+name+".png")
