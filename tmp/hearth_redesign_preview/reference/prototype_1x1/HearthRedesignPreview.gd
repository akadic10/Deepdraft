extends "TreeRedesignPreview.gd"

var _hearth_mode := "Comparison"
var _angle := "Three-quarter"

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
	for mode in ["Comparison","Dwarf scale","Tavern context","Prototype"]:
		var button := Button.new()
		button.text = mode
		button.pressed.connect(func(): _show(mode,_angle))
		controls.add_child(button)
	for angle in ["Three-quarter","RTS","Rear"]:
		var button := Button.new()
		button.text = angle
		button.pressed.connect(func(): _show(_hearth_mode,angle))
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
	_hearth_mode = mode
	_angle = angle
	for child in _actors.get_children():
		child.free()
	for label in _labels:
		label.text = ""
	_title.text = "DEEPDRAFT   /   HEARTH STUDY"
	_subtitle.text = "Raised dressed stone · recessed coals and iron grate · compact three-tongue flame"
	_footer.text = "8 voxels per block · 1 × 1 footprint · 1-block total height · mesh only, rendered with the game's lit vertex-color material"
	var target := Vector3(0,.35,0)
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 2.0
	var elevation := 32.0 if angle == "Three-quarter" else 50.0
	var yaw := 30.0 if angle != "Rear" else 205.0
	if mode == "Comparison":
		_prop("res://reference/hearth.glb",Vector3(-.9,0,0))
		_prop("res://models/hearth.glb",Vector3(.9,0,0))
		_camera.size = 4.1
		yaw = 0
		_labels[0].text = "CURRENT / 0.25 blocks tall"
		_labels[1].text = "PROPOSED / 1 block tall"
		_subtitle.text = "Current and proposed · identical world scale and lighting · existing 1 × 1 × 1 placement envelope"
	elif mode == "Dwarf scale":
		_prop("res://reference/hearth.glb",Vector3(-2.3,0,0))
		_prop("res://models/hearth.glb",Vector3(2.3,0,0))
		_dwarf(_actors,Vector3(-3.7,0,0),15)
		_dwarf(_actors,Vector3(.9,0,0),15)
		_camera.size = 10.3
		target = Vector3(-.45,1.0,0)
		yaw = 0
		_labels[0].text = "CURRENT / actual dwarf scale"
		_labels[1].text = "PROPOSED / actual dwarf scale"
		_subtitle.text = "Both dwarves are 3.375 blocks tall · hearths and characters use the same 8-voxel block scale"
	elif mode == "Tavern context":
		_prop("res://models/hearth.glb",Vector3.ZERO)
		_prop("res://context/bench.glb",Vector3(-2,0,.8),90)
		_prop("res://context/bench.glb",Vector3(2,0,.8),90)
		_prop("res://context/tavern_bar.glb",Vector3(0,0,-3.6))
		_prop("res://context/barrel.glb",Vector3(2.3,0,-3.8))
		_dwarf(_actors,Vector3(-1.5,0,-1.5),-25)
		_dwarf(_actors,Vector3(3.5,0,-.9),75)
		_camera.size = 10.6
		target = Vector3(0,.7,-.4)
		elevation = 50
		_subtitle.text = "Proposed hearth with current tavern furniture · actual asset sizes · RTS elevation 50°"
	else:
		_prop("res://models/hearth.glb",Vector3.ZERO)
		_subtitle.text = "Proposed hearth · " + angle + " · flat voxel faces and broad material regions"
	var dir := Vector3(sin(deg_to_rad(yaw))*cos(deg_to_rad(elevation)),sin(deg_to_rad(elevation)),cos(deg_to_rad(yaw))*cos(deg_to_rad(elevation)))
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
	for spec in [["Comparison","Three-quarter","comparison"],["Comparison","RTS","comparison_rts"],
		["Dwarf scale","Three-quarter","dwarf_scale"],["Dwarf scale","RTS","dwarf_scale_rts"],
		["Prototype","Three-quarter","prototype"],["Prototype","RTS","prototype_rts"],
		["Prototype","Rear","prototype_rear"],["Tavern context","RTS","tavern_context"]]:
		_show(spec[0],spec[1])
		await _shot(spec[2])
	print("HEARTH_REDESIGN_REVIEW_OK")
	get_tree().quit()
