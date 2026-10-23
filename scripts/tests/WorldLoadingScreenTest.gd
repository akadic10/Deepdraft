extends SceneTree

var failures: Array[String] = []
var saw_partial := false
var saw_full := false
const OUT := "res://tmp/loading_screen_20261017/"

func _init() -> void: _run.call_deferred()
func _expect(ok: bool, description: String) -> void:
	if not ok: failures.append(description)

func _run() -> void:
	create_timer(150).timeout.connect(func(): push_error("Loading screen timeout"); quit(1))
	var clock = root.get_node("WorldClock")
	var saves = root.get_node("SaveManager")
	clock.set_paused(false)
	_expect(saves.configure_storage_for_testing("user://loading_screen_test"),"isolated save directory")
	change_scene_to_file("res://scenes/main/debug_world.tscn")
	await process_frame
	await process_frame
	var screen = current_scene.get_node("WorldLoadingScreen")
	var backgrounds: Array = root.get_node("UIRegistry").get_loading_screen().backgrounds
	var selected_art: Texture2D = screen._art.artwork
	_expect(selected_art!=null and selected_art.resource_path in backgrounds,"startup chooses a configured background")
	var renderer = current_scene.get_node("Renderer")
	var camera = current_scene.get_node("CameraRig")
	var start_hour: float = clock.hour
	_expect(screen.visible and not screen._released,"first scene frames are covered")
	_expect(clock.paused and not clock.serialize_state().paused,"loading hold never changes the saved pause preference")
	for entry in screen._hidden_layers:
		_expect(not entry.node.get_ref().visible,"all game HUD layers hidden")
	var camera_target: Vector3 = camera._target_pos
	var key := InputEventKey.new()
	key.keycode = KEY_SPACE
	key.pressed = true
	Input.parse_input_event(key)
	key = InputEventKey.new()
	key.keycode = KEY_D
	key.physical_keycode = KEY_D
	key.pressed = true
	Input.parse_input_event(key)
	for frame in range(3): await process_frame
	_expect(camera._target_pos.is_equal_approx(camera_target),"held pan keys are ignored during loading")
	key.pressed = false
	Input.parse_input_event(key)
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OUT+"first_frames.png")
	var prior := 0.0
	var captured := false
	while not screen._released:
		_expect(screen._art.artwork==selected_art,"artwork remains fixed throughout loading")
		_expect(screen._art.progress>=prior,"progress never goes backwards")
		prior = screen._art.progress
		if not renderer.tiles.initial_load and renderer.tiles.overview_tile_nodes.size()<1024:
			saw_partial = true
			_expect(screen.visible,"near-camera terrain completion must not reveal the world")
			if not captured and DisplayServer.get_name()!="headless":
				captured = true
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(OUT+"actual_startup.png")
		if screen._art.complete: saw_full = true
		await process_frame
	_expect(saw_partial,"exercised the old early-release milestone")
	_expect(saw_full and is_equal_approx(screen._art.progress,1.0),"mug reaches full before reveal")
	_expect(renderer.tiles.overview_built and renderer.tiles.overview_tile_nodes.size()==1024 and renderer.tiles.dirty_overview_tiles.is_empty() and not renderer.tiles.ovt_building,"all overview tiles complete at reveal")
	_expect(screen.loading_state().ready,"scenery, water, lighting and restoration complete at reveal")
	_expect(is_equal_approx(start_hour,clock.hour),"simulation remains frozen until reveal")
	_expect(not clock.paused and not clock.is_loading_held(),"original running state restored")
	_expect(camera._target_pos.is_equal_approx(camera_target),"loading input cannot pan the camera")
	_expect(current_scene.get_node("DockUI").visible and not current_scene.get_node("DebugLoadingOverlay").visible,"original HUD visibility restored")
	clock.set_paused(true)
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OUT+"world_revealed.png")
	# A normal local rebuild must never reopen the startup screen.
	renderer.tiles._enqueue_overview_tiles_for_blocks([Vector3i(512,70,512)] as Array[Vector3i])
	await process_frame
	_expect(not screen.visible and screen._released,"ordinary terrain changes do not reopen loading")
	_expect(saves.request_save(),"save is accepted")
	while saves.is_saving(): await process_frame
	_expect(saves.request_load(),"saved world starts reloading")
	await scene_changed
	await process_frame
	screen = current_scene.get_node("WorldLoadingScreen")
	_expect(screen.visible and clock.is_loading_held(),"scene reload installs a new loading screen")
	selected_art = screen._art.artwork
	_expect(selected_art!=null and selected_art.resource_path in backgrounds,"save reload chooses a configured background")
	while not screen._released:
		_expect(screen._art.artwork==selected_art,"reload artwork remains fixed throughout loading")
		await process_frame
	_expect(not saves.is_loading() and screen.loading_state().ready,"load reveal waits for restore and rebuilt slice")
	_expect(clock.paused and clock.serialize_state().paused and not clock.is_loading_held(),"saved pause preference survives the loading hold")
	# Early scene teardown cannot leave a global hold behind.
	var temporary = load("res://scripts/ui/WorldLoadingScreen.gd").new()
	for field in ["renderer_path","flora_path","details_path","wildlife_path"]:
		temporary.set(field,screen.get(field))
	current_scene.add_child(temporary)
	_expect(clock.is_loading_held() and not current_scene.get_node("DockUI").visible,"temporary screen acquires its presentation hold")
	var running: Dictionary = clock.serialize_state()
	running.paused = false
	clock.restore_state(running)
	_expect(clock.paused and not clock.serialize_state().paused,"restoring a running clock cannot bypass a loading hold")
	temporary.free()
	_expect(not clock.paused and not clock.is_loading_held() and current_scene.get_node("DockUI").visible,"early screen teardown restores HUD and resumes a running clock")
	var hold := Node.new()
	root.add_child(hold)
	clock.hold_for_loading(hold,true)
	clock.hold_for_loading(hold,true)
	clock.hold_for_loading(hold,false)
	hold.free()
	_expect(not clock.is_loading_held(),"loading hold is idempotent")
	for failure in failures: push_error(failure)
	print("WORLD_LOADING_SCREEN_OK" if failures.is_empty() else "WORLD_LOADING_SCREEN_FAIL")
	quit(0 if failures.is_empty() else 1)
