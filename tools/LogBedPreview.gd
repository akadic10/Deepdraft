extends SceneTree

## Native review of the starter bed and its four material variants.
const OUTPUT := "res://tmp/rudimentary_bed_20261011/"
var scene := Node3D.new()
var camera := Camera3D.new()
var models: Array[Node3D] = []
var captions: Array[Label] = []

func _init() -> void: _run.call_deferred()

func _run() -> void:
	for key in ["SaveManager","RoomManager","StockpileManager","TaskManager","WorldClock","WaterManager"]:
		root.get_node(key).set_process(false)
	root.get_node("WorldClock").set_paused(true)
	root.size = Vector2i(1200,850)
	root.add_child(scene)
	current_scene = scene
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("30382e")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = .65
	scene.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50,-32,0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	scene.add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.mesh = BoxMesh.new()
	floor_mesh.mesh.size = Vector3(30,.25,30)
	floor_mesh.position.y = -.125
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color("69715d")
	floor_mesh.material_override = floor_material
	scene.add_child(floor_mesh)
	scene.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 6.5
	camera.position = Vector3(8,9,11)
	camera.look_at(Vector3(0,.35,0))
	var registry = load("res://scripts/systems/FurniturePlacementController.gd").new()
	registry._load_defs()
	var definition: Dictionary = registry.get_defs()["base:furniture:log_bed"]
	var materials := root.get_node("CraftMaterials")
	for wood in ["oak","pine","juniper","applewood"]:
		var model: Node3D = load(String(definition.model)).instantiate()
		materials.apply_palette(model,definition,"base:material:"+wood)
		var material := StandardMaterial3D.new()
		material.vertex_color_use_as_albedo = true
		material.roughness = 1
		for mesh: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false): mesh.material_override = material
		scene.add_child(model)
		model.visible = models.is_empty()
		models.append(model)
		var caption := Label.new()
		caption.text = materials.material_name("base:material:"+wood)
		caption.add_theme_font_size_override("font_size",22)
		caption.visible = false
		root.add_child(caption)
		captions.append(caption)
	registry.free()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	await _capture("log_bed")
	camera.position = Vector3(0,12,.01)
	camera.look_at(Vector3.ZERO)
	await _capture("top")
	camera.size = 13
	camera.position = Vector3(0,14,18)
	camera.look_at(Vector3(0,0,0))
	for index in range(4):
		models[index].visible = true
		models[index].position = Vector3(-3.25+6.5*(index%2),0,-2.5+5*(index>>1))
		captions[index].visible = true
		captions[index].position = camera.unproject_position(models[index].position+Vector3(0,0,1.9))-Vector2(30,0)
	await _capture("wood_variants")
	print("LOG_BED_PREVIEW_OK")
	quit()

func _capture(label: String) -> void:
	for frame in range(8): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUTPUT+label+".png")
