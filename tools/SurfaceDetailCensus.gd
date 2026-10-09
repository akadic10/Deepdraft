extends RefCounted

## Read-only measurements from the real accepted layout, not a second sampler.
static func summarize(owner: Node) -> Dictionary:
	var registry: Node = owner.get_node("/root/SurfaceDetailRegistry")
	var generator: Node = owner.get_node("/root/WorldGenerator")
	var blocks: Node = owner.get_node("/root/BlockRegistry")
	var categories: Dictionary = {}
	var regions: Dictionary = {}
	var footprint_cells := 0
	var blocked_cells := 0
	for record: Dictionary in owner._records.values():
		var definition: Dictionary = registry.get_definition(record.definition)
		var category := String(definition.category)
		if not categories.has(category):
			categories[category] = {"count":0,"support_cells":0,"min_y":127,"max_y":0,"ground":{},"habitats":{}}
		var entry: Dictionary = categories[category]
		var cells := int(definition.footprint) * int(definition.footprint)
		entry.count += 1
		entry.support_cells += cells
		entry.min_y = mini(entry.min_y,record.origin.y)
		entry.max_y = maxi(entry.max_y,record.origin.y)
		var kind := String(blocks.get_def(blocks.get_key(generator.get_generated_block_id(record.origin.x,record.origin.y,record.origin.z))).get("kind",""))
		entry.ground[kind] = int(entry.ground.get(kind,0)) + 1
		entry.habitats[record.habitat] = int(entry.habitats.get(record.habitat,0)) + 1
		footprint_cells += cells
		if bool(definition.get("blocking",false)): blocked_cells += cells
		var region := Vector2i(record.origin.x/64,record.origin.z/64)
		if not regions.has(region): regions[region] = {"count":0,"support_cells":0,"categories":{},"height_sum":0}
		var local: Dictionary = regions[region]
		local.count += 1
		local.support_cells += cells
		local.height_sum += record.origin.y
		local.categories[category] = int(local.categories.get(category,0)) + 1
	var counts: Array[int] = []
	var densest := Vector2i.ZERO
	var largest := 0
	var max_cells := 0
	for x in range(16):
		for z in range(16):
			var region := Vector2i(x,z)
			var local: Dictionary = regions.get(region,{})
			var count := int(local.get("count",0))
			counts.append(count)
			max_cells = maxi(max_cells,int(local.get("support_cells",0)))
			if count > largest:
				largest = count
				densest = region
	counts.sort()
	var targets: Dictionary = {}
	var dense: Dictionary = regions.get(densest,{})
	if not dense.is_empty():
		targets["dense"] = {"position":[densest.x*64+32,float(dense.height_sum)/dense.count+1,densest.y*64+32],"zoom":100.0,"region_categories":dense.categories}
	for pair: Array in [["cliff","scree",70.0],["mountain","boulder",90.0],["shore","reeds",70.0]]:
		var best := -INF
		var selected: Dictionary = {}
		for record: Dictionary in owner._records.values():
			if String(registry.get_definition(record.definition).category) != pair[1]: continue
			var region := Vector2i(record.origin.x/64,record.origin.z/64)
			var local: Dictionary = regions[region]
			var score: float = float(local.count) + local.categories.size()*5
			if pair[0] == "mountain": score += record.origin.y * 2
			if score <= best: continue
			best = score
			selected = record
		if not selected.is_empty():
			targets[pair[0]] = {"position":[selected.origin.x+.5,selected.origin.y+1,selected.origin.z+.5],"zoom":pair[2],"id":selected.id}
	targets["wide"] = {"position":[512,generator.get_surface_y(512,512)+1,512],"zoom":180.0}
	return {"categories":categories,"support_cells":footprint_cells,"support_percent_map":footprint_cells/10485.76,
		"blocking_cells":blocked_cells,"blocking_percent_map":blocked_cells/10485.76,
		"regions64":{"min_clumps":counts[0],"median_clumps":counts[128],"p95_clumps":counts[243],"max_clumps":largest,
			"max_support_percent":max_cells/40.96,"empty_regions":counts.count(0)},"targets":targets}
