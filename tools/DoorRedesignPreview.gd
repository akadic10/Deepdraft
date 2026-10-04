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
	for mode in ["Comparison","Door","Dwarf scale","Wall fit"]:
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
	_title.text = "DEEPDRAFT   /   OAK DOUBLE DOOR"
	_subtitle.text = "Heavy oak frames · recessed panels · strap hinges and paired ring pulls"
	_footer.text = "8 voxels per block · 2 × 1 footprint / 3.875 blocks tall · Walk-through and room sealing preserved"
	var target := Vector3(0,1.9,0)
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 6.8
	var elevation := 18.0 if angle=="Three-quarter" else 50.0
	var yaw := 30.0 if angle!="Rear" else 205.0
	if mode=="Comparison":
		_prop("res://reference/door.glb",Vector3(-2.1,0,0),15)
		_prop("res://models/door.glb",Vector3(2.1,0,0),15)
		_camera.size = 9.5
		yaw = 0
		_labels[0].text = "ORIGINAL / DOOR"
		_labels[1].text = "REDESIGN / DOOR"
		_subtitle.text = "Identical scale and lighting · original retains its in-game color interpretation"
	elif mode=="Dwarf scale":
		_prop("res://models/door.glb",Vector3(1.5,0,0),15)
		_dwarf(_actors,Vector3(-1.35,0,.25),15)
		_camera.size = 8
		target = Vector3(0,1.8,0)
		yaw = 0
		_subtitle.text = "Double door 3.875 blocks tall · approved dwarf 3.375 blocks · actual asset sizes"
	elif mode=="Wall fit":
		_prop("res://models/door.glb",Vector3.ZERO)
		for x in [-1.5,1.5]:
			for y in range(4):
				_wall_block(Vector3(x,y+.5,0),y)
		for x in [-1.5,-.5,.5,1.5]:
			_wall_block(Vector3(x,4.5,0),4)
		_dwarf(_actors,Vector3(-2.4,0,1.5),15)
		_prop("res://context/storage_crate.glb",Vector3(2.1,0,1.5),15)
		_prop("res://context/barrel.glb",Vector3(3.25,0,1.2),-15)
		_camera.size = 12
		target = Vector3(0,2,0)
		elevation = 28
		_subtitle.text = "Fits a 2-wide, 4-high opening · mock stone surround for scale · actual asset sizes"
	else:
		_prop("res://models/door.glb",Vector3.ZERO)
		_subtitle.text += " · "+angle
	var dir := Vector3(sin(deg_to_rad(yaw))*cos(deg_to_rad(elevation)),sin(deg_to_rad(elevation)),cos(deg_to_rad(yaw))*cos(deg_to_rad(elevation)))
	_camera.position = target+dir*15
	_camera.look_at(target)
	_place_labels()

func _capture() -> void:
	for spec in [["Comparison","Three-quarter","comparison"],["Comparison","RTS","comparison_rts"],
		["Door","Three-quarter","door"],["Door","RTS","door_rts"],["Door","Rear","door_rear"],
		["Dwarf scale","Three-quarter","dwarf_scale"],["Wall fit","RTS","wall_fit"]]:
		_show(spec[0],spec[1])
		await _shot(spec[2])
	print("DOOR_REDESIGN_REVIEW_OK")
	get_tree().quit(0)

func _wall_block(at: Vector3,row: int) -> void:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE
	node.mesh = mesh
	node.position = at
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(.52,.50,.47) if row%2==0 else Color(.48,.46,.43)
	material.roughness = 1
	node.material_override = material
	_actors.add_child(node)
