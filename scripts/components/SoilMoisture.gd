extends RefCounted

## Sparse, analytic soil moisture. Changing a wet contact first settles the old
## rate. Queries never advance state, so rendering cannot affect the simulation.
const SCALE := 1000000
var wet_usec := 120000000
var dry_usec := 1440000000
var soils: Dictionary = {}
var sources: Dictionary = {}
var contacts: Dictionary = {}

func value_units(cell: Vector3i, now: int) -> int:
	if not soils.has(cell): return 0
	var state: Dictionary = soils[cell]
	var duration := wet_usec if int(state.target)>int(state.value) else dry_usec
	var change := int(float(maxi(0,now-int(state.since)))*SCALE/duration)
	return mini(int(state.target),int(state.value)+change) if int(state.target)>int(state.value) else maxi(int(state.target),int(state.value)-change)

func set_source(source: Vector3i, reached: Dictionary, now: int) -> void:
	var affected: Dictionary = sources.get(source,{}).duplicate()
	for cell: Vector3i in sources.get(source,{}):
		contacts[cell].erase(source)
	for cell: Vector3i in reached:
		if not contacts.has(cell): contacts[cell] = {}
		contacts[cell][source] = reached[cell]
		affected[cell] = true
	sources[source] = reached
	for cell: Vector3i in affected:
		var target := 0
		for strength: int in contacts[cell].values(): target = maxi(target,strength)
		if soils.has(cell) and int(soils[cell].target)==target: continue
		soils[cell] = {"value":value_units(cell,now),"target":target,"since":now}

func serialize() -> Array:
	var result: Array = []
	var keys := soils.keys()
	keys.sort_custom(func(a: Vector3i,b: Vector3i): return a.x<b.x or (a.x==b.x and (a.z<b.z or (a.z==b.z and a.y<b.y))))
	for cell: Vector3i in keys:
		var state: Dictionary = soils[cell]
		result.append({"cell":[cell.x,cell.y,cell.z],"value":state.value,"target":state.target,"since":state.since})
	return result

func restore(entries: Array) -> void:
	soils.clear()
	for entry: Dictionary in entries:
		var p: Array = entry.cell
		soils[Vector3i(int(p[0]),int(p[1]),int(p[2]))] = {"value":int(entry.value),"target":int(entry.target),"since":int(entry.since)}
