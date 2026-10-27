extends "res://scripts/tests/WorkerCraftingTest.gd"

## The Appeal view (doc 23 "The Appeal view"): its button sits before X-ray at the dock's
## end and lights while on; its scale (each word, its tint and range, highest first) rises
## above the dock as X-ray's options do. While on, the world dims, each room's floor takes
## its word's tint (rooms whose floor is above the slice hide), the pieces a room counts glow
## warm and its loose goods cool, and turning it off gives every piece its own look back.
## A screen point over a room's floor finds that room; its card gives the room's name, word,
## number and parts; a click there opens the room window on its Appeal tab. One pass scores
## every room as the room window does.

var rooms
var view
var room_tool
var stub_slice
var probe := Vector3i(62, 21, 62)


func _run() -> void:
	create_timer(150).timeout.connect(func(): push_error("Appeal view timeout"); quit(1))
	await _setup_crafting_fixture()
	rooms = root.get_node("RoomManager")
	rooms.clear_runtime_state()
	_walls(60, 69, 60, 69)
	_put("door", Vector3i(63, 20, 60))
	_put("log_bed", Vector3i(62, 20, 64))
	_put("wooden_torch", Vector3i(68, 20, 64))
	_put("hearth", Vector3i(67, 20, 67))
	_put("bench", Vector3i(68, 20, 61), 1)
	drops.spawn_drop(STONE, 1, Vector3i(61, 21, 62))
	_walls(80, 89, 60, 69)
	_put("door", Vector3i(83, 20, 60))
	rooms._rebuild_all_rooms()
	var id: int = rooms.get_room_id_at(probe)
	var bare: int = rooms.get_room_id_at(Vector3i(85, 21, 64))
	_one_pass(id, bare)
	# A slice cut just under the roofs lets the camera see the floors.
	stub_slice = _stub_slice(24)
	scene.add_child(stub_slice)
	room_tool = load("res://scripts/systems/RoomOverlayController.gd").new()
	room_tool.name = "RoomTool"
	room_tool.window_manager_path = NodePath("../Windows")
	room_tool.dock_ui_path = NodePath("../Dock")
	scene.add_child(room_tool)
	view = load("res://scripts/systems/AppealViewController.gd").new()
	view.name = "AppealView"
	view.dock_path = NodePath("../Dock")
	view.slice_path = NodePath("../Slice")
	view.rooms_tool_path = NodePath("../RoomTool")
	var tools: Array[NodePath] = [NodePath("../RoomTool")]
	view.tool_paths = tools
	scene.add_child(view)
	await _frames(3)
	await _button_and_scale()
	await _drawing(id, bare)
	await _hover_and_click(id)
	view.set_active(false)
	await _frames(2)
	_expect(not is_instance_valid(view._dim) and view._glows.is_empty() and _overlays(id).all(func(overlay) -> bool: return overlay == null),
		"turning the view off takes the dim, the tints and every glow away")
	for failure: String in failures: push_error(failure)
	print("APPEAL_VIEW_OK: one pass, button, scale, dim, tints, slice, glows, hover card, click and off" if failures.is_empty() else "APPEAL_VIEW_FAIL")
	quit(0 if failures.is_empty() else 1)


## All rooms in one pass give what each room gives, with the nodes the view lights.
func _one_pass(id: int, bare: int) -> void:
	var all: Dictionary = rooms.all_room_appeals()
	for room_id: int in [id, bare]:
		var single: Dictionary = rooms.room_appeal(rooms.get_rooms()[room_id])
		_expect(is_equal_approx(float(all[room_id].score), float(single.score)) and all[room_id].parts.size() == single.parts.size(),
			"one pass scores room %d as the room window does: %s and %s" % [room_id, all[room_id].score, single.score])
	_expect(is_equal_approx(float(all[id].score), 8.5) and all[id].warm.size() == 5 and all[id].cool.size() == 1,
		"the bedroom's five pieces (its door too) glow warm and its pile cool: %s warm, %s cool" % [all[id].warm.size(), all[id].cool.size()])
	_expect(all[bare].warm.size() == 1 and all[bare].word.word == "Plain", "a bare room lights only its door")


func _button_and_scale() -> void:
	var hud = dock._time_slice_hud
	_expect(hud.appeal_button.visible and hud.appeal_button.get_index() < hud.xray_button.get_index() and not hud.appeal_button.button_pressed,
		"the Appeal button sits before X-ray, off")
	hud.appeal_button.pressed.emit()
	await _frames(3)
	_expect(view.active and hud.appeal_button.button_pressed and hud.appeal_panel.visible, "the button turns the view on and lights")
	var texts: Array = hud._appeal_labels.map(func(label: Label) -> String: return label.text)
	_expect(texts.slice(0, 8) == ["Beautiful", "16 and up", "Pleasant", "8 to 16", "Plain", "0 to 8", "Horrid", "below 0"],
		"the scale lists each word with its range, highest first: %s" % [texts])
	var panel: Rect2 = hud.appeal_panel.get_global_rect()
	_expect(panel.end.y <= dock._dock_panel.get_global_rect().position.y and panel in hud.occupied_rects(),
		"the scale stands above the dock, and other panels keep clear of it")


func _drawing(id: int, bare: int) -> void:
	_expect(is_instance_valid(view._dim) and view._dim.material_override is ShaderMaterial, "the world dims")
	var tint := Color(String(rooms.appeal_step(8.5).tint), float(view._config.tint_alpha))
	var plain := Color(String(rooms.appeal_step(6.5).tint), tint.a)
	_expect(view._tints.multimesh.instance_count == 128 and _tint_is(id, tint) and _tint_is(bare, plain),
		"each room's 64 floor tiles take its word's tint: %s" % [view.room_tints])
	var bed_meshes: Array = _overlays(id)
	_expect(not bed_meshes.is_empty() and bed_meshes.all(func(overlay) -> bool: return overlay == view._glow_materials.warm),
		"the pieces the bedroom counts glow warm")
	var pile: Node3D = drops.loose_items()[0]
	_expect(view._meshes(pile).all(func(mesh: MeshInstance3D) -> bool: return mesh.material_overlay == view._glow_materials.cool), "its loose pile glows cool")
	drops.spawn_drop(STONE, 1, Vector3i(61, 21, 63))
	drops.spawn_drop(STONE, 1, Vector3i(62, 21, 63))
	view._refresh()
	_expect(_tint_is(id, plain) and _tint_is(bare, plain), "two more piles turn the bedroom Plain at the next refresh")
	stub_slice.y = 19
	view._mark_dirty()
	view._refresh()
	_expect(view._tints.multimesh.instance_count == 0 and view.room_tints.is_empty(), "a room whose floor is above the slice shows no tint")
	stub_slice.y = 24
	view._refresh()
	await _frames(2)


func _hover_and_click(id: int) -> void:
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 24
	camera.position = Vector3(64.5, 60, 64.5)
	camera.look_at(Vector3(64.5, 20, 64.5), Vector3.FORWARD)
	await _frames(2)
	var floor_point: Vector2 = camera.unproject_position(Vector3(62.5, 21.0, 62.5))
	var hit: Dictionary = view.room_under(floor_point)
	_expect(hit.get("id", -1) == id, "a screen point over the floor finds its room: %s" % hit)
	_expect(view.room_under(camera.unproject_position(Vector3(74.5, 21.0, 64.5))).is_empty(), "outside rooms finds none")
	view._fill_card(id)
	var title: String = view._card._title.text
	var status: String = view._card._status.text
	var body: String = view._card._body.text
	_expect(title == room_tool.room_title(rooms.get_rooms()[id], id) and status == "Plain · 6.5" and body.contains("Log bed  +3")
		and body.contains("3 × Loose goods  −3") and body.ends_with("Click for the room's appeal."), "the card names the room, its word, number and parts: %s / %s / %s" % [title, status, body])
	room_tool.activate()
	_expect(view._hover_blocked(), "no card while a click tool works")
	room_tool.deactivate()
	_expect(view.try_select_zone_at_screen(floor_point), "a click on the floor is the view's")
	await _frames(3)
	var window = room_tool._window_content
	_expect(room_tool._window_panel.visible and window._appeal.visible and window._banner_word.text == "Plain",
		"it opens the room window on its Appeal tab")
	room_tool._close_window()
	view.set_active(false)
	_expect(not view.try_select_zone_at_screen(floor_point), "with the view off, the floor click is not the view's")
	view.set_active(true)
	await _frames(2)


## Whether a room's 64 floor tiles show a colour.
func _tint_is(id: int, colour: Color) -> bool:
	var shown: Dictionary = view.room_tints.get(id, {})
	return int(shown.get("count", 0)) == 64 and (shown.get("colour", Color.BLACK) as Color).is_equal_approx(colour)


## The overlays on the meshes of the pieces a room counts.
func _overlays(id: int) -> Array:
	var overlays := []
	for node in rooms.all_room_appeals()[id].warm:
		for mesh in view._meshes(node): overlays.append(mesh.material_overlay)
	return overlays


## A stand-in for the SliceController: its height and whether it is on.
func _stub_slice(height: int) -> Node:
	var script := GDScript.new()
	script.source_code = "extends Node\nsignal slice_changed(height: int)\nvar y := 0\nfunc get_slice_y() -> int: return y\nfunc is_active() -> bool: return true\n"
	script.reload()
	var node: Node = script.new()
	node.name = "Slice"
	node.y = height
	return node


func _put(short_key: String, cell: Vector3i, yaw := 0):
	var key := "base:furniture:" + short_key
	furniture._install(key, furniture.get_defs()[key], cell, yaw)
	return furniture._installed[furniture._next_installed_id - 1]


## Stone walls and a roof around the floor x0+1..x1-1 by z0+1..z1-1 (y 20), with a
## two-wide doorway at x0+3 on the z0 side.
func _walls(x0: int, x1: int, z0: int, z1: int) -> void:
	var stone: int = blocks.get_id("base:terrain:rock:rock01")
	for x in range(x0, x1 + 1):
		for z in range(z0, z1 + 1):
			for y in range(21, 26):
				if x in [x0 + 3, x0 + 4] and z == z0 and y < 25: continue
				if x in [x0, x1] or z in [z0, z1] or y == 25: world.set_block(x, y, z, stone)
