extends "res://scripts/tests/WorkerCraftingTest.gd"

const BRIDGE := "base:furniture:log_bridge"
const KIT := "base:resources:furniture:log_bridge"
const RECIPE := "base:recipe:worker:log_bridge"
var bridges
var nav
var water
var bank := Vector3i(43,20,48)
var far_bank := Vector3i(49,20,48)

func _run() -> void:
	create_timer(150).timeout.connect(func(): push_error("Log bridge timed out"); quit(1))
	await _setup_crafting_fixture()
	# Terrain edits below the synthetic surface compare against seeded resources.
	root.get_node("WorldGenerator")._build_noise_instances()
	bridges = furniture._bridges
	bridges.set_process(false)
	_expect(dock._place_catalog.has_design(BRIDGE), "Place catalog exposes the bridge under Access")
	furniture._ladders.set_process(false)
	nav = root.get_node("NavGrid")
	await _geometry_checks()
	await _river()
	var baseline: Dictionary = water.flow.mass.duplicate()
	_expect(nav.find_path(bank,far_bank).is_empty(), "water prevents an ordinary crossing")
	var order_id: int = crafting.queue_order(RECIPE,1)
	drops.spawn_drop(PINE,2,Vector3i(40,21,41))
	crafting._refresh()
	_expect(crafting.get_order(order_id).lease_id < 0, "kit recipe requires a workbench")
	crafting.remove_order(order_id)
	order_id = crafting.queue_order(BENCH_RECIPE,1)
	_expect(await _completed(order_id), "Worker crafts the bootstrap bench")
	furniture.activate_for(BENCH,true)
	furniture._hover_cell = Vector3i(39,20,46)
	furniture._confirm_ghost()
	furniture.deactivate()
	_expect(await _installed(BENCH), "Worker installs the workbench")
	order_id = crafting.queue_order(RECIPE,1)
	_expect(await _completed(order_id), "Worker crafts a real bridge kit")
	_expect(_count(KIT)==1 and _count(PINE)==0, "two logs become one bench and one kit")
	var kit: Node3D = drops.nearest_loose_of_key(KIT,bank)
	drops.set_disallowed(kit,true)
	_expect(bridges.place(bank,3)<0, "disallowed kit cannot fund a plan")
	drops.set_disallowed(kit,false)
	var obstruction: int = root.get_node("PlacedEntityRegistry").register_box(Vector3i(46,23,48),Vector3i.ONE)
	_expect(bridges.place(bank,3)<0, "three-block head clearance rejects obstacles above the gap")
	root.get_node("PlacedEntityRegistry").unregister(obstruction)
	furniture.activate_for(BRIDGE,true)
	furniture._yaw = 3
	furniture._hover_cell = bank
	furniture._hover_valid = furniture._placement_valid(bank)
	furniture._position_preview(bank)
	_expect(furniture._hover_valid and furniture._visuals.hint_text.contains("5-block gap"), "preview quotes span and kit from the selected bank")
	if "--capture" in OS.get_cmdline_user_args(): await _bridge_preview_capture()
	furniture._confirm_ghost()
	furniture.deactivate()
	var id: int = bridges._next_id-1
	_expect(bridges.routes.has(id) and furniture.has_pending_placement(-1_000_000-id), "Place queues a cancellable bridge plan")
	_expect(nav.find_path(bank,far_bank).is_empty(), "ghost never grants a crossing")
	_expect(furniture.get_catalog_stock()[BRIDGE].available==0, "one real kit reserved exactly once")
	furniture.cancel_ghost(-1_000_000-id)
	_expect(_count(KIT)==1 and furniture.get_catalog_stock()[BRIDGE].available==1, "Undo releases the kit")
	id = bridges.place(bank,3)
	_expect(await _phase(worker.TaskPhase.FETCH_WORKING), "builder fetches the kit and works on the near bank")
	_expect(worker.current_cell().x==bank.x, "builder never needs an existing crossing")
	worker._process(.5)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(bridges.serialize_state()))
	_expect(saved.routes[0].progress>0 and not saved.routes[0].built, "partial installation saves its work without granting support")
	worker.force_interrupt()
	var source_id: int = bridges.work.get_source(id).source_id
	_expect(tasks._tasks.values().filter(func(task): return task.source_id==source_id).size()==1, "interruption preserves exactly one construction lease")
	bridges.restore_state(saved)
	_expect(_count(KIT)==1, "interruption/load conserves the unconsumed physical kit")
	for task in tasks._tasks.values(): task.retry_at = 0
	_expect(await _condition(func(): return bridges.routes[id].built), "resumed installation completes")
	var open: Dictionary = bridges.get_explorer_data(id)
	_expect(ResourceLoader.exists(String(open.picture)) and open.status.tone == "fine"
		and open.actions.any(func(action): return action.id == "remove"), "compact panel: an open bridge shows its picture, status and Dismantle")
	_expect(_count(KIT)==0 and not nav.find_path(bank,far_bank).is_empty(), "one kit becomes a traversable deck")
	_expect(water.flow.mass==baseline, "bridge construction does not displace, dam or consume water")
	_expect(nav.line_walkable_flat(bank,far_bank), "ordinary path smoothing accepts the completed deck")
	_expect(furniture.blocks_zone_cell(bank), "landings remain reserved against storage zones")
	_expect(not furniture._floor_placement_reason(furniture.get_defs()[BENCH],bank,0).is_empty(), "furniture cannot block a bridge landing")
	var bounds: AABB = bridges.get_explorer_bounds(id)
	var visible_bounds: AABB = load("res://scripts/components/ObjectPicking.gd").world_bounds(bridges.routes[id].node)
	_expect(is_equal_approx(bounds.size.x,7) and is_equal_approx(bounds.size.z,2) and is_equal_approx(visible_bounds.end.y,21), "deck and selection have a 2 by 7 footprint with a flush walking top")
	saved = JSON.parse_string(JSON.stringify(bridges.serialize_state()))
	bridges.restore_state(saved)
	_expect(JSON.parse_string(JSON.stringify(bridges.serialize_state()))==saved and not nav.find_path(far_bank,bank).is_empty(), "installed bridge round trips and restores navigation")
	_expect(bridges.routes[id].material_id == "base:material:pine", "bridge saves and restores crafted wood")
	# Actual hauling across the river uses the normal worker path and cargo.
	zone._cell_set.clear()
	var storage_cells: Array[Vector3i] = [Vector3i(52,20,48)]
	zone.setup(1,storage_cells)
	drops.spawn_drop(STONE,1,Vector3i(41,21,48))
	_expect(await _condition(func(): zone.update_leases(); return zone.stored_count()==1), "worker hauls a real stone over the finished bridge")
	_expect(worker.current_cell().x>=49, "hauler arrives on the opposite bank")
	if "--capture" in OS.get_cmdline_user_args(): await _bridge_capture()
	# An idle occupant must leave before removal; new paths must not enter.
	worker.abort_task()
	worker.position = Vector3(46.5,21,48.5)
	drops.restore_loose_item(PINE,Vector3(46.5,21,49.5),0,1)
	var on_deck: Node3D = drops.nearest_loose_of_key(PINE,bank)
	_expect(is_equal_approx(on_deck.position.y,21), "loose and restored cargo rests on deck support")
	bridges.perform_explorer_action(id,"remove")
	_expect(not bridges._safe_to_remove(bridges.routes[id]), "dismantling waits for occupants")
	_expect(nav.find_path(bank,far_bank).is_empty() and not nav.line_walkable_flat(bank,far_bank), "closing rejects new routes and shortcuts")
	_expect(not nav.find_path(worker.current_cell(),bank).is_empty(), "closing permits escape to land")
	_expect(await _condition(func(): return not worker.needs_bridge_exit() and worker.current_cell().x not in range(44,49)), "idle occupant walks to safety automatically")
	_expect(await _condition(func(): return not bridges.routes.has(id)), "worker dismantles from a bank")
	_expect(_count(KIT)==1 and nav.find_path(bank,far_bank).is_empty(), "dismantling recovers exactly one kit and removes support")
	_expect(drops.nearest_loose_of_key(KIT,bank,{},"",-1,"base:material:pine") != null, "recovered bridge kit keeps pine")
	_expect(water.flow.mass==baseline, "dismantling leaves finite water unchanged")
	await _frames(2)
	_expect(on_deck.position.y<21, "loose goods settle when a removed deck no longer supports them")
	# Destruction cancels unpaid plans without losing their item.
	worker.position = Vector3(bank)+Vector3(.5,1,.5)
	id = bridges.place(bank,3)
	_expect(id>0, "recovered kit can be placed again")
	world.set_block(far_bank.x,far_bank.y,far_bank.z,0)
	await process_frame
	bridges._process(.25)
	_expect(not bridges.routes.has(id) and _count(KIT)==1, "lost bank cancels an unbuilt plan and releases kit")
	world.set_block(far_bank.x,far_bank.y,far_bank.z,blocks.get_id("base:terrain:rock:rock01"))
	await process_frame
	id = bridges.place(bank,3)
	_expect(await _condition(func(): return bridges.routes[id].built), "recovered kit rebuilds after bank repair")
	bridges.perform_explorer_action(id,"remove")
	bridges.perform_explorer_action(id,"reopen")
	_expect(not nav.find_path(bank,far_bank).is_empty() and _count(KIT)==0, "cancel dismantling reopens the paid deck without creating a kit")
	worker.position = Vector3(46.5,21,48.5)
	worker._begin_sleep()
	world.set_block(far_bank.x,far_bank.y,far_bank.z,0)
	await process_frame
	bridges._process(.25)
	_expect(bridges.routes[id].mode=="damaged" and nav.bridge_supports(worker.current_cell()), "bank damage closes traffic while retaining occupied supports")
	_expect(await _condition(func(): return not bridges.routes.has(id)), "sleeping occupant evacuates before damaged bridge recovers")
	_expect(nav.is_walkable(worker.current_cell()) and _count(KIT)==1, "damage recovery leaves the dwarf on land and conserves the kit")
	for message: String in failures: push_error(message)
	print("LOG_BRIDGE_OK" if failures.is_empty() else "LOG_BRIDGE_FAIL: %s" % str(failures))
	quit(0 if failures.is_empty() else 1)

func _tick() -> void:
	bridges._process(.25)
	crafting._refresh()
	furniture._process(.25)
	tasks._run_scheduler()
	worker._process(.1)
	await process_frame

func _condition(condition: Callable) -> bool:
	for i in range(1800):
		if condition.call(): return true
		await _tick()
	print("BRIDGE WAIT: ",worker.current_cell()," phase=",worker._task_phase," routes=",bridges.serialize_state())
	print("BRIDGE TASKS: idle=",tasks._idle_dwarves," exit=",worker.needs_bridge_exit()," sleep=",worker.is_sleeping())
	for task in tasks._tasks.values(): print("JOB ",task.id," type=",task.type," status=",task.status," blocked=",task.blocked_count," retry=",task.retry_at," source=",task.source_id)
	return false

func _geometry_checks() -> void:
	var site := Vector3i(80,20,80)
	var rock: int = blocks.get_id("base:terrain:rock:rock01")
	var wet: int = blocks.get_id("base:terrain:water:source")
	for yaw in range(4):
		for span in range(1,7):
			for step in range(1,span+1):
				for lane in range(2):
					var cell: Vector3i = site+bridges.facing(yaw)*step+bridges.side(yaw)*lane
					world.set_block(cell.x,cell.y,cell.z,wet)
			await process_frame
			var spec: Dictionary = bridges.describe(site,yaw)
			_expect((spec.reason=="" and spec.span==span) if span<=5 else spec.reason!="", "rotation %d accepts only 1–5 block spans (%d)" % [yaw,span])
			var aim: Dictionary = bridges.from_hit({"x":site.x,"y":site.y,"z":site.z},(yaw+1)%4)
			_expect((aim.reason=="" and aim.span==span and aim.yaw==yaw) if span<=5 else aim.reason!="", "bank snapping finds rotation %d without extending span %d" % [yaw,span])
			for step in range(1,span+1):
				for lane in range(2):
					var cell: Vector3i = site+bridges.facing(yaw)*step+bridges.side(yaw)*lane
					world.set_block(cell.x,cell.y,cell.z,rock)
	var edge := site+Vector3i.RIGHT
	world.set_block(edge.x,edge.y,edge.z,wet)
	await process_frame
	_expect(bridges.describe(site,3).reason!="", "unequal bank distances rejected")
	world.set_block(edge.x,edge.y,edge.z,rock)

func _river() -> void:
	# Enclose the loaded test arena so a failed route cannot wander into the
	# intentionally uninitialized procedural world outside this fixture.
	var rock: int = blocks.get_id("base:terrain:rock:rock01")
	for edge in range(128):
		for y in range(18,26):
			for cell: Vector3i in [Vector3i(0,y,edge),Vector3i(127,y,edge),Vector3i(edge,y,0),Vector3i(edge,y,127)]:
				world.set_block(cell.x,cell.y,cell.z,rock)
	for x in range(44,49):
		for z in range(1,127):
			for y in range(18,21): world.set_block(x,y,z,0)
	await process_frame
	water = root.get_node("WaterManager")
	water.set_process(false)
	water._config = root.get_node("WorldGenerator").load_water_profile()
	water.moisture = load("res://scripts/components/SoilMoisture.gd").new()
	water.flow = load("res://scripts/components/WaterFlow.gd").new()
	water.flow.spans_at = func(col: Vector2i): return [Vector2i(18,128)] if col.x>=44 and col.x<=48 else [Vector2i(21,128)]
	water._water_id = blocks.get_id("base:terrain:water:source")
	water.initialized = true
	for x in range(44,49):
		for z in range(128): water.flow.seed_column(Vector3i(x,18,z),2.0)
	nav._walkable_cache.clear()
	nav._path_cache.clear()
	# Dedicated native review scenery follows the same bank/deck elevations.
	for child in scene.get_children():
		if child is MeshInstance3D: child.visible = false
	for entry in [[Vector3(37,20.5,48),Vector3(14,1,24),Color("748475")],
		[Vector3(56,20.5,48),Vector3(14,1,24),Color("748475")],
		[Vector3(46.5,19.95,48),Vector3(5,.1,24),Color("72b8c4")]]:
		var mesh := MeshInstance3D.new()
		mesh.mesh = BoxMesh.new()
		mesh.position = entry[0]
		mesh.mesh.size = entry[1]
		var material := StandardMaterial3D.new()
		material.albedo_color = entry[2]
		mesh.material_override = material
		scene.add_child(mesh)

func _bridge_capture() -> void:
	var cam := root.get_camera_3d()
	cam.position = Vector3(60,33,63)
	cam.look_at(Vector3(46,20,48))
	cam.size = 20
	await _frames(4)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tmp/log_bridge_20261011/bridge.png")

func _bridge_preview_capture() -> void:
	var cam := root.get_camera_3d()
	cam.position = Vector3(60,33,63)
	cam.look_at(Vector3(46,20,48))
	cam.size = 20
	dock._open_place_catalog()
	dock._place_catalog.selected_key = BRIDGE
	dock._place_catalog.refresh()
	dock._place_catalog._fit()
	dock._place_catalog._select(BRIDGE)
	furniture._yaw = 3
	furniture._hover_cell = bank
	furniture._hover_valid = furniture._placement_valid(bank)
	furniture._position_preview(bank)
	await _frames(4)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tmp/log_bridge_20261011/preview.png")
	manager.close("place")
	furniture.activate_for(BRIDGE,true)
	furniture._yaw = 3
	furniture._hover_cell = bank
	furniture._hover_valid = furniture._placement_valid(bank)
	furniture._position_preview(bank)
