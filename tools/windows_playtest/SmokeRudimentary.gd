extends SceneTree

## Run the editor executable --main-pack <release.pck> with this external script
## and an isolated APPDATA. Release executables ignore the --script switch.
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
	if not "rudimentary_package_profile" in OS.get_user_data_dir() or output.is_empty():
		push_error("Requires isolated rudimentary_package_profile and --output"); quit(2); return
	if FileAccess.file_exists("res://tools/windows_playtest/SmokeRudimentary.gd"):
		push_error("Must run the exported package, without loose workspace resources"); quit(2); return
	create_timer(150).timeout.connect(func(): push_error("Rudimentary package timeout"); quit(1))
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1280,720)
	var saves = root.get_node("SaveManager")
	saves.set_process(false)
	var clock_node = root.get_node("WorldClock")
	clock_node.set_paused(true)
	node_added.connect(func(node):
		if node.name=="Renderer": node.set("world_seed",1234))
	change_scene_to_file("res://scenes/main/debug_world.tscn")
	await process_frame
	while current_scene == null or current_scene.get_node("Renderer")._initial_load: await process_frame
	clock_node.set_paused(true)
	var furniture = get_first_node_in_group("furniture_controller")
	var crafting = get_first_node_in_group("crafting_manager")
	check(furniture != null and furniture._games != null,"scene owns recreation coordinator")
	for id: String in ["log_fence","log_gate","board_game_table"]:
		var key := "base:furniture:"+id
		check(furniture.get_defs().has(key),"packed definition: "+id)
		check(crafting.recipes.has("base:recipe:worker:"+id),"packed Worker recipe: "+id)
		var model: Node3D = load("res://assets/models/furniture/"+id+".glb").instantiate()
		check(model != null,"packed imported model: "+id)
		model.free()
		check(ResourceLoader.exists("res://assets/ui/furniture/"+id+".png"),"packed thumbnail: "+id)
	# Normal arrival waits for a player-placed settlement flag. Seed a private
	# test squad through the existing development entry point while paused.
	get_first_node_in_group("dwarf_director").spawn_squad_at_camera()
	var agents: Array = root.get_node("TaskManager")._agents.values()
	check(not agents.is_empty(),"private test squad spawns on valid ground")
	if not agents.is_empty():
		var dwarf = agents[0]
		dwarf._mood.record_recreation()
		dwarf._mood.recreation_retry_hours = 2.0
		var id: int = dwarf.dwarf_id
		saves.set_process(true)
		check(saves.request_save(),"release accepts save with recreation thought")
		while saves.is_saving(): await process_frame
		check(saves.request_load(),"release reload accepts saved thought")
		while saves.is_loading(): await process_frame
		saves.set_process(false)
		clock_node.set_paused(true)
		var restored = root.get_node("TaskManager")._agents.get(id)
		check(restored != null and is_equal_approx(restored._mood.recreation_memory_hours,12.0),"release restores completed happiness memory")
		check(restored != null and is_equal_approx(restored._mood.recreation_retry_hours,2.0),"release restores cooldown")
		check(restored != null and not restored.is_recreating(),"release does not restore stale game claims")
	await create_timer(2).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output+"release_startup.png")
	FileAccess.open(output+"result.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures},"  "))
	print("RUDIMENTARY_PACKAGE_OK: %d checks"%checks if failures.is_empty() else "RUDIMENTARY_PACKAGE_FAIL")
	quit(0 if failures.is_empty() else 1)
