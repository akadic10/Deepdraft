extends SceneTree

## Offline geography contract and seed gallery. Never loads the game scene.
## Run with APPDATA/LOCALAPPDATA beneath tmp/world_layout_review (see doc 66).
const Layout = preload("res://scripts/components/WorldLayout.gd")
const Validator = preload("res://scripts/components/WorldLayoutValidator.gd")
const OUTPUT := "res://tmp/world_layout_review/"
const GALLERY_SEEDS := [0, 1, 2, 7, 42, 1234, 65535, 20261007, 3381051336, 4294967295, 987654321, 314159265, 271828182, 8675309, 1000000007, 2147483647]
var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if not OS.get_environment("APPDATA").replace("\\", "/").contains("/tmp/world_layout_review/"):
		printerr("Use the isolated test APPDATA path documented in doc 66.")
		quit(2)
		return
	root.get_node("SaveManager").set_process(false)
	root.get_node("WorldClock").set_paused(true)
	var profile: Dictionary = root.get_node("WorldGenerator").load_macro_layout_profile()
	var profile_errors := Validator.profile_errors(profile)
	if not profile_errors.is_empty():
		printerr(profile_errors)
		quit(1)
		return
	var sample_count := 1000
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--count="): sample_count = maxi(16, int(arg.trim_prefix("--count=")))
	var started := Time.get_ticks_msec()
	var gallery: Array = []
	var fingerprints: Dictionary = {}
	var attempts: Dictionary = {}
	var quadrants := [0, 0, 0, 0]
	var mountain_min := 1024
	var mountain_max := 0
	var mountain_sum := 0
	var lowland_min := 1024
	var summit_min := 1024
	var summit_max := 0
	var tarns := 0
	var coastal := 0
	var fallbacks := 0
	var rejected_reasons: Dictionary = {}
	for i in range(sample_count):
		var world_seed := int(GALLERY_SEEDS[i]) if i < GALLERY_SEEDS.size() else (i * 2654435761) & 0xffffffff
		var layout: Dictionary = Layout.new().generate(world_seed, profile)
		if not bool(layout.get("ok", false)):
			_failures.append("Seed %d failed: %s" % [world_seed, layout])
			break
		var check := Validator.inspect(layout, profile)
		_require(not layout.has("settlement"), "Layout still reserves a starting area: %d" % world_seed)
		_require(check["errors"].is_empty(), "Independent recheck failed: %d" % world_seed)
		var metrics: Dictionary = check["metrics"]
		var mountain := int(metrics["connected_summit_mountain_cells"])
		mountain_min = mini(mountain_min, mountain)
		mountain_max = maxi(mountain_max, mountain)
		mountain_sum += mountain
		lowland_min = mini(lowland_min, int(metrics["largest_dry_lowland_cells"]))
		summit_min = mini(summit_min, int(metrics["summit_cells"]))
		summit_max = maxi(summit_max, int(metrics["summit_cells"]))
		if metrics["has_tarn"]: tarns += 1
		if metrics["lake_coastal"]: coastal += 1
		if layout["used_fallback"]: fallbacks += 1
		var quadrant := (1 if float(metrics["summit_center"][0]) >= 16.0 else 0) + (2 if float(metrics["summit_center"][1]) >= 16.0 else 0)
		quadrants[quadrant] += 1
		var attempt_key := str(layout["attempts"])
		attempts[attempt_key] = int(attempts.get(attempt_key, 0)) + 1
		for rejection: Array in layout["rejected"]:
			for reason: String in rejection:
				rejected_reasons[reason] = int(rejected_reasons.get(reason, 0)) + 1
		var fingerprint := JSON.stringify(layout).sha256_text()
		fingerprints[str(world_seed)] = fingerprint
		if i < GALLERY_SEEDS.size():
			gallery.append(layout)
			var repeated: Dictionary = Layout.new().generate(world_seed, profile)
			_require(fingerprint == JSON.stringify(repeated).sha256_text(), "Nondeterministic seed %d" % world_seed)
		if (i + 1) % 100 == 0: print("WorldLayoutTest: %d / %d seeds" % [i + 1, sample_count])
	for quadrant in range(4): _require(quadrants[quadrant] > 0, "No summit in quadrant %d" % quadrant)
	_require(tarns > 0 and tarns < sample_count, "Tarn optionality was not exercised.")
	_require(coastal > 0 and coastal < sample_count, "Coastal/inland lake variation was not exercised.")
	var fallback_profile := profile.duplicate(true)
	fallback_profile["max_attempts"] = 0
	for i in range(Layout.FALLBACK_VARIANTS):
		var layout: Dictionary = Layout.new().generate(i, fallback_profile)
		_require(bool(layout.get("ok", false)) and bool(layout.get("used_fallback", false)), "Forced fallback %d failed: %s" % [i, layout.get("errors", [])])
		_require(int(layout.get("fallback_variant", -1)) == i, "Fallback coverage missed variant %d" % i)
	if not gallery.is_empty(): _test_rejections(gallery[0], profile)
	var bad_profile := profile.duplicate(true)
	bad_profile["macro_count"] = 16
	_require(not Layout.new().generate(0, bad_profile).get("ok", true), "Unsupported grid accepted.")
	var report := {"profile_id": profile["profile_id"], "sample_count": sample_count, "elapsed_ms": Time.get_ticks_msec() - started,
		"passed": _failures.is_empty(), "failures": _failures, "forced_fallback_variants": Layout.FALLBACK_VARIANTS, "determinism_repeats": GALLERY_SEEDS.size(),
		"connected_mountain_cells": {"min": mountain_min, "max": mountain_max, "mean": float(mountain_sum) / sample_count},
		"lowest_connected_dry_lowland_cells": lowland_min, "summit_cells": {"min": summit_min, "max": summit_max},
		"tarn_count": tarns, "coastal_lake_count": coastal, "inland_lake_count": sample_count - coastal,
		"summit_quadrants_nw_ne_sw_se": quadrants, "attempt_histogram": attempts, "fallback_count": fallbacks,
		"rejected_reasons": rejected_reasons, "fingerprints": fingerprints}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	_write_json("report.json", report)
	_write_json("gallery.json", {"profile": profile, "layouts": gallery})
	print("WorldLayoutTest: %s in %d ms; mountain cells %d..%d; tarns %d; coast/inland %d/%d; fallback %d" % [
		"PASS" if _failures.is_empty() else "FAIL", report["elapsed_ms"], mountain_min, mountain_max, tarns, coastal, sample_count - coastal, fallbacks])
	for failure in _failures: printerr(failure)
	quit(0 if _failures.is_empty() else 1)


func _test_rejections(original: Dictionary, profile: Dictionary) -> void:
	var broken := original.duplicate(true)
	for i in range(broken["ranks"].size()):
		if broken["ranks"][i] == 9:
			broken["ranks"][i] = 8
			broken["heights"][i] = 103
	_rejects(broken, profile, "Missing required Y115 summit.")
	broken = original.duplicate(true)
	broken["ranks"][0] = 9
	broken["heights"][0] = 115
	_rejects(broken, profile, "Adjacent terrain shelves differ by more than one rank.")
	broken = original.duplicate(true)
	broken["heights"][broken["water_bodies"][0]["cells"][0]] = 10
	_rejects(broken, profile, "Water footprint/floor disagree with final maps.")
	broken = original.duplicate(true)
	broken["water_bodies"][0]["cells"].append(1023)
	_rejects(broken, profile, "Disconnected water body.")
	var strict := profile.duplicate(true)
	strict["requirements"]["min_connected_mountain_cells"] = 1024
	_rejects(original, strict, "Summit lacks a substantial connected mountain region.")
	strict = profile.duplicate(true)
	strict["requirements"]["min_connected_dry_lowland_cells"] = 1024
	_rejects(original, strict, "Insufficient connected dry lowland.")
	# Deep copies used for corruption tests must not mutate the accepted map.
	_require(Validator.inspect(original, profile)["errors"].is_empty(), "Corruption tests altered the original layout.")


func _rejects(layout: Dictionary, profile: Dictionary, expected: String) -> void:
	_require(expected in Validator.inspect(layout, profile)["errors"], "Validator missed: " + expected)


func _require(condition: bool, message: String) -> void:
	if not condition: _failures.append(message)


func _write_json(filename: String, value: Dictionary) -> void:
	var file := FileAccess.open(OUTPUT + filename, FileAccess.WRITE)
	if file == null:
		_failures.append("Cannot write " + filename)
		return
	file.store_string(JSON.stringify(value, "\t"))
	file.close()
