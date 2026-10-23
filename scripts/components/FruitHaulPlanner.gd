extends RefCounted

## Optional top-ups use a proven delivery route plus short out-and-back spurs.
## A missed budget only skips an optimization; the original delivery proceeds.
static func candidate(manager: ItemDropManager, key: String, material: String, route: Array[Vector3i],
		exclude: Dictionary, detour: int, deadline: int, config: Dictionary) -> Dictionary:
	if route.is_empty(): return {}
	var anchors := {}
	var radius := maxi(0, floori(detour*.5))
	var route_limit := mini(route.size(), int(config.get("fruit_route_cells",512)))
	# Index the route once, rather than expand every path cell into a corridor.
	for i in route_limit:
		if Time.get_ticks_usec() >= deadline: return {}
		if not anchors.has(route[i]): anchors[route[i]]=i
	var choices: Array[Dictionary] = []
	for item in manager._loose:
		if Time.get_ticks_usec() >= deadline: break
		if not ItemDropManager.Permission.allowed(item) or manager._reserved.has(item) or exclude.has(item): continue
		if manager.item_key_of(item)!=key or CraftMaterials.of_item(item)!=material or item.has_meta("instance_id"): continue
		var cell: Vector3i = manager.item_floor_cell(item)
		if exclude.has(cell): continue
		var stands := StorageComponent.ground_access_cells(cell)
		var best := {}
		for distance in range(radius+1):
			for stand: Vector3i in stands:
				for x in range(-distance,distance+1):
					for z in [-distance+absi(x),distance-absi(x)]:
						var point := stand+Vector3i(x,0,z)
						if anchors.has(point) and (best.is_empty() or int(anchors[point])<int(best.index)):
							best={"item":item,"stand":stand,"index":anchors[point],"distance":distance}
			if not best.is_empty(): break
		if not best.is_empty(): choices.append(best)
	choices.sort_custom(func(a: Dictionary,b: Dictionary):
		return a.index < b.index if a.index!=b.index else a.distance < b.distance)
	var probes := 0
	for choice in choices:
		if Time.get_ticks_usec() >= deadline or probes >= int(config.get("fruit_candidate_limit",16)): break
		probes += 1
		var spur: Array[Vector3i]
		var anchor: Vector3i = route[choice.index]
		if anchor==choice.stand: spur=[anchor]
		else:
			var query := {}
			var status := NavGrid.advance_reachability(query,anchor,choice.stand,
				int(config.get("fruit_probe_nodes",128)),deadline,false)
			if status != NavGrid.ProbeResult.REACHABLE: continue
			spur=query.path
		var cost := (spur.size()-1)*2
		if cost > detour: continue
		var pickup: Array[Vector3i] = route.slice(0,int(choice.index)+1)
		pickup.append_array(spur.slice(1))
		var onward: Array[Vector3i] = spur.duplicate()
		onward.reverse()
		onward.append_array(route.slice(int(choice.index)+1))
		return {"item":choice.item,"pickup":pickup,"onward":onward,"detour":cost}
	return {}
