extends SceneTree

## Rain and snow cover the whole view (doc 24, "Rain and snow"; doc 291). Until
## 2026-11-01 every drop fell within 24 blocks of the screen centre, a small patch
## of a zoomed-out view. Checks that the drawn tiles reach every screen corner at
## each zoom and screen shape, keep their world places while the camera pans, keep
## drops per screen area even across zoom, and that drops land on roofs, dug
## floors and water. Weather fades in and out; snow uses the same field. The
## shader itself is judged by eye in the game.
var failures: Array[String] = []
var rain
var camera := Camera3D.new()
var view := View.new()
var slice := Slice.new()

class View extends Node3D:
	var zoom := 85.0
	var focus := Vector3.ZERO
	func get_work_audio_context() -> Dictionary:
		return {"focus": focus, "zoom": zoom}

class Slice extends Node:
	var height := 127
	func get_slice_y() -> int: return height


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	create_timer(60).timeout.connect(func(): push_error("Weather precipitation timed out"); quit(1))
	for id in ["SaveManager", "SkyController", "WeatherManager", "TaskManager", "RoomManager", "StockpileManager", "WaterManager", "AmbientAudio"]:
		root.get_node(id).set_process(false)
	var generator = root.get_node("WorldGenerator")
	generator.world_seed = 1234
	await process_frame
	await process_frame
	generator._maps_ready = true
	generator.heightmap.resize(1024 * 1024)
	generator.heightmap.fill(20)
	generator.waterline_map.resize(1024 * 1024)
	generator.waterline_map.fill(-1)
	generator._cache_block_ids()
	# Digging fills chunks with the real generator, ore noise included.
	generator._build_noise_instances()
	var clock = root.get_node("WorldClock")
	clock.set_process(false)
	clock.paused = false
	clock.speed = 1
	var weather = root.get_node("WeatherManager")
	var scene := Node3D.new()
	root.add_child(scene)
	view.add_to_group("work_audio_view")
	slice.add_to_group("work_feedback_slice")
	scene.add_child(view)
	scene.add_child(slice)
	camera.fov = 45.0
	camera.far = 1024.0
	scene.add_child(camera)
	camera.current = true
	rain = load("res://scripts/components/WeatherPrecipitation.gd").new()
	scene.add_child(rain)
	rain.set_process(false)
	var focus := Vector3(512, 21, 512)

	# Storm fades in rather than switching on.
	weather.set_weather("base:weather:storm")
	await _look(focus, 85.0, 50.0, 0.0, Vector2i(1920, 540))
	_step(0.5, 2)
	_expect(rain.amount > 0.0 and rain.amount < 1.0 and rain.visual.visible, "storm fades in: %.2f" % rain.amount)
	_step(0.5, 8)
	_expect(rain.amount == 1.0, "storm fully in after the fade")
	_expect(rain.landing_at(Vector2i(512, 512)) == 21.0, "untouched ground lands on the heightmap top: %s" % rain.landing_at(Vector2i(512, 512)))

	# The reported bug: rain only in the centre. Every corner of the view is covered.
	for case: Array in [[85.0, 50.0, 0.0, Vector2i(1920, 540)], [180.0, 50.0, 45.0, Vector2i(1920, 540)],
			[20.0, 50.0, 0.0, Vector2i(1280, 720)], [140.0, 80.0, 30.0, Vector2i(1280, 720)], [60.0, 30.0, 0.0, Vector2i(1280, 720)]]:
		await _look(focus, case[0], case[1], case[2], case[3])
		_step(0.05, 1)
		var label := "zoom %d pitch %d yaw %d at %s" % [case[0], case[1], case[2], case[3]]
		var missed := _uncovered(focus.y, float(case[0]) * 3.5)
		_expect(missed.is_empty(), label + ": rain reaches every screen point, missed " + str(missed))
		_expect(rain.visual.custom_aabb.has_point(Vector3(focus.x, 40, focus.z)), label + ": bounds hold the view")
	await _look(focus, 85.0, 50.0, 0.0, Vector2i(1920, 540))
	_step(0.05, 1)
	_expect(rain.visible_streaks > 2000, "the storm draws thousands of drops at default zoom: %d" % rain.visible_streaks)
	_expect(rain.visual.multimesh.visible_instance_count <= rain.visual.multimesh.instance_count, "drawn drops stay inside the budget")

	# Drops keep their world places: panning keeps each tile's place, size and level.
	var sizes: Vector2 = rain.tile_sizes
	var marker := Vector2(focus.x + 10, focus.z + 10)
	var before := _tile_at(marker)
	await _look(focus + Vector3(13.3, 0, -7.1), 85.0, 50.0, 0.0, Vector2i(1920, 540))
	_step(0.05, 1)
	_expect(rain.tile_sizes == sizes and before != Vector3(-1, -1, -1) and _tile_at(marker) == before, "a pan keeps the same world tiles")
	await _look(focus, 88.0, 50.0, 0.0, Vector2i(1920, 540))
	_step(0.05, 1)
	_expect(rain.tile_sizes == sizes, "a small zoom keeps the tile sizes")

	# Drops per screen area stay even across zoom, including a level change at 64.
	var even := []
	for zoom: float in [63.9, 64.1, 80.0, 100.0, 127.9]:
		await _look(focus, zoom, 50.0, 0.0, Vector2i(1280, 720))
		_step(0.05, 1)
		var shown: Vector2 = rain.material.get_shader_parameter("drops_shown")
		even.append((shown.x / pow(rain.tile_sizes.x, 2) + shown.y / pow(rain.tile_sizes.y, 2)) * zoom * zoom)
	for value: float in even:
		_expect(absf(value / even[0] - 1.0) < 0.01, "drops per screen area stay even across zoom: %s" % [even])

	# Drops land on what is really there: built roofs, dug floors, water.
	var rock: int = root.get_node("BlockRegistry").get_id("base:terrain:rock:rock01")
	var air: int = root.get_node("BlockRegistry").AIR_ID
	var world = root.get_node("WorldData")
	world.set_block(512, 26, 512, rock)
	rain._read_landing(1000000)
	_expect(rain.landing_at(Vector2i(512, 512)) == 27.0, "a built roof stops drops on top of it")
	slice.height = 24
	_step(0.05, 1)
	_expect(float(rain.material.get_shader_parameter("slice_top")) == 25.0 and rain.landing_at(Vector2i(512, 512)) >= 25.0,
		"a roof the slice hides still holds drops above the cut, so none fall into the room")
	slice.height = 127
	world.set_block(512, 26, 512, air)
	rain._read_landing(1000000)
	_expect(rain.landing_at(Vector2i(512, 512)) == 21.0, "removing the roof lets drops reach the ground again")
	world.set_block(513, 20, 512, air)
	world.set_block(513, 19, 512, air)
	world.set_block(514, 10, 512, air)
	rain._read_landing(1000000)
	_expect(rain.landing_at(Vector2i(513, 512)) == 19.0, "drops fall into a dug pit")
	_expect(rain.landing_at(Vector2i(514, 512)) == 21.0, "a tunnel under the surface leaves the ground as the landing")
	var water = root.get_node("WaterManager")
	var flow = load("res://scripts/components/WaterFlow.gd").new()
	var pool := Vector3i(520, 21, 512)
	flow.mass[pool] = roundi(0.6 * flow.UNITS)
	water.flow = flow
	water.initialized = true
	water.surface_changed.emit([pool])
	rain._read_landing(1000000)
	_expect(absf(rain.landing_at(Vector2i(520, 512)) - 21.6) < 0.01, "drops land on the water surface, not the bed: %s" % rain.landing_at(Vector2i(520, 512)))
	flow.mass[pool] = roundi(3.25 * flow.UNITS)
	water.surface_changed.emit([pool])
	rain._read_landing(1000000)
	_expect(absf(rain.landing_at(Vector2i(520, 512)) - 24.25) < 0.01, "deep water raises the landing to its surface")
	flow.mass.erase(pool)
	water.surface_changed.emit([pool])
	rain._read_landing(1000000)
	_expect(rain.landing_at(Vector2i(520, 512)) == 21.0, "dried ground is the landing again")
	water.initialized = false
	water.flow = null

	# Paused time freezes the drops.
	clock.paused = true
	var frozen: float = rain._time
	_step(0.5, 2)
	_expect(rain._time == frozen, "pause freezes the fall")
	clock.paused = false
	_step(0.5, 1)
	_expect(rain._time != frozen, "the fall resumes after pause")

	# Clear weather fades the storm out, then hides it.
	weather.set_weather("base:weather:clear")
	_step(0.5, 1)
	_expect(rain.amount > 0.0 and rain.visual.visible, "clear weather fades the storm out rather than cutting it")
	_step(0.5, 8)
	_expect(not rain.visual.visible and rain.visible_streaks == 0, "clear weather removes precipitation")

	# Snow uses the same field after the rain has faded out.
	weather.set_weather("base:weather:storm")
	_step(0.5, 10)
	weather.set_weather("base:weather:snow")
	_step(0.5, 2)
	_expect(int(rain.material.get_shader_parameter("style")) == 0 and rain.amount < 1.0, "the storm fades out before snow")
	_step(0.5, 18)
	_expect(int(rain.material.get_shader_parameter("style")) == 1 and rain.amount == 1.0 and rain.visible_streaks > 0, "snow falls in the same field")
	await _look(focus, 85.0, 50.0, 0.0, Vector2i(1920, 540))
	_step(0.05, 1)
	_expect(_uncovered(focus.y, 300.0).is_empty(), "snow covers the view too")

	for failure in failures: push_error(failure)
	print("WeatherPrecipitationTest: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)


func _look(focus: Vector3, zoom: float, pitch: float, yaw: float, screen: Vector2i) -> void:
	if root.size != screen:
		root.size = screen
		await process_frame
	var down := deg_to_rad(pitch)
	var turn := deg_to_rad(yaw)
	camera.global_position = focus + Vector3(sin(turn) * cos(down), sin(down), cos(turn) * cos(down)) * zoom
	camera.look_at(focus)
	view.focus = focus
	view.zoom = zoom


func _step(seconds: float, times: int) -> void:
	for i in times: rain._process(seconds)


## Screen points (as fractions) whose ground has no drawn tile.
func _uncovered(ground: float, reach: float) -> Array:
	var missed := []
	var rect: Vector2 = root.get_visible_rect().size
	for x: float in [0.02, 0.25, 0.5, 0.75, 0.98]:
		for y: float in [0.02, 0.5, 0.98]:
			var from := camera.project_ray_origin(Vector2(x, y) * rect)
			var direction := camera.project_ray_normal(Vector2(x, y) * rect)
			if direction.y > -0.001: continue
			var along := (ground - from.y) / direction.y
			if along > reach: continue
			var point := from + direction * along
			if _tile_at(Vector2(point.x, point.z)) == Vector3(-1, -1, -1): missed.append(Vector2(x, y))
	return missed


## The drawn tile, with drops shown, holding a ground point; (-1, -1, -1) if none.
func _tile_at(point: Vector2) -> Vector3:
	var shown: Vector2 = rain.material.get_shader_parameter("drops_shown")
	for tile: Vector3 in rain.tiles:
		var size: float = rain.tile_sizes.y if tile.z > 0.5 else rain.tile_sizes.x
		if (shown.y if tile.z > 0.5 else shown.x) < 1.0: continue
		if point.x >= tile.x * size and point.x < (tile.x + 1) * size and point.y >= tile.y * size and point.y < (tile.y + 1) * size:
			return tile
	return Vector3(-1, -1, -1)


func _expect(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
