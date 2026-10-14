extends SceneTree

class Slice extends Node:
	var height := 47
	func get_slice_y() -> int: return height
class Sleeper extends Node3D:
	func is_resting() -> bool: return true
class Fires extends Node3D:
	var _installed := {}

var failures: Array[String] = []

func _init() -> void: _run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func _run() -> void:
	for id: String in ["SaveManager", "WorldClock", "RoomManager", "TaskManager", "StockpileManager", "WaterManager", "AmbientAudio"]:
		root.get_node(id).set_process(false)
	var generator = root.get_node("WorldGenerator")
	generator.heightmap.resize(1024 * 1024)
	generator.heightmap.fill(43)
	generator._maps_ready = true
	generator._cache_block_ids()
	var world = root.get_node("WorldData")
	var blocks = root.get_node("BlockRegistry")
	var rock: int = blocks.get_id("base:terrain:rock:rock01")
	for cx in range(2, 6):
		for cy in range(2, 5):
			for cz in range(2, 6):
				var chunk := Chunk.new()
				for x in 16:
					for y in 16:
						for z in 16:
							if cy * 16 + y <= 43 or cy * 16 + y == 58: chunk.blocks[Chunk.local_index(x, y, z)] = rock
				world.submit_chunk(cx, cy, cz, chunk)
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var slice := Slice.new()
	slice.add_to_group("work_feedback_slice")
	scene.add_child(slice)
	var rig = load("res://scripts/systems/Camera.gd").new()
	scene.add_child(rig)
	rig.set_process(false)
	rig.global_position = Vector3(64, 61, 64)
	var camera: Camera3D = rig.camera_node
	camera.reparent(scene)
	camera.global_position = Vector3(64, 63, 64)
	camera.look_at(Vector3(64, 44, 54))
	camera.current = true
	await process_frame
	var saved_transform: Transform3D = camera.global_transform
	var context: Dictionary = rig.get_work_audio_context()
	check(context.focus.distance_to(Vector3(64, 44.05, 54)) < .1, "centre ray reaches bedroom floor through sliced roof")
	check(float(context.zoom) > 20, "audible framing uses distance to room, not two-block spring arm")
	check(rig.get_work_audio_context() == context, "all sound owners share one cached ray per frame")
	check(camera.global_transform == saved_transform and rig.global_position == Vector3(64, 61, 64), "audio does not move camera or its pivot")
	var feedback = root.get_node("WorkFeedback")
	feedback.clear_transients()
	var clock = root.get_node("WorldClock")
	clock.paused = false
	clock.speed = 1
	var sleeper := Sleeper.new()
	scene.add_child(sleeper)
	sleeper.position = Vector3(64, 44, 54)
	check(feedback.play_snore(sleeper), "visible sleeping dwarf emits from viewed room")
	var fires := Fires.new()
	scene.add_child(fires)
	var torch := Node3D.new()
	fires.add_child(torch)
	torch.position = Vector3(66, 45, 53)
	fires._installed[1] = {"installed_id": 1, "node": torch, "def": {"fire_sound": "torch"}}
	var sound = load("res://scripts/components/FurnitureFireSound.gd").new()
	sound.furniture = fires
	fires.add_child(sound)
	sound.set_process(false)
	for i in 20: sound._process(.25)
	check(sound.voices.any(func(v): return v.gain > .025), "torch is audible despite elevated camera pivot")
	slice.height = 43
	await process_frame
	sound._process(.25)
	feedback._process(.25)
	check(sound.voices.all(func(v): return v.gain == 0), "slice still hides fire sources above cut")
	check(feedback._voices.all(func(v): return v.remaining == 0), "slice still hides sleeping dwarf above cut")
	slice.height = 47
	camera.global_position.x += 8
	await process_frame
	check(absf(rig.get_work_audio_context().focus.x - 72.0) < .1, "panning moves listening point with the viewed room")
	camera.global_transform = saved_transform
	camera.global_position += camera.global_basis.z * 10
	await process_frame
	var farther: Dictionary = rig.get_work_audio_context()
	check(farther.focus.distance_to(context.focus) < .1 and absf(farther.zoom - context.zoom - 10) < .1, "zoom changes audible distance while keeping viewed floor fixed")
	camera.global_transform = saved_transform
	var water = root.get_node("WaterManager")
	water.flow = load("res://scripts/components/WaterFlow.gd").new()
	water.flow.spans_at = func(_column: Vector2i): return [Vector2i(44,58)]
	water.initialized = true
	for x in range(63,66):
		for z in range(53,59): water.flow.seed_column(Vector3i(x,44,z),2.4)
	await process_frame
	check(absf(rig.get_work_audio_context().focus.y - 46.45) < .01, "listener follows fractional water surface instead of submerged lake bed")
	water.flow.mass.clear()
	await process_frame
	check(absf(rig.get_work_audio_context().focus.y - 44.05) < .1, "draining water restores terrain listening height")
	water.initialized = false
	slice.height = 127
	await process_frame
	check(absf(rig.get_work_audio_context().focus.y - 59.05) < .1, "full-world view listens at roof rather than hidden bedroom")
	slice.height = 47
	# The centre ray lands on a cell edge; clear both sides of that edge.
	for x in range(63, 66):
		for z in range(53, 56): world.set_block(x, 43, z, blocks.AIR_ID)
	await process_frame
	check(float(rig.get_work_audio_context().focus.y) < 44, "mining beneath the view updates listening surface")
	camera.look_at(camera.position + Vector3.UP, Vector3.FORWARD)
	await process_frame
	check(rig.get_work_audio_context().focus == rig.global_position, "sky-facing ray has finite pivot fallback")
	scene.remove_child(rig)
	check(rig.get_work_audio_context().is_empty(), "detached camera cannot read global transforms")
	rig.free()
	print("AudioListeningPointTest: ", "PASS" if failures.is_empty() else str(failures))
	quit(0 if failures.is_empty() else 1)
