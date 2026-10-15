extends SceneTree

## Use the editor executable --path <export directory> --main-pack <export.pck>
## --script <absolute path>, with the export directory as the working directory.
## Release executables omit --script; test their normal startup separately.
func _init() -> void: _run.call_deferred()

func _run() -> void:
	if not "/water_mesh_20261014/" in OS.get_user_data_dir().replace("\\","/"):
		push_error("Water export smoke test requires an isolated profile")
		quit(2)
		return
	if FileAccess.file_exists("res://tools/performance/CameraBenchmark.gd"):
		push_error("Smoke test requires the exported PCK, not the workspace")
		quit(2)
		return
	print("WATER_EXPORT_START")
	create_timer(120).timeout.connect(func(): push_error("Water export smoke timeout"); quit(1))
	var saves = root.get_node("SaveManager")
	var clock_node = root.get_node("WorldClock")
	clock_node.set_paused(true)
	var placeholder := Node3D.new()
	placeholder.scene_file_path = "res://scenes/main/debug_world.tscn"
	root.add_child(placeholder)
	current_scene = placeholder
	if not saves.request_load(): quit(1); return
	while saves.is_loading(): await process_frame
	saves.set_process(false)
	clock_node.set_paused(true)
	var terrain = current_scene.get_node("Renderer")
	var water_view = terrain.get_node("Water")
	if not water_view.has_method("get_mesh_stats"):
		push_error("Export does not contain the new water renderer"); quit(1); return
	await _settle(terrain,water_view)
	print("WATER_EXPORT_LOADED")
	clock_node.set_speed(1)
	clock_node.set_paused(false)
	await create_timer(5).timeout
	clock_node.set_paused(true)
	await _settle(terrain,water_view)
	print("WATER_EXPORT_ACTIVE")
	var original_slice: int = terrain.slice_y
	terrain.slice_y = 35
	await _settle(terrain,water_view)
	print("WATER_EXPORT_SLICE")
	terrain.slice_y = original_slice
	await _settle(terrain,water_view)
	print("WATER_EXPORT_PASS ",JSON.stringify({"water":water_view.get_mesh_stats(),
		"dwarves":current_scene.get_node("DwarfDirector").get_roster().size(),
		"driver":RenderingServer.get_current_rendering_driver_name()}))
	root.get_node("WorldGenerator").prepare_for_world_reload()
	quit(0)

func _settle(terrain: Node, water_view: Node) -> void:
	# First frame lets the renderer observe a newly assigned slice.
	await process_frame
	await process_frame
	while not terrain._overview_built or not terrain._dirty_overview_tiles.is_empty() \
		or terrain._cavity_shell_dirty or terrain.underground_lighting.is_updating() \
		or not root.get_node("WaterManager").dirty_tiles.is_empty() \
		or not water_view._pending.is_empty() or not water_view._jobs.is_empty():
		await process_frame
