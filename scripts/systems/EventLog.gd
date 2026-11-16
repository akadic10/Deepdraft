extends Node

## The colony's event log (doc 23): arrivals, caverns found, colony news and
## warnings, kept for keep_days (event_log.json) and saved with the colony as the
## `events` section. A warning stays pinned by its key until it is resolved: the
## hungry-dwarves check here raises and resolves its own, and a held warning (rising
## water) resolves itself once it has not been raised again for its hold. Toasts, the
## Events window and the dock's bell follow entry_added and changed. The player's own
## messages (saves, loads, the flag) never land here; they stay toasts
## (DockUI.show_persistence_status).
##
## An entry is kept and saved as a code and its fields, never a sentence (doc 13, "Codes
## and words"): `line` names its words in event_log.json's lines, and `fields` holds the
## numbers, the proper names and the ids its sentence takes ({"count": 3, "item":
## "base:item:carrot", "where": "stockpile:2"}). This script is the one place that words
## them: every copy it hands out (entries(), warning(), pinned(), entry_added) carries the
## built `text` and `detail`.

signal entry_added(entry: Dictionary)
signal changed

const Wording = preload("res://scripts/components/Wording.gd")
const FoodSpoilage = preload("res://scripts/components/FoodSpoilage.gd")
const DATA_PATH := "res://data/events/event_log.json"
## SaveSnapshotValidator bounds the saved list to this many entries.
const MAX_ENTRIES := 200

var config: Dictionary = {}
var _entries: Array = []        # oldest first
var _next_id := 1
var _seen_id := 0
var _check_left := 0.0


func _ready() -> void:
	config = preload("res://scripts/registries/JsonData.gd").read_dict(DATA_PATH)
	add_to_group("save_state_owner")
	InteriorTracker.cavern_found.connect(_on_cavern_found)
	WaterManager.flood_warning.connect(_on_flood)
	WorldClock.season_changed.connect(_on_season_changed)


func _process(delta: float) -> void:
	_check_left -= delta
	if _check_left > 0.0: return
	_check_left = float(config.get("food_check_seconds", 1.0))
	check_food()
	_expire_held()


## Adds an entry at the colony's time and returns its id, or 0 while a save loads.
## `line` is its code in event_log.json's lines, and `fields` what its sentence takes:
## numbers, proper names and ids, never words the game would say another way.
## options: picture (else the kind's), place (a cell), and dwarves (ids; Locate follows
## them).
func post(kind: String, line: String, fields: Dictionary = {}, options: Dictionary = {}) -> int:
	if SaveManager.is_loading(): return 0
	return _add(_entry(kind, line, fields, options))


## Pins the warning `key`, or updates its line, fields, picture, place and dwarves while it
## lasts, without a new toast. options as post(), plus hold_hours: the warning then
## resolves itself once it has not been raised again for that many in-game hours. Once
## resolved it reads in its line's past words, when the line has them ("2 dwarves could
## not find reachable food.").
func raise(key: String, line: String, fields: Dictionary = {}, options: Dictionary = {}) -> int:
	if SaveManager.is_loading(): return 0
	var entry := _warning(key)
	if entry.is_empty():
		entry = _entry("warning", line, fields, options)
		entry.warning = key
		entry.raised = entry.time
		if options.has("hold_hours"): entry.hold = float(options.hold_hours)
		return _add(entry)
	var before := entry.duplicate(true)
	_known(line)
	entry.line = line
	entry.fields = fields.duplicate(true)
	if options.has("picture"): entry.picture = String(options.picture)
	if options.has("hold_hours"): entry.hold = float(options.hold_hours)
	entry.erase("place")
	entry.erase("dwarves")
	_locate(entry, options)
	entry.raised = WorldClock.elapsed_days()
	before.raised = entry.raised
	if entry != before: changed.emit()
	return int(entry.id)


## Resolves the warning `key`: it leaves the pinned warnings and stays in its day, in its
## line's past words when it has them.
func resolve(key: String) -> void:
	var entry := _warning(key)
	if entry.is_empty(): return
	_settle(entry)
	changed.emit()


## The hungry-dwarves warning (doc 41): hungry dwarves whose food searches failed,
## checked every food_check_seconds. Events pins it, and the dock's bell turns rust.
func check_food() -> void:
	if SaveManager.is_loading(): return
	var hungry: Array = []
	for agent: DwarfAgent in TaskManager.get_agents():
		if is_instance_valid(agent) and agent.get_food() != null and agent.get_food().shortage and agent.get_food().hungry():
			hungry.append(agent.dwarf_id)
	if hungry.is_empty():
		resolve("food")
		return
	raise("food", "food_short", {"count": hungry.size()}, {"dwarves": hungry})


## Every entry, newest first, as copies with their words (text and detail).
func entries() -> Array:
	var list: Array = []
	for index in range(_entries.size() - 1, -1, -1): list.append(_shown(_entries[index]))
	return list


## The warning `key` while it is unresolved, as a copy with its words; {} otherwise.
func warning(key: String) -> Dictionary:
	var entry := _warning(key)
	return _shown(entry) if not entry.is_empty() else {}


## The warnings still unresolved, newest first, as copies with their words: Events' Needs
## attention.
func pinned() -> Array:
	var list: Array = []
	for index in range(_entries.size() - 1, -1, -1):
		if _pinned(_entries[index]): list.append(_shown(_entries[index]))
	return list


## How many entries arrived since Events was last looked at.
func unseen() -> int:
	var count := 0
	for entry: Dictionary in _entries:
		if int(entry.id) > _seen_id: count += 1
	return count


## The newest entry id already seen; Events tags the entries after it as New.
func last_seen() -> int:
	return _seen_id


## Everything logged so far has been seen.
func mark_seen() -> void:
	if _seen_id == _next_id - 1: return
	_seen_id = _next_id - 1
	changed.emit()


## How long a toast stays for an entry of this kind.
func toast_seconds(kind: String) -> float:
	return float(_kind(kind).get("toast_seconds", 4.0))


## How long a toast stays for the player's own message.
func message_seconds(is_error: bool) -> float:
	var messages: Dictionary = config.get("messages", {})
	return float(messages.get("error_toast_seconds" if is_error else "toast_seconds", 2.5))


## How many toasts show at once.
func toast_limit() -> int:
	return int(config.get("toast_limit", 3))


## Every line code the data has, for the save check: a save naming another is refused.
func line_codes() -> Dictionary:
	var codes := {}
	for code: String in config.get("lines", {}): codes[code] = true
	return codes


# ── Words (doc 13, "Codes and words") ──────────────────────────────────────────

## A copy of an entry as the windows read it, with its words: `text`, its line's sentence
## with its fields put in (the line's past words once a warning that has them is resolved),
## and `detail`, its second line or "". A line the data does not have reads as its code.
func _shown(entry: Dictionary) -> Dictionary:
	var copy := entry.duplicate(true)
	var words: Dictionary = _line(String(entry.line))
	var fields := _worded(entry.fields)
	var said: Variant = words.get("past") if entry.has("resolved") and words.has("past") else words.get("text", String(entry.line))
	copy.text = Wording.fill(said, fields)
	copy.detail = Wording.fill(words.detail, fields) if words.has("detail") else ""
	return copy


func _line(code: String) -> Dictionary:
	return config.get("lines", {}).get(code, {})


## What a line advises, its second line in Events, for a window that gives the same advice
## about the same trouble (a hungry dwarf's own card). "" when the line has none.
func advice(code: String) -> String:
	var words: Dictionary = _line(code)
	return Wording.fill(words.detail, {}) if words.has("detail") else ""


func _known(line: String) -> bool:
	if not _line(line).is_empty(): return true
	push_error("EventLog: '%s' is not a line in %s." % [line, DATA_PATH])
	return false


## The fields as a sentence takes them: numbers and proper names as they are, and each id
## in the game's words. An item gives {item}, {items} and {Items}; a crop {crops}; an
## arrival's id {animal} and {animals}; a season {season} and {Season}; a place code {where}.
func _worded(fields: Dictionary) -> Dictionary:
	var words := fields.duplicate()
	if fields.has("item"):
		var item := ContentRegistry.item_def(String(fields.item))
		var single := String(item.get("display_name", fields.item)).to_lower()
		var many := String(item.get("plural_name", single))
		words.merge({"item": single, "items": many, "Items": many.left(1).to_upper() + many.substr(1)}, true)
	if fields.has("crop"): words.crops = String(ContentRegistry.crop(String(fields.crop)).get("plural_name", fields.crop))
	if fields.has("profession"):
		words.profession = String(DwarfAssets.profession_definition(String(fields.profession)).get("display_name", fields.profession))
	# A season's id and a map edge's are their words in English.
	if fields.has("season"): words.Season = String(fields.season).capitalize()
	if fields.has("event"):
		var director := get_tree().get_first_node_in_group("world_events")
		var names: Dictionary = director.arrival_names(String(fields.event)) if director != null else {}
		words.animal = String(names.get("one", fields.event))
		words.animals = String(names.get("other", fields.event))
	if fields.has("where"): words.where = _place(String(fields.where))
	if fields.has("days"): words.days = FoodSpoilage.days_text(float(fields.days))
	return words


## Where goods lie, from a place code: "ground", "storage", "stockpile:<number>" or
## "piece:<furniture id>" (StorageComponent.place_code()).
func _place(where: String) -> String:
	var kind := where.get_slice(":", 0)
	var rest := where.substr(kind.length() + 1)
	return Wording.of(config.get("places", {}), kind,
		{"zone": rest, "piece": String(ContentRegistry.furniture_def(rest).get("display_name", rest)).to_lower()})


# ── Saving (doc 13, the save_state_owner contract) ─────────────────────────────

func save_section_key() -> String:
	return "events"


## Last: the log names no other section's state.
func save_restore_priority() -> int:
	return 90


func serialize_state() -> Dictionary:
	return {"next_id": _next_id, "seen_id": _seen_id, "entries": _entries.duplicate(true)}


func restore_state(state: Dictionary) -> void:
	_entries.clear()
	for saved: Dictionary in state.entries:
		var entry := saved.duplicate(true)
		entry.id = int(entry.id)   # JSON numbers come back as floats
		for field: String in entry.fields:
			var value: Variant = entry.fields[field]
			if value is float and value == floorf(value) and field != "days": entry.fields[field] = int(value)
		if entry.has("place"): entry.place = (entry.place as Array).map(func(value: Variant) -> int: return int(value))
		if entry.has("dwarves"): entry.dwarves = (entry.dwarves as Array).map(func(value: Variant) -> int: return int(value))
		_entries.append(entry)
	_next_id = int(state.next_id)
	_seen_id = int(state.seen_id)
	changed.emit()


## A new world, or a load about to replace this one (SaveManager).
func clear_runtime_state() -> void:
	_entries.clear()
	_next_id = 1
	_seen_id = 0
	changed.emit()


# ── Sources ────────────────────────────────────────────────────────────────────

func _on_cavern_found(cells: Array[Vector3i]) -> void:
	if not cells.is_empty(): post("discovery", "cavern_found", {}, {"place": _middle(cells)})


func _on_flood(cell: Vector3i) -> void:
	raise("flood", "flood", {}, {"place": cell, "hold_hours": float(config.get("flood_hold_hours", 3.0))})


## A new season, but not the clock being restored by a load or a new game.
func _on_season_changed(season: String) -> void:
	if not WorldClock.restoring_state: post("colony", "season_came", {"season": season})


# ── The entries ────────────────────────────────────────────────────────────────

func _entry(kind: String, line: String, fields: Dictionary, options: Dictionary) -> Dictionary:
	if _kind(kind).is_empty(): push_error("EventLog: '%s' is not a kind in %s." % [kind, DATA_PATH])
	_known(line)
	var entry := {"id": _next_id, "kind": kind, "line": line, "fields": fields.duplicate(true),
		"picture": String(options.get("picture", _kind(kind).get("picture", ""))), "time": WorldClock.elapsed_days()}
	_next_id += 1
	_locate(entry, options)
	return entry


## Where Locate takes the player: a cell, or the dwarves concerned.
static func _locate(entry: Dictionary, options: Dictionary) -> void:
	if options.has("place"):
		var cell: Vector3i = options.place
		entry.place = [cell.x, cell.y, cell.z]
	if options.has("dwarves"): entry.dwarves = (options.dwarves as Array).duplicate()


func _add(entry: Dictionary) -> int:
	_entries.append(entry)
	_prune()
	entry_added.emit(_shown(entry))
	changed.emit()
	return int(entry.id)


## The unresolved warning `key` itself, not a copy, or {}.
func _warning(key: String) -> Dictionary:
	for index in range(_entries.size() - 1, -1, -1):
		var entry: Dictionary = _entries[index]
		if String(entry.get("warning", "")) == key and not entry.has("resolved"): return entry
	return {}


func _kind(kind: String) -> Dictionary:
	return config.get("kinds", {}).get(kind, {})


static func _pinned(entry: Dictionary) -> bool:
	return entry.has("warning") and not entry.has("resolved")


## Keeps keep_days of entries, and pinned warnings however old, up to MAX_ENTRIES.
func _prune() -> void:
	var oldest := WorldClock.elapsed_days() - float(config.get("keep_days", 10))
	var kept: Array = []
	for entry: Dictionary in _entries:
		if float(entry.time) >= oldest or _pinned(entry): kept.append(entry)
	while kept.size() > MAX_ENTRIES:
		var index := 0
		while index < kept.size() - 1 and _pinned(kept[index]): index += 1
		kept.remove_at(index)
	_entries = kept


## Resolves the held warnings that have not been raised again within their hold.
func _expire_held() -> void:
	if SaveManager.is_loading(): return
	var now := WorldClock.elapsed_days()
	for entry: Dictionary in _entries:
		if _pinned(entry) and entry.has("hold") and (now - float(entry.raised)) * WorldClock.hours_per_day() > float(entry.hold):
			_settle(entry)
			changed.emit()


## Marks a warning resolved now; from then on it reads in its line's past words.
static func _settle(entry: Dictionary) -> void:
	entry.resolved = WorldClock.elapsed_days()


## The found cell nearest the middle of them all.
static func _middle(cells: Array[Vector3i]) -> Vector3i:
	var sum := Vector3.ZERO
	for cell: Vector3i in cells: sum += Vector3(cell)
	var middle := sum / float(cells.size())
	var best := cells[0]
	for cell: Vector3i in cells:
		if Vector3(cell).distance_squared_to(middle) < Vector3(best).distance_squared_to(middle): best = cell
	return best
