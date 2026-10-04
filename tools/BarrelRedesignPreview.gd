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
	for mode in ["Comparison","Barrel","Dwarf scale","Tavern context"]:
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
	_title.text = "DEEPDRAFT   /   OAK STORAGE BARREL"
	_subtitle.text = "Full oak staves · dark iron hoops · raised rim and recessed plank lid"
	_footer.text = "8 voxels per block · 1 × 1 footprint / 1 block tall · Existing capacity: 8 items"
	var target := Vector3(0,.5,0)
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 2.3
	var elevation := 28.0 if angle=="Three-quarter" else 50.0
	var yaw := 30.0 if angle!="Rear" else 205.0
	if mode=="Comparison":
		_prop("res://reference/barrel.glb",Vector3(-1.1,0,0),15)
		_prop("res://models/barrel.glb",Vector3(1.1,0,0),15)
		_camera.size = 4.8
		yaw = 0
		_labels[0].text = "ORIGINAL / BARREL"
		_labels[1].text = "REDESIGN / BARREL"
		_subtitle.text = "Identical scale and lighting · original retains its in-game color interpretation"
	elif mode=="Dwarf scale":
		_prop("res://models/barrel.glb",Vector3(-1.15,0,.6),15)
		_prop("res://context/tavern_bar.glb",Vector3(1.7,0,.7),15)
		_dwarf(_actors,Vector3(.25,0,-1.1),15)
		_camera.size = 7.5
		target = Vector3(.3,1.25,0)
		yaw = 0
		_subtitle.text = "New barrel with upgraded bar and 3.375-block dwarf · actual asset sizes"
	elif mode=="Tavern context":
		_prop("res://context/hearth.glb",Vector3.ZERO)
		_prop("res://context/bench.glb",Vector3(-3,0,1.2),90)
		_prop("res://context/bench.glb",Vector3(3,0,1.2),90)
		_prop("res://context/tavern_bar.glb",Vector3(0,0,-4.6))
		_prop("res://models/barrel.glb",Vector3(2.1,0,-4.4),20)
		_prop("res://models/barrel.glb",Vector3(3.3,0,-4.7),-20)
		_dwarf(_actors,Vector3(-2.5,0,-2.0),-25)
		_dwarf(_actors,Vector3(4,0,-1.8),75)
		_camera.size = 13
		target = Vector3(0,.7,-.4)
		elevation = 50
		_subtitle.text = "Upgraded tavern set · matching oak and iron · RTS elevation 50°"
	else:
		_prop("res://models/barrel.glb",Vector3.ZERO)
		_subtitle.text += " · "+angle
	var dir := Vector3(sin(deg_to_rad(yaw))*cos(deg_to_rad(elevation)),sin(deg_to_rad(elevation)),cos(deg_to_rad(yaw))*cos(deg_to_rad(elevation)))
	_camera.position = target+dir*15
	_camera.look_at(target)
	_place_labels()

func _capture() -> void:
	for spec in [["Comparison","Three-quarter","comparison"],["Comparison","RTS","comparison_rts"],
		["Barrel","Three-quarter","barrel"],["Barrel","RTS","barrel_rts"],["Barrel","Rear","barrel_rear"],
		["Dwarf scale","Three-quarter","dwarf_scale"],["Tavern context","RTS","tavern_context"]]:
		_show(spec[0],spec[1])
		await _shot(spec[2])
	print("BARREL_REDESIGN_REVIEW_OK")
	get_tree().quit(0)
