extends SceneTree
var errors: Array[String] = []
func _init() -> void: _run.call_deferred()
func check(ok: bool,message: String) -> void:
	if not ok:
		errors.append(message)
		push_error(message)
func _run() -> void:
	if not OS.get_environment("APPDATA").replace("\\","/").contains("/tmp/duck_review/"):
		quit(2)
		return
	root.get_node("SaveManager").configure_storage_for_testing("user://duck_preview")
	var clock = root.get_node("WorldClock")
	clock.paused = true
	clock.hour = 10
	var scene: Node = load("res://scenes/main/debug_world.tscn").instantiate()
	scene.get_node("Renderer").world_seed = 1234
	var publish := func(node: Node):
		if node==scene: current_scene = scene
	node_added.connect(publish)
	root.add_child(scene)
	node_added.disconnect(publish)
	var wildlife = scene.get_node("WildlifeManager")
	var renderer = scene.get_node("Renderer")
	var deadline := Time.get_ticks_msec()+150000
	while Time.get_ticks_msec()<deadline:
		await process_frame
		if wildlife.duck_initialized and renderer._overview_built and wildlife.arrival_ready(): break
	check(wildlife.duck_initialized and wildlife.arrival_ready(),"world and full flora finish loading")
	var ducks: Array = wildlife.animals_of_species("duck")
	check(ducks.size()>=6,"natural flocks spawned")
	if ducks.is_empty(): quit(1); return
	var camera = scene.get_node("CameraRig")
	var result: String = wildlife.dev_locate_next("duck")
	check(not result.is_empty(),"DEV locates natural duck")
	ducks.sort_custom(func(a,b): return a.position.y<b.position.y)
	var duck = ducks[0]
	var explorer = get_first_node_in_group("object_explorer")
	check(explorer.select_object(wildlife,duck),"shared inspector selects duck")
	wildlife.perform_explorer_action(duck,"follow")
	check(wildlife.is_following(duck),"Follow tracks duck")
	wildlife.perform_explorer_action(duck,"stop_follow")
	check(not wildlife.is_following(duck),"Stop following releases camera")
	var original: Dictionary = duck.serialize_state()
	# Get the actual camera through the manager's configured reference.
	camera = wildlife._camera
	print("DUCK_CAMERA ",camera.name)
	camera.stop_following()
	camera.focus_world_position(duck.position,12)
	camera._pitch = -65
	camera._orbit_y = 35
	await _capture("natural_flock")
	var flew: bool = duck._try_flight()
	if flew:
		for i in 30: duck.advance(.05,0,[])
		camera.focus_world_position(duck.position,12)
		await _capture("flight")
		for i in 300: duck.advance(.05,0,[])
		check(duck.mode=="water","flight avoids loaded canopy and lands")
	check(flew,"natural duck can fly between pools with full forest loaded")
	duck.restore_state(original)
	camera.focus_world_position(duck.position,12)
	duck.sex = "male"
	duck._pose()
	camera.focus_world_position(duck.position,6)
	await _capture("male")
	duck.sex = "female"
	duck._pose()
	await _capture("female")
	# Run ordinary live flocks with the hydrology and tree canopy present.
	clock.paused = false
	wildlife.set_process(false)
	var timing := Time.get_ticks_usec()
	for i in 1200:
		wildlife.advance(.1,[])
		if i%100==0: await process_frame
	print("DUCK_FULL_WORLD_SIM_MS ",(Time.get_ticks_usec()-timing)/1000.0)
	clock.paused = true
	for bird in ducks:
		check(bird.mode=="air" or wildlife.duck_navigation.clear_body(bird.position,.49),"duck stays clear of terrain")
	camera.focus_world_position(duck.position,12)
	await _capture("after_activity")
	if errors.is_empty(): print("DUCK_LIVE_PREVIEW_OK")
	quit(0 if errors.is_empty() else 1)
func _capture(label: String) -> void:
	for i in 15: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tmp/duck_review/"+label+".png")
