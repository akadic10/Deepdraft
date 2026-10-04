extends "TavernRedesignPreview.gd"

const Lighting = preload("FurnitureLighting.gd")
var _torch_def: Dictionary
var _env: Environment
var _lights: Array[DirectionalLight3D] = []

func _ready() -> void:
	# Isolated art-tool manifest; runtime definitions remain controller-owned.
	_torch_def = JSON.parse_string(FileAccess.get_file_as_string("res://wall_torch.json"))
	_build_stage()
	for child in get_children():
		if child is WorldEnvironment:
			_env = child.environment
		elif child is DirectionalLight3D:
			_lights.append(child)
	_build_ui()
	_show("Torch", "Three-quarter")
	if "--capture" in OS.get_cmdline_user_args():
		_capture.call_deferred()
	elif "--movie" in OS.get_cmdline_user_args():
		_capture_movie.call_deferred()

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_label(layer, _title, Vector2(28,20), 28)
	_label(layer, _subtitle, Vector2(28,61), 19)
	_label(layer, _footer, Vector2.ZERO, 17)
	var controls := HBoxContainer.new()
	controls.position = Vector2(28,102)
	controls.visible = not ("--capture" in OS.get_cmdline_user_args() or "--movie" in OS.get_cmdline_user_args())
	layer.add_child(controls)
	for mode in ["Torch", "Dwarf scale", "Torchlit room", "Unlit room"]:
		var button := Button.new()
		button.text = mode
		button.pressed.connect(func(): _show(mode, _angle))
		controls.add_child(button)
	for angle in ["Three-quarter", "RTS", "Side"]:
		var button := Button.new()
		button.text = angle
		button.pressed.connect(func(): _show(_tavern_mode, angle))
		controls.add_child(button)
	get_viewport().size_changed.connect(_place_labels)

func _stone(at: Vector3, size: Vector3, color: Color) -> void:
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

func _wall(width: int, height: int, z: float) -> void:
	for y in range(height):
		for x in range(width):
			var shade := .28 + float(posmod(x*7+y*3, 5))*.014
			_stone(Vector3(x-width*.5+.5,y+.5,z-.5),Vector3(.98,.98,1),Color(shade,shade*1.04,shade*1.09))

func _torch(at: Vector3, lit: bool = true) -> Node3D:
	var node := _prop("res://models/wall_torch.glb", at)
	if lit:
		Lighting.attach(node, _torch_def)
	return node

func _show(mode: String, angle: String) -> void:
	_tavern_mode = mode
	_angle = angle
	for child in _actors.get_children():
		child.free()
	var room := mode.ends_with("room")
	for light in _lights:
		light.visible = not room
	_env.background_color = Color(.08,.09,.11) if room else Color(.69,.71,.69)
	_env.ambient_light_energy = .055 if room else .4
	for label in [_title,_subtitle,_footer]:
		label.add_theme_color_override("font_color", Color(.88,.84,.76) if room else Color(.12,.15,.16))
	_title.text = "DEEPDRAFT   /   IRON WALL TORCH"
	_subtitle.text = "Rising voxel flames · drifting hot core · gentle light flicker"
	_footer.text = "8 voxels per block · 1.5 blocks tall · Wall mounted / walkable floor · 200 heat units"
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 3.3
	var target := Vector3(0,.8,.25)
	var elevation := 22.0
	var yaw := 26.0
	if angle == "RTS":
		elevation = 52
	elif angle == "Side":
		yaw = 78
	if room:
		_wall(10,5,-2.5)
		for x in range(-5,5):
			for z in range(-2,5):
				var tone := .26 + float(posmod(x*3+z*7,4))*.016
				_stone(Vector3(x+.5,-.11,z+.5),Vector3(.98,.2,.98),Color(tone,tone,tone*.97))
		_torch(Vector3(-2.5,2.5,-2.5),mode=="Torchlit room")
		_torch(Vector3(2.5,2.5,-2.5),mode=="Torchlit room")
		_prop("res://context/wooden_table.glb",Vector3(0,0,.5))
		_prop("res://context/wooden_chair.glb",Vector3(0,0,2.4),180)
		_prop("res://context/storage_shelf.glb",Vector3(3.6,0,-1.6))
		_prop("res://context/barrel.glb",Vector3(-3.7,0,-1.6))
		_dwarf(_actors,Vector3(-2,0,.7),-10)
		_camera.size = 12.4
		target = Vector3(0,1.8,0)
		elevation = 38
		yaw = 10
		_subtitle.text = "Independent flame timing · warm animated light · gameplay scale" if mode=="Torchlit room" else "Same room / torches off / identical ambient light"
	elif mode == "Dwarf scale":
		_wall(5,4,-.65)
		_torch(Vector3(.7,2.5,-.65))
		_dwarf(_actors,Vector3(-1,0,.5))
		_camera.size = 7.6
		target = Vector3(0,2,0)
		yaw = 12
		_subtitle.text = "Actual scale · torch base 2.5 blocks above the floor · flame above a dwarf's head"
	else:
		_wall(3,2,-.02)
		# Display at origin in the close-up; only the context view uses mounting height.
		_torch(Vector3.ZERO)
		_subtitle.text += " · "+angle
	var dir := Vector3(sin(deg_to_rad(yaw))*cos(deg_to_rad(elevation)),sin(deg_to_rad(elevation)),cos(deg_to_rad(yaw))*cos(deg_to_rad(elevation)))
	_camera.position = target + dir * 20
	_camera.look_at(target)
	_place_labels()

func _capture() -> void:
	for spec in [["Torch","Three-quarter","torch"],["Torch","RTS","torch_rts"],
		["Torch","Side","torch_side"],["Dwarf scale","Three-quarter","dwarf_scale"],
		["Torchlit room","RTS","torchlit_room"],["Unlit room","RTS","unlit_room"]]:
		_show(spec[0],spec[1])
		await _shot(spec[2])
	print("WALL_TORCH_REVIEW_OK")
	get_tree().quit(0)

func _capture_movie() -> void:
	_show("Torch","Three-quarter")
	_camera.size = 4.3
	for frame in range(120):
		await get_tree().process_frame
	_show("Torchlit room","RTS")
	for frame in range(120):
		await get_tree().process_frame
	print("TORCH_ANIMATION_MOVIE_OK")
	get_tree().quit(0)
