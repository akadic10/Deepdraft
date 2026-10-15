extends SceneTree
## Native packed-save check. Run from the package directory with editor Godot
## --path <package> --main-pack <pck> --script <absolute helper path>.
var failures: Array[String] = []
var output := ""

func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=").trim_suffix("/")+"/"
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func _run() -> void:
	if not "/wildlife_20261014/" in OS.get_user_data_dir().replace("\\","/") or output.is_empty():
		push_error("Wildlife check requires isolated wildlife_20261014 profile and output")
		quit(2); return
	if FileAccess.file_exists("res://tools/performance/CameraBenchmark.gd"):
		push_error("Packed check must not resolve loose workspace files")
		quit(2); return
	DirAccess.make_dir_recursive_absolute(output)
	create_timer(120).timeout.connect(func(): push_error("Wildlife packed check timeout"); quit(1))
	root.size=Vector2i(1600,1000)
	var clock_node=root.get_node("WorldClock")
	var saves=root.get_node("SaveManager")
	clock_node.set_paused(true)
	var placeholder:=Node3D.new()
	placeholder.scene_file_path="res://scenes/main/debug_world.tscn"
	root.add_child(placeholder)
	current_scene=placeholder
	if not saves.request_load(): quit(1); return
	while saves.is_loading(): await process_frame
	saves.set_process(false)
	clock_node.set_paused(true)
	var terrain=current_scene.get_node("Renderer")
	await _settle(terrain)
	var wildlife=current_scene.get_node("WildlifeManager")
	var rig=current_scene.get_node("CameraRig")
	var camera: Camera3D=rig.camera_node
	var before: Dictionary={}
	var offscreen:=0
	for animal in wildlife.animals:
		before[animal.animal_id]=animal.serialize_state()
		if not camera.is_position_in_frustum(animal.global_position): offscreen+=1
	clock_node.set_speed(1)
	clock_node.set_paused(false)
	await create_timer(8).timeout
	clock_node.set_paused(true)
	var moved:=0
	for animal in wildlife.animals:
		if not before.has(animal.animal_id): continue
		check(animal.pose_time>float(before[animal.animal_id].pose_time),"offscreen/onscreen animal time advances: "+animal.animal_id)
		if animal.position!=saves.unpack_v3(before[animal.animal_id].position): moved+=1
	check(offscreen>0 and moved>0,"copied world contains moving offscreen wildlife")
	var paused: Dictionary=wildlife.serialize_state()
	await create_timer(.2).timeout
	check(paused==wildlife.serialize_state(),"pause freezes all wildlife state")
	for species in ["wolf","duck"]:
		var animals: Array=wildlife.animals_of_species(species)
		check(not animals.is_empty(),"copied save restores "+species)
		if animals.is_empty(): continue
		var animal: Node3D=animals[0]
		rig.stop_following()
		rig._target_pos=animal.position+Vector3.UP
		rig.global_position=rig._target_pos
		rig._target_zoom=16.0
		await create_timer(1.5).timeout
		await _settle(terrain)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output+species+".png")
	var first: Node3D=wildlife.animals[0]
	wildlife.apply_slice(floori(first.position.y)-1)
	check(not first.visible,"slice immediately conceals wildlife")
	wildlife.apply_slice(127)
	check(first.visible,"surface wildlife reappears on full slice")
	var navigation=load("res://scripts/components/AnimalNavigation.gd")
	var result: Dictionary={"failures":failures,"offscreen_at_start":offscreen,"moved":moved,
		"animals_after":wildlife.animals.size(),"cache":navigation.get_cache_stats(),
		"dwarves":current_scene.get_node("DwarfDirector").get_roster().size(),
		"driver":RenderingServer.get_current_rendering_driver_name()}
	FileAccess.open(output+"packed_smoke.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("WILDLIFE_EXPORT_PASS " if failures.is_empty() else "WILDLIFE_EXPORT_FAIL ",JSON.stringify(result))
	root.get_node("WorldGenerator").prepare_for_world_reload()
	quit(0 if failures.is_empty() else 1)

func _settle(terrain: Node) -> void:
	await process_frame
	await process_frame
	while not terrain._overview_built or not terrain._dirty_overview_tiles.is_empty() or terrain._cavity_shell_dirty or terrain.underground_lighting.is_updating():
		await process_frame
