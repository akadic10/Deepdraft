extends Node

## Drives the scene's WorldEnvironment sky + fog and the Sun/Moon directional lights from
## data/sky/sky_settings.json, animated against WorldClock (the day/night cycle).
##
## Registered as an autoload (project.godot [autoload]), loaded after WorldClock. Render concerns
## are usually scene nodes here (WorldRenderer, Camera), but an autoload mirrors Stonehearth's
## sky_renderer *service* and avoids editing the main scene; either is acceptable.
##
## A full-sphere backdrop shares its broad ambient gradient with roof-aware fog.
## Stars, clouds and celestial discs are background detail; the existing directional
## light curves remain responsible for lighting the world.
##
## JSON = what things are (the curves); GDScript = what things do (interpolating + applying them).

const SETTINGS_PATH := "res://data/sky/sky_settings.json"
const SKY_SHADER := preload("res://scripts/shaders/diorama_sky.gdshader")
const WORLD_SCENE_PATH := "res://scenes/main/debug_world.tscn"

## Emitted after each scene bind applies (or skips) the Hearthblock look, so
## scene-owned materials, lights and overlays can follow it.
signal hearthblock_lighting_changed(active: bool)

# ── Tuning (safe to tweak; calibrate against screenshots) ─────────────────────
const SUN_ENERGY_SCALE   := 1.5    # light_energy = colour_brightness × this
const MOON_ENERGY_SCALE   := 1.5
const LIGHT_OFF_THRESHOLD := 0.02  # celestial colour brightness below this = light switched off
const UPDATE_INTERVAL     := 0.05  # seconds between sky updates (~20 Hz; sky changes slowly)
const TWILIGHT_HOURS      := 1.0   # dawn/dusk shoulder either side of sunrise/sunset
const WEATHER_BLEND       := 0.04  # per-update smoothing toward weather targets (~1.5 s settle)
const DARK_FACTOR         := 0.65  # sky/fog brightness scale when is_dark_during_daytime


var _settings: Dictionary = {}
var _clock: Node = null
var _world_env: WorldEnvironment = null
var _env: Environment = null
var _sky_mat: ShaderMaterial = null
var _sun: DirectionalLight3D = null
var _moon: DirectionalLight3D = null
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

var _event_hours: Dictionary = {}
var _accum: float = 0.0
var _ready_ok: bool = false

# Weather state — applied target, smoothed by _update for soft transitions.
var _active_weather: Dictionary = {}
var _darken: float = 1.0
var _c_stars: Array = []
var _atmosphere: Dictionary = {}


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


func underground_settings() -> Dictionary:
	return _settings.get("underground", {}).duplicate(true)


# ── Settings loader ───────────────────────────────────────────────────────────

func _load_settings() -> Dictionary:
	# On failure (reported) the scene sky/fog stays as authored.
	return preload("res://scripts/registries/JsonData.gd").read_dict(SETTINGS_PATH)


# ── Scene binding ─────────────────────────────────────────────────────────────

## The autoload outlives the scene. Stop reading its lights before Godot
## detaches/frees them, including the gap inside reload_current_scene().
func _clear_scene_binding() -> void:
	_ready_ok = false
	_accum = 0.0
	if is_instance_valid(_world_env) and _world_env.tree_exiting.is_connected(_clear_scene_binding):
		_world_env.tree_exiting.disconnect(_clear_scene_binding)
	_world_env = null
	_env = null
	_sky_mat = null
	_sun = null
	_moon = null


func _bind_to_scene() -> void:
	_clear_scene_binding()
	var scene := get_tree().current_scene
	if not is_instance_valid(scene) or not scene.is_inside_tree():
		push_warning("SkyController: no current scene — cannot bind sky/fog.")
		return

	_world_env = _find_by_class(scene, "WorldEnvironment") as WorldEnvironment
	_sun = _find_by_class(scene, "DirectionalLight3D") as DirectionalLight3D
	# A scene with no world to light (the title screen) has no sky to drive.
	if _world_env == null and _sun == null:
		return

	if _world_env != null:
		_world_env.tree_exiting.connect(_clear_scene_binding)
		_env = _world_env.environment
		if _env != null:
			_sky_mat = ShaderMaterial.new()
			_sky_mat.shader = SKY_SHADER
			var sky := Sky.new()
			sky.sky_material = _sky_mat
			sky.process_mode = Sky.PROCESS_MODE_REALTIME
			sky.radiance_size = Sky.RADIANCE_SIZE_256
			_env.sky = sky
			_env.background_mode = Environment.BG_SKY

	if _sun != null:
		preload("res://scripts/components/TerrainLighting.gd").configure_sun(_sun)
		_sun_yaw = _sun.rotation_degrees.y
		_moon_yaw = _sun_yaw + 180.0

	# Create a Moon directional light at runtime so nights are not pitch black. It never casts
	# shadows (one shadow-caster — the Sun — keeps the cost down).
	_moon = scene.get_node_or_null("Moon") as DirectionalLight3D
	if _moon == null:
		_moon = DirectionalLight3D.new()
		_moon.name = "Moon"
		_moon.shadow_enabled = false
		_moon.light_energy = 0.0
		_moon.visible = false
		scene.add_child(_moon)

	_ready_ok = _env != null
	if _env == null:
		push_warning("SkyController: WorldEnvironment has no Environment resource.")


## SaveManager reloads the gameplay scene while this autoload survives. Rebind
## every scene-owned render reference before the next sky update.
func rebind_to_current_scene() -> void:
	_bind_to_scene()
	_apply_static_base()
	if _ready_ok:
		_update(_current_hour())


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


## Read-only HUD access to the same seasonal anchors used by world lighting.
func current_event_hours() -> Dictionary:
	if _event_hours.is_empty(): _refresh_event_hours()
	return _event_hours.duplicate()


## Computes today's event-time anchors. midnight and midday (solar noon) stay fixed; the
## sunrise/sunset events move so the lit span equals the seasonal daylight length — ~8 h at the
## winter solstice, ~16 h at the summer solstice (WorldClock.daylight_hours). The keyframed curves
## are anchored to these event names, so they stretch/compress automatically with the season.
func _refresh_event_hours() -> void:
	# Event hours, day length and the seasonal curve all come from calendar.json via WorldClock.
	var base: Dictionary = WorldClock.get_event_times()
	var midnight: float = float(base.get("midnight", 0))
	var midday: float = float(base.get("midday", 12))
	var daylight := WorldClock.daylight_hours(WorldClock.day_of_year())
	var day_hours := _day_hours()
	var half := daylight * 0.5
	var sunrise := midday - half
	var sunset := midday + half

	_event_hours = {
		"midnight":      midnight,
		"sunrise_start": clampf(sunrise - TWILIGHT_HOURS, 0.0, day_hours),
		"sunrise":       clampf(sunrise, 0.0, day_hours),
		"sunrise_end":   clampf(sunrise + TWILIGHT_HOURS, 0.0, day_hours),
		"midday":        midday,
		"sunset_start":  clampf(sunset - TWILIGHT_HOURS, 0.0, day_hours),
		"sunset":        clampf(sunset, 0.0, day_hours),
		"sunset_end":    clampf(sunset + TWILIGHT_HOURS, 0.0, day_hours),
	}


# ── Curve construction ────────────────────────────────────────────────────────

func _build_curves() -> void:
	# _event_hours is precomputed by _refresh_event_hours() (seasonal day length).
	var sky: Dictionary = _settings.get("sky_gradient_colors", {})
	_c_sky_top     = _color_curve(sky.get("top", []))
	_c_sky_horizon = _color_curve(sky.get("horizon", []))
	_c_sky_ground  = _color_curve(sky.get("ground_bottom", []))
	_c_stars = _scalar_curve(_settings.get("starfield_brightness", []), "value")

	var sun: Dictionary = _settings.get("sun", {})
	_c_sun_color = _color_curve(sun.get("light_color", []))
	_c_sun_pitch = _scalar_curve(sun.get("angle_pitch", []), "deg")

	var moon: Dictionary = _settings.get("moon", {})
	_c_moon_color = _color_curve(moon.get("light_color", []))
	_c_moon_pitch = _scalar_curve(moon.get("angle_pitch", []), "deg")


# Weather presentation blends without changing generation or streaming budgets.
func apply_weather(weather: Dictionary) -> void:
	_active_weather = weather if weather != null else {}


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


func _event_hour(event_name: String) -> float:
	return float(_event_hours.get(event_name, -1.0))


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
		h0 = curve[i0][0]; h1 = curve[i1][0] + _day_hours()
	elif idx == 0:
		# h is before the first keyframe — wrap from the last (-24h).
		i0 = n - 1; i1 = 0
		h0 = curve[i0][0] - _day_hours(); h1 = curve[i1][0]
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
	if not _ready_ok:
		return
	if not is_instance_valid(_world_env) or not _world_env.is_inside_tree():
		_clear_scene_binding()
		return
	var darken_target := DARK_FACTOR if bool(_active_weather.get("is_dark_during_daytime", false)) else 1.0
	_darken = lerpf(_darken, darken_target, WEATHER_BLEND)
	var look: Dictionary = _settings.get("diorama", {})
	var targets: Dictionary = look.get("atmosphere", {}).duplicate()
	targets.merge(_active_weather.get("sky_overrides", {}).get("atmosphere", {}), true)
	for key: String in targets:
		_atmosphere[key] = lerpf(float(_atmosphere.get(key, targets[key])), float(targets[key]), WEATHER_BLEND)
	var cover: float = _atmosphere.get("cloud_cover", 0.0)
	var top := _weather_color(_eval_color(_c_sky_top, h), cover)
	var horizon := _weather_color(_eval_color(_c_sky_horizon, h), cover)
	var bottom := _weather_color(_eval_color(_c_sky_ground, h), cover)
	var night := _eval_scalar(_c_stars, h)
	var sun_live := is_instance_valid(_sun) and _sun.is_inside_tree()
	var moon_live := is_instance_valid(_moon) and _moon.is_inside_tree()
	if sun_live:
		_apply_light(_sun, _eval_color(_c_sun_color, h), _eval_scalar(_c_sun_pitch, h), _sun_yaw, SUN_ENERGY_SCALE)
	if moon_live:
		_apply_light(_moon, _eval_color(_c_moon_color, h), _eval_scalar(_c_moon_pitch, h), _moon_yaw, MOON_ENERGY_SCALE)
	if _sky_mat != null:
		_sky_mat.set_shader_parameter("sky_top", top)
		_sky_mat.set_shader_parameter("sky_horizon", horizon)
		_sky_mat.set_shader_parameter("sky_bottom", bottom)
		_sky_mat.set_shader_parameter("night_amount", night * (1.0 - cover * 0.85))
		_sky_mat.set_shader_parameter("cloud_cover", cover)
		# Calendar motion stops when paused and wraps continuously at midnight.
		_sky_mat.set_shader_parameter("cloud_rotation", h * TAU / _day_hours())
		var cloud_day := _to_color(look.get("cloud_day", [.82, .86, .91]))
		var cloud_night := _to_color(look.get("cloud_night", [.13, .18, .28]))
		_sky_mat.set_shader_parameter("cloud_color", _scale_color(cloud_day.lerp(cloud_night, night), _darken))
		if sun_live:
			_sky_mat.set_shader_parameter("sun_direction", _sun.global_basis.z.normalized())
			_sky_mat.set_shader_parameter("sun_visibility", (1.0 - night) * (1.0 - cover * .8) if _sun.visible else 0.0)
		else:
			_sky_mat.set_shader_parameter("sun_visibility", 0.0)
		if moon_live:
			_sky_mat.set_shader_parameter("moon_direction", _moon.global_basis.z.normalized())
			_sky_mat.set_shader_parameter("moon_visibility", night * (1.0 - cover * .8) if _moon.visible else 0.0)
		else:
			_sky_mat.set_shader_parameter("moon_visibility", 0.0)
	if _env != null:
		var camera := get_viewport().get_camera_3d()
		# Godot otherwise stretches an orthographic camera's world-unit size
		# across the sky. Give study/overview cameras a finite angular backdrop.
		_env.sky_custom_fov = camera.fov if camera != null and camera.projection == Camera3D.PROJECTION_ORTHOGONAL else 0.0
		_env.fog_light_color = horizon
		_env.fog_density = float(_atmosphere.get("fog_density", .2))
		_env.fog_depth_begin = float(_atmosphere.get("fog_begin", 90.0))
		_env.fog_depth_end = float(_atmosphere.get("fog_end", 450.0))


func _weather_color(color: Color, cover: float) -> Color:
	var grey := color.get_luminance()
	return _scale_color(color.lerp(Color(grey, grey, grey), cover * .55), _darken)


func _apply_light(light: DirectionalLight3D, c: Color, pitch: float, yaw: float, energy_scale: float) -> void:
	if not is_instance_valid(light) or not light.is_inside_tree():
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
	_env.fog_enabled = true
	_env.fog_mode = Environment.FOG_MODE_DEPTH
	_env.fog_aerial_perspective = 1.0
	_env.fog_sky_affect = 0.0
	_env.fog_sun_scatter = 0.0
	_env.fog_depth_curve = 1.0
	var diorama: Dictionary = _settings.get("diorama", {})
	if _sky_mat != null:
		var curves: Array = diorama.get("gradient_curves", [1.8, 1.2])
		_sky_mat.set_shader_parameter("gradient_curves", Vector2(float(curves[0]), float(curves[1])))
		for key in ["star_brightness", "star_scale", "sun_radius", "moon_radius"]:
			if diorama.has(key): _sky_mat.set_shader_parameter(key, float(diorama[key]))
	_apply_hearthblock_environment()
	hearthblock_lighting_changed.emit(hearthblock_active())


# ── Hearthblock lighting (docs/00_dev_roadmap/255_hearthblock_lighting_pass.md) ─

## Data for the lighting pass; empty when the block is absent.
func hearthblock_settings() -> Dictionary:
	return _settings.get("hearthblock_lighting", {}).duplicate(true)


## True only in the main world scene. Previews, galleries and isolated test
## scenes keep their authored look.
func hearthblock_active() -> bool:
	var scene := get_tree().current_scene if is_inside_tree() else null
	return is_instance_valid(scene) and scene.scene_file_path == WORLD_SCENE_PATH


## Tone mapping and glow on the bound world Environment. Other scenes keep the
## values authored on their own Environment.
func _apply_hearthblock_environment() -> void:
	if _env == null or not hearthblock_active():
		return
	var look := hearthblock_settings()
	_env.tonemap_mode = {
		"linear": Environment.TONE_MAPPER_LINEAR, "filmic": Environment.TONE_MAPPER_FILMIC,
		"aces": Environment.TONE_MAPPER_ACES, "agx": Environment.TONE_MAPPER_AGX,
	}.get(String(look.get("tonemap", "aces")), Environment.TONE_MAPPER_ACES)
	_env.tonemap_exposure = float(look.get("exposure", 1.0))
	_env.tonemap_white = float(look.get("white", 1.0))
	var glow: Dictionary = look.get("glow", {})
	_env.glow_enabled = not glow.is_empty()
	if glow.is_empty():
		return
	_env.glow_intensity = float(glow.get("intensity", 0.8))
	_env.glow_strength = float(glow.get("strength", 1.0))
	_env.glow_bloom = float(glow.get("bloom", 0.0))
	_env.glow_hdr_threshold = float(glow.get("hdr_threshold", 1.0))
	_env.glow_hdr_scale = float(glow.get("hdr_scale", 2.0))
	_env.glow_blend_mode = {
		"additive": Environment.GLOW_BLEND_MODE_ADDITIVE, "screen": Environment.GLOW_BLEND_MODE_SCREEN,
		"softlight": Environment.GLOW_BLEND_MODE_SOFTLIGHT, "mix": Environment.GLOW_BLEND_MODE_MIX,
	}.get(String(glow.get("blend", "screen")), Environment.GLOW_BLEND_MODE_SCREEN)
	var glow_levels: Array = glow.get("levels", [])
	for i in range(mini(7, glow_levels.size())): _env.set_glow_level(i, float(glow_levels[i]))


# ── Helpers ───────────────────────────────────────────────────────────────────

func _day_hours() -> float:
	return float(WorldClock.hours_per_day())


func _current_hour() -> float:
	if _clock != null:
		return float(_clock.get("hour"))
	return 12.0


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
