extends Node

## The player's video settings (doc 23, the game menu's Settings; doc 21, frame pacing): how
## the game fills the screen, the world's render scale, the frame rate, VSync, shadows and
## anti-aliasing, and the UI scale the Interface tab shows (doc 23). The settings, their
## choices and their defaults come from video_settings.json. Each Video default is what the
## game does unaided, so nothing changes until the player chooses; the UI scale starts at
## Auto, the scale Windows sets for the screen. The choices are kept in user://video.cfg,
## for every colony, and apply the moment they change. Headless, the display calls and the
## frame cap are skipped; the values still change.
## The UI scale is the window's content scale, so this is its one owner: it applies while
## the window draws at its own size, as the game does, and a tool that stretches the window
## for captures keeps the scale at 1. Set it through set_value("ui_scale", ...).
signal preferences_changed

const CONFIG_PATH := "res://data/video/video_settings.json"
const WINDOW_MODES := {"borderless": DisplayServer.WINDOW_MODE_FULLSCREEN,
	"fullscreen": DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN, "windowed": DisplayServer.WINDOW_MODE_WINDOWED}
const MSAA := {0: Viewport.MSAA_DISABLED, 2: Viewport.MSAA_2X, 4: Viewport.MSAA_4X}
const SMALLEST_WINDOW := Vector2i(960, 540)   # the menu's small size still fits

var config: Dictionary = {}
## Tests: a refresh rate in place of the screen's.
var refresh_override := 0.0
## Tests: a screen DPI in place of the screen's (96 is Windows' 100%).
var dpi_override := 0.0
var _preferences_path := "user://video.cfg"
var _windowless := DisplayServer.get_name() == "headless"
var _settings := {}   # id -> its definition
var _values := {}
var _window_size := Vector2i.ZERO   # the window's size while windowed, kept for next time
var _pacing := false   # the frame cap applies once the world's camera starts
var _save_left := -1.0


func _ready() -> void:
	config = preload("res://scripts/registries/JsonData.gd").read_dict(CONFIG_PATH)
	for setting: Dictionary in config.get("settings", []):
		_settings[String(setting.id)] = setting
	set_process(false)
	get_viewport().size_changed.connect(_on_window_resized)
	reload_preferences(true)


func _exit_tree() -> void:
	if _save_left >= 0: save_preferences()


func _process(delta: float) -> void:
	_save_left -= delta
	if _save_left < 0: save_preferences()


## The settings in the order the page shows them: each one's id, title, about and default,
## with its choices or its slider's range.
func settings() -> Array:
	return config.get("settings", [])


func value(id: String) -> Variant:
	return _values.get(id)


func default_value(id: String) -> Variant:
	var fallback: Variant = _settings[id].default
	match id:
		"render_scale": return float(fallback)
		"frame_rate": return int(fallback)
	return String(fallback)


## Sets one setting, applies it at once and keeps it.
func set_value(id: String, new_value: Variant) -> void:
	if not _settings.has(id): return
	var checked: Variant = _valid(id, new_value)
	var was: Variant = _values.get(id)
	if typeof(checked) == typeof(was) and checked == was: return   # the UI scale is "auto" or a number
	_values[id] = checked
	_apply(id)
	_save_soon()
	preferences_changed.emit()


## Puts the settings back to their defaults: those of one Settings section ("video" or
## "interface"), or all of them.
func restore_defaults(section := "") -> void:
	for id: String in _settings:
		if not section.is_empty() and section_of(id) != section: continue
		_values[id] = default_value(id)
		_apply(id)
	_save_soon()
	preferences_changed.emit()


## The Settings tab a setting shows on.
func section_of(id: String) -> String:
	return String(_settings[id].get("section", "video"))


## Reads the player's choices; anything missing or malformed falls back to its default. At
## startup the window keeps the mode and VSync it opened with unless the player chose
## otherwise, so the command line's --windowed or --disable-vsync still count.
func reload_preferences(starting := false) -> void:
	var prefs := ConfigFile.new()
	prefs.load(_preferences_path)
	for id: String in _settings:
		_values[id] = _valid(id, prefs.get_value("video", id, default_value(id)))
	var size: Variant = prefs.get_value("window", "size", Vector2i.ZERO)
	_window_size = size if size is Vector2i else Vector2i.ZERO
	for id: String in _settings:
		if starting and id in ["display", "vsync"] and _values[id] == default_value(id): continue
		_apply(id)
	preferences_changed.emit()


func save_preferences() -> void:
	var prefs := ConfigFile.new()
	for id: String in _settings:
		prefs.set_value("video", id, _values[id])
	if _window_size != Vector2i.ZERO: prefs.set_value("window", "size", _window_size)
	var error := prefs.save(_preferences_path)
	if error != OK: push_warning("Could not save video settings: " + error_string(error))
	_save_left = -1.0
	set_process(false)


## The world's camera starts frame pacing (doc 21): from then on the Frame rate setting caps
## Engine.max_fps. Tools that never start the camera stay uncapped.
func pace_frames() -> void:
	_pacing = true
	_apply("frame_rate")
	if not _windowless: print("VideoSettings: frame pacing %d fps on a %.0f Hz display." % [Engine.max_fps, refresh_rate()])


## The screen's refresh rate, or 60 when the screen does not say.
func refresh_rate() -> float:
	if refresh_override > 0.0: return refresh_override
	var rate := -1.0 if _windowless else DisplayServer.screen_get_refresh_rate(DisplayServer.window_get_current_screen())
	return rate if rate > 0.0 else 60.0


## The frame rates on offer: the even shares of the refresh rate, highest first.
func frame_rates() -> Array[int]:
	var setting: Dictionary = _settings.frame_rate
	var rates: Array[int] = []
	for share in range(1, int(setting.shares) + 1):
		var fps := roundi(refresh_rate() / share)
		if fps >= int(setting.lowest) and not rates.has(fps): rates.append(fps)
	return rates


## The frame cap that applies: the largest even share of the refresh rate not above the
## chosen rate, so every frame stays on screen equally long. The half frame absorbs the
## rounding of the rates on offer (165 Hz offers 41 for 41.25).
func frame_rate() -> int:
	var refresh := refresh_rate()
	return roundi(refresh / maxi(1, ceili(refresh / (float(_values.frame_rate) + 0.5) - 0.01)))


## The world's resolution at the render scale, in the screen's pixels: the UI scale changes
## only the room the interface lays out in.
func render_size() -> Vector2i:
	return Vector2i((Vector2(get_window().size) * float(_values.render_scale)).round())


# ── UI scale (doc 23) ─────────────────────────────────────────────────────────

## The display scale Windows sets for the screen the game is on, in percent: the screen's DPI
## over 96 (Godot's screen scale says 1.0 on Windows). Headless, or where the screen says
## less, 100.
func system_scale() -> int:
	var dpi := dpi_override
	if dpi <= 0.0: dpi = 96.0 if _windowless else float(DisplayServer.screen_get_dpi(DisplayServer.window_get_current_screen()))
	return roundi(maxf(dpi, 96.0) / 96.0 * 100.0)


## The UI scale steps the window has room for, in percent, smallest first: those that leave
## the interface at least SMALLEST_WINDOW to lay out in. 100% always.
func ui_scales() -> Array[int]:
	var window := Vector2(get_window().size)
	var steps: Array[int] = []
	for step: Variant in _settings.ui_scale.steps:
		var room := window * 100.0 / float(step)
		if int(step) == 100 or (room.x >= SMALLEST_WINDOW.x and room.y >= SMALLEST_WINDOW.y): steps.append(int(step))
	return steps


## The UI scale in effect, in percent: the chosen step, or for Auto the largest step not above
## Windows' scale, lowered to the largest step the window has room for.
func ui_percent() -> int:
	var wanted: int = system_scale() if _values.ui_scale is String else int(_values.ui_scale)
	var percent := 100
	for step: int in ui_scales():
		if step <= wanted: percent = step
	return percent


func ui_scale() -> float:
	return ui_percent() / 100.0


## The room the interface lays out in: the window's size over the UI scale.
func layout_size() -> Vector2i:
	return Vector2i((Vector2(get_window().size) / ui_scale()).round())


func _valid(id: String, raw: Variant) -> Variant:
	var setting: Dictionary = _settings[id]
	var number := (raw is float or raw is int) and is_finite(float(raw))
	match id:
		"render_scale":
			if not number: return default_value(id)
			return clampf(snappedf(float(raw), float(setting.step)), float(setting.min), float(setting.max))
		"frame_rate":
			return int(raw) if number and float(raw) >= float(setting.lowest) else default_value(id)
		"ui_scale":
			if number:
				for step: Variant in setting.steps:
					if is_equal_approx(float(raw), float(step)): return int(step)
			return raw if raw is String and raw == "auto" else default_value(id)
	for choice: Dictionary in setting.get("choices", []):
		if raw is String and raw == String(choice.id): return raw
	return default_value(id)


func _choice(id: String) -> Dictionary:
	for choice: Dictionary in _settings[id].get("choices", []):
		if String(choice.id) == _values[id]: return choice
	return {}


func _apply(id: String) -> void:
	var view := get_viewport()
	match id:
		"display":
			_apply_display()
		"render_scale":
			var scale: float = _values.render_scale
			view.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if scale < 1.0 else Viewport.SCALING_3D_MODE_BILINEAR
			view.scaling_3d_scale = scale
		"frame_rate":
			if _pacing and not _windowless: Engine.max_fps = frame_rate()
		"vsync":
			if not _windowless:
				DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if _values.vsync == "on" else DisplayServer.VSYNC_DISABLED)
		"shadows":
			var preset := _choice(id)
			var quality := int(preset.soft_quality) as RenderingServer.ShadowQuality
			RenderingServer.directional_shadow_atlas_set_size(int(preset.directional_size),
				bool(ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/16_bits", true)))
			RenderingServer.directional_soft_shadow_filter_set_quality(quality)
			RenderingServer.positional_soft_shadow_filter_set_quality(quality)
			view.positional_shadow_atlas_size = int(preset.positional_size)
		"anti_aliasing":
			var preset := _choice(id)
			view.msaa_3d = MSAA[int(preset.msaa)]
			view.screen_space_aa = Viewport.SCREEN_SPACE_AA_SMAA if bool(preset.smaa) else Viewport.SCREEN_SPACE_AA_DISABLED
		"ui_scale":
			var window := get_window()
			var scale := ui_scale() if window.content_scale_mode == Window.CONTENT_SCALE_MODE_DISABLED else 1.0
			if not is_equal_approx(window.content_scale_factor, scale): window.content_scale_factor = scale


## Windowed opens at its kept size, or a share of the screen, centred on the screen it is on.
func _apply_display() -> void:
	if _windowless: return
	var mode: DisplayServer.WindowMode = WINDOW_MODES[_values.display]
	if DisplayServer.window_get_mode() == mode: return
	DisplayServer.window_set_mode(mode)
	if mode != DisplayServer.WINDOW_MODE_WINDOWED: return
	var area := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	var size := _window_size if _window_size != Vector2i.ZERO else Vector2i(Vector2(area.size) * float(config.window_screen_share))
	size = size.clamp(SMALLEST_WINDOW, area.size)
	DisplayServer.window_set_size(size)
	DisplayServer.window_set_position(area.position + (area.size - size) / 2)


## A resize can change the UI scale steps the window has room for. While windowed, the
## window's size is kept for next time.
func _on_window_resized() -> void:
	if _values.has("ui_scale"): _apply("ui_scale")
	if _windowless or _values.get("display") != "windowed": return
	if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED: return
	_window_size = DisplayServer.window_get_size()
	_save_soon()


func _save_soon() -> void:
	_save_left = .4
	set_process(true)
