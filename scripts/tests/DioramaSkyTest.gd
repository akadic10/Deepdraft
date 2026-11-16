extends SceneTree

var failures: Array[String] = []
var checks := 0
var sky
var clock
var weather
var env: Environment
var camera: Camera3D
var captures := "res://tmp/sky_art_20261013/fixture/"

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	root.get_node("SaveManager").configure_storage_for_testing("user://sky_fixture")
	for id in ["SaveManager", "TaskManager", "WorldClock", "SkyController", "WeatherManager"]:
		root.get_node(id).set_process(false)
	sky = root.get_node("SkyController")
	clock = root.get_node("WorldClock")
	weather = root.get_node("WeatherManager")
	clock.set_paused(true)
	await process_frame
	await process_frame
	_setup_scene()
	sky.rebind_to_current_scene()
	for season in ["spring", "summer", "autumn", "winter"]:
		clock.season = season
		clock.day = 2
		sky._refresh_event_hours()
		sky._build_curves()
		_set_weather("clear", 0.7667)
		_check(env.background_mode == Environment.BG_SKY, season + " uses sky background")
		_check(env.sky.sky_material is ShaderMaterial, season + " has full sphere shader")
		_check(_parameter("night_amount") > .9, season + " midnight stars")
		_check(_parameter("moon_visibility") > .9, season + " midnight moon")
		_check(env.fog_light_color.b > env.fog_light_color.r * 2.0, season + " blue night haze")
		var night_color := env.fog_light_color
		sky._update(14.0)
		_check(is_zero_approx(_parameter("night_amount")), season + " no daytime stars")
		_check(is_zero_approx(_parameter("moon_visibility")), season + " no daytime moon")
		_check(env.fog_light_color.get_luminance() > night_color.get_luminance() * 3, season + " day/night haze follows sky")
		var events: Dictionary = sky.current_event_hours()
		for event in ["sunrise_start", "sunrise", "sunrise_end", "sunset_start", "sunset", "sunset_end"]:
			sky._update(float(events[event]) - .0001)
			var before: float = _parameter("night_amount")
			sky._update(float(events[event]) + .0001)
			_check(absf(before - _parameter("night_amount")) < .001, season + " continuous " + event)
		_set_weather("foggy", 0.7667)
		_check(env.fog_density > .7 and env.fog_depth_end < 200, season + " foggy atmosphere")
		_check(_parameter("night_amount") < .25, season + " weather veils stars")
		_set_weather("clear", 0.7667)
		_check(env.fog_density < .21 and env.fog_depth_begin > 89, season + " clear weather restores light haze")
	_check_sun_path()
	var moon_id: int = sky._moon.get_instance_id()
	for i in range(3): sky.rebind_to_current_scene()
	_check(sky._moon.get_instance_id() == moon_id, "rebind reuses moon instead of stacking lights")
	_check(current_scene.get_child_count() == 4, "one environment, camera, sun and moon")
	var previous := current_scene
	_setup_scene()
	previous.queue_free()
	sky.rebind_to_current_scene()
	await process_frame
	_set_weather("clear", 0.7667)
	_check(sky._env == env and is_instance_valid(sky._moon), "scene replacement rebinds atmosphere and moon")
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	sky._update(0.7667)
	_check(env.sky_custom_fov == camera.fov, "orthographic sky has finite angular field")
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	sky._update(0.7667)
	_check(is_zero_approx(env.sky_custom_fov), "perspective sky follows camera lens")
	if DisplayServer.get_name() != "headless": await _render_checks()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(captures))
	FileAccess.open(captures + "checks.json", FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures}, "  "))
	print("DIORAMA_SKY_PASS " if failures.is_empty() else "DIORAMA_SKY_FAIL ", checks, " checks ", failures)
	quit(0 if failures.is_empty() else 1)

func _setup_scene() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var world_env := WorldEnvironment.new()
	env = Environment.new()
	world_env.environment = env
	scene.add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-45.0, -30.0, 0.0)   # as the world scene authors it: the yaw is the path's heading
	scene.add_child(sun)
	camera = Camera3D.new()
	scene.add_child(camera)
	camera.current = true
	camera.fov = 70
	root.size = Vector2i(1000, 700)

func _parameter(key: String) -> float:
	return float(env.sky.sky_material.get_shader_parameter(key))

## The sun's path leans (doc 24, "Sky"). With the shipped setting the midday sun stands 60 degrees
## up, on the side the owner's study showed; sunrise and sunset keep their directions; with a lean
## of 0, or no setting, it climbs straight overhead as before. The moon's path stays upright.
func _check_sun_path() -> void:
	var sun: DirectionalLight3D = sky._sun
	var settings: Dictionary = sky._settings["sun"]
	var lean := float(settings.get("path_lean_degrees", 0.0))
	var yaw: float = sky._sun_yaw
	var events: Dictionary = sky.current_event_hours()
	var midday := float(events.midday)
	_check(absf(yaw + 30.0) < 0.001, "the fixture's sun heads where the world scene's does: %s" % yaw)
	sky._update(midday)
	var noon := sun.global_basis.z
	_check(absf(_elevation(noon) - 60.0) < 0.01, "the midday sun stands 60 degrees up: %.3f" % _elevation(noon))
	_check(_near(noon, Vector3(0.4330, 0.8660, 0.25), 0.001), "the midday sun leans toward +X and a little +Z: %s" % noon)
	_check(_near(env.sky.sky_material.get_shader_parameter("sun_direction"), noon, 0.0001), "the sun's disc follows the light")
	# The study the owner picked from printed these, to two decimals, for 12:00 and 9:00 in the colony.
	for sample: Array in [[-72.80226, Vector3(0.27, 0.83, 0.49), 55.8], [-47.00565, Vector3(-0.02, 0.63, 0.77), 39.3]]:
		var pitch := float(sample[0])
		sky._apply_light(sun, Color.WHITE, pitch, yaw, 1.0, lean)
		var toward := sun.global_basis.z
		_check(_near(toward, sample[1], 0.006) and absf(_elevation(toward) - float(sample[2])) < 0.06,
			"at pitch %s the sun stands toward %s, %s degrees up: %s, %.2f" % [pitch, sample[1], sample[2], toward, _elevation(toward)])
		# The lean said the study's way: the upright pose, turned about the line from sunset to sunrise.
		var heading := Vector3(sin(deg_to_rad(yaw)), 0.0, cos(deg_to_rad(yaw)))
		var turned := Basis(heading, deg_to_rad(-lean)) * Basis.from_euler(Vector3(deg_to_rad(pitch), deg_to_rad(yaw), 0.0))
		_check(sun.global_basis.is_equal_approx(turned), "at pitch %s the light is the upright pose turned about the heading" % pitch)
	for pitch: float in [0.0, -180.0]:
		sky._apply_light(sun, Color.WHITE, pitch, yaw, 1.0, 0.0)
		var upright := sun.global_basis.z
		sky._apply_light(sun, Color.WHITE, pitch, yaw, 1.0, lean)
		_check(absf(upright.y) < 0.0001 and _near(sun.global_basis.z, upright, 0.0001),
			"%s keeps its direction under the lean: %s, was %s" % ["sunrise" if pitch == 0.0 else "sunset", sun.global_basis.z, upright])
	# A rebind reads the heading from the light again: it must find the path's, not the leaned sun's.
	sky._update(midday)
	sky.rebind_to_current_scene()
	sky._update(midday)
	_check(_near(sun.global_basis.z, noon, 0.0001), "a rebind keeps the leaned sun's heading: %s" % sun.global_basis.z)
	sky._update(float(events.midnight))
	_check(_near(sky._moon.global_basis.z, Vector3.UP, 0.0001), "the moon's path does not lean: %s" % sky._moon.global_basis.z)
	for absent: bool in [false, true]:
		if absent: settings.erase("path_lean_degrees")
		else: settings["path_lean_degrees"] = 0.0
		sky._build_curves()
		sky._update(midday)
		_check(_near(sun.global_basis.z, Vector3.UP, 0.0001),
			"%s the midday sun is straight overhead, as before: %s" % ["with no lean setting" if absent else "at a lean of 0", sun.global_basis.z])
	settings["path_lean_degrees"] = lean
	sky._build_curves()

func _elevation(toward: Vector3) -> float:
	return rad_to_deg(asin(clampf(toward.normalized().y, -1.0, 1.0)))

func _near(a: Vector3, b: Vector3, tolerance: float) -> bool:
	return absf(a.x - b.x) < tolerance and absf(a.y - b.y) < tolerance and absf(a.z - b.z) < tolerance

func _set_weather(id: String, hour: float) -> void:
	clock.hour = hour
	weather.set_weather("base:weather:" + id)
	for i in range(240): sky._update(hour)

func _snapshot(name: String) -> Image:
	for i in range(12): await process_frame
	await RenderingServer.frame_post_draw
	var capture := root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(captures))
	capture.save_png(captures + name + ".png")
	return capture

func _render_checks() -> void:
	for i in range(4):
		camera.rotation = Vector3(-.3, float(i) * PI / 2.0, 0)
		var a := await _snapshot("orbit_" + str(i))
		camera.position += Vector3(300, 100, -200)
		var b := await _snapshot("translated_" + str(i))
		_check(a.get_data() == b.get_data(), "sky is stationary under translation at yaw " + str(i))
		var bright := 0
		for x in range(a.get_width()):
			for y in range(a.get_height()):
				if a.get_pixel(x,y).get_luminance() > .3: bright += 1
		_check(bright > 20 and bright < 10000, "star points visible below horizon at yaw " + str(i))
		camera.rotation.y += TAU
		var wrapped := await _snapshot("wrapped_" + str(i))
		var delta := 0.0
		for x in range(0, a.get_width(), 4):
			for y in range(0, a.get_height(), 4): delta += absf(a.get_pixel(x,y).get_luminance() - wrapped.get_pixel(x,y).get_luminance())
		_check(delta < 1.0, "full turn has no panorama seam " + str(i))

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)
