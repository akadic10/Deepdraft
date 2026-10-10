extends "res://scripts/tests/ObjectExplorerTest.gd"
## Real voxel terrain, imported models, clock, occupancy, inspector and JSON
## persistence. No generated world, player storage, worker jobs or item yields.
var Navigation
var wildlife
var rabbit
var clock_node

func _run() -> void:
	Navigation = load("res://scripts/components/AnimalNavigation.gd")
	create_timer(60).timeout.connect(func(): push_error("Rabbit test timed out"); quit(1))
	for service in ["SaveManager", "TaskManager", "RoomManager", "WorldClock"]: root.get_node(service).set_process(false)
	clock_node = root.get_node("WorldClock")
	clock_node.set_paused(false)
	clock_node.set_speed(1)
	world = root.get_node("WorldData")
	blocks = root.get_node("BlockRegistry")
	_build_floor()
	var grass: int = blocks.get_id("base:terrain:surface:grass_01")
	for x in range(20, 64):
		for z in range(20, 64): world.set_block(x, 20, z, grass)
	scene = Node3D.new()
	root.add_child(scene)
	current_scene = scene
	wildlife = load("res://scripts/systems/WildlifeManager.gd").new()
	scene.add_child(wildlife)
	wildlife.set_process(false)
	wildlife.initialized = true
	rabbit = wildlife.add_rabbit("rabbit:fixture:40:40", Vector3i(40,21,40), 1234)
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
	root.size = Vector2i(1280,800)
	_aim_above(rabbit.position)
	await process_frame
	var bounds: AABB = wildlife.get_explorer_bounds(rabbit)
	_expect(bounds.position.y == 21 and bounds.size.y <= 1.6 and bounds.size.x <= 1 and bounds.size.z <= 1, "rabbit is grounded and fits its two-cell clearance")
	var hit: Dictionary = wildlife.pick_explorer_object(bounds.get_center() + Vector3.UP * 10, bounds.get_center() - Vector3.UP * 2)
	_expect(hit.get("id") == rabbit, "imported rabbit can be picked")
	_expect(explorer.select_object(wildlife, rabbit), "shared inspector accepts wildlife")
	_expect(explorer._outline_subject == rabbit, "outline follows moving wildlife")
	wildlife.apply_slice(20)
	_expect(wildlife.get_explorer_data(rabbit).is_empty() and wildlife.pick_explorer_object(bounds.get_center()+Vector3.UP*10,bounds.get_center()-Vector3.UP*2).is_empty(), "hidden rabbits cannot be inspected or picked")
	wildlife.apply_slice(127)
	var start: Dictionary = rabbit.serialize_state()
	clock_node.set_paused(true)
	wildlife.advance(60, [])
	_expect(rabbit.serialize_state() == start, "pause freezes appetite, motion, decisions and animation")
	clock_node.set_paused(false)
	clock_node.set_speed(2)
	wildlife.advance(0.1, [])
	var double_speed: Dictionary = rabbit.serialize_state()
	rabbit.restore_state(start)
	clock_node.set_speed(1)
	wildlife.advance(0.2, [])
	_expect(rabbit.serialize_state() == double_speed, "clock speed scales needs and animation together")
	rabbit.restore_state(start)
	rabbit.hunger = 0.7
	rabbit.timer = 0
	rabbit.fatigue = 0
	wildlife.advance(0.01, [])
	_expect(rabbit.activity == "Grazing", "hungry rabbit grazes surface vegetation")
	for i in range(62): wildlife.advance(0.1, [])
	_expect(rabbit.hunger < 0.2 and world.get_block(40,20,40) == grass, "one completed graze satisfies hunger without consuming terrain or crops")
	rabbit.restore_state(start)
	rabbit.activity = "Grazing"
	rabbit.timer = 3
	rabbit.hunger = 0.7
	var before_distance: float = rabbit.position.distance_to(Vector3(37.5,21,40.5))
	wildlife.advance(0.01, [Vector3(37.5,21,40.5)])
	_expect(rabbit.activity == "Fleeing" and rabbit.hunger >= 0.7, "danger interrupts eating with no free meal")
	for i in range(30): wildlife.advance(0.02, [Vector3(37.5,21,40.5)])
	_expect(rabbit.position.distance_to(Vector3(37.5,21,40.5)) > before_distance, "flight gains distance from dwarf")
	rabbit.restore_state(start)
	clock_node.hour = 12
	rabbit.fatigue = 0.8
	rabbit.hunger = 0.1
	rabbit.timer = 0
	wildlife.advance(0.01, [])
	_expect(rabbit.activity == "Sleeping", "tired rabbit takes a scheduled nap")
	var nap: Dictionary = rabbit.serialize_state()
	rabbit.restore_state(nap)
	_expect(rabbit.serialize_state() == nap, "a naturally entered nap survives observational saving")
	for i in range(100): wildlife.advance(0.1, [])
	_expect(rabbit.fatigue < 0.8, "sleep restores rest gradually")
	wildlife.advance(0.01, [rabbit.position + Vector3(2,0,0)])
	_expect(rabbit.activity == "Fleeing", "danger wakes a sleeping rabbit")
	_navigation_checks(start)
	# Save while partway through a hop, including random state and pose phase.
	rabbit.restore_state(start)
	rabbit._hop(Vector3i(41,21,40))
	wildlife.advance(0.1, [])
	var saved: Dictionary = JSON.parse_string(JSON.stringify(wildlife.serialize_state()))
	var old_rabbit: Node3D = rabbit
	wildlife.restore_state(saved)
	rabbit = wildlife.animals[0]
	_expect(wildlife.animals.size() == 1 and not wildlife._inspectable(old_rabbit), "load replaces rather than duplicates wildlife or stale selection")
	await process_frame
	_expect(not wildlife._inspectable(old_rabbit), "freed pre-load selection is safely rejected")
	var restored: Dictionary = wildlife.serialize_state()
	for key in saved.rabbits[0]:
		var before: Variant = saved.rabbits[0][key]
		var after: Variant = restored.rabbits[0][key]
		if before is float:
			_expect(is_equal_approx(before, float(after)), "mid-hop JSON restores %s" % key)
		elif before is Array:
			_expect(Vector3(float(before[0]),float(before[1]),float(before[2])).is_equal_approx(Vector3(float(after[0]),float(after[1]),float(after[2]))), "mid-hop JSON restores %s" % key)
		else: _expect(before == after, "mid-hop JSON restores %s" % key)
	var clone_state: Dictionary = rabbit.serialize_state()
	for i in range(40): wildlife.advance(0.05, [])
	var future: Dictionary = rabbit.serialize_state()
	rabbit.restore_state(clone_state)
	for i in range(40): wildlife.advance(0.05, [])
	_expect(rabbit.serialize_state() == future, "restored RNG and hop phase resume the same decisions")
	wildlife.restore_state({"initialized":true,"rabbits":[]})
	_expect(wildlife.initialized and wildlife.animals.is_empty(), "saved empty population stays empty")
	if failures.is_empty(): print("RABBIT_WILDLIFE_OK")
	else:
		for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _navigation_checks(start: Dictionary) -> void:
	var source := Vector3i(40,21,40)
	var destination := Vector3i(41,21,40)
	var stone: int = blocks.get_id("base:terrain:rock:rock01")
	var water: int = blocks.get_id("base:terrain:water:source")
	for y in range(4,21): world.set_block(48,y,48,0)
	_expect(Navigation.standable(Vector3i(48,4,48)), "immutable bedrock remains valid support without allowing feet inside it")
	_expect(Navigation.can_hop(source,destination), "flat hop is legal")
	var handle: int = root.get_node("PlacedEntityRegistry").register_box(destination,Vector3i(1,3,1))
	_expect(not Navigation.can_hop(source,destination), "tree/furniture occupancy blocks rabbits")
	root.get_node("PlacedEntityRegistry").unregister(handle)
	world.set_block(41,21,40,stone)
	_expect(Navigation.can_hop(source,destination+Vector3i.UP), "one-block terrace is reachable")
	rabbit.restore_state(start)
	rabbit._hop(destination+Vector3i.UP)
	wildlife.advance(0.1,[])
	_expect(is_equal_approx(rabbit.position.x,40.5) and rabbit.position.y>21, "step-up rises before crossing the solid edge")
	world.set_block(40,23,40,stone)
	_expect(not Navigation.can_hop(source,destination+Vector3i.UP), "swept overhead clearance blocks step-up")
	world.set_block(40,23,40,0)
	world.set_block(41,21,40,water)
	_expect(water != 0 and not Navigation.can_hop(source,destination), "rabbit refuses water")
	world.set_block(41,21,40,0)
	world.set_block(41,20,40,0)
	world.set_block(41,19,40,0)
	_expect(not Navigation.can_hop(source,destination+Vector3i(0,-2,0)), "rabbit cannot hop down a cliff")
	world.set_block(41,19,40,stone)
	world.set_block(41,20,40,stone)
	rabbit.restore_state(start)
	rabbit._hop(destination)
	wildlife.advance(0.1,[])
	handle = root.get_node("PlacedEntityRegistry").register_box(destination,Vector3i(1,3,1))
	wildlife.advance(0.1,[])
	_expect(rabbit.cell == source and rabbit.hop_progress == 1, "new obstruction cancels an in-progress hop")
	root.get_node("PlacedEntityRegistry").unregister(handle)
	rabbit.restore_state(start)
	rabbit._hop(destination)
	wildlife.advance(0.1,[])
	world.set_block(40,20,40,0)
	for i in range(9): wildlife.advance(0.02,[])
	_expect(rabbit.cell == source + Vector3i.DOWN and rabbit.position == Vector3(40.5,20,40.5), "mining support during a hop falls inside the source column onto the next floor")
	world.set_block(40,20,40,blocks.get_id("base:terrain:surface:grass_01"))
