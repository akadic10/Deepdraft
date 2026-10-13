extends RefCounted

## Emergency self-care; SurfaceDetailManager owns claims, crop work and rewards.
const Route = preload("WorkRouteProbe.gd")
var agent: DwarfAgent
var owner: Node
var query := {}
var route := {}
var candidates: Array = []
var id := ""
var state := "searching"
var elapsed := 0.0
var travel_left := 0.0
var destination := Vector3i(-1,-1,-1)

func _init(dwarf: DwarfAgent) -> void:
	agent = dwarf
	owner = agent.get_tree().get_first_node_in_group("surface_details")

func tick(seconds: float) -> void:
	if not is_instance_valid(owner):
		_fail()
		return
	var config: Dictionary = agent._food.config
	if state == "searching":
		elapsed += seconds
		if elapsed >= float(config.search_seconds):
			_fail()
			return
		var deadline := Time.get_ticks_usec()+int(config.search_budget_usec)
		if not bool(query.get("done",false)):
			if not owner.advance_forage_candidates(agent.current_cell(),int(config.forage_distance),query,deadline): return
			query.done = true
			candidates = query.candidates
		if id.is_empty():
			if candidates.is_empty():
				_fail()
				return
			var candidate: Dictionary = candidates.pop_front()
			id = candidate.id
			destination = candidate.cell
		if not owner.forage_available(id):
			_next()
			return
		var goals := {}
		for cell: Vector3i in owner.forage_stands(id,agent.current_cell()): goals[cell] = true
		if goals.is_empty():
			_next()
			return
		var result := Route.advance(route,agent.current_cell(),goals.keys()[0],int(config.search_nodes),deadline,false,goals)
		if result == NavGrid.ProbeResult.SEARCHING: return
		if result != NavGrid.ProbeResult.REACHABLE or path_length(agent.current_cell(),route.get("path",[])) > float(config.forage_distance):
			_next()
			return
		if not owner.claim_forage(id,agent.dwarf_id):
			_next()
			return
		state = "walking"
		travel_left = agent._food.start_walk(route.path)
		agent._food.message = "No reachable harvested food. Picking nearby wild berries."
	elif not owner.forage_available(id,agent.dwarf_id):
		_fail()
	elif state == "walking":
		travel_left -= seconds
		if travel_left <= 0 or agent._move_path.is_empty(): _fail()
		else: agent._follow_path(seconds)
	elif state == "picking":
		var left: float = owner.advance_forage(id,agent.dwarf_id,agent.current_cell(),seconds*agent._food.work_multiplier())
		if left < 0:
			_fail()
			return
		var contact: Vector3 = owner._gather_contact(agent.global_position,id)
		var direction := contact-agent.global_position
		agent.rotation.y = atan2(direction.x,direction.z)
		agent._carry_pose.gather(fposmod(left,1.0),agent.to_local(contact))
		if left == 0.0:
			var portion: Node3D = owner.take_forage_portion(id,agent.dwarf_id,agent.current_cell())
			if portion == null: _fail()
			else: agent._food.receive_portion(portion)

func walk_finished(success: bool) -> void:
	if state != "walking": return
	if success and is_instance_valid(owner) and agent.current_cell() in owner.forage_stands(id,agent.current_cell()):
		state = "picking"
		agent._reset_part_offsets()
	else: _fail()

func release() -> void:
	if is_instance_valid(owner): owner.release_forage(id,agent.dwarf_id)

func _next() -> void:
	release()
	id = ""
	route = {}

func _fail() -> void:
	agent._food.shortage = true
	agent._food.cancel("No reachable food or nearby ripe berries; will try again.")

static func path_length(from: Vector3i, path: Array) -> float:
	var length := 0.0
	var previous := from
	for cell: Vector3i in path:
		length += Vector3(cell-previous).length()
		previous = cell
	return length
