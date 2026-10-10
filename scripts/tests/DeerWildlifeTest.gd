extends "res://scripts/tests/ObjectExplorerTest.gd"
## Complete support/stride checks, shared needs, herd steering, articulated art,
## inspection, audio routing and mixed-species persistence in real voxel terrain.
var Navigation
var wildlife
var deer
var clock_node

func _run() -> void:
	create_timer(60).timeout.connect(func(): push_error("Deer test timed out"); quit(1))
	Navigation = load("res://scripts/components/AnimalNavigation.gd")
	for service in ["SaveManager","TaskManager","RoomManager","WorldClock"]: root.get_node(service).set_process(false)
	clock_node = root.get_node("WorldClock")
	clock_node.set_paused(false)
	clock_node.set_speed(1)
	clock_node.hour = 12
	world = root.get_node("WorldData")
	blocks = root.get_node("BlockRegistry")
	_build_floor()
	var grass: int = blocks.get_id("base:terrain:surface:grass_01")
	for x in range(20,80):
		for z in range(20,80): world.set_block(x,20,z,grass)
	scene = Node3D.new()
	root.add_child(scene)
	current_scene = scene
	wildlife = load("res://scripts/systems/WildlifeManager.gd").new()
	scene.add_child(wildlife)
	wildlife.set_process(false)
	wildlife.initialized = true
	wildlife.deer_initialized = true
	deer = wildlife.add_deer("deer:fixture:40:40",Vector3i(40,21,40),543,"herd:test")
	var mate = wildlife.add_deer("deer:fixture:48:40",Vector3i(48,21,40),544,"herd:test")
	var rabbit = wildlife.add_rabbit("rabbit:fixture",Vector3i(34,21,40),545)
	manager = load("res://scripts/ui/UIWindowManager.gd").new()
	manager.name = "Windows"
	scene.add_child(manager)
	manager._layout_loaded = false
	explorer = load("res://scripts/ui/ObjectExplorerController.gd").new()
	explorer.window_manager_path = NodePath("../Windows")
	scene.add_child(explorer)
	camera = Camera3D.new()
	scene.add_child(camera)
	camera.current = true
	_aim_above(deer.position)
	camera.set_meta("work_focus",deer.position)
	camera.set_meta("work_zoom",12.0)
	await process_frame
	var box: AABB = wildlife.get_explorer_bounds(deer)
	_expect(box.position.y == 21 and box.size.y > 3 and box.size.y < 4 and box.size.x <= 2 and box.size.z <= 2,"deer stands inside its wider four-cell envelope")
	_expect(wildlife.pick_explorer_object(box.get_center()+Vector3.UP*10,box.get_center()-Vector3.UP*3).get("id") == deer,"deer meshes are selectable")
	var events: Array = []
	var feedback := root.get_node("WorkFeedback")
	feedback.sound_started.connect(func(kind,_p,_v): events.append(kind))
	clock_node.set_paused(true)
	_expect(explorer.select_object(wildlife,deer),"deer opens shared inspector")
	_expect(explorer._name_label.text == "Wild Deer" and events == ["deer_select"],"deer identity and paused selection sound use deer definition")
	var data: Dictionary = wildlife.get_explorer_data(deer)
	_expect(data.rows.back() == ["Herd","2 deer"],"inspector reports saved herd membership")
	var snapshot: Dictionary = wildlife.serialize_state()
	wildlife.advance(10,[])
	_expect(snapshot == wildlife.serialize_state(),"pause freezes both species")
	wildlife.apply_slice(20)
	_expect(wildlife.get_explorer_data(deer).is_empty(),"deer respects slice concealment")
	wildlife.apply_slice(127)
	clock_node.set_paused(false)
	deer.hunger = .7
	deer.fatigue = 0
	deer.timer = 0
	wildlife.advance(.01,[])
	_expect(deer.activity == "Grazing" and deer.head.rotation.x > 1 and deer.neck.rotation.x < -2,"neck/head joints form grazing pose")
	for phase in [0.0,PI/10.0,3.0*PI/10.0]:
		deer.pose_time = phase
		deer._pose()
		var grazing_box: AABB = wildlife.get_explorer_bounds(deer)
		_expect(grazing_box.position.y >= 20.99 and grazing_box.position.z >= 38.99 and grazing_box.end.z <= 42.01,"grazing muzzle and antlers stay above the checked standing/reach area: %s" % grazing_box)
	feedback.clear_transients()
	wildlife.advance(.85,[])
	_expect(events.back() == "deer_graze","deer meal uses its own cue timing and sound bank")
	for i in range(80): wildlife.advance(.1,[])
	_expect(deer.hunger < .2 and world.get_block(40,20,40) == grass,"gentle grazing satisfies hunger without terrain or crop damage")
	deer.restore_state(snapshot.deer[0])
	deer.activity = "Grazing"
	deer.hunger = .7
	deer.timer = 4
	var obstruction: int = root.get_node("PlacedEntityRegistry").register_box(Vector3i(40,21,39),Vector3i(2,4,1))
	_expect(not deer.can_graze(),"grazing reach refuses a wall beyond the standing footprint")
	wildlife.advance(.01,[])
	_expect(deer.activity != "Grazing" and deer.hunger >= .7,"new obstruction interrupts grazing without granting a meal")
	root.get_node("PlacedEntityRegistry").unregister(obstruction)
	deer.restore_state(snapshot.deer[0])
	deer.hunger = .1
	deer.fatigue = .8
	deer.timer = 0
	wildlife.advance(.01,[])
	_expect(deer.activity == "Sleeping" and deer.visual.scale == Vector3.ONE,"deer rests with folded legs and a full-size body")
	var rest_box: AABB = wildlife.get_explorer_bounds(deer)
	_expect(rest_box.position.y >= 20.99 and rest_box.position.z >= 39.99 and rest_box.end.z <= 42.01,"resting deer stays above ground inside its footprint")
	for i in range(100): wildlife.advance(.1,[])
	_expect(deer.fatigue < .8,"sleep restores fatigue")
	wildlife.advance(.01,[deer.position+Vector3(-5,0,0)])
	_expect(deer.activity == "Fleeing" and deer.hop_seconds < .4,"danger wakes deer into a fast stride")
	_expect(2.0/float(wildlife.deer_definition.navigation.flee_hop_seconds) > 1.0/float(wildlife.definition.navigation.flee_hop_seconds),"deer flee faster than rabbits")
	_navigation_checks()
	# Separate herd steering from urgent needs and confirm it cannot consume rabbit RNG.
	deer.restore_state(snapshot.deer[0])
	mate.restore_state(snapshot.deer[1])
	mate.position.x = 61
	mate.cell.x = 60
	mate.target = mate.cell
	wildlife._update_herd_context(deer)
	_expect(deer._movement_score(Vector3i(42,21,40)) > deer._movement_score(Vector3i(38,21,40)),"loose cohesion prefers moving toward a distant herd")
	mate.position = Vector3(43,21,41)
	mate.cell = Vector3i(42,21,40)
	mate.target = mate.cell
	wildlife._update_herd_context(deer)
	_expect(not deer._can_enter(mate.cell),"deer avoid occupied peer footprints")
	mate.restore_state(snapshot.deer[1])
	deer._hop(Vector3i(42,21,40))
	wildlife.advance(.15,[])
	_expect(deer.legs[0].rotation.x * deer.legs[1].rotation.x < 0,"walking alternates diagonal legs")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(wildlife.serialize_state()))
	wildlife.restore_state(saved)
	deer = wildlife.animals_of_species("deer")[0]
	_expect(wildlife.animals_of_species("rabbit").size() == 1 and wildlife.animals_of_species("deer").size() == 2,"mixed populations replace without duplicates")
	_expect(deer.herd_id == "herd:test" and is_equal_approx(deer.hop_progress,float(saved.deer[0].hop_progress)),"herd and partial stride survive JSON restore")
	var replay: Dictionary = wildlife.serialize_state()
	for i in range(20): wildlife.advance(.05,[])
	var future: Dictionary = wildlife.serialize_state()
	wildlife.restore_state(replay)
	for i in range(20): wildlife.advance(.05,[])
	_expect(future == wildlife.serialize_state(),"mixed-species decisions resume deterministically")
	wildlife.restore_state({"initialized":true,"rabbits":saved.rabbits})
	_expect(not wildlife.deer_initialized and wildlife.animals_of_species("rabbit").size() == 1,"rabbit-only save requests one-time deer seeding")
	wildlife.restore_state({"initialized":true,"rabbits":[],"deer_initialized":true,"deer":[]})
	_expect(wildlife.animals.is_empty() and wildlife.deer_initialized,"explicit empty deer population does not respawn")
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("DEER_WILDLIFE_OK")
	quit(0 if failures.is_empty() else 1)

func _navigation_checks() -> void:
	var from := Vector3i(60,21,60)
	var to := Vector3i(62,21,60)
	_expect(Navigation.can_hop(from,to,4,2),"two-cell deer stride is traversable")
	var handle: int = root.get_node("PlacedEntityRegistry").register_box(Vector3i(63,21,61),Vector3i(1,4,1))
	_expect(not Navigation.can_hop(from,to,4,2),"far corner occupancy blocks whole deer footprint")
	root.get_node("PlacedEntityRegistry").unregister(handle)
	world.set_block(63,20,61,0)
	_expect(not Navigation.can_hop(from,to,4,2),"missing corner support prevents crossing a pit")
	var stone: int = blocks.get_id("base:terrain:rock:rock01")
	world.set_block(63,20,61,stone)
	for x in [62,63]:
		for z in [60,61]: world.set_block(x,21,z,stone)
	_expect(Navigation.can_hop(from,to+Vector3i.UP,4,2),"deer can stride onto a supported terrace")
	world.set_block(60,25,61,stone)
	_expect(not Navigation.can_hop(from,to+Vector3i.UP,4,2),"antler clearance is swept across the step")
	world.set_block(60,25,61,0)
	_expect(not Navigation.can_hop(from,to+Vector3i(0,2,0),4,2),"deer refuses a two-block cliff")
	_expect(not Navigation.can_hop(from,from+Vector3i(1,0,1),4,2),"diagonal shortcut cannot bypass swept columns")
