extends "res://scripts/tests/WorkerCraftingTest.gd"

## Navigation contracts and native review. Save callbacks are replaced with
## probes inside this fixture, so clicking its save/load art never touches a save.
const OUT := "res://tmp/remaining_menus_20261012/"
var save_calls := [0, 0, 0]

class SpawnProbe extends Node:
	var drops := 0
	var furniture := 0
	func dev_spawn_drops() -> void: drops += 1
	func dev_spawn_furniture() -> void: furniture += 1

func _run() -> void:
	create_timer(90).timeout.connect(func(): push_error("Remaining menus timed out"); quit(1))
	await _setup_crafting_fixture()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for signal_name in ["save_game_requested", "load_game_requested", "load_autosave_requested"]:
		for connection: Dictionary in dock.get_signal_connection_list(signal_name):
			dock.disconnect(signal_name, connection.callable)
	dock.save_game_requested.connect(func(): save_calls[0] += 1)
	dock.load_game_requested.connect(func(): save_calls[1] += 1)
	dock.load_autosave_requested.connect(func(): save_calls[2] += 1)
	for entry: Dictionary in root.get_node("UIRegistry").get_menu("save_load").items:
		var renamed := entry.duplicate()
		renamed.label = "A changed caption"
		dock._dispatch_menu_entry(renamed)
	_expect(save_calls == [1, 1, 1], "save commands route by stable identity, independent of captions")
	var probe := SpawnProbe.new()
	scene.add_child(probe)
	dock._stockpile_controller = probe
	for id in ["spawn_drops", "spawn_furniture"]:
		dock._dispatch_menu_entry({"id": id, "label": "Renamed action", "action": "panel_action", "target": "storage_zone"})
	_expect(probe.drops == 1 and probe.furniture == 1, "development spawn commands route by stable identity")
	dock._stockpile_controller = null
	_expect(not manager.has_window("clock") and dock._sky_dial != null, "permanent Sky Dial replaces the clock window")
	var time_buttons: Array = manager.get_ui_window("time_weather_dev").find_children("*", "Button", true, false)
	var commands: Array[String] = []
	for button: Button in time_buttons: commands.append(button.text)
	_expect(commands.has("+1 Hour") and commands.has("+1 Season") and commands.has("Weather →"), "development owns all three time/weather controls")
	var categories: Array = root.get_node("UIRegistry").get_place_catalog().categories
	for entry: Dictionary in categories:
		var button = dock._place_catalog._tabs[entry.id]
		_expect(button.text.is_empty() and button.icon is AtlasTexture and button.caption == entry.label, "Place category has art and an accessible name")
	for entry: Dictionary in root.get_node("UIRegistry").get_inventory_catalog().categories:
		var button = dock._inventory_panel._tabs[entry.id]
		_expect(button.text.is_empty() and button.icon is AtlasTexture and button.caption == entry.label, "Inventory category has art and an accessible name")
	var rooms = load("res://scripts/systems/RoomOverlayController.gd").new()
	rooms.window_manager_path = NodePath("../Windows")
	rooms.dock_ui_path = NodePath("../Dock")
	scene.add_child(rooms)
	rooms.set_process(false)
	var room_panel = rooms._window_content
	explorer = load("res://scripts/ui/ObjectExplorerController.gd").new()
	explorer.window_manager_path = NodePath("../Windows")
	scene.add_child(explorer)
	furniture._install(BENCH, furniture.get_defs()[BENCH], Vector3i(45,20,42), 0)
	var piece = furniture._installed.values()[0]
	for viewport_size in [Vector2i(1280,720), Vector2i(960,540), Vector2i(2560,1440)]:
		root.size = viewport_size
		await _frames(8)
		for target in ["craft", "colony", "system", "save_load", "development"]:
			dock._open_action_panel(target)
			await _frames(8)
			var bounds := Rect2(Vector2.ZERO, Vector2(viewport_size))
			_expect(bounds.encloses(dock._panel_container.get_global_rect()), "illustrated menu fits: " + target + str(viewport_size))
			for button in dock._panel_body.get_children():
				_expect(button.text.is_empty() and button.icon is AtlasTexture, "menu entry uses art: " + target)
				_expect(dock._panel_scroll.get_global_rect().encloses(button.get_global_rect()), "menu entry remains reachable: " + target)
			var first = dock._panel_body.get_child(0)
			first.grab_focus()
			await create_timer(.35).timeout
			_expect(first._info != null and first._info.visible and bounds.encloses(first._info.get_global_rect()), "keyboard explanation fits: " + target)
			await _capture_menu("%s_%d" % [target, viewport_size.x])
			first.release_focus()
			dock._close_action_panel()
			_expect(first._info == null or not first._info.visible, "closed menu hides its explanation")
		# Actual input on the child row and its Back arrow, with safe save probes.
		dock._open_action_panel("save_load")
		await _frames(6)
		_click(dock._panel_body.get_child(0).get_global_rect().get_center())
		_expect(not dock.is_action_menu_open(), "save action closes its menu")
		dock._open_action_panel("save_load")
		await _frames(6)
		_click(dock._panel_rail_back.get_global_rect().get_center())
		_expect(dock._active_panel_target == "system", "Back returns to Menu")
		dock._close_action_panel()
		manager.open("room_inspector")
		room_panel.show_room({"temp_c": 16.0, "volume": 81, "cells": {}, "floor_tiles": 81,
			"finished_floor_tiles": 81, "flooring_complete": true, "flooring_appeal": 5.0})
		await _frames(8)
		_expect(room_panel._flooring.text == "81 / 81 tiles" and room_panel._flooring_appeal.text == "+5 · Complete", "room art retains exact flooring facts")
		_expect(Rect2(Vector2.ZERO, Vector2(viewport_size)).encloses(rooms._window_panel.get_global_rect()), "room information fits the viewport")
		await _capture_menu("rooms_%d" % viewport_size.x)
		manager.close("room_inspector")
		# Reflow a wide chooser around the real Object explorer at a moved position.
		explorer.select_object(furniture, "installed:%d" % piece.installed_id)
		explorer._window.position = Vector2(viewport_size.x * .5 - 160, 180)
		dock._open_action_panel("craft")
		await _frames(10)
		_expect(not dock._panel_container.get_global_rect().intersects(explorer._window.get_global_rect()), "Craft wraps beside a centrally moved inspector")
		for button in dock._panel_body.get_children():
			_expect(dock._panel_scroll.get_global_rect().encloses(button.get_global_rect()), "wrapped profession remains reachable")
		await _capture_menu("craft_inspector_%d" % viewport_size.x)
		explorer.clear_selection()
		dock._close_action_panel()
	_expect(save_calls == [4, 1, 1], "three real save icon clicks invoke exactly one callback each")
	for failure in failures: push_error(failure)
	print("REMAINING_MENUS_OK: stable actions, time/weather separation, illustrated categories, keyboard hover, Back, room facts, native layouts" if failures.is_empty() else "REMAINING_MENUS_FAIL")
	quit(0 if failures.is_empty() else 1)

func _capture_menu(filename: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + filename + ".png")
