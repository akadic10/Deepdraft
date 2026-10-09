extends SceneTree

## Actual-block resource audit, including caves. Samples are not world totals.
## --baseline records the current configuration, including shadowed intervals.
const SEEDS := [7, 1234, 65535, 20261007, 3381051336, 4294967295, 314159265, 2147483647]
const DIRECTIONS := [Vector3i.LEFT, Vector3i.RIGHT, Vector3i.UP, Vector3i.DOWN, Vector3i.FORWARD, Vector3i.BACK]
var _generator: Node
var _blocks: Node
var _world: Node
var _names: Dictionary = {}
var _failures: Array[String] = []
var _baseline := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if not OS.get_environment("APPDATA").replace("\\", "/").contains("/tmp/world_layout_review/"):
		printerr("Use isolated APPDATA below tmp/world_layout_review.")
		quit(2)
		return
	_baseline = "--baseline" in OS.get_cmdline_user_args()
	_generator = root.get_node("WorldGenerator")
	_blocks = root.get_node("BlockRegistry")
	_world = root.get_node("WorldData")
	root.get_node("SaveManager").set_process(false)
	root.get_node("WorldClock").set_paused(true)
	if "--windows-only" in OS.get_cmdline_user_args():
		_generator._cache_block_ids()
		_generator._build_noise_instances()
		_check_windows()
		for failure in _failures: printerr(failure)
		print("WorldResourceBalanceTest windows: %s" % ("PASS" if _failures.is_empty() else "FAIL"))
		quit(0 if _failures.is_empty() else 1)
		return
	var report: Array = []
	var shadowed: Array = []
	for world_seed: int in SEEDS:
		var started := Time.get_ticks_msec()
		_world.clear_world()
		_generator._reset_generation_state()
		_generator.world_seed = world_seed
		_generator._cache_block_ids()
		_generator._layout_profile = _generator.load_macro_layout_profile()
		_generator._build_noise_instances()
		_generator._build_seeded_maps()
		_generator._apply_edge_detail()
		_generator._build_cave_maps()
		_generator._maps_ready = true
		for window: Dictionary in _generator._resource_focus_windows:
			_names[window["id"]] = String(window["key"])
		if report.is_empty(): shadowed = _check_windows()
		var sample := _sample_world()
		var caves := _audit_caves()
		var shape := _sample_vein_shape()
		var deep := _deep_gem_census() if "--deep-census" in OS.get_cmdline_user_args() else {}
		report.append({"seed": world_seed, "sample": sample, "caves": caves, "vein_box": shape,
			"deep_gem_census": deep,
			"geography_sha256": (var_to_bytes(_generator.heightmap) + var_to_bytes(_generator.waterline_map)).hex_encode().sha256_text(),
			"elapsed_ms": Time.get_ticks_msec() - started})
		print("WorldResourceBalanceTest: seed %d; diamond %d; emerald %d; %d ms" % [world_seed,
			sample["counts"]["base:terrain:gem:diamond"], sample["counts"]["base:terrain:gem:emerald"], Time.get_ticks_msec() - started])
		await process_frame
	# Preserve doc 69's historical before/after evidence when checking new rules.
	var suffix := "baseline_current" if _baseline else "current"
	var file := FileAccess.open("res://tmp/world_layout_review/resource_balance_%s.json" % suffix, FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed": _failures.is_empty(), "failures": _failures,
		"sample_method": "x/z 4,12,...,1020; every Y4 through solid terrain top, including generated cave air",
		"shadowed_windows": shadowed, "windows": _generator._resource_focus_windows, "seeds": report}, "\t"))
	file.close()
	for failure in _failures: printerr(failure)
	print("WorldResourceBalanceTest: %s (%s)" % ["PASS" if _failures.is_empty() else "FAIL", suffix])
	quit(0 if _failures.is_empty() else 1)


func _empty_counts() -> Dictionary:
	var counts := {}
	for key: String in _names.values(): counts[key] = 0
	return counts


func _check_windows() -> Array:
	var shadowed: Array = []
	_check_metal_fields()
	for windows: Array[Dictionary] in [_generator._gem_windows, _generator._soil_windows]:
		for window: Dictionary in windows:
			for y in range(int(window["min_y"]), int(window["max_y"]) + 1):
				var upper := 1.0
				for earlier: Dictionary in windows:
					if earlier["id"] == window["id"]: break
					if y >= earlier["min_y"] and y <= earlier["max_y"]: upper = minf(upper, earlier["threshold"])
				var threshold := float(window["threshold"])
				if upper <= threshold:
					shadowed.append({"key": window["key"], "y": y, "threshold": threshold, "upper": upper})
					if not _baseline: _expect(false, "Unreachable resource: %s at Y%d" % [window["key"], y])
				else:
					_expect(_generator._pick_resource_from_windows(windows, y, (upper + threshold) * 0.5) == window["id"], "Reachable interval selects wrong resource.")
			# Strict noise boundary and inclusive depth bounds, independent of a
			# particular seed hitting these rare noise values.
			var one: Array[Dictionary] = [window]
			var low := int(window["min_y"])
			var high := int(window["max_y"])
			var threshold := float(window["threshold"])
			_expect(_generator._pick_resource_from_windows(one, low, threshold) == -1, "Threshold must be strictly exceeded.")
			_expect(_generator._pick_resource_from_windows(one, low, threshold + 0.00001) == window["id"], "Resource missing at minimum depth.")
			_expect(_generator._pick_resource_from_windows(one, high, threshold + 0.00001) == window["id"], "Resource missing at maximum depth.")
			_expect(_generator._pick_resource_from_windows(one, low - 1, 1.0) == -1 and _generator._pick_resource_from_windows(one, high + 1, 1.0) == -1, "Resource escaped depth bounds.")
	return shadowed


func _check_metal_fields() -> void:
	var saved_windows: Array[Dictionary] = _generator._metal_windows
	var saved_noise: Array[FastNoiseLite] = _generator._metal_noise
	_expect(saved_windows.size() == 6 and saved_noise.size() == 6, "Missing metal field.")
	var offsets := {}
	for i in range(saved_windows.size()):
		var window: Dictionary = saved_windows[i].duplicate(true)
		var settings: Dictionary = window["noise_field"]
		_expect(not offsets.has(settings["seed_offset"]), "Metal fields reuse a seed offset.")
		offsets[settings["seed_offset"]] = true
		_expect(window["threshold"] > 0.0 and window["threshold"] < 1.0, "Metal cutoff out of range.")
		_expect(is_equal_approx(saved_noise[i].frequency, settings["frequency"]), "Metal frequency differs from data.")
		var one: Array[Dictionary] = [window]
		var one_noise: Array[FastNoiseLite] = [saved_noise[i]]
		_generator._metal_windows = one
		_generator._metal_noise = one_noise
		# Exercise the actual production selector at every inclusive depth,
		# including strict equality, independently of rare natural noise maxima.
		for y in range(int(window["min_y"]), int(window["max_y"]) + 1):
			var value := (saved_noise[i].get_noise_3d(125, y, 257) + 1.0) * 0.5
			window["threshold"] = value
			_expect(_generator._pick_metal_from_fields(125, y, 257) == -1, "Metal threshold must be strictly exceeded.")
			window["threshold"] = value - 0.00001
			_expect(_generator._pick_metal_from_fields(125, y, 257) == window["id"], "Independent metal unreachable at configured depth.")
		window["threshold"] = -1.0
		_expect(_generator._pick_metal_from_fields(125, int(window["min_y"]) - 1, 257) == -1, "Metal below depth band.")
		_expect(_generator._pick_metal_from_fields(125, int(window["max_y"]) + 1, 257) == -1, "Metal above depth band.")
	# Both resources qualify: first wins. If its own field fails, the second can
	# qualify even with a higher cutoff, unlike the old shared-channel selection.
	var overlap: Array[Dictionary] = [saved_windows[0].duplicate(true), saved_windows[1].duplicate(true)]
	var pair: Array[FastNoiseLite] = [saved_noise[0], saved_noise[1]]
	_generator._metal_windows = overlap
	_generator._metal_noise = pair
	for window: Dictionary in overlap: window["threshold"] = -1.0
	_expect(_generator._pick_metal_from_fields(125, 24, 257) == overlap[0]["id"], "Metal overlap lost priority.")
	var checked_independence := false
	for x in range(128):
		var first := (pair[0].get_noise_3d(x, 24, 257) + 1.0) * 0.5
		var second := (pair[1].get_noise_3d(x, 24, 257) + 1.0) * 0.5
		if second <= first + 0.001: continue
		overlap[0]["threshold"] = first
		overlap[1]["threshold"] = second - 0.00001
		_expect(_generator._pick_metal_from_fields(x, 24, 257) == overlap[1]["id"], "Later metal did not use its own field.")
		checked_independence = true
		break
	_expect(checked_independence, "No independent metal field fixture found.")
	_generator._metal_windows = saved_windows
	_generator._metal_noise = saved_noise


func _sample_world() -> Dictionary:
	var counts := _empty_counts()
	var by_y: Dictionary = {}
	var eligible_by_y: Dictionary = {}
	var examples: Dictionary = {}
	var blocks := PackedInt32Array()
	var air := 0
	var gem_max_by_y := {}
	for x in range(4, 1024, 8):
		for z in range(4, 1024, 8):
			var top: int = _generator.get_surface_y(x, z)
			for y in range(4, top + 1):
				var id: int = _generator.get_generated_block_id(x, y, z)
				blocks.append(id)
				if id == _blocks.AIR_ID:
					air += 1
					continue
				if y < top and not _generator._is_resource_perimeter_column(x, z) and not _generator._is_natural_exposed_wall(x, y, z):
					var strata: int = _generator.get_overview_strata_block_id(x, y, z)
					if _generator._is_resource_replaceable_rock(strata):
						eligible_by_y[y] = int(eligible_by_y.get(y, 0)) + 1
						if y <= 22:
							var noise: float = (_generator.noise_gem.get_noise_3d(x, y, z) + 1.0) * 0.5
							gem_max_by_y[y] = maxf(gem_max_by_y.get(y, 0.0), noise)
				if not _names.has(id): continue
				var key: String = _names[id]
				counts[key] += 1
				if not by_y.has(y): by_y[y] = _empty_counts()
				by_y[y][key] += 1
				if not examples.has(key): examples[key] = Vector3i(x, y, z)
				_expect(y > 3 and y < top and not _generator._is_resource_perimeter_column(x, z) and not _generator._is_natural_exposed_wall(x, y, z), "Resource breached protected surface/foundation edge.")
	# Rebuild noise and check actual generated, streamed, and concealed identities.
	_generator._build_noise_instances()
	for key: String in examples:
		var cell: Vector3i = examples[key]
		var expected: int = _blocks.get_id(StringName(key))
		_expect(_generator.get_generated_block_id(cell.x, cell.y, cell.z) == expected, "Resource changed after seeded noise rebuild.")
		_generator._fill_chunk_column(cell.x / 16, cell.z / 16)
		_expect(_world.get_block(cell.x, cell.y, cell.z) == expected, "Streamed resource differs from generated block.")
		_expect(_generator.get_overview_strata_block_id(cell.x, cell.y, cell.z) != expected, "Slice strata exposed a resource.")
	return {"counts": counts, "by_y": by_y, "eligible_by_y": eligible_by_y, "gem_max_by_y": gem_max_by_y,
		"sampled_blocks": blocks.size(), "cave_air": air, "examples": examples,
		"block_sha256": blocks.to_byte_array().hex_encode().sha256_text()}


func _audit_caves() -> Dictionary:
	var layout: Dictionary = _generator._cave_layout
	var removed := _empty_counts()
	var air_cells: Array[Vector3i] = []
	var boundary := {}
	var volumes: Array = []
	for cave: Dictionary in layout["systems"]:
		var cells: Array[Vector3i] = _generator.get_cave_air_cells(cave["id"])
		air_cells.append_array(cells)
		var own_boundary := {}
		for cell: Vector3i in cells:
			for direction: Vector3i in DIRECTIONS:
				var next := cell + direction
				if _generator.get_cave_id(next) < 0: own_boundary[next] = true
		var exposed := _empty_counts()
		for cell: Vector3i in own_boundary:
			var id: int = _generator.get_generated_block_id(cell.x, cell.y, cell.z)
			if _names.has(id): exposed[_names[id]] += 1
		boundary.merge(own_boundary)
		volumes.append({"id": cave["id"], "floor_y": cave["floor_y"], "floor_area": cave["floor_area"],
			"air_blocks": cave["air_blocks"], "boundary_blocks": own_boundary.size(), "exposed": exposed})
	# Counterfactual queries only: do not carve/restore WorldData or edit profiles.
	_generator._cave_layout = {"systems": [], "columns": {}, "soil": {}}
	for cell: Vector3i in air_cells:
		var id: int = _generator.get_generated_block_id(cell.x, cell.y, cell.z)
		if _names.has(id): removed[_names[id]] += 1
	_generator._cave_layout = layout
	return {"removed_resources_exact": removed, "air_blocks_exact": air_cells.size(), "systems": volumes}


func _sample_vein_shape() -> Dictionary:
	# One contiguous 64^3 box under the first Y115 macro-cell center. Components
	# touching its edge are clipped samples, never presented as complete veins.
	var center := Vector2i(-1, -1)
	for x in range(48, 992, 32):
		for z in range(48, 992, 32):
			if _generator.get_surface_y(x, z) == 115:
				center = Vector2i(x, z)
				break
		if center.x >= 0: break
	_expect(center.x >= 0, "Missing summit for spatial resource sample.")
	var origin := Vector3i(center.x - 32, 12, center.y - 32)
	var remaining: Dictionary = {}
	var id_counts := _empty_counts()
	for dx in range(64):
		for dz in range(64):
			for dy in range(64):
				var cell := origin + Vector3i(dx, dy, dz)
				var id: int = _generator.get_generated_block_id(cell.x, cell.y, cell.z)
				if _names.has(id) and ":ore:" in _names[id]:
					remaining[cell] = id
					id_counts[_names[id]] += 1
	var components: Dictionary = {}
	while not remaining.is_empty():
		var start: Vector3i = remaining.keys()[0]
		var id: int = remaining[start]
		var key: String = _names[id]
		var queue: Array[Vector3i] = [start]
		remaining.erase(start)
		var cursor := 0
		var lower := start
		var upper := start
		var clipped := false
		while cursor < queue.size():
			var cell := queue[cursor]
			cursor += 1
			lower = lower.min(cell)
			upper = upper.max(cell)
			var local := cell - origin
			if local.x == 0 or local.y == 0 or local.z == 0 or local.x == 63 or local.y == 63 or local.z == 63: clipped = true
			for direction: Vector3i in DIRECTIONS:
				var next := cell + direction
				if remaining.get(next, -1) != id: continue
				remaining.erase(next)
				queue.append(next)
		if not components.has(key): components[key] = []
		components[key].append({"size": queue.size(), "extent": [upper.x - lower.x + 1, upper.y - lower.y + 1, upper.z - lower.z + 1], "clipped": clipped})
	return {"origin": [origin.x, origin.y, origin.z], "size": 64, "counts": id_counts, "components": components}


func _deep_gem_census() -> Dictionary:
	# Exhaustive Y4-22 scan in the non-suppressed world interior. Noise is a cheap
	# candidate filter; counts come from the actual generated block getter. Sparse
	# 8-block sampling is insufficient to infer absence of tiny, rare deposits.
	var keys := ["diamond", "emerald", "sapphire", "ruby"]
	var counts := {"diamond": 0, "emerald": 0, "sapphire": 0, "ruby": 0}
	var before: Dictionary = counts.duplicate()
	var overlap := {"diamond": 0, "emerald": 0}
	var by_y := {}
	var examples := {}
	var old_windows: Array[Dictionary] = _generator._gem_windows.duplicate(true)
	for window: Dictionary in old_windows:
		if String(window["key"]) == "base:terrain:gem:diamond": window["threshold"] = 0.90
	var changed := 0
	for x in range(8, 1016):
		for z in range(8, 1016):
			var top: int = _generator.get_surface_y(x, z)
			for y in range(4, mini(22, top - 1) + 1):
				var noise: float = (_generator.noise_gem.get_noise_3d(x, y, z) + 1.0) * 0.5
				if noise <= 0.88: continue
				var cell := Vector3i(x, y, z)
				if _generator.get_cave_id(cell) >= 0 or _generator._is_natural_exposed_wall(x, y, z): continue
				var strata: int = _generator.get_overview_strata_block_id(x, y, z)
				if not _generator._is_resource_replaceable_rock(strata): continue
				var old_id: int = _generator._pick_resource_from_windows(old_windows, y, noise)
				var id: int = _generator.get_generated_block_id(x, y, z)
				var old_name := String(_names.get(old_id, "")).get_slice(":", 3)
				var name := String(_names.get(id, "")).get_slice(":", 3)
				if old_name in keys: before[old_name] += 1
				if name in keys:
					counts[name] += 1
					if not by_y.has(y): by_y[y] = {"diamond": 0, "emerald": 0, "sapphire": 0, "ruby": 0}
					by_y[y][name] += 1
					if not examples.has(name): examples[name] = cell
					if y >= 5 and y <= 12 and name in overlap: overlap[name] += 1
				if old_name == "diamond" and id != old_id: changed += 1
	for name: String in keys:
		_expect(counts[name] > 0, "Deep gem absent from full census: %s seed %d" % [name, _generator.world_seed])
	_expect(overlap["emerald"] > 0, "Emerald is absent from the corrected Y5-12 interval.")
	# The first actual example of every rare gem must stream and stay concealed.
	for name: String in examples:
		var cell: Vector3i = examples[name]
		var expected: int = _blocks.get_id(StringName("base:terrain:gem:" + name))
		_generator._fill_chunk_column(cell.x / 16, cell.z / 16)
		_expect(_world.get_block(cell.x, cell.y, cell.z) == expected, "Streamed deep gem differs from census.")
		_expect(_generator.get_overview_strata_block_id(cell.x, cell.y, cell.z) != expected, "Deep gem leaked through slice strata.")
	print("WorldResourceBalanceTest: deep census seed %d: %s" % [_generator.world_seed, str(counts)])
	return {"range": "all x/z 8..1015 and Y4..22 below surface; perimeter is suppressed", "counts": counts,
		"before_diamond_090": before, "by_y": by_y, "overlap_y5_12": overlap, "changed_diamonds": changed, "examples": examples}


func _expect(condition: bool, message: String) -> void:
	if not condition and message not in _failures: _failures.append(message)
