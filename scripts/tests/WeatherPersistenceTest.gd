extends SceneTree

## Compare uninterrupted daily weather with JSON save/load, through every
## season and a year boundary. No world generation or player save I/O.
var failures: Array[String] = []
var weather
var calendar


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	for id in ["SaveManager", "WorldClock", "SkyController", "WeatherManager", "TaskManager", "RoomManager", "StockpileManager"]:
		root.get_node(id).set_process(false)
	root.get_node("WorldGenerator").world_seed = 1234
	# Let the weather autoload finish its deferred initial seeding first.
	await process_frame
	await process_frame
	weather = root.get_node("WeatherManager")
	calendar = root.get_node("WorldClock")
	var positive_large := false
	var negative_large := false
	var cases := 0
	for world_seed in [1, 1234, 99991, 2147483647]:
		for warmup in [0, 7, 93]:
			calendar.restore_state({"day": 28, "season": "winter", "year": 3, "hour": 23.5, "paused": true})
			weather._rng.seed = world_seed
			for day in range(warmup): weather._weather_for_season("winter")
			weather.set_weather("base:weather:foggy")
			var exact_state: int = weather._rng.state
			positive_large = positive_large or exact_state > 9007199254740992
			negative_large = negative_large or exact_state < -9007199254740992
			var checkpoint: Dictionary = JSON.parse_string(JSON.stringify({
				"clock": calendar.serialize_state(), "weather": weather.serialize_state()}))
			var label := "seed %d after %d draws" % [world_seed, warmup]
			var expected := _advance_year()
			# Match SaveManager's restore order: the clock emits a day change,
			# then weather restoration must replace that incidental random draw.
			calendar.restore_state(checkpoint.clock)
			weather.restore_state(checkpoint.weather)
			_expect(weather._rng.state == exact_state, label + ": exact 64-bit state survives JSON")
			_expect(weather.current_weather_id() == "base:weather:foggy", label + ": current weather survives restore")
			var actual := _advance_year()
			_expect(actual == expected, label + ": next 112 daily weather choices and RNG states match")
			# Reusing a save repeatedly must not draw or drift the stream.
			for reload_index in range(3):
				calendar.restore_state(checkpoint.clock)
				weather.restore_state(checkpoint.weather)
				_expect(weather._rng.state == exact_state, label + ": repeated load retains exact state")
			cases += 1
	_expect(positive_large and negative_large, "fixtures cover both signs beyond JSON's exact integer range")
	print("WEATHER_PERSISTENCE_TEST: ", JSON.stringify({"cases": cases, "days_per_case": 112, "failures": failures}))
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)


func _advance_year() -> Array:
	var result: Array = []
	for day in range(112):
		calendar.advance_hours(24)
		result.append([calendar.season, calendar.day, weather.current_weather_id(), weather._rng.state])
	return result


func _expect(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
