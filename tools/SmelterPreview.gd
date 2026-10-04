extends "TavernRedesignPreview.gd"

const Lighting = preload("FurnitureLighting.gd")
var _smelter_def: Dictionary
var _env: Environment
var _lights: Array[DirectionalLight3D] = []

func _ready() -> void:
	# Isolated review data; the live game uses the placement controller's registry.
	_smelter_def = JSON.parse_string(FileAccess.get_file_as_string("res://smelter.json"))
	_build_stage()
	for child in get_children():
		if child is WorldEnvironment:
			_env = child.environment
		elif child is DirectionalLight3D:
			_lights.append(child)
	_build_ui()
	_show("Smelter","Three-quarter")
	if "--capture" in OS.get_cmdline_user_args():
		_capture.call_deferred()
	elif "--movie" in OS.get_cmdline_user_args():
		_capture_movie.call_deferred()

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
	for mode in ["Smelter","Dwarf scale","Workshop","Firelit workshop"]:
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

func _prop(path: String,at: Vector3,turn: float = 0) -> Node3D:
	var node := super._prop(path,at,turn)
	if path=="res://models/smelter.glb":
		Lighting.attach(node,_smelter_def)
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
	_tavern_mode = mode
	_angle = angle
	for child in _actors.get_children():
		child.free()
	var dark := mode=="Firelit workshop"
	for light in _lights:
		light.visible = not dark
	_env.background_color = Color(.08,.09,.11) if dark else Color(.69,.71,.69)
	_env.ambient_light_energy = .10 if dark else .4
	for label in [_title,_subtitle,_footer]:
		label.add_theme_color_override("font_color",Color(.88,.84,.76) if dark else Color(.12,.15,.16))
	_title.text = "DEEPDRAFT   /   STONE SMELTER"
	_subtitle.text = "Arched firebox · iron hood and grate · soot-darkened chimney"
	_footer.text = "8 voxels per block · 2 × 2 footprint · 3 blocks tall · Animated furnace fire"
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 5.6
	var target := Vector3(0,1.4,0)
	var elevation := 24.0 if angle=="Three-quarter" else 48.0
	var yaw := 30.0 if angle!="Rear" else 205.0
	if mode=="Dwarf scale":
		_prop("res://models/smelter.glb",Vector3(1.7,0,0))
		_dwarf(_actors,Vector3(-1.4,0,.4),15)
		_camera.size = 8.3
		target = Vector3(.2,1.5,0)
		yaw = 0
		_subtitle.text = "Three-block furnace beside a full-size 3.375-block dwarf"
	elif mode in ["Workshop","Firelit workshop"]:
		for x in range(-5,5):
			for z in range(-4,5):
				var tone := .27 + float(posmod(x*3+z*7,4))*.016
				_stone(Vector3(x+.5,-.11,z+.5),Vector3(.98,.2,.98),Color(tone,tone,tone*.97))
			for y in range(5):
				var tone := .28 + float(posmod(x*7+y*3,5))*.014
				_stone(Vector3(x+.5,y+.5,-4.5),Vector3(.98,.98,1),Color(tone,tone*1.04,tone*1.09))
		_prop("res://models/smelter.glb",Vector3(0,0,-1.8))
		_prop("res://context/anvil.glb",Vector3(2.4,0,.5))
		_prop("res://context/storage_shelf.glb",Vector3(-3,0,-2.5))
		_prop("res://context/storage_crate.glb",Vector3(3.1,0,-2.5))
		_dwarf(_actors,Vector3(-1.8,0,.1),-5)
		_camera.size = 12
		target = Vector3(0,1.5,-.5)
		elevation = 35
		yaw = 10
		_subtitle.text = "Smelter, anvil and dwarf at gameplay scale"+ (" · warm light through the firebox" if dark else "")
	else:
		_prop("res://models/smelter.glb",Vector3.ZERO)
		_subtitle.text += " · "+angle
	var dir := Vector3(sin(deg_to_rad(yaw))*cos(deg_to_rad(elevation)),sin(deg_to_rad(elevation)),cos(deg_to_rad(yaw))*cos(deg_to_rad(elevation)))
	_camera.position = target+dir*20
	_camera.look_at(target)
	_place_labels()

func _capture() -> void:
	for spec in [["Smelter","Three-quarter","smelter"],["Smelter","RTS","smelter_rts"],["Smelter","Rear","smelter_rear"],["Dwarf scale","Three-quarter","dwarf_scale"],["Workshop","RTS","workshop"],["Firelit workshop","RTS","firelit_workshop"]]:
		_show(spec[0],spec[1])
		await _shot(spec[2])
	print("SMELTER_REVIEW_OK")
	get_tree().quit(0)

func _capture_movie() -> void:
	_show("Smelter","Three-quarter")
	for frame in range(120):
		await get_tree().process_frame
	_show("Firelit workshop","RTS")
	for frame in range(120):
		await get_tree().process_frame
	print("SMELTER_MOVIE_OK")
	get_tree().quit(0)
