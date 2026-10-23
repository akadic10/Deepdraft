extends RefCounted

## Generation metrics for WorldGenerator: domain shares, heights, top-surface
## coverage, water and layout summaries, and the startup report. Built once on
## the generator thread after maps_ready from the finished, read-only maps; the
## result is a new Dictionary, so nothing here is shared or mutable.

const WorldSize = preload("res://scripts/systems/WorldSize.gd")
const WORLD_SIZE_X: int = WorldSize.WORLD_SIZE_X
const WORLD_SIZE_Y: int = WorldSize.WORLD_SIZE_Y
const WORLD_SIZE_Z: int = WorldSize.WORLD_SIZE_Z
const BlockFill = preload("res://scripts/components/WorldBlockFill.gd")


## `generator` is WorldGenerator; the other arguments are its private layout
## state at the time of the call.
static func build(generator: Node, domain_counts: Dictionary, layout_profile: Dictionary,
		macro_layout: Dictionary, layout_validation: Dictionary) -> Dictionary:
	var total_columns := WORLD_SIZE_X * WORLD_SIZE_Z
	var lake_waterline := int(layout_profile["lowland_lake"]["waterline_y"])
	var lake_floor := _water_floor_metrics(generator, generator.lake_columns, lake_waterline)
	var tarn_floor := _water_floor_metrics(generator, generator.tarn_columns, generator.tarn_waterline)
	var cave_layout: Dictionary = generator.cave_layout()
	return {
		"seed": generator.world_seed,
		"world_size": Vector3i(WORLD_SIZE_X, WORLD_SIZE_Y, WORLD_SIZE_Z),
		"domains": {
			"mountain": domain_counts.get("mountain", 0),
			"valley": domain_counts.get("valley", 0),
			"lowland": domain_counts.get("lowland", 0),
			"mountain_pct": pct(domain_counts.get("mountain", 0), total_columns),
			"valley_pct": pct(domain_counts.get("valley", 0), total_columns),
			"lowland_pct": pct(domain_counts.get("lowland", 0), total_columns),
		},
		"heights": _compute_height_metrics(generator),
		"surface": compute_surface_metrics(generator),
		"macro": _compute_macro_layout_metrics(layout_profile, macro_layout, layout_validation),
		"caves": {"systems": cave_layout["systems"].size(), "floor_columns": cave_layout["columns"].size()},
		"water": {
			"lake_center": generator.lake_center,
			"lake_waterline": lake_waterline,
			"lake_columns": generator.lake_columns.size(),
			"lake_floor_min": lake_floor.get("floor_min", 0),
			"lake_floor_max": lake_floor.get("floor_max", 0),
			"lake_depth_max": lake_floor.get("depth_max", 0),
			"tarn_center": generator.tarn_center,
			"tarn_waterline": generator.tarn_waterline,
			"tarn_columns": generator.tarn_columns.size(),
			"tarn_floor_min": tarn_floor.get("floor_min", 0),
			"tarn_floor_max": tarn_floor.get("floor_max", 0),
			"tarn_depth_max": tarn_floor.get("depth_max", 0),
			"bank_columns": generator.water_bank_columns.size(),
			"bodies": generator.water_bodies.duplicate(true),
		},
	}


static func _water_floor_metrics(generator: Node, columns: Dictionary, waterline: int) -> Dictionary:
	if columns.is_empty():
		return {"floor_min": 0, "floor_max": 0, "depth_max": 0}
	var heightmap: PackedInt32Array = generator.heightmap
	var floor_min := WORLD_SIZE_Y
	var floor_max := 0
	for col_variant: Variant in columns.keys():
		var col := col_variant as Vector2i
		var floor_y: int = heightmap[col.x * WORLD_SIZE_Z + col.y]
		floor_min = mini(floor_min, floor_y)
		floor_max = maxi(floor_max, floor_y)
	return {
		"floor_min": floor_min,
		"floor_max": floor_max,
		"depth_max": maxi(0, waterline - floor_min),
	}


static func _compute_height_metrics(generator: Node) -> Dictionary:
	var heightmap: PackedInt32Array = generator.heightmap
	var domain_map: PackedInt32Array = generator.domain_map
	var total_columns := WORLD_SIZE_X * WORLD_SIZE_Z
	var min_h := WORLD_SIZE_Y
	var max_h := 0
	var sum_h := 0
	var by_domain := {
		"mountain": _new_height_bucket(),
		"valley": _new_height_bucket(),
		"lowland": _new_height_bucket(),
	}

	for x in range(WORLD_SIZE_X):
		for z in range(WORLD_SIZE_Z):
			var idx := x * WORLD_SIZE_Z + z
			var h: int = heightmap[idx]
			min_h = mini(min_h, h)
			max_h = maxi(max_h, h)
			sum_h += h

			var bucket: Dictionary = by_domain[domain_label(domain_map[idx])]
			bucket["count"] = (bucket.get("count", 0) as int) + 1
			bucket["min"] = mini(bucket.get("min", WORLD_SIZE_Y) as int, h)
			bucket["max"] = maxi(bucket.get("max", 0) as int, h)
			bucket["sum"] = (bucket.get("sum", 0) as int) + h

	for key: String in by_domain.keys():
		var bucket: Dictionary = by_domain[key]
		var count := bucket.get("count", 0) as int
		bucket["avg"] = float(bucket.get("sum", 0) as int) / float(maxi(count, 1))
		bucket.erase("sum")

	return {
		"min": min_h,
		"max": max_h,
		"avg": float(sum_h) / float(maxi(total_columns, 1)),
		"by_domain": by_domain,
	}


## One top visible generated block per column, including water above its bed.
## This measures plan-view coverage, not exposed cliff area or material volume.
static func compute_surface_metrics(generator: Node) -> Dictionary:
	var heightmap: PackedInt32Array = generator.heightmap
	var waterline_map: PackedInt32Array = generator.waterline_map
	var domain_map: PackedInt32Array = generator.domain_map
	var fill: BlockFill = generator.block_fill
	var counts := {
		"grass": 0,
		"dirt": 0,
		"rock": 0,
		"water": 0,
		"other": 0,
	}
	var total_columns := WORLD_SIZE_X * WORLD_SIZE_Z
	var by_domain := {
		"mountain": _new_surface_bucket(),
		"valley": _new_surface_bucket(),
		"lowland": _new_surface_bucket(),
	}

	for x in range(WORLD_SIZE_X):
		for z in range(WORLD_SIZE_Z):
			var idx := x * WORLD_SIZE_Z + z
			var visible_y := maxi(heightmap[idx], waterline_map[idx])
			var block_id := fill.generate_block_id(x, visible_y, z)
			var category := _surface_category(fill, block_id)
			counts[category] = (counts[category] as int) + 1
			var bucket: Dictionary = by_domain[domain_label(domain_map[idx])]
			bucket[category] = (bucket[category] as int) + 1
			bucket["total"] = (bucket["total"] as int) + 1

	for key: String in by_domain.keys():
		_add_surface_bucket_percentages(by_domain[key])

	return {
		"total": total_columns,
		"grass": counts["grass"],
		"dirt": counts["dirt"],
		"rock": counts["rock"],
		"water": counts["water"],
		"other": counts["other"],
		"grass_pct": pct(counts["grass"] as int, total_columns),
		"dirt_pct": pct(counts["dirt"] as int, total_columns),
		"rock_pct": pct(counts["rock"] as int, total_columns),
		"water_pct": pct(counts["water"] as int, total_columns),
		"other_pct": pct(counts["other"] as int, total_columns),
		"by_domain": by_domain,
	}


static func _compute_macro_layout_metrics(layout_profile: Dictionary, macro_layout: Dictionary,
		layout_validation: Dictionary) -> Dictionary:
	return {"profile_id": layout_profile.get("profile_id", ""),
		"attempts": macro_layout.get("attempts", 0), "used_fallback": macro_layout.get("used_fallback", false),
		"macro": macro_layout.get("metrics", {}).duplicate(true), "finished": layout_validation.duplicate(true)}


static func _new_height_bucket() -> Dictionary:
	return {"count": 0, "min": WORLD_SIZE_Y, "max": 0, "sum": 0}


static func _new_surface_bucket() -> Dictionary:
	return {"grass": 0, "dirt": 0, "rock": 0, "water": 0, "other": 0, "total": 0}


static func _add_surface_bucket_percentages(bucket: Dictionary) -> void:
	var total := bucket.get("total", 0) as int
	bucket["grass_pct"] = pct(bucket.get("grass", 0) as int, total)
	bucket["dirt_pct"] = pct(bucket.get("dirt", 0) as int, total)
	bucket["rock_pct"] = pct(bucket.get("rock", 0) as int, total)
	bucket["water_pct"] = pct(bucket.get("water", 0) as int, total)
	bucket["other_pct"] = pct(bucket.get("other", 0) as int, total)


static func _surface_category(fill: BlockFill, block_id: int) -> String:
	if fill.grass_ids.has(block_id):
		return "grass"
	if fill.dirt_ids.has(block_id):
		return "dirt"
	if block_id == fill.id_water:
		return "water"
	if block_id == fill.id_rock07 or block_id == fill.id_rock08 or block_id == fill.id_rock09 or block_id == fill.id_rock10 or block_id == fill.id_rock11 or fill.mountain_rock_ids.has(block_id):
		return "rock"
	return "other"


static func domain_label(domain: int) -> String:
	match domain:
		BlockFill.DOMAIN_MOUNTAIN:
			return "mountain"
		BlockFill.DOMAIN_VALLEY:
			return "valley"
	return "lowland"


static func pct(value: int, total: int) -> float:
	if total <= 0:
		return 0.0
	return float(value) / float(total) * 100.0


## Main thread: prints the startup summary of a build() snapshot.
static func print_report(snapshot: Dictionary) -> void:
	var domains: Dictionary = snapshot.get("domains", {})
	var heights: Dictionary = snapshot.get("heights", {})
	var surface: Dictionary = snapshot.get("surface", {})
	var water: Dictionary = snapshot.get("water", {})
	var macro: Dictionary = snapshot.get("macro", {})
	var finished: Dictionary = macro.get("finished", {})

	print("WorldGenerator metrics:")
	print("  domains: mountain %.1f%%, valley %.1f%%, lowland %.1f%%" % [
		domains.get("mountain_pct", 0.0),
		domains.get("valley_pct", 0.0),
		domains.get("lowland_pct", 0.0),
	])
	print("  height: min %d, max %d, avg %.1f" % [
		heights.get("min", 0),
		heights.get("max", 0),
		heights.get("avg", 0.0),
	])
	print("  top surface: grass %.1f%%, dirt %.1f%%, rock %.1f%%, water %.1f%%" % [
		surface.get("grass_pct", 0.0),
		surface.get("dirt_pct", 0.0),
		surface.get("rock_pct", 0.0),
		surface.get("water_pct", 0.0),
	])
	var surface_by_domain: Dictionary = surface.get("by_domain", {})
	var mountain_surface: Dictionary = surface_by_domain.get("mountain", {})
	var valley_surface: Dictionary = surface_by_domain.get("valley", {})
	print("  surface domains: mountain rock %.1f%%; valley grass %.1f%% dirt %.1f%% rock %.1f%%" % [
		mountain_surface.get("rock_pct", 0.0),
		valley_surface.get("grass_pct", 0.0),
		valley_surface.get("dirt_pct", 0.0),
		valley_surface.get("rock_pct", 0.0),
	])
	print("  finished terrain: summit %d columns, detailed %d, dry shore %d" % [
		finished.get("summit_columns", 0),
		finished.get("detailed_columns", 0),
		finished.get("shore_land_columns", 0),
	])
	print("  water: lake %s y%d floor %d-%d depth %d columns %d; tarn %s y%d floor %d-%d depth %d columns %d; banks %d" % [
		str(water.get("lake_center", Vector2i.ZERO)),
		water.get("lake_waterline", 0),
		water.get("lake_floor_min", 0),
		water.get("lake_floor_max", 0),
		water.get("lake_depth_max", 0),
		water.get("lake_columns", 0),
		str(water.get("tarn_center", Vector2i.ZERO)),
		water.get("tarn_waterline", 0),
		water.get("tarn_floor_min", 0),
		water.get("tarn_floor_max", 0),
		water.get("tarn_depth_max", 0),
		water.get("tarn_columns", 0),
		water.get("bank_columns", 0),
	])
	print("  layout: %s; attempts %d; fallback %s" % [
		macro.get("profile_id", ""), macro.get("attempts", 0), macro.get("used_fallback", false)])
