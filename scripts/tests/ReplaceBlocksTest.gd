extends "res://scripts/tests/ConstructionTest.gd"

## Build's Replace (doc 285):
## - Replace takes a solid block with an open face that isn't already what the material builds:
##   rock is already stone; a buried block, air, bedrock's layers, a block marked for mining, a
##   planned block and grass under a roof are refused;
## - a drag over a row plans only the blocks that differ;
## - a builder digs the old block with the pick, then hammers the new one in. The cell is solid
##   the whole time, the copper becomes the layer's rock, one rough stone is spent, and a release
##   mid-dig changes nothing and keeps the progress;
## - a replaced log gives its log back at the builder's feet;
## - a block mined out or made to match leaves its plan;
## - a replace plan saves with its progress;
## - Build's Replace switch, its F key and its name, and the block panel's list and action.
const SOIL := "base:resources:soil:soil"
const PINE := "base:resources:wood:pine_log"
const COPPER := "base:terrain:ore:copper"

func _run() -> void:
	create_timer(120).timeout.connect(func(): push_error("Replace blocks test timed out"); quit(1))
	await _setup_fixture()
	await _new_trip(STONE,4)
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
	_rules_test()
	await _swap_test()
	await _log_test()
	await _sweep_test()
	_save_replace_test()
	_tool_test()
	_panel_test()
	_expect(tasks.lifecycle_errors().is_empty(),"replacing leaves no orphan tasks or claims")
	for failure: String in failures: push_error(failure)
	print("REPLACE_BLOCKS_OK" if failures.is_empty() else "REPLACE_BLOCKS_FAIL")
	quit(0 if failures.is_empty() else 1)

func _key_at(cell: Vector3i) -> String:
	return String(blocks.get_key(world.get_terrain_block(cell.x,cell.y,cell.z)))

func _put(cell: Vector3i, key: String) -> void:
	world.set_block(cell.x,cell.y,cell.z,blocks.get_id(key) if not key.is_empty() else blocks.AIR_ID)

func _loose_of(key: String) -> Array:
	return drops._loose.keys().filter(func(item: Node3D) -> bool: return String(drops._loose[item]) == key)

func _rules_test() -> void:
	var copper := Vector3i(44,20,40)
	_put(copper,COPPER)
	_expect(construction.replace_reason(copper,"stone").is_empty(),"a copper floor block can become stone")
	_expect(construction.replace_reason(Vector3i(45,20,40),"stone")=="Already native stone","rock is already stone")
	_expect(construction.replace_reason(Vector3i(45,20,40),"dirt").is_empty(),"rock can become dirt")
	_expect(construction.replace_reason(Vector3i(44,19,40),"dirt")=="Only a block with an open face can be replaced","a buried block is out of reach")
	_expect(construction.replace_reason(Vector3i(44,21,40),"stone")=="Nothing here to replace","air has nothing to replace")
	_expect(construction.replace_reason(Vector3i(44,3,40),"dirt")=="Outside the buildable world","bedrock's layers stay")
	_put(Vector3i(44,25,40),"base:terrain:rock:rock01")
	_expect(construction.replace_reason(copper,"grass")=="Grass needs open sky above","grass needs open sky")
	_put(Vector3i(44,25,40),"")
	_expect(construction.replace_reason(copper,"grass").is_empty(),"grass can take a block under open sky")
	var zone_id: int = mine._create_zone(_cells([copper]))
	_expect(construction.replace_reason(copper,"stone")=="Marked for mining","a block marked for mining is left to the miners")
	mine._remove_zone(zone_id)
	_expect(construction.replace_reason(copper,"stone").is_empty(),"unmarked, it can be replaced again")
	var dirt := Vector3i(46,20,40)
	_put(dirt,"base:terrain:surface:dirt")
	var row := _cells([Vector3i(43,20,40),copper,Vector3i(45,20,40),dirt,Vector3i(47,20,40)])
	var id: int = construction.create_order(row,-1,false,"stone","",{},{},"",true)
	_expect(id>0 and construction.orders[id].cells==_cells([copper,dirt]),"a row of stone plans only the copper and the dirt")
	if id>0:
		_expect(construction.orders[id].title()=="Replace with native stone","the plan is named for what goes in")
		_expect(construction.replace_reason(copper,"dirt")=="Construction already planned here","a planned block is not planned twice")
		construction.cancel_order(id)
	_put(dirt,"base:terrain:rock:rock01")

func _swap_test() -> void:
	var copper := Vector3i(44,20,40)
	var stone_before := _stone_units()
	var id: int = construction.create_order(_cells([copper]),-1,false,"stone","",{},{},"",true)
	var order = construction.orders[id]
	var opened := false
	var dug := false
	var hammered := false
	var released := false
	for tick in range(3000):
		await _tick()
		if not blocks.is_solid(world.get_live_block(copper.x,copper.y,copper.z)): opened = true
		var working: bool = worker.get_task_phase()==worker.TaskPhase.FETCH_WORKING and order.builder_id==worker.dwarf_id
		if working and order.digging():
			dug = dug or (worker._mining_pose.pickaxe != null and worker._mining_pose.pickaxe.visible and _key_at(copper)==COPPER)
			if not released and order.progress>0:
				# A release mid-dig changes nothing and keeps the dig's progress (Hard Rule 12).
				var progress: float = order.work_progress.get(copper,0.0)
				tasks.cancel_source_tasks(order.source_id)
				_expect(_key_at(copper)==COPPER and order.materials.count()==1,"a release mid-dig leaves the copper and the stone")
				_expect(is_equal_approx(float(order.work_progress.get(copper,0.0)),progress) and progress>0,"the dig's progress is kept")
				released = true
		elif working:
			hammered = hammered or (worker._construction_pose.tool != null and worker._construction_pose.tool.visible
				and not worker._mining_pose.pickaxe.visible)
		if not construction.orders.has(id): break
	_expect(released and not construction.orders.has(id),"the builder comes back and finishes the replacement")
	_expect(not opened,"the cell is never open")
	_expect(world.get_terrain_block(copper.x,copper.y,copper.z)==root.get_node("WorldGenerator").construction_stone_id(copper),"the copper is now the layer's rock")
	_expect(dug and hammered,"the pick digs the copper out, then the hammer sets the stone in")
	_expect(_stone_units()==stone_before-1,"one rough stone is spent")
	_expect(nav.is_walkable(copper),"the floor stays walkable")

## Rough stone loose or stored, carried, or in a crate.
func _stone_units() -> int:
	var total := 0
	for entry: Dictionary in drops.serialize_state().loose:
		if String(entry.item_key)==STONE: total += int(entry.count)
	for entry in worker.serialize_state().carried_items:
		if String(entry.item_key)==STONE: total += int(entry.count)
	for order in construction.orders.values(): total += order.materials.staged_count(STONE)
	return total

func _log_test() -> void:
	var log_cell := Vector3i(46,21,42)
	_put(log_cell,"base:construction:log:pine:up")
	drops.spawn_drop(SOIL,1,Vector3i(41,21,41))
	var id: int = construction.create_order(_cells([log_cell]),-1,false,"dirt","",{},{},"",true)
	_expect(id>0,"a log can become dirt")
	for tick in range(3000):
		await _tick()
		if not construction.orders.has(id): break
	_expect(_key_at(log_cell)=="base:terrain:surface:dirt","the log is now dirt")
	var logs := _loose_of(PINE)
	_expect(logs.size()==1 and drops.item_floor_cell(logs[0]) in construction.stands_for(log_cell),
		"the pine log comes back at the builder's feet: %s" % [logs.map(func(item: Node3D) -> Vector3i: return drops.item_floor_cell(item))])

func _sweep_test() -> void:
	var a := Vector3i(48,20,46)
	var b := Vector3i(49,20,46)
	_put(a,COPPER)
	_put(b,COPPER)
	# No soil in stock: the plan waits, and the world changes under it.
	var id: int = construction.create_order(_cells([a,b]),-1,false,"dirt","",{},{},"",true)
	_put(a,"")
	await _tick()
	_expect(construction.orders.has(id) and construction.orders[id].cells==_cells([b]),"a block mined out leaves the plan")
	_put(b,"base:terrain:surface:dirt")
	await _tick()
	_expect(not construction.orders.has(id),"a block made to match leaves it too, and the empty plan goes")
	_put(a,"base:terrain:rock:rock01")
	_put(b,"base:terrain:rock:rock01")

func _save_replace_test() -> void:
	var cell := Vector3i(50,20,40)
	_put(cell,COPPER)
	var id: int = construction.create_order(_cells([cell]),-1,false,"stone","",{},{},"",true)
	construction.orders[id].work_progress[cell] = .5
	var saved: Dictionary = JSON.parse_string(JSON.stringify(construction.serialize_state()))
	construction.restore_state(saved)
	var order = construction.orders.get(id)
	_expect(order != null and order.replace and order.cells==_cells([cell]) and is_equal_approx(float(order.work_progress[cell]),.5),
		"a replace plan keeps its block and its progress through a save")
	if order != null: _expect(order.work_seconds_of(cell)>float(order.def.work_seconds),"its block's dig adds to the hammering")
	construction.cancel_order(id)

func _tool_test() -> void:
	construction._on_tool_requested("construct_build")
	var state: Dictionary = construction.tool_bar_state()
	var toggle: Array = state.get("toggles",[]).filter(func(each: Dictionary) -> bool: return each.id=="replace")
	_expect(toggle.size()==1 and not toggle[0].on and not state.has("name"),"Build opens building, with Replace off")
	var key := InputEventKey.new()
	key.keycode = KEY_F
	key.pressed = true
	construction._unhandled_input(key)
	state = construction.tool_bar_state()
	_expect(construction._replace and state.get("name")=="Replace" and state.get("keys")=="construct_replace","F switches Replace on, and the bar names it")
	construction._unhandled_input(key)
	_expect(not construction._replace,"F again goes back to building")
	construction.set_tool_setting("replace",true)
	construction._on_tool_requested("construct_build")
	construction._on_tool_requested("construct_build")
	_expect(construction.is_active() and not construction._replace,"Build reopens building")
	construction._on_tool_requested("construct_shapes")
	_expect(not construction.tool_bar_state().get("toggles",[]).any(func(each: Dictionary) -> bool: return each.id=="replace"),"Shapes has no Replace")
	construction.deactivate()

func _panel_test() -> void:
	var copper := Vector3i(52,20,40)
	_put(copper,COPPER)
	var ids: Array = construction.replace_options(copper).map(func(option: Dictionary) -> String: return option.id)
	_expect(ids==["replace:stone","replace:dirt","replace:grass","replace:wood"],"the panel offers each material for copper: %s" % [ids])
	ids = construction.replace_options(Vector3i(53,20,40)).map(func(option: Dictionary) -> String: return option.id)
	_expect(not ids.has("replace:stone") and ids.has("replace:dirt"),"rock is not offered stone: %s" % [ids])
	var provider: Node = load("res://scripts/ui/TerrainExplorerProvider.gd").new()
	scene.add_child(provider)
	provider.perform_explorer_action({"x":copper.x,"y":copper.y,"z":copper.z,"normal":Vector3i.UP},"replace:dirt")
	var planned: Array = construction.orders.values().filter(func(order) -> bool: return order.cells.has(copper))
	_expect(planned.size()==1 and planned[0].replace and planned[0].construction_kind=="dirt","the panel's choice plans the block's replacement with dirt")
	for order in planned: construction.cancel_order(order.ghost_id)
	provider.queue_free()
