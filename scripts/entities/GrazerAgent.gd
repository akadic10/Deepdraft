extends Node3D
## Lightweight wildlife state. The scene owner supplies definitions and ticks;
## no tasks, inventories, starvation, breeding or off-screen respawn.
const Navigation = preload("res://scripts/components/AnimalNavigation.gd")
const Lighting = preload("res://scripts/components/UndergroundLighting.gd")

var animal_id := ""
var definition: Dictionary
var footprint := 1
var cell := Vector3i.ZERO
var home := Vector3i.ZERO
var target := Vector3i.ZERO
var hunger := 0.0
var fatigue := 0.0
var activity := "Idle"
var timer := 0.0
var calm_left := 0.0
var hop_progress := 1.0
var hop_seconds := 0.48
var rest_offset := 0.0
var pose_time := 0.0
var rng := RandomNumberGenerator.new()
var visual: Node3D
var head: Node3D
var ears: Node3D
var arrival: Dictionary = {}

func configure(data: Dictionary, id: String, origin: Vector3i, seed_value: int, models: Dictionary) -> void:
	definition = data
	footprint = int(data.navigation.get("footprint", 1))
	animal_id = id
	cell = origin
	home = origin
	target = origin
	position = Navigation.centre(cell, footprint)
	rng.seed = seed_value
	hunger = rng.randf_range(0.12, 0.42)
	fatigue = rng.randf_range(0.05, 0.35)
	rest_offset = rng.randf_range(-1.0, 1.0)
	timer = rng.randf_range(1, 5)
	visual = Node3D.new()
	add_child(visual)
	_build_visual(models)
	_materials(visual)
	Lighting.bind_world_tree(visual)

func _build_visual(_models: Dictionary) -> void:
	pass # Species supplies articulated model parts.

func _materials(node: Node) -> void:
	if node is MeshInstance3D:
		var material := StandardMaterial3D.new()
		material.vertex_color_use_as_albedo = true
		material.roughness = 1.0
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		node.material_override = material
	for child in node.get_children(): _materials(child)

func advance(seconds: float, hours: float, threats: Array) -> void:
	if seconds <= 0: return
	var behavior: Dictionary = definition.behavior
	hunger = clampf(hunger + hours * float(behavior.hunger_per_hour), 0, 1)
	fatigue = clampf(fatigue + hours * float(behavior.fatigue_per_hour), 0, 1)
	pose_time += seconds
	if not arrival.is_empty() and activity == "Arrival blocked": arrival.blocked = float(arrival.blocked)+seconds
	var nearest := Vector3.ZERO
	var distance := INF
	for threat: Vector3 in threats:
		var d := position.distance_to(threat)
		if d < distance:
			distance = d
			nearest = threat
	if distance < float(behavior.threat_radius) or (calm_left > 0 and distance < float(behavior.safe_radius)):
		calm_left = float(behavior.calm_seconds)
	else:
		calm_left = maxf(0, calm_left - seconds)
	if calm_left > 0 and activity != "Fleeing":
		activity = "Fleeing"
		timer = 0
		# An interrupted graze grants no meal, and a nap ends immediately.
		if hop_progress < 1: hop_seconds = float(definition.navigation.flee_hop_seconds)
	if not _support(seconds):
		_pose()
		return
	if hop_progress < 1:
		if not Navigation.can_hop(cell, target, int(definition.navigation.clearance), footprint):
			target = cell
			hop_progress = 1
			position = Navigation.centre(cell, footprint)
			timer = 0
		else:
			hop_progress = minf(1, hop_progress + seconds / hop_seconds)
			position = _hop_position()
			if hop_progress >= 1: cell = target
		_pose()
		return
	if activity == "Sleeping" and calm_left <= 0:
		fatigue = maxf(0, fatigue - hours * (float(behavior.sleep_recovery_per_hour) + float(behavior.fatigue_per_hour)))
		if fatigue > float(behavior.wake_threshold) and hunger < float(behavior.wake_hunger_threshold):
			_pose()
			return
		activity = "Idle"
		timer = 0
	timer = maxf(0, timer - seconds)
	if timer > 0:
		_pose()
		return
	if activity == "Grazing" and calm_left <= 0 and can_graze():
		hunger = maxf(0, hunger - float(behavior.meal_relief))
	_decide(nearest, distance)
	_pose()

func can_graze() -> bool:
	return _forage_at(cell)

func _forage_at(at: Vector3i) -> bool:
	var key := BlockRegistry.get_key(Navigation.block_at(at + Vector3i.DOWN))
	return String(key).begins_with("base:terrain:surface:") and BlockRegistry.get_def(key).get("kind", "") in definition.forage_kinds

func _rest_time() -> bool:
	var hour := fposmod(WorldClock.hour + rest_offset, 24)
	for period: Array in definition.behavior.rest_hours:
		if float(period[0]) < float(period[1]):
			if hour >= float(period[0]) and hour < float(period[1]): return true
		elif hour >= float(period[0]) or hour < float(period[1]): return true
	return false

func _decide(threat: Vector3, threat_distance: float) -> void:
	var behavior: Dictionary = definition.behavior
	var choices: Array[Vector3i] = []
	for next in Navigation.neighbors(cell, int(definition.navigation.clearance), footprint):
		if _can_enter(next): choices.append(next)
	if calm_left > 0:
		activity = "Fleeing"
		var escape := cell
		var best := position.distance_squared_to(threat) if threat_distance < INF else -INF
		for next in choices:
			var score := Navigation.centre(next, footprint).distance_squared_to(threat) if threat_distance < INF else rng.randf()
			if score > best:
				best = score
				escape = next
		if escape != cell: _hop(escape, true)
		else: timer = 0.2
		return
	if hunger >= float(behavior.hungry_threshold) and can_graze():
		activity = "Grazing"
		timer = float(behavior.graze_seconds)
		return
	if fatigue >= float(behavior.sleep_threshold) and (_rest_time() or fatigue >= float(behavior.exhausted_threshold)):
		# Prefer nearby cover once; then settle. No inaccessible den/path dependency.
		if activity != "Seeking shelter":
			var sheltered := cell
			var cover := _cover(cell)
			for next in choices:
				if _cover(next) > cover:
					cover = _cover(next)
					sheltered = next
			if sheltered != cell:
				activity = "Seeking shelter"
				_hop(sheltered)
				return
		activity = "Sleeping"
		return
	if _continue_arrival(): return
	activity = "Foraging" if hunger >= float(behavior.hungry_threshold) else "Exploring"
	var destination := cell
	var best_score := -INF
	for next in choices:
		var home_distance := Vector2(next.x-home.x, next.z-home.z).length()
		var score := rng.randf() * 2.0
		score += _movement_score(next)
		if home_distance > float(definition.navigation.home_radius): score -= home_distance
		if activity == "Foraging" and _forage_at(next): score += 4
		if score > best_score:
			best_score = score
			destination = next
	if destination != cell: _hop(destination)
	else: activity = "Alert" if hunger >= float(behavior.hungry_threshold) else "Idle"
	timer = rng.randf_range(float(behavior.idle_seconds[0]), float(behavior.idle_seconds[1]))

func _can_enter(_cell: Vector3i) -> bool:
	return true

func begin_arrival(event_id: String, route: Array, blocked_seconds: float) -> void:
	arrival = {"event": event_id, "route": route.duplicate(true), "cursor": 1,
		"blocked": 0.0, "max_blocked": blocked_seconds, "status": "Travelling inland"}
	home = SaveManager.unpack_v3i(route.back())
	activity = "Arriving"
	timer = 0

func _continue_arrival() -> bool:
	if arrival.is_empty() or arrival.route.is_empty(): return false
	var route: Array = arrival.route
	var cursor := int(arrival.cursor)
	# Escape or terrain support can move the animal off its intended route.
	# Rejoin using legal local hops, keeping needs and fleeing higher priority.
	for i in range(cursor, route.size()):
		if cell == SaveManager.unpack_v3i(route[i]): cursor = i+1
	arrival.cursor = cursor
	if cursor >= route.size():
		arrival.route = []
		arrival.status = "Settled"
		return false
	var next := SaveManager.unpack_v3i(route[cursor])
	if not Navigation.can_hop(cell, next, int(definition.navigation.clearance), footprint):
		next = Navigation.approach(cell, Navigation.centre(next, footprint), int(definition.navigation.clearance), footprint, 64, .1)
	if next != cell and _can_enter(next):
		activity = "Arriving"
		arrival.blocked = 0.0
		_hop(next)
		timer = 0
		return true
	if float(arrival.blocked) >= float(arrival.max_blocked):
		arrival.route = []
		arrival.status = "Journey interrupted"
		return false # Remain here safely; ordinary wandering still favours home.
	activity = "Arrival blocked"
	timer = 1.0
	return true

func _movement_score(_cell: Vector3i) -> float:
	return 0.0

func _cover(at: Vector3i) -> int:
	var result := 0
	for direction: Vector3i in Navigation.DIRECTIONS:
		if not Navigation.clear(at + direction * footprint, int(definition.navigation.clearance), footprint): result += 1
	return result

func _hop(destination: Vector3i, fleeing := false) -> void:
	target = destination
	hop_progress = 0
	hop_seconds = float(definition.navigation.flee_hop_seconds if fleeing else definition.navigation.hop_seconds)
	var direction := Vector3(target - cell)
	rotation.y = atan2(-direction.x, -direction.z)
	if fleeing: timer = 0

func _hop_position() -> Vector3:
	var from := Navigation.centre(cell, footprint)
	var to := Navigation.centre(target, footprint)
	# Rise before crossing a step; clear its edge before descending. A straight
	# diagonal interpolation would push the body through the step's solid side.
	if target.y > cell.y:
		if hop_progress < 0.32: return from + Vector3.UP * (hop_progress / 0.32)
		return (from + Vector3.UP).lerp(to, (hop_progress - 0.32) / 0.68)
	if target.y < cell.y:
		if hop_progress < 0.68: return from.lerp(to + Vector3.UP, hop_progress / 0.68)
		return (to + Vector3.UP).lerp(to, (hop_progress - 0.68) / 0.32)
	return from.lerp(to, hop_progress)

func _support(seconds: float) -> bool:
	if Navigation.standable(cell, int(definition.navigation.clearance), footprint): return true
	hop_progress = 1
	target = cell
	# Return an interrupted hop to its last supported column before falling;
	# fractional X/Z must not descend through the neighbouring solid step.
	position.x = float(cell.x) + footprint * 0.5
	position.z = float(cell.z) + footprint * 0.5
	# Mining out support causes a visible fall, without crossing solid terrain.
	if Navigation.clear(cell, int(definition.navigation.clearance), footprint):
		var lower := cell + Vector3i.DOWN
		if Navigation.clear(lower, int(definition.navigation.clearance), footprint):
			position.y = maxf(float(lower.y), position.y - seconds * float(definition.navigation.fall_speed))
			if position.y <= float(lower.y):
				cell = lower
				target = cell
			activity = "Falling"
			timer = 0
			return false
	# A new building may occupy a wildlife cell: move only to an open neighbour.
	for direction: Vector3i in Navigation.DIRECTIONS:
		var next := cell + direction * footprint
		if Navigation.standable(next, int(definition.navigation.clearance), footprint) and _can_enter(next):
			cell = next
			target = cell
			position = Navigation.centre(cell, footprint)
			activity = "Alert"
			timer = 0
			return false
	activity = "Alert"
	return false

func _pose() -> void:
	pass # Species supplies gait, grazing and rest poses.

func serialize_state() -> Dictionary:
	var state := {"id": animal_id, "cell": SaveManager.pack_v3i(cell), "home": SaveManager.pack_v3i(home),
		"target": SaveManager.pack_v3i(target), "position": SaveManager.pack_v3(position), "yaw": rotation.y,
		"hunger": hunger, "fatigue": fatigue, "activity": activity, "timer": timer, "calm_left": calm_left,
		"hop_progress": hop_progress, "hop_seconds": hop_seconds, "rest_offset": rest_offset,
		"pose_time": pose_time, "rng_state": str(rng.state)}
	if not arrival.is_empty(): state.arrival = arrival.duplicate(true)
	return state

func restore_state(state: Dictionary) -> void:
	arrival = state.get("arrival", {}).duplicate(true)
	cell = SaveManager.unpack_v3i(state.get("cell", []))
	home = SaveManager.unpack_v3i(state.get("home", []))
	target = SaveManager.unpack_v3i(state.get("target", []))
	position = SaveManager.unpack_v3(state.get("position", []))
	rotation.y = float(state.get("yaw", 0))
	hunger = clampf(float(state.get("hunger", 0)), 0, 1)
	fatigue = clampf(float(state.get("fatigue", 0)), 0, 1)
	activity = String(state.get("activity", "Idle"))
	timer = maxf(0, float(state.get("timer", 0)))
	calm_left = maxf(0, float(state.get("calm_left", 0)))
	hop_progress = clampf(float(state.get("hop_progress", 1)), 0, 1)
	hop_seconds = maxf(0.05, float(state.get("hop_seconds", 0.48)))
	rest_offset = float(state.get("rest_offset", 0))
	pose_time = float(state.get("pose_time", 0))
	rng.state = int(String(state.get("rng_state", str(rng.state))))
	_pose()
