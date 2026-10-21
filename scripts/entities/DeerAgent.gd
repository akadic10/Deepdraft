extends "res://scripts/entities/GrazerAgent.gd"
## A wider grazer with four articulated legs and loose, non-commanded herds.
var herd_id := ""
var herd_centre := Vector3.ZERO
var herd_members := 1
var peer_spaces: Array[Vector3] = [] # Transient positions/stride reservations.
var legs: Array[Node3D] = []
var neck: Node3D

func _build_visual(models: Dictionary) -> void:
	# Rig numbers live in deer.json (visual_pose); parts keep standing coordinates.
	var pose: Dictionary = definition.visual_pose
	visual.position.z = float(pose.get("shift_z", 0.0))
	visual.add_child((models.body as PackedScene).instantiate())
	neck = Node3D.new()
	neck.position = _point(pose.neck)
	visual.add_child(neck)
	var neck_mesh := (models.neck as PackedScene).instantiate() as Node3D
	neck.add_child(neck_mesh)
	neck_mesh.position = -neck.position
	var head_origin := _point(pose.head)
	head = Node3D.new()
	head.position = head_origin - neck.position
	neck.add_child(head)
	for part in ["head","antlers"]:
		var mesh := (models[part] as PackedScene).instantiate() as Node3D
		head.add_child(mesh)
		mesh.position = -head_origin
	ears = Node3D.new()
	ears.position = _point(pose.ears) - head_origin
	head.add_child(ears)
	var ear_mesh := (models.ears as PackedScene).instantiate() as Node3D
	ears.add_child(ear_mesh)
	ear_mesh.position = -head_origin - ears.position
	for side: Vector2 in [Vector2(-1,-1),Vector2(1,-1),Vector2(-1,1),Vector2(1,1)]:
		var pivot := Vector3(side.x*float(pose.hip_x),float(pose.hip_y),side.y*float(pose.hip_z))
		var leg := preload("res://scripts/components/RigidAnimalLeg.gd").build(models.leg,pivot,float(pose.knee_y))
		visual.add_child(leg)
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
	visual.position.y = float(definition.visual_pose.rest_y) if sleeping else sin(hop_progress*PI)*float(definition.navigation.hop_height) if moving else 0.0
	_squash_stretch(hop_progress if moving and not sleeping else 1.0)
	# Lower the neck, counter-rotate the head: muzzle reaches grass while the
	# antlers stay above it. Rest folds the legs without shrinking the torso.
	neck.rotation.x = -2.3 if activity == "Grazing" else .15 if sleeping else 0.0
	head.rotation.x = 1.5 + sin(pose_time*5)*.035 if activity == "Grazing" else -.35 if sleeping else 0.0
	ears.rotation.x = .32 if sleeping else sin(pose_time*1.1)*.04
	for i in range(legs.size()):
		var leg := legs[i]
		var diagonal := 1.0 if i in [0,3] else -1.0
		var folded := -1.0 if i<2 else 1.0
		# Fold rigid voxel legs along the body; never compress their cells.
		leg.rotation.x = folded * 1.35 if sleeping else sin(hop_progress*TAU)*diagonal*.38 if moving else 0.0
		leg.get_node("Knee").rotation.x=-folded*2.7 if sleeping else 0.0

func serialize_state() -> Dictionary:
	var result := super.serialize_state()
	result.herd_id = herd_id
	return result

func restore_state(state: Dictionary) -> void:
	herd_id = String(state.get("herd_id",""))
	super.restore_state(state)
