extends SceneTree

## Live map phases, actual blocks, water streaming and navigation on natural terrain.
const Validator = preload("res://scripts/components/WorldLayoutValidator.gd")
const SEEDS := [7, 1234, 65535, 20261007, 3381051336, 4294967295, 314159265, 2147483647]
var _failures: Array[String] = []
var _generator: Node
var _blocks: Node
var _world: Node
var _nav: Node


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if not OS.get_environment("APPDATA").replace("\\", "/").contains("/tmp/world_layout_review/"):
		printerr("Use isolated APPDATA below tmp/world_layout_review.")
		quit(2)
		return
	_generator = root.get_node("WorldGenerator")
	_blocks = root.get_node("BlockRegistry")
	_world = root.get_node("WorldData")
	_nav = root.get_node("NavGrid")
	root.get_node("SaveManager").set_process(false)
	root.get_node("WorldClock").set_paused(true)
	var report: Array = []
	var force_fallback := "--fallbacks" in OS.get_cmdline_user_args()
	var seeds: Array = range(32) if force_fallback else SEEDS
	for world_seed: int in seeds:
		var started := Time.get_ticks_msec()
		_world.clear_world()
		_nav.clear_runtime_state()
		_generator._reset_generation_state()
		_generator.world_seed = world_seed
		_generator._cache_block_ids()
		_generator._layout_profile = _generator.load_macro_layout_profile()
		if force_fallback: _generator._layout_profile["max_attempts"] = 0
		_generator._build_noise_instances()
		_generator._build_seeded_maps()
		_generator._apply_edge_detail()
		_generator._validate_finished_layout()
		_generator._build_cave_maps()
		var validation: Dictionary = _generator._layout_validation.duplicate(true)
		_expect(validation.get("errors", ["missing validation"]).is_empty(), "Seed %d: %s" % [world_seed, validation.get("errors", [])])
		if not _failures.is_empty(): break
		_generator._maps_ready = true
		_check_rough_faces()
		_expect(_check_gameplay(), "Gameplay checks did not complete.")
		_check_water()
		_check_blocks()
		if world_seed == 7: _check_rejections()
		var fingerprint := (var_to_bytes(_generator.heightmap) + var_to_bytes(_generator.waterline_map)).hex_encode().sha256_text()
		report.append({"seed": world_seed, "validation": validation, "elapsed_ms": Time.get_ticks_msec() - started, "map_sha256": fingerprint})
		print("WorldGenerationTest: seed %d; max %d; summit columns %d; detail %d; %d ms" % [world_seed,
			validation["max_y"], validation["summit_columns"], validation["detailed_columns"], Time.get_ticks_msec() - started])
		await process_frame
	var report_name := "live_fallback_report.json" if force_fallback else "live_report.json"
	var file := FileAccess.open("res://tmp/world_layout_review/" + report_name, FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed": _failures.is_empty(), "failures": _failures, "seeds": report}, "\t"))
	file.close()
	for failure in _failures: printerr(failure)
	print("WorldGenerationTest: %s (%d seeds)" % ["PASS" if _failures.is_empty() else "FAIL", report.size()])
	quit(0 if _failures.is_empty() else 1)


func _check_gameplay() -> bool:
	# Choose an existing shelf for this test; generation does not reserve one.
	var rect := _natural_mining_test_rect()
	_expect(rect.has_area(), "No natural shelf found for the mining fixture.")
	if not rect.has_area(): return false
	var midpoint := rect.get_center()
	var center := Vector3i(midpoint.x, _generator.get_surface_y(midpoint.x, midpoint.y), midpoint.y)
	_expect(_nav.is_walkable(center), "Natural shelf center is not walkable.")
	var flag: Node = load("res://scripts/systems/FlagPlacementController.gd").new()
	_expect(flag._is_valid_cell(center), "Flag cannot be placed on valid natural ground.")
	flag.free()
	var flora: Node = load("res://scripts/systems/SurfaceFloraSpawner.gd").new()
	for cell in range(1024):
		if _generator._macro_layout["water_index"][cell] >= 0: continue
		var x := (cell / 32) * 32 + 16
		var z := (cell % 32) * 32 + 16
		_expect(flora._footprint_ok({}, x, z, 1, _generator.get_surface_y(x, z)), "Dry flat ground has an artificial flora exclusion.")
	flora.free()
	var approach := Vector3i(-1, -1, -1)
	var wall := approach
	for x in range(rect.position.x, rect.end.x):
		for z in range(rect.position.y, rect.end.y):
			if _generator.get_surface_y(x, z) != 43: continue
			for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var next: Vector2i = Vector2i(x, z) + direction
				if _generator.get_surface_y(next.x, next.y) >= 47:
					approach = Vector3i(x, 43, z)
					wall = Vector3i(next.x, 44, next.y)
					break
			if wall.y >= 0: break
		if wall.y >= 0: break
	_expect(wall.y >= 0, "No usable mining face beside natural shelf.")
	if wall.y < 0: return false
	_expect(not _nav.find_path(center, approach, 12000).is_empty(), "No path across natural shelf to mining face.")
	_expect(_blocks.is_solid(_generator.get_generated_block_id(wall.x, wall.y, wall.z)), "Mining face is not solid.")
	var mining: Node = load("res://scripts/systems/MiningDesignationController.gd").new()
	mining._mine_block_world(wall)
	_expect(_world.get_block(wall.x, wall.y, wall.z) == _blocks.AIR_ID, "Mining did not remove generated rock.")
	_expect(_world.get_block(wall.x, wall.y + 1, wall.z) == _generator.get_generated_block_id(wall.x, wall.y + 1, wall.z), "Materializing a mined chunk lost neighboring terrain.")
	mining.free()
	return true


func _natural_mining_test_rect() -> Rect2i:
	var layout: Dictionary = _generator._macro_layout
	for cell in range(1024):
		if layout["ranks"][cell] != 3 or layout["water_index"][cell] >= 0: continue
		var point := Vector2i(cell / 32, cell % 32)
		for direction: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next := point + direction
			if next.x < 0 or next.y < 0 or next.x >= 32 or next.y >= 32: continue
			var neighbor := next.x * 32 + next.y
			if layout["ranks"][neighbor] == 4 and layout["water_index"][neighbor] < 0:
				return Rect2i(point * 32, Vector2i(32, 32))
	return Rect2i()


## Check every original cliff segment, including summit lips, foothill edges,
## lowland transitions and both shores. A uniformly shifted wall is insufficient.
func _check_rough_faces() -> void:
	var layout: Dictionary = _generator._macro_layout
	var heights: PackedInt32Array = layout["heights"]
	var water: PackedInt32Array = layout["water_index"]
	var shore_land := PackedInt32Array()
	var shore_shallow := PackedInt32Array()
	shore_land.resize(layout["water_bodies"].size())
	shore_shallow.resize(shore_land.size())
	for cell in range(1024):
		if water[cell] >= 0: continue
		var mx := cell / 32
		var mz := cell % 32
		for direction: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next := Vector2i(mx, mz) + direction
			if next.x < 0 or next.y < 0 or next.x >= 32 or next.y >= 32: continue
			var neighbor := next.x * 32 + next.y
			if heights[neighbor] >= heights[cell]: continue
			var changed := 0
			var profiles: Dictionary = {}
			for along in range(32):
				var x := mx * 32 + (31 if direction.x > 0 else 0 if direction.x < 0 else along)
				var z := mz * 32 + (31 if direction.y > 0 else 0 if direction.y < 0 else along)
				var samples: Array[int] = []
				for distance in range(1, 4):
					var tx := x + direction.x * distance
					var tz := z + direction.y * distance
					var height: int = _generator.get_surface_y(tx, tz)
					samples.append(height)
					if height <= heights[neighbor]: continue
					changed += 1
					if water[neighbor] >= 0:
						if _generator.get_waterline(tx, tz) < 0: shore_land[water[neighbor]] += 1
						else: shore_shallow[water[neighbor]] += 1
				profiles[str(samples)] = true
			_expect(changed > 0 and profiles.size() > 1, "Cliff/shore remained uniform: cell %d toward %s." % [cell, direction])
	for i in range(shore_land.size()):
		_expect(shore_land[i] > 0 and shore_shallow[i] > 0, "Water body lacks irregular land and submerged ledges.")


func _check_water() -> void:
	var water_id: int = _blocks.get_id(&"base:terrain:water:source")
	for body: Dictionary in _generator.water_bodies:
		var index := int(body["cells"][0])
		var x := (index / 32) * 32 + 16
		var z := (index % 32) * 32 + 16
		var floor_y := int(body["floor_y"])
		var line := int(body["waterline_y"])
		_expect(_generator.get_visible_surface_y(x, z) == line and _generator.get_waterline(x, z) == line, "Water visible surface differs from body.")
		_expect(_generator.get_overview_surface_height(x, z) == -1, "Water treated as a solid overview surface.")
		_expect(_blocks.is_solid(_generator.get_generated_block_id(x, floor_y, z)), "Missing lake floor.")
		for y in range(floor_y + 1, line + 1):
			_expect(_generator.get_generated_block_id(x, y, z) == water_id, "Water column has a gap.")
		_expect(_generator.get_generated_block_id(x, line + 1, z) == _blocks.AIR_ID, "Water extends above its line.")
		_generator._fill_chunk_column(x / 16, z / 16)
		for y in range(floor_y + 1, line + 1):
			_expect(_world.get_block(x, y, z) == water_id, "Streamed chunk lost water above lake floor.")
		_expect(_generator.get_visible_surface_block_id(x, z) == water_id, "Overview water block disagrees with generated block.")
		# Exercise actual streamed ledges, not only untouched basin centers.
		var checked: Dictionary = {}
		for macro_cell: int in body["cells"]:
			for dx in range(32):
				for dz in range(32):
					var sx := (macro_cell / 32) * 32 + dx
					var sz := (macro_cell % 32) * 32 + dz
					var surface: int = _generator.get_surface_y(sx, sz)
					if surface <= floor_y: continue
					var wet: bool = _generator.get_waterline(sx, sz) >= 0
					if checked.has(wet): continue
					checked[wet] = true
					var mask: Dictionary = _generator.lake_columns if body["kind"] == "lowland_lake" else _generator.tarn_columns
					_expect(mask.has(Vector2i(sx, sz)) == wet, "Detailed shore has stale water membership.")
					_generator._fill_chunk_column(sx / 16, sz / 16)
					for sy in range(floor_y, maxi(surface, line) + 2):
						var expected: int = _generator.get_generated_block_id(sx, sy, sz)
						_expect(_world.get_block(sx, sy, sz) == expected, "Streamed shore differs from detailed terrain.")
					_expect(_generator.get_visible_surface_y(sx, sz) == (line if wet else surface), "Detailed shoreline surface is stale.")
		_expect(checked.size() == 2, "Missing streamed wet/dry shoreline coverage.")


func _check_blocks() -> void:
	var layout: Dictionary = _generator._macro_layout
	var rank_seen: Dictionary = {}
	for index in range(1024):
		var x := (index / 32) * 32 + 16
		var z := (index % 32) * 32 + 16
		for y in range(4):
			_expect(_generator.get_generated_block_id(x, y, z) == _generator._id_bedrock, "Bedrock changed.")
		if layout["water_index"][index] >= 0: continue
		var y: int = _generator.get_surface_y(x, z)
		_expect(_generator.get_visible_surface_block_id(x, z) == _generator.get_generated_block_id(x, y, z), "Visible surface does not match terrain blocks.")
		_expect(_blocks.is_solid(_generator.get_generated_block_id(x, y, z)), "Dry surface is not solid.")
		_expect(_generator.get_generated_block_id(x, y + 1, z) == _blocks.AIR_ID, "Dry terrain has unexpected blocks above its surface.")
		var rank := int(layout["ranks"][index])
		if rank < 4 or rank_seen.has(rank): continue
		rank_seen[rank] = true
		# Concealed overview strata remain the authored shelf rock, even where
		# detail generation may place an ore/gem inside the mountain.
		var key := "base:terrain:rock:rock%02d" % (10 - rank)
		_expect(_generator.get_overview_strata_block_id(x, y, z) == _blocks.get_id(StringName(key)), "Mountain shelf strata changed.")
	_expect(rank_seen.size() == 6, "Not all six mountain materials are present.")


func _check_rejections() -> void:
	var heights: PackedInt32Array = _generator.heightmap.duplicate()
	var peak := -1
	for i in range(1024):
		if _generator._macro_layout["ranks"][i] == 9:
			peak = ((i / 32) * 32 + 16) * 1024 + (i % 32) * 32 + 16
			break
	if peak >= 0:
		heights[peak] = 114
		var check := Validator.inspect_columns(_generator._macro_layout, _generator._layout_profile,
			heights, _generator.domain_map, _generator.waterline_map)
		_expect(not check["errors"].is_empty(), "Final validator missed a one-block summit defect.")


func _expect(condition: bool, message: String) -> void:
	if not condition and message not in _failures: _failures.append(message)
