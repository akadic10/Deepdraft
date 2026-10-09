extends SceneTree

const SEEDS := [7, 1234, 65535, 20261007, 3381051336, 4294967295, 314159265, 2147483647]
var _failures: Array[String] = []
var _generator: Node
var _blocks: Node
var _interior: Node
var _world: Node


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if not OS.get_environment("APPDATA").replace("\\", "/").contains("/tmp/world_layout_review/"):
		printerr("Use isolated APPDATA below tmp/world_layout_review.")
		quit(2)
		return
	_generator = root.get_node("WorldGenerator")
	_blocks = root.get_node("BlockRegistry")
	_interior = root.get_node("InteriorTracker")
	_world = root.get_node("WorldData")
	root.get_node("SaveManager").set_process(false)
	root.get_node("WorldClock").set_paused(true)
	var report: Array = []
	for world_seed: int in SEEDS:
		_world.clear_world()
		_interior.clear_runtime_state()
		root.get_node("NavGrid").clear_runtime_state()
		_generator._reset_generation_state()
		_generator.world_seed = world_seed
		_generator._cache_block_ids()
		_generator._layout_profile = _generator.load_macro_layout_profile()
		_generator._build_noise_instances()
		_generator._build_seeded_maps()
		_generator._apply_edge_detail()
		var heights_before: PackedInt32Array = _generator.heightmap.duplicate()
		var water_before: PackedInt32Array = _generator.waterline_map.duplicate()
		_generator._build_cave_maps()
		_generator._maps_ready = true
		_expect(heights_before == _generator.heightmap and water_before == _generator.waterline_map, "Caves changed terrain or water maps.")
		var catalog: Array = _generator.get_cave_catalog()
		_expect(catalog.size() == 8, "Expected eight cave systems in test seed %d." % world_seed)
		var summary: Array = []
		for cave: Dictionary in catalog:
			_check_cave(cave)
			var item := cave.duplicate()
			item.erase("columns")
			summary.append(item)
		var fingerprint: String = var_to_bytes(_generator._cave_layout).hex_encode().sha256_text()
		_generator._build_cave_maps()
		_expect(fingerprint == var_to_bytes(_generator._cave_layout).hex_encode().sha256_text(), "Cave generation is not deterministic.")
		if not catalog.is_empty(): _check_discovery(catalog[0])
		report.append({"seed": world_seed, "caves": summary, "sha256": fingerprint})
		print("CaveGenerationTest: seed %d, %d caves checked." % [world_seed, catalog.size()])
		await process_frame
	var file := FileAccess.open("res://tmp/world_layout_review/caves_report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed": _failures.is_empty(), "failures": _failures, "seeds": report}, "\t"))
	for failure in _failures: printerr(failure)
	print("CaveGenerationTest: %s" % ("PASS" if _failures.is_empty() else "FAIL"))
	quit(0 if _failures.is_empty() else 1)


func _check_cave(cave: Dictionary) -> void:
	var floor_y := int(cave["floor_y"])
	var columns: Dictionary = {}
	var volume := 0
	for index: int in cave["columns"]: columns[index] = true
	var connected: Dictionary = {}
	var queue: Array[int] = [int(cave["columns"][0])]
	connected[queue[0]] = true
	var cursor := 0
	while cursor < queue.size():
		var index := queue[cursor]
		cursor += 1
		for offset in [-1024, 1024, -1, 1]:
			if columns.has(index + offset) and not connected.has(index + offset):
				connected[index + offset] = true
				queue.append(index + offset)
	_expect(connected.size() == columns.size(), "Cave floor has disconnected pockets.")
	for index: int in cave["columns"]:
		var x := index / 1024
		var z := index % 1024
		var span: Vector3i = _generator._cave_layout["columns"][index]
		_expect(span.y - floor_y >= 4 and floor_y >= 16, "Cave lost headroom or foundation protection.")
		_expect(root.get_node("NavGrid").is_walkable(Vector3i(x, floor_y, z)), "Cave floor is not walkable.")
		for y in range(floor_y + 1, span.y + 1):
			_expect(_generator.get_generated_block_id(x, y, z) == _blocks.AIR_ID, "Cave span contains solid blocks.")
			_expect(_blocks.is_solid(_generator.get_overview_strata_block_id(x, y, z)), "Undiscovered cave leaks through strata lookup.")
			volume += 1
		_expect(_blocks.is_solid(_generator.get_generated_block_id(x, span.y + 1, z)), "Missing cave roof.")
		# Every side has a rock shell and water buffer, including diagonal cliffs.
		for dx in [-6, 0, 6]:
			for dz in [-6, 0, 6]:
				_expect(_generator.get_surface_y(x + dx, z + dz) >= span.y + 6, "Cave breaches terrain shell.")
		for dx in range(-8, 9):
			for dz in range(-8, 9):
				_expect(_generator.get_waterline(x + dx, z + dz) < 0, "Cave touches lake/tarn buffer.")
	_expect(volume == cave["air_blocks"], "Cave catalog volume differs from real blocks.")
	# At least two chambers and substantial walkable area are the useful-space reward.
	_expect(cave["rooms"] >= 2 and columns.size() >= 150, "Cave has insufficient usable space.")


func _check_discovery(cave: Dictionary) -> void:
	var renderer: Node = load("res://scripts/systems/WorldRenderer.gd").new()
	_interior.caves_discovered.connect(renderer.add_discovered_cave_blocks)
	var mining: Node = load("res://scripts/systems/MiningDesignationController.gd").new()
	mining._renderer = renderer
	var cells: Array[Vector3i] = _generator.get_cave_air_cells(cave["id"])
	var center: Vector3i = cave["center"]
	var air := center + Vector3i.UP
	renderer.slice_y = center.y + 3
	_expect(_blocks.is_solid(mining._designation_block_id_at(air)), "Hidden cave is revealed by mining picker.")
	var hidden: Dictionary = renderer._overview_visible_surface_after_cut(center.x, center.z)
	_expect(hidden.get("wy", -1) == center.y + 3, "Hidden cave is exposed by slicing.")
	var plan: Array[Vector3i] = [air]
	renderer.add_visual_cut_blocks(plan)
	renderer.set_debug_cave_blocks(cells)
	renderer._ovt_cut = renderer._visual_cut_blocks.duplicate()
	renderer._ovt_mined = renderer._debug_cave_blocks.duplicate()
	var preview: Dictionary = renderer._overview_visible_surface_after_cut(center.x, center.z)
	_expect(preview.get("wy", -1) == center.y, "Developer preview does not show the cave floor.")
	_expect(_interior.discovered_cave_count() == 0 and mining._mined_blocks.is_empty(), "Developer preview mutated discovery/mining.")
	renderer.clear_debug_cave_blocks()
	_expect(renderer._visual_cut_blocks.size() == 1 and renderer._visual_cut_blocks.has(air), "Preview cleanup erased a mining plan.")
	renderer.remove_visual_cut_blocks(plan)
	_expect(renderer._visual_cut_blocks.is_empty(), "Developer preview left hidden cave holes.")
	var index := int(cave["columns"][0]) # Minimum x ensures the west neighbour is solid.
	var wall := Vector3i(index / 1024 - 1, center.y + 1, index % 1024)
	_expect(_blocks.is_solid(_generator.get_generated_block_id(wall.x, wall.y, wall.z)), "Discovery fixture is not rock.")
	mining._mine_block_world(wall)
	_expect(_interior.discovered_cave_count() == 1, "Mining a cave wall failed to discover exactly one system.")
	_expect(renderer._discovered_cave_blocks.size() == cells.size(), "Discovery did not reveal the whole connected chamber.")
	_expect(mining._designation_block_id_at(air) == _blocks.AIR_ID, "Discovered cave still picks as solid.")
	_expect(mining._mined_blocks.size() == 1, "Natural cave air was persisted as mined blocks.")
	renderer.set_debug_cave_blocks(cells)
	renderer.clear_debug_cave_blocks()
	_expect(renderer._visual_cut_blocks.has(air), "Closing preview hid an actually discovered cave.")
	var breach: Array[Vector3i] = [wall + Vector3i.UP, wall + Vector3i.UP * 2]
	mining._mine_blocks_world(breach)
	var start := wall - Vector3i.UP
	_expect(not root.get_node("NavGrid").find_path(start, center, 12000).is_empty(), "Dwarf cannot walk from breach into cave.")
	var saved: Dictionary = mining.serialize_state()
	_interior.caves_discovered.disconnect(renderer.add_discovered_cave_blocks)
	mining.free()
	renderer.free()
	_world.clear_world()
	_interior.clear_runtime_state()
	mining = load("res://scripts/systems/MiningDesignationController.gd").new()
	mining.restore_state(saved)
	_expect(_interior.discovered_cave_count() == 1, "Discovery was not reconstructed from saved mining.")
	mining.free()


func _expect(condition: bool, message: String) -> void:
	if not condition and message not in _failures: _failures.append(message)
