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
## Heavy carried items slow the walk (doc 18 §2.3 / resources.json contract).
var carry_speed_mult: float = 1.0


func _init(p_agent: DwarfAgent = null, p_rig: BodyRig = null) -> void:
	agent = p_agent
	rig = p_rig


## Path part of DwarfAgent.walk_to. Returns true if a path was found and the
## walk began; emits walk_finished(false) when there is none.
func walk_to(goal_cell: Vector3i) -> bool:
	rig.reset_part_offsets()
	var floor_filter := Callable()
	var dwarf_id := agent.dwarf_id
	if agent.is_sleeping(): floor_filter = func(cell: Vector3i): return Privacy.allowed(cell,dwarf_id,true)
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


func stop_walking() -> void:
	if move_path.is_empty():
		return
	clear_path()
	rig.reset_part_offsets()
	agent.walk_finished.emit(false)


## NOTE: never .clear() move_path — NavGrid hands out its CACHED array, so
## clearing in place would corrupt the cache. Always swap in a fresh one.
func clear_path() -> void:
	var fresh: Array[Vector3i] = []
	move_path = fresh
	move_index = 0


## String-pulling (the zigzag fix): advance the target waypoint to the FURTHEST
## same-level path cell reachable in a straight walkable line from here, so the
## agent walks at any angle between obstacles instead of tracing 45-degree grid
## stairs. The grid path remains the correctness authority; elevation changes
## stay waypoint-exact (no shortcutting across terrace steps).
func _advance_shortcut() -> void:
	var here := agent.current_cell()
	var best := move_index
	var limit := mini(move_path.size() - 1, move_index + SHORTCUT_LOOKAHEAD)
	for j in range(move_index + 1, limit + 1):
		if move_path[j].y != here.y:
			break   # elevation change ahead — take those steps exactly
		if agent.is_sleeping() and not Privacy.segment(here,move_path[j],agent.dwarf_id,true): break
		if NavGrid.line_walkable_flat_from(agent.global_position, move_path[j]):
			best = j
		else:
			break
	move_index = best


func is_walking() -> bool:
	return not move_path.is_empty()


func follow_path(delta: float) -> void:
	if ladder_path_revision != NavGrid.ladder_revision:
		_repath_walk()
		return
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
	var target := Vector3(float(cell.x) + 0.5, float(cell.y + 1), float(cell.z) + 0.5)
	var to_target := target - agent.global_position
	var distance := to_target.length()
	# Heavy carried items slow the walk (doc 18 §2.3 / resources.json contract).
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
		agent.rotation.y = lerp_angle(agent.rotation.y, target_yaw, minf(1.0, delta * 10.0))

	if distance <= step:
		agent.global_position = target
		move_index += 1
		if move_index >= move_path.size():
			clear_path()
			rig.reset_part_offsets()
			agent.walk_finished.emit(true)
		return
	agent.global_position += to_target / distance * step
	if rig.climbing:
		walk_cycle = fposmod(walk_cycle + step / 1.0, 1.0)
		rig.carry_pose.climb(rig.carried_entries, walk_cycle)
		if rig.foot_l != null: rig.foot_l.position = Vector3(0, .12 + .12 * sin(walk_cycle * TAU), .18)
		if rig.foot_r != null: rig.foot_r.position = Vector3(0, .12 - .12 * sin(walk_cycle * TAU), .18)
	else: walk_bob(step)


func move_segment_clear(cell: Vector3i) -> bool:
	if not NavGrid.is_navigable(cell): return false
	var here := agent.current_cell()
	if here.y == cell.y and NavGrid.is_walkable(here) and NavGrid.is_walkable(cell):
		return NavGrid.line_walkable_flat_from(agent.global_position,cell)
	if PlacedEntityRegistry.barrier_blocks_segment(agent.global_position,Vector3(cell)+Vector3(.5,1,.5)): return false
	# Steps and ladder entry/exit stay waypoint-exact. During a vertical step,
	# current_cell() can briefly be between the two supporting floor heights.
	return absi(here.x-cell.x)+absi(here.z-cell.z) <= 1


func _repath_walk() -> void:
	var goal: Vector3i = move_path.back()
	if agent.is_recreating():
		agent.get_recreation().cancel()
		return
	if agent.get_idle_behavior() != null and agent.get_idle_behavior().owns_walk():
		agent.walk_nearby(goal)
	else:
		agent.walk_to(goal)
	# walk_to/nearby clear failure state BEFORE emitting walk_finished; never
	# clear here, since a task's failure handler may already have a new route.


## Distance drives the stride so carrying and time controls cannot make feet
## skate. The stance half remains linear; the return half eases into a higher
## arc. Rotations pivot around the part centres, not around the actor's feet.
func walk_bob(moved: float) -> void:
	var stride_length := agent.stride_length
	walk_cycle = fposmod(walk_cycle + moved / maxf(stride_length * 2.0, 0.01), 1.0)
	var amp := stride_length * .5
	_pose_foot(rig.foot_r,walk_cycle,amp)
	_pose_foot(rig.foot_l,fposmod(walk_cycle+.5,1.0),amp)
	var wave := sin(walk_cycle*TAU)
	var bounce := (1.0-cos(walk_cycle*TAU*2.0))*.025
	var lean := deg_to_rad(agent.walk_lean_deg)
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
	return NavGrid.bridge_supports(cell) or BlockRegistry.is_solid(WorldData.get_live_block(cell.x,cell.y,cell.z))


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
	# String pulling may already have advanced the target along the upper floor.
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
