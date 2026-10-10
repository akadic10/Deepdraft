extends RefCounted

## Low-cost, interruptible leisure. The dwarf stays in the scheduler's idle
## pool. No tasks, goods or needs are created by wandering or using a chair.
const Seating = preload("res://scripts/components/FurnitureSeating.gd")
const Picking = preload("res://scripts/components/ObjectPicking.gd")
var agent: DwarfAgent
var config: Dictionary
var state := "waiting"
var home := Vector3i(-1,-1,-1)
var goal := Vector3i(-1,-1,-1)
var timer := 0.0
var elapsed := 0.0
var seat: InstalledFurnitureComponent
var _furniture: Node
var _rng := RandomNumberGenerator.new()
var _chairs: Array = []
var _chair_index := 0
var _sitting_blend := 0.0
var _seat_check_revision := -1
var _focus_fire_id := -1

func _init(owner: DwarfAgent) -> void:
	agent = owner
	config = TaskManager.get_config_section("idle")
	_rng.seed = hash([WorldGenerator.world_seed, agent.dwarf_id, "leisure"])

func owns_walk() -> bool:
	return state in ["strolling","to_seat"]

func active() -> bool:
	return home.x >= 0

func cancel() -> void:
	var walking := owns_walk()
	state = "waiting" # Clear before stop_walking emits its synchronous callback.
	_release_seat()
	home = Vector3i(-1,-1,-1)
	goal = home
	_chairs = []
	_sitting_blend = 0.0
	if walking: agent.stop_walking()
	agent._reset_part_offsets()

func _release_seat() -> void:
	if seat != null and seat.idle_seat_owner == agent.dwarf_id:
		seat.idle_seat_owner = -1
		seat.idle_seat_yaw_steps = -1
	seat = null
	_focus_fire_id = -1

func tick(delta: float) -> bool:
	# External/DEV walks retain control. Sleep, ladders and tasks are handled
	# before this method; cargo must never be taken on a leisure walk.
	if not agent._carried_entries.is_empty() or (agent.is_walking() and not owns_walk()): return false
	if home.x < 0:
		home = agent.current_cell()
		timer = _range("start_delay_min_s","start_delay_max_s")
		state = "waiting"
	elapsed += delta
	if state in ["to_seat","sitting","standing_up"] and not _seat_valid():
		cancel()
		return true
	if owns_walk():
		# Straight local routes cannot acquire a distant detour or use ladders.
		if (state=="strolling" and not _clear_stop(goal)) or not NavGrid.line_walkable_flat(agent.current_cell(),goal):
			cancel()
			return true
		agent._follow_path(delta)
		return true
	if state in ["sitting","standing_up"]:
		var step := delta / maxf(.05,float(config.get("seat_transition_s",.5)))
		_sitting_blend = move_toward(_sitting_blend,0.0 if state=="standing_up" else 1.0,step)
		_pose()
		timer -= delta
		if state=="sitting" and timer <= 0: state = "standing_up"
		if state=="standing_up" and _sitting_blend <= 0:
			_release_seat()
			agent._reset_part_offsets()
			_pause()
		return true
	_look_around()
	if state=="looking_for_seat":
		_find_seat_step()
		return true
	timer -= delta
	if timer > 0: return true
	if _rng.randf() < float(config.get("seat_chance",.6)):
		_furniture = agent.get_tree().get_first_node_in_group("furniture_controller")
		if is_instance_valid(_furniture):
			_chairs = _furniture._installed.values()
			_chair_index = 0
			state = "looking_for_seat"
			return true
	_wander()
	return true

func _range(lo: String, hi: String) -> float:
	return _rng.randf_range(float(config.get(lo,5.0)),float(config.get(hi,10.0)))

func _pause() -> void:
	state = "waiting"
	goal = Vector3i(-1,-1,-1)
	timer = _range("pause_min_s","pause_max_s")

func _wander() -> void:
	var from := agent.current_cell()
	var radius := int(config.get("walk_radius",5))
	for attempt in range(int(config.get("candidate_attempts",12))):
		var cell := from+Vector3i(_rng.randi_range(-radius,radius),0,_rng.randi_range(-radius,radius))
		if Vector2(cell.x-from.x,cell.z-from.z).length() < 2.0: continue
		if not _local(cell) or not _uncrowded(cell) or not _clear_stop(cell): continue
		if not NavGrid.line_walkable_flat(from,cell): continue
		goal = cell
		state = "strolling"
		agent.walk_nearby(cell)
		return
	_pause() # A boxed-in dwarf waits; no search loop and no forced teleport.

func _local(cell: Vector3i) -> bool:
	return cell.y == home.y and Vector2(cell.x-home.x,cell.z-home.z).length() <= float(config.get("home_radius",9))

func _uncrowded(cell: Vector3i) -> bool:
	var point := Vector3(cell)+Vector3(.5,1,.5)
	var spacing := float(config.get("spacing",2.4))
	for other: DwarfAgent in TaskManager._agents.values():
		if other == agent or not is_instance_valid(other): continue
		if point.distance_to(other.global_position) < spacing: return false
		if other._idle_behavior != null and other._idle_behavior.goal.x >= 0:
			if Vector3(cell-other._idle_behavior.goal).length() < spacing: return false
	return true

func _clear_stop(cell: Vector3i) -> bool:
	if not NavGrid.is_walkable(cell): return false
	for offset: Vector3i in [Vector3i.ZERO,Vector3i.LEFT,Vector3i.RIGHT,Vector3i.FORWARD,Vector3i.BACK]:
		if not NavGrid.ladder_at(cell+offset).is_empty(): return false
	for zone in StockpileManager._zones.values():
		if cell in zone.tile_cells: return false
	var furniture := agent.get_tree().get_first_node_in_group("furniture_controller")
	if furniture != null:
		if furniture._cell_to_ghost.has(cell): return false
		for offset: Vector3i in [Vector3i.LEFT,Vector3i.RIGHT,Vector3i.FORWARD,Vector3i.BACK]:
			if furniture._cell_to_installed.has(cell+offset): return false
	return true

## One furniture candidate per frame; no full-colony pathfinding burst.
func _find_seat_step() -> void:
	if _chair_index >= _chairs.size():
		_chairs = []
		_wander()
		return
	var candidate: InstalledFurnitureComponent = _chairs[_chair_index]
	_chair_index += 1
	if candidate.flagged_uninstall or candidate.idle_seat_owner >= 0 or not is_instance_valid(candidate.node): return
	if not Seating.is_chair(candidate.def) or not candidate.def.seating_chair.has("rest_pose"): return
	if Vector3(candidate.origin_cell-agent.current_cell()).length() > float(config.get("seat_radius",9)): return
	var facing := _seat_facing(candidate)
	if facing.is_empty(): return
	var access := Seating.access_cells(candidate.def,candidate.origin_cell,candidate.yaw_steps)
	var from := agent.current_cell()
	access.sort_custom(func(a: Vector3i,b: Vector3i): return Vector3(a-from).length_squared() < Vector3(b-from).length_squared())
	for cell in access:
		if not _local(cell) or not _uncrowded(cell) or not NavGrid.is_walkable(cell): continue
		if not NavGrid.line_walkable_flat(from,cell): continue
		seat = candidate
		seat.idle_seat_owner = agent.dwarf_id
		seat.idle_seat_yaw_steps = int(facing.yaw)
		_focus_fire_id = int(facing.get("fire_id",-1))
		_seat_check_revision = -1
		goal = cell
		state = "to_seat"
		_chairs = []
		agent.walk_nearby(cell)
		return

## Pick once per visit, keeping backed chairs aligned with their furniture.
## Round stools prefer the nearest visible fire only if the seated pose fits.
func _seat_facing(candidate: InstalledFurnitureComponent) -> Dictionary:
	if bool(candidate.def.seating_chair.get("face_nearby_fire",false)):
		var fires: Array = []
		var radius := float(config.get("seat_focus_radius",6))
		for piece: InstalledFurnitureComponent in _furniture._installed.values():
			if piece.def.get("seating_focus","") != "fire" or piece.flagged_uninstall or not is_instance_valid(piece.node): continue
			if piece.origin_cell.y != candidate.origin_cell.y: continue
			if piece.node.global_position.distance_to(candidate.node.global_position) > radius: continue
			fires.append(piece)
		fires.sort_custom(func(a,b): return a.node.global_position.distance_squared_to(candidate.node.global_position) < b.node.global_position.distance_squared_to(candidate.node.global_position))
		for fire: InstalledFurnitureComponent in fires:
			var offset := fire.node.global_position-candidate.node.global_position
			if offset.length_squared() < .001: continue
			var yaw := posmod(roundi(atan2(offset.x,offset.z)/(PI*.5)),4)
			if not _furniture._seating.placement_reason(candidate.def,candidate.origin_cell,yaw,candidate).is_empty(): continue
			var eyes := candidate.node.global_position+Vector3(0,2.5,0)
			var sight := fire.node.global_position+Vector3.UP-eyes
			if not Picking.terrain_hit(eyes,sight.normalized(),WorldData.WORLD_SIZE_Y-1,sight.length()).is_empty(): continue
			return {"yaw":yaw,"fire_id":fire.installed_id}
	if _furniture._seating.placement_reason(candidate.def,candidate.origin_cell,candidate.yaw_steps,candidate).is_empty():
		return {"yaw":candidate.yaw_steps}
	return {}

func _seat_valid() -> bool:
	if seat == null or not is_instance_valid(_furniture) or not is_instance_valid(seat.node): return false
	if _furniture._installed.get(seat.installed_id) != seat or seat.flagged_uninstall: return false
	if seat.idle_seat_owner != agent.dwarf_id or not NavGrid.is_walkable(goal): return false
	for cell in seat.cells:
		if not BlockRegistry.is_solid(NavGrid._block_id(cell.x,cell.y,cell.z)): return false
	if _seat_check_revision != NavGrid.navigation_revision:
		if not _furniture._seating.placement_reason(seat.def,seat.origin_cell,Seating.clearance_yaw(seat),seat).is_empty(): return false
		_seat_check_revision = NavGrid.navigation_revision
	return true

func walk_finished(success: bool) -> void:
	if not owns_walk(): return
	if success and state=="to_seat" and _seat_valid():
		state = "sitting"
		_sitting_blend = 0.0
		timer = _range("sit_min_s","sit_max_s")
		agent.rotation.y = float(seat.idle_seat_yaw_steps)*PI*.5
	else:
		_release_seat()
		_pause()

func _look_around() -> void:
	agent._idle_bob()
	if is_instance_valid(agent._head): agent._head.rotation.y = sin(elapsed*.45+agent._bob_phase)*.16

func _vector(values: Array) -> Vector3:
	return Vector3(float(values[0]),float(values[1]),float(values[2]))

## Keep the logical actor on the proven access tile. Seating only offsets its
## visual parts into the chair, so interruption/load never starts inside solid
## furniture. Each seat definition supplies its supported torso and resting limbs.
func _pose() -> void:
	var base := agent.to_local(seat.node.global_position)
	var pose: Dictionary = seat.def.seating_chair.rest_pose
	var parts := {"body":agent._body,"left_hand":agent._hand_l,"right_hand":agent._hand_r,
		"left_foot":agent._foot_l,"right_foot":agent._foot_r}
	for key: String in parts:
		if is_instance_valid(parts[key]): parts[key].position = (base+_vector(pose[key]))*_sitting_blend
	if is_instance_valid(agent._head):
		agent._head.position = (base+_vector(pose.body)+Vector3(0,sin(elapsed*1.8)*.012,0))*_sitting_blend
		var look := 0.0
		var fire = _furniture._installed.get(_focus_fire_id)
		if fire != null and not fire.flagged_uninstall and is_instance_valid(fire.node):
			var direction: Vector3 = fire.node.global_position-seat.node.global_position
			look = clampf(wrapf(atan2(direction.x,direction.z)-agent.rotation.y,-PI,PI),-PI*.25,PI*.25)
		agent._head.rotation.y = (look+sin(elapsed*.7+agent._bob_phase)*.025)*_sitting_blend

func describe() -> Dictionary:
	match state:
		"strolling": return {"activity":"Strolling nearby", "explanation":"Taking a short walk while available for work.", "destination":goal}
		"to_seat": return {"activity":"Going to sit", "explanation":"Heading to a nearby free chair; available for work.", "destination":goal}
		"sitting","standing_up": return {"activity":"Sitting" if state=="sitting" else "Getting up", "explanation":"Taking a seat while available for work.", "destination":goal}
	return {"activity":"Looking around", "explanation":"Taking a breather while available for work.", "destination":Vector3i(-1,-1,-1)}
