extends "TavernRedesignPreview.gd"

func _ready() -> void:
	_build_stage()
	_build_ui()
	_show("Chair","Three-quarter")
	if "--capture" in OS.get_cmdline_user_args():
		_capture.call_deferred()

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_label(layer,_title,Vector2(28,20),28)
	_label(layer,_subtitle,Vector2(28,61),19)
	var controls := HBoxContainer.new()
	controls.position = Vector2(28,102)
	controls.add_theme_constant_override("separation",8)
	controls.visible = not "--capture" in OS.get_cmdline_user_args()
	layer.add_child(controls)
	for mode in ["Chair","Dwarf scale","Table comparison","Dining arrangement"]:
		var button := Button.new()
		button.text = mode
		button.pressed.connect(func(): _show(mode,_angle))
		controls.add_child(button)
	for angle in ["Three-quarter","Front","RTS","Rear"]:
		var button := Button.new()
		button.text = angle
		button.pressed.connect(func(): _show(_tavern_mode,angle))
		controls.add_child(button)
	_label(layer,_footer,Vector2.ZERO,17)
	get_viewport().size_changed.connect(_place_labels)

func _show(mode: String,angle: String) -> void:
	_tavern_mode = mode
	_angle = angle
	for child in _actors.get_children():
		child.free()
	_title.text = "DEEPDRAFT   /   STANDALONE OAK CHAIR"
	_subtitle.text = "Framed oak back · worn seat · stout legs · solid arms · dark iron fittings"
	_footer.text = "8 voxels per block · 1 × 1 footprint · 2-block back / 1-block seat rim · Built and placed independently"
	var target := Vector3(0,1,0)
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 3.65
	var elevation := 24.0
	var yaw := 30.0
	if angle=="RTS":
		elevation = 50
	elif angle=="Rear":
		yaw = 205
	elif angle=="Front":
		yaw = 0
		elevation = 14
	if mode=="Dwarf scale":
		_prop("res://models/wooden_chair.glb",Vector3(1.2,0,0),15)
		_dwarf(_actors,Vector3(-1.1,0,0),15)
		_prop("res://context/packed_furniture.glb",Vector3(.4,0,1.5))
		_camera.size = 7.1
		target = Vector3(.1,1.35,0)
		yaw = 0
		_subtitle.text = "Standing dwarf and chair at actual scale · shared packed crate · sitting animation is future work"
	elif mode=="Table comparison":
		_prop("res://context/wooden_table.glb",Vector3(-1.7,0,0))
		_prop("res://models/wooden_chair.glb",Vector3(1.1,0,.1),15)
		_prop("res://context/bench.glb",Vector3(2.9,0,1.6),15)
		_camera.size = 8.4
		target = Vector3(.35,.9,.2)
		yaw = 10
		_subtitle.text = "Three separate build items · tabletop 1.5 blocks · chair and bench seat rims 1 block"
	elif mode=="Dining arrangement":
		_prop("res://context/wooden_table.glb",Vector3.ZERO)
		for x in [-.5,.5]:
			_prop("res://models/wooden_chair.glb",Vector3(x,0,-1.5))
			_prop("res://models/wooden_chair.glb",Vector3(x,0,1.5),180)
		_camera.size = 7.1
		target.y = .6
		elevation = 50
		_subtitle.text = "Example layout only: one table and four independently placed chairs on adjacent grid cells"
	else:
		_prop("res://models/wooden_chair.glb",Vector3.ZERO)
		_subtitle.text += " · "+angle
	var dir := Vector3(sin(deg_to_rad(yaw))*cos(deg_to_rad(elevation)),sin(deg_to_rad(elevation)),cos(deg_to_rad(yaw))*cos(deg_to_rad(elevation)))
	_camera.position = target+dir*15
	_camera.look_at(target)
	_place_labels()

func _capture() -> void:
	for spec in [["Chair","Three-quarter","chair"],["Chair","Front","chair_front"],
		["Chair","RTS","chair_rts"],["Chair","Rear","chair_rear"],
		["Dwarf scale","Three-quarter","dwarf_scale"],["Table comparison","Three-quarter","table_comparison"],
		["Dining arrangement","RTS","dining_arrangement"]]:
		_show(spec[0],spec[1])
		await _shot(spec[2])
	print("CHAIR_REVIEW_OK")
	get_tree().quit(0)
