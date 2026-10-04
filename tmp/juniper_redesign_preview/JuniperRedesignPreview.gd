extends "TreeRedesignPreview.gd"

var _label_count := 2


func _ready() -> void:
	_build_stage()
	_build_ui()
	_set_mode("Summer & winter")
	if "--capture" in OS.get_cmdline_user_args():
		_capture.call_deferred()


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_label(layer,_title,Vector2(28,20),28)
	_label(layer,_subtitle,Vector2(28,58),18)
	var controls := HBoxContainer.new()
	controls.position = Vector2(28,96)
	controls.add_theme_constant_override("separation",8)
	controls.visible = not "--capture" in OS.get_cmdline_user_args()
	layer.add_child(controls)
	for mode in ["Summer & winter","Before / after","Species scale","Grove","Winter grove"]:
		var button := Button.new()
		button.text = mode
		button.pressed.connect(_set_mode.bind(mode))
		controls.add_child(button)
	for view_name in ["Three-quarter","RTS","Rear","Front"]:
		var button := Button.new()
		button.text = view_name
		button.pressed.connect(_set_view.bind(view_name))
		controls.add_child(button)
	_label(layer,_footer,Vector2.ZERO,17)
	for i in range(4):
		var label := Label.new()
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label(layer,label,Vector2.ZERO,22)
		_labels.append(label)
	get_viewport().size_changed.connect(_place_labels)


func _juniper(winter: bool, at: Vector3, turn: float = 25, reference: bool = false, dwarf: bool = true) -> void:
	_tree("juniper",winter,at,turn,reference,false)
	if dwarf:
		_dwarf(_actors,at+Vector3(5,0,4))


func _set_mode(mode: String) -> void:
	_mode = mode
	_trees.clear()
	for child in _actors.get_children():
		child.free()
	for label in _labels:
		label.text = ""
	_title.text = "DEEPDRAFT   /   JUNIPER STUDY"
	_subtitle.text = "Mature prototype · Crooked wood, upright blue-green sprays and slate-blue berries · 12 blocks tall"
	_footer.text = "Summer and winter share every voxel · Existing 1 × 1 trunk footprint · Dwarfs at actual 3.375-block scale"
	_label_count = 2
	match mode:
		"Before / after":
			_label_count = 4
			for i in range(4):
				_juniper(i>=2,Vector3((i-1.5)*14,0,0),25,i%2==0)
				_labels[i].text = ["SUMMER / current","SUMMER / prototype","WINTER / current","WINTER / prototype"][i]
			_subtitle.text = "Identical world scale and lighting · Existing models retain their actual in-game color interpretation"
		"Species scale":
			_label_count = 4
			for i in range(4):
				_tree(["juniper","apple","oak","pine"][i],false,Vector3((i-1.5)*21,0,0),25)
				_labels[i].text = ["JUNIPER / 12 blocks","APPLE / 12 blocks","OAK / 17 blocks","PINE / 20 blocks"][i]
			_subtitle.text = "All four mature silhouettes · Juniper prototype beside the imported apple, oak and pine"
		"Grove", "Winter grove":
			var winter := mode == "Winter grove"
			for spec in [[-10,-7,20],[1,-13,110],[11,-5,200],[-9,9,280],[9,10,45]]:
				_juniper(winter,Vector3(spec[0],0,spec[1]),spec[2],false,false)
			for spec in [[-2,3,20],[1,5,10],[3,9,-25]]:
				_dwarf(_actors,Vector3(spec[0],0,spec[1]),spec[2])
			_subtitle.text = "Gameplay view · Perspective FOV 45° · Elevation 50° · Distance 65 blocks · Several rotations"
			_footer.text = "Winter / same structure with joined snow patches" if winter else "Summer / compact, upright evergreen"
		_:
			for i in range(2):
				_juniper(i==1,Vector3((i-.5)*16,0,0))
				_labels[i].text = ["SUMMER / berries","WINTER / snow"][i]
	_set_view(_view)


func _set_view(view_name: String) -> void:
	_view = view_name
	var grove := _mode in ["Grove","Winter grove"]
	var elevation := 50.0 if view_name == "RTS" or grove else 28.0
	if view_name == "Front" and not grove:
		elevation = 12
	var target := Vector3(0,6,0)
	_camera.projection = Camera3D.PROJECTION_PERSPECTIVE if grove else Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 25 if _label_count == 2 else 41
	if _mode == "Species scale":
		_camera.size = 57
		target.y = 8
	var yaw := deg_to_rad(32.0) if grove else 0.0
	_camera.position = target+Vector3(sin(yaw)*cos(deg_to_rad(elevation)),sin(deg_to_rad(elevation)),cos(yaw)*cos(deg_to_rad(elevation)))*65
	_camera.look_at(target)
	if not grove:
		for tree in _trees:
			tree.rotation_degrees.y = 145 if view_name == "Rear" else (0 if view_name == "Front" else 25)
	_place_labels()


func _place_labels() -> void:
	var size := get_viewport().get_visible_rect().size
	for i in range(_labels.size()):
		_labels[i].position = Vector2(size.x*(i+.5)/_label_count-190,size.y-94)
		_labels[i].size = Vector2(380,30)
	_footer.position = Vector2(28,size.y-42)


func _capture() -> void:
	_set_mode("Summer & winter")
	for view_name in ["Three-quarter","RTS","Rear","Front"]:
		_set_view(view_name)
		await _shot("pair_"+view_name.to_lower().replace("-","_"))
	_set_view("Three-quarter")
	_set_mode("Before / after")
	await _shot("comparison")
	_set_mode("Species scale")
	await _shot("species_scale")
	_set_mode("Grove")
	await _shot("grove_gameplay")
	_set_mode("Winter grove")
	await _shot("grove_winter_gameplay")
	print("JUNIPER_REDESIGN_REVIEW_OK")
	get_tree().quit(0)
