extends SceneTree

const Solver := preload("res://scripts/components/WaterFlow.gd")
var errors: Array[String] = []
var geometry: Dictionary = {}

func _init() -> void: _run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok:
		errors.append(message)
		push_error(message)

func solver() -> RefCounted:
	var f := Solver.new()
	f.spans_at = func(col: Vector2i): return geometry.get(col,[])
	return f

func settle(f: RefCounted, count := 500) -> void:
	for _i in count: f.step(0.1,10000)

func _run() -> void:
	root.get_node("WorldClock").paused = true
	# Equal levels and exact conservation between differently elevated floors.
	geometry = {Vector2i(0,0):[Vector2i(4,20)],Vector2i(1,0):[Vector2i(6,20)]}
	var f := solver()
	f.seed_column(Vector3i(0,4,0),10)
	settle(f)
	check(absf(f.level(Vector3i(0,4,0))-10)<0.001,"unequal reservoir levels")
	check(absf(f.total_volume()-10)<1e-9,"transfer created/lost water")
	# An open waterfall drains into its lower channel, not sideways across a
	# higher terrace. Rotate the geometry to catch cardinal iteration bias.
	for direction: Vector2i in Solver.DIRECTIONS:
		var origin := Vector2i(10,10)
		var exit := origin+direction
		var side := origin+Vector2i(-direction.y,direction.x)
		geometry = {origin:[Vector2i(10,20)],exit:[Vector2i(4,20)],side:[Vector2i(8,20)]}
		f = solver()
		for _i in 100:
			f.add_at(Vector3i(origin.x,10,origin.y),0.1,11)
			f.remove_at(Vector3i(exit.x,4,exit.y),0.1,4,true)
			f.step(0.1,100)
		check(f.volume(Vector3i(side.x,8,side.y))==0,"free waterfall spilled onto higher side terrace %s: %s" % [direction,f.mass])
		check(absf(f.total_volume()-f.added+f.drained)<1e-8,"waterfall routing lost volume")
		# Close the lower exit: the same water must now escape over the terrace.
		geometry[exit] = [Vector2i(14,20)]
		f.terrain_changed(exit)
		for _i in 100:
			f.add_at(Vector3i(origin.x,10,origin.y),0.1,11)
			f.step(0.1,100)
		check(f.volume(Vector3i(side.x,8,side.y))>1,"blocked waterfall failed to spill")
	# Dam blocks direct route. Water accumulates, overtops side bank, fills land.
	geometry = {Vector2i(0,0):[Vector2i(4,20)],Vector2i(1,0):[Vector2i(14,20)],Vector2i(0,1):[Vector2i(8,20)],Vector2i(0,2):[Vector2i(4,20)]}
	f = solver()
	for _i in 400:
		f.add_at(Vector3i(0,4,0),0.1,12)
		f.step(0.1,100)
	check(f.depth_at(Vector3i(0,4,2))>0.5,"blocked channel did not flood low surrounding terrain")
	check(f.depth_at(Vector3i(1,14,0))==0,"water climbed above supplying head")
	check(absf(f.total_volume()-f.added)<1e-8,"source accounting differs")
	# A sealed mouth stops replenishing; outlet keeps stored lake below lip.
	geometry = {Vector2i(0,0):[Vector2i(4,20)]}
	f = solver()
	check(f.add_at(Vector3i(0,4,0),100,9)==5,"spring cap failed")
	check(f.add_at(Vector3i(0,4,0),1,9)==0,"submerged spring did not stop")
	check(f.remove_at(Vector3i(0,4,0),100,7,true)==2,"outlet drained below its lip")
	check(f.remove_at(Vector3i(0,4,0),100,7,true)==0,"outlet drained retained lake")
	# Excavate reservoir floor into a sealed cave; same water falls to cave floor.
	geometry = {Vector2i(0,0):[Vector2i(4,8),Vector2i(10,20)]}
	f = solver()
	f.seed_column(Vector3i(0,10,0),3)
	f.spans(Vector2i(0,0))
	geometry[Vector2i(0,0)] = [Vector2i(4,20)]
	f.terrain_changed(Vector2i(0,0))
	check(f.depth_at(Vector3i(0,4,0))==1,"breach did not flood cave")
	check(f.depth_at(Vector3i(0,10,0))==0,"breach left water suspended")
	check(absf(f.total_volume()-3)<1e-9,"breach volume loss")
	# Solid placement preserves displacement, including completely sealed volume.
	geometry[Vector2i(0,0)] = []
	f.terrain_changed(Vector2i(0,0))
	check(absf(f.total_volume()-3)<1e-9,"solid placement deleted water")
	geometry[Vector2i(0,0)] = [Vector2i(4,20)]
	f.terrain_changed(Vector2i(0,0))
	check(absf(f.total_volume()-3)<1e-9 and f.pending.is_empty(),"displaced volume did not return")
	# Active queue and fractional volume survive JSON and reproduce future flow.
	geometry = {Vector2i(0,0):[Vector2i(4,20)],Vector2i(1,0):[Vector2i(4,20)],Vector2i(2,0):[Vector2i(4,20)]}
	f = solver()
	f.seed_column(Vector3i(0,4,0),8)
	f.step(0.1,1)
	var restored := solver()
	restored.seed_column(Vector3i(0,4,0),8)
	restored.restore(JSON.parse_string(JSON.stringify(f.serialize(),"",false,true)))
	settle(f,10)
	settle(restored,10)
	check(f.serialize()==restored.serialize(),"JSON restore diverges from uninterrupted flow")
	var soil := preload("res://scripts/components/SoilMoisture.gd").new()
	var cell := Vector3i(1,4,1)
	soil.set_source(Vector3i(0,4,1),{cell:1000000},0)
	check(soil.value_units(cell,0)==0,"irrigation wets soil instantly")
	check(soil.value_units(cell,60000000)==500000,"irrigation did not rise gradually")
	check(soil.value_units(cell,120000000)==1000000,"irrigation did not saturate")
	var soil_state := soil.serialize()
	soil.value_units(cell,10000000000)
	check(soil.serialize()==soil_state,"moisture query mutated state")
	soil.set_source(Vector3i(0,4,1),{},120000000)
	check(soil.value_units(cell,840000000)==500000,"dry ditch did not gradually lose moisture")
	var soil_copy := preload("res://scripts/components/SoilMoisture.gd").new()
	soil_copy.restore(JSON.parse_string(JSON.stringify(soil.serialize())))
	check(soil_copy.value_units(cell,840000000)==500000,"moisture changed after JSON restore")
	print("WaterFlowTest: %s" % ("PASS" if errors.is_empty() else str(errors)))
	quit(0 if errors.is_empty() else 1)
