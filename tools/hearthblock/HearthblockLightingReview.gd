extends "res://tools/voxel_assets/CopiedSaveReview.gd"

## Hearthblock lighting pass review (docs/00_dev_roadmap/255_hearthblock_lighting_pass.md).
## Loads a recovery copy of a player save in an isolated profile, verifies the
## on/off contract end to end, captures matched views and measures GPU time.
## Run through tools/hearthblock/RunLightingReview.ps1; never against a live profile.
# Autoload names are not identifiers in --script mode, and scripts that use them
# cannot be preloaded here; refer to the light group and closed shader by path.
const LOOK_GROUP := &"hearthblock_furniture_lights"
const CLOSED_SHADER_PATH := "res://scripts/shaders/underground_lighting_closed.gdshader"
const GPU_SAMPLES := 180

var save_source := "res://tmp/hearthblock_lighting_20261020/recovery/player_saves/quicksave.json"
var _scene_env: Environment
var _lighting: Node
var _stockpiles: Node


func _run() -> void:
	output = "res://tmp/hearthblock_lighting_20261020/review/"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=").trim_suffix("/") + "/"
		if arg.begins_with("--source="): save_source = arg.trim_prefix("--source=")
	if not "/hearthblock_lighting_20261020/" in OS.get_user_data_dir().replace("\\", "/"):
		_fail("isolated recovery-copy profile required"); return
	create_timer(600).timeout.connect(func(): _fail("hearthblock review timeout"))
	DirAccess.make_dir_recursive_absolute(output)
	# The project starts borderless fullscreen; keep reviews in a fixed 32:9 window.
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	root.size = Vector2i(3840, 1080)
	_save_manager = root.get_node("SaveManager")
	_world_generator = root.get_node("WorldGenerator")
	_world_clock = root.get_node("WorldClock")
	_save_manager.configure_storage_for_testing("user://hearthblock_copy")
	# Startup resume (milestone 240) would load the copy on its own and reject the
	# explicit load below as busy; this review loads it explicitly instead.
	_save_manager._startup_checked = true
	_save_manager.set_process(false)
	DirAccess.make_dir_recursive_absolute("user://hearthblock_copy")
	FileAccess.open("user://hearthblock_copy/quicksave.json", FileAccess.WRITE).store_string(FileAccess.get_file_as_string(save_source))
	var read: Dictionary = _save_manager._read_snapshot("user://hearthblock_copy/quicksave.json")
	if not read.get("ok", false): _fail("invalid copied input"); return
	var expected: Dictionary = read.snapshot
	report = {"source_sha256": FileAccess.get_sha256(save_source), "failures": failures, "views": [], "gpu_ms": {}}
	_world_generator.world_seed = int(expected.world_seed)
	_world_clock.set_paused(true)
	node_added.connect(func(node: Node):
		if node.name == "Renderer" and node.get_script() != null: node.world_seed = int(expected.world_seed))
	change_scene_to_file("res://scenes/main/debug_world.tscn")
	await process_frame
	await process_frame
	if not await _wait_for_world_ready(WORLD_TIMEOUT_MSEC): _fail("initial world timeout"); return
	if not await _load_copy(): _fail("load failed"); return
	_scene_env = (current_scene.get_node("WorldEnvironment") as WorldEnvironment).environment
	_lighting = current_scene.get_node("Renderer").underground_lighting
	_stockpiles = current_scene.find_child("StockpileDesignationController", true, false)
	for layer in current_scene.find_children("*", "CanvasLayer", true, false): layer.visible = false
	var sky := root.get_node("SkyController")
	report["started_enabled"] = sky.is_hearthblock_enabled()
	report["counts"] = {"furniture_lights": get_nodes_in_group(LOOK_GROUP).size(),
		"cached_materials": _lighting._material_cache.size(), "stockpile_zones": _stockpiles._zones.size() if _stockpiles != null else 0}

	# The previous look first, as the reference that switching off must restore.
	sky.set_hearthblock_lighting(false)
	await _frames(3)
	var baseline := _state()
	_check_off(baseline)
	sky.set_hearthblock_lighting(true)
	await _frames(3)
	_check_on(_state())
	sky.set_hearthblock_lighting(false)
	await _frames(3)
	var restored := _state()
	var difference := _deep_diff(baseline, restored, "restore")
	if difference != "": failures.append("switching off did not restore the previous look: " + difference)

	# Matched views of the hall around the dining table: the save's own zoom,
	# pitch and rotation, a gameplay zoom and a close-up.
	var rig = current_scene.get_node("CameraRig")
	var saved_view: Dictionary = rig.serialize_state()
	var hall := _nearest_table(expected, _save_manager.unpack_v3(saved_view.target_position))
	var hall_view := _with(saved_view, {"target_position": _save_manager.pack_v3(hall)})
	var views := [
		["colony", hall_view],
		["gameplay", _with(hall_view, {"zoom": 40.0})],
		["close", _with(hall_view, {"zoom": 15.0, "pitch": -38.0})],
	]
	for view in views:
		rig.restore_state(view[1])
		await _settle_visuals()
		for on in [false, true]:
			sky.set_hearthblock_lighting(on)
			await _frames(4)
			await _capture(String(view[0]) + ("_on" if on else "_off"))
		report.views.append({"name": view[0], "camera": view[1]})
	# Tone mapping and glow also reach the surface: the full world, unsliced, at the save's hour.
	var slice = current_scene.get_node("SliceController")
	slice.deactivate()
	rig.restore_state(_with(hall_view, {"zoom": 60.0}))
	await _settle_visuals()
	for on in [false, true]:
		sky.set_hearthblock_lighting(on)
		await _frames(4)
		await _capture("surface" + ("_on" if on else "_off"))
	report.views.append({"name": "surface", "hour": _world_clock.hour})
	slice.activate()
	slice._set_slice_y(int(expected.scene.slice.get("slice_y", 127)))
	rig.restore_state(hall_view)
	await _settle_visuals()
	for on in [false, true, false, true]:
		sky.set_hearthblock_lighting(on)
		var samples := await _gpu_samples()
		var key := "on" if on else "off"
		report.gpu_ms[key] = report.gpu_ms.get(key, []) + [samples]
	FileAccess.open(output + "report.json", FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	for failure in failures: push_error(failure)
	print("HEARTHBLOCK_LIGHTING_PASS " if failures.is_empty() else "HEARTHBLOCK_LIGHTING_FAIL ", JSON.stringify(report.counts), " gpu ", JSON.stringify(report.gpu_ms))
	quit(0 if failures.is_empty() else 1)


func _frames(count: int) -> void:
	for i in count: await process_frame


func _with(base: Dictionary, changes: Dictionary) -> Dictionary:
	var value := base.duplicate(true)
	value.merge(changes, true)
	return value


func _nearest_table(snapshot: Dictionary, near: Vector3) -> Vector3:
	var best := near
	var best_distance := INF
	for piece: Dictionary in snapshot.scene.furniture.installed:
		if String(piece.get("key", "")) != "base:furniture:log_table": continue
		var at: Array = piece.get("origin", piece.get("position", []))
		if at.size() < 3: continue
		var position := Vector3(float(at[0]) + 1.5, float(at[1]), float(at[2]) + 1.5)
		if position.distance_to(near) < best_distance:
			best_distance = position.distance_to(near)
			best = position
	report["close_target"] = _save_manager.pack_v3(best)
	return best


## Everything the look touches, in comparable form.
func _state() -> Dictionary:
	var env := {}
	for key in ["tonemap_mode", "tonemap_exposure", "tonemap_white", "glow_enabled", "glow_intensity", "glow_strength",
			"glow_bloom", "glow_blend_mode", "glow_hdr_threshold", "glow_hdr_scale"]:
		env[key] = _scene_env.get(key)
	var levels := []
	for i in range(7): levels.append(_scene_env.get_glow_level(i))
	env["glow_levels"] = levels
	var materials := []
	for id in _lighting._material_cache:
		var material: ShaderMaterial = _lighting._material_cache[id]
		var row := {"closed": material.shader.resource_path == CLOSED_SHADER_PATH}
		for parameter in ["readability_floor", "readability_tint", "view_fill", "slice_cap_tint"]:
			row[parameter] = var_to_str(material.get_shader_parameter(parameter))
		materials.append(row)
	var lights := []
	for light: OmniLight3D in get_nodes_in_group(LOOK_GROUP):
		var flame: Variant = light.get_meta("flame_material", null)
		lights.append({"color": var_to_str(light.light_color), "base": var_to_str(light.get_meta("base_color")),
			"warm": var_to_str(light.get_meta("hearthblock_color", null)),
			"flame": var_to_str(flame.albedo_color) if flame is StandardMaterial3D else ""})
	var zones := []
	if _stockpiles != null:
		for color: Color in _stockpiles._zone_colors(): zones.append(var_to_str(color))
	return {"env": env, "materials": materials, "lights": lights, "zones": zones}


func _check_off(state: Dictionary) -> void:
	if state.env.tonemap_mode != Environment.TONE_MAPPER_LINEAR: failures.append("off: tone mapping is not linear")
	if state.env.glow_enabled: failures.append("off: glow enabled")
	for row: Dictionary in state.materials:
		if str_to_var(row.readability_floor) != 0.008: failures.append("off: readability floor changed"); break
		if row.view_fill != var_to_str(0.0): failures.append("off: view fill present"); break
	for row: Dictionary in state.lights:
		if row.color != row.base: failures.append("off: light colour differs from its definition"); break
		if row.flame != "" and row.flame != var_to_str(Color.WHITE): failures.append("off: flame gain applied"); break


func _check_on(state: Dictionary) -> void:
	var look: Dictionary = root.get_node("SkyController").hearthblock_settings()
	if state.env.tonemap_mode != Environment.TONE_MAPPER_ACES: failures.append("on: tone mapping is not ACES")
	if not state.env.glow_enabled: failures.append("on: glow disabled")
	if not is_equal_approx(float(state.env.tonemap_exposure), float(look.exposure)): failures.append("on: exposure")
	var closed_fill := false
	for row: Dictionary in state.materials:
		if not is_equal_approx(float(str_to_var(row.readability_floor)), float(look.underground_fill.readability_floor)): failures.append("on: readability floor"); break
		if row.closed and is_equal_approx(float(str_to_var(row.view_fill)), float(look.view_fill)): closed_fill = true
		if not row.closed and row.view_fill != var_to_str(0.0): failures.append("on: view fill on an open material"); break
	if not closed_fill and not state.materials.is_empty(): failures.append("on: no closed material received the view fill")
	var warmed := 0
	for row: Dictionary in state.lights:
		if row.warm != "null":
			if row.color != row.warm: failures.append("on: light not warmed"); break
			warmed += 1
		if row.flame != "" and row.flame == var_to_str(Color.WHITE): failures.append("on: flame gain missing"); break
	report["warmed_lights"] = warmed
	if _stockpiles != null and state.zones == [var_to_str(_stockpiles.COLOR_ZONE), var_to_str(_stockpiles.COLOR_ZONE_EDGE)]:
		failures.append("on: stockpile zones kept the blue overlay")


func _gpu_samples() -> Dictionary:
	var rid := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	await _frames(20)
	var gpu: Array[float] = []
	var cpu: Array[float] = []
	for i in GPU_SAMPLES:
		await process_frame
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
		cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(rid))
	gpu.sort(); cpu.sort()
	return {"gpu_median": gpu[gpu.size() / 2], "gpu_p95": gpu[int(gpu.size() * 0.95)], "render_cpu_median": cpu[cpu.size() / 2]}
