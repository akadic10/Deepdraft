extends SceneTree
## Full-world native audio integration; only records this game's Master bus.
func _init() -> void: _run.call_deferred()
func _run() -> void:
	create_timer(240).timeout.connect(func(): push_error("Water audio world timeout"); quit(1))
	var clock_node = root.get_node("WorldClock")
	clock_node.paused = true
	clock_node.set_process(false)
	root.get_node("SaveManager").set_process(false)
	node_added.connect(func(node: Node):
		if node.name=="Renderer" and node.get_script()!=null: node.set("world_seed",2795346874))
	change_scene_to_file("res://scenes/main/debug_world.tscn")
	await process_frame
	await process_frame
	var gen = root.get_node("WorldGenerator")
	var water = root.get_node("WaterManager")
	water.set_process(false)
	var terrain = current_scene.get_node("Renderer")
	while not terrain._overview_built or terrain._overview_tile_nodes.size()!=1024: await process_frame
	water.initialize()
	await process_frame
	while not water.dirty_tiles.is_empty(): await process_frame
	for i in 900:
		water.step(0.1)
		if i%2==0: await process_frame
	var view = terrain.get_node("Water")
	var sound = view._sound
	while not sound._streams_ready: await process_frame
	var rig = get_first_node_in_group("work_audio_view")
	rig.set_process(false)
	rig.remove_from_group("work_audio_view")
	root.get_node("WorkFeedback")._view = null
	var camera := Camera3D.new()
	current_scene.add_child(camera)
	camera.make_current()
	var falls: Array[Vector3] = []
	for sites: Array in view._splash_sites.values():
		for site in sites:
			if sound._current_strength(site.key)>0.3: falls.append(site.point)
	if falls.is_empty():
		push_error("No active waterfall audio sites")
		quit(1)
		return
	var river := Vector3.ZERO
	var best_distance := 0.0
	for key: Vector3i in view.motion.velocities:
		if not gen.river_layout.columns.has(Vector2i(key.x,key.z)) or sound._current_strength(key)<0.5: continue
		var point := Vector3(key.x+0.5,water.flow.level(key),key.z+0.5)
		var distance := 100000.0
		for fall in falls: distance = minf(distance,Vector2(point.x-fall.x,point.z-fall.z).length())
		if distance>best_distance:
			best_distance = distance
			river = point
	var lake := Vector3.ZERO
	for key: Vector3i in water.flow.mass:
		if key.y>=18 or water.flow.volume(key)<4 or Vector2(key.x-river.x,key.z-river.z).length()<100: continue
		var point := Vector3(key.x+0.5,water.flow.level(key),key.z+0.5)
		camera.set_meta("work_focus",point)
		camera.set_meta("work_zoom",28.0)
		sound._scan({"focus":point,"zoom":28.0})
		if sound.voices.waterfall.target_gain==0 and sound.voices.river.target_gain==0:
			lake = point
			break
	clock_node.paused = false
	var recorder := AudioEffectRecord.new()
	recorder.format = AudioStreamWAV.FORMAT_16_BITS
	AudioServer.add_bus_effect(0,recorder)
	var results := {}
	for label in ["falls","river","lake"]:
		var point: Vector3 = falls[0] if label=="falls" else river if label=="river" else lake
		camera.position = point+Vector3(14,20,16)
		camera.look_at(point)
		camera.set_meta("work_focus",point)
		camera.set_meta("work_zoom",28.0)
		for i in 40:
			water.step(0.1)
			await create_timer(0.1).timeout
		recorder.set_recording_active(true)
		var max_scan := 0
		for i in 60:
			water.step(0.1)
			await create_timer(0.1).timeout
			max_scan = maxi(max_scan,sound.last_scan_usec)
		recorder.set_recording_active(false)
		var wav := recorder.get_recording()
		var data := wav.data
		wav.save_to_wav("res://tmp/water_review/audio/world_"+label+".wav")
		var energy := 0.0
		var peak := 0.0
		for i in data.size()/2:
			var sample := float(data.decode_s16(i*2))/32768.0
			energy += sample*sample
			peak = maxf(peak,absf(sample))
		results[label] = {"point":point,"peak":peak,"rms":sqrt(energy/maxi(1,data.size()/2)),"scan_usec":max_scan,"falls_gain":sound.voices.waterfall.gain,"river_gain":sound.voices.river.gain}
		print("Water world audio ",label," ",results[label])
	AudioServer.remove_bus_effect(0,AudioServer.get_bus_effect_count(0)-1)
	var ok: bool = results.falls.peak>0.01 and results.river.peak>0.002 and results.lake.peak<0.001 and results.river.rms<results.falls.rms
	print("WaterAudioWorldPreview: ","PASS" if ok else "FAIL"," terrain tiles=",terrain._overview_tile_nodes.size()," river distance from falls=",best_distance)
	quit(0 if ok else 1)
