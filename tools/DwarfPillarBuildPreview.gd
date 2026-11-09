extends "res://scripts/tests/ConstructionTest.gd"

## A real builder on a real order: one 1x1 stone pillar, three blocks tall, from the stone stockpile.
## Nothing is posed by hand. Records frames and every part from the first hammer blow until well
## after the job ends, to see what a builder does when it stops hammering.
## Run with a rendering device (no --headless), in an isolated profile.
const OUT := "res://tmp/pillar_build_20261103/"
const PILLAR: Array[Vector3i] = [Vector3i(44,21,40),Vector3i(44,22,40),Vector3i(44,23,40)]
const STEP := 1.0/60.0
const CAPTURE_EVERY := 3
const AFTER_SECONDS := 8.0
## With --leave: the builder is sent off with the top block unfinished, as when it runs out of stone
## or another job takes it. The first run of this scene missed that: it always finished the order.
var leave := false
var left := false
## With --mine: a real miner on two real rock blocks in place of the pillar, through to walking off.
var mining := false
## With --approach: recording starts as the builder walks to the pillar, with a fixed side camera.
var approach := false
var rock_shown: Array = []
var views := {}
var shown := {}
var log_rows: Array = []
var frame := 0


func _stage() -> void:
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(.14,.18,.2)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = .8
	environment.environment = env
	scene.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48,-35,0)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	scene.add_child(sun)
	var a := StandardMaterial3D.new()
	a.albedo_color = Color(.34,.39,.4)
	var b := StandardMaterial3D.new()
	b.albedo_color = Color(.29,.33,.34)
	var tile := BoxMesh.new()
	tile.size = Vector3(1,.2,1)
	for x in range(34,56):
		for z in range(30,52):
			var m := MeshInstance3D.new()
			m.mesh = tile
			m.material_override = a if (x+z)%2==0 else b
			scene.add_child(m)
			m.position = Vector3(x+.5,20.9,z+.5)
	root.get_node("SkyController").set_process(false)
	for key in ["near","side","back"]:
		var view := SubViewport.new()
		view.size = Vector2i(420,420)
		view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		view.msaa_3d = Viewport.MSAA_4X
		root.add_child(view)
		var camera3d := Camera3D.new()
		view.add_child(camera3d)
		camera3d.current = true
		camera3d.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera3d.size = 6.5
		views[key] = {"view":view,"camera":camera3d}


func _show_blocks() -> void:
	var done := _completed_cells()
	for cell: Vector3i in PILLAR:
		if done.has(cell) and not shown.has(cell):
			var m := MeshInstance3D.new()
			var box := BoxMesh.new()
			m.mesh = box
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(.6,.55,.46)
			m.material_override = mat
			scene.add_child(m)
			m.position = Vector3(cell)+Vector3.ONE*.5
			shown[cell] = m


func _aim() -> void:
	var look: Vector3 = worker.global_position+Vector3(0,1.7,.0)
	var basis: Basis = worker.global_basis
	if approach:
		look = Vector3(42.5,22.7,40.5)
		basis = Basis.IDENTITY.rotated(Vector3.UP,PI/2)
	views.near.camera.global_position = look+basis*Vector3(-9,7.5,3)
	views.near.camera.look_at(look)
	views.side.camera.global_position = look+basis*Vector3(-14,0,0)
	views.side.camera.look_at(look)
	views.back.camera.global_position = look+basis*Vector3(0,8,-8)
	views.back.camera.look_at(look)


func _step_world() -> void:
	worker._food.value = 1.0
	worker.sleep = 1.0
	construction._process(STEP)
	tasks._run_scheduler()
	worker._process(STEP)


func _log(t: float) -> void:
	var idle = worker._idle_behavior
	var head_front: Vector3 = worker._head.global_transform*Vector3(0,2.45,.75)
	var cell: Vector3i = worker.current_cell()
	var drawn: Vector3 = worker._body.global_position
	log_rows.append({"t":snappedf(t,.001),"drawn":[drawn.x,drawn.y,drawn.z],"phase":int(worker._task_phase),"task":worker.current_task_id,
		"idle":String(idle.state),"path":worker._move_path.size(),"pos":str(worker.global_position),"yaw":snappedf(worker.rotation.y,.001),
		"body":str(worker._body.position),"head":str(worker._head.position),"foot_l":str(worker._foot_l.position),"foot_r":str(worker._foot_r.position),
		"head_front":str(head_front),"cell":str(cell),"done":_completed_cells().size(),"tool":is_instance_valid(worker._construction_pose.tool) and worker._construction_pose.tool.visible,
		"stand_back":worker._rig._stand_back,"spot":worker._rig._work_spot,"wall":worker._rig._wall_at_face()})


func _record_frame() -> void:
	await RenderingServer.frame_post_draw
	await process_frame
	await RenderingServer.frame_post_draw
	for key: String in views:
		views[key].view.get_texture().get_image().save_png("%s%s_%04d.png" % [OUT,key,frame])
	frame += 1


func _run() -> void:
	leave = "--leave" in OS.get_cmdline_user_args()
	mining = "--mine" in OS.get_cmdline_user_args()
	approach = "--approach" in OS.get_cmdline_user_args()
	await _setup_fixture()
	await _new_trip(STONE,12)
	stockpiles.reset_runtime_state()
	stockpiles._process(0)
	nav = root.get_node("NavGrid")
	root.get_node("WorldGenerator")._cache_block_ids()
	mine = load("res://scripts/systems/MiningDesignationController.gd").new()
	scene.add_child(mine)
	mine.set_process(false)
	mine.set_process_unhandled_input(false)
	construction = load("res://scripts/systems/ConstructionController.gd").new()
	construction.mining = mine
	scene.add_child(construction)
	construction.set_process(false)
	construction.set_process_unhandled_input(false)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	root.size = Vector2i(320,180)
	_stage()
	DirAccess.make_dir_recursive_absolute(OUT)
	var cells: Array[Vector3i] = PILLAR
	var id := -1
	var ended: Callable
	if mining:
		var rock: Array[Vector3i] = [Vector3i(44,22,40),Vector3i(44,21,40)]
		for cell in rock:
			world.set_block(cell.x,cell.y,cell.z,blocks.get_id("base:terrain:rock:rock01"))
			var m := MeshInstance3D.new()
			m.mesh = BoxMesh.new()
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(.57,.6,.62)
			m.material_override = mat
			scene.add_child(m)
			m.position = Vector3(cell)+Vector3.ONE*.5
			rock_shown.append([cell,m])
		mine._create_zone(rock)
		ended = func(): return worker.current_task_id < 0 and worker._mining_pose.tool != null and not worker._mining_pose.tool.visible
	else:
		id = construction.create_order(cells)
		ended = func(): return left or not construction.orders.has(id)
	var reached := false
	for i in range(20000):
		_step_world()
		tasks.advance_supervision(STEP)
		if approach and worker._task_phase == worker.TaskPhase.FETCH_TO_GHOST:
			reached = true
			break
		if mining and worker._task_phase == worker.TaskPhase.ZONE_SWINGING:
			reached = true
			break
		if worker._task_phase == worker.TaskPhase.FETCH_WORKING and is_instance_valid(worker._construction_pose.tool) and worker._construction_pose.tool.visible:
			reached = true
			break
		if i%200 == 0: await process_frame
	print("REACHED_WORK ",reached," pos ",worker.global_position," yaw ",worker.rotation.y)
	var t := 0.0
	var finished_at := -1.0
	var tick := 0
	while finished_at < 0.0 or t < finished_at+AFTER_SECONDS:
		if left: worker._process(STEP)
		else:
			_step_world()
			tasks.advance_supervision(STEP)
		t += STEP
		if not mining: _show_blocks()
		for pair: Array in rock_shown:
			if world.get_live_block(pair[0].x,pair[0].y,pair[0].z) == blocks.AIR_ID: pair[1].hide()
		_log(t)
		if not mining and leave and not left and _completed_cells().size() >= 2:
			left = true
			finished_at = t
			var stand: Vector3i = worker.current_cell()+Vector3i(-1,0,-3)
			print("LEFT_AT t=",t," drawn ",worker._body.global_position," walking to ",stand)
			worker._release_task_for_need()
			worker.walk_to(stand)
		if finished_at < 0.0 and ended.call():
			finished_at = t
			print("ORDER_FINISHED t=",t," frame ",frame," pos ",worker.global_position," yaw ",worker.rotation.y)
		if tick%CAPTURE_EVERY == 0:
			_aim()
			await _record_frame()
		tick += 1
		if t > 240.0: break
	var file := FileAccess.open(OUT+"log.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"finished_at":finished_at,"rows":log_rows}))
	file.close()
	print("PILLAR_PREVIEW_OK frames ",frame," finished_at ",finished_at)
	quit(0)
