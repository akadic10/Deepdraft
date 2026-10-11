extends SceneTree

## The two user-reported worlds must stay inside their natural channels.
## Exercise real edge-detailed terrain, the same fixed budget as live play,
## and a long unedited control. WaterWorldTest covers a real dam and breach.
var failures: Array[String] = []

func _init() -> void: _run.call_deferred()

func check(ok: bool,message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func _run() -> void:
	var generator = root.get_node("WorldGenerator")
	var manager = root.get_node("WaterManager")
	var world = root.get_node("WorldData")
	var nav = root.get_node("NavGrid")
	root.get_node("WorldClock").paused = true
	var seeds: Array = [474028005,1630876908,1234,42]
	if not OS.get_cmdline_user_args().is_empty():
		seeds = []
		for arg: String in OS.get_cmdline_user_args(): seeds.append(int(arg))
	for seed_value in seeds:
		generator.generate(seed_value)
		while not generator._maps_ready: await process_frame
		manager.initialize()
		for col: Vector2i in generator.river_layout.columns:
			for dir: Vector2i in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
				var bank := col+dir
				if generator.get_waterline(bank.x,bank.y)>=0: continue
				check(generator.get_surface_y(bank.x,bank.y)>=generator.get_surface_y(col.x,col.y)+2,"river has an uncontained dry edge")
		var initial: float = manager.flow.total_volume()
		var peak_count := 0
		var peak_depth := 0.0
		var spill := 0.0
		for i in 3000:
			manager.step(0.1)
			if i%100!=99: continue
			var flooded := 0
			spill = 0.0
			for key: Vector3i in manager.flow.mass:
				if generator.get_waterline(key.x,key.z)>=0: continue
				if generator.spring_cave.water.has(key): continue
				var depth: float = manager.flow.volume(key)
				peak_depth = maxf(peak_depth,depth)
				spill += depth
				if depth>=manager.standing_depth: flooded += 1
			peak_count = maxi(peak_count,flooded)
		check(peak_count==0,"untouched river floods for seed %d: %d cells, depth %.6f" % [seed_value,peak_count,peak_depth])
		check(spill<0.001,"untouched waterfall still leaks: seed %d volume %.6f" % [seed_value,spill])
		check(absf(manager.flow.total_volume()-initial-manager.flow.added+manager.flow.drained)<1e-6,"natural river volume accounting")
		print("WaterStability seed %d: peak flooded %d; peak off-channel depth %.6f; final spill %.6f; supplied %.3f" % [seed_value,peak_count,peak_depth,spill,manager.flow.added])
		# Shallow films remain conserved and saveable, without blocking land.
		var dry := Vector3i(100,generator.get_surface_y(100,100)+1,100)
		check(nav.is_walkable(dry-Vector3i.UP),"dry test ground is not walkable")
		manager.flow.add_at(dry,0.005,dry.y+0.005)
		manager._flush_changes()
		check(manager.live_block(dry,0)==0,"thin film blocks land occupancy")
		check(nav.is_walkable(dry-Vector3i.UP),"thin film blocks cached navigation")
		manager.flow.add_at(dry,0.1,dry.y+0.105)
		manager._flush_changes()
		check(manager.has_standing_water(dry) and manager.live_block(dry,0)!=0,"real standing water does not block occupancy")
		check(not nav.is_walkable(dry-Vector3i.UP),"rising water did not invalidate navigation")
		manager.extract(dry,1)
		check(manager.live_block(dry,0)==0,"drained water leaves blocked occupancy")
		check(nav.is_walkable(dry-Vector3i.UP),"drained film left stale navigation")
		generator.prepare_for_world_reload()
		world.clear_world()
		# Drain the stopped generator's deferred completion/cleanup before a
		# new worker thread exists (the live save/load path replaces the scene).
		for _i in 3: await process_frame
	print("WaterStabilityTest: %s" % ("PASS" if failures.is_empty() else str(failures)))
	quit(0 if failures.is_empty() else 1)
