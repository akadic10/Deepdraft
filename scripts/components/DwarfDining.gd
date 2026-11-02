extends RefCounted

## Finite, resumable dining search. Logical feet stay on proven access ground;
## only the visual body moves into a chair, just like ordinary leisure seating.
## Given a burning campfire (grilling, doc 290), it looks only at that fire: a stool facing it,
## else a place at its side, claimed as a table's place is. Its outcome is then "fire".
const Seating = preload("FurnitureSeating.gd")
const Privacy = preload("DwarfPrivacy.gd")
const Route = preload("WorkRouteProbe.gd")
const Travel = preload("DwarfForaging.gd")
var agent: DwarfAgent
var furniture: Node
var pieces: Array = []
var tables: Array = []
var candidates: Array[Dictionary] = []
var choice := {}
var route := {}
var goal := Vector3i(-1,-1,-1)
var state := "searching"
var elapsed := 0.0
var travel_left := 0.0
var revision := -1
var radius := 16.0
var focus_radius := 6.0
var fire: InstalledFurnitureComponent

func _init(dwarf: DwarfAgent, grill_fire: InstalledFurnitureComponent = null) -> void:
	agent = dwarf
	fire = grill_fire
	# Dining starts only after collecting a real portion. Hunger must not hide
	# nearby seats now that food is secured; search and travel remain bounded.
	radius = float(agent._food.config.dining_distance)
	focus_radius = float(TaskManager.get_config_section("idle").get("seat_focus_radius",6))
	furniture = agent.get_tree().get_first_node_in_group("furniture_controller")
	if furniture == null: return
	var here := agent.current_cell()
	for piece: InstalledFurnitureComponent in furniture.get_installed_pieces():
		if not _installed(piece) or Vector3(piece.origin_cell-here).length() > radius+4: continue
		if not Privacy.allowed(piece.origin_cell,agent.dwarf_id): continue
		if fire != null:
			var near_fire := piece.node.global_position.distance_to(fire.node.global_position) <= focus_radius
			if piece == fire or (near_fire and Seating.is_chair(piece.def) and not furniture.get_seating().is_recreation_seat(piece)): pieces.append(piece)
			continue
		if piece.def.has("seating") and not piece.def.has("recreation"): tables.append(piece)
		if Seating.is_chair(piece.def) and not furniture.get_seating().is_recreation_seat(piece): pieces.append(piece)
	# Each seat takes a frame to check, so check the nearest first: the nearest seat at
	# a table is found early. Tables alone are considered after all seat arrangements.
	pieces.sort_custom(func(a,b): return (a.origin_cell-here).length_squared() < (b.origin_cell-here).length_squared())
	pieces.append_array(tables)

func tick(seconds: float) -> bool:
	if state == "ready": return true
	elapsed += seconds
	if state == "walking":
		travel_left -= seconds
		if not valid() or travel_left <= 0 or agent._move_path.is_empty():
			fallback()
			return true
		agent._follow_path(seconds)
		return state == "ready"
	if elapsed > float(agent._food.config.dining_search_seconds):
		fallback()
		return true
	# A seat at a table is the best there is, so route one as soon as it is found;
	# anything less waits until every piece has been checked.
	if choice.is_empty() and not pieces.is_empty() and not candidates.any(func(candidate): return candidate.rank == 0):
		_add_candidate(pieces.pop_front())
		return false
	if choice.is_empty():
		if candidates.is_empty():
			fallback()
			return true
		candidates.sort_custom(func(a,b): return a.rank < b.rank if a.rank != b.rank else a.distance < b.distance)
		choice = candidates.pop_front()
		if not _available(choice):
			choice = {}
			return false
	var goals: Dictionary = choice.goals
	var result := Route.advance(route,agent.current_cell(),goals.keys()[0],int(agent._food.config.search_nodes),
		Time.get_ticks_usec()+int(agent._food.config.search_budget_usec),false,goals)
	if result == NavGrid.ProbeResult.SEARCHING: return false
	if result != NavGrid.ProbeResult.REACHABLE or Travel.path_length(agent.current_cell(),route.get("path",[])) > radius or not _private_route():
		choice = {}; route = {}
		return false
	goal = route.path.back() if not route.path.is_empty() else agent.current_cell()
	if not _available(choice) or (choice.get("table") != null and choice.table.dining_claims.has(goal)):
		choice = {}; route = {}
		return false
	if choice.get("seat") != null:
		choice.seat.idle_seat_owner = agent.dwarf_id
		choice.seat.idle_seat_yaw_steps = choice.yaw
	if choice.get("table") != null: choice.table.dining_claims[goal] = agent.dwarf_id
	state = "walking"
	travel_left = agent._food.start_walk(route.path)
	if agent.current_cell() == goal: walk_finished(true)
	return state == "ready"

func _installed(piece) -> bool:
	return piece != null and is_instance_valid(furniture) and is_instance_valid(piece.node) \
		and furniture.get_installed(piece.installed_id) == piece and not piece.flagged_uninstall

func _available(candidate: Dictionary) -> bool:
	var seat = candidate.get("seat")
	var table = candidate.get("table")
	return (seat == null or (_installed(seat) and seat.idle_seat_owner < 0)) and (table == null or _installed(table))

func _add_candidate(piece: InstalledFurnitureComponent) -> void:
	if not _installed(piece): return
	if Seating.is_chair(piece.def):
		if piece.idle_seat_owner >= 0 or not piece.def.seating_chair.has("rest_pose"): return
		var seating = furniture.get_seating()
		for candidate in tables:
			if not _installed(candidate) or candidate.origin_cell.y != piece.origin_cell.y: continue
			var matched: int = seating.table_yaw(piece,candidate)
			if matched >= 0 and seating.placement_reason(piece.def,piece.origin_cell,matched,piece).is_empty():
				_add(piece,candidate,Seating.access_cells(piece.def,piece.origin_cell,matched),matched,0)
				break
		# The seat alone faces as idle sitting would (a stool turns to a burning fire).
		# A blocked table arrangement must not hide this fallback.
		var facing: Dictionary = seating.facing(piece,focus_radius,false)
		if facing.is_empty() or (fire != null and int(facing.get("fire_id",-1)) != fire.installed_id): return
		var yaw := int(facing.yaw)
		_add(piece,null,Seating.access_cells(piece.def,piece.origin_cell,yaw),yaw,1,int(facing.get("fire_id",-1)))
	else:
		var stands: Array[Vector3i] = []
		for cell in piece.cells:
			for offset: Vector3i in [Vector3i.LEFT,Vector3i.RIGHT,Vector3i.FORWARD,Vector3i.BACK]:
				if cell+offset not in piece.cells and cell+offset not in stands: stands.append(cell+offset)
		_add(null,piece,stands,0,2)

func _add(seat, table, stands: Array[Vector3i], yaw: int, rank: int, fire_id := -1) -> void:
	var goals := {}
	var distance := INF
	for cell in stands:
		if not NavGrid.is_walkable(cell) or not Privacy.allowed(cell,agent.dwarf_id): continue
		if table != null and table.dining_claims.has(cell): continue
		var cost := Vector3(cell-agent.current_cell()).length()
		if cost > radius: continue
		goals[cell] = true
		distance = minf(distance,cost)
	if not goals.is_empty(): candidates.append({"seat":seat,"table":table,"yaw":yaw,"fire_id":fire_id,"rank":rank,"goals":goals,"distance":distance})

func _private_route() -> bool:
	var previous := agent.current_cell()
	for cell: Vector3i in route.get("path",[]):
		if not Privacy.segment(previous,cell,agent.dwarf_id): return false
		previous = cell
	return true

func valid() -> bool:
	if choice.is_empty(): return true
	if not NavGrid.is_walkable(goal) or not Privacy.allowed(goal,agent.dwarf_id): return false
	var seat = choice.get("seat")
	if seat != null:
		if not _installed(seat) or seat.idle_seat_owner != agent.dwarf_id: return false
		for cell: Vector3i in seat.cells:
			if not BlockRegistry.is_solid(WorldData.get_live_block(cell.x,cell.y,cell.z)): return false
		if revision != NavGrid.navigation_revision:
			if not furniture.get_seating().placement_reason(seat.def,seat.origin_cell,choice.yaw,seat).is_empty(): return false
			revision = NavGrid.navigation_revision
	var table = choice.get("table")
	if table != null and (not _installed(table) or int(table.dining_claims.get(goal,-1)) != agent.dwarf_id):
		if int(table.dining_claims.get(goal,-1)) == agent.dwarf_id: table.dining_claims.erase(goal)
		choice.table = null
		if seat == null: return false
	return true

func walk_finished(success: bool) -> void:
	if success and agent.current_cell() == goal and valid():
		state = "ready"
		if choice.get("seat") != null: agent.rotation.y = float(choice.yaw)*PI*.5
		elif choice.get("table") != null:
			var offset: Vector3 = choice.table.node.global_position-agent.global_position
			agent.rotation.y = atan2(offset.x,offset.z)
		agent._reset_part_offsets()
	else: fallback()

func pose(seconds: float) -> Vector3:
	if not valid(): fallback()
	var seat = choice.get("seat")
	if seat == null: return Vector3.ZERO
	var blend := smoothstep(0.0,.5,seconds)
	var base := agent.to_local(seat.node.global_position)
	var settings: Dictionary = furniture.get_seating().chair_settings(seat)
	var pose_data: Dictionary = settings.rest_pose
	for pair in [[agent._body,"body"],[agent._head,"head"],[agent._foot_l,"left_foot"],[agent._foot_r,"right_foot"]]:
		var values: Array = pose_data.get(pair[1],pose_data.body)
		if is_instance_valid(pair[0]): pair[0].position = (base+Vector3(values[0],values[1],values[2]))*blend
	var body: Array = pose_data.body
	# The meal's detached hands follow the surface without lifting the seated torso.
	return (base+Vector3(body[0],body[1]+float(settings.get("meal_hand_lift",0)),body[2]))*blend

func outcome() -> String:
	if not valid(): fallback()
	if fire != null and not choice.is_empty(): return "fire"
	if choice.get("seat") != null: return "proper" if choice.get("table") != null else "seat_only"
	return "table_only" if choice.get("table") != null else "neither"

## Grilling: the meal has its place at the fire, on a stool facing it or at its side.
func at_fire() -> bool:
	return fire != null and state == "ready" and not choice.is_empty() and valid()

## The meal's seat and table, those it had: what the dwarf used (doc 41 "Tastes").
func used_pieces() -> Array:
	# The campfire a fish was grilled at holds the place of a table, but it is no table.
	var table: Variant = choice.get("table") if fire == null else null
	return [choice.get("seat"), table].filter(func(piece: Variant) -> bool: return piece != null)

## A completed meal can become ordinary idle rest in the same chair. Transfer
## the exclusive claim before cleanup; the table claim still belongs to dining.
func continue_seated() -> bool:
	if state != "ready" or not valid() or choice.get("seat") == null or agent._idle_behavior == null: return false
	agent._idle_behavior.continue_seated(choice.seat,furniture,goal,int(choice.get("fire_id",-1)))
	choice.erase("seat")
	return true

func release() -> void:
	var seat = choice.get("seat")
	if seat != null and seat.idle_seat_owner == agent.dwarf_id:
		seat.idle_seat_owner = -1
		seat.idle_seat_yaw_steps = -1
	var table = choice.get("table")
	if table != null and int(table.dining_claims.get(goal,-1)) == agent.dwarf_id: table.dining_claims.erase(goal)
	choice = {}

func fallback() -> void:
	release()
	state = "ready"
	agent.stop_walking()
	agent._reset_part_offsets()
