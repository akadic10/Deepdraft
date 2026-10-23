extends "res://scripts/tests/WorkerCraftingTest.gd"

const FROM := Vector3i(44,20,40)
const TO := Vector3i(53,20,44)
const JUNIPER := "base:material:juniper"
const BED := "base:furniture:log_bed"

func _run() -> void:
	create_timer(120).timeout.connect(func(): push_error("Furniture Move timed out"); quit(1))
	await _setup_crafting_fixture()
	explorer = load("res://scripts/ui/ObjectExplorerController.gd").new()
	explorer.window_manager_path = NodePath("../Windows")
	scene.add_child(explorer)
	var piece = _install_piece(BENCH)
	_expect(explorer.select_object(furniture,"installed:%d" % piece.installed_id),"workbench inspection opens")
	await _frames(4)
	var move_button: Button
	for button in explorer._actions.get_children():
		if button.text=="Move": move_button=button
	_expect(move_button!=null,"real inspector offers Move for the workbench")
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tmp/furniture_move_20261012/workbench.png")
	if move_button!=null: _click(move_button.get_global_rect().get_center())
	_expect(furniture.is_active() and not piece.flagged_uninstall and furniture._ghosts.is_empty(),"Move starts preview without touching the source")
	var escape:=InputEventKey.new(); escape.keycode=KEY_ESCAPE; escape.pressed=true
	furniture._unhandled_input(escape)
	_expect(not furniture.is_active() and not piece.flagged_uninstall,"Escape leaves the installed piece alone")
	var plan = _plan(piece)
	_expect(piece.flagged_uninstall and not plan.required_instance_id.is_empty(),"confirmed destination posts exact-piece relocation")
	if "--capture" in OS.get_cmdline_user_args():
		explorer.select_object(furniture,"ghost:%d" % plan.ghost_id)
		await _frames(6)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tmp/furniture_move_20261012/pending.png")
	furniture.perform_explorer_action("installed:%d" % piece.installed_id,"cancel_move")
	_expect(not piece.flagged_uninstall and furniture._ghosts.is_empty() and furniture._moves.records.is_empty(),"cancel before packing keeps the original and releases the plan")
	# A spare of the same design and material must never satisfy this Move.
	drops.restore_loose_item(BENCH_ITEM,Vector3(52.5,21,43.5),0,1,"",false,JUNIPER)
	plan = _plan(piece)
	plan.update_lease()
	_expect(not plan.has_lease(),"spare matching furniture cannot substitute for the chosen piece")
	var plan_id: int=plan.ghost_id
	_expect(await _move_until(func(): return not furniture._installed.has(piece.installed_id)),"worker packs selected workbench")
	_expect(plan.continuation_worker==worker.dwarf_id,"packer is preferred for the carrying stage")
	_expect(await _move_until(func(): return not furniture._ghosts.has(plan_id)),"worker carries and installs selected workbench")
	var relocated = _at(TO)
	_expect(relocated!=null and relocated.material_id==JUNIPER and relocated.yaw_steps==1,"destination preserves material and chosen rotation")
	_expect(_count(BENCH_ITEM)==1 and furniture._installed.size()==1 and furniture._moves.records.is_empty(),"Move leaves one installed piece and the untouched spare")
	await _interruption_and_save()
	await _blocked_destination()
	await _settings_and_crafting()
	await _wall_move()
	for failure in failures: push_error(failure)
	print("FURNITURE_MOVE_OK: inspector, preview, exact item, worker transport, interruption, cancellation, settings, crafting, wall mounts and saves" if failures.is_empty() else "FURNITURE_MOVE_FAIL")
	quit(0 if failures.is_empty() else 1)

func _install_piece(key: String, origin := FROM):
	var id: int=furniture._next_installed_id
	furniture._install(key,furniture.get_defs()[key],origin,0,JUNIPER)
	return furniture._installed[id]

func _plan(piece, target := TO, yaw := 1):
	furniture.begin_furniture_move(piece.installed_id)
	furniture._yaw=yaw
	furniture._hover_cell=target
	_expect(furniture._placement_valid(target),"Move destination is valid: "+piece.furniture_key)
	var id: int=furniture._next_ghost_id
	furniture._confirm_ghost()
	return furniture._ghosts.get(id)

func _at(cell: Vector3i):
	for piece in furniture._installed.values():
		if piece.origin_cell==cell: return piece
	return null

func _move_until(condition: Callable) -> bool:
	for i in 1000:
		if condition.call(): return true
		await _tick()
	return false

func _clean() -> void:
	explorer.clear_selection()
	for id in furniture._ghosts.keys(): furniture.cancel_ghost(id)
	for id in furniture._installed.keys(): furniture.dev_remove_installed(id)
	for node in drops._loose.keys(): drops.take(node); node.queue_free()
	worker.force_interrupt()
	worker._idle_behavior.cancel(); worker.stop_walking()
	worker.position=Vector3(40.5,21,39.5)
	worker.sleep=1; worker._food.value=1
	await _frames(2)

func _interruption_and_save() -> void:
	await _clean()
	var piece = _install_piece(BENCH)
	var plan = _plan(piece)
	var move_id: String=plan.required_instance_id
	var saved: Dictionary=JSON.parse_string(JSON.stringify(furniture.serialize_state()))
	_expect(saved.moves.records[move_id].installed_id==piece.installed_id and saved.ghosts[0].move_id==move_id,"pending Move saves both source and exact destination")
	# Recreate the actual owner; its claims are restored before loose/carry goods.
	furniture.cancel_ghost(plan.ghost_id)
	furniture.dev_remove_installed(piece.installed_id)
	for node in drops._loose.keys(): drops.take(node); node.queue_free()
	furniture.free()
	furniture=load("res://scripts/systems/FurniturePlacementController.gd").new()
	scene.add_child(furniture); furniture.set_process(false); furniture._process(0)
	furniture.restore_state(saved)
	crafting.furniture=furniture
	plan=furniture._ghosts.values()[0]
	_expect(await _phase(worker.TaskPhase.FETCH_TO_GHOST),"restored move resumes and physically carries its item")
	var cargo: Node3D=worker._work_execution._fetch_item
	_expect(String(cargo.get_meta("instance_id",""))==move_id,"carrier holds the exact identified furniture")
	var mid: Dictionary=JSON.parse_string(JSON.stringify(furniture.serialize_state()))
	var actor: Dictionary=worker.serialize_state()
	_expect(mid.moves.records[move_id].installed_id==-1 and actor.carried_items[0].instance_id==move_id,"in-flight save has no old installed copy and keeps cargo identity")
	worker.force_interrupt()
	_expect(drops.instance_promised(move_id) and _count(BENCH_ITEM)==1,"worker interruption preserves and protects the packed piece")
	_expect(await _phase(worker.TaskPhase.FETCH_TO_GHOST),"another attempt picks up the same protected piece")
	furniture.cancel_ghost(plan.ghost_id)
	_expect(not drops.instance_promised(move_id) and _count(BENCH_ITEM)==1 and worker._work_execution._fetch_item==null,"cancel while carrying safely drops intact furniture for ordinary storage")
	# Ordinary placement of the cancelled packed item still consumes its record.
	furniture.activate_for(BENCH,true); furniture._hover_cell=TO; furniture._confirm_ghost(); furniture.deactivate()
	_expect(await _move_until(func(): return furniture._ghosts.is_empty()),"cancelled packed furniture can be placed normally")
	_expect(_at(TO)!=null and furniture._moves.records.is_empty(),"ordinary placement retires recovered identity")

func _blocked_destination() -> void:
	await _clean()
	var piece = _install_piece(BENCH)
	var plan = _plan(piece)
	_expect(await _phase(worker.TaskPhase.FETCH_TO_GHOST),"worker carries before destination changes")
	world.set_block(TO.x,TO.y+1,TO.z,blocks.get_id("base:terrain:rock:rock01"))
	for i in 100: await _tick()
	_expect(furniture._ghosts.has(plan.ghost_id) and _at(TO)==null and _count(BENCH_ITEM)==1,"blocked destination keeps plan and exact item without consuming it")
	world.set_block(TO.x,TO.y+1,TO.z,0)
	_expect(await _move_until(func(): return furniture._ghosts.is_empty()),"cleared destination allows Move to resume")
	_expect(_at(TO)!=null and _count(BENCH_ITEM)==0,"resumed Move installs exactly once")

func _settings_and_crafting() -> void:
	await _clean()
	var bed = _install_piece(BED)
	_expect(furniture.assign_bed(bed.installed_id,worker.dwarf_id),"bed owner assigned")
	_plan(bed)
	_expect(await _move_until(func(): return furniture._ghosts.is_empty()),"assigned bed moves")
	_expect(_at(TO)!=null and _at(TO).assigned_dwarf_id==worker.dwarf_id,"moved bed retains its owner")
	await _clean()
	var bench = _install_piece(BENCH)
	drops.spawn_drop(PINE,1,Vector3i(42,21,39))
	var order: int=crafting.queue_order(TORCH_RECIPE,1)
	_expect(await _phase(worker.TaskPhase.FETCH_WORKING),"worker crafts at the selected station")
	_plan(bench)
	_expect(await _move_until(func(): return furniture._ghosts.is_empty()),"busy station relocates after safely releasing crafting")
	_expect(await _completed(order) and _count(TORCH_ITEM)==4 and _count(PINE)==0,"same craft order resumes with one four-torch batch and no lost ingredients")

func _wall_move() -> void:
	await _clean()
	var key: String=TORCH
	var definition: Dictionary=furniture.get_defs()[key]
	var mount=load("res://scripts/components/WallFurnitureMount.gd")
	for origin in [FROM,TO]:
		for cell: Vector3i in mount.supports(definition,origin,0):
			world.set_block(cell.x,cell.y,cell.z,blocks.get_id("base:terrain:rock:rock01"))
	await _frames(2)
	var torch = _install_piece(key)
	_plan(torch,TO,0)
	_expect(await _move_until(func(): return furniture._ghosts.is_empty()),"wall light uses real removal and installation reach")
	_expect(_at(TO)!=null and _at(TO).material_id==JUNIPER,"wall light retains material at new mount")
