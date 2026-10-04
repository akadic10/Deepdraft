extends "HearthRedesignPreview.gd"

const Lighting = preload("FurnitureLighting.gd")
var _hearth_def: Dictionary
var _env: Environment
var _studio_lights: Array[DirectionalLight3D] = []

func _ready() -> void:
	# Standalone review manifest; gameplay uses the furniture controller's data.
	_hearth_def = JSON.parse_string(FileAccess.get_file_as_string("res://hearth.json"))
	_build_stage()
	for child in get_children():
		if child is WorldEnvironment:
			_env = child.environment
		elif child is DirectionalLight3D:
			_studio_lights.append(child)
	_build_ui()
	_show("Hearth", "Three-quarter")
	if "--movie" in OS.get_cmdline_user_args():
		_capture_movie.call_deferred()
	elif "--capture" in OS.get_cmdline_user_args():
		_capture.call_deferred()

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_label(layer,_title,Vector2(28,20),28)
	_label(layer,_subtitle,Vector2(28,61),19)
	_label(layer,_footer,Vector2.ZERO,17)
	var controls := HBoxContainer.new()
	controls.position = Vector2(28,102)
	controls.visible = not ("--capture" in OS.get_cmdline_user_args() or "--movie" in OS.get_cmdline_user_args())
	layer.add_child(controls)
	for mode in ["Hearth", "Dwarf scale", "Firelit tavern"]:
		var button := Button.new()
		button.text = mode
		button.pressed.connect(func(): _show(mode,_angle))
		controls.add_child(button)
	for angle in ["Three-quarter", "RTS", "Rear"]:
		var button := Button.new()
		button.text = angle
		button.pressed.connect(func(): _show(_hearth_mode,angle))
		controls.add_child(button)
	get_viewport().size_changed.connect(_place_labels)

func _prop(path: String,at: Vector3,turn: float = 0) -> Node3D:
	var node := super._prop(path,at,turn)
	if path == "res://models/hearth.glb":
		Lighting.attach(node,_hearth_def)
	return node

func _stone(at: Vector3,size: Vector3,color: Color) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = at
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1
	mesh.material_override = mat
	_actors.add_child(mesh)

func _show(mode: String,angle: String) -> void:
	_hearth_mode = mode
	_angle = angle
	for child in _actors.get_children():
		child.free()
	var room := mode == "Firelit tavern"
	for light in _studio_lights:
		light.visible = not room
	_env.background_color = Color(.08,.09,.11) if room else Color(.69,.71,.69)
	_env.ambient_light_energy = .07 if room else .4
	for label in [_title,_subtitle,_footer]:
		label.add_theme_color_override("font_color",Color(.88,.84,.76) if room else Color(.12,.15,.16))
	_title.text = "DEEPDRAFT   /   LIVING HEARTH"
	_subtitle.text = "Three curling flame tongues · steady ember bed · gentle firelight"
	_footer.text = "8 voxels per block · 2 × 2 footprint · Stone rim 1 block / flame up to 2 blocks · 400 heat units"
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 4.6
	var target := Vector3(0,.8,0)
	var elevation := 34.0 if angle == "Three-quarter" else 52.0
	var yaw := 30.0 if angle != "Rear" else 205.0
	_prop("res://models/hearth.glb",Vector3.ZERO)
	if room:
		for x in range(-5,5):
			for z in range(-4,5):
				var tone := .27 + float(posmod(x*3+z*7,4))*.016
				_stone(Vector3(x+.5,-.11,z+.5),Vector3(.98,.2,.98),Color(tone,tone,tone*.97))
			for y in range(5):
				var tone := .28 + float(posmod(x*7+y*3,5))*.014
				_stone(Vector3(x+.5,y+.5,-4.5),Vector3(.98,.98,1),Color(tone,tone*1.04,tone*1.09))
		_prop("res://context/bench.glb",Vector3(-2.6,0,.4),90)
		_prop("res://context/bench.glb",Vector3(2.6,0,.4),90)
		_prop("res://context/tavern_bar.glb",Vector3(0,0,-3.25))
		_prop("res://context/barrel.glb",Vector3(2.3,0,-3.25))
		_dwarf(_actors,Vector3(-2.2,0,-1.8),-20)
		_camera.size = 11.5
		target = Vector3(0,1.15,-.6)
		elevation = 42
		yaw = 12
		_subtitle.text = "Animated hearth at gameplay scale · warm light across stone, oak and iron"
	elif mode == "Dwarf scale":
		_dwarf(_actors,Vector3(-2,0,0),20)
		_camera.size = 7.7
		target = Vector3(-.65,1.2,0)
		yaw = 15
	var dir := Vector3(sin(deg_to_rad(yaw))*cos(deg_to_rad(elevation)),sin(deg_to_rad(elevation)),cos(deg_to_rad(yaw))*cos(deg_to_rad(elevation)))
	_camera.position = target+dir*20
	_camera.look_at(target)
	_place_labels()

func _capture() -> void:
	for spec in [["Hearth","Three-quarter","hearth"],["Hearth","RTS","hearth_rts"],["Hearth","Rear","hearth_rear"],["Dwarf scale","Three-quarter","dwarf_scale"],["Firelit tavern","RTS","firelit_tavern"]]:
		_show(spec[0],spec[1])
		await _shot(spec[2])
	print("HEARTH_ANIMATION_REVIEW_OK")
	get_tree().quit(0)

func _capture_movie() -> void:
	_show("Hearth","Three-quarter")
	for frame in range(120):
		await get_tree().process_frame
	_show("Firelit tavern","RTS")
	for frame in range(120):
		await get_tree().process_frame
	print("HEARTH_ANIMATION_MOVIE_OK")
	get_tree().quit(0)
