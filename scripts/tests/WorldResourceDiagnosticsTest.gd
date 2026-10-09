extends SceneTree

## Exact top-column census plus deterministic, spatially sampled ore checks.
## --baseline records the pre-fix behavior without expecting corrected results.
const SEEDS := [7, 1234, 65535, 20261007]
const CATEGORIES := ["grass", "dirt", "rock", "water", "other"]
const DOMAINS := ["lowland", "valley", "mountain"]
const METALS := ["gold", "silver", "iron", "copper", "tin", "coal"]
var _generator: Node
var _blocks: Node
var _world: Node
var _failures: Array[String] = []
var _category_cache: Dictionary = {}
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
	var report: Array = []
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
		_generator._validate_finished_layout()
		_expect(_generator._layout_validation.get("errors", ["missing"]).is_empty(), "Layout validation failed.")
		_generator._maps_ready = true
		var surface := _check_surface()
		var resources := _check_resources()
		if not _baseline:
			_check_metal_windows()
			_generator._build_generation_metrics()
			_check_overlay()
		report.append({"seed": world_seed, "surface": surface, "resources": resources,
			"map_sha256": (var_to_bytes(_generator.heightmap) + var_to_bytes(_generator.waterline_map)).hex_encode().sha256_text(),
			"elapsed_ms": Time.get_ticks_msec() - started})
		print("WorldResourceDiagnosticsTest: seed %d; tin overlap %d; copper overlap %d; %d ms" % [
			world_seed, resources["overlap"]["tin"], resources["overlap"]["copper"], Time.get_ticks_msec() - started])
		await process_frame
	var suffix := "baseline_current" if _baseline else "current"
	var file := FileAccess.open("res://tmp/world_layout_review/resource_diagnostics_%s.json" % suffix, FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed": _failures.is_empty(), "failures": _failures,
		"sample": "x/z = 4,12,...,1020; every Y4 through the solid column top", "seeds": report}, "\t"))
	file.close()
	for failure in _failures: printerr(failure)
	print("WorldResourceDiagnosticsTest: %s (%s, %d seeds)" % ["PASS" if _failures.is_empty() else "FAIL", suffix, report.size()])
	quit(0 if _failures.is_empty() else 1)


func _bucket() -> Dictionary:
	return {"grass": 0, "dirt": 0, "rock": 0, "water": 0, "other": 0, "total": 0}


func _check_surface() -> Dictionary:
	var actual := _bucket()
	var by_domain := {"lowland": _bucket(), "valley": _bucket(), "mountain": _bucket()}
	for x in range(1024):
		for z in range(1024):
			var block_id: int = _generator.get_visible_surface_block_id(x, z)
			if not _category_cache.has(block_id):
				var kind := String(_blocks.get_def(_blocks.get_key(block_id)).get("kind", "other"))
				_category_cache[block_id] = kind if kind in CATEGORIES else "other"
			var category: String = _category_cache[block_id]
			actual[category] += 1
			actual["total"] += 1
			var bucket: Dictionary = by_domain[DOMAINS[_generator.domain_map[x * 1024 + z]]]
			bucket[category] += 1
			bucket["total"] += 1
	var measured: Dictionary = _generator._compute_surface_metrics()
	if not _baseline:
		_compare_bucket(actual, measured, "world")
		for domain in DOMAINS: _compare_bucket(by_domain[domain], measured["by_domain"][domain], domain)
	return {"actual": actual, "actual_by_domain": by_domain, "reported": measured}


func _compare_bucket(actual: Dictionary, reported: Dictionary, label: String) -> void:
	_expect(reported.get("total", -1) == actual["total"], "Surface total differs: " + label)
	for category in CATEGORIES:
		_expect(actual[category] == reported.get(category, -1), "Surface count differs: %s/%s" % [label, category])
		var expected_pct := float(actual[category]) * 100.0 / maxi(actual["total"], 1)
		_expect(is_equal_approx(expected_pct, reported.get(category + "_pct", -1.0)), "Surface percent differs: %s/%s" % [label, category])


func _check_resources() -> Dictionary:
	var ids: Dictionary = {}
	var counts: Dictionary = {}
	var by_y: Dictionary = {}
	var overlap := {"copper": 0, "tin": 0}
	var examples: Dictionary = {}
	var sampled := PackedInt32Array()
	for metal in METALS:
		ids[_blocks.get_id(StringName("base:terrain:ore:" + metal))] = metal
		counts[metal] = 0
		by_y[metal] = {}
	for x in range(4, 1024, 8):
		for z in range(4, 1024, 8):
			var top: int = _generator.get_surface_y(x, z)
			for y in range(4, top + 1):
				var block_id: int = _generator.get_generated_block_id(x, y, z)
				sampled.append(block_id)
				if not ids.has(block_id): continue
				var metal: String = ids[block_id]
				counts[metal] += 1
				by_y[metal][y] = int(by_y[metal].get(y, 0)) + 1
				_expect(y < top and x >= 8 and z >= 8 and x < 1016 and z < 1016, "Ore reached surface/perimeter.")
				if y >= 55 and y <= 88 and metal in overlap:
					overlap[metal] += 1
					if not examples.has(metal): examples[metal] = Vector3i(x, y, z)
	if not _baseline:
		_expect(overlap["tin"] > 0 and overlap["copper"] > 0, "Copper or tin absent from sampled shared depths.")
		# Rebuilding the seeded noise must reproduce the chosen blocks; streaming
		# must store the same ore while the slice overview continues to conceal it.
		_generator._build_noise_instances()
		for metal: String in examples:
			var cell: Vector3i = examples[metal]
			var expected: int = _blocks.get_id(StringName("base:terrain:ore:" + metal))
			_expect(_generator.get_generated_block_id(cell.x, cell.y, cell.z) == expected, "Seeded ore changed on noise rebuild.")
			_generator._fill_chunk_column(cell.x / 16, cell.z / 16)
			_expect(_world.get_block(cell.x, cell.y, cell.z) == expected, "Streamed ore differs from generated block.")
			_expect(_generator.get_overview_strata_block_id(cell.x, cell.y, cell.z) != expected, "Slice overview exposed an ore vein.")
	return {"counts": counts, "by_y": by_y, "overlap": overlap, "sampled_blocks": sampled.size(),
		"block_sha256": sampled.to_byte_array().hex_encode().sha256_text()}


func _check_metal_windows() -> void:
	var windows: Array[Dictionary] = _generator._metal_windows
	var offsets := {}
	_expect(windows.size() == _generator._metal_noise.size(), "Missing independent metal field.")
	for window: Dictionary in windows:
		var settings: Dictionary = window["noise_field"]
		_expect(not offsets.has(settings["seed_offset"]), "Metal fields share a seed offset.")
		offsets[settings["seed_offset"]] = true
		_expect(window["threshold"] > 0.0 and window["threshold"] < 1.0, "Metal threshold out of range.")
		_expect(window["min_y"] > 3 and window["max_y"] >= window["min_y"], "Invalid metal depth band.")


func _check_overlay() -> void:
	var overlay: Node = load("res://scripts/ui/DebugLoadingOverlay.gd").new()
	root.add_child(overlay)
	var label_text: String = overlay._label.text
	_expect("top surface" in label_text and "summit" in label_text and "detail" in label_text, "Overlay lacks current diagnostics.")
	_expect("settlement candidates" not in label_text and "SE foothill" not in label_text and "plateau" not in label_text, "Overlay retains obsolete layout fields.")
	overlay.free()


func _expect(condition: bool, message: String) -> void:
	if not condition and message not in _failures: _failures.append(message)
