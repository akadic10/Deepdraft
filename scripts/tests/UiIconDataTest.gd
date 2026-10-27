extends SceneTree

## Every picture the UI data names exists and loads (doc 259): dock items, menu
## entries, room symbols, the time/slice buttons, each
## profession's icon and each mood step's face.
## Every Hearthblock icon names a known family, so its tile has a colour, and the
## dock, the Orders, Zones, Construction and Crafters menus, and the entries on Colony's
## page use Hearthblock icons throughout.
## The world order markers reuse the Orders pictures. The concern badges over dwarves'
## heads and the compact panel's actions and badges have pictures too.
var failures: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var ui = root.get_node("UIRegistry")
	var entries: Array = []
	entries.append_array(ui.get_dock_items())
	for key: String in ui._menus:
		entries.append_array(ui._menus[key].items)
	entries.append_array(ui._room_symbols.values())
	entries.append_array(ui.get_time_slice().get("buttons", {}).values())
	var checked := 0
	for entry: Dictionary in entries:
		var path := String(entry.get("icon", ""))
		if path.is_empty(): continue
		checked += 1
		var name := String(entry.get("id", entry.get("label", path)))
		_expect(ResourceLoader.exists(path), "icon file exists: %s (%s)" % [path, name])
		_expect(ui.get_dock_icon(entry) is Texture2D, "icon loads as a texture: " + name)
		if entry.has("family"):
			_expect(ui.get_icon_family_color(String(entry.family)).a > 0.0, "known icon family: %s (%s)" % [entry.family, name])
	_expect(checked > 60, "the UI data names its pictures (%d checked)" % checked)
	# Each profession names one Hearthblock icon, shared by the career map, the equipment
	# view and Crafters.
	var dwarves = root.get_node("DwarfAssets")
	for key: String in dwarves.profession_ids():
		var icon := String(dwarves.profession_definition(key).get("icon", ""))
		_expect(icon.begins_with("res://assets/ui/icons/") and load(icon) is Texture2D, "profession has a Hearthblock icon: " + key)
	# The character sheet's five mood faces (doc 261), named by the mood steps.
	for step: Dictionary in root.get_node("TaskManager").get_config_section("mood").steps:
		_expect(String(step.icon).begins_with("res://assets/ui/icons/") and load(String(step.icon)) is Texture2D, "mood step has a Hearthblock face: " + String(step.word))
	# The event log's pictures (doc 23): each kind's own, and each arrival's species.
	var event_log = root.get_node("EventLog")
	for kind: String in event_log.config.kinds:
		var picture := String(event_log.config.kinds[kind].get("picture", ""))
		if not picture.is_empty():
			_expect(picture.begins_with("res://assets/ui/icons/") and load(picture) is Texture2D, "event kind has a Hearthblock picture: " + kind)
	var director: Node = load("res://scripts/systems/WorldEventDirector.gd").new()
	root.add_child(director)
	director.set_process(false)
	for event: Dictionary in director.config.events:
		_expect(String(event.picture).begins_with("res://assets/ui/icons/") and load(String(event.picture)) is Texture2D,
			"arrival has its species' picture: " + String(event.id))
	root.remove_child(director)
	director.free()
	for entry: Dictionary in dwarves.promotion_entries():
		_expect(dwarves.profession_definition("base:profession:" + String(entry.role)).has("icon"), "career map role has an icon: " + String(entry.role))
	for item: Dictionary in ui._menus.colony.items:
		_expect(String(item.icon).begins_with("res://assets/ui/icons/") and String(item.get("family", "")) == "people",
			"Colony entry uses a Hearthblock icon on the people tile: " + String(item.id))
	for item: Dictionary in ui._menus.craft.items:
		_expect(String(item.icon).begins_with("res://assets/ui/icons/") and String(item.get("family", "")) == "settlement",
			"Crafters entry uses a Hearthblock icon on the settlement tile: " + String(item.id))
		var profession := "base:profession:" + ("worker" if item.id == "rudimentary" else String(item.id))
		if profession in dwarves.profession_ids():
			_expect(String(item.icon) == String(dwarves.profession_definition(profession).icon), "Crafters %s shows its profession's icon" % item.id)
	for item: Dictionary in ui.get_dock_items():
		_expect(String(item.icon).begins_with("res://assets/ui/icons/") and item.has("family"),
			"dock entry uses a Hearthblock icon on a family tile: " + String(item.id))
	var orders: Dictionary = {}
	for menu: String in ["orders", "zones", "construction"]:
		for item: Dictionary in ui._menus[menu].items:
			_expect(String(item.icon).begins_with("res://assets/ui/icons/") and String(item.get("family", "")) == "work",
				"%s entry uses a Hearthblock icon on the work tile: %s" % [menu, item.id])
			orders[String(item.id)] = ui.get_dock_icon(item)
	for kind: String in ["fell", "harvest", "clear_stones", "clear_plants", "uproot"]:
		_expect(ui.get_order_marker(kind) is Texture2D, "world marker picture loads: " + kind)
	for pair: Array in [["fell", "chop"], ["harvest", "harvest_plants"], ["clear_stones", "clear_stones"], ["clear_plants", "clear_shrubs"]]:
		_expect(ui.get_order_marker(pair[0]) == orders.get(pair[1]), "the %s marker shows the %s Orders icon" % pair)
	_expect(ui.get_order_marker_tile() == ui.get_icon_family_color("work"), "world markers sit on the work tile")
	# The concern badges over dwarves' heads, and the compact panel's action and badge pictures.
	var indicators: Dictionary = ui.get_dwarf_indicators()
	for kind: String in ["food", "rest", "mood"]:
		_expect(String(indicators.icons[kind]).begins_with("res://assets/ui/icons/") and ui.get_need_icon(kind) is Texture2D,
			"concern badge has a Hearthblock icon: " + kind)
	_expect(ui.get_icon_family_color(String(indicators.get("family", ""))).a > 0.0, "concern badges sit on a known family tile")
	for id: String in ui._compact_panel.actions:
		_expect(ui.get_compact_action(id).icon is Texture2D, "compact panel action has a picture: " + id)
	for kind: String in ui._compact_panel.badges:
		_expect(ui.get_compact_badge(kind) is Texture2D, "compact panel badge has a picture: " + kind)
	for failure in failures: push_error(failure)
	print("UI_ICON_DATA_OK: %d pictures" % checked if failures.is_empty() else "UI_ICON_DATA_FAIL")
	quit(0 if failures.is_empty() else 1)


func _expect(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
