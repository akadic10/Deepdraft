extends RefCounted

## Room types (doc 34 "Room types"; the room window in doc 23): what a sealed room is, by
## what it holds and how warm it is. RoomManager owns the rooms and the data
## (data/rooms/room_kinds.json); this works a room's type out and says, in the data's words,
## what a type needs and what a room still lacks.
## - A room takes the first type whose needs it meets, in the data's order; with none it is a
##   plain room.
## - A need is a count with a least and sometimes a most (beds, lights, doors, tables, seats,
##   fires, food_stores), a `temperature` range in °C, or the type's `owner` (the room's one
##   bed has an owner).
## - A plain room is on its way to a type whose key piece it holds: the one it is fewest
##   needs away from, the first such in the data's order. Holding no type's key piece, it is
##   on its way to none, and the room window shows what it could be.

var owner: Node              # RoomManager
var all: Array = []          # every type, in the order rooms are tested against them
var things: Dictionary = {}  # need id -> its words and picture


func _init(manager: Node, data: Dictionary) -> void:
	owner = manager
	all = data.get("kinds", [])
	things = data.get("things", {})


## What an installed piece counts as toward room types, beyond the beds, lights and doors
## RoomManager already tracks, from its definition: a dining table by its dining surface, a
## seat by its seating, a fire by its nightly fire (the hearth and the campfire, lit or cold;
## a torch is a light only) and a food store by storage that takes food.
static func piece_things(def: Dictionary) -> Array[String]:
	var found: Array[String] = []
	if def.has("dining_surface_height"): found.append("tables")
	if def.has("seating_chair"): found.append("seats")
	if def.has("nightly_fire"): found.append("fires")
	if "stockpile_food" in def.get("storage", {}).get("accepts", []): found.append("food_stores")
	return found


# ── A room's type ─────────────────────────────────────────────────────────────

## Sets the room's type and owner. `bed_owner` is the owner of the room's one bed; only a
## type that takes an owner keeps it.
func classify(room: Dictionary, bed_owner: int) -> void:
	room.owner_id = bed_owner
	room.room_type = "room"
	for kind: Dictionary in all:
		if missing(room, kind).is_empty():
			room.room_type = String(kind.id)
			break
	if not bool(kind_of(room).get("owner", false)): room.owner_id = -1


## The room's type from the data, or {} for a plain room.
func kind_of(room: Dictionary) -> Dictionary:
	var id := String(room.get("room_type", ""))
	for kind: Dictionary in all:
		if String(kind.id) == id: return kind
	return {}


## The counts a room's needs are measured in: whole beds, light sources and door pieces, and
## the pieces piece_things() names.
func counts(room: Dictionary) -> Dictionary:
	var held := {"beds": int(room.get("bed_count", 0)), "lights": int(room.get("light_count", 0)),
		"doors": room.get("door_cells", {}).size()}
	held.merge(room.get("things", {}))
	return held


## What a room still lacks to be a type: the ids of its unmet needs.
func missing(room: Dictionary, kind: Dictionary) -> Array[String]:
	var held := counts(room)
	var lacking: Array[String] = []
	var needs: Dictionary = kind.get("needs", {})
	for need: String in needs:
		var rule: Dictionary = needs[need]
		if need == "temperature":
			if not temperature_met(rule, float(room.get("temp_c", 0.0))): lacking.append(need)
			continue
		var count := int(held.get(need, 0))
		if count < int(rule.get("least", 0)) or (rule.has("most") and count > int(rule.most)): lacking.append(need)
	if bool(kind.get("owner", false)) and int(room.get("owner_id", -1)) < 0: lacking.append("owner")
	return lacking


## The type a room is measured against in the room window: its own; for a plain room the
## type it is on its way to (see the header); {} when it is on its way to none.
func nearest(room: Dictionary) -> Dictionary:
	var own := kind_of(room)
	if not own.is_empty(): return own
	var held := counts(room)
	var found := {}
	var fewest := 1 << 30
	for kind: Dictionary in all:
		if int(held.get(String(kind.get("key", "")), 0)) <= 0: continue
		var lacking := missing(room, kind).size()
		if lacking < fewest:
			found = kind
			fewest = lacking
	return found


## The types the room window lists: every type but those listed under another (a personal
## bedroom under the bedroom).
func listed() -> Array:
	return all.filter(func(kind: Dictionary) -> bool: return not kind.has("variant_of"))


## The id a type is listed under: its own, or the type it is a variant of.
static func listed_id(kind: Dictionary) -> String:
	return String(kind.get("variant_of", kind.get("id", "")))


# ── Temperature needs ─────────────────────────────────────────────────────────

func temperature_met(rule: Dictionary, temp_c: float) -> bool:
	if rule.has("above") and temp_c <= degrees(rule.above): return false
	if rule.has("below") and temp_c >= degrees(rule.below): return false
	if rule.has("at_most") and temp_c > degrees(rule.at_most): return false
	if rule.has("at_least") and temp_c < degrees(rule.at_least): return false
	return true


## A temperature need's bound in °C: a number, or a value named in temperature.json.
func degrees(value: Variant) -> float:
	return float(owner.temperature_config[value]) if value is String else float(value)


# ── Words ─────────────────────────────────────────────────────────────────────

## A need's goal as its row says it: "Needs 1", "Needs 2 or more", "Needs 1 to 3"; a
## temperature's is its range, kept short for the row: "0 to 16 °C", "0 °C or below".
func goal_words(need: String, rule: Dictionary) -> String:
	if need == "temperature":
		if rule.has("above") and rule.has("below"): return "%s to %s °C" % [_number(degrees(rule.above)), _number(degrees(rule.below))]
		return capital(range_words(rule))
	var least := int(rule.get("least", 0))
	if not rule.has("most"): return "Needs %d" % least if least <= 1 else "Needs %d or more" % least
	var most := int(rule.most)
	return "Needs %d" % least if most == least else "Needs %d to %d" % [least, most]


## A temperature need's range: "between 0 and 16 °C", "below 16 °C", "0 °C or below".
func range_words(rule: Dictionary) -> String:
	if rule.has("above") and rule.has("below"): return "between %s and %s °C" % [_number(degrees(rule.above)), _number(degrees(rule.below))]
	if rule.has("at_least") and rule.has("at_most"): return "%s to %s °C" % [_number(degrees(rule.at_least)), _number(degrees(rule.at_most))]
	if rule.has("below"): return "below %s °C" % _number(degrees(rule.below))
	if rule.has("at_most"): return "%s °C or below" % _number(degrees(rule.at_most))
	if rule.has("above"): return "above %s °C" % _number(degrees(rule.above))
	if rule.has("at_least"): return "%s °C or more" % _number(degrees(rule.at_least))
	return ""


## The steps from a room to a type, in words: "add a bed and a light", "add a food shelf and
## get it below 16 °C", "give the bed an owner"; "" when the room lacks nothing.
func steps_words(room: Dictionary, kind: Dictionary) -> String:
	var held := counts(room)
	var needs: Dictionary = kind.get("needs", {})
	var adds: Array[String] = []
	var rest: Array[String] = []
	for need: String in missing(room, kind):
		var words: Dictionary = things.get(need, {})
		if need == "temperature":
			rest.append(_temperature_step(needs[need], float(room.get("temp_c", 0.0))))
		elif not needs.has(need):
			rest.append(String(words.get("step", need)))
		else:
			var rule: Dictionary = needs[need]
			var count := int(held.get(need, 0))
			var short := int(rule.get("least", 0)) - count
			if short > 0: adds.append(_some(words, need, short))
			else: rest.append("take out " + _some(words, need, count - int(rule.most)))
	if not adds.is_empty(): rest.push_front("add " + list_words(adds))
	return list_words(rest)


## What a type needs, as a sentence: "One bed, a light and a door.", "A food shelf and a
## door, between 0 and 16 °C."
func needs_sentence(kind: Dictionary) -> String:
	var needs: Dictionary = kind.get("needs", {})
	var parts: Array[String] = []
	var warmth := ""
	for need: String in needs:
		var rule: Dictionary = needs[need]
		if need == "temperature":
			warmth = range_words(rule)
			continue
		var words: Dictionary = things.get(need, {})
		var one := String(words.get("full", words.get("a", need)))
		var many := String(words.get("many", need))
		var least := int(rule.get("least", 0))
		if not rule.has("most"): parts.append(one if least <= 1 else "%d or more %s" % [least, many])
		elif int(rule.most) != least: parts.append("%d to %d %s" % [least, int(rule.most), many])
		else: parts.append("one " + one.trim_prefix("an ").trim_prefix("a ") if least == 1 else "%d %s" % [least, many])
	var sentence := list_words(parts)
	if not warmth.is_empty(): sentence += ", %s%s" % ["at " if warmth.left(1).is_valid_int() or warmth.begins_with("−") else "", warmth]
	return capital(sentence) + "."


## "a", "a and b", "a, b and c".
static func list_words(words: Array) -> String:
	if words.size() <= 1: return "" if words.is_empty() else String(words[0])
	return ", ".join(PackedStringArray(words.slice(0, words.size() - 1))) + " and " + String(words[words.size() - 1])


static func capital(words: String) -> String:
	return words.left(1).to_upper() + words.substr(1)


## One of a thing by its article ("a bed"), or several by their count ("2 beds").
func _some(words: Dictionary, need: String, count: int) -> String:
	return String(words.get("a", need)) if count <= 1 else "%d %s" % [count, String(words.get("many", need))]


## The way to a temperature need from where the room is: "get it below 16 °C".
func _temperature_step(rule: Dictionary, temp_c: float) -> String:
	if rule.has("below") and temp_c >= degrees(rule.below): return "get it below %s °C" % _number(degrees(rule.below))
	if rule.has("at_most") and temp_c > degrees(rule.at_most): return "get it to %s °C or below" % _number(degrees(rule.at_most))
	if rule.has("above") and temp_c <= degrees(rule.above): return "get it above %s °C" % _number(degrees(rule.above))
	if rule.has("at_least") and temp_c < degrees(rule.at_least): return "get it to %s °C or more" % _number(degrees(rule.at_least))
	return ""


## A bound as the game writes it: "16", "7.5", "−2".
static func _number(value: float) -> String:
	return ("−" if value <= -0.05 else "") + ("%.1f" % absf(value)).trim_suffix(".0")
