extends SceneTree

## Whole-world regression: surface cave discovery must not replace initial terrain
## scheduling. Run headless, or add -- --capture for native gameplay-camera PNGs.
const OUTPUT := "res://tmp/water_review/terrain_startup"
var _seed := 2795346874
var _capture := false
var _load_finished := false
var _load_ok := false

func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.is_valid_int(): _seed = int(arg)
		if arg == "--capture": _capture = true
	_run.call_deferred()

func _run() -> void:
	create_timer(180).timeout.connect(func(): _fail("timeout"))
	var clock = root.get_node("WorldClock")
	clock.paused = true
	var saves = root.get_node("SaveManager")
	if not saves.configure_storage_for_testing("user://terrain_startup_test"):
		_fail("test storage unavailable")
		return
	node_added.connect(func(node: Node):
		if node.name == "Renderer" and node.get_script() != null:
			node.set("world_seed", _seed))
	change_scene_to_file("res://scenes/main/debug_world.tscn")
	await process_frame
	await process_frame
	var gen = root.get_node("WorldGenerator")
	while not gen._maps_ready or gen.is_generating(): await process_frame
	var view = current_scene.get_node("Renderer")
	await _settle(view)
	if not _coverage(view, "fresh world"): return
	if view._discovered_cave_blocks.is_empty():
		_fail("spring cave was not revealed during startup")
		return
	if _capture: await _pictures(view)

	# A local change must retain far-away mesh nodes and geometry, rather than
	# reinitializing the entire map whenever the dirty queue becomes nonempty.
	var distant: MeshInstance3D = view._overview_tile_nodes[Vector2i.ZERO]
	var distant_mesh := distant.mesh
	var mouth: Vector3i = gen.spring_cave.mouth
	var local_blocks: Array[Vector3i] = [mouth]
	view._enqueue_overview_tiles_for_blocks(local_blocks)
	await _settle(view)
	if not _coverage(view, "local refresh"): return
	if view._overview_tile_nodes[Vector2i.ZERO] != distant or distant.mesh != distant_mesh:
		_fail("local refresh rebuilt distant terrain")
		return

	# Load a saved slice through the real SaveManager scene-reload path. Cave
	# exposure and restored edits can enqueue local work before initial meshes.
	var slices = current_scene.get_node("SliceController")
	slices.restore_state({"active": true, "slice_y": mouth.y + 3})
	await _settle(view)
	if not _coverage(view, "slice"): return
	var saved_slice: int = view.slice_y
	if not saves.request_save():
		_fail("save failed")
		return
	saves.load_finished.connect(func(ok: bool, _backup: bool):
		_load_ok = ok
		_load_finished = true)
	if not saves.request_load():
		_fail("load did not start")
		return
	while not _load_finished: await process_frame
	if not _load_ok:
		_fail("load failed")
		return
	view = current_scene.get_node("Renderer")
	await _settle(view)
	if not _coverage(view, "save reload"): return
	if view.slice_y != saved_slice:
		_fail("saved slice was not restored")
		return
	current_scene.get_node("SliceController").deactivate()
	await _settle(view)
	if not _coverage(view, "slice off after reload"): return

	# Full invalidation followed immediately by a local event is the same race
	# as startup, and must schedule every tile again.
	view._invalidate_overview_global()
	view._enqueue_overview_tiles_for_blocks(local_blocks)
	await _settle(view)
	if not _coverage(view, "global invalidation plus local update"): return
	print("WorldTerrainStartupTest: PASS seed=", _seed)
	quit()

func _settle(view: Node) -> void:
	await process_frame
	while not view._overview_built or not view._dirty_overview_tiles.is_empty():
		await process_frame

func _coverage(view: Node, stage: String) -> bool:
	var count := ceili(float(view.WORLD_SIZE_X) / view.OVERVIEW_TILE_SIZE)
	if view._overview_tile_nodes.size() != count * count:
		_fail("%s: only %d/%d terrain tiles" % [stage, view._overview_tile_nodes.size(), count * count])
		return false
	for x in count:
		for z in count:
			var tile: MeshInstance3D = view._overview_tile_nodes.get(Vector2i(x, z))
			if tile == null or not tile.visible or tile.mesh == null or tile.mesh.get_surface_count() == 0:
				_fail("%s: missing visible geometry at %s" % [stage, Vector2i(x, z)])
				return false
	print("WorldTerrainStartupTest: ", stage, " all ", count * count, " tiles have visible geometry")
	return true

func _pictures(view: Node) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	root.size = Vector2i(1600, 1000)
	root.get_node("SkyController").rebind_to_current_scene()
	root.get_node("WorldClock").hour = 9.0
	root.get_node("SkyController")._update(9.0)
	var gen = root.get_node("WorldGenerator")
	var rig = current_scene.get_node("CameraRig")
	rig.set_process(false)
	var camera: Camera3D = rig.camera_node
	# SpringArm3D still positions children on physics ticks when rig processing
	# is paused. Detach the real gameplay camera for deterministic review poses.
	var camera_parent := camera.get_parent()
	var camera_transform := camera.transform
	camera.reparent(current_scene)
	var back2: Vector2i = gen.river_layout.spring_back
	var back := Vector3(back2.x, 0, back2.y)
	var side := Vector3(-back2.y, 0, back2.x)
	var route: Array = gen.river_layout.route
	var mid: Vector2i = route[route.size() / 2]
	var samples := {
		"spring_wide": [Vector3(gen.spring_cave.mouth), -back * 95 + side * 45 + Vector3(0, 65, 0)],
		"river": [Vector3(mid.x, gen.get_surface_y(mid.x, mid.y), mid.y), Vector3(60, 80, 50)],
		"lake": [Vector3(gen.river_layout.outlet), Vector3(90, 110, 90)],
		"remote_ground": [Vector3(256, gen.get_surface_y(256, 256), 256), Vector3(60, 80, 50)]}
	for label in samples:
		camera.global_position = samples[label][0] + samples[label][1]
		camera.look_at(samples[label][0])
		for frame in 30: await process_frame
		while view.underground_lighting.is_updating(): await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OUTPUT + "/%d_%s.png" % [_seed, label])
	camera.reparent(camera_parent)
	camera.transform = camera_transform
	rig.set_process(true)

func _fail(message: String) -> void:
	push_error("WorldTerrainStartupTest: FAIL " + message)
	quit(1)
