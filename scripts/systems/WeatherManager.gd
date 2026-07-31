extends Node

## Per-season weather scheduler. Picks a weather type each in-game day from the weighted table in
## data/calendar/weather_schedule.json, and hands the chosen weather to SkyController, which blends
## its sky overrides (fog density/distance), darkening, and vision multiplier into the day/night look.
##
## Registered as an autoload (project.godot [autoload]), loaded AFTER SkyController so it can call it.
## Mirrors Stonehearth's weather_service: plan-by-season, switch on a daily cadence, support a manual
## override. Draws use a seeded RNG (from the world seed) so a given world replays the same weather.
##
## JSON = what things are (weather defs + the weighted schedule); GDScript = what things do (picking,
## scheduling, applying).

const SCHEDULE_PATH := "res://data/calendar/weather_schedule.json"
const WEATHER_FILES := [
	"res://data/weather/clear.json",
	"res://data/weather/foggy.json",
	"res://data/weather/overcast.json",
	"res://data/weather/snow.json",
]

var _weather_by_id: Dictionary = {}   # id -> weather definition dict
var _ordered_ids: Array[String] = []  # load order, for the manual cycle button
var _schedule: Dictionary = {}        # season -> Array of { weather, weight }
var _rng := RandomNumberGenerator.new()

var _clock: Node = null
var _sky: Node = null
var _current_id: String = ""

@warning_ignore("unused_signal")  # connected by UI / future systems
signal weather_changed(weather_id: String)


func _ready() -> void:
	_load_weather_defs()
	_load_schedule()
	_clock = get_node_or_null("/root/WorldClock")
	_sky = get_node_or_null("/root/SkyController")
	# Wait one frame so SkyController has bound to the scene, then set initial weather.
	await get_tree().process_frame
	# Seed AFTER the await: WorldGenerator.world_seed is 0 during autoload
	# _ready and only gets set when WorldRenderer._ready (scene node, runs
	# after all autoloads but before the first process frame) calls
	# WorldGenerator.generate(). Seeding before the await always found 0 and
	# silently fell back to randomize(), breaking the same-seed-same-weather
	# contract documented in the header.
	_seed_rng()
	if _clock != null:
		if not _clock.is_connected("day_changed", _on_day_changed):
			_clock.connect("day_changed", _on_day_changed)
	_switch_weather_for_current_season()
	print("WeatherManager: ready (%d weather types, current = %s)." % [_ordered_ids.size(), _current_id])


# ── Loaders ───────────────────────────────────────────────────────────────────

func _load_weather_defs() -> void:
	for path in WEATHER_FILES:
		var d := _load_json(path)
		if d.is_empty():
			continue
		var id := String(d.get("id", ""))
		if id == "":
			push_warning("WeatherManager: %s has no 'id' — skipped." % path)
			continue
		_weather_by_id[id] = d
		_ordered_ids.append(id)


func _load_schedule() -> void:
	var d := _load_json(SCHEDULE_PATH)
	for season in d:
		if String(season).begins_with("__"):
			continue
		if d[season] is Array:
			_schedule[season] = d[season]


func _load_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("WeatherManager: cannot open %s." % path)
		return {}
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	file.close()
	if err != OK:
		push_error("WeatherManager: JSON parse error in %s — %s" % [path, json.get_error_message()])
		return {}
	if json.data is Dictionary:
		return json.data
	return {}


func _seed_rng() -> void:
	var seed_val := 0
	var wg := get_node_or_null("/root/WorldGenerator")
	if wg != null:
		seed_val = int(wg.get("world_seed"))
	if seed_val == 0:
		# Should not happen in the normal boot path (see _ready ordering note);
		# warn loudly so a silent determinism break can't sneak back in.
		push_warning("WeatherManager: world_seed unavailable — weather RNG randomized (non-deterministic).")
		_rng.randomize()
	else:
		_rng.seed = seed_val


# ── Scheduling ────────────────────────────────────────────────────────────────

func _on_day_changed(_new_day: int) -> void:
	_switch_weather_for_current_season()


func _switch_weather_for_current_season() -> void:
	var season := "summer"
	if _clock != null:
		season = String(_clock.get("season"))
	var id := _weather_for_season(season)
	if id != "":
		_apply(id)


func _weather_for_season(season: String) -> String:
	var entries = _schedule.get(season, [])
	if not (entries is Array) or (entries as Array).is_empty():
		return _ordered_ids[0] if not _ordered_ids.is_empty() else ""
	var total := 0.0
	for e in entries:
		total += float(e.get("weight", 0.0))
	if total <= 0.0:
		return _ordered_ids[0] if not _ordered_ids.is_empty() else ""
	var r := _rng.randf() * total
	var acc := 0.0
	for e in entries:
		acc += float(e.get("weight", 0.0))
		if r <= acc:
			return String(e.get("weather", ""))
	return String((entries as Array).back().get("weather", ""))


# ── Apply ─────────────────────────────────────────────────────────────────────

func _apply(id: String) -> void:
	if not _weather_by_id.has(id):
		push_warning("WeatherManager: unknown weather id '%s'." % id)
		return
	_current_id = id
	if _sky != null and _sky.has_method("apply_weather"):
		_sky.call("apply_weather", _weather_by_id[id])
	weather_changed.emit(id)


# ── Public API ────────────────────────────────────────────────────────────────

## Force a specific weather id (used for testing / scripted events).
func set_weather(id: String) -> void:
	_apply(id)


## Advance to the next weather type in load order — wired to the Clock window's test button.
func cycle_weather() -> void:
	if _ordered_ids.is_empty():
		return
	var idx := _ordered_ids.find(_current_id)
	idx = (idx + 1) % _ordered_ids.size()
	_apply(_ordered_ids[idx])


func current_weather_id() -> String:
	return _current_id


func serialize_state() -> Dictionary:
	return {
		"current_id": _current_id,
		"rng_state": _rng.state,
	}


func restore_state(state: Dictionary) -> void:
	var id := String(state.get("current_id", ""))
	if _weather_by_id.has(id):
		_apply(id)
	if state.has("rng_state"):
		_rng.state = int(state["rng_state"])


func current_weather_name() -> String:
	if _weather_by_id.has(_current_id):
		return String(_weather_by_id[_current_id].get("display_name", _current_id))
	return "—"
