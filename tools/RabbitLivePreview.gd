extends SceneTree
## Run with isolated APPDATA below tmp/rabbit_review (or deer_review with --deer).
## Native main scene,
## real seeded habitat, public DEV action and screen picking; saves no players.
var failures: Array[String] = []
var species := "rabbit"
var output_dir := "res://tmp/rabbit_review/"

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	if "--deer" in OS.get_cmdline_user_args():
		species = "deer"
		output_dir = "res://tmp/deer_review/"
	if "--wolf" in OS.get_cmdline_user_args():
		species = "wolf"
		output_dir = "res://tmp/wolf_review/"
	if not OS.get_environment("APPDATA").replace("\\","/").contains("/tmp/"+species+"_review/"):
		printerr("Use isolated APPDATA below tmp/"+species+"_review.")
		quit(2)
		return
	root.get_node("SaveManager").configure_storage_for_testing("user://rabbit_preview")
	root.get_node("WorldClock").set_paused(true)
	var scene: Node = load("res://scenes/main/debug_world.tscn").instantiate()
	scene.get_node("Renderer").world_seed = 1234
	var publish := func(node: Node):
		if node == scene: current_scene = scene
	node_added.connect(publish)
	root.add_child(scene)
	node_added.disconnect(publish)
	var wildlife := scene.get_node("WildlifeManager")
	var renderer := scene.get_node("Renderer")
	var generator := root.get_node("WorldGenerator")
	var clock_node := root.get_node("WorldClock")
	var deadline := Time.get_ticks_msec() + 120000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if wildlife.initialized and wildlife.deer_initialized and wildlife.wolf_initialized and renderer._overview_built: break
	if not wildlife.initialized or not wildlife.deer_initialized or not wildlife.wolf_initialized or not renderer._overview_built:
		printerr("Wildlife world timed out")
		quit(1)
		return
	clock_node.set_paused(true)
	var cells: Array = wildlife.initial_cells(1234)
	_check(cells.size() == 48 and cells == wildlife.initial_cells(1234), "seeded population is full and repeatable")
	_check(cells != wildlife.initial_cells(5678), "different seed changes wildlife layout")
	var Navigation = load("res://scripts/components/AnimalNavigation.gd")
	for cell: Vector3i in cells:
		_check(cell.y <= 44 and Navigation.standable(cell), "rabbit has dry lowland support and clearance")
	if species == "deer":
		var groups: Array = wildlife.initial_deer_groups(1234)
		_check(groups.size() == 6 and groups == wildlife.initial_deer_groups(1234),"six deer herds spawn repeatably")
		_check(groups != wildlife.initial_deer_groups(5678),"deer seed changes group identities")
		_check(wildlife.animals_of_species("deer").size() == 18,"eighteen deer spawn alongside rabbits")
		for group: Dictionary in groups:
			_check(group.cells.size() == 3,"three members per connected group")
			for cell: Vector3i in group.cells:
				_check(Navigation.standable(cell,4,2) and cell.y <= 44,"deer has complete lowland support and clearance")
		var original: Dictionary = wildlife.serialize_state()
		wildlife.restore_state({"initialized":true,"rabbits":original.rabbits})
		wildlife.initialize_population()
		var migrated: Dictionary = wildlife.serialize_state()
		_check(migrated.rabbits == original.rabbits and migrated.deer.size() == 18,"rabbit-only save seeds deer without changing existing rabbits")
		wildlife.initialize_population()
		_check(wildlife.serialize_state() == migrated,"migration seeds deer only once")
		wildlife.restore_state(original)
	if species == "wolf":
		var original: Dictionary = wildlife.serialize_state()
		_check(original.wolves.size() == 4,"four seeded wolves join the existing prey populations")
		var old_save := original.duplicate(true)
		old_save.erase("wolves")
		old_save.erase("wolf_initialized")
		wildlife.restore_state(old_save)
		wildlife.initialize_population()
		var migrated: Dictionary = wildlife.serialize_state()
		_check(migrated.rabbits == original.rabbits and migrated.deer == original.deer and migrated.wolves.size() == 4,"older wildlife save adds wolves without changing existing prey")
		wildlife.initialize_population()
		_check(wildlife.serialize_state() == migrated,"wolf migration occurs only once")
		wildlife.restore_state(original)
	var dock := scene.get_node("DockUI")
	var explorer := scene.get_node("ObjectExplorerController")
	var rig := scene.get_node("CameraRig")
	dock._dispatch_panel_action("wildlife", "DEV: Next "+species)
	_check(explorer._provider == wildlife, "development menu opens wildlife inspector")
	var rabbit: Node3D = explorer._object_id
	for i in range(150): await process_frame
	# Find an exposed natural rabbit for a real screen-space click.
	var point := Vector2(-1,-1)
	for attempt in range(12):
		var box: AABB = wildlife.get_explorer_bounds(rabbit)
		for x in range(2,9):
			for y in range(2,9):
				var screen := root.get_camera_3d().unproject_position(box.position + box.size * Vector3(x / 10.0,y / 10.0,0.5))
				var hit: Dictionary = explorer.pick_at_screen(screen)
				if hit.get("provider") == wildlife and hit.get("id") == rabbit: point = screen
		if point.x >= 0: break
		dock._dispatch_panel_action("wildlife", "DEV: Next "+species)
		rabbit = explorer._object_id
		for i in range(100): await process_frame
	_check(point.x >= 0, "natural rabbit is selectable through terrain-aware screen picking")
	if point.x >= 0:
		explorer.clear_selection()
		_check(explorer.select_at_screen(point), "click selects the live rabbit")
	await _shot("rabbit_world")
	rabbit.hop_progress = 1.0
	rabbit.target = rabbit.cell
	rabbit.position = Navigation.centre(rabbit.cell,rabbit.footprint)
	rig.focus_world_position(rabbit.position + Vector3.UP * 0.7, 12)
	for i in range(80): await process_frame
	rabbit.activity = "Eating" if species == "wolf" else "Grazing"
	rabbit.hunger = 0.6
	rabbit._pose()
	explorer._refresh_selected()
	await _shot("rabbit_grazing")
	rabbit.activity = "Sleeping"
	rabbit.hunger = 0.2
	rabbit.fatigue = 0.6
	rabbit._pose()
	explorer._refresh_selected()
	await _shot("rabbit_sleeping")
	wildlife.perform_explorer_action(rabbit,"follow")
	_check(rig.is_following(rabbit), "camera follows rabbit")
	wildlife.perform_explorer_action(rabbit,"stop_follow")
	_check(not rig.is_following(rabbit), "camera can stop following")
	# Native model study on its real ground, plus a dwarf for scale.
	explorer.clear_selection()
	rabbit.activity = "Idle"
	rabbit._pose()
	var factory = load("res://scripts/entities/DwarfFactory.gd").new()
	var dwarf: Node3D = factory.spawn(factory.generate(918,{}),918)
	scene.add_child(dwarf)
	dwarf.set_process(false)
	dwarf.position = rabbit.position + Vector3(2,0,0)
	for dx in [2,-2,3,-3]:
		var beside: Vector3i = rabbit.cell + Vector3i(dx,0,0)
		if Navigation.standable(beside,3):
			dwarf.position = Navigation.centre(beside)
			break
	rabbit.rotation.y = 0
	var view := Camera3D.new()
	scene.add_child(view)
	view.current = true
	view.fov = 40
	view.global_position = rabbit.position + Vector3(8,4,-8)
	view.look_at(rabbit.position + Vector3(0.8,1.5,0))
	rig.set_process(false)
	await _shot("rabbit_scale")
	if species in ["deer","wolf"]:
		view.global_position = rabbit.position + Vector3(9,4,-4)
		view.look_at(rabbit.position + Vector3(0,1.4,0))
		dwarf.queue_free()
		await process_frame
		if species == "wolf":
			view.global_position = rabbit.position + Vector3(5,2.8,-4)
			view.look_at(rabbit.position + Vector3(0,.8,0))
		await _shot(species+"_standing_profile")
		rabbit.activity = "Eating" if species == "wolf" else "Grazing"
		rabbit._pose()
		await _shot(species+"_feeding_profile")
		rabbit.activity = "Sleeping"
		rabbit._pose()
		await _shot(species+"_rest_profile")
	print(species.to_upper()+"_LIVE_PREVIEW_OK" if failures.is_empty() else species.to_upper()+"_LIVE_PREVIEW_FAILED")
	generator.prepare_for_world_reload()
	quit(0 if failures.is_empty() else 1)

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func _shot(label: String) -> void:
	for i in range(4): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output_dir + label.replace("rabbit",species) + ".png")
