extends Node

# ── Calendar state ────────────────────────────────────────────────────────────
# Authoritative time source for the entire simulation.
# All time-sensitive systems (flora growth, caravans, mood events, surface
# palette swaps, sky/day-night) read from these variables and signals — never
# maintain their own counters.
#
# Time scale (data/calendar/calendar.json; defaults from 11_overview.md):
#   1 in-game hour  = 60 real seconds  (at ×1 speed)  -> 1 in-game DAY = 24 real minutes
#   1 in-game day   = 24 hours
#   1 season        = 28 days
#   1 year          = 4 seasons = 112 days
#
# The clock now advances in _process(). Configuration (time scale, season order,
# start date, event times, day-length curve) is loaded from calendar.json — this
# autoload is that file's owning system, so it reads it directly (Registry Pattern).
# JSON = what things are (the numbers); GDScript = what things do (the ticking).

const CALENDAR_PATH := "res://data/calendar/calendar.json"

# ── Public calendar state (read-only to other systems) ────────────────────────
var day:    int    = 1         # 1–_days_per_season within the current season
var season: String = "summer"  # one of _season_order
var year:   int    = 1
var hour:   float  = 0.0       # 0.0–23.999… (24-hour clock)

# ── Speed / pause ─────────────────────────────────────────────────────────────
## Multiplies real time. 0 = frozen. 1 = ×1 (24-minute day). Set via set_speed().
var speed:  float = 1.0
var paused: bool  = false

# ── Configuration (loaded from calendar.json; values below are fallbacks) ──────
var _real_seconds_per_game_hour: float = 60.0
var _hours_per_day:  int = 24
var _days_per_season: int = 28
var _season_order: Array[String] = ["spring", "summer", "autumn", "winter"]
var _event_times:  Dictionary = {}   # name -> hour (for SkyController, later phases)
var _day_length:   Dictionary = {}   # mean_hours / amplitude_hours / *_solstice_doy

# ── Internal ──────────────────────────────────────────────────────────────────
var _last_hour_int: int = -1

## Fired once per whole in-game hour boundary (new_hour is 0–23).
## Sky/temperature systems connect here for hourly recomputes.
signal hour_changed(new_hour: int)

## Fired at the start of each new in-game day. Flora growth ticks connect here.
signal day_changed(new_day: int)

## Fired when the season advances. Systems that swap seasonal assets
## (surface block colors, flora meshes, caravan spawns) connect here.
signal season_changed(new_season: String)


func _ready() -> void:
	_load_config()
	_last_hour_int = int(floor(hour))
	print("WorldClock: year %d, %s, day %d, %s (1 day = %.0f real min)." % [
		year, season, day, time_string(),
		(_real_seconds_per_game_hour * float(_hours_per_day)) / 60.0,
	])


func _process(delta: float) -> void:
	if paused or speed <= 0.0:
		return

	# Advance the clock. delta is real seconds; convert to in-game hours.
	hour += (delta * speed) / _real_seconds_per_game_hour

	# Roll whole in-game days (handles huge deltas / high speed via the loop).
	while hour >= float(_hours_per_day):
		hour -= float(_hours_per_day)
		_advance_day()

	# Emit hour_changed only when we cross a whole-hour boundary.
	var cur_hour_int := int(floor(hour))
	if cur_hour_int != _last_hour_int:
		_last_hour_int = cur_hour_int
		hour_changed.emit(cur_hour_int)


# ── Rollover ──────────────────────────────────────────────────────────────────

func _advance_day() -> void:
	day += 1
	if day > _days_per_season:
		day = 1
		_advance_season()        # emits season_changed BEFORE the day_changed below
	day_changed.emit(day)


func _advance_season() -> void:
	var idx := _season_order.find(season)
	if idx < 0:
		idx = 0
	idx = (idx + 1) % _season_order.size()
	if idx == 0:
		year += 1                # wrapped past the last season -> new year
	season = _season_order[idx]
	season_changed.emit(season)


# ── Speed / pause control ─────────────────────────────────────────────────────

## Sets the time multiplier (e.g. 1.0, 2.0, 3.0). 0 freezes the clock.
func set_speed(new_speed: float) -> void:
	speed = maxf(0.0, new_speed)


func get_speed() -> float:
	return speed


func set_paused(value: bool) -> void:
	paused = value


## In-game hours that elapse per real second at the current speed (0 while
## paused). For agent behaviours timed in game hours outside this autoload
## (e.g. sleep-lite, doc 16 Phase 5) — they multiply their _process delta by
## this instead of tracking their own calendar (WorldClock stays authoritative).
func game_hours_per_real_second() -> float:
	if paused or speed <= 0.0:
		return 0.0
	return speed / _real_seconds_per_game_hour


func toggle_pause() -> void:
	paused = not paused


func serialize_state() -> Dictionary:
	return {
		"day": day,
		"season": season,
		"year": year,
		"hour": hour,
		"speed": speed,
		"paused": paused,
	}


func restore_state(state: Dictionary) -> void:
	day = clampi(int(state.get("day", 1)), 1, _days_per_season)
	var restored_season := String(state.get("season", "summer"))
	season = restored_season if _season_order.has(restored_season) else "summer"
	year = maxi(int(state.get("year", 1)), 1)
	hour = clampf(float(state.get("hour", 0.0)), 0.0, float(_hours_per_day) - 0.001)
	speed = maxf(float(state.get("speed", 1.0)), 0.0)
	paused = bool(state.get("paused", false))
	_last_hour_int = int(floor(hour))
	season_changed.emit(season)
	day_changed.emit(day)
	hour_changed.emit(_last_hour_int)


# ── Debug / testing helpers ───────────────────────────────────────────────────

## Advance the clock by a number of in-game hours, rolling days/seasons and firing
## hour_changed / day_changed / season_changed exactly like normal ticking. Used by the
## Clock window's "+1 Hour" test button.
func advance_hours(amount: float) -> void:
	if amount <= 0.0:
		return
	hour += amount
	while hour >= float(_hours_per_day):
		hour -= float(_hours_per_day)
		_advance_day()
	var cur_hour_int := int(floor(hour))
	if cur_hour_int != _last_hour_int:
		_last_hour_int = cur_hour_int
		hour_changed.emit(cur_hour_int)


## Jump straight to the next season (day and hour unchanged), firing season_changed and
## rolling the year on wrap. Used by the Clock window's "+1 Season" test button.
func advance_season() -> void:
	_advance_season()


# ── Public API ────────────────────────────────────────────────────────────────

## Current in-game time as a 24-hour "HH:MM" string (e.g. "08:30", "21:05").
func time_string() -> String:
	var h := int(floor(hour)) % _hours_per_day
	var m := int(floor((hour - floor(hour)) * 60.0))
	return "%02d:%02d" % [h, m]


## Returns the current season's growth rate multiplier for flora.
## Used by the farming system when processing growth ticks.
func growth_rate_multiplier() -> float:
	match season:
		"spring": return 1.2
		"summer": return 1.0
		"autumn": return 0.8
		"winter": return 0.0
	return 1.0


## Returns the day-of-year (0–111) for the current calendar position.
## Used by the cosine day-length curve in 11_overview.md §5.
func day_of_year() -> int:
	var season_index: int = _season_order.find(season)
	if season_index < 0:
		season_index = 0
	return season_index * _days_per_season + (day - 1)


## Returns daylight hours for a given day-of-year via the seasonal cosine
## (11_overview.md §5). Read-only helper; not yet consumed by any system —
## the day/night renderer (08_sky_plan.md phase 3) will use it.
func daylight_hours(doy: int) -> float:
	var mean:   float = float(_day_length.get("mean_hours", 12.0))
	var ampl:   float = float(_day_length.get("amplitude_hours", 4.0))
	var summer: float = float(_day_length.get("summer_solstice_doy", 28))
	var total:  float = float(_days_per_season * _season_order.size())
	if total <= 0.0:
		return mean
	var angle := (float(doy) - summer) / total * TAU
	# +cos: at the summer solstice (doy == summer) cos == 1 -> mean+ampl = LONGEST day.
	# (11_overview.md §5 prints this as "mean - ampl", which is inverted; +ampl is correct.)
	return mean + ampl * cos(angle)


## Returns the named time-of-day events (name -> hour) from calendar.json.
## SkyController keys its colour/fog curves against these (later phases).
func get_event_times() -> Dictionary:
	return _event_times


# ── Config loader ─────────────────────────────────────────────────────────────

func _load_config() -> void:
	var file := FileAccess.open(CALENDAR_PATH, FileAccess.READ)
	if file == null:
		push_warning("WorldClock: cannot open %s — using built-in defaults." % CALENDAR_PATH)
		return

	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_error("WorldClock: JSON parse error in %s — %s" % [CALENDAR_PATH, json.get_error_message()])
		file.close()
		return
	file.close()

	var d: Dictionary = json.data

	var ts: Dictionary = d.get("time_scale", {})
	_real_seconds_per_game_hour = float(ts.get("real_seconds_per_game_hour", _real_seconds_per_game_hour))
	_hours_per_day  = int(ts.get("hours_per_day",  _hours_per_day))
	_days_per_season = int(ts.get("days_per_season", _days_per_season))

	var order = d.get("season_order", [])
	if order is Array and not (order as Array).is_empty():
		_season_order.clear()
		for s in order:
			_season_order.append(String(s))

	var start: Dictionary = d.get("start", {})
	year   = int(start.get("year", year))
	season = String(start.get("season", season))
	day    = int(start.get("day", day))
	hour   = float(start.get("hour", hour))

	_event_times = d.get("event_times", {})
	_day_length  = d.get("day_length_curve", {})
