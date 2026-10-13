extends "res://scripts/tests/WorkerCraftingTest.gd"

## Real UI input and authoritative SliceController, without a generated world.
const OUT := "res://tmp/time_slice_20261012/"
class SliceRenderer extends Node:
	var slice_y := 127

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
	for entry in root.get_node("UIRegistry").get_menu("system").items:
		_expect(entry.target != "slice", "Menu has no duplicate Slice shortcut")
	_expect(hud.readout.text == "Full\nworld", "inactive view says Full world")
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
	_expect(hud.tower.get_global_rect() == before and hud.readout.text == "Full\nworld", "off state retains fixed tower")
	_wheel(scroll_point, true)
	slice.step_single_down()
	_key(KEY_BRACKETLEFT)
	_expect(slice.get_slice_y() == 127, "inactive wheel, keys and stepping cannot move plane")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(slice.serialize_state()))
	slice.show_at_height(80)
	slice.restore_state(saved)
	_key(KEY_BACKSLASH)
	_expect(slice.is_active() and slice.get_slice_y() == 47 and hud.readout.text == "47", "save/restore and keyboard toggle recover previous height")
	saved = JSON.parse_string(JSON.stringify(slice.serialize_state()))
	slice.deactivate()
	slice.restore_state(saved)
	_expect(slice.is_active() and hud.slice_button.button_pressed and hud.readout.text == "47", "loading an active slice refreshes controls immediately")
	for resolution in [Vector2i(1280,720), Vector2i(960,540), Vector2i(2560,1440), Vector2i(800,600)]:
		root.size = resolution
		await _frames(8)
		var bounds := Rect2(Vector2.ZERO, Vector2(resolution))
		for rect: Rect2 in hud.occupied_rects():
			_expect(bounds.encloses(rect), "HUD fits " + str(resolution))
			_expect(not rect.intersects(dock._dock_panel.get_global_rect()), "utility clears main dock " + str(resolution))
			_expect(not rect.intersects(dock._sky_dial.get_global_rect()), "utility clears Sky Dial " + str(resolution))
		dock._food_warning.set_process(false)
		dock._food_warning.label.text = "2 dwarves cannot find reachable food.\nHarvest berries or make stored food accessible."
		dock._food_warning.show()
		await _frames(3)
		for rect: Rect2 in hud.occupied_rects():
			_expect(not rect.intersects(dock._food_warning.get_global_rect()), "utility clears food warning " + str(resolution))
		dock._food_warning.hide()
		hud.step_buttons.up_four.grab_focus()
		await create_timer(.35).timeout
		await _frames(2)
		_expect(hud.step_buttons.up_four._info.visible and bounds.encloses(hud.step_buttons.up_four._info.get_global_rect()), "keyboard focus reveals readable four-level help " + str(resolution))
		hud.step_buttons.up_four.release_focus()
		_click(hud.speed_buttons[2].get_global_rect().get_center())
		_expect(not clock_node.paused and clock_node.speed == 2 and hud.speed_buttons[2].button_pressed, "Fast resumes at 2×")
		_click(hud.speed_buttons[0].get_global_rect().get_center())
		_expect(clock_node.paused and hud.speed_buttons[0].button_pressed, "Pause has a visible active state")
		_click(hud.speed_buttons[0].get_global_rect().get_center())
		_expect(not clock_node.paused and clock_node.speed == 2, "Pause resumes previous speed")
		_click(hud.speed_buttons[1].get_global_rect().get_center())
		_expect(not clock_node.paused and clock_node.speed == 1 and hud.speed_buttons[1].button_pressed, "Play resumes at 1×")
		for menu in ["construction", "system", "development", "craft", "colony"]:
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
	for failure in failures: push_error(failure)
	print("TIME_SLICE_HUD_OK: real clicks, keys, wheel routing, exact offsets, bounds, save/restore, speed and responsive layouts" if failures.is_empty() else "TIME_SLICE_HUD_FAIL")
	quit(0 if failures.is_empty() else 1)


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
