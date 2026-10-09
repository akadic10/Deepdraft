extends RefCounted

## Independent checks over completed macro maps. Never repairs the generator's
## output. Water floors are checked separately from the surrounding shelf ranks.
const CARDINAL: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
const SHELVES := [19, 27, 35, 43, 55, 67, 79, 91, 103, 115]


static func profile_errors(profile: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	for key in ["profile_id", "algorithm_version", "macro_count", "macro_size", "shelf_tops", "max_attempts",
			"primary", "secondary", "requirements", "lowland_lake", "mountain_tarn", "edge_detail"]:
		if not profile.has(key): errors.append("Missing profile field: " + key)
	if not errors.is_empty(): return errors
	if int(profile["algorithm_version"]) != 1 or int(profile["macro_count"]) != 32 or int(profile["macro_size"]) != 32:
		errors.append("Layout v1 supports only the current 32 x 32 plates of 32 blocks.")
	# JSON numbers arrive as floats; compare the numeric entries, not Array
	# equality (which distinguishes the parsed floats from integer constants).
	var shelves: Array = profile["shelf_tops"]
	var matching_shelves := shelves.size() == SHELVES.size()
	for i in range(mini(shelves.size(), SHELVES.size())):
		if float(shelves[i]) != float(SHELVES[i]): matching_shelves = false
	if not matching_shelves: errors.append("Layout v1 must use the existing shelf heights.")
	if int(profile["max_attempts"]) < 0 or int(profile["max_attempts"]) > 32: errors.append("Invalid retry bound.")
	var fields := {
		"edge_detail": ["foothill_depth", "mountain_depth", "shore_depth"],
		"primary": ["anchor_margin", "ridge_length_min", "ridge_length_max", "summit_expansion_chance",
			"shoulders_min", "shoulders_max", "shoulder_size_min", "shoulder_size_max"],
		"secondary": ["count_min", "count_max", "rank_min", "rank_max"],
		"requirements": ["min_summit_cells", "min_connected_mountain_cells", "min_cells_per_mountain_shelf",
			"min_connected_dry_lowland_cells"],
		"lowland_lake": ["min_cells", "max_cells", "coastal_chance", "floor_y", "waterline_y"],
		"mountain_tarn": ["chance", "floor_y", "waterline_y"]}
	for group: String in fields:
		if not profile[group] is Dictionary:
			errors.append("Profile section must be an object: " + group)
			continue
		for field: String in fields[group]:
			if not profile[group].has(field): errors.append("Missing profile field: " + group + "." + field)
	if not errors.is_empty(): return errors
	var primary: Dictionary = profile["primary"]
	var secondary: Dictionary = profile["secondary"]
	var requirements: Dictionary = profile["requirements"]
	var lake: Dictionary = profile["lowland_lake"]
	var tarn: Dictionary = profile["mountain_tarn"]
	for field in ["foothill_depth", "mountain_depth", "shore_depth"]:
		if int(profile["edge_detail"][field]) < 1 or int(profile["edge_detail"][field]) > 3:
			errors.append("Edge detail must stay within three columns of a macro boundary.")
	if int(primary["anchor_margin"]) < 5 or int(primary["anchor_margin"]) > 12: errors.append("Invalid anchor margin.")
	for spec in [[primary, "ridge_length", 3, 16], [primary, "shoulders", 0, 5],
			[primary, "shoulder_size", 2, 6], [secondary, "count", 0, 5], [secondary, "rank", 1, 8]]:
		var low := int(spec[0][spec[1] + "_min"])
		var high := int(spec[0][spec[1] + "_max"])
		if low < int(spec[2]) or high > int(spec[3]) or low > high: errors.append("Invalid range: " + str(spec[1]))
	for probability in [primary["summit_expansion_chance"], lake["coastal_chance"], tarn["chance"]]:
		if float(probability) < 0 or float(probability) > 1: errors.append("Invalid probability.")
	for field in ["min_summit_cells", "min_connected_mountain_cells", "min_cells_per_mountain_shelf", "min_connected_dry_lowland_cells"]:
		if int(requirements[field]) < 1 or int(requirements[field]) > 1024: errors.append("Invalid minimum: " + field)
	if int(lake["min_cells"]) < 12 or int(lake["max_cells"]) > 64 or int(lake["min_cells"]) > int(lake["max_cells"]):
		errors.append("Invalid lowland lake size.")
	if int(lake["floor_y"]) != 11 or int(lake["waterline_y"]) != 18 or int(tarn["floor_y"]) != 47 or int(tarn["waterline_y"]) != 54:
		errors.append("Layout v1 uses the current water elevations and depths.")
	return errors


static func inspect(layout: Dictionary, profile: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var count := int(profile["macro_count"])
	var ranks: PackedInt32Array = layout.get("ranks", PackedInt32Array())
	var heights: PackedInt32Array = layout.get("heights", PackedInt32Array())
	var water: PackedInt32Array = layout.get("water_index", PackedInt32Array())
	var bodies: Array = layout.get("water_bodies", [])
	if ranks.size() != count * count or heights.size() != ranks.size() or water.size() != ranks.size():
		return {"errors": ["Map dimensions are incorrect."], "metrics": {}}
	var histogram: Array[int] = []
	histogram.resize(10)
	var mountain: Dictionary = {}
	var lowland: Dictionary = {}
	var all_lowland: Dictionary = {}
	var max_height := 0
	var min_height := 128
	var peak_x_sum := 0
	var peak_z_sum := 0
	var step_violations := 0
	for x in range(count):
		for z in range(count):
			var index := x * count + z
			var rank := ranks[index]
			if rank < 0 or rank >= SHELVES.size():
				errors.append("Out-of-range shelf rank.")
				continue
			max_height = maxi(max_height, heights[index])
			min_height = mini(min_height, heights[index])
			if heights[index] <= 3 or heights[index] > 115: errors.append("Terrain outside supported height range.")
			if rank == 0: all_lowland[index] = true
			if water[index] < 0:
				histogram[rank] += 1
				if heights[index] != SHELVES[rank]: errors.append("Dry surface does not match its shelf.")
				if rank >= 4: mountain[index] = true
				if rank == 0: lowland[index] = true
				if rank == 9:
					peak_x_sum += x
					peak_z_sum += z
			elif water[index] >= bodies.size(): errors.append("Invalid water body index.")
			for dx in range(-1, 2):
				for dz in range(-1, 2):
					if x + dx < 0 or z + dz < 0 or x + dx >= count or z + dz >= count: continue
					if absi(rank - ranks[(x + dx) * count + z + dz]) > 1: step_violations += 1
	if step_violations: errors.append("Adjacent terrain shelves differ by more than one rank.")
	var requirements: Dictionary = profile["requirements"]
	if max_height != 115 or histogram[9] < int(requirements["min_summit_cells"]): errors.append("Missing required Y115 summit.")
	for rank in range(4, 9):
		if histogram[rank] < int(requirements["min_cells_per_mountain_shelf"]): errors.append("Insufficient shelf area at Y%d." % SHELVES[rank])
	var largest_peak_component := 0
	for component: Array in _components(mountain, count):
		var has_peak := false
		for index: int in component:
			if ranks[index] == 9: has_peak = true
		if has_peak: largest_peak_component = maxi(largest_peak_component, component.size())
	if largest_peak_component < int(requirements["min_connected_mountain_cells"]): errors.append("Summit lacks a substantial connected mountain region.")
	var largest_lowland := 0
	var safe_lowland_columns := 0
	for component: Array in _components(lowland, count):
		largest_lowland = maxi(largest_lowland, component.size())
		var safe_area := 0
		for index: int in component: safe_area += _flat_area_budget(index, ranks, water, profile)
		safe_lowland_columns = maxi(safe_lowland_columns, safe_area)
	if largest_lowland < int(requirements["min_connected_dry_lowland_cells"]): errors.append("Insufficient connected dry lowland.")
	if safe_lowland_columns < int(requirements["min_connected_dry_lowland_cells"]) * 1024:
		errors.append("Insufficient connected dry lowland after reserving edge detail.")
	var safe_shelves := PackedInt32Array()
	safe_shelves.resize(10)
	for index in range(ranks.size()):
		if ranks[index] in [4, 5, 6, 7, 8] and water[index] < 0:
			safe_shelves[ranks[index]] += _flat_area_budget(index, ranks, water, profile)
	for rank in range(4, 9):
		if safe_shelves[rank] < int(requirements["min_cells_per_mountain_shelf"]) * 1024:
			errors.append("Insufficient flat mountain shelf after reserving edge detail.")
	for component: Array in _components(all_lowland, count):
		var reaches_edge := false
		for index: int in component:
			var x := index / count
			var z := index % count
			if x == 0 or z == 0 or x == count - 1 or z == count - 1: reaches_edge = true
		if not reaches_edge: errors.append("Isolated lowland hole within higher terrain.")
	var lake_count := 0
	var tarn_count := 0
	var lake_coastal := false
	var listed: Dictionary = {}
	for body_index in range(bodies.size()):
		var body: Dictionary = bodies[body_index]
		var mask: Dictionary = {}
		var kind := String(body["kind"])
		if kind == "lowland_lake": lake_count += 1
		elif kind == "mountain_tarn": tarn_count += 1
		else: errors.append("Unknown water body kind.")
		for index: int in body["cells"]:
			if index < 0 or index >= ranks.size():
				errors.append("Water outside map.")
				continue
			if listed.has(index): errors.append("Overlapping water cells.")
			listed[index] = true
			mask[index] = true
			if water[index] != body_index or heights[index] != int(body["floor_y"]): errors.append("Water footprint/floor disagree with final maps.")
			var x := index / count
			var z := index % count
			if kind == "lowland_lake":
				if ranks[index] != 0: errors.append("Main lake lies outside lowland.")
				if x == 0 or z == 0 or x == count - 1 or z == count - 1: lake_coastal = true
			elif kind == "mountain_tarn":
				if ranks[index] != 4 or x == 0 or z == 0 or x == count - 1 or z == count - 1:
					errors.append("Invalid tarn center.")
					continue
				for dx in range(-1, 2):
					for dz in range(-1, 2):
						if ranks[(x + dx) * count + z + dz] not in [4, 5]: errors.append("Tarn lacks its M1/M2 surround.")
		if _components(mask, count).size() != 1: errors.append("Disconnected water body.")
		var config: Dictionary = profile["lowland_lake"] if kind == "lowland_lake" else profile["mountain_tarn"]
		if int(body["floor_y"]) != int(config["floor_y"]) or int(body["waterline_y"]) != int(config["waterline_y"]): errors.append("Unexpected water elevation.")
		if kind == "lowland_lake" and (mask.size() < int(config["min_cells"]) or mask.size() > int(config["max_cells"])): errors.append("Main lake size outside limits.")
		if kind == "mountain_tarn" and mask.size() != 1: errors.append("Tarn must occupy one macro cell.")
		for index: int in mask:
			var point := Vector2i(index / count, index % count)
			for direction in CARDINAL:
				var next := point + direction
				if next.x < 0 or next.y < 0 or next.x >= count or next.y >= count: continue
				var neighbor := next.x * count + next.y
				if not mask.has(neighbor) and heights[neighbor] <= int(body["waterline_y"]): errors.append("Lake has an uncontained landward shore.")
	for index in range(water.size()):
		if water[index] >= 0 and not listed.has(index): errors.append("Unlisted water cell.")
	if lake_count != 1 or tarn_count > 1: errors.append("Expected one main lake and at most one tarn.")
	return {"errors": errors, "metrics": {"min_y": min_height, "max_y": max_height, "dry_shelf_cells": histogram,
		"mountain_cells": mountain.size(), "connected_summit_mountain_cells": largest_peak_component,
		"summit_cells": histogram[9], "summit_center": [float(peak_x_sum) / maxi(1, histogram[9]), float(peak_z_sum) / maxi(1, histogram[9])],
		"largest_dry_lowland_cells": largest_lowland, "lake_coastal": lake_coastal, "has_tarn": tarn_count == 1,
		"step_violations": step_violations}}


static func _components(mask: Dictionary, count: int) -> Array:
	var seen: Dictionary = {}
	var result: Array = []
	for index: int in mask:
		if seen.has(index): continue
		var queue: Array[int] = [index]
		seen[index] = true
		var head := 0
		while head < queue.size():
			var current := queue[head]
			head += 1
			var point := Vector2i(current / count, current % count)
			for direction in CARDINAL:
				var next := point + direction
				if next.x < 0 or next.y < 0 or next.x >= count or next.y >= count: continue
				var neighbor := next.x * count + next.y
				if mask.has(neighbor) and not seen.has(neighbor):
					seen[neighbor] = true
					queue.append(neighbor)
		result.append(queue)
	return result


## Conservative area left when every higher neighbor occupies its full detail
## strip. Overlapping corners are subtracted twice, so this is a lower bound.
static func _flat_area_budget(index: int, ranks: PackedInt32Array, water: PackedInt32Array, profile: Dictionary) -> int:
	var count := int(profile["macro_count"])
	var size := int(profile["macro_size"])
	var point := Vector2i(index / count, index % count)
	var area := size * size
	for direction in CARDINAL:
		var next := point + direction
		if next.x < 0 or next.y < 0 or next.x >= count or next.y >= count: continue
		var neighbor := next.x * count + next.y
		if water[neighbor] >= 0 or ranks[neighbor] <= ranks[index]: continue
		area -= size * int(profile["edge_detail"]["mountain_depth" if ranks[neighbor] >= 4 else "foothill_depth"])
	return area


## Validate every final column, not just macro-cell centers. The accepted macro
## graph proves connectivity. Detail is confined to narrow boundary strips, so
## connected lowland/water cores survive; their finished areas are counted too.
static func inspect_columns(layout: Dictionary, profile: Dictionary, heights: PackedInt32Array,
		domains: PackedInt32Array, waterlines: PackedInt32Array) -> Dictionary:
	var check := inspect(layout, profile)
	if not check["errors"].is_empty(): return check
	var count := int(profile["macro_count"])
	var size := int(profile["macro_size"])
	var width := count * size
	if heights.size() != width * width or domains.size() != heights.size() or waterlines.size() != heights.size():
		return {"errors": ["Finished map dimensions are incorrect."]}
	var issues: Dictionary = {}
	var histogram := PackedInt32Array()
	histogram.resize(116)
	var macro_heights: PackedInt32Array = layout["heights"]
	var macro_ranks: PackedInt32Array = layout["ranks"]
	var macro_water: PackedInt32Array = layout["water_index"]
	var bodies: Array = layout["water_bodies"]
	var lowland_columns := PackedInt32Array()
	lowland_columns.resize(count * count)
	var lowland_mask: Dictionary = {}
	var shore_land_columns := 0
	var shallow_water_columns := 0
	var detailed_columns := 0
	var water_columns := 0
	var peak_columns := 0
	var min_y := 128
	var max_y := 0
	for mx in range(count):
		for mz in range(count):
			var macro_index := mx * count + mz
			var original := macro_heights[macro_index]
			var body := macro_water[macro_index]
			var body_waterline := int(bodies[body]["waterline_y"]) if body >= 0 else -1
			if body < 0 and macro_ranks[macro_index] == 0: lowland_mask[macro_index] = true
			for x in range(mx * size, (mx + 1) * size):
				for z in range(mz * size, (mz + 1) * size):
					var index := x * width + z
					var height := heights[index]
					var protected := macro_ranks[macro_index] == 9
					min_y = mini(min_y, height)
					max_y = maxi(max_y, height)
					if height < original or height > 115: issues["Detail eroded terrain or exceeded Y115."] = true
					if protected and height != original: issues["Protected summit changed."] = true
					if height != original:
						detailed_columns += 1
						if not _within_detail_boundary(x, z, macro_index, layout, profile): issues["Detail escaped its boundary strip."] = true
					var expected_waterline := body_waterline if body >= 0 and height < body_waterline else -1
					if waterlines[index] != expected_waterline: issues["Finished waterline differs from its body."] = true
					var expected_domain := 0 if height <= 19 else (1 if height <= 43 else 2)
					if domains[index] != expected_domain: issues["Finished domain disagrees with height."] = true
					if body >= 0 and expected_waterline < 0: shore_land_columns += 1
					if expected_waterline >= 0:
						water_columns += 1
						if height > original: shallow_water_columns += 1
						for direction in CARDINAL:
							var nx := x + direction.x
							var nz := z + direction.y
							if nx < 0 or nz < 0 or nx >= width or nz >= width: continue
							var neighbor := nx * width + nz
							if waterlines[neighbor] != body_waterline and heights[neighbor] < body_waterline:
								issues["Finished water has an uncontained shore."] = true
						continue
					if body < 0 and macro_ranks[macro_index] == 0 and height == 19: lowland_columns[macro_index] += 1
					if height >= 0 and height <= 115: histogram[height] += 1
					if height == 115: peak_columns += 1
					# Forward neighbors cover all eight directions exactly once.
					for offset: int in [1, width - 1, width, width + 1]:
						if offset == 1 and z == width - 1: continue
						if offset != 1 and x == width - 1: continue
						if offset == width - 1 and z == 0: continue
						if offset == width + 1 and z == width - 1: continue
						var neighbor := index + offset
						if waterlines[neighbor] >= 0 or heights[neighbor] == height: continue
						if absi(_rank(height) - _rank(heights[neighbor])) > 1: issues["Detail introduced an excessive dry shelf step."] = true
	var requirements: Dictionary = profile["requirements"]
	var connected_lowland_columns := 0
	for component: Array in _components(lowland_mask, count):
		var area := 0
		for index: int in component: area += lowland_columns[index]
		connected_lowland_columns = maxi(connected_lowland_columns, area)
	if connected_lowland_columns < int(requirements["min_connected_dry_lowland_cells"]) * size * size:
		issues["Detail removed too much connected dry lowland."] = true
	for rank in range(4, 9):
		if histogram[SHELVES[rank]] < int(requirements["min_cells_per_mountain_shelf"]) * size * size:
			issues["Detail removed too much flat mountain shelf area."] = true
	return {"errors": issues.keys(), "min_y": min_y, "max_y": max_y, "summit_columns": peak_columns,
		"water_columns": water_columns, "shore_land_columns": shore_land_columns, "shallow_water_columns": shallow_water_columns,
		"connected_dry_lowland_columns": connected_lowland_columns, "detailed_columns": detailed_columns, "dry_height_histogram": histogram}


## Only a higher, originally dry neighboring plate can add material, within its
## bounded strip. Thus every original water/lowland cell keeps its full inner
## 26 x 26 core and a wide connection to each equal-height neighboring cell.
static func _within_detail_boundary(x: int, z: int, index: int, layout: Dictionary, profile: Dictionary) -> bool:
	var size := int(profile["macro_size"])
	var count := int(profile["macro_count"])
	var ranks: PackedInt32Array = layout["ranks"]
	var heights: PackedInt32Array = layout["heights"]
	var water: PackedInt32Array = layout["water_index"]
	var point := Vector2i(index / count, index % count)
	var distances := [x % size + 1, size - x % size, z % size + 1, size - z % size]
	for i in range(4):
		var next := point + CARDINAL[i]
		if next.x < 0 or next.y < 0 or next.x >= count or next.y >= count: continue
		var neighbor := next.x * count + next.y
		if water[neighbor] >= 0 or heights[neighbor] <= heights[index]: continue
		var field := "shore_depth" if water[index] >= 0 else "mountain_depth" if ranks[neighbor] >= 4 else "foothill_depth"
		if distances[i] <= int(profile["edge_detail"][field]): return true
	return false


static func _rank(height: int) -> int:
	if height <= 19: return 0
	if height <= 43: return 1 + (height - 20) / 8
	return 4 + (height - 44) / 12
