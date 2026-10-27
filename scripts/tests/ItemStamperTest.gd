extends "res://scripts/tests/WorkerCraftingTest.gd"

## The DEV item stamper (doc 23, "The item stamper"), with the real dock, window and drops:
## - the Development menu holds Item stamper in place of the three old spawners;
## - every item has a tile and a picture; the search keeps what matches by name or id, says
##   when nothing does, and Enter picks the first;
## - furniture shows its woods with Pine first; the amount jumps and steps;
## - Stamp starts the tool and announces it; the floor under the pointer is found as the
##   other tools find it; a stamp puts one pile of the amount, in the chosen wood, and
##   remembers the item first in Recent, kept for the next window;
## - items that keep a record elsewhere are refused, with the reason;
## - Esc, closing the window and another tool all end stamping;
## - without DEV tools the tool never registers.
const STAMPER := "res://scripts/systems/ItemStamperController.gd"
const BED := "base:resources:furniture:log_bed"
const FLOWERS := "base:resources:plant:flowers_1"
const OAK := "base:material:oak"


class DockStub extends Node:
	signal tool_requested(tool_id: String)
	var registered := 0
	func register_item_stamper(_tool: Node) -> void: registered += 1


func _run() -> void:
	create_timer(120).timeout.connect(func(): push_error("Item stamper timed out"); quit(1))
	await _setup_crafting_fixture()
	var development: Array = root.get_node("UIRegistry").get_menu("development").items
	_expect(development.size() == 8 and development.any(func(entry): return entry.id == "item_stamper")
		and not development.any(func(entry): return String(entry.id).begins_with("spawn_")),
		"Development holds Item stamper in place of the three spawners")
	var stamper = load(STAMPER).new()
	stamper.name = "Stamper"
	stamper.dock_path = NodePath("../Dock")
	scene.add_child(stamper)
	await _frames(2)
	_expect(manager.has_window("item_stamper"), "the stamper registers its DEV window")
	dock._dispatch_menu_entry({"id": "item_stamper", "label": "Item stamper", "action": "toggle_window", "target": "item_stamper"})
	await _frames(4)
	var panel = dock._stamper_panel
	_expect(manager.is_open("item_stamper") and panel.is_visible_in_tree(), "the Development entry opens the window")
	var items: Dictionary = root.get_node("ContentRegistry").items
	var missing: Array = items.keys().filter(func(key: String) -> bool: return panel._items[key].picture == null)
	_expect(panel._items.size() == items.size() and panel.grid._tiles.size() == items.size() and missing.is_empty(),
		"every item has a tile with its picture: " + str(missing))
	# Search: by name, by id, nothing, and Enter for the first.
	panel.search.text = "pine"
	panel.search.text_changed.emit("pine")
	var shown := _shown(panel)
	_expect(not shown.is_empty() and shown.all(func(key: String) -> bool:
		return String(panel._items[key].name).to_lower().contains("pine") or key.contains("pine")), "the search keeps the items it names: " + str(shown))
	panel.search.text = "rough_stone"
	panel.search.text_changed.emit("rough_stone")
	_expect(_shown(panel) == ["base:resources:stone:rough_stone"], "an id finds its item")
	panel.search.text = "xyzzy"
	panel.search.text_changed.emit("xyzzy")
	_expect(_shown(panel).is_empty() and panel._nothing.visible and panel._nothing.text.contains("xyzzy"), "nothing matching says so")
	panel.search.text = "pine log"
	panel.search.text_submitted.emit("pine log")
	_expect(panel.selected_key == "base:resources:wood:pine_log" and stamper.key == panel.selected_key, "Enter picks the first match")
	panel.search.text = ""
	panel.search.text_changed.emit("")
	# Furniture: its woods, Pine first; the amount.
	panel._select(BED)
	await _frames(2)
	var woods: Array = panel.woods._tiles.keys()
	_expect(panel.woods.visible and woods.size() == 4 and woods[0] == "base:material:pine" and stamper.material == "base:material:pine",
		"furniture offers its woods, Pine first")
	panel.woods.item_pressed.emit(OAK)
	var jump: Button = panel._amount_row.get_children().filter(func(node: Node) -> bool: return node is Button and node.text == "5")[0]
	jump.pressed.emit()
	panel._amount_row.get_child(2).pressed.emit()   # +
	_expect(stamper.material == OAK and stamper.amount == 6 and panel._value.text == "6", "a wood and the amount reach the tool")
	# Stamp: the tool starts, the floor under the pointer, one pile in the chosen wood.
	var announced: Array[String] = []
	dock.tool_requested.connect(func(id: String): announced.append(id))
	panel.stamp_button.pressed.emit()
	dock._tool_bar.refresh()
	_expect(stamper.is_active() and announced == ["item_stamper"] and panel.stamp_button.disabled
		and dock._tool_bar.active_tool() == stamper and dock._tool_bar._name.text == "Stamp · Log bed (packed)",
		"Stamp starts the tool, announces it, and the tool bar names the item")
	var floor := Vector3i(44, 20, 42)
	var point: Vector2 = camera.unproject_position(Vector3(44.5, 21.0, 42.5))
	_expect(stamper.floor_under(point) == floor, "the floor under the pointer is found as the other tools find it: " + str(stamper.floor_under(point)))
	_expect(stamper.stamp_at(floor) == 6, "a stamp puts the amount down")
	var beds: Array = drops.loose_items().filter(func(node: Node3D) -> bool:
		return drops.item_key_of(node) == BED and drops.item_floor_cell(node) == floor)
	_expect(beds.size() == 6 and beds.all(func(node: Node3D) -> bool: return root.get_node("CraftMaterials").of_item(node) == OAK),
		"one pile of six oak log beds on that floor")
	_expect(panel.recent == [BED] and dock._tool_bar._status_text.text.begins_with("Stamped 6 Log bed (packed)"),
		"the stamp is told on the tool bar and remembered")
	var again = load("res://scripts/ui/ItemStamperPanel.gd").new()
	_expect(again.recent == [BED], "Recent is kept for the next window")
	again.free()
	# Refused: items that keep a record elsewhere.
	panel._select(FLOWERS)
	_expect(not stamper.is_active() and panel.stamp_button.disabled and panel._refusal.visible and stamper.stamp_at(floor) == 0,
		"wildflowers are refused, with the reason")
	for key: String in ["base:resources:water:wet_stone", "base:resources:special:settlement_flag"]:
		_expect(not load(STAMPER).refusal(key).is_empty(), key + " is refused")
	# Ending: Esc, closing the window, another tool.
	panel._select(BED)
	panel.stamp_button.pressed.emit()
	_key(KEY_ESCAPE)
	_expect(not stamper.is_active(), "Esc ends stamping")
	panel.stamp_button.pressed.emit()
	manager.close("item_stamper")
	_expect(not stamper.is_active(), "closing the window ends stamping")
	manager.open("item_stamper")
	panel.stamp_button.pressed.emit()
	dock.tool_requested.emit("furniture")
	_expect(not stamper.is_active(), "another tool ends stamping")
	# Without DEV tools the tool never registers.
	var registry := root.get_node("UIRegistry")
	var stub := DockStub.new()
	stub.name = "StubDock"
	scene.add_child(stub)
	registry.dev_tools_enabled = false
	var hidden = load(STAMPER).new()
	hidden.dock_path = NodePath("../StubDock")
	scene.add_child(hidden)
	registry.dev_tools_enabled = true
	_expect(stub.registered == 0, "without DEV tools the stamper never registers")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(panel.RECENT_PATH))
	for failure in failures: push_error(failure)
	print("ITEM_STAMPER_OK: the entry, the window, search, woods, amounts, stamping, Recent, refusals and endings" if failures.is_empty() else "ITEM_STAMPER_FAIL")
	quit(0 if failures.is_empty() else 1)


## The items the grid shows now, Recent left out.
func _shown(panel: Node) -> Array:
	var keys: Array = []
	for id: String in panel.grid._tiles:
		if not id.begins_with(panel.RECENT) and panel.grid._tiles[id].is_visible_in_tree(): keys.append(id)
	return keys


func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	root.push_input(event)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event)
