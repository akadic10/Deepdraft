extends RefCounted

## Later ingredients use the same read-only pickup/delivery proof as the first.
## The batch keeps its staged physical goods and bench while this bounded step
## searches; interruption returns them through WorkerCraftOrder.cancel_fetch.
static func advance(order: RefCounted, worker: DwarfAgent, context: Dictionary, deadline: int) -> int:
	var from := worker.current_cell()
	if context.is_empty() or not preload("FurnitureFetchPlanner.gd").dependencies_current(context):
		context.clear()
		context.merge({"stage":"quote","excluded":{},"loose":{},"stored":{},"route_dependencies":{},"ladder_revision":NavGrid.ladder_revision})
		context["keys"] = order.next_ingredient_keys()
	if context.stage=="quote":
		var keys: Array[String] = context.keys
		if not order.manager.items.advance_material_quote(keys,from,context.loose,deadline,context.excluded): return NavGrid.ProbeResult.SEARCHING
		if not StockpileManager.advance_material_quote(keys,from,context.stored,deadline,context.excluded): return NavGrid.ProbeResult.SEARCHING
		var quote: Dictionary = context.loose.best
		if quote.is_empty() or (not context.stored.best.is_empty() and context.stored.best.distance<quote.distance): quote = context.stored.best
		if quote.is_empty(): return NavGrid.ProbeResult.BUDGET_EXHAUSTED if bool(context.get("unknown",false)) else NavGrid.ProbeResult.UNREACHABLE
		context["material"] = quote
		context.stage = "pickup"
		context["route_query"] = {}
	var goals := {}
	var start := from
	if context.stage=="pickup":
		for cell: Vector3i in StorageComponent.ground_access_cells(context.material.cell):
			if NavGrid.is_walkable(cell): goals[cell] = true
	else:
		start = context.pickup_stand
		if order.bench_id<0: goals[start] = true
		elif order.manager.bench_valid(order.bench_id,order.id):
			for cell: Vector3i in order.manager.furniture._installed[order.bench_id].cells:
				for offset: Vector3i in [Vector3i.LEFT,Vector3i.RIGHT,Vector3i.FORWARD,Vector3i.BACK]:
					if NavGrid.is_walkable(cell+offset): goals[cell+offset] = true
	var result := NavGrid.ProbeResult.UNREACHABLE
	if not goals.is_empty():
		var nodes := int(TaskManager.get_config_section("supervision").get("ingredient_planning_node_cap",32))
		result = preload("WorkRouteProbe.gd").advance(context.route_query,start,goals.keys()[0],nodes,deadline,false,goals) as NavGrid.ProbeResult
	context.route_dependencies.merge(context.route_query.get("chunks",{}))
	if result==NavGrid.ProbeResult.SEARCHING: return result
	if result!=NavGrid.ProbeResult.REACHABLE:
		context["unknown"] = bool(context.get("unknown",false)) or result==NavGrid.ProbeResult.BUDGET_EXHAUSTED
		context.excluded[context.material.cell] = true
		context.stage = "quote"
		context.loose = {}
		context.stored = {}
		return NavGrid.ProbeResult.SEARCHING
	if context.stage=="pickup":
		context["pickup_stand"] = context.route_query.path.back()
		context["pickup_route"] = context.route_query
		context.route_query = {}
		context.stage = "delivery"
		return NavGrid.ProbeResult.SEARCHING
	context["delivery_stand"] = context.route_query.path.back()
	context["dwarf_id"] = worker.dwarf_id
	context["from"] = from
	NavGrid.remember_reachable_path(context.pickup_route)
	NavGrid.remember_reachable_path(context.route_query)
	order.prefer_fetch_plan(context.duplicate())
	return result
