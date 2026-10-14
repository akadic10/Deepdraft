extends RefCounted

## Read-only, resumable two-leg planning. No physical claim changes until both
## legs have a proof. Alternative supplies and every legal work side participate.
static func advance(source: FurnitureGhostComponent, worker: DwarfAgent, context: Dictionary,
		node_budget: int, deadline: int) -> int:
	var from := worker.current_cell()
	if context.is_empty() or context.get("from") != from or not dependencies_current(context) or int(context.get("stock_revision",-1)) != StockpileManager.hauling_revision:
		context.clear()
		context.merge({"from":from,"excluded":{},"loose":{},"stored":{},"stage":"quote","route_dependencies":{},"ladder_revision":NavGrid.ladder_revision})
		context["stock_revision"] = StockpileManager.hauling_revision
	while Time.get_ticks_usec() < deadline:
		if context.stage == "quote":
			if not is_instance_valid(source.drop_manager): return NavGrid.ProbeResult.UNREACHABLE
			var keys: Array[String] = [source.item_key]
			if not source.drop_manager.advance_material_quote(keys,from,context.loose,deadline,context.excluded,
					source.claim_owner_id(),source.required_material_id,source.required_instance_id,false): return NavGrid.ProbeResult.SEARCHING
			if not StockpileManager.advance_material_quote(keys,from,context.stored,deadline,context.excluded,
					source.claim_owner_id(),source.required_material_id,source.required_instance_id): return NavGrid.ProbeResult.SEARCHING
			var quote: Dictionary = context.loose.best
			if quote.is_empty() or (not context.stored.best.is_empty() and context.stored.best.distance < quote.distance): quote = context.stored.best
			if quote.is_empty():
				if bool(context.get("unknown",false)):
					context["reason"] = "Route search budget exhausted; reachability unknown"
					return NavGrid.ProbeResult.BUDGET_EXHAUSTED
				context["reason"] = "No reachable matching supply" if not context.excluded.is_empty() else "Waiting for matching supplies"
				return NavGrid.ProbeResult.UNREACHABLE
			context["material"] = quote
			context["stage"] = "pickup"
			context["route_query"] = {}
		var goals := {}
		var start: Vector3i = from
		if context.stage == "pickup":
			for cell: Vector3i in StorageComponent.ground_access_cells(context.material.cell):
				if NavGrid.is_walkable(cell): goals[cell] = true
		else:
			start = context.pickup_stand
			for cell: Vector3i in source.work_stands(start): goals[cell] = true
		var result := NavGrid.ProbeResult.UNREACHABLE
		if not goals.is_empty():
			result = preload("res://scripts/components/WorkRouteProbe.gd").advance(context.route_query,start,goals.keys()[0],node_budget,deadline,false,goals) as NavGrid.ProbeResult
			context.route_dependencies.merge(context.route_query.get("chunks",{}))
		if result == NavGrid.ProbeResult.SEARCHING: return result
		if result != NavGrid.ProbeResult.REACHABLE:
			if result == NavGrid.ProbeResult.BUDGET_EXHAUSTED: context["unknown"] = true
			context.excluded[context.material.cell] = true
			context.stage = "quote"
			context.loose = {}
			context.stored = {}
			context.erase("route_query")
			# One search slice per scheduler probe, even after a failed leg.
			return NavGrid.ProbeResult.SEARCHING
		if context.stage == "pickup":
			context["pickup_stand"] = context.route_query.path.back()
			context["pickup_route"] = context.route_query
			context.route_query = {}
			context.stage = "delivery"
			return NavGrid.ProbeResult.SEARCHING
		context["delivery_stand"] = context.route_query.path.back()
		context["dwarf_id"] = worker.dwarf_id
		NavGrid.remember_reachable_path(context.pickup_route)
		NavGrid.remember_reachable_path(context.route_query)
		source.prefer_fetch_plan(context.duplicate())
		return NavGrid.ProbeResult.REACHABLE
	return NavGrid.ProbeResult.SEARCHING

static func dependencies_current(context: Dictionary) -> bool:
	var dependencies: Dictionary = context.get("route_dependencies",{})
	return dependencies.is_empty() or NavGrid.search_is_current({"chunks":dependencies,"revision":-1,"ladder_revision":context.get("ladder_revision",NavGrid.ladder_revision)})
