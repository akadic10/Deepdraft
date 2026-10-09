extends "res://scripts/tests/WorldResourceBalanceTest.gd"

## Integration plus an unfitted eight-seed abundance check. Counterfactual old
## counts come from a frozen pre-change profile, never a live fallback generator.
const NEW_SEEDS := [0, 42, 8675309, 20261008, 305419896, 987654321, 2718281828, 4000000000]
const OUT := "res://tmp/ore_field_integration/"
var _old_windows: Array[Dictionary] = []
var _old_noise: FastNoiseLite
var _old_resources: Dictionary
var _sample_comparison: Dictionary


func _run() -> void:
	if not OS.get_environment("APPDATA").replace("\\", "/").contains("/tmp/ore_field_integration/"):
		printerr("Use isolated APPDATA under tmp/ore_field_integration.")
		quit(2)
		return
	_generator = root.get_node("WorldGenerator")
	_blocks = root.get_node("BlockRegistry")
	_world = root.get_node("WorldData")
	root.get_node("SaveManager").set_process(false)
	root.get_node("WorldClock").set_paused(true)
	_old_resources = JSON.parse_string(FileAccess.get_file_as_string(OUT + "resources_before.json"))
	var historical: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tmp/world_layout_review/resource_balance_after.json"))
	var old_by_seed := {}
	for row: Dictionary in historical["seeds"]: old_by_seed[int(row["seed"])] = row
	var reports := []
	for seed_value: int in SEEDS + NEW_SEEDS:
		var started := Time.get_ticks_msec()
		_world.clear_world()
		_generator._reset_generation_state()
		_generator.world_seed = seed_value
		_generator._cache_block_ids()
		_generator._layout_profile = _generator.load_macro_layout_profile()
		_generator._build_noise_instances()
		_generator._build_seeded_maps()
		_generator._apply_edge_detail()
		_generator._build_cave_maps()
		_generator._maps_ready = true
		for window: Dictionary in _generator._resource_focus_windows:
			_names[window["id"]] = String(window["key"])
		if reports.is_empty():
			_check_windows()
			_check_unchanged_rules()
		_old_windows = _generator._metal_windows.duplicate(true)
		for window: Dictionary in _old_windows:
			window["threshold"] = _old_resources[String(window["key"])]["noise_threshold"]
		_old_noise = FastNoiseLite.new()
		_old_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_old_noise.seed = seed_value + 1
		_old_noise.frequency = 0.02
		_old_noise.fractal_octaves = 2
		var sample := _sample_world()
		var comparison := _sample_comparison
		var caves := _audit_caves()
		var fingerprint: String = (var_to_bytes(_generator.heightmap) + var_to_bytes(_generator.waterline_map)).hex_encode().sha256_text()
		if old_by_seed.has(seed_value):
			var old: Dictionary = old_by_seed[seed_value]
			_expect(fingerprint == old["geography_sha256"], "Geography changed at seed %d." % seed_value)
			_expect(caves["air_blocks_exact"] == old["caves"]["air_blocks_exact"], "Cave volume changed.")
			for key: String in sample["counts"]:
				if ":gem:" in key:
					_expect(sample["counts"][key] == old["sample"]["counts"][key], "Gem sample changed: " + key)
				if ":ore:" in key:
					_expect(comparison["before"][key] == old["sample"]["counts"][key], "Old ore reference does not reproduce audit: " + key)
		var shape := _sample_vein_shape() if seed_value in SEEDS else {}
		reports.append({"seed": seed_value, "held_out": seed_value in NEW_SEEDS, "sample": sample,
			"comparison": comparison, "caves": caves, "vein_box": shape, "geography_sha256": fingerprint,
			"elapsed_ms": Time.get_ticks_msec() - started})
		print("OreFieldIntegrationTest: seed %d (%s), %d ms." % [seed_value, "held out" if seed_value in NEW_SEEDS else "calibration", Time.get_ticks_msec() - started])
		await process_frame
	var file := FileAccess.open(OUT + "integration.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed": _failures.is_empty(), "failures": _failures,
		"calibration_seeds": SEEDS, "held_out_seeds": NEW_SEEDS, "windows": _generator._resource_focus_windows,
		"seeds": reports}, "\t"))
	for failure in _failures: printerr(failure)
	print("OreFieldIntegrationTest: %s" % ("PASS" if _failures.is_empty() else "FAIL"))
	quit(0 if _failures.is_empty() else 1)


func _check_unchanged_rules() -> void:
	for key: String in _old_resources:
		if key.begins_with("__"): continue
		var before: Dictionary = _old_resources[key].duplicate(true)
		var after: Dictionary = _blocks.get_resource_def(StringName(key)).duplicate(true)
		if ":ore:" in key:
			before.erase("noise_threshold")
			after.erase("noise_threshold")
			after.erase("noise_field")
		_expect(before == after, "Non-ore-shape metadata changed: " + key)


func _sample_world() -> Dictionary:
	# The inherited pass checks actual identities, streaming, rebuild determinism
	# and concealed strata. Compare abundance against the old field on the exact
	# same eligible positions; gems always win before either metal option.
	var sample := super._sample_world()
	var before := _empty_counts()
	var before_by_y := {}
	for x in range(4, 1024, 8):
		for z in range(4, 1024, 8):
			var top: int = _generator.get_surface_y(x, z)
			for y in range(4, top + 1):
				var actual: int = _generator.get_generated_block_id(x, y, z)
				if actual == _blocks.AIR_ID: continue
				if _names.has(actual):
					for window: Dictionary in _generator._resource_focus_windows:
						if window["id"] != actual: continue
						# Authored cave-floor soil is a separate placement, outside
						# the procedural soil window; metals and gems keep theirs.
						if window["channel"] != "soil":
							_expect(y >= window["min_y"] and y <= window["max_y"], "Resource escaped its depth window.")
				if _names.has(actual) and ":gem:" in _names[actual]: continue
				if y >= top or _generator._is_resource_perimeter_column(x, z) or _generator._is_natural_exposed_wall(x, y, z): continue
				if not _generator._is_resource_replaceable_rock(_generator.get_overview_strata_block_id(x, y, z)): continue
				var value := (_old_noise.get_noise_3d(x, y, z) + 1.0) * 0.5
				var old_id: int = _generator._pick_resource_from_windows(_old_windows, y, value)
				if old_id >= 0:
					var key: String = _names[old_id]
					before[key] += 1
					if not before_by_y.has(y): before_by_y[y] = _empty_counts()
					before_by_y[y][key] += 1
	for window: Dictionary in _old_windows:
		_expect(sample["counts"][String(window["key"])] > 0, "Ore missing from seed sample: " + String(window["key"]))
	_sample_comparison = {"before": before, "before_by_y": before_by_y}
	return sample
