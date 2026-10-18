extends SceneTree

## Native GPU regression: a plant above a cliff cannot cast through the solid
## plateau onto the lower terrace. Compare the actual shadow with/without it.
const TerrainLight = preload("res://scripts/components/TerrainLighting.gd")
const OUT := "res://tmp/plant_shadow_20261017/"
const PLANT := "base:flora:wild_strawberry_bush"
var failures: Array[String] = []
var stage: Node3D
var camera: Camera3D
var sun: DirectionalLight3D
var details
var plateau: MeshInstance3D
var plant: Node3D
var measurements: Array[Dictionary] = []

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	create_timer(60).timeout.connect(func(): push_error("Terrain sun shadow test timed out"); quit(1))
	for id in ["SaveManager","WorldClock","TaskManager","RoomManager","StockpileManager","SkyController","WeatherManager"]:
		root.get_node(id).set_process(false)
	root.get_node("WorldClock").restore_state({"year":1,"season":"summer","day":1,"hour":12,"speed":1,"paused":true})
	root.get_node("WorldGenerator").world_seed = 1234
	var world = root.get_node("WorldData")
	var grass: int = root.get_node("BlockRegistry").get_id("base:terrain:surface:grass_01")
	for x in range(30,51):
		for z in range(23,57):
			world.set_block(x,19,z,grass)
			if z >= 44:
				for y in range(20,28): world.set_block(x,y,z,grass)
	root.size = Vector2i(1280,900)
	stage = Node3D.new()
	root.add_child(stage)
	current_scene = stage
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("7b8892")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = .35
	stage.add_child(environment)
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 100
	stage.add_child(sun)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 28
	camera.position = Vector3(51,46,16)
	stage.add_child(camera)
	camera.look_at(Vector3(40,24,43))
	camera.current = true
	_box(Vector3(40.5,19.5,40),Vector3(21,1,34),Color("708551"))
	plateau = _box(Vector3(40.5,24,50),Vector3(21,8,12),Color("708551"))
	details = load("res://scripts/systems/SurfaceDetailManager.gd").new()
	stage.add_child(details)
	details.set_process(false)
	details._initialized = true
	details.register_record({"id":"shadow-plant","definition":PLANT,"origin":Vector3i(40,27,48),"variant":0,"yaw":0})
	details._spawn_visual("shadow-plant")
	plant = details._records["shadow-plant"].node
	await _frames(6) # Allow the scene-owned sky binding to settle before controls.
	sun.light_color = Color.WHITE
	sun.light_energy = 1.0
	environment.environment.fog_enabled = false
	DirAccess.make_dir_recursive_absolute(OUT)
	for pitch in [30.0,40.0]:
		sun.rotation_degrees = Vector3(-pitch,0,0)
		# The former policy is an explicit negative control, never the assertion.
		sun.shadow_caster_mask &= ~TerrainLight.TERRAIN_LAYER
		plant.show()
		var before := await _capture("before_%d"%int(pitch))
		plant.hide()
		var before_empty := await _capture("")
		var leaked := _difference(before,before_empty)
		_expect(leaked.changed>10 and leaked.maximum>.03,"negative control reproduces a distinct plant shadow below the cliff")
		TerrainLight.configure_sun(sun)
		_expect((sun.shadow_caster_mask & TerrainLight.TERRAIN_LAYER)!=0,"production sun includes terrain shadow casters")
		plant.show()
		var after := await _capture("after_%d"%int(pitch))
		plant.hide()
		var after_empty := await _capture("")
		var corrected := _difference(after,after_empty)
		_expect(corrected.changed<=2 and corrected.maximum<.01,"solid cliff fully occludes the plant's lower-terrace shadow")
		var open_before := _luminance(before_empty,Vector3(35,20.01,39))
		var shaded_after := _luminance(after_empty,Vector3(35,20.01,39))
		_expect(shaded_after<open_before*.8,"lower terrace receives the cliff's own shadow")
		_expect(absf(_luminance(before_empty,Vector3(35,28.01,50))-_luminance(after_empty,Vector3(35,28.01,50)))<.02,"exposed plateau retains normal sunlight")
		plant.show()
		details.apply_slice(19)
		plateau.hide()
		var sliced := await _capture("slice_%d"%int(pitch))
		_expect(not plant.visible,"slicing away the plant removes its caster")
		_expect(absf(_luminance(sliced,Vector3(35,20.01,39))-open_before)<.02,"sliced-away geometry leaves no stale lower shadow")
		plateau.show()
		details.apply_slice(27)
		measurements.append({"pitch":pitch,"before":leaked,"after":corrected,"open_luminance":open_before,"cliff_shadow_luminance":shaded_after})
	for mesh: MeshInstance3D in plant.find_children("*","MeshInstance3D",true,false):
		_expect(mesh.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_ON,"plant retains normal shadow casting")
	var original_mask := sun.shadow_caster_mask
	sun.shadow_caster_mask = 1
	TerrainLight.configure_sun(sun)
	TerrainLight.configure_sun(sun)
	_expect(sun.shadow_caster_mask==(1|TerrainLight.TERRAIN_LAYER),"sun configuration is idempotent and preserves unrelated mask bits")
	sun.shadow_caster_mask = original_mask
	FileAccess.open(OUT+"checks.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"measurements":measurements},"  "))
	for failure in failures: push_error(failure)
	print("TERRAIN_SUN_SHADOW_OK" if failures.is_empty() else "TERRAIN_SUN_SHADOW_FAIL",": ",JSON.stringify(measurements))
	quit(0 if failures.is_empty() else 1)

func _box(position: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = position
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	node.material_override = material
	TerrainLight.configure_mesh(node)
	stage.add_child(node)
	return node

func _frames(count: int) -> void:
	for i in count: await process_frame

func _capture(label: String) -> Image:
	await _frames(6)
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if not label.is_empty(): image.save_png(OUT+label+".png")
	return image

func _difference(a: Image, b: Image) -> Dictionary:
	var maximum := 0.0
	var changed := 0
	for x in range(370,441):
		for z in range(310,421):
			var point := Vector3(x*.1,20.01,z*.1)
			var difference := absf(_luminance(a,point)-_luminance(b,point))
			maximum = maxf(maximum,difference)
			if difference>.01: changed += 1
	return {"maximum":maximum,"changed":changed}

func _luminance(image: Image, point: Vector3) -> float:
	var pixel := Vector2i(camera.unproject_position(point))
	var color := image.get_pixel(pixel.x,pixel.y)
	return color.r*.2126+color.g*.7152+color.b*.0722

func _expect(ok: bool, label: String) -> void:
	if not ok: failures.append(label)
