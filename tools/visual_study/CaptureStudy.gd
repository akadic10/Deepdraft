extends SceneTree

var failures: Array[String] = []
var checks_passed := 0

func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	create_timer(150).timeout.connect(func(): push_error("Visual study capture timed out"); quit(1))
	root.size = Vector2i(1600,1000)
	change_scene_to_file("res://scenes/studies/visual_study.tscn")
	while current_scene == null: await process_frame
	var study = current_scene
	while not study.ready_for_review: await process_frame
	study.capture_mode = true
	var directional_lights := 0
	for light in study.get_children():
		if light is DirectionalLight3D: directional_lights += 1
	_check(directional_lights == 2,"exactly one sun and one moon after deferred startup")
	_check(root.get_node("WeatherManager").current_weather_id() == "base:weather:clear","comparison weather is fixed after autoload startup")
	var report := {"scope":"32×32 presentation study; not a full-world performance forecast", "adapter":RenderingServer.get_video_adapter_name(),"resolution":[1600,1000],"captures":{},"failures":[]}
	await _check_controls(study)
	var room := Vector3i(49,22,37)
	var roof_light: float = study.field.sky_at(room)
	var opening_inside := Vector3i(35,22,40)
	var closed_light: float = study.field.sky_at(opening_inside)
	_check(roof_light < .05,"roofed room has little daylight")
	for phase in ["Day","Dusk","Night"]:
		for proposed in [false,true]:
			study.apply_look(proposed,phase)
			await study.settle()
			var readings: Array[float] = []
			for i in range(120):
				await process_frame
				if i >= 30: readings.append(study.render_metrics().gpu_ms)
			readings.sort()
			var name: String = ("study_" if proposed else "current_")+phase.to_lower()
			var sample: Dictionary = study.render_metrics()
			sample["terrain_rebuild_ms"] = study.last_remesh_ms
			sample["gpu_median_ms"] = readings[readings.size()/2]
			sample["gpu_p95_ms"] = readings[floori(readings.size()*.95)]
			sample["sample_frames"] = readings.size()
			study.metrics.text = "GPU median %.2f ms · %d draws\nLast terrain rebuild %.1f ms" % [sample.gpu_median_ms,sample.draw_calls,study.last_remesh_ms]
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(study.OUT+name+".png")
			report.captures[name] = sample
	study.set_view("Rooms")
	for proposed in [false,true]:
		study.apply_look(proposed,"Day")
		await study.settle()
		study.metrics.text = "Room detail · Same camera and world data\n32 × 32 bounded scene"
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(study.OUT+("study_rooms" if proposed else "current_rooms")+".png")
	# Isolate the new ground treatment from the already-approved pass 2 trees,
	# stone, dressing and lights. Both pairs use identical native cameras.
	for view in ["Scene","Ground"]:
		study.set_view(view)
		for detailed in [false,true]:
			if study.detailed_ground != detailed: study.toggle_ground()
			await study.settle()
			study.metrics.text = "Ground comparison · Same trees and lighting\n32 × 32 bounded scene"
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(study.OUT+"pass_%d_%s.png" % [3 if detailed else 2,view.to_lower()])
	for view in ["Stream","Trees"]:
		study.set_view(view)
		study.metrics.text = view+" · Prototype environment art\n32 × 32 bounded scene"
		await study.settle()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(study.OUT+"study_"+view.to_lower()+".png")
	study.set_view("Scene")
	study.apply_look(true,"Day")
	study.metrics.text = "Terrain / roof-lighting check\n32 × 32 bounded scene"
	for height in [23,31,24]:
		study.set_slice(height)
		await study.settle()
		_check(is_equal_approx(study.field.sky_at(room),roof_light),"slice preserves physical roof lighting at %d" % height)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(study.OUT+"slice_%d.png" % height)
	var cells_before: Dictionary = study.terrain.original_sample.duplicate()
	study.toggle_sample()
	await study.settle()
	_check(study.field.sky_at(opening_inside) > closed_light,"mining a real opening admits daylight")
	report["opening_daylight"] = {"closed":closed_light,"open":study.field.sky_at(opening_inside)}
	for cell: Vector3i in cells_before:
		_check(root.get_node("WorldData").get_block(cell.x,cell.y,cell.z) == 0,"sample opening is real edited air")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(study.OUT+"study_mined.png")
	study.toggle_sample()
	await study.settle()
	for cell: Vector3i in cells_before:
		_check(root.get_node("WorldData").get_block(cell.x,cell.y,cell.z) == cells_before[cell],"sample restores exact block identity")
	_check(is_equal_approx(study.field.sky_at(room),roof_light),"restoration preserves room skylight")
	_check(is_equal_approx(study.field.sky_at(opening_inside),closed_light),"restoration closes the daylight opening")
	for y in range(4):
		_check(root.get_node("WorldData").get_block(32,y,32) == root.get_node("BlockRegistry").get_id("base:terrain:bedrock"),"bedrock remains intact")
	report.failures = failures
	report["checks_passed"] = checks_passed
	report["fixture_chunks"] = 8
	report["allocated_chunks"] = root.get_node("WorldData")._chunks.size()
	report["roof_light"] = roof_light
	report["environment_art_triangles"] = study.environment_art.triangle_count
	report["study_msaa"] = "4x; current comparison uses the shipped disabled setting"
	FileAccess.open(study.OUT+"report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  ")+"\n")
	for failure in failures: push_error(failure)
	print("VISUAL_STUDY_OK " if failures.is_empty() else "VISUAL_STUDY_FAIL ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
	else: checks_passed += 1


func _check_controls(study: Node3D) -> void:
	_click(study.mode_button.get_global_rect().get_center())
	_check(not study.study,"native Compare click selects current treatment")
	_check(not study.environment_art.visible and study.original_trees[0].visible,"comparison displays the original trees")
	_key(KEY_C)
	_check(study.study,"native C selects study treatment")
	_check(study.environment_art.visible and not study.original_trees[0].visible,"study displays prototype environment art")
	var world: Node = root.get_node("WorldData")
	var before := {}
	for coord in world._chunks: before[coord] = hash(world._chunks[coord].blocks)
	_key(KEY_G)
	_check(not study.detailed_ground and study.environment_art.visible,"G compares pass 2 ground while retaining the new trees")
	_click(study.ground_button.get_global_rect().get_center())
	_check(study.detailed_ground,"native Ground button restores pass 3")
	var after := {}
	for coord in world._chunks: after[coord] = hash(world._chunks[coord].blocks)
	_check(before == after,"ground comparison preserves all logical block data")
	for key in [KEY_3,KEY_2,KEY_1]: _key(key)
	_check(study.phase == "Day","time keys restore day")
	var level: int = study.terrain.slice_y
	_key(KEY_BRACKETLEFT)
	_check(study.terrain.slice_y == level-1,"bracket lowers the real slice")
	_key(KEY_BRACKETRIGHT)
	_check(study.terrain.slice_y == level,"bracket restores slice")
	var size: float = study.camera.size
	var wheel := InputEventMouseButton.new()
	wheel.position = Vector2(1450,700)
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	root.push_input(wheel,true)
	_check(study.camera.size < size,"wheel over world zooms camera")
	study.set_view("Scene")
	await study.settle()


func _click(at: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	root.push_input(motion,true)
	for pressed in [true,false]:
		var click := InputEventMouseButton.new()
		click.position = at
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		root.push_input(click,true)


func _key(code: int) -> void:
	for pressed in [true,false]:
		var key := InputEventKey.new()
		key.keycode = code
		key.pressed = pressed
		root.push_input(key,true)
