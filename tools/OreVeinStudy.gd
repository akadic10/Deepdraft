extends SceneTree

## Offline comparison only. Nothing in the live game imports this tool or its
## profile. This entry point owns its study inputs and generated review files.
const OUT := "res://tmp/ore_vein_review/"
const NAMES := ["gold", "silver", "iron", "copper", "tin", "coal"]
const VARIANTS := ["current", "finer_shared", "separate_metals"]
var _gen: Node
var _blocks: Node
var _profile: Dictionary
var _windows: Array[Dictionary]
var _ids: Dictionary = {}
var _thresholds: Array[float] = []
var _training: Array[Dictionary] = []
var _failures: Array[String] = []
var _baseline_noise: FastNoiseLite


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if not OS.get_environment("APPDATA").replace("\\", "/").contains("/tmp/ore_vein_review/"):
		printerr("Use isolated APPDATA under tmp/ore_vein_review.")
		quit(2)
		return
	_profile = JSON.parse_string(FileAccess.get_file_as_string("res://tools/ore_vein_study/profiles.json"))
	_gen = root.get_node("WorldGenerator")
	_blocks = root.get_node("BlockRegistry")
	root.get_node("SaveManager").set_process(false)
	root.get_node("WorldClock").set_paused(true)
	var rows: Array = []
	for seed_index in range(_profile["seeds"].size()):
		var seed_value := int(_profile["seeds"][seed_index])
		_build_world(seed_value)
		var sample := _sample_world()
		if seed_index < int(_profile["calibration_seed_count"]): _training.append(sample)
		rows.append({"seed": seed_value, "sample": sample["counts"],
			"sampled_cells": sample["sampled_cells"], "eligible_cells": sample["points"].size(),
			"geography_hash": (var_to_bytes(_gen.heightmap) + var_to_bytes(_gen.waterline_map)).hex_encode().sha256_text()})
		_save_points(seed_value, sample["points"])
		print("OreVeinStudy: sampled seed %d." % seed_value)
		await process_frame
	_calibrate()
	_training.clear()
	for row: Dictionary in rows:
		var seed_value := int(row["seed"])
		_build_world(seed_value)
		var fields := _fields(seed_value)
		var points := _read_points(seed_value)
		var separate_counts := [0, 0, 0, 0, 0, 0]
		for point: Vector3 in points:
			var code := _pick_separate(point, fields)
			if code > 0: separate_counts[code - 1] += 1
		row["sample"]["separate_metals"] = separate_counts
		row["box"] = _export_box(seed_value, fields)
		print("OreVeinStudy: exported seed %d; separate counts %s." % [seed_value, str(separate_counts)])
		await process_frame
	var report := {"study_id": _profile["study_id"], "passed": _failures.is_empty(), "failures": _failures,
		"names": NAMES, "variants": VARIANTS, "profile": _profile, "thresholds": _thresholds,
		"calibration_seeds": _profile["seeds"].slice(0, int(_profile["calibration_seed_count"])),
		"held_out_seeds": _profile["seeds"].slice(int(_profile["calibration_seed_count"])), "seeds": rows}
	var file := FileAccess.open(OUT + "study.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	for failure in _failures: printerr(failure)
	print("OreVeinStudy: %s" % ("PASS" if _failures.is_empty() else "FAIL"))
	quit(0 if _failures.is_empty() else 1)


func _build_world(seed_value: int) -> void:
	root.get_node("WorldData").clear_world()
	_gen._reset_generation_state()
	_gen.world_seed = seed_value
	_gen._cache_block_ids()
	_gen._layout_profile = _gen.load_macro_layout_profile()
	_gen._build_noise_instances()
	_gen._build_seeded_maps()
	_gen._apply_edge_detail()
	_gen._build_cave_maps()
	_gen._maps_ready = true
	# Keep the reviewed shared-field baseline reproducible after live integration.
	_windows = _gen._metal_windows.duplicate(true)
	for i in range(_windows.size()):
		_windows[i]["threshold"] = _profile["baseline_thresholds"][NAMES[i]]
	_baseline_noise = _noise(seed_value + 1, 0.02)
	_ids.clear()
	for i in range(_windows.size()): _ids[_windows[i]["id"]] = i + 1


func _noise(seed_value: int, frequency: float) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.seed = seed_value
	noise.frequency = frequency
	noise.fractal_octaves = 2
	return noise


func _fields(seed_value: int) -> Array[FastNoiseLite]:
	var fields: Array[FastNoiseLite] = []
	for name: String in NAMES:
		var def: Dictionary = _profile["independent_fields"][name]
		fields.append(_noise(seed_value + int(def["seed_offset"]), def["frequency"]))
	return fields


func _eligible(x: int, y: int, z: int, top: int, actual: int) -> bool:
	if y <= 3 or y >= top or actual == _blocks.AIR_ID: return false
	if _gen._is_resource_perimeter_column(x, z) or _gen._is_natural_exposed_wall(x, y, z): return false
	# Actual gems win before all prototype ores, just as in live generation.
	for window: Dictionary in _gen._gem_windows:
		if actual == window["id"]: return false
	return _gen._is_resource_replaceable_rock(_gen.get_overview_strata_block_id(x, y, z))


func _sample_world() -> Dictionary:
	var counts := {"current": [0,0,0,0,0,0], "finer_shared": [0,0,0,0,0,0]}
	var finer := _noise(_gen.world_seed + 1, _profile["shared_frequency"])
	var points := PackedVector3Array()
	var sampled := 0
	for x in range(4, 1024, 8):
		for z in range(4, 1024, 8):
			var top: int = _gen.get_surface_y(x, z)
			for y in range(4, top + 1):
				sampled += 1
				var actual: int = _gen.get_generated_block_id(x, y, z)
				if not _eligible(x, y, z, top, actual): continue
				var old_id: int = _gen._pick_resource_from_windows(_windows, y, (_baseline_noise.get_noise_3d(x, y, z) + 1.0) * 0.5)
				if _ids.has(old_id): counts["current"][_ids[old_id] - 1] += 1
				points.append(Vector3(x, y, z))
				var noise := (finer.get_noise_3d(x, y, z) + 1.0) * 0.5
				var id: int = _gen._pick_resource_from_windows(_windows, y, noise)
				if id >= 0: counts["finer_shared"][_ids[id] - 1] += 1
	return {"seed": _gen.world_seed, "counts": counts, "sampled_cells": sampled, "points": points}


func _save_points(seed_value: int, points: PackedVector3Array) -> void:
	var file := FileAccess.open(OUT + "points_%d.bin" % seed_value, FileAccess.WRITE)
	file.store_var(points)


func _read_points(seed_value: int) -> PackedVector3Array:
	var file := FileAccess.open(OUT + "points_%d.bin" % seed_value, FileAccess.READ)
	return file.get_var()


func _calibrate() -> void:
	# Fit six global cutoffs on four seeds, never per seed or per displayed box.
	# Later resources are fitted on the cells earlier resources leave unassigned.
	for data: Dictionary in _training:
		data["fields"] = _fields(data["seed"])
		var assigned := PackedByteArray()
		assigned.resize(data["points"].size())
		data["assigned"] = assigned
	for i in range(NAMES.size()):
		var values := PackedFloat32Array()
		var target := 0
		var window: Dictionary = _windows[i]
		for data: Dictionary in _training:
			target += data["counts"]["current"][i]
			var points: PackedVector3Array = data["points"]
			var assigned: PackedByteArray = data["assigned"]
			var field: FastNoiseLite = data["fields"][i]
			for j in range(points.size()):
				var point := points[j]
				if assigned[j] != 0 or point.y < window["min_y"] or point.y > window["max_y"]: continue
				values.append((field.get_noise_3dv(point) + 1.0) * 0.5)
		values.sort()
		_expect(target > 0 and target < values.size(), "Insufficient calibration candidates for " + NAMES[i])
		var cutoff := (values[values.size() - target - 1] + values[values.size() - target]) * 0.5
		_thresholds.append(cutoff)
		for data: Dictionary in _training:
			var points: PackedVector3Array = data["points"]
			var assigned: PackedByteArray = data["assigned"]
			var field: FastNoiseLite = data["fields"][i]
			for j in range(points.size()):
				var point := points[j]
				if assigned[j] != 0 or point.y < window["min_y"] or point.y > window["max_y"]: continue
				if (field.get_noise_3dv(point) + 1.0) * 0.5 > cutoff: assigned[j] = i + 1
			data["assigned"] = assigned
		print("OreVeinStudy: calibrated %s to %.8f (%d target blocks)." % [NAMES[i], cutoff, target])


func _pick_separate(point: Vector3, fields: Array[FastNoiseLite]) -> int:
	for i in range(_windows.size()):
		var window: Dictionary = _windows[i]
		if point.y < window["min_y"] or point.y > window["max_y"]: continue
		if (fields[i].get_noise_3dv(point) + 1.0) * 0.5 > _thresholds[i]: return i + 1
	return 0


func _export_box(seed_value: int, fields: Array[FastNoiseLite]) -> Dictionary:
	var center := Vector2i(-1, -1)
	for x in range(48, 992, 32):
		for z in range(48, 992, 32):
			if _gen.get_surface_y(x, z) == 115:
				center = Vector2i(x, z)
				break
		if center.x >= 0: break
	_expect(center.x >= 0, "Missing summit sample.")
	var origin := Vector3i(center.x - 32, 12, center.y - 32)
	var current := PackedByteArray()
	var finer := PackedByteArray()
	var separate := PackedByteArray()
	var fine_field := _noise(seed_value + 1, _profile["shared_frequency"])
	var second_fields := _fields(seed_value)
	var size := 64
	var eligible_count := 0
	# File order: [local Y][local Z][local X]. A horizontal layer is 4096 bytes.
	for dy in range(size):
		for dz in range(size):
			for dx in range(size):
				var point := origin + Vector3i(dx, dy, dz)
				var actual: int = _gen.get_generated_block_id(point.x, point.y, point.z)
				if not _eligible(point.x, point.y, point.z, _gen.get_surface_y(point.x, point.z), actual):
					_expect(not _ids.has(actual), "Ineligible live ore cell.")
					current.append(0)
					finer.append(0)
					separate.append(0)
					continue
				eligible_count += 1
				var old_id: int = _gen._pick_resource_from_windows(_windows, point.y, (_baseline_noise.get_noise_3dv(Vector3(point)) + 1.0) * 0.5)
				current.append(int(_ids.get(old_id, 0)))
				var noise := (fine_field.get_noise_3dv(Vector3(point)) + 1.0) * 0.5
				var id: int = _gen._pick_resource_from_windows(_windows, point.y, noise)
				finer.append(int(_ids.get(id, 0)))
				var proposed := _pick_separate(Vector3(point), fields)
				separate.append(proposed)
				if proposed > 0:
					var window: Dictionary = _windows[proposed - 1]
					_expect(point.y >= window["min_y"] and point.y <= window["max_y"], "Prototype escaped resource depth band.")
				# Independent instance/reverse lookup spot check guards stateful RNG.
				if dx % 13 == 0 and dy % 11 == 0 and dz % 7 == 0:
					_expect(_pick_separate(Vector3(point), second_fields) == proposed, "Prototype noise is not seed deterministic.")
	var variants := [current, finer, separate]
	var hashes := {}
	for i in range(VARIANTS.size()):
		var file := FileAccess.open(OUT + "%d_%s.bin" % [seed_value, VARIANTS[i]], FileAccess.WRITE)
		file.store_buffer(variants[i])
		hashes[VARIANTS[i]] = (variants[i] as PackedByteArray).hex_encode().sha256_text()
	return {"origin": [origin.x, origin.y, origin.z], "size": size, "eligible_cells": eligible_count, "sha256": hashes}


func _expect(condition: bool, message: String) -> void:
	if not condition and message not in _failures: _failures.append(message)
