extends "res://scripts/tests/ObjectExplorerTest.gd"

var wildlife
var duck
var water
var clock_node
var geometry := {}

func _run() -> void:
	create_timer(120).timeout.connect(func(): push_error("Duck test timed out"); quit(1))
	for service in ["SaveManager","TaskManager","RoomManager","WorldClock","WaterManager"]: root.get_node(service).set_process(false)
	clock_node = root.get_node("WorldClock")
	clock_node.paused = false
	clock_node.speed = 1
	world = root.get_node("WorldData")
	blocks = root.get_node("BlockRegistry")
	_build_floor()
	# A broad pool and a bank, represented by actual terrain and finite water.
	for x in range(32,75):
		for z in range(32,65):
			world.set_block(x,20,z,0)
			geometry[Vector2i(x,z)] = [Vector2i(20,128)]
	water = root.get_node("WaterManager")
	water.flow = load("res://scripts/components/WaterFlow.gd").new()
	water.flow.spans_at = func(col: Vector2i): return geometry.get(col,[Vector2i(21,128)])
	water.initialized = true
	for col: Vector2i in geometry: water.flow.seed_column(Vector3i(col.x,20,col.y),.75)
	scene = Node3D.new()
	root.add_child(scene)
	current_scene = scene
	wildlife = load("res://scripts/systems/WildlifeManager.gd").new()
	scene.add_child(wildlife)
	wildlife.set_process(false)
	wildlife.initialized = true
	wildlife.deer_initialized = true
	wildlife.wolf_initialized = true
	wildlife.duck_initialized = true
	duck = wildlife.add_duck("duck:test",Vector3i(40,20,40),421,"test-flock")
	var navigation = wildlife.duck_navigation
	_expect(is_equal_approx(duck.position.y,20.47),"duck floats on the finite surface with submerged feet")
	var bounds: AABB = wildlife.get_explorer_bounds(duck)
	_expect(bounds.size.y<1.3 and bounds.size.x<1.5,"compact voxel duck fits amphibious clearance")
	_expect(wildlife.pick_explorer_object(bounds.get_center()+Vector3.UP*10,bounds.get_center()-Vector3.UP*2).get("id")==duck,"duck is selectable through actual model geometry")
	_expect(wildlife.get_explorer_data(duck).title=="Wild Duck","duck has shared wildlife inspector")
	var start: Dictionary = duck.serialize_state()
	var validator = load("res://scripts/components/SaveSnapshotValidator.gd")
	_expect(validator._validate(start,"duck","duck").is_empty(),"current duck save is valid")
	for pair: Array in [["sex","invalid"],["mode","invalid"],["flight_index",-1],["flight",[[0,0]]],["launch_left",-1],["hop_seconds",0],["position",[1,999,1]]]:
		var malformed := start.duplicate(true)
		malformed[pair[0]] = pair[1]
		_expect(not validator._validate(malformed,"duck","duck").is_empty(),"reject invalid duck "+pair[0])
	clock_node.paused = true
	wildlife.advance(10,[])
	_expect(duck.serialize_state()==start,"pause freezes duck decisions, needs and pose")
	clock_node.paused = false
	clock_node.speed = 2
	wildlife.advance(.1,[])
	var fast: Dictionary = duck.serialize_state()
	duck.restore_state(start)
	clock_node.speed = 1
	wildlife.advance(.2,[])
	_expect(duck.serialize_state()==fast,"speed scales duck motion and needs together")
	duck.restore_state(start)
	duck.hunger = .8
	duck.timer = 0
	wildlife.advance(.01,[])
	_expect(duck.activity=="Grazing","duck dabbles when hungry")
	for i in 52: wildlife.advance(.1,[])
	_expect(duck.hunger<.4,"completed forage relieves hunger")
	duck.restore_state(start)
	duck.timer = 0
	duck.definition.behavior.preen_chance = 0
	wildlife.advance(.01,[])
	_expect(duck.hop_progress<1,"duck starts swimming")
	wildlife.advance(.2,[])
	_expect(duck.position.distance_to(Vector3(40.5,20.47,40.5))>.1,"swimming moves continuously")
	_expect(duck._wake.visible,"swimming produces a small wake")
	wildlife.apply_slice(19)
	_expect(not duck.visible and not duck._wake.visible,"slicing hides both duck and wake")
	wildlife.apply_slice(127)
	_expect(wildlife._visible_at(Vector3(40,135,40)),"full-world view includes birds above terrain height")
	_round_trip_future("swimming")
	duck.restore_state(start)
	var destination: Dictionary = navigation.surface(Vector2i(65,50))
	var path: PackedVector3Array = navigation.flight_path(duck.position,destination.position)
	_expect(path.size()>2,"open pool has a swept flight route")
	duck.begin_flight(path,destination.cell)
	for i in 20: wildlife.advance(.05,[])
	_expect(duck.mode=="air" and duck.position.y>21,"takeoff climbs above the surface")
	_round_trip_future("airborne")
	for i in 200: wildlife.advance(.05,[])
	_expect(duck.mode=="water" and duck.position.y<21,"flight finishes on live water")
	duck.restore_state(start)
	duck.begin_flight(path,destination.cell)
	duck.launch_left = 0
	var blocked := Vector3i(path[1].floor())
	water.initialized = false # This fixture supplies its own unchanged water spans.
	world.set_block(blocked.x,blocked.y,blocked.z,blocks.get_id("base:terrain:rock:rock01"))
	water.initialized = true
	for i in 12:
		wildlife.advance(.02,[])
		if duck.flight.is_empty(): break
	_expect(duck.flight.is_empty() and navigation.clear_body(duck.position,.5),"new terrain blocks an already planned flight before contact")
	water.initialized = false
	world.set_block(blocked.x,blocked.y,blocked.z,0)
	water.initialized = true
	duck.restore_state(start)
	wildlife.advance(.01,[duck.position+Vector3(2,0,0)])
	_expect(duck.mode=="air" and duck.activity=="Taking off","nearby dwarf startles duck into short flight")
	duck.restore_state(start)
	# Rising water changes height without deleting/adding water for ducks.
	for key: Vector3i in water.flow.mass: water.flow.mass[key] = 950000
	wildlife.advance(.2,[])
	_expect(is_equal_approx(duck.position.y,20.67),"duck tracks rising water")
	var volume: float = water.flow.total_volume()
	wildlife.advance(.1,[])
	_expect(water.flow.total_volume()==volume,"wildlife never changes water volume")
	for key: Vector3i in water.flow.mass: water.flow.mass[key] = 750000
	var bank: Dictionary = navigation.surface(Vector2i(31,40))
	var edge: Dictionary = navigation.surface(Vector2i(32,40))
	_expect(navigation.neighbors(edge).any(func(p): return p.cell==bank.cell),"duck can climb from water onto a real bank")
	duck._settle(bank)
	duck.flight_left = 100
	duck.calm_left = 0
	duck.timer = 0
	duck.hunger = .1
	duck.fatigue = .95
	wildlife.advance(.01,[])
	_expect(duck.activity=="Sleeping","exhausted duck rests on the bank")
	# A real cliff outlet makes nearby water unsuitable even if depth is ample.
	geometry[Vector2i(75,50)] = [Vector2i(15,128)]
	water.flow.terrain_changed(Vector2i(75,50))
	_expect(navigation.surface(Vector2i(73,50)).is_empty(),"duck avoids waterfall approaches")
	# Full canopy bounds block flying even when trunk occupancy would not.
	flora = load("res://scripts/systems/SurfaceFloraSpawner.gd").new()
	scene.add_child(flora)
	flora.set_process(false)
	var tree := Node3D.new()
	flora.add_child(tree)
	tree.set_meta("tree_id",Vector2i(50,40))
	flora._loaded_columns[Vector2i(3,2)] = [tree]
	flora._trees[Vector2i(50,40)] = {"bounds":AABB(Vector3(45,21,35),Vector3(10,20,10))}
	navigation.flora = flora
	_expect(not navigation.segment_clear(Vector3(40,30,40),Vector3(60,30,40),1.3,true),"air sweep rejects canopy overhang")
	_expect(navigation.segment_clear(Vector3(40,44,40),Vector3(60,44,40),1.3,true),"air sweep permits clear air above trees")
	# Disappearing water initiates a real escape; it must never strand a swimmer.
	duck.restore_state(start)
	for x in range(38,43):
		for z in range(38,43): water.flow.mass.erase(Vector3i(x,20,z))
	wildlife.advance(.1,[])
	_expect(duck.mode=="air","draining a pool triggers relocation")
	if failures.is_empty(): print("DUCK_WILDLIFE_OK")
	else:
		for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _round_trip_future(label: String) -> void:
	var state: Dictionary = JSON.parse_string(JSON.stringify(wildlife.serialize_state(),"",false,true))
	for i in 30: wildlife.advance(.02,[])
	var expected: Dictionary = wildlife.serialize_state()
	wildlife.restore_state(state)
	duck = wildlife.animals[0]
	for i in 30: wildlife.advance(.02,[])
	var actual: Dictionary = wildlife.serialize_state()
	_expect(is_equal_approx(expected.ducks[0].pose_time,actual.ducks[0].pose_time),label+" animation phase survives JSON rounding")
	actual.ducks[0].pose_time = expected.ducks[0].pose_time
	_expect(actual==expected,label+" JSON resumes identical decisions and motion")
