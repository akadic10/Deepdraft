extends SceneTree
## Exercise habitat selection on different finished terrain layouts without a
## renderer. Map generation follows the existing SurfaceDetailLayoutTest path.
var failures: Array[String] = []

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	for service in ["SaveManager","WorldClock","TaskManager"]: root.get_node(service).set_process(false)
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var wildlife = load("res://scripts/systems/WildlifeManager.gd").new()
	scene.add_child(wildlife)
	wildlife.set_process(false)
	var generator := root.get_node("WorldGenerator")
	var navigation = load("res://scripts/components/AnimalNavigation.gd")
	var previous: Array = []
	for seed_value in [0,42,1234,20261009]:
		root.get_node("WorldData").clear_world()
		generator._reset_generation_state()
		generator.world_seed = seed_value
		generator._cache_block_ids()
		generator._layout_profile = generator.load_macro_layout_profile()
		generator._build_noise_instances()
		generator._build_seeded_maps()
		generator._apply_edge_detail()
		generator._maps_ready = true
		var groups: Array = wildlife.initial_deer_groups(seed_value)
		_check(groups.size() == 6,"six complete groups on seed %d" % seed_value)
		_check(groups == wildlife.initial_deer_groups(seed_value),"repeatable habitat selection")
		_check(groups != previous,"different world seeds produce distinct herds")
		previous = groups
		var wolves: Array = wildlife.initial_wolf_cells(seed_value)
		_check(wolves.size() == 4 and wolves == wildlife.initial_wolf_cells(seed_value),"four repeatable wolves on seed %d" % seed_value)
		for i in range(wolves.size()):
			_check(wolves[i].y <= 44 and navigation.standable(wolves[i],2,2),"wolf has dry supported habitat")
			for j in range(i):
				_check(Vector2(wolves[i].x-wolves[j].x,wolves[i].z-wolves[j].z).length() >= 128,"wolves start sparsely spaced")
		var occupied := {}
		var homes: Array[Vector3i] = []
		for group: Dictionary in groups:
			_check(group.cells.size() == 3,"three deer in each group")
			for other in homes:
				_check(Vector2(group.home.x-other.x,group.home.z-other.z).length() >= 96,"herds have separate home areas")
			homes.append(group.home)
			for cell: Vector3i in group.cells:
				_check(cell.y <= 44 and navigation.standable(cell,4,2),"complete dry lowland support")
				for x in range(2):
					for z in range(2):
						var floor_cell := cell+Vector3i(x,-1,z)
						_check(not occupied.has(floor_cell),"starting deer footprints do not overlap")
						occupied[floor_cell] = true
		print("WILDLIFE_POPULATION_SEED: ",seed_value," deer_groups=",groups.size()," wolves=",wolves.size())
	if failures.is_empty(): print("DEER_POPULATION_OK")
	quit(0 if failures.is_empty() else 1)

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)
