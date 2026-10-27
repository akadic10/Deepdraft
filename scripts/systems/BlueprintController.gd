extends Node3D

## Copy and placing blueprints (doc 273, Phase 3), beside Build and Shapes. ConstructionController
## makes it as its child and owns the plans it lays; BlueprintLibrary keeps the blueprints.
## - Copy: drag a box (its footprint, then Height; With floor takes the layer it stands on too).
##   The box stands on the ground, even when the drag starts on a wall's face.
##   Every solid block in it becomes the material that builds it: rock, ore and gems stone;
##   dirt, grass and wood themselves; floors and plans their own. What the colony has not seen
##   is copied as the slice shows it, its strata, so a copy never gives away a cave, a buried
##   deposit or water in the rock (Hard Rule 11). The copy, trimmed to its blocks, is kept
##   under a name to change in the Blueprints window, which opens on it.
## - Placing (Place, in the Blueprints window): the blueprint follows the pointer as a green
##   ghost and R turns it a quarter (Shift + R back). A click plans it, one plan a material, and
##   Undo takes the placement back whole. Blocks in the way show in rust and are left out, as is
##   what the slice hides.
signal tool_active_changed(active: bool)
## A placement was planned: its receipt for the tool bar's Undo (doc 23, "The tool bar").
signal order_created(receipt: Dictionary)
## What a click did when it planned or kept nothing.
signal order_feedback(message: String)
## Copy kept a blueprint, which the Blueprints window then shows to be named.
signal blueprint_saved(id: String)

const Work = preload("res://scripts/components/ConstructionWork.gd")
const Picking = preload("res://scripts/components/ObjectPicking.gd")
const INVALID := Vector3i(-1, -1, -1)
const SIDES: Array[Vector3i] = [Vector3i.LEFT, Vector3i.RIGHT, Vector3i.UP, Vector3i.DOWN, Vector3i.FORWARD, Vector3i.BACK]
var construction: Node
var _mode := ""   # "copy" or "place"; "" while neither is on
var _blueprint := ""   # the blueprint being placed
var _turns := 0
var _height := 3
var _with_floor := false
var _dragging := false
var _anchor := INVALID
var _hover := INVALID
var _drag_plane_y := 0.0
var _pointer := Vector2(-1, -1)
var _elapsed := 0.0
var _box: MeshInstance3D
var _ghost: MeshInstance3D
var _clash: MeshInstance3D
var _ghost_cells: Dictionary = {}   # kind -> Array[Vector3i]: what a click plans
var _clashes: Array[Vector3i] = []
var _ghost_key := ""
var _copy_count := 0
var _copy_key := ""


func _ready() -> void:
	_box = MeshInstance3D.new()
	_box.mesh = BoxMesh.new()
	_box.material_override = _overlay_material(Color(.35, .75, 1, .22))
	_box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_box.visible = false
	add_child(_box)
	_ghost = _overlay(Color(.35, 1, .55, .4))
	_clash = _overlay(Color(1, .45, .25, .45))
	set_process(false)
	# While Copy or placing is on, world clicks are this tool's, not the object explorer's.
	add_to_group("click_tool")
	var dock: Node = construction.dock if construction != null else null
	if dock == null: return
	dock.tool_requested.connect(_on_tool_requested)
	if dock.has_method("register_blueprint_controller"): dock.register_blueprint_controller(self)


func _overlay(color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.material_override = _overlay_material(color)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	return node


func _overlay_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


func is_active() -> bool:
	return not _mode.is_empty()


## Whether a blueprint is being placed (Copy is the other mode).
func is_placing() -> bool:
	return _mode == "place"


## Copy is a dock tool; placing starts from the Blueprints window (place()). Any other tool
## ends both.
func _on_tool_requested(tool: String) -> void:
	if tool == "construct_copy": _set_mode("" if _mode == "copy" else "copy")
	elif tool != "blueprint_place": _set_mode("")


## Starts placing a blueprint, square to the world.
func place(id: String) -> void:
	if BlueprintLibrary.get_blueprint(id).is_empty(): return
	_blueprint = id
	_turns = 0
	_set_mode("place")


## The tool bar's Done, as Esc.
func deactivate() -> void:
	_set_mode("")


func _set_mode(mode: String) -> void:
	var was := is_active()
	_mode = mode
	_dragging = false
	_anchor = INVALID
	_hover = INVALID
	_box.visible = false
	_ghost.mesh = null
	_clash.mesh = null
	_ghost_cells.clear()
	_clashes.clear()
	_ghost_key = ""
	set_process(is_active())
	if was != is_active(): tool_active_changed.emit(is_active())


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= .1: _update()


# ── The tool bar ──────────────────────────────────────────────────────────────

## What the tool bar shows (doc 23, "The tool bar"). Copy: Height and With floor, and while a
## box is dragged its size and blocks; it makes no orders, so no Undo, only what it last
## copied. Placing: the blueprint's name, and beside the pointer its size, its blocks and what
## is in the way.
func tool_bar_state() -> Dictionary:
	if _mode == "copy":
		var state := {"tool": "construct_copy", "undo": false,
			"settings": [{"id": "height", "label": "Height", "value": _height, "min": 1, "max": BlueprintLibrary.MAX_SIZE.y,
				"keys": "Alt + Wheel", "tooltip": "How many blocks tall the box is, from the ground you drag on."}],
			"toggle": {"id": "floor", "label": "With floor", "on": _with_floor, "keys": "F",
				"tooltip": "Takes the layer the box stands on too: its floors, or the ground there."}}
		if _dragging:
			var box := _copy_box()
			state.selection = {"count": "%d × %d · %d tall" % [box.size.x, box.size.z, box.size.y], "short": false, "at": _pointer,
				"detail": "%d block%s to copy" % [_copy_count, "" if _copy_count == 1 else "s"]}
		return state
	var blueprint := BlueprintLibrary.get_blueprint(_blueprint)
	var state := {"tool": "blueprint_place", "name": "Place · %s" % String(blueprint.get("name", "")),
		"picture": "res://assets/ui/icons/blueprints.png", "family": "work"}
	if _hover != INVALID and not blueprint.is_empty():
		var size := turned_size(blueprint.size, _turns)
		var count := 0
		for kind: String in _ghost_cells: count += (_ghost_cells[kind] as Array).size()
		var cost := _cost()
		state.selection = {"count": "%d × %d · %d tall" % [size.x, size.z, size.y], "short": cost.short, "at": _pointer,
			"detail": "%d block%s · %s%s" % [count, "" if count == 1 else "s", cost.detail,
				" · %d in the way" % _clashes.size() if not _clashes.is_empty() else ""]}
	return state


func set_tool_setting(id: String, value: Variant) -> void:
	if id == "height": _height = clampi(int(value), 1, BlueprintLibrary.MAX_SIZE.y)
	elif id == "floor": _with_floor = bool(value)
	else: return
	_copy_key = ""
	_update(_pointer)


## What the placement takes against the stock, good by good: "39 rough stone · 6 in stock",
## "30 pine logs · 12 in stock", short when any runs out.
func _cost() -> Dictionary:
	var words: Array[String] = []
	var short := false
	for good: Dictionary in BlueprintLibrary.goods(_ghost_cells):
		if int(good.count) == 0: continue
		var need: int = int(good.count) * int(BlockRegistry.get_construction_def(good.kind).get("cost", 1))
		var stock := 0
		for item: String in BlockRegistry.construction_goods(good.kind, good.wood):
			stock += StockpileManager.get_available_total(item)
		words.append("%d %s · %d in stock" % [need, Work.good_words(good.kind, good.wood, need), stock])
		short = short or need > stock
	return {"detail": ", ".join(words), "short": short}


# ── Input ─────────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if not is_active(): return
	if event is InputEventMouseMotion:
		_update(event.position)
	elif event is InputEventKey and event.pressed and not event.echo and not (event.ctrl_pressed or event.alt_pressed or event.meta_pressed):
		if event.keycode == KEY_ESCAPE: deactivate()
		elif event.keycode == KEY_R and _mode == "place":
			_turns = posmod(_turns + (-1 if event.shift_pressed else 1), 4)
			_update(_pointer)
		elif event.keycode == KEY_F and _mode == "copy": set_tool_setting("floor", not _with_floor)
		else: return
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var wheel := 0
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]: wheel = 1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1
		if event.pressed and wheel != 0 and event.alt_pressed and _mode == "copy":
			set_tool_setting("height", _height + wheel)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if _mode == "place":
				if event.pressed:
					_update(event.position)
					place_here()
			elif event.pressed:
				_update(event.position)
				_anchor = _hover
				# The drag follows the ground the box stands on.
				_drag_plane_y = float(_anchor.y)
				_dragging = _anchor != INVALID
				_copy_key = ""
				_update(event.position)
			elif _dragging:
				_update(event.position)
				_finish_copy()
				_dragging = false
				_box.visible = false
			get_viewport().set_input_as_handled()


func _slice_top() -> int:
	return int(construction.renderer.slice_y) if construction.renderer != null else WorldData.WORLD_SIZE_Y - 1


## The air beside the face under the pointer (for Copy, on the ground below it), or along the
## drag's plane while a box is dragged.
func _update(mouse := Vector2(-1, -1)) -> void:
	_elapsed = 0.0
	if construction == null or construction.furniture == null or construction.mining == null: return
	if mouse.x < 0: mouse = get_viewport().get_mouse_position()
	_pointer = mouse
	var camera := get_viewport().get_camera_3d()
	if camera == null: return
	var hit: Dictionary = construction.furniture.surface_cell_for(mouse)
	_hover = Vector3i(hit.x, hit.y, hit.z) + Vector3i(hit.normal) if not hit.is_empty() else INVALID
	if _mode == "copy" and _hover != INVALID: _hover = _on_ground(_hover)
	if _dragging:
		var point = Plane(Vector3.UP, _drag_plane_y).intersects_ray(camera.project_ray_origin(mouse), camera.project_ray_normal(mouse))
		if point != null: _hover = Vector3i(floori(point.x), _anchor.y, floori(point.z))
	if _mode == "copy": _show_box()
	elif _mode == "place": _show_ghost()


# ── Copy ──────────────────────────────────────────────────────────────────────

## Copy's box stands on the ground: the air beside a wall's face drops to the floor below it, as
## the slice shows it, so a box begun on a wall still takes the whole wall.
func _on_ground(cell: Vector3i) -> Vector3i:
	var at := cell
	for i in range(BlueprintLibrary.MAX_SIZE.y):
		var below := at + Vector3i.DOWN
		if below.y < 0 or BlockRegistry.is_solid(Picking.concealed_block(below)): return at
		at = below
	return cell


## The box a copy takes: its lowest corner and its size, the footprint held to the largest
## blueprint, With floor reaching one layer down.
func _copy_box() -> Dictionary:
	var start := _anchor if _dragging else _hover
	var reach := BlueprintLibrary.MAX_SIZE - Vector3i.ONE
	var end := Vector3i(clampi(_hover.x, start.x - reach.x, start.x + reach.x), start.y, clampi(_hover.z, start.z - reach.z, start.z + reach.z))
	var floor := 1 if _with_floor else 0
	var low := Vector3i(mini(start.x, end.x), start.y - floor, mini(start.z, end.z))
	var height := mini(_height + floor, BlueprintLibrary.MAX_SIZE.y)
	return {"low": low, "size": Vector3i(absi(end.x - start.x) + 1, height, absi(end.z - start.z) + 1)}


func _show_box() -> void:
	if _hover == INVALID:
		_box.visible = false
		return
	var box := _copy_box()
	var size := Vector3(box.size)
	(_box.mesh as BoxMesh).size = size + Vector3.ONE * .02
	_box.position = Vector3(box.low) + size * .5
	_box.visible = true
	if not _dragging: return
	var key := str(box)
	if key == _copy_key: return
	_copy_key = key
	_copy_count = 0
	var copy := capture(box.low, box.size)
	for kind: String in copy.blocks: _copy_count += (copy.blocks[kind] as Array).size()


func _finish_copy() -> void:
	var box := _copy_box()
	var copy := capture(box.low, box.size)
	var count := 0
	for kind: String in copy.blocks: count += (copy.blocks[kind] as Array).size()
	if count == 0:
		order_feedback.emit("Nothing to copy here")
		return
	var blueprint := BlueprintLibrary.save(_free_name(), copy.size, copy.blocks)
	if blueprint.is_empty():
		order_feedback.emit("The blueprint could not be kept")
		return
	order_feedback.emit("Copied %d blocks as %s" % [count, blueprint.name])
	blueprint_saved.emit(String(blueprint.id))


## "Blueprint 3": the first number no blueprint of the player's is called by.
func _free_name() -> String:
	var taken := {}
	for blueprint: Dictionary in BlueprintLibrary.blueprints(): taken[String(blueprint.name)] = true
	var n := 1
	while taken.has("Blueprint %d" % n): n += 1
	return "Blueprint %d" % n


## The blocks in a box as the materials that build them (doc 273): plans as their own, rock,
## ore and gems as stone, dirt and grass as themselves, logs as their wood lying their way (doc
## 275). Air, water and bedrock stay empty, and what the colony has not seen is its strata
## (material_at). The copy is trimmed to its blocks, its cells from its corner: {size, blocks}.
func capture(low: Vector3i, size: Vector3i) -> Dictionary:
	var planned := {}
	for order in construction.orders.values():
		for cell: Vector3i in order.cells:
			planned[cell] = String(order.construction_kind) if order.wood.is_empty() \
				else BlueprintLibrary.log_material(order.wood, String(order.directions.get(cell, "up")))
	var found := {}
	var first := Vector3i(WorldData.WORLD_SIZE_X, WorldData.WORLD_SIZE_Y, WorldData.WORLD_SIZE_Z)
	var last := -Vector3i.ONE
	for x in range(size.x):
		for y in range(size.y):
			for z in range(size.z):
				var cell := low + Vector3i(x, y, z)
				var kind := String(planned[cell]) if planned.has(cell) else material_at(cell)
				if kind.is_empty(): continue
				found[cell] = kind
				first = Vector3i(mini(first.x, cell.x), mini(first.y, cell.y), mini(first.z, cell.z))
				last = Vector3i(maxi(last.x, cell.x), maxi(last.y, cell.y), maxi(last.z, cell.z))
	var blocks := {}
	for cell: Vector3i in found:
		if not blocks.has(found[cell]):
			var list: Array[Vector3i] = []
			blocks[found[cell]] = list
		(blocks[found[cell]] as Array).append(cell - first)
	return {"size": last - first + Vector3i.ONE if not found.is_empty() else Vector3i.ZERO, "blocks": blocks}


## The construction kind that would build what a cell holds, "" for nothing buildable. A cell the
## colony has not seen is taken as the slice shows it, its strata: a copy never gives away a
## cave, a buried deposit (cave soil is dirt) or water in the rock (Hard Rule 11).
static func material_at(cell: Vector3i) -> String:
	if cell.y < 0 or cell.y >= WorldData.WORLD_SIZE_Y: return ""
	if InteriorTracker.is_hidden_cave(cell):
		var rock := _strata_material(cell)
		return rock if not rock.is_empty() else "stone"
	var held := _block_material(WorldData.get_live_block(cell.x, cell.y, cell.z))
	# Rock, ore and gems all copy as stone, so only dirt and empty space can give anything away,
	# and open air above the ground hides nothing.
	if held != "dirt" and not held.is_empty(): return held
	if held.is_empty() and cell.y > WorldGenerator.get_surface_y(cell.x, cell.z): return held
	var shown := _strata_material(cell)
	return held if shown == held or _seen(cell) else shown


## The material that would build a block, "" for none: a log is its wood lying its way.
static func _block_material(id: int) -> String:
	var held := BlockRegistry.log_of(id)
	if not held.is_empty(): return BlueprintLibrary.log_material(String(held.wood), String(held.direction))
	var definition := BlockRegistry.get_def(BlockRegistry.get_key(id))
	match String(definition.get("kind", "void")):
		"void", "water", "bedrock": return ""
		"dirt": return "dirt"
		"grass": return "grass"
	return "stone"


## What the slice shows at a cell: the authored strata's material, without caves or deposits.
static func _strata_material(cell: Vector3i) -> String:
	return _block_material(WorldGenerator.get_overview_strata_block_id(cell.x, cell.y, cell.z))


## Whether the colony can have seen a cell: dug, built or explored, or facing open air or a cell
## that was.
static func _seen(cell: Vector3i) -> bool:
	if WorldData.has_terrain_override(cell) or InteriorTracker.is_known(cell): return true
	for side: Vector3i in SIDES:
		var near := cell + side
		if WorldData.has_terrain_override(near) or InteriorTracker.is_known(near) or _strata_material(near).is_empty(): return true
	return false


# ── Placing ───────────────────────────────────────────────────────────────────

## A blueprint's footprint after `turns` quarter turns.
static func turned_size(size: Vector3i, turns: int) -> Vector3i:
	return Vector3i(size.z, size.y, size.x) if posmod(turns, 2) == 1 else size


## A blueprint's cells turned `turns` quarters about its corner, still from the corner, a lying
## log's direction turning with them: {material: Array[Vector3i]}.
static func turned(blueprint: Dictionary, turns: int) -> Dictionary:
	var size: Vector3i = blueprint.size
	var result := {}
	for kind: String in blueprint.blocks:
		var cells: Array[Vector3i] = []
		for cell: Vector3i in blueprint.blocks[kind]:
			match posmod(turns, 4):
				1: cells.append(Vector3i(size.z - 1 - cell.z, cell.y, cell.x))
				2: cells.append(Vector3i(size.x - 1 - cell.x, cell.y, size.z - 1 - cell.z))
				3: cells.append(Vector3i(cell.z, cell.y, size.x - 1 - cell.x))
				_: cells.append(cell)
		result[BlueprintLibrary.turned_material(kind, turns)] = cells
	return result


## The ghost at the pointer: what a click would plan, green, and what is in the way, rust.
## Unexplored space shows as rock does, so the ghost never gives a cave away.
func _show_ghost() -> void:
	var blueprint := BlueprintLibrary.get_blueprint(_blueprint)
	if blueprint.is_empty():
		deactivate()
		return
	var key := "%s|%s|%d|%d" % [_blueprint, _hover, _turns, _slice_top()]
	if key == _ghost_key: return
	_ghost_key = key
	ghost_at(_hover)
	var green: Array[Vector3i] = []
	for kind: String in _ghost_cells: green.append_array(_ghost_cells[kind])
	_ghost.mesh = construction.mining.build_fill_mesh(green, Color.WHITE, .005) if not green.is_empty() else null
	_clash.mesh = construction.mining.build_fill_mesh(_clashes, Color.WHITE, .006) if not _clashes.is_empty() else null


## Works out the blueprint placed with its corner at `origin`: the cells a click plans, by
## material, and the cells in the way. What the slice hides is left out of both.
func ghost_at(origin: Vector3i) -> void:
	_ghost_cells.clear()
	_clashes.clear()
	var blueprint := BlueprintLibrary.get_blueprint(_blueprint)
	if origin == INVALID or blueprint.is_empty(): return
	var obstacles: Dictionary = construction.obstacle_snapshot()
	var top := _slice_top()
	var cells := turned(blueprint, _turns)
	for kind: String in cells:
		var planned: Array[Vector3i] = []
		for cell: Vector3i in cells[kind]:
			var at := origin + cell
			if at.y > top: continue
			if String(construction.build_reason(at, true, false, String(BlueprintLibrary.material_parts(kind).kind), obstacles)).is_empty(): planned.append(at)
			else: _clashes.append(at)
		_ghost_cells[kind] = planned


## Plans the blueprint where the ghost stands: one plan a kind and wood, its logs lying as they
## were copied, taken back together by Undo. How many blocks it planned.
func place_here() -> int:
	var ids: Array[int] = []
	var count := 0
	var plans := {}
	for material: String in _ghost_cells:
		var parts := BlueprintLibrary.material_parts(material)
		var key := "%s|%s" % [parts.kind, parts.wood]
		if not plans.has(key):
			var cells: Array[Vector3i] = []
			plans[key] = {"kind": String(parts.kind), "wood": String(parts.wood), "cells": cells, "directions": {}}
		for cell: Vector3i in _ghost_cells[material]:
			plans[key].cells.append(cell)
			if not String(parts.direction).is_empty(): plans[key].directions[cell] = parts.direction
	for plan: Dictionary in plans.values():
		if (plan.cells as Array).is_empty(): continue
		var id: int = construction.create_order(plan.cells, -1, false, plan.kind, plan.wood, plan.directions)
		if id < 0: continue
		ids.append(id)
		count += (construction.orders[id].cells as Array).size()
	if ids.is_empty():
		order_feedback.emit("Nothing of it can be planned here")
		return 0
	var name := String(BlueprintLibrary.get_blueprint(_blueprint).get("name", "blueprint"))
	order_created.emit({"orders": ids, "message": "Planned %s · %d blocks" % [name, count]})
	_ghost_key = ""
	_update(_pointer)
	return count


func order_is_pending(receipt: Dictionary) -> bool:
	for id: int in receipt.get("orders", []):
		if construction.orders.has(id): return true
	return false


func undo_order(receipt: Dictionary) -> int:
	var left := 0
	for id: int in receipt.get("orders", []):
		if not construction.orders.has(id): continue
		left += (construction.orders[id].cells as Array).size()
		construction.cancel_order(id)
	return left


func inspect_order(receipt: Dictionary) -> void:
	for id: int in receipt.get("orders", []):
		if construction.orders.has(id):
			construction.inspect_order({"order_id": id, "order": construction.orders[id]})
			return
