extends SceneTree

var failures: Array[String] = []
func _init() -> void: _run.call_deferred()
func check(ok: bool,message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func _run() -> void:
	root.get_node("WorldClock").paused = true
	root.get_node("SaveManager").set_process(false)
	var gen = root.get_node("WorldGenerator")
	var water = root.get_node("WaterManager")
	var world = root.get_node("WorldData")
	var nav = root.get_node("NavGrid")
	var blocks = root.get_node("BlockRegistry")
	var seeds: Array = [1675083273,2544080684,474028005,1630876908,1234,42,7,65535,20261010]
	if "--source-only" in OS.get_cmdline_user_args(): seeds = [2544080684]
	var requested: Array = []
	for arg: String in OS.get_cmdline_user_args():
		if arg.is_valid_int(): requested.append(int(arg))
	if not requested.is_empty(): seeds = requested
	for seed_value in seeds:
		gen.generate(seed_value)
		while not gen._maps_ready: await process_frame
		water.initialize()
		var cave: Dictionary = gen.spring_cave
		var back: Vector2i = gen.river_layout.spring_back
		var side := Vector2i(-back.y,back.x)
		check(cave==preload("res://scripts/components/SpringCaveLayout.gd").build(seed_value,
			{"spring":cave.mouth,"spring_back":back},gen.heightmap,gen.water_profile.spring_cave),"cave is not deterministic")
		var cave_id: int = gen.get_cave_id(cave.source)
		check(cave_id>=0 and root.get_node("InteriorTracker").is_cave_discovered(cave_id),"open cave is concealed")
		check(not root.get_node("InteriorTracker").is_cave_discovered(0),"unrelated cave revealed")
		for index: int in cave.columns:
			var span: Vector3i = cave.columns[index]
			for y in range(span.x+1,span.y+1):
				check(not blocks.is_solid(world.get_terrain_block(index/1024,y,index%1024)),"cave air is solid")
			var col := Vector2i(index/1024,index%1024)
			var d := Vector2(col-Vector2i(cave.mouth.x,cave.mouth.z)).dot(Vector2(back))
			if d>=cave.length-3:
				check(blocks.is_solid(world.get_terrain_block(col.x,span.y+1,col.y)),"chamber has no roof: %d %s" % [seed_value,col])
		var stone: Vector3i = cave.stone
		check(not blocks.is_solid(world.get_terrain_block(stone.x,stone.y,stone.z)),"loose wet stone is embedded in terrain")
		check(blocks.is_solid(world.get_terrain_block(stone.x,stone.y-1,stone.z)),"loose wet stone lacks ledge support")
		check(stone.y>gen.river_layout.spring_level and gen.get_cave_id(stone)==cave_id,"wet stone is not exposed beside the cave pool")
		# A side route can pass the connectivity search while a bank pinches the
		# visible mouth. Require all three lanes to leave the cave downhill,
		# without a solid lip, missing water, or a sideways jog at the entrance.
		for u in range(-1,2):
			var previous: Vector3i = cave.mouth+Vector3i(side.x*u,0,side.y*u)
			for d in range(1,int(gen.water_profile.river.spring_exit_length)+1):
				var p := Vector2i(cave.mouth.x,cave.mouth.z)-back*d+side*u
				var cell: Vector3i = water.flow.space_at(Vector3i(p.x,previous.y,p.y))
				check(cell.x>=0 and cell.y<=previous.y,"spring exit lane obstructed: seed %d distance %d lane %d" % [seed_value,d,u])
				if cell.x<0: break
				check(water.flow.volume(cell)>=water.standing_depth,"spring exit lane is dry: seed %d distance %d lane %d" % [seed_value,d,u])
				check(not blocks.is_solid(world.get_terrain_block(cell.x,cell.y,cell.z)),"spring exit has a solid water cell")
				previous = cell
		# Prove the generated source still has an open wet route into the river,
		# rather than merely passing the no-flood test by sealing itself off.
		var target_col: Vector2i = gen.river_layout.route[20]
		var target: Vector3i = water.flow.space_at(Vector3i(target_col.x,gen.get_surface_y(target_col.x,target_col.y)+1,target_col.y))
		var reached := {cave.source:true}
		var queue: Array[Vector3i] = [cave.source]
		var cursor := 0
		while cursor<queue.size() and not reached.has(target) and cursor<4096:
			var cell := queue[cursor]
			cursor += 1
			for link: Array in water.flow.connections(cell):
				if reached.has(link[0]) or water.flow.volume(link[0])<=0 or link[1]>=gen.river_layout.spring_level: continue
				reached[link[0]] = true
				queue.append(link[0])
		check(reached.has(target),"source has no open water route to the river")
		var entry: Vector3i = cave.ledges[0]
		var end: Vector3i = cave.source+Vector3i(-side.x*2,1,-side.y*2)
		check(nav.is_walkable(entry) and nav.is_walkable(end),"ledge is not walkable")
		check(not nav.find_path(entry,end,12000).is_empty(),"no dry route through cave")
		# A fixed exterior coordinate can land in the winding river. Require
		# an actual dry bank outside the cave footprint to reach the ledge.
		var accessible := false
		for bank: int in [-1,1]:
			var bank_entry: Vector3i = cave.mouth+Vector3i(side.x*2*bank,1,side.y*2*bank)
			for d in range(1,5):
				for u in range(3,7):
					var outside := Vector2i(cave.mouth.x,cave.mouth.z)-back*d+side*u*bank
					var approach := Vector3i(outside.x,gen.get_surface_y(outside.x,outside.y),outside.y)
					if nav.is_walkable(approach) and not nav.find_path(approach,bank_entry,2000).is_empty():
						accessible = true
						break
				if accessible: break
			if accessible: break
		check(accessible,"no dry route from outside: %d" % seed_value)
		if not accessible:
			for d in range(-3,2):
				var row: Array = []
				for u in range(-4,5):
					var p := Vector2i(cave.mouth.x,cave.mouth.z)+back*d+side*u
					row.append([u,gen.get_surface_y(p.x,p.y),nav.is_walkable(Vector3i(p.x,cave.mouth.y+1,p.y))])
				print("Approach row ",d,": ",row)
		print("SpringCave seed ",seed_value," depth ",cave.length," ledges ",entry," to ",end)
		if seed_value==2544080684:
			var mining = load("res://scripts/systems/MiningDesignationController.gd").new()
			var stone_cells: Array[Vector3i] = [cave.stone]
			check(mining._filter_mineable_blocks(stone_cells).is_empty(),"fixed wet stone can be designated for mining")
			mining.free()
		if seed_value==2544080684 and not "--geometry-only" in OS.get_cmdline_user_args():
			var saved: Dictionary = water.serialize_state()
			for i in 100: water.step(0.1)
			var future: Dictionary = water.serialize_state()
			water.restore_state(JSON.parse_string(JSON.stringify(saved,"",false,true)))
			for i in 100: water.step(0.1)
			check(water.serialize_state()==future,"cave water future diverges after save/load")
			# Seal the real mouth, supply only through the actual wet stone, and
			# wait for the isolated source chamber to reach its discharge cap.
			var dam: Array[Vector3i] = []
			for u in range(-1,2):
				for y in range(cave.mouth.y,cave.mouth.y+2):
					var cell: Vector3i = cave.mouth+Vector3i(side.x*u,y-cave.mouth.y,side.y*u)
					world.set_block(cell.x,cell.y,cell.z,blocks.get_id("base:terrain:rock:rock07"))
					dam.append(cell)
			var before: float = water.flow.total_volume()
			var supplied: float = water.flow.added-water.flow.drained
			for i in 3000: water.step(0.1)
			check(water.flow.level(water.flow.space_at(cave.source))>gen.river_layout.spring_level-0.002,"blocked cave did not back up")
			var prior: float = water.flow.added
			for i in 100: water.step(0.1)
			print("Sealed spring residual supply ",water.flow.added-prior," level ",water.flow.level(water.flow.space_at(cave.source)))
			var missing := 0.0
			for cell: Vector3i in cave.water:
				if not dam.has(cell): missing += maxf(0,gen.river_layout.spring_level-water.flow.level(cell))
			print("Cave unfilled capacity ",missing," pending ",water.flow._queue.size()-water.flow._head)
			check(water.flow.add_at(cave.source,0.2,gen.river_layout.spring_level)==0,"submerged stone continues adding water")
			check(absf(water.flow.total_volume()-before-water.flow.added+water.flow.drained+supplied)<0.00001,"blocked cave loses water")
			for cell: Vector3i in dam: world.set_block(cell.x,cell.y,cell.z,0)
			for i in 1200: water.step(0.1)
			print("Reopened supply ",water.flow.added-prior," mouth ",water.depth_at(cave.mouth))
			check(water.flow.added>prior+0.1,"reopening mouth did not restart spring")
			# A real excavation alongside the stream must receive its water.
			var breach: Vector3i = cave.source+Vector3i(side.x*2,0,side.y*2)
			world.set_block(breach.x,breach.y,breach.z,0)
			for i in 100: water.step(0.1)
			check(water.depth_at(breach)>0.01,"excavation into source chamber did not fill")
		gen.prepare_for_world_reload()
		world.clear_world()
		root.get_node("InteriorTracker").clear_runtime_state()
		nav.clear_runtime_state()
		for i in 3: await process_frame
	print("SpringCaveTest: ","PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
