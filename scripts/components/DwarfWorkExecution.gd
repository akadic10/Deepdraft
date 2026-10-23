extends "res://scripts/components/DwarfCarryWork.gd"

## Work execution for one dwarf (doc 16 §2.7). The cargo executors, the shared
## pickup/carry/set-down presentation and the attempt identity are in the base
## script, DwarfCarryWork.gd. This half holds dispatch from DwarfAgent
## (receive_task, walk_finished, interruption), the in-place executors (MINE
## zone lease, UNINSTALL, adjacent clearing), the per-frame tick and the
## progress samples TaskManager supervision observes.

## Zone-lease execution state (doc 16 step 6).
const ZONE_PULL_FAILURE_LIMIT := 3   # §2.7 step 2: 3 path failures -> release lease
## Workers retain normal speed. Miner experience reduces digging time only.
var _zone_id: int = -1
var _zone_block: Vector3i = Vector3i(-1, -1, -1)
var _zone_stand_cells: Array[Vector3i] = []
var _stand_index: int = 0
var _swings_left: int = 0
var _swing_time: float = 1.0
var _swing_timer: float = 0.0
var _pull_failures: int = 0
var _pull_exclude: Dictionary = {}   # Vector3i -> true; this-round blacklist (unpathable or nothing to mine)
var _mine_contact := Vector3.ZERO

## UNINSTALL: walk to the piece's stand cell -> teardown swing. An interrupt
## leaves the piece installed with the flag set (doc 19 §3.4).
var _uninstall_source_id: int = -1
var _fell_source_id := -1
var _fell_stands: Array[Vector3i] = []
var _fell_stand_index := 0
var _fell_contact := Vector3.ZERO


# ── Dispatch from DwarfAgent ──────────────────────────────────────────────────

## Called from DwarfAgent.receive_task once the assignment is accepted. Each
## task family runs its source's executor (MINE/HAUL leases carry zone_id). A
## task with no executor can never be worked, so it fails permanently instead
## of cycling through PENDING.
func start(assigned_id: int, task: Task, target_pos: Vector3i, carried_item: Node3D) -> void:
	task_target = target_pos
	if task != null and task.type == Task.Type.MINE and task.payload.has("zone_id"):
		_zone_id = int(task.payload["zone_id"])
		_pull_failures = 0
		_pull_exclude.clear()
		_zone_pull_next()
		return
	if task != null and task.type == Task.Type.HAUL and task.payload.has("zone_id"):
		_haul_source_id = int(task.payload["zone_id"])
		_haul_failures = 0
		_haul_exclude.clear()
		for cell: Vector3i in task.payload.get("haul_excluded_cells", []):
			_haul_exclude[cell] = true
		task.payload.erase("haul_excluded_cells") # one assignment's probe results only
		_haul_pull_next()
		return
	if task != null and task.type in [Task.Type.FETCH_BUILD, Task.Type.CRAFT]:
		_fetch_source_id = task.source_id
		if is_instance_valid(carried_item):
			_fetch_item = carried_item
			_fetch_picked_up = true
			var key := String(carried_item.get_meta("item_key", ""))
			var manager := ItemDropManager.find(agent.get_tree())
			_fetch_heavy = String(manager.get_item_def(key).get("weight_class", "light")) == "heavy"
			rig.carried_entries.append([carried_item, key])
			movement.carry_speed_mult = float(TaskManager.get_config_section("hauling").get("carry_speed_mult_heavy", .7)) if _fetch_heavy else 1.0
			rig.carry_pose.hold(rig.carried_entries)
			_fetch_travel_to_ghost()
		else:
			_fetch_begin()
		return
	if task != null and task.type == Task.Type.UNINSTALL:
		_uninstall_source_id = task.source_id
		_uninstall_begin()
		return
	if task != null and task.type in Task.SURFACE_WORK:
		_fell_source_id = task.source_id
		_fell_begin()
		return
	# No executor for this task (e.g. a MINE/HAUL without a zone source). Nothing
	# was reserved or carried yet; fail it so it is not reassigned forever.
	push_warning("DwarfAgent: task %d (%s) has no work source; failing it." % [assigned_id, Task.type_name(task.type) if task != null else "?"])
	agent.current_task_id = -1
	fail(agent.dwarf_id, "No work source can perform this task")


## The task-phase half of DwarfAgent's walk_finished handler.
func walk_finished(success: bool) -> void:
	if task_phase == DwarfAgent.TaskPhase.FELL_MOVING:
		task_phase = DwarfAgent.TaskPhase.FELL_FINDING
		if success:
			_begin_felling_work()
		return
	if task_phase == DwarfAgent.TaskPhase.ZONE_MOVING:
		task_phase = DwarfAgent.TaskPhase.NONE
		if success:
			_begin_swinging()
		else:
			# Path invalidated mid-walk — try the block's remaining stand cells.
			_zone_try_stand()
		return
	if task_phase == DwarfAgent.TaskPhase.HAUL_TO_ITEM:
		task_phase = DwarfAgent.TaskPhase.NONE
		if success:
			_haul_pickup_current()
		else:
			_haul_skip_current()   # this item unreachable; the bundle continues
		return
	if task_phase == DwarfAgent.TaskPhase.HAUL_TO_ZONE:
		task_phase = DwarfAgent.TaskPhase.NONE
		if success:
			_begin_haul_deposit()
		else:
			# Carrying and the path died — drop everything at the feet
			# (Hard Rule 12); the items re-enter the loose index.
			drop_carried_at_feet()
			_haul_cancel_pull()
			_haul_count_failure()
		return
	if task_phase == DwarfAgent.TaskPhase.FETCH_TO_ITEM:
		task_phase = DwarfAgent.TaskPhase.NONE
		if success:
			_fetch_pickup()
		else:
			_fetch_fail_release()
		return
	if task_phase == DwarfAgent.TaskPhase.FETCH_TO_GHOST:
		task_phase = DwarfAgent.TaskPhase.NONE
		if success:
			_begin_fetch_work()
		else:
			_fetch_fail_release()
		return
	if task_phase == DwarfAgent.TaskPhase.UNINSTALL_MOVING:
		task_phase = DwarfAgent.TaskPhase.NONE
		if success:
			task_phase = DwarfAgent.TaskPhase.UNINSTALL_WORKING
			exec_timer = _furniture_time("uninstall_time_s")
		else:
			_finish_uninstall_state()
			agent.current_task_id = -1
			release(agent.dwarf_id, Task.ReleaseReason.PATH_INVALID)
		return


## Interruption teardown shared by abort, sleep and force_interrupt: every
## executor drops or releases what it holds (Hard Rule 12).
func clear_task_state() -> void:
	_finish_zone_state()
	_finish_haul_state()
	_finish_fetch_state()
	_finish_uninstall_state()
	_finish_felling_state()
	task_phase = DwarfAgent.TaskPhase.NONE
	exec_timer = 0.0


## Called when the task is cancelled out from under the dwarf.
func abort() -> void:
	# Defensive unreserve — the controller's cancelled-route also frees it,
	# but cancel ordering clears assigned_to before the signal fires.
	if _zone_id >= 0:
		var source := TaskManager.get_work_source(_zone_id)
		if source != null:
			source.call("release_worker", agent.dwarf_id)
	clear_task_state()


func get_zone_block() -> Vector3i: return _zone_block


# ── Zone-lease executor (doc 16 §2.7 worker loop) ─────────────────────────────

func _zone_source() -> RefCounted:
	if _zone_id < 0:
		return null
	return TaskManager.get_work_source(_zone_id) as RefCounted

## Step 1 of the worker loop: pull the nearest pullable block. Nothing to
## pull -> the lease completes early (other workers finish the zone) or the
## zone is done — either way this dwarf is finished here.
func _zone_pull_next() -> void:
	if agent.current_task_id < 0:
		return   # cancelled out from under us mid-loop
	var source := _zone_source()
	if source == null:
		_finish_zone_state()
		agent.current_task_id = -1
		fail(agent.dwarf_id, "zone gone")
		return
	var pull: Dictionary = source.call("reserve_next", agent.dwarf_id, agent.current_cell(), _pull_exclude)
	if pull.is_empty():
		_finish_zone_state()
		agent.current_task_id = -1
		complete(agent.dwarf_id)
		return
	_zone_block = pull["block"]
	_zone_stand_cells = pull["stand_cells"]
	_stand_index = 0
	_zone_try_stand()

## Step 2: path to a stand cell (nearest first). All unpathable -> unreserve,
## blacklist the block, try the next; 3 failed blocks -> release the lease
## with backoff (§2.7 step 2).
func _zone_try_stand() -> void:
	while _stand_index < _zone_stand_cells.size():
		var stand := _zone_stand_cells[_stand_index]
		_stand_index += 1
		if stand == agent.current_cell():
			_begin_swinging()
			return
		if agent.walk_to(stand):
			task_phase = DwarfAgent.TaskPhase.ZONE_MOVING
			return
	# No stand cell pathable for this block.
	var source := _zone_source()
	if source != null:
		source.call("unreserve", agent.dwarf_id)
	_pull_exclude[_zone_block] = true
	_pull_failures += 1
	if _pull_failures >= ZONE_PULL_FAILURE_LIMIT:
		_finish_zone_state()
		agent.current_task_id = -1
		release(agent.dwarf_id, Task.ReleaseReason.PATH_INVALID)
	else:
		_zone_pull_next()

## Step 3: swing timer = (base × hardness / speed) ÷ durability per swing
## (doc 43 block time, doc 16 durability-per-swing). Partial progress is
## DISCARDED on any interruption — the block keeps full durability (§2.8).
func _begin_swinging() -> void:
	var source := _zone_source()
	if source == null:
		_zone_pull_next()   # routes to fail via null source
		return
	var work: Dictionary = source.call("get_block_work", agent.dwarf_id)
	if work.is_empty():
		# Reservation lost or nothing left to mine — pull something else.
		_skip_zone_block(source)
		return
	_swings_left = int(work["swings"])
	_swing_time = float(work["swing_time"]) * DwarfAssets.mining_duration_multiplier(agent.profession, agent.profession_experience)
	_swing_timer = _swing_time
	task_phase = DwarfAgent.TaskPhase.ZONE_SWINGING
	_face_cell(_zone_block)
	rig.reset_part_offsets()
	_mine_contact = agent.to_local(MiningPose.contact_point(_zone_block,agent.global_position,agent.global_basis.z))
	rig.mining_pose.apply(0,_mine_contact)

## Nothing to mine at the reserved block: the reservation was lost, or the cell
## is already open (e.g. cave air revealed by the previous commit stays planned
## until the deferred cleanup). Exclude it for the rest of this lease before
## pulling again — its stand is usually the current cell, so re-pulling it
## swings straight back here and recurses without end.
func _skip_zone_block(source: RefCounted) -> void:
	source.call("unreserve", agent.dwarf_id)
	_pull_exclude[_zone_block] = true
	_zone_pull_next()

func _process_swinging(delta: float) -> void:
	var source := _zone_source()
	if source == null or source.call("get_block_work",agent.dwarf_id).is_empty():
		rig.reset_part_offsets()
		if source == null:
			_zone_pull_next()   # routes to fail via null source
		else:
			_skip_zone_block(source)
		return
	# Coalesce a long frame into one contact, capped at this block's last
	# swing. Crossing (rather than pose evaluation) prevents hold/reveal replay.
	var phase := 1.0-_swing_timer/_swing_time
	var work_step := minf(delta,_swing_timer+(_swings_left-1)*_swing_time)
	var next_phase := phase+work_step/_swing_time
	if floori(next_phase-MiningPose.CONTACT_PHASE) > floori(phase-MiningPose.CONTACT_PHASE) and agent.is_visible_in_tree():
		var contact := agent.to_global(_mine_contact)
		var offset := contact-(Vector3(_zone_block)+Vector3.ONE*.5)
		var normal := Vector3.ZERO
		var axis := offset.abs().max_axis_index()
		normal[axis] = signf(offset[axis])
		source.call("play_mining_impact",agent.dwarf_id,contact,normal)
	_swing_timer -= delta
	rig.mining_pose.apply(clampf(1.0-_swing_timer/_swing_time,0,1),_mine_contact)
	if _swing_timer > 0.0:
		return
	# Carry fractional time through swing boundaries at high speed/low FPS.
	# At most this reserved block can complete; no catch-up work on a new block.
	var completed_swings := mini(_swings_left,1+floori(-_swing_timer/_swing_time))
	_swings_left -= completed_swings
	if _swings_left > 0:
		_swing_timer += completed_swings*_swing_time
		rig.mining_pose.apply(1.0-_swing_timer/_swing_time,_mine_contact)
		return
	# Step 4: the block falls. commit_mined routes the world mutation through
	# the controller (bedrock re-guard, WorldData void, renderer promotion,
	# drops, X0) and marks zone progress.
	task_phase = DwarfAgent.TaskPhase.NONE
	rig.reset_part_offsets()
	var committed := source != null and commit(agent.dwarf_id,"mine:%s" % _zone_block,func(): return source.commit_mined(agent.dwarf_id))
	if committed and agent.profession == "base:profession:miner":
		# The final commit may end the zone lease synchronously. Award first.
		agent.profession_experience[agent.profession] = maxi(0, int(agent.profession_experience.get(agent.profession, 0))) + 1
	movement.snap_to_floor()
	if agent.current_task_id < 0:
		_finish_zone_state()
		return   # task ended during commit (zone destroyed / cancelled)
	if committed:
		_pull_failures = 0
		_pull_exclude.clear()
	_zone_pull_next()

func _finish_zone_state() -> void:
	_zone_id = -1
	_zone_block = Vector3i(-1, -1, -1)
	_zone_stand_cells = []
	_stand_index = 0
	_swings_left = 0
	_swing_timer = 0.0
	_pull_failures = 0
	_pull_exclude.clear()
	if task_phase == DwarfAgent.TaskPhase.ZONE_MOVING or task_phase == DwarfAgent.TaskPhase.ZONE_SWINGING:
		task_phase = DwarfAgent.TaskPhase.NONE
		rig.reset_part_offsets()

func _face_cell(cell: Vector3i) -> void:
	var flat := Vector2(
		float(cell.x) + 0.5 - agent.global_position.x,
		float(cell.z) + 0.5 - agent.global_position.z)
	if flat.length_squared() > 0.0001:
		# +Z faces forward for dwarf part GLBs (see DwarfMovement.follow_path note).
		agent.rotation.y = atan2(flat.x, flat.y)

# ── UNINSTALL executor (doc 19 §3.4) ──────────────────────────────────────────

func _furniture_time(key: String) -> float:
	var config: Dictionary = TaskManager.get_config_section("furniture")
	return float(config.get(key, 2.0))


func uninstall_source() -> RefCounted:
	if _uninstall_source_id < 0:
		return null
	return TaskManager.get_work_source(_uninstall_source_id) as RefCounted


## UNINSTALL step 1: walk to the piece's stand cell.
func _uninstall_begin() -> void:
	var source := uninstall_source()
	if source == null:
		_finish_uninstall_state()
		agent.current_task_id = -1
		fail(agent.dwarf_id, "installed furniture gone")
		return
	var target: Vector3i = source.call("nearest_stand_target", agent.current_cell())
	var task := TaskManager.get_task(agent.current_task_id)
	if task != null and task.payload.has("wall_work_stand"):
		target = task.payload.wall_work_stand
		if not source.can_uninstall_from(target): target = Vector3i(-1,-1,-1)
	if target.x < 0:
		_finish_uninstall_state()
		agent.current_task_id = -1
		release(agent.dwarf_id, Task.ReleaseReason.PATH_INVALID)
		return
	if target == agent.current_cell():
		task_phase = DwarfAgent.TaskPhase.UNINSTALL_WORKING
		exec_timer = _furniture_time("uninstall_time_s")
	elif agent.walk_to(target):
		task_phase = DwarfAgent.TaskPhase.UNINSTALL_MOVING
	else:
		_finish_uninstall_state()
		agent.current_task_id = -1
		release(agent.dwarf_id, Task.ReleaseReason.PATH_INVALID)


## UNINSTALL step 2: teardown swing finished.
func _uninstall_complete() -> void:
	var source := uninstall_source()
	if source != null and source.has_method("can_uninstall_from") and not source.can_uninstall_from(agent.current_cell()):
		agent.abort_task()
		release(agent.dwarf_id,Task.ReleaseReason.PATH_INVALID)
		return
	if source == null or not commit(agent.dwarf_id,"uninstall",func(): source.complete_uninstall(agent.dwarf_id)):
		agent.abort_task()
		release(agent.dwarf_id,Task.ReleaseReason.PLAN_CHANGED)
		return
	task_phase = DwarfAgent.TaskPhase.NONE
	_uninstall_source_id = -1
	var finished_id := agent.current_task_id
	agent.current_task_id = -1
	if finished_id >= 0:
		complete(agent.dwarf_id)


## Interrupt teardown: the piece stays installed, the 📤 flag stays set —
## the lease returns to PENDING and another dwarf finishes the job.
func _finish_uninstall_state() -> void:
	_uninstall_source_id = -1
	if task_phase == DwarfAgent.TaskPhase.UNINSTALL_MOVING or task_phase == DwarfAgent.TaskPhase.UNINSTALL_WORKING:
		task_phase = DwarfAgent.TaskPhase.NONE


# ── Adjacent clearing (trees and boulders) ────────────────────────────────────────

func _fell_source() -> RefCounted:
	return TaskManager.get_work_source(_fell_source_id) as RefCounted if _fell_source_id >= 0 else null


func _fell_begin() -> void:
	var source := _fell_source()
	if source == null:
		_fell_release()
		return
	_fell_stands = source.call("reserve_work", agent.dwarf_id, agent.current_cell())
	_fell_stand_index = 0
	task_phase = DwarfAgent.TaskPhase.FELL_FINDING


## One full path request per frame, bounded by NavGrid's normal node cap.
## Try alternative trunk faces before releasing the job with retry backoff.
func _fell_try_stand() -> void:
	if _fell_stand_index >= _fell_stands.size() or _fell_source() == null:
		_fell_release()
		return
	var stand := _fell_stands[_fell_stand_index]
	_fell_stand_index += 1
	if stand == agent.current_cell():
		_begin_felling_work()
	elif agent.walk_to(stand):
		task_phase = DwarfAgent.TaskPhase.FELL_MOVING


func _begin_felling_work() -> void:
	var source := _fell_source()
	if source == null or not bool(source.call("is_work_position", agent.current_cell())):
		task_phase = DwarfAgent.TaskPhase.FELL_FINDING
		return
	task_phase = DwarfAgent.TaskPhase.FELL_WORKING
	var task := TaskManager.get_task(agent.current_task_id)
	if task != null:
		task.status = Task.Status.IN_PROGRESS
	var contact: Vector3 = source.call("chop_contact",agent.global_position)
	var direction := contact-agent.global_position
	agent.rotation.y = atan2(direction.x,direction.z)
	_fell_contact = agent.to_local(contact)
	_swing_time = FellingPose.CYCLE_SECONDS
	_swing_timer = _swing_time
	_apply_clearing_pose(0.0)


func _clearing_uses_pick() -> bool:
	var task := TaskManager.get_task(agent.current_task_id)
	return task != null and task.type == Task.Type.CLEAR_BOULDER


func _apply_clearing_pose(phase: float) -> void:
	var task := TaskManager.get_task(agent.current_task_id)
	if task != null and task.type in Task.GATHER_WORK:
		rig.carry_pose.gather(phase, _fell_contact)
	elif _clearing_uses_pick():
		rig.mining_pose.apply(phase, _fell_contact)
	elif rig.felling_pose != null:
		rig.felling_pose.apply(phase, _fell_contact)


func _process_felling(delta: float) -> void:
	var source := _fell_source()
	if source == null or not bool(source.call("is_work_position", agent.current_cell())):
		_fell_release()
		return
	# Emit once when crossing contact, including wrapped/skipped frames. A long
	# stalled frame never replays a backlog or impacts after the tree completes.
	var remaining := maxf(0,float(source.get("duration"))-float(source.get("state").get("work_seconds",0)))
	var elapsed := minf(delta,remaining)
	var before := 1.0-_swing_timer/_swing_time
	var after := before+elapsed/_swing_time
	var impact_phase := MiningPose.CONTACT_PHASE if _clearing_uses_pick() else FellingPose.CONTACT_PHASE
	if floori(after-impact_phase) > floori(before-impact_phase) \
			and agent.is_visible_in_tree() and bool(source.call("feedback_visible")):
		if _clearing_uses_pick():
			WorkFeedback.mining_impact(agent.to_global(_fell_contact), source.get("origin"),
				BlockRegistry.get_id(String(source.get("state").get("feedback_block", "base:terrain:rock:rock01"))), -agent.global_basis.z)
		elif source.get("task_type") == Task.Type.FELL_TREE:
			WorkFeedback.play_chop(agent.to_global(_fell_contact),int(source.get("origin").y))
	_swing_timer = fposmod(_swing_timer - elapsed, _swing_time)
	_apply_clearing_pose(1.0-_swing_timer/_swing_time)
	if bool(source.call("advance_work", agent.dwarf_id, delta)):
		_finish_felling_state()
		agent.current_task_id = -1
		complete(agent.dwarf_id)


func _fell_release() -> void:
	_finish_felling_state()
	agent.current_task_id = -1
	agent.stop_walking()
	release(agent.dwarf_id, Task.ReleaseReason.PATH_INVALID)


func _finish_felling_state() -> void:
	var source := _fell_source()
	if source != null:
		source.call("release_worker", agent.dwarf_id)
	_fell_source_id = -1
	_fell_stands = []
	_fell_stand_index = 0
	if task_phase in [DwarfAgent.TaskPhase.FELL_FINDING, DwarfAgent.TaskPhase.FELL_MOVING, DwarfAgent.TaskPhase.FELL_WORKING]:
		task_phase = DwarfAgent.TaskPhase.NONE
		_swing_timer = 0.0
		rig.reset_part_offsets()


# ── Supervision samples and the per-frame tick ───────────────────────────────

func sample() -> Dictionary:
	var phase: int = task_phase
	var step: String = DwarfAgent.TaskPhase.keys()[phase].to_lower()
	var unit := str(task_target)
	var remaining := 0.0
	var seconds := 1.0
	if phase==DwarfAgent.TaskPhase.FETCH_PLANNING:
		unit = str(_fetch_plan.get("stage","quote"))+str(_fetch_plan.get("material",{}).get("cell",""))
		remaining = -float(_fetch_plan.get("route_query",{}).get("expanded",0))
		seconds = 30.0
	elif not movement.move_path.is_empty():
		unit = str(movement.move_path.back())
		var point: Vector3 = agent.global_position
		for index in range(movement.move_index,movement.move_path.size()):
			var next := Vector3(movement.move_path[index])+Vector3(.5,1,.5)
			remaining += point.distance_to(next)
			point = next
		seconds = remaining / maxf(.1,agent.walk_speed*movement.carry_speed_mult*.4)
	elif phase == DwarfAgent.TaskPhase.ZONE_SWINGING:
		unit = str(_zone_block)
		remaining = maxf(0.0,(_swings_left-1)*_swing_time+_swing_timer)
		seconds = remaining
	elif phase in [DwarfAgent.TaskPhase.HAUL_PICKUP,DwarfAgent.TaskPhase.FETCH_PICKUP,
			DwarfAgent.TaskPhase.HAUL_DEPOSIT,DwarfAgent.TaskPhase.FETCH_DEPOSIT]:
		remaining = maxf(0.0,_handling_duration-_handling_elapsed)
		seconds = remaining
		unit = str(_handling_target)
	elif phase == DwarfAgent.TaskPhase.FELL_WORKING:
		var source: Object = _fell_source()
		remaining = float(source.remaining_work()) if is_instance_valid(source) and source.has_method("remaining_work") else _swing_timer
		seconds = remaining
		unit = str(_fell_source_id)
	elif phase == DwarfAgent.TaskPhase.FELL_FINDING:
		remaining = _fell_stands.size()-_fell_stand_index
	else:
		remaining = exec_timer
		seconds = remaining
		if phase == DwarfAgent.TaskPhase.FETCH_WORKING:
			var source := fetch_source()
			if source != null and source.has_method("commit_staged_build"):
				unit = str(source.target)
	if movement.move_path.is_empty() and phase not in [DwarfAgent.TaskPhase.FETCH_PLANNING,DwarfAgent.TaskPhase.FELL_FINDING]:
		seconds /= maxf(.1,agent.get_food().work_multiplier())
	return {"step":step,"unit":unit,"remaining":remaining,"expected_seconds":seconds}

## Simulation-time execution dispatch; DwarfMovement and the body rig own locomotion and poses.
func tick(delta: float) -> bool:
	# Needs slow productive labor, never navigation, meal timing or search budgets.
	var work_delta: float = delta*agent.get_food().work_multiplier()
	if agent.current_task_id >= 0 and not TaskManager.matches_attempt(agent.dwarf_id,task_id,generation):
		agent.abort_task()
		TaskManager.notify_dwarf_idle(agent.dwarf_id)
		return true
	if task_phase==DwarfAgent.TaskPhase.FETCH_PLANNING:
		var source := fetch_source()
		if source==null:
			_fetch_fail_release()
			return true
		var budget := int(TaskManager.get_config_section("supervision").get("ingredient_planning_budget_usec",250))
		var result := preload("CraftIngredientPlanner.gd").advance(source,agent,_fetch_plan,Time.get_ticks_usec()+budget)
		if result==NavGrid.ProbeResult.REACHABLE: _fetch_begin()
		elif result==NavGrid.ProbeResult.BUDGET_EXHAUSTED: _fetch_fail_release(Task.ReleaseReason.SEARCH_BUDGET_EXHAUSTED)
		elif result!=NavGrid.ProbeResult.SEARCHING: _fetch_fail_release()
		return true
	if task_phase in [DwarfAgent.TaskPhase.HAUL_PICKUP, DwarfAgent.TaskPhase.FETCH_PICKUP, DwarfAgent.TaskPhase.HAUL_DEPOSIT, DwarfAgent.TaskPhase.FETCH_DEPOSIT]:
		_process_item_handling(work_delta)
		return true
	if task_phase == DwarfAgent.TaskPhase.FELL_FINDING:
		_fell_try_stand()
		return true
	if task_phase == DwarfAgent.TaskPhase.FELL_WORKING:
		_process_felling(work_delta)
		return true
	if task_phase == DwarfAgent.TaskPhase.FELL_MOVING and not movement.move_path.is_empty() \
			and not NavGrid.is_navigable(movement.move_path[movement.move_index]):
		movement.clear_path()
		task_phase = DwarfAgent.TaskPhase.FELL_FINDING
		return true
	if task_phase == DwarfAgent.TaskPhase.ZONE_SWINGING:
		_process_swinging(work_delta)
		return true   # swing bob owns the part offsets this frame
	elif task_phase == DwarfAgent.TaskPhase.FETCH_WORKING:
		var craft := fetch_source()
		if craft != null and craft.has_method("advance_install"):
			if not craft.can_complete_build():
				_fetch_fail_release()
				return true
			var before := float(craft.progress)/ConstructionPose.CYCLE_SECONDS
			exec_timer = craft.advance_install(work_delta)
			var face: Vector3i = craft.work_facing(agent.current_cell())
			agent.rotation.y = atan2(face.x, face.z)
			if craft.has_method("commit_staged_build"):
				var contact := _construction_work_pose(craft)
				var after := float(craft.progress)/ConstructionPose.CYCLE_SECONDS
				# Actual clamped progress crosses contact once. Stalls coalesce hits;
				# resuming a partially built block cannot replay an earlier impact.
				if floori(after-ConstructionPose.CONTACT_PHASE) > floori(before-ConstructionPose.CONTACT_PHASE) \
						and agent.is_visible_in_tree():
					WorkFeedback.play_hammer(contact,int(craft.target.y))
			else:
				rig.carry_pose.gather(fposmod(float(craft.progress), 1.0), Vector3(0, 1.7, .4))
			if exec_timer <= 0.0: _fetch_complete()
			return true
		if craft != null and craft.has_method("advance_craft"):
			if not bool(craft.call("can_complete_build")):
				_fetch_fail_release()
				return true
			var before := float(craft.get("progress"))/FellingPose.CYCLE_SECONDS
			exec_timer = float(craft.call("advance_craft", work_delta))
			var after := float(craft.get("progress"))/FellingPose.CYCLE_SECONDS
			var contact := _craft_pose(craft)
			# Follow actual axe contact and clamped work progress. A stalled frame
			# emits at most one hit; resumed work never replays earlier strikes.
			if floori(after-FellingPose.CONTACT_PHASE) > floori(before-FellingPose.CONTACT_PHASE) \
					and agent.is_visible_in_tree():
				WorkFeedback.play_chop(contact,int(craft.get("work_cell").y))
			if exec_timer <= 0.0: _begin_fetch_deposit()
			return true
		if craft != null and craft.has_method("advance_plant"):
			if not craft.can_complete_build():
				_fetch_fail_release()
				return true
			exec_timer = craft.advance_plant(work_delta)
			var phase := 1.0 - exec_timer / maxf(_plant_animation_duration, .001)
			_plant_pose(craft, clampf(phase, 0.0, 1.0))
			if exec_timer <= 0.0: _fetch_complete()
			return true # Planting owns the cargo/hands; the idle hold pose must not overwrite it.
		# Ordinary furniture uses FETCH_DEPOSIT immediately on arrival. Every
		# timed source above owns both its work progress and visible animation.
		_fetch_fail_release()
		return true
	elif task_phase == DwarfAgent.TaskPhase.UNINSTALL_WORKING:
		var removal := uninstall_source()
		if removal != null and removal.has_method("advance_removal"):
			exec_timer = removal.advance_removal(work_delta, agent.dwarf_id)
			var face: Vector3i = removal.work_facing()
			agent.rotation.y = atan2(face.x, face.z)
			rig.carry_pose.gather(fposmod(float(removal.progress), 1.0), Vector3(0, 1.7, .4))
			if exec_timer <= 0.0: _uninstall_complete()
			return true
		exec_timer -= work_delta
		if exec_timer <= 0.0:
			_uninstall_complete()
	return false
