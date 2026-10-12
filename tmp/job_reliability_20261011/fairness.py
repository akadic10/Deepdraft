from pathlib import Path
p=Path('scripts/systems/TaskManager.gd');s=p.read_text(encoding='utf-8')
# Specialized matchers still own quotes/ranking. Give each a bounded quantum,
# storing its exact frontier before moving to the next pending lease.
s+='''
func _assign_specialized_bucket(type: int, probes_left: int, t_start: int) -> int:
	var ids: Array = _pending.get(type,[])
	var selected: Task
	var cursor := int(_scan_cursor.get(type,0))
	for offset in range(ids.size()):
		var next: Task = _tasks.get(ids[(cursor+offset)%ids.size()])
		if next != null and next.is_available(Time.get_ticks_msec()):
			selected = next
			_scan_cursor[type] = (cursor+offset)%ids.size()
			break
	if selected == null: return probes_left
	var context: Dictionary = _family_frontiers.get(selected.id,{})
	if not FetchPlanner.dependencies_current(context): context.clear()
	context["task_id"] = selected.id
	if type == Task.Type.HAUL:
		_haul_match = context
		probes_left = _try_assign_hauls(probes_left,t_start)
		context = _haul_match
	elif type == Task.Type.CRAFT:
		_craft_match = context
		probes_left = _try_assign_crafts(probes_left,t_start)
		context = _craft_match
	else:
		_surface_match = context
		probes_left = _try_assign_surface(type,probes_left,t_start)
		context = _surface_match
	var retained: Task = _tasks.get(int(context.get("task_id",-1)))
	if retained != null and retained.status == Task.Status.PENDING:
		_family_frontiers[retained.id] = context
		_family_quanta[retained.id] = int(_family_quanta.get(retained.id,0))+1
		if int(_family_quanta[retained.id]) >= int(get_config_section("supervision").get("planning_quantum_slices",8)):
			_family_quanta[retained.id] = 0
			_scan_cursor[type] = maxi(0,(_pending.get(type,[]) as Array).find(retained.id))+1
	return probes_left

## Missed availability notifications cannot permanently lose a registered
## worker. This inspects a bounded subset, never scans world objects.
func _reconcile_workers() -> void:
	var ids := _agents.keys()
	for unused in range(mini(ids.size(),4)):
		var id: int = ids[_reconcile_cursor%ids.size()]
		_reconcile_cursor += 1
		var agent: DwarfAgent = _agents.get(id)
		if not is_instance_valid(agent):
			deregister_dwarf(id)
			continue
		if _active.has(id):
			_remove_idle(id)
			continue
		if agent.current_task_id >= 0:
			# An orphan executor must relinquish its real cargo before rejoining.
			agent.abort_task()
		if agent.is_sleeping() or agent.promotion_pending() or agent.needs_bridge_exit() or agent.needs_ladder_exit():
			_remove_idle(id)
		elif not id in _idle_dwarves:
			_mark_idle(id)

## Read-only contract checks for fault tests and development diagnostics.
func lifecycle_errors() -> Array[String]:
	var errors: Array[String] = []
	for id: int in _active:
		var task := get_task(int(_active[id]))
		var agent: DwarfAgent = _agents.get(id)
		if task == null or task.assigned_to != id: errors.append("Active worker has no matching lease: %d"%id)
		elif task.attempt == null or task.attempt.worker_id != id: errors.append("Missing attempt identity: %d"%id)
		if not is_instance_valid(agent) or agent.current_task_id != int(_active[id]): errors.append("Executor disagrees with lease: %d"%id)
		if id in _idle_dwarves: errors.append("Working actor also idle: %d"%id)
	for task: Task in _tasks.values():
		if task.assigned_to >= 0 and int(_active.get(task.assigned_to,-1)) != task.id: errors.append("Orphan assigned lease: %d"%task.id)
	return errors
'''
# Holds only cancel ordinary leisure. Existing dev/sleep/exit control wins.
for name, end in [('_try_assign_move','_try_assign_crafts'),('_try_assign_crafts','_advance_craft_probe'),('_try_assign_surface','_try_assign_hauls'),('_try_assign_hauls','_restart_haul_ranking')]:
 a=s.index('func '+name+'(');b=s.index('func '+end+'(',a)
 part=s[a:b].replace('var from := agent.current_cell()', 'hold_for_planning(agent)\n\t\t\tvar from := agent.current_cell()' if name!='_try_assign_move' else 'hold_for_planning(agent)\n\t\tvar from := agent.current_cell()')
 part=part.replace('var from := candidate_agent.current_cell()', 'hold_for_planning(candidate_agent)\n\t\t\tvar from := candidate_agent.current_cell()')
 s=s[:a]+part+s[b:]
p.write_text(s,encoding='utf-8')
