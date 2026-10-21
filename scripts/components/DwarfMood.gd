extends RefCounted

## Actual sleeping time earns comfort thoughts, never walking/settling time.
## Exposure and memories use game hours and survive mid-sleep saves.
var config: Dictionary
var personal_sleep_hours := 0.0
var bedroom_memory_hours := 0.0
var thermal_hours := {"cold":0.0,"chilly":0.0,"hot":0.0}
var thermal_memory := {"cold":0.0,"chilly":0.0,"hot":0.0}
var food: RefCounted
var dining_outcome := ""
var dining_memory_hours := 0.0
var recreation_memory_hours := 0.0
var solo_recreation_memory_hours := 0.0
var recreation_retry_hours := 0.0

func _init() -> void:
	config = TaskManager.get_config_section("mood")

func tick(hours: float) -> void:
	recreation_memory_hours = maxf(0.0,recreation_memory_hours-hours)
	solo_recreation_memory_hours = maxf(0.0,solo_recreation_memory_hours-hours)
	recreation_retry_hours = maxf(0.0,recreation_retry_hours-hours)
	dining_memory_hours = maxf(0.0,dining_memory_hours-hours)
	bedroom_memory_hours = maxf(0.0,bedroom_memory_hours-hours)
	for kind: String in thermal_memory: thermal_memory[kind] = maxf(0.0,float(thermal_memory[kind])-hours)

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

func finish_sleep() -> void:
	if personal_sleep_hours >= float(config.personal_bedroom.minimum_sleep_hours):
		bedroom_memory_hours = float(config.personal_bedroom.duration_hours)
	personal_sleep_hours = 0.0

func value() -> float:
	return clampf(float(config.baseline)+(float(config.personal_bedroom.bonus) if bedroom_memory_hours>0 else 0.0)+_recreation_bonus()-_thermal_penalty()-_dining_penalty()-(food.mood_penalty() if food != null else 0.0),0.0,1.0)

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


func strongest_negative_thought() -> Dictionary:
	var strongest := {}
	var amount := 0.0
	if food != null and food.mood_penalty()>amount:
		amount = food.mood_penalty()
		strongest = {"reason":"Famished" if food.famished() else "Hungry","help":"Keep harvested food accessible."}
	if _dining_penalty()>amount:
		amount = _dining_penalty()
		strongest = {"reason":{"seat_only":"Ate without a table","table_only":"Ate standing up","neither":"Ate without a proper place"}[dining_outcome],
			"help":"Provide a seat beside a table. The memory will fade over time."}
	for kind: String in thermal_memory:
		var penalty := float(config.thermal[kind+"_penalty"])
		if float(thermal_memory[kind])<=0 or penalty<=amount: continue
		amount = penalty
		strongest = {"reason":{"cold":"Slept in the cold","chilly":"Chilly sleep","hot":"Slept in the heat"}[kind],
			"help":"Reduce heating in the sleeping room. The memory will fade over time." if kind=="hot" else "Warm the sleeping room with a hearth. The memory will fade over time."}
	return strongest

func describe() -> Dictionary:
	var thoughts: PackedStringArray = []
	if recreation_memory_hours>0:
		thoughts.append("Played a board game with a friend · +%d happiness\n%.1f game hours remaining" % [roundi(float(config.recreation.bonus)*100),recreation_memory_hours])
	elif solo_recreation_memory_hours>0:
		thoughts.append("Played a board game on my own · +%d happiness\n%.1f game hours remaining" % [roundi(float(config.recreation.solo_bonus)*100),solo_recreation_memory_hours])
	if food != null and food.hungry():
		thoughts.append("%s · −%d happiness\nWork speed −%d%% until fed" % ["Famished" if food.famished() else "Hungry",roundi(food.mood_penalty()*100),roundi((1.0-food.work_multiplier())*100)])
	if _dining_penalty()>0:
		thoughts.append("%s · −%d happiness\n%.1f game hours remaining" % [{"seat_only":"Ate without a table","table_only":"Ate standing up","neither":"Ate without a proper place"}[dining_outcome],roundi(_dining_penalty()*100),dining_memory_hours])
	if bedroom_memory_hours>0:
		thoughts.append("Slept in my own bedroom · +%d happiness\n%.1f game hours remaining" % [roundi(float(config.personal_bedroom.bonus)*100),bedroom_memory_hours])
	for kind: String in thermal_memory:
		if float(thermal_memory[kind])<=0 or not is_equal_approx(float(config.thermal[kind+"_penalty"]),_thermal_penalty()): continue
		thoughts.append("%s · −%d happiness\n%.1f game hours remaining" % [{"cold":"Slept in the cold","chilly":"Chilly sleep","hot":"Slept in the heat"}[kind],roundi(_thermal_penalty()*100),float(thermal_memory[kind])])
		break
	return {"value":value(),"label":"Unhappy" if value()<float(config.baseline) else ("Happy" if value()>float(config.baseline) else "Content"),
		"thought":"\n\n".join(thoughts) if not thoughts.is_empty() else "No recent comfort thoughts."}

func serialize() -> Dictionary:
	var data := {"personal_sleep_hours":personal_sleep_hours,"bedroom_memory_hours":bedroom_memory_hours,"dining_outcome":dining_outcome,"dining_memory_hours":dining_memory_hours}
	data.recreation_memory_hours = recreation_memory_hours
	if solo_recreation_memory_hours>0: data.solo_recreation_memory_hours = solo_recreation_memory_hours
	data.recreation_retry_hours = recreation_retry_hours
	for kind: String in thermal_hours:
		data[kind+"_sleep_hours"] = thermal_hours[kind]
		data[kind+"_memory_hours"] = thermal_memory[kind]
	return data

func restore(data: Dictionary) -> void:
	recreation_memory_hours = clampf(float(data.get("recreation_memory_hours",0.0)),0.0,float(config.recreation.duration_hours))
	solo_recreation_memory_hours = clampf(float(data.get("solo_recreation_memory_hours",0.0)),0.0,float(config.recreation.duration_hours))
	recreation_retry_hours = clampf(float(data.get("recreation_retry_hours",0.0)),0.0,float(TaskManager.get_config_section("recreation").cooldown_hours))
	dining_outcome = String(data.get("dining_outcome",""))
	dining_memory_hours = clampf(float(data.get("dining_memory_hours",0.0)),0.0,float(config.dining.duration_hours))
	personal_sleep_hours = clampf(float(data.get("personal_sleep_hours",0.0)),0.0,DwarfAgent.SLEEP_HOURS)
	bedroom_memory_hours = clampf(float(data.get("bedroom_memory_hours",0.0)),0.0,float(config.personal_bedroom.duration_hours))
	for kind: String in thermal_hours:
		thermal_hours[kind] = clampf(float(data.get(kind+"_sleep_hours",0.0)),0.0,DwarfAgent.SLEEP_HOURS)
		thermal_memory[kind] = clampf(float(data.get(kind+"_memory_hours",0.0)),0.0,float(config.thermal.duration_hours))
