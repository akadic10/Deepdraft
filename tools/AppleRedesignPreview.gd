extends "TreeRedesignPreview.gd"

## Four seasons plus the separate fruit-bearing autumn state.
## Reuses the oak/pine study's lighting, scale figures and material setup.
var _label_count := 2


func _ready() -> void:
	_build_stage()
	_build_ui()
	_set_mode("Blossom & fruit")
	if "--capture" in OS.get_cmdline_user_args():
		_capture.call_deferred()


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
	for mode in ["Seasons", "Blossom & fruit", "Summer & winter", "Harvest states", "Before / after", "Species scale", "Orchard"]:
		var button := Button.new()
		button.text = mode
		button.pressed.connect(_set_mode.bind(mode))
		controls.add_child(button)
	for view_name in ["Three-quarter", "RTS", "Rear", "Front"]:
		var button := Button.new()
		button.text = view_name
		button.pressed.connect(_set_view.bind(view_name))
		controls.add_child(button)
	_label(layer, _footer, Vector2.ZERO, 17)
	for i in range(4):
		var label := Label.new()
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label(layer, label, Vector2.ZERO, 22)
		_labels.append(label)
	get_viewport().size_changed.connect(_place_labels)


func _apple(season: String, at: Vector3, turn: float = 25, reference: bool = false, dwarf: bool = true) -> void:
	var group := Node3D.new()
	_actors.add_child(group)
	_trees.append(group)
	group.position = at
	group.rotation_degrees.y = turn
	var folder := "reference/" if reference else "models/"
	var suffix := "" if season == "summer" else "_"+season
	_part(group, "res://"+folder+"apple_mature"+suffix+".glb")
	if dwarf:
		_dwarf(_actors, at+Vector3(8, 0, 6))


func _set_mode(mode: String) -> void:
	_mode = mode
	_trees.clear()
	for child in _actors.get_children():
		child.free()
	for label in _labels:
		label.text = ""
	_title.text = "DEEPDRAFT   /   APPLE ORCHARD STUDY"
	_subtitle.text = "Mature apple · 1 voxel per block · 12-block leafy height · shared branches across all four seasons"
	_footer.text = "Isolated art review · Actual world scale, with 3.375-block dwarfs · Same material and lighting as the oak/pine study"
	_label_count = 2
	match mode:
		"Seasons":
			_label_count = 4
			var seasons := ["spring", "summer", "autumn_fruiting", "winter"]
			for i in range(4):
				_apple(seasons[i], Vector3((i-1.5)*19, 0, 0))
				_labels[i].text = ["SPRING / blossom", "SUMMER / leaf", "AUTUMN / fruit", "WINTER / bare"][i]
		"Before / after":
			_label_count = 4
			for i in range(4):
				_apple("summer" if i < 2 else "autumn_fruiting", Vector3((i-1.5)*19, 0, 0), 25, i%2 == 0)
				_labels[i].text = ["SUMMER / current", "SUMMER / prototype", "FRUIT / current", "FRUIT / prototype"][i]
			_subtitle.text = "Before / after · Identical world scale, camera and lighting · Current models retain their actual color interpretation"
		"Species scale":
			_label_count = 3
			_apple("autumn_fruiting", Vector3(-22, 0, 0))
			_tree("oak", false, Vector3(0, 0, 0), 25)
			_tree("pine", false, Vector3(22, 0, 0), 25)
			for i in range(3):
				_labels[i].text = ["APPLE / 12 blocks", "OAK / 17 blocks", "PINE / 20 blocks"][i]
			_subtitle.text = "Species silhouettes · New apple prototype beside the imported oak and pine · Unchanged world scale"
		"Orchard":
			for spec in [[-16, -8, 25], [0, -13, 110], [15, -6, 200], [-12, 13, 280], [10, 13, 45]]:
				_apple("autumn_fruiting", Vector3(spec[0], 0, spec[1]), spec[2], false, false)
			for spec in [[-3, 5, 20], [0, 3, 10], [2, 9, -25], [-5, -5, 40]]:
				_dwarf(_actors, Vector3(spec[0], 0, spec[1]), spec[2])
			_subtitle.text = "Fruiting orchard · Perspective FOV 45° · Camera distance 85 blocks / elevation 50° · Repeated prototype from multiple sides"
			_footer.text = "Fruit visibility at gameplay zoom"
		_:
			var seasons := ["spring", "autumn_fruiting"]
			var labels := ["SPRING / blossom", "AUTUMN / fruit"]
			if mode == "Summer & winter":
				seasons = ["summer", "winter"]
				labels = ["SUMMER / leaf", "WINTER / bare"]
			elif mode == "Harvest states":
				seasons = ["autumn_fruiting", "autumn"]
				labels = ["AUTUMN / with fruit", "AUTUMN / without fruit"]
				_subtitle.text = "Fruit-state comparison · Removing fruit retains every branch and leaf cube"
			for i in range(2):
				_apple(seasons[i], Vector3((i-.5)*22, 0, 0))
				_labels[i].text = labels[i]
	_set_view(_view)


func _set_view(view_name: String) -> void:
	_view = view_name
	var orchard := _mode == "Orchard"
	var elevation := 50.0 if view_name == "RTS" or orchard else 28.0
	if view_name == "Front" and not orchard:
		elevation = 12
	var target := Vector3(0, 6, 0)
	_camera.projection = Camera3D.PROJECTION_PERSPECTIVE if orchard else Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 29 if _label_count == 2 else 51
	if _mode == "Species scale":
		_camera.size = 45
		target.y = 8
	var yaw := deg_to_rad(32.0) if orchard else 0.0
	_camera.position = target+Vector3(sin(yaw)*cos(deg_to_rad(elevation)), sin(deg_to_rad(elevation)), cos(yaw)*cos(deg_to_rad(elevation)))*85
	_camera.look_at(target)
	if not orchard:
		for tree in _trees:
			tree.rotation_degrees.y = 145 if view_name == "Rear" else (0 if view_name == "Front" else 25)
	_place_labels()


func _place_labels() -> void:
	var size := get_viewport().get_visible_rect().size
	for i in range(_labels.size()):
		_labels[i].position = Vector2(size.x*(i+.5)/_label_count-190, size.y-94)
		_labels[i].size = Vector2(380, 30)
	_footer.position = Vector2(28, size.y-42)


func _capture() -> void:
	for spec in [["Seasons", "seasons"], ["Blossom & fruit", "blossom_fruit"], ["Summer & winter", "summer_winter"], ["Harvest states", "harvest_states"]]:
		_set_mode(spec[0])
		for view_name in ["Three-quarter", "RTS", "Rear"]:
			_set_view(view_name)
			await _shot(spec[1]+"_"+view_name.to_lower().replace("-", "_"))
	_set_view("Three-quarter")
	_set_mode("Before / after")
	await _shot("comparison")
	_set_mode("Species scale")
	await _shot("species_scale")
	_set_mode("Orchard")
	await _shot("orchard_gameplay")
	print("APPLE_REDESIGN_REVIEW_OK")
	get_tree().quit(0)
