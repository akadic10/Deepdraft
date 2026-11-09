extends "res://scripts/tests/TreeFellingTest.gd"

## Doc 298: a dwarf walks to where it will swing, rather than to its cell centre and then sliding back.
## The owner saw this on tree felling. Runs the real job from four sides, and measures how far the
## drawn body retreats from the trunk after its closest approach. The spot it walks to belongs to
## that walk alone: a meal's walk after an interrupted one, and a replanned walk whose new route
## ends on a step, never head for it (project review 2026-11-09).
const STEP := 1.0/60.0
const STARTS := [Vector3(34.5,21,40.5),Vector3(46.5,21,40.5),Vector3(40.5,21,34.5),Vector3(40.5,21,46.5)]
const OUT := "res://tmp/tree_arrival_20261103/"
var capture := false
var views := {}
var frame := 0


func _approach(index: int) -> void:
	var tree_id := Vector2i(40,40)
	var tree := _spawn_tree("oak","mature",tree_id)
	var trunk := Vector2(tree.position.x,tree.position.z)
	flora.designate_felling(tree_id)
	worker.position = STARTS[index]
	worker.rotation = Vector3.ZERO
	var closest := INF
	var retreat := 0.0
	var fastest := 0.0
	var previous: Vector3 = worker._body.global_position
	var worked := 0.0
	var walked := 0.0
	var ticks := 0
	while worked < 1.0 and ticks < 3000:
		ticks += 1
		tasks._run_scheduler()
		worker._food.value = 1.0
		worker.sleep = 1.0
		worker._process(STEP)
		var drawn: Vector3 = worker._body.global_position
		var gap := Vector2(drawn.x,drawn.z).distance_to(trunk)
		closest = minf(closest,gap)
		if worker.get_move_path().is_empty(): retreat = maxf(retreat,gap-closest)
		else: retreat = maxf(retreat,0.0)
		walked += Vector2(drawn.x-previous.x,drawn.z-previous.z).length() if ticks > 1 else 0.0
		if ticks > 30: fastest = maxf(fastest,Vector2(drawn.x-previous.x,drawn.z-previous.z).length()/STEP)
		previous = drawn
		if worker._task_phase == worker.TaskPhase.FELL_WORKING: worked += STEP
		if capture and index == 0 and gap < 4.0 and ticks%3 == 0: await _record()
		if ticks%60 == 0: await process_frame
	print("ARRIVAL side %d: walked %.2f, cell %s, retreat %.3f, fastest %.2f blocks/s" % [index,walked,worker.current_cell(),retreat,fastest])
	_expect(walked > 1.0,"side %d really walks to the tree (%.2f)" % [index,walked])
	_expect(worked > 0.0,"the job reaches felling from side %d" % index)
	_expect(retreat < .15,"no slide back on arrival from side %d (%.2f)" % [index,retreat])
	_expect(fastest < 4.5,"the body never outruns a walk from side %d (%.2f)" % [index,fastest])
	worker.abort_task()
	flora.cancel_felling(tree_id)


## Already on the stand, there is no walk to shorten: the body still moves back to its swing, and the
## feet must step there rather than slide. A foot on the ground stays put, and one foot moves at a time.
func _from_the_spot() -> void:
	var tree_id := Vector2i(40,40)
	_spawn_tree("oak","mature",tree_id)
	worker.position = Vector3(39.5,21,40.5)
	worker.rotation = Vector3(0,PI/2,0)
	worker._rig.reset_part_offsets()
	worker._rig.finish_frame(1.0)
	flora.designate_felling(tree_id)
	var feet: Array = [worker._foot_l,worker._foot_r]
	var previous: Array = feet.map(func(foot): return foot.global_position)
	var ground: float = feet[0].global_position.y
	var skate := 0.0
	var highest := 0.0
	var both_up := 0
	var body_moved := 0.0
	var body_start: Vector3 = worker._body.global_position
	var worked := 0.0
	for tick in range(240):
		tasks._run_scheduler()
		worker._food.value = 1.0
		worker.sleep = 1.0
		worker._process(STEP)
		if worker._task_phase == worker.TaskPhase.FELL_WORKING: worked += STEP
		if worked <= 0.0:
			previous = feet.map(func(foot): return foot.global_position)
			body_start = worker._body.global_position
			continue
		if worked > .7: break
		body_moved = maxf(body_moved,Vector2(worker._body.global_position.x-body_start.x,worker._body.global_position.z-body_start.z).length())
		var up := 0
		for i in range(2):
			var now: Vector3 = feet[i].global_position
			var lift: float = now.y-ground
			highest = maxf(highest,lift)
			if lift > .02: up += 1
			else: skate += Vector2(now.x-previous[i].x,now.z-previous[i].z).length()
			previous[i] = now
		if up == 2: both_up += 1
		if capture and tick%2 == 0: await _record()
	print("ON_SPOT body moved %.2f, feet slid on the ground %.3f, highest step %.3f, frames both up %d" % [body_moved,skate,highest,both_up])
	_expect(body_moved > .4,"the check sees the body move back (%.2f)" % body_moved)
	_expect(skate < .15,"feet step rather than slide (%.2f)" % skate)
	_expect(highest > .1,"the feet really lift (%.2f)" % highest)
	_expect(both_up <= 2,"one foot steps at a time (%d frames both up)" % both_up)
	worker.abort_task()
	flora.cancel_felling(tree_id)


## Hunger stops a dwarf walking to its stand (DwarfFoodBehavior._leave_work aborts the task), and the
## meal's walk starts on a route already searched. That walk ends at its own last cell, on its route:
## it never heads for the stand's spot, and nothing is drawn standing back from the work.
func _meal_walk_after_stand_walk() -> void:
	var stand := Vector3i(50,20,30)
	var movement = worker._movement
	worker.position = Vector3(44.5,21,30.5)
	worker.rotation = Vector3.ZERO
	_expect(worker.walk_to(stand),"a route to the stand")
	worker.stop_short_of(Vector3(51.0,22,30.5),1.5)
	_expect(movement.arriving,"the walk to the stand ends short of it, where the swing will stand")
	for i in range(20): movement.follow_path(STEP)
	worker.abort_task()
	var route: Array[Vector3i] = root.get_node("NavGrid").find_path(worker.current_cell(),Vector3i(42,20,24))
	_expect(not route.is_empty(),"a route to the meal")
	worker.get_food().start_walk(route)
	var off_route := 0.0
	for i in range(60*20):
		if not worker.is_walking(): break
		movement.follow_path(STEP)
		var at := Vector2(worker.global_position.x,worker.global_position.z)
		var nearest := INF
		for cell: Vector3i in route: nearest = minf(nearest,at.distance_to(Vector2(cell.x+.5,cell.z+.5)))
		off_route = maxf(off_route,nearest)
	print("MEAL_WALK off the route %.2f, ended at %s, drawn back %.2f" % [off_route,worker.global_position,worker._rig._work_spot])
	_expect(not worker.is_walking() and worker.global_position.distance_to(Vector3(42.5,21,24.5)) < .01,"the meal's walk ends at its own last cell")
	_expect(off_route < 1.5,"and keeps to its route, never heading for the stand's spot (%.2f blocks off)" % off_route)
	_expect(worker._rig._work_spot < .01,"nothing is drawn standing back from work (%.2f)" % worker._rig._work_spot)


## A walk to a stand is replanned when its way is blocked. When the new route's last stretch is a
## step down into the stand, the spot short of it would hang over the step, so the walk forgets it.
## A trench leads to the stand; the rest of the ground is one block higher; then the trench's last
## cell is filled.
func _replan_onto_a_step() -> void:
	var stand := Vector3i(50,20,40)
	var rock: int = blocks.get_id("base:terrain:rock:rock01")
	var raised: Array[Vector3i] = []
	for x in range(42,57):
		for z in range(36,45):
			if z != 40 or x > 50: raised.append(Vector3i(x,21,z))
	for cell: Vector3i in raised: world.set_block(cell.x,cell.y,cell.z,rock)
	await process_frame
	await process_frame
	var movement = worker._movement
	worker.position = Vector3(43.5,21,40.5)
	worker.rotation = Vector3(0,PI/2,0)
	_expect(worker.walk_to(stand),"a route along the trench to the stand")
	var path: Array[Vector3i] = worker.get_move_path()
	worker.stop_short_of(Vector3(51.0,22,40.5),1.5)
	_expect(movement.arriving,"the level walk ends short of the stand")
	for i in range(20): movement.follow_path(STEP)
	world.set_block(49,21,40,rock)
	await process_frame
	await process_frame
	var replanned := false
	var rearmed := false
	for i in range(60*20):
		if not worker.is_walking(): break
		movement.follow_path(STEP)
		if not replanned and not is_same(worker.get_move_path(),path) and worker.is_walking():
			replanned = true
			var route: Array[Vector3i] = worker.get_move_path()
			rearmed = movement.arriving
			_expect(route.back() == stand and route[route.size()-2].y != stand.y,"the new route ends with a step down into the stand: %s" % [route])
	_expect(replanned and not rearmed,"the replanned walk forgets the spot short of the stand (replanned %s, kept %s)" % [replanned,rearmed])
	_expect(not worker.is_walking() and worker.global_position.distance_to(Vector3(50.5,21,40.5)) < .01,"and ends on the stand")
	for cell: Vector3i in raised + [Vector3i(49,21,40)]: world.set_block(cell.x,cell.y,cell.z,0)
	await process_frame


func _stage_capture() -> void:
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
	var ground := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(30,.2,30)
	ground.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(.33,.42,.33)
	ground.material_override = material
	scene.add_child(ground)
	ground.position = Vector3(40,20.9,40)
	root.get_node("SkyController").set_process(false)
	for key in ["near","side"]:
		var view := SubViewport.new()
		view.size = Vector2i(420,420)
		view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(view)
		var eye := Camera3D.new()
		view.add_child(eye)
		eye.current = true
		eye.projection = Camera3D.PROJECTION_ORTHOGONAL
		eye.size = 9.0
		views[key] = {"view":view,"camera":eye}
	var look := Vector3(38.5,22.5,40.5)
	views.near.camera.global_position = look+Vector3(-4,9,9)
	views.near.camera.look_at(look)
	views.side.camera.global_position = look+Vector3(0,0,16)
	views.side.camera.look_at(look)
	DirAccess.make_dir_recursive_absolute(OUT)


func _record() -> void:
	await RenderingServer.frame_post_draw
	await process_frame
	await RenderingServer.frame_post_draw
	for key: String in views:
		views[key].view.get_texture().get_image().save_png("%s%s_%04d.png" % [OUT,key,frame])
	frame += 1


func _run() -> void:
	create_timer(120 if "--capture" in OS.get_cmdline_user_args() else 60).timeout.connect(func(): push_error("Arrival test timed out"); quit(1))
	capture = "--capture" in OS.get_cmdline_user_args()
	_setup_fixture()
	if capture: _stage_capture()
	var factory = load("res://scripts/entities/DwarfFactory.gd").new()
	var data: Dictionary = factory.generate(101, {})
	data.erase("stats")
	worker = factory.spawn(data, 101)
	scene.add_child(worker)
	worker.set_process(false)
	tasks.register_dwarf(worker)
	var sides := [] if capture else range(STARTS.size())
	for index: int in sides:
		await _approach(index)
	await _from_the_spot()
	if not capture:
		_meal_walk_after_stand_walk()
		await _replan_onto_a_step()
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("DWARF_WORK_ARRIVAL_OK")
	quit(0 if failures.is_empty() else 1)
