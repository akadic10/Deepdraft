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
	for mode in ["Comparison","Crate","Carried scale","Stockpile"]:
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
	_title.text = "DEEPDRAFT   /   PACKED FURNITURE"
	_subtitle.text = "Framed oak planks · recessed side panels · rope bindings and raised knot"
	_footer.text = "8 voxels per block · Existing 5 × 4 × 5-cell envelope · One shared crate for all seven packed furniture types"
	var target := Vector3(.0625,.22,.0625)
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 1.65
	var elevation := 28.0 if angle=="Three-quarter" else 55.0
	var yaw := 30.0 if angle!="Rear" else 205.0
	if mode=="Comparison":
		_prop("res://reference/packed_furniture.glb",Vector3(-.8,0,0),15)
		_prop("res://models/packed_furniture.glb",Vector3(.8,0,0),15)
		_camera.size = 3.4
		yaw = 0
		_labels[0].text = "ORIGINAL / PACKED CRATE"
		_labels[1].text = "REDESIGN / PACKED CRATE"
		_subtitle.text = "Identical bounds and lighting · original retains its in-game color interpretation"
	elif mode=="Carried scale":
		_dwarf(_actors,Vector3.ZERO,0)
		# DwarfAgent.CARRY_OFFSET, at native item scale. This is a static
		# scale study using the existing carry attachment, not a new pose.
		_prop("res://models/packed_furniture.glb",Vector3(0,1.05,1.55))
		_prop("res://models/packed_furniture.glb",Vector3(1.8,0,1.3),15)
		_prop("res://context/storage_crate.glb",Vector3(2.3,0,-.3),15)
		_camera.size = 6.8
		target = Vector3(.6,1.35,.4)
		yaw = 25
		_subtitle.text = "Existing carry attachment at native scale · ground crate and installed chest for comparison"
	elif mode=="Stockpile":
		for x in range(3):
			for z in range(2):
				_prop("res://models/packed_furniture.glb",Vector3(x-1,0,z-.5))
		_prop("res://context/barrel.glb",Vector3(2.4,0,-.2),15)
		_prop("res://context/storage_crate.glb",Vector3(2.4,0,1.2),15)
		_camera.size = 6
		target = Vector3(.7,.35,.3)
		elevation = 50
		_subtitle.text = "One crate per stockpile cell · same oak palette as installed storage · actual asset sizes"
	else:
		_prop("res://models/packed_furniture.glb",Vector3.ZERO)
		_subtitle.text += " · "+angle
	var dir := Vector3(sin(deg_to_rad(yaw))*cos(deg_to_rad(elevation)),sin(deg_to_rad(elevation)),cos(deg_to_rad(yaw))*cos(deg_to_rad(elevation)))
	_camera.position = target+dir*15
	_camera.look_at(target)
	_place_labels()

func _capture() -> void:
	for spec in [["Comparison","Three-quarter","comparison"],["Comparison","RTS","comparison_rts"],
		["Crate","Three-quarter","crate"],["Crate","RTS","crate_rts"],["Crate","Rear","crate_rear"],
		["Carried scale","Three-quarter","carried_scale"],["Stockpile","RTS","stockpile"]]:
		_show(spec[0],spec[1])
		await _shot(spec[2])
	print("PACKED_FURNITURE_REDESIGN_REVIEW_OK")
	get_tree().quit(0)
