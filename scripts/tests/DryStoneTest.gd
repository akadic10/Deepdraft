extends SceneTree

var failures: Array[String] = []
func _init() -> void: _run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func _run() -> void:
	create_timer(120).timeout.connect(func(): push_error("Dry stone timeout"); quit(1))
	root.get_node("WorldClock").paused = true
	root.get_node("SaveManager").set_process(false)
	var gen = root.get_node("WorldGenerator")
	var world = root.get_node("WorldData")
	var water = root.get_node("WaterManager")
	var blocks = root.get_node("BlockRegistry")
	for seed_value in [2795346874,1234,42]:
		gen.generate(seed_value)
		while not gen._maps_ready: await process_frame
		water.initialize()
		var layout: Dictionary = gen.river_layout
		var stone: Vector3i = layout.dry_stone
		var intake: Vector3i = layout.outlet
		check(stone.y==gen.get_surface_y(stone.x,stone.z)+1,"loose stone does not rest on the lakebed")
		check(stone==intake and water.depth_at(intake)>0,"stone lacks a submerged intake")
		check(not blocks.is_solid(world.get_terrain_block(stone.x,stone.y,stone.z)),"loose stone displaces water with solid terrain")
		check(blocks.is_solid(world.get_terrain_block(stone.x,stone.y-1,stone.z)),"stone lacks lakebed support")
		check(gen.get_overview_strata_block_id(stone.x,stone.y-1,stone.z)==world.get_terrain_block(stone.x,stone.y-1,stone.z),"overview disagrees with supporting lakebed")
		var before: float = water.flow.total_volume()
		check(water.flow.remove_at(intake,100,layout.outlet_level,true)==0,"normal lake level drains through bottom stone")
		check(water.flow.add_at(intake,2,layout.outlet_level+2)==2,"intake blocked by stone")
		check(is_equal_approx(water.flow.remove_at(intake,0.8,layout.outlet_level,true),0.8),"outlet rate exceeds request")
		check(is_equal_approx(water.flow.remove_at(intake,100,layout.outlet_level,true),1.2),"outlet failed to retain lake")
		check(is_equal_approx(water.flow.level(intake),layout.outlet_level) and is_equal_approx(water.flow.total_volume(),before),"lake volume changed after excess drained")
		var state: Dictionary = water.serialize_state()
		for i in 20: water.step(0.1)
		var future: Dictionary = water.serialize_state()
		water.restore_state(JSON.parse_string(JSON.stringify(state,"",false,true)))
		for i in 20: water.step(0.1)
		check(water.serialize_state()==future,"dry stone water continuation diverges after load")
		print("Dry stone seed ",seed_value," model base=",stone," intake=",intake," retained level=",layout.outlet_level)
		gen.prepare_for_world_reload()
		world.clear_world()
		root.get_node("InteriorTracker").clear_runtime_state()
		root.get_node("NavGrid").clear_runtime_state()
		for i in 3: await process_frame
	print("DryStoneTest: ","PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
