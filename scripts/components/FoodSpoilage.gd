extends RefCounted

## Food spoilage (doc 42 "Spoilage"; doc 282 phase 2), owned by StockpileManager. Each food
## stack carries its spoil, 0 fresh to 1 rotten (ItemDropManager.spoil_of; a stored stack in
## its storage entry, shown on its crate). Once a game hour a pass, spread over frames
## (budget_usec, task_config.json food.spoilage), adds the hours since the last pass:
## - speed = rate_per_10c ^ ((T - reference_c) / 10) at the stack's temperature T now (doc 34);
## - frozen_speed instead under a roof at temperature.json's frozen_at_c or colder;
## - open_sky_speed more under the open sky, wet_speed in rain, storm or snow;
## - spoil += hours x speed / (24 x keeps_days), keeps_days being the food's (resources.json).
## A stored stack spoils at its cell, a loose one where it lies, a carried one where its carrier
## stands; fruit on the bush never spoils. At 1 the units nobody has claimed rot and go. Units
## claimed for a meal or a haul, and those in hand, stay until used (Hard Rule 12).
## Events gets one line for each food in each place that passes warn_at or rots.
## Only the spoil is saved; after a load the hours start afresh.
## A pass finished: the readouts show the new spoil (the storage window's Keeping list).
signal passed
var owner: Node   # StockpileManager
var config: Dictionary
var _last_days := -1.0   # WorldClock.elapsed_days() at the last pass; -1 before the first
var _pass := {}          # the pass under way: {hours, drops, entries, index, crates, warned, rotted}


func _init(manager: Node) -> void:
	owner = manager
	config = TaskManager.get_config_section("food").get("spoilage", {})


func clear() -> void:
	_last_days = -1.0
	_pass = {}


func busy() -> bool:
	return not _pass.is_empty()


## A game hour passed: a pass over the hours since the last one. While a pass is still going,
## the next one takes these hours too.
func on_hour() -> void:
	if busy(): return
	var now := WorldClock.elapsed_days()
	var hours := (now - _last_days) * WorldClock.hours_per_day() if _last_days >= 0.0 else 0.0
	_last_days = now
	if hours > 0.0: _begin(hours)


## Carries the pass on within the frame's budget.
func tick() -> void:
	if not busy(): return
	var deadline := Time.get_ticks_usec() + int(config.get("budget_usec", 500))
	while Time.get_ticks_usec() < deadline:
		if not _step():
			_finish()
			return


## A whole pass over `hours` at once, for tests and development tools.
func run(hours: float) -> void:
	_begin(hours)
	while _step(): pass
	_finish()


## How fast food spoils at a spot now: 1 at reference_c under a roof.
func speed_at(cell: Vector3i) -> float:
	var climate = RoomManager.climate
	var temperature := float(RoomManager.temperature_at(cell))
	var speed := pow(float(config.rate_per_10c), (temperature - float(config.reference_c)) / 10.0)
	if climate.is_open_sky(cell):
		speed += float(config.wet_speed if climate.is_wet() else config.open_sky_speed)
	elif temperature <= float(RoomManager.temperature_config.frozen_at_c):
		speed = float(config.frozen_speed)
	return speed


## Days a food lasts from fresh at a spot, as the spot is now; 0 for goods that never spoil.
func keeps_days_at(food: Dictionary, cell: Vector3i) -> float:
	return float(food.get("keeps_days", 0.0)) / speed_at(cell)


## A stack's freshness at a spot, as the readouts say it (doc 23): {word, tone, days, text}.
## Fresh below spoiling_at (moss), Spoiling below warn_at (hay), then Going bad (rust); Frozen
## while it keeps at frozen_speed, in its spoil's tone. days is what it has left there.
func freshness(food: Dictionary, spoil: float, cell: Vector3i) -> Dictionary:
	var speed := speed_at(cell)
	var tone := "fine" if spoil < float(config.spoiling_at) else ("waiting" if spoil < float(config.warn_at) else "blocked")
	var word: String = {"fine": "Fresh", "waiting": "Spoiling", "blocked": "Going bad"}[tone]
	if speed <= float(config.frozen_speed) + 0.000001: word = "Frozen"
	var days := (1.0 - spoil) * float(food.get("keeps_days", 0.0)) / speed
	return {"word": word, "tone": tone, "days": days, "text": "%s · %s left" % [word, days_text(days)]}


## "less than a day", "about a day", "about 6 days".
static func days_text(days: float) -> String:
	if days < 1.0: return "less than a day"
	if days < 1.5: return "about a day"
	return "about %d days" % roundi(days)


# ── The pass ──────────────────────────────────────────────────────────────────

func _begin(hours: float) -> void:
	var drops := ItemDropManager.find(owner.get_tree())
	if drops == null: return
	var entries: Array = []
	for zone: StockpileZoneComponent in owner.get_zones():
		for cell: Vector3i in zone.cell_stacks:
			if _keeps(drops, String(zone.cell_stacks[cell].get("item", ""))) > 0.0: entries.append(["stored", zone, cell])
	for node: Node3D in drops.loose_items():
		if _keeps(drops, drops.item_key_of(node)) > 0.0: entries.append(["loose", node])
	for agent: DwarfAgent in TaskManager.get_agents():
		if not is_instance_valid(agent): continue
		for carried: Array in agent.get_carried_entries():
			if _keeps(drops, String(carried[1])) > 0.0: entries.append(["carried", carried[0], agent])
	_pass = {"hours": hours, "drops": drops, "entries": entries, "index": 0, "crates": drops.stored_nodes(),
		"warned": {}, "rotted": {}}


## One stack; false when the pass has none left.
func _step() -> bool:
	if not busy() or not is_instance_valid(_pass.drops) or int(_pass.index) >= (_pass.entries as Array).size(): return false
	var entry: Array = _pass.entries[_pass.index]
	_pass.index += 1
	match String(entry[0]):
		"stored": _stored(entry[1], entry[2])
		"loose": _loose(entry[1])
		"carried": _carried(entry[1], entry[2])
	return true


func _stored(zone: StockpileZoneComponent, cell: Vector3i) -> void:
	if not owner.is_registered(zone) or not zone.cell_stacks.has(cell): return
	var stack: Dictionary = zone.cell_stacks[cell]
	var key := String(stack.item)
	var before := float(stack.get("spoil", 0.0))
	var after := minf(1.0, before + _gain(key, cell + Vector3i.UP))
	stack["spoil"] = after
	var crate: Node3D = _pass.crates.get(cell)
	if is_instance_valid(crate): ItemDropManager.set_spoil(crate, after)
	var place := "in Stockpile %d" % zone.zone_id
	if after >= 1.0: _note(_pass.rotted, key, place, cell, zone.discard_unclaimed(cell))
	elif before < float(config.warn_at) and after >= float(config.warn_at): _warn(key, place, cell, after)


func _loose(node: Node3D) -> void:
	var drops: ItemDropManager = _pass.drops
	if not is_instance_valid(node) or node.is_queued_for_deletion() or not drops.is_loose(node): return
	var key := drops.item_key_of(node)
	var cell := drops.item_floor_cell(node)
	var before := ItemDropManager.spoil_of(node)
	var after := minf(1.0, before + _gain(key, cell + Vector3i.UP))
	ItemDropManager.set_spoil(node, after)
	if after >= 1.0:
		if drops.is_claimed(node): return
		var count := drops.quantity_of(node)
		drops.discard(node)
		_note(_pass.rotted, key, "on the ground", cell, count)
	elif before < float(config.warn_at) and after >= float(config.warn_at): _warn(key, "on the ground", cell, after)


## In hand food is claimed; it never rots there, and rots where it is put down if due.
func _carried(node: Node3D, agent: DwarfAgent) -> void:
	if not is_instance_valid(node) or not is_instance_valid(agent) or bool(node.get_meta("stored", false)): return
	if (_pass.drops as ItemDropManager).is_loose(node): return
	var key := String(node.get_meta("item_key", ""))
	ItemDropManager.set_spoil(node, minf(1.0, ItemDropManager.spoil_of(node) + _gain(key, agent.current_cell() + Vector3i.UP)))


## What the pass's hours cost a food at a spot.
func _gain(key: String, cell: Vector3i) -> float:
	var keeps := _keeps(_pass.drops, key)
	if keeps <= 0.0: return 0.0
	return float(_pass.hours) * speed_at(cell) / (float(WorldClock.hours_per_day()) * keeps)


func _keeps(drops: ItemDropManager, key: String) -> float:
	return float(drops.food_definition(key).get("keeps_days", 0.0)) if not key.is_empty() else 0.0


# ── Events ────────────────────────────────────────────────────────────────────

func _note(notes: Dictionary, key: String, place: String, cell: Vector3i, count: int) -> void:
	if count <= 0: return
	var id := "%s|%s" % [key, place]
	if not notes.has(id): notes[id] = {"key": key, "place": place, "cell": cell, "count": 0, "days": INF}
	notes[id].count = int(notes[id].count) + count


## A stack passing warn_at, with the days it has left at this spot as it is now.
func _warn(key: String, place: String, cell: Vector3i, spoil: float) -> void:
	_note(_pass.warned, key, place, cell, 1)
	var food: Dictionary = (_pass.drops as ItemDropManager).food_definition(key)
	var note: Dictionary = _pass.warned["%s|%s" % [key, place]]
	note.days = minf(float(note.days), (1.0 - spoil) * keeps_days_at(food, cell + Vector3i.UP))


func _finish() -> void:
	if busy() and is_instance_valid(_pass.drops):
		for note: Dictionary in (_pass.rotted as Dictionary).values():
			EventLog.post("warning", "%d %s rotted %s." % [int(note.count), _name(note.key, int(note.count)), note.place],
				{"picture": _picture(note.key), "place": note.cell})
		for note: Dictionary in (_pass.warned as Dictionary).values():
			var name := _name(note.key, 2)
			EventLog.post("warning", "%s %s are going bad: %s left." % [name.left(1).to_upper() + name.substr(1), note.place, days_text(float(note.days))],
				{"picture": _picture(note.key), "place": note.cell})
	var finished := busy()
	_pass = {}
	if finished: passed.emit()


func _name(key: String, count: int) -> String:
	var definition := (_pass.drops as ItemDropManager).get_item_def(key)
	var single := String(definition.get("display_name", key)).to_lower()
	return single if count == 1 else String(definition.get("plural_name", single + "s"))


static func _picture(key: String) -> String:
	return "res://assets/ui/items/%s.png" % key.replace(":", "_")
