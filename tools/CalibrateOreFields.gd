extends "res://tools/OreVeinStudy.gd"

## One-time offline fit against the eight original study samples. Never run
## during world generation. The next eight integration seeds are not fitted.
func _run() -> void:
	if not OS.get_environment("APPDATA").replace("\\", "/").contains("/tmp/ore_field_integration/"):
		printerr("Use isolated APPDATA under tmp/ore_field_integration.")
		quit(2)
		return
	var original: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OUT + "study.json"))
	_profile = original["profile"]
	_gen = root.get_node("WorldGenerator")
	_gen._cache_block_ids()
	_windows = _gen._metal_windows
	for row: Dictionary in original["seeds"]:
		_training.append({"seed": int(row["seed"]), "points": _read_points(int(row["seed"])), "counts": row["sample"]})
	_calibrate()
	var report := {"passed": _failures.is_empty(), "failures": _failures,
		"calibration_seeds": _profile["seeds"], "thresholds": _thresholds, "profile": _profile}
	var file := FileAccess.open("res://tmp/ore_field_integration/calibration.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	for failure in _failures: printerr(failure)
	print("CalibrateOreFields: %s" % ("PASS" if _failures.is_empty() else "FAIL"))
	quit(0 if _failures.is_empty() else 1)
