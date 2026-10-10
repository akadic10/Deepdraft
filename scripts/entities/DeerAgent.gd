extends "res://scripts/entities/GrazerAgent.gd"
## A wider grazer with four articulated legs and loose, non-commanded herds.
var herd_id := ""
var herd_centre := Vector3.ZERO
var herd_members := 1
var peer_spaces: Array[Vector3] = [] # Transient positions/stride reservations.
var legs: Array[Node3D] = []
var neck: Node3D

func _build_visual(models: Dictionary) -> void:
	visual.add_child((models.body as PackedScene).instantiate())
	neck = Node3D.new()
	neck.position = Vector3(0,1.5,-.3)
	visual.add_child(neck)
	var neck_mesh := (models.neck as PackedScene).instantiate() as Node3D
	neck.add_child(neck_mesh)
	neck_mesh.position = -neck.position
	var head_origin := Vector3(0,2.65,-.55)
	head = Node3D.new()
	head.position = head_origin - neck.position
	neck.add_child(head)
	for part in ["head","antlers"]:
		var mesh := (models[part] as PackedScene).instantiate() as Node3D
		head.add_child(mesh)
		mesh.position = -head_origin
	ears = Node3D.new()
	ears.position = Vector3(0,2.65,-0.45) - head_origin
	head.add_child(ears)
	var ear_mesh := (models.ears as PackedScene).instantiate() as Node3D
	ears.add_child(ear_mesh)
	ear_mesh.position = -head_origin - ears.position
	for pivot: Vector3 in [Vector3(-.35,1.25,-.5),Vector3(.35,1.25,-.5),Vector3(-.35,1.25,.5),Vector3(.35,1.25,.5)]:
		var leg := Node3D.new()
		leg.position = pivot
		visual.add_child(leg)
		leg.add_child((models.leg as PackedScene).instantiate())
		legs.append(leg)

func _can_enter(at: Vector3i) -> bool:
	var centre := Navigation.centre(at,footprint)
	for peer in peer_spaces:
		if absf(peer.y-centre.y) < 2 and absf(peer.x-centre.x) < float(definition.herd.personal_space) and absf(peer.z-centre.z) < float(definition.herd.personal_space): return false
	return true

func _movement_score(at: Vector3i) -> float:
	if herd_members < 2: return 0
	var point := Navigation.centre(at,footprint)
	var distance := Vector2(point.x-herd_centre.x,point.z-herd_centre.z).length()
	return -maxf(0,distance-float(definition.herd.cohesion_radius))*float(definition.herd.cohesion_weight)

func can_graze() -> bool:
	# The lowered neck reaches beyond the standing footprint. Check one extra
	# row in the facing direction so the muzzle cannot enter a wall or a pit.
	var forward := Vector3i(roundi(-sin(rotation.y)),0,roundi(-cos(rotation.y)))
	return super.can_graze() and Navigation.standable(cell+forward,int(definition.navigation.clearance),footprint)

func advance(seconds: float, hours: float, threats: Array) -> void:
	if seconds > 0 and activity == "Grazing" and not can_graze():
		activity = "Idle"
		timer = 0
	super.advance(seconds,hours,threats)

func _pose() -> void:
	var sleeping := activity == "Sleeping"
	var moving := hop_progress < 1
	visual.position.y = -0.85 if sleeping else sin(hop_progress*PI)*float(definition.navigation.hop_height) if moving else 0.0
	# Lower the neck, counter-rotate the head: muzzle reaches grass while the
	# antlers stay above it. Rest folds the legs without shrinking the torso.
	neck.rotation.x = -2.3 if activity == "Grazing" else .15 if sleeping else 0.0
	head.rotation.x = 1.5 + sin(pose_time*5)*.035 if activity == "Grazing" else -.35 if sleeping else 0.0
	ears.rotation.x = .32 if sleeping else sin(pose_time*1.1)*.04
	for i in range(legs.size()):
		var leg := legs[i]
		var diagonal := 1.0 if i in [0,3] else -1.0
		leg.rotation.x = diagonal * .6 if sleeping else sin(hop_progress*TAU)*diagonal*.38 if moving else 0.0
		# Keep a walking hoof above its support plane as the leg swings.
		leg.scale.y = .32 if sleeping else 1.0

func serialize_state() -> Dictionary:
	var result := super.serialize_state()
	result.herd_id = herd_id
	return result

func restore_state(state: Dictionary) -> void:
	herd_id = String(state.get("herd_id",""))
	super.restore_state(state)
