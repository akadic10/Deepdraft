extends "res://scripts/tests/DwarfIdleBehaviorTest.gd"

const LOG_BENCH := "base:furniture:bench"
const LOG_BENCH_ITEM := "base:resources:furniture:bench"
var capture_output := ""

func _run() -> void:
	create_timer(90).timeout.connect(func(): push_error("Log bench test timed out"); quit(1))
	await _setup_crafting_fixture()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): capture_output = arg.trim_prefix("--output=")
	if not capture_output.is_empty(): DirAccess.make_dir_recursive_absolute(capture_output)
	var picking = load("res://scripts/components/ObjectPicking.gd")
	var seating = load("res://scripts/components/FurnitureSeating.gd")
	_configure(worker)
	worker._idle_behavior.config.seat_chance = 1.0
	var definition: Dictionary = furniture.get_defs()[LOG_BENCH]
	var origin := Vector3i(48,20,44)
	for yaw in 4:
		var id: int = furniture._next_installed_id
		furniture._install(LOG_BENCH,definition,origin,yaw,"base:material:juniper")
		var bench = furniture._installed[id]
		var bounds: AABB = picking.world_bounds(bench.node)
		var size := Vector3(2,1,1) if yaw%2==0 else Vector3(1,1,2)
		_expect(bounds.size.is_equal_approx(size),"bench stays inside the 1x2 footprint in rotation "+str(yaw))
		_expect(bench.cells.size()==2,"bench occupies exactly two floor cells")
		for cell: Vector3i in bench.cells:
			_expect(not root.get_node("NavGrid").is_walkable(cell),"both support cells block walking")
		for cell in seating.access_cells(definition,origin,yaw):
			_expect(root.get_node("NavGrid").is_walkable(cell),"side/rear approaches remain usable")
		_reset_at(worker,Vector3i(45,20,42))
		_expect(await _seat_phase(worker,"sitting"),"dwarf reaches the bench in rotation "+str(yaw))
		worker._process(1)
		_expect(is_equal_approx(picking.world_bounds(worker._body).position.y,bounds.end.y),"torso rests on the unchanged seat plane")
		_expect(bench.idle_seat_owner==worker.dwarf_id,"bench retains its single broad dwarf seat")
		for hand in [worker._hand_l,worker._hand_r]:
			_expect(not picking.world_bounds(hand).intersects(bounds.grow(-.001)),"resting hands clear the seat")
		for foot in [worker._foot_l,worker._foot_r]:
			var foot_bounds: AABB = picking.world_bounds(foot)
			_expect(is_equal_approx(foot_bounds.position.y,float(origin.y+1)) and not foot_bounds.intersects(bounds.grow(-.001)),"boots rest on the ground ahead of the bench")
		var front: Vector3i = [Vector3i(0,0,1),Vector3i(1,0,0),Vector3i(0,0,-1),Vector3i(-1,0,0)][yaw]
		_expect(furniture._seating.placement_reason(furniture.get_defs()[BENCH],origin+front,yaw)=="seat_clearance","nearby furniture cannot occupy the seated boots")
		var saved_dwarf: Dictionary = worker.serialize_state()
		var safe: Vector3 = root.get_node("SaveManager").unpack_v3(saved_dwarf.position)
		_expect(root.get_node("NavGrid").is_walkable(Vector3i(floori(safe.x),roundi(safe.y)-1,floori(safe.z))),"seated save uses a safe access cell")
		if not capture_output.is_empty():
			camera.size = 7
			camera.position = Vector3(55,27,51)
			camera.look_at(Vector3(49,22.1,44.5))
			await _frames(3)
			await RenderingServer.frame_post_draw
			_expect(root.get_texture().get_image().save_png(capture_output.path_join("seated_%d.png"%yaw))==OK,"native seated capture")
		worker._idle_behavior.cancel()
		_expect(bench.idle_seat_owner<0,"leaving releases the seat")
		var saved: Dictionary = furniture.serialize_state()
		furniture._teardown_installed(id,false)
		# Teardown refunds the packed item. Remove it before independently restoring
		# the installed snapshot; no player inventory participates in this fixture.
		for node in drops._loose.keys(): drops.take(node); node.free()
		furniture.restore_state(saved)
		bench = furniture._installed[id]
		_expect(bench.cells.size()==2 and bench.material_id=="base:material:juniper" and bench.yaw_steps==yaw,"restore keeps two cells, wood and orientation")
		furniture._teardown_installed(id,false)
		for node in drops._loose.keys(): drops.take(node); node.free()
	# Move the same packed identity through actual worker delivery and reinstall.
	worker._idle_behavior.config.seat_chance = 0.0
	_reset_at(worker,Vector3i(45,20,42))
	furniture._install(LOG_BENCH,definition,origin,0,"base:material:juniper")
	var original = furniture._installed.values()[0]
	furniture.begin_furniture_move(original.installed_id)
	furniture._yaw = 1
	var target := Vector3i(53,20,44)
	furniture._hover_cell = target
	_expect(furniture._placement_valid(target),"rotated Move destination is valid")
	furniture._confirm_ghost()
	furniture.deactivate()
	for i in 1000:
		await _tick()
		if furniture._ghosts.is_empty(): break
	_expect(furniture._ghosts.is_empty() and furniture._installed.size()==1,"worker packs, carries and installs exactly one bench")
	var moved = furniture._installed.values()[0]
	_expect(moved.origin_cell==target and moved.yaw_steps==1 and moved.cells.size()==2 and moved.material_id=="base:material:juniper","Move preserves material and two-cell rotated footprint")
	_expect(_count(LOG_BENCH_ITEM)==0,"Move does not duplicate the packed item")
	for failure in failures: push_error(failure)
	print("LOG_BENCH_OK: four rotations, seated contacts, access, save and worker Move" if failures.is_empty() else "LOG_BENCH_FAIL")
	quit(0 if failures.is_empty() else 1)
