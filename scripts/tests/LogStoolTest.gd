extends "res://scripts/tests/DwarfIdleBehaviorTest.gd"

const STOOL := "base:furniture:log_chair"
const STOOL_ITEM := "base:resources:furniture:log_chair"
var picking
var seating
var capture_output := "res://tmp/log_stool_review"

func _run() -> void:
	create_timer(60).timeout.connect(func(): push_error("Log stool test timed out"); quit(1))
	await _setup_crafting_fixture()
	picking = load("res://scripts/components/ObjectPicking.gd")
	seating = load("res://scripts/components/FurnitureSeating.gd")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): capture_output=arg.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(capture_output)
	_configure(worker)
	worker._idle_behavior.config.seat_chance = 1.0
	var definition: Dictionary = furniture.get_defs()[STOOL]
	var origin := Vector3i(48,20,44)
	# Unoccupied furniture and seated dwarves retain separate physical bounds.
	for yaw in range(4):
		furniture._install(STOOL,definition,origin,yaw)
		var stool = furniture._installed.values()[0]
		var bounds: AABB = picking.world_bounds(stool.node)
		_expect(bounds.size.is_equal_approx(Vector3(.875,.875,.875)),"player stump preserves its 14-cell diameter and height without raised back/arms")
		_expect(stool.cells.size()==1 and not root.get_node("NavGrid").is_walkable(origin),"stool occupies exactly one ground tile")
		for cell in seating.access_cells(definition,origin,yaw):
			_expect(root.get_node("NavGrid").is_walkable(cell),"all four adjacent approach tiles remain walkable")
		_expect(furniture._seating.placement_reason(definition,origin+Vector3i.RIGHT,yaw)=="seat_clearance","compact stools still protect seated dwarves from overlapping heads")
		_expect(furniture._seating.placement_reason(definition,origin+Vector3i(3,0,0),yaw).is_empty(),"spaced stools remain placeable")
		_reset_at(worker,Vector3i(45,20,42))
		_expect(await _seat_phase(worker,"sitting"),"dwarf can use stump in rotation "+str(yaw))
		worker._process(1)
		var body_bounds: AABB = picking.world_bounds(worker._body)
		_expect(is_equal_approx(body_bounds.position.y,bounds.end.y),"seated torso rests on flat stump top")
		for foot in [worker._foot_l,worker._foot_r]:
			var foot_bounds: AABB = picking.world_bounds(foot)
			_expect(foot_bounds.position.y>=float(origin.y+1) and not foot_bounds.intersects(bounds.grow(-.001)),"boots rest forward of the stump, above ground")
		var saved_dwarf: Dictionary = worker.serialize_state()
		var saved_position: Vector3 = root.get_node("SaveManager").unpack_v3(saved_dwarf.position)
		_expect(root.get_node("NavGrid").is_walkable(Vector3i(floori(saved_position.x),roundi(saved_position.y)-1,floori(saved_position.z))),"seated save retains safe access position")
		if "--capture" in OS.get_cmdline_user_args():
			camera.size = 7
			camera.position = Vector3(55,27,51)
			camera.look_at(Vector3(48.5,22.1,44.5))
			await _stool_capture("occupied_%d" % yaw)
		worker._idle_behavior.cancel()
		_expect(stool.idle_seat_owner<0 and worker._body.position.is_zero_approx(),"leaving stool clears claim and seated pose")
		if yaw==0 and "--capture" in OS.get_cmdline_user_args():
			worker.hide()
			camera.size = 3
			camera.look_at(Vector3(48.5,21.3,44.5))
			await _stool_capture("stump")
			worker.show()
		furniture.dev_remove_installed(stool.installed_id)
		for node in drops._loose.keys(): drops.take(node); node.free()
	for failure in failures: push_error(failure)
	print("LOG_STOOL_OK: compact geometry, four rotations, torso/feet fit, access, head clearance, and seated save" if failures.is_empty() else "LOG_STOOL_FAIL")
	quit(0 if failures.is_empty() else 1)

func _stool_capture(name: String) -> void:
	await _frames(3)
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image().save_png(capture_output.path_join(name+".png"))
	_expect(result==OK,"native stool capture saved: "+name)
