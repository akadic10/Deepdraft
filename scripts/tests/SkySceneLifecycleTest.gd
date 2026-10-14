extends SceneTree

## The sky autoload survives the synchronous detach and deferred replacement
## performed by SceneTree.reload_current_scene during SaveManager loading.
var sky
var failures: Array[String] = []
var checks := 0

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	root.get_node("SaveManager").configure_storage_for_testing("user://sky_lifecycle_test")
	for id in ["SaveManager", "WorldClock", "WeatherManager", "TaskManager", "SkyController"]:
		root.get_node(id).set_process(false)
	sky = root.get_node("SkyController")
	await process_frame
	await process_frame
	root.get_node("WeatherManager").set_weather("base:weather:clear")
	for hour in [0.7667, 14.0]:
		root.get_node("WorldClock").hour = hour
		var scene := _make_scene()
		sky.rebind_to_current_scene()
		var moon: DirectionalLight3D = sky._moon
		for i in range(3): sky.rebind_to_current_scene()
		_check(sky._ready_ok and sky._moon == moon, "repeated bind retains exactly one moon")
		var old_material: ShaderMaterial = sky._sky_mat
		var old_phase: float = old_material.get_shader_parameter("cloud_rotation")
		# Exact gap reported by the player: lights still exist but have left the tree.
		root.remove_child(scene)
		_check(not sky._ready_ok, "detaching the scene immediately invalidates its sky binding")
		sky._process(.1)
		sky._update(hour + .5)
		_check(old_material.get_shader_parameter("cloud_rotation") == old_phase, "detached sky receives no updates")
		_check(sky._sun == null and sky._moon == null and sky._env == null, "scene exit releases all render references")
		if not failures.is_empty():
			scene.free()
			_finish()
			return
		scene.free()
		sky._process(.1)
		sky._update(hour)
		await process_frame
		var replacement := _make_scene()
		sky.rebind_to_current_scene()
		sky._update(hour)
		_check(sky._ready_ok and sky._sun.is_inside_tree() and sky._moon.is_inside_tree(), "new scene resumes live sky bindings")
		_check(sky._moon.get_parent() == replacement, "moon belongs to the replacement scene")
		var new_material: ShaderMaterial = sky._sky_mat
		_check(new_material != old_material, "new scene owns a fresh sky material")
		_check(float(new_material.get_shader_parameter("night_amount")) > .9 if hour < 1 else is_zero_approx(float(new_material.get_shader_parameter("night_amount"))), "restored hour selects correct day/night sky")
		# Rebind can precede freeing an old preview scene; its later exit must not
		# invalidate the replacement. Rebinding must disconnect the old listener.
		var next_scene := _make_scene()
		sky.rebind_to_current_scene()
		replacement.free()
		_check(sky._ready_ok and sky._moon.get_parent() == next_scene, "old scene exit cannot clear a newer binding")
		# Individually removed lights are also safe until the next scene bind.
		var detached_sun: DirectionalLight3D = sky._sun
		next_scene.remove_child(detached_sun)
		sky._update(hour)
		_check(is_zero_approx(float(sky._sky_mat.get_shader_parameter("sun_visibility"))), "detached sun is hidden from the backdrop")
		detached_sun.free()
		sky._moon.free()
		sky._update(hour)
		_check(is_zero_approx(float(sky._sky_mat.get_shader_parameter("moon_visibility"))), "freed moon is safe and hidden from the backdrop")
		next_scene.free()
		sky._process(.1)
	_finish()

func _make_scene() -> Node3D:
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var world_env := WorldEnvironment.new()
	world_env.environment = Environment.new()
	scene.add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	scene.add_child(sun)
	return scene

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func _finish() -> void:
	for failure in failures: push_error(failure)
	print("SKY_SCENE_LIFECYCLE_PASS " if failures.is_empty() else "SKY_SCENE_LIFECYCLE_FAIL ", checks, " checks ", failures)
	quit(0 if failures.is_empty() else 1)
