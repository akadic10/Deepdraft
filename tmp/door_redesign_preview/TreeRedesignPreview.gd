extends Node3D

## Isolated art study, copied into tmp/tree_redesign_preview by the generator.
## Run normally for interactive review, or with -- --capture for screenshots.
var _camera: Camera3D
var _actors := Node3D.new()
var _trees: Array[Node3D] = []
var _floor: MeshInstance3D
var _title := Label.new()
var _subtitle := Label.new()
var _footer := Label.new()
var _labels: Array[Label] = []
var _mode := "Summer"
var _view := "Three-quarter"
var _correct_reference := false


func _ready() -> void:
	_build_stage()
	_build_ui()
	_set_mode("Summer")
	if "--capture" in OS.get_cmdline_user_args():
		_capture.call_deferred()


func _build_stage() -> void:
	add_child(_actors)
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(.69, .71, .69)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(.95, .97, 1)
	env.ambient_light_energy = .4
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = env
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -32, 0)
	sun.light_color = Color(1, .95, .87)
	sun.light_energy = .7
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 180
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-25, 125, 0)
	fill.light_color = Color(.8, .88, 1)
	fill.light_energy = .15
	add_child(fill)
	_floor = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(500, .15, 500)
	_floor.mesh = box
	_floor.position.y = -.08
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(.50, .55, .51)
	mat.roughness = 1
	_floor.material_override = mat
	add_child(_floor)
	_camera = Camera3D.new()
	_camera.current = true
	_camera.far = 250
	_camera.fov = 45
	add_child(_camera)


func _label(layer: CanvasLayer, label: Label, at: Vector2, size: int) -> void:
	label.position = at
	label.add_theme_color_override("font_color", Color(.12, .15, .16))
	label.add_theme_font_size_override("font_size", size)
	layer.add_child(label)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_label(layer, _title, Vector2(28, 20), 28)
	_label(layer, _subtitle, Vector2(28, 58), 18)
	var controls := HBoxContainer.new()
	controls.position = Vector2(28, 96)
	controls.add_theme_constant_override("separation", 8)
	controls.visible = not "--capture" in OS.get_cmdline_user_args()
	layer.add_child(controls)
	for mode in ["Summer", "Winter", "Before / after", "Winter comparison", "Grove", "Winter grove"]:
		var button := Button.new()
		button.text = mode
		button.pressed.connect(_set_mode.bind(mode))
		controls.add_child(button)
	for view_name in ["Three-quarter", "RTS", "Rear"]:
		var button := Button.new()
		button.text = view_name
		button.pressed.connect(_set_view.bind(view_name))
		controls.add_child(button)
	var correct := CheckButton.new()
	correct.text = "Correct old colors"
	correct.toggled.connect(func(value: bool): _correct_reference = value; _set_mode(_mode))
	controls.add_child(correct)
	_label(layer, _footer, Vector2.ZERO, 17)
	for i in range(4):
		var label := Label.new()
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label(layer, label, Vector2.ZERO, 22)
		_labels.append(label)
	get_viewport().size_changed.connect(_place_labels)


func _tint(node: Node, color: Color, srgb: bool = false) -> void:
	if node is MeshInstance3D:
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.vertex_color_is_srgb = srgb
		mat.albedo_color = color
		mat.roughness = 1
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		node.material_override = mat
	for child in node.get_children():
		_tint(child, color, srgb)


func _part(parent: Node3D, path: String, color: Color = Color.WHITE, mirror: bool = false, srgb: bool = false) -> Node3D:
	var packed := load(path) as PackedScene
	assert(packed != null, "Cannot load " + path)
	var node := packed.instantiate() as Node3D
	parent.add_child(node)
	if mirror:
		node.scale.x = -1
	_tint(node, color, srgb)
	return node


func _dwarf(parent: Node3D, at: Vector3, turn: float = 0) -> void:
	var dwarf := Node3D.new()
	parent.add_child(dwarf)
	dwarf.position = at
	dwarf.rotation_degrees.y = turn
	var skin := Color(.85, .65, .50)
	var hair := Color(.42, .26, .14)
	_part(dwarf, "res://dwarves/head_adult.glb", skin)
	_part(dwarf, "res://dwarves/body_base.glb")
	_part(dwarf, "res://dwarves/eyes.glb", Color(.25, .55, .85))
	_part(dwarf, "res://dwarves/brows_m_arched.glb", hair)
	_part(dwarf, "res://dwarves/hair_m_short_back.glb", hair)
	_part(dwarf, "res://dwarves/beard_short_trimmed.glb", hair)
	for mirror in [false, true]:
		_part(dwarf, "res://dwarves/hand.glb", skin, mirror)
		_part(dwarf, "res://dwarves/foot.glb", Color.WHITE, mirror)


func _tree(species: String, winter: bool, at: Vector3, turn: float, reference: bool = false, dwarf: bool = true) -> void:
	var group := Node3D.new()
	_actors.add_child(group)
	_trees.append(group)
	group.position = at
	group.rotation_degrees.y = turn
	var folder := "reference/" if reference else "models/"
	var suffix := "_winter" if winter else ""
	_part(group, "res://" + folder + species + "_mature" + suffix + ".glb", Color.WHITE, false, reference and _correct_reference)
	if dwarf:
		_dwarf(_actors, at + Vector3(8, 0, 6))


func _set_mode(mode: String) -> void:
	_mode = mode
	_trees.clear()
	for child in _actors.get_children():
		child.free()
	for label in _labels:
		label.text = ""
	var winter := mode in ["Winter", "Winter comparison", "Winter grove"]
	var comparison := mode in ["Before / after", "Winter comparison"]
	var grove := mode in ["Grove", "Winter grove"]
	_title.text = "DEEPDRAFT   /   OAK + PINE STUDY"
	_subtitle.text = "Mature prototypes · 1 voxel per block · oak 17 blocks / pine 20 blocks · dwarfs at their actual 3.375-block scale"
	_footer.text = "Isolated art review · Summer and winter share their structure · Flat voxel faces and the game's vertex-color material"
	if grove:
		for spec in [["oak", -16, -8, 20], ["pine", 2, -16, 90], ["pine", 18, -5, 180], ["oak", 9, 13, 100], ["pine", -13, 13, 275]]:
			_tree(spec[0], winter, Vector3(spec[1], 0, spec[2]), spec[3], false, false)
		for spec in [[-3, 5, 20], [0, 3, 10], [2, 9, -25], [-5, -5, 40]]:
			_dwarf(_actors, Vector3(spec[0], 0, spec[1]), spec[2])
		_subtitle.text = "Mixed grove · perspective FOV 45° · camera distance 85 blocks / elevation 50° · actual asset scale"
		_footer.text = "Winter" if winter else "Summer"
	elif comparison:
		for i in range(4):
			var species := "oak" if i < 2 else "pine"
			_tree(species, winter, Vector3((i-1.5)*21, 0, 0), 25, i%2 == 0)
			_labels[i].text = species.to_upper() + (" / current" if i%2 == 0 else " / prototype")
		_subtitle.text = "Before / after · identical world scale, camera and lighting · " + ("winter" if winter else "summer")
		_footer.text = "Old palette preview corrected to sRGB; geometry unchanged" if _correct_reference else "Current references retain their actual in-game color interpretation"
	else:
		_tree("oak", winter, Vector3(-11, 0, 0), 25)
		_tree("pine", winter, Vector3(11, 0, 0), 25)
		_labels[0].text = "OAK / " + ("winter" if winter else "summer")
		_labels[1].text = "PINE / " + ("winter" if winter else "summer")
	_set_view(_view)


func _set_view(view_name: String) -> void:
	_view = view_name
	var grove := _mode in ["Grove", "Winter grove"]
	var comparison := _mode in ["Before / after", "Winter comparison"]
	var elevation := 50.0 if view_name == "RTS" or grove else 28.0
	var target := Vector3(0, 8, 0)
	_camera.projection = Camera3D.PROJECTION_PERSPECTIVE if grove else Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 55 if comparison else 35
	var distance := 85.0
	var yaw := deg_to_rad(32.0) if grove else 0.0
	_camera.position = target + Vector3(sin(yaw)*cos(deg_to_rad(elevation)), sin(deg_to_rad(elevation)), cos(yaw)*cos(deg_to_rad(elevation)))*distance
	_camera.look_at(target)
	if not grove:
		for actor in _trees:
			actor.rotation_degrees.y = 145 if view_name == "Rear" else 25
	_place_labels()


func _place_labels() -> void:
	var size := get_viewport().get_visible_rect().size
	var count := 4 if _mode in ["Before / after", "Winter comparison"] else 2
	for i in range(_labels.size()):
		_labels[i].position = Vector2(size.x*(i+.5)/count-190, size.y-94)
		_labels[i].size = Vector2(380, 30)
	_footer.position = Vector2(28, size.y-42)


func _shot(file: String) -> void:
	for i in range(5):
		await RenderingServer.frame_post_draw
	var error := get_viewport().get_texture().get_image().save_png("res://renders/"+file+".png")
	assert(error == OK, "Capture failed: " + file)
	print("TREE_CAPTURED ", file)


func _capture() -> void:
	for season in ["Summer", "Winter"]:
		_set_mode(season)
		for view_name in ["Three-quarter", "RTS", "Rear"]:
			_set_view(view_name)
			await _shot(season.to_lower()+"_"+view_name.to_lower().replace("-", "_"))
	_set_view("Three-quarter")
	_set_mode("Before / after")
	await _shot("comparison_summer")
	_correct_reference = true
	_set_mode("Before / after")
	await _shot("comparison_color_corrected")
	_correct_reference = false
	_set_mode("Winter comparison")
	await _shot("comparison_winter")
	_set_mode("Grove")
	await _shot("grove_summer")
	_set_mode("Winter grove")
	await _shot("grove_winter")
	print("TREE_REDESIGN_REVIEW_OK")
	get_tree().quit(0)
