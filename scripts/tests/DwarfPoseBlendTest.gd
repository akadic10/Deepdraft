extends "res://scripts/tests/MiningAnimationTest.gd"

## Doc 298: clips ease into each other, and the hands stay out of the dwarf during ladders,
## grilling and casting.
const STEP := 1.0/60.0

func _largest_step(rig: RefCounted, frames: int, write: Callable) -> float:
	var parts: Array = [rig.hand_l,rig.hand_r,rig.foot_l,rig.foot_r,rig.body,rig.head]
	var worst := 0.0
	for i in range(frames):
		var before: Array = parts.map(func(part): return part.position)
		rig.begin_frame()
		write.call(i)
		rig.finish_frame(STEP)
		for p in range(parts.size()):
			worst = maxf(worst,before[p].distance_to(parts[p].position))
	return worst

func _run() -> void:
	create_timer(45).timeout.connect(func(): push_error("Pose blend test timed out"); quit(1))
	await _setup_mining_fixture()
	var rig: RefCounted = worker._rig
	var contact := Vector3(0,1.4,.55)
	rig.reset_part_offsets()
	rig.finish_frame(1.0)

	# Starting work: the hands travel about two blocks, and no longer in one frame.
	var relaxed: Vector3 = rig.hand_l.position
	rig.reset_part_offsets()
	var step := _largest_step(rig,40,func(_i): rig.mining_pose.apply(.2,contact))
	_expect(step < .45,"starting work eases in (largest step %.2f)" % step)
	var settled: Transform3D = rig.hand_l.transform
	rig.mining_pose.apply(.2,contact)
	_expect(settled.is_equal_approx(rig.hand_l.transform),"the blend ends exactly on the clip")
	_expect(relaxed.distance_to(rig.hand_l.position) > 1.0,"the check spans a real move")

	# Stopping: the rest pose comes back whole, including what idle never writes.
	rig.reset_part_offsets()
	_largest_step(rig,3,func(_i): pass)
	rig.begin_frame()
	_expect(rig.hand_l.position.is_equal_approx(rig.relaxed_hand(-1)),"mid-blend the clip still sees its true pose")
	_largest_step(rig,40,func(_i): pass)
	_expect(rig.body.position.is_zero_approx() and rig.body.rotation.is_zero_approx(),"no blended value sticks to the body")
	_expect(rig.foot_l.position.is_equal_approx(Vector3(-.06,0,0)),"no blended value sticks to a foot")
	_expect(rig.hand_r.scale.is_equal_approx(Vector3(-1,1,1)),"blending keeps the mirrored fist")
	rig.leave_work_spot()

	# Finishing any tool work: the dwarf stays drawn back, and only walking ends it. The audit of real
	# jobs measured felling .92, mining .87 and boulders .55 of a block forward at the finish.
	for finish: Callable in [
			func(): rig.mining_pose.apply(.2,Vector3(0,1.4,.55)),
			func(): rig.felling_pose.apply(.2,Vector3(0,1.3,.5))]:
		rig.reset_part_offsets()
		rig.finish_frame(1.0)
		finish.call()
		rig.finish_frame(1.0)
		var worked: float = rig.body.position.z
		_expect(worked < -.5,"the check starts from a real work stance (%.2f)" % worked)
		rig.begin_frame()
		rig.reset_part_offsets()
		rig.idle_bob(0.0)
		_expect(is_equal_approx(rig.body.position.z,worked),"tool work ends where the dwarf stood")
		rig.carry_pose.lower(.5,[],Vector3.ZERO)
		rig.carry_pose.gather(.5,Vector3(0,.5,1))
		_expect(absf(rig.body.position.z-worked) < .1,"reaching from that spot does not pull the body forward")
		rig.finish_frame(1.0)
		rig.reset_part_offsets()   # as a walk starts
		rig.leave_work_spot()
		worker.global_position = Vector3(41.5,21,40.5)
		rig.finish_frame(1.0)

	# A long way for the body takes longer than a short one.
	rig.reset_part_offsets()
	rig.finish_frame(1.0)
	rig.blend_pose()
	rig.body.position = Vector3(0,0,-1)
	rig.finish_frame(1.0/60.0)
	_expect(rig._blend_total > .4,"a one-block move eases over longer (%.2f s)" % rig._blend_total)
	rig.begin_frame()
	rig.reset_part_offsets()
	rig.finish_frame(1.0)

	# Ladder: hands outside the head for the whole cycle, feet planted for the climb.
	rig.reset_part_offsets()
	rig.finish_frame(1.0)
	var climb_back: float = rig.CLIMB_BACK
	var head_box := AABB(Vector3(-1,1.8125,-.6875-climb_back),Vector3(2,1.5,1.4375))
	var pose = rig.carry_pose
	for i in range(24):
		pose.climb([],float(i)/24.0,INF,climb_back)
		var left: Vector3 = rig.hand_l.transform*pose.PALM
		var right: Vector3 = rig.hand_r.transform*pose.PALM
		_expect(not head_box.has_point(left) and not head_box.has_point(right),"climbing hands stay out of the head")
		_expect(absf(left.x) < .35 and absf(right.x) < .35,"climbing hands grip the rails, not the air beside them")
	pose.climb([],.25,1.5,climb_back)
	_expect((rig.hand_l.transform*pose.PALM).y <= 1.501,"hands never grip above the ladder's top")
	_expect(is_equal_approx(rig.head.position.z,-climb_back),"the head climbs behind the ladder, not through it")
	var feet := []
	for cycle in [.25,.75]:
		pose.climb([],cycle)
		feet.append(rig.foot_l.position.y)
	_expect(absf(absf(feet[0]-feet[1])-.5) < .001,"a half cycle moves a foot half a block, the climb's half cycle")
	rig.reset_part_offsets()

	# Grill carry: the fist and the stick stand clear of the body and head.
	var perch: Dictionary = root.get_node("DwarfAssets").grill_sticks["base:item:perch"]
	rig.grill_pose.apply("carry",perch.raw,Vector3.ZERO)
	var grip: Vector3 = rig.hand_r.transform*rig.grill_pose.PALM
	_expect(absf(grip.x) > 1.0,"the carried stick stands beside the head, not inside it")
	rig.reset_part_offsets()

	# Cast: the free hand travels to the rod over the swing, not in one frame.
	rig.finish_frame(1.0)
	rig.blend_pose()   # as a new catch does
	var water := Vector3(0,-.05,3.8)
	var cast := _largest_step(rig,144,func(i): rig.fishing_pose.apply(float(i)/60.0/30.0,water))
	_expect(cast < .4,"the free hand never teleports in a cast (largest step %.2f)" % cast)
	rig.reset_part_offsets()

	# Idle at a wall: the head stands clear of it, in the drawing only. The owner saw a finished
	# builder's head and beard inside the stone it had just built.
	var wall_cell := Vector3i(41,22,41)
	var behind := Vector3i(41,22,39)
	worker.global_position = Vector3(41.5,21,40.5)
	worker.rotation = Vector3.ZERO
	world.set_block(wall_cell.x,wall_cell.y,wall_cell.z,blocks.get_id("base:terrain:rock:rock01"))
	rig.reset_part_offsets()
	rig.idle_bob(0.0)
	_expect(rig.head.position.z < -.25,"an idle head stands back from a wall at the face")
	_expect(worker.global_position.z == 40.5,"standing back leaves the actor on its cell centre")
	_expect(is_equal_approx(rig.foot_l.position.z,rig.head.position.z),"the feet stand back with the head")
	world.set_block(behind.x,behind.y,behind.z,blocks.get_id("base:terrain:rock:rock01"))
	rig.idle_bob(0.0)
	_expect(is_zero_approx(rig.head.position.z),"no room behind: stay on the spot")
	world.set_block(behind.x,behind.y,behind.z,blocks.AIR_ID)
	world.set_block(wall_cell.x,wall_cell.y,wall_cell.z,blocks.AIR_ID)
	rig.idle_bob(0.0)
	_expect(is_zero_approx(rig.head.position.z),"open ground: stand on the spot")
	rig.reset_part_offsets()

	# Build hammer: raised clear of the head, and the strike lands on the block's face.
	var builder = rig.construction_pose
	var block := Vector3i(41,22,41)
	var builds = load("res://scripts/components/DwarfConstructionPose.gd")
	var hit: Vector3 = builds.contact_point(block,worker.global_position,worker.global_basis.z)
	_expect(AABB(Vector3(block)-Vector3.ONE*.03,Vector3.ONE*1.06).has_point(hit),"the strike point lies on the block")
	var local_hit: Vector3 = worker.to_local(hit)
	_expect(local_hit.x < -.1,"the strike lands on the dwarf's right")
	builder.prepare_stance(worker.to_local(load("res://scripts/components/DwarfMiningPose.gd").contact_point(block,worker.global_position,worker.global_basis.z)))
	var inward: Vector3 = worker.global_basis.inverse()*-builds.contact_normal(block,hit)
	builder.apply(builder.RAISED_PHASE,local_hit,inward)
	var raised_fist: Vector3 = rig.hand_r.transform*builder.PALM
	_expect(raised_fist.x < -1.2,"the raised fist stands beside the head (x %.2f)" % raised_fist.x)
	builder.apply(builder.CONTACT_PHASE,local_hit,inward)
	var struck: Vector3 = builder.tool.global_transform*builder.MODEL_POINT
	_expect(struck.distance_to(hit) < .001,"the hammer's end reaches the strike point")
	var steady: Vector3 = rig.hand_l.transform*builder.PALM
	_expect(steady.x > 0.0 and absf(steady.z-local_hit.z) < .4,"the free hand steadies the block")
	# Finishing: the builder stays on its hammering spot, and leaves it only by walking. The owner
	# saw it slide forward into what it had built.
	rig.finish_frame(1.0)
	var hammering: float = rig.body.position.z
	_expect(hammering < -.5,"the check starts from a real hammering stance")
	rig.reset_part_offsets()
	rig.idle_bob(0.0)
	_expect(is_equal_approx(rig.body.position.z,hammering) and is_equal_approx(rig.foot_l.position.z,hammering),"a finished builder keeps its hammering spot")
	rig.reset_part_offsets()
	rig.idle_bob(0.0)
	_expect(is_equal_approx(rig.body.position.z,hammering),"a second reset does not lose the spot")
	# Leaving by walking: nothing moves on screen. The owner saw the body pulled half a block forward
	# into the stone by the first step, when a builder left with the top block unfinished.
	rig.finish_frame(1.0/60.0)
	var drawn_before: Vector3 = worker.to_global(rig._shown[0].origin)
	var actor_before: Vector3 = worker.global_position
	worker._movement.walk_to(worker.current_cell())
	worker._movement.clear_path()
	_expect(worker.global_position.z < actor_before.z-.4,"walking moves the actor back to the drawn spot")
	_expect(worker.to_global(rig._blend_from[0].origin).distance_to(drawn_before) < .02,"leaving does not move the body on screen")
	rig.idle_bob(0.0)
	_expect(is_zero_approx(rig.body.position.z),"walking leaves the spot")
	worker.global_position = actor_before
	rig.reset_part_offsets()

	# A block's first swing opens at the ready pose and still lands on contact.
	var execution: RefCounted = worker._work_execution
	execution._opening_swing = true
	_expect(is_equal_approx(execution._mine_phase(0.0),.2),"the first swing opens at the ready pose")
	_expect(is_equal_approx(execution._mine_phase(.92),.92),"the first swing still lands on contact")
	execution._opening_swing = false
	_expect(is_equal_approx(execution._mine_phase(.5),.5),"later swings keep their phase")

	# Idle: breathing that shows at game zoom, gestures from each kind, feet planted, no z drift.
	rig.reset_part_offsets()
	rig.finish_frame(1.0)
	var gestures = load("res://scripts/components/DwarfIdleGesture.gd")
	var seen := {}
	var lowest := INF
	var highest := -INF
	var furthest_hand := 0.0
	for i in range(6000):
		var t := float(i)*.05
		rig.idle_pose(t,3)
		lowest = minf(lowest,rig.body.position.y)
		highest = maxf(highest,rig.body.position.y)
		furthest_hand = maxf(furthest_hand,rig.hand_l.position.distance_to(rig.relaxed_hand(-1)))
		seen[gestures._kind(gestures._roll(floori(t/gestures.SLOT_SECONDS),3))] = true
		_expect(is_zero_approx(rig.foot_l.position.z) and is_zero_approx(rig.foot_r.position.y),"idle feet stay planted")
	_expect(highest-lowest > .07,"breathing is large enough to see (%.3f)" % (highest-lowest))
	_expect(furthest_hand > 1.0,"a gesture really lifts a hand (%.2f)" % furthest_hand)
	_expect(seen.size() >= 5,"a dwarf's idle goes through the gestures (%d)" % seen.size())
	_expect(not gestures.at(0.0,3).is_empty() and gestures.at(1.0,3).hash() == gestures.at(1.0,3).hash(),"a gesture follows the time alone")
	_expect(gestures.blinking(.05,0) and not gestures.blinking(1.0,0),"blinks are brief")
	rig.begin_frame()
	rig.reset_part_offsets()

	# Step up and down: each foot is planted where it stands in the world, and clears the block's edge.
	var steps = load("res://scripts/components/DwarfStepPose.gd")
	for rise in [1,-1]:
		for i in range(101):
			var t := float(i)/100.0
			steps.apply(rig,t,rise,1.0,true)
			var lead_along: float = rig.foot_r.position.z+t
			var trail_along: float = rig.foot_l.position.z+t
			var lead_up: float = (rig.foot_r.position.y+t*rise)*rise
			var trail_up: float = (rig.foot_l.position.y+t*rise)*rise
			if t >= .55: _expect(is_equal_approx(lead_along,.75) and absf(lead_up-1.0) < .01,"the lead foot stays planted on the new level")
			if t <= .45: _expect(is_zero_approx(trail_along) and is_zero_approx(trail_up),"the trailing foot stays planted on the old level")
			if rise > 0:
				if lead_along > .5: _expect(lead_up > .95,"the lead foot clears the block's edge")
				if trail_along > .5: _expect(trail_up > .95,"the trailing foot clears the block's edge")
			else:
				if lead_up > .05: _expect(lead_along > .5,"a foot stays on the upper level until past the edge")
				if trail_up > .05: _expect(trail_along > .5,"the trailing foot crosses the edge before dropping")
		steps.apply(rig,.25,rise,1.0,true)
		_expect(rig.body.position.y*rise < -.15 if rise > 0 else rig.body.position.y > .15,"the body keeps to the feet, not the straight line")
		steps.apply(rig,1.0,rise,1.0,true)
		_expect(absf(rig.body.position.y) < .001,"the step ends with the body on the new level")
	rig.reset_part_offsets()

	# Carrying: a load rocks against the stride, a heavy one leans the dwarf back, and it all stops
	# when the walk does. Turning laden is limited, as a load rides ahead of the dwarf.
	var load_node := Node3D.new()
	worker.add_child(load_node)
	rig.carried_entries = [[load_node,"stone"]]
	var mover = worker._movement
	mover.carry_speed_mult = 1.0
	mover.walk_cycle = .2
	mover.walk_bob(.01)
	var light_lean: float = rig.body.rotation.x
	for i in 12: rig.carry_pose.hold(rig.carried_entries,0.0)
	var swayed: float = load_node.position.x
	_expect(absf(swayed) > .01,"the load rocks against the stride (%.3f)" % swayed)
	mover.carry_speed_mult = .7
	mover.walk_cycle = .2
	mover.walk_bob(.01)
	_expect(rig.body.rotation.x < light_lean-.05,"a heavy load leans the dwarf back")
	mover.carry_speed_mult = 1.0
	rig.reset_part_offsets()
	var settling: float = rig.carry_pose.sway
	rig.carry_pose.hold(rig.carried_entries,0.0)
	_expect(absf(rig.carry_pose.sway-settling) < .02,"stopping never jerks the load")
	for i in 40: rig.carry_pose.hold(rig.carried_entries,0.0)
	_expect(absf(rig.carry_pose.sway) < .001 and absf(rig.carry_pose.roll) < .001,"standing, the load stops rocking")
	rig.carried_entries = []
	load_node.free()
	rig.reset_part_offsets()

	# Gathering: one hand at a time, in turn, slower than the old one-second loop.
	var pick_at := Vector3(0,.5,1.2)
	rig.carry_pose.gather_loop(rig.carry_pose.PICK_SECONDS*.5,pick_at)
	var left_out: Vector3 = rig.hand_l.transform*rig.carry_pose.PALM
	var right_home: Vector3 = rig.hand_r.transform*rig.carry_pose.PALM
	_expect(left_out.distance_to(pick_at) < .35 and right_home.distance_to(pick_at) > .5,"one hand picks while the other waits")
	rig.carry_pose.gather_loop(rig.carry_pose.PICK_SECONDS*1.5,pick_at)
	_expect((rig.hand_r.transform*rig.carry_pose.PALM).distance_to(pick_at) < .35,"the hands take turns")
	rig.reset_part_offsets()

	# Fishing's long wait keeps breathing and glancing; the cast and the bite stay as they were.
	var bobbing := {}
	var glancing := {}
	for i in range(200):
		rig.fishing_pose.apply(lerpf(.1,.8,float(i)/199.0),water)
		bobbing[snappedf(rig.body.position.y,.005)] = true
		glancing[snappedf(rig.head.rotation.y,.02)] = true
	_expect(bobbing.size() > 6 and glancing.size() > 10,"the wait is not total stillness")
	rig.reset_part_offsets()

	# Mining: the fists go around the head, not through it, at every height.
	var miner = rig.mining_pose
	var worst := 0.0
	for height in [1.4,2.2,3.0,3.6,4.15]:
		var strike_at := Vector3(0,height,1.3)
		var inside := 0
		for i in range(200):
			miner.apply(float(i)/200.0,strike_at)
			var box := AABB(head_box.position+Vector3(0,0,climb_back)+rig.head.position,head_box.size)
			var left_fist: Vector3 = rig.hand_l.transform*miner.PALM
			var right_fist: Vector3 = rig.hand_r.transform*miner.PALM
			if box.has_point(left_fist) or box.has_point(right_fist): inside += 1
		print("MINE_ARC height ",height," inside ",inside/2.0,"%")
		worst = maxf(worst,inside/2.0)
	_expect(worst < 15.0,"mining fists mostly stay out of the head (worst %.1f%% of a swing)" % worst)
	rig.reset_part_offsets()

	# Bench work: each career's own motion lands on the same contact as the Worker's swing, and the
	# small strokes really stay small.
	var bench_contact := Vector3(0,1.2,1.3)
	var feller = rig.felling_pose
	var tool_scene: PackedScene = load("res://assets/models/items/tools/stone_hammer.glb")
	var travelled := {}
	for motion in ["adze","tap","blow",""]:
		var lowest_fist := INF
		var highest_fist := -INF
		var free_hand_moved := 0.0
		feller.apply_bench(feller.CONTACT_PHASE,bench_contact,tool_scene,motion)
		var free_at: Vector3 = rig.hand_l.transform*feller.PALM
		var edge: Vector3 = (rig.hand_r.transform*feller.PALM)
		for i in range(100):
			feller.apply_bench(float(i)/100.0,bench_contact,tool_scene,motion)
			var fist: Vector3 = rig.hand_r.transform*feller.PALM
			lowest_fist = minf(lowest_fist,fist.y)
			highest_fist = maxf(highest_fist,fist.y)
			free_hand_moved = maxf(free_hand_moved,(rig.hand_l.transform*feller.PALM).distance_to(free_at))
		travelled[motion] = highest_fist-lowest_fist
		_expect(edge.distance_to(bench_contact) < 2.0,"the %s stroke lands at the bench" % motion)
		if motion in ["tap","blow"]: _expect(free_hand_moved < .1,"the free hand stays on the work: %s" % motion)
	_expect(travelled["tap"] < travelled["adze"] and travelled["adze"] < travelled["blow"],"a tap is smaller than an adze stroke, and that smaller than a blow: %s" % travelled)
	_expect(travelled["adze"] < .9,"an adze stroke stays close in (%.2f)" % travelled["adze"])
	feller.apply_bench(.2,bench_contact,tool_scene,"blow")
	_expect((rig.hand_r.transform*feller.PALM).x < -1.0,"the raised hammer clears the head")
	rig.reset_part_offsets()

	# Mining: the same dig time, cut into calmer swings.
	var dig_work = load("res://scripts/components/MiningZoneWork.gd").new(null,{},{},4,.5)
	dig_work.visible_swing = .9
	var dig_block := Vector3i(41,10,41)
	world.set_block(dig_block.x,dig_block.y,dig_block.z,blocks.get_id("base:terrain:rock:rock01"))
	var dug: Dictionary = dig_work.get_block_work(dig_block)
	var hardness := float(blocks.get_def("base:terrain:rock:rock01").get("hardness",1))
	_expect(is_equal_approx(float(dug.swings)*float(dug.swing_time),.5*hardness),"regrouping keeps the dig time")
	_expect(float(dug.swing_time) >= .6,"a rock swing is calm (%.2f s)" % float(dug.swing_time))
	world.set_block(dig_block.x,dig_block.y,dig_block.z,blocks.AIR_ID)
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("DWARF_POSE_BLEND_OK")
	quit(0 if failures.is_empty() else 1)
