extends RefCounted

## Live water/shore positions and swept air routes, separate from dwarf paths.
const Ground = preload("res://scripts/components/AnimalNavigation.gd")
const DIRS := [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]
var config: Dictionary
var flora: Node

func water_at(col: Vector2i) -> Dictionary:
	if not WaterManager.initialized or not _inside(col): return {}
	for span: Vector2i in WaterManager.flow.spans(col):
		var key := Vector3i(col.x,span.x,col.y)
		var depth: float = WaterManager.flow.volume(key)
		if depth<float(config.swim_depth): continue
		var level: float = WaterManager.flow.level(key)
		if WorldGenerator.get_cave_id(Vector3i(col.x,floori(level),col.y))>=0: continue
		var point := Vector3(col.x+.5,level-float(config.submerge),col.y+.5)
		if not clear_body(point,float(config.radius)): continue
		return {"position":point,"cell":Vector3i(point.floor()),"water":true,"key":key,"level":level}
	return {}

func surface(col: Vector2i, safe := true) -> Dictionary:
	if not _inside(col) or not WaterManager.initialized: return {}
	var wet := water_at(col)
	if not wet.is_empty():
		if safe and not calm_water(col,wet): return {}
		return wet
	var spans: Array = WaterManager.flow.spans(col)
	if spans.is_empty(): return {}
	var feet := Vector3i(col.x,spans.back().x,col.y)
	if WaterManager.depth_at(feet)>0.02 or not Ground.standable(feet,2): return {}
	var point := Ground.centre(feet)
	if not clear_body(point,float(config.radius)): return {}
	return {"position":point,"cell":feet,"water":false}

func calm_water(col: Vector2i, wet: Dictionary) -> bool:
	# Derive safety from hydraulic heads/outlets, not optional visual telemetry.
	for dir: Vector2i in DIRS:
		for d in range(int(config.waterfall_margin)+1):
			var p := col+dir*d
			var sample := water_at(p)
			if sample.is_empty(): continue
			if absf(float(sample.level)-float(wet.level))>float(config.max_water_step): return false
			if WaterManager.flow.lowest_receiving_level(sample.key)<float(sample.key.y)-0.5: return false
	return true

func _inside(col: Vector2i) -> bool:
	return col.x>0 and col.y>0 and col.x<1023 and col.y<1023

func clear_body(point: Vector3, radius: float) -> bool:
	var low := Vector3i((point-Vector3(radius,0,radius)+Vector3.ONE*.001).floor())
	var high := Vector3i((point+Vector3(radius,float(config.body_height),radius)-Vector3.ONE*.001).floor())
	if low.x<0 or low.z<0 or high.x>=1024 or high.z>=1024 or low.y<4 or high.y>=int(config.flight_max_y): return false
	for x in range(low.x,high.x+1):
		for y in range(low.y,high.y+1):
			for z in range(low.z,high.z+1):
				var p := Vector3i(x,y,z)
				if y<128 and BlockRegistry.is_solid(WorldData.get_terrain_block(x,y,z)): return false
				if PlacedEntityRegistry.occupies(p): return false
	return true

func segment_clear(from: Vector3, to: Vector3, radius: float, airborne := false) -> bool:
	if airborne and is_instance_valid(flora):
		var area := AABB(from.min(to),from.max(to)-from.min(to)).grow(radius+float(config.body_height))
		for box: AABB in flora.flight_obstacles(area):
			if box.grow(radius).intersects_segment(from+Vector3.UP*.5,to+Vector3.UP*.5)!=null: return false
	var count := maxi(1,ceili(from.distance_to(to)*4))
	for i in range(count+1):
		if not clear_body(from.lerp(to,float(i)/count),radius): return false
	return true

func step_position(from: Vector3, to: Vector3, progress: float) -> Vector3:
	if absf(to.y-from.y)<0.15: return from.lerp(to,progress)
	var top := maxf(from.y,to.y)
	if progress<.3: return from.lerp(Vector3(from.x,top,from.z),progress/.3)
	if progress<.7: return Vector3(from.x,top,from.z).lerp(Vector3(to.x,top,to.z),(progress-.3)/.4)
	return Vector3(to.x,top,to.z).lerp(to,(progress-.7)/.3)

func neighbors(from: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var col := Vector2i(from.cell.x,from.cell.z)
	for dir: Vector2i in DIRS:
		var next := surface(col+dir)
		if next.is_empty() or absf(float(next.position.y)-float(from.position.y))>1.3: continue
		if from.water and next.water and absf(float(next.level)-float(from.level))>float(config.max_water_step): continue
		var last: Vector3 = from.position
		var clear := true
		for i in range(1,9):
			var point := step_position(from.position,next.position,float(i)/8)
			if not segment_clear(last,point,float(config.radius)):
				clear = false
				break
			last = point
		if clear: result.append(next)
	return result

func near_shore(col: Vector2i, distance: int, forage: Array = []) -> bool:
	for dir: Vector2i in DIRS:
		for d in range(1,distance+1):
			var sample := surface(col+dir*d)
			if sample.is_empty() or sample.water: continue
			if forage.is_empty(): return true
			var ground: Vector3i = sample.cell+Vector3i.DOWN
			var kind: String = BlockRegistry.get_def(BlockRegistry.get_key(Ground.block_at(ground))).get("kind","")
			if kind in forage: return true
	return false

func flight_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	# A sampled arch gives a continuous climb/glide/descent. Every section is
	# swept at planning and again during flight, including canopy overhangs.
	var count := maxi(16,ceili(from.distance_to(to)/2))
	for rise: float in config.flight_rises:
		var points := PackedVector3Array([from])
		var clear := true
		for i in range(1,count+1):
			var t := float(i)/count
			var p := from.lerp(to,t)+Vector3.UP*sin(t*PI)*rise
			var radius := float(config.radius) if i==1 or i==count else float(config.flight_radius)
			if not segment_clear(points[-1],p,radius,true):
				clear = false
				break
			points.append(p)
		if clear: return points
	return PackedVector3Array()

func near_water(col: Vector2i) -> bool:
	for dir: Vector2i in DIRS:
		for d in range(1,4):
			var sample := surface(col+dir*d)
			if not sample.is_empty() and sample.water: return true
	return false

func landing_candidates(origin: Vector3, rng: RandomNumberGenerator, prefer_shore := false) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for attempt in int(config.landing_attempts):
		var angle := rng.randf()*TAU
		var distance := rng.randf_range(float(config.flight_range[0]),float(config.flight_range[1]))
		var col := Vector2i(floori(origin.x+cos(angle)*distance),floori(origin.z+sin(angle)*distance))
		var sample := surface(col)
		if not sample.is_empty() and (sample.water or (prefer_shore and near_water(col))): result.append(sample)
	return result

func group_cells(origin: Vector2i, count: int, spacing: float) -> Array[Vector3i]:
	var queue: Array[Vector2i] = [origin]
	var seen := {origin:true}
	var result: Array[Vector3i] = []
	var read := 0
	while read<queue.size() and read<120 and result.size()<count:
		var col := queue[read]
		read += 1
		var sample := surface(col)
		if sample.is_empty() or not sample.water: continue
		var spaced := true
		for other in result:
			if Vector2(col-Vector2i(other.x,other.z)).length()<spacing: spaced = false
		if spaced: result.append(sample.cell)
		for next in neighbors(sample):
			var p := Vector2i(next.cell.x,next.cell.z)
			if not next.water or seen.has(p) or Vector2(p-origin).length()>8: continue
			seen[p] = true
			queue.append(p)
	return result
