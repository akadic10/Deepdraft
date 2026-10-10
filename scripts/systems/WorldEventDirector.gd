extends Node
## Calendar opportunities are independent of population and kills. Providers own
## entry routing and actors; this owner owns decisions, expiry and batch progress.
signal arrival_finished(event_id: String, count: int, edge: String)

const DATA_PATH := "res://data/world_events/arrivals.json"
var config: Dictionary = {}
var initialized := false
var schedules: Dictionary = {}
var pressure: Dictionary = {}
var history: Array = []
var random := RandomNumberGenerator.new()
var serial := 0

func _ready() -> void:
	add_to_group("world_events")
	add_to_group(SaveManager.OWNER_GROUP)
	config = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH)) as Dictionary
	arrival_finished.connect(_announce)

func _process(delta: float) -> void:
	if SaveManager.is_loading(): return
	var ready := false
	for event: Dictionary in config.events:
		var provider := _provider(event)
		if provider != null and provider.arrival_ready(): ready = true
	if ready: advance(delta)

func initialize_schedule() -> void:
	if not initialized:
		random.seed = WorldGenerator.world_seed + int(config.salt)
		initialized = true
	for event: Dictionary in config.events:
		# Newly introduced event definitions get their own delayed first chance
		# after loading; existing decisions are preserved.
		if not schedules.has(event.id): schedules[event.id] = {"next": _draw(event), "active": {}}

func _draw(event: Dictionary) -> Dictionary:
	serial += 1
	return {"id": "%s:%d:%d" % [event.id, WorldGenerator.world_seed, serial],
		"due": WorldClock.elapsed_days() + random.randf_range(float(event.interval_days[0]), float(event.interval_days[1])),
		"count": random.randi_range(int(event.group_size[0]), int(event.group_size[1])),
		"roll": random.randf(), "seed": str(random.randi())}

func advance(delta: float) -> void:
	if SaveManager.is_loading(): return
	initialize_schedule()
	if WorldClock.paused or WorldClock.speed <= 0: return
	var now := WorldClock.elapsed_days()
	for event: Dictionary in config.events:
		var state: Dictionary = schedules[event.id]
		if now >= float(state.next.due):
			# Consume once, schedule from now, and discard missed opportunities.
			# A long clock jump never creates a backlog or a burst of arrivals.
			var plan: Dictionary = state.next
			state.next = _draw(event)
			if not state.active.is_empty(): _finish(event, state, "expired")
			if now > float(plan.due) + float(event.expiry_days):
				_record(plan.id, "missed", 0)
			elif float(plan.roll) >= float(event.season_chance.get(WorldClock.season, 0)):
				_record(plan.id, "season", 0)
			else:
				state.active = plan.duplicate(true)
				state.active.merge({"attempt": 0, "issued": 0, "wait": 0.0, "route": [], "edge": ""})
		var active: Dictionary = state.active
		if active.is_empty(): continue
		if now > float(active.due) + float(event.expiry_days):
			_finish(event, state, "expired")
			continue
		var provider := _provider(event)
		if provider == null or not provider.arrival_ready(): continue
		if active.route.is_empty():
			var result: Dictionary = provider.prepare_arrival(event, active, self)
			active.attempt = int(active.attempt) + 1
			if result.get("status", "retry") == "blocked":
				_finish(event, state, String(result.get("reason", "blocked")))
				continue
			if result.get("status", "retry") == "ready": active.merge(result, true)
			elif int(active.attempt) >= int(event.entry_attempts):
				_finish(event, state, "no corridor")
				continue
			else: continue # At most one bounded candidate search per frame.
		active.wait = maxf(0, float(active.wait) - delta * WorldClock.speed)
		if float(active.wait) > 0: continue
		var outcome: String = provider.spawn_arrival_member(event, active, self)
		if outcome == "spawned":
			active.issued = int(active.issued) + 1
			active.wait = float(event.member_seconds)
			if int(active.issued) >= int(active.count): _finish(event, state, "arrived")
		elif outcome != "wait": _finish(event, state, outcome)
		else: active.wait = float(event.member_seconds)

func _provider(event: Dictionary) -> Node:
	for provider in get_tree().get_nodes_in_group("arrival_provider"):
		if provider.arrival_provider_key() == event.provider: return provider
	return null

func _finish(event: Dictionary, state: Dictionary, reason: String) -> void:
	var active: Dictionary = state.active
	_record(active.id, reason, int(active.issued))
	state.active = {}
	if int(active.issued) > 0: arrival_finished.emit(event.id, int(active.issued), String(active.edge))

func _record(id: String, reason: String, count: int) -> void:
	history.append({"id": id, "result": reason, "count": count, "day": WorldClock.elapsed_days()})
	if history.size() > 12: history.pop_front()

func _announce(event_id: String, count: int, edge: String) -> void:
	var dock := get_tree().get_first_node_in_group("command_dock")
	if dock == null: return
	for event: Dictionary in config.events:
		if event.id != event_id: continue
		var subject := "A %s has" % event.singular_name if count == 1 else "%d %s have" % [count, event.plural_name]
		dock.show_persistence_status(subject+" arrived from the %s." % edge)
		return

func record_player_hunt(at: Vector3i) -> void:
	# Only the wildlife owner's successful player_hunt removal calls this hook.
	# Predation does not count. No schedule, count, roll or RNG changes here.
	var tuning: Dictionary = config.hunting_pressure
	var size := int(tuning.cell_size)
	var key := "%d:%d" % [floori(float(at.x)/size), floori(float(at.z)/size)]
	var now := WorldClock.elapsed_days()
	var old: Dictionary = pressure.get(key, {"level": 0.0, "day": now})
	var level := _pressure_level(old, now)
	pressure[key] = {"x": floori(float(at.x)/size)*size+size/2.0,
		"z": floori(float(at.z)/size)*size+size/2.0,
		"level": minf(float(tuning.maximum), level+float(tuning.per_kill)), "day": now}
	# Bounded by the world's fixed region grid; remove fully faded regions.
	for region in pressure.keys():
		if _pressure_level(pressure[region], now) <= 0: pressure.erase(region)

func _pressure_level(region: Dictionary, now: float) -> float:
	return maxf(0, float(region.level) - maxf(0, now-float(region.day))*float(config.hunting_pressure.decay_per_day))

func safe_arrival_cell(at: Vector3i) -> bool:
	var tuning: Dictionary = config.hunting_pressure
	for region: Dictionary in pressure.values():
		if Vector2(at.x-float(region.x), at.z-float(region.z)).length() <= float(tuning.radius) and _pressure_level(region, WorldClock.elapsed_days()) >= float(tuning.avoid_threshold): return false
	return true

func dev_status() -> String:
	if not initialized: return "Arrival schedule is waiting for the world."
	var lines := PackedStringArray()
	for event: Dictionary in config.events:
		if not schedules.has(event.id): continue
		var state: Dictionary = schedules[event.id]
		var days := maxf(0, float(state.next.due)-WorldClock.elapsed_days())
		var detail := "No arrivals yet."
		if not state.active.is_empty(): detail = "A group is entering."
		else:
			for i in range(history.size()-1, -1, -1):
				var last: Dictionary = history[i]
				if not String(last.id).begins_with(String(event.id)+":"): continue
				detail = "Last: %d arrived." % int(last.count) if int(last.count) > 0 else "Skipped: %s." % last.result
				break
		lines.append("%s opportunity in %.1f days. %s" % [String(event.singular_name).capitalize(), days, detail])
	return "\n".join(lines)

func save_section_key() -> String:
	return "world_events"

func save_restore_priority() -> int:
	return 66

func serialize_state() -> Dictionary:
	return {"initialized": initialized, "serial": serial, "rng": str(random.state),
		"schedules": schedules.duplicate(true), "pressure": pressure.duplicate(true), "history": history.duplicate(true)}

func restore_state(state: Dictionary) -> void:
	initialized = bool(state.get("initialized", false))
	serial = int(state.get("serial", 0))
	random.state = int(String(state.get("rng", "0")))
	schedules = state.get("schedules", {}).duplicate(true)
	pressure = state.get("pressure", {}).duplicate(true)
	history = state.get("history", []).duplicate(true)
