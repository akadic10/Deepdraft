extends "TavernRedesignPreview.gd"

func _ready() -> void:
	_build_stage()
	_build_ui()
	_show("Anvil","Three-quarter")
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
	for mode in ["Anvil","Dwarf scale","Workshop context"]:
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
	_title.text = "DEEPDRAFT   /   IRON ANVIL"
	_subtitle.text = "Tapered horn · worn steel face · flared feet · bolted stone pedestal"
	_footer.text = "8 voxels per block · 2 × 1 footprint · 1.5-block working height · Independently buildable"
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 3.5
	var target := Vector3(0,.72,0)
	var elevation := 24.0 if angle=="Three-quarter" else 52.0
	var yaw := -32.0 if angle!="Rear" else 150.0
	if mode=="Dwarf scale":
		_prop("res://models/anvil.glb",Vector3(1.5,0,.5))
		_dwarf(_actors,Vector3(-1.1,0,0),15)
		_prop("res://context/packed_furniture.glb",Vector3(.1,0,1.65))
		_camera.size = 7.4
		target = Vector3(.2,1.35,0)
		yaw = 0
		_subtitle.text = "1.5-block working surface beside a full-size 3.375-block dwarf"
	elif mode=="Workshop context":
		_prop("res://models/anvil.glb",Vector3.ZERO)
		_prop("res://context/storage_shelf.glb",Vector3(-2.2,0,-2))
		_prop("res://context/storage_crate.glb",Vector3(2.4,0,-1.4),15)
		_prop("res://context/barrel.glb",Vector3(2.5,0,-2.8))
		_dwarf(_actors,Vector3(.3,0,-1.8),-5)
		_camera.size = 9.2
		target = Vector3(0,1,-.5)
		elevation = 45
		yaw = -18
		_subtitle.text = "Anvil with approved storage furniture · all assets at actual game scale"
	else:
		_prop("res://models/anvil.glb",Vector3.ZERO)
		_subtitle.text += " · "+angle
	var dir := Vector3(sin(deg_to_rad(yaw))*cos(deg_to_rad(elevation)),sin(deg_to_rad(elevation)),cos(deg_to_rad(yaw))*cos(deg_to_rad(elevation)))
	_camera.position = target+dir*15
	_camera.look_at(target)
	_place_labels()

func _capture() -> void:
	for spec in [["Anvil","Three-quarter","anvil"],["Anvil","RTS","anvil_rts"],["Anvil","Rear","anvil_rear"],["Dwarf scale","Three-quarter","dwarf_scale"],["Dwarf scale","RTS","dwarf_scale_rts"],["Workshop context","RTS","workshop_context"]]:
		_show(spec[0],spec[1])
		await _shot(spec[2])
	print("ANVIL_REVIEW_OK")
	get_tree().quit(0)
