extends Node3D

## Owns unfinished structural orders. Completed blocks belong to WorldData.
const Work = preload("res://scripts/components/ConstructionWork.gd")
const Picking = preload("res://scripts/components/ObjectPicking.gd")
const Shapes = preload("res://scripts/components/ConstructionShapes.gd")
const Inventory = preload("res://scripts/components/ColonyInventory.gd")
const INVALID := Vector3i(-1,-1,-1)
const DIRECTIONS := [Vector3i.LEFT,Vector3i.RIGHT,Vector3i.UP,Vector3i.DOWN,Vector3i.FORWARD,Vector3i.BACK]
@export var mining_path: NodePath
@export var furniture_path: NodePath
@export var renderer_path: NodePath
@export var dock_path: NodePath
signal tool_active_changed(active: bool)
## A plan was queued: its receipt for the tool bar's Undo (doc 23, "The tool bar").
signal order_created(receipt: Dictionary)
## What the last click did when it queued nothing ("No clear cells to build").
signal order_feedback(message: String)
var definition: Dictionary = {}
var orders: Dictionary = {}
var next_id := 1
var mining: Node
var furniture: Node
var renderer: Node
var dock: Node
var drops: ItemDropManager
## Copy and placing blueprints, its child (BlueprintController).
var blueprints: Node
var _sources: Dictionary = {}
var _dirty := true
var _active := false
var _dragging := false
var _anchor := INVALID
var _hover := INVALID
var _hover_plane_y := 0.0
var _drag_plane_y := 0.0
var _height := 1
var _preview: MeshInstance3D
var _plans: MeshInstance3D
var _preview_cells: Array[Vector3i] = []
var _reason := ""   # why the cell under the pointer cannot be built
var _pointer := Vector2(-1, -1)
var _preview_elapsed := 0.0
var _kind := "stone"
var _material := "stone"   # Build's chosen material (doc 275): stone, dirt, grass or wood, kept between uses
var _types := {}           # each material's chosen kind: Stone's native stone, Wood's upright or lying log
var _wood := ""            # the wood logs are built from; at first, the one the colony holds most of
var _log_axis := "x"       # which way a lying log points for a click or a square drag; R turns it
var _preview_dirs := {}    # logs: which way each previewed cell's log lies
var _ghost: Node3D         # a log drag's green ghost logs
var _roofs: Dictionary = {}   # column -> highest block that is not air, until a block changes
# Shapes (doc 273, Phase 2): Build's materials laid out as a rectangle, circle or stairs.
var _shapes := false
var _shape := "rectangle"
var _filled := false
var _door := 0   # a hollow rectangle's door gap, in blocks
var _stair_note := ""   # why a flight stops short
var _stair_size := Vector2i.ZERO   # the flight planned: its steps, and how wide
# Ctrl + drag removes plans block by block.
var _erasing := false
var _erase: MeshInstance3D
var _erase_cells: Array[Vector3i] = []
var _dev_feedback: Dictionary = {}
# Build's Replace switch (doc 285): a drag picks the blocks themselves, swapped for the material.
var _replace := false
var _moved: Dictionary = {}   # cells whose block changed since the last frame, for replace plans

func _ready() -> void:
	add_to_group("construction")
	add_to_group("object_explorer_provider")
	add_to_group(SaveManager.OWNER_GROUP)
	definition = BlockRegistry.get_construction_def("stone")
	if not mining_path.is_empty(): mining = get_node(mining_path)
	if not furniture_path.is_empty(): furniture = get_node(furniture_path)
	if not renderer_path.is_empty(): renderer = get_node(renderer_path)
	if not dock_path.is_empty(): dock = get_node(dock_path)
	drops = ItemDropManager.find(get_tree())
	if dock != null:
		dock.tool_requested.connect(_on_tool_requested)
		dock.register_construction_controller(self)
	if renderer != null:
		renderer.visible_volume_changed.connect(func(): _dirty = true; _dragging = false)
	_plans = _make_overlay("ConstructionPlans",Color(.25,.8,1,.26))
	_preview = _make_overlay("ConstructionPreview",Color(.35,1,.55,.4))
	_erase = _make_overlay("ConstructionErase",Color(1,.45,.25,.45))
	TaskManager.task_completed.connect(func(task: Task): _task_gone(task,-1))
	TaskManager.task_cancelled.connect(func(task: Task): _task_gone(task,task.assigned_to))
	TaskManager.task_failed.connect(func(task: Task,_why: String): _task_gone(task,task.assigned_to))
	TaskManager.task_released.connect(_task_released)
	WorldData.block_changed.connect(_on_block_changed)
	# Copy and placing blueprints (doc 273, Phase 3) work on these plans.
	blueprints = preload("res://scripts/systems/BlueprintController.gd").new()
	blueprints.name = "Blueprints"
	blueprints.construction = self
	add_child(blueprints)
	# Every Construction tool offers Mine blocks' 32 × 32 guide, on the one switch (doc 23).
	if mining != null:
		mining.offer_area_guide(self)
		mining.offer_area_guide(blueprints)

func _exit_tree() -> void:
	for id: int in orders.keys(): cancel_order(id,false)

## A block changed: grass looks for its open sky again, and a replace plan checks the block.
func _on_block_changed(cell: Vector3i, _old: int, _new: int) -> void:
	_roofs.erase(Vector2i(cell.x,cell.z))
	if not orders.is_empty(): _moved[cell] = true

func _make_overlay(label: String, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = label
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	return node

func _process(delta: float) -> void:
	if _dirty:
		_dirty = false
		_rebuild_visuals()
	if not SaveManager.is_loading():
		if not _moved.is_empty(): _sweep_replaced()
		for order in orders.values():
			if order.materials != null: order.materials.tick_site(delta,_slice_y())
			order.update_lease()
	if _active:
		_preview_elapsed += delta
		if _preview_elapsed >= .1: _update_preview()

func is_active() -> bool: return _active

func _tool_definition() -> Dictionary:
	return BlockRegistry.get_construction_def(_kind)

## Build's materials (doc 275): Stone, Dirt, Grass and Wood, in tool bar order.
func build_materials() -> Array[String]:
	var result: Array[String] = []
	result.assign(BlockRegistry.build_materials())
	return result

func _is_build(kind: String) -> bool:
	return BlockRegistry.get_construction_def(kind).get("tool","") == "build"

## A material's chosen kind: the one picked in its menu, else its first.
func _kind_of(material: String) -> String:
	var kinds: Array = BlockRegistry.get_build_material(material).get("kinds",[])
	return String(_types.get(material,kinds[0] if not kinds.is_empty() else ""))

## Build and Shapes open on their last material and type; `construct_<kind>` opens that kind.
func _on_tool_requested(tool: String) -> void:
	var shapes := tool == "construct_shapes"
	var kind := _kind_of(_material) if tool in ["construct_build", "construct_shapes"] else tool.trim_prefix("construct_")
	var supported := tool.begins_with("construct_") and not BlockRegistry.get_construction_def(kind).is_empty()
	_active = supported and not (_active and _kind == kind and _shapes == shapes)
	if supported:
		_kind = kind
		_shapes = shapes
	if _is_build(_kind):
		_material = BlockRegistry.build_material_of(_kind)
		_types[_material] = _kind
	if _wood.is_empty(): _wood = _likeliest_wood()
	_reason = ""
	_stair_note = ""
	_dragging = false
	_erasing = false
	# Build always opens building; Replace is switched on each time (doc 285).
	_replace = false
	_preview.mesh = null
	_erase.mesh = null
	_clear_ghost()
	tool_active_changed.emit(_active)

## The wood the colony holds the most logs of; the first wood when it holds none.
func _likeliest_wood() -> String:
	var best := ""
	var most := -1
	for wood: String in BlockRegistry.woods():
		var stock := StockpileManager.get_available_total(String(BlockRegistry.get_wood(wood).item_key))
		if stock > most:
			best = wood
			most = stock
	return best


## The tool bar's Done, as Esc.
func deactivate() -> void:
	if _active: _on_tool_requested("")


## What the tool bar shows (doc 23, "The tool bar"): Shapes' shape and Build's material as
## choices, Stone's and Wood's with the menu their picture opens, the height and a door gap as
## steppers, Filled, Build's Replace and the 32 × 32 guide as switches, and while a plan is
## dragged, its blocks and their goods against the stock (or, while erasing, the plans to go).
func tool_bar_state() -> Dictionary:
	var def := _tool_definition()
	var build := _is_build(_kind)
	var state := {"tool": "construct_shapes" if _shapes else ("construct_build" if build else "construct_" + _kind)}
	# Replace (doc 285) names the tool and shows its own keys while the switch is on.
	if _replace:
		state.name = "Replace"
		state.keys = "construct_replace"
	var choices := []
	if _shapes:
		var shapes := BlockRegistry.get_construction_shapes()
		var options := []
		for shape: String in shapes:
			options.append({"id": shape, "label": String(shapes[shape].label), "picture": String(shapes[shape].picture), "tooltip": String(shapes[shape].tooltip)})
		choices.append({"id": "shape", "label": "Shape", "value": _shape, "options": options, "keys": "Tab"})
		state.picture = String(shapes[_shape].picture)
	if build:
		var options := []
		for material: String in build_materials(): options.append(_material_option(material))
		choices.append({"id": "material", "label": "Material", "value": _material, "options": options, "keys": "Q / E"})
		if not _shapes: state.picture = Work.picture(_kind,_wood)
	if not choices.is_empty(): state.choices = choices
	var settings := []
	if int(def.get("max_height", 1)) > 1 and not (_shapes and _shape == "stairs"):
		settings.append({"id": "height", "label": "Height", "value": _column_height(), "min": 1, "max": int(def.max_height),
			"keys": "Alt + Wheel", "tooltip": "How many blocks tall each column is built."})
	if _shapes and _shape == "rectangle" and not _filled:
		settings.append({"id": "door", "label": "Door", "value": _door, "min": 0, "max": int(_door_widths().max()),
			"keys": "Shift + Wheel", "tooltip": "A door gap in the middle of the side facing you, 3 blocks tall: 2, 3 or 4 wide, as the doors come, or none."})
	if not settings.is_empty(): state.settings = settings
	var toggles := []
	if _shapes and _shape != "stairs":
		toggles.append({"id": "filled", "label": "Filled", "on": _filled, "keys": "F",
			"tooltip": "Fills the shape, a slab or a platform. Off, it is walls round its edge."})
	if build and not _shapes:
		toggles.append({"id": "replace", "label": "Replace", "on": _replace, "keys": "F",
			"tooltip": "Picks the blocks you point at, not the air in front of them. A dwarf digs each one out and sets the material in its place; blocks already of it are left."})
	if mining != null: toggles.append(mining.area_guide_toggle("building"))
	if not toggles.is_empty(): state.toggles = toggles
	if _erasing:
		state.selection = {"count": _drag_size(), "short": false, "at": _pointer,
			"detail": "takes %d planned block%s out" % [_erase_cells.size(), "" if _erase_cells.size() == 1 else "s"]}
	elif _dragging and not _preview_cells.is_empty():
		var cost := _cost(_preview_cells.size())
		state.selection = {"count": _drag_size(), "short": cost.short, "at": _pointer,
			"detail": "%d block%s · %s" % [_preview_cells.size(), "" if _preview_cells.size() == 1 else "s", cost.detail]}
		# Why a flight stops short goes on the tag too, where the eye is.
		if not _stair_note.is_empty(): state.selection.detail += "\n" + _stair_note
	if not _stair_note.is_empty(): state.message = _stair_note
	elif _preview_cells.is_empty() and not _erasing and not _reason.is_empty(): state.message = _reason
	return state


## A material on the tool bar: its name and its chosen type's picture. Stone and Wood also carry
## the menu their picture opens (doc 275, format A): its types, then for Wood the woods with
## their stock. Their cards are named for the material, then name the chosen type (owner,
## 2026-10-26): "Wood", then "Upright oak log. Stands on end. …".
func _material_option(material: String) -> Dictionary:
	var info := BlockRegistry.get_build_material(material)
	var kind := _kind_of(material)
	var option := {"id": material, "label": String(info.label), "picture": Work.picture(kind,_wood),
		"tooltip": String(BlockRegistry.get_construction_def(kind).tooltip)}
	if not info.has("menu"): return option
	option.tooltip = "%s. %s\nClick it for the %s menu." % [Work.type_name(kind,_wood), option.tooltip, String(info.label)]
	var types := []
	for each: String in info.kinds:
		var type_def := BlockRegistry.get_construction_def(each)
		types.append({"id": each, "label": String(type_def.type_label), "picture": Work.picture(each,_wood), "tooltip": String(type_def.tooltip)})
	var rows := [{"id": "type", "label": String(info.menu), "value": kind, "options": types}]
	if info.has("woods"):
		var woods := []
		for wood: String in BlockRegistry.woods():
			var words := BlockRegistry.get_wood(wood)
			var stock := StockpileManager.get_available_total(String(words.item_key))
			woods.append({"id": wood, "label": String(words.label), "tooltip": "1 %s a block. Mining it gives the log back." % String(words.one),
				"picture": "res://assets/ui/items/%s.png" % String(words.item_key).replace(":","_"),
				"count": str(stock), "tone": "fine" if stock > 0 else "blocked", "note": "%d %s in stock" % [stock, String(words.many)]})
		rows.append({"id": "wood", "label": String(info.woods), "value": _wood, "options": woods})
	option.menu = rows
	return option


## Height and the door gap from their steppers, the shape and the material from their choices,
## a material's type and wood from its menu, Filled, Replace and the guide from their switches. A
## material keeps the height chosen for the others, though grass is one block tall.
func set_tool_setting(id: String, value: Variant) -> void:
	if id == "guide" and mining != null: mining.set_mining_guide_enabled(bool(value))
	if id == "material" and String(value) in build_materials():
		_material = String(value)
		_kind = _kind_of(_material)
	elif id == "type" and String(value) in BlockRegistry.get_build_material(_material).get("kinds",[]):
		_kind = String(value)
		_types[_material] = _kind
	elif id == "wood" and not BlockRegistry.get_wood(String(value)).is_empty():
		_wood = String(value)
	elif id == "shape" and BlockRegistry.get_construction_shapes().has(String(value)):
		_shape = String(value)
	elif id == "filled":
		_filled = bool(value)
	elif id == "replace":
		_replace = bool(value) and _is_build(_kind) and not _shapes
	elif id == "door":
		_door = _door_width(int(value))
	elif id == "height":
		_height = clampi(int(value),1,int(_tool_definition().max_height))
	else: return
	_update_preview(_pointer)

func _door_widths() -> Array:
	return BlockRegistry.get_construction_shapes().rectangle.doors

## The door gap a step lands on: the next width the doors come in, past the ones they don't.
func _door_width(value: int) -> int:
	var widths := _door_widths().map(func(width: Variant) -> int: return int(width))
	widths.sort()
	if value in widths: return value
	if value < _door: widths.reverse()
	for width: int in widths:
		if (width > _door) == (value > _door) and width != _door: return width
	return _door

func _column_height() -> int:
	return clampi(_height,1,int(_tool_definition().max_height))


## A plan's cost against the stock: "27 rough stone · 6 in stock", short when it is more. Logs
## count the chosen wood's: "18 pine logs · 6 in stock". `kind` is the tool's own unless given.
func _cost(cells: int, kind := "") -> Dictionary:
	if kind.is_empty(): kind = _kind
	var def := BlockRegistry.get_construction_def(kind)
	var need := cells * int(def.get("cost", 1))
	var stock := 0
	for item: String in BlockRegistry.construction_goods(kind,_wood): stock += StockpileManager.get_available_total(item)
	return {"detail": "%d %s · %d in stock" % [need, Work.good_words(kind,_wood,need), stock], "short": need > stock}

func _unhandled_input(event: InputEvent) -> void:
	if not _active: return
	if event is InputEventMouseMotion:
		_update_preview(event.position)
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_on_tool_requested("")
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and not (event.ctrl_pressed or event.alt_pressed or event.meta_pressed) \
			and _key_setting(event.keycode,event.shift_pressed):
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var wheel := 0
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]: wheel = 1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1
		if event.pressed and wheel != 0 and event.alt_pressed:
			if int(_tool_definition().max_height) > 1:
				_height = clampi(_column_height()+wheel,1,int(_tool_definition().max_height))
			_update_preview(event.position)
			get_viewport().set_input_as_handled()
		elif event.pressed and wheel != 0 and event.shift_pressed and _shapes and _shape == "rectangle" and not _filled:
			set_tool_setting("door",_door+wheel)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if not event.ctrl_pressed and _inspect_at(event.position):
					_dragging = false
					get_viewport().set_input_as_handled()
					return
				_update_preview(event.position)
				# Ctrl + drag erases, from the plan under the pointer or the ground there.
				var plan := _plan_cell_at(event.position) if event.ctrl_pressed else INVALID
				_anchor = plan if plan != INVALID else _hover
				_drag_plane_y = float(plan.y)+.5 if plan != INVALID else _hover_plane_y
				_dragging = _anchor != INVALID
				_erasing = event.ctrl_pressed and _dragging
				if _erasing: _update_preview(event.position)
			else:
				if _dragging:
					_update_preview(event.position)
					if _erasing: _finish_erase()
					else:
						var id := create_order(_preview_cells,-1,false,_kind,_wood,_preview_dirs,{},"",_replace)
						if id >= 0: order_created.emit(_receipt(id))
						else: order_feedback.emit("No blocks here to replace" if _replace else "No clear cells to build")
				_dragging = false
				_erasing = false
				_erase.mesh = null
			get_viewport().set_input_as_handled()

## Q and E step through the materials, R turns a lying log, Tab (Shift + Tab back) steps through
## Shapes' shapes, and F fills a shape or empties it, or in Build switches Replace. False when the
## key does none of these.
func _key_setting(key: Key, back: bool) -> bool:
	if key in [KEY_Q,KEY_E] and _is_build(_kind):
		var materials := build_materials()
		set_tool_setting("material",materials[posmod(materials.find(_material)+(1 if key == KEY_E else -1),materials.size())])
	elif key == KEY_R and String(_tool_definition().get("logs","")) == "lie":
		_log_axis = "z" if _log_axis == "x" else "x"
		_update_preview(_pointer)
	elif key == KEY_TAB and _shapes:
		var shapes: Array = BlockRegistry.get_construction_shapes().keys()
		set_tool_setting("shape",shapes[posmod(shapes.find(_shape)+(-1 if back else 1),shapes.size())])
	elif key == KEY_F and _shapes and _shape != "stairs":
		set_tool_setting("filled",not _filled)
	elif key == KEY_F and _is_build(_kind) and not _shapes:
		set_tool_setting("replace",not _replace)
	else: return false
	return true

func _slice_y() -> int: return int(renderer.slice_y) if renderer != null else WorldData.WORLD_SIZE_Y-1

func target_from_hit(hit: Dictionary) -> Vector3i:
	if hit.is_empty(): return INVALID
	return Vector3i(hit.x,hit.y,hit.z)+Vector3i(hit.normal)

func _update_preview(mouse := Vector2(-1,-1)) -> void:
	_preview_elapsed = 0.0
	if furniture == null or mining == null: return
	if mouse.x < 0: mouse = get_viewport().get_mouse_position()
	_pointer = mouse
	var camera := get_viewport().get_camera_3d()
	if camera == null: return
	var hit: Dictionary = furniture.surface_cell_for(mouse)
	# Replace (doc 285) takes the block itself, not the air in front of its face.
	_hover = (Vector3i(hit.x,hit.y,hit.z) if not hit.is_empty() else INVALID) if _replace else target_from_hit(hit)
	if not hit.is_empty():
		_hover_plane_y = camera.project_ray_origin(mouse).y+camera.project_ray_normal(mouse).y*float(hit.distance)
	if _dragging:
		var point = Plane(Vector3.UP,_drag_plane_y).intersects_ray(camera.project_ray_origin(mouse),camera.project_ray_normal(mouse))
		if point != null: _hover = Vector3i(floori(point.x),_anchor.y,floori(point.z))
	_preview_cells.clear()
	_preview_dirs.clear()
	_stair_note = ""
	if _erasing:
		_show_preview()
		_update_erase()
		return
	if _hover == INVALID:
		_show_preview()
		_reason = ""
		return
	var start := _anchor if _dragging else _hover
	var reason := ""
	for cell: Vector3i in _shape_cells(start,_hover):
		if cell.y > _slice_y(): continue
		var invalid := replace_reason(cell,_kind,_wood) if _replace else build_reason(cell,true,false,_kind)
		if invalid.is_empty(): _preview_cells.append(cell)
		else: reason = invalid
	_preview_dirs = _directions(_preview_cells,start,_drag_finish(start,_hover))
	_show_preview()
	_reason = "" if not _preview_cells.is_empty() else (reason if not reason.is_empty() else ("No blocks here to replace" if _replace else "Raise the slice to build above this face"))

## The drag's preview: green cells, or for logs green ghost logs lying as they will be built
## (owner's pick, doc 275). Blocks to replace stay green cells, since a ghost would hide in them.
func _show_preview() -> void:
	if _preview_dirs.is_empty() or renderer == null or _replace:
		_clear_ghost()
		_preview.mesh = mining.build_fill_mesh(_preview_cells,Color.WHITE,.005) if not _preview_cells.is_empty() else null
		return
	_preview.mesh = null
	if is_instance_valid(_ghost) and _ghost.get_meta("dirs",{}) == _preview_dirs and _ghost.get_meta("wood","") == _wood: return
	_clear_ghost()
	_ghost = renderer.built_logs.ghost(_preview_dirs,_wood,_preview.material_override)
	_ghost.set_meta("dirs",_preview_dirs.duplicate())
	_ghost.set_meta("wood",_wood)
	add_child(_ghost)

func _clear_ghost() -> void:
	if is_instance_valid(_ghost): _ghost.queue_free()
	_ghost = null

## Which way each planned log lies (doc 275), {} for blocks. Upright logs stand. A lying log
## follows the drag's longer side, or R's way for a click or a square. Shapes lay a hollow
## rectangle's logs along each side, a circle's along the ring and stairs' across the flight.
func _directions(cells: Array[Vector3i], start: Vector3i, finish: Vector3i) -> Dictionary:
	var result := {}
	var lie := String(_tool_definition().get("logs",""))
	if lie.is_empty(): return result
	var span := Vector2i(absi(finish.x-start.x),absi(finish.z-start.z))
	var along := "x" if span.x > span.y else ("z" if span.y > span.x else _log_axis)
	var low := Vector2i(mini(start.x,finish.x),mini(start.z,finish.z))
	var high := Vector2i(maxi(start.x,finish.x),maxi(start.z,finish.z))
	for cell: Vector3i in cells:
		var direction := along
		if lie == "up": direction = "up"
		elif _shapes and _shape == "rectangle" and not _filled:
			direction = "x" if cell.z == low.y or cell.z == high.y else "z"
		elif _shapes and _shape == "circle":
			direction = "z" if absi(cell.x-start.x) > absi(cell.z-start.z) else "x"
		elif _shapes and _shape == "stairs":
			direction = "z" if span.x >= span.y else "x"
		result[cell] = direction
	return result

## The cells a drag from `start` to `end` plans, up to the drag limit across: Build's box, or
## Shapes' shape (doc 273). The caller leaves out what build_reason refuses and the slice hides.
func _shape_cells(start: Vector3i, end: Vector3i) -> Array[Vector3i]:
	var finish := _drag_finish(start,end)
	var sides: Array[Vector3i] = []
	if not _shapes: return Shapes.rectangle(start,finish,_column_height(),true,0,sides)
	match _shape:
		"circle":
			return Shapes.circle(start,_circle_radius(start,finish),_column_height(),_filled)
		"stairs":
			return _stair_cells(start,finish)
	var camera := get_viewport().get_camera_3d()
	sides = Shapes.facing_sides(-camera.global_basis.z if camera != null else Vector3.FORWARD)
	return Shapes.rectangle(start,finish,_column_height(),_filled,_door,sides)

## The drag's far corner, held to the drag limit across.
func _drag_finish(start: Vector3i, end: Vector3i) -> Vector3i:
	var limit := int(_tool_definition().max_drag_size)-1
	return Vector3i(clampi(end.x,start.x-limit,start.x+limit),start.y,clampi(end.z,start.z-limit,start.z+limit))

## A circle's radius from its centre out to the drag's end, at most half the drag limit.
func _circle_radius(center: Vector3i, finish: Vector3i) -> int:
	return mini(roundi(Vector2(finish.x-center.x,finish.z-center.z).length()),floori((int(_tool_definition().max_drag_size)-1)*.5))

## The drag's size for the tool bar's tag (owner, 2026-10-26: the player sees the dimensions):
## "12 × 10 · 3 tall" for a box or a rectangle, "9 across" for a circle, "6 steps · 2 wide" for
## stairs, and the box "4 × 3" while erasing.
func _drag_size() -> String:
	var finish := _drag_finish(_anchor,_hover)
	var tall := " · %d tall" % _column_height() if _column_height() > 1 and not _erasing else ""
	if _shapes and _shape == "stairs" and not _erasing:
		return "%d step%s · %d wide" % [_stair_size.x,"" if _stair_size.x == 1 else "s",_stair_size.y]
	if _shapes and _shape == "circle" and not _erasing:
		return "%d across%s" % [_circle_radius(_anchor,finish)*2+1,tall]
	return "%d × %d%s" % [absi(finish.x-_anchor.x)+1,absi(finish.z-_anchor.z)+1,tall]

## Shapes' stairs: the steps from the foot, until one would lack the dwarves' headroom (Hard
## Rule 4), which the tool bar then names. Grass, one block tall, makes none.
func _stair_cells(foot: Vector3i, top: Vector3i) -> Array[Vector3i]:
	var cells: Array[Vector3i] = []
	var def := _tool_definition()
	_stair_note = ""
	if bool(def.get("needs_sky", false)):
		_stair_note = "%s is one block tall, so it makes no stairs" % String(def.label)
		return cells
	var steps := Shapes.stairs(foot,top,int(def.max_drag_size))
	_stair_size = Vector2i(0,steps[0].cells.size() if not steps.is_empty() else 0)
	for i in range(steps.size()):
		for cell: Vector3i in steps[i].cells:
			if cell.y == int(steps[i].tread)-1 and _headroom_blocked(cell+Vector3i.UP):
				_stair_note = "Rock above step %d: stairs keep %d blocks of headroom" % [i+1,NavGrid.CLEARANCE]
				return cells
		cells.append_array(steps[i].cells)
		_stair_size.x = i+1
	return cells

## Whether rock fills any of the dwarves' clearance from `cell` up. Unexplored caves count as
## rock, so stairs never give one away (Hard Rule 11).
func _headroom_blocked(cell: Vector3i) -> bool:
	for up in range(NavGrid.CLEARANCE):
		var at := cell+Vector3i(0,up,0)
		if BlockRegistry.is_solid(WorldData.get_live_block(at.x,at.y,at.z)) or InteriorTracker.is_hidden_cave(at): return true
	return false

## The planned cell under the pointer, when terrain does not hide it.
func _plan_cell_at(screen: Vector2) -> Vector3i:
	var camera := get_viewport().get_camera_3d()
	if camera == null or _plan_at_screen(screen).is_empty(): return INVALID
	var start := camera.project_ray_origin(screen)
	var end := start+camera.project_ray_normal(screen)*600.0
	var nearest := INF
	var result := INVALID
	for order in orders.values():
		for cell: Vector3i in order.cells:
			if cell.y > _slice_y(): continue
			var point = AABB(Vector3(cell),Vector3.ONE).intersects_segment(start,end)
			if point != null and start.distance_to(point) < nearest:
				nearest = start.distance_to(point)
				result = cell
	return result

## Ctrl + drag (doc 273): every plan's blocks in the box's columns, up to the slice.
func _update_erase() -> void:
	_erase_cells.clear()
	if _anchor != INVALID and _hover != INVALID:
		var finish := _drag_finish(_anchor,_hover)
		var low := Vector2i(mini(_anchor.x,finish.x),mini(_anchor.z,finish.z))
		var high := Vector2i(maxi(_anchor.x,finish.x),maxi(_anchor.z,finish.z))
		for order in orders.values():
			for cell: Vector3i in order.cells:
				if cell.y <= _slice_y() and cell.x >= low.x and cell.x <= high.x and cell.z >= low.y and cell.z <= high.y:
					_erase_cells.append(cell)
	_erase.mesh = mining.build_fill_mesh(_erase_cells,Color.WHITE,.006) if not _erase_cells.is_empty() else null

## Takes the erase box's blocks out of their plans.
func _finish_erase() -> void:
	var marked := {}
	for cell: Vector3i in _erase_cells: marked[cell] = true
	var removed := 0
	for id: int in orders.keys():
		var gone: Array = orders[id].cells.filter(func(cell: Vector3i) -> bool: return marked.has(cell))
		if gone.is_empty(): continue
		removed += gone.size()
		erase_cells(id,gone)
	order_feedback.emit("Took %d planned block%s out of their plans" % [removed,"" if removed == 1 else "s"] if removed > 0 else "No plans here to take out")

## Takes cells out of a plan, block by block. A plan left empty is cancelled; a crate holding
## more than the plan still needs gives the rest back, and a builder at a taken cell lets go.
func erase_cells(id: int, cells: Array) -> void:
	var order = orders.get(id)
	if order == null: return
	var taken := {}
	for cell: Vector3i in cells:
		var good: String = order.good_of(cell)
		taken[good] = int(taken.get(good,0))+1
		order.cells.erase(cell)
		order.work_progress.erase(cell)
	order.total_blocks = maxi(order.total_blocks-cells.size(),order.cells.size())
	# Each good keeps the blocks it still has, built or planned.
	var need: Dictionary = order.needs()
	for good: String in taken:
		order.totals[good] = maxi(int(order.totals.get(good,0))-int(taken[good]),int(need.get(good,0)))
		if int(order.totals[good]) <= 0: order.totals.erase(good)
	if order.cells.is_empty():
		cancel_order(id)
		return
	if order.target != INVALID and not order.cells.has(order.target) and order.source_id >= 0:
		TaskManager.cancel_source_tasks(order.source_id)
	if order.materials != null: order.materials.refund_excess()
	order.update_lease()
	_dirty = true

## A queued plan's receipt: the tool bar's Undo takes back what is not built yet.
func _receipt(id: int) -> Dictionary:
	var order = orders[id]
	var message := "Queued %d %s · %s" % [order.cells.size(), "replacements" if order.replace else "blocks",
		String(_cost(order.cells.size(),order.construction_kind).detail).get_slice(" · ", 0)]
	return {"order_id": id, "order": order, "message": message}

func order_is_pending(receipt: Dictionary) -> bool:
	return orders.get(int(receipt.order_id)) == receipt.order

func undo_order(receipt: Dictionary) -> int:
	if not order_is_pending(receipt): return 0
	var left: int = orders[int(receipt.order_id)].cells.size()
	cancel_order(int(receipt.order_id))
	return left

func inspect_order(receipt: Dictionary) -> void:
	var explorer := get_tree().get_first_node_in_group("object_explorer")
	if order_is_pending(receipt) and explorer != null: explorer.select_object(self,int(receipt.order_id))

func _inspect_at(screen: Vector2) -> bool:
	var explorer := get_tree().get_first_node_in_group("object_explorer")
	if explorer == null: return false
	var hit: Dictionary = explorer.pick_at_screen(screen)
	return not hit.is_empty() and hit.provider == self and explorer.select_object(self,hit.id)

func _plan_at_screen(screen: Vector2) -> Dictionary:
	# Use shared arbitration when available so terrain and foreground objects
	# protect plans from selection or cancellation through them.
	var explorer := get_tree().get_first_node_in_group("object_explorer")
	if explorer != null:
		var hit: Dictionary = explorer.pick_at_screen(screen)
		return hit if hit.get("provider") == self else {}
	var camera := get_viewport().get_camera_3d()
	if camera == null: return {}
	var origin := camera.project_ray_origin(screen)
	var direction := camera.project_ray_normal(screen)
	var terrain := Picking.terrain_hit(origin,direction,_slice_y())
	return pick_explorer_object(origin,origin+direction*minf(600.0,float(terrain.get("distance",600.0))+.002))

func pick_explorer_object(start: Vector3,end: Vector3) -> Dictionary:
	var result := {}
	var distance := start.distance_to(end)
	for id: int in orders:
		var materials = orders[id].materials
		if materials != null and is_instance_valid(materials.visual) and materials.visual.visible:
			var point = AABB(Vector3(materials.crate_cell)+Vector3(.05,1,.05),Vector3(.9,.6,.9)).intersects_segment(start,end)
			if point != null and start.distance_to(point)<distance:
				distance = start.distance_to(point)
				result = {"id":id,"distance":distance}
		for cell: Vector3i in orders[id].cells:
			if cell.y > _slice_y(): continue
			var point = AABB(Vector3(cell),Vector3.ONE).intersects_segment(start,end)
			if point != null and start.distance_to(point)<distance:
				distance = start.distance_to(point)
				result = {"id":id,"distance":distance}
	return result

func get_explorer_bounds(object_id: Variant) -> AABB:
	var order = orders.get(object_id)
	var bounds := AABB()
	if order == null: return bounds
	for cell: Vector3i in order.cells:
		if cell.y > _slice_y(): continue
		var box := AABB(Vector3(cell),Vector3.ONE)
		bounds = box if bounds.size == Vector3.ZERO else bounds.merge(box)
	return bounds

func get_explorer_data(object_id: Variant) -> Dictionary:
	var order = orders.get(object_id)
	if order == null or get_explorer_bounds(object_id).size == Vector3.ZERO: return {}
	# The compact panel (doc 260): the plan's construction icon and one status line. A placed
	# blueprint (doc 276) is named for it, and a plan of several goods counts each.
	var picture := Work.picture(order.construction_kind,order.wood) if order.project_name.is_empty() else "res://assets/ui/icons/blueprints.png"
	var task := TaskManager.get_task(order.lease_id())
	var worker: DwarfAgent = TaskManager.get_agent(order.builder_id)
	var materials = order.materials
	var goods: Array = order.totals.keys()
	var mixed := goods.size() > 1
	var good := Work.good_words(order.construction_kind,order.wood) if not mixed else Work.items_words(goods)
	var short: Array = order.needs().keys().filter(func(item: String) -> bool: return materials.staged_count(item) < int(order.needs()[item]))
	var waiting := "Waiting for %s" % (good if not mixed else Work.items_words(short))
	var status := waiting
	var details := "Deliver all materials to the temporary crate, then hammer each block. Cancelling returns unused %s; completed blocks remain." % good
	if mixed: details = "Deliver each good to the temporary crate; a good's blocks are hammered once all of it is in. Cancelling returns unused %s; completed blocks remain." % good
	# Replace (doc 285): the builder digs each old block out and hammers the new one in.
	if order.replace: details = "Deliver all materials to the temporary crate, then dig out each old block and hammer the new one into its place. The old block drops what mining it would. Cancelling returns unused %s; replaced blocks remain." % good
	var haulers: Array[String] = []
	for dwarf_id: int in materials.puller_ids():
		var hauler: DwarfAgent = TaskManager.get_agent(dwarf_id)
		if is_instance_valid(hauler): haulers.append(hauler.dwarf_name)
	if materials.crate_cell == INVALID or materials.delivery_stand_cells(materials.crate_cell).is_empty():
		status = "No delivery access"
	elif is_instance_valid(worker):
		var working := worker.get_task_phase() == DwarfAgent.TaskPhase.FETCH_WORKING
		status = ("Replacing" if working else "Going to replace") if order.replace else ("Building" if working else "Going to build")
	elif order.ready_for_staged_work():
		status = "Waiting for builder"
		if task != null and task.blocked_count > 0:
			status = "No construction access"
			details = task.wait_reason+"\n\n"+details
	elif not haulers.is_empty(): status = "Delivering materials"
	if task != null and task.recovery_paused: status = "Needs attention"
	var progress := "—"
	if order.cells.has(order.target):
		progress = "%d%%" % roundi(clampf(float(order.work_progress.get(order.target,0.0))/order.work_seconds_of(order.target),0.0,1.0)*100.0)
	var built: int = order.total_blocks - order.cells.size()
	# A plan of several goods names those still short; its Materials card counts each.
	var delivered := " · %d / %d %s delivered" % [materials.count() + built, order.total_blocks, good] if not mixed else ""
	var count := delivered if status in [waiting, "Delivering materials"] else " · %d / %d blocks %s" % [built, order.total_blocks, "replaced" if order.replace else "built"]
	var tone := "blocked" if status.begins_with("No ") or status == "Needs attention" else "waiting" if status.begins_with("Waiting") else "fine"
	# One Materials row, or for several goods a row each: "Oak logs · 30 / 247 delivered".
	var rows := [["Status",status],["Blocks left",str(order.cells.size())]]
	var on_way: Array[String] = []
	if not mixed:
		rows.append(["Materials","%d / %d %s delivered" % [materials.count()+built,order.total_blocks,good]])
		on_way.append("%d %s" % [materials.in_transit(),good])
	else:
		for item: String in goods:
			var total := int(order.totals[item])
			var item_built := total-int(order.needs().get(item,0))
			var words := Work.item_words(item)
			rows.append([words.left(1).to_upper()+words.substr(1),"%d / %d delivered" % [materials.staged_count(item)+item_built,total]])
			on_way.append("%d %s" % [materials.in_transit(item),Work.item_words(item,materials.in_transit(item))])
	rows.append_array([["Worker",worker.dwarf_name if is_instance_valid(worker) else "None assigned"],
		["Current block",progress],["On the way",", ".join(on_way)],
		["Delivery workers",", ".join(haulers) if not haulers.is_empty() else "None assigned"],
		["Completed","%d / %d blocks" % [built,order.total_blocks]],
		["Work remaining","%.1f seconds at normal speed" % order.total_remaining_work()]])
	var dev_note := "DEV finish uses delivered materials and supplies any missing ones instantly. Occupied or unsupported blocks stay pending."
	if order.replace: dev_note = "DEV finish uses delivered materials and supplies any missing ones instantly. The old blocks drop nothing."
	return {"title":order.project_name if not order.project_name.is_empty() else order.title(),
		"family":"work", "picture":picture,
		"status":{"text":status + count, "tone":tone},
		"rows":rows,
		"details":details+_dev_details(object_id,dev_note),
		"actions":[{"id":"materials","text":"Materials","card":"materials"},
			{"id":"dev_build","text":"DEV: Finish construction","variant":"dev"},{"id":"cancel","text":"Cancel construction","variant":"danger"}],
		"cards":{"materials":_materials_card(order,haulers)}}

## The Materials card (doc 23, owner's option C, 2026-10-27): each good the plan takes, how much
## is delivered and on the way, its stock on a tag, and who is hauling. Stock counts what the
## colony holds unclaimed, stored or loose (`ColonyInventory.available`).
func _materials_card(order: RefCounted, haulers: Array[String]) -> Dictionary:
	var rows := []
	# The good with the most blocks first, the walls' before a roof's, saved or not.
	var items: Array = order.totals.keys()
	items.sort_custom(func(a: String, b: String) -> bool: return int(order.totals[a]) > int(order.totals[b]) or (int(order.totals[a]) == int(order.totals[b]) and a < b))
	for item: String in items:
		var total := int(order.totals[item])
		var delivered: int = order.materials.staged_count(item) + total - int(order.needs().get(item,0))
		var coming: int = order.materials.in_transit(item)
		var stock := Inventory.available(drops,item)
		var words := Work.item_words(item)
		var tag := "All in" if delivered >= total else ("None in stock" if stock == 0 else "%d in stock" % stock)
		var tone := "fine" if delivered >= total else ("blocked" if stock == 0 and coming == 0 else "waiting")
		rows.append({"picture":Inventory.thumbnail_path(item),"name":words.left(1).to_upper()+words.substr(1),
			"detail":"%d of %d delivered · %d on the way" % [delivered,total,coming],"tag":tag,"tone":tone})
	return {"title":"Materials","rows":rows,
		"footer":"Hauling: %s" % ", ".join(haulers) if not haulers.is_empty() else "No one is hauling"}

## DEV notes and results appear only while the development tools are on.
func _dev_details(object_id: Variant,note: String) -> String:
	return "\n%s\n%s" % [note,String(_dev_feedback.get(object_id,""))] if UIRegistry.dev_tools_enabled else ""

func perform_explorer_action(object_id: Variant,action_id: String) -> void:
	if action_id == "cancel": cancel_order(int(object_id))
	elif action_id == "dev_build": dev_build_order(int(object_id))

## A work-stand pass is synchronous: capture moving actors and loose items
## once for that call, never across frames or while a route search yields.
func obstacle_snapshot() -> Dictionary:
	var actors: Array[AABB] = []
	for actor in TaskManager.get_agents():
		if is_instance_valid(actor): actors.append(AABB(actor.global_position-Vector3(.5,0,.5),Vector3(1,3,1)))
	var loose := {}
	if drops != null:
		for item in drops.loose_items():
			if is_instance_valid(item): loose[drops.item_floor_cell(item)+Vector3i.UP] = true
	return {"actors":actors,"loose":loose}

func build_reason(cell: Vector3i, planning := true, require_support := true, kind := "stone", obstacles: Dictionary = {}) -> String:
	if cell.x < 0 or cell.z < 0 or cell.y <= 3 or cell.x >= WorldData.WORLD_SIZE_X or cell.z >= WorldData.WORLD_SIZE_Z or cell.y >= WorldData.WORLD_SIZE_Y: return "Outside the buildable world"
	# A cave not yet found is the rock it shows as, with rock's reason (Hard Rule 11).
	if WorldData.get_live_block(cell.x,cell.y,cell.z) != BlockRegistry.AIR_ID or InteriorTracker.is_hidden_cave(cell):
		return "Mine existing terrain before building"
	if WaterManager.has_standing_water(cell): return "Clear water before building"
	var def := BlockRegistry.get_construction_def(kind)
	if bool(def.get("needs_sky", false)) and _roof(cell) > cell.y: return "%s needs open sky above" % String(def.label)
	if PlacedEntityRegistry.occupies(cell): return "A placed object occupies this cell"
	var area := AABB(Vector3(cell)+Vector3.ONE*.001,Vector3.ONE*.998)
	if obstacles.has("actors"):
		for bounds: AABB in obstacles.actors:
			if area.intersects(bounds): return "A dwarf occupies this cell"
	else:
		for actor in TaskManager.get_agents():
			if is_instance_valid(actor) and area.intersects(AABB(actor.global_position-Vector3(.5,0,.5),Vector3(1,3,1))): return "A dwarf occupies this cell"
	if obstacles.has("loose"):
		if obstacles.loose.has(cell): return "Haul loose items clear first"
	elif drops != null:
		for item in drops.loose_items():
			if is_instance_valid(item) and drops.item_floor_cell(item)+Vector3i.UP == cell: return "Haul loose items clear first"
	if furniture != null:
		for group: Array in [furniture.get_ghost_pieces(),furniture.get_installed_pieces()]:
			for piece in group:
				if furniture.visual_bounds(piece.def,piece.origin_cell,piece.yaw_steps).intersects(area): return "Furniture or a placement plan occupies this cell"
		if furniture.get_ladders().reserves(area): return "Keep access structures clear"
	for zone: StockpileZoneComponent in StockpileManager.get_zones():
		if zone.tile_cells.has(cell-Vector3i.UP): return "Remove the storage designation first"
	if planning:
		for order in orders.values():
			if order.cells.has(cell): return "Construction already planned here"
	if require_support:
		var supported := false
		for direction: Vector3i in DIRECTIONS:
			var neighbour := cell+direction
			if BlockRegistry.is_solid(WorldData.get_terrain_block(neighbour.x,neighbour.y,neighbour.z)):
				supported = true
				break
		if not supported: return "Waiting for an adjoining solid block"
	return ""

## The highest block in a column that is not air, so grass can find the open sky. Kept until a
## block in the column changes.
func _roof(cell: Vector3i) -> int:
	var column := Vector2i(cell.x,cell.z)
	if not _roofs.has(column):
		_roofs[column] = -1
		for y in range(WorldData.MAX_Y,-1,-1):
			if WorldData.get_live_block(cell.x,y,cell.z) != BlockRegistry.AIR_ID:
				_roofs[column] = y
				break
	return int(_roofs[column])

## Why Replace (doc 285) can't take a block, "" when it can: a solid block with an open face,
## above bedrock's layers, not marked for mining or planned, and not already what `kind` builds.
## The open face keeps a drag to what the colony sees: a wall's face, never the rock behind it,
## and a cave or deposit not yet found reads as the rock around it (Hard Rule 11).
func replace_reason(cell: Vector3i, kind := "stone", wood := "", planning := true) -> String:
	if cell.x < 0 or cell.z < 0 or cell.y <= 3 or cell.x >= WorldData.WORLD_SIZE_X or cell.z >= WorldData.WORLD_SIZE_Z or cell.y >= WorldData.WORLD_SIZE_Y: return "Outside the buildable world"
	if not open_face(cell): return "Only a block with an open face can be replaced"
	var block := WorldData.get_live_block(cell.x,cell.y,cell.z)
	if not BlockRegistry.is_solid(block): return "Nothing here to replace"
	if mining != null and mining.is_marked(cell): return "Marked for mining"
	var def := BlockRegistry.get_construction_def(kind)
	if _already(block,kind,wood):
		var words := "a %s log" % String(BlockRegistry.get_wood(wood).get("label","")).to_lower() if def.has("logs") else Work.type_name(kind,wood).to_lower()
		return "Already %s" % words
	if bool(def.get("needs_sky", false)) and _roof(cell) > cell.y: return "%s needs open sky above" % String(def.label)
	if planning:
		for order in orders.values():
			if order.cells.has(cell): return "Construction already planned here"
	return ""

## Whether a block faces air the colony knows. Water and a cave not yet found count as closed.
func open_face(cell: Vector3i) -> bool:
	for direction: Vector3i in DIRECTIONS:
		var near: Vector3i = cell+direction
		if WorldData.get_live_block(near.x,near.y,near.z) == BlockRegistry.AIR_ID and not InteriorTracker.is_hidden_cave(near): return true
	return false

## Whether a block is already what `kind` builds: natural rock for stone (built stone is its
## layer's rock), the kind's own block for dirt and grass, a log of the wood, whichever way it lies.
func _already(block: int, kind: String, wood: String) -> bool:
	var def := BlockRegistry.get_construction_def(kind)
	if def.has("logs"): return String(BlockRegistry.log_of(block).get("wood","")) == wood
	if def.has("block_key"): return BlockRegistry.get_key(block) == StringName(String(def.block_key))
	return String(BlockRegistry.get_def(BlockRegistry.get_key(block)).get("kind","")) == "rock"

## A replaced block's dig, timed as Mine blocks times it: {swings, swing_time}, {} for nothing to dig.
func dig_work(cell: Vector3i) -> Dictionary:
	return mining.get_zone_block_work(cell) if mining != null and cell != INVALID else {}

func play_dig_impact(cell: Vector3i, contact: Vector3, normal: Vector3) -> void:
	if mining != null: mining.play_zone_mining_impact(cell,contact,normal)

## The block panel's Replace list (doc 285): each of Build's materials, as its chosen type, that
## could take the block's place, with its picture and stock: "Native stone · 6 in stock".
func replace_options(cell: Vector3i) -> Array:
	if _wood.is_empty(): _wood = _likeliest_wood()
	var options := []
	for material: String in build_materials():
		var kind := _kind_of(material)
		if not replace_reason(cell,kind,_wood).is_empty(): continue
		options.append({"id": "replace:" + material, "picture": Work.picture(kind,_wood),
			"text": "%s · %s" % [Work.type_name(kind,_wood), String(_cost(1,kind).detail).get_slice(" · ",1)]})
	return options

## The panel's Replace: plans one block's replacement with a material's chosen type, as a drag
## with Replace on would, and shows the plan. -1 when it can't.
func replace_block(cell: Vector3i, material: String) -> int:
	if not material in build_materials(): return -1
	if _wood.is_empty(): _wood = _likeliest_wood()
	var cells: Array[Vector3i] = [cell]
	var id := create_order(cells,-1,false,_kind_of(material),_wood,{},{},"",true)
	if id < 0: return id
	var receipt := _receipt(id)
	order_created.emit(receipt)
	inspect_order(receipt)
	return id

## Where a replace plan's crate is sought from and its lease points: a floor a builder could work
## its lowest reachable block from, else its first block.
func _replace_origin(cells: Array[Vector3i]) -> Vector3i:
	for cell: Vector3i in cells:
		var stands := stands_for(cell)
		if not stands.is_empty(): return stands[0]
	return cells[0]

## A replace plan's block that changed under it leaves the plan, as Ctrl + drag takes one out:
## mined out, or made what the plan would make it.
func _sweep_replaced() -> void:
	var moved := _moved
	_moved = {}
	for id: int in orders.keys():
		var order = orders.get(id)
		if order == null or not order.replace: continue
		var gone: Array[Vector3i] = []
		for cell: Vector3i in order.cells:
			if not moved.has(cell): continue
			var block := WorldData.get_live_block(cell.x,cell.y,cell.z)
			if not BlockRegistry.is_solid(block) or _already(block,order.kind_of(cell),order.wood_of(cell)): gone.append(cell)
		if not gone.is_empty(): erase_cells(id,gone)

func stands_for(cell: Vector3i) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	if cell == INVALID: return result
	for side: Vector3i in [Vector3i.LEFT,Vector3i.RIGHT,Vector3i.FORWARD,Vector3i.BACK]:
		for y in range(maxi(3,cell.y-int(definition.reach_up)),mini(WorldData.WORLD_SIZE_Y,cell.y+int(definition.reach_down)+1)):
			var stand := Vector3i(cell.x+side.x,y,cell.z+side.z)
			if NavGrid.is_walkable(stand): result.append(stand)
	return result

## A plan of blocks. Logs (doc 275) name their wood and which way each cell's log lies. A placed
## blueprint (doc 276) is one plan of several materials: `own` gives a block its own kind and
## wood ([kind, wood]) where they are not the plan's, and `project_name` is the blueprint's. A
## replace plan (doc 285) holds solid blocks to swap for the kind, by Replace's rules.
func create_order(requested: Array[Vector3i], saved_id := -1, restoring := false, kind := "stone", wood := "", directions: Dictionary = {}, own: Dictionary = {}, project_name := "", replace := false) -> int:
	var def := BlockRegistry.get_construction_def(kind)
	if not _buildable(kind,wood): return -1
	var cells: Array[Vector3i] = []
	var taken := {}
	for cell: Vector3i in requested:
		if taken.has(cell): continue
		var cell_kind := String(own[cell][0]) if own.has(cell) else kind
		if own.has(cell) and not _buildable(cell_kind,String(own[cell][1])): continue
		var reason := "" if restoring else (replace_reason(cell,cell_kind,wood) if replace else build_reason(cell,true,false,cell_kind))
		if restoring or (cell.y<=_slice_y() and reason.is_empty()):
			cells.append(cell)
			taken[cell] = true
	if cells.is_empty(): return -1
	cells.sort_custom(func(a: Vector3i,b: Vector3i): return a.y<b.y if a.y!=b.y else (a.x<b.x if a.x!=b.x else a.z<b.z))
	var id := saved_id if saved_id > 0 else next_id
	next_id = maxi(next_id,id+1)
	var order = Work.new()
	order.controller = self
	order.construction_kind = kind
	order.project_name = project_name
	order.replace = replace
	if def.has("logs"): order.wood = wood
	for cell: Vector3i in cells:
		if own.has(cell):
			var cell_def := BlockRegistry.get_construction_def(String(own[cell][0]))
			var material := [String(own[cell][0]),String(own[cell][1]) if cell_def.has("logs") else ""]
			if material != [kind,order.wood]: order.own[cell] = material
		var logs := String(BlockRegistry.get_construction_def(order.kind_of(cell)).get("logs",""))
		if not logs.is_empty(): order.directions[cell] = "up" if logs == "up" else String(directions.get(cell,_log_axis))
	order.setup(id,kind,def,_replace_origin(cells) if replace else cells[0]-Vector3i.UP,0)
	order.cells = cells
	order.total_blocks = cells.size()
	order.totals = order.needs().duplicate()
	order.drop_manager = drops
	orders[id] = order
	order.source_id = TaskManager.allocate_source_id()
	_sources[order.source_id] = id
	TaskManager.register_work_source(order.source_id,order)
	order.initialize_materials()
	order.materials.source_id = TaskManager.allocate_source_id()
	_sources[order.materials.source_id] = id
	TaskManager.register_work_source(order.materials.source_id,order.materials)
	if not SaveManager.is_loading() and not restoring:
		place_materials_crate(order.materials)
		order.update_lease()
	_dirty = true
	return id

## Whether a kind can be planned: one the game knows, and a log with a wood.
func _buildable(kind: String, wood: String) -> bool:
	var def := BlockRegistry.get_construction_def(kind)
	return not def.is_empty() and not (def.has("logs") and BlockRegistry.get_wood(wood).is_empty())

## Automatic packaging on a clear, flat patch. Keep an open ring around it;
## never occupy stairs, storage, access structures, doors or any blueprint.
func _crate_site_clear(site: Vector3i) -> bool:
	if site == INVALID or not NavGrid.is_walkable(site): return false
	for offset: Vector3i in [Vector3i.ZERO,Vector3i.LEFT,Vector3i.RIGHT,Vector3i.FORWARD,Vector3i.BACK]:
		var around := site+offset
		if not NavGrid.is_walkable(around): return false
		for dy in range(1,4):
			for order in orders.values():
				if order.cells.has(around+Vector3i(0,dy,0)): return false
	return build_reason(site+Vector3i.UP,true,false).is_empty()

func place_materials_crate(materials: RefCounted) -> void:
	if is_instance_valid(materials.visual): return
	var order: RefCounted = materials.project()
	var chosen: Vector3i = materials.crate_cell
	if not _crate_site_clear(chosen):
		chosen = INVALID
		var origin: Vector3i = order.origin_cell
		var radius := int(order.def.get("materials_crate_radius",6))
		for ring in range(1,radius+1):
			for dx in range(-ring,ring+1):
				for dz in range(-ring,ring+1):
					if maxi(absi(dx),absi(dz)) != ring: continue
					for dy in [0,-1,1,-2,2]:
						var candidate := origin+Vector3i(dx,dy,dz)
						if _crate_site_clear(candidate):
							chosen = candidate
							break
					if chosen != INVALID: break
				if chosen != INVALID: break
			if chosen != INVALID: break
	if chosen == INVALID:
		materials.crate_cell = INVALID
		return
	materials.crate_cell = chosen
	var scene := load(String(order.def.materials_crate_model)) as PackedScene
	materials.visual = scene.instantiate()
	preload("res://scripts/components/VoxelShadowSetup.gd").configure(materials.visual)
	materials.visual.name = "ConstructionMaterials%d" % order.ghost_id
	# Generated meshes carry their wood colors in vertices, like loose goods.
	# Share the drop owner's material so enclosed rooms use the same lighting.
	drops.apply_item_material(materials.visual)
	add_child(materials.visual)
	materials.visual.position = Vector3(chosen)+Vector3(.5,1,.5)
	materials.occupancy = PlacedEntityRegistry.register_box(chosen+Vector3i.UP,Vector3i.ONE)
	materials.visual.visible = chosen.y+1 <= _slice_y()

## Goods waiting in materials crates, by item and material, as the colony's stock counts them.
func staged_inventory() -> Dictionary:
	var result := {}
	for order in orders.values():
		if order.materials == null: continue
		for item: String in order.materials.staged:
			if not result.has(item): result[item] = {}
			var staged: Dictionary = order.materials.staged[item]
			for material: String in staged:
				result[item][material] = int(result[item].get(material,0))+int(staged[material])
	return result

## The block a finished cell becomes, by its own kind: a log of its wood lying its way, the
## kind's own block (dirt, grass), else the natural rock of its layer (stone).
func block_key_for(order: RefCounted, cell: Vector3i) -> String:
	var def: Dictionary = BlockRegistry.get_construction_def(order.kind_of(cell))
	if def.has("logs"): return String(BlockRegistry.log_block(order.wood_of(cell),String(order.directions.get(cell,"up"))))
	if def.has("block_key"): return String(def.block_key)
	return String(BlockRegistry.get_key(WorldGenerator.construction_stone_id(cell)))

func commit_block(order: RefCounted) -> void:
	# A replaced block drops what mining it would, at its builder's feet, since its own cell
	# stays solid (doc 285).
	if order.replace and mining != null:
		var cell: Vector3i = order.target
		var worker: DwarfAgent = TaskManager.get_agent(order.builder_id)
		if is_instance_valid(worker): mining.spawn_block_drops(WorldData.get_live_block(cell.x,cell.y,cell.z),worker.current_cell()+Vector3i.UP)
	_place_block(order.target,block_key_for(order,order.target))

func _place_block(cell: Vector3i, key: String) -> void:
	mining.ensure_chunk_real(cell)
	WorldData.set_block(cell.x,cell.y,cell.z,BlockRegistry.get_id(key))
	NavGrid.refresh_mined_block(cell)
	_dirty = true

func dev_build_order(id: int) -> int:
	var order = orders.get(id)
	if order == null: return 0
	# Abort before changing the blueprint: haulers drop carried supplies and
	# builders release their tool/stance through the ordinary task lifecycle.
	if order.source_id >= 0: TaskManager.cancel_source_tasks(order.source_id)
	if order.materials != null: TaskManager.cancel_source_tasks(order.materials.source_id)
	var count := 0
	var reason := ""
	var obstacles := obstacle_snapshot()
	var progressed := true
	# A supported end can be later in cell order; repeat only while new
	# adjoining blocks allow more of the original blueprint to finish.
	while progressed:
		progressed = false
		reason = ""
		for cell: Vector3i in order.cells.duplicate():
			var invalid: String = order.blocked_reason(cell,order.kind_of(cell),obstacles)
			if cell.y > _slice_y(): invalid = "Raise the slice to show the remaining blocks"
			if not invalid.is_empty():
				reason = invalid
				continue
			if order.materials != null: order.materials.consume(order.good_of(cell))
			_place_block(cell,block_key_for(order,cell))
			order.cells.erase(cell)
			order.work_progress.erase(cell)
			count += 1
			progressed = true
	_dev_feedback[id] = "Finished %d blocks. %s" % [count,reason]
	if order.cells.is_empty(): cancel_order(id)
	else: order.update_lease()
	_dirty = true
	return count

func cancel_order(id: int, refund_materials := true) -> void:
	var order = orders.get(id)
	if order == null: return
	orders.erase(id)
	_dev_feedback.erase(id)
	if order.source_id >= 0:
		TaskManager.cancel_source_tasks(order.source_id)
		_sources.erase(order.source_id)
		TaskManager.unregister_work_source(order.source_id)
	order.release_claim()
	if order.materials != null:
		var materials = order.materials
		TaskManager.cancel_source_tasks(materials.source_id)
		materials.release_storage_claims()
		_sources.erase(materials.source_id)
		TaskManager.unregister_work_source(materials.source_id)
		if refund_materials: materials.refund()
		materials.remove_visual()
	_dirty = true

func _task_gone(task: Task, dwarf: int) -> void:
	var order = orders.get(_sources.get(task.source_id,-1))
	if order == null: return
	var source := TaskManager.get_work_source(task.source_id)
	if source != null: source.on_task_gone(task.id,dwarf)
	if order.cells.is_empty(): cancel_order(order.ghost_id)
	_dirty = true

func _task_released(task: Task,dwarf: int,_why: int) -> void:
	var order = orders.get(_sources.get(task.source_id,-1))
	if order != null:
		if task.source_id == order.source_id: order.cancel_fetch(dwarf)
		else: order.materials.cancel_haul(dwarf)

func _rebuild_visuals() -> void:
	if mining != null:
		var pending: Array[Vector3i] = []
		for order in orders.values():
			for cell: Vector3i in order.cells:
				if cell.y <= _slice_y(): pending.append(cell)
		_plans.mesh = mining.build_fill_mesh(pending,Color.WHITE,.004) if not pending.is_empty() else null

func save_section_key() -> String: return "construction"
func save_restore_priority() -> int: return 15

func serialize_state() -> Dictionary:
	var saved_orders := []
	for order in orders.values():
		var pending := []
		for cell: Vector3i in order.cells:
			var saved := {"cell":SaveManager.pack_v3i(cell),"work":float(order.work_progress.get(cell,0.0))}
			if order.directions.has(cell): saved["dir"] = String(order.directions[cell])
			# A placed blueprint's block of another material names its own (doc 276).
			if order.own.has(cell):
				saved["kind"] = String(order.own[cell][0])
				if not String(order.own[cell][1]).is_empty(): saved["wood"] = String(order.own[cell][1])
			pending.append(saved)
		var entry := {"id":order.ghost_id,"kind":order.construction_kind,"cells":pending,"total_blocks":order.total_blocks}
		if not order.wood.is_empty(): entry["wood"] = order.wood
		if order.replace: entry["replace"] = true
		if not order.project_name.is_empty(): entry["name"] = order.project_name
		if order.totals.size() > 1: entry["totals"] = order.totals.duplicate()
		if order.materials != null:
			entry["materials"] = order.materials.staged.duplicate(true)
			if order.materials.crate_cell != INVALID: entry["crate_cell"] = SaveManager.pack_v3i(order.materials.crate_cell)
		saved_orders.append(entry)
	return {"orders":saved_orders,"next_id":next_id}

func restore_state(state: Dictionary) -> void:
	for id: int in orders.keys(): cancel_order(id,false)
	next_id = int(state.next_id)
	for entry: Dictionary in state.orders:
		var cells: Array[Vector3i] = []
		var directions := {}
		var own := {}
		for pending: Dictionary in entry.cells:
			cells.append(SaveManager.unpack_v3i(pending.cell))
			if pending.has("dir"): directions[cells.back()] = String(pending.dir)
			if pending.has("kind"): own[cells.back()] = [String(pending.kind),String(pending.get("wood",""))]
		var id := create_order(cells,int(entry.id),true,String(entry.kind),String(entry.get("wood","")),directions,own,String(entry.get("name","")),bool(entry.get("replace",false)))
		if id >= 0:
			orders[id].total_blocks = int(entry.total_blocks)
			# Each good's blocks, built ones included; a plan of one good has them all.
			var totals := {}
			for good: String in entry.get("totals",{}): totals[good] = int(entry.totals[good])
			if totals.is_empty(): totals[orders[id].good_of(INVALID)] = int(entry.total_blocks)
			orders[id].totals = totals
			if orders[id].materials != null:
				orders[id].materials.staged = entry.get("materials",{}).duplicate(true)
				# Restore the location after furniture/storage owners load too.
				orders[id].materials.crate_cell = SaveManager.unpack_v3i(entry.crate_cell) if entry.has("crate_cell") else INVALID
				if not SaveManager.is_loading(): place_materials_crate(orders[id].materials)
			for pending: Dictionary in entry.cells: orders[id].work_progress[SaveManager.unpack_v3i(pending.cell)] = float(pending.work)
	_dirty = true
