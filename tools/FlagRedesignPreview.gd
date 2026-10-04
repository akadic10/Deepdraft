extends "TavernRedesignPreview.gd"

func _ready() -> void:
	_build_stage()
	_build_ui()
	_show("Comparison","Three-quarter")
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
	for mode in ["Comparison","Flag","Dwarf scale","Camp"]:
		var button := Button.new()
		button.text = mode
		button.pressed.connect(func(): _show(mode,_angle))
		controls.add_child(button)
	for angle in ["Three-quarter","RTS","Rear"]:
		var button := Button.new()
		button.text = angle
		button.pressed.connect(func(): _show(_tavern_mode,angle))
		controls.add_child(button)
	_label(layer,_footer,Vector2.ZERO,17)
	for i in range(2):
		var label := Label.new()
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label(layer,label,Vector2.ZERO,22)
		_labels.append(label)
	get_viewport().size_changed.connect(_place_labels)

func _show(mode: String,angle: String) -> void:
	_tavern_mode = mode
	_angle = angle
	for child in _actors.get_children():
		child.free()
	for label in _labels:
		label.text = ""
	_title.text = "DEEPDRAFT   /   SETTLEMENT STANDARD"
	_subtitle.text = "Crimson cloth · gold rune · iron-bound oak · dressed-stone footing"
	_footer.text = "8 voxels per block · 1 × 1 footprint / 3 blocks tall · Existing settlement placement and occupancy"
	var target := Vector3(0,1.5,0)
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 4.7
	var elevation := 20.0 if angle=="Three-quarter" else 50.0
	var yaw := 25.0 if angle!="Rear" else 205.0
	if mode=="Comparison":
		_prop("res://reference/settlement_flag.glb",Vector3(-1.45,0,0),15)
		_prop("res://models/settlement_flag.glb",Vector3(1.45,0,0),15)
		_camera.size = 7.5
		yaw = 0
		_labels[0].text = "ORIGINAL / IN-GAME MATERIAL"
		_labels[1].text = "REDESIGN / SETTLEMENT FLAG"
		_subtitle.text = "Identical scale and lighting · original uses the placement controller's white material override"
	elif mode=="Dwarf scale":
		_prop("res://models/settlement_flag.glb",Vector3(1.2,0,0),15)
		_dwarf(_actors,Vector3(-1.2,0,0),15)
		_camera.size = 7
		target = Vector3(0,1.6,0)
		yaw = 0
		_subtitle.text = "Flag 3 blocks tall · approved dwarf 3.375 blocks · actual asset sizes"
	elif mode=="Camp":
		_prop("res://models/settlement_flag.glb",Vector3(-1.7,0,-1.5),15)
		_prop("res://context/hearth.glb",Vector3(.6,0,.6))
		_prop("res://context/storage_crate.glb",Vector3(2.2,0,-1.8),-15)
		_prop("res://context/barrel.glb",Vector3(3.3,0,-1.5),15)
		_dwarf(_actors,Vector3(-2.5,0,1.0),20)
		_camera.size = 10.5
		target = Vector3(0,1,0)
		elevation = 40
		_subtitle.text = "Settlement marker with upgraded dwarf, hearth and storage · actual asset sizes"
	else:
		_prop("res://models/settlement_flag.glb",Vector3.ZERO)
		_subtitle.text += " · "+angle
	var dir := Vector3(sin(deg_to_rad(yaw))*cos(deg_to_rad(elevation)),sin(deg_to_rad(elevation)),cos(deg_to_rad(yaw))*cos(deg_to_rad(elevation)))
	_camera.position = target+dir*15
	_camera.look_at(target)
	_place_labels()

func _capture() -> void:
	for spec in [["Comparison","Three-quarter","comparison"],["Comparison","RTS","comparison_rts"],
		["Flag","Three-quarter","flag"],["Flag","RTS","flag_rts"],["Flag","Rear","flag_rear"],
		["Dwarf scale","Three-quarter","dwarf_scale"],["Camp","RTS","camp"]]:
		_show(spec[0],spec[1])
		await _shot(spec[2])
	print("FLAG_REDESIGN_REVIEW_OK")
	get_tree().quit(0)
