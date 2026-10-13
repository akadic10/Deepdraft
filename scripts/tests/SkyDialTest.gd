extends "res://scripts/tests/WorkerCraftingTest.gd"

## Exercise live clock/weather/restoration and actual HUD input without touching
## saves. --capture additionally renders the real controls at supported sizes.
const OUT := "res://tmp/sky_dial_20261012/"

func _run() -> void:
	create_timer(60).timeout.connect(func(): push_error("Sky Dial timed out"); quit(1))
	await _setup_crafting_fixture()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var dial = dock._sky_dial
	var weather = root.get_node("WeatherManager")
	var sky = root.get_node("SkyController")
	var registry = root.get_node("UIRegistry")
	_expect(dial.get_canvas_layer_node().layer == 21, "permanent status has a separate HUD layer")
	_expect(not manager.has_window("clock"), "legacy clock window is no longer registered")
	for item in registry.get_menu("system").items:
		_expect(item.target != "clock", "Menu has no redundant clock shortcut")
	_expect(dial._frame != null and dial._symbols.size() == 9 and dial._landscapes.size() == 4, "all approved art assets load")
	for season in ["spring", "summer", "autumn", "winter"]:
		clock_node.restore_state({"year": 2, "season": season, "day": 1, "hour": 12.0, "speed": 1, "paused": true})
		dial.refresh()
		_expect(dial.state.season == season and dial.state.day == 1 and dial.state.year == 2, "restoring calendar refreshes " + season)
		_expect(is_equal_approx(dial.state.sunrise, sky.current_event_hours().sunrise) and is_equal_approx(dial.state.sunset, sky.current_event_hours().sunset), "HUD rise/set match world lighting")
		for id in ["clear", "overcast", "foggy", "snow"]:
			weather.set_weather("base:weather:" + id)
			dial.refresh()
			_expect(dial.state.weather_id == "base:weather:" + id and dial.tooltip_text.contains(weather.current_weather_name()), "actual weather is displayed: " + id)
	clock_node.restore_state({"year": 1, "season": "summer", "day": 1, "hour": 8.55, "speed": 1, "paused": false})
	weather.set_weather("base:weather:clear")
	dial.refresh()
	var summer_length: float = dial.state.sunset - dial.state.sunrise
	_expect(dial._time_label.text == "08:33" and dial.state.weather_symbol == "sun", "morning shows exact live time and sun")
	clock_node.set_paused(true)
	clock_node._process(60)
	dial.refresh()
	_expect(dial._time_label.text == "08:33" and dial.state.paused, "pause freezes display and cycle")
	clock_node.set_paused(false)
	clock_node.set_speed(2)
	clock_node._process(30)
	dial.refresh()
	_expect(dial._time_label.text == "09:33", "speed changes use the authoritative simulation clock")
	clock_node.restore_state({"year": 1, "season": "winter", "day": 1, "hour": 23.0, "speed": 1, "paused": true})
	weather.set_weather("base:weather:clear")
	dial.refresh()
	_expect(dial.state.weather_symbol == "moon" and not dial.state.is_day, "clear night shows moon")
	_expect(dial.state.sunset - dial.state.sunrise < summer_length, "winter daylight track is shorter")
	clock_node.hour = float(dial.state.sunrise)
	dial.refresh()
	_expect(dial.state.phase == "Dawn" and dial.state.daylight > 0 and dial.state.daylight < 1, "dawn blends day/night paintings")
	clock_node.hour = float(dial.state.sunset)
	dial.refresh()
	_expect(dial.state.phase == "Dusk" and not dial.state.is_day, "sunset switches the celestial marker")
	clock_node.restore_state({"year": 3, "season": "winter", "day": 28, "hour": 23.95, "speed": 1, "paused": true})
	clock_node.advance_hours(.1)
	dial.refresh()
	_expect(dial.state.season == "spring" and dial.state.day == 1 and dial.state.year == 4, "day/season/year rollover reaches the HUD")
	for viewport_size in [Vector2i(1280, 720), Vector2i(960, 540), Vector2i(2560, 1440)]:
		root.size = viewport_size
		await _frames(8)
		var bounds := Rect2(Vector2.ZERO, Vector2(viewport_size))
		_expect(bounds.encloses(dial.get_global_rect()), "dial fits " + str(viewport_size))
		_expect(is_equal_approx(dial.get_global_rect().end.x, viewport_size.x - 16), "dial anchors to top right")
		_expect(not dial.get_global_rect().intersects(dock._time_slice_hud.get_global_rect()), "time controls remain separate")
		dock._food_warning.set_process(false)
		dock._food_warning.label.text = "2 dwarves cannot find reachable food.\nHarvest berries or make stored food accessible."
		dock._food_warning.show()
		await _frames(3)
		_expect(not dial.get_global_rect().intersects(dock._food_warning.get_global_rect()), "food warning clears dial")
		_expect(bounds.encloses(dock._food_warning.get_global_rect()), "food warning fits")
		var inspector: UIWindow = manager.get_ui_window("time_weather_dev")
		inspector.show()
		inspector.position = Vector2(viewport_size.x - inspector.size.x - 16, 32)
		inspector.clamp_to_viewport()
		_expect(not dial.get_global_rect().intersects(inspector.get_global_rect()), "ordinary windows make room for the dial")
		inspector.hide()
		for example in [["summer", 1, 8.55, "clear"], ["autumn", 12, 17.75, "overcast"], ["winter", 6, 23.1667, "clear"], ["spring", 8, 12.0, "foggy"], ["winter", 12, 12.0, "snow"]]:
			clock_node.restore_state({"year": 1, "season": example[0], "day": example[1], "hour": example[2], "speed": 1, "paused": true})
			weather.set_weather("base:weather:" + example[3])
			dial.refresh()
			await _frames(4)
			await _capture_dial("%s_%s_%d" % [example[0], example[3], viewport_size.x])
		_click(dial.get_global_rect().get_center())
		await _frames(4)
		_expect(dial.has_focus() and dial._focus_info.visible, "click/focus reveals clock details")
		_expect(bounds.encloses(dial._focus_info.get_global_rect()), "focus detail fits viewport")
		_expect(not dial._focus_info.get_global_rect().intersects(dock._food_warning.get_global_rect()), "details do not conceal the food warning")
		await _capture_dial("details_%d" % viewport_size.x)
		dial.release_focus()
		_expect(not dial._focus_info.visible, "leaving focus dismisses details")
		_click(dock._speed_buttons[2].get_global_rect().get_center())
		_expect(not clock_node.paused and is_equal_approx(clock_node.speed, 2), "actual speed button still resumes")
		_click(dock._speed_buttons[0].get_global_rect().get_center())
		_expect(clock_node.paused, "actual pause button still works")
	for failure in failures: push_error(failure)
	print("SKY_DIAL_OK: art, weather, seasonal lighting, pause/speed, rollover/restoration, input and responsive HUD" if failures.is_empty() else "SKY_DIAL_FAIL")
	quit(0 if failures.is_empty() else 1)


func _capture_dial(filename: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + filename + ".png")
