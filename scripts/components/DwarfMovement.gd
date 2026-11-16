extends RefCounted

## Dwarf movement (doc 16 step 3b): path following, ladder climbing, the
## distance-driven walk cycle and physical floor support. Path = ordered floor
## cells from NavGrid; the agent stands on cell tops (y = floor_y + 1). Direct
## position movement — no physics sweep (collision_mask 0); obstacle
## correctness comes from the nav grid, not the physics engine.
##
## DwarfAgent.walk_to/walk_nearby cancel leisure, meals and promotions first,
## then call the matching method here. walk_finished is the agent's signal.
##
## Walk animation (2026-07-02 rework): the gait cycle is driven by
## DISTANCE TRAVELLED, not time — feet plant in sync with ground covered at
## any speed. With foot swing amplitude = stride_length/2 and the planted
## foot sliding backward (relative to the body) exactly one stride per half
## cycle, the planted foot stays world-fixed — the core fix for foot sliding.

const Privacy = preload("res://scripts/components/DwarfPrivacy.gd")
const BodyRig = preload("res://scripts/components/DwarfBodyRig.gd")
const StepPose = preload("res://scripts/components/DwarfStepPose.gd")
const LADEN_TURN := 6.0   # radians a second
const LONGEST_STEP := 1.5   # blocks of ground a step's feet may cover, whatever line the actor is on
const SHORTCUT_INTERVAL := 0.3   # s between string-pulling rescans (cost bound)
## String-pulling cells scanned ahead per check (bounds cost).
const SHORTCUT_LOOKAHEAD := 24

var agent: DwarfAgent
var rig: BodyRig
var foot_lift := .22
var move_path: Array[Vector3i] = []
var move_index: int = 0
var walk_cycle: float = 0.0
var shortcut_timer: float = 0.0
var ladder_path_revision := -1
var move_validation_revision := -1
var move_validation_index := -1
var ladder_fall_target := Vector3i(-1, -1, -1)
## Heavy carried items slow the walk (doc 18 §2.3 / items.json contract).
var carry_speed_mult: float = 1.0
## The walk's last stretch heads for where the work will draw the body (stop_short_of).
var arriving := false
var arrive_spot := Vector3.ZERO
var arrive_yaw := 0.0
## A walk to a meal's seat or a game (doc 41 "Privacy"): its replans and its shortcuts keep to the
## rooms the dwarf may use, as its first route did. Work walks stay unrestricted.
var leisure := false
## The step up or down being taken: +1, -1 or 0, and how far through it the feet have got.
var step_rise := 0
var step_progress := 0.0


func _init(p_agent: DwarfAgent = null, p_rig: BodyRig = null) -> void:
	agent = p_agent
	rig = p_rig


## Path part of DwarfAgent.walk_to. Returns true if a path was found and the
## walk began; emits walk_finished(false) when there is none.
func walk_to(goal_cell: Vector3i, private_walk := false) -> bool:
	rig.reset_part_offsets()
	rig.leave_work_spot()
	arriving = false
	leisure = private_walk
	var floor_filter := Callable()
	var dwarf_id := agent.dwarf_id
	if agent.is_sleeping(): floor_filter = func(cell: Vector3i): return Privacy.allowed(cell,dwarf_id,true)
	elif leisure: floor_filter = func(cell: Vector3i): return Privacy.allowed(cell,dwarf_id)
	var path := NavGrid.find_path(agent.current_cell(), goal_cell,NavGrid.DEFAULT_MAX_NODES,floor_filter)
	if path.is_empty():
		clear_path() # Failure callbacks may synchronously install a new route.
		agent.walk_finished.emit(false)
		return false
	move_path = path
	ladder_path_revision = NavGrid.ladder_revision
	move_index = 0
	move_validation_index = -1
	walk_cycle = 0.0
	shortcut_timer = 0.0   # string-pull immediately on the first frame
	return true


## Path part of DwarfAgent.walk_nearby: a short, fully checked flat segment.
func walk_nearby(goal_cell: Vector3i) -> void:
	rig.reset_part_offsets()
	rig.leave_work_spot()
	arriving = false
	if not NavGrid.line_walkable_flat_from(agent.global_position,goal_cell):
		clear_path()
		agent.walk_finished.emit(false)
		return
	move_path = [agent.current_cell(),goal_cell]
	move_index = 0
	move_validation_index = -1
	walk_cycle = 0.0
	shortcut_timer = 0.0
	ladder_path_revision = NavGrid.ladder_revision


## Starts a walk along a route already searched (a meal's, a game's, a promotion's) as walk_to
## starts one: the body leaves its work spot, and no earlier walk's stop-short spot carries over.
func start_route(path: Array, private_walk := false) -> void:
	rig.reset_part_offsets()
	rig.leave_work_spot()
	arriving = false
	leisure = private_walk
	var route: Array[Vector3i] = []
	route.assign(path)
	move_path = route
	move_index = 0
	move_validation_index = -1
	ladder_path_revision = NavGrid.ladder_revision
	walk_cycle = 0.0
	shortcut_timer = 0.0


## Work that stands closer than its swing's `reach` draws the body back from the cell centre. Walk to
## that spot instead of past it and sliding back (doc 298). The job still starts on the cell centre:
## arrive_at moves the actor there unseen, and goods in hand stay where they are drawn.
func stop_short_of(contact: Vector3, reach: float) -> void:
	if not _may_stop_short(): return
	var goal: Vector3i = move_path.back()
	var center := Vector3(goal.x+.5,goal.y+1,goal.z+.5)
	var flat := Vector3(contact.x-center.x,0,contact.z-center.z)
	var back := reach-flat.length()
	if flat.length() < .3 or back <= .02: return
	var toward := flat.normalized()
	var spot := center-toward*back
	var cell := Vector3i(floori(spot.x),goal.y,floori(spot.z))
	if cell != goal and not NavGrid.is_walkable(cell): spot = center-toward*minf(back,rig.CELL_EDGE)
	arriving = true
	arrive_spot = spot
	arrive_yaw = atan2(toward.x,toward.z)


## Whether this walk may end short of its goal cell. Not on a ladder; and a last step up or down is
## taken as ever, since a spot behind it would hang over the lower floor and the support check would
## drop the dwarf off the step.
func _may_stop_short() -> bool:
	if move_path.is_empty(): return false
	var goal: Vector3i = move_path.back()
	if not NavGrid.ladder_at(goal).is_empty(): return false
	return move_path.size() < 2 or move_path[move_path.size()-2].y == goal.y


func stop_walking() -> void:
	if move_path.is_empty():
		return
	clear_path()
	rig.reset_part_offsets()
	agent.walk_finished.emit(false)


## NOTE: never .clear() move_path — NavGrid hands out its CACHED array, so
## clearing in place would corrupt the cache. Always swap in a fresh one.
## An abandoned walk's stop-short spot goes with it.
func clear_path() -> void:
	var fresh: Array[Vector3i] = []
	move_path = fresh
	move_index = 0
	arriving = false
	leisure = false


## String-pulling (the zigzag fix): advance the target waypoint to the FURTHEST
## same-level path cell reachable in a straight walkable line from here, so the
## agent walks at any angle between obstacles instead of tracing 45-degree grid
## stairs. The grid path remains the correctness authority; elevation changes
## stay waypoint-exact (no shortcutting across terrace steps).
func _advance_shortcut() -> void:
	var here := agent.current_cell()
	# Halfway through a step or rung the actor already counts as on the new floor. It finishes on the
	# waypoint first: a shortcut from here would spread the last of the height over the whole line.
	if absf(agent.global_position.y-float(here.y+1)) > .001: return
	var best := move_index
	var limit := mini(move_path.size() - 1, move_index + SHORTCUT_LOOKAHEAD)
	for j in range(move_index + 1, limit + 1):
		if move_path[j].y != here.y:
			break   # elevation change ahead — take those steps exactly
		if (agent.is_sleeping() or leisure) and not Privacy.segment(here,move_path[j],agent.dwarf_id,agent.is_sleeping()): break
		if NavGrid.line_walkable_flat_from(agent.global_position, move_path[j]):
			best = j
		else:
			break
	move_index = best


func is_walking() -> bool:
	return not move_path.is_empty()


func follow_path(delta: float) -> void:
	if ladder_path_revision != NavGrid.ladder_revision:
		# A ladder elsewhere changes nothing for this walk; only one on its way replans it.
		if NavGrid.ladder_change_touches(move_path, move_index, ladder_path_revision):
			_repath_walk()
			return
		ladder_path_revision = NavGrid.ladder_revision
	shortcut_timer -= delta
	if shortcut_timer <= 0.0:
		_advance_shortcut()
		shortcut_timer = SHORTCUT_INTERVAL
	var cell := move_path[move_index]
	# Cache the check until the target segment or navigation changes. A distant
	# edit can require a cheap clearance check, but never a new A* search unless
	# this segment is actually blocked. Later waypoints are checked on entry too.
	if move_validation_index != move_index or move_validation_revision != NavGrid.navigation_revision:
		if not move_segment_clear(cell):
			_repath_walk()
			return
		move_validation_index = move_index
		move_validation_revision = NavGrid.navigation_revision
	var center := Vector3(float(cell.x) + 0.5, float(cell.y + 1), float(cell.z) + 0.5)
	var last := move_index == move_path.size()-1
	var target := Vector3(arrive_spot.x,center.y,arrive_spot.z) if arriving and last else center
	var to_target := target - agent.global_position
	var distance := to_target.length()
	# Heavy carried items slow the walk (doc 18 §2.3 / items.json contract).
	var step := agent.walk_speed * carry_speed_mult * delta
	var here := agent.current_cell()
	var route := NavGrid.ladder_at(here)
	if route.is_empty(): route = NavGrid.ladder_at(cell)
	var climbing := not route.is_empty() and (absf(to_target.y) > .01 or not NavGrid.is_walkable(here))
	if climbing != rig.climbing: rig.reset_part_offsets()
	rig.climbing = climbing
	if rig.climbing:
		step *= float(route.speed)
		agent.rotation.y = atan2(route.facing.x, route.facing.z)

	# Face travel direction (XZ only). The dwarf part GLBs are authored with
	# the FACE on the +Z side (tools/hearthblock/art/dwarves.mjs), so local +Z —
	# not Godot's usual -Z — must point along travel. Smooth turn, no snap.
	var flat := Vector2(to_target.x, to_target.z)
	if not rig.climbing and flat.length_squared() > 0.0001:
		var target_yaw := atan2(flat.x, flat.y)
		var turn := delta * 10.0
		# Turning to the work over the last block, so nothing in hand swings as the walk ends.
		if arriving and last and distance < 1.0:
			target_yaw = arrive_yaw
			turn /= maxf(distance, .1)
		var yaw := lerp_angle(agent.rotation.y, target_yaw, minf(1.0, turn))
		# A load rides ahead of the dwarf, so a sharp turn would swing it through the air.
		if not rig.carried_entries.is_empty() and not (arriving and last and distance < 1.0):
			yaw = rotate_toward(agent.rotation.y, yaw, LADEN_TURN * delta)
		agent.rotation.y = yaw

	_track_step(0 if rig.climbing or absf(to_target.y) < .001 else int(signf(to_target.y)))
	if distance <= step:
		agent.global_position = target
		if step_rise != 0: _pose_step(Vector3.ZERO)
		elif not rig.climbing and distance > 0.0: walk_bob(distance)
		_track_step(0)
		move_index += 1
		if move_index >= move_path.size():
			var arrived := arriving
			arriving = false
			clear_path()
			rig.reset_part_offsets()
			if arrived: rig.arrive_at(center,arrive_yaw)
			agent.walk_finished.emit(true)
		return
	agent.global_position += to_target / distance * step
	if rig.climbing:
		walk_cycle = fposmod(walk_cycle + step / 1.0, 1.0)
		var top := float(route.base.y + 1 + route.height) - agent.global_position.y
		rig.carry_pose.climb(rig.carried_entries, walk_cycle, top, rig.climb_back())
	elif step_rise != 0: _pose_step(to_target)
	else: walk_bob(step)


## A step up or down starts and ends with an ease, and each one leads with the other foot.
func _track_step(rise: int) -> void:
	if rise == step_rise: return
	rig.blend_pose()
	step_rise = rise
	step_progress = 0.0
	if rise != 0: walk_cycle = fposmod(walk_cycle+.5,1.0)


## Height sets the progress: an actor rises evenly along a step, and the pose does the rest.
func _pose_step(to_target: Vector3) -> void:
	var t := clampf(1.0-absf(to_target.y),0.0,1.0)
	var flat := minf(Vector2(to_target.x,to_target.z).length()/maxf(1.0-t,.05),LONGEST_STEP) if t < .95 else 1.0
	for plant in [StepPose.LEAD_PLANTS,StepPose.TRAIL_PLANTS]:
		if step_progress < plant and t >= plant: WorkFeedback.play_footstep(agent)
	step_progress = t
	StepPose.apply(rig,t,step_rise,flat,walk_cycle < .5)


func move_segment_clear(cell: Vector3i) -> bool:
	if not NavGrid.is_navigable(cell): return false
	var here := agent.current_cell()
	if here.y == cell.y and NavGrid.is_walkable(here) and NavGrid.is_walkable(cell):
		return NavGrid.line_walkable_flat_from(agent.global_position,cell)
	# Steps and ladder entry/exit stay waypoint-exact. During a vertical step,
	# current_cell() can briefly be between the two supporting floor heights.
	return absi(here.x-cell.x)+absi(here.z-cell.z) <= 1


func _repath_walk() -> void:
	var goal: Vector3i = move_path.back()
	var keep := [arriving,arrive_spot,arrive_yaw]
	var idle := agent.get_idle_behavior()
	if idle != null and idle.owns_walk():
		agent.walk_nearby(goal)
	else:
		if idle != null and idle.active(): idle.cancel()
		# Not agent.walk_to: a meal, game or promotion keeps its walk, and hears only if no route is left.
		# A walk to a meal's seat or a game keeps out of rooms the dwarf may not use (doc 41).
		walk_to(goal, leisure)
		# The new route keeps the spot only if it could stop short too (no last step up or down).
		if keep[0] and not move_path.is_empty() and move_path.back() == goal and _may_stop_short():
			arriving = true
			arrive_spot = keep[1]
			arrive_yaw = keep[2]
	# walk_to/nearby clear failure state BEFORE emitting walk_finished; never
	# clear here, since a task's failure handler may already have a new route.


## Distance drives the stride so carrying and time controls cannot make feet
## skate. The stance half remains linear; the return half eases into a higher
## arc. Rotations pivot around the part centres, not around the actor's feet.
func walk_bob(moved: float) -> void:
	var stride_length := agent.stride_length
	var next_cycle := walk_cycle + moved / maxf(stride_length * 2.0, 0.01)
	# Both feet land once per cycle. Coalesce skipped contacts on a stalled
	# frame, and advance phase even when the listener cannot hear the dwarf.
	var contact := moved > 0.0 and floori(next_cycle * 2.0) > floori(walk_cycle * 2.0)
	walk_cycle = fposmod(next_cycle, 1.0)
	if contact and not rig.climbing: WorkFeedback.play_footstep(agent)
	var amp := stride_length * .5
	_pose_foot(rig.foot_r,walk_cycle,amp)
	_pose_foot(rig.foot_l,fposmod(walk_cycle+.5,1.0),amp)
	var wave := sin(walk_cycle*TAU)
	var bounce := (1.0-cos(walk_cycle*TAU*2.0))*.025
	var lean := deg_to_rad(agent.walk_lean_deg)
	if not rig.carried_entries.is_empty():
		# The load rocks against the stride, and a heavy one leans the dwarf back and works its knees.
		var heft: float = rig.carry_pose.heft_of(rig.carried_entries,carry_speed_mult)
		lean -= heft*.11
		bounce *= 1.0+heft*.6
		rig.carry_pose.sway_target = -wave*(.03+.05*heft)
		rig.carry_pose.roll_target = wave*(.015+.03*heft)
	var body := rig.body
	var head := rig.head
	if body != null:
		body.rotation = Vector3(lean,wave*.045,-wave*.018)
		var pivot := Vector3(0,1.15,0)
		body.position = pivot+Vector3(wave*.035,bounce,0)-body.basis*pivot
	if head != null:
		head.rotation = Vector3(lean*.35,-wave*.018,wave*.01)
		var pivot := Vector3(0,2.45,0)
		head.position = pivot+Vector3(wave*.02,bounce*.65,0)-head.basis*pivot
	if rig.hand_l != null: rig.hand_l.position = rig.relaxed_hand(-1)+Vector3(0,bounce+.025, wave*amp*.75)
	if rig.hand_r != null: rig.hand_r.position = rig.relaxed_hand(1)+Vector3(0,bounce+.025,-wave*amp*.75)


func _pose_foot(foot: Node3D, q: float, amp: float) -> void:
	if foot == null: return
	var forward: float
	var lift := 0.0
	var pitch := 0.0
	if q < .5:
		var phase := q*2.0
		forward = lerpf(-amp,amp,smoothstep(0.0,1.0,phase))
		lift = sin(phase*PI)*foot_lift
		pitch = -sin(phase*TAU)*.15
	else:
		forward = lerpf(amp,-amp,(q-.5)*2.0)
	var pivot := Vector3(-.5 if foot==rig.foot_r else .5,0,.15)
	foot.rotation.x = pitch
	foot.position = pivot+Vector3(0,lift,forward)-Basis(Vector3.RIGHT,pitch)*pivot
	foot.position.x += agent.proportions.relaxed_foot_inset * (1 if foot==rig.foot_r else -1)


# ── Physical support ──────────────────────────────────────────────────────────

func has_floor_support(cell: Vector3i) -> bool:
	return BlockRegistry.is_solid(WorldData.get_live_block(cell.x,cell.y,cell.z))


## Recover a one-block floor intersecting the feet, including saved positions.
## This is not a search through rock: the tile immediately above must already
## provide the normal three-block clearance and must not contain furniture.
func lift_from_raised_floor() -> bool:
	if ladder_fall_target.x >= 0 or not NavGrid.ladder_at(agent.current_cell()).is_empty(): return false
	var position := agent.global_position
	var feet := Vector3i(floori(position.x),floori(position.y+.001),floori(position.z))
	if not BlockRegistry.is_solid(WorldData.get_live_block(feet.x,feet.y,feet.z)) or not NavGrid.is_walkable(feet): return false
	# A valid interpolated step can briefly enter its higher supporting block.
	# Let that route finish naturally; invalidated routes cannot suppress repair.
	if is_walking() and not is_equal_approx(position.y,roundf(position.y)) \
			and move_segment_clear(move_path[move_index]): return false
	agent.global_position.y = float(feet.y+1)
	agent.apply_slice(agent.get_slice_y())
	return true


## Used immediately after our own mining commit as well as before every tick.
## Physical support is distinct from walkability: an obstructed/wet floor must
## never be skipped in favour of a deeper floor through solid terrain.
## Ladders and supported step interpolation already own their vertical motion.
func snap_to_floor() -> bool:
	var cell := agent.current_cell()
	if has_floor_support(cell) or not NavGrid.ladder_at(cell).is_empty() or ladder_fall_target.x >= 0:
		return false
	# While stepping up, rounded nav height can differ from the solid block
	# immediately under the feet. Do not lower the actor into that step.
	var feet := Vector3i(cell.x,floori(agent.global_position.y-.001),cell.z)
	if has_floor_support(feet): return false
	for y in range(mini(cell.y,feet.y)-1,-1,-1):
		var below := Vector3i(cell.x,y,cell.z)
		if has_floor_support(below):
			agent.global_position.y = float(below.y + 1)
			agent.apply_slice(agent.get_slice_y())
			return true
	return false
