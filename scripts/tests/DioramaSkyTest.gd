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
	scene.add_child(sun)
	camera = Camera3D.new()
	scene.add_child(camera)
	camera.current = true
	camera.fov = 70
	root.size = Vector2i(1000, 700)

func _parameter(key: String) -> float:
	return float(env.sky.sky_material.get_shader_parameter(key))

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
