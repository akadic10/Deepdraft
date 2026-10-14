extends Control

## Permanent information HUD. Artwork is registry-owned; all time/weather state
## comes from the simulation. There is no second timer, forecast or saved state.
const SCENE_CENTER := Vector2(.489, .502)
const SCENE_RADIUS := .359
const TRACK_RADIUS := .389
const SCENE_BOTTOM := .632
var _clock: Node
var _weather: Node
var _sky: Node
var _frame: Texture2D
var _landscapes: Dictionary = {}
var _symbols: Dictionary = {}
var _weather_symbols: Dictionary = {}
var _time_label: Label
var _date_label: Label
var _focus_info: PanelContainer
var _focus_text: Label
var _refresh_remaining := 0.0
var state: Dictionary = {}


func _ready() -> void:
	name = "SkyDial"
	add_to_group("sky_dial")
	UITheme.apply_surface(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_clock = get_node_or_null("/root/WorldClock")
	_weather = get_node_or_null("/root/WeatherManager")
	_sky = get_node_or_null("/root/SkyController")
	var data: Dictionary = UIRegistry.get_sky_dial()
	_frame = UIRegistry.get_dock_icon(data.get("frame", {}))
	_weather_symbols = data.get("weather_symbols", {})
	for season: String in data.get("landscapes", {}):
		var views: Dictionary = {}
		for phase: String in ["day", "night"]:
			views[phase] = UIRegistry.get_dock_icon({"icon": data.landscape_atlas,
				"icon_region": data.landscapes[season][phase]})
		_landscapes[season] = views
	for symbol: String in data.get("symbols", {}):
		_symbols[symbol] = UIRegistry.get_dock_icon({"icon": data.symbol_atlas,
			"icon_region": data.symbols[symbol]})
	_time_label = _label("Time", 27)
	_date_label = _label("SeasonAndDay", 13)
	resized.connect(_layout_labels)
	focus_entered.connect(_show_focus_info)
	focus_exited.connect(func():
		if _focus_info != null: _focus_info.hide()
		queue_redraw())
	_layout_labels()
	refresh()


func _label(id: String, font_size: int) -> Label:
	var label := Label.new()
	label.name = id
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UITheme.apply_title(label, font_size)
	label.add_theme_color_override("font_shadow_color", Color("0c1314"))
	label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(label)
	return label


func _layout_labels() -> void:
	if _time_label == null: return
	_time_label.position = size * Vector2(.19, .657)
	_time_label.size = size * Vector2(.60, .12)
	_time_label.add_theme_font_size_override("font_size", roundi(size.x * .133))
	_date_label.position = size * Vector2(.285, .803)
	_date_label.size = size * Vector2(.485, .105)
	_date_label.add_theme_font_size_override("font_size", maxi(12, roundi(size.x * .063)))
	if _focus_info != null: _focus_info.hide()
	queue_redraw()


func _process(delta: float) -> void:
	_refresh_remaining -= delta
	if _refresh_remaining > 0: return
	_refresh_remaining = .1
	refresh()


func refresh() -> void:
	if _clock == null or _weather == null or _sky == null: return
	var events: Dictionary = _sky.current_event_hours()
	var hour := float(_clock.hour)
	var sunrise := float(events.sunrise)
	var sunset := float(events.sunset)
	var daylight := smoothstep(float(events.sunrise_start), float(events.sunrise_end), hour) \
		* (1.0 - smoothstep(float(events.sunset_start), float(events.sunset_end), hour))
	var is_day := hour >= sunrise and hour < sunset
	var phase := "Daytime" if is_day else "Night"
	if hour >= float(events.sunrise_start) and hour < float(events.sunrise_end): phase = "Dawn"
	elif hour >= float(events.sunset_start) and hour < float(events.sunset_end): phase = "Dusk"
	var weather_id := String(_weather.current_weather_id())
	var weather_symbol := String(_weather_symbols.get(weather_id, "overcast"))
	if weather_symbol == "sun" and not is_day: weather_symbol = "moon"
	state = {"hour": hour, "season": String(_clock.season), "day": int(_clock.day),
		"year": int(_clock.year), "time": String(_clock.time_string()),
		"sunrise": sunrise, "sunset": sunset, "daylight": daylight, "is_day": is_day,
		"phase": phase, "weather_id": weather_id, "weather_symbol": weather_symbol,
		"weather_name": String(_weather.current_weather_name()),
		"paused": bool(_clock.paused) or float(_clock.speed) <= 0}
	_time_label.text = state.time
	_date_label.text = "%s · Day %d" % [String(state.season).capitalize(), state.day]
	tooltip_text = "%s · %s\n%s · Day %d · Year %d\n%s%s\nSunrise %s · Sunset %s\nThe rim follows one full day, from midnight to midnight." % [
		state.phase, state.weather_name, String(state.season).capitalize(), state.day, state.year,
		state.time, " · Paused" if state.paused else "", _hour_text(sunrise), _hour_text(sunset)]
	if _focus_text != null: _focus_text.text = tooltip_text
	queue_redraw()


func _hour_text(hour: float) -> String:
	var minute := floori(hour * 60.0)
	return "%02d:%02d" % [floori(minute / 60.0), minute % 60]


func _draw() -> void:
	if state.is_empty() or _frame == null: return
	var points := _scene_points()
	var uv := PackedVector2Array()
	for point in points:
		uv.append((point / size.x - Vector2(.13, .14)) / Vector2(.718, .492))
	var views: Dictionary = _landscapes.get(state.season, _landscapes.get("summer", {}))
	# Two paintings crossfade through the same dawn/dusk anchors as the world.
	if not views.is_empty():
		_draw_landscape(points, uv, views.night, Color.WHITE)
		_draw_landscape(points, uv, views.day, Color(1, 1, 1, state.daylight))
	var weather_symbol: String = state.weather_symbol
	if weather_symbol in ["overcast", "foggy", "snow", "rain", "storm"]:
		draw_colored_polygon(points, Color(.26, .31, .39, .30 if weather_symbol == "overcast" else .44))
		_draw_symbol("overcast", Rect2(size * Vector2(.25, .20), size * Vector2(.44, .25)), Color(.85, .89, .96, .9))
		if weather_symbol == "foggy":
			_draw_symbol("foggy", Rect2(size * Vector2(.22, .37), size * Vector2(.54, .22)), Color(1, 1, 1, .8))
		elif weather_symbol == "snow":
			for i in 12:
				# Deterministic flakes follow game time, freezing when paused.
				var x := .29 + fmod(float(i) * .117, .42)
				var y := .35 + fmod(float(i) * .057 + float(state.hour) * .1, .23)
				draw_circle(size * Vector2(x, y), maxf(1, size.x * .005), Color(.88, .94, 1, .85))
		elif weather_symbol in ["rain", "storm"]:
			for i in 9:
				var point := size * Vector2(.29 + fmod(i * .117, .42), .37 + fmod(i * .057 + float(state.hour) * .1, .2))
				draw_line(point, point + size * Vector2(-.008, .026), Color(.65, .8, .93, .8), 1.2, true)
	else:
		_draw_symbol("sun" if state.is_day else "moon", Rect2(size * Vector2(.26, .23), size * Vector2(.16, .16)))
	draw_texture_rect(_frame, Rect2(Vector2.ZERO, size), false)
	_draw_cycle()
	_draw_symbol(weather_symbol, Rect2(size * Vector2(.79, .508), size * Vector2(.147, .147)))
	_draw_symbol(state.season, Rect2(size * Vector2(.20, .811), size * Vector2(.09, .09)))
	if has_focus():
		draw_style_box(UITheme.focus_style(), Rect2(Vector2(2, 2), size - Vector2(4, 4)))


func _scene_points() -> PackedVector2Array:
	var points := PackedVector2Array([size * Vector2(SCENE_CENTER.x - SCENE_RADIUS, SCENE_BOTTOM)])
	for i in 65:
		var angle := PI + PI * float(i) / 64.0
		points.append(size * (SCENE_CENTER + Vector2(cos(angle), sin(angle)) * SCENE_RADIUS))
	points.append(size * Vector2(SCENE_CENTER.x + SCENE_RADIUS, SCENE_BOTTOM))
	return points


func _draw_cycle() -> void:
	var center := size * SCENE_CENTER
	var radius := size.x * TRACK_RADIUS
	for i in 96:
		var hour := (float(i) + .5) * .25
		var daylight: bool = hour >= float(state.sunrise) and hour < float(state.sunset)
		var color := Color("d3af5c") if daylight else Color("253950")
		draw_arc(center, radius, PI + PI * i / 96.0, PI + PI * (i + 1) / 96.0,
			3, color, size.x * .034, true)
	for i in 25:
		var angle := PI + PI * i / 24.0
		var direction := Vector2(cos(angle), sin(angle))
		draw_line(center + direction * (radius - size.x * .016),
			center + direction * (radius + size.x * .016), Color("927854"), 1, true)
	var marker_angle := PI + PI * float(state.hour) / 24.0
	var marker := center + Vector2(cos(marker_angle), sin(marker_angle)) * radius
	draw_circle(marker, size.x * .040, Color("172124"))
	draw_arc(marker, size.x * .040, 0, TAU, 32, UITheme.HEARTH_COPPER, 1.3, true)
	_draw_symbol("sun" if state.is_day else "moon", Rect2(marker - size * .04, size * .08))


func _draw_symbol(id: String, rect: Rect2, tint := Color.WHITE) -> void:
	if id in ["rain", "storm"]:
		_draw_symbol("overcast", rect, tint)
		for i in 3:
			var point := rect.position + rect.size * Vector2(.3 + i * .21, .67)
			draw_line(point, point + rect.size * Vector2(-.08, .22), Color(.6, .8, 1), maxf(1, rect.size.x * .04), true)
		if id == "storm":
			var bolt := PackedVector2Array()
			for point: Vector2 in [Vector2(.58,.38), Vector2(.37,.65), Vector2(.53,.65), Vector2(.42,.9), Vector2(.76,.54), Vector2(.59,.54)]: bolt.append(rect.position + rect.size * point)
			draw_colored_polygon(bolt, Color("e7c67e"))
		return
	var texture: Texture2D = _symbols.get(id)
	if texture != null: draw_texture_rect(texture, rect, false, tint)


func _draw_landscape(points: PackedVector2Array, uv: PackedVector2Array, texture: AtlasTexture, tint: Color) -> void:
	var atlas_uv := PackedVector2Array()
	for point in uv:
		atlas_uv.append((texture.region.position + point * texture.region.size) / texture.atlas.get_size())
	draw_polygon(points, PackedColorArray([tint]), atlas_uv, texture.atlas)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT: grab_focus()
		accept_event()
	elif event.is_action_pressed("ui_cancel"):
		release_focus()
		accept_event()


func _get_tooltip(_at_position: Vector2) -> String:
	# Keyboard/click focus already shows the same information explicitly.
	return "" if has_focus() else tooltip_text


func _show_focus_info() -> void:
	if _focus_info == null:
		var layer := CanvasLayer.new()
		layer.layer = 30
		add_child(layer)
		_focus_info = PanelContainer.new()
		UITheme.apply_surface(_focus_info)
		_focus_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_focus_info.add_theme_stylebox_override("panel", UITheme.dock_tooltip_style())
		layer.add_child(_focus_info)
		_focus_text = Label.new()
		_focus_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_focus_text.custom_minimum_size.x = 260
		_focus_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_focus_info.add_child(_focus_text)
	_focus_text.text = tooltip_text
	_focus_info.show()
	_focus_info.reset_size()
	# Beside the dial so details do not cover the food warning underneath it.
	_focus_info.position = Vector2(maxf(8, get_global_rect().position.x - _focus_info.size.x - 8),
		get_global_rect().position.y + 24)
	queue_redraw()
