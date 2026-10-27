extends "res://scripts/tests/FurnitureMoveTest.gd"

const FLAG := "base:furniture:settlement_flag"
const FLAG_ITEM := "base:items:special:settlement_flag"
const THIRD := Vector3i(48,20,49)
const OUT := "res://tmp/settlement_flag_move_20261012/"
var flag_controller
var founder

class FoundingProbe extends Node:
	var settlement_anchor := Vector3i(-1,-1,-1)
	var squads := 0
	func set_settlement_anchor(cell: Vector3i) -> void: settlement_anchor=cell
	func spawn_squad_at(_x: int, _z: int) -> int: squads+=1; return 1

func _run() -> void:
	create_timer(90).timeout.connect(func(): push_error("Settlement flag Move timed out"); quit(1))
	await _setup_crafting_fixture()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	founder=FoundingProbe.new(); founder.name="Founder"; scene.add_child(founder)
	flag_controller=load("res://scripts/systems/FlagPlacementController.gd").new()
	flag_controller.dock_ui_path=NodePath("../Dock")
	flag_controller.dwarf_director_path=NodePath("../Founder")
	scene.add_child(flag_controller)
	explorer=load("res://scripts/ui/ObjectExplorerController.gd").new()
	explorer.window_manager_path=NodePath("../Windows")
	scene.add_child(explorer)
	flag_controller._place_flag(FROM)
	var piece = _at(FROM)
	_expect(piece!=null and piece.furniture_key==FLAG and founder.squads==1,"founding creates one normal furniture flag and one starting squad")
	_expect(founder.settlement_anchor==FROM,"initial flag records colony anchor")
	dock._toggle_window("flag")
	_expect(explorer.is_object_selected(furniture, "installed:%d" % piece.installed_id) and not flag_controller.is_active(), "Colony flag entry inspects the founded flag without arming founding")
	for y in range(1,4): _expect(root.get_node("PlacedEntityRegistry").occupies(FROM+Vector3i(0,y,0)),"flag keeps full three-block occupancy")
	_aim_above(piece.node.position)
	camera.position=piece.node.position+Vector3(10,9,14)
	camera.look_at(piece.node.position+Vector3.UP*1.4)
	camera.size=15
	await _frames(3)
	var screen := camera.unproject_position(piece.node.position+Vector3.UP*1.8)
	explorer.clear_selection()
	_click(screen)
	await _frames(3)
	_expect(explorer._provider==furniture and explorer._object_id=="installed:%d" % piece.installed_id,"clicking the banner opens its furniture inspector")
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OUT+"inspector.png")
	var move_button: Button = explorer.get_compact_panel().get_action_button("move")
	_expect(move_button!=null,"flag panel offers Move")
	if move_button!=null: _click(move_button.get_global_rect().get_center())
	_expect(furniture.is_active() and not piece.flagged_uninstall,"Move starts the normal preview")
	furniture.deactivate()
	# The standard furniture slice and terrain occlusion rules apply to the flag.
	furniture._on_slice_changed(19)
	_expect(furniture.pick_explorer_object(Vector3(FROM)+Vector3(.5,30,.5),Vector3(FROM)+Vector3(.5,1,.5)).is_empty(),"slice-hidden flag cannot be selected")
	furniture._on_slice_changed(127)
	explorer.clear_selection()
	for x in range(FROM.x-4,FROM.x+5):
		for z in range(FROM.z-4,FROM.z+5): world.set_block(x,FROM.y+5,z,blocks.get_id("base:terrain:rock:rock01"))
	_expect(not explorer.select_at_screen(screen),"terrain hides the flag from clicks")
	for x in range(FROM.x-4,FROM.x+5):
		for z in range(FROM.z-4,FROM.z+5): world.set_block(x,FROM.y+5,z,blocks.AIR_ID)
	var plan = _plan(piece)
	furniture.cancel_ghost(plan.ghost_id)
	_expect(not piece.flagged_uninstall and founder.settlement_anchor==FROM,"cancelling destination keeps the founded flag")
	plan=_plan(piece)
	_expect(await _phase(worker.TaskPhase.FETCH_TO_GHOST),"worker really packs and carries the flag")
	_expect(_count(FLAG_ITEM)==1 and _at(FROM)==null and founder.settlement_anchor==FROM,"in-transit flag has one physical owner and retains last anchor")
	dock._toggle_window("flag")
	_expect(explorer.is_object_selected(furniture, "ghost:%d" % plan.ghost_id), "Colony flag entry shows its pending move during transport")
	explorer.clear_selection()
	flag_controller._place_flag(THIRD)
	_expect(founder.squads==1 and furniture._installed.is_empty(),"founding cannot grant a second flag while first is packed")
	_expect(await _move_until(func(): return furniture._ghosts.is_empty()),"worker installs the moved flag")
	piece=_at(TO)
	_expect(piece!=null and piece.yaw_steps==1 and founder.settlement_anchor==TO and founder.squads==1,"Move updates anchor and rotation without spawning colonists")
	_expect(not root.get_node("PlacedEntityRegistry").occupies(FROM+Vector3i.UP),"old flag occupancy is released")
	await _save_and_recover(piece)
	for failure in failures: push_error(failure)
	print("SETTLEMENT_FLAG_MOVE_OK: founding once, click/occlusion/slice, worker Move, cancellation, packed stock, current save recovery and anchor" if failures.is_empty() else "SETTLEMENT_FLAG_MOVE_FAIL")
	quit(0 if failures.is_empty() else 1)

func _save_and_recover(piece) -> void:
	var plan = _plan(piece,THIRD,2)
	_expect(await _phase(worker.TaskPhase.FETCH_TO_GHOST),"second Move reaches real cargo state")
	var furniture_state: Dictionary=JSON.parse_string(JSON.stringify(furniture.serialize_state()))
	var flag_state: Dictionary=JSON.parse_string(JSON.stringify(flag_controller.serialize_state()))
	var cargo: Dictionary=worker.serialize_state().carried_items[0]
	worker.force_interrupt()
	furniture.cancel_ghost(plan.ghost_id)
	for node in drops._loose.keys(): drops.take(node); node.queue_free()
	furniture.free()
	furniture=load("res://scripts/systems/FurniturePlacementController.gd").new()
	furniture.dock_ui_path=NodePath("../Dock")
	scene.add_child(furniture); furniture.set_process(false); furniture._process(0)
	crafting.furniture=furniture
	flag_controller.restore_state(flag_state)
	_expect(furniture._installed.is_empty(),"restoring settlement history never creates an extra flag")
	furniture.restore_state(furniture_state)
	drops.restore_loose_item(cargo.item_key,worker.position,0,1,cargo.instance_id,false,cargo.material_id)
	_expect(await _move_until(func(): return furniture._ghosts.is_empty()),"saved cargo resumes its flag destination")
	_expect(_at(THIRD)!=null and founder.settlement_anchor==THIRD and founder.squads==1 and _count(FLAG_ITEM)==0,"current save recovery preserves exactly one flag and no extra squad")
	# Cancellation after packing permits normal Place, even though founding stays closed.
	plan=_plan(_at(THIRD),FROM,0)
	_expect(await _phase(worker.TaskPhase.FETCH_TO_GHOST),"third Move carries the flag")
	furniture.cancel_ghost(plan.ghost_id)
	_expect(_count(FLAG_ITEM)==1 and furniture.get_catalog_stock()[FLAG].available==1,"cancelled flag is available in ordinary Place stock")
	furniture.activate_for(FLAG,true); furniture._hover_cell=FROM; furniture._confirm_ghost(); furniture.deactivate()
	_expect(await _move_until(func(): return furniture._ghosts.is_empty()),"normal placement recovers cancelled flag")
	_expect(_at(FROM)!=null and founder.settlement_anchor==FROM and founder.squads==1,"ordinary placement also updates anchor without founding again")
	var installed = _at(FROM)
	furniture.perform_explorer_action("installed:%d" % installed.installed_id,"uninstall")
	_expect(await _move_until(func(): return furniture._installed.is_empty()),"ordinary Uninstall packs the flag for storage")
	_expect(_count(FLAG_ITEM)==1 and flag_controller.serialize_state().founded and founder.squads==1,"uninstall preserves the founded colony and one recoverable flag")
	dock._toggle_window("flag")
	_expect(manager.is_open("place") and dock._place_catalog.selected_key == FLAG, "Colony flag entry opens the packed flag's existing Place flow")
	_expect(founder.squads == 1 and not flag_controller.is_active(), "packed navigation never grants another founding flag or squad")
