extends RefCounted

## Emergency self-care; SurfaceDetailManager owns claims, crop work and rewards.
const Route = preload("WorkRouteProbe.gd")
const PENDING := 0
const FOUND := 1
const NONE := 2
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
var from := Vector3i.ZERO   # where the search stands; a dwarf on a job walks on meanwhile

func _init(dwarf: DwarfAgent) -> void:
	agent = dwarf
	owner = agent.get_tree().get_first_node_in_group("surface_details")
	from = agent.current_cell()

func tick(seconds: float) -> void:
	if not is_instance_valid(owner):
		_fail()
		return
	var config: Dictionary = agent.get_food().config
	if state == "searching":
		elapsed += seconds
		if elapsed >= float(config.search_seconds):
			_fail()
			return
		var result := advance_search(Time.get_ticks_usec()+int(config.search_budget_usec))
		if result == PENDING: return
		if result == NONE:
			_fail()
			return
		if not owner.claim_forage(id,agent.dwarf_id):
			_next()
			return
		state = "walking"
		travel_left = agent.get_food().start_walk(route.path)
		agent.get_food().message = "No reachable harvested food. Picking nearby wild berries."
	elif not owner.forage_available(id,agent.dwarf_id):
		_fail()
	elif state == "walking":
		travel_left -= seconds
		if travel_left <= 0 or agent._move_path.is_empty(): _fail()
		else: agent._follow_path(seconds)
	elif state == "picking":
		var left: float = owner.advance_forage(id,agent.dwarf_id,agent.current_cell(),seconds*agent.get_food().work_multiplier())
		if left < 0:
			_fail()
			return
		var contact: Vector3 = owner._gather_contact(agent.global_position,id)
		var direction := contact-agent.global_position
		agent.rotation.y = atan2(direction.x,direction.z)
		agent._carry_pose.gather_loop(left,agent.to_local(contact))
		if left == 0.0:
			var portion: Node3D = owner.take_forage_portion(id,agent.dwarf_id,agent.current_cell())
			if portion == null: _fail()
			else: agent.get_food().receive_portion(portion)

## A slice of the search. FOUND leaves the bush in `id` and its route in `route`, nothing claimed yet.
func advance_search(deadline: int) -> int:
	if not is_instance_valid(owner): return NONE
	var config: Dictionary = agent.get_food().config
	if not bool(query.get("done",false)):
		if not owner.advance_forage_candidates(from,int(config.forage_distance),query,deadline): return PENDING
		query.done = true
		candidates = query.candidates
	if id.is_empty():
		if candidates.is_empty(): return NONE
		var candidate: Dictionary = candidates.pop_front()
		id = candidate.id
		destination = candidate.cell
	if not owner.forage_available(id):
		_next()
		return PENDING
	var goals := {}
	for cell: Vector3i in owner.forage_stands(id,from): goals[cell] = true
	if goals.is_empty():
		_next()
		return PENDING
	var result := Route.advance(route,from,goals.keys()[0],int(config.search_nodes),deadline,false,goals)
	if result == NavGrid.ProbeResult.SEARCHING: return PENDING
	if result != NavGrid.ProbeResult.REACHABLE or path_length(from,route.get("path",[])) > float(config.forage_distance):
		_next()
		return PENDING
	return FOUND

## The dwarf left its job for the berries the search found: the route starts from here instead.
func set_out() -> void:
	from = agent.current_cell()
	route = {}

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
	agent.get_food().shortage = true
	agent.get_food().cancel("No reachable food or nearby ripe berries; will try again.")

static func path_length(from: Vector3i, path: Array) -> float:
	var length := 0.0
	var previous := from
	for cell: Vector3i in path:
		length += Vector3(cell-previous).length()
		previous = cell
	return length
