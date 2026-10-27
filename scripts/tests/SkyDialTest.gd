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
	_expect(dial._layers.size() == 19 and dial._layers.has("frame") and dial._layers.has("sun") and dial._layers.has("moon"),
		"every layer of the sky window loads (%d)" % dial._layers.size())
	_expect(dial._plate.position.y >= dial.picture_height(dial.size.x) and is_equal_approx(dial.size.y, dial.height_for(dial.size.x)),
		"the plate sits under the window, inside the dial")
	for season in ["spring", "summer", "autumn", "winter"]:
		clock_node.restore_state({"year": 2, "season": season, "day": 1, "hour": 12.0, "speed": 1, "paused": true})
		dial.refresh()
		_expect(dial.state.season == season and dial.state.day == 1 and dial.state.year == 2, "restoring calendar refreshes " + season)
		_expect(is_equal_approx(dial.state.sunrise, sky.current_event_hours().sunrise) and is_equal_approx(dial.state.sunset, sky.current_event_hours().sunset), "HUD rise/set match world lighting")
		_expect(dial._layers.has("hills_" + season) and dial._date_label.text == season.capitalize() + " 1" and dial._bar.season == season
			and dial._left_label.text == "28 days to " + String(dial.state.next_season), "the window shows %s's land, and the plate its first day" % season)
		for id in ["clear", "overcast", "foggy", "snow", "rain", "storm"]:
			weather.set_weather("base:weather:" + id)
			dial.refresh()
			_expect(dial.state.weather_id == "base:weather:" + id and dial.tooltip_text.contains(weather.current_weather_name()), "actual weather is displayed: " + id)
			# Grey weather greys the noon sky and hides the sun, but fog lets it through.
			_expect(dial.state.grey == (id != "clear") and dial.state.sky[0] == ("day" if id == "clear" else "grey")
				and dial.state.body_shown == (id in ["clear", "foggy"]), "noon in %s: sky %s, sun shown %s" % [id, dial.state.sky[0], dial.state.body_shown])
	clock_node.restore_state({"year": 1, "season": "summer", "day": 1, "hour": 8.55, "speed": 1, "paused": false})
	weather.set_weather("base:weather:clear")
	dial.refresh()
	var summer_length: float = dial.state.sunset - dial.state.sunrise
	_expect(dial._time_label.text == "08:33" and dial.state.body == "sun", "morning shows exact live time and sun")
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
	_expect(dial.state.body == "moon" and dial.state.body_shown and not dial.state.is_day and dial.state.sky == ["night", "night", 0.0], "clear night shows the moon in a night sky")
	_expect(dial.state.sunset - dial.state.sunrise < summer_length, "winter daylight track is shorter")
	weather.set_weather("base:weather:snow")
	dial.refresh()
	_expect(dial.state.body == "moon" and dial.state.body_shown, "a snowy night still shows the moon behind its clouds")
	weather.set_weather("base:weather:clear")
	var events: Dictionary = sky.current_event_hours()
	clock_node.hour = (float(events.sunrise_start) + float(events.sunrise)) * 0.5
	dial.refresh()
	_expect(dial.state.phase == "Dawn" and dial.state.sky[0] == "night" and dial.state.sky[1] == "dawn" and absf(float(dial.state.sky[2]) - 0.5) < 0.01,
		"before sunrise the night sky fades into dawn's, at the world's anchors")
	# The sun climbs from the left at sunrise, over the top at midday, to the right at sunset.
	var places: Array = []
	for hour: float in [float(dial.state.sunrise) + 0.01, (float(dial.state.sunrise) + float(dial.state.sunset)) * 0.5, float(dial.state.sunset) - 0.01]:
		clock_node.hour = hour
		dial.refresh()
		places.append(float(dial.state.body_t))
	_expect(dial.state.body == "sun" and places[0] < 0.01 and absf(places[1] - 0.5) < 0.01 and places[2] > 0.99, "the sun crosses from sunrise to sunset: %s" % [places])
	clock_node.hour = float(dial.state.sunrise)
	dial.refresh()
	_expect(dial.state.phase == "Dawn" and dial.state.sky[0] == "dawn" and dial.state.sky[1] == "day", "after sunrise dawn's sky fades into the day's")
	clock_node.hour = float(dial.state.sunset)
	dial.refresh()
	_expect(dial.state.phase == "Dusk" and not dial.state.is_day and dial.state.body == "moon" and float(dial.state.body_t) < 0.01,
		"at sunset the moon rises on the left")
	clock_node.restore_state({"year": 1, "season": "autumn", "day": 28, "hour": 12.0, "speed": 1, "paused": true})
	dial.refresh()
	_expect(dial._left_label.text == "1 day to winter" and dial._bar.day == 28, "the season's last day says one day to the next")
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
		for rect: Rect2 in dock._time_slice_hud.occupied_rects():
			_expect(not dial.get_global_rect().intersects(rect), "time controls remain separate")
		var time_rect: Rect2 = dock._time_slice_hud.time_panel.get_global_rect()
		_expect(time_rect.position.y >= dial.get_global_rect().end.y and absf(time_rect.get_center().x - dial.get_global_rect().get_center().x) < 1.0,
			"pause and speed hang centred under the dial (doc 259)")
		var inspector: UIWindow = manager.get_ui_window("time_weather_dev")
		inspector.show()
		inspector.position = Vector2(viewport_size.x - inspector.size.x - 16, 32)
		inspector.clamp_to_viewport()
		_expect(not dial.get_global_rect().intersects(inspector.get_global_rect()), "ordinary windows make room for the dial")
		inspector.hide()
		for example in [["summer", 1, 8.55, "clear"], ["autumn", 12, 17.75, "overcast"], ["winter", 6, 23.1667, "clear"], ["spring", 8, 12.0, "foggy"], ["winter", 12, 12.0, "snow"], ["spring", 8, 12.0, "rain"], ["summer", 8, 12.0, "storm"]]:
			clock_node.restore_state({"year": 1, "season": example[0], "day": example[1], "hour": example[2], "speed": 1, "paused": true})
			weather.set_weather("base:weather:" + example[3])
			dial.refresh()
			await _frames(4)
			await _capture_dial("%s_%s_%d" % [example[0], example[3], viewport_size.x])
		_click(dial.get_global_rect().get_center())
		await _frames(4)
		_expect(dial.has_focus() and dial._focus_info.visible, "click/focus reveals clock details")
		_expect(bounds.encloses(dial._focus_info.get_global_rect()), "focus detail fits viewport")
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
