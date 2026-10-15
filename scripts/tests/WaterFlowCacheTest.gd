extends SceneTree
const Flow = preload("res://scripts/components/WaterFlow.gd")
var failures: Array[String] = []
var geometry: Dictionary = {}

func _init() -> void: _run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func _run() -> void:
	for x in range(4,16): geometry[Vector2i(x,8)] = [Vector2i(10,20)]
	var flow = Flow.new()
	flow.spans_at = func(col: Vector2i): return geometry.get(col,[])
	for pair in [[4,8.0],[5,4.0],[6,2.0],[8,6.0]]: flow.seed_column(Vector3i(pair[0],10,8),pair[1])
	var start: float = flow.total_volume()
	flow._level_wet_reach(Vector3i(4,10,8),Vector2i.RIGHT)
	check(flow.volume(Vector3i(8,10,8))==6.0,"cached topology does not equalize through a dry gap")
	flow.add_at(Vector3i(7,10,8),1.0,20)
	flow._level_wet_reach(Vector3i(4,10,8),Vector2i.RIGHT)
	check(flow.volume(Vector3i(8,10,8))<6.0,"newly wet gap joins existing cached reach")
	check(absf(flow.total_volume()-start-1.0)<1e-8,"equalization conserves integer volume")
	# The changed column is remote from the cached reach's origin.
	geometry[Vector2i(6,8)] = []
	flow.terrain_changed(Vector2i(6,8))
	var downstream: int = flow.mass[Vector3i(8,10,8)]
	flow._level_wet_reach(Vector3i(4,10,8),Vector2i.RIGHT)
	check(flow.mass[Vector3i(8,10,8)]==downstream,"a new dam invalidates reaches rooted elsewhere")
	check(absf(flow.total_volume()-start-1.0)<1e-8,"solid displacement retains all water")
	check(flow.ceiling(Vector3i(4,10,8))==20,"original ceiling cached")
	geometry[Vector2i(4,8)] = [Vector2i(10,14)]
	flow.terrain_changed(Vector2i(4,8))
	check(flow.ceiling(Vector3i(4,10,8))==14,"lowered ceiling invalidates cached height")
	geometry[Vector2i(4,8)] = [Vector2i(8,14)]
	flow.terrain_changed(Vector2i(4,8))
	check(flow.ceiling(Vector3i(4,10,8))==10 and flow.ceiling(Vector3i(4,8,8))==14,"mining changes the space identity")
	check(flow.ceiling(Vector3i(5,8,8))==8,"absent space is not cached as a real ceiling")
	geometry[Vector2i(5,8)] = [Vector2i(8,20)]
	flow.terrain_changed(Vector2i(5,8))
	check(flow.ceiling(Vector3i(5,8,8))==20,"a previously absent space can become real")
	flow.level_reach=2
	check(flow._reach_geometry(Vector3i(8,10,8),Vector2i.RIGHT).size()==2,"short reach configuration applies")
	flow.level_reach=6
	check(flow._reach_geometry(Vector3i(8,10,8),Vector2i.RIGHT).size()==6,"changed reach length invalidates geometry")
	var saved: Dictionary=flow.serialize()
	flow.restore(saved)
	check(flow._ceilings.is_empty() and flow._reaches.is_empty(),"restore discards derived topology")
	check(flow.serialize()==saved,"cache reset does not change serialized simulation")
	for x in range(100,100+Flow.MAX_CACHED_REACHES+1): flow._reach_geometry(Vector3i(x,10,8),Vector2i.RIGHT)
	check(flow._reaches.size()<=Flow.MAX_CACHED_REACHES,"reach cache has bounded storage")
	_check_connection_ceilings()
	print("WATER_FLOW_CACHE_PASS" if failures.is_empty() else "WATER_FLOW_CACHE_FAIL")
	quit(0 if failures.is_empty() else 1)

func _check_connection_ceilings() -> void:
	geometry={Vector2i(4,8):[Vector2i(10,20)],Vector2i(5,8):[Vector2i(10,20)]}
	var flow=Flow.new()
	flow.spans_at=func(col: Vector2i): return geometry.get(col,[])
	var source:=Vector3i(4,10,8)
	var target:=Vector3i(5,10,8)
	flow.seed_column(source,8.0)
	check(flow.connections(source)[0][2]==20,"connection carries receiving ceiling")
	geometry[Vector2i(5,8)]=[Vector2i(10,14)]
	flow.terrain_changed(Vector2i(5,8))
	check(flow.connections(source)[0][2]==14,"neighbor edit invalidates receiving ceiling")
	for tick in 100: flow.step(.1,384)
	check(flow.level(target)<=14.0,"transfer respects lowered receiving ceiling")
	check(flow.total_volume()==8.0,"lowered ceiling preserves integer volume")
	flow.changed.clear()
	flow.remove_at(source,.1,10)
	check(flow.changed.has(source),"external withdrawal still notifies after a completed tick")
	flow.step(.1,0)
	var saved: Dictionary=flow.serialize()
	flow.restore(saved)
	check(flow._links.is_empty(),"restore discards connection ceiling snapshots")
	check(flow.connections(source)[0][2]==14,"restored connection uses current topology")
