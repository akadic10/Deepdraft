extends SceneTree

## Native-renderer regression: each side of a thin door must sample its own
## side of the room seal, including rotated doors and animated leaves.
const OUTPUT := "res://tmp/door_lighting_20261011/"
var lighting_script
var failures: Array[String] = []
var measurements: Array[Dictionary] = []
var stage: Node3D
var camera: Camera3D
var furniture
var field
var world
var blocks
var rooms

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	create_timer(180).timeout.connect(func(): push_error("Door lighting test timed out"); quit(1))
	if not "/door_lighting_20261011/" in OS.get_user_data_dir().replace("\\", "/"):
		push_error("DoorLightingTest requires isolated APPDATA"); quit(1); return
	for id in ["SaveManager", "WorldClock", "TaskManager", "RoomManager", "StockpileManager", "SkyController", "WeatherManager"]:
		root.get_node(id).set_process(false)
	root.get_node("WorldClock").set_paused(true)
	var generator = root.get_node("WorldGenerator")
	generator.world_seed = 1234
	generator._maps_ready = false
	world = root.get_node("WorldData")
	blocks = root.get_node("BlockRegistry")
	rooms = root.get_node("RoomManager")
	lighting_script = load("res://scripts/components/UndergroundLighting.gd")
	root.size = Vector2i(960, 720)
	stage = Node3D.new()
	root.add_child(stage)
	current_scene = stage
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("71838f")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = .8
	environment.environment.ambient_light_sky_contribution = 0.0
	stage.add_child(environment)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 6
	stage.add_child(camera)
	camera.current = true
	var sun := DirectionalLight3D.new()
	camera.add_child(sun)
	furniture = load("res://scripts/systems/FurniturePlacementController.gd").new()
	stage.add_child(furniture)
	furniture.set_process(false)
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	for width in [4, 2, 3]:
		for yaw in range(4):
			await _door_case(width, yaw)
			if "--baseline" in OS.get_cmdline_user_args(): break
		if "--baseline" in OS.get_cmdline_user_args(): break
	FileAccess.open(OUTPUT + "checks.json", FileAccess.WRITE).store_string(JSON.stringify({"failures": failures, "measurements": measurements}, "  "))
	print("DoorLightingTest: ", "PASS" if failures.is_empty() else str(failures))
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _door_case(width: int, yaw: int) -> void:
	var key := "base:furniture:door" if width == 2 else "base:furniture:log_door_%d" % width
	var origin := Vector3i(128 + width * 32, 20, 128 + yaw * 32)
	var definition: Dictionary = furniture.get_defs()[key]
	furniture._install(key, definition, origin, yaw, "base:material:pine")
	var piece = furniture._installed[furniture._next_installed_id - 1]
	var model: Node3D = piece.node
	model.get_node("DoorAnimation").set_process(false)
	var stone: int = blocks.get_id("base:terrain:rock:rock01")
	# Physical room behind local +Z, open daylight in front of local -Z.
	for x in range(width + 2):
		for z in range(8):
			for y in range(-1, 5):
				var cell := Vector3i((model.to_global(Vector3(x - width * .5 - .5, y + .5, z))).floor())
				var wall := x == 0 or x == width + 1 or z == 7 or y == 4 or y == -1
				world.set_block(cell.x, cell.y, cell.z, stone if wall else blocks.AIR_ID)
	field = lighting_script.new()
	stage.add_child(field)
	lighting_script.bind_world_tree(model)
	await _settle()
	if width == 4 and yaw == 1:
		var saved: Dictionary = JSON.parse_string(JSON.stringify(furniture.serialize_state()))
		var installed_id: int = piece.installed_id
		furniture._teardown_installed(installed_id, false)
		furniture.restore_state(saved)
		piece = furniture._installed[installed_id]
		model = piece.node
		model.get_node("DoorAnimation").set_process(false)
		await _settle()
	_expect(field.sky_at(Vector3i(model.to_global(Vector3(0, 2, -1)).floor())) == 1.0, "outside is daylight: %d/%d" % [width, yaw])
	_expect(field.sky_at(Vector3i(model.to_global(Vector3(0, 2, 2)).floor())) == 0.0, "room remains sealed: %d/%d" % [width, yaw])
	var values := {"width": width, "yaw": yaw}
	for side in [-1, 1]:
		var target := model.to_global(Vector3(0, 1.8, 0))
		camera.position = model.to_global(Vector3(0, 1.8, side * 6.0))
		camera.look_at(target)
		var point := model.to_global(Vector3(-.55, 1.3, side * .25))
		var label := "%d_%d_%s" % [width, yaw, "outdoor" if side < 0 else "indoor"]
		var actual := _sample(await _capture(label), point)
		for mesh in model.find_children("*", "MeshInstance3D", true, false): mesh.set_instance_shader_parameter("actor_sky_access", 1.0)
		var reference := _sample(await _capture(label + "_daylight_reference"), point)
		_expect(reference > .2, "reference face receives daylight: " + label)
		for mesh in model.find_children("*", "MeshInstance3D", true, false): mesh.set_instance_shader_parameter("actor_sky_access", -1.0)
		values["outdoor" if side < 0 else "indoor"] = actual
		values["reference_%d" % side] = reference
		if side < 0:
			_expect(actual > reference * .8, "outdoor face retains daylight: " + label)
		else:
			_expect(actual < reference * .18, "indoor face stays dark: " + label)
			if width == 4 and yaw == 0:
				var torch_light := OmniLight3D.new()
				torch_light.light_color = Color("ffbf75")
				torch_light.omni_range = 6.0
				stage.add_child(torch_light)
				torch_light.position = model.to_global(Vector3(0, 2, 2))
				values["torchlit_inside"] = _sample(await _capture("torchlit_inside"), point)
				_expect(values.torchlit_inside > actual + .08, "local firelight still lights the room-facing wood")
				torch_light.free()
	measurements.append(values)
	# Hinge rotation must not rotate the stored doorway's lighting boundary.
	# Starter doors consist only of the moving leaves, with no fixed frame.
	var animation = model.get_node("DoorAnimation")
	for direction in [-1.0, 1.0]:
		for angle in [45.0, 90.0]:
			for i in animation._hinges.size():
				animation._hinges[i].rotation.y = deg_to_rad(angle) * direction * (1.0 if i == 0 else -1.0)
			var leaf: Node3D = model.find_child("leaf_left", true, false)
			var local_point := Vector3(-width * .5 + 1.35, 1.3, -.25)
			var point := leaf.to_global(local_point)
			var normal := -leaf.global_basis.z.normalized()
			camera.position = point + normal * 5
			camera.look_at(point)
			var label := "%d_%d_open_%d_%d" % [width, yaw, direction, angle]
			var value := _sample(await _capture(label), point)
			values[label] = {"luminance": value, "depth": model.to_local(point).z}
			# Left leaf swung toward the exterior is exposed; the leaf swung
			# into the sealed room remains dark even with an exterior-facing normal.
			var outside: bool = model.to_local(point).z < -.5
			_expect(value > .15 if outside else value < .12, "moving leaf follows physical side: " + label)
	furniture._teardown_installed(piece.installed_id, false)
	field.free()
	await process_frame

func _settle() -> void:
	while field.is_updating(): await process_frame
	for i in range(3): await process_frame

func _capture(label: String) -> Image:
	for i in range(3): await process_frame
	await RenderingServer.frame_post_draw
	var capture := root.get_texture().get_image()
	if "--capture" in OS.get_cmdline_user_args() or "--baseline" in OS.get_cmdline_user_args(): capture.save_png(OUTPUT + label + ".png")
	return capture

func _sample(capture: Image, point: Vector3) -> float:
	var pixel := Vector2i(camera.unproject_position(point))
	var total := 0.0
	for x in range(-2, 3):
		for y in range(-2, 3): total += capture.get_pixel(pixel.x + x, pixel.y + y).get_luminance()
	return total / 25.0

func _expect(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
