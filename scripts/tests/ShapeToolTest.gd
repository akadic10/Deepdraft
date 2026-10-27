extends "res://scripts/tests/ConstructionTest.gd"

## Shapes (doc 273, Phase 2):
## - rectangles (hollow, filled, one-wide walls, door gaps) and circles plan the right cells,
##   and stairs climb a block a step along the drag's longer axis;
## - Shapes is its own tool: Tab steps through the shapes, F fills them, the door gap steps
##   past the widths the doors don't come in, stairs take their height from the drag;
## - rock in a step's headroom stops the flight there, and grass makes no stairs;
## - rock in the way is left out, the slice caps the height, and one Undo takes back a shape;
## - Ctrl + drag takes blocks out of plans one by one, gives back what a crate no longer needs,
##   and a plan with nothing left is gone.
const Shapes = preload("res://scripts/components/ConstructionShapes.gd")

class SliceStub extends Node:
	var slice_y := 127

func _run() -> void:
	create_timer(90).timeout.connect(func(): push_error("Shape tool test timed out"); quit(1))
	await _setup_fixture()
	await _new_trip(STONE,8)
	stockpiles.reset_runtime_state()
	stockpiles._process(0)
	nav = root.get_node("NavGrid")
	root.get_node("WorldGenerator")._cache_block_ids()
	mine = load("res://scripts/systems/MiningDesignationController.gd").new()
	scene.add_child(mine)
	mine.set_process(false)
	construction = load("res://scripts/systems/ConstructionController.gd").new()
	construction.mining = mine
	scene.add_child(construction)
	construction.set_process(false)
	_geometry_test()
	_tool_test()
	_planning_test()
	_erase_test()
	_expect(tasks.lifecycle_errors().is_empty(),"shapes leave no orphan tasks or claims")
	for failure: String in failures: push_error(failure)
	print("SHAPE_TOOL_OK" if failures.is_empty() else "SHAPE_TOOL_FAIL")
	quit(0 if failures.is_empty() else 1)

func _loose_of(key: String) -> int:
	var total := 0
	for entry: Dictionary in drops.serialize_state().loose:
		if String(entry.item_key) == key: total += int(entry.count)
	return total

func _geometry_test() -> void:
	var none: Array[Vector3i] = []
	var toward_z: Array[Vector3i] = [Vector3i(0,0,1),Vector3i(1,0,0)]
	var toward_x: Array[Vector3i] = [Vector3i(1,0,0),Vector3i(0,0,1)]
	var a := Vector3i(40,21,40)
	_expect(Shapes.rectangle(a,a+Vector3i(4,0,3),1,false,0,none).size()==14,"a hollow 5 × 4 rectangle keeps its 14 edge blocks")
	_expect(Shapes.rectangle(a,a+Vector3i(4,0,3),2,true,0,none).size()==40,"a filled one, two tall, is 40 blocks")
	_expect(Shapes.rectangle(a,a+Vector3i(6,0,0),3,false,0,none).size()==21,"a one-wide rectangle is a wall")
	var door := Shapes.rectangle(a,a+Vector3i(6,0,4),4,false,3,toward_z)
	_expect(door.size()==71 and not door.has(a+Vector3i(3,0,4)) and door.has(a+Vector3i(3,3,4)) and door.has(a+Vector3i(1,0,4)),
		"a door gap 3 wide opens 3 tall in the middle of the side facing the camera")
	var wall := Shapes.rectangle(a,a+Vector3i(6,0,0),3,false,2,toward_x)
	_expect(wall.size()==15 and not wall.has(a+Vector3i(2,0,0)) and not wall.has(a+Vector3i(3,0,0)),
		"a wall end-on to the camera takes its door in its long side")
	_expect(Shapes.rectangle(a,a+Vector3i(3,0,3),1,false,4,toward_z).size()==12,"a door too wide for a side leaves it whole")
	_expect(Shapes.circle(a,2,1,true).size()==21 and Shapes.circle(a,2,1,false).size()==12,"a circle 5 across: 21 blocks filled, a ring of 12")
	_expect(Shapes.circle(a,0,3,false).size()==3,"a circle of radius 0 is one column")
	var flight := Shapes.stairs(a,a+Vector3i(3,0,1),32)
	var count := 0
	for step: Dictionary in flight: count += step.cells.size()
	_expect(flight.size()==4 and count==20 and int(flight[3].tread)==a.y+4,"four steps up, two wide, each a column under its tread")
	_expect(Shapes.stairs(a,a+Vector3i(-1,0,-5),32).size()==6,"a flight runs along the drag's longer axis")

func _tool_test() -> void:
	construction._on_tool_requested("construct_shapes")
	var state: Dictionary = construction.tool_bar_state()
	_expect(construction.is_active() and state.tool=="construct_shapes","Shapes is its own tool")
	_expect(state.choices.size()==2 and state.choices[0].id=="shape" and state.choices[1].id=="material","Shapes chooses a shape, then a material")
	_expect(state.toggle.id=="filled" and state.settings.map(func(setting: Dictionary) -> String: return setting.id)==["height","door"],
		"a hollow rectangle offers its height, a door gap and Filled")
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_TAB
	construction._unhandled_input(key)
	_expect(construction._shape=="circle","Tab steps to the next shape")
	key.keycode = KEY_F
	construction._unhandled_input(key)
	_expect(construction._filled and not construction.tool_bar_state().settings.any(func(setting: Dictionary) -> bool: return setting.id=="door"),
		"F fills the shape, which keeps no door gap")
	key.keycode = KEY_TAB
	key.shift_pressed = true
	construction._unhandled_input(key)
	_expect(construction._shape=="rectangle","Shift + Tab steps back")
	construction.set_tool_setting("filled",false)
	construction.set_tool_setting("door",1)
	_expect(construction._door==2,"the door gap steps past 1, to the doors' 2")
	construction.set_tool_setting("door",1)
	_expect(construction._door==0,"and back past 1 to none")
	construction.set_tool_setting("shape","stairs")
	state = construction.tool_bar_state()
	_expect(not state.has("settings") and not state.has("toggle"),"stairs take their height from the drag")
	var foot := Vector3i(44,21,44)
	_expect(construction._shape_cells(foot,foot+Vector3i(3,0,0)).size()==10,"a four-step flight plans ten blocks")
	world.set_block(foot.x+2,foot.y+5,foot.z,blocks.get_id("base:terrain:rock:rock01"))
	var cells: Array[Vector3i] = construction._shape_cells(foot,foot+Vector3i(3,0,0))
	_expect(cells.size()==3 and construction._stair_note.begins_with("Rock above step 3"),
		"rock in a step's headroom stops the flight there: \"%s\"" % construction._stair_note)
	_expect(construction.tool_bar_state().message==construction._stair_note,"the tool bar says why the flight stops")
	world.set_block(foot.x+2,foot.y+5,foot.z,blocks.AIR_ID)
	construction.set_tool_setting("material","grass")
	_expect(construction._shape_cells(foot,foot+Vector3i(3,0,0)).is_empty() and construction._stair_note.contains("no stairs"),"grass makes no stairs")
	construction.set_tool_setting("material","stone")
	construction.set_tool_setting("shape","rectangle")
	construction.deactivate()

func _planning_test() -> void:
	construction._on_tool_requested("construct_shapes")
	construction.set_tool_setting("height",3)
	var corner := Vector3i(48,21,44)
	world.set_block(corner.x,corner.y+1,corner.z,blocks.get_id("base:terrain:rock:rock01"))
	var ring: Array[Vector3i] = construction._shape_cells(corner,corner+Vector3i(3,0,3))
	var id: int = construction.create_order(ring,-1,false,"stone")
	_expect(ring.size()==36 and construction.orders[id].cells.size()==35,"rock in the way is left out of a hollow rectangle three tall")
	_expect(construction.undo_order(construction._receipt(id))==35 and not construction.orders.has(id),"one Undo takes back a whole shape")
	world.set_block(corner.x,corner.y+1,corner.z,blocks.AIR_ID)
	var stub := SliceStub.new()
	stub.slice_y = 22
	construction.renderer = stub
	id = construction.create_order(construction._shape_cells(corner,corner+Vector3i(3,0,3)),-1,false,"stone")
	_expect(construction.orders[id].cells.size()==24,"the slice caps the height: two of three courses")
	construction.cancel_order(id)
	construction.renderer = null
	stub.free()
	# The tag gives the drag's size (owner, 2026-10-26).
	construction._anchor = corner
	construction._hover = corner+Vector3i(11,0,9)
	_expect(construction._drag_size()=="12 × 10 · 3 tall","a rectangle's tag gives its size: %s" % construction._drag_size())
	construction.set_tool_setting("shape","circle")
	construction._hover = corner+Vector3i(4,0,0)
	_expect(construction._drag_size()=="9 across · 3 tall","a circle's, across: %s" % construction._drag_size())
	construction.set_tool_setting("shape","stairs")
	construction._shape_cells(corner,corner+Vector3i(5,0,1))
	_expect(construction._drag_size()=="6 steps · 2 wide","stairs', in steps: %s" % construction._drag_size())
	construction.set_tool_setting("shape","rectangle")
	construction._anchor = Vector3i(-1,-1,-1)
	construction._hover = Vector3i(-1,-1,-1)
	construction.deactivate()

func _erase_test() -> void:
	var none: Array[Vector3i] = []
	var plan := Vector3i(44,21,48)
	var id: int = construction.create_order(Shapes.rectangle(plan,plan+Vector3i(2,0,0),2,true,0,none),-1,false,"stone")
	var order = construction.orders[id]
	order.materials.staged = {STONE: {"": 6}}
	var loose := _loose_of(STONE)
	construction._anchor = plan
	construction._hover = plan
	construction._erasing = true
	construction._update_erase()
	_expect(construction._erase_cells.size()==2,"the erase box takes every planned block in its columns")
	_expect(construction._drag_size()=="1 × 1","the erase box gives its size, never a height")
	construction._erasing = false
	construction._finish_erase()
	_expect(order.cells.size()==4 and order.total_blocks==4,"Ctrl + drag takes blocks out of a plan one by one")
	_expect(order.materials.count()==4 and _loose_of(STONE)==loose+2,"the crate gives back what the plan no longer needs")
	construction._hover = plan+Vector3i(2,0,0)
	construction._update_erase()
	construction._finish_erase()
	_expect(not construction.orders.has(id),"a plan with nothing left is gone")
	construction._anchor = Vector3i(-1,-1,-1)
	construction._hover = Vector3i(-1,-1,-1)
