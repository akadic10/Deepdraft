extends SceneTree

## Native art review at the real bank height, with production palettes and dwarf.
const OUT := "res://tmp/log_bridge_art_20261013/"
var scene: Node3D
var camera: Camera3D
var controller
var stage: Node3D
var label: Label

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	for id in ["SaveManager", "TaskManager", "WorldClock", "SkyController", "WeatherManager", "RoomManager", "StockpileManager", "AmbientAudio"]:
		root.get_node(id).set_process(false)
	scene = Node3D.new()
	root.add_child(scene)
	current_scene = scene
	root.size = Vector2i(1280, 900)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("26363d")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("d5e3ed")
	environment.environment.ambient_light_energy = .55
	scene.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -35, 0)
	sun.light_energy = 1.15
	sun.light_color = Color("fff1d8")
	sun.shadow_enabled = true
	scene.add_child(sun)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.current = true
	scene.add_child(camera)
	controller = load("res://scripts/systems/FurniturePlacementController.gd").new()
	controller._load_defs()
	var layer := CanvasLayer.new()
	scene.add_child(layer)
	label = Label.new()
	label.position = Vector2(24, 22)
	label.add_theme_font_size_override("font_size", 24)
	layer.add_child(label)
	var prefix := "after"
	if "--before" in OS.get_cmdline_user_args(): prefix = "before"
	DirAccess.make_dir_recursive_absolute(OUT)
	for span in [1, 3, 5]:
		await _show(span, "pine", false, prefix)
		await _show(span, "pine", true, prefix)
	for wood in ["oak", "juniper", "applewood"]:
		await _show(3, wood, false, prefix)
	controller.free()
	print("LOG_BRIDGE_REVIEW_OK: 9 native views, spans 1/3/5 and four wood palettes")
	quit()

func _show(span: int, wood: String, close_view: bool, prefix: String) -> void:
	if is_instance_valid(stage): stage.free()
	stage = Node3D.new()
	scene.add_child(stage)
	_box(Vector3(.5, -.5, 2.5), Vector3(9, 1, 6), Color("728650"))
	_box(Vector3(.5, -.5, -span-3.5), Vector3(9, 1, 6), Color("728650"))
	_box(Vector3(.5, -.68, -(span+1)*.5), Vector3(9, .1, span), Color("77becf"))
	var definition: Dictionary = controller.get_defs()["base:furniture:log_bridge"].duplicate(true)
	definition.model = "res://assets/models/furniture/log_bridge_%d.glb" % span
	var bridge: Node3D = controller._instance_model("", controller._make_solid_material(), definition)
	stage.add_child(bridge)
	root.get_node("CraftMaterials").apply_palette(bridge, definition, "base:material:" + wood)
	var factory = load("res://scripts/entities/DwarfFactory.gd").new()
	var dwarf: Node3D = factory.spawn(factory.generate(141, {}), 1720)
	stage.add_child(dwarf)
	dwarf.set_process(false)
	dwarf.get_node("Readability").set_process(false)
	dwarf.position = Vector3(-1.8, 0, .8)
	dwarf.rotation.y = PI * .3
	var target := Vector3(.5, -.08, -(span+1)*.5)
	camera.position = target + (Vector3(6, 4, -9) if close_view else Vector3(7, 10, 12))
	camera.look_at(target)
	camera.size = span + (2.8 if close_view else 7.5)
	label.text = "LOG BRIDGE / %s / %d-block crossing / %s" % [wood.capitalize(), span, "Close" if close_view else "Colony view"]
	for i in 5: await process_frame
	await RenderingServer.frame_post_draw
	var path := OUT + "%s_%d_%s_%s.png" % [prefix, span, wood, "close" if close_view else "colony"]
	assert(root.get_texture().get_image().save_png(path) == OK)

func _box(center: Vector3, size: Vector3, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	mesh.mesh.size = size
	mesh.position = center
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1
	mesh.material_override = material
	stage.add_child(mesh)
