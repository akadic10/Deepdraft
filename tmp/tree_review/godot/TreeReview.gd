extends Node3D
var camera: Camera3D
var actors := Node3D.new()
var title := Label.new()
var caption := Label.new()

func _ready() -> void:
	add_child(actors)
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(.69,.71,.69)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(.95,.97,1)
	env.ambient_light_energy = .4
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = env
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52,-32,0)
	sun.light_color = Color(1,.95,.87)
	sun.light_energy = .7
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 180
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-25,125,0)
	fill.light_color = Color(.80,.88,1)
	fill.light_energy = .15
	add_child(fill)
	var floor_mesh := MeshInstance3D.new()
	var floor_box := BoxMesh.new()
	floor_box.size = Vector3(110,.15,45)
	floor_mesh.mesh = floor_box
	floor_mesh.position.y = -.08
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(.50,.55,.51)
	mat.roughness = 1
	floor_mesh.material_override = mat
	add_child(floor_mesh)
	camera = Camera3D.new()
	camera.current = true
	camera.far = 250
	add_child(camera)
	var layer := CanvasLayer.new()
	add_child(layer)
	title.position = Vector2(24,20)
	title.add_theme_color_override("font_color",Color(.12,.15,.16))
	title.add_theme_font_size_override("font_size",24)
	layer.add_child(title)
	caption.text = "PINE                                        OAK                                        APPLE                                    JUNIPER"
	caption.position = Vector2(165,845)
	caption.add_theme_font_size_override("font_size",22)
	caption.add_theme_color_override("font_color",Color(.12,.15,.16))
	layer.add_child(caption)
	if "--color-test" in OS.get_cmdline_user_args():
		_color_test.call_deferred()
	else:
		_capture.call_deferred()

func _tint(node: Node, color: Color = Color.WHITE) -> void:
	if node is MeshInstance3D:
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.albedo_color = color
		mat.roughness = 1
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		node.material_override = mat
	for child in node.get_children(): _tint(child,color)

func _part(parent: Node3D, asset: String, color: Color = Color.WHITE, mirror: bool = false) -> void:
	var scene := load("res://models/"+asset+".glb") as PackedScene
	var node := scene.instantiate() as Node3D
	parent.add_child(node)
	if mirror: node.scale.x = -1
	_tint(node,color)

func _dwarf(parent: Node3D) -> void:
	var dwarf := Node3D.new()
	parent.add_child(dwarf)
	dwarf.position = Vector3(8,0,5)
	var skin := Color(.85,.65,.50)
	var hair := Color(.42,.26,.14)
	_part(dwarf,"head_adult",skin)
	_part(dwarf,"body_base")
	_part(dwarf,"eyes",Color(.25,.55,.85))
	_part(dwarf,"brows_m_arched",hair)
	_part(dwarf,"hair_m_short_back",hair)
	_part(dwarf,"beard_short_trimmed",hair)
	for mirror in [false,true]:
		_part(dwarf,"hand",skin,mirror)
		_part(dwarf,"foot",Color.WHITE,mirror)

func _lineup(stage: String, season: String) -> void:
	for child in actors.get_children(): child.free()
	var species := ["pine","oak","apple","juniper"]
	for i in range(4):
		var group := Node3D.new()
		group.position.x = (i-1.5)*26
		group.rotation_degrees.y = 25
		actors.add_child(group)
		var asset: String = species[i]+"_"+stage
		if season != "summer":
			var wanted: String = asset+"_"+season
			if ResourceLoader.exists("res://models/"+wanted+".glb"): asset = wanted
		_part(group,asset)
		_dwarf(group)
	title.text = "CURRENT tree assets · %s / %s · unchanged world scale, with 3.375-block dwarfs" % [stage,season]

func _view(elevation: float, gameplay: bool = false) -> void:
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE if gameplay else Camera3D.PROJECTION_ORTHOGONAL
	camera.fov = 45
	camera.size = 60
	var target := Vector3(0,9,0)
	camera.position = target + Vector3(0,sin(deg_to_rad(elevation)),cos(deg_to_rad(elevation)))*85
	camera.look_at(target)

func _shot(file: String) -> void:
	for i in range(4): await RenderingServer.frame_post_draw
	assert(get_viewport().get_texture().get_image().save_png("res://../"+file+".png") == OK)
	print("TREE_CAPTURED ",file)

func _capture() -> void:
	for stage in ["mature","ancient"]:
		_lineup(stage,"summer")
		_view(30)
		await _shot("godot_"+stage)
		_view(50)
		await _shot("godot_"+stage+"_rts")
	_lineup("mature","winter")
	_view(30)
	await _shot("godot_winter")
	_lineup("mature","spring")
	await _shot("godot_spring")
	_lineup("mature","autumn")
	await _shot("godot_autumn")
	_lineup("mature","autumn_fruiting")
	await _shot("godot_fruiting")
	_lineup("mature","summer")
	_view(50,true)
	await _shot("godot_gameplay_distance")
	print("TREE_REVIEW_OK")
	get_tree().quit(0)

func _srgb(node: Node) -> void:
	if node is MeshInstance3D:
		node.material_override.vertex_color_is_srgb = true
	for child in node.get_children(): _srgb(child)

func _color_test() -> void:
	for child in actors.get_children(): child.free()
	for i in range(4):
		var group := Node3D.new()
		group.position.x = (i-1.5)*26
		group.rotation_degrees.y = 25
		actors.add_child(group)
		_part(group,"pine_mature" if i<2 else "oak_mature")
		if i%2 == 1: _srgb(group.get_child(0))
		_dwarf(group)
	title.text = "Color interpretation test ONLY · identical current geometry, lighting and palettes · dwarfs unchanged"
	caption.text = "PINE: current                      PINE: sRGB preview                      OAK: current                       OAK: sRGB preview"
	caption.position.x = 75
	_view(30)
	await _shot("godot_color_comparison")
	print("TREE_COLOR_REVIEW_OK")
	get_tree().quit(0)
