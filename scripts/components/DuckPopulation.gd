extends RefCounted

## Seeded shore groups and aerial arrivals; the wildlife owner owns all actors.
var owner: Node
var _arrival_search: RefCounted
var _arrival_key := ""

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

func cancel_arrival_preparation() -> void:
	_arrival_search=null
	_arrival_key=""

func prepare_arrival(event: Dictionary, plan: Dictionary, events: Node, deadline_usec: int = 0) -> Dictionary:
	if not WaterManager.initialized or not owner.duck_initialized: return {}
	var room: int=int(event.population_cap)-owner.animals_of_species("duck").size()
	if room<=0:
		cancel_arrival_preparation()
		return {"status":"blocked","reason":"population cap"}
	var key:="%s:%s:%d" % [String(plan.id),String(plan.seed),int(plan.attempt)]
	if _arrival_search==null or _arrival_key!=key:
		cancel_arrival_preparation()
		_arrival_key=key
		_arrival_search=preload("res://scripts/components/DuckArrivalPreparation.gd").new()
		_arrival_search.setup(owner,event,plan,events,room)
	# Reuse queries only during this synchronous slice, never across frames.
	owner.duck_navigation.begin_update()
	var finished: bool=_arrival_search.advance(deadline_usec)
	owner.duck_navigation.end_update()
	if not finished: return {"status":"pending"}
	var result: Dictionary=_arrival_search.result
	cancel_arrival_preparation()
	return result

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
