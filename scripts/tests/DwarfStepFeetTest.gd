extends "res://scripts/tests/WorkerCraftingTest.gd"

## A step or rung ends on its own waypoint before the walk shortcuts ahead, and a step never draws a
## foot far from the dwarf (doc 32 "Vertical Path Mechanics"). In the owner's save a dwarf coming off
## a ladder had its feet 44 blocks away, and its selection frame grew to hold them.
const STEP := 1.0/60.0
const LADDER_ID := 900
var nav
var picking

func _run() -> void:
	create_timer(90).timeout.connect(func(): push_error("Dwarf step feet test timed out"); quit(1))
	await _setup_crafting_fixture()
	nav = root.get_node("NavGrid")
	picking = load("res://scripts/components/ObjectPicking.gd")
	_off_a_ladder()
	await _over_a_step()
	_from_a_save_mid_step()
	_long_line_pose()
	for failure in failures: push_error(failure)
	print("DWARF_STEP_FEET_OK" if failures.is_empty() else "DWARF_STEP_FEET_FAIL")
	quit(0 if failures.is_empty() else 1)

func _foot_gap() -> float:
	var rig = worker._rig
	return maxf(Vector2(rig.foot_l.position.x,rig.foot_l.position.z).length(),Vector2(rig.foot_r.position.x,rig.foot_r.position.z).length())

## Walks to `goal` frame by frame, watching what the screenshot showed: feet, the selection frame,
## and height left over on a long line.
func _walk(goal: Vector3i, label: String) -> void:
	_expect(worker.walk_to(goal),"%s: a route exists" % label)
	var furthest_foot := 0.0
	var widest_frame := 0.0
	var longest_slope := 0.0
	for i in 60*60:
		if not worker.is_walking(): break
		# A real walk looks for a shortcut every .3 s, so catching a step mid-way is down to timing.
		worker._movement.shortcut_timer = 0.0
		worker._process(STEP)
		furthest_foot = maxf(furthest_foot,_foot_gap())
		var box: AABB = picking.visible_world_bounds(worker)
		widest_frame = maxf(widest_frame,maxf(box.size.x,box.size.z))
		var at: Vector3 = worker.position
		if worker.is_walking() and absf(at.y-roundf(at.y)) > .001:
			var cell: Vector3i = worker._move_path[worker._move_index]
			longest_slope = maxf(longest_slope,Vector2(cell.x+.5-at.x,cell.z+.5-at.z).length())
	_expect(worker.current_cell() == goal,"%s: the walk arrives (%s)" % [label,worker.current_cell()])
	_expect(furthest_foot < 2.0,"%s: the feet stay with the dwarf (%.1f blocks)" % [label,furthest_foot])
	_expect(widest_frame < 5.0,"%s: the selection frame keeps the dwarf's size (%.1f blocks)" % [label,widest_frame])
	_expect(longest_slope <= 1.5,"%s: height is only left on a step's own waypoint (%.1f blocks)" % [label,longest_slope])

func _off_a_ladder() -> void:
	nav.set_ladder(LADDER_ID,Vector3i(30,20,30),8,Vector3i.LEFT,.45)
	worker.position = Vector3(30.5,25,30.5)
	_walk(Vector3i(50,20,44),"off a ladder")
	nav.remove_ladder(LADDER_ID)

func _over_a_step() -> void:
	var rock: int = blocks.get_id("base:terrain:rock:rock01")
	for x in range(34,60):
		for z in range(20,60): world.set_block(x,21,z,rock)
	await process_frame
	worker.position = Vector3(24.5,21,40.5)
	_walk(Vector3i(55,21,47),"up a step")
	_walk(Vector3i(24,20,33),"down a step")
	for x in range(34,60):
		for z in range(20,60): world.set_block(x,21,z,0)
	await process_frame

## The owner's save held the dwarf a little above the floor, and the walk restarts from there on load.
func _from_a_save_mid_step() -> void:
	worker.position = Vector3(30.42,21.05,30.42)
	_walk(Vector3i(50,20,44),"from a save mid-step")

## A step is about a block long, so the pose holds even if some other line reaches it.
func _long_line_pose() -> void:
	var movement = worker._movement
	movement.step_rise = -1
	movement._pose_step(Vector3(12,-.06,9))
	_expect(_foot_gap() < 2.0,"a step on a long line keeps the feet with the dwarf (%.1f blocks)" % _foot_gap())
	movement.step_rise = 0
	worker._rig.reset_part_offsets()
