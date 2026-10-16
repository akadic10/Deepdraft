extends RefCounted

## Seeded shore groups and aerial arrivals; the wildlife owner owns all actors.
var owner: Node

func groups(seed_value: int) -> Array[Dictionary]:
	var data: Dictionary = owner.duck_definition
	var nav: RefCounted = owner.duck_navigation
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value+int(data.population.salt)
	var all: Array[Vector2i] = []
	for key: Vector3i in WaterManager.flow.mass:
		if WaterManager.flow.volume(key)>=float(data.navigation.swim_depth): all.append(Vector2i(key.x,key.z))
	all.sort()
	var river: Array = WorldGenerator.river_layout.get("columns",{}).keys()
	river.sort()
	var result: Array[Dictionary] = []
	if all.is_empty(): return result
	for attempt in int(data.population.attempts):
		if result.size()>=int(data.population.groups): break
		# Try the quiet river first; lakes remain the fallback for a steep run.
		var pool: Array = river if result.is_empty() and attempt<150 and not river.is_empty() else all
		var col: Vector2i = pool[rng.randi_range(0,pool.size()-1)]
		var sample: Dictionary = nav.surface(col)
		if sample.is_empty() or not sample.water or not nav.near_shore(col,int(data.population.shore_distance),data.forage_kinds): continue
		var crowded := false
		for group in result:
			if Vector2(col-Vector2i(group.home.x,group.home.z)).length()<float(data.population.min_spacing): crowded = true
		if crowded: continue
		var count := rng.randi_range(data.population.group_size[0],data.population.group_size[1])
		var cells: Array = nav.group_cells(col,count,float(data.navigation.member_spacing))
		if cells.size()!=count: continue
		result.append({"id":"flock:%d:%d:%d" % [seed_value,col.x,col.y],"home":sample.cell,"cells":cells})
	return result

func prepare_arrival(event: Dictionary, plan: Dictionary, events: Node) -> Dictionary:
	if not WaterManager.initialized or not owner.duck_initialized: return {}
	var room: int = int(event.population_cap)-owner.animals_of_species("duck").size()
	if room<=0: return {"status":"blocked","reason":"population cap"}
	var rng := RandomNumberGenerator.new()
	rng.seed = int(String(plan.seed))+int(plan.attempt)*7919
	var habitats := groups(rng.randi())
	for group in habitats:
		var home: Vector3i = group.home
		if not owner._arrival_cell_allowed(home,event,events): continue
		var close := false
		for animal in owner.animals_of_species("duck"):
			if animal.position.distance_to(Vector3(home))<float(event.settlement_spacing): close = true
		if close: continue
		var count := mini(room,int(plan.count))
		var cells: Array = owner.duck_navigation.group_cells(Vector2i(home.x,home.z),count,2.0)
		if cells.size()!=count: continue
		var routes: Array = []
		var edge := "west"
		var distances := [home.x,1023-home.x,home.z,1023-home.z]
		var nearest := distances.find(distances.min())
		edge = ["west","east","north","south"][nearest]
		for cell: Vector3i in cells:
			var entry := cell
			if nearest==0: entry.x = 1
			elif nearest==1: entry.x = 1022
			elif nearest==2: entry.z = 1
			else: entry.z = 1022
			entry.y = maxi(cell.y,WorldGenerator.get_surface_y(entry.x,entry.z)+1)+16
			var dest: Dictionary = owner.duck_navigation.surface(Vector2i(cell.x,cell.z))
			if dest.is_empty(): break
			var path: PackedVector3Array = owner.duck_navigation.flight_path(Vector3(entry)+Vector3(.5,0,.5),dest.position)
			if path.is_empty(): break
			routes.append([SaveManager.pack_v3i(entry),SaveManager.pack_v3i(cell)])
		if routes.size()==count:
			return {"status":"ready","count":count,"route":routes[0],"member_routes":routes,"edge":edge}
	return {}

func spawn_member(event: Dictionary, batch: Dictionary, events: Node) -> String:
	if owner.animals_of_species("duck").size()>=int(event.population_cap): return "population cap"
	var route: Array = batch.member_routes[int(batch.issued)]
	var landing := SaveManager.unpack_v3i(route[-1])
	if not owner._arrival_cell_allowed(landing,event,events): return "unsafe"
	var dest: Dictionary = owner.duck_navigation.surface(Vector2i(landing.x,landing.z))
	if dest.is_empty() or not dest.water: return "habitat lost"
	var entry := SaveManager.unpack_v3i(route[0])
	if not owner._arrival_entry_free(entry,owner.duck_definition): return "wait"
	for other in owner.animals_of_species("duck"):
		if other.position.distance_to(dest.position)<1.5: return "wait"
	var start := Vector3(entry)+Vector3(.5,0,.5)
	var path: PackedVector3Array = owner.duck_navigation.flight_path(start,dest.position)
	if path.is_empty(): return "blocked"
	var id := "%s:member:%d" % [batch.id,int(batch.issued)]
	for animal in owner.animals:
		if animal.animal_id==id: return "spawned"
	var duck: Node3D = owner.add_duck(id,landing,int(String(batch.seed))+int(batch.issued)*7919,"flock:"+String(batch.id))
	duck.position = start
	duck.home = landing
	duck.begin_flight(path,landing,true)
	duck.arrival = {"event":batch.id,"status":"Flying inland","route":[]}
	return "spawned"
