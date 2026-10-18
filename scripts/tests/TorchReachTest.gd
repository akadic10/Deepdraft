extends SceneTree

## Native GPU comparison through the production underground material and
## furniture light attachment. Freeze flicker to measure distance falloff.
const OUTPUT := "res://tmp/torch_reach_20261017/"
const FurnitureLight = preload("res://scripts/components/FurnitureLighting.gd")
var stage: Node3D
var camera: Camera3D
var field
var failures: Array[String] = []
var measures := {}

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	create_timer(60).timeout.connect(func(): push_error("Torch reach timed out"); quit(1))
	for id in ["SaveManager","WorldClock","TaskManager","RoomManager","StockpileManager","SkyController","WeatherManager"]:
		root.get_node(id).set_process(false)
	root.get_node("WorldClock").set_paused(true)
	root.size = Vector2i(1280,900)
	stage = Node3D.new()
	root.add_child(stage)
	current_scene = stage
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color.BLACK
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	stage.add_child(environment)
	field = load("res://scripts/components/UndergroundLighting.gd").new()
	stage.add_child(field)
	var furniture = load("res://scripts/systems/FurniturePlacementController.gd").new()
	stage.add_child(furniture)
	furniture.set_process(false)
	_box(Vector3(42,1,50),Vector3(0,-.5,10))
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 30
	camera.position = Vector3(0,45,11)
	camera.rotation_degrees = Vector3(-90,0,0)
	stage.add_child(camera)
	camera.current = true
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var unlit := await _capture("unlit")
	var baseline := _sample(unlit,Vector3(0,0,16))
	for key in ["wooden_torch","wall_torch"]:
		var definition: Dictionary = furniture.get_defs()["base:furniture:"+key]
		var torch: Node3D = load(definition.model).instantiate()
		stage.add_child(torch)
		torch.position = Vector3(0,1.5,-.8125)
		FurnitureLight.attach(torch,definition)
		torch.get_node("FlameAnimation").set_process(false)
		var light: OmniLight3D = torch.get_node("FurnitureLight")
		light.light_energy = float(definition.light_source.energy)
		var current_range := light.omni_range
		light.omni_range = 12
		var before := await _capture(key+"_before")
		light.omni_range = current_range
		var after := await _capture(key+"_after")
		var old_profile: Array[float] = []
		var new_profile: Array[float] = []
		for step in range(81):
			var distance := 2.0+step*.25
			old_profile.append(_sample(before,Vector3(0,0,distance)))
			new_profile.append(_sample(after,Vector3(0,0,distance)))
		_expect(new_profile[56]>old_profile[56]+.02,key+" lights floor 16 voxels away")
		_expect(new_profile[64]>baseline+.005,key+" has a faint tail at 18 voxels")
		_expect(absf(new_profile[80]-baseline)<.005,key+" leaves distant unlit floor dark")
		var old_drop := _maximum_drop(old_profile,24,40) # old edge, 8–12 voxels
		var new_drop := _maximum_drop(new_profile,40,72) # new edge, 12–20 voxels
		_expect(new_drop<old_drop*.8,key+" spreads the outer fade over a gentler gradient")
		for i in range(1,new_profile.size()):
			_expect(new_profile[i]<=new_profile[i-1]+.005,key+" falloff never brightens or bands outward")
		var wall := _box(Vector3(16,6,1),Vector3(0,3,8))
		var shadowed := await _capture(key+"_blocked")
		var blocked := _sample(shadowed,Vector3(0,0,12))
		_expect(blocked<baseline+.01 and light.shadow_enabled,key+" remains blocked by solid walls")
		measures[key] = {"range":current_range,"unlit":baseline,"sample_start":2,"sample_step":.25,
			"before":old_profile,"after":new_profile,"old_max_edge_drop":old_drop,
			"new_max_edge_drop":new_drop,"behind_wall":blocked}
		wall.free()
		torch.free()
	FileAccess.open(OUTPUT+"checks.json",FileAccess.WRITE).store_string(JSON.stringify({"measures":measures,"failures":failures},"  ")+"\n")
	for failure in failures: push_error(failure)
	print("TORCH_REACH_OK" if failures.is_empty() else "TORCH_REACH_FAIL")
	quit(0 if failures.is_empty() else 1)

func _box(size: Vector3, position: Vector3) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var shape := BoxMesh.new()
	shape.size = size
	mesh.mesh = shape
	mesh.position = position
	var source := StandardMaterial3D.new()
	source.albedo_color = Color("827967")
	mesh.material_override = field.make_material(source)
	stage.add_child(mesh)
	# A fully underground surface, independent of daylight/roof generation.
	mesh.set_instance_shader_parameter("actor_sky_access",0.0)
	return mesh

func _capture(label: String) -> Image:
	for i in range(5): await process_frame
	await RenderingServer.frame_post_draw
	var capture := root.get_texture().get_image()
	capture.save_png(OUTPUT+label+".png")
	return capture

func _sample(capture: Image, position: Vector3) -> float:
	var at := Vector2i(camera.unproject_position(position))
	var value := 0.0
	for x in range(at.x-1,at.x+2):
		for y in range(at.y-1,at.y+2): value += capture.get_pixel(x,y).get_luminance()
	return value/9.0

func _maximum_drop(profile: Array[float], start: int, end: int) -> float:
	var drop := 0.0
	for i in range(start,end): drop = maxf(drop,profile[i]-profile[i+1])
	return drop

func _expect(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
