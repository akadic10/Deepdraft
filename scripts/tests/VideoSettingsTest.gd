extends SceneTree

## VideoSettings (doc 23, the game menu's Video and Interface tabs; doc 21, frame pacing):
## the Video defaults are what the game does unaided; the frame rates on offer are the even
## shares of the refresh rate, and the chosen one reaches Engine.max_fps once the camera
## paces frames; render scale, shadows and anti-aliasing reach the root viewport. The UI
## scale starts at Auto, Windows' scale as the largest step not above it, offers
## only the steps the window has room for, and reaches the window's content scale, while the
## world's resolution stays in the screen's pixels. The choices survive a reload, malformed
## ones fall back to the defaults, and Restore defaults puts back everything or one tab's.
## The choices go to a test file.
const PREFS := "user://video_settings_test.cfg"
var failures: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var video = root.get_node("VideoSettings")
	var window_before := root.size
	video._preferences_path = PREFS
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	video.reload_preferences()
	var changes := [0]
	video.preferences_changed.connect(func(): changes[0] += 1)
	# The defaults are what the game does unaided.
	for entry: Array in [["display", "borderless"], ["render_scale", 1.0], ["frame_rate", 75], ["vsync", "on"], ["shadows", "high"],
			["anti_aliasing", "off"], ["ui_scale", "auto"]]:
		_expect(_same(video.value(entry[0]), entry[1]), "the default %s is %s (got %s)" % [entry[0], entry[1], video.value(entry[0])])
	_expect(root.scaling_3d_scale == 1.0 and root.scaling_3d_mode == Viewport.SCALING_3D_MODE_BILINEAR and root.msaa_3d == Viewport.MSAA_DISABLED
		and root.screen_space_aa == Viewport.SCREEN_SPACE_AA_DISABLED and root.positional_shadow_atlas_size == 4096,
		"the defaults leave the viewport as the engine has it")
	_expect(is_equal_approx(root.content_scale_factor, 1.0), "headless, Auto is 100%: the interface draws at the window's size")
	# Frame rates: the even shares of the refresh rate; the default 75 paces as before.
	for entry: Array in [[60.0, [60, 30], 60], [120.0, [120, 60, 40, 30], 60], [144.0, [144, 72, 48, 36], 72], [165.0, [165, 83, 55, 41], 55]]:
		video.refresh_override = entry[0]
		video.set_value("frame_rate", 75)
		_expect(Array(video.frame_rates()) == entry[1] and video.frame_rate() == entry[2],
			"%d Hz offers %s and paces the default at %d (got %s and %d)" % [entry[0], entry[1], entry[2], video.frame_rates(), video.frame_rate()])
		for fps: int in video.frame_rates():
			video.set_value("frame_rate", fps)
			_expect(video.frame_rate() == fps, "choosing %d fps at %d Hz caps at %d (got %d)" % [fps, entry[0], fps, video.frame_rate()])
	video.refresh_override = 120.0
	video.set_value("frame_rate", 40)
	video._windowless = false   # headless skips the cap; here it must reach the engine
	video.pace_frames()
	_expect(Engine.max_fps == 40, "once the camera paces frames, the chosen rate caps Engine.max_fps (got %d)" % Engine.max_fps)
	video.set_value("frame_rate", 120)
	_expect(Engine.max_fps == 120, "a new frame rate applies at once (got %d)" % Engine.max_fps)
	video._windowless = true
	Engine.max_fps = 0
	video.set_value("frame_rate", 10)
	_expect(video.value("frame_rate") == 75, "a rate below the lowest falls back to the default")
	# Render scale, shadows and anti-aliasing reach the root viewport.
	video.set_value("render_scale", 0.75)
	_expect(is_equal_approx(root.scaling_3d_scale, .75) and root.scaling_3d_mode == Viewport.SCALING_3D_MODE_FSR,
		"75% draws the world smaller and upscales it with FSR")
	_expect(video.render_size() == Vector2i((Vector2(root.size) * .75).round()), "the world's resolution follows the render scale")
	video.set_value("render_scale", 0.77)
	_expect(is_equal_approx(video.value("render_scale"), .75), "render scale moves in steps of 5%")
	video.set_value("render_scale", 0.2)
	_expect(is_equal_approx(video.value("render_scale"), .5) and is_equal_approx(root.scaling_3d_scale, .5), "render scale stops at 50%")
	video.set_value("render_scale", 1.0)
	_expect(root.scaling_3d_scale == 1.0 and root.scaling_3d_mode == Viewport.SCALING_3D_MODE_BILINEAR, "100% draws the world at full size, without FSR")
	video.set_value("shadows", "low")
	_expect(root.positional_shadow_atlas_size == 1024, "Low shadows shrink the shadow atlas")
	video.set_value("shadows", "medium")
	_expect(root.positional_shadow_atlas_size == 2048, "Medium shadows halve the shadow atlas")
	video.set_value("anti_aliasing", "smaa")
	_expect(root.screen_space_aa == Viewport.SCREEN_SPACE_AA_SMAA and root.msaa_3d == Viewport.MSAA_DISABLED, "SMAA smooths the screen")
	video.set_value("anti_aliasing", "msaa_4x")
	_expect(root.msaa_3d == Viewport.MSAA_4X and root.screen_space_aa == Viewport.SCREEN_SPACE_AA_DISABLED, "MSAA 4× samples each pixel four times")
	video.set_value("display", "windowed")
	video.set_value("vsync", "off")
	_expect(video.value("display") == "windowed" and video.value("vsync") == "off", "display and VSync keep their choices (headless skips the window)")
	_expect(changes[0] > 10, "each change tells the page")
	# The choices survive a reload and apply again.
	video.set_value("frame_rate", 120)
	root.size = Vector2i(3840, 2160)
	video.set_value("ui_scale", 150)
	video.save_preferences()
	video.restore_defaults()
	_expect(root.msaa_3d == Viewport.MSAA_DISABLED and root.positional_shadow_atlas_size == 4096 and video.value("display") == "borderless",
		"Restore defaults puts everything back")
	video.reload_preferences()
	_expect(video.value("display") == "windowed" and video.value("vsync") == "off" and video.value("shadows") == "medium"
		and video.value("anti_aliasing") == "msaa_4x" and video.value("frame_rate") == 120 and root.msaa_3d == Viewport.MSAA_4X
		and root.positional_shadow_atlas_size == 2048 and _same(video.value("ui_scale"), 150) and is_equal_approx(root.content_scale_factor, 1.5),
		"the choices survive a reload and apply again")
	# Malformed choices fall back to the defaults.
	var bad := ConfigFile.new()
	for entry: Array in [["display", "sideways"], ["render_scale", "big"], ["frame_rate", -5], ["vsync", true], ["shadows", 3],
			["anti_aliasing", "msaa_16x"], ["ui_scale", "huge"]]:
		bad.set_value("video", entry[0], entry[1])
	bad.set_value("window", "size", "large")
	bad.save(PREFS)
	video.reload_preferences()
	for id: String in ["display", "render_scale", "frame_rate", "vsync", "shadows", "anti_aliasing", "ui_scale"]:
		_expect(_same(video.value(id), video.default_value(id)), "a malformed %s falls back to its default" % id)
	_expect(root.msaa_3d == Viewport.MSAA_DISABLED and root.scaling_3d_scale == 1.0, "the defaults apply after a malformed file")
	_check_ui_scale(video)
	video.refresh_override = 0.0
	video.dpi_override = 0.0
	root.size = window_before
	video.restore_defaults("interface")
	_expect(is_equal_approx(root.content_scale_factor, 1.0), "the window draws at its own size again")
	video.save_preferences()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	for failure in failures: push_error(failure)
	print("VideoSettingsTest: ", "PASS" if failures.is_empty() else "FAIL (%d)" % failures.size())
	quit(0 if failures.is_empty() else 1)


## The UI scale (doc 23): Auto takes Windows' scale as the largest step not above it; only
## the steps that leave the interface 960 x 540 are offered, and a choice too large for the
## window waits at the largest that fits; the scale reaches the window's content scale, the
## room it leaves is what the interface lays out in, and the world's resolution stays in the
## screen's pixels. A tool that stretches the window keeps the scale at 1, and Restore
## defaults on one tab leaves the other's settings.
func _check_ui_scale(video) -> void:
	video.dpi_override = 144.0   # Windows at 150%
	root.size = Vector2i(7680, 2160)
	_expect(video.system_scale() == 150 and Array(video.ui_scales()) == [100, 125, 150, 200] and video.ui_percent() == 150
		and is_equal_approx(root.content_scale_factor, 1.5) and video.layout_size() == Vector2i(5120, 1440)
		and root.get_visible_rect().size.is_equal_approx(Vector2(5120, 1440)),
		"Auto follows Windows' 150%%: the interface lays out at 5120 x 1440 (got %d%%, %s)" % [video.ui_percent(), root.get_visible_rect().size])
	_expect(video.render_size() == Vector2i(7680, 2160), "the world keeps the screen's full resolution under the UI scale")
	video.dpi_override = 168.0   # 175%
	root.size = Vector2i(3840, 2160)
	_expect(video.ui_percent() == 150, "Windows at 175%% gives the largest step not above it, 150%% (got %d%%)" % video.ui_percent())
	video.dpi_override = 288.0   # 300%
	root.size = Vector2i(7680, 2160)
	_expect(video.ui_percent() == 200 and is_equal_approx(root.content_scale_factor, 2.0), "the steps stop at 200%")
	video.set_value("ui_scale", 125)
	_expect(_same(video.value("ui_scale"), 125) and is_equal_approx(root.content_scale_factor, 1.25)
		and video.layout_size() == Vector2i(6144, 1728), "a chosen step applies at once")
	video.set_value("ui_scale", 175)
	_expect(_same(video.value("ui_scale"), "auto"), "175% is not a step, so the choice falls back to Auto")
	video.set_value("ui_scale", 200)
	for entry: Array in [[Vector2i(1920, 1080), [100, 125, 150, 200], 200], [Vector2i(1280, 720), [100, 125], 125],
			[Vector2i(960, 540), [100], 100], [Vector2i(2560, 1440), [100, 125, 150, 200], 200]]:
		root.size = entry[0]
		_expect(Array(video.ui_scales()) == entry[1] and video.ui_percent() == entry[2]
			and is_equal_approx(root.content_scale_factor, entry[2] / 100.0),
			"at %s the window offers %s and 200%% waits at %d%% (got %s, %d%%)" % [entry[0], entry[1], entry[2], video.ui_scales(), video.ui_percent()])
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.size = Vector2i(1920, 1080)
	_expect(is_equal_approx(root.content_scale_factor, 1.0), "a tool that stretches the window keeps the scale at 1")
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(2560, 1440)
	_expect(is_equal_approx(root.content_scale_factor, 2.0), "the window drawing at its own size takes the scale again")
	video.set_value("shadows", "low")
	video.restore_defaults("video")
	_expect(_same(video.value("ui_scale"), 200) and video.value("shadows") == "high", "Restore defaults on Video leaves the UI scale")
	video.set_value("shadows", "medium")
	video.restore_defaults("interface")
	_expect(_same(video.value("ui_scale"), "auto") and video.value("shadows") == "medium" and is_equal_approx(root.content_scale_factor, 2.0),
		"Restore defaults on Interface puts Auto back, here Windows' 300% as 200%, and leaves the video settings")
	root.size = Vector2i(3840, 2160)


## Equal and of one type: the UI scale is "auto" or a number.
func _same(value: Variant, expected: Variant) -> bool:
	return typeof(value) == typeof(expected) and value == expected


func _expect(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
