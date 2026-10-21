extends "res://scripts/tests/JuniperHarvestTest.gd"

const APPLE := "base:resources:flora:apple"

func _run() -> void:
	create_timer(90).timeout.connect(func(): push_error("Apple harvest timed out"); quit(1))
	_setup_fixture()
	root.get_node("StockpileManager").set_process(false)
	if "--capture" in OS.get_cmdline_user_args():
		capture_output="res://tmp/apple_harvest_20261019/native/"
		DirAccess.make_dir_recursive_absolute(capture_output)
		_capture_environment()
	_season("summer")
	_spawn_tree("apple","mature",MATURE)
	_spawn_tree("apple","ancient",ANCIENT)
	_spawn_tree("apple","sapling",Vector2i(64,40))
	_spawn_tree("oak","mature",Vector2i(72,40))
	_expect(not flora.designate_harvest(MATURE),"summer apples cannot be gathered")
	_expect(flora.get_explorer_data(MATURE).rows[1][1]=="Out of season","summer fruit status is accurate")
	_season("autumn")
	_expect(not flora.designate_harvest(Vector2i(64,40)) and not flora.designate_harvest(Vector2i(72,40)),"saplings and non-fruit trees excluded")
	var data: Dictionary=flora.get_explorer_data(MATURE)
	_expect(data.rows[1][1]=="Ready to harvest" and data.actions.any(func(a): return a.id=="harvest" and a.text=="Gather apples"),"ripe apple inspector offers Gather apples")
	_expect("4–6 apples" in data.details and "berries" not in data.details,"apple yield description is species-specific")
	_expect("_autumn_fruiting" in String(flora._trees[MATURE].model_path),"ripe tree displays fruit")
	worker=_worker(402,Vector3i(39,20,40))
	explorer.select_object(flora,MATURE)
	if "--capture" in OS.get_cmdline_user_args(): await _capture_juniper("ready")
	explorer._perform_action("harvest")
	var source=flora._felling_sources[MATURE]
	var lease: int=source.lease_id
	flora.designate_harvest(MATURE)
	_expect(source.task_type==Task.Type.HARVEST_TREE and source.duration==4 and source.lease_id==lease,"single harvest lease with authored duration")
	_expect(not flora.designate_felling(MATURE),"active gathering cannot be silently replaced by felling")
	_expect(await _until_working(),"real worker walks to the apple tree")
	var inspection=load("res://scripts/components/DwarfInspection.gd")
	_expect(inspection.describe(worker).activity=="Harvesting apples" and inspection.roster_state(worker).summary=="Harvesting apples","worker inspector and roster name apples")
	_expect(not is_instance_valid(worker._felling_pose.axe) or not worker._felling_pose.axe.visible,"apple gathering uses hands")
	worker._process(.5)
	var partial: float=source.state.work_seconds
	clock_node.set_paused(true)
	worker._process(10)
	_expect(source.state.work_seconds==partial,"paused gathering preserves work")
	clock_node.set_paused(false)
	worker.dev_force_interrupt()
	_expect(source.reserved_by<0 and source.state.work_seconds==partial,"interruption preserves work and releases worker")
	var crop: int=flora._tree_fruit_yield(MATURE)
	var saved: Dictionary=JSON.parse_string(JSON.stringify(flora.serialize_state()))
	flora.restore_state(saved)
	_expect(JSON.parse_string(JSON.stringify(flora.serialize_state()))==saved and flora._tree_fruit_yield(MATURE)==crop,"partial picking and deterministic crop survive save/restore")
	_expect(await _until_working(),"restored picking resumes")
	if "--capture" in OS.get_cmdline_user_args(): await _capture_juniper("picking")
	var body: Node3D=flora._trees[MATURE].node
	var occupancy: int=flora._trees[MATURE].occupancy_id
	source=flora._felling_sources[MATURE]
	_expect(await _until_harvested(MATURE),"mature apple crop completes")
	_expect(_berries()>=4 and _berries()<=6 and _berries()==crop,"mature yield uses documented 4–6 range")
	_expect(flora._trees[MATURE].node==body and flora._trees[MATURE].occupancy_id==occupancy and not flora._tree_changes[MATURE].felled,"tree, trunk collision and occupancy survive picking")
	_expect("_autumn_fruiting" not in String(flora._trees[MATURE].model_path),"picked tree loses visible apples")
	_expect(flora.get_explorer_data(MATURE).rows[1][1]=="Picked this season","inspector records completed crop")
	_expect(not flora.designate_harvest(MATURE) and not source.advance_work(worker.dwarf_id,100),"repeat and stale completions cannot duplicate apples")
	if "--capture" in OS.get_cmdline_user_args(): await _capture_juniper("picked")
	await _eat_harvested_apple()
	saved=JSON.parse_string(JSON.stringify(flora.serialize_state()))
	flora._despawn_column(Vector2i(2,2))
	flora.restore_state(saved)
	_spawn_tree("apple","mature",MATURE)
	_expect(not flora.can_harvest_tree(MATURE) and "_autumn_fruiting" not in String(flora._trees[MATURE].model_path),"reload/streaming does not renew the crop or its fruit visual")
	flora.designate_harvest(ANCIENT)
	worker.position=Vector3(51.5,21,40.5)
	_expect(await _until_working(),"ancient tree has a reachable perimeter")
	_expect(flora._felling_sources[ANCIENT].duration==6,"ancient picking uses authored six seconds")
	worker._process(.7)
	_season("winter")
	_expect(worker.current_task_id<0 and not flora._felling_sources.has(ANCIENT),"season end releases the harvest safely")
	_season("autumn",2)
	_expect(flora.can_harvest_tree(MATURE) and "_autumn_fruiting" in String(flora._trees[MATURE].model_path),"next autumn renews mature crop and visual")
	flora.designate_harvest(ANCIENT)
	_expect(flora._tree_changes[ANCIENT].work_seconds==0,"new crop starts fresh work")
	var before:=_berries()
	_expect(await _until_harvested(ANCIENT),"ancient crop completes")
	_expect(_berries()-before>=7 and _berries()-before<=10,"ancient yield uses documented 7–10 range")
	await _apple_orders()
	flora.designate_felling(MATURE)
	worker.position=Vector3(39.5,21,40.5)
	before=_berries()
	_expect(await _until_felled(MATURE),"felling remains a separate explicit action")
	_expect(_berries()==before and _item_count("base:resources:wood:apple_wood")==2,"felling grants wood, never an extra apple crop")
	for message: String in failures: push_error(message)
	print("APPLE_HARVEST_OK" if failures.is_empty() else "APPLE_HARVEST_FAIL: %s" % str(failures))
	quit(0 if failures.is_empty() else 1)

func _berries() -> int:
	var count:=0
	for item: Node3D in drops._loose:
		if drops._loose[item]==APPLE: count+=int(item.get_meta("quantity",1))
	return count

func _eat_harvested_apple() -> void:
	var before:=_berries()
	worker._idle_behavior.cancel()
	worker.stop_walking()
	worker._food.value=.2
	worker._food.retry_hours=0
	for i in 1000:
		worker._process(.05)
		if worker._food.last_meal==APPLE and not worker._food.active(): break
		if i%15==0: await process_frame
	_expect(worker._food.last_meal==APPLE and worker._food.value>.7,"hungry dwarf eats a real freshly gathered apple")
	_expect(_berries()==before-1 and worker._carried_entries.is_empty(),"meal consumes exactly one apple")
	_expect(not flora._tree_changes[MATURE].felled,"feeding the dwarf leaves the tree standing")

func _apple_orders() -> void:
	_season("autumn",3)
	details=load("res://scripts/systems/SurfaceDetailManager.gd").new()
	scene.add_child(details)
	details.set_process(false)
	details._initialized=true
	chop._details=details
	chop.order_created.connect(func(value: Dictionary): receipt=value)
	dock.tool_requested.emit("harvest_plants")
	_aim_above(Vector3(48,21,42))
	await process_frame
	var trunk: Node3D=flora._trees[MATURE].node
	_expect(chop.designate_at_screen(camera.unproject_position(trunk.position+Vector3.UP)),"Harvest plants click accepts ripe apples")
	_expect(chop.order_is_pending(receipt) and chop.undo_order(receipt)==1,"apple order supports Undo")
	chop._dragging=true
	chop._box_select=true
	chop._anchor=Vector3i(38,20,38)
	chop._finish_drag(camera.unproject_position(Vector3(60,21.02,47)))
	_expect(receipt.get("trees",[]).size()==2 and chop.order_is_pending(receipt),"Harvest plants rectangle includes both adult apple trees")
	_expect(chop.undo_order(receipt)==2,"Undo cancels both apple orders")
	chop.deactivate()
