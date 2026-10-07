extends "res://tools/DwarfRedesignPreview.gd"

## Live art QA: real DwarfAgent assembly/tints/gait through DwarfAssets.
## Run tools/dwarf_roster_review.tscn with -- --capture (GPU) or -- --check
## (headless). Never enters the colony scene or writes a game save.

func _ready() -> void:
	SkyController.set_process(false)
	WorldClock.set_process(false)
	SaveManager.set_process(false)
	WorldGenerator.world_seed = 1 # deterministic weather initialization in the review only
	_build_stage()
	_build_ui()
	_set_lineup(false)
	_set_view("Three-quarter")
	# Autoloads bind on their first deferred frame. Restore studio light after
	# that one-time binding; a BG_COLOR review has no sky to supply ambient light.
	await get_tree().process_frame
	await get_tree().process_frame
	for child in get_children():
		if child is WorldEnvironment:
			child.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			child.environment.ambient_light_color = Color(0.95, 0.97, 1.0)
			child.environment.ambient_light_energy = 0.40
	var sun := get_children().filter(func(n: Node): return n is DirectionalLight3D)[0] as DirectionalLight3D
	sun.rotation_degrees = Vector3(-52, -32, 0)
	sun.light_color = Color(1.0, 0.95, 0.87)
	sun.light_energy = 0.70
	if "--check" in OS.get_cmdline_user_args():
		_validate_registry()
		get_tree().quit(0)
	elif "--capture" in OS.get_cmdline_user_args():
		_capture_all.call_deferred()


func _title_text() -> String:
	return "Deepdraft dwarves   ·   live assets   ·   8 voxels per block"


func _comparison_text() -> String:
	return "More styles"


func _make_actor(spec: Array) -> DwarfAgent:
	var ap := DwarfAppearanceData.new()
	ap.gender = spec[0]
	ap.hair_style = spec[1]
	ap.beard_style = spec[2]
	ap.age_tier = spec[3]
	ap.skin_tone = spec[4]
	ap.hair_color = spec[5]
	ap.eyebrow_style = spec[6]
	ap.eye_color = "blue"
	var actor := DwarfAgent.new()
	actor.setup(0, {"name": "Art review", "gender": ap.gender, "appearance": ap})
	actor.set_process(false)
	return actor


func _set_lineup(alternate: bool) -> void:
	_comparison = alternate
	for actor in _actors:
		actor.free()
	_actors.clear()
	var specs := [
		["male", "short_back", "", "adult", "medium", "brown", "arched", "Cropped"],
		["male", "short_back", "short_trimmed", "adult", "medium", "brown", "arched", "Short beard"],
		["female", "braid_side", "", "adult", "pale", "red", "thin_arched", "Side braid"],
		["male", "braided_back", "full_braided", "elder", "dark", "white", "bushy", "Elder / full braid"],
	]
	if alternate:
		specs = [
			["male", "wild_loose", "forked", "middle", "tan", "brown", "thick_flat", "Forked beard"],
			["female", "twin_braids", "", "young", "medium", "black", "sharp_angled", "Twin braids"],
			["male", "shaved", "braided_long", "elder", "pale", "white", "unibrow", "Long double braid"],
			["female", "loose_long", "", "middle", "dark", "red", "bushy", "Loose hair"],
		]
	for i in range(4):
		var actor := _make_actor(specs[i])
		actor.position.x = (float(i) - 1.5) * 3.7
		_lineup.add_child(actor)
		_actors.append(actor)
		_labels[i].text = specs[i][7]
	_set_view(_view)


func _process(delta: float) -> void:
	if _walking:
		for actor in _actors:
			actor.call("_walk_bob", delta * 2.2)


func _reset_pose() -> void:
	for actor in _actors:
		actor.call("_reset_part_offsets")


func _validate_registry() -> void:
	var pools := DwarfAssets.get_appearance_pools()
	var count := 0
	for gender in ["male", "female"]:
		var beards := [""]
		if gender == "male":
			for entry in pools[gender]["beard"]["styles"]:
				beards.append(entry["id"])
		for age in DwarfAssets.heads:
			for hair in pools[gender]["hair_style"]:
				for brow in pools[gender]["eyebrow_style"]:
					for beard in beards:
						var actor := _make_actor([gender, hair["id"], beard, age,
							"medium", "brown", brow["id"]])
						for part in ["MeshHead", "MeshBody", "MeshHandL", "MeshHandR", "MeshFootL", "MeshFootR",
							"MeshHead/MeshEyes", "MeshHead/MeshBrows"]:
							assert(actor.has_node(part), "Missing " + part)
						assert(actor.has_node("MeshHead/MeshHair") == (hair["id"] != "bald"))
						assert(actor.has_node("MeshHead/MeshBeard") == (beard != ""))
						assert(actor.get_node("MeshFootR").scale.x == -1.0)
						assert(actor.get_node("LogicalBox").shape.size == Vector3(1, 3, 1))
						actor.free()
						count += 1
	assert(count == 800)
	print("DWARF_ROSTER_ASSEMBLY_OK: ", count)


func _snapshot(capture_name: String) -> void:
	for i in range(3):
		await RenderingServer.frame_post_draw
	var result := get_viewport().get_texture().get_image().save_png(
		"res://tmp/dwarf_roster/renders/" + capture_name + ".png")
	assert(result == OK)
	print("CAPTURED ", capture_name)


func _capture_all() -> void:
	_validate_registry()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tmp/dwarf_roster/renders"))
	for view_name in ["Three-quarter", "Side", "RTS", "Rear"]:
		_set_view(view_name)
		await _snapshot("live_" + view_name.to_lower().replace("-", "_"))
	_set_lineup(true)
	_set_view("Three-quarter")
	await _snapshot("live_variants")
	_set_view("Rear")
	await _snapshot("live_variants_rear")
	_set_view("Three-quarter")
	_walking = true
	for i in range(30):
		await get_tree().process_frame
	await _snapshot("live_walk")
	_walking = false
	_reset_pose()
	var item := load("res://assets/models/items/stone/rough_stone.glb") as PackedScene
	for actor in _actors:
		var drop := item.instantiate() as Node3D
		actor.add_child(drop)
		actor._carry_pose.hold([[drop, ""]])
		_tint(drop, Color.WHITE)
	await _snapshot("live_carry")
	_set_view("Side")
	await _snapshot("live_carry_side")
	print("DWARF_ROSTER_PREVIEW_OK")
	get_tree().quit(0)
