extends "TavernRedesignPreview.gd"

func _ready() -> void:
	_build_stage()
	_build_ui()
	_show("Table","Three-quarter")
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
	for mode in ["Table","Dining set","Dwarf scale","Tavern context"]:
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
	get_viewport().size_changed.connect(_place_labels)

func _dining_set(at: Vector3) -> void:
	_prop("res://models/wooden_table.glb",at)
	_prop("res://context/bench.glb",at+Vector3(0,0,1.5))
	_prop("res://context/bench.glb",at+Vector3(0,0,-1.5))

func _show(mode: String,angle: String) -> void:
	_tavern_mode = mode
	_angle = angle
	for child in _actors.get_children():
		child.free()
	_title.text = "DEEPDRAFT   /   OAK DINING TABLE"
	_subtitle.text = "Broad oak planks · braced trestles · worn edges · iron corner fittings"
	_footer.text = "8 voxels per block · 2 × 2 footprint · 1.5-block tabletop / 1-block bench seats · Actual asset sizes"
	var target := Vector3(0,.7,0)
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 4.4
	var elevation := 26.0 if angle=="Three-quarter" else 50.0
	var yaw := 32.0 if angle!="Rear" else 205.0
	if mode=="Dining set":
		_dining_set(Vector3.ZERO)
		_camera.size = 7.1
		target.y = .45
		_subtitle.text = "Matching table and benches · adjacent, grid-aligned footprints"
	elif mode=="Dwarf scale":
		_prop("res://models/wooden_table.glb",Vector3(1.2,0,0))
		_prop("res://context/bench.glb",Vector3(1.2,0,1.5))
		_dwarf(_actors,Vector3(-1.55,0,-.5),15)
		_prop("res://context/packed_furniture.glb",Vector3(-1.6,0,1.6))
		_camera.size = 8.2
		target = Vector3(.1,1.2,.2)
		yaw = 12
		_subtitle.text = "Dwarf 3.375 blocks tall · tabletop 1.5 blocks · shared packed crate at native scale"
	elif mode=="Tavern context":
		_dining_set(Vector3(-2,0,1.5))
		_prop("res://context/hearth.glb",Vector3(2,0,.5))
		_prop("res://context/tavern_bar.glb",Vector3(0,0,-3.5))
		_prop("res://context/barrel.glb",Vector3(2,0,-3.5))
		_dwarf(_actors,Vector3(-3,0,-2),20)
		_dwarf(_actors,Vector3(3.5,0,3),-35)
		_camera.size = 12.8
		target = Vector3(0,.6,0)
		elevation = 50
		_subtitle.text = "The dining hall set · table, benches, hearth, bar and barrel · RTS view"
	else:
		_prop("res://models/wooden_table.glb",Vector3.ZERO)
		_subtitle.text += " · "+angle
	var dir := Vector3(sin(deg_to_rad(yaw))*cos(deg_to_rad(elevation)),sin(deg_to_rad(elevation)),cos(deg_to_rad(yaw))*cos(deg_to_rad(elevation)))
	_camera.position = target+dir*15
	_camera.look_at(target)
	_place_labels()

func _capture() -> void:
	for spec in [["Table","Three-quarter","table"],["Table","RTS","table_rts"],["Table","Rear","table_rear"],
		["Dining set","Three-quarter","dining_set"],["Dining set","RTS","dining_set_rts"],
		["Dwarf scale","Three-quarter","dwarf_scale"],["Tavern context","RTS","tavern_context"]]:
		_show(spec[0],spec[1])
		await _shot(spec[2])
	print("DINING_TABLE_REVIEW_OK")
	get_tree().quit(0)
