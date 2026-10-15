extends SceneTree
## Exact comparison against the frozen solver preceding performance pass 184.
## Reference text is outside the runtime export. This is a diagnostic, not gameplay.
const REFERENCE := "res://docs/00_dev_roadmap/concepts/water_loop_20261014/WaterFlowBefore.gd.txt"
var failures: Array[String] = []
var geometry: Dictionary = {}
var before
var after
var before_usec := 0
var after_usec := 0
var reference: GDScript
var output := ""
func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=")
	_run.call_deferred()
func _run() -> void:
	if output.is_empty() or not "/water_loop_20261014/" in OS.get_user_data_dir().replace("\\","/"):
		push_error("Use an isolated water_loop_20261014 profile and --output path"); quit(2); return
	reference=GDScript.new()
	reference.source_code=FileAccess.get_file_as_string(REFERENCE)
	if reference.reload()!=OK: quit(2); return
	var fingerprint:=FileAccess.get_sha256("res://scripts/components/WaterFlow.gd")
	var cases: Array=[]
	for seed in [6813,47,991]: cases.append(_synthetic(seed))
	cases.append(_world())
	if fingerprint!=FileAccess.get_sha256("res://scripts/components/WaterFlow.gd"): failures.append("Source changed during test")
	var result: Dictionary={"cases":cases,"failures":failures,"reference_sha256":FileAccess.get_sha256(REFERENCE),"flow_sha256":fingerprint}
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("WATER_FLOW_DIFFERENTIAL ",JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)
func _synthetic(seed: int) -> Dictionary:
	before=reference.new()
	after=load("res://scripts/components/WaterFlow.gd").new()
	before_usec=0
	after_usec=0
	geometry.clear()
	var random:=RandomNumberGenerator.new()
	random.seed=seed
	for x in 24:
		for z in 24:
			var bottom:=12-floori(x/4.0)
			geometry[Vector2i(x,z)]=[Vector2i(bottom,24)] if z%5 else [Vector2i(4,6),Vector2i(bottom,24)]
	for flow in [before,after]:
		flow.spans_at=func(col: Vector2i): return geometry.get(col,[])
		flow.track_surface_motion=true
	for col: Vector2i in geometry:
		for span: Vector2i in geometry[col]:
			var amount:=random.randf_range(0.0,minf(3.0,span.y-span.x))
			if random.randf()<.2: continue
			for flow in [before,after]: flow.seed_column(Vector3i(col.x,span.x,col.y),amount)
	var initial: float=before.total_volume()
	var completed := 0
	for tick in 900:
		if tick%97==0:
			for solver in [before,after]: solver.track_surface_motion=not solver.track_surface_motion
		if tick in [250,375,600]:
			for solver in [before,after]:
				solver.epsilon=[.000001,.00001,.0001][tick%3]
				solver.conductance=[.5,3.0,8.0][tick%3]
		if tick%7==0:
			var source:=Vector3i(random.randi_range(0,23),15,random.randi_range(0,23))
			for flow in [before,after]: flow.add_at(source,.2,18)
		if tick%13==0:
			var outlet:=Vector3i(random.randi_range(0,23),15,random.randi_range(0,23))
			for flow in [before,after]: flow.remove_at(outlet,.3,9,tick%2==0)
		if tick in [80,200,400,600]:
			var col:=Vector2i(8+tick%9,10)
			geometry[col]=[] if tick==80 else [Vector2i(4,7),Vector2i(10,16)] if tick==200 else [Vector2i(4,24)]
			for flow in [before,after]: flow.terrain_changed(col)
		if tick==450:
			for flow in [before,after]: flow.restore(JSON.parse_string(JSON.stringify(flow.serialize(),"",false,true)))
		if tick==700:
			for flow in [before,after]: flow.level_reach=4
		for solver in ([before,after] if tick%2==0 else [after,before]):
			var started:=Time.get_ticks_usec()
			solver.step([.025,.1,.3][tick%3],[0,1,64,384][tick%4])
			if solver==before: before_usec+=Time.get_ticks_usec()-started
			else: after_usec+=Time.get_ticks_usec()-started
		if not _flow_equal(before,after):
			failures.append("seed %d tick %d diverged" % [seed,tick])
			break
		if absf(after.total_volume()-initial-after.added+after.drained+after.extracted)>1e-8:
			failures.append("conservation tick %d" % tick)
			break
		completed+=1
		before.changed.clear()
		after.changed.clear()
		if tick%3==0:
			before.surface_flux.clear()
			after.surface_flux.clear()
	return {"kind":"synthetic","seed":seed,"ticks":completed,"before_ms":before_usec/1000.0,"after_ms":after_usec/1000.0}

func _world() -> Dictionary:
	before_usec=0
	after_usec=0
	for service in ["SaveManager","WorldClock","TaskManager","WaterManager"]: root.get_node(service).set_process(false)
	root.get_node("WorldClock").paused=true
	var generator=root.get_node("WorldGenerator")
	var water=root.get_node("WaterManager")
	var scene:=Node3D.new()
	root.add_child(scene)
	current_scene=scene
	generator._reset_generation_state()
	generator.world_seed=1234
	generator._cache_block_ids()
	generator._layout_profile=generator.load_macro_layout_profile()
	generator.water_profile=generator.load_water_profile()
	generator._build_noise_instances()
	generator._build_seeded_maps()
	generator._apply_edge_detail()
	generator._build_river()
	generator._build_cave_maps()
	generator._maps_ready=true
	water.initialize()
	var original=water.get_script().new()
	scene.add_child(original)
	original.set_process(false)
	original.initialize()
	_attach_reference(original)
	# Both solvers begin with cold disposable topology caches.
	water.flow.restore(water.flow.serialize())
	water.flow.track_surface_motion=true
	original.flow.track_surface_motion=true
	if water.serialize_state()!=original.serialize_state(): failures.append("initial world differs")
	var snapshots:=1
	var completed := 0
	for tick in 500:
		if tick in [100,300]:
			water.dev_toggle_dam()
			original.test_dam=water.test_dam.duplicate(true)
		if tick==200:
			for owner in [water,original]: owner.extract(generator.river_layout.outlet,100)
		if tick==350:
			var state: Dictionary=water.serialize_state()
			for owner in [water,original]: owner.restore_state(JSON.parse_string(JSON.stringify(state,"",false,true)))
		var owners: Array = [original,water] if tick%2==0 else [water,original]
		for owner in owners:
			var start := Time.get_ticks_usec()
			owner.step(.1)
			if owner==original: before_usec+=Time.get_ticks_usec()-start
			else: after_usec+=Time.get_ticks_usec()-start
		if not _flow_equal(original.flow,water.flow):
			failures.append("world tick %d differs" % tick)
			break
		if tick%25==24:
			snapshots+=1
			if water.serialize_state()!=original.serialize_state():
				failures.append("full snapshot %d differs" % tick)
				break
		completed+=1
		original.flow.surface_flux.clear()
		water.flow.surface_flux.clear()
	return {"kind":"generated_world","seed":1234,"ticks":completed,"full_snapshots":snapshots,"before_ms":before_usec/1000.0,"after_ms":after_usec/1000.0}

func _attach_reference(owner: Node) -> void:
	var reference_flow=reference.new()
	reference_flow.spans_at=owner.flow.spans_at
	reference_flow.initial=owner.flow.initial.duplicate()
	reference_flow.conductance=owner.flow.conductance
	reference_flow.epsilon=owner.flow.epsilon
	reference_flow.level_reach=owner.flow.level_reach
	reference_flow.restore(owner.flow.serialize())
	reference_flow.track_surface_motion=true
	owner.flow=reference_flow

func _flow_equal(left: RefCounted, right: RefCounted) -> bool:
	# Compare all serialized inputs directly, plus transient notifications and
	# flux. Avoid sorting the full world into JSON-shaped arrays on every tick.
	return left.mass==right.mass and left.initial==right.initial and left.modified==right.modified \
		and left._queue.slice(left._head)==right._queue.slice(right._head) and left._queued==right._queued \
		and left.pending==right.pending and left.added_units==right.added_units \
		and left.drained_units==right.drained_units and left.extracted_units==right.extracted_units \
		and left.changed==right.changed and left.surface_flux==right.surface_flux
