extends SceneTree

## Run against the exported PCK, with an isolated copy of the player save.
var output := ""
var failures: Array[String] = []
var checks := 0
var materials := 0

func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=").trim_suffix("/") + "/"
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func _run() -> void:
	if not "/shared_atmosphere_20261015/" in OS.get_user_data_dir().replace("\\", "/") or output.is_empty():
		push_error("Atmosphere package check requires isolated profile and output"); quit(2); return
	if FileAccess.file_exists("res://tools/performance/CameraBenchmark.gd"):
		push_error("Package check must not resolve loose project files"); quit(2); return
	create_timer(180).timeout.connect(func(): push_error("Atmosphere package timeout"); quit(1))
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1600, 1000)
	var saves = root.get_node("SaveManager")
	var clock_node = root.get_node("WorldClock")
	clock_node.set_paused(true)
	var placeholder := Node3D.new()
	placeholder.scene_file_path = "res://scenes/main/debug_world.tscn"
	root.add_child(placeholder)
	current_scene = placeholder
	check(saves.request_load(), "copied settlement load accepted")
	while saves.is_loading(): await process_frame
	saves.set_process(false)
	clock_node.set_paused(true)
	await _settle()
	var sky = root.get_node("SkyController")
	sky.set_process(false)
	root.get_node("WeatherManager").set_process(false)
	var field = current_scene.get_node("Renderer").underground_lighting
	var packet: ImageTexture = field._atmosphere.texture
	var rid := packet.get_rid()
	var previous := PackedByteArray()
	for hour in [12.0, 18.0, 0.0]:
		clock_node.hour = hour
		sky._update(hour)
		field._sync_fog()
		var bytes := packet.get_image().get_data()
		check(packet.get_rid() == rid, "day/night retain texture RID")
		check(bytes != previous, "day/night keep live atmosphere")
		previous = bytes
		_check_materials(field, packet)
		await _capture("hour_%02d" % int(hour))
	# Real asynchronous save/reload must recreate a scene-local packet.
	saves.set_process(true)
	check(saves.request_save(), "package manual save accepted")
	while saves.is_saving(): await process_frame
	check(saves.request_load(), "package saved settlement reload accepted")
	while saves.is_loading(): await process_frame
	saves.set_process(false)
	clock_node.set_paused(true)
	await _settle()
	field = current_scene.get_node("Renderer").underground_lighting
	sky._update(clock_node.hour)
	field._sync_fog()
	var restored: ImageTexture = field._atmosphere.texture
	check(restored != packet and restored.get_rid() != rid, "reload owns a fresh packet")
	check(restored.get_image().get_data() == previous, "reload restores exact night atmosphere")
	check(is_zero_approx(clock_node.hour), "reload restores the saved midnight")
	check(current_scene.get_node("DwarfDirector").get_roster().size() == 5, "copied dwarves survive reload")
	check(current_scene.get_node("WildlifeManager").animals.size() == 79, "copied wildlife survive reload")
	_check_materials(field, restored)
	await _capture("restored_night")
	var result := {"checks": checks, "failures": failures, "materials": materials, "hour": clock_node.hour}
	FileAccess.open(output + "checks.json", FileAccess.WRITE).store_string(JSON.stringify(result, "  "))
	print("ATMOSPHERE_EXPORT_PASS " if failures.is_empty() else "ATMOSPHERE_EXPORT_FAIL ", JSON.stringify(result))
	root.get_node("WorldGenerator").prepare_for_world_reload()
	quit(0 if failures.is_empty() else 1)

func _check_materials(field: Node, packet: ImageTexture) -> void:
	materials = field._material_cache.size()
	check(materials > 100, "developed settlement has many lighting materials")
	for material: ShaderMaterial in field._material_cache.values():
		check(material.get_shader_parameter("atmosphere_data") == packet, "all materials bind this scene's atmosphere")

func _settle() -> void:
	var renderer = current_scene.get_node("Renderer")
	for i in 12000:
		await process_frame
		var flora = current_scene.get_node("SurfaceFloraSpawner")
		var details = current_scene.get_node("SurfaceDetailManager")
		if renderer._overview_built and renderer._dirty_overview_tiles.is_empty() and not renderer._ovt_building and not renderer._cavity_shell_dirty \
			and flora._ready_to_spawn and flora._pending.is_empty() and details._initialized and details._visual_queue.is_empty() \
			and not renderer.underground_lighting.is_updating(): return
	check(false, "world settles")

func _capture(label: String) -> void:
	for i in 6: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output + label + ".png")
