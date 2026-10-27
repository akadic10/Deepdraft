extends "res://scripts/tests/WorkerCraftingTest.gd"

## The tool bar (doc 23, "The tool bar"), with the real dock and tools:
## - Build shows its bar: its name and keys, its materials as pictures, the height as a
##   stepper whose + raises the wall, and a held drag's tag, in rust when the stone runs short;
## - one Undo list for every tool, newest first: blocks marked for mining after a queued
##   plan are taken back first, from Build's own bar; Done ends the tool; Ctrl + Z with
##   no tool on then takes back the plan and says so;
## - Place names the piece; the DEV stamper names its item and has no Undo;
## - the bar sits above the open shelf, clears the slice tower, and fits at 960 x 540.
const STAMPER := "res://scripts/systems/ItemStamperController.gd"
const BED := "base:resources:furniture:log_bed"
var builder
var mining
var bar


func _run() -> void:
	create_timer(80).timeout.connect(func(): push_error("Tool bar test timed out"); quit(1))
	await _setup_crafting_fixture()
	root.get_node("WorldClock").set_paused(true)
	stockpiles.reset_runtime_state()
	mining = load("res://scripts/systems/MiningDesignationController.gd").new()
	mining.name = "Mining"
	mining.dock_ui_path = NodePath("../Dock")
	scene.add_child(mining)
	mining.set_process(false)
	builder = load("res://scripts/systems/ConstructionController.gd").new()
	builder.name = "Construction"
	builder.furniture = furniture
	builder.mining = mining
	builder.dock = dock
	scene.add_child(builder)
	await _frames(4)
	bar = dock._tool_bar
	_expect(bar != null and not bar._bar.visible, "the bar waits for a tool")
	await _check_build()
	await _check_shapes()
	await _check_undo()
	await _check_other_tools()
	await _check_placement()
	for failure: String in failures: push_error(failure)
	print("TOOL_BAR_OK" if failures.is_empty() else "TOOL_BAR_FAIL")
	quit(0 if failures.is_empty() else 1)


## Build: its name, keys, materials and height; a held drag's tag in rust, the stone being short.
func _check_build() -> void:
	dock.tool_requested.emit("construct_build")
	await _frames(2)
	bar.refresh()
	_expect(bar._bar.visible and bar._name.text == "Build" and bar._keys.get_child_count() > 0
		and bar._settings.get_node("Height/Row/Value").text == "1", "Build shows its name, keys and height")
	var row: Control = bar._settings.get_node("Material/Row")
	_expect(row.get_child_count() == 4 and (row.get_node("Stone") as Button).button_pressed, "Build's four materials are pictures, stone chosen")
	(row.get_node("Wood") as Button).pressed.emit()
	var menu: Control = bar.open_menu()
	_expect(builder._material == "wood" and (row.get_node("Wood") as Button).button_pressed and not (row.get_node("Stone") as Button).button_pressed
		and menu != null and menu.get_node("Pad/Rows/Type").get_child_count() == 2 and menu.get_node("Pad/Rows/Wood").get_child_count() == 4,
		"a picture chooses its material, and Wood's opens its menu: the two logs over the four woods")
	(menu.get_node("Pad/Rows/Type/LogHorizontal") as Button).pressed.emit()
	(menu.get_node("Pad/Rows/Wood/Oak") as Button).pressed.emit()
	_expect(builder._kind == "log_horizontal" and builder._wood == "oak" and bar.open_menu() == menu
		and (menu.get_node("Pad/Rows/Wood/Oak") as Button).button_pressed and not (menu.get_node("Pad/Rows/Type/LogUpright") as Button).button_pressed,
		"the menu picks the log and the wood, lit, and stays open")
	_expect((row.get_node("Wood/Picture") as TextureRect).texture == bar._texture("res://assets/ui/icons/log_horizontal_oak.png"),
		"Wood's picture shows the chosen log in the chosen wood")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	root.push_input(escape)
	await _frames(1)
	_expect(bar.open_menu() == null and builder.is_active(), "Esc closes the menu before it ends the tool")
	(row.get_node("Stone") as Button).pressed.emit()
	_expect(bar.open_menu() != null and bar.open_menu().get_node("Pad/Rows/Type").get_child_count() == 1, "Stone's menu holds native stone")
	(row.get_node("Stone") as Button).pressed.emit()
	_expect(bar.open_menu() == null and builder._material == "stone", "Stone's picture again closes its menu")
	bar._settings.get_node("Height/Row/More").pressed.emit()
	_expect(builder._height == 2 and bar._settings.get_node("Height/Row/Value").text == "2", "the height's + raises the wall, as Alt + wheel does")
	builder.set_process(false)   # its preview would follow the headless pointer
	var a := camera.unproject_position(Vector3(44.5, 21, 42.5))
	var b := camera.unproject_position(Vector3(46.5, 21, 42.5))
	_move(a)
	_mouse_button(a, true)
	_move(b)
	builder._update_preview(b)
	bar.refresh()
	var stock: int = stockpiles.get_available_total("base:resources:stone:rough_stone")
	_expect(bar._tag.visible and bar._tag_big.text == "3 × 1 · 2 tall" and bar._tag_small.text == "6 blocks · 6 rough stone · %d in stock" % stock,
		"a held drag shows its size, blocks and stone on the tag: \"%s\", \"%s\"" % [bar._tag_big.text, bar._tag_small.text])
	_expect(stock < 6 and bar._tag_small.get_theme_color("font_color") == UITheme.TAG_TONES.blocked[1], "the stone runs short, in rust")
	_mouse_button(b, false)
	bar.refresh()
	_expect(builder.orders.size() == 1 and not bar._tag.visible and bar._status_text.text == "Queued 6 blocks · 6 rough stone",
		"the plan is queued and stays on the bar: \"%s\"" % bar._status_text.text)


## One list for every tool: the newest order first, whichever tool made it.
func _check_undo() -> void:
	var marked: Array[Vector3i] = [Vector3i(30, 20, 30), Vector3i(31, 20, 30)]
	mining._preview_blocks = marked
	mining._confirm_preview()
	bar.refresh()
	_expect(bar.newest_order().owner == mining and not bar._undo.disabled, "blocks marked for mining are the newest order")
	bar._undo.pressed.emit()
	_expect(mining._zones.is_empty() and builder.orders.size() == 1 and bar._status_text.text == "Took back: 2 blocks marked for mining",
		"Stone block's Undo takes back the newest order, the mining: \"%s\"" % bar._status_text.text)
	bar._done.pressed.emit()
	await _frames(2)
	bar.refresh()
	_expect(not builder.is_active() and not bar._bar.visible, "Done ends the tool and the bar goes")
	var said: Array[String] = []
	bar.undone.connect(func(message: String): said.append(message))
	var undo := InputEventKey.new()
	undo.pressed = true
	undo.keycode = KEY_Z
	undo.physical_keycode = KEY_Z
	undo.ctrl_pressed = true
	root.push_input(undo, true)
	await _frames(2)
	_expect(builder.orders.is_empty() and said == ["Took back: Queued 6 blocks · 6 rough stone"],
		"Ctrl + Z with no tool on takes back the plan and says so: %s" % str(said))


## Place names the piece; the DEV stamper names its item and has no Undo.
func _check_other_tools() -> void:
	furniture.activate_for(BENCH)
	await _frames(2)
	bar.refresh()
	_expect(bar._bar.visible and bar._name.text == "Place · " + String(furniture.get_defs()[BENCH].display_name) and bar._picture.texture != null,
		"Place names the piece with its picture: \"%s\"" % bar._name.text)
	bar._done.pressed.emit()
	await _frames(2)
	_expect(not furniture.is_active(), "Done ends placing")
	var stamper = load(STAMPER).new()
	stamper.name = "Stamper"
	stamper.dock_path = NodePath("../Dock")
	scene.add_child(stamper)
	await _frames(2)
	stamper.choose(BED, 1, "")
	stamper.activate()
	await _frames(2)
	bar.refresh()
	_expect(bar._bar.visible and bar._name.text == "Stamp · Log bed (packed)" and not bar._undo.visible,
		"the stamper names its item and has no Undo: \"%s\"" % bar._name.text)
	bar._done.pressed.emit()
	await _frames(2)
	_expect(not stamper.is_active(), "Done ends stamping")


## Shapes: its shapes and Build's materials as rows of pictures, and a hollow rectangle's door
## gap and Filled; stairs take their height from the drag.
func _check_shapes() -> void:
	dock.tool_requested.emit("construct_shapes")
	await _frames(2)
	bar.refresh()
	_expect(bar._name.text == "Shapes" and bar._settings.get_node("Shape/Row").get_child_count() == 3
		and bar._settings.get_node("Material/Row").get_child_count() == 4, "Shapes shows its shapes and Build's materials")
	_expect(bar._settings.has_node("Door") and bar._settings.has_node("Toggle"), "a hollow rectangle offers a door gap and Filled")
	(bar._settings.get_node("Shape/Row/Stairs") as Button).pressed.emit()
	_expect(builder._shape == "stairs" and not bar._settings.has_node("Height") and not bar._settings.has_node("Toggle"),
		"stairs take their height from the drag")
	(bar._settings.get_node("Shape/Row/Rectangle") as Button).pressed.emit()
	dock.tool_requested.emit("construct_build")   # back to Build for the Undo check
	await _frames(2)


## Above the open shelf, clear of the slice tower, and inside a small screen.
func _check_placement() -> void:
	dock.tool_requested.emit("construct_stone")
	dock._orders.set_open(true, "orders")
	await _frames(3)
	bar.refresh()
	_expect(bar._bar.get_global_rect().end.y <= dock._orders.shelf_rect().position.y, "the bar sits above the open shelf")
	dock._orders.set_open(false)
	# The tower stands while Slice is on; this fixture has no slice, so it is shown by hand.
	var tower: Control = dock._time_slice_hud.tower
	for i in range(4):
		var size: Vector2i = [Vector2i(1280, 720), Vector2i(960, 540)][i % 2]
		if i == 2: dock.tool_requested.emit("construct_shapes")   # Shapes has the widest bar
		root.size = size
		await _frames(6)
		tower.visible = true
		bar.refresh()
		var rect: Rect2 = bar._bar.get_global_rect()
		_expect(not rect.intersects(tower.get_global_rect()) and rect.position.x >= 0.0 and rect.end.x <= float(size.x)
			and rect.end.y <= dock._dock_panel.get_global_rect().position.y, "%s's bar clears the tower and fits %s: bar %s, tower %s, dock %s"
			% [bar._name.text, size, rect, tower.get_global_rect(), dock._dock_panel.get_global_rect()])
	builder.deactivate()


func _move(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	root.push_input(event, true)


func _mouse_button(point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	root.push_input(event, true)
