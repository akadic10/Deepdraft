extends Node

## Drives the scene's WorldEnvironment sky + fog and the Sun/Moon directional lights from
## data/sky/sky_settings.json, animated against WorldClock (the day/night cycle).
##
## Registered as an autoload (project.godot [autoload]), loaded after WorldClock. Render concerns
## are usually scene nodes here (WorldRenderer, Camera), but an autoload mirrors Stonehearth's
## sky_renderer *service* and avoids editing the main scene; 08_sky_plan.md §D.2 allows either.
##
## PHASE 2 (this file): each frame, evaluate the keyframed curves at the current in-game hour and
##   - tint the ProceduralSkyMaterial gradient (sky_gradient_colors curve),
##   - match the fog colour to the sky horizon and set fog density/distance (height_fog curve),
##   - move + recolour the Sun and a runtime Moon (sun/moon colour + angle_pitch curves).
## Non-time-varying renderer params (aerial perspective, sky affect, sun scatter, fog enabled,
## ambient energy) are applied once from the static 'environment' block. Ambient stays sky-sourced,
## so it darkens for free as the sky gradient darkens at night.
##
## JSON = what things are (the curves); GDScript = what things do (interpolating + applying them).

const SETTINGS_PATH := "res://data/sky/sky_settings.json"

# ── Tuning (safe to tweak; calibrate against screenshots) ─────────────────────
const SUN_ENERGY_SCALE   := 1.5    # light_energy = colour_brightness × this
const MOON_ENERGY_SCALE   := 1.5
const LIGHT_OFF_THRESHOLD := 0.02  # celestial colour brightness below this = light switched off
const UPDATE_INTERVAL     := 0.05  # seconds between sky updates (~20 Hz; sky changes slowly)
const DAY_HOURS           := 24.0
const TWILIGHT_HOURS      := 1.0   # dawn/dusk shoulder either side of sunrise/sunset
const MIN_DAYLIGHT        := 8.0   # winter-solstice daylight span (hours)
const MAX_DAYLIGHT        := 16.0  # summer-solstice daylight span (hours)
const WEATHER_BLEND       := 0.04  # per-update smoothing toward weather targets (~1.5 s settle)
const DARK_FACTOR         := 0.65  # sky/fog brightness scale when is_dark_during_daytime
const FOG_END_FRACTION    := 0.9   # fog hits FULL opacity at 0.9×far — BEFORE the far clip, so the
								   # clip only ever cuts already-invisible terrain (no hard edge).
const EDGE_FADE_START     := 0.55  # fade begins at 0.55×(fog end) — a wide, clearly visible dissolve.
const MIN_VIEW            := 32.0  # never collapse the fogged view below this many blocks
const FAR_FALLBACK        := 512.0 # used if no Camera3D is found in the scene
const FOG_DIAGNOSTIC      := false # TEMP debug: forces an unmistakable RED fog. Leave false.
const FOG_SATURATION      := 3.0   # exponential density × distance at the saturation point (~95% opacity)
const MANAGE_FOG          := false # keep Environment fog inactive; sky/fog solution is still under review.

# Fallback event hours if WorldClock has none (matches data/calendar/calendar.json).
const DEFAULT_EVENT_HOURS := {
	"midnight": 0, "sunrise_start": 5, "sunrise": 6, "sunrise_end": 7,
	"midday": 14, "sunset_start": 20, "sunset": 21, "sunset_end": 22,
}

var _settings: Dictionary = {}
var _clock: Node = null
var _world_env: WorldEnvironment = null
var _env: Environment = null
var _sky_mat: ProceduralSkyMaterial = null
var _sun: DirectionalLight3D = null
var _moon: DirectionalLight3D = null
var _camera: Camera3D = null
var _renderer: Node = null   # optional renderer hook for future fog/radius coupling.
var _sun_yaw: float = 45.0
var _moon_yaw: float = 225.0

# Precomputed curves — each is a sorted Array of [hour: float, value] (value = Color or float).
var _c_sky_top: Array = []
var _c_sky_horizon: Array = []
var _c_sky_ground: Array = []
var _c_sun_color: Array = []
var _c_sun_pitch: Array = []
var _c_moon_color: Array = []
var _c_moon_pitch: Array = []
var _c_fog_thickness: Array = []
var _c_fog_distance: Array = []

var _event_hours: Dictionary = {}
var _accum: float = 0.0
var _ready_ok: bool = false

# Weather state — applied target, smoothed by _update for soft transitions.
var _active_weather: Dictionary = {}
var _c_fog_thickness_w: Array = []
var _c_fog_distance_w: Array = []
var _darken: float = 1.0
var _vision: float = 1.0
var _fog_density_applied: float = -1.0
var _fog_end_applied: float = -1.0
var _fog_begin_applied: float = -1.0


func _ready() -> void:
	_settings = _load_settings()
	_clock = get_node_or_null("/root/WorldClock")
	# Autoloads run _ready BEFORE the main scene exists; wait one frame, then bind + start driving.
	await get_tree().process_frame
	_bind_to_scene()
	_connect_clock()
	_refresh_event_hours()
	_build_curves()
	_apply_static_base()
	if _ready_ok:
		_update(_current_hour())
		print("SkyController: day/night driver active (%s)." % SETTINGS_PATH)


func _process(delta: float) -> void:
	if not _ready_ok:
		return
	_accum += delta
	if _accum < UPDATE_INTERVAL:
		return
	_accum = 0.0
	_update(_current_hour())


# ── Settings loader ───────────────────────────────────────────────────────────

func _load_settings() -> Dictionary:
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if file == null:
		push_warning("SkyController: cannot open %s — leaving scene sky/fog as authored." % SETTINGS_PATH)
		return {}
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	file.close()
	if err != OK:
		push_error("SkyController: JSON parse error in %s — %s" % [SETTINGS_PATH, json.get_error_message()])
		return {}
	return json.data


# ── Scene binding ─────────────────────────────────────────────────────────────

func _bind_to_scene() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		push_warning("SkyController: no current scene — cannot bind sky/fog.")
		return

	_world_env = _find_by_class(scene, "WorldEnvironment") as WorldEnvironment
	_sun = _find_by_class(scene, "DirectionalLight3D") as DirectionalLight3D
	_camera = _find_by_class(scene, "Camera3D") as Camera3D   # fog pins to its far plane
	_renderer = scene.get_node_or_null("Renderer")
	if _renderer == null or not _renderer.has_method("set_terrain_fog"):
		_renderer = _find_by_method(scene, "set_terrain_fog")

	if _world_env != null:
		_env = _world_env.environment
		if _env != null and _env.sky != null and _env.sky.sky_material is ProceduralSkyMaterial:
			_sky_mat = _env.sky.sky_material as ProceduralSkyMaterial

	if _sun != null:
		_sun_yaw = _sun.rotation_degrees.y
		_moon_yaw = _sun_yaw + 180.0

	# Create a Moon directional light at runtime so nights are not pitch black. It never casts
	# shadows (one shadow-caster — the Sun — keeps the cost down).
	_moon = DirectionalLight3D.new()
	_moon.name = "Moon"
	_moon.shadow_enabled = false
	_moon.light_energy = 0.0
	_moon.visible = false
	scene.add_child(_moon)

	_ready_ok = _env != null
	if _env == null:
		push_warning("SkyController: WorldEnvironment has no Environment resource.")


func _find_by_class(node: Node, cls: StringName) -> Node:
	if node == null:
		return null
	if node.is_class(cls):
		return node
	for child in node.get_children():
		var found := _find_by_class(child, cls)
		if found != null:
			return found
	return null


func _find_by_method(node: Node, m: StringName) -> Node:
	if node == null:
		return null
	if node.has_method(m):
		return node
	for child in node.get_children():
		var found := _find_by_method(child, m)
		if found != null:
			return found
	return null


# ── Seasonal day length ──────────────────────────────────────────────────────

func _connect_clock() -> void:
	if _clock == null:
		return
	# Recompute rise/set hours when the day or season changes — daylight length is seasonal.
	if not _clock.is_connected("day_changed", _on_calendar_changed):
		_clock.connect("day_changed", _on_calendar_changed)
	if not _clock.is_connected("season_changed", _on_calendar_changed):
		_clock.connect("season_changed", _on_calendar_changed)


func _on_calendar_changed(_value = null) -> void:
	_refresh_event_hours()
	_build_curves()


## Computes today's event-time anchors. midnight and midday (solar noon) stay fixed; the
## sunrise/sunset events move so the lit span equals the seasonal daylight length — ~8 h at the
## winter solstice, ~16 h at the summer solstice (WorldClock.daylight_hours). The keyframed curves
## are anchored to these event names, so they stretch/compress automatically with the season.
func _refresh_event_hours() -> void:
	var base := DEFAULT_EVENT_HOURS.duplicate()
	if _clock != null and _clock.has_method("get_event_times"):
		var e = _clock.call("get_event_times")
		if e is Dictionary and not (e as Dictionary).is_empty():
			base = e
	var midnight: float = float(base.get("midnight", 0))
	var midday: float = float(base.get("midday", 14))

	var daylight := 12.0
	if _clock != null and _clock.has_method("daylight_hours") and _clock.has_method("day_of_year"):
		var doy: int = int(_clock.call("day_of_year"))
		daylight = clampf(float(_clock.call("daylight_hours", doy)), MIN_DAYLIGHT, MAX_DAYLIGHT)
	var half := daylight * 0.5
	var sunrise := midday - half
	var sunset := midday + half

	_event_hours = {
		"midnight":      midnight,
		"sunrise_start": clampf(sunrise - TWILIGHT_HOURS, 0.0, DAY_HOURS),
		"sunrise":       clampf(sunrise, 0.0, DAY_HOURS),
		"sunrise_end":   clampf(sunrise + TWILIGHT_HOURS, 0.0, DAY_HOURS),
		"midday":        midday,
		"sunset_start":  clampf(sunset - TWILIGHT_HOURS, 0.0, DAY_HOURS),
		"sunset":        clampf(sunset, 0.0, DAY_HOURS),
		"sunset_end":    clampf(sunset + TWILIGHT_HOURS, 0.0, DAY_HOURS),
	}


# ── Curve construction ────────────────────────────────────────────────────────

func _build_curves() -> void:
	# _event_hours is precomputed by _refresh_event_hours() (seasonal day length).
	var sky: Dictionary = _settings.get("sky_gradient_colors", {})
	_c_sky_top     = _color_curve(sky.get("top", []))
	_c_sky_horizon = _color_curve(sky.get("horizon", []))
	_c_sky_ground  = _color_curve(sky.get("ground_bottom", []))

	var sun: Dictionary = _settings.get("sun", {})
	_c_sun_color = _color_curve(sun.get("light_color", []))
	_c_sun_pitch = _scalar_curve(sun.get("angle_pitch", []), "deg")

	var moon: Dictionary = _settings.get("moon", {})
	_c_moon_color = _color_curve(moon.get("light_color", []))
	_c_moon_pitch = _scalar_curve(moon.get("angle_pitch", []), "deg")

	var hf = _settings.get("height_fog", [])
	_c_fog_thickness = _scalar_curve(hf, "thickness")
	_c_fog_distance  = _scalar_curve(hf, "distance")
	_build_weather_curves()


# ── Weather ───────────────────────────────────────────────────────────────────

## Called by WeatherManager. Stores the active weather and rebuilds its fog-override curves.
## The look is blended in smoothly by _update (darkening, fog density/distance, vision range).
func apply_weather(weather: Dictionary) -> void:
	_active_weather = weather if weather != null else {}
	_build_weather_curves()


func _build_weather_curves() -> void:
	_c_fog_thickness_w = []
	_c_fog_distance_w = []
	var ov: Dictionary = _active_weather.get("sky_overrides", {})
	var hf = ov.get("height_fog", [])
	if hf is Array and not (hf as Array).is_empty():
		_c_fog_thickness_w = _scalar_curve(hf, "thickness")
		_c_fog_distance_w  = _scalar_curve(hf, "distance")


func _color_curve(arr) -> Array:
	var out: Array = []
	if arr is Array:
		for pt in arr:
			if not (pt is Dictionary):
				continue
			var h := _event_hour(String(pt.get("at", "")))
			if h < 0.0:
				continue
			out.append([h, _to_color(pt.get("rgb", [1, 0, 1]))])
	out.sort_custom(func(a, b): return a[0] < b[0])
	return out


func _scalar_curve(arr, key: String) -> Array:
	var out: Array = []
	if arr is Array:
		for pt in arr:
			if not (pt is Dictionary) or not (pt as Dictionary).has(key):
				continue
			var h := _event_hour(String(pt.get("at", "")))
			if h < 0.0:
				continue
			out.append([h, float(pt[key])])
	out.sort_custom(func(a, b): return a[0] < b[0])
	return out


func _event_hour(name: String) -> float:
	return float(_event_hours.get(name, -1.0))


# ── Evaluation (keyframe interpolation with 24-hour wraparound) ───────────────

## Returns [i0, i1, t] — the bracketing indices and the 0–1 blend factor for hour h.
func _frac(curve: Array, h: float) -> Array:
	var n := curve.size()
	if n == 0:
		return []
	if n == 1:
		return [0, 0, 0.0]

	var idx := -1
	for i in n:
		if curve[i][0] > h:
			idx = i
			break

	var i0: int
	var i1: int
	var h0: float
	var h1: float
	if idx == -1:
		# h is at/after the last keyframe — wrap to the first (+24h).
		i0 = n - 1; i1 = 0
		h0 = curve[i0][0]; h1 = curve[i1][0] + DAY_HOURS
	elif idx == 0:
		# h is before the first keyframe — wrap from the last (-24h).
		i0 = n - 1; i1 = 0
		h0 = curve[i0][0] - DAY_HOURS; h1 = curve[i1][0]
	else:
		i0 = idx - 1; i1 = idx
		h0 = curve[i0][0]; h1 = curve[i1][0]

	var span := h1 - h0
	var t := 0.0 if span <= 0.0 else clampf((h - h0) / span, 0.0, 1.0)
	return [i0, i1, t]


func _eval_color(curve: Array, h: float) -> Color:
	var b := _frac(curve, h)
	if b.is_empty():
		return Color.MAGENTA
	return (curve[b[0]][1] as Color).lerp(curve[b[1]][1] as Color, b[2])


func _eval_scalar(curve: Array, h: float) -> float:
	var b := _frac(curve, h)
	if b.is_empty():
		return 0.0
	return lerpf(float(curve[b[0]][1]), float(curve[b[1]][1]), b[2])


# ── Per-frame apply ───────────────────────────────────────────────────────────

func _update(h: float) -> void:
	# Weather targets, smoothed toward for soft transitions.
	var darken_target := DARK_FACTOR if bool(_active_weather.get("is_dark_during_daytime", false)) else 1.0
	var vision_target := float(_active_weather.get("vision_multiplier", 1.0))
	_darken = lerpf(_darken, darken_target, WEATHER_BLEND)
	_vision = lerpf(_vision, vision_target, WEATHER_BLEND)

	var horizon := _scale_color(_eval_color(_c_sky_horizon, h), _darken)

	# Sky gradient (dimmed by overcast/fog/snow weather).
	if _sky_mat != null:
		_sky_mat.sky_top_color        = _scale_color(_eval_color(_c_sky_top, h), _darken)
		_sky_mat.sky_horizon_color    = horizon
		_sky_mat.ground_horizon_color = horizon                       # match the sky horizon
		_sky_mat.ground_bottom_color  = _scale_color(_eval_color(_c_sky_ground, h), _darken)

	# Fog: colour tracks the sky horizon (sky/fog match). Density + distance come from the weather
	# height_fog override when present (else base); distance is further scaled by the weather's
	# vision multiplier (fog closes in during foggy/snow). Both are smoothed for a soft transition.
	if MANAGE_FOG and _renderer != null:
		_renderer.call("set_terrain_fog", horizon, _vision, FOG_END_FRACTION, EDGE_FADE_START, FOG_DIAGNOSTIC)

	# Celestial lights.
	_apply_light(_sun,  _eval_color(_c_sun_color, h),  _eval_scalar(_c_sun_pitch, h),  _sun_yaw,  SUN_ENERGY_SCALE)
	_apply_light(_moon, _eval_color(_c_moon_color, h), _eval_scalar(_c_moon_pitch, h), _moon_yaw, MOON_ENERGY_SCALE)


func _apply_light(light: DirectionalLight3D, c: Color, pitch: float, yaw: float, energy_scale: float) -> void:
	if light == null:
		return
	var b := maxf(c.r, maxf(c.g, c.b))
	if b <= LIGHT_OFF_THRESHOLD:
		light.visible = false
		return
	light.visible = true
	light.light_color  = Color(c.r / b, c.g / b, c.b / b)   # normalised hue (brightness -> energy)
	light.light_energy = b * energy_scale
	light.rotation_degrees = Vector3(pitch, yaw, 0.0)


# ── Static (non-time-varying) base from the 'environment' block ───────────────

func _apply_static_base() -> void:
	if _env == null:
		return
	var look: Dictionary = _settings.get("environment", {})
	if look.is_empty():
		return
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	if look.has("ambient_color"):
		_env.ambient_light_color = _to_color(look["ambient_color"])
	if look.has("ambient_energy"):
		_env.ambient_light_energy = float(look["ambient_energy"])
	if MANAGE_FOG:
		_env.fog_enabled = false


# ── Helpers ───────────────────────────────────────────────────────────────────

func _current_hour() -> float:
	if _clock != null:
		return float(_clock.get("hour"))
	return 12.0


## The camera far plane (in blocks) the edge fog dissolves at. Read live so it tracks far_clip.
func _far_distance() -> float:
	if _camera != null:
		return _camera.far
	return FAR_FALLBACK


## Multiplies a colour's RGB by a scalar (alpha untouched). Used for weather darkening.
func _scale_color(c: Color, s: float) -> Color:
	return Color(c.r * s, c.g * s, c.b * s, c.a)


## Converts a JSON [r, g, b] or [r, g, b, a] array (0–1 floats) to a Color.
func _to_color(arr) -> Color:
	if arr is Array and (arr as Array).size() >= 3:
		var a: float = 1.0
		if (arr as Array).size() >= 4:
			a = float(arr[3])
		return Color(float(arr[0]), float(arr[1]), float(arr[2]), a)
	return Color.MAGENTA
