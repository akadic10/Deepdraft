extends SceneTree

const OUTPUT := "res://tmp/log_furniture_20261011/art"
var camera := Camera3D.new()
var scene := Node3D.new()
var doors: Array[Node3D] = []
var actor

func _init() -> void: _run.call_deferred()
func _run() -> void:
	for name in ["SaveManager","RoomManager","StockpileManager","TaskManager","WorldClock","WaterManager"]: root.get_node(name).set_process(false)
	root.get_node("WorldClock").paused = true
	root.size = Vector2i(1600,1000)
	root.add_child(scene)
	current_scene = scene
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("222c2d")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("e3e3d0")
	environment.environment.ambient_light_energy = .7
	scene.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48,-28,0)
	sun.light_color = Color("ffe5bb")
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	scene.add_child(sun)
	_box(Vector3(0,-.2,2),Vector3(26,.4,20),Color("737c69"))
	scene.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 16
	camera.position = Vector3(10,12,25)
	camera.look_at(Vector3(0,1,2))
	var registry = load("res://scripts/systems/FurniturePlacementController.gd").new()
	registry._load_defs()
	for entry in [["door",Vector3(-6,0,0)],["log_door_3",Vector3(-2,0,0)],["log_door_4",Vector3(3,0,0)],["bench",Vector3(0,0,5)],["wooden_torch",Vector3(-8,1.0,4)],["campfire",Vector3(5,0,6)]]:
		var def: Dictionary = registry.get_defs()["base:furniture:"+entry[0]]
		var model: Node3D = load(String(def.model)).instantiate()
		scene.add_child(model)
		model.position = entry[1]
		var material := StandardMaterial3D.new()
		material.vertex_color_use_as_albedo = true
		material.roughness = 1
		for mesh: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false): mesh.material_override = material
		load("res://scripts/components/FurnitureLighting.gd").attach(model,def)
		if def.has("door_animation"):
			var animation = load("res://scripts/components/FurnitureDoorAnimation.gd").new()
			model.add_child(animation)
			animation.setup(model,def.door_animation)
			animation.set_process(false)
			doors.append(model)
			model.set_meta("animation",animation)
		_label(String(def.display_name),entry[1]+Vector3(0,-.1,1.2))
	_box(Vector3(-8,1.6,3.5),Vector3(2,3.2,1),Color("66695c"))
	var heading := Label.new()
	heading.text = "DEEPDRAFT / LOG FURNITURE"
	heading.position = Vector2(40,35)
	heading.add_theme_font_size_override("font_size",30)
	root.add_child(heading)
	var factory = load("res://scripts/entities/DwarfFactory.gd").new()
	actor = factory.spawn(factory.generate(874,{}),874)
	actor.set_process(false)
	scene.add_child(actor)
	actor.position = Vector3(8,0,1)
	root.get_node("TaskManager").register_dwarf(actor)
	registry.free()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	await _capture("closed")
	root.get_node("WorldClock").paused = false
	root.get_node("WorldClock").speed = 1
	for model in doors:
		actor.position = model.to_global(Vector3(0,0,-2))
		model.get_meta("animation")._process(.4)
	actor.position = Vector3(8,0,1)
	await _capture("open")
	quit()

func _box(point: Vector3, size: Vector3, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	mesh.mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh.material_override = material
	scene.add_child(mesh)
	mesh.position = point

func _label(text: String, point: Vector3) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size",20)
	label.position = camera.unproject_position(point)-Vector2(60,0)
	root.add_child(label)

func _capture(name: String) -> void:
	for i in range(8): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUTPUT+"/"+name+".png")
