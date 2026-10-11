extends Node3D
## Sole animal-definition loader, seeded population owner and save/inspector
## provider. Small populations keep full simulation, even outside the camera.
const Rabbit = preload("res://scripts/entities/RabbitAgent.gd")
const Deer = preload("res://scripts/entities/DeerAgent.gd")
const Wolf = preload("res://scripts/entities/WolfAgent.gd")
const Duck = preload("res://scripts/entities/DuckAgent.gd")
const Navigation = preload("res://scripts/components/AnimalNavigation.gd")
const Picking = preload("res://scripts/components/ObjectPicking.gd")
const ArrivalPlanner = preload("res://scripts/components/EdgeArrivalPlanner.gd")
const DEFINITION_PATH := "res://data/entities/animals/rabbit.json"
const DEER_PATH := "res://data/entities/animals/deer.json"
const WOLF_PATH := "res://data/entities/animals/wolf.json"

@export var slice_controller_path: NodePath
@export var camera_path: NodePath
var definition: Dictionary = {}
var animals: Array[Node3D] = []
var initialized := false
var deer_initialized := false
var deer_definition: Dictionary = {}
var wolf_initialized := false
var wolf_definition: Dictionary = {}
var duck_definition: Dictionary = {}
var duck_initialized := false
var duck_navigation := preload("res://scripts/components/DuckNavigation.gd").new()
var duck_population := preload("res://scripts/components/DuckPopulation.gd").new()
var _duck_models: Dictionary = {}
var _wolf_models: Dictionary = {}
var _deer_models: Dictionary = {}
var _models: Dictionary = {}
var _picking := Picking.new()
var _slice_y := 127
var _dev_cursors: Dictionary = {}
var _camera: Node3D

func _ready() -> void:
	add_to_group("wildlife")
	add_to_group("arrival_provider")
	add_to_group("object_explorer_provider")
	add_to_group(SaveManager.OWNER_GROUP)
	definition = JSON.parse_string(FileAccess.get_file_as_string(DEFINITION_PATH)) as Dictionary
	for part: String in definition.model_parts: _models[part] = load(definition.model_parts[part])
	deer_definition = JSON.parse_string(FileAccess.get_file_as_string(DEER_PATH)) as Dictionary
	for part: String in deer_definition.model_parts: _deer_models[part] = load(deer_definition.model_parts[part])
	wolf_definition = JSON.parse_string(FileAccess.get_file_as_string(WOLF_PATH)) as Dictionary
	for part: String in wolf_definition.model_parts: _wolf_models[part] = load(wolf_definition.model_parts[part])
	duck_definition = JSON.parse_string(FileAccess.get_file_as_string("res://data/entities/animals/duck.json")) as Dictionary
	for part: String in duck_definition.model_parts: _duck_models[part] = load(duck_definition.model_parts[part])
	duck_navigation.config = duck_definition.navigation
	duck_population.owner = self
	_camera = get_node_or_null(camera_path) as Node3D if not camera_path.is_empty() else null
	var slice := get_node_or_null(slice_controller_path) if not slice_controller_path.is_empty() else null
	if slice != null:
		slice.slice_changed.connect(apply_slice)
		_slice_y = int(slice.get_slice_y())

func _process(delta: float) -> void:
	if not initialized or not deer_initialized or not wolf_initialized or not duck_initialized:
		var details := get_tree().get_first_node_in_group("surface_details")
		if not WorldGenerator.get_streaming_stats().get("maps_ready", false) or details == null or not details._initialized: return
		initialize_population()
	duck_navigation.flora = get_tree().get_first_node_in_group("surface_flora")
	var threats: Array[Vector3] = []
	var director := get_tree().get_first_node_in_group("dwarf_director")
	if director != null:
		for dwarf: Node3D in director.get_roster(): threats.append(dwarf.global_position)
	advance(delta, threats)

func advance(delta: float, threats: Array) -> void:
	if WorldClock.paused or WorldClock.speed <= 0: return
	var prey_threats := threats.duplicate()
	for animal in animals:
		if animal is Wolf: prey_threats.append(animal.position)
	for animal in animals.duplicate():
		if not animal in animals: continue
		if animal is Deer: _update_herd_context(animal)
		if animal is Duck: _update_flock_context(animal)
		if animal is Wolf: _update_wolf_target(animal)
		var animal_definition: Dictionary = animal.definition
		var feeding_activity := "Eating" if animal is Wolf else "Grazing"
		var was_grazing: bool = animal.activity == feeding_activity
		var previous_timer: float = animal.timer
		animal.advance(delta * WorldClock.speed, delta * WorldClock.game_hours_per_real_second(), threats if animal is Wolf else prey_threats)
		if animal is Wolf: _try_capture(animal)
		animal.visible = _visible_at(animal.position)
		if animal is Duck: animal.update_effect_visibility()
		# Crossings are derived from existing meal progress: no sound timers/RNG
		# in saves, no missed-cue backlog after panning, pausing or restoring.
		if was_grazing and animal.activity == feeding_activity and animal.visible and animal.hop_progress >= 1:
			var duration := float(animal_definition.hunting.eat_seconds if animal is Wolf else animal_definition.behavior.graze_seconds)
			var cues: Array = animal_definition.feedback.eating_cues if animal is Wolf else animal_definition.feedback.grazing_cues
			for fraction: float in cues:
				var crossing := duration * (1.0 - fraction)
				if previous_timer > crossing and animal.timer <= crossing:
					WorkFeedback.play_animal(animal_definition.feedback.eating_sound if animal is Wolf else animal_definition.feedback.grazing_sound, animal)
					break # A stalled frame never bursts through skipped sounds.

func initial_cells(seed_value: int) -> Array[Vector3i]:
	var random := RandomNumberGenerator.new()
	random.seed = seed_value + int(definition.population.salt)
	var result: Array[Vector3i] = []
	for attempt in range(int(definition.population.attempts)):
		if result.size() >= int(definition.population.count): break
		var x := random.randi_range(8, WorldData.WORLD_SIZE_X - 9)
		var z := random.randi_range(8, WorldData.WORLD_SIZE_Z - 9)
		var y := WorldGenerator.get_surface_y(x, z)
		if y > int(definition.population.max_ground_y): continue
		var cell := Vector3i(x, y + 1, z)
		var key := BlockRegistry.get_key(Navigation.block_at(cell + Vector3i.DOWN))
		if BlockRegistry.get_def(key).get("kind", "") != "grass": continue
		if not Navigation.standable(cell, int(definition.navigation.clearance)): continue
		if Navigation.neighbors(cell, int(definition.navigation.clearance)).size() < 2: continue
		var crowded := false
		for other in result:
			if Vector2(cell.x-other.x, cell.z-other.z).length() < float(definition.population.min_spacing):
				crowded = true
				break
		if not crowded: result.append(cell)
	return result

func initialize_population() -> void:
	if not initialized:
		for cell in initial_cells(WorldGenerator.world_seed):
			var id := "rabbit:%d:%d:%d" % [WorldGenerator.world_seed, cell.x, cell.z]
			add_rabbit(id, cell, WorldGenerator.world_seed + cell.x * 1009 + cell.z * 9176)
		initialized = true
	if not deer_initialized:
		for group: Dictionary in initial_deer_groups(WorldGenerator.world_seed):
			for cell: Vector3i in group.cells:
				var id := "deer:%d:%d:%d" % [WorldGenerator.world_seed,cell.x,cell.z]
				var animal := add_deer(id,cell,WorldGenerator.world_seed + cell.x * 701 + cell.z * 2141,group.id)
				animal.home = group.home
		deer_initialized = true
	if not wolf_initialized:
		for cell in initial_wolf_cells(WorldGenerator.world_seed):
			add_wolf("wolf:%d:%d:%d" % [WorldGenerator.world_seed,cell.x,cell.z],cell,WorldGenerator.world_seed+cell.x*3253+cell.z*9781)
		wolf_initialized = true
	if not duck_initialized and WaterManager.initialized:
		for group: Dictionary in duck_population.groups(WorldGenerator.world_seed):
			for cell: Vector3i in group.cells:
				var duck := add_duck("duck:%d:%d:%d" % [WorldGenerator.world_seed,cell.x,cell.z],cell,WorldGenerator.world_seed+cell.x*3251+cell.z*421,group.id)
				duck.home = group.home
		duck_initialized = true
	print("Wildlife: %d rabbits, %d deer, %d wolves, %d ducks." % [animals_of_species("rabbit").size(),animals_of_species("deer").size(),animals_of_species("wolf").size(),animals_of_species("duck").size()])

func initial_wolf_cells(seed_value: int) -> Array[Vector3i]:
	var random := RandomNumberGenerator.new()
	var p: Dictionary = wolf_definition.population
	var height := int(wolf_definition.navigation.clearance)
	var width := int(wolf_definition.navigation.footprint)
	random.seed = seed_value+int(p.salt)
	# Use original seed-derived habitat, not the surviving/moving prey records.
	# Thus migration and reload cannot change wolf identities after predation.
	var prey_cells := initial_cells(seed_value)
	for group: Dictionary in initial_deer_groups(seed_value): prey_cells.append_array(group.cells)
	var result: Array[Vector3i] = []
	if prey_cells.is_empty(): return result
	for attempt in range(int(p.attempts)):
		if result.size() >= int(p.count): break
		var nearby := prey_cells[random.randi_range(0,prey_cells.size()-1)]
		var x := nearby.x+random.randi_range(-int(p.prey_max_distance),int(p.prey_max_distance))
		var z := nearby.z+random.randi_range(-int(p.prey_max_distance),int(p.prey_max_distance))
		if x < 2 or z < 2 or x+width >= WorldData.WORLD_SIZE_X or z+width >= WorldData.WORLD_SIZE_Z: continue
		var cell := Vector3i(x,WorldGenerator.get_surface_y(x,z)+1,z)
		if cell.y-1 > int(p.max_ground_y) or not Navigation.standable(cell,height,width): continue
		var key := BlockRegistry.get_key(Navigation.block_at(cell+Vector3i.DOWN))
		if BlockRegistry.get_def(key).get("kind","") != "grass" or Navigation.neighbors(cell,height,width).size() < 2: continue
		var distance := INF
		for prey_cell in prey_cells: distance = minf(distance,Vector3(cell-prey_cell).length())
		if distance < float(p.prey_min_distance) or distance > float(p.prey_max_distance): continue
		var crowded := false
		for other in result:
			if Vector2(cell.x-other.x,cell.z-other.z).length() < float(p.min_spacing): crowded = true
		if not crowded: result.append(cell)
	return result

func initial_deer_groups(seed_value: int) -> Array[Dictionary]:
	var random := RandomNumberGenerator.new()
	random.seed = seed_value + int(deer_definition.population.salt)
	var groups: Array[Dictionary] = []
	var p: Dictionary = deer_definition.population
	var height := int(deer_definition.navigation.clearance)
	var width := int(deer_definition.navigation.footprint)
	for attempt in range(int(p.attempts)):
		if groups.size() * int(p.group_size) >= int(p.count): break
		var x := random.randi_range(12,WorldData.WORLD_SIZE_X-13)
		var z := random.randi_range(12,WorldData.WORLD_SIZE_Z-13)
		var origin := Vector3i(x,WorldGenerator.get_surface_y(x,z)+1,z)
		if not _deer_habitat(origin): continue
		var crowded := false
		for group in groups:
			if Vector2(x-group.home.x,z-group.home.z).length() < float(p.min_spacing): crowded = true
		if crowded: continue
		# All herd members start on one connected local patch, not across water
		# or a cliff. Two-cell strides match their complete support footprint.
		var queue: Array[Vector3i] = [origin]
		var seen := {origin:true}
		var cells: Array[Vector3i] = [origin]
		var cursor := 0
		while cursor < queue.size() and cells.size() < int(p.group_size):
			var current := queue[cursor]
			cursor += 1
			for next in Navigation.neighbors(current,height,width):
				if seen.has(next) or Vector2(next.x-x,next.z-z).length() > float(p.group_radius): continue
				seen[next] = true
				if not _deer_habitat(next): continue
				queue.append(next)
				var spaced := true
				for other in cells:
					if Vector2(next.x-other.x,next.z-other.z).length() < float(p.member_spacing): spaced = false
				if spaced and cells.size() < int(p.group_size): cells.append(next)
		if cells.size() == int(p.group_size):
			groups.append({"id":"herd:%d:%d:%d" % [seed_value,x,z],"home":origin,"cells":cells})
	return groups

func _deer_habitat(cell: Vector3i) -> bool:
	if cell.y-1 > int(deer_definition.population.max_ground_y): return false
	var height := int(deer_definition.navigation.clearance)
	var width := int(deer_definition.navigation.footprint)
	if not Navigation.standable(cell,height,width): return false
	for x in range(width):
		for z in range(width):
			var key := BlockRegistry.get_key(Navigation.block_at(cell+Vector3i(x,-1,z)))
			if BlockRegistry.get_def(key).get("kind","") != "grass": return false
	return Navigation.neighbors(cell,height,width).size() >= 2

func animals_of_species(species: String) -> Array[Node3D]:
	var result: Array[Node3D] = []
	for animal in animals:
		if animal.definition.id == "base:animal:"+species: result.append(animal)
	return result

func _update_herd_context(animal: Node3D) -> void:
	var centre := animal.position
	var count := 1
	animal.peer_spaces.clear()
	for other in animals:
		if other == animal or not other is Deer: continue
		animal.peer_spaces.append(other.position)
		if other.hop_progress < 1: animal.peer_spaces.append(Navigation.centre(other.target,other.footprint))
		if not animal.herd_id.is_empty() and other.herd_id == animal.herd_id:
			centre += other.position
			count += 1
	animal.herd_centre = centre / count
	animal.herd_members = count

func add_rabbit(id: String, cell: Vector3i, seed_value: int) -> Node3D:
	var animal := Rabbit.new()
	add_child(animal)
	animal.configure(definition, id, cell, seed_value, _models)
	animals.append(animal)
	animal.visible = _visible_at(animal.position)
	return animal

func add_deer(id: String, cell: Vector3i, seed_value: int, herd_id := "") -> Node3D:
	var animal := Deer.new()
	add_child(animal)
	animal.configure(deer_definition,id,cell,seed_value,_deer_models)
	animal.herd_id = herd_id
	animals.append(animal)
	animal.visible = _visible_at(animal.position)
	return animal

func add_wolf(id: String, cell: Vector3i, seed_value: int) -> Node3D:
	var animal := Wolf.new()
	add_child(animal)
	animal.configure(wolf_definition,id,cell,seed_value,_wolf_models)
	animals.append(animal)
	animal.visible = _visible_at(animal.position)
	return animal

func _eligible_prey(prey: Node3D) -> bool:
	if not is_instance_valid(prey) or not prey in animals or prey.is_queued_for_deletion(): return false
	var kind: String = prey.definition.id
	var food: Dictionary = wolf_definition.hunting.prey.get(kind,{})
	if food.is_empty(): return false
	var count := 0
	for other in animals:
		if other.definition.id == kind: count += 1
	return count > int(food.minimum_population)

func add_duck(id: String, cell: Vector3i, seed_value: int, flock_id := "") -> Node3D:
	var animal := Duck.new()
	animal.navigation = duck_navigation
	add_child(animal)
	animal.configure(duck_definition,id,cell,seed_value,_duck_models)
	animal.flock_id = flock_id
	animals.append(animal)
	animal.visible = _visible_at(animal.position)
	return animal

func _update_flock_context(duck: Node3D) -> void:
	var centre: Vector3 = duck.position
	var count := 1
	duck.peers.clear()
	for other in animals:
		if other==duck or not other is Duck: continue
		duck.peers.append(other.position)
		if other.hop_progress<1: duck.peers.append(Vector3(other.target)+Vector3(.5,0,.5))
		if other.flock_id==duck.flock_id and other.mode!="air":
			centre += other.position
			count += 1
	duck.flock_centre = centre/count
	duck.flock_members = count

func _update_wolf_target(wolf: Node3D) -> void:
	wolf.prey = null
	if not wolf.hunt_target_id.is_empty():
		for animal in animals:
			if animal.animal_id == wolf.hunt_target_id and _eligible_prey(animal): wolf.prey = animal
		if wolf.prey == null or not wolf.wants_hunt(): wolf.abandon_hunt()
		else: return
	if not wolf.wants_hunt(): return
	var claimed := {}
	for other in animals:
		if other is Wolf and other != wolf and not other.hunt_target_id.is_empty(): claimed[other.hunt_target_id] = true
	var best: Node3D
	var distance := float(wolf_definition.hunting.search_radius)
	for animal in animals:
		if claimed.has(animal.animal_id) or not _eligible_prey(animal): continue
		var candidate: float = wolf.position.distance_to(animal.position)
		if candidate < distance and Navigation.sight_clear(wolf.position,animal.position):
			best = animal
			distance = candidate
	if best != null: wolf.begin_hunt(best)
	else: wolf.retry_hours = float(wolf_definition.hunting.retry_hours)

func _try_capture(wolf: Node3D) -> bool:
	if WorldClock.paused or WorldClock.speed <= 0 or wolf.activity != "Hunting" or wolf.hop_progress < 1 or not wolf.wants_hunt(): return false
	var prey: Node3D = wolf.prey
	if not _eligible_prey(prey) or prey.animal_id != wolf.hunt_target_id: return false
	if not Navigation.contact_clear(wolf.position,prey.position,float(wolf_definition.hunting.capture_radius)): return false
	var food: Dictionary = wolf_definition.hunting.prey[prey.definition.id]
	# One owner commits both removal and meal. No corpse items, loot, replayed
	# kill on restore, or second wolf consuming the same animal.
	remove_animal(prey, "predation")
	wolf.begin_meal(food)
	return true

func remove_animal(animal: Node3D, cause: String) -> bool:
	if not is_instance_valid(animal) or not animal in animals: return false
	if cause == "player_hunt":
		var events := get_tree().get_first_node_in_group("world_events")
		if events != null: events.record_player_hunt(animal.cell)
	animals.erase(animal)
	remove_child(animal)
	animal.queue_free()
	return true

func arrival_provider_key() -> String:
	return "wildlife"

func arrival_ready() -> bool:
	if not initialized or not deer_initialized or not wolf_initialized: return false
	# Whole-map trees install trunk occupancy over several startup frames. Do
	# not validate a distant corridor against a forest that is still loading.
	var flora := get_tree().get_first_node_in_group("surface_flora")
	if flora != null and flora.cover_whole_map:
		var stats: Dictionary = flora.get_spawn_stats()
		if int(stats.loaded_columns) == 0 or int(stats.pending_columns) > 0: return false
	return true

func arrival_definition(species: String) -> Dictionary:
	return {"rabbit": definition, "deer": deer_definition, "wolf": wolf_definition,"duck":duck_definition}.get(species, {})

func _wolf_arrival_capacity(event: Dictionary) -> int:
	# Only prey above the existing protected reserves can support new wolves.
	# All living wolves count, including members still travelling inland.
	var surplus := 0
	for kind: String in wolf_definition.hunting.prey:
		var count := animals_of_species(kind.trim_prefix("base:animal:")).size()
		surplus += maxi(0, count-int(wolf_definition.hunting.prey[kind].minimum_population))
	return maxi(0, floori(float(surplus)/float(event.surplus_prey_per_wolf))-animals_of_species("wolf").size())

func _wolf_arrival_has_prey(at: Vector3i, event: Dictionary) -> bool:
	var count := 0
	for animal in animals:
		if animal.position.distance_to(Navigation.centre(at, 2)) <= float(event.local_prey_radius) and _eligible_prey(animal): count += 1
	return count >= int(event.local_prey_minimum)

func prepare_arrival(event: Dictionary, plan: Dictionary, events: Node) -> Dictionary:
	if event.species=="duck": return duck_population.prepare_arrival(event,plan,events)
	var data := arrival_definition(event.species)
	if data.is_empty() or event.entry != "wilderness": return {"status": "blocked", "reason": "unsupported"}
	var room := int(event.population_cap)-animals_of_species(event.species).size()
	if room <= 0: return {"status": "blocked", "reason": "population cap"}
	if event.species == "wolf":
		room = mini(room, _wolf_arrival_capacity(event))
		if room <= 0: return {"status": "blocked", "reason": "scarce prey"}
	var result := ArrivalPlanner.probe(event, plan, data, _arrival_cell_allowed.bind(event, events))
	if result.is_empty(): return result
	result.count = mini(int(plan.count), room)
	var routes: Array = [result.route]
	if event.has("member_spacing"):
		routes = ArrivalPlanner.group_routes(result.route, int(result.count), event, data, _arrival_cell_allowed.bind(event, events))
		if routes.is_empty(): return {}
		result.member_routes = routes
	for route: Array in routes:
		var home_cell := SaveManager.unpack_v3i(route.back())
		for animal in animals_of_species(event.species):
			if Vector3(animal.home-home_cell).length() < float(event.settlement_spacing): return {}
		if event.species == "wolf" and not _wolf_arrival_has_prey(home_cell, event): return {}
	return result

func _arrival_cell_allowed(at: Vector3i, event: Dictionary, events: Node) -> bool:
	if not events.safe_arrival_cell(at): return false
	var dwarves := get_tree().get_first_node_in_group("dwarf_director")
	if dwarves != null:
		for dwarf: Node3D in dwarves.get_roster():
			if dwarf.global_position.distance_to(Vector3(at)) < float(event.dwarf_distance): return false
	return true

func spawn_arrival_member(event: Dictionary, batch: Dictionary, events: Node) -> String:
	if event.species=="duck": return duck_population.spawn_member(event,batch,events)
	var data := arrival_definition(event.species)
	if data.is_empty() or event.entry != "wilderness": return "unsupported"
	if animals_of_species(event.species).size() >= int(event.population_cap): return "population cap"
	if event.species == "wolf" and _wolf_arrival_capacity(event) <= 0: return "scarce prey"
	var route: Array = batch.member_routes[int(batch.issued)] if batch.has("member_routes") else batch.route
	if route.size() < 2: return "blocked"
	var width := int(data.navigation.get("footprint", 1))
	# Recheck the complete corridor before each member enters. A new wall, mine,
	# building or dangerous area cancels the rest; it never teleports them inland.
	for i in range(route.size()):
		var at := SaveManager.unpack_v3i(route[i])
		if not _arrival_cell_allowed(at, event, events): return "unsafe"
		if i > 0 and not Navigation.can_hop(SaveManager.unpack_v3i(route[i-1]), at, int(data.navigation.clearance), width): return "blocked"
	var home_cell := SaveManager.unpack_v3i(route.back())
	if not ArrivalPlanner.habitat(home_cell, data): return "habitat lost"
	if event.species == "wolf" and not _wolf_arrival_has_prey(home_cell, event): return "prey moved away"
	var entry := SaveManager.unpack_v3i(route[0])
	if not _arrival_entry_free(entry, data): return "wait"
	var id := "%s:member:%d" % [batch.id, int(batch.issued)]
	# A consumed member's ordinal is never reused. This guard also avoids an
	# accidental duplicate if a future caller replays a member command.
	for animal in animals:
		if animal.animal_id == id: return "spawned"
	var seed_value := int(String(batch.seed))+int(batch.issued)*7919
	var animal: Node3D
	match String(event.species):
		"rabbit": animal = add_rabbit(id, entry, seed_value)
		"deer": animal = add_deer(id, entry, seed_value, "herd:"+String(batch.id))
		"wolf":
			animal = add_wolf(id, entry, seed_value)
			animal.hunger = float(event.initial_hunger)
	animal.begin_arrival(String(batch.id), route, float(event.blocked_seconds))
	return "spawned"

func _arrival_entry_free(entry: Vector3i, data: Dictionary) -> bool:
	var width := int(data.navigation.get("footprint", 1))
	var bounds := AABB(Vector3(entry), Vector3(width, int(data.navigation.clearance), width))
	for animal in animals:
		var size := Vector3(animal.footprint, int(animal.definition.navigation.clearance), animal.footprint)
		var offset := Vector3(animal.footprint*.5, 0, animal.footprint*.5)
		if bounds.intersects(AABB(animal.position-offset, size)): return false
		if animal.hop_progress < 1 and bounds.intersects(AABB(Vector3(animal.target), size)): return false
		# Retain the rabbit pilot's two-block breathing room at the entry.
		if animal.position.distance_to(Navigation.centre(entry, width)) < 2.0: return false
	return true

func apply_slice(y: int) -> void:
	_slice_y = y
	for animal in animals:
		animal.visible = _visible_at(animal.position)
		if animal is Duck: animal.update_effect_visibility()

func _visible_at(at: Vector3) -> bool:
	# Full-world view includes birds flying above the terrain's top layer.
	if _slice_y<WorldData.WORLD_SIZE_Y-1 and floori(at.y)>_slice_y: return false
	var cave_id := WorldGenerator.get_cave_id(Vector3i(at.floor()))
	return cave_id < 0 or InteriorTracker.is_cave_discovered(cave_id)

func _inspectable(id: Variant) -> bool:
	return is_instance_valid(id) and id is Node3D and id in animals and id.is_visible_in_tree() and not id.is_queued_for_deletion()

func pick_explorer_object(start: Vector3, end: Vector3) -> Dictionary:
	var nearest := INF
	var selected: Node3D
	for animal in animals:
		if not _inspectable(animal): continue
		if Picking.visible_world_bounds(animal).intersects_segment(start, end) == null: continue
		var distance := _picking.hit_distance(animal, start, end)
		if distance < nearest:
			nearest = distance
			selected = animal
	return {"id": selected, "distance": nearest} if selected != null else {}

func get_explorer_bounds(id: Variant) -> AABB:
	return Picking.visible_world_bounds(id) if _inspectable(id) else AABB()

func get_explorer_data(id: Variant) -> Dictionary:
	if not _inspectable(id): return {}
	var data: Dictionary = id.definition
	var rows: Array = [["Activity", id.activity], ["Appetite", "Looking for a nibble" if id.hunger >= float(data.behavior.hungry_threshold) else "Content"],
		["Rest", "Sleepy" if id.fatigue >= float(data.behavior.sleep_threshold) else "Rested"], ["Diet", "Ground vegetation"]]
	if not id.arrival.is_empty(): rows.append(["Arrival", id.arrival.status])
	if id is Deer:
		var count := 0
		for other in animals:
			if other is Deer and other.herd_id == id.herd_id: count += 1
		rows.append(["Herd", "%d deer" % count if not id.herd_id.is_empty() else "Solitary"])
	if id is Wolf:
		rows[3] = ["Diet","Rabbits and deer"]
		rows.append(["Hunting","Settling in" if not id.arrival.is_empty() and not id.arrival.route.is_empty() else "Satisfied after a meal" if id.satisfied_hours > 0 else "Pursuing prey" if not id.hunt_target_id.is_empty() else "Resting between attempts" if id.retry_hours > 0 else "Ready when hungry"])
	if id is Duck:
		rows[3] = ["Diet","Water plants and shore forage"]
		rows.append(["Plumage",String(id.sex).capitalize()])
		var count := 0
		for other in animals:
			if other is Duck and other.flock_id==id.flock_id: count += 1
		rows.append(["Flock","%d ducks" % count])
	return {"title": data.display_name, "kind": "Wildlife", "subject": id,
		"rows": rows, "details": data.description,
		"actions": [{"id":"locate", "text":"Locate"}, {"id":"stop_follow" if is_following(id) else "follow", "text":"Stop following" if is_following(id) else "Follow"}]}

func is_following(id: Variant) -> bool:
	return is_instance_valid(_camera) and _camera.is_following(id)

func perform_explorer_action(id: Variant, action: String) -> void:
	if not _inspectable(id) or not is_instance_valid(_camera): return
	if action == "follow": _camera.follow_subject(id)
	elif action == "locate": _camera.locate_subject(id)
	elif action == "stop_follow": _camera.stop_following()

func clear_explorer_selection(id: Variant) -> void:
	if is_following(id): _camera.stop_following()

func on_explorer_selected(id: Variant) -> void:
	if _inspectable(id): WorkFeedback.play_animal(id.definition.feedback.selection_sound, id)

func dev_locate_next(species := "rabbit") -> String:
	var candidates: Array[Node3D] = []
	if species == "arrival" or species.ends_with(" arrival"):
		for animal in animals:
			if not animal.arrival.is_empty() and (species == "arrival" or animal.definition.id == "base:animal:"+species.trim_suffix(" arrival")): candidates.append(animal)
	else: candidates = animals_of_species(species)
	if candidates.is_empty(): return ""
	var cursor := int(_dev_cursors.get(species,0))
	var animal := candidates[cursor % candidates.size()]
	_dev_cursors[species] = cursor+1
	var slice := get_node_or_null(slice_controller_path) if not slice_controller_path.is_empty() else null
	if slice != null: slice.deactivate_if_active()
	if _camera != null: _camera.focus_world_position(animal.position + Vector3.UP, 30.0 if animal is Deer else 24.0)
	var dock := get_tree().get_first_node_in_group("command_dock")
	if dock != null: dock.tool_requested.emit("")
	var explorer := get_tree().get_first_node_in_group("object_explorer")
	if explorer != null: explorer.select_object(self, animal)
	return animal.animal_id

func save_section_key() -> String:
	return "wildlife"

func save_restore_priority() -> int:
	return 65

func serialize_state() -> Dictionary:
	var records: Array = []
	var deer: Array = []
	var wolves: Array = []
	var ducks: Array = []
	for animal in animals:
		if animal is Duck: ducks.append(animal.serialize_state())
		elif animal is Wolf: wolves.append(animal.serialize_state())
		elif animal is Deer: deer.append(animal.serialize_state())
		else: records.append(animal.serialize_state())
	return {"initialized": initialized, "rabbits": records,"deer_initialized":deer_initialized,"deer":deer,"wolf_initialized":wolf_initialized,"wolves":wolves,"duck_initialized":duck_initialized,"ducks":ducks}

func restore_state(state: Dictionary) -> void:
	for animal in animals:
		remove_child(animal)
		animal.queue_free()
	animals.clear()
	_dev_cursors.clear()
	initialized = bool(state.get("initialized", false))
	# A rabbit-only save seeds deer once after restore, without replacing its
	# rabbits. Explicitly saved empty deer populations never replenish.
	deer_initialized = bool(state.get("deer_initialized",state.has("deer")))
	wolf_initialized = bool(state.get("wolf_initialized",state.has("wolves")))
	duck_initialized = bool(state.get("duck_initialized",false))
	var seen := {}
	for raw: Dictionary in state.get("rabbits", []):
		var id := String(raw.get("id", ""))
		if id.is_empty() or seen.has(id): continue
		seen[id] = true
		var origin := SaveManager.unpack_v3i(raw.get("cell", []))
		if not Navigation.inside(origin): continue
		var animal := add_rabbit(id, origin, 1)
		animal.restore_state(raw)
	for raw: Dictionary in state.get("deer",[]):
		var id := String(raw.get("id",""))
		if id.is_empty() or seen.has(id): continue
		seen[id] = true
		var origin := SaveManager.unpack_v3i(raw.get("cell",[]))
		if not Navigation.inside(origin): continue
		var animal := add_deer(id,origin,1)
		animal.restore_state(raw)
	for raw: Dictionary in state.get("wolves",[]):
		var id := String(raw.get("id",""))
		if id.is_empty() or seen.has(id): continue
		seen[id] = true
		var origin := SaveManager.unpack_v3i(raw.get("cell",[]))
		if not Navigation.inside(origin): continue
		var animal := add_wolf(id,origin,1)
		animal.restore_state(raw)
	for raw: Dictionary in state.get("ducks",[]):
		if seen.has(raw.id): continue
		seen[raw.id] = true
		var animal := add_duck(raw.id,SaveManager.unpack_v3i(raw.cell),1,raw.flock_id)
		animal.restore_state(raw)
	apply_slice(_slice_y)
