extends "res://scripts/tests/ConstructionTest.gd"

## Build's materials (doc 273, doc 275):
## - logs take only the chosen wood, each block is that wood's log lying its way, and mining
##   gives the log back whole;
## - dirt and grass cost soil and become the world's own dirt and grass; grass needs open
##   sky, which comes back when the roof goes;
## - Build opens on its last material, Q and E step through the four, Stone's and Wood's
##   pictures carry their menus, a drag lays logs along its longer side and R turns them for a
##   click, grass hides the height, and the tag counts the chosen wood's logs;
## - a log plan keeps its wood, its directions and its crate through a save.
const PINE := "base:resources:wood:pine_log"
const OAK := "base:resources:wood:oak_log"
const SOIL := "base:resources:soil:soil"

func _run() -> void:
	create_timer(100).timeout.connect(func(): push_error("Build materials test timed out"); quit(1))
	await _setup_fixture()
	await _new_trip(PINE,2)
	drops.restore_loose_item(OAK,Vector3(41.5,21,40.65),0,1)
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
	_terrain_before = world.terrain_overrides()
	await _log_test()
	_soil_test()
	_tool_test()
	_log_save_test()
	_expect(tasks.lifecycle_errors().is_empty(),"building leaves no orphan tasks or claims")
	for failure: String in failures: push_error(failure)
	print("BUILD_MATERIALS_OK" if failures.is_empty() else "BUILD_MATERIALS_FAIL")
	quit(0 if failures.is_empty() else 1)

func _key_at(cell: Vector3i) -> String:
	return String(blocks.get_key(world.get_terrain_block(cell.x,cell.y,cell.z)))

func _loose_of(key: String) -> int:
	var total := 0
	for entry: Dictionary in drops.serialize_state().loose:
		if String(entry.item_key) == key: total += int(entry.count)
	return total

func _log_test() -> void:
	var cells := _cells([Vector3i(44,21,40),Vector3i(45,21,40)])
	var id: int = construction.create_order(cells,-1,false,"log_horizontal","pine",{cells[0]:"x",cells[1]:"x"})
	_expect(construction.orders[id].materials.filter_items==[PINE],"a log plan's crate takes only its wood")
	_expect(construction.create_order(_cells([Vector3i(47,21,40)]),-1,false,"log_horizontal","")==-1,"a log plan needs a wood")
	for tick in range(2000):
		await _tick()
		if construction.orders.is_empty(): break
	var built: Array = cells.map(_key_at)
	_expect(built.all(func(key: String) -> bool: return key=="base:construction:log:pine:x"),"each block is a pine log lying along x: %s" % [built])
	_expect(_loose_of(OAK)==1,"the oak log is left alone")
	var zone_id: int = mine._create_zone(_cells([cells[0]]))
	_expect(mine.execute_zone_block_mined(zone_id,cells[0],worker.dwarf_id),"a log mines like terrain")
	_expect(_key_at(cells[0])==String(blocks.get_key(blocks.AIR_ID)) and _loose_of(PINE)==1,"mining a log gives its log back")
	await process_frame

func _soil_test() -> void:
	var dirt := Vector3i(48,21,40)
	var id: int = construction.create_order(_cells([dirt]),-1,false,"dirt")
	_expect(construction.orders[id].materials.filter_items==[SOIL],"dirt costs soil")
	construction.dev_build_order(id)
	_expect(_key_at(dirt)=="base:terrain:surface:dirt","a dirt block is the world's dirt")
	var open := Vector3i(50,21,40)
	_expect(construction.build_reason(open,true,false,"grass").is_empty(),"grass can be planned under open sky")
	world.set_block(50,25,40,blocks.get_id("base:terrain:rock:rock01"))
	_expect(construction.build_reason(open,true,false,"grass")=="Grass needs open sky above","grass refuses a cell under a roof")
	_expect(construction.build_reason(open,true,false,"dirt").is_empty(),"dirt does not need the sky")
	world.set_block(50,25,40,blocks.AIR_ID)
	_expect(construction.build_reason(open,true,false,"grass").is_empty(),"the sky opens again once the roof goes")
	id = construction.create_order(_cells([open]),-1,false,"grass")
	_expect(construction.orders[id].materials.filter_items==[SOIL],"grass costs soil")
	construction.dev_build_order(id)
	_expect(_key_at(open)=="base:terrain:surface:grass","a grass block is the world's grass")

func _tool_test() -> void:
	construction._on_tool_requested("construct_build")
	var state: Dictionary = construction.tool_bar_state()
	_expect(state.tool=="construct_build" and state.choices.size()==1 and state.choices[0].options.size()==4 and state.choices[0].value=="stone",
		"Build opens on stone, with four materials to choose from")
	var options := {}
	for option: Dictionary in state.choices[0].options: options[option.id] = option
	_expect(options.stone.menu.size()==1 and options.stone.menu[0].options.size()==1 and options.stone.menu[0].options[0].label=="Native stone"
		and not options.dirt.has("menu") and options.wood.menu.size()==2 and options.wood.menu[0].options.size()==2 and options.wood.menu[1].options.size()==4,
		"Stone's menu holds native stone; Wood's its two logs, then the four woods")
	var key := InputEventKey.new()
	key.keycode = KEY_E
	key.pressed = true
	construction._unhandled_input(key)
	_expect(construction._material=="dirt" and construction._kind=="dirt","E steps to the next material")
	key.keycode = KEY_Q
	construction._unhandled_input(key)
	construction._unhandled_input(key)
	_expect(construction._material=="wood" and construction._kind=="log_upright","Q steps back, round to the last: wood, on its first log")
	construction.set_tool_setting("type","log_horizontal")
	construction.set_tool_setting("wood","juniper")
	_expect(String(construction._cost(3).detail).begins_with("3 juniper logs · ") and String(construction._cost(1).detail).begins_with("1 juniper log · "),
		"the tag counts the chosen wood's logs: %s" % construction._cost(3).detail)
	var wood: Dictionary = construction.tool_bar_state().choices[0].options[3]
	_expect(String(wood.label)=="Wood" and String(wood.tooltip).begins_with("Horizontal juniper log. ") and String(wood.tooltip).ends_with("Click it for the Wood menu."),
		"Wood's card is named Wood, then names the chosen log and wood: %s · %s" % [wood.label, wood.tooltip])
	# Which way a lying log points: along a drag's longer side, else the way R sets.
	var a := Vector3i(60,21,40)
	var single := _cells([a])
	_expect(construction._directions(single,a,a)[a]=="x","a click lays a log along x at first")
	key.keycode = KEY_R
	construction._unhandled_input(key)
	_expect(construction._directions(single,a,a)[a]=="z","R turns it")
	var row := _cells([a,a+Vector3i(1,0,0),a+Vector3i(2,0,0)])
	_expect(construction._directions(row,a,a+Vector3i(2,0,1)).values().all(func(way: String) -> bool: return way=="x"),"a drag lays logs along its longer side")
	construction.set_tool_setting("type","log_upright")
	_expect(construction._directions(row,a,a+Vector3i(2,0,1)).values().all(func(way: String) -> bool: return way=="up"),"upright logs stand")
	construction.set_tool_setting("material","grass")
	_expect(not construction.tool_bar_state().has("settings"),"grass is one block tall, so Build hides the height")
	construction._on_tool_requested("construct_build")
	_expect(not construction.is_active(),"Build again ends the tool")
	construction._on_tool_requested("construct_build")
	_expect(construction.is_active() and construction._kind=="grass","Build reopens on its last material")
	construction.set_tool_setting("material","wood")
	_expect(construction._kind=="log_upright" and construction._wood=="juniper","Wood keeps the log and the wood last picked")
	construction.deactivate()

func _log_save_test() -> void:
	var cells := _cells([Vector3i(44,21,43),Vector3i(45,21,43)])
	var id: int = construction.create_order(cells,-1,false,"log_horizontal","oak",{cells[0]:"z",cells[1]:"x"})
	construction.orders[id].materials.staged = {OAK: {"": 2}}
	var saved: Dictionary = JSON.parse_string(JSON.stringify(construction.serialize_state()))
	construction.restore_state(saved)
	var order = construction.orders[id]
	_expect(order.wood=="oak" and order.directions[cells[0]]=="z" and order.directions[cells[1]]=="x" and order.materials.count()==2,
		"a log plan keeps its wood, its directions and its crate through a save")
	_expect(int(construction.staged_inventory()[OAK][""])==2,"staged logs count in the colony's stock")
	_expect(construction.dev_build_order(id)==2,"both logs finish from the staged logs")
	_expect(_key_at(cells[0])=="base:construction:log:oak:z" and _key_at(cells[1])=="base:construction:log:oak:x","each log lies its own way")
