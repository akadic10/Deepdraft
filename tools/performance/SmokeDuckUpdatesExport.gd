extends SceneTree
## Native package-only check using a private copy of the settlement.
var output := ""
var failures: Array[String] = []
var checks := 0

func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=").trim_suffix("/")+"/"
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func _run() -> void:
	if not "/duck_updates_20261015/" in OS.get_user_data_dir().replace("\\","/") or output.is_empty():
		push_error("Duck package check requires isolated profile and output"); quit(2); return
	if FileAccess.file_exists("res://tools/performance/CameraBenchmark.gd"):
		push_error("Package check must not resolve loose project files"); quit(2); return
	create_timer(180).timeout.connect(func(): push_error("Duck package check timeout"); quit(1))
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1600,1000)
	var saves = root.get_node("SaveManager")
	var clock_node = root.get_node("WorldClock")
	clock_node.set_paused(true)
	var placeholder := Node3D.new()
	placeholder.scene_file_path = "res://scenes/main/debug_world.tscn"
	root.add_child(placeholder)
	current_scene = placeholder
	check(saves.request_load(),"copied settlement load accepted")
	while saves.is_loading(): await process_frame
	saves.set_process(false)
	clock_node.set_paused(true)
	await _settle()
	var wildlife = current_scene.get_node("WildlifeManager")
	var rig = current_scene.get_node("CameraRig")
	var before := {}
	var offscreen := 0
	for bird in wildlife.animals_of_species("duck"):
		before[bird.animal_id] = bird.serialize_state()
		if not rig.camera_node.is_position_in_frustum(bird.position): offscreen += 1
	check(before.size()==11 and offscreen>0,"copied settlement contains eleven ducks including offscreen birds")
	clock_node.set_speed(1)
	clock_node.set_paused(false)
	await create_timer(8).timeout
	clock_node.set_paused(true)
	var moved := 0
	for bird in wildlife.animals_of_species("duck"):
		check(bird.pose_time>float(before[bird.animal_id].pose_time),"duck updates onscreen/offscreen: "+bird.animal_id)
		if bird.position!=saves.unpack_v3(before[bird.animal_id].position): moved += 1
	check(moved>0,"ducks continue moving")
	var paused: Dictionary = wildlife.serialize_state()
	await create_timer(.2).timeout
	check(paused==wildlife.serialize_state(),"pause freezes wildlife")
	var bird: Node3D = wildlife.animals_of_species("duck")[0]
	var nav = wildlife.duck_navigation
	check(nav.clear_body(bird.position,float(nav.config.radius)),"live duck body is clear")
	var occupancy = root.get_node("PlacedEntityRegistry")
	var handle: int = occupancy.register_box(Vector3i(bird.position.floor()),Vector3i.ONE)
	check(not nav.clear_body(bird.position,float(nav.config.radius)),"package obstacle immediately invalidates cached body")
	occupancy.unregister(handle)
	check(nav.clear_body(bird.position,float(nav.config.radius)),"package removal immediately reopens body")
	wildlife.apply_slice(floori(bird.position.y)-1)
	check(not bird.visible,"slice conceals duck")
	wildlife.apply_slice(127)
	check(bird.visible,"full slice reveals duck")
	rig.stop_following()
	rig._target_pos = bird.position+Vector3.UP
	rig.global_position = rig._target_pos
	rig._target_zoom = 16.0
	await create_timer(1.5).timeout
	await _capture("duck_before_reload")
	var saved: Dictionary = wildlife.serialize_state()
	saves.set_process(true)
	check(saves.request_save(),"package manual save accepted")
	while saves.is_saving(): await process_frame
	# SaveFileStore uses the existing default JSON float precision. Compare at
	# that boundary, not unrounded in-memory doubles; IDs/RNG remain exact.
	var committed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("user://saves/quicksave.json"))
	var encoded: Dictionary = JSON.parse_string(JSON.stringify(saved))
	check(encoded==committed.scene.wildlife,"committed wildlife matches captured state at save precision")
	check(saves.request_load(),"package saved settlement reload accepted")
	while saves.is_loading(): await process_frame
	saves.set_process(false)
	clock_node.set_paused(true)
	await _settle()
	wildlife = current_scene.get_node("WildlifeManager")
	FileAccess.open(output+"wildlife_before.json",FileAccess.WRITE).store_string(JSON.stringify(saved,"  ",false,true))
	FileAccess.open(output+"wildlife_after.json",FileAccess.WRITE).store_string(JSON.stringify(wildlife.serialize_state(),"  ",false,true))
	var restored: Dictionary = JSON.parse_string(JSON.stringify(wildlife.serialize_state()))
	check(encoded==restored,"reload preserves wildlife positions, needs, routes, timers and RNG at save precision")
	check(current_scene.get_node("DwarfDirector").get_roster().size()==5,"copied colony survives reload")
	check(wildlife.animals.size()==79,"all copied wildlife survive reload")
	await _capture("duck_after_reload")
	var navigation = load("res://scripts/components/AnimalNavigation.gd")
	var result := {"checks":checks,"failures":failures,"ducks":before.size(),"offscreen":offscreen,"moved":moved,"cache":navigation.get_cache_stats()}
	FileAccess.open(output+"checks.json",FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	print("DUCK_UPDATES_EXPORT_PASS " if failures.is_empty() else "DUCK_UPDATES_EXPORT_FAIL ",JSON.stringify(result))
	root.get_node("WorldGenerator").prepare_for_world_reload()
	quit(0 if failures.is_empty() else 1)

func _settle() -> void:
	var renderer = current_scene.get_node("Renderer")
	for i in 12000:
		await process_frame
		var flora = current_scene.get_node("SurfaceFloraSpawner")
		var details = current_scene.get_node("SurfaceDetailManager")
		if renderer.tiles.overview_built and renderer.tiles.dirty_overview_tiles.is_empty() and not renderer.tiles.ovt_building and not renderer.cavity_shell.dirty \
			and flora._ready_to_spawn and flora._pending.is_empty() and details._initialized and details._visual_queue.is_empty() \
			and not renderer.underground_lighting.is_updating(): return
	check(false,"world settles")

func _capture(label: String) -> void:
	for i in 6: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output+label+".png")
