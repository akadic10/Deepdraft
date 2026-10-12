extends RefCounted

## Unknown after a finite search is not proof of disconnection. Escalate the
## total search allowance twice, retaining the frontier and per-wake CPU cap.
static func advance(query: Dictionary, from: Vector3i, goal: Vector3i, nodes: int,
		deadline: int, adjacent := true, goals: Dictionary = {}) -> int:
	if int(query.get("status",-1)) == NavGrid.ProbeResult.BUDGET_EXHAUSTED:
		var limit := int(query.get("search_limit",NavGrid.DEFAULT_MAX_NODES))
		var maximum := int(TaskManager.get_config_section("supervision").get("maximum_search_nodes",24000))
		if limit < maximum:
			query.search_limit = mini(limit*2,maximum)
			query.status = NavGrid.ProbeResult.SEARCHING
	var result := NavGrid.advance_reachability(query,from,goal,nodes,deadline,adjacent,goals)
	if result == NavGrid.ProbeResult.BUDGET_EXHAUSTED \
			and int(query.get("search_limit",NavGrid.DEFAULT_MAX_NODES)) < int(TaskManager.get_config_section("supervision").get("maximum_search_nodes",24000)):
		return NavGrid.ProbeResult.SEARCHING
	return result
