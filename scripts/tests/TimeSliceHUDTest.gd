extends "res://scripts/tests/WorkerCraftingTest.gd"

## Real UI input and authoritative SliceController, without a generated world.
const OUT := "res://tmp/time_slice_20261012/"
class SliceRenderer extends Node:
	var slice_y := 127

## The X-ray controller's interface as the HUD uses it; the HUD only presents it.
class XrayStub extends Node:
	signal changed
	var mode := "off"
	var last_mode := "full"
	var show_reference := true
	var reference_y := 40
	var working := false
	func toggle() -> void:
		mode = last_mode if mode == "off" else "off"
		changed.emit()
	func set_mode(value: String) -> void:
		mode = value
		last_mode = value
		changed.emit()
	func set_reference_enabled(enabled: bool) -> void:
		show_reference = enabled
		changed.emit()
	func pin_reference() -> void:
		reference_y = 47
		changed.emit()

## The Appeal view's interface as the HUD uses it.
class AppealStub extends Node:
	signal changed
	var active := false
	func toggle() -> void:
		active = not active
		changed.emit()

class WorldInputProbe extends Node:
	var scrolls := 0
	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]: scrolls += 1

var slice: Node
var hud: Control
var world_input: Node


func _run() -> void:
	create_timer(75).timeout.connect(func(): push_error("Time/Slice HUD timed out"); quit(1))
	await _setup_crafting_fixture()
	root.get_node("WorldGenerator").waterline_map.resize(1024*1024)
	root.get_node("WorldGenerator").waterline_map.fill(-1)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var renderer := SliceRenderer.new()
	renderer.name = "SliceRenderer"
	scene.add_child(renderer)
	var camera := Node3D.new()
	camera.name = "SliceCamera"
	camera.position = Vector3(40, 20, 40)
	scene.add_child(camera)
	slice = load("res://scripts/systems/SliceController.gd").new()
	slice.renderer_path = NodePath("../SliceRenderer")
	slice.camera_path = NodePath("../SliceCamera")
	slice.dock_ui_path = NodePath("../Dock")
	scene.add_child(slice)
	hud = dock._time_slice_hud
	world_input = WorldInputProbe.new()
	scene.add_child(world_input)
	await _frames(6)
	_expect(not manager.has_window("slice_palette"), "Slice never creates a floating window")
	_expect(not hud.tower.visible, "Slice off: the arrows stay hidden (doc 259)")
	for button in hud.step_buttons.values(): _expect(button.disabled, "inactive arrows are disabled")
	_click(hud.slice_button.get_global_rect().get_center())
	_expect(slice.is_active() and slice.get_slice_y() == 23, "first click seeds from camera surface")
	slice.show_at_height(47)
	for spec in [["up_one",48], ["up_four",52], ["down_one",51], ["down_four",47]]:
		_click(hud.step_buttons[spec[0]].get_global_rect().get_center())
		_expect(slice.get_slice_y() == spec[1] and hud.readout.text == str(spec[1]), "actual " + spec[0] + " moves an exact offset")
	var scroll_point: Vector2 = hud._plate.get_global_rect().get_center()
	_wheel(scroll_point, true)
	_expect(slice.get_slice_y() == 48, "wheel raises one level over readout")
	_wheel(scroll_point, false, true)
	_expect(slice.get_slice_y() == 44, "Ctrl + wheel lowers four levels")
	_expect(world_input.scrolls == 0, "HUD wheel does not reach world camera input")
	_wheel(Vector2(32, 32), true)
	_expect(world_input.scrolls == 1 and slice.get_slice_y() == 44, "wheel over world remains available for camera zoom")
	_wheel(hud.step_buttons.up_four.get_global_rect().get_center(), true)
	_expect(slice.get_slice_y() == 45 and world_input.scrolls == 1, "wheel on arrow buttons also belongs to tower")
	_wheel(hud.position + Vector2(10, 10), false)
	_expect(world_input.scrolls == 2 and slice.get_slice_y() == 45, "empty area beside tower passes input through")
	slice.show_at_height(44)
	_key(KEY_BRACKETRIGHT)
	_expect(slice.get_slice_y() == 48, "plain bracket raises exactly four")
	_key(KEY_BRACKETLEFT, true)
	_expect(slice.get_slice_y() == 47, "Ctrl + bracket moves one without double firing")
	slice.show_at_height(125)
	_click(hud.step_buttons.up_four.get_global_rect().get_center())
	_expect(slice.get_slice_y() == 127 and hud.step_buttons.up_four.disabled and hud.step_buttons.up_one.disabled, "upper bound clamps and disables both up arrows")
	slice.show_at_height(6)
	_click(hud.step_buttons.down_four.get_global_rect().get_center())
	_expect(slice.get_slice_y() == 4 and hud.step_buttons.down_four.disabled and hud.step_buttons.down_one.disabled, "lower bound clamps and disables both down arrows")
	slice.show_at_height(47)
	var before: Rect2 = hud.tower.get_global_rect()
	_click(hud.slice_button.get_global_rect().get_center())
	_expect(not slice.is_active() and slice.get_slice_y() == 127, "Slice off shows complete terrain")
	_expect(not hud.tower.visible, "turning Slice off hides the arrows")
	_wheel(scroll_point, true)
	slice.step_single_down()
	_key(KEY_BRACKETLEFT)
	_expect(slice.get_slice_y() == 127, "inactive wheel, keys and stepping cannot move plane")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(slice.serialize_state()))
	slice.show_at_height(80)
	slice.restore_state(saved)
	_key(KEY_BACKSLASH)
	_expect(slice.is_active() and slice.get_slice_y() == 47 and hud.readout.text == "47", "save/restore and keyboard toggle recover previous height")
	_expect(hud.tower.visible and hud.tower.get_global_rect() == before, "the arrows return above Slice, in the same place")
	saved = JSON.parse_string(JSON.stringify(slice.serialize_state()))
	slice.deactivate()
	slice.restore_state(saved)
	_expect(slice.is_active() and hud.slice_button.button_pressed and hud.readout.text == "47", "loading an active slice refreshes controls immediately")
	# X-ray is one button beside Slice; its options show only while it is on (doc 259).
	_expect(not hud.xray_button.visible, "without an X-ray controller there is no X-ray button")
	var xray := XrayStub.new()
	xray.mode = "off"
	scene.add_child(xray)
	hud.bind_xray(xray)
	await _frames(3)
	for resolution in [Vector2i(1280,720), Vector2i(960,540), Vector2i(2560,1440), Vector2i(800,600)]:
		root.size = resolution
		await _frames(8)
		var bounds := Rect2(Vector2.ZERO, Vector2(resolution))
		# Option B (doc 259): pause and speed under the Sky Dial; Appeal, X-ray and Slice are
		# the dock's last group, looking and sized like its other icons.
		var dial_rect: Rect2 = dock._sky_dial.get_global_rect()
		var time_rect: Rect2 = hud.time_panel.get_global_rect()
		var dock_rect: Rect2 = dock._dock_panel.get_global_rect()
		var row: Control = dock._dock_row
		_expect(time_rect.position.y >= dial_rect.end.y and absf(time_rect.get_center().x - dial_rect.get_center().x) < 1.0,
			"pause and speed sit centred under the Sky Dial " + str(resolution))
		_expect(hud.xray_button.get_parent() == row and hud.slice_button.get_index() == row.get_child_count() - 1
			and hud.xray_button.get_index() == row.get_child_count() - 2 and hud.appeal_button.get_index() == row.get_child_count() - 3
			and not row.get_child(row.get_child_count() - 4) is Button,
			"Appeal, X-ray and Slice end the dock as their own group " + str(resolution))
		for button: Button in [hud.xray_button, hud.slice_button]:
			_expect(button.size == dock._button_by_target.orders.size and button.text.is_empty() and dock_rect.encloses(button.get_global_rect()),
				"view toggles are dock icons of the same size, without captions " + str(resolution))
		_expect(absf(dock_rect.get_center().x - resolution.x * 0.5) < 1.0, "the dock stays centred " + str(resolution))
		_expect(hud.tower.get_global_rect().end.y <= dock_rect.position.y and absf(hud.tower.get_global_rect().get_center().x - hud.slice_button.get_global_rect().get_center().x) < 1.0,
			"the arrows rise from the Slice button " + str(resolution))
		for rect: Rect2 in [hud.tower.get_global_rect(), hud.xray_panel.get_global_rect()]:
			_expect(not rect.intersects(time_rect) and not rect.intersects(dial_rect), "the arrows and X-ray options stay clear of the clock " + str(resolution))
		for rect: Rect2 in hud.occupied_rects():
			_expect(bounds.encloses(rect), "HUD fits " + str(resolution))
			_expect(not rect.intersects(dock._dock_panel.get_global_rect()), "utility clears main dock " + str(resolution))
			_expect(not rect.intersects(dock._sky_dial.get_global_rect()), "utility clears Sky Dial " + str(resolution))
		hud.step_buttons.up_four.grab_focus()
		await create_timer(.35).timeout
		await _frames(2)
		_expect(hud.step_buttons.up_four._info.visible and bounds.encloses(hud.step_buttons.up_four._info.get_global_rect()), "keyboard focus reveals readable four-level help " + str(resolution))
		# The hover card (doc 259, option C): the system family's colour on top, a white title
		# and the real key on a keycap.
		var card: Control = hud.step_buttons.up_four._info
		var system: Color = root.get_node("UIRegistry").get_icon_family_color("system")
		var top: int = card.get_script().POINTER_ROWS * card._cell if card._side == "below" else 0
		_expect(_near(card._art.get_image().get_pixel(card._art.get_width() >> 1, top + card._cell * 3 + 1), system)
			and card._title.text == "Raise 4 levels" and card._title.get_theme_color("font_color") == UITheme.CARD_TITLE
			and card.shown_keys() == PackedStringArray(["]"]), "hover card wears its family's colour and shows the key from the input map " + str(resolution))
		_expect(card.get_global_rect().end.y <= hud.step_buttons.up_four.get_global_rect().position.y
			or card.get_global_rect().position.y >= hud.step_buttons.up_four.get_global_rect().end.y, "hover card never covers its button " + str(resolution))
		hud.step_buttons.up_four.release_focus()
		_click(hud.speed_buttons[2].get_global_rect().get_center())
		_expect(not clock_node.paused and clock_node.speed == 2 and hud.speed_buttons[2].button_pressed, "Fast resumes at 2×")
		_click(hud.speed_buttons[0].get_global_rect().get_center())
		_expect(clock_node.paused and hud.speed_buttons[0].button_pressed, "Pause has a visible active state")
		_click(hud.speed_buttons[0].get_global_rect().get_center())
		_expect(not clock_node.paused and clock_node.speed == 2, "Pause resumes previous speed")
		_click(hud.speed_buttons[1].get_global_rect().get_center())
		_expect(not clock_node.paused and clock_node.speed == 1 and hud.speed_buttons[1].button_pressed, "Play resumes at 1×")
		for menu in ["construction", "development", "craft"]:
			dock._open_action_panel(menu)
			await _frames(5)
			for rect: Rect2 in hud.occupied_rects():
				_expect(not rect.intersects(dock._panel_container.get_global_rect()), "open " + menu + " clears utility controls " + str(resolution))
			if menu == "development": await _capture_hud("development_%d" % resolution.x)
			dock._close_action_panel()
		hud.speed_buttons[1].release_focus()
		await _capture_hud("active_%d" % resolution.x)
		_click(hud.slice_button.get_global_rect().get_center())
		hud.slice_button.release_focus()
		await _frames(3)
		await _capture_hud("full_world_%d" % resolution.x)
		_click(hud.slice_button.get_global_rect().get_center())
		_expect(slice.get_slice_y() == 47, "toggle after resize retains height")
	_expect(hud.xray_button.visible and not hud.xray_panel.visible, "X-ray off: one button and no options")
	_expect(hud.xray_button.icon is Texture2D and hud.slice_button.icon is Texture2D, "view toggles show Hearthblock icons")
	_click(hud.xray_button.get_global_rect().get_center())
	await _frames(3)
	_expect(xray.mode == "full" and hud.xray_button.button_pressed and hud.xray_panel.visible, "X-ray on: the button is lit and its options show")
	_expect(hud.reference_readout.text == "Guide: level 40", "the options name the guide level")
	_click(hud.xray_modes.flat.get_global_rect().get_center())
	_expect(xray.mode == "flat", "Flat switches the X-ray mode")
	_click(hud.reference_pin.get_global_rect().get_center())
	_expect(hud.reference_readout.text == "Guide: level 47", "Pin moves the guide to this level")
	_click(hud.xray_button.get_global_rect().get_center())
	await _frames(3)
	_expect(xray.mode == "off" and not hud.xray_panel.visible, "turning X-ray off hides its options")
	await _check_keys(xray)
	await _check_banner(xray)
	for failure in failures: push_error(failure)
	print("TIME_SLICE_HUD_OK: real clicks, keys, wheel routing, exact offsets, bounds, save/restore, speed, time and view keys and responsive layouts" if failures.is_empty() else "TIME_SLICE_HUD_FAIL")
	quit(0 if failures.is_empty() else 1)


## The time and view keys (doc 23 "Keys"): Space pauses and resumes even with a button in
## focus, 1 and 2 pick the speed, V and X switch the views as their buttons do, and the
## buttons' hover cards name them. A text field keeps its keys, and Space does nothing while
## the clock is held.
func _check_keys(xray: Node) -> void:
	var appeal := AppealStub.new()
	scene.add_child(appeal)
	hud.bind_appeal(appeal)
	var hints := [hud.speed_buttons[0].key_hint, hud.speed_buttons[1].key_hint, hud.speed_buttons[2].key_hint,
		hud.appeal_button.key_hint, hud.xray_button.key_hint]
	_expect(hints == ["Space", "1", "2", "V", "X"], "the time and view buttons' hover cards name their keys " + str(hints))
	_key(KEY_1)
	_expect(not clock_node.paused and clock_node.speed == 1 and hud.speed_buttons[1].button_pressed, "1 runs at normal speed")
	_key(KEY_2)
	_expect(not clock_node.paused and clock_node.speed == 2 and hud.speed_buttons[2].button_pressed, "2 runs at fast speed")
	hud.speed_buttons[1].grab_focus()
	_key(KEY_SPACE)
	_expect(clock_node.paused and clock_node.speed == 2 and hud.speed_buttons[0].button_pressed,
		"Space pauses, even with a button in focus that it would otherwise press")
	_key(KEY_SPACE)
	_expect(not clock_node.paused and clock_node.speed == 2, "Space again resumes at the previous speed")
	hud.speed_buttons[1].release_focus()
	var field := LineEdit.new()
	hud.get_parent().add_child(field)
	field.grab_focus()
	for code: Key in [KEY_SPACE, KEY_1, KEY_V, KEY_X]: _key(code)
	_expect(field.text == " 1VX" and not clock_node.paused and clock_node.speed == 2 and not appeal.active and xray.mode == "off",
		"a text field keeps the keys it types")
	field.queue_free()
	await _frames(1)
	clock_node.hold_for_loading(world_input, true)
	_key(KEY_SPACE)
	clock_node.hold_for_loading(world_input, false)
	_expect(not clock_node.paused, "Space does nothing while the clock is held (the game menu, loading)")
	_key(KEY_V)
	await _frames(2)
	_expect(appeal.active and hud.appeal_button.button_pressed and hud.appeal_panel.visible, "V turns the Appeal view on, as its button")
	_key(KEY_X)
	await _frames(2)
	_expect(xray.mode != "off" and hud.xray_button.button_pressed and hud.xray_panel.visible, "X turns X-ray on, as its button")
	_key(KEY_X, true)
	_expect(xray.mode != "off", "Ctrl + X is not X-ray's key")
	_key(KEY_X)
	_key(KEY_V)
	await _frames(2)
	_expect(xray.mode == "off" and not appeal.active and not hud.appeal_panel.visible and not hud.xray_panel.visible,
		"X and V again turn the views off")


## The view banner (doc 23, "Views"): while a view is on, the top centre names it with one
## line on what it shows and how to leave, toasts sit below it, and it fits small screens.
## X-ray's line steps aside while a tool works; Appeal's stays.
func _check_banner(xray: Node) -> void:
	var appeal: Node = hud._appeal
	var banner: Control = dock._view_banner
	banner.bind("appeal", appeal)
	banner.bind("xray", xray)
	await _frames(2)
	_expect(not banner.visible and dock._toasts.reserved_top == 0.0, "no view on: no banner, and the toasts keep the top")
	for resolution in [Vector2i(960,540), Vector2i(1280,720), Vector2i(2560,1440)]:
		root.size = resolution
		appeal.toggle()
		await _frames(3)
		var rect: Rect2 = banner.get_global_rect()
		_expect(banner.visible and banner._rows.appeal.row.visible and not banner._rows.xray.row.visible
			and banner._rows.appeal.name.text == "Appeal view"
			and banner._rows.appeal.line.text == "How each room feels to the dwarves · V or its button to leave",
			"Appeal on: the banner names it, with what it shows and how to leave " + str(resolution))
		_expect(absf(rect.get_center().x - resolution.x * 0.5) <= 1.0 and Rect2(Vector2.ZERO, Vector2(resolution)).encloses(rect),
			"the banner sits at the top centre, on screen " + str(resolution))
		dock.show_persistence_status("Saved")
		await _frames(3)
		_expect(dock._toasts.get_child(0).get_global_rect().position.y >= rect.end.y, "toasts sit below the banner " + str(resolution))
		for toast: Node in dock._toasts.get_children(): dock._toasts._drop(toast)
		if resolution.x == 1280: await _capture_hud("banner_%d" % resolution.x)
		appeal.toggle()
		await _frames(3)
	appeal.toggle()
	xray.toggle()
	await _frames(3)
	_expect(banner._rows.appeal.row.visible and banner._rows.xray.row.visible and banner._rows.xray.name.text == "X-ray view"
		and banner._rows.xray.line.text.ends_with("X or its button to leave"), "both views on: a line each")
	xray.working = true
	xray.changed.emit()
	await _frames(3)
	_expect(banner.visible and banner._rows.appeal.row.visible and not banner._rows.xray.row.visible,
		"X-ray steps aside while a tool works, and its line with it; Appeal's stays")
	xray.working = false
	xray.toggle()
	appeal.toggle()
	await _frames(3)
	_expect(not banner.visible and dock._toasts.reserved_top == 0.0, "views off: the banner goes and the toasts take the top again")


func _wheel(point: Vector2, up: bool, ctrl := false) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
	event.ctrl_pressed = ctrl
	event.pressed = true
	root.push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event, true)


func _key(code: Key, ctrl := false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	# What the key types, as a text field receives it.
	event.unicode = code if code >= KEY_SPACE and code <= KEY_ASCIITILDE and not ctrl else 0
	event.ctrl_pressed = ctrl
	event.pressed = true
	root.push_input(event)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event)


func _capture_hud(filename: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	await _frames(3)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + filename + ".png")

## Cell art stores 8 bits a channel, so colours compare within one step.
static func _near(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.006 and absf(a.g - b.g) < 0.006 and absf(a.b - b.b) < 0.006 and absf(a.a - b.a) < 0.006
