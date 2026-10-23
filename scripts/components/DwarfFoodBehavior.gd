extends RefCounted

## Personal self-care. Storage/drop owners retain inventory authority; hunger
## commits only when the dwarf consumes an actual carried portion.
const Route = preload("res://scripts/components/WorkRouteProbe.gd")
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
var _travel_left := 0.0
var shortage := false
var last_dining := ""
var _foraging: RefCounted
var _dining: RefCounted
var _serving: Node3D

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

func begin_if_needed() -> bool:
	if active() or not hungry() or retry_hours > 0.0: return false
	if agent.is_sleeping() or agent.promotion_pending() or not NavGrid.is_walkable(agent.current_cell()): return false
	_items = ItemDropManager.find(agent.get_tree())
	if _items == null: return false
	_keys = _items.edible_keys()
	# Clear work and callbacks before claiming self-care ownership.
	var had_task := agent.current_task_id >= 0
	agent.abort_task()
	if had_task: agent._work_execution.release(agent.dwarf_id, Task.ReleaseReason.NEED_INTERRUPT, false)
	state = "finding"
	message = "Looking for reachable food in storage."
	_query = {}; _quote = {}; _route = {}; _excluded = {}
	_loose = false
	_search_elapsed = 0.0
	TaskManager.notify_dwarf_unavailable(agent.dwarf_id)
	return true

func tick(seconds: float) -> void:
	if state == "foraging":
		_foraging.tick(seconds)
		return
	if state == "dining":
		if not is_instance_valid(portion):
			cancel()
			return
		if _dining.tick(seconds):
			state = "eating"
			_elapsed = 0.0
			message = "Eating %s." % _items.get_item_def(_quote.key).display_name
		_meal_pose(0.0)
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
		agent._carry_pose.gather(clampf(_elapsed/float(config.pickup_seconds),0.0,1.0), Vector3(0,1.1,.65))
		if _elapsed >= float(config.pickup_seconds): _take()
	elif state == "eating":
		if not is_instance_valid(portion) or not agent._carried_entries.any(func(entry): return entry[0] == portion):
			cancel("Meal interrupted; will try again.")
			return
		_elapsed += seconds
		_meal_pose(_elapsed)
		if _elapsed >= float(config.eat_seconds): _finish_meal()

func _find_food() -> void:
	var deadline := Time.get_ticks_usec()+int(config.search_budget_usec)
	if _quote.is_empty():
		var done: bool
		if _loose:
			done = _items.advance_material_quote(_keys,agent.current_cell(),_query,deadline,_excluded,-1,"","",false)
		else:
			done = StockpileManager.advance_material_quote(_keys,agent.current_cell(),_query,deadline,_excluded)
		if not done: return
		_quote = _query.best
		if _quote.is_empty():
			if not _loose:
				_loose = true
				_query = {}; _excluded = {}
				message = "Looking for reachable harvested food."
			else:
				shortage = true
				if famished():
					state = "foraging"
					_foraging = preload("DwarfForaging.gd").new(agent)
					message = "No reachable harvested food. Looking for nearby ripe berries."
				else: cancel("No reachable food; will try again.")
			return
	var goals := {}
	for cell: Vector3i in _stands():
		if NavGrid.is_walkable(cell): goals[cell] = true
	var result := NavGrid.ProbeResult.UNREACHABLE
	if not goals.is_empty():
		result = Route.advance(_route,agent.current_cell(),goals.keys()[0],int(config.search_nodes),deadline,false,goals) as NavGrid.ProbeResult
	if result == NavGrid.ProbeResult.SEARCHING: return
	if result != NavGrid.ProbeResult.REACHABLE:
		_exclude_quote()
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

func start_walk(path: Array) -> float:
	agent._move_path = []
	agent._move_path.assign(path)
	agent._move_index = 0
	agent._move_validation_index = -1
	agent._ladder_path_revision = NavGrid.ladder_revision
	agent._walk_cycle = 0.0
	agent._shortcut_timer = 0.0
	return maxf(10.0,preload("DwarfForaging.gd").path_length(agent.current_cell(),path)/maxf(.1,agent.walk_speed)*3.0)

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
	# Keep one real inventory portion; its temporary serving is presentation only.
	portion.hide()
	_serving = preload("DwarfMealVisual.gd").create(_items.food_definition(_quote.key))
	agent.add_child(_serving)
	state = "dining"
	_dining = preload("DwarfDining.gd").new(agent)
	_elapsed = 0.0
	message = "Finding a nearby place to eat."
	_meal_pose(0.0)

func _meal_pose(seconds: float) -> void:
	if not is_instance_valid(_serving): return
	var offset: Vector3 = _dining.pose(seconds) if state == "eating" else Vector3.ZERO
	var bite := (1.0-cos(seconds*TAU*.65))*.5 if state == "eating" else 0.0
	var grip := offset+Vector3(-.42,lerpf(1.4,2.2,bite),lerpf(.85,.62,bite))
	agent._carry_pose._pose_hand(agent._hand_r,grip,Quaternion.IDENTITY)
	agent._carry_pose._pose_hand(agent._hand_l,offset+Vector3(.65,1.35,.7),Quaternion.IDENTITY)
	_serving.position = grip+Vector3(0,.14,.08)
	_serving.rotation = Vector3(bite*.3,0,0)

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
	if is_instance_valid(_serving): _serving.queue_free()
	_serving = null
	if is_instance_valid(portion): agent._drop_carried_at_feet()
	portion = null
	_query = {}; _quote = {}; _route = {}; _excluded = {}; _token = {}
	_source = null
	agent.stop_walking()
	if not seated: agent._reset_part_offsets()
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
	if not last_dining.is_empty(): meal += "\n"+String({"proper":"Ate seated at a table","seat_only":"Ate without a table","table_only":"Ate standing at a table","neither":"Ate without a seat or table"}.get(last_dining,""))
	var effects := "Work speed −%d%% · Happiness −%d" % [roundi((1.0-work_multiplier())*100),roundi(mood_penalty()*100)] if hungry() else ""
	var destination: Vector3i = _quote.get("cell",Vector3i(-1,-1,-1))
	if state == "foraging": destination = _foraging.destination
	elif state in ["dining","eating"]:
		destination = _dining.goal if _dining.goal.x >= 0 else agent.current_cell()
	var activity: String = {"finding":"Looking for food","walking":"Collecting food","pickup":"Taking a food portion","eating":"Eating","dining":"Finding a place to eat"}.get(state,"")
	if state == "foraging": activity = {"searching":"Looking for emergency berries","walking":"Going to pick berries","picking":"Picking emergency berries"}.get(_foraging.state,"")
	return {"value":value,"label":label,"meal":meal,"effects":effects,"shortage":shortage and hungry(),
		"detail":meal+("\n"+effects if not effects.is_empty() else "")+("\n"+message if not message.is_empty() else ""),
		"activity":activity,
		"explanation":message,"destination":destination}

func serialize() -> Dictionary:
	return {"value":value,"last_meal":last_meal,"last_dining":last_dining,"hours_since_meal":hours_since_meal,"retry_hours":retry_hours}

func restore(data: Dictionary) -> void:
	value = clampf(float(data.value),0.0,1.0)
	last_meal = String(data.last_meal)
	last_dining = String(data.last_dining)
	shortage = false
	hours_since_meal = maxf(0.0,float(data.hours_since_meal))
	retry_hours = maxf(0.0,float(data.retry_hours))
