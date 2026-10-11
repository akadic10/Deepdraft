extends SceneTree

const River := preload("res://scripts/components/RiverLayout.gd")
const Layout := preload("res://scripts/components/WorldLayout.gd")
var failures: Array[String] = []
func _init() -> void: _run.call_deferred()
func check(ok: bool,message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func _run() -> void:
	var generator = root.get_node("WorldGenerator")
	var manager = root.get_node("WaterManager")
	var clock = root.get_node("WorldClock")
	clock.paused = true
	var profile: Dictionary = generator.load_macro_layout_profile()
	var water_profile: Dictionary = generator.load_water_profile()
	var fallback := "--fallbacks" in OS.get_cmdline_user_args()
	if fallback: profile.max_attempts = 0
	var seeds: Array = range(32) if fallback else [1,42,1234,7331,8675309,20261010,2147483647,99]
	for seed_value in seeds:
		var layout: Dictionary = Layout.new().generate(seed_value,profile)
		var h := PackedInt32Array()
		var w := PackedInt32Array()
		h.resize(1024*1024)
		w.resize(h.size())
		w.fill(-1)
		for x in 1024:
			for z in 1024:
				var index := (x/32)*32+z/32
				h[x*1024+z] = layout.heights[index]
				if layout.water_index[index] >= 0: w[x*1024+z] = layout.water_bodies[layout.water_index[index]].waterline_y
		var original := h.duplicate()
		var river := River.carve(seed_value,layout,h,w,water_profile.river)
		check(river.spring.y >= 78,"spring too low: %d" % seed_value)
		check(river.columns.size()>100 and not river.falls.is_empty(),"missing river/falls: %d" % seed_value)
		var last := 128
		for p: Vector2i in river.route:
			check(w[p.x*1024+p.y]>=0,"dry gap on river route: %d %s" % [seed_value,p])
			var level := w[p.x*1024+p.y]
			check(level <= last,"uphill watercourse: %d %s" % [seed_value,p])
			last = level
		for p: Vector2i in river.columns:
			check(original[p.x*1024+p.y]<115,"river cut protected summit")
		check(river.spring_back!=Vector2i.ZERO,"spring lacks an upper rock face")
		var cave := preload("res://scripts/components/SpringCaveLayout.gd").build(seed_value,river,h,water_profile.spring_cave)
		for ci: int in cave.columns:
			var col := Vector2i(ci/1024,ci%1024)
			var d := Vector2(col-Vector2i(cave.mouth.x,cave.mouth.z)).dot(Vector2(river.spring_back))
			if d>=cave.length-3: check(h[ci]>cave.columns[ci].y,"spring chamber has no roof: %d" % seed_value)
		print("WaterWorldTest seed %d: mouth %s, %d wet columns, %d falls" % [seed_value,river.spring,river.columns.size(),river.falls.size()])
	if fallback:
		print("WaterWorldTest fallbacks: %s (32 routes)" % ("PASS" if failures.is_empty() else str(failures)))
		quit(0 if failures.is_empty() else 1)
		return
	# Real generation includes edge detail/caves and the owning autoloads.
	generator.generate(1234)
	while not generator._maps_ready: await process_frame
	manager.initialize()
	var mouth: Vector3i = generator.river_layout.spring
	check(manager.depth_at(mouth)>0,"generated source has no live water")
	var total: float = manager.flow.total_volume()
	var lake: Vector3i = generator.river_layout.outlet
	var lake_floor := lake-Vector3i.UP
	var full_lake: Dictionary = manager.serialize_state()
	check(not root.get_node("NavGrid").is_walkable(lake_floor),"navigation enters standing water")
	var withdrawn: float = manager.extract(lake,100)
	check(withdrawn>0 and root.get_node("NavGrid").is_walkable(lake_floor),"navigation did not refresh after drawdown")
	manager.restore_state(full_lake)
	check(not root.get_node("NavGrid").is_walkable(lake_floor),"restored water left a stale dry navigation cache")
	manager.extract(lake,100)
	check(root.get_node("NavGrid").is_walkable(lake_floor),"restored water retained incorrect wet boundary state")
	for _i in 100: manager.step(0.1)
	check(manager.flow.added>0,"natural spring did not supply the river")
	check(absf(manager.flow.total_volume()-(total+manager.flow.added-manager.flow.drained-manager.flow.extracted))<1e-6,"world volume accounting")
	var state: Dictionary = manager.serialize_state()
	manager._process(10)
	check(manager.serialize_state()==state,"pause advanced water")
	for _i in 20: manager.step(0.1)
	var future: Dictionary = manager.serialize_state()
	manager.restore_state(JSON.parse_string(JSON.stringify(state,"",false,true)))
	for _i in 20: manager.step(0.1)
	check(manager.serialize_state()==future,"world future diverged after load")
	if manager.serialize_state()!=future:
		var actual: Dictionary = manager.serialize_state()
		for key: String in future:
			if actual[key]!=future[key]:
				if key != "flow": print("DIFF ",key," ",actual[key]," expected ",future[key])
				else:
					for field: String in future.flow:
						if future.flow[field] != actual.flow[field]: print("FLOW DIFF ",field," ",str(actual.flow[field]).left(250)," expected ",str(future.flow[field]).left(250))
	if "--continuation" in OS.get_cmdline_user_args():
		print("WaterWorldTest continuation: %s" % ("PASS" if failures.is_empty() else str(failures)))
		generator.prepare_for_world_reload()
		quit(0 if failures.is_empty() else 1)
		return
	var dam: Vector3i = manager.dev_toggle_dam()
	check(dam!=Vector3i.ZERO,"no usable river dam site")
	var before_dam: float = manager.flow.total_volume()
	var input_before: float = manager.flow.added-manager.flow.drained
	# Apply measured inflow just upstream, so this is a deterministic barrier
	# and overflow test rather than a wait for a distant spring's travel time.
	# Ordinary untouched-source stability has its own long-running control.
	var feed := Vector3i.ZERO
	var route: Array = generator.river_layout.route
	for i in route.size():
		if route[i]!=Vector2i(dam.x,dam.z): continue
		var p: Vector2i = route[maxi(0,i-10)]
		feed = Vector3i(p.x,generator.get_surface_y(p.x,p.y)+1,p.y)
		break
	check(feed!=Vector3i.ZERO,"dam has no upstream feed location")
	for _i in 3000:
		manager.flow.add_at(feed,0.2,float(dam.y+4))
		manager.step(0.1)
	var flooded := 0
	for cell: Vector3i in manager.flow.mass:
		if generator.get_waterline(cell.x,cell.z)<0 and manager.flow.volume(cell)>=manager.standing_depth and Vector3(cell).distance_to(Vector3(dam))<24.0: flooded += 1
	check(flooded>0,"real river dam did not spill onto terrain")
	check(absf(manager.flow.total_volume()-before_dam-(manager.flow.added-manager.flow.drained-input_before))<1e-6,"dam edit/overflow volume accounting")
	print("WaterWorldTest: flooded %d previously dry columns; spring added %.3f; dam %s" % [flooded,manager.flow.added,dam])
	manager.dev_toggle_dam()
	# Breach a stored lake downward through authoritative terrain edits.
	var world = root.get_node("WorldData")
	var reservoir: Vector2i = generator.lake_center
	var old_floor: int = generator.get_surface_y(reservoir.x,reservoir.y)
	var old_volume: float = manager.flow.total_volume()
	for y in range(old_floor-3,old_floor+1): world.set_block(reservoir.x,y,reservoir.y,0)
	check(manager.depth_at(Vector3i(reservoir.x,old_floor-3,reservoir.y))>0,"live reservoir breach did not flood excavation")
	check(absf(manager.flow.total_volume()-old_volume)<1e-6,"live reservoir breach lost stored water")
	# Clock speed scales the fixed simulation ticks; pause was checked above.
	var time_before: int = manager.elapsed_usec
	clock.paused = false
	clock.speed = 2.0
	manager._process(0.1)
	check(manager.elapsed_usec-time_before==200000,"water ignores clock speed")
	clock.paused = true
	print("WaterWorldTest: %s; step %.2f ms" % ["PASS" if failures.is_empty() else str(failures),manager.last_step_usec/1000.0])
	generator.prepare_for_world_reload()
	quit(0 if failures.is_empty() else 1)
