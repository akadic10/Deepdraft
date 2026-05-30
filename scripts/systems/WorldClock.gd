extends Node

# ── Calendar state ────────────────────────────────────────────────────────────
# Authoritative time source for the entire simulation.
# All time-sensitive systems (flora growth, caravans, mood events, surface
# palette swaps) read from these variables — never maintain their own counters.
#
# Time scale (from 11_overview.md):
#   1 in-game hour  = 60 real seconds  (at ×1 speed)
#   1 in-game day   = 24 hours
#   1 season        = 28 days
#   1 year          = 4 seasons = 112 days
#
# NOTE: Timer advancement is NOT implemented yet.
# _process() is intentionally absent. The clock is a static stub until the
# task system and simulation loop are built. Signals are declared now so other
# systems can connect to them without requiring changes later.

var day:    int    = 1         # 1–28 within the current season
var season: String = "summer"  # "spring" | "summer" | "autumn" | "winter"
var year:   int    = 1
var hour:   float  = 0.0       # 0.0–23.99

## Fired when the season advances. Systems that swap seasonal assets
## (surface block colors, flora meshes, caravan spawns) connect here.
@warning_ignore("unused_signal")  # connected by seasonal-asset systems (not built yet)
signal season_changed(new_season: String)

## Fired at the start of each new in-game day. Flora growth ticks connect here.
@warning_ignore("unused_signal")  # connected by the flora growth tick (not built yet)
signal day_changed(new_day: int)

# ── Season ordering ───────────────────────────────────────────────────────────
const SEASONS: Array[String] = ["spring", "summer", "autumn", "winter"]
const DAYS_PER_SEASON: int   = 28


func _ready() -> void:
	print("WorldClock: year %d, %s, day %d." % [year, season, day])


# ── Public API ────────────────────────────────────────────────────────────────

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
	var season_index: int = SEASONS.find(season)
	return season_index * DAYS_PER_SEASON + (day - 1)
