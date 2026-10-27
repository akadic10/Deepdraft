extends Control

## The Sky Dial (doc 23, "The Sky Dial"): a Hearthblock window onto the sky, over a plate with
## the time, the date and the year's seasons. The window stacks layers rendered from the sky
## models (data/ui/sky_dial.json; tools/GenerateUiIcons.gd renders them):
## - the sky for the part of the day, crossfading at the world's own dawn and dusk anchors;
## - the stars by night;
## - the sun from sunrise on the left to sunset on the right, and the moon through the night;
## - the weather's clouds and its rain or snow, which fall with game time;
## - the season's hills, and the frame.
## All time and weather state comes from the simulation. There is no second timer, forecast or
## saved state.
# Text sizes come from the type scale (doc 23, "Type").
const MEDIUM := UITheme.TYPE_MEDIUM
const SMALL := UITheme.TYPE_SMALL
const PLATE_GAP := 4.0

## The year as a bar: each season in its colour, seven cells long; the current season lit and
## its days still to come a little darker, the others dim; a copper notch over today.
class SeasonBar extends Control:
	var seasons: Array[String] = []
	var colours: Dictionary = {}
	var season := ""
	var day := 1
	var days := 28
	var cell := 6.0

	func _get_minimum_size() -> Vector2:
		return Vector2(cell * 7.0 * seasons.size() + 3.0 * maxf(0.0, seasons.size() - 1.0) + 1.0, roundf(cell * 1.6) + 7.0)

	func _draw() -> void:
		var x := (size.x - _get_minimum_size().x) * 0.5
		var tall := roundf(cell * 1.6)
		var today := clampf((float(day) - 0.5) / float(days), 0.0, 1.0) * 7.0
		for index in range(seasons.size()):
			var lit: bool = seasons[index] == season
			if lit: draw_colored_polygon(PackedVector2Array([Vector2(x + today * cell - 4, 0), Vector2(x + today * cell + 4, 0),
				Vector2(x + today * cell, 6)]), UITheme.HEARTH_COPPER)
			for c in range(7):
				var colour: Color = colours.get(seasons[index], Color.GRAY)
				if not lit: colour = colour.darkened(0.45)
				elif float(c) + 0.5 > today: colour = colour.darkened(0.25)
				draw_rect(Rect2(x + 1, 8, cell - 1, tall - 1), Color("1e1712"))
				draw_rect(Rect2(x, 7, cell - 1, tall - 1), colour)
				x += cell
			x += 3.0

var _clock: Node
var _weather: Node
var _sky: Node
var _data: Dictionary = {}
var _layers: Dictionary = {}   # piece -> its picture
var _frame := Rect2()   # the picture's framing on the camera plane, in cells
var _layer_width := 448.0   # the layers' width in pixels
var _pitch := 0.0
var _plate: PanelContainer
var _time_label: Label
var _date_label: Label
var _left_label: Label
var _bar: SeasonBar
var _focus_info: Control
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
	_data = UIRegistry.get_sky_dial()
	var picture: Dictionary = _data.get("picture", {})
	var framing: Array = picture.get("rect", [0, 0, 1, 1])
	_frame = Rect2(float(framing[0]), float(framing[1]), float(framing[2]), float(framing[3]))
	_layer_width = float(picture.get("width", 448))
	_pitch = deg_to_rad(float(picture.get("pitch", 0.0)))
	var folder := String(_data.get("layers", "res://assets/ui/sky_dial/"))
	var pieces: Array[String] = ["frame", "stars", "sun", "moon", "cloud_big", "cloud_small", "storm_big", "storm_small", "rain", "snow"]
	for phase: String in ["day", "dawn", "dusk", "night", "grey"]: pieces.append("sky_" + phase)
	if _clock != null:
		for season: String in _clock.season_order(): pieces.append("hills_" + season)
	for piece: String in pieces:
		if ResourceLoader.exists(folder + piece + ".png"): _layers[piece] = load(folder + piece + ".png")
	_build_plate()
	resized.connect(_layout)
	focus_entered.connect(_show_focus_info)
	focus_exited.connect(func():
		if _focus_info != null: _focus_info.hide()
		queue_redraw())
	_layout()
	refresh()


## The plate under the window: the time and the date on one line, the season bar, and how
## long until the next season.
func _build_plate() -> void:
	_plate = PanelContainer.new()
	_plate.name = "Plate"
	_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate.add_theme_stylebox_override("panel", UITheme.dock_panel_style())
	add_child(_plate)
	var lines := VBoxContainer.new()
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lines.add_theme_constant_override("separation", 1)
	_plate.add_child(lines)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	lines.add_child(row)
	_time_label = _label("Time", row)
	_date_label = _label("Date", row)
	_bar = SeasonBar.new()
	_bar.name = "Seasons"
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _clock != null:
		_bar.seasons = _clock.season_order()
		_bar.days = int(_clock.days_per_season())
	for season: String in _data.get("seasons", {}):
		_bar.colours[season] = Color(String(_data.seasons[season]))
	lines.add_child(_bar)
	_left_label = _label("SeasonLeft", lines)


func _label(id: String, parent: Control) -> Label:
	var label := Label.new()
	label.name = id
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_shadow_color", Color("0c1314"))
	label.add_theme_constant_override("shadow_offset_y", 1)
	parent.add_child(label)
	return label


## The plate's sizes from the type scale: the medium step from 204 px across, the small one
## on the narrowest dial (screens under 1200 px across).
func _type_for(width: float) -> Dictionary:
	return MEDIUM if width >= 204.0 else SMALL


func _apply_type(width: float) -> void:
	var type := _type_for(width)
	UITheme.apply_title(_time_label, type.name)
	# The time changes every game minute: figures of one width keep it from wobbling.
	_time_label.add_theme_font_override("font", UITheme.font("figures"))
	UITheme.apply_title(_date_label, type.lead)
	UITheme.format_label(_left_label, false, type.small, UITheme.HEARTH_MUTED)
	# The narrowest dial leaves the days to the next season to its hover card, so the slice
	# tower keeps its room under the clock on short screens.
	_left_label.visible = width >= 204.0
	_bar.cell = 6.0 if width >= 204.0 else 5.0
	_bar.update_minimum_size()


## The window's height for a width: the framing's shape.
func picture_height(width: float) -> float:
	return roundf(width * _frame.size.y / _frame.size.x)


## The whole dial's height for a width: the window, then the plate under it.
func height_for(width: float) -> float:
	_apply_type(width)
	return picture_height(width) + PLATE_GAP + _plate.get_combined_minimum_size().y


func _layout() -> void:
	if _plate == null: return
	_apply_type(size.x)
	var top := picture_height(size.x) + PLATE_GAP
	_plate.position = Vector2(0, top)
	_plate.size = Vector2(size.x, maxf(size.y - top, _plate.get_combined_minimum_size().y))
	if _focus_info != null: _focus_info.hide()
	queue_redraw()


func _process(delta: float) -> void:
	_refresh_remaining -= delta
	# Rain and snow fall smoothly; the rest moves with the game's minutes.
	if String(_look().get("fall", "")) != "": queue_redraw()
	if _refresh_remaining > 0: return
	_refresh_remaining = .1
	refresh()


## What the current weather shows (data/ui/sky_dial.json "weather").
func _look() -> Dictionary:
	return _data.get("weather", {}).get(String(state.get("weather_id", "")), {})


func refresh() -> void:
	if _clock == null or _weather == null or _sky == null: return
	var events: Dictionary = _sky.current_event_hours()
	var hour := float(_clock.hour)
	var sunrise := float(events.sunrise)
	var sunset := float(events.sunset)
	var is_day := hour >= sunrise and hour < sunset
	var phase := "Daytime" if is_day else "Night"
	if hour >= float(events.sunrise_start) and hour < float(events.sunrise_end): phase = "Dawn"
	elif hour >= float(events.sunset_start) and hour < float(events.sunset_end): phase = "Dusk"
	var weather_id := String(_weather.current_weather_id())
	var look: Dictionary = _data.get("weather", {}).get(weather_id, {})
	var seasons: Array[String] = _clock.season_order()
	var season := String(_clock.season)
	var days_left := int(_clock.days_per_season()) - int(_clock.day) + 1
	state = {"hour": hour, "season": season, "day": int(_clock.day), "year": int(_clock.year),
		"time": String(_clock.time_string()), "sunrise": sunrise, "sunset": sunset, "is_day": is_day,
		"phase": phase, "weather_id": weather_id, "weather_name": String(_weather.current_weather_name()),
		"paused": bool(_clock.paused) or float(_clock.speed) <= 0, "grey": bool(look.get("grey", false)),
		"days_left": days_left, "next_season": seasons[(seasons.find(season) + 1) % seasons.size()]}
	state.sky = _sky_blend(hour, events, bool(state.grey))
	# The sun crosses from sunrise to sunset; the moon through the night.
	if is_day:
		state.body = "sun"
		state.body_t = (hour - sunrise) / maxf(0.01, sunset - sunrise)
	else:
		state.body = "moon"
		state.body_t = fposmod(hour - sunset, 24.0) / maxf(0.01, 24.0 - (sunset - sunrise))
	state.body_shown = not (bool(state.grey) and is_day and not bool(look.get("sun", false)))
	_time_label.text = state.time
	_date_label.text = "%s %d" % [season.capitalize(), int(state.day)]
	_left_label.text = "%d %s to %s" % [days_left, "day" if days_left == 1 else "days", String(state.next_season)]
	_bar.season = season
	_bar.day = int(state.day)
	_bar.queue_redraw()
	tooltip_text = "%s · %s\n%s · Day %d · Year %d\n%s%s\nSunrise %s · Sunset %s\n%s\nThe sun crosses the window from sunrise to sunset, and the moon by night." % [
		state.phase, state.weather_name, season.capitalize(), state.day, state.year,
		state.time, " · Paused" if state.paused else "", _hour_text(sunrise), _hour_text(sunset), _left_label.text]
	if _focus_info != null and _focus_info.visible: _fill_focus_info()
	queue_redraw()


## The sky's two parts of the day and how far the second has faded in, at the world's anchors:
## night to dawn from sunrise_start to sunrise, dawn to day until sunrise_end, day to dusk from
## sunset_start to sunset, dusk to night until sunset_end. Grey weather greys the day.
func _sky_blend(hour: float, events: Dictionary, grey: bool) -> Array:
	var day := "grey" if grey else "day"
	var spans := [["night", "dawn", float(events.sunrise_start), float(events.sunrise)],
		["dawn", day, float(events.sunrise), float(events.sunrise_end)],
		["day", "dusk", float(events.sunset_start), float(events.sunset)],
		["dusk", "night", float(events.sunset), float(events.sunset_end)]]
	for span: Array in spans:
		if hour >= float(span[2]) and hour < float(span[3]):
			var from := day if span[0] == "day" else String(span[0])
			return [from, String(span[1]), (hour - float(span[2])) / maxf(0.01, float(span[3]) - float(span[2]))]
	if hour >= float(events.sunrise_end) and hour < float(events.sunset_start): return [day, day, 0.0]
	return ["night", "night", 0.0]


func _hour_text(hour: float) -> String:
	var minute := floori(hour * 60.0)
	return "%02d:%02d" % [floori(minute / 60.0), minute % 60]


## Where a point of the window (x, y, z in cells) falls in the picture, in pixels.
func _to_picture(point: Vector3, scale: float) -> Vector2:
	var up := point.y * cos(_pitch) - point.z * sin(_pitch)
	return Vector2((point.x - _frame.position.x) * scale, (_frame.position.y + _frame.size.y - up) * scale)


func _draw() -> void:
	if state.is_empty() or not _layers.has("frame"): return
	var picture := Rect2(0, 0, size.x, picture_height(size.x))
	var scale := picture.size.x / _frame.size.x   # pixels a cell on screen
	var shrink := picture.size.x / _layer_width   # a layer's pixels to the screen's
	var opening_cells: Array = _data.get("opening", [_frame.position.x, _frame.position.y, _frame.size.x, _frame.size.y])
	var opening := Rect2(Vector2(float(opening_cells[0]) - _frame.position.x, _frame.position.y + _frame.size.y - float(opening_cells[1]) - float(opening_cells[3])) * scale,
		Vector2(float(opening_cells[2]), float(opening_cells[3])) * scale)
	var look := _look()
	var hours := float(_clock.elapsed_days()) * float(_clock.hours_per_day()) if _clock != null else 0.0
	var sky: Array = state.sky
	_draw_layer("sky_" + String(sky[0]), picture)
	if float(sky[2]) > 0.0: _draw_layer("sky_" + String(sky[1]), picture, Color(1, 1, 1, float(sky[2])))
	var night := 1.0 if sky[0] == "night" and sky[1] == "night" else (1.0 - float(sky[2]) if sky[0] == "night" else (float(sky[2]) if sky[1] == "night" else 0.0))
	if night > 0.0 and not bool(state.grey): _draw_layer("stars", picture, Color(1, 1, 1, night))
	if bool(state.body_shown):
		var arc: Dictionary = _data.get("arc", {})
		var centre: Array = arc.get("centre", [0, 0, 0])
		var radius: Array = arc.get("radius", [1, 1])
		var angle := PI * (1.0 - float(state.body_t))
		var point := Vector3(float(centre[0]) + cos(angle) * float(radius[0]), float(centre[1]) + sin(angle) * float(radius[1]), float(centre[2]))
		_draw_sprite(String(state.body), _to_picture(point, scale), shrink, opening)
	var clouds := String(look.get("clouds", ""))
	if not clouds.is_empty():
		# Clouds drift right and come round again, out of sight beyond the opening's edges.
		var span := float(opening_cells[2]) + 28.0
		for spot: Array in _data.get("clouds", []):
			var x := fposmod(float(spot[0]) - float(opening_cells[0]) + 14.0 + hours * float(_data.get("drift", 0.0)), span) + float(opening_cells[0]) - 14.0
			_draw_sprite("%s_%s" % [clouds, String(spot[3])], _to_picture(Vector3(x, float(spot[1]), float(spot[2])), scale), shrink, opening)
	var fall := String(look.get("fall", ""))
	if _layers.has(fall):
		# The field repeats down the opening's height, so it falls without a seam.
		var period := float(opening_cells[3]) * scale
		var drop := fposmod(hours * float(_data.get("fall", {}).get(fall, 0.0)) * scale, period)
		for shift: float in [drop, drop - period]:
			_draw_clipped(_layers[fall], Rect2(picture.position + Vector2(0, shift), picture.size), opening)
	var hills := "hills_" + String(state.season)
	var arriving: float = _clock.season_visual_progress() if _clock != null else 1.0
	if arriving < 1.0:
		# A new season's land comes in by its first sunrise, as the world's does.
		var seasons: Array[String] = _clock.season_order()
		_draw_layer("hills_" + seasons[(seasons.find(String(state.season)) + seasons.size() - 1) % seasons.size()], picture)
		_draw_layer(hills, picture, Color(1, 1, 1, arriving))
	else:
		_draw_layer(hills, picture)
	if look.has("veil"): draw_rect(opening, Color(String(look.veil)))
	_draw_layer("frame", picture)
	if has_focus():
		draw_style_box(UITheme.focus_style(), Rect2(Vector2(2, 2), size - Vector2(4, 4)))


func _draw_layer(piece: String, rect: Rect2, tint := Color.WHITE) -> void:
	var texture: Texture2D = _layers.get(piece)
	if texture != null: draw_texture_rect(texture, rect, false, tint)


## A sprite (the sun, the moon, a cloud) centred where its origin falls, cut to the opening.
func _draw_sprite(piece: String, centre: Vector2, shrink: float, clip: Rect2) -> void:
	var texture: Texture2D = _layers.get(piece)
	if texture == null: return
	var extent := Vector2(texture.get_size()) * shrink
	_draw_clipped(texture, Rect2(centre - extent * 0.5, extent), clip)


## Draws `texture` over `rect`, only where it falls inside `clip`.
func _draw_clipped(texture: Texture2D, rect: Rect2, clip: Rect2, tint := Color.WHITE) -> void:
	var shown := rect.intersection(clip)
	if not shown.has_area(): return
	var texels := Vector2(texture.get_size()) / rect.size
	draw_texture_rect_region(texture, shown, Rect2((shown.position - rect.position) * texels, shown.size * texels), tint)


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


## The dial's details in the panel format's hover card (doc 260): the time of day and
## weather as the title, the date, time and daylight below.
func _fill_focus_info() -> void:
	var lines := tooltip_text.split("\n")
	# The dial belongs with the time controls, so its card wears the system family's colour.
	var registry := get_tree().root.get_node_or_null("UIRegistry")
	var family: Color = registry.get_icon_family_color("system") if registry != null else Color.TRANSPARENT
	_focus_info.show_card(lines[0], "\n".join(lines.slice(1)), "", "", get_viewport_rect().size.x >= 1200.0, family)


func _show_focus_info() -> void:
	if _focus_info == null:
		var layer := CanvasLayer.new()
		layer.layer = 30
		add_child(layer)
		_focus_info = preload("res://scripts/ui/HoverCard.gd").new()
		layer.add_child(_focus_info)
	_fill_focus_info()
	_focus_info.show()
	# Beside the dial so details do not cover the time controls under it.
	_focus_info.point_at(get_global_rect(), "left")
	queue_redraw()
