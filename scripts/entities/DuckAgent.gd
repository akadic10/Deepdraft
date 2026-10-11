extends "res://scripts/entities/GrazerAgent.gd"

## Uses common identity/needs/inspection fields, with amphibious and air motion.
var navigation: RefCounted
var flock_id := ""
var flock_centre := Vector3.ZERO
var flock_members := 1
var peers: Array[Vector3] = []
var sex := "male"
var mode := "water"
var step_from := Vector3.ZERO
var flight := PackedVector3Array()
var flight_index := 1
var launch_left := 0.0
var flight_left := 0.0
var quack_left := 0.0
var shore_left := 0.0
var _bodies: Dictionary = {}
var _heads: Dictionary = {}
var _wings: Array[Node3D] = []
var _feet: Array[Node3D] = []
var _wake: Node3D
var _foam: Array[MeshInstance3D] = []
var _splash_left := 0.0

func configure(data: Dictionary, id: String, origin: Vector3i, seed_value: int, models: Dictionary) -> void:
	super.configure(data,id,origin,seed_value,models)
	var sample: Dictionary = navigation.surface(Vector2i(origin.x,origin.z))
	if not sample.is_empty():
		position = sample.position
		cell = sample.cell
		target = cell
		mode = "water" if sample.water else "land"
	step_from = position
	flock_centre = position
	flight_left = rng.randf_range(data.navigation.flight_interval[0],data.navigation.flight_interval[1])
	quack_left = rng.randf_range(data.behavior.quack_seconds[0],data.behavior.quack_seconds[1])
	_pose()

func _build_visual(models: Dictionary) -> void:
	sex = "male" if rng.randf()<.5 else "female"
	for variant in ["male","female"]:
		var body := Node3D.new()
		visual.add_child(body)
		body.add_child(models[variant+"_body"].instantiate())
		_bodies[variant] = body
		var joint := Node3D.new()
		joint.position = Vector3(0,.65,-.22)
		body.add_child(joint)
		var model: Node3D = models[variant+"_head"].instantiate()
		joint.add_child(model)
		model.position = -joint.position
		_heads[variant] = joint
		for side in [-1,1]:
			var wing := Node3D.new()
			wing.position = Vector3(side*.25,.65,0)
			body.add_child(wing)
			var mesh: Node3D = models[variant+"_wing"].instantiate()
			wing.add_child(mesh)
			mesh.scale.x = side
			wing.set_meta("side",side)
			_wings.append(wing)
	for side in [-1,1]:
		var foot := Node3D.new()
		visual.add_child(foot)
		foot.position = Vector3(side*.15,0,.02)
		foot.add_child(models.foot.instantiate())
		_feet.append(foot)
	# World effects are siblings, so they never become inspector bounds/outline.
	_wake = Node3D.new()
	get_parent().add_child(_wake)
	var foam := StandardMaterial3D.new()
	foam.albedo_color = Color("b7dce0")
	foam.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for i in 8:
		var piece := MeshInstance3D.new()
		var cube := BoxMesh.new()
		cube.size = Vector3(.11,.018,.11)
		piece.mesh = cube
		piece.material_override = foam
		piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_wake.add_child(piece)
		_foam.append(piece)

func advance(seconds: float, hours: float, threats: Array) -> void:
	if seconds<=0: return
	var b: Dictionary = definition.behavior
	hunger = clampf(hunger+hours*float(b.hunger_per_hour),0,1)
	fatigue = clampf(fatigue+hours*float(b.fatigue_per_hour),0,1)
	pose_time += seconds
	flight_left = maxf(0,flight_left-seconds)
	shore_left = maxf(0,shore_left-seconds)
	_splash_left = maxf(0,_splash_left-seconds)
	var threat := Vector3.ZERO
	var distance := INF
	for other: Vector3 in threats:
		if position.distance_to(other)<distance:
			threat = other
			distance = position.distance_to(other)
	calm_left = float(b.calm_seconds) if distance<float(b.threat_radius) else maxf(0,calm_left-seconds)
	if mode=="air":
		_advance_flight(seconds)
		_pose()
		return
	var here: Dictionary = navigation.surface(Vector2i(floori(position.x),floori(position.z)))
	if here.is_empty() or (mode=="water" and not here.water):
		if activity!="Seeking safe water": flight_left = 0
		if flight_left<=0 and _try_flight(threat,distance):
			_pose()
			return
		# A drained pool exposes a real floor. Descend visibly if no flight is
		# available, instead of leaving a floating duck or teleporting to shore.
		if not here.is_empty() and navigation.segment_clear(position,here.position,float(definition.navigation.radius)):
			position.y = move_toward(position.y,here.position.y,seconds*3)
			if is_equal_approx(position.y,here.position.y): _settle(here)
		activity = "Seeking safe water"
		_pose()
		return
	if calm_left>0 and activity!="Fleeing":
		activity = "Fleeing"
		timer = 0
		flight_left = 0
	if distance<3.5 and flight_left<=0 and _try_flight(threat,distance):
		_pose()
		return
	if hop_progress<1:
		var dest: Dictionary = navigation.surface(Vector2i(target.x,target.z))
		if dest.is_empty():
			hop_progress = 1
			timer = 0
		else:
			var progress := minf(1,hop_progress+seconds/hop_seconds)
			var next: Vector3 = navigation.step_position(step_from,dest.position,progress)
			if navigation.segment_clear(position,next,float(definition.navigation.radius)):
				position = next
				hop_progress = progress
				if progress>=1: _settle(dest)
			else:
				hop_progress = 1
				timer = 0
		_pose()
		return
	# Re-anchor to the changing water surface without consuming any water.
	if here.water: position.y = move_toward(position.y,here.position.y,seconds*4)
	cell = here.cell
	mode = "water" if here.water else "land"
	if activity=="Sleeping" and calm_left<=0:
		fatigue = maxf(0,fatigue-hours*(float(b.sleep_recovery_per_hour)+float(b.fatigue_per_hour)))
		if fatigue>float(b.wake_threshold) and hunger<float(b.wake_hunger_threshold):
			_pose()
			return
		timer = 0
	quack_left -= seconds
	if quack_left<=0:
		quack_left = rng.randf_range(b.quack_seconds[0],b.quack_seconds[1])
		if calm_left<=0: WorkFeedback.play_animal(definition.feedback.ambient_sound,self)
	timer = maxf(0,timer-seconds)
	if timer<=0:
		if activity=="Grazing" and calm_left<=0: hunger = maxf(0,hunger-float(b.meal_relief))
		_decide_duck(here,threat,distance)
	_pose()

func _decide_duck(here: Dictionary, threat: Vector3, distance: float) -> void:
	var b: Dictionary = definition.behavior
	if flight_left<=0 and calm_left<=0 and _try_flight(): return
	if calm_left<=0:
		if hunger>=float(b.hungry_threshold):
			activity = "Grazing"
			timer = float(b.graze_seconds)
			return
		if mode=="land" and fatigue>=float(b.sleep_threshold) and (_rest_time() or fatigue>=float(b.exhausted_threshold)):
			activity = "Sleeping"
			return
		if rng.randf()<float(b.preen_chance):
			activity = "Preening"
			timer = rng.randf_range(2.0,4.0)
			return
		if mode=="water" and (rng.randf()<float(b.shore_chance) or fatigue>=float(b.sleep_threshold)): shore_left = 18
	var choices: Array = navigation.neighbors(here)
	var best := -INF
	var destination: Dictionary = {}
	for next: Dictionary in choices:
		var crowded := false
		for peer in peers:
			if peer.distance_to(next.position)<float(definition.navigation.member_spacing): crowded = true
		if crowded: continue
		var score := rng.randf()*2
		if calm_left>0 and distance<INF:
			score += (next.position as Vector3).distance_to(threat)*3
			if next.water: score += 2
		else:
			var separation: float = next.position.distance_to(flock_centre)
			if separation>float(definition.navigation.group_radius): score -= separation*.4
			if Vector3(next.cell-home).length()>float(definition.navigation.home_radius): score -= 3
			if shore_left>0:
				if not next.water: score += 6
				elif navigation.near_shore(Vector2i(next.cell.x,next.cell.z),2): score += 2
			elif next.water: score += 3
		if score>best:
			best = score
			destination = next
	if destination.is_empty():
		activity = "Alert" if calm_left>0 else "Resting"
		timer = 1
		return
	step_from = position
	target = destination.cell
	hop_progress = 0
	hop_seconds = float(definition.navigation.flee_seconds if calm_left>0 else definition.navigation.swim_seconds if destination.water else definition.navigation.walk_seconds)
	var direction: Vector3 = destination.position-position
	rotation.y = atan2(-direction.x,-direction.z)
	activity = "Fleeing" if calm_left>0 else "Swimming" if destination.water else "Walking"
	timer = 0 if calm_left>0 else rng.randf_range(b.idle_seconds[0],b.idle_seconds[1])

func _settle(sample: Dictionary) -> void:
	var entered: bool = sample.water and mode!="water"
	mode = "water" if sample.water else "land"
	position = sample.position
	cell = sample.cell
	target = cell
	hop_progress = 1
	if entered:
		_splash_left = .6
		WorkFeedback.play_animal(definition.feedback.splash_sound,self)

func _try_flight(threat := Vector3.ZERO, distance := INF) -> bool:
	var prefer_shore := calm_left<=0 and fatigue>=float(definition.behavior.sleep_threshold)
	var destinations: Array = navigation.landing_candidates(position,rng,prefer_shore)
	# Nearby valid water also offers an escape from a drained or cut-off pool.
	for dir: Vector2i in navigation.DIRS:
		var nearby: Dictionary = navigation.surface(Vector2i(floori(position.x),floori(position.z))+dir*4)
		if not nearby.is_empty() and (nearby.water or (prefer_shore and navigation.near_water(Vector2i(nearby.cell.x,nearby.cell.z)))): destinations.append(nearby)
	if prefer_shore: destinations.sort_custom(func(a,b): return not a.water and b.water)
	for dest: Dictionary in destinations:
		if distance<INF and (dest.position as Vector3).distance_to(threat)<distance+5: continue
		var crowded := false
		for peer in peers:
			if peer.distance_to(dest.position)<2: crowded = true
		if crowded: continue
		var path: PackedVector3Array = navigation.flight_path(position,dest.position)
		if not path.is_empty():
			begin_flight(path,dest.cell)
			return true
	flight_left = float(definition.navigation.flight_retry_seconds)
	return false

func begin_flight(path: PackedVector3Array, landing: Vector3i, already_airborne := false) -> void:
	flight = path
	flight_index = 1
	target = landing
	hop_progress = 1
	launch_left = 0 if already_airborne or mode=="air" else float(definition.navigation.takeoff_seconds)
	mode = "air"
	activity = "Taking off" if launch_left>0 else "Flying"
	flight_left = rng.randf_range(definition.navigation.flight_interval[0],definition.navigation.flight_interval[1])
	if path.size()>1:
		var direction := path[1]-position
		rotation.y = atan2(-direction.x,-direction.z)

func _advance_flight(seconds: float) -> void:
	if launch_left>0:
		launch_left = maxf(0,launch_left-seconds)
		return
	if flight.is_empty():
		activity = "Seeking a landing"
		if flight_left<=0: _try_flight()
		return
	var remaining := seconds*float(definition.navigation.flight_speed)
	while remaining>0 and flight_index<flight.size():
		if flight_index==flight.size()-1:
			var landing: Dictionary = navigation.surface(Vector2i(target.x,target.z))
			if landing.is_empty():
				flight.clear()
				flight_left = 0
				return
			flight[flight_index] = landing.position
		var goal := flight[flight_index]
		var distance := position.distance_to(goal)
		var next := position.move_toward(goal,remaining)
		var radius := float(definition.navigation.radius) if flight_index==1 or flight_index==flight.size()-1 else float(definition.navigation.flight_radius)
		if not navigation.segment_clear(position,next,radius,true):
			flight.clear()
			flight_left = 0
			return
		var direction := next-position
		if Vector2(direction.x,direction.z).length()>.001: rotation.y = atan2(-direction.x,-direction.z)
		position = next
		remaining -= distance
		if position.is_equal_approx(goal): flight_index += 1
	activity = "Landing" if flight_index>flight.size()*3/4 else "Flying"
	if flight_index>=flight.size():
		var landing: Dictionary = navigation.surface(Vector2i(target.x,target.z))
		flight.clear()
		if landing.is_empty(): return
		_settle(landing)
		home = cell
		activity = "Swimming" if landing.water else "Resting"
		timer = 2
		if not arrival.is_empty(): arrival.status = "Settled"

func _pose() -> void:
	if visual==null: return
	for variant: String in _bodies: _bodies[variant].visible = variant==sex
	var airborne := mode=="air" and launch_left<=0
	var moving := hop_progress<1 or launch_left>0
	visual.position.y = sin(pose_time*2.2)*.025 if mode=="water" else 0.0
	visual.rotation.z = sin(pose_time*12)*.035 if moving and mode=="land" else 0.0
	for joint: Node3D in _heads.values():
		joint.rotation.x = .65+sin(pose_time*6)*.12 if activity=="Grazing" else .25 if activity=="Sleeping" else 0.0
		joint.rotation.y = 1.5+sin(pose_time*3)*.15 if activity=="Preening" else .9 if activity=="Sleeping" else 0.0
	# Keep the wings tucked through the narrow launch/landing sections; those
	# are swept for the body footprint, while cruise uses the full wingspan.
	var wings_open := airborne and flight_index>1 and flight_index<flight.size()-1
	for wing in _wings:
		var side := int(wing.get_meta("side"))
		wing.scale.x = 1.0 if wings_open else .43
		wing.rotation.z = side*(sin(pose_time*18)*.7 if activity!="Landing" else .06) if wings_open else -side*(1.1+sin(pose_time*18)*.1 if launch_left>0 else 1.1)
	for i in _feet.size():
		_feet[i].position.y = .21 if airborne else 0.0
		_feet[i].rotation.x = .8 if airborne else sin(pose_time*(20 if launch_left>0 else 12)+i*PI)*.5 if moving else 0.0
	update_effect_visibility()
	if is_instance_valid(_wake):
		_wake.position = position+Vector3.UP*(float(definition.navigation.submerge)+.025)
		_wake.rotation.y = rotation.y
		for i in _foam.size():
			var phase := fposmod(pose_time*1.1+i*.21,1.0)
			var sign_value := -1 if i%2==0 else 1
			_foam[i].position = Vector3(sign_value*(.23+phase*.4),sin(phase*PI)*.25 if _splash_left>0 else 0,.2+phase*.8)
			_foam[i].scale = Vector3.ONE*(1-phase)*(.9 if _splash_left>0 else .6)

func update_effect_visibility() -> void:
	if is_instance_valid(_wake): _wake.visible = is_visible_in_tree() and mode=="water" and (hop_progress<1 or _splash_left>0)

func serialize_state() -> Dictionary:
	var state := super.serialize_state()
	var path: Array = []
	for point in flight: path.append(SaveManager.pack_v3(point))
	state.merge({"flock_id":flock_id,"sex":sex,"mode":mode,"step_from":SaveManager.pack_v3(step_from),
		"flight":path,"flight_index":flight_index,"launch_left":launch_left,"flight_left":flight_left,
		"quack_left":quack_left,"shore_left":shore_left})
	return state

func restore_state(state: Dictionary) -> void:
	flock_id = state.flock_id
	sex = state.sex
	mode = state.mode
	step_from = SaveManager.unpack_v3(state.step_from)
	flight.clear()
	for point: Array in state.flight: flight.append(SaveManager.unpack_v3(point))
	flight_index = int(state.flight_index)
	launch_left = float(state.launch_left)
	flight_left = float(state.flight_left)
	quack_left = float(state.quack_left)
	shore_left = float(state.shore_left)
	_splash_left = 0
	super.restore_state(state)

func _exit_tree() -> void:
	if is_instance_valid(_wake): _wake.queue_free()
