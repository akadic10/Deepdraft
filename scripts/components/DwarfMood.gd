extends RefCounted

## Actual sleeping time earns comfort thoughts, never walking/settling time.
## Exposure and memories use game hours and survive mid-sleep saves.
## Room thoughts (doc 41): a sleep, a meal or a game in a sealed room leaves the room's
## appeal word for a while (horrid, pleasant or beautiful; plain leaves none), and the next
## of each replaces it. Their hours are room_appeal's slept_hours, ate_hours and played_hours.
## The word is the room as this dwarf feels it: their found tastes (DwarfTastes) count, and
## the thought names the strongest ("Slept in a pleasant room · loves the log bed").
const ROOM_ACTIVITIES := {"slept": "Slept", "ate": "Ate", "played": "Played"}
const ROOM_HOURS := {"slept": "slept_hours", "ate": "ate_hours", "played": "played_hours"}
var config: Dictionary
var personal_sleep_hours := 0.0
var bedroom_memory_hours := 0.0
var thermal_hours := {"cold":0.0,"chilly":0.0,"hot":0.0}
var thermal_memory := {"cold":0.0,"chilly":0.0,"hot":0.0}
var food: RefCounted
var tastes: RefCounted   # DwarfTastes, the dwarf's own
var dining_outcome := ""
var dining_memory_hours := 0.0
var recreation_memory_hours := 0.0
var solo_recreation_memory_hours := 0.0
var recreation_retry_hours := 0.0
var room_words := {"slept": "", "ate": "", "played": ""}   # activity -> the room's word, lower case
var room_hours := {"slept": 0.0, "ate": 0.0, "played": 0.0}
var room_tastes := {"slept": "", "ate": "", "played": ""}   # activity -> the taste its thought names

func _init() -> void:
	config = TaskManager.get_config_section("mood")

func tick(hours: float) -> void:
	recreation_memory_hours = maxf(0.0,recreation_memory_hours-hours)
	solo_recreation_memory_hours = maxf(0.0,solo_recreation_memory_hours-hours)
	recreation_retry_hours = maxf(0.0,recreation_retry_hours-hours)
	dining_memory_hours = maxf(0.0,dining_memory_hours-hours)
	bedroom_memory_hours = maxf(0.0,bedroom_memory_hours-hours)
	for kind: String in thermal_memory: thermal_memory[kind] = maxf(0.0,float(thermal_memory[kind])-hours)
	for activity: String in room_hours: room_hours[activity] = maxf(0.0,float(room_hours[activity])-hours)

func begin_sleep() -> void:
	personal_sleep_hours = 0.0
	for kind: String in thermal_hours: thermal_hours[kind] = 0.0

func record_sleep(hours: float, personal_room: bool, temperature_c := 20.0) -> void:
	if personal_room: personal_sleep_hours += hours
	var kind := RoomManager.comfort_label(temperature_c).to_lower()
	if not thermal_hours.has(kind): return
	thermal_hours[kind] += hours
	if float(thermal_hours[kind])>=float(config.thermal.minimum_sleep_hours):
		thermal_memory[kind] = float(config.thermal.duration_hours)

## `appeal` is the room the dwarf slept in (RoomManager.appeal_at), or {} outside rooms.
func finish_sleep(appeal := {}) -> void:
	if personal_sleep_hours >= float(config.personal_bedroom.minimum_sleep_hours):
		bedroom_memory_hours = float(config.personal_bedroom.duration_hours)
	personal_sleep_hours = 0.0
	record_room("slept", appeal)

func value() -> float:
	return clampf(float(config.baseline)+(float(config.personal_bedroom.bonus) if bedroom_memory_hours>0 else 0.0)+_recreation_bonus()-_thermal_penalty()-_dining_penalty()-(food.mood_penalty() if food != null else 0.0)+_room_bonus(),0.0,1.0)

## After a sleep, a meal or a game: the room's appeal (RoomManager.appeal_at), or {} outside
## rooms, felt through the dwarf's found tastes. A word that gives nothing (Plain), or no
## room, ends the last memory of it.
func record_room(activity: String, appeal: Dictionary) -> void:
	var felt: Dictionary = tastes.felt(appeal) if tastes != null and not appeal.is_empty() else {"word": appeal.get("word", {}), "taste": ""}
	var word: Dictionary = felt.word
	var gives := not word.is_empty() and not is_zero_approx(float(word.get("points", 0.0)))
	room_words[activity] = String(word.word).to_lower() if gives else ""
	room_hours[activity] = float(config.room_appeal[ROOM_HOURS[activity]]) if gives else 0.0
	room_tastes[activity] = String(felt.taste) if gives else ""

func _room_bonus() -> float:
	var total := 0.0
	for activity: String in ROOM_ACTIVITIES: total += _room_points(activity)
	return total

## The points of the word an activity's memory holds (appeal.json), while it lasts.
func _room_points(activity: String) -> float:
	if float(room_hours[activity]) <= 0.0: return 0.0
	for entry: Dictionary in RoomManager.appeal_config.get("words", []):
		if String(entry.word).to_lower() == String(room_words[activity]): return float(entry.points)
	return 0.0

func _recreation_bonus() -> float:
	return maxf(float(config.recreation.bonus) if recreation_memory_hours>0 else 0.0,
		float(config.recreation.solo_bonus) if solo_recreation_memory_hours>0 else 0.0)

func record_recreation(together := true) -> void:
	# Separate timers prevent solo play from downgrading or extending an earned
	# social memory. Only the strongest current recreation thought contributes.
	if together: recreation_memory_hours = float(config.recreation.duration_hours)
	else: solo_recreation_memory_hours = float(config.recreation.duration_hours)

func record_dining(outcome: String) -> void:
	dining_outcome = outcome
	dining_memory_hours = 0.0 if outcome == "proper" else float(config.dining.duration_hours)

func _dining_penalty() -> float:
	return float(config.dining.get(dining_outcome,0.0)) if dining_memory_hours>0 else 0.0

func _thermal_penalty() -> float:
	var penalty := 0.0
	for kind: String in thermal_memory:
		if float(thermal_memory[kind])>0: penalty = maxf(penalty,float(config.thermal[kind+"_penalty"]))
	return penalty


## The thoughts that count toward happiness now (doc 261), as rows: a stable id (the
## journal's topic and its lines' key), the words, the happiness points (+ or −), the game
## hours left (−1 while it lasts until the dwarf eats), how many hours ago it came, what
## helps a bad one, and any other effect.
func thoughts() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if recreation_memory_hours>0:
		rows.append(_thought("recreation_together","Played a board game with a friend",float(config.recreation.bonus),recreation_memory_hours,float(config.recreation.duration_hours)))
	elif solo_recreation_memory_hours>0:
		rows.append(_thought("recreation_alone","Played a board game on my own",float(config.recreation.solo_bonus),solo_recreation_memory_hours,float(config.recreation.duration_hours)))
	if food != null and food.hungry():
		var hunger := _thought("famished" if food.famished() else "hungry","Famished" if food.famished() else "Hungry",-food.mood_penalty(),-1.0,0.0,"Keep harvested food accessible.")
		hunger.effect = "Work speed −%d%% until fed" % roundi((1.0-food.work_multiplier())*100)
		rows.append(hunger)
	if _dining_penalty()>0:
		rows.append(_thought("dining_"+dining_outcome,{"seat_only":"Ate without a table","table_only":"Ate standing up","neither":"Ate without a proper place"}[dining_outcome],
			-_dining_penalty(),dining_memory_hours,float(config.dining.duration_hours),"Provide a seat beside a table. The memory will fade over time."))
	if bedroom_memory_hours>0:
		rows.append(_thought("bedroom","Slept in my own bedroom",float(config.personal_bedroom.bonus),bedroom_memory_hours,float(config.personal_bedroom.duration_hours)))
	for kind: String in thermal_memory:
		if float(thermal_memory[kind])<=0 or not is_equal_approx(float(config.thermal[kind+"_penalty"]),_thermal_penalty()): continue
		rows.append(_thought(kind,{"cold":"Slept in the cold","chilly":"Chilly sleep","hot":"Slept in the heat"}[kind],-_thermal_penalty(),
			float(thermal_memory[kind]),float(config.thermal.duration_hours),
			"Reduce heating in the sleeping room. The memory will fade over time." if kind=="hot" else "Warm the sleeping room with a hearth. The memory will fade over time."))
		break
	for activity: String in ROOM_ACTIVITIES:
		var points := _room_points(activity)
		if is_zero_approx(points): continue
		var word := String(room_words[activity])
		var taste := String(room_tastes[activity])
		var text := "%s in a %s room" % [ROOM_ACTIVITIES[activity], word]
		if not taste.is_empty() and tastes != null: text += " · " + tastes.describe(taste)
		rows.append(_thought("%s_%s" % [activity, word], text, points,
			float(room_hours[activity]), float(config.room_appeal[ROOM_HOURS[activity]]),
			"Furnish the room, and clear loose goods and stores out of it. The memory will fade over time." if points < 0 else ""))
	return rows

func _thought(id: String, text: String, amount: float, hours: float, duration: float, help := "") -> Dictionary:
	return {"id":id,"text":text,"points":roundi(amount*100),"hours":hours,"age":maxf(0.0,duration-hours) if hours>=0 else 0.0,"help":help,"effect":""}

## Happiness on the sheet's 0-100 scale.
func points() -> int:
	return roundi(value()*100)

## Happiness as one of five steps (doc 261): its place on the scale (0 Miserable to
## 4 Joyful), its word, its line and its face.
func step() -> Dictionary:
	var steps: Array = config.steps
	for i in range(steps.size()):
		var entry: Dictionary = steps[i]
		if i == steps.size()-1 or points() <= int(entry.most):
			return {"index":i,"word":String(entry.word),"line":String(entry.line),"icon":String(entry.icon)}
	return {}

## The two lowest steps, Unhappy and Miserable: the face shows over the dwarf's head.
func unhappy() -> bool:
	return int(step().index) < 2

func strongest_negative_thought() -> Dictionary:
	var strongest := {}
	for thought: Dictionary in thoughts():
		if int(thought.points) < int(strongest.get("points",0)): strongest = thought
	return {} if strongest.is_empty() else {"reason":strongest.text,"help":strongest.help}

func describe() -> Dictionary:
	var lines: PackedStringArray = []
	for thought: Dictionary in thoughts():
		var points := int(thought.points)
		lines.append("%s · %s%d happiness\n%s" % [thought.text,"+" if points>0 else "−",absi(points),
			thought.effect if float(thought.hours)<0 else "%.1f game hours remaining" % float(thought.hours)])
	return {"value":value(),"label":step().word,"thought":"\n\n".join(lines) if not lines.is_empty() else "No recent comfort thoughts."}

func serialize() -> Dictionary:
	var data := {"personal_sleep_hours":personal_sleep_hours,"bedroom_memory_hours":bedroom_memory_hours,"dining_outcome":dining_outcome,"dining_memory_hours":dining_memory_hours}
	data.recreation_memory_hours = recreation_memory_hours
	if solo_recreation_memory_hours>0: data.solo_recreation_memory_hours = solo_recreation_memory_hours
	data.recreation_retry_hours = recreation_retry_hours
	for kind: String in thermal_hours:
		data[kind+"_sleep_hours"] = thermal_hours[kind]
		data[kind+"_memory_hours"] = thermal_memory[kind]
	for activity: String in ROOM_ACTIVITIES:
		data[activity+"_room"] = room_words[activity]
		data[activity+"_room_hours"] = room_hours[activity]
		data[activity+"_room_taste"] = room_tastes[activity]
	return data

func restore(data: Dictionary) -> void:
	recreation_memory_hours = clampf(float(data.recreation_memory_hours),0.0,float(config.recreation.duration_hours))
	solo_recreation_memory_hours = clampf(float(data.get("solo_recreation_memory_hours",0.0)),0.0,float(config.recreation.duration_hours))
	recreation_retry_hours = clampf(float(data.recreation_retry_hours),0.0,float(TaskManager.get_config_section("recreation").cooldown_hours))
	dining_outcome = String(data.dining_outcome)
	dining_memory_hours = clampf(float(data.dining_memory_hours),0.0,float(config.dining.duration_hours))
	personal_sleep_hours = clampf(float(data.personal_sleep_hours),0.0,DwarfAgent.SLEEP_HOURS)
	bedroom_memory_hours = clampf(float(data.bedroom_memory_hours),0.0,float(config.personal_bedroom.duration_hours))
	for kind: String in thermal_hours:
		thermal_hours[kind] = clampf(float(data[kind+"_sleep_hours"]),0.0,DwarfAgent.SLEEP_HOURS)
		thermal_memory[kind] = clampf(float(data[kind+"_memory_hours"]),0.0,float(config.thermal.duration_hours))
	# A word appeal.json no longer has leaves no memory.
	var words := RoomManager.appeal_word_ids()
	for activity: String in ROOM_ACTIVITIES:
		var word := str(data.get(activity+"_room",""))
		room_words[activity] = word if words.has(word) else ""
		room_hours[activity] = 0.0 if room_words[activity] == "" else clampf(float(data.get(activity+"_room_hours",0.0)),0.0,float(config.room_appeal[ROOM_HOURS[activity]]))
		# Only a taste the dwarf has found can be named.
		var taste := str(data.get(activity+"_room_taste",""))
		room_tastes[activity] = taste if tastes != null and tastes.found.has(taste) and room_words[activity] != "" else ""
