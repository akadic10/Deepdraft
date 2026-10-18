extends "res://scripts/tests/HaulingSelectionTest.gd"

var indicators
var director
var concern_script
var rested
var unhappy
const OUT := "res://tmp/dwarf_concerns_20261017/"


func _run() -> void:
	create_timer(90).timeout.connect(func(): push_error("Dwarf indicators timed out"); quit(1))
	await _setup_fixture()
	clock_node.set_paused(true)
	root.size = Vector2i(1280,720)
	var generator = root.get_node("WorldGenerator")
	generator._maps_ready = true
	generator.heightmap.resize(1024*1024); generator.heightmap.fill(20)
	generator.waterline_map.resize(1024*1024); generator.waterline_map.fill(-1)
	generator._cache_block_ids()
	concern_script = load("res://scripts/components/DwarfConcern.gd")
	manager = load("res://scripts/ui/UIWindowManager.gd").new()
	manager.name = "Windows"
	scene.add_child(manager)
	manager._layout_loaded=false; manager._layout.clear()
	director = load("res://scripts/entities/DwarfDirector.gd").new()
	director.name = "Dwarves"
	director.window_manager_path = NodePath("../Windows")
	scene.add_child(director)
	worker.position = Vector3(44.5,21,45.5)
	worker._food.value=1.0
	_expect(concern_script.describe(worker).is_empty(),"satisfied dwarf has no alert")
	worker._food.value=.35
	_expect(concern_script.describe(worker).is_empty(),"ordinary hunger is quiet while self-care can resolve it")
	worker._food.shortage=true
	_expect(concern_script.describe(worker).reason=="No reachable food","failed food search makes ordinary hunger actionable")
	worker._food.value=.1
	worker.sleep=.1
	worker._mood.thermal_memory.cold=12.0
	_expect(concern_script.describe(worker).kind=="food","serious hunger takes priority over exhaustion and unhappiness")
	worker._food.state="walking"
	_expect(concern_script.describe(worker).reason=="Collecting food","finding a portion replaces the stale shortage explanation")
	worker._food.state=""
	worker.sleep=1.0; worker._mood.thermal_memory.cold=0.0
	rested = _other(224,Vector3i(50,20,45))
	rested.sleep=.1; rested._food.value=1.0
	unhappy = _other(225,Vector3i(56,20,45))
	unhappy._food.value=1.0
	unhappy._mood.thermal_memory.cold=12.0
	unhappy._mood.record_dining("neither")
	_expect(concern_script.describe(unhappy).reason=="Slept in the cold","mood shows the strongest negative thought")
	for agent in [worker,rested,unhappy]:
		agent.reparent(director)
		director._agents.append(agent)
	camera = Camera3D.new()
	scene.add_child(camera)
	camera.current=true
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=28
	_frame_camera()
	indicators = load("res://scripts/ui/DwarfNeedIndicators.gd").new()
	indicators.dwarf_director_path=NodePath("../Dwarves")
	scene.add_child(indicators)
	indicators.set_process(false)
	explorer = load("res://scripts/ui/ObjectExplorerController.gd").new()
	explorer.window_manager_path=NodePath("../Windows")
	explorer.dwarf_director_path=NodePath("../Dwarves")
	scene.add_child(explorer)
	_render_fixture()
	await process_frame; await process_frame
	indicators._process(1.0)
	_expect(indicators._entries.size()==3,"one badge per troubled dwarf")
	for entry in indicators._entries.values():
		_expect(entry.icon.visible and entry.icon.mouse_filter==Control.MOUSE_FILTER_IGNORE,"visible badges leave world input alone")
	var original: Dictionary = worker.serialize_state()
	var screen := camera.unproject_position(worker.position+Vector3.UP*2)
	_click(screen)
	await process_frame
	_expect(explorer._object_id==worker,"clicking the marked dwarf opens its normal inspector")
	var panel = explorer._dwarf_panel
	_expect(panel._concern_box.visible and "No reachable food" in panel._concern_title.text,"inspector exposes the same current concern")
	_expect("Harvest berries" in panel._concern_help.text,"inspector explains how to help")
	_expect(worker.serialize_state()==original,"display and selection do not mutate saved needs or inventory")
	# No ordinary-sleep warning; an unresolved bed search reports its actual stage.
	rested._sleeping=true; rested._rest_behavior.state="sleeping"
	_expect(concern_script.describe(rested).is_empty(),"settled sleepers are recovering, not asking for intervention")
	rested._rest_behavior.state="finding_bed"
	_expect(concern_script.describe(rested).reason=="Needs sleep","unfinished bed search never claims there are no beds")
	rested._rest_behavior.state="searching"
	_expect(concern_script.describe(rested).reason=="No available bed found","failed bed search explains the fallback")
	rested._sleeping=false; rested._rest_behavior.state=""
	# Hidden slices and opaque rock must never reveal an actor through a badge.
	var entry: Dictionary = indicators._entries[worker.get_instance_id()]
	worker.apply_slice(20); indicators._process(.3)
	_expect(not entry.icon.visible,"sliced-away dwarf loses its badge immediately")
	worker.apply_slice(127)
	var head: Vector3 = load("res://scripts/components/ObjectPicking.gd").visible_world_bounds(worker._head).get_center()
	var ray_start := camera.project_ray_origin(camera.unproject_position(head))
	var blocker := Vector3i((head+(ray_start-head).normalized()*4).floor())
	world.set_block(blocker.x,blocker.y,blocker.z,blocks.get_id("base:terrain:rock:rock01"))
	indicators._process(.3)
	_expect(not entry.icon.visible,"solid terrain occludes the overhead indicator")
	world.set_block(blocker.x,blocker.y,blocker.z,blocks.AIR_ID)
	indicators._process(.3)
	_expect(entry.icon.visible,"removing occlusion restores the indicator while paused")
	camera.size=350; indicators._process(.3)
	_expect(not entry.icon.visible,"far overview suppresses unreadable badges")
	camera.size=28
	# Actual loading gate owns all CanvasLayer visibility, including this one.
	var gate = load("res://scripts/ui/WorldLoadingScreen.gd").new()
	scene.add_child(gate)
	gate.set_process(false)
	_expect(not indicators.visible,"loading gate hides need indicators")
	gate._reveal()
	_expect(indicators.visible,"world reveal restores indicators")
	gate.free()
	# Live disappearance and reconstruction from existing saved need data.
	worker._food.value=1.0
	indicators._process(.3); explorer._refresh_selected()
	_expect(not entry.icon.visible and not panel._concern_box.visible,"resolving hunger clears both presentations")
	worker.restore_saved_runtime(original)
	indicators._process(.3); explorer._refresh_selected()
	_expect(entry.icon.visible and panel._concern_box.visible,"restored serious hunger needs no extra save fields")
	worker._food.shortage=true
	for viewport: Vector2i in [Vector2i(1280,720),Vector2i(1680,720),Vector2i(2560,720)]:
		root.size=viewport
		_frame_camera()
		for i in 4: await process_frame
		indicators._process(1.0); explorer._refresh_selected()
		for item in indicators._entries.values():
			_expect(item.icon.visible and is_equal_approx(item.icon.size.x,28.8),"same readable badge width at %s" % viewport)
		_expect(panel._follow.get_global_rect().end.y<=viewport.y,"inspector actions remain reachable at %s" % viewport)
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute(OUT)
		root.get_texture().get_image().save_png(OUT+"needs_%dx%d.png" % [viewport.x,viewport.y])
	var removed_id: int = unhappy.get_instance_id()
	director._agents.erase(unhappy); unhappy.free()
	indicators.refresh()
	_expect(not indicators._entries.has(removed_id),"removed dwarves leave no orphan badges")
	for failure in failures: push_error(failure)
	print("DWARF_NEED_INDICATORS_OK" if failures.is_empty() else "DWARF_NEED_INDICATORS_FAIL")
	quit(0 if failures.is_empty() else 1)


func _frame_camera() -> void:
	var target := Vector3(50,23,45)
	camera.position=target+Vector3(3,23,32)
	camera.look_at(target)


func _render_fixture() -> void:
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode=Environment.BG_COLOR
	env.background_color=Color("293238")
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color=Color.WHITE
	env.ambient_light_energy=.7
	environment.environment=env
	scene.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees=Vector3(-50,-30,0)
	sun.shadow_enabled=true
	scene.add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size=Vector3(44,.2,28)
	floor_mesh.mesh=box
	floor_mesh.position=Vector3(50,20.9,45)
	var mat := StandardMaterial3D.new()
	mat.albedo_color=Color("645e4e")
	floor_mesh.material_override=mat
	scene.add_child(floor_mesh)
