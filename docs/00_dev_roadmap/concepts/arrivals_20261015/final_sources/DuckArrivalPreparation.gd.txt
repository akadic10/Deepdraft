extends RefCounted
## Main-thread continuation only. No live navigation query cache crosses a frame.
## Partial work is transient; the saved event seed/attempt restarts it on load.
var owner: Node
var event: Dictionary
var plan: Dictionary
var events: Node
var data: Dictionary
var nav: RefCounted
var room: int
var rng := RandomNumberGenerator.new()
var keys: Array = []
var cursor := 0
var all := PackedInt32Array()
var river: Array = []
var habitats: Array[Dictionary] = []
var attempt := 0
var group_index := 0
var cells: Array = []
var routes: Array = []
var edge := ""
var nearest := 0
var flight: Dictionary = {}
var entry := Vector3i.ZERO
var phase := "pools"
var done := false
var result: Dictionary = {}

func setup(wildlife: Node, definition: Dictionary, decision: Dictionary, director: Node, capacity: int) -> void:
	owner=wildlife; event=definition; plan=decision.duplicate(true); events=director
	data=owner.duck_definition; nav=owner.duck_navigation; room=capacity
	rng.seed=int(String(plan.seed))+int(plan.attempt)*7919
	var seed_value:=rng.randi()
	rng.seed=seed_value+int(data.population.salt)
	keys=WaterManager.flow.mass.keys()
	river=WorldGenerator.river_layout.get("columns",{}).keys()
	river.sort()

func advance(deadline_usec: int) -> bool:
	while not done and (deadline_usec<=0 or Time.get_ticks_usec()<deadline_usec):
		match phase:
			"pools":
				# Integer ordering is exactly Vector2i's x/z ordering, including duplicates.
				var end:=mini(cursor+32,keys.size())
				while cursor<end:
					var key: Vector3i=keys[cursor]
					if WaterManager.flow.volume(key)>=float(data.navigation.swim_depth): all.append(key.x*1024+key.z)
					cursor+=1
				if cursor==keys.size():
					keys.clear()
					all.sort()
					phase="habitats"
					if all.is_empty(): done=true
			"habitats":
				if habitats.size()>=int(data.population.groups) or attempt>=int(data.population.attempts):
					phase="landing"; continue
				var use_river:=habitats.is_empty() and attempt<150 and not river.is_empty()
				attempt+=1
				var col: Vector2i
				if use_river: col=river[rng.randi_range(0,river.size()-1)]
				else:
					var packed:=all[rng.randi_range(0,all.size()-1)]
					col=Vector2i(packed/1024,packed%1024)
				var sample: Dictionary=nav.surface(col)
				if sample.is_empty() or not sample.water or not nav.near_shore(col,int(data.population.shore_distance),data.forage_kinds): continue
				var crowded:=false
				for group in habitats:
					if Vector2(col-Vector2i(group.home.x,group.home.z)).length()<float(data.population.min_spacing): crowded=true
				if crowded: continue
				var count:=rng.randi_range(data.population.group_size[0],data.population.group_size[1])
				var group_cells: Array=nav.group_cells(col,count,float(data.navigation.member_spacing))
				if group_cells.size()==count: habitats.append({"home":sample.cell,"cells":group_cells})
			"landing":
				if group_index>=habitats.size(): done=true; continue
				var home: Vector3i=habitats[group_index].home
				group_index+=1
				if not owner._arrival_cell_allowed(home,event,events): continue
				var close:=false
				for animal in owner.animals_of_species("duck"):
					if animal.position.distance_to(Vector3(home))<float(event.settlement_spacing): close=true
				if close: continue
				var count:=mini(room,int(plan.count))
				cells=nav.group_cells(Vector2i(home.x,home.z),count,2.0)
				if cells.size()!=count: continue
				routes=[]
				var distances: Array=[home.x,1023-home.x,home.z,1023-home.z]
				nearest=distances.find(distances.min())
				edge=["west","east","north","south"][nearest]
				phase="member"
			"member":
				if routes.size()==cells.size():
					result={"status":"ready","count":cells.size(),"route":routes[0],"member_routes":routes,"edge":edge}
					done=true; continue
				var cell: Vector3i=cells[routes.size()]
				entry=cell
				if nearest==0: entry.x=1
				elif nearest==1: entry.x=1022
				elif nearest==2: entry.z=1
				else: entry.z=1022
				entry.y=maxi(cell.y,WorldGenerator.get_surface_y(entry.x,entry.z)+1)+16
				var dest: Dictionary=nav.surface(Vector2i(cell.x,cell.z))
				if dest.is_empty(): phase="landing"; continue
				flight=nav.begin_flight_path(Vector3(entry)+Vector3(.5,0,.5),dest.position)
				phase="flight"
			"flight":
				if not nav.advance_flight_path(flight,deadline_usec): return false
				if flight.result.is_empty(): phase="landing"
				else:
					routes.append([SaveManager.pack_v3i(entry),SaveManager.pack_v3i(cells[routes.size()])])
					phase="member"
				flight={}
	return done
