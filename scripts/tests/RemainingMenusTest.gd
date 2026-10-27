extends "res://scripts/tests/WorkerCraftingTest.gd"

## Navigation contracts and native review of the dock's remaining menus.
const OUT := "res://tmp/remaining_menus_20261012/"

func _run() -> void:
	create_timer(90).timeout.connect(func(): push_error("Remaining menus timed out"); quit(1))
	await _setup_crafting_fixture()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_expect(root.get_node("UIRegistry").get_menu("development").items.any(func(entry): return entry.id=="item_stamper"),
		"Development contains the item stamper")
	_expect(not manager.has_window("clock") and dock._sky_dial != null, "permanent Sky Dial replaces the clock window")
	var time_buttons: Array = manager.get_ui_window("time_weather_dev").find_children("*", "Button", true, false)
	var commands: Array[String] = []
	for button: Button in time_buttons: commands.append(button.text)
	_expect(commands.has("+1 Hour") and commands.has("+1 Season") and commands.has("Weather ›"), "development owns all three time/weather controls")
	var rooms = load("res://scripts/systems/RoomOverlayController.gd").new()
	rooms.window_manager_path = NodePath("../Windows")
	rooms.dock_ui_path = NodePath("../Dock")
	scene.add_child(rooms)
	rooms.set_process(false)
	var room_panel = rooms._window_content
	explorer = load("res://scripts/ui/ObjectExplorerController.gd").new()
	explorer.window_manager_path = NodePath("../Windows")
	explorer.dock_ui_path = NodePath("../Dock")
	scene.add_child(explorer)
	furniture._install(BENCH, furniture.get_defs()[BENCH], Vector3i(45,20,42), 0)
	var piece = furniture._installed.values()[0]
	for viewport_size in [Vector2i(1280,720), Vector2i(960,540), Vector2i(2560,1440)]:
		root.size = viewport_size
		await _frames(8)
		for target in ["craft", "development"]:
			dock._open_action_panel(target)
			await _frames(8)
			var bounds := Rect2(Vector2.ZERO, Vector2(viewport_size))
			_expect(bounds.encloses(dock._panel_container.get_global_rect()), "illustrated menu fits: " + target + str(viewport_size))
			for button in dock._panel_body.get_children():
				_expect(button.text.is_empty() and button.icon != null, "menu entry uses art: " + target)
				_expect(dock._panel_scroll.get_global_rect().encloses(button.get_global_rect()), "menu entry remains reachable: " + target)
			var first = dock._panel_body.get_child(0)
			first.grab_focus()
			await create_timer(.35).timeout
			_expect(first._info != null and first._info.visible and bounds.encloses(first._info.get_global_rect()), "keyboard explanation fits: " + target)
			await _capture_menu("%s_%d" % [target, viewport_size.x])
			first.release_focus()
			dock._close_action_panel()
			_expect(first._info == null or not first._info.visible, "closed menu hides its explanation")
		manager.open("room_inspector")
		room_panel.show_room({"temp_c": 16.0, "volume": 81, "cells": {}, "floor_tiles": 81})
		await _frames(8)
		_expect(room_panel._banner_word.text == "Plain" and room_panel._banner_value.text == "0", "the room window shows the appeal")
		_expect(Rect2(Vector2.ZERO, Vector2(viewport_size)).encloses(rooms._window_panel.get_global_rect()), "room information fits the viewport")
		await _capture_menu("rooms_%d" % viewport_size.x)
		manager.close("room_inspector")
		# Reflow a wide chooser around the compact object panel beside the dock (doc 260).
		explorer.select_object(furniture, "installed:%d" % piece.installed_id)
		dock._open_action_panel("craft")
		await _frames(10)
		_expect(not dock._panel_container.get_global_rect().intersects(explorer.get_compact_panel().get_global_rect()), "Craft keeps clear of the selected object's panel")
		for button in dock._panel_body.get_children():
			_expect(dock._panel_scroll.get_global_rect().encloses(button.get_global_rect()), "wrapped profession remains reachable")
		await _capture_menu("craft_inspector_%d" % viewport_size.x)
		explorer.clear_selection()
		dock._close_action_panel()
	for failure in failures: push_error(failure)
	print("REMAINING_MENUS_OK: time/weather separation, keyboard hover, room facts, native layouts" if failures.is_empty() else "REMAINING_MENUS_FAIL")
	quit(0 if failures.is_empty() else 1)

func _capture_menu(filename: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + filename + ".png")
