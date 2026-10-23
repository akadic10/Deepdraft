extends "res://scripts/tests/WorkerCraftingTest.gd"

## A load listener can synchronously detach the dock through scene reload.
## Exercise the menu route and callbacks already queued before that reload.
func _run() -> void:
	await _setup_crafting_fixture()
	for signal_name in ["save_game_requested", "load_game_requested", "load_autosave_requested", "new_game_requested"]:
		for connection: Dictionary in dock.get_signal_connection_list(signal_name):
			dock.disconnect(signal_name, connection.callable)
		dock.connect(signal_name, _detach_on_request)
	for command in ["save_game", "load_game", "load_autosave", "new_game"]:
		dock._open_action_panel("system" if command == "new_game" else "save_load")
		await _frames(2)
		dock.call_deferred("_layout_action_panel")
		dock.call_deferred("_position_action_panel")
		dock._dispatch_menu_entry({"id": command, "label": "Changed caption",
			"action": "panel_action", "target": "save_load"})
		_expect(not dock.is_inside_tree(), "persistence listener detached the old dock")
		await _frames(2)
		scene.add_child(dock)
		await _frames(2)
	for failure in failures: push_error(failure)
	print("DOCK_PERSISTENCE_LIFECYCLE_OK" if failures.is_empty() else "DOCK_PERSISTENCE_LIFECYCLE_FAIL")
	quit(0 if failures.is_empty() else 1)


func _detach_on_request() -> void:
	_expect(not dock.is_action_menu_open() and dock._active_panel_target.is_empty(),
		"persistence callback starts after the menu has finished closing")
	_expect(not dock._panel_connector.visible, "persistence callback starts after the connector is hidden")
	scene.remove_child(dock)
