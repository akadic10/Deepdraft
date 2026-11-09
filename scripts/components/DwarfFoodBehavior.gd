extends RefCounted

## Personal self-care. Storage/drop owners retain inventory authority; hunger
## commits only when the dwarf consumes an actual carried portion.
## Grilling (doc 290): while a campfire burns within reach, a hungry dwarf looks for a fresh
## fish first, takes it to a place at the fire, grills it on a stick and eats it there. The
## meal fills as the raw fish would, adds a little Rest and leaves a good memory. With no fish,
## no fire or no room at it, the meal is an ordinary one.
const Route = preload("res://scripts/components/WorkRouteProbe.gd")
const Fires = preload("res://scripts/components/FurnitureFires.gd")
const Foraging = preload("DwarfForaging.gd")
enum Search { PENDING, FOUND, NONE }
var agent: DwarfAgent
var config: Dictionary
var value := 1.0
var last_meal := ""
var hours_since_meal := 0.0
var retry_hours := 0.0
var state := ""
var message := ""
var portion: Node3D
var _items: ItemDropManager
var _keys: Array[String] = []
var _query := {}
var _quote := {}
var _route := {}
var _excluded := {}
var _token := {}
var _source: StorageComponent
var _loose := false
var _elapsed := 0.0
var _search_elapsed := 0.0
var _search_from := Vector3i.ZERO          # where the search stands; a dwarf on a job walks on meanwhile
var _scouting := false                     # searching while still on the job
var _travel_left := 0.0
var shortage := false
var last_dining := ""
var _foraging: RefCounted
var _dining: RefCounted
var _serving: Node3D
var _reach := Vector3(0,1.1,.85)           # where the hands go for the food, in the dwarf's own space
var _grill_frame := ""
var grilled := false                       # this meal's fish is grilled at `_grill_fire`
var _grill_fire: InstalledFurnitureComponent
var _grill_search := false                 # the search is for fish to grill
const BITE_PITCH := .2
const CHEW_PITCH := .05
const CHEW_RISE := .025
var _head_nudge := Vector3.ZERO
var _at_fire_seconds := 0.0                # grilling and eating there, for the seat's blend

func _init(owner: DwarfAgent) -> void:
	agent = owner
	config = TaskManager.get_config_section("food")
	value = 1.0-fposmod(float(agent.dwarf_id)*0.137, float(config.initial_spread))

func active() -> bool:
	return not state.is_empty()

func hungry() -> bool:
	return value <= float(config.hungry_threshold)

func famished() -> bool:
	return value <= float(config.famished_threshold)

func work_multiplier() -> float:
	return float(config.famished_work_multiplier if famished() else config.hungry_work_multiplier if hungry() else 1.0)

func mood_penalty() -> float:
	return float(config.famished_mood_penalty if famished() else config.hungry_mood_penalty if hungry() else 0.0)

func clock_tick(hours: float) -> void:
	value = maxf(0.0, value-hours*float(config.drain_per_hour))
	retry_hours = maxf(0.0, retry_hours-hours)
	if not hungry(): shortage = false
	if not last_meal.is_empty(): hours_since_meal += hours

## True once the dwarf has left what it was doing for its meal. A dwarf on a job searches first and
## keeps working meanwhile, so hunger only costs it the job, and any cargo, when there is food to go to.
func begin_if_needed() -> bool:
	if not hungry() or agent.is_sleeping() or agent.promotion_pending():
		_scouting = false
		return false
	if active() or retry_hours > 0.0 or not NavGrid.is_walkable(agent.current_cell()): return false
	if not _scouting and not _open_search(): return false
	if agent.current_task_id >= 0 and not _scout(): return false
	_leave_work()
	return true

func _open_search() -> bool:
	_items = ItemDropManager.find(agent.get_tree())
	if _items == null: return false
	_keys = _items.edible_keys()
	_grill_fire = _grill_fire_near()
	var grill_keys: Array[String] = []
	if _grill_fire != null: grill_keys = _items.grill_keys()
	_grill_search = not grill_keys.is_empty()
	if _grill_search: _keys = grill_keys
	_query = {}; _quote = {}; _route = {}; _excluded = {}
	_loose = false
	_foraging = null
	_search_from = agent.current_cell()
	_scouting = true
	return true

## One slice of the search on the job. True when there is food, or ripe berries for a famished dwarf.
func _scout() -> bool:
	var deadline := Time.get_ticks_usec()+int(config.search_budget_usec)
	if _foraging != null:
		var forage: int = _foraging.advance_search(deadline)
		if forage == Foraging.NONE: _scout_failed("No reachable food or nearby ripe berries; will try again.")
		return forage == Foraging.FOUND
	var result := _advance_search(deadline)
	if result == Search.NONE:
		shortage = true
		if famished(): _foraging = Foraging.new(agent)
		else: _scout_failed("No reachable food; will try again.")
	return result == Search.FOUND

func _scout_failed(reason: String) -> void:
	_scouting = false
	_foraging = null
	_grill_fire = null
	_grill_search = false
	_query = {}; _quote = {}; _route = {}; _excluded = {}
	message = reason
	retry_hours = float(config.retry_hours)

## What the search found stays, but its route is walked from here, so it is searched again from here.
func _leave_work() -> void:
	# Clear work and callbacks before claiming self-care ownership.
	var had_task := agent.current_task_id >= 0
	agent.abort_task()
	if had_task: agent._work_execution.release(agent.dwarf_id, Task.ReleaseReason.NEED_INTERRUPT, false)
	_scouting = false
	_route = {}
	_search_from = agent.current_cell()
	_search_elapsed = 0.0
	if _foraging != null:
		_foraging.set_out()
		state = "foraging"
		message = "No reachable harvested food. Looking for nearby ripe berries."
	else:
		state = "finding"
		message = "Looking for reachable food in storage."
	TaskManager.notify_dwarf_unavailable(agent.dwarf_id)

func tick(seconds: float) -> void:
	if state == "foraging":
		_foraging.tick(seconds)
		return
	if state == "dining":
		if not is_instance_valid(portion):
			cancel()
			return
		if _dining.tick(seconds):
			if grilled and not _dining.at_fire():
				_serve_plain()   # no room at the fire: an ordinary meal
				return
			state = "grilling" if grilled else "eating"
			_elapsed = 0.0
			_at_fire_seconds = 0.0
			var food_name := String(_items.get_item_def(_quote.key).display_name)
			message = "Grilling a %s by the campfire." % food_name.to_lower() if grilled else "Eating %s." % food_name
		_pose(0.0)
		return
	if state == "grilling":
		if not _holding_portion() or not _dining.valid():
			cancel("Meal interrupted; will try again.")
			return
		_elapsed += seconds
		_at_fire_seconds += seconds
		_pose(_elapsed)
		if _elapsed >= float(config.grilling.grill_seconds):
			state = "eating"
			_elapsed = 0.0
			message = "Eating a grilled %s by the fire." % String(_items.get_item_def(_quote.key).display_name).to_lower()
		return
	if state == "finding":
		_search_elapsed += seconds
		if _search_elapsed >= float(config.search_seconds):
			cancel("Food search paused; will try again.")
		else: _find_food()
		return
	if state == "walking" or state == "pickup":
		if not _supply_available():
			cancel("Food became unavailable; will try again.")
			return
	if state == "walking":
		_travel_left -= seconds
		if _travel_left <= 0.0 or agent._move_path.is_empty():
			cancel("The route to food changed; will try again.")
			return
		agent._follow_path(seconds)
	elif state == "pickup":
		if agent.current_cell() not in _stands():
			cancel("Food is no longer within reach.")
			return
		_elapsed += seconds
		agent._carry_pose.gather(clampf(_elapsed/float(config.pickup_seconds),0.0,1.0), _reach)
		if _elapsed >= float(config.pickup_seconds): _take()
	elif state == "eating":
		if not _holding_portion():
			cancel("Meal interrupted; will try again.")
			return
		_elapsed += seconds
		_at_fire_seconds += seconds
		_pose(_elapsed)
		if _elapsed >= float(config.eat_seconds): _finish_meal()

func _find_food() -> void:
	var result := _advance_search(Time.get_ticks_usec()+int(config.search_budget_usec))
	if result == Search.PENDING: return
	if result == Search.NONE:
		shortage = true
		if famished():
			state = "foraging"
			_foraging = Foraging.new(agent)
			message = "No reachable harvested food. Looking for nearby ripe berries."
		else: cancel("No reachable food; will try again.")
		return
	if _quote.has("source"):
		_source = _quote.source
		_token = _source.reserve_portion(_quote.slot,String(_quote.key),agent.dwarf_id)
		if _token.is_empty():
			_exclude_quote()
			return
	elif not is_instance_valid(_quote.get("node")) or not _items.reserve(_quote.node,agent.dwarf_id):
		_exclude_quote()
		return
	state = "walking"
	message = "Collecting one portion of %s." % _items.get_item_def(_quote.key).display_name
	_travel_left = start_walk(_route.path)

## Storage first, then loose food, each to a real route from `_search_from`. FOUND leaves the proven
## food in `_quote` and its route in `_route`, nothing claimed yet.
func _advance_search(deadline: int) -> Search:
	if _quote.is_empty():
		var done: bool
		# Older food first: a fully spoilt stack counts route_margin_blocks nearer (doc 41).
		var margin := float(config.spoilage.route_margin_blocks)
		if _loose:
			done = _items.advance_material_quote(_keys,_search_from,_query,deadline,_excluded,-1,"","",false,margin)
		else:
			done = StockpileManager.advance_material_quote(_keys,_search_from,_query,deadline,_excluded,-1,"","",margin)
		if not done: return Search.PENDING
		_quote = _query.best
		if _quote.is_empty():
			if not _loose:
				_loose = true
				_query = {}; _excluded = {}
				message = "Looking for reachable harvested food."
			elif _grill_search:
				# No fresh fish within reach to grill: any food, eaten as usual.
				_grill_search = false
				_grill_fire = null
				_keys = _items.edible_keys()
				_loose = false
				_query = {}; _excluded = {}
				message = "Looking for reachable food in storage."
			else: return Search.NONE
			return Search.PENDING
	var goals := {}
	for cell: Vector3i in _stands():
		if NavGrid.is_walkable(cell): goals[cell] = true
	var result := NavGrid.ProbeResult.UNREACHABLE
	if not goals.is_empty():
		result = Route.advance(_route,_search_from,goals.keys()[0],int(config.search_nodes),deadline,false,goals) as NavGrid.ProbeResult
	if result == NavGrid.ProbeResult.SEARCHING: return Search.PENDING
	if result != NavGrid.ProbeResult.REACHABLE:
		_exclude_quote()
		return Search.PENDING
	return Search.FOUND

func start_walk(path: Array, private_walk := false) -> float:
	agent.start_route(path, private_walk)
	return maxf(10.0,Foraging.path_length(agent.current_cell(),path)/maxf(.1,agent.walk_speed)*3.0)

func _stands() -> Array[Vector3i]:
	if _quote.has("source"):
		var source: StorageComponent = _quote.source
		if not StockpileManager.is_registered(source): return []
		return source.withdrawal_stands(_quote.slot)
	return StorageComponent.ground_access_cells(_quote.cell) if not _quote.is_empty() else []

func _supply_available() -> bool:
	if not is_instance_valid(_items): return false
	if _quote.has("source"): return _source.portion_available(_token,agent.dwarf_id)
	var node: Node3D = _quote.get("node")
	return is_instance_valid(node) and _items.reserved_by(node,agent.dwarf_id) \
		and _items.item_floor_cell(node) == _quote.cell and _items.item_key_of(node) == _quote.key

func _exclude_quote() -> void:
	_excluded[_quote.cell] = true
	_query = {}; _quote = {}; _route = {}
	_source = null

func walk_finished(success: bool) -> void:
	if state == "foraging":
		_foraging.walk_finished(success)
		return
	if state == "dining":
		_dining.walk_finished(success)
		return
	if state != "walking": return
	if not success or agent.current_cell() not in _stands():
		cancel("The route to food changed; will try again.")
		return
	state = "pickup"
	_elapsed = 0.0
	var target: Vector3 = _source.withdrawal_contact(_quote.slot) if _source != null else Vector3(_quote.cell)+Vector3(.5,1,.5)
	var offset := target-agent.global_position
	if Vector2(offset.x,offset.z).length_squared() > .001: agent.rotation.y = atan2(offset.x,offset.z)
	# Toward the food, which the dwarf now faces, and never into its own chest (doc 298). As high
	# as a food shelf's upper deck (doc 299).
	_reach = Vector3(0,clampf(offset.y,.2,2.0),maxf(Vector2(offset.x,offset.z).length(),.85))
	agent._reset_part_offsets()

func _take() -> void:
	var picked := _source.take_portion(_token,agent.dwarf_id,agent.current_cell()) if _source != null else _items.take_quantity(_quote.node,1,agent.dwarf_id)
	if not is_instance_valid(picked):
		cancel("Food could not be collected; will try again.")
		return
	receive_portion(picked)

func receive_portion(picked: Node3D) -> void:
	release_reservation()
	portion = picked
	_quote = {"key":_items.item_key_of(portion),"cell":agent.current_cell()}
	shortage = false
	agent.add_child(portion)
	agent._carried_entries.append([portion,String(_quote.key)])
	# Keep one real inventory portion; its serving or its stick is presentation only.
	portion.hide()
	state = "dining"
	_elapsed = 0.0
	var grills := bool(_items.food_definition(_quote.key).get("grill", false))
	grilled = grills and _grill_fire != null and is_instance_valid(_grill_fire.node) and Fires.burning(_grill_fire)
	if grilled:
		_dining = preload("DwarfDining.gd").new(agent, _grill_fire)
		message = "Taking the %s to the campfire." % String(_items.get_item_def(_quote.key).display_name).to_lower()
		_pose(0.0)
		return
	_serve_plain()

## An ordinary meal: the portion's serving in hand and a seat or table to find.
func _serve_plain() -> void:
	if grilled: agent.get_grill_pose().reset()
	if _dining != null: _dining.release()
	grilled = false
	_serving = preload("DwarfMealVisual.gd").create(_items.food_definition(_quote.key))
	agent.add_child(_serving)
	_dining = preload("DwarfDining.gd").new(agent)
	state = "dining"
	_elapsed = 0.0
	message = "Finding a nearby place to eat."
	_meal_pose(0.0)

func _holding_portion() -> bool:
	return is_instance_valid(portion) and agent._carried_entries.any(func(entry): return entry[0] == portion)

func _pose(seconds: float) -> void:
	if not grilled:
		_meal_pose(seconds)
		return
	var stick: Dictionary = DwarfAssets.grill_sticks.get(String(_quote.key), {})
	var browned := state == "eating" or (state == "grilling" and seconds >= float(config.grilling.grill_seconds) * float(config.grilling.browned_at))
	var offset: Vector3 = _dining.pose(_at_fire_seconds) if state in ["grilling", "eating"] else Vector3.ZERO
	if state == "eating": offset.y += sin(seconds * 5.0) * 0.03   # small bites
	var frame: String = {"dining": "carry", "grilling": "hold", "eating": "bite"}[state]
	if frame != _grill_frame: agent.blend_pose()
	_grill_frame = frame
	agent.get_grill_pose().apply(frame, stick.get("grilled" if browned else "raw"), offset)
	if state == "eating": _bite_head((1.0+sin(seconds*5.0))*.5, seconds, agent.get_head().rotation)

func _meal_pose(seconds: float) -> void:
	if not is_instance_valid(_serving): return
	var offset: Vector3 = _dining.pose(seconds) if state == "eating" else Vector3.ZERO
	var bite := (1.0-cos(seconds*TAU*.65))*.5 if state == "eating" else 0.0
	var grip := offset+Vector3(-.42,lerpf(1.4,2.2,bite),lerpf(.85,.62,bite))
	agent._carry_pose._pose_hand(agent._hand_r,grip,Quaternion.IDENTITY)
	# The free hand steadies the meal and comes up a little with each bite.
	agent._carry_pose._pose_hand(agent._hand_l,offset+Vector3(.65,1.35+bite*.22,.7-bite*.08),Quaternion.IDENTITY)
	_serving.position = grip+Vector3(0,.14,.08)
	_serving.rotation = Vector3(bite*.3,0,0)
	if state == "eating": _bite_head(bite, seconds, Vector3.ZERO)

## The head dips to meet the food, then chews as the hand comes down (doc 298). It turns about its own
## centre, on top of wherever the seat put it; standing, that is the rest position.
func _bite_head(bite: float, seconds: float, base: Vector3) -> void:
	var head: Node3D = agent.get_head()
	if not is_instance_valid(head): return
	var chew := sin(seconds*TAU*2.2)*(1.0-bite)
	head.rotation = base+Vector3(bite*BITE_PITCH+chew*CHEW_PITCH,0,0)
	var seated: bool = _dining != null and _dining.choice.get("seat") != null
	var rest := head.position if seated else Vector3.ZERO   # the seat writes it afresh each frame
	var pivot := Vector3(0,2.45,0)
	_head_nudge = pivot+Vector3(0,chew*CHEW_RISE,0)-head.basis*pivot
	head.position = rest+_head_nudge


func _finish_meal() -> void:
	var key := _items.item_key_of(portion)
	var food := _items.food_definition(key)
	if food.is_empty() or _items.quantity_of(portion) != 1:
		cancel("This portion is no longer edible.")
		return
	if not agent.detach_placement_cargo(portion):
		cancel("Meal interrupted.")
		return
	value = minf(1.0,value+float(food.nutrition))
	last_meal = key
	last_dining = _dining.outcome()
	agent._mood.record_dining(last_dining)
	if grilled:
		agent.sleep = minf(1.0, agent.sleep + float(config.grilling.rest))
		agent.get_mood().record_grill(_company())
	agent.meet_pieces(_dining.used_pieces())
	agent.get_mood().record_room("ate", RoomManager.appeal_at(agent.current_cell() + Vector3i.UP))
	hours_since_meal = 0.0
	portion.queue_free()
	portion = null
	_items.loose_items_changed.emit()
	_end_meal("",true,false,true)

func cancel(reason := "Meal interrupted; will try again.", resume := true, retry := true) -> void:
	_end_meal(reason,resume,retry)

func _end_meal(reason: String, resume: bool, retry: bool, rest_seated := false) -> void:
	if not active(): return
	state = "" # Stop callbacks before releasing paths or inventory.
	var seated: bool = rest_seated and _dining != null and _dining.continue_seated()
	release_reservation()
	_foraging = null
	_dining = null
	grilled = false
	_grill_fire = null
	_grill_search = false
	if is_instance_valid(_serving): _serving.queue_free()
	_serving = null
	if is_instance_valid(portion): agent._drop_carried_at_feet()
	portion = null
	_query = {}; _quote = {}; _route = {}; _excluded = {}; _token = {}
	_source = null
	agent.stop_walking()
	if not seated: agent._reset_part_offsets()
	elif is_instance_valid(agent.get_head()):
		agent.get_head().rotation = Vector3.ZERO
		agent.get_head().position -= _head_nudge
	_head_nudge = Vector3.ZERO
	message = reason
	retry_hours = float(config.retry_hours) if retry else 0.0
	if resume and not agent.is_sleeping(): TaskManager.notify_dwarf_idle(agent.dwarf_id)

func release_reservation() -> void:
	if _foraging != null: _foraging.release()
	if _dining != null: _dining.release()
	if _source != null and not _token.is_empty(): _source.release_outgoing(_token)
	if is_instance_valid(_quote.get("node")) and is_instance_valid(_items): _items.unreserve(_quote.node,agent.dwarf_id)

func describe() -> Dictionary:
	var label := "Famished" if famished() else "Hungry" if hungry() else "Satisfied"
	if not is_instance_valid(_items) and agent.is_inside_tree():
		_items = ItemDropManager.find(agent.get_tree())
	var meal_name := String(_items.get_item_def(last_meal).get("display_name",last_meal)) if is_instance_valid(_items) else last_meal
	var meal := "No meal yet" if last_meal.is_empty() else "Last meal: %s · %.1f game hours ago" % [meal_name,hours_since_meal]
	if not last_dining.is_empty(): meal += "\n"+String({"proper":"Ate seated at a table","seat_only":"Ate without a table","table_only":"Ate standing at a table","neither":"Ate without a seat or table","fire":"Ate grilled fish by the fire"}.get(last_dining,""))
	var effects := "Work speed −%d%% · Happiness −%d" % [roundi((1.0-work_multiplier())*100),roundi(mood_penalty()*100)] if hungry() else ""
	var destination: Vector3i = _quote.get("cell",Vector3i(-1,-1,-1))
	if state == "foraging": destination = _foraging.destination
	elif state in ["dining","grilling","eating"]:
		destination = _dining.goal if _dining.goal.x >= 0 else agent.current_cell()
	var activity: String = {"finding":"Looking for food","walking":"Collecting food","pickup":"Taking a food portion","eating":"Eating","dining":"Finding a place to eat","grilling":"Grilling a fish by the campfire"}.get(state,"")
	if state == "dining" and grilled: activity = "Taking a fish to the campfire"
	if state == "foraging": activity = {"searching":"Looking for emergency berries","walking":"Going to pick berries","picking":"Picking emergency berries"}.get(_foraging.state,"")
	return {"value":value,"label":label,"meal":meal,"effects":effects,"shortage":shortage and hungry(),
		"rested_by_fire":last_dining == "fire" and hours_since_meal < float(config.grilling.rested_hours),
		"detail":meal+("\n"+effects if not effects.is_empty() else "")+("\n"+message if not message.is_empty() else ""),
		"activity":activity,
		"explanation":message,"destination":destination}

## The nearest burning campfire to grill at (doc 290) within the meal's reach, or null.
func _grill_fire_near() -> InstalledFurnitureComponent:
	var furniture := agent.get_tree().get_first_node_in_group("furniture_controller")
	if furniture == null: return null
	var best: InstalledFurnitureComponent
	var reach := float(config.dining_distance)
	for piece: InstalledFurnitureComponent in furniture.get_installed_pieces():
		if not bool(piece.def.get("grilling", false)) or piece.flagged_uninstall or not is_instance_valid(piece.node) or not Fires.burning(piece): continue
		var gap := Vector3(piece.origin_cell - agent.current_cell()).length()
		if gap <= reach:
			best = piece
			reach = gap
	return best

## Another dwarf grilling at the same fire, or sitting by it: "Grilled fish with company".
func _company() -> bool:
	if _grill_fire == null: return false
	for other: DwarfAgent in TaskManager.get_agents():
		if other == agent or not is_instance_valid(other): continue
		if other.get_food().grilling_fire_id() == _grill_fire.installed_id or other.fire_watched() == _grill_fire.installed_id: return true
	return false

## The campfire this dwarf is grilling at, or -1.
func grilling_fire_id() -> int:
	return _grill_fire.installed_id if grilled and _grill_fire != null and state in ["grilling", "eating"] else -1

func serialize() -> Dictionary:
	return {"value":value,"last_meal":last_meal,"last_dining":last_dining,"hours_since_meal":hours_since_meal,"retry_hours":retry_hours}

func restore(data: Dictionary) -> void:
	value = clampf(float(data.value),0.0,1.0)
	last_meal = String(data.last_meal)
	last_dining = String(data.last_dining)
	shortage = false
	_scouting = false
	hours_since_meal = maxf(0.0,float(data.hours_since_meal))
	retry_hours = maxf(0.0,float(data.retry_hours))
