extends Node

## The colony's journal (doc 23): what the dwarves said, kept for keep_days
## (journal_lines.json) and saved with the colony as the `journal` section. Colony's page
## shows it beside the rows.
## - Every check_seconds it looks at each dwarf's thoughts (DwarfMood.thoughts()). A
##   thought begins when the dwarf has it and did not at the last look, or when its memory
##   comes again: its age falls back by more than renewed_hours (a second night in the
##   cold, another meal off the knees).
## - Each topic gets one line a day. The first dwarf whose thought began speaks, in one of
##   the thought's lines; each other dwarf whose same thought begins that day joins it.
## - What dwarves already think when the journal first sees them (after a load, or on
##   arrival) is not news.
## Nothing is noted while the clock stands still or a save loads.

signal changed

const DATA_PATH := "res://data/colony/journal_lines.json"
## SaveSnapshotValidator bounds the saved list to this many lines.
const MAX_LINES := 200

var config: Dictionary = {}
var _lines: Array = []   # oldest first
var _known := {}         # dwarf id -> {thought id: its age at the last look}
var _check_left := 0.0


func _ready() -> void:
	config = preload("res://scripts/registries/JsonData.gd").read_dict(DATA_PATH)
	add_to_group("save_state_owner")


func _process(delta: float) -> void:
	_check_left -= delta
	if _check_left > 0.0: return
	_check_left = float(config.get("check_seconds", 1.0))
	check_thoughts()


## Notes every thought that began since the last look.
func check_thoughts() -> void:
	if SaveManager.is_loading() or WorldClock.paused or WorldClock.speed <= 0.0: return
	var seen := {}
	for agent: DwarfAgent in TaskManager.get_agents():
		if not is_instance_valid(agent) or agent.get_mood() == null: continue
		seen[agent.dwarf_id] = true
		var before: Variant = _known.get(agent.dwarf_id)
		var now := {}
		for thought: Dictionary in agent.get_mood().thoughts():
			now[thought.id] = float(thought.age)
			if before == null: continue
			if not (before as Dictionary).has(thought.id) \
					or float(thought.age) < float(before[thought.id]) - float(config.get("renewed_hours", 0.5)):
				note(agent, thought)
		_known[agent.dwarf_id] = now
	for id: int in _known.keys():
		if not seen.has(id): _known.erase(id)


## `thought` began for `agent` (a DwarfMood.thoughts() row): today's line for its topic
## gains the dwarf, or a new line opens in the dwarf's words.
func note(agent: DwarfAgent, thought: Dictionary) -> void:
	var words: Array = config.get("lines", {}).get(thought.id, [])
	if words.is_empty(): push_error("ColonyJournal: the thought '%s' has no lines in %s." % [thought.id, DATA_PATH])
	_add_line(agent, String(thought.id), String(thought.text), "complaint" if int(thought.points) < 0 else "praise", words)


## `agent` found one of their tastes (doc 41 "Tastes"): today's line for that taste, a praise
## for a love or a like and a complaint for a dislike, in the dwarf's words about the thing
## (found_love, found_like and found_dislike, with {thing} for its name).
func note_taste(agent: DwarfAgent, thing: String, kind: String) -> void:
	if SaveManager.is_loading(): return
	var tastes: RefCounted = agent.get_tastes()
	_add_line(agent, "found_%s:%s" % [kind, thing], "Found a taste: " + tastes.describe(thing),
		"complaint" if kind == "dislike" else "praise", config.get("lines", {}).get("found_" + kind, []), {"thing": tastes.thing_name(thing)})


## Today's line for a topic gains the dwarf, or a new line opens in the dwarf's words: one of
## `words`, chosen by the dwarf, the day and the topic, with `fill` put in.
func _add_line(agent: DwarfAgent, topic: String, text: String, tone: String, words: Array, fill := {}) -> void:
	var day := floori(WorldClock.elapsed_days())
	for line: Dictionary in _lines:
		if int(line.day) != day or line.topic != topic: continue
		if not agent.dwarf_id in line.dwarves:
			(line.dwarves as Array).append(agent.dwarf_id)
			changed.emit()
		return
	var said := "" if words.is_empty() else String(words[posmod(("%d:%d:%s" % [agent.dwarf_id, day, topic]).hash(), words.size())]).format(fill)
	_lines.append({"day": day, "topic": topic, "text": text, "tone": tone, "dwarves": [agent.dwarf_id],
		"speaker": agent.dwarf_id, "name": agent.dwarf_name, "words": said})
	_prune()
	changed.emit()


## Every line, newest first, as copies: {day, topic, text (the thought), tone (complaint or
## praise), dwarves (ids sharing it that day), speaker, name (the speaker's), words}.
func lines() -> Array:
	var list := _lines.duplicate(true)
	list.reverse()
	return list


# ── Saving (doc 13, the save_state_owner contract) ─────────────────────────────

func save_section_key() -> String:
	return "journal"


## Last: the journal names no other section's state.
func save_restore_priority() -> int:
	return 90


func serialize_state() -> Dictionary:
	return {"lines": _lines.duplicate(true)}


func restore_state(state: Dictionary) -> void:
	_lines.clear()
	for saved: Dictionary in state.lines:
		var line := saved.duplicate(true)
		line.day = int(line.day)   # JSON numbers come back as floats
		line.speaker = int(line.speaker)
		line.dwarves = (line.dwarves as Array).map(func(value: Variant) -> int: return int(value))
		_lines.append(line)
	_known.clear()
	changed.emit()


## A new world, or a load about to replace this one (SaveManager).
func clear_runtime_state() -> void:
	_lines.clear()
	_known.clear()
	changed.emit()


## Keeps keep_days of lines, today included, up to MAX_LINES.
func _prune() -> void:
	var oldest := floori(WorldClock.elapsed_days()) - int(config.get("keep_days", 10)) + 1
	_lines = _lines.filter(func(line: Dictionary) -> bool: return int(line.day) >= oldest)
	while _lines.size() > MAX_LINES: _lines.remove_at(0)
