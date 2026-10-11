extends RefCounted

## A real, surface-connected cavity. The heightmap still describes the roof;
## column spans describe the stream bed and the raised, walkable ledges below it.
static func build(seed_value: int, river: Dictionary, heights: PackedInt32Array, profile: Dictionary) -> Dictionary:
	var mouth: Vector3i = river.get("spring_mouth",river.spring)
	var back: Vector2i = river.spring_back
	var side := Vector2i(-back.y,back.x)
	var origin := Vector2i(mouth.x,mouth.z)
	var ledge := mouth.y+1
	var ceiling := ledge+int(profile.headroom)
	var length := int(profile.depth_min)+posmod(seed_value,int(profile.depth_max)-int(profile.depth_min)+1)
	# Fine cliff ledges can put the first roof several cells behind the face.
	# Extend into solid mountain until the entire chamber has a real rock roof.
	for attempt in range(length,int(profile.search_depth)+1):
		var covered := true
		for d in range(attempt-3,attempt+2):
			for u in range(-3,4):
				var p := origin+back*d+side*u
				if heights[p.x*1024+p.y]<ceiling+int(profile.roof_thickness): covered = false
		if covered:
			length = attempt
			break
	var columns: Dictionary = {}
	var wet: Dictionary = {}
	var ledges: Array[Vector3i] = []
	var bounds := Rect2i(origin,Vector2i.ONE)
	for d in range(0,length+1):
		var radius := 3 if d>=length-3 else 2
		for u in range(-radius,radius+1):
			var p := origin+back*d+side*u
			var index := p.x*1024+p.y
			# Widen into a collection pool; the chamber expands one row before
			# the water so each dry ledge can turn around the wider basin.
			var stream := absi(u)<=(2 if d>=length-2 and d<length else 1)
			var floor_y := mouth.y-1 if stream else ledge
			var top := ceiling+(1 if d>=length-3 and absi(u)<2 else 0)
			columns[index] = Vector3i(floor_y,top,-1)
			bounds = bounds.merge(Rect2i(p,Vector2i.ONE))
			if stream: wet[Vector3i(p.x,floor_y+1,p.y)] = roundi(lerpf(0.85,0.98,float(d)/maxi(1,length))*1000000.0)
			else: ledges.append(Vector3i(p.x,floor_y,p.y))
	# Cliff detailing can leave a three-block step just outside the opening.
	# Continue each dry ledge through that final lip; the central stream stays
	# open and the approach uses the same real solid floor/air as the chamber.
	for u in range(-1,2):
		var p := origin-back+side*u
		var index := p.x*1024+p.y
		if heights[index]<mouth.y: continue # Already carved by the river.
		# The river preserves upper cliff columns. Tunnel through a protruding
		# lip at water height without shaving away its roof or the summit.
		columns[index] = Vector3i(mouth.y-1,ceiling,-1)
		wet[Vector3i(p.x,mouth.y,p.y)] = 850000
		bounds = bounds.merge(Rect2i(p,Vector2i.ONE))
	for bank: int in [-1,1]:
		var p := origin-back+side*2*bank
		columns[p.x*1024+p.y] = Vector3i(ledge,ceiling,-1)
		ledges.append(Vector3i(p.x,ledge,p.y))
		bounds = bounds.merge(Rect2i(p,Vector2i.ONE))
	var source_col := origin+back*length
	# A loose ore-shaped stone rests on the existing ledge beside the source
	# pool. Its model does not displace water or replace the chamber's rock wall.
	var stone_col := source_col+side*2
	var stone := Vector3i(stone_col.x,ledge+1,stone_col.y)
	return {"columns":columns,"water":wet,"ledges":ledges,"bounds":bounds.grow(1),
		"mouth":mouth,"source":Vector3i(source_col.x,mouth.y,source_col.y),
		"stone":stone,"ceiling":ceiling,"length":length}
