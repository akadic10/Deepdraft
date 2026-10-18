extends RefCounted

## Execution identity and meaningful progress shared by every work family.
## Locomotion, rest and world mutation remain with their existing owners.
var task_id := -1
var generation := 0

func bind(task: Task) -> void:
	task_id = task.id
	generation = task.attempt.generation

func complete(worker_id: int) -> void:
	TaskManager.complete_dwarf_task(worker_id,task_id,generation)

func release(worker_id: int, reason: int, available := true) -> void:
	TaskManager.release_dwarf_task(worker_id,reason,available,task_id,generation)

func fail(worker_id: int, reason: String) -> void:
	TaskManager.fail_dwarf_task(worker_id,reason,task_id,generation)

func commit(worker_id: int, unit: String, operation: Callable) -> bool:
	return TaskManager.commit_step(worker_id,task_id,generation,unit,operation)

static func sample(agent: DwarfAgent) -> Dictionary:
	var phase: int = agent._task_phase
	var step: String = DwarfAgent.TaskPhase.keys()[phase].to_lower()
	var unit := str(agent._task_target)
	var remaining := 0.0
	var seconds := 1.0
	if phase==DwarfAgent.TaskPhase.FETCH_PLANNING:
		unit = str(agent._fetch_plan.get("stage","quote"))+str(agent._fetch_plan.get("material",{}).get("cell",""))
		remaining = -float(agent._fetch_plan.get("route_query",{}).get("expanded",0))
		seconds = 30.0
	elif not agent._move_path.is_empty():
		unit = str(agent._move_path.back())
		var point: Vector3 = agent.global_position
		for index in range(agent._move_index,agent._move_path.size()):
			var next := Vector3(agent._move_path[index])+Vector3(.5,1,.5)
			remaining += point.distance_to(next)
			point = next
		seconds = remaining / maxf(.1,agent.walk_speed*agent._carry_speed_mult*.4)
	elif phase == DwarfAgent.TaskPhase.ZONE_SWINGING:
		unit = str(agent._zone_block)
		remaining = maxf(0.0,(agent._swings_left-1)*agent._swing_time+agent._swing_timer)
		seconds = remaining
	elif phase in [DwarfAgent.TaskPhase.HAUL_PICKUP,DwarfAgent.TaskPhase.FETCH_PICKUP,
			DwarfAgent.TaskPhase.HAUL_DEPOSIT,DwarfAgent.TaskPhase.FETCH_DEPOSIT]:
		remaining = maxf(0.0,agent._handling_duration-agent._handling_elapsed)
		seconds = remaining
		unit = str(agent._handling_target)
	elif phase == DwarfAgent.TaskPhase.FELL_WORKING:
		var source: Object = agent._fell_source()
		remaining = float(source.remaining_work()) if is_instance_valid(source) and source.has_method("remaining_work") else agent._swing_timer
		seconds = remaining
		unit = str(agent._fell_source_id)
	elif phase == DwarfAgent.TaskPhase.FELL_FINDING:
		remaining = agent._fell_stands.size()-agent._fell_stand_index
	else:
		remaining = agent._exec_timer
		seconds = remaining
		if phase == DwarfAgent.TaskPhase.FETCH_WORKING:
			var source := agent._fetch_source()
			if source != null and source.has_method("commit_staged_build"):
				unit = str(source.target)
	if agent._move_path.is_empty() and phase not in [DwarfAgent.TaskPhase.FETCH_PLANNING,DwarfAgent.TaskPhase.FELL_FINDING]:
		seconds /= maxf(.1,agent._food.work_multiplier())
	return {"step":step,"unit":unit,"remaining":remaining,"expected_seconds":seconds}

## Simulation-time execution dispatch; the agent retains locomotion and poses.
func tick(agent: DwarfAgent, delta: float) -> bool:
	# Needs slow productive labor, never navigation, meal timing or search budgets.
	var work_delta: float = delta*agent._food.work_multiplier()
	if agent.current_task_id >= 0 and not TaskManager._matches_attempt(agent.dwarf_id,task_id,generation):
		agent.abort_task()
		TaskManager.notify_dwarf_idle(agent.dwarf_id)
		return true
	if agent._task_phase==DwarfAgent.TaskPhase.FETCH_PLANNING:
		var source := agent._fetch_source()
		if source==null:
			agent._fetch_fail_release()
			return true
		var budget := int(TaskManager.get_config_section("supervision").get("ingredient_planning_budget_usec",250))
		var result := preload("CraftIngredientPlanner.gd").advance(source,agent,agent._fetch_plan,Time.get_ticks_usec()+budget)
		if result==NavGrid.ProbeResult.REACHABLE: agent._fetch_begin()
		elif result==NavGrid.ProbeResult.BUDGET_EXHAUSTED: agent._fetch_fail_release(Task.ReleaseReason.SEARCH_BUDGET_EXHAUSTED)
		elif result!=NavGrid.ProbeResult.SEARCHING: agent._fetch_fail_release()
		return true
	if agent._task_phase in [DwarfAgent.TaskPhase.HAUL_PICKUP, DwarfAgent.TaskPhase.FETCH_PICKUP, DwarfAgent.TaskPhase.HAUL_DEPOSIT, DwarfAgent.TaskPhase.FETCH_DEPOSIT]:
		agent._process_item_handling(work_delta)
		return true
	if agent._task_phase == DwarfAgent.TaskPhase.FELL_FINDING:
		agent._fell_try_stand()
		return true
	if agent._task_phase == DwarfAgent.TaskPhase.FELL_WORKING:
		agent._process_felling(work_delta)
		return true
	if agent._task_phase == DwarfAgent.TaskPhase.FELL_MOVING and not agent._move_path.is_empty() \
			and not NavGrid.is_navigable(agent._move_path[agent._move_index]):
		agent._clear_path()
		agent._task_phase = DwarfAgent.TaskPhase.FELL_FINDING
		return true
	if agent._task_phase == DwarfAgent.TaskPhase.EXECUTING:
		agent._exec_timer -= work_delta
		if agent._exec_timer <= 0.0:
			agent._task_phase = DwarfAgent.TaskPhase.NONE
			var finished_id := agent.current_task_id
			agent.current_task_id = -1
			if finished_id >= 0:
				agent._work_execution.complete(agent.dwarf_id)
	elif agent._task_phase == DwarfAgent.TaskPhase.ZONE_SWINGING:
		agent._process_swinging(work_delta)
		return true   # swing bob owns the part offsets this frame
	elif agent._task_phase == DwarfAgent.TaskPhase.FETCH_WORKING:
		var craft := agent._fetch_source()
		if craft != null and craft.has_method("advance_install"):
			if not craft.can_complete_build():
				agent._fetch_fail_release()
				return true
			var before := float(craft.progress)/DwarfAgent.ConstructionPose.CYCLE_SECONDS
			agent._exec_timer = craft.advance_install(work_delta)
			var face: Vector3i = craft.work_facing(agent.current_cell())
			agent.rotation.y = atan2(face.x, face.z)
			if craft.has_method("commit_staged_build"):
				var contact := agent._construction_work_pose(craft)
				var after := float(craft.progress)/DwarfAgent.ConstructionPose.CYCLE_SECONDS
				# Actual clamped progress crosses contact once. Stalls coalesce hits;
				# resuming a partially built block cannot replay an earlier impact.
				if floori(after-DwarfAgent.ConstructionPose.CONTACT_PHASE) > floori(before-DwarfAgent.ConstructionPose.CONTACT_PHASE) \
						and agent.is_visible_in_tree():
					WorkFeedback.play_hammer(contact,int(craft.target.y))
			else:
				agent._carry_pose.gather(fposmod(float(craft.progress), 1.0), Vector3(0, 1.7, .4))
			if agent._exec_timer <= 0.0: agent._fetch_complete()
			return true
		if craft != null and craft.has_method("advance_craft"):
			if not bool(craft.call("can_complete_build")):
				agent._fetch_fail_release()
				return true
			var before := float(craft.get("progress"))/DwarfAgent.FellingPose.CYCLE_SECONDS
			agent._exec_timer = float(craft.call("advance_craft", work_delta))
			var after := float(craft.get("progress"))/DwarfAgent.FellingPose.CYCLE_SECONDS
			var contact := agent._craft_pose(craft)
			# Follow actual axe contact and clamped work progress. A stalled frame
			# emits at most one hit; resumed work never replays earlier strikes.
			if floori(after-DwarfAgent.FellingPose.CONTACT_PHASE) > floori(before-DwarfAgent.FellingPose.CONTACT_PHASE) \
					and agent.is_visible_in_tree():
				WorkFeedback.play_chop(contact,int(craft.get("work_cell").y))
			if agent._exec_timer <= 0.0: agent._begin_fetch_deposit()
			return true
		if craft != null and craft.has_method("advance_plant"):
			if not craft.can_complete_build():
				agent._fetch_fail_release()
				return true
			agent._exec_timer = craft.advance_plant(work_delta)
			var phase := 1.0 - agent._exec_timer / maxf(agent._plant_animation_duration, .001)
			agent._plant_pose(craft, clampf(phase, 0.0, 1.0))
			if agent._exec_timer <= 0.0: agent._fetch_complete()
			return true # Planting owns the cargo/hands; the idle hold pose must not overwrite it.
		# Ordinary furniture uses FETCH_DEPOSIT immediately on arrival. Every
		# timed source above owns both its work progress and visible animation.
		agent._fetch_fail_release()
		return true
	elif agent._task_phase == DwarfAgent.TaskPhase.UNINSTALL_WORKING:
		var removal := agent._uninstall_source()
		if removal != null and removal.has_method("advance_removal"):
			agent._exec_timer = removal.advance_removal(work_delta, agent.dwarf_id)
			var face: Vector3i = removal.work_facing()
			agent.rotation.y = atan2(face.x, face.z)
			agent._carry_pose.gather(fposmod(float(removal.progress), 1.0), Vector3(0, 1.7, .4))
			if agent._exec_timer <= 0.0: agent._uninstall_complete()
			return true
		agent._exec_timer -= work_delta
		if agent._exec_timer <= 0.0:
			agent._uninstall_complete()
	return false
