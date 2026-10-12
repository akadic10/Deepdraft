extends "res://scripts/tests/LogBridgeTest.gd"

const OUTPUT := "res://tmp/bridge_placement_20261011/"

func _run() -> void:
	create_timer(90).timeout.connect(func(): push_error("Bridge input test timed out"); quit(1))
	await _setup_crafting_fixture()
	bridges = furniture._bridges
	bridges.set_process(false)
	furniture._ladders.set_process(false)
	nav = root.get_node("NavGrid")
	await _river()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	drops.spawn_drop(KIT,1,Vector3i(41,21,45))
	camera.position = Vector3(60,29,64)
	camera.look_at(Vector3(46,20,48))
	camera.size = 20
	await _frames(4)
	# Existing bridge tests injected bank coordinates/yaw, bypassing picking.
	# These points enter the actual terrain DDA and mouse-click dispatch.
	for point: Vector3 in [Vector3(43.5,21.001,48.5),Vector3(44.001,19.2,48.5),Vector3(46.5,19.95,48.5),Vector3(49.5,21.001,48.5)]:
		var screen := camera.unproject_position(point)
		var hit: Dictionary = furniture._surface_cell_for(screen)
		_expect(not hit.is_empty(),"test aim hits real terrain: "+str(point))
		if hit.is_empty(): continue
		var raw := Vector3i(hit.x,hit.y,hit.z)
		print("BRIDGE_PICK: aim=",point," raw=",raw," normal=",hit.normal)
		_expect(not String(bridges.describe(raw,0).reason).is_empty(),"old fixed-direction furniture picking rejects this usable crossing")
		furniture.activate_for(BRIDGE,true)
		furniture._update_hover(true,screen)
		_expect(furniture._hover_valid and furniture._hover_cell.y==20,"top, bank face and water hover all resolve the bank top: "+str(point))
		_expect(bridges.describe(furniture._hover_cell,furniture._yaw).span==5,"preview spans the full river without hand-setting yaw")
		var preview_base: Vector3i = furniture._hover_cell
		var preview_yaw: int = furniture._yaw
		_click(screen)
		await _frames(3)
		_expect(bridges.routes.size()==1,"real mouse click queues exactly one bridge: "+str(point))
		if bridges.routes.is_empty(): continue
		var id: int = bridges.routes.keys()[0]
		_expect(bridges.routes[id].base==preview_base and bridges.routes[id].yaw==preview_yaw,"click keeps the preview's exact bank and rotation")
		_expect(nav.find_path(bank,far_bank).is_empty(),"clicking a plan does not enable an unpaid crossing")
		furniture.cancel_ghost(-1_000_000-id)
		await _frames(3)
		_expect(_count(KIT)==1,"Undo returns the single kit reservation")
	# A vertical view really hits the riverbed instead of the opposite wall.
	var prior_camera: Transform3D = camera.global_transform
	camera.global_position = Vector3(46.5,40,48.5)
	camera.look_at(Vector3(46.5,18,48.5),Vector3.FORWARD)
	await _frames(2)
	var wet_screen := camera.unproject_position(Vector3(46.5,19.95,48.5))
	var bed_hit: Dictionary = furniture._surface_cell_for(wet_screen)
	_expect(bed_hit.get("y",-1)==17,"vertical water picking hits the submerged riverbed")
	furniture.activate_for(BRIDGE,true)
	furniture._update_hover(true,wet_screen)
	_expect(furniture._hover_valid and furniture._hover_cell.y==20,"submerged bed resolves to a nearby dry bank")
	_click(wet_screen)
	await _frames(3)
	_expect(bridges.routes.size()==1,"riverbed mouse click queues the snapped crossing")
	for id: int in bridges.routes.keys(): furniture.cancel_ghost(-1_000_000-id)
	camera.global_transform = prior_camera
	await _frames(3)
	# No snapping around a blocked landing or into a hidden slice.
	var bank_screen := camera.unproject_position(Vector3(43.5,21.001,48.5))
	furniture.activate_for(BRIDGE,true)
	furniture._update_hover(true,bank_screen)
	var obstruction: int = root.get_node("PlacedEntityRegistry").register_box(Vector3i(43,22,47),Vector3i(1,1,3))
	await _frames(2)
	furniture._update_hover(false,bank_screen)
	_expect(not furniture._hover_valid and furniture._hint_label.text.contains("Clear"),"stationary preview rejects a newly blocked landing with a useful reason")
	root.get_node("PlacedEntityRegistry").unregister(obstruction)
	await _frames(2)
	furniture._update_hover(false,bank_screen)
	_expect(furniture._hover_valid,"stationary preview recovers when landing obstruction is removed")
	furniture._slice_y = 20
	furniture._update_hover(true,bank_screen)
	_expect(not furniture._hover_valid,"auto-alignment still respects the slice")
	furniture._slice_y = 127
	furniture._update_hover(true,bank_screen)
	# A rotation preference can choose a direction only where a valid crossing
	# exists; it cannot leave a straight river's preview pointing along the bank.
	furniture._yaw = (furniture._yaw+1)%4
	furniture._update_hover(true,bank_screen)
	_expect(furniture._hover_valid,"rotation preference retains a valid crossing on a straight bank")
	if "--capture" in OS.get_cmdline_user_args():
		dock._open_place_catalog()
		dock._place_catalog.category = "access"
		dock._place_catalog._select(BRIDGE)
		furniture._update_hover(true,bank_screen)
		await _frames(4)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OUTPUT+"auto_aligned.png")
		manager.close("place")
		furniture.activate_for(BRIDGE,true)
	# The preview may anchor on the opposite bank from the workers and kit.
	# Installation must still happen from their reachable end of the crossing.
	var opposite_screen := camera.unproject_position(Vector3(49.5,21.001,49.5))
	furniture._update_hover(true,opposite_screen)
	_expect(furniture._hover_cell.x==far_bank.x,"final preview is anchored on the far bank")
	_click(opposite_screen)
	await _frames(3)
	_expect(bridges.routes.size()==1,"opposite-bank click designates final installation")
	if not bridges.routes.is_empty():
		var id: int = bridges.routes.keys()[0]
		_expect(await _phase(worker.TaskPhase.FETCH_WORKING),"builder delivers the kit from the reachable bank")
		_expect(worker.current_cell().x==bank.x,"builder stays on the colony bank before the deck exists")
		worker._process(.1)
		_expect(absf(wrapf(worker.rotation.y-PI/2,-PI,PI))<.01,"builder faces across the river from the opposite end")
		_expect(await _condition(func(): return bridges.routes[id].built),"Worker collects kit and installs the mouse-designated bridge")
		_expect(_count(KIT)==0 and not nav.find_path(bank,far_bank).is_empty(),"installed bridge consumes one kit and opens the crossing")
	for failure in failures: push_error(failure)
	print("BRIDGE_PLACEMENT_INPUT_OK" if failures.is_empty() else "BRIDGE_PLACEMENT_INPUT_FAIL")
	quit(0 if failures.is_empty() else 1)
