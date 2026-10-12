extends SceneTree

const SEEDS := [1908979947,7,1234,65535,20261007,42,8675309,305419896]
var failures: Array[String] = []
var generator: Node
var blocks: Node

func _init() -> void: _run.call_deferred()

func _run() -> void:
	if not OS.get_environment("APPDATA").replace("\\","/").contains("/tmp/"): quit(2); return
	generator = root.get_node("WorldGenerator")
	blocks = root.get_node("BlockRegistry")
	root.get_node("SaveManager").set_process(false)
	root.get_node("WorldClock").set_paused(true)
	_check_filter()
	var report: Array = []
	for seed_value: int in SEEDS:
		var started := Time.get_ticks_msec()
		root.get_node("WorldData").clear_world()
		generator._reset_generation_state()
		generator.world_seed = seed_value
		generator._cache_block_ids()
		generator._layout_profile = generator.load_macro_layout_profile()
		generator.water_profile = generator.load_water_profile()
		generator._build_noise_instances()
		generator._build_seeded_maps()
		generator._apply_edge_detail()
		generator._build_river()
		generator._build_cave_maps()
		generator._maps_ready = true
		var map_ms := Time.get_ticks_msec()-started
		var strata := [{},{},{},{}]
		var totals := [0,0,0,0]
		var examples := {}
		for x in range(8,1016,16):
			for z in range(8,1016,16):
				for y in range(4,int(generator.get_surface_y(x,z))):
					var id: int = generator.get_generated_block_id(x,y,z)
					if not blocks.is_solid(id): continue
					var stage := 0
					for depth: int in [10,20,32]:
						if generator.has_natural_cover(x,y,z,depth): stage += 1
					totals[stage] += 1
					var key: String = blocks.get_key(id)
					if not (key.begins_with("base:terrain:ore:") or key.begins_with("base:terrain:gem:")): continue
					strata[stage][key] = int(strata[stage].get(key,0))+1
					var def: Dictionary = blocks.get_resource_def(key)
					_expect(generator.has_natural_cover(x,y,z,int(def.min_burial)),"resource violates original cover")
					_expect(y<=int(def.depth_bias.max_y),"precious resource bypasses descent")
					if not examples.has(key): examples[key] = Vector3i(x,y,z)
		for key: String in examples:
			var cell: Vector3i = examples[key]
			var before: int = generator.get_generated_block_id(cell.x,cell.y,cell.z)
			root.get_node("WorldData").set_block(cell.x,cell.y+1,cell.z,blocks.AIR_ID)
			_expect(generator.get_generated_block_id(cell.x,cell.y,cell.z)==before,"mining changed geology")
			_expect(generator.get_overview_strata_block_id(cell.x,cell.y,cell.z)!=before,"hidden resource leaked to strata")
		for key: String in strata[0]:
			_expect(key.get_slice(":",3) in ["coal","copper"],"starter excavation found advanced material")
		var saved_excavation := {}
		if seed_value==1908979947:
			var excavation: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://scripts/tests/fixtures/starter_excavation.json"))
			for cell: Array in excavation.cells:
				var key: String = blocks.get_key(generator.get_generated_block_id(int(cell[0]),int(cell[1]),int(cell[2])))
				saved_excavation[key] = int(saved_excavation.get(key,0))+1
		var rare_examples := _find_deep_gems()
		_expect(rare_examples.size()==4,"deep precious gems missing in seed %d" % seed_value)
		var row := {"seed":seed_value,"solid_samples_by_stage":totals,"resources_by_stage":strata,"saved_excavation":saved_excavation,"starter_tunnel":_starter_tunnel(),"rare_examples":rare_examples,"map_ms":map_ms,"elapsed_ms":Time.get_ticks_msec()-started}
		report.append(row)
		print("RESOURCE_SEED ",JSON.stringify(row))
		await process_frame
	var output := FileAccess.open("res://tmp/colony_balance_review_20261011/resource_progression.json",FileAccess.WRITE)
	output.store_string(JSON.stringify({"stages":["cover below 10","cover 10–19","cover 20–31","cover 32+"],"method":"x/z every 16 blocks, all solid Y; eight fresh full layouts including rivers and caves","seeds":report,"failures":failures},"  "))
	for failure: String in failures: push_error(failure)
	print("RESOURCE_PROGRESSION_OK" if failures.is_empty() else "RESOURCE_PROGRESSION_FAIL")
	quit(0 if failures.is_empty() else 1)

func _check_filter() -> void:
	var source := PackedInt32Array()
	for x in 17:
		for z in 17: source.append(posmod(x*x+z*13+x*z,128))
	var filter = load("res://scripts/components/NaturalRockCover.gd")
	for radius in [1,2,6,10]:
		var result: PackedByteArray = filter.minimum_heights(source,17,radius)
		for x in 17:
			for z in 17:
				var minimum := 127
				for cx in range(maxi(0,x-radius),mini(17,x+radius+1)):
					for cz in range(maxi(0,z-radius),mini(17,z+radius+1)): minimum = mini(minimum,source[cx*17+cz])
				_expect(result[x*17+z]==minimum,"minimum filter differs from brute force")

func _find_deep_gems() -> Dictionary:
	var found := {}
	for x in range(48,976):
		for z in range(48,976):
			if not generator.has_natural_cover(x,4,z,40): continue
			for y in range(4,13):
				var noise: float = (generator.noise_gem.get_noise_3d(x,y,z)+1.0)*.5
				if noise<=.88: continue
				var key: String = blocks.get_key(generator.get_generated_block_id(x,y,z))
				if key.get_slice(":",3) in ["ruby","sapphire","emerald","diamond"]: found[key] = str(Vector3i(x,y,z))
				if found.size()==4: return found
	return found

func _starter_tunnel() -> Dictionary:
	# Contiguous 4-wide, 4-high, 8-deep excavation into a natural starter cliff.
	for x in range(256,768,4):
		for z in range(256,768,4):
			var floor_y: int = generator.get_surface_y(x,z)
			if floor_y<32 or floor_y>60: continue
			for direction: Vector3i in [Vector3i.LEFT,Vector3i.RIGHT,Vector3i.FORWARD,Vector3i.BACK]:
				if generator.get_surface_y(x+direction.x,z+direction.z)<floor_y+4: continue
				var counts := {}
				var start := Vector3i(x,floor_y,z)
				var side := Vector3i(direction.z,0,-direction.x)
				for step in range(1,9):
					for width in range(-1,3):
						for rise in range(1,5):
							var cell := start+direction*step+side*width+Vector3i.UP*rise
							var key: String = blocks.get_key(generator.get_generated_block_id(cell.x,cell.y,cell.z))
							counts[key] = int(counts.get(key,0))+1
							_expect(not key.begins_with("base:terrain:gem:") and key not in ["base:terrain:ore:iron","base:terrain:ore:gold","base:terrain:ore:silver"],"starter cliff tunnel contains advanced material")
				return {"start":str(start),"direction":str(direction),"counts":counts}
	_expect(false,"no starter cliff sample found")
	return {}

func _expect(ok: bool, message: String) -> void:
	if not ok and not message in failures: failures.append(message)
