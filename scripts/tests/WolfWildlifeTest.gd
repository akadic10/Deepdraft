extends "res://scripts/tests/ObjectExplorerTest.gd"
## Predator integration on real voxel support: pursuit, atomic feeding,
## conservation, interruption, visibility, audio, persistence and navigation.
var wildlife
var wolf
var rabbit
var clock_node
var Navigation
var initial: Dictionary

func _run() -> void:
	create_timer(60).timeout.connect(func(): push_error("Wolf test timed out"); quit(1))
	for service in ["SaveManager","TaskManager","RoomManager","WorldClock"]: root.get_node(service).set_process(false)
	clock_node = root.get_node("WorldClock")
	clock_node.set_paused(false)
	clock_node.set_speed(1)
	clock_node.hour = 12
	world = root.get_node("WorldData")
	blocks = root.get_node("BlockRegistry")
	Navigation = load("res://scripts/components/AnimalNavigation.gd")
	_build_floor()
	var grass: int = blocks.get_id("base:terrain:surface:grass_01")
	for x in range(20,100):
		for z in range(20,100): world.set_block(x,20,z,grass)
	scene = Node3D.new()
	root.add_child(scene)
	current_scene = scene
	wildlife = load("res://scripts/systems/WildlifeManager.gd").new()
	scene.add_child(wildlife)
	wildlife.set_process(false)
	wildlife.initialized = true
	wildlife.deer_initialized = true
	wildlife.wolf_initialized = true
	# Small fixture populations exercise the configured reserve boundary at one.
	wildlife.wolf_definition.hunting.prey["base:animal:rabbit"].minimum_population = 1
	wildlife.wolf_definition.hunting.prey["base:animal:deer"].minimum_population = 0
	rabbit = wildlife.add_rabbit("rabbit:target",Vector3i(50,21,40),100)
	wildlife.add_rabbit("rabbit:reserve",Vector3i(80,21,70),101)
	wildlife.add_deer("deer:target",Vector3i(80,21,80),102,"herd:test")
	wolf = wildlife.add_wolf("wolf:test",Vector3i(40,21,40),103)
	wolf.hunger = .8
	wolf.fatigue = 0
	wolf.timer = 0
	initial = wildlife.serialize_state()
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
	_aim_above(wolf.position)
	camera.set_meta("work_focus",wolf.position)
	camera.set_meta("work_zoom",12.0)
	await process_frame
	var box: AABB = wildlife.get_explorer_bounds(wolf)
	_expect(box.position.y >= 20.99 and box.size.y < 2 and box.size.x <= 2 and box.size.z <= 2,"wolf fits a grounded two-cell envelope")
	_expect(wildlife.pick_explorer_object(box.get_center()+Vector3.UP*5,box.get_center()-Vector3.UP*2).get("id") == wolf,"wolf meshes are pickable")
	var events: Array = []
	var feedback := root.get_node("WorkFeedback")
	feedback.sound_started.connect(func(kind,_position,_variant): events.append(kind))
	clock_node.set_paused(true)
	_expect(explorer.select_object(wildlife,wolf) and explorer._name_label.text == "Wild Wolf","shared inspector shows wolf identity")
	_expect(events == ["wolf_select"],"selection cue works while paused")
	var paused: Dictionary = wildlife.serialize_state()
	wildlife.advance(10,[])
	_expect(wildlife.serialize_state() == paused and not wildlife._try_capture(wolf),"pause freezes hunting, needs and capture")
	wildlife.apply_slice(20)
	_expect(wildlife.get_explorer_data(wolf).is_empty(),"wolves respect slice concealment")
	wildlife.apply_slice(127)
	clock_node.set_paused(false)
	wolf.hunger = .1
	wildlife.advance(.01,[])
	_expect(wolf.hunt_target_id.is_empty(),"content wolves do not hunt")
	_reset()
	wildlife.advance(.05,[])
	_expect(wolf.hunt_target_id == rabbit.animal_id and wolf.activity == "Hunting","hungry wolf claims nearby visible prey")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(wildlife.serialize_state()))
	wildlife.restore_state(saved)
	_bind()
	var replay: Dictionary = wildlife.serialize_state()
	for i in range(15): wildlife.advance(.05,[])
	var future: Dictionary = wildlife.serialize_state()
	wildlife.restore_state(replay)
	_bind()
	for i in range(15): wildlife.advance(.05,[])
	_expect(wildlife.serialize_state() == future,"saved target ID and partial chase resume deterministically")
	var victim: Node3D = rabbit
	var saw_escape: bool = rabbit.activity == "Fleeing"
	for i in range(220):
		wildlife.advance(.05,[])
		if victim in wildlife.animals: saw_escape = saw_escape or victim.activity == "Fleeing"
		if wolf.activity == "Eating": break
	_expect(saw_escape,"prey flee from the approaching wolf")
	_expect(wolf.activity == "Eating" and wildlife.animals_of_species("rabbit").size() == 1,"bounded live chase ends in one capture and meal")
	_expect(not wildlife._inspectable(victim),"captured prey cannot leave stale selection")
	_expect(wolf.hunger < .2 and wolf.satisfied_hours > 35,"rabbit meal satisfies the wolf for a long interval")
	_expect(not wildlife._try_capture(wolf),"a captured meal cannot be committed twice")
	feedback.clear_transients()
	camera.set_meta("work_focus",wolf.position)
	wildlife.advance(1.2,[])
	_expect(events.back() == "wolf_eat","meal crossing emits the wolf eating bank")
	var after_meal: Dictionary = JSON.parse_string(JSON.stringify(wildlife.serialize_state()))
	wildlife.restore_state(after_meal)
	_bind()
	wildlife.initialize_population()
	_expect(wildlife.animals_of_species("rabbit").size() == 1 and wolf.satisfied_hours > 35,"save/load preserves consumed prey and meal lockout without replenishing")
	wolf.hunger = 1
	wildlife.advance(.05,[])
	_expect(wolf.hunt_target_id.is_empty(),"satisfaction blocks hunting even at high appetite")
	wolf.satisfied_hours = 0
	wolf.activity = "Idle"
	wolf.retry_hours = 0
	var reserve = wildlife.animals_of_species("rabbit")[0]
	_expect(not wildlife._eligible_prey(reserve),"minimum prey population remains protected")
	wolf.begin_meal(wildlife.wolf_definition.hunting.prey["base:animal:deer"])
	_expect(wolf.satisfied_hours == 72 and wolf.hunger == 0,"deer meal provides greater and longer satisfaction")
	wildlife.advance(.01,[wolf.position+Vector3(-3,0,0)])
	_expect(wolf.activity == "Fleeing" and wolf.satisfied_hours > 71,"dwarf interrupts eating without losing the credited meal")
	_reset()
	wolf.begin_hunt(rabbit)
	wolf.hunt_left = .02
	wildlife.advance(.05,[])
	_expect(wolf.hunt_target_id.is_empty() and wolf.retry_hours > 0,"pursuit timeout releases prey and waits before retrying")
	_reset()
	wildlife.advance(.01,[wolf.position+Vector3(3,0,0)])
	_expect(wolf.activity == "Fleeing" and wolf.hunt_target_id.is_empty(),"wolves avoid dwarves instead of attacking")
	_reset()
	var second = wildlife.add_wolf("wolf:second",Vector3i(40,21,44),104)
	second.hunger = .8
	wildlife._update_wolf_target(wolf)
	wildlife._update_wolf_target(second)
	_expect(not wolf.hunt_target_id.is_empty() and second.hunt_target_id != wolf.hunt_target_id,"two wolves cannot claim the same prey")
	_reset()
	wolf.hunger = .1
	wolf.fatigue = .8
	wildlife.advance(.01,[])
	_expect(wolf.activity == "Sleeping","tired satisfied wolf rests during its preferred window")
	var rest: AABB = wildlife.get_explorer_bounds(wolf)
	_expect(rest.position.y >= 20.99,"folded rest pose remains above ground")
	var fatigue: float = wolf.fatigue
	for i in range(40): wildlife.advance(.1,[])
	_expect(wolf.fatigue < fatigue,"sleep restores wolf fatigue")
	_navigation_checks()
	wildlife.restore_state({"initialized":true,"rabbits":[],"deer_initialized":true,"deer":[]})
	_expect(not wildlife.wolf_initialized,"older wildlife saves request one-time wolf seeding")
	wildlife.restore_state({"initialized":true,"rabbits":[],"deer_initialized":true,"deer":[],"wolf_initialized":true,"wolves":[]})
	wildlife.initialize_population()
	_expect(wildlife.animals.is_empty(),"explicitly empty populations stay empty")
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("WOLF_WILDLIFE_OK")
	quit(0 if failures.is_empty() else 1)

func _reset() -> void:
	wildlife.restore_state(initial)
	_bind()

func _bind() -> void:
	wolf = wildlife.animals_of_species("wolf")[0]
	var rabbits: Array = wildlife.animals_of_species("rabbit")
	rabbit = rabbits[0] if not rabbits.is_empty() else null

func _navigation_checks() -> void:
	var a := Vector3(50.5,21,50.5)
	var b := Vector3(52.5,21,50.5)
	_expect(Navigation.contact_clear(a,b,3),"supported nearby contact is clear")
	var handle: int = root.get_node("PlacedEntityRegistry").register_box(Vector3i(51,21,50),Vector3i(1,2,1))
	_expect(not Navigation.contact_clear(a,b,3),"contact cannot cross an occupied wall")
	root.get_node("PlacedEntityRegistry").unregister(handle)
	handle = root.get_node("PlacedEntityRegistry").register_box(Vector3i(51,21,51),Vector3i(1,2,1))
	_expect(not Navigation.contact_clear(Vector3(50.99,21,50.01),Vector3(52.01,21,51.03),1.6),"contact rejects a tiny corner intersection between ray samples")
	root.get_node("PlacedEntityRegistry").unregister(handle)
	world.set_block(51,20,50,0)
	_expect(not Navigation.contact_clear(a,b,3),"contact cannot cross a pit")
	world.set_block(51,20,50,blocks.get_id("base:terrain:surface:grass_01"))
	handle = root.get_node("PlacedEntityRegistry").register_box(Vector3i(62,21,58),Vector3i(2,3,6))
	var from := Vector3i(60,21,60)
	var next: Vector3i = Navigation.approach(from,Vector3(71,21,61),2,2,64,1.6)
	_expect(next != from and Navigation.can_hop(from,next,2,2) and next.x == from.x,"bounded pursuit routes around a nearby wall")
	root.get_node("PlacedEntityRegistry").unregister(handle)
