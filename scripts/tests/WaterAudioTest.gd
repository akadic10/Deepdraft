extends SceneTree
## Native run also records ONLY game output (Master bus), never a microphone.
const Synth := preload("res://scripts/components/WaterAudioSynth.gd")
const OUTPUT := "res://tmp/water_review/audio"
class Terrain extends Node3D:
	var slice_y := 127
	var revealed := true
	func is_revealed_air(_cell: Vector3i) -> bool: return revealed
class View extends Node3D:
	var terrain := Terrain.new()
	var motion := preload("res://scripts/components/WaterSurfaceMotion.gd").new()
	var _splash_sites := {}

var failures: Array[String] = []
var sound
var view := View.new()
var camera := Camera3D.new()
var clock_node
var water
var feedback
var recorder := AudioEffectRecord.new()
var key := Vector3i(64,20,64)

func _init() -> void: _run.call_deferred()
func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)

func _run() -> void:
	create_timer(120).timeout.connect(func(): push_error("Water audio timeout"); quit(1))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	for name in ["SaveManager","RoomManager","StockpileManager","TaskManager","WorldClock","WaterManager"]: root.get_node(name).set_process(false)
	clock_node = root.get_node("WorldClock")
	clock_node.paused = false
	clock_node.speed = 1
	water = root.get_node("WaterManager")
	feedback = root.get_node("WorkFeedback")
	var gen = root.get_node("WorldGenerator")
	gen.water_profile = gen.load_water_profile()
	gen.heightmap.resize(1024*1024)
	gen.heightmap.fill(30)
	gen._maps_ready = true
	var start := Time.get_ticks_usec()
	for kind in ["waterfall","river"]:
		var wav := Synth.stream(kind)
		var data := wav.data
		check(wav==Synth.stream(kind),"synthesis must be cached")
		wav.save_to_wav(OUTPUT+"/"+kind+"_synth.wav")
		var energy := 0.0
		var peak := 0.0
		var difference := 0.0
		var count := data.size()/2
		var previous := float(data.decode_s16((count-1)*2))/32768.0
		var seam := absf(float(data.decode_s16(0))/32768.0-previous)
		for i in count:
			var sample := float(data.decode_s16(i*2))/32768.0
			energy += sample*sample
			peak = maxf(peak,absf(sample))
			difference += (sample-previous)*(sample-previous)
			previous = sample
		check(peak<0.8 and sqrt(energy/count)>0.08,"audible bank with headroom: "+kind)
		check(seam<sqrt(difference/count)*4.0,"loop seam is not an impulse: "+kind)
		# The wrap must retain ambience rather than dip to silence every nine seconds.
		var edge_energy := 0.0
		for i in 2205: edge_energy += pow(float(data.decode_s16(i*2))/32768.0,2)
		check(sqrt(edge_energy/2205)>sqrt(energy/count)*0.7,"no loop fade hole: "+kind)
	print("Water bank synthesis usec=",Time.get_ticks_usec()-start)
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	scene.add_child(view)
	view.add_child(view.terrain)
	scene.add_child(camera)
	camera.position = Vector3(64,40,84)
	camera.look_at(Vector3(64,20,64))
	camera.current = true
	camera.set_meta("work_focus",Vector3(64,20,64))
	camera.set_meta("work_zoom",24.0)
	water.flow = preload("res://scripts/components/WaterFlow.gd").new()
	water.flow.spans_at = func(_p: Vector2i) -> Array: return [Vector2i(20,128)]
	water.initialized = true
	_fixture("waterfall")
	var original: Dictionary = water.flow.serialize()
	sound = load("res://scripts/components/WaterSound.gd").new()
	sound.water_view = view
	view.add_child(sound)
	while not sound._streams_ready: await process_frame
	await process_frame
	# Query the actual selector and fade code, including hidden/sliced/dry cases.
	sound.set_process(false)
	for label in ["waterfall","river","still","dry","sliced","hidden","far","overview","paused","zero_speed","loading","hidden_view","no_camera"]:
		_fixture(label)
		for i in 50: sound._process(0.2)
		var audible: bool = sound.voices.waterfall.gain>0.001 or sound.voices.river.gain>0.001
		check(audible==(label in ["waterfall","river"]),"water source gating: "+label)
	_fixture("waterfall")
	sound._process(0.25)
	var single: float = sound.voices.waterfall.target_gain
	for i in 100: view._splash_sites[Vector2i.ZERO].append({"key":key,"point":Vector3(64.5,18,64.5)})
	sound._process(0.25)
	check(is_equal_approx(single,sound.voices.waterfall.target_gain),"many faces amplify waterfall")
	check(sound.get_child_count()==2,"ambience voice count must stay bounded")
	_fixture("waterfall")
	check(water.flow.serialize()==original,"audio mutated authoritative water")
	clock_node.paused = true
	sound._process(0.01)
	clock_node.paused = false
	sound._process(0.01)
	check(sound.voices.waterfall.gain<single*0.1,"resume must fade in")
	clock_node.speed = 2
	sound._process(0.3)
	check(sound.voices.waterfall.player.pitch_scale==1.0,"speed changes sound pitch")
	if DisplayServer.get_name()!="headless":
		sound.set_process(true)
		recorder.format = AudioStreamWAV.FORMAT_16_BITS
		AudioServer.add_bus_effect(0,recorder)
		var samples := {}
		for label in ["waterfall","river","left","right","far","overview","quiet","muted","paused","stopped","loading"]:
			if label=="stopped":
				_fixture("waterfall")
				await create_timer(1.8).timeout
			_fixture(label)
			await create_timer(3.8 if label in ["far","overview","stopped"] else 1.8).timeout
			recorder.set_recording_active(true)
			await create_timer(10.0 if label in ["waterfall","river"] else 0.8).timeout
			recorder.set_recording_active(false)
			var wav := recorder.get_recording()
			var data := wav.data
			wav.save_to_wav(OUTPUT+"/"+label+".wav")
			var energy := Vector2.ZERO
			var peak := 0.0
			var count := data.size()/4
			for i in count:
				var l := float(data.decode_s16(i*4))/32768.0
				var r := float(data.decode_s16(i*4+2))/32768.0
				energy += Vector2(l*l,r*r)
				peak = maxf(peak,maxf(absf(l),absf(r)))
			samples[label] = {"peak":peak,"energy":energy/maxi(count,1)}
		check(samples.waterfall.peak>0.01 and samples.river.peak>0.005,"near water produces real PCM")
		check(samples.river.energy.length()<samples.waterfall.energy.length()*0.35,"river calmer than waterfall")
		check(samples.left.energy.x>samples.left.energy.y and samples.right.energy.y>samples.right.energy.x,"stereo follows water")
		check(samples.quiet.energy.length()<samples.waterfall.energy.length()*0.1,"volume changes output")
		for label in ["far","overview","muted","paused","stopped","loading"]: check(samples[label].peak<0.001,"silent PCM: "+label)
		for label in samples: check(samples[label].peak<0.5,"output headroom: "+label)
		print("Water audio PCM: ",samples)
		AudioServer.remove_bus_effect(0,AudioServer.get_bus_effect_count(0)-1)
	feedback.set_muted(false)
	feedback.set_volume_db(float(feedback.config.audio.volume_db))
	var players: Array = [weakref(sound.voices.waterfall.player),weakref(sound.voices.river.player)]
	scene.queue_free()
	await process_frame
	await process_frame
	check(players[0].get_ref()==null and players[1].get_ref()==null,"scene exit leaked voices")
	print("WaterAudioTest: ","PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)

func _fixture(label: String) -> void:
	clock_node.paused = label=="paused"
	clock_node.speed = 0 if label=="zero_speed" else 1
	root.get_node("SaveManager")._loading = label=="loading"
	feedback.set_muted(label=="muted")
	feedback.set_volume_db(-27 if label=="quiet" else -7)
	camera.set_meta("work_focus",Vector3(200,20,200) if label=="far" else Vector3(64,20,64))
	camera.set_meta("work_zoom",240.0 if label=="overview" else 24.0)
	camera.current = label!="no_camera"
	view.visible = label!="hidden_view"
	view.terrain.slice_y = 19 if label=="sliced" else 127
	view.terrain.revealed = label!="hidden"
	key = Vector3i(58 if label=="left" else 70 if label=="right" else 64,20,64)
	water.flow.mass.clear()
	water.flow.mass[key] = 2000000 if label!="dry" else 0
	view.motion.slots.clear()
	view.motion.slot(key)
	view.motion.velocities = {} if label in ["still","stopped"] else {key:Vector2(0.03,0)}
	view._splash_sites = {} if label=="river" else {Vector2i.ZERO:[{"key":key,"point":Vector3(key.x+0.5,18,key.z+0.5)}]}
	if is_instance_valid(sound): sound._until_scan = 0.0
