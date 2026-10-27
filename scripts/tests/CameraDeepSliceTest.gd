extends SceneTree

## The camera comes down to a deep slice under high ground (the todo "The camera can't come
## close to a deep slice under high ground", fixed 2026-10-26). With the slice cut deep under a
## mountain:
## - wheel zoom aims at the cut floor and gets as close to it as to open ground;
## - the middle-drag grab and the orbit pivot sit on the cut floor, not the hidden mountain top;
## - the floor guard follows the visible floor: down into a room mined under the cut and a cave
##   the colony found, never below water standing there, never into a cave it has not found
##   (Hard Rule 11);
## - raising the slice again lifts the camera clear of the mountain.
## Wheel, middle and right buttons go through real input; the pointer moves as the OS moves it.

class Terrain extends Node:   # stands in for WorldRenderer: the slice plane and found caves
	var slice_y := 0
	var caves := {}
	func discovered_cave_blocks() -> Dictionary: return caves

class Pond extends RefCounted:   # stands in for WaterManager's flow: water standing in cells
	var wet := {}
	func depth_at(point: Vector3i) -> float: return 1.0 if wet.has(point) else 0.0

const OPEN_GROUND := 20
const PEAK := 100                             # the mountain covers x and z 200 to 329
const CUT := 40                               # the slice plane, 60 blocks under the peak
const OPEN := Vector3(100.5, OPEN_GROUND + 1, 100.5)
const FLOOR := Vector3(264.5, CUT + 1, 264.5) # the cut floor's top face, mid-mountain
const CAVE := 7
const CAVE_FLOOR := 35                        # its air runs from 36 up through the cut
const ROOM_FLOOR := 36                        # a room mined from 37 up through the cut
const CAVE_CENTRE := Vector3(300.5, 0, 217.5)
const ROOM_CENTRE := Vector3(224.5, 0, 300.5)

var failures: Array[String] = []
var world
var terrain: Terrain
var rig
var camera: Camera3D


func _init() -> void: _run.call_deferred()


func _run() -> void:
	create_timer(90).timeout.connect(func(): push_error("Camera deep slice timed out"); quit(1))
	for id: String in ["SaveManager", "WorldClock", "RoomManager", "TaskManager", "StockpileManager", "WaterManager", "AmbientAudio"]:
		root.get_node(id).set_process(false)
	world = root.get_node("WorldData")
	_build_mountain()
	root.size = Vector2i(1280, 720)
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	terrain = Terrain.new()
	terrain.slice_y = world.MAX_Y
	terrain.add_to_group("terrain_overview_renderer")
	scene.add_child(terrain)
	rig = load("res://scripts/systems/Camera.gd").new()
	scene.add_child(rig)
	camera = rig.camera_node
	await process_frame
	var centre := root.get_visible_rect().size * .5
	_point_at(centre)
	_expect(root.get_mouse_position().distance_to(centre) < .5, "the test pointer reaches the camera: %s" % root.get_mouse_position())

	var open: Dictionary = await _zoom_in_on(OPEN)
	terrain.slice_y = CUT
	var cut: Dictionary = await _zoom_in_on(FLOOR)
	print("Zoomed in: open ground %s, cut floor %s" % [open, cut])
	_expect(open.aim == OPEN_GROUND, "on open ground the wheel aims at the ground: %s" % open)
	_expect(cut.aim == CUT, "under the mountain the wheel aims at the cut floor, not the hidden top: %s" % cut)
	_expect(absf(cut.height - open.height) < .25 and absf(cut.gap - open.gap) < .25 and cut.height < 3.0,
		"the camera comes as close to the cut floor as to open ground: open %s, cut %s" % [open, cut])
	terrain.slice_y = world.MAX_Y
	await _settle()
	_expect(camera.global_position.y >= PEAK + 1.4, "raising the slice lifts the camera clear of the mountain: %s" % camera.global_position)
	terrain.slice_y = CUT

	await _drag_test()
	await _orbit_test()
	await _floor_test()
	for failure: String in failures: push_error(failure)
	print("CAMERA_DEEP_SLICE_OK" if failures.is_empty() else "CAMERA_DEEP_SLICE_FAIL")
	quit(0 if failures.is_empty() else 1)


## Open ground at 20 with a mountain plateau at 100. Its middle holds a cave the colony has
## not found and a room it mined, both cut open by the slice at 40.
func _build_mountain() -> void:
	var generator = root.get_node("WorldGenerator")
	generator.heightmap.resize(world.WORLD_SIZE_X * world.WORLD_SIZE_Z)
	generator.heightmap.fill(OPEN_GROUND)
	for x in range(200, 330):
		for z in range(200, 330):
			generator.heightmap[x * world.WORLD_SIZE_Z + z] = PEAK
	generator.waterline_map.resize(world.WORLD_SIZE_X * world.WORLD_SIZE_Z)
	generator.waterline_map.fill(-1)
	generator._maps_ready = true
	generator._cache_block_ids()
	generator._build_noise_instances()   # mining compares each cell with its generated rock
	for x in range(293, 308):
		for z in range(210, 225):
			generator._cave_layout.columns[x * world.WORLD_SIZE_Z + z] = Vector3i(CAVE_FLOOR, CUT, CAVE)
	var air: int = root.get_node("BlockRegistry").AIR_ID
	for x in range(220, 229):
		for z in range(296, 305):
			for y in range(ROOM_FLOOR + 1, CUT + 1): world.set_block(x, y, z, air)


## Frames the top face `point` from 60 blocks away, then turns the wheel toward it until the
## camera stops. Returns the ground block the wheel aimed at, the camera's height above the
## framed ground block and its distance from the aimed point.
func _zoom_in_on(point: Vector3) -> Dictionary:
	rig.focus_world_position(point, 60.0)
	await _settle()
	_point_at(camera.unproject_position(point))
	var target: Dictionary = rig._zoom_target_point()
	if target.is_empty():
		return {"aim": -1, "height": INF, "gap": INF}
	var aim: Vector3 = target.point
	for notch in 40:
		_button(MOUSE_BUTTON_WHEEL_UP, true)
		await process_frame
	await _settle()
	var eye := camera.global_position
	return {"aim": int(aim.y), "height": snappedf(eye.y - (point.y - 1), .01), "gap": snappedf(eye.distance_to(aim), .01)}


## Middle-drag grabs the cut floor and keeps the grabbed point under the pointer.
func _drag_test() -> void:
	rig.focus_world_position(FLOOR, 30.0)
	await _settle()
	var start := camera.unproject_position(FLOOR + Vector3(-3, 0, 0))
	var finish := camera.unproject_position(FLOOR + Vector3(4, 0, -5))
	_point_at(start)
	_button(MOUSE_BUTTON_MIDDLE, true)
	_expect(rig._dragging and is_equal_approx(rig._drag_grab.y, CUT), "middle-drag grabs the cut floor: %s" % rig._drag_grab)
	_point_at(finish)
	for frame in 3: await process_frame
	var under: Vector2 = camera.unproject_position(rig._drag_grab)
	_expect(under.distance_to(finish) < 2.0, "the grabbed floor stays under the pointer: %s, pointer %s" % [under, finish])
	_button(MOUSE_BUTTON_MIDDLE, false)


## A pivot left high above the cut floor, where the hidden top used to hold it, moves onto the
## floor when orbit starts.
func _orbit_test() -> void:
	rig.focus_world_position(Vector3(FLOOR.x, 70, FLOOR.z), 40.0)
	await _settle()
	_point_at(root.get_visible_rect().size * .5)
	_button(MOUSE_BUTTON_RIGHT, true)
	var turn := InputEventMouseMotion.new()
	turn.position = root.get_mouse_position()
	turn.relative = Vector2(20, 0)
	root.push_input(turn, true)
	_expect(rig._orbit_active and absf(rig._target_pos.y - CUT) < .01, "orbit pivots on the cut floor: %s" % rig._target_pos)
	_button(MOUSE_BUTTON_RIGHT, false)


## The floor guard and the surface march follow the floor the slice shows.
func _floor_test() -> void:
	_expect(_ground_at(ROOM_CENTRE) == ROOM_FLOOR, "a room mined under the cut is open to the camera: %d" % _ground_at(ROOM_CENTRE))
	_expect(await _lowest_eye(ROOM_CENTRE, ROOM_FLOOR + 2) < CUT + 1, "the camera comes down into the mined room")
	# Water standing in the room is its ground, as a lake's surface is. The stand-in water lives
	# only for these two calls: every frame's audio listener would ask it for more.
	var dry_eye: float = await _lowest_eye(ROOM_CENTRE, ROOM_FLOOR + 1)
	var water = root.get_node("WaterManager")
	var pond := Pond.new()
	for x in range(220, 229):
		for z in range(296, 305):
			for y in range(ROOM_FLOOR + 1, ROOM_FLOOR + 3): pond.wet[Vector3i(x, y, z)] = true
	water.flow = pond
	water.initialized = true
	var wet_ground := _ground_at(ROOM_CENTRE)
	rig._enforce_camera_floor()
	var wet_eye: float = camera.global_position.y
	water.initialized = false
	water.flow = null
	_expect(wet_ground == ROOM_FLOOR + 2, "water standing in the room is its ground: %d" % wet_ground)
	_expect(dry_eye < ROOM_FLOOR + 3 and wet_eye >= ROOM_FLOOR + 3.4, "the camera rises above the water: dry %.2f, wet %.2f" % [dry_eye, wet_eye])
	_expect(_ground_at(CAVE_CENTRE) == CUT, "a cave not yet found is rock under the cut: %d" % _ground_at(CAVE_CENTRE))
	_expect(await _lowest_eye(CAVE_CENTRE, CAVE_FLOOR + 2) >= CUT + 1.4, "the camera never dips into a cave not yet found")
	for x in range(293, 308):
		for z in range(210, 225):
			for y in range(CAVE_FLOOR + 1, CUT + 1): terrain.caves[Vector3i(x, y, z)] = true
	_expect(_ground_at(CAVE_CENTRE) == CAVE_FLOOR, "a found cave's floor is the ground: %d" % _ground_at(CAVE_CENTRE))
	_expect(await _lowest_eye(CAVE_CENTRE, CAVE_FLOOR + 2) < CUT + 1, "the camera comes down into a found cave")
	terrain.caves = {}


## The ground block straight down at `column`, as the camera's zoom, drag and orbit find it.
func _ground_at(column: Vector3) -> int:
	var hit: Dictionary = rig._march_surface(Vector3(column.x, 120, column.z), Vector3.DOWN)
	return -1 if hit.is_empty() else int(hit.point.y)


## Asks for the closest framing on `column` with the pivot at `pivot_y`; returns the height the
## floor guard lets the camera keep.
func _lowest_eye(column: Vector3, pivot_y: float) -> float:
	rig.focus_world_position(Vector3(column.x, pivot_y, column.z), 2.0)
	await _settle()
	return camera.global_position.y


## Moves the pointer the way the OS does: a headless run reads the viewport's mouse
## position from Input.
func _point_at(screen: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = screen
	motion.global_position = screen
	Input.parse_input_event(motion)
	Input.flush_buffered_events()


func _button(index: MouseButton, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = index
	event.pressed = pressed
	event.position = root.get_mouse_position()
	event.global_position = event.position
	root.push_input(event, true)


## Lets smoothing, the spring arm and the floor guard come to rest.
func _settle() -> void:
	await create_timer(1.2).timeout


func _expect(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
