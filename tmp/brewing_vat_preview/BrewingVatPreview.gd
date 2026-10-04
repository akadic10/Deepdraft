extends "TavernRedesignPreview.gd"

func _ready() -> void:
	_build_stage()
	_build_ui()
	_show("Vat","Three-quarter")
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
	for mode in ["Vat","Dwarf scale","Barrel comparison","Brewing area"]:
		var button := Button.new()
		button.text = mode
		button.pressed.connect(func(): _show(mode,_angle))
		controls.add_child(button)
	for angle in ["Three-quarter","RTS","Rear","Top"]:
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
	_title.text = "DEEPDRAFT   /   DWARVEN BREWING VAT"
	_subtitle.text = "Broad oak staves · heavy iron hoops · open rim · recessed liquid · copper draw-off tap"
	_footer.text = "8 voxels per block · 2 × 2 footprint / 2 blocks tall · Placeable asset; brewing behavior is future work"
	var target := Vector3(0,1,0)
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 4.2
	var elevation := 30.0
	var yaw := 32.0
	if angle=="RTS":
		elevation = 52
	elif angle=="Rear":
		yaw = 215
	elif angle=="Top":
		elevation = 89.9
		yaw = 0
	if mode=="Dwarf scale":
		_prop("res://models/brewing_vat.glb",Vector3(1.25,0,0),-15)
		_dwarf(_actors,Vector3(-1.45,0,.2),10)
		_camera.size = 8.1
		target = Vector3(0,1.4,0)
		yaw = 0
		_subtitle.text = "Full-size 3.375-block dwarf beside the 2-block vat · tap and skids stay inside its footprint"
	elif mode=="Barrel comparison":
		_prop("res://models/brewing_vat.glb",Vector3(-1,0,0),10)
		_prop("res://context/barrel.glb",Vector3(1.3,0,.3),10)
		_prop("res://context/packed_furniture.glb",Vector3(2.2,0,.5))
		_camera.size = 6.4
		target = Vector3(.1,.8,0)
		yaw = 0
		_subtitle.text = "Brewing vat / storage barrel / shared packed crate · actual sizes · each is a separate item"
	elif mode=="Brewing area":
		_prop("res://models/brewing_vat.glb",Vector3(-1.5,0,-.5))
		_prop("res://context/storage_shelf.glb",Vector3(1.3,0,-1.5))
		_prop("res://context/barrel.glb",Vector3(1.4,0,.2))
		_prop("res://context/barrel.glb",Vector3(2.5,0,.2))
		_prop("res://context/tavern_bar.glb",Vector3(2.8,0,-2.1))
		_dwarf(_actors,Vector3(-1.3,0,1.8),-20)
		_camera.size = 10
		target = Vector3(.4,1,0)
		yaw = 0
		_subtitle.text = "Example brewing area · vat, barrels, shelf and bar are independently built furniture"
	else:
		_prop("res://models/brewing_vat.glb",Vector3.ZERO)
		_subtitle.text += " · "+angle
	var dir := Vector3(sin(deg_to_rad(yaw))*cos(deg_to_rad(elevation)),sin(deg_to_rad(elevation)),cos(deg_to_rad(yaw))*cos(deg_to_rad(elevation)))
	_camera.position = target+dir*15
	_camera.look_at(target)
	_place_labels()

func _capture() -> void:
	for spec in [["Vat","Three-quarter","vat"],["Vat","RTS","vat_rts"],
		["Vat","Rear","vat_rear"],["Vat","Top","vat_top"],
		["Dwarf scale","Three-quarter","dwarf_scale"],["Barrel comparison","Three-quarter","barrel_comparison"],
		["Brewing area","RTS","brewing_area"]]:
		_show(spec[0],spec[1])
		await _shot(spec[2])
	print("BREWING_VAT_REVIEW_OK")
	get_tree().quit(0)
