extends "TreeRedesignPreview.gd"

var _tavern_mode := "Bar comparison"
var _angle := "Three-quarter"

func _ready() -> void:
	_build_stage()
	_build_ui()
	_show(_tavern_mode,_angle)
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
	for mode in ["Bar comparison","Bench comparison","Dwarf scale","Tavern context","Bar","Bench"]:
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

func _prop(path: String,at: Vector3,turn: float = 0) -> Node3D:
	var node := _part(_actors,path)
	node.position = at
	node.rotation_degrees.y = turn
	return node

func _show(mode: String,angle: String) -> void:
	_tavern_mode = mode
	_angle = angle
	for child in _actors.get_children():
		child.free()
	for label in _labels:
		label.text = ""
	_title.text = "DEEPDRAFT   /   TAVERN OAK + IRON"
	_subtitle.text = "Framed oak panels · thick counter slab · iron footrail · twin taps · braced bench"
	_footer.text = "8 voxels per block · Both footprints stay 2 × 1 · Bar 2 blocks tall including taps / bench 1 block tall"
	var target := Vector3(0,1,0)
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 4.2
	var elevation := 28.0 if angle == "Three-quarter" else 50.0
	var yaw := 30.0 if angle != "Rear" else 205.0
	if mode == "Bar comparison" or mode == "Bench comparison":
		var file := "tavern_bar" if mode == "Bar comparison" else "bench"
		_prop("res://reference/"+file+".glb",Vector3(-1.8,0,0),25)
		_prop("res://models/"+file+".glb",Vector3(1.8,0,0),25)
		_camera.size = 7.5
		yaw = 0
		target.y = .85 if file == "tavern_bar" else .4
		_labels[0].text = "CURRENT / "+file.replace("_"," ").to_upper()
		_labels[1].text = "REDESIGN / "+file.replace("_"," ").to_upper()
		_subtitle.text = "Identical world scale and lighting · current asset retains its in-game color interpretation"
	elif mode == "Dwarf scale":
		_prop("res://models/tavern_bar.glb",Vector3(-1.1,0,0),15)
		_prop("res://models/bench.glb",Vector3(1.8,0,1.3),15)
		_dwarf(_actors,Vector3(1.5,0,-1.2),15)
		_camera.size = 7.7
		target = Vector3(.3,1.25,0)
		yaw = 0
		_subtitle.text = "Approved dwarf at 3.375 blocks · countertop 1.5 blocks · all assets at actual scale"
	elif mode == "Tavern context":
		_prop("res://context/hearth.glb",Vector3.ZERO)
		_prop("res://models/bench.glb",Vector3(-3,0,1.2),90)
		_prop("res://models/bench.glb",Vector3(3,0,1.2),90)
		_prop("res://models/tavern_bar.glb",Vector3(0,0,-4.6))
		_prop("res://context/barrel.glb",Vector3(2.3,0,-4.8))
		_dwarf(_actors,Vector3(-2.5,0,-2.0),-25)
		_dwarf(_actors,Vector3(4,0,-1.8),75)
		_camera.size = 13
		target = Vector3(0,.7,-.4)
		elevation = 50
		_subtitle.text = "New bar and benches with the installed 2 × 2 hearth · actual sizes · RTS elevation 50°"
	else:
		_prop("res://models/"+("tavern_bar" if mode == "Bar" else "bench")+".glb",Vector3.ZERO)
		target.y = .85 if mode == "Bar" else .4
		_camera.size = 3.6 if mode == "Bar" else 3.4
		_subtitle.text = mode+" · "+angle+" · solid oak construction and dark iron fittings"
	var dir := Vector3(sin(deg_to_rad(yaw))*cos(deg_to_rad(elevation)),sin(deg_to_rad(elevation)),cos(deg_to_rad(elevation))*cos(deg_to_rad(yaw)))
	_camera.position = target+dir*15
	_camera.look_at(target)
	_place_labels()

func _place_labels() -> void:
	var size := get_viewport().get_visible_rect().size
	for i in range(_labels.size()):
		_labels[i].position = Vector2(size.x*(i+.5)/2-250,size.y-97)
		_labels[i].size = Vector2(500,30)
	_footer.position = Vector2(28,size.y-42)

func _capture() -> void:
	for spec in [["Bar comparison","Three-quarter","bar_comparison"],
		["Bench comparison","Three-quarter","bench_comparison"],
		["Dwarf scale","Three-quarter","dwarf_scale"],["Dwarf scale","RTS","dwarf_scale_rts"],
		["Bar","Three-quarter","bar"],["Bar","RTS","bar_rts"],["Bar","Rear","bar_rear"],
		["Bench","Three-quarter","bench"],["Bench","Rear","bench_rear"],
		["Tavern context","RTS","tavern_context"]]:
		_show(spec[0],spec[1])
		await _shot(spec[2])
	print("TAVERN_REDESIGN_REVIEW_OK")
	get_tree().quit(0)
