extends RefCounted

## Seeded, downhill route over the existing shelf graph. The summit is never
## cut. Fine channels are carved into authoritative terrain, before cave layout.
const DIRS := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
const SIZE := 1024
const VERSION := 5 # Aligned spring outlet; saved volume deltas require this base.

static func carve(seed_value: int, macro: Dictionary, heights: PackedInt32Array, water: PackedInt32Array, profile: Dictionary) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	var original_heights := heights.duplicate()
	var original_water := water.duplicate()
	rng.seed = seed_value + int(profile.salt)
	var parent: Dictionary = {}
	var queue: Array[int] = []
	var mh: PackedInt32Array = macro.heights
	for body: Dictionary in macro.water_bodies:
		if body.kind != "lowland_lake": continue
		for index: int in body.cells:
			parent[index] = -1
			queue.append(index)
	var read := 0
	var candidates: Array[int] = []
	var best_height := -1
	while read < queue.size():
		var index := queue[read]
		read += 1
		var h := mh[index]
		if h > best_height:
			best_height = h
			candidates.clear()
		if h == best_height: candidates.append(index)
		var col := Vector2i(index / 32, index % 32)
		var turn := rng.randi_range(0,3)
		for j in 4:
			var next: Vector2i = col + DIRS[(j + turn) % 4]
			if next.x < 1 or next.y < 1 or next.x >= 31 or next.y >= 31: continue
			var ni := next.x * 32 + next.y
			if parent.has(ni) or mh[ni] < h or mh[ni] > int(profile.source_preferred_y): continue
			parent[ni] = index
			queue.append(ni)
	assert(best_height >= int(profile.source_min_y), "No high spring route to lake")
	var rock_faces: Array[int] = []
	for index: int in candidates:
		var col := Vector2i(index/32,index%32)
		for dir: Vector2i in DIRS:
			var neighbor := col+dir
			if neighbor.x>=0 and neighbor.y>=0 and neighbor.x<32 and neighbor.y<32 and mh[neighbor.x*32+neighbor.y]>best_height:
				rock_faces.append(index)
				break
	assert(not rock_faces.is_empty(),"High spring requires an upper rock face")
	candidates = rock_faces
	var source := candidates[rng.randi_range(0, candidates.size()-1)]
	var route: Array[Vector2i] = []
	var cursor := source
	while cursor >= 0:
		route.append(Vector2i(cursor / 32, cursor % 32) * 32 + Vector2i(16 + rng.randi_range(-4,4),16 + rng.randi_range(-4,4)))
		cursor = int(parent[cursor])
	# Move the mouth towards an adjacent upper rock face when available.
	var source_macro := Vector2i(source / 32, source % 32)
	var spring_back := Vector2i.ZERO
	for dir: Vector2i in DIRS:
		var neighbor := source_macro + dir
		if mh[neighbor.x * 32 + neighbor.y] > best_height:
			var point := source_macro * 32 + Vector2i(16,16)
			for _i in 20:
				var next := point+dir
				if original_heights[next.x*SIZE+next.y] > best_height: break
				point = next
			route.push_front(point)
			spring_back = dir
			break
	var line: Array[Vector2i] = [route[0]]
	for end: Vector2i in route.slice(1):
		var point: Vector2i = line.back()
		while point != end:
			var diff := end - point
			if diff.x != 0 and (diff.y == 0 or rng.randf() < 0.5): point.x += signi(diff.x)
			else: point.y += signi(diff.y)
			line.append(point)
	line = _align_spring_exit(line,spring_back,int(profile.spring_exit_length))
	var columns: Dictionary = {}
	var nearest: Dictionary = {}
	var bed := best_height - int(profile.bed_depth)
	var falls: Array[Vector3i] = []
	for i in line.size():
		var point := line[i]
		var index := point.x * SIZE + point.y
		if original_water[index] >= 0:
			bed = mini(bed,original_water[index]-1)
			continue # Pass through pools without replacing their stored volume.
		var next_bed := mini(bed, original_heights[index] - int(profile.bed_depth))
		var plunge := bed-next_bed>=2
		if plunge: falls.append(Vector3i(point.x,bed+2,point.y))
		bed = next_bed
		var radius := int(profile.channel_radius)
		# Broad ordinary reaches, with a small spring mouth and occasional short
		# narrows. Keep each width for a stretch, rather than jittering every cell.
		var interval := int(profile.narrow_interval)
		if i<8 or (i+posmod(seed_value,interval))%interval<int(profile.narrow_length):
			radius = int(profile.narrow_radius)
		# Small quiet collection pools along the run, all with a downhill exit.
		if plunge or (i > 6 and i % 80 < 5): radius = int(profile.pool_radius)
		for dx in range(-radius,radius+1):
			for dz in range(-radius,radius+1):
				var p := point + Vector2i(dx,dz)
				var pi := p.x * SIZE + p.y
				if original_water[pi] >= 0: continue
				if original_heights[pi] > best_height: continue
				heights[pi] = mini(heights[pi],bed)
				water[pi] = heights[pi]+1
				columns[p] = true
				var distance := absi(dx)+absi(dz)
				if not nearest.has(p) or distance<int(nearest[p][1]): nearest[p] = [i,distance]
	# Edge detail can lower an adjacent terrace below the macro shelf. A cut
	# based only on the centerline then has no bank on that side. Plan against
	# the actual dry perimeter, and carry any lower bed downstream so fixing a
	# bank never creates an uphill exit or an isolated deep gutter.
	var sections: Dictionary = {}
	var bank_limits: Dictionary = {}
	for col: Vector2i in columns:
		var section := int(nearest[col][0])
		if not sections.has(section): sections[section] = []
		sections[section].append(col)
		for dir: Vector2i in DIRS:
			var neighbor := col+dir
			if columns.has(neighbor) or original_water[neighbor.x*SIZE+neighbor.y]>=0: continue
			var limit := original_heights[neighbor.x*SIZE+neighbor.y]-int(profile.bed_depth)
			bank_limits[section] = mini(int(bank_limits.get(section,128)),limit)
	bed = best_height-int(profile.bed_depth)
	for i in line.size():
		var point: Vector2i = line[i]
		var index := point.x*SIZE+point.y
		if original_water[index]>=0:
			bed = mini(bed,original_water[index]-1)
			continue
		bed = mini(bed,mini(heights[index],int(bank_limits.get(i,128))))
		for col: Vector2i in sections.get(i,[]):
			var ci := col.x*SIZE+col.y
			heights[ci] = mini(heights[ci],bed)
			water[ci] = heights[ci]+1
	# Refresh landmarks from the final bed rather than the pre-bank pass.
	falls.clear()
	for i in range(1,line.size()):
		var before: Vector2i = line[i-1]
		var after: Vector2i = line[i]
		var high := heights[before.x*SIZE+before.y]
		if high-heights[after.x*SIZE+after.y]>=2: falls.append(Vector3i(after.x,high+2,after.y))
	# Seed each quiet reach with a shallow downhill hydraulic gradient. A flat,
	# brim-full initial channel otherwise waits for a drawdown wave to traverse
	# the entire terrace before its spring can begin supplying the stream.
	var depths: Dictionary = {}
	var run_start := 0
	while run_start<line.size():
		var first: Vector2i = line[run_start]
		var floor_y := heights[first.x*SIZE+first.y]
		var run_end := run_start+1
		while run_end<line.size():
			var p: Vector2i = line[run_end]
			if heights[p.x*SIZE+p.y]!=floor_y: break
			run_end += 1
		for i in range(run_start,run_end): depths[i] = roundi(lerpf(0.95,0.35,float(i-run_start)/maxi(1,run_end-run_start-1))*1000000.0)
		run_start = run_end
	var initial_units: Dictionary = {}
	for col: Vector2i in columns: initial_units[col] = depths[int(nearest[col][0])]
	var start := line[0]
	var mouth := Vector3i(start.x,heights[start.x*SIZE+start.y]+1,start.y)
	var lake: Vector2i = route.back()
	var farthest := -1.0
	for body: Dictionary in macro.water_bodies:
		if body.kind != "lowland_lake": continue
		for macro_index: int in body.cells:
			var corner := Vector2i(macro_index/32,macro_index%32)*32
			for dx in 32:
				for dz in 32:
					var col := corner+Vector2i(dx,dz)
					if original_water[col.x*SIZE+col.y] != 18: continue
					for dir: Vector2i in DIRS:
						var bank := col+dir
						if bank.x<0 or bank.y<0 or bank.x>=SIZE or bank.y>=SIZE: continue
						if original_water[bank.x*SIZE+bank.y]>=0 or original_heights[bank.x*SIZE+bank.y]<19: continue
						var distance := Vector2(col).distance_squared_to(Vector2(start))
						if distance>farthest:
							farthest = distance
							lake = col
	# The loose dry stone rests on the bed at the existing intake. Its model
	# does not displace stored water or change the minimum retained lake level.
	var outlet := Vector3i(lake.x,heights[lake.x*SIZE+lake.y]+1,lake.y)
	return {"columns":columns,"initial_units":initial_units,"route":line,"falls":falls,"spring":mouth,"spring_mouth":mouth,"spring_back":spring_back,
		"spring_level":float(mouth.y+1),"outlet":outlet,"dry_stone":outlet,"outlet_level":19.0}

## Leave the cave along its axis before meandering. An immediate sideways step
## puts the first bend into the dry approach ledges, pinching the three-cell
## opening and hiding the remaining connection behind a rock lip. Reorder only
## the short initial Manhattan path, retaining the seeded route beyond the join.
static func _align_spring_exit(line: Array[Vector2i], back: Vector2i, length: int) -> Array[Vector2i]:
	var origin := line[0]
	var join := 0
	while join<line.size()-1 and Vector2(line[join]-origin).dot(Vector2(-back))<length:
		join += 1
	assert(Vector2(line[join]-origin).dot(Vector2(-back))==length,"Spring route does not clear the cliff")
	var result: Array[Vector2i] = []
	for d in range(length+1): result.append(origin-back*d)
	var point: Vector2i = result.back()
	while point!=line[join]:
		var diff := line[join]-point
		if diff.x!=0: point.x += signi(diff.x)
		else: point.y += signi(diff.y)
		result.append(point)
	result.append_array(line.slice(join+1))
	return result
