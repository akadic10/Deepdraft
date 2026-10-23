extends SceneTree

## With data/ui/dev_tools.json off, the main world offers no development tools:
## no Development menu, no DEV windows or block inspector, and no DEV buttons or
## object actions. Player feedback that lives in a debug panel keeps working.
var failures: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	create_timer(120).timeout.connect(func(): push_error("Dev tools switch test timed out"); quit(1))
	var ui = root.get_node("UIRegistry")
	_expect(ui.dev_tools_enabled, "the switch file loads and is on in the project")
	var actions := [{"id": "dev_build", "variant": "dev"}, {"id": "cancel", "variant": "danger"}]
	_expect(_ids(ui.get_dock_items()).has("development") and ui.shown_actions(actions).size() == 2,
		"switch on: Development menu and DEV actions are offered")

	ui.dev_tools_enabled = false
	_expect(not _ids(ui.get_dock_items()).has("development") and _ids(ui.get_dock_items()).has("orders"),
		"switch off: the dock drops only the Development button")
	_expect(ui.get_menu("development").is_empty() and not ui.get_menu("orders").items.is_empty(),
		"switch off: the Development menu is empty; others are unchanged")
	_expect(_ids(ui.shown_actions(actions)) == ["cancel"], "switch off: object windows drop DEV actions")

	root.get_node("WorldClock").paused = true
	var saves = root.get_node("SaveManager")
	_expect(saves.configure_storage_for_testing("user://dev_tools_switch_test"), "isolated save directory")
	change_scene_to_file("res://scenes/main/debug_world.tscn")
	await process_frame
	await process_frame
	var gen = root.get_node("WorldGenerator")
	while not gen._maps_ready or gen.is_generating(): await process_frame
	for i in range(10): await process_frame
	var scene := current_scene
	var dock = scene.get_node("DockUI")
	_expect(not dock._button_by_target.has("development") and dock._button_by_target.has("orders"),
		"main world: no Development dock button")
	var windows = scene.get_node("UIWindowManager")
	var dev_windows: Array = windows._windows.keys().filter(func(id: String) -> bool: return id.ends_with("_dev"))
	_expect(dev_windows.is_empty(), "main world: no DEV windows registered (%s)" % ", ".join(dev_windows))
	_expect(scene.get_node("Renderer").get_node_or_null("BlockInspector") == null, "main world: no block inspector")
	var dev_buttons: Array[String] = []
	for id: String in windows._windows:
		for button: Node in windows._windows[id].find_children("*", "BaseButton", true, false):
			if button is Button and String(button.text).begins_with("DEV") and button.visible:
				dev_buttons.append("%s: %s" % [id, button.text])
	_expect(dev_buttons.is_empty(), "main world: no visible DEV buttons (%s)" % ", ".join(dev_buttons))
	_expect(not root.get_node("WaterManager").flood_warning.get_connections().is_empty(),
		"the flood warning still reaches the player")
	print("DEV_TOOLS_SWITCH_OK" if failures.is_empty() else "DEV_TOOLS_SWITCH_FAIL")
	quit(0 if failures.is_empty() else 1)


func _ids(entries: Array) -> Array:
	return entries.map(func(entry: Dictionary) -> String: return String(entry.id))


func _expect(ok: bool, label: String) -> void:
	if ok:
		print("  ok  ", label)
	else:
		failures.append(label)
		push_error(label)
