extends SceneTree

## Render the frozen pre-sharing shader and the live shader in the same scene.
## This catches colour-space, matrix-layout and stale-data errors independently
## of the new packet's packing code. Run natively with isolated APPDATA.
var owner_script: GDScript
const ORIGINAL := "res://docs/00_dev_roadmap/concepts/shared_atmosphere_20261015/underground_lighting.gdshader.before.txt"
var output := "res://tmp/shared_atmosphere_20261015/parity/"
var failures: Array[String] = []
var checks := 0
var comparisons: Array = []
var field: Node
var scene: Node3D
var camera: Camera3D
var environment: Environment
var source: StandardMaterial3D
var modern: ShaderMaterial
var original: ShaderMaterial
var meshes: Array[MeshInstance3D] = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("AtmosphereSharingTest requires native rendering"); quit(1); return
	if not "/shared_atmosphere_20261015/" in OS.get_user_data_dir().replace("\\", "/"):
		push_error("AtmosphereSharingTest requires isolated APPDATA"); quit(1); return
	create_timer(120).timeout.connect(func(): push_error("Atmosphere sharing timeout"); quit(1))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=").trim_suffix("/") + "/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.get_node("SaveManager").configure_storage_for_testing("user://atmosphere_test")
	for id in ["SaveManager", "WorldClock", "WeatherManager", "TaskManager", "SkyController"]:
		root.get_node(id).set_process(false)
	root.size = Vector2i(640, 480)
	await process_frame
	_setup()
	var sky = root.get_node("SkyController")
	sky.rebind_to_current_scene()
	root.get_node("WeatherManager").set_weather("base:weather:clear")
	for hour in [12.0, 18.0, 0.0]:
		sky._update(hour)
		await _compare("hour_%02d" % int(hour))
	# Exercise all four sun slots, both hemispheres, height and exponential fog,
	# nontrivial rotation and HDR colours through the existing environment path.
	for i in 2:
		var light := DirectionalLight3D.new()
		light.light_color = Color(.5, .3 + i * .2, .8)
		light.light_energy = 1.3
		scene.add_child(light)
		light.rotation = Vector3(-.2, .6 + i, .1)
	for light in scene.find_children("*", "DirectionalLight3D", true, false): light.visible = true
	environment.sky.sky_material = ProceduralSkyMaterial.new()
	environment.sky_rotation = Vector3(.3, -.4, .2)
	environment.background_energy_multiplier = 1.6
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	environment.fog_density = .035
	environment.fog_height = 4.0
	environment.fog_height_density = .06
	environment.fog_light_color = Color(.3, .6, .85)
	environment.fog_light_energy = 1.7
	environment.fog_aerial_perspective = .65
	environment.fog_sun_scatter = .4
	await _compare("procedural_height_hdr")
	_check(field._fog_parameters.fog_sun_count == 4, "all four directional light slots exercised")
	camera.position = Vector3(12, -8, 20)
	camera.look_at(Vector3(0, 2, 0))
	await _compare("upper_hemisphere")
	camera.position = Vector3(12, 10, 20)
	camera.look_at(Vector3(0, 1, 0))
	camera.environment = environment.duplicate(true)
	camera.environment.fog_mode = Environment.FOG_MODE_DEPTH
	camera.environment.fog_depth_begin = 1
	camera.environment.fog_depth_end = 50
	camera.environment.fog_depth_curve = 1.7
	camera.environment.fog_height_density = -.03
	camera.environment.fog_light_color = Color(.8, .25, .1)
	await _compare("camera_override_depth")
	camera.environment.fog_enabled = false
	await _compare("fog_disabled")
	camera.environment.fog_enabled = true
	await _compare("fog_reenabled")
	await _ownership()
	for failure in failures: push_error(failure)
	var result := {"checks": checks, "failures": failures, "comparisons": comparisons}
	FileAccess.open(output + "checks.json", FileAccess.WRITE).store_string(JSON.stringify(result, "  "))
	print("ATMOSPHERE_SHARING_PASS " if failures.is_empty() else "ATMOSPHERE_SHARING_FAIL ", JSON.stringify(result))
	scene.free()
	quit(0 if failures.is_empty() else 1)


func _setup() -> void:
	owner_script = load("res://scripts/components/UndergroundLighting.gd")
	scene = Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var world_environment := WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
	environment = Environment.new()
	world_environment.environment = environment
	scene.add_child(world_environment)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	scene.add_child(sun)
	camera = Camera3D.new()
	camera.position = Vector3(12, 10, 20)
	scene.add_child(camera)
	camera.look_at(Vector3(0, 1, 0))
	camera.current = true
	field = owner_script.new()
	scene.add_child(field)
	field.set_process(false)
	source = StandardMaterial3D.new()
	source.albedo_color = Color(.7, .45, .2)
	modern = field.make_material(source)
	var shader := Shader.new()
	shader.code = FileAccess.get_file_as_string(ORIGINAL)
	original = ShaderMaterial.new()
	original.shader = shader
	for key in ["tint", "vertex_color", "readability_floor", "sky_table", "sky_page_0", "sky_page_1", "sky_page_2", "sky_page_3"]:
		original.set_shader_parameter(key, modern.get_shader_parameter(key))
	for i in 3:
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(3, 4, 3)
		mesh.mesh = box
		mesh.position = Vector3((i - 1) * 4, 2, 0)
		scene.add_child(mesh)
		mesh.set_instance_shader_parameter("actor_sky_access", [0.0, .25, 1.0][i])
		meshes.append(mesh)


func _compare(label: String) -> void:
	field._sync_fog()
	for key in field._fog_parameters: original.set_shader_parameter(key, field._fog_parameters[key])
	var before := await _capture(original)
	var after := await _capture(modern)
	before.save_png(output + label + "_before.png")
	after.save_png(output + label + "_after.png")
	var a := before.get_data()
	var b := after.get_data()
	_check(a.size() == b.size(), label + ": same image format")
	var maximum := 0
	var different := 0
	for i in mini(a.size(), b.size()):
		var delta := absi(int(a[i]) - int(b[i]))
		maximum = maxi(maximum, delta)
		if delta > 0: different += 1
	comparisons.append({"label": label, "max_byte_difference": maximum, "different_channels": different, "channels": a.size()})
	_check(maximum <= 1, label + ": every rendered channel agrees within 1/255")
	_check(modern.get_shader_parameter("atmosphere_data") == field._atmosphere.texture, label + ": stable material binding")


func _capture(material: ShaderMaterial) -> Image:
	for mesh in meshes: mesh.material_override = material
	for i in 4:
		await process_frame
		await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


func _ownership() -> void:
	var packet: ImageTexture = modern.get_shader_parameter("atmosphere_data")
	var rid := packet.get_rid()
	var before := packet.get_image().get_data()
	field._sync_fog()
	_check(packet.get_image().get_data() == before, "unchanged atmosphere retains exact packet")
	var other_view := SubViewport.new()
	other_view.own_world_3d = true
	scene.add_child(other_view)
	var other: Node = owner_script.new()
	other_view.add_child(other)
	other.set_process(false)
	other._sync_fog()
	var other_packet: ImageTexture = other.make_material(source).get_shader_parameter("atmosphere_data")
	var other_before := other_packet.get_image().get_data()
	_check(other_packet != packet, "viewport owners have separate packets")
	camera.environment.fog_density = .79
	field._sync_fog()
	_check(packet.get_rid() == rid and packet.get_image().get_data() != before, "live data changes without replacing the texture RID")
	_check(other_packet.get_image().get_data() == other_before, "one viewport cannot change another's atmosphere")
	var late: ShaderMaterial = field.make_material(StandardMaterial3D.new())
	_check(late.get_shader_parameter("atmosphere_data") == packet, "late material binds current shared texture")
	_check(field.make_material(source) == modern, "material cache still reuses source")
	other_view.free()
	var replacement: Node = owner_script.new()
	scene.add_child(replacement)
	replacement.set_process(false)
	replacement._sync_fog()
	_check(replacement._atmosphere.texture != packet, "replacement scene owner creates its own texture")
	_check(replacement._atmosphere.texture.get_image().get_data() == packet.get_image().get_data(), "replacement restores current environment exactly")
	replacement.free()


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
