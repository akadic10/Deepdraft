extends Node3D

## Isolated art review. Copied into tmp/dwarf_redesign_preview by the generator.
## No game autoloads, world generation, saves, or live registry edits.
var _camera: Camera3D
var _lineup := Node3D.new()
var _actors: Array[Node3D] = []
var _labels: Array[Label] = []
var _walking := false
var _cycle := 0.0
var _comparison := false
var _view := "Three-quarter"
var _capture := false


func _ready() -> void:
	_capture = "--capture" in OS.get_cmdline_user_args()
	_build_stage()
	_build_ui()
	_set_lineup(false)
	_set_view("Three-quarter")
	if _capture:
		_capture_all.call_deferred()


func _build_stage() -> void:
	add_child(_lineup)
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.69, 0.71, 0.69)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.95, 0.97, 1.0)
	env.ambient_light_energy = 0.40
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = env
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -32, 0)
	sun.light_color = Color(1.0, 0.95, 0.87)
	sun.light_energy = 0.70
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 110.0
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-25, 125, 0)
	fill.light_color = Color(0.80, 0.88, 1.0)
	fill.light_energy = 0.15
	add_child(fill)
	# The 1-block floor tiles expose actual world scale without touching terrain.
	for x in range(-10, 11):
		for z in range(-6, 7):
			var tile := MeshInstance3D.new()
			var mesh := BoxMesh.new()
			mesh.size = Vector3(0.99, 0.12, 0.99)
			tile.mesh = mesh
			tile.position = Vector3(x, -0.065, z)
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.54, 0.57, 0.56) if (x + z) % 2 == 0 else Color(0.52, 0.55, 0.54)
			mat.roughness = 1.0
			tile.material_override = mat
			add_child(tile)
	_camera = Camera3D.new()
	_camera.current = true
	_camera.fov = 45.0
	_camera.near = 0.05
	_camera.far = 150.0
	add_child(_camera)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var title := Label.new()
	title.text = _title_text()
	title.position = Vector2(28, 20)
	title.add_theme_color_override("font_color", Color(0.12, 0.15, 0.16))
	title.add_theme_font_size_override("font_size", 22)
	layer.add_child(title)
	var controls := HBoxContainer.new()
	controls.position = Vector2(28, 60)
	controls.add_theme_constant_override("separation", 8)
	layer.add_child(controls)
	for view_name in ["Front", "Three-quarter", "Side", "RTS", "Rear", "Gameplay"]:
		var button := Button.new()
		button.text = view_name
		button.pressed.connect(_set_view.bind(view_name))
		controls.add_child(button)
	var compare_button := Button.new()
	compare_button.text = _comparison_text()
	compare_button.pressed.connect(func(): _set_lineup(not _comparison))
	controls.add_child(compare_button)
	var walk_button := Button.new()
	walk_button.text = "Walk preview"
	walk_button.toggle_mode = true
	walk_button.toggled.connect(func(value: bool): _walking = value; _reset_pose())
	controls.add_child(walk_button)
	for i in range(4):
		var label := Label.new()
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_color_override("font_color", Color(0.12, 0.15, 0.16))
		label.add_theme_font_size_override("font_size", 18)
		layer.add_child(label)
		_labels.append(label)
	get_viewport().size_changed.connect(_place_labels)


func _title_text() -> String:
	return "Dwarf redesign study   ·   8 voxels per block   ·   prototype height: 27 voxels"


func _comparison_text() -> String:
	return "Current / prototype"


func _set_lineup(compare: bool) -> void:
	_comparison = compare
	for actor in _actors:
		_lineup.remove_child(actor)
		actor.queue_free()
	_actors.clear()
	var specs: Array = [
		[false, "cropped", false, Color(0.85, 0.65, 0.50), Color(0.42, 0.26, 0.14), "Cropped · no beard"],
		[false, "cropped", true, Color(0.85, 0.65, 0.50), Color(0.42, 0.26, 0.14), "Cropped · short beard"],
		[false, "swept_braid", false, Color(0.96, 0.84, 0.77), Color(0.78, 0.22, 0.08), "Swept braid · no beard"],
		[false, "swept_braid", true, Color(0.42, 0.28, 0.18), Color(0.92, 0.92, 0.92), "Swept braid · short beard"],
	]
	if compare:
		specs = [
			[true, "cropped", false, Color(0.85, 0.65, 0.50), Color(0.42, 0.26, 0.14), "Current · no beard"],
			[false, "cropped", false, Color(0.85, 0.65, 0.50), Color(0.42, 0.26, 0.14), "Prototype · no beard"],
			[true, "cropped", true, Color(0.85, 0.65, 0.50), Color(0.42, 0.26, 0.14), "Current · long beard"],
			[false, "cropped", true, Color(0.85, 0.65, 0.50), Color(0.42, 0.26, 0.14), "Prototype · short beard"],
		]
	for i in range(4):
		var s: Array = specs[i]
		var actor := _assemble(bool(s[0]), String(s[1]), bool(s[2]), s[3], s[4])
		actor.position.x = (float(i) - 1.5) * 3.7
		_lineup.add_child(actor)
		_actors.append(actor)
		_labels[i].text = String(s[5])
	_set_view(_view)


func _assemble(reference: bool, hair: String, beard: bool, skin: Color, hair_color: Color) -> Node3D:
	var actor := Node3D.new()
	var folder := "res://reference/" if reference else "res://models/"
	var head_group := Node3D.new()
	head_group.name = "Head"
	actor.add_child(head_group)
	_add_part(head_group, folder + "head_adult.glb", skin, "Skull")
	_add_part(head_group, folder + "eyes.glb", Color(0.25, 0.55, 0.85), "Eyes")
	_add_part(head_group, folder + ("brows_m_bushy" if reference else "brows") + ".glb", hair_color, "Brows")
	_add_part(head_group, folder + ("hair_m_short_back" if reference else "hair_" + hair) + ".glb", hair_color, "Hair")
	if beard:
		_add_part(head_group, folder + ("beard_full_long" if reference else "beard_short") + ".glb", hair_color, "Beard")
	_add_part(actor, folder + "body_base.glb", Color.WHITE, "Body")
	_add_part(actor, folder + "hand.glb", skin, "HandL")
	_add_part(actor, folder + "hand.glb", skin, "HandR", true)
	_add_part(actor, folder + "foot.glb", Color.WHITE, "FootL")
	_add_part(actor, folder + "foot.glb", Color.WHITE, "FootR", true)
	return actor


func _add_part(parent: Node3D, path: String, color: Color, part_name: String, mirror: bool = false) -> void:
	var packed := load(path) as PackedScene
	assert(packed != null, "Cannot load " + path)
	var node := packed.instantiate() as Node3D
	node.name = part_name
	if mirror:
		node.scale.x = -1.0
	parent.add_child(node)
	_tint(node, color)


func _tint(node: Node, color: Color) -> void:
	if node is MeshInstance3D:
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.albedo_color = color
		mat.roughness = 1.0
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		node.material_override = mat
	for child in node.get_children():
		_tint(child, color)


func _set_view(view_name: String) -> void:
	_view = view_name
	var elevation := 25.0
	var turn := 30.0
	match view_name:
		"Front": elevation = 0.0; turn = 0.0
		"Side": elevation = 10.0; turn = 90.0
		"RTS": elevation = 50.0; turn = 35.0
		"Rear": elevation = 30.0; turn = 145.0
		"Gameplay": elevation = 50.0; turn = 35.0
	for actor in _actors:
		actor.rotation_degrees.y = turn
	_camera.projection = Camera3D.PROJECTION_PERSPECTIVE if view_name == "Gameplay" else Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 9.0
	var distance := 85.0 if view_name == "Gameplay" else 24.0
	var target := Vector3(0, 1.6, 0)
	_camera.position = target + Vector3(0, sin(deg_to_rad(elevation)), cos(deg_to_rad(elevation))) * distance
	_camera.look_at(target, Vector3.UP)
	_place_labels()


func _place_labels() -> void:
	if _camera == null:
		return
	var size := get_viewport().get_visible_rect().size
	for i in range(_labels.size()):
		_labels[i].position = Vector2(size.x * (float(i) + 0.5) / 4.0 - 180.0, size.y - 62.0)
		_labels[i].size = Vector2(360, 30)


func _process(delta: float) -> void:
	if not _walking:
		return
	# Same distance/stride relation and part offsets as DwarfAgent's gait.
	_cycle = fposmod(_cycle + delta * 2.2 / 1.4, 1.0)
	var bounce := absf(sin(_cycle * TAU)) * 0.04
	for actor in _actors:
		_pose_foot(actor.get_node("FootR"), _cycle)
		_pose_foot(actor.get_node("FootL"), fposmod(_cycle + 0.5, 1.0))
		actor.get_node("Body").position.y = bounce
		actor.get_node("Body").rotation.x = deg_to_rad(2.5)
		actor.get_node("Head").position.y = bounce * 1.2
		actor.get_node("Head").rotation.x = deg_to_rad(1.5)
		actor.get_node("HandL").position = Vector3(0, bounce, sin(_cycle * TAU) * 0.175)
		actor.get_node("HandR").position = Vector3(0, bounce, -sin(_cycle * TAU) * 0.175)


func _pose_foot(foot: Node3D, phase: float) -> void:
	if phase < 0.5:
		foot.position = Vector3(0, sin(phase * 2.0 * PI) * 0.10, lerpf(-0.35, 0.35, phase * 2.0))
	else:
		foot.position = Vector3(0, 0, lerpf(0.35, -0.35, (phase - 0.5) * 2.0))


func _reset_pose() -> void:
	for actor in _actors:
		for child in actor.get_children():
			if child is Node3D:
				child.position = Vector3.ZERO
				child.rotation = Vector3.ZERO


func _snapshot(name: String) -> void:
	for i in range(3):
		await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png("res://renders/" + name + ".png")
	assert(error == OK, "Screenshot failed: " + str(error))
	print("CAPTURED ", name)


func _capture_all() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://renders"))
	_set_lineup(true)
	_set_view("Three-quarter")
	await _snapshot("godot_comparison")
	_set_lineup(false)
	for view_name in ["Front", "Three-quarter", "Side", "RTS", "Rear", "Gameplay"]:
		_set_view(view_name)
		await _snapshot("godot_" + view_name.to_lower().replace("-", "_"))
	_set_view("Three-quarter")
	_walking = true
	for i in range(30):
		await get_tree().process_frame
	await _snapshot("godot_walk")
	_walking = false
	_reset_pose()
	for actor in _actors:
		_lineup.remove_child(actor)
		actor.queue_free()
	_actors.clear()
	var palette := [
		[Color(0.96, 0.84, 0.77), Color(0.88, 0.76, 0.44), "Pale / blonde"],
		[Color(0.42, 0.28, 0.18), Color(0.10, 0.08, 0.08), "Dark / black"],
		[Color(0.71, 0.50, 0.35), Color(0.42, 0.26, 0.14), "Tan / brown"],
		[Color(0.96, 0.84, 0.77), Color(0.92, 0.92, 0.92), "Pale / white"],
	]
	for i in range(4):
		var actor := _assemble(false, "cropped", true, palette[i][0], palette[i][1])
		actor.position.x = (float(i) - 1.5) * 3.7
		_lineup.add_child(actor)
		_actors.append(actor)
		_labels[i].text = palette[i][2]
	_set_view("Three-quarter")
	await _snapshot("godot_palette")
	print("DWARF_REDESIGN_PREVIEW_OK")
	get_tree().quit(0)
