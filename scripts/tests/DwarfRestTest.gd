extends "res://scripts/tests/HaulingAnimationTest.gd"

var nav
var second
var wall_cells: Array[Vector3i] = []
var feedback

func _run() -> void:
	create_timer(100).timeout.connect(func(): push_error("Dwarf rest timeout"); quit(1))
	await _setup_fixture()
	nav = root.get_node("NavGrid")
	feedback = root.get_node("WorkFeedback")
	tasks.reset_runtime_state()
	stockpiles.reset_runtime_state()
	tasks.register_dwarf(worker)
	for item in drops._loose.keys(): drops.take(item); item.free()
	worker.position = Vector3(48.5,21,55.5)
	_wall()
	_check_awake_fatigue()
	worker._begin_sleep()
	var initial: float = worker._sleep_hours_left
	_expect(not tasks._idle_dwarves.has(worker.dwarf_id),"rest search leaves work pool")
	worker._process(.1)
	_expect(worker._sleep_hours_left == initial,"walking/searching does not refill sleep")
	_expect(await _rested(worker),"seated dwarf reaches a sheltered sleeping spot")
	_expect(worker._rest_behavior.pose=="sitting" and worker._rest_behavior._shelter.x>=0,"odd dwarf chooses supported seated pose")
	_expect(worker._body.position.y<-.35 and worker._head.position.y<-.3,"sleeper is visibly lowered to the ground")
	_expect(worker.get_node_or_null("SleepIndicator")==null,"no sleep emoji remains")
	_expect(not worker._head.get_node("MeshEyes").visible,"resting eyes close")
	var saved: Dictionary = worker.serialize_state()
	var pos: Vector3 = worker.position
	var remaining: float = worker._sleep_hours_left
	worker.restore_saved_runtime(saved)
	_expect(worker.is_resting() and worker.position==pos and worker._sleep_hours_left==remaining,"saved rest reconstructs pose without moving or resetting need")
	var body: Transform3D = worker._body.transform
	clock_node.set_paused(true)
	worker._process(3)
	_expect(worker._body.transform==body and worker._sleep_hours_left==remaining,"pause freezes pose and sleep clock")
	clock_node.set_paused(false)
	clock_node.set_speed(2)
	worker._process(.1)
	_expect(worker._sleep_hours_left<remaining,"rest duration advances at simulation speed")
	clock_node.set_speed(1)
	var factory = load("res://scripts/entities/DwarfFactory.gd").new()
	var second_data: Dictionary = factory.generate(142,{})
	second_data.gender = "male"
	second_data.appearance.gender = "male"
	second_data.appearance.beard_style = "full_long"
	second_data.appearance.hair_style = "short_back"
	second_data.appearance.age_tier = "elder"
	second = factory.spawn(second_data,142)
	scene.add_child(second)
	second.position = Vector3(49.5,21,55.5)
	second.set_process(false)
	tasks.register_dwarf(second)
	second._begin_sleep()
	_expect(await _rested(second),"second dwarf finds a separate sleeping spot")
	_expect(second._rest_behavior.pose=="lying","even dwarf lies down")
	for cell in second._rest_behavior.cells:
		_expect(not cell in worker._rest_behavior.cells,"sleep footprints never overlap")
	_expect(second._head.rotation.x < -1.3,"lying pose rotates the head onto its back")
	_check_limb_anchors(worker)
	_check_limb_anchors(second)
	_audio_fixture()
	_expect(feedback.play_snore(worker),"settled dwarf can snore nearby")
	worker._rest_behavior.begin_waking()
	feedback._process(.01)
	_expect(not feedback._voices.any(func(v): return v.get("kind","")=="snore" and v.remaining>0),"snore stops when waking begins")
	for i in 15:
		worker._process(.1)
		if not worker.is_sleeping(): break
	_expect(not worker.is_sleeping() and tasks._idle_dwarves.has(worker.dwarf_id),"wake transition returns worker to scheduling")
	_check_empty_pose()
	_expect(worker._head.get_node("MeshEyes").visible,"waking reopens eyes")
	_expect(not feedback.play_snore(worker),"awake dwarves cannot snore")
	_check_movement()
	await _check_tree_and_fallback()
	await _check_directions()
	if "--capture" in OS.get_cmdline_user_args():
		await _capture_rest()
		await _native_audio()
	for failure: String in failures: push_error(failure)
	print("DWARF_REST_OK: shelter, separate ground poses, fatigue/sleep clock, save, pause, wake, tree removal, fallback, gait and audio" if failures.is_empty() else "DWARF_REST_FAIL")
	quit(0 if failures.is_empty() else 1)

func _check_awake_fatigue() -> void:
	var origin: Vector3 = worker.position
	var normal_drain := 0.0
	for speed in [1.0,2.0,3.0]:
		worker._idle_behavior.cancel()
		worker.stop_walking()
		worker.position = origin
		worker.sleep = 0.9
		clock_node.set_speed(speed)
		# The same game hour takes fewer real seconds at faster speeds.
		var real_step: float = (1.0/60.0)/clock_node.game_hours_per_real_second()
		for i in 60: worker._process(real_step)
		var drained: float = 0.9-worker.sleep
		if speed==1.0: normal_drain = drained
		_expect(drained>0.0 and is_equal_approx(drained,normal_drain),"one game hour drains equal awake fatigue at x%s" % speed)
	var before: float = worker.sleep
	clock_node.set_paused(true)
	worker._process(60)
	_expect(worker.sleep==before,"pause freezes awake fatigue")
	clock_node.set_paused(false)
	clock_node.set_speed(0)
	worker._process(60)
	_expect(worker.sleep==before,"zero game speed freezes awake fatigue")
	clock_node.set_speed(3)
	# Enough rest for 1.5 simulation seconds: a one-second x3 tick must interrupt.
	worker.sleep = worker.SLEEP_THRESHOLD+normal_drain*(1.5/60.0)
	worker._process(1)
	_expect(worker.is_sleeping() and not tasks._idle_dwarves.has(worker.dwarf_id),"accelerated fatigue crosses sleep threshold and releases availability")
	worker._wake_up()
	worker._idle_behavior.cancel()
	worker.stop_walking()
	worker.position = origin
	clock_node.set_speed(1)

func _wall() -> void:
	var stone: int = blocks.get_id("base:terrain:rock:rock01")
	for x in range(38,62):
		for y in range(21,26):
			var cell := Vector3i(x,y,50)
			world.set_block(cell.x,cell.y,cell.z,stone)
			wall_cells.append(cell)

func _rested(dwarf) -> bool:
	for i in 240:
		dwarf._process(.1)
		if dwarf.is_resting(): return true
		await process_frame
	return false

func _check_limb_anchors(dwarf) -> void:
	var left: Vector3 = dwarf._foot_l.transform*Vector3(.5,.2,.15)
	var right: Vector3 = dwarf._foot_r.transform*Vector3(.5,.2,.15)
	_expect(left.x>0 and right.x<0 and left.y>.19 and right.y>.19,"both reflected boots retain their floor anchors")
	for part: Node3D in [dwarf._foot_l,dwarf._foot_r]:
		var bounds: AABB = part.transform*dwarf._carry_pose.item_bounds(part)
		_expect(bounds.position.y >= -.04,"boot stays above floor: %s %s y=%.3f" % [dwarf._rest_behavior.pose,part.name,bounds.position.y])

func _check_directions() -> void:
	worker._wake_up()
	second._wake_up()
	var stone: int = blocks.get_id("base:terrain:rock:rock01")
	var center := Vector3i(105,20,45)
	for facing: Vector3i in worker._rest_behavior.DIRECTIONS:
		var side := Vector3i(facing.z,0,-facing.x)
		var placed: Array[Vector3i] = []
		for x in range(-5,6):
			for y in range(1,5):
				var block := center+side*x+Vector3i.UP*y
				placed.append(block)
				world.set_block(block.x,block.y,block.z,stone)
		worker.position = Vector3(center+facing*4)+Vector3(.5,1,.5)
		worker._begin_sleep()
		_expect(await _rested(worker),"rest reaches wall in each cardinal direction")
		_expect(worker._rest_behavior._facing==facing,"sleeping face points away from the wall")
		_check_limb_anchors(worker)
		worker._wake_up()
		for block in placed: world.set_block(block.x,block.y,block.z,blocks.AIR_ID)

func _check_movement() -> void:
	worker._idle_behavior.cancel()
	worker.position = Vector3(44.5,21,60.5)
	worker.walk_nearby(Vector3i(58,20,60))
	worker._follow_path(.001) # consume the cell-centre waypoint
	var start: Vector3 = worker.position
	worker._follow_path(1)
	_expect(is_equal_approx(worker.position.distance_to(start),3.4),"normal speed is 3.4 blocks/sec")
	var maximum_lift := 0.0
	for i in 40:
		worker._movement.walk_bob(.0525)
		maximum_lift = maxf(maximum_lift,maxf(worker._foot_l.position.y,worker._foot_r.position.y))
	_expect(maximum_lift>.19,"new walking cycle lifts feet visibly")
	start = worker.position
	clock_node.set_speed(2)
	worker._process(.1)
	_expect(is_equal_approx(worker.position.distance_to(start),.68),"game speed accelerates real work/navigation movement")
	clock_node.set_speed(1)
	worker.stop_walking()
	_check_empty_pose()

func _audio_fixture() -> void:
	camera = Camera3D.new()
	scene.add_child(camera)
	camera.position = worker.position+Vector3(0,8,12)
	camera.look_at(worker.position)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 18
	camera.set_meta("work_focus",worker.position)
	camera.set_meta("work_zoom",18.0)
	camera.current = true
	feedback.clear_transients()
	for stream: AudioStream in feedback._streams.snore:
		_expect(stream.get_length()>2 and stream.get_length()<3,"short imported snore variants")

func _check_tree_and_fallback() -> void:
	worker._wake_up()
	flora = load("res://scripts/systems/SurfaceFloraSpawner.gd").new()
	scene.add_child(flora)
	flora.set_process(false)
	var species: Dictionary = flora._species[0]
	var stage: Dictionary = species.stages.mature
	var cell := Vector3i(80,20,80)
	var model: String = flora.resolve_tree_model_for_season(stage,"summer",cell)
	flora._instance_tree(species.name,model,"mature",stage,80,80,20,flora._footprint_for(species.placement,"mature"))
	worker.position = Vector3(84.5,21,84.5)
	worker._begin_sleep()
	_expect(await _rested(worker),"dwarf finds an actual tree trunk")
	_expect(worker._rest_behavior._shelter.x>=0,"tree counts as shelter")
	var rest_left: float = worker._sleep_hours_left
	flora._unregister_tree_occupancy(Vector2i(80,80))
	worker._process(.6)
	_expect(worker._rest_behavior.state=="searching" and worker._sleep_hours_left==rest_left,"removed shelter causes safe reselection without resetting need")
	_expect(await _rested(worker),"open-ground fallback eventually sleeps")
	_expect(worker._rest_behavior._shelter.x<0,"fallback does not invent a tree")
	var floor_cell: Vector3i = worker.current_cell()
	world.set_block(floor_cell.x,floor_cell.y,floor_cell.z,blocks.AIR_ID)
	nav.refresh_mined_block(floor_cell)
	worker._process(.01)
	_expect(worker.current_cell()==floor_cell-Vector3i.UP and worker.is_sleeping(),"sleeping actor settles after floor removal")
	world.set_block(floor_cell.x,floor_cell.y,floor_cell.z,blocks.get_id("base:terrain:rock:rock01"))

func _capture_rest() -> void:
	worker._wake_up()
	second._wake_up()
	worker.position = Vector3(46.5,21,54.5)
	second.position = Vector3(53.5,21,55.5)
	worker._begin_sleep()
	second._begin_sleep()
	_expect(await _rested(worker) and await _rested(second),"capture actual resting actors")
	root.size = Vector2i(1280,800)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color(.18,.23,.25)
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color.WHITE
	settings.ambient_light_energy = .65
	environment.environment = settings
	scene.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45,-25,0)
	sun.shadow_enabled = true
	scene.add_child(sun)
	_box(Vector3(50,20.5,56),Vector3(30,1,20),Color(.46,.52,.38))
	_box(Vector3(50,23,50.5),Vector3(24,4,1),Color(.42,.45,.48))
	camera.size = 16
	camera.position = Vector3(61,31,69)
	camera.look_at(Vector3(50,22,52.7))
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tmp/dwarf_rest_20261011/rest.png")
	# Close-up makes closed eyelids, hand placement, beard and boot clearance reviewable.
	camera.size = 6
	camera.position = worker.position+Vector3(5,3,7)
	camera.look_at(worker.position+Vector3(0,1,.35))
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tmp/dwarf_rest_20261011/seated.png")
	camera.position = second.position+Vector3(5,4,7)
	camera.look_at(second.position+Vector3(0,.8,.3))
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tmp/dwarf_rest_20261011/lying.png")
	# The same live part transforms used by path following, at four stride phases.
	worker._wake_up()
	worker.position = Vector3(48.5,21,57.5)
	worker.rotation.y = -.3
	camera.position = worker.position+Vector3(5,4,8)
	camera.look_at(worker.position+Vector3(0,1.5,0))
	worker._walk_cycle = 0
	for phase in 4:
		worker._movement.walk_bob(worker.stride_length*.5)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tmp/dwarf_rest_20261011/walk_%d.png" % phase)
	worker._reset_part_offsets()
	worker._begin_sleep()
	_expect(await _rested(worker),"preview dwarf can return to sleep")

func _box(at: Vector3, size: Vector3, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh.material_override = material
	scene.add_child(mesh)
	mesh.position = at

func _native_audio() -> void:
	feedback.set_process(true)
	camera.set_meta("work_zoom",18.0)
	camera.set_meta("work_focus",worker.position)
	var recorder := AudioEffectRecord.new()
	recorder.format = AudioStreamWAV.FORMAT_16_BITS
	AudioServer.add_bus_effect(0,recorder)
	var readings := {}
	for label in ["snore","quiet","muted","paused","hidden","far","overview","awake"]:
		feedback.clear_transients()
		clock_node.paused = label=="paused"
		worker.visible = label!="hidden"
		worker._rest_behavior.state = "waking" if label=="awake" else "sleeping"
		feedback.set_muted(label=="muted")
		feedback.set_volume_db(-27 if label=="quiet" else -7)
		camera.set_meta("work_focus",worker.position+Vector3(100,0,0) if label=="far" else worker.position)
		camera.set_meta("work_zoom",180.0 if label=="overview" else 18.0)
		await create_timer(.12).timeout
		recorder.set_recording_active(true)
		var played: bool = feedback.play_snore(worker)
		_expect(played==(label in ["snore","quiet","muted"]),"audio emission guard: "+label)
		await create_timer(2.6 if label=="snore" else 1.0).timeout
		recorder.set_recording_active(false)
		var wav := recorder.get_recording()
		if label=="snore": wav.save_to_wav("res://tmp/dwarf_rest_20261011/snore_playback.wav")
		var data := wav.data
		var energy := 0.0
		var peak := 0.0
		var count := data.size()>>1
		for i in count:
			var sample := float(data.decode_s16(i*2))/32768.0
			energy += sample*sample
			peak = maxf(peak,absf(sample))
		readings[label] = {"rms":sqrt(energy/maxi(1,count)),"peak":peak}
	_expect(readings.snore.rms>.002 and readings.snore.peak<.5,"actual imported snore is audible without clipping")
	_expect(readings.quiet.rms<readings.snore.rms*.2,"Work slider controls actual snore output")
	for label in ["muted","paused","hidden","far","overview","awake"]:
		_expect(readings[label].peak<.001,"actual silence: "+label)
	print("Snore PCM: ",readings)
	AudioServer.remove_bus_effect(0,AudioServer.get_bus_effect_count(0)-1)
	feedback.clear_transients()
	clock_node.paused = false
	feedback.set_muted(false)
	feedback.set_volume_db(-7)
