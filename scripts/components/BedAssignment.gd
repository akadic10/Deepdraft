extends RefCounted

## Furniture owns assignments; sleeping claims remain transient and independent.
static func assign(controller: Node, piece: InstalledFurnitureComponent, dwarf_id: int) -> bool:
	if not piece.def.has("sleep_surface") or piece.flagged_uninstall: return false
	if dwarf_id < -1 or (dwarf_id>=0 and not is_instance_valid(TaskManager.get_agent(dwarf_id))): return false
	if piece.assigned_dwarf_id==dwarf_id: return true
	if dwarf_id>=0:
		for other: InstalledFurnitureComponent in controller.get_installed_pieces():
			if other!=piece and other.assigned_dwarf_id==dwarf_id:
				other.assigned_dwarf_id = -1
				RoomManager.on_bed_assignment_changed(other.origin_cell,-1)
	piece.assigned_dwarf_id = dwarf_id
	RoomManager.on_bed_assignment_changed(piece.origin_cell,dwarf_id)
	for agent: DwarfAgent in TaskManager.get_agents():
		if not is_instance_valid(agent) or not agent.is_sleeping() or agent.get_rest_behavior()==null: continue
		var current: InstalledFurnitureComponent = agent.get_rest_behavior().bed_rest.bed
		if agent.dwarf_id==dwarf_id or (current!=null and current.assigned_dwarf_id not in [-1,agent.dwarf_id]):
			agent.get_rest_behavior().begin() # Reselect a valid bed without refilling rest.
	return true

static func action(controller: Node, piece: InstalledFurnitureComponent) -> Dictionary:
	var options: Array[Dictionary] = [{"id":"assign_bed:-1","text":"Unassigned · anyone may sleep here","selected":piece.assigned_dwarf_id<0}]
	var agents: Array = TaskManager.get_agents()
	agents.sort_custom(func(a,b): return a.dwarf_name.naturalnocasecmp_to(b.dwarf_name)<0)
	for agent: DwarfAgent in agents:
		var caption := agent.dwarf_name
		for other: InstalledFurnitureComponent in controller.get_installed_pieces():
			if other!=piece and other.assigned_dwarf_id==agent.dwarf_id:
				caption += " · move assignment"
				break
		options.append({"id":"assign_bed:%d" % agent.dwarf_id,"text":caption,"selected":piece.assigned_dwarf_id==agent.dwarf_id})
	return {"id":"assign_bed","text":"Assign bed…" if piece.assigned_dwarf_id<0 else "Change bed assignment…","options":options,"disabled":piece.flagged_uninstall}
