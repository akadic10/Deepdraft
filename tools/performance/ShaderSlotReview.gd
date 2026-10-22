extends "res://tools/voxel_assets/CopiedSaveReview.gd"

## Shader-slot review (docs/00_dev_roadmap/00_todo.md, "Lit-shader per-object slots").
## Loads a copy of a player save in an isolated profile and counts the meshes that
## reserve a block of the global shader buffer: every mesh whose shader declares
## `instance uniform`s, directly or through underground_lighting_common.gdshaderinc.
## Godot reserves 16 slots per mesh, visible or not, so the cap is buffer_size / 16.
## With --mining it also times freshly mined blocks, in order: the per-block cost
## (~19 ms on the owner's save after the 2026-10-21 fix) and the one-off hitch on
## the first block after a load (00_todo.md).
## Run through tools/performance/RunShaderSlots.ps1; never against a live profile.

const SLOT_MARKERS := ["instance uniform", "underground_lighting_common"]
const SLOTS_PER_MESH := 16
const MINED_SAMPLES := 6

var save_source := ""
var time_mining := false


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=").trim_suffix("/") + "/"
		if arg.begins_with("--source="): save_source = arg.trim_prefix("--source=")
		if arg == "--mining": time_mining = true
	if not "/tmp/shader_slots/" in OS.get_user_data_dir().replace("\\", "/"):
		_fail("isolated shader-slot profile required"); return
	if save_source.is_empty() or not FileAccess.file_exists(save_source):
		_fail("--source=<copied save> required"); return
	create_timer(900).timeout.connect(func(): _fail("shader slot review timeout"))
	DirAccess.make_dir_recursive_absolute(output)
	_save_manager = root.get_node("SaveManager")
	_world_generator = root.get_node("WorldGenerator")
	_world_clock = root.get_node("WorldClock")
	_save_manager.configure_storage_for_testing("user://shader_slot_copy")
	# Startup resume (milestone 240) would load the copy on its own and reject the
	# explicit load below as busy; this review loads it explicitly instead.
	_save_manager._startup_checked = true
	_save_manager.set_process(false)
	DirAccess.make_dir_recursive_absolute("user://shader_slot_copy")
	FileAccess.open("user://shader_slot_copy/quicksave.json", FileAccess.WRITE).store_string(FileAccess.get_file_as_string(save_source))
	var read: Dictionary = _save_manager._read_snapshot("user://shader_slot_copy/quicksave.json")
	if not read.get("ok", false): _fail("invalid copied save: %s" % read.get("error", "")); return
	var expected: Dictionary = read.snapshot
	report = {"source_sha256": FileAccess.get_sha256(save_source)}
	_world_generator.world_seed = int(expected.world_seed)
	_world_clock.set_paused(true)
	node_added.connect(func(node: Node):
		if node.name == "Renderer" and node.get_script() != null: node.world_seed = int(expected.world_seed))
	change_scene_to_file("res://scenes/main/debug_world.tscn")
	await process_frame
	await process_frame
	if not await _wait_for_world_ready(WORLD_TIMEOUT_MSEC): _fail("world timeout"); return
	if not await _load_copy(): _fail("load failed"); return
	for i in 30: await process_frame
	report["dwarves"] = _count_dwarves()
	report["slots"] = _count_slot_users()
	if time_mining: report["mining"] = await _time_mining()
	FileAccess.open(output + "report.json", FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print("SHADER_SLOT_REVIEW_PASS ", JSON.stringify(report))
	quit(0)


func _count_dwarves() -> int:
	var count := 0
	for node in root.find_children("*", "CharacterBody3D", true, false):
		if node.get_script() != null and String(node.get_script().resource_path).ends_with("DwarfAgent.gd"): count += 1
	return count


# ── Slot users ────────────────────────────────────────────────────────────────

## A MultiMeshInstance3D reserves one block however many instances it draws.
func _count_slot_users() -> Dictionary:
	var meshes := 0
	var users := 0
	var visible_users := 0
	var by_system := {}
	for node in root.find_children("*", "GeometryInstance3D", true, false):
		meshes += 1
		if not _reserves_slots(node): continue
		users += 1
		if node.is_visible_in_tree(): visible_users += 1
		var system := _system_of(node)
		by_system[system] = int(by_system.get(system, 0)) + 1
	var buffer_size := int(ProjectSettings.get_setting("rendering/limits/global_shader_variables/buffer_size", 65536))
	return {"users": users, "cap": buffer_size / SLOTS_PER_MESH, "visible_users": visible_users,
		"geometry_instances": meshes, "by_system": by_system}


## Top-level node under the scene (Renderer, SurfaceDetailManager, …).
func _system_of(node: Node) -> String:
	var n := node
	while n.get_parent() != null and n.get_parent() != current_scene and n.get_parent() != root:
		n = n.get_parent()
	return String(n.name)


func _reserves_slots(gi: GeometryInstance3D) -> bool:
	if _declares_slots(gi.material_override) or _declares_slots(gi.material_overlay): return true
	if gi is MeshInstance3D and gi.mesh != null:
		for i in gi.mesh.get_surface_count():
			if _declares_slots(gi.get_surface_override_material(i)) or _declares_slots(gi.mesh.surface_get_material(i)): return true
	if gi is MultiMeshInstance3D and gi.multimesh != null and gi.multimesh.mesh != null:
		for i in gi.multimesh.mesh.get_surface_count():
			if _declares_slots(gi.multimesh.mesh.surface_get_material(i)): return true
	return false


func _declares_slots(material: Material) -> bool:
	while material != null:
		if material is ShaderMaterial and (material as ShaderMaterial).shader != null:
			var code: String = (material as ShaderMaterial).shader.code
			for marker in SLOT_MARKERS:
				if code.contains(marker): return true
		material = material.next_pass
	return false


# ── Mining cost (--mining) ────────────────────────────────────────────────────

## Mines blocks beside existing tunnels while the clock stays paused. call_ms is the
## mining call itself; frame_ms is the worst of the next four frames.
func _time_mining() -> Dictionary:
	var world = root.get_node("WorldData")
	var registry = root.get_node("BlockRegistry")
	var nav = root.get_node("NavGrid")
	var renderer = current_scene.get_node("Renderer")
	var mining = current_scene.get_node("MiningDesignationController")
	var result := {"idle_frame_ms": await _frame_median_ms(40), "blocks": []}
	for block: Vector3i in _minable_blocks(world, registry, renderer, MINED_SAMPLES):
		for i in 5: await process_frame
		var started := Time.get_ticks_usec()
		mining._mine_block_world(block)
		nav.refresh_mined_block(block)
		var call_ms := (Time.get_ticks_usec() - started) / 1000.0
		var worst := 0.0
		var last := Time.get_ticks_usec()
		for i in 4:
			await process_frame
			var now := Time.get_ticks_usec()
			worst = maxf(worst, (now - last) / 1000.0)
			last = now
		result.blocks.append({"block": [block.x, block.y, block.z], "call_ms": snappedf(call_ms, 0.1),
			"frame_ms": snappedf(worst, 0.1)})
	return result


func _minable_blocks(world, registry, renderer, count: int) -> Array[Vector3i]:
	var found: Array[Vector3i] = []
	var dirs := [Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK, Vector3i.DOWN]
	for air: Vector3i in renderer._mined_blocks.keys():
		for d: Vector3i in dirs:
			var b: Vector3i = air + d
			if b.y <= 5 or found.has(b): continue
			var id: int = world.get_live_block(b.x, b.y, b.z)
			if not registry.is_solid(id): continue
			var def: Dictionary = registry.get_def(registry.get_key(id))
			if int(def.get("hardness", 1)) < 0 or String(def.get("kind", "")) == "water": continue
			found.append(b)
			if found.size() >= count: return found
	return found


func _frame_median_ms(frames: int) -> float:
	var samples: Array[float] = []
	var last := Time.get_ticks_usec()
	for i in frames:
		await process_frame
		var now := Time.get_ticks_usec()
		samples.append((now - last) / 1000.0)
		last = now
	samples.sort()
	return snappedf(samples[samples.size() / 2], 0.1)
