extends "res://scripts/tests/WorkerCraftingTest.gd"

const LADDER := "base:furniture:crude_ladder"
const SECTION := "base:resources:furniture:crude_ladder"
const RECIPE := "base:recipe:worker:crude_ladder"
var ladders
var nav
var base := Vector3i(48,20,48)
var upper := Vector3i(48,32,46)

func _run() -> void:
	create_timer(120).timeout.connect(func(): push_error("Ladder test timed out"); quit(1))
	await _setup_crafting_fixture()
	ladders = furniture._ladders
	ladders.set_process(false)
	nav = root.get_node("NavGrid")
	_build_cliff()
	await process_frame
	await _check_section_heights()
	var order_id: int = crafting.queue_order(RECIPE, 1)
	drops.spawn_drop(PINE, 4, Vector3i(42,21,42))
	crafting._refresh()
	_expect(crafting.get_order(order_id).lease_id < 0, "ladder crafting requires a crude workbench")
	crafting.remove_order(order_id)
	order_id = crafting.queue_order(BENCH_RECIPE, 1)
	_expect(await _completed(order_id), "worker crafts bootstrap bench from raw timber")
	furniture.activate_for(BENCH, true)
	furniture._hover_cell = Vector3i(44,20,42)
	furniture._confirm_ghost()
	furniture.deactivate()
	_expect(await _installed(BENCH), "worker physically installs the bench")
	order_id = crafting.queue_order(RECIPE, 3)
	_expect(await _completed(order_id), "ordinary Worker crafts three ladder sections")
	_expect(_count(SECTION) == 3 and _count(PINE) == 0, "four logs become bench plus three sections")
	var spec: Dictionary = ladders.describe(base, 0)
	_expect(spec.reason == "" and spec.height == 12 and ladders.sections(spec.height) == 3, "12-block cliff quotes three sections")
	_expect(ladders.sections(4) == 1 and ladders.sections(8) == 2 and ladders.sections(5) == 2, "four-block module uses ceiling costs")
	_expect(nav.find_path(base, upper).is_empty(), "tall cliff has no natural route")
	var obstruction: int = root.get_node("PlacedEntityRegistry").register_box(base + Vector3i(0,7,0), Vector3i.ONE)
	_expect(not ladders.placement_reason(base, 0).is_empty(), "head clearance rejects an occupied climbing column")
	root.get_node("PlacedEntityRegistry").unregister(obstruction)
	for yaw in range(4):
		var normal: Vector3i = -ladders.facing(yaw)
		var aim: Dictionary = ladders.from_hit({"x":48,"y":25,"z":47,"normal":normal}, yaw)
		if not aim.is_empty(): _expect(aim.yaw == yaw, "wall hit preserves facing %d" % yaw)
	var cancelled: int = ladders.place(base, 0)
	ladders.perform_explorer_action(cancelled, "pause")
	_expect(_count(SECTION) == 3 and furniture.get_catalog_stock()[LADDER].available == 3, "cancel before construction returns every claimed section")
	furniture.activate_for(LADDER, true)
	furniture._yaw = 0
	furniture._hover_cell = base
	furniture._hover_valid = furniture._placement_valid(base)
	furniture._position_preview(base)
	_expect(furniture._hint_label.text.contains("12-block") and furniture._hint_label.text.contains("3 ladder sections"), "Place preview displays full height and cost")
	var id: int = ladders._next_id
	furniture._confirm_ghost()
	furniture.deactivate()
	_expect(id > 0, "stock-backed plan is accepted")
	if id < 0: _finish(); return
	_expect(furniture.get_catalog_stock()[LADDER].available == 0, "whole route reserves exactly three sections")
	_expect(await _until_condition(func(): return ladders.routes[id].built == 4), "first section built entirely from reachable ground")
	_expect(nav.find_path(base, upper).is_empty() and not nav.find_path(base, base + Vector3i.UP * 4).is_empty(), "unfinished ladder serves extension work but cannot reach top")
	var partial: Dictionary = JSON.parse_string(JSON.stringify(ladders.serialize_state()))
	ladders.perform_explorer_action(id, "pause")
	_expect(ladders.routes[id].built == 4 and ladders.routes[id].mode == "paused", "cancelled extension retains paid support")
	_check_visible_height(id, 4)
	ladders.restore_state(partial)
	_expect(ladders.routes[id].built == 4 and ladders.routes[id].mode == "build", "unfinished route restores its next section job")
	_expect(await _until_condition(func(): return worker._climbing and worker._carried_entries.size() == 1), "worker climbs installed section carrying the next module")
	var pos: Vector3 = worker.position
	clock_node.set_paused(true)
	worker._process(2)
	_expect(worker.position == pos, "pause freezes a loaded climber")
	clock_node.set_paused(false)
	worker.dev_force_interrupt()
	_expect(worker._carried_entries.is_empty(), "interrupt drops intact section")
	_expect(await _until_condition(func(): return nav.is_walkable(worker.current_cell()) and not worker._ladder_exiting), "interrupted worker descends to safe ground")
	for task in tasks._tasks.values(): task.retry_at = 0
	_expect(await _until_condition(func(): return ladders.routes[id].built == 12), "tall ladder completes after interruption")
	_check_visible_height(id, 12)
	_expect(_count(SECTION) == 0 and not nav.find_path(base, upper).is_empty(), "completed route consumes exactly three sections and connects the top")
	# Real haul across the cliff into ground storage at the top.
	zone._cell_set.clear()
	var storage_cells: Array[Vector3i] = [Vector3i(48,32,44)]
	zone.setup(1, storage_cells)
	drops.spawn_drop(STONE, 1, Vector3i(47,21,49))
	for i in range(1800):
		zone.update_leases()
		await _tick()
		if worker._climbing and not worker._carried_entries.is_empty():
			_expect(worker._carried_entries[0][0].position.z < 0, "climbing cargo rides behind the worker, leaving hands free")
			if "--capture" in OS.get_cmdline_user_args():
				for step in range(350):
					if worker.position.y > 27: break
					await _tick()
				await _ladder_capture("loaded_climb")
			break
	_expect(await _until_condition(func(): return zone.stored_count() == 1), "hauler delivers stone through the ladder route")
	_expect(worker.current_cell().y == upper.y, "delivery worker reaches upper landing")
	# Save round trip retains paid sections and graph without phantom stock.
	var saved: Dictionary = JSON.parse_string(JSON.stringify(ladders.serialize_state()))
	ladders.restore_state(saved)
	_expect(JSON.parse_string(JSON.stringify(ladders.serialize_state())) == saved, "route state round trips with namespaced definition key")
	_expect(not nav.find_path(upper, base).is_empty(), "restored ladder is traversable in reverse")
	# Put a second dwarf on the route, then close it for recovery.
	var factory = load("res://scripts/entities/DwarfFactory.gd").new()
	extra_worker = factory.spawn(factory.generate(142,{}),142)
	scene.add_child(extra_worker)
	extra_worker.position = Vector3(base) + Vector3(.5,7,.5)
	extra_worker.set_process(false)
	tasks.register_dwarf(extra_worker)
	_expect(not ladders._safe_to_remove(ladders.routes[id], worker.dwarf_id), "recovery waits for other climbers")
	ladders.perform_explorer_action(id, "remove")
	_expect(nav.find_path(upper, base + Vector3i(0,0,1)).is_empty(), "closed route rejects new through traffic")
	_expect(not nav.find_path(extra_worker.current_cell(), base).is_empty(), "closing route still permits evacuation")
	_expect(await _until_condition(func(): return not ladders.routes.has(id)), "workers recover sections from the top down")
	_expect(_count(SECTION) == 3 and nav.find_path(base, upper).is_empty(), "all three sections recovered and route removed")
	# A need interrupt halfway up reaches the floor before sleeping.
	worker.sleep = 1.0
	worker.position = Vector3(base) + Vector3(.5,1,.5)
	id = ladders.place(base, 0)
	_expect(id > 0, "recovered sections can be reused")
	_expect(await _until_condition(func(): return ladders.routes[id].built == 12), "reused route completes")
	worker.abort_task()
	worker.position = Vector3(base) + Vector3(.5,7,.5)
	worker._begin_sleep()
	_expect(not worker.is_sleeping(), "need interrupt does not sleep in midair")
	_expect(await _until_condition(func(): return worker.is_sleeping()), "tired climber reaches safe ground then sleeps")
	_expect(nav.is_walkable(worker.current_cell()), "sleeping position has a real floor")
	worker._wake_up()
	worker.position = Vector3(base) + Vector3(.5,7,.5)
	# Excavating support closes the route, lets its occupant settle safely,
	# and recovers only the sections actually installed.
	world.set_block(base.x, base.y - 1, base.z, blocks.get_id("base:terrain:rock:rock01"))
	world.set_block(base.x, base.y, base.z, 0)
	await process_frame
	ladders._process(.25)
	_expect(await _until_condition(func(): return not ladders.routes.has(id) and nav.is_walkable(worker.current_cell())), "support loss evacuates occupant to surviving floor")
	_expect(_count(SECTION) == 3, "support loss conserves installed sections")
	_finish()

func _check_section_heights() -> void:
	var site := Vector3i(60,20,55)
	var rock: int = blocks.get_id("base:terrain:rock:rock01")
	var picking = load("res://scripts/components/ObjectPicking.gd")
	for height in [4,8,12,5,9]:
		for x in range(59,62):
			for z in range(53,57):
				for y in range(20,37):
					world.set_block(x,y,z,rock if y == 20 or (z < 55 and y <= 20 + height) else 0)
		await process_frame
		var spec: Dictionary = ladders.describe(site, 0)
		var expected: int = {4:4,8:8,12:12,5:8,9:12}[height]
		_expect(spec.reason == "" and spec.height == expected, "%d-block ledge uses a complete %d-block ladder" % [height, expected])
		# Both a full preview and the finished art must stop at the quoted top.
		for built in [0, expected]:
			var visual: Node3D = ladders.make_visual(spec.height, built)
			scene.add_child(visual)
			var bounds: AABB = picking.world_bounds(visual)
			_expect(is_zero_approx(bounds.position.y) and is_equal_approx(bounds.end.y, expected), "%d-block model/preview has no extra top cap" % expected)
			visual.free()
		ladders.restore_state({"next_id":2, "routes":[{"id":1,"key":LADDER,
			"base":[60,20,55],"yaw":0,"height":expected,"built":expected,"mode":"ready","progress":0.0}]})
		_check_visible_height(1, expected)
		_expect(not nav.find_path(site, Vector3i(60,20+height,54)).is_empty(), "full sections still exit onto the actual %d-block landing" % height)
		_expect(not nav.is_navigable(site + Vector3i.UP * (expected + 1)), "no unpaid rung above the quoted height")
		_expect(ladders.reserves(AABB(Vector3(site) + Vector3(0,expected+3,0), Vector3.ONE)), "visual bounds do not remove the three-block clearance reservation")
		ladders.restore_state({})
		if height == 5:
			var obstacle: int = root.get_node("PlacedEntityRegistry").register_box(site + Vector3i.UP * 11, Vector3i.ONE)
			_expect(not String(ladders.describe(site, 0).reason).is_empty(), "rounding up still checks body clearance above the full final section")
			root.get_node("PlacedEntityRegistry").unregister(obstacle)
	# Remove the secondary test cliff before the real crafting/installation loop.
	for x in range(59,62):
		for z in range(53,55):
			for y in range(21,33): world.set_block(x,y,z,0)
	await process_frame

func _check_visible_height(id: int, height: int) -> void:
	var route: Dictionary = ladders.routes[id]
	var bounds: AABB = load("res://scripts/components/ObjectPicking.gd").world_bounds(route.node)
	_expect(is_equal_approx(bounds.size.y, height) and is_equal_approx(bounds.end.y, route.base.y + 1 + height), "installed ladder ends at its paid height (%d)" % height)
	_expect(is_equal_approx(ladders.get_explorer_bounds(id).size.y, height), "selection outline matches the visible %d-block ladder" % height)

func _finish() -> void:
	for message: String in failures: push_error(message)
	print("LADDER_OK" if failures.is_empty() else "LADDER_FAIL: %s" % str(failures))
	quit(0 if failures.is_empty() else 1)

func _tick() -> void:
	if ladders != null: ladders._process(.25)
	crafting._refresh()
	furniture._process(.25)
	tasks._run_scheduler()
	worker._process(.1)
	zone.update_leases()
	if is_instance_valid(extra_worker): extra_worker._process(.1)
	await process_frame

func _until_condition(condition: Callable) -> bool:
	for i in range(2400):
		if condition.call(): return true
		await _tick()
	print("LADDER WAIT FAILED: ", worker.current_cell(), " phase=",worker._task_phase, " tasks=", tasks._tasks.size(), " routes=", ladders.serialize_state())
	return false

func _build_cliff() -> void:
	var rock: int = blocks.get_id("base:terrain:rock:rock01")
	for x in range(32,64):
		for z in range(32,48):
			for y in range(21,33): world.set_block(x,y,z,rock)
	# Bench/crafting area stays on the lower side.
	for x in range(32,47):
		for z in range(38,48):
			for y in range(21,33): world.set_block(x,y,z,0)
	var cliff := MeshInstance3D.new()
	cliff.mesh = BoxMesh.new()
	cliff.mesh.size = Vector3(12,12,12)
	cliff.position = Vector3(53,27,42)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("7e8385")
	cliff.material_override = mat
	scene.add_child(cliff)

func _ladder_capture(label: String) -> void:
	var camera: Camera3D = root.get_camera_3d()
	camera.position = Vector3(59,37,62)
	camera.look_at(Vector3(48.5,27,47.5))
	camera.size = 20
	await _frames(3)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tmp/ladder_review/" + label + ".png")
