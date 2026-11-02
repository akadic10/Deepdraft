extends SceneTree

## Storm lightning (doc 24, "Lightning"; doc 291). Each storm thunder is a strike:
## the sky, clouds, fog and a light from above flash first, and the thunder follows
## after the flash's lead. Checks the flash rises and fully clears, the light is
## shadowless and reused on rebind, and thunder never starts before its flash.
## The look is judged by eye in the game.
var failures: Array[String] = []
var sky
var env: Environment


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	create_timer(60).timeout.connect(func(): push_error("Storm lightning timed out"); quit(1))
	root.get_node("SaveManager").configure_storage_for_testing("user://lightning_fixture")
	for id in ["SaveManager", "TaskManager", "WorldClock", "SkyController", "WeatherManager", "AmbientAudio"]:
		root.get_node(id).set_process(false)
	sky = root.get_node("SkyController")
	var clock = root.get_node("WorldClock")
	var weather = root.get_node("WeatherManager")
	clock.set_paused(true)
	await process_frame
	await process_frame
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
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.current = true
	sky.rebind_to_current_scene()
	clock.hour = 1.0
	weather.set_weather("base:weather:storm")
	for i in 240: sky._update(1.0)
	var calm_fog: Color = env.fog_light_color
	var calm_cloud: Color = env.sky.sky_material.get_shader_parameter("cloud_color")
	_expect(scene.get_node_or_null("Lightning") == null, "no lightning light before the first strike")

	# A strike flashes the sky, clouds, fog and open ground, then clears completely.
	sky.flash_lightning(1.0)
	_frames(1)
	var bolt = scene.get_node_or_null("Lightning")
	_expect(bolt != null and bolt.visible and bolt.light_energy > 1.0, "the strike lights a light from above")
	_expect(bolt != null and not bolt.shadow_enabled, "the lightning light casts no shadows; sky access keeps rooms dark")
	_expect(env.fog_light_color.get_luminance() > calm_fog.get_luminance() + 0.1, "the fog and distant land flash: %s -> %s" % [calm_fog, env.fog_light_color])
	var flash_cloud: Color = env.sky.sky_material.get_shader_parameter("cloud_color")
	_expect(flash_cloud.get_luminance() > calm_cloud.get_luminance() + 0.1, "the clouds flash")
	var peak: float = sky.lightning_level()
	# The last flicker starts within 0.4 s; by 0.75 s every flicker has faded.
	_frames(44)
	_expect(sky.lightning_level() < peak * 0.5, "the flash fades")
	_frames(70)
	_expect(sky.lightning_level() == 0.0 and not bolt.visible, "after the strike the light is off")
	_expect(env.fog_light_color.is_equal_approx(calm_fog), "the sky returns exactly to the storm's colours")
	for i in 3: sky.rebind_to_current_scene()
	sky.flash_lightning(1.0)
	_frames(1)
	var lights := scene.get_children().filter(func(n: Node) -> bool: return n.name.begins_with("Lightning"))
	_expect(lights.size() == 1, "rebinding reuses the one lightning light")
	_frames(120)

	# Thunder follows its flash: the strike flashes now and starts no thunder yet.
	var ambience = root.get_node("AmbientAudio")
	var voice := AudioStreamPlayer3D.new()
	scene.add_child(voice)
	ambience.calls.append({"player": voice, "kind": "", "left": 0.0, "gain": 0.0})
	ambience.targets = {"thunder": 1.0}
	ambience._context = {"focus": Vector3.ZERO}
	var lead: Array = ambience.config.calls.thunder.flash_lead
	ambience._strike()
	_frames(1)
	_expect(sky.lightning_level() > 0.0, "a thunder call strikes lightning")
	_expect(ambience._thunder_due >= float(lead[0]) and ambience._thunder_due <= float(lead[1]), "its thunder waits within the lead: %s" % ambience._thunder_due)
	_expect(ambience.calls[0].left == 0.0, "no thunder before the flash")
	ambience._tick_thunder(float(lead[0]) * 0.5)
	_expect(ambience.calls[0].left == 0.0, "no thunder during the lead")
	ambience._tick_thunder(float(lead[1]))
	_expect(ambience.calls[0].kind == "thunder" and ambience.calls[0].left > 0.0, "the thunder follows")

	# The nearest strikes crack (recorded close thunder); the rest rumble in the distance.
	_expect(ambience._streams.thunder_near.size() == 3 and ambience._streams.thunder_near.all(func(s) -> bool: return s != null), "three recorded near-strike cracks load")
	for far: float in [0.05, 0.9]:
		ambience.calls[0].left = 0.0
		ambience._strike(far)
		ambience._tick_thunder(float(lead[1]) + 0.1)
		var path: String = ambience.calls[0].player.stream.resource_path
		var near: bool = path.get_file().begins_with("thunder_near_")
		_expect(near == (far < float(ambience.config.calls.thunder.near_share)), "strike at %.2f plays %s" % [far, path.get_file()])
		_expect(ambience.calls[0].kind == "thunder", "a crack is still the thunder call, on its bus and level")
	_frames(120)
	ambience.calls.clear()

	for failure in failures: push_error(failure)
	print("StormLightningTest: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)


## Runs the sky as the game does, one 60 fps frame at a time.
func _frames(count: int) -> void:
	for i in count: sky._process(1.0 / 60.0)


func _expect(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
