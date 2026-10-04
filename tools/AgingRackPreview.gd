extends "TavernRedesignPreview.gd"

func _ready() -> void:
	_build_stage()
	_build_ui()
	_show("Aging rack","Three-quarter")
	if "--capture" in OS.get_cmdline_user_args():
		_capture.call_deferred()

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_label(layer,_title,Vector2(28,20),28)
	_label(layer,_subtitle,Vector2(28,61),19)
	_label(layer,_footer,Vector2.ZERO,17)
	var controls := HBoxContainer.new()
	controls.position = Vector2(28,102)
	controls.add_theme_constant_override("separation",8)
	controls.visible = not "--capture" in OS.get_cmdline_user_args()
	layer.add_child(controls)
	for mode in ["Aging rack","Dwarf scale","Cellar context"]:
		var button := Button.new()
		button.text = mode
		button.pressed.connect(func(): _show(mode,_angle))
		controls.add_child(button)
	for angle in ["Three-quarter","RTS","Rear"]:
		var button := Button.new()
		button.text = angle
		button.pressed.connect(func(): _show(_tavern_mode,angle))
		controls.add_child(button)
	get_viewport().size_changed.connect(_place_labels)

func _show(mode: String,angle: String) -> void:
	_tavern_mode = mode
	_angle = angle
	for child in _actors.get_children():
		child.free()
	_title.text = "DEEPDRAFT   /   OAK AGING RACK"
	_subtitle.text = "Twin casks · recessed heads · iron hoops · braced timber cradle · batch plaque"
	_footer.text = "8 voxels per block · 2 × 2 footprint · 2 blocks tall · Independently buildable"
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 4.0
	var target := Vector3(0,.95,0)
	var elevation := 24.0 if angle=="Three-quarter" else 52.0
	var yaw := 30.0 if angle!="Rear" else 150.0
	if mode=="Dwarf scale":
		_prop("res://models/aging_rack.glb",Vector3(1.5,0,.2))
		_dwarf(_actors,Vector3(-1.2,0,0),15)
		_prop("res://context/packed_furniture.glb",Vector3(.1,0,1.65))
		_camera.size = 7.4
		target = Vector3(.2,1.4,0)
		yaw = 0
		_subtitle.text = "Two-block rack beside a full-size 3.375-block dwarf · shared packed crate"
	elif mode=="Cellar context":
		_prop("res://models/aging_rack.glb",Vector3(1.4,0,0))
		_prop("res://models/aging_rack.glb",Vector3(1.4,0,-2.5))
		_prop("res://context/brewing_vat.glb",Vector3(-1.8,0,-1.5))
		_prop("res://context/barrel.glb",Vector3(3.3,0,-1.5))
		_dwarf(_actors,Vector3(-1.6,0,1.5),15)
		_camera.size = 10.0
		target = Vector3(.3,1,-.5)
		elevation = 42
		yaw = 25
		_subtitle.text = "Aging racks with the approved brewing vat and storage barrel · actual game scale"
	else:
		_prop("res://models/aging_rack.glb",Vector3.ZERO)
		_subtitle.text += " · "+angle
	var dir := Vector3(sin(deg_to_rad(yaw))*cos(deg_to_rad(elevation)),sin(deg_to_rad(elevation)),cos(deg_to_rad(yaw))*cos(deg_to_rad(elevation)))
	_camera.position = target+dir*15
	_camera.look_at(target)
	_place_labels()

func _capture() -> void:
	for spec in [["Aging rack","Three-quarter","aging_rack"],["Aging rack","RTS","aging_rack_rts"],["Aging rack","Rear","aging_rack_rear"],["Dwarf scale","Three-quarter","dwarf_scale"],["Dwarf scale","RTS","dwarf_scale_rts"],["Cellar context","RTS","cellar_context"]]:
		_show(spec[0],spec[1])
		await _shot(spec[2])
	print("AGING_RACK_REVIEW_OK")
	get_tree().quit(0)
