extends "res://scripts/entities/GrazerAgent.gd"
## Shared terrestrial movement/rest, with bounded pursuit instead of grazing.
## WildlifeManager owns prey claims and the atomic capture/population change.
var hunt_target_id := ""
var prey: Node3D # Transient: rebound by stable ID after restore.
var hunt_left := 0.0
var retry_hours := 0.0
var satisfied_hours := 0.0
var legs: Array[Node3D] = []
var tail: Node3D

func configure(data: Dictionary, id: String, origin: Vector3i, seed_value: int, models: Dictionary) -> void:
	super.configure(data,id,origin,seed_value,models)
	hunger = rng.randf_range(float(data.population.initial_hunger[0]),float(data.population.initial_hunger[1]))
	_pose()

func _build_visual(models: Dictionary) -> void:
	visual.add_child((models.body as PackedScene).instantiate())
	head = Node3D.new()
	head.position = Vector3(0,1.125,-.5)
	visual.add_child(head)
	var face := (models.head as PackedScene).instantiate() as Node3D
	head.add_child(face)
	face.position = -head.position
	ears = Node3D.new()
	head.add_child(ears)
	var ear_mesh := (models.ears as PackedScene).instantiate() as Node3D
	ears.add_child(ear_mesh)
	ear_mesh.position = -head.position
	tail = Node3D.new()
	tail.position = Vector3(0,.875,.5)
	visual.add_child(tail)
	var brush := (models.tail as PackedScene).instantiate() as Node3D
	tail.add_child(brush)
	brush.position = -tail.position
	for pivot: Vector3 in [Vector3(-.25,.75,-.375),Vector3(.25,.75,-.375),Vector3(-.25,.75,.375),Vector3(.25,.75,.375)]:
		var leg := Node3D.new()
		leg.position = pivot
		visual.add_child(leg)
		leg.add_child((models.leg as PackedScene).instantiate())
		legs.append(leg)

func can_graze() -> bool:
	return false

func wants_hunt() -> bool:
	if not arrival.is_empty() and not arrival.route.is_empty(): return false
	return hunger >= float(definition.behavior.hungry_threshold) and satisfied_hours <= 0 and retry_hours <= 0 and calm_left <= 0 and activity not in ["Eating","Sleeping"] and fatigue < float(definition.behavior.exhausted_threshold)

func begin_hunt(target_animal: Node3D) -> void:
	prey = target_animal
	hunt_target_id = prey.animal_id
	hunt_left = float(definition.hunting.pursuit_seconds)
	timer = 0
	activity = "Hunting"
	if hop_progress < 1: hop_seconds = float(definition.hunting.stride_seconds)

func abandon_hunt() -> void:
	hunt_target_id = ""
	prey = null
	hunt_left = 0
	retry_hours = float(definition.hunting.retry_hours)
	if activity == "Hunting":
		activity = "Idle"
		timer = 0

func begin_meal(food: Dictionary) -> void:
	hunt_target_id = ""
	prey = null
	hunt_left = 0
	# Credit the one captured meal immediately, even if a dwarf interrupts the
	# eating pose. The wolf never makes another kill to replace that animation.
	hunger = maxf(0,hunger-float(food.meal_relief))
	satisfied_hours = float(food.satisfied_hours)
	activity = "Eating"
	timer = float(definition.hunting.eat_seconds)
	_pose()

func advance(seconds: float, hours: float, threats: Array) -> void:
	if seconds <= 0: return
	retry_hours = maxf(0,retry_hours-hours)
	satisfied_hours = maxf(0,satisfied_hours-hours)
	if not hunt_target_id.is_empty():
		hunt_left = maxf(0,hunt_left-seconds)
		var interrupted := calm_left > 0 or not is_instance_valid(prey) or hunt_left <= 0
		if is_instance_valid(prey): interrupted = interrupted or position.distance_to(prey.position) > float(definition.hunting.pursuit_radius)
		for threat: Vector3 in threats:
			if position.distance_to(threat) < float(definition.behavior.threat_radius): interrupted = true
		if interrupted: abandon_hunt()
	super.advance(seconds,hours,threats)

func _decide(threat: Vector3, threat_distance: float) -> void:
	if not hunt_target_id.is_empty() and calm_left <= 0 and wants_hunt() and is_instance_valid(prey):
		activity = "Hunting"
		var destination := Navigation.approach(cell,prey.position,int(definition.navigation.clearance),footprint,int(definition.hunting.route_budget),float(definition.hunting.capture_radius))
		if destination != cell:
			_hop(destination)
			hop_seconds = float(definition.hunting.stride_seconds)
			timer = 0
			return
		# Stay for the manager's contact check; blocked hunts back off.
		if Navigation.contact_clear(position,prey.position,float(definition.hunting.capture_radius)):
			timer = .1
			return
		abandon_hunt()
	elif not hunt_target_id.is_empty(): abandon_hunt()
	super._decide(threat,threat_distance)
	if activity in ["Foraging","Alert"]: activity = "Searching" if wants_hunt() else "Prowling"
	elif activity == "Exploring": activity = "Prowling"

func _pose() -> void:
	var resting := activity == "Sleeping"
	var moving := hop_progress < 1
	visual.position.y = -.43 if resting else sin(hop_progress*PI)*float(definition.navigation.hop_height) if moving else 0.0
	head.rotation.x = -.45 + sin(pose_time*6)*.045 if activity == "Eating" else -.12 if resting else 0.0
	ears.rotation.x = .3 if resting else sin(pose_time*1.3)*.025
	tail.rotation.y = sin(pose_time*2)*.09 if moving else .35 if resting else 0.0
	for i in range(legs.size()):
		var diagonal := 1.0 if i in [0,3] else -1.0
		legs[i].rotation.x = diagonal*.65 if resting else sin(hop_progress*TAU)*diagonal*.38 if moving else 0.0
		legs[i].scale.y = .4 if resting else 1.0

func serialize_state() -> Dictionary:
	var result := super.serialize_state()
	result.merge({"hunt_target_id":hunt_target_id,"hunt_left":hunt_left,"retry_hours":retry_hours,"satisfied_hours":satisfied_hours})
	return result

func restore_state(state: Dictionary) -> void:
	hunt_target_id = String(state.get("hunt_target_id",""))
	hunt_left = maxf(0,float(state.get("hunt_left",0)))
	retry_hours = maxf(0,float(state.get("retry_hours",0)))
	satisfied_hours = maxf(0,float(state.get("satisfied_hours",0)))
	prey = null
	super.restore_state(state)
