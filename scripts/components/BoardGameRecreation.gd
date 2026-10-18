extends RefCounted

## Scene-owned matchmaking: one candidate and one bounded route slice per frame.
## Games/seat claims are transient; only earned memories and retry timers save.
const Seating = preload("FurnitureSeating.gd")
const Privacy = preload("DwarfPrivacy.gd")
const Route = preload("WorkRouteProbe.gd")
const Travel = preload("DwarfForaging.gd")
var furniture: Node
var config: Dictionary
var games: Dictionary = {}
var tables: Array = []
var candidates: Array = []
var choice := {}
var route := {}
var delay := 0.0
var search_elapsed := 0.0

func _init(controller: Node) -> void:
	furniture = controller
	config = TaskManager.get_config_section("recreation")

func eligible(agent) -> bool:
	if not is_instance_valid(agent) or not agent.is_inside_tree() or agent.is_queued_for_deletion(): return false
	if agent.is_recreating() or agent.is_sleeping() or agent.is_eating() or agent.promotion_pending(): return false
	if agent.sleep <= DwarfAgent.SLEEP_THRESHOLD or agent._food.hungry(): return false
	# The happiness thought lasts longer than the cooldown. Remembering a game
	# must not prevent an otherwise available dwarf from joining another player.
	if agent._mood.recreation_retry_hours > 0: return false
	if not agent._carried_entries.is_empty() or agent.needs_bridge_exit() or agent.needs_ladder_exit(): return false
	if not NavGrid.is_walkable(agent.current_cell()): return false
	if agent.current_task_id >= 0: return agent._mood.value() < float(agent._mood.config.baseline)
	# Explicit player movement keeps priority over autonomous recreation.
	return not agent.is_walking() or agent._idle_behavior.owns_walk()

func installed(piece) -> bool:
	return piece != null and is_instance_valid(piece.node) and not piece.flagged_uninstall \
		and furniture._installed.get(piece.installed_id) == piece

func seats(table) -> Array:
	if not installed(table): return []
	var slots: Array = furniture.get_dining_seats(table.installed_id)
	if slots.size() != 2: return []
	var result: Array = []
	for slot: Dictionary in slots:
		var seat = furniture._installed.get(slot.chair_id)
		if not installed(seat): return []
		result.append(seat)
	return result

func tick(seconds: float) -> void:
	if WorldClock.paused or WorldClock.speed <= 0 or SaveManager.is_loading(): return
	for game in games.values(): game.tick(seconds)
	delay -= seconds
	if delay > 0: return
	if choice.is_empty():
		if candidates.is_empty():
			if tables.is_empty():
				for piece in furniture._installed.values():
					if piece.def.get("recreation","") == "board_game": tables.append(piece)
				delay = 1.0
				return
			var table = tables.pop_front()
			var chairs := seats(table)
			if chairs.size() != 2: return
			for chair in chairs:
				if chair.idle_seat_owner >= 0: continue
				for agent in TaskManager._agents.values():
					if eligible(agent) and Vector3(agent.current_cell()-chair.origin_cell).length() <= float(config.search_radius):
						candidates.append({"table":table,"seat":chair,"agent":agent})
			return
		choice = candidates.pop_front()
		route = {}
		search_elapsed = 0.0
	var table = choice.table
	var seat = choice.seat
	var agent = choice.agent
	if not eligible(agent) or seats(table).size() != 2 or not installed(seat) or seat.idle_seat_owner >= 0:
		choice = {}; return
	if not furniture._seating.placement_reason(seat.def,seat.origin_cell,seat.yaw_steps,seat).is_empty():
		choice = {}; return
	var goals := {}
	for cell: Vector3i in Seating.access_cells(seat.def,seat.origin_cell,seat.yaw_steps):
		if NavGrid.is_walkable(cell) and Privacy.allowed(cell,agent.dwarf_id): goals[cell] = true
	if goals.is_empty() or not Privacy.allowed(seat.origin_cell,agent.dwarf_id):
		choice = {}; return
	search_elapsed += seconds
	if search_elapsed > float(config.search_seconds): choice = {}; return
	var result := Route.advance(route,agent.current_cell(),goals.keys()[0],int(config.search_nodes),
		Time.get_ticks_usec()+int(config.search_budget_usec),false,goals)
	if result == NavGrid.ProbeResult.SEARCHING: return
	if result == NavGrid.ProbeResult.REACHABLE and Travel.path_length(agent.current_cell(),route.path) <= float(config.search_radius):
		var previous: Vector3i = agent.current_cell()
		var private_route := true
		for cell: Vector3i in route.path:
			if not Privacy.segment(previous,cell,agent.dwarf_id): private_route = false; break
			previous = cell
		if private_route:
			var game = games.get(table.installed_id)
			if game == null:
				game = Game.new(self,table)
				games[table.installed_id] = game
			game.join(agent,seat,route.path)
	choice = {}

class Game extends RefCounted:
	var controller: Node
	var config: Dictionary
	var table: InstalledFurnitureComponent
	var players: Array[Dictionary] = []
	var elapsed := 0.0
	var playing := false
	var ended := false
	var revision := -1

	func _init(owner, piece) -> void:
		controller = owner.furniture
		config = owner.config
		table = piece

	func join(agent: DwarfAgent, seat: InstalledFurnitureComponent, path: Array) -> void:
		if ended or players.size() >= 2: return
		var had_task := agent.current_task_id >= 0
		agent.abort_task()
		if had_task: agent._work_execution.release(agent.dwarf_id,Task.ReleaseReason.NEED_INTERRUPT,false)
		var goal: Vector3i = path.back() if not path.is_empty() else agent.current_cell()
		seat.idle_seat_owner = agent.dwarf_id
		seat.idle_seat_yaw_steps = seat.yaw_steps
		agent._recreation = self
		players.append({"agent":agent,"seat":seat,"goal":goal,"arrived":false,"blend":0.0})
		TaskManager.notify_dwarf_unavailable(agent.dwarf_id)
		agent._food.start_walk(path)
		if agent.current_cell() == goal: walk_finished(agent,true)

	func valid() -> bool:
		if ended or not is_instance_valid(controller): return false
		var manager = controller._games
		if manager.seats(table).size() != 2: return false
		for cell: Vector3i in table.cells:
			if not BlockRegistry.is_solid(NavGrid._block_id(cell.x,cell.y,cell.z)): return false
		for player in players:
			var agent = player.agent
			var seat = player.seat
			if not is_instance_valid(agent) or agent.is_queued_for_deletion() or agent._recreation != self: return false
			if agent.is_sleeping() or agent.is_eating() or agent.promotion_pending() or agent._food.hungry() or agent.sleep <= DwarfAgent.SLEEP_THRESHOLD: return false
			if not manager.installed(seat) or seat.idle_seat_owner != agent.dwarf_id: return false
			if not NavGrid.is_walkable(player.goal) or not Privacy.allowed(seat.origin_cell,agent.dwarf_id): return false
			for cell: Vector3i in seat.cells:
				if not BlockRegistry.is_solid(NavGrid._block_id(cell.x,cell.y,cell.z)): return false
			if revision != NavGrid.navigation_revision and not controller._seating.placement_reason(seat.def,seat.origin_cell,seat.yaw_steps,seat).is_empty(): return false
		revision = NavGrid.navigation_revision
		return true

	func tick(seconds: float) -> void:
		if not valid(): cancel(); return
		if not playing and players.size() == 2 and players.all(func(p): return p.arrived and p.blend >= 1.0):
			playing = true
			elapsed = 0.0
		elapsed += seconds
		if playing and elapsed >= float(config.play_seconds): cancel(-1,true)
		elif not playing and elapsed >= float(config.wait_seconds): cancel()

	func tick_actor(agent: DwarfAgent, seconds: float) -> void:
		if not valid(): cancel(); return
		for player in players:
			if player.agent != agent: continue
			if not player.arrived:
				if agent.is_walking(): agent._follow_path(seconds)
				else: walk_finished(agent,agent.current_cell() == player.goal)
				return
			player.blend = minf(1.0,float(player.blend)+seconds/.6)
			_pose(player)

	func walk_finished(agent: DwarfAgent, success: bool) -> void:
		if ended: return
		for player in players:
			if player.agent != agent: continue
			if not success or agent.current_cell() != player.goal: cancel(); return
			player.arrived = true
			agent.rotation.y = player.seat.yaw_steps*PI*.5
			agent._reset_part_offsets()

	func _pose(player: Dictionary) -> void:
		var agent: DwarfAgent = player.agent
		var seat: InstalledFurnitureComponent = player.seat
		var base := agent.to_local(seat.node.global_position)
		var pose: Dictionary = seat.def.seating_chair.rest_pose
		var blend := smoothstep(0,1,player.blend)
		for pair in [[agent._body,"body"],[agent._head,"body"],[agent._hand_l,"left_hand"],[agent._hand_r,"right_hand"],[agent._foot_l,"left_foot"],[agent._foot_r,"right_foot"]]:
			var values: Array = pose[pair[1]]
			if is_instance_valid(pair[0]): pair[0].position = (base+Vector3(values[0],values[1],values[2]))*blend
		if playing:
			# Alternating detached-hand reaches; no arm/leg geometry or inventory pieces.
			var turn := int(elapsed/2.0)%2 == players.find(player)
			var reach := sin(fmod(elapsed,2.0)*PI/2.0) if turn else 0.0
			# Target the log's surface from either seat and in every rotation.
			# The mirrored palm uses the shared dwarf authoring anchor.
			var palm := Vector3(-1.0625,1.25,.1875)
			var target := agent.to_local(table.node.global_position) + Vector3(-.5,float(table.def.game_surface_height)+.28,-.5)
			agent._hand_r.position = agent._hand_r.position.lerp((target-palm)*blend,reach)
			agent._hand_r.position.y += sin(reach*PI)*.08*blend
			agent._head.rotation.x = .06+reach*.035

	func describe(agent: DwarfAgent) -> Dictionary:
		for player in players:
			if player.agent == agent:
				return {"activity":"Playing a board game" if playing else "Waiting for a game partner" if player.arrived else "Going to play",
					"explanation":"A short game together restores happiness. Food and sleep take priority.","destination":player.goal}
		return {}

	func cancel(excluded_dwarf_id := -1, completed := false) -> void:
		if ended: return
		ended = true # Clear ownership before stop_walking emits synchronous callbacks.
		if is_instance_valid(controller): controller._games.games.erase(table.installed_id)
		for player in players:
			var agent = player.agent
			var seat = player.seat
			if not is_instance_valid(agent): continue
			if seat.idle_seat_owner == agent.dwarf_id:
				seat.idle_seat_owner = -1
				seat.idle_seat_yaw_steps = -1
			agent._recreation = null
			agent._mood.recreation_retry_hours = float(config.cooldown_hours if completed else config.retry_hours)
			if completed: agent._mood.record_recreation()
			agent.stop_walking()
			agent._reset_part_offsets()
			if agent.dwarf_id != excluded_dwarf_id: TaskManager.notify_dwarf_idle(agent.dwarf_id)
		players.clear()
