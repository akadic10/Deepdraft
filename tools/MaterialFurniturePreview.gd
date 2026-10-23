extends SceneTree

## Native palette contact sheet. Uses the same registry and meshes as installation.
const OUTPUT := "res://tmp/material_furniture_20261011/palettes.png"
var scene := Node3D.new()
var camera := Camera3D.new()

func _init() -> void: _run.call_deferred()
func _run() -> void:
	for key in ["SaveManager", "RoomManager", "StockpileManager", "TaskManager", "WorldClock", "WaterManager"]:
		root.get_node(key).set_process(false)
	root.size = Vector2i(1600,1000)
	root.add_child(scene)
	current_scene = scene
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("222c2d")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = .7
	scene.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48,-28,0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	scene.add_child(sun)
	scene.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 13
	camera.position = Vector3(0,14,23)
	camera.look_at(Vector3(0,.5,0))
	var registry = load("res://scripts/systems/FurniturePlacementController.gd").new()
	var materials = root.get_node("CraftMaterials")
	var columns := ["pine","oak","juniper","applewood"]
	for column in range(columns.size()):
		var id: String = "base:material:" + columns[column]
		var x := -6.0 + 4.0 * column
		for row in range(3):
			var key: String = ["wooden_torch", "bench", "log_chair"][row]
			var definition: Dictionary = registry.get_defs()["base:furniture:"+key]
			var model: Node3D = load(String(definition.model)).instantiate()
			materials.apply_palette(model, definition, id)
			var material := StandardMaterial3D.new()
			material.vertex_color_use_as_albedo = true
			material.roughness = 1
			for mesh: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false): mesh.material_override = material
			scene.add_child(model)
			model.position = Vector3(x,0,-4+row*4)
			model.rotation_degrees.y = -18
			if row == 0: load("res://scripts/components/FurnitureLighting.gd").attach(model,definition)
		_label(materials.material_name(id), camera.unproject_position(Vector3(x,0,-6))-Vector2(65,25), 24)
		var score: Dictionary = materials.appeal(registry.get_defs()["base:furniture:log_chair"], id)
		_label("Stool appeal: %s" % str(score.total), camera.unproject_position(Vector3(x,0,5.7))-Vector2(70,0), 18)
	_label("DEEPDRAFT  /  WOOD MATERIALS", Vector2(40,30), 30)
	_label("One design, four shared palettes • wood changes; flame, stone and bindings keep their colors", Vector2(40,76), 19)
	registry.free()
	for i in range(10): await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT.get_base_dir()))
	root.get_texture().get_image().save_png(OUTPUT)
	quit()

func _label(caption: String, point: Vector2, font_size: int) -> void:
	var label := Label.new()
	label.text = caption
	label.position = point
	label.add_theme_font_size_override("font_size",font_size)
	root.add_child(label)
