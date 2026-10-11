extends RefCounted

## Conservative finite-volume solver over connected, solid-separated vertical
## spaces. A column may contain surface water AND several underground pools.
## All elevations are voxel boundaries; volume is measured in block cubed.
## Open reservoirs rise and spill. Pressurized pipes are deliberately excluded.
const UNITS := 1000000 # Integer millionths of a block cubed; exact JSON persistence.
const DIRECTIONS := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
var spans_at: Callable
var mass: Dictionary = {} # Vector3i(x, bottom, z) -> volume
var initial: Dictionary = {}
var changed: Dictionary = {}
var modified: Dictionary = {}
var pending: Array = [] # Displaced water waiting for accessible capacity.
var conductance := 3.0
var epsilon := 0.00001
var level_reach := 8
var added_units := 0
var drained_units := 0
var extracted_units := 0
## Optional, transient presentation telemetry. Never feeds the solver or saves.
var track_surface_motion := false
var surface_flux: Dictionary = {} # Sum of horizontal transfers at each wet space.
var added: float:
	get: return float(added_units)/UNITS
var drained: float:
	get: return float(drained_units)/UNITS
var extracted: float:
	get: return float(extracted_units)/UNITS
var _spans: Dictionary = {}
var _links: Dictionary = {}
var _queue: Array[Vector3i] = []
var _queued: Dictionary = {}
var _head := 0

func spans(column: Vector2i) -> Array:
	if not _spans.has(column): _spans[column] = spans_at.call(column)
	return _spans[column]

func space_at(point: Vector3i) -> Vector3i:
	for span: Vector2i in spans(Vector2i(point.x, point.z)):
		if point.y >= span.x and point.y < span.y: return Vector3i(point.x, span.x, point.z)
	return Vector3i(-1,-1,-1)

func ceiling(key: Vector3i) -> int:
	for span: Vector2i in spans(Vector2i(key.x, key.z)):
		if span.x == key.y: return span.y
	return key.y

func volume(key: Vector3i) -> float:
	return float(mass.get(key,0))/UNITS

func level(key: Vector3i) -> float:
	return key.y + volume(key)

func depth_at(point: Vector3i) -> float:
	var key := space_at(point)
	return clampf(level(key) - point.y, 0.0, 1.0) if key.x >= 0 else 0.0

func seed_column(key: Vector3i, volume: float, active := true) -> void:
	if volume <= 0: return
	mass[key] = roundi(volume*UNITS)
	initial[key] = mass[key]
	if active: wake(key)

func wake(key: Vector3i) -> void:
	if not _queued.has(key):
		_queued[key] = true
		_queue.append(key)

func connections(key: Vector3i) -> Array:
	if _links.has(key): return _links[key]
	var result: Array = []
	var top := ceiling(key)
	for dir: Vector2i in DIRECTIONS:
		var col := Vector2i(key.x, key.z) + dir
		for span: Vector2i in spans(col):
			var sill := maxi(key.y, span.x)
			if sill < mini(top, span.y): result.append([Vector3i(col.x, span.x, col.y), sill])
	_links[key] = result
	return result

func _set_mass(key: Vector3i, value: int) -> void:
	mass[key] = maxi(value,0)
	modified[key] = true
	changed[key] = true
	wake(key)
	for link: Array in connections(key):
		if volume(link[0]) > epsilon: wake(link[0])

func add_at(point: Vector3i, requested: float, maximum_level: float) -> float:
	var key := space_at(point)
	if key.x < 0 or requested <= 0: return 0.0
	var room := roundi((minf(ceiling(key),maximum_level)-key.y)*UNITS)-int(mass.get(key,0))
	var amount := mini(roundi(requested*UNITS),maxi(0,room))
	if amount > 0:
		_set_mass(key,int(mass.get(key,0))+amount)
		added_units += amount
	return float(amount)/UNITS

func remove_at(point: Vector3i, requested: float, minimum_level: float, is_outlet := false) -> float:
	var key := space_at(point)
	if key.x < 0 or requested <= 0: return 0.0
	var available := int(mass.get(key,0))-roundi((maxf(key.y,minimum_level)-key.y)*UNITS)
	var amount := mini(roundi(requested*UNITS),maxi(0,available))
	if amount > 0:
		_set_mass(key,int(mass.get(key,0))-amount)
		if is_outlet: drained_units += amount
		else: extracted_units += amount
	return float(amount)/UNITS

## Shared by simulation and presentation: only actual free outlets get a
## falling curtain. A neighboring dry terrace is not automatically a waterfall.
func lowest_receiving_level(key: Vector3i) -> float:
	var lowest := float(key.y)
	for link: Array in connections(key):
		var other: Vector3i = link[0]
		if ceiling(other)-level(other)>epsilon: lowest = minf(lowest,level(other))
	return lowest


func _record_surface_transfer(from: Vector3i, to: Vector3i, units: int) -> void:
	if not track_surface_motion or units == 0: return
	var flux := Vector2(to.x-from.x,to.z-from.z)*float(units)/UNITS*0.5
	# Incoming and outgoing water contribute to the same downstream direction.
	surface_flux[from] = Vector2(surface_flux.get(from,Vector2.ZERO))+flux
	surface_flux[to] = Vector2(surface_flux.get(to,Vector2.ZERO))+flux

func step(delta: float, budget: int) -> int:
	_settle_displaced()
	var count := mini(budget, _queue.size() - _head)
	for i in count:
		var key := _queue[_head]
		_head += 1
		_queued.erase(key)
		if volume(key) <= epsilon: continue
		var links := connections(key)
		# A free overfall drains towards the lowest receiving surface. Treating
		# every exposed side as an equal outlet sprayed a little water onto each
		# lower terrace beside a waterfall, even with an open channel below it.
		# Once that channel backs up to this floor, ordinary level/sill exchange
		# resumes, so a dam can still raise the reservoir and overflow its banks.
		var lowest := lowest_receiving_level(key)
		for link: Array in links:
			var other: Vector3i = link[0]
			if lowest < key.y-epsilon and level(other)>lowest+epsilon: continue
			var available := maxf(0, level(key) - float(link[1]))
			var difference := level(key) - maxf(level(other), float(link[1]))
			var amount := minf(available, minf(difference * 0.5, difference * conductance * delta))
			amount = minf(amount, ceiling(other) - level(other))
			if amount <= epsilon: continue
			var units := mini(int(mass[key]),floori(amount*UNITS))
			_set_mass(key,int(mass[key])-units)
			_set_mass(other,int(mass.get(other,0))+units)
			_record_surface_transfer(key,other,units)
		# Water within an already connected, flat wet reach shares its level.
		# This avoids one-cell diffusion making long quiet river reaches behave
		# like thousands of tiny sealed tanks. Never crosses dry gaps or a sill.
		if key.x % 4 == 0: _level_wet_reach(key,Vector2i.RIGHT)
		if key.z % 4 == 0: _level_wet_reach(key,Vector2i.DOWN)
	if _head > 4096 or _head == _queue.size():
		_queue = _queue.slice(_head)
		_head = 0
	return count

func _level_wet_reach(key: Vector3i, dir: Vector2i) -> void:
	var keys: Array[Vector3i] = [key]
	var top := ceiling(key)
	var total := int(mass.get(key,0))
	var smallest := total
	var largest := total
	if total <= roundi(epsilon*UNITS): return
	for distance in range(1,level_reach+1):
		var col := Vector2i(key.x,key.z)+dir*distance
		var same_space := false
		for span: Vector2i in spans(col):
			if span.x==key.y and span.y==top:
				same_space = true
				break
		var next := Vector3i(col.x,key.y,col.y)
		var stored := int(mass.get(next,0))
		if not same_space or stored<=roundi(epsilon*UNITS): break
		keys.append(next)
		total += stored
		smallest = mini(smallest,stored)
		largest = maxi(largest,stored)
	if keys.size()<3 or largest-smallest<=roundi(epsilon*UNITS): return
	@warning_ignore("integer_division")
	var mean := total/keys.size()
	var remainder := total%keys.size()
	var crossing := 0
	for i in keys.size():
		var value := mean+(1 if i<remainder else 0)
		# Prefix mass difference gives the net transfer through each interface
		# in this conservative equalization pass, including negative (back) flow.
		crossing += int(mass[keys[i]])-value
		if i+1 < keys.size(): _record_surface_transfer(keys[i],keys[i+1],crossing)
		if int(mass[keys[i]])!=value: _set_mass(keys[i],value)

## Rebuild only the edited column and its interfaces. Preserve water intersected
## by new solid blocks as explicit displaced volume; never silently delete it.
func terrain_changed(column: Vector2i) -> void:
	var old: Array = []
	for span: Vector2i in spans(column):
		var key := Vector3i(column.x, span.x, column.y)
		if int(mass.get(key,0)) > 0: old.append([span.x,level(key),int(mass[key])])
		mass.erase(key)
		surface_flux.erase(key)
		_links.erase(key)
		modified[key] = true
		changed[key] = true
	_spans.erase(column)
	var nearby: Array[Vector2i] = [column]
	for dir: Vector2i in DIRECTIONS: nearby.append(column + dir)
	for col: Vector2i in nearby:
		for span: Vector2i in spans(col):
			var key := Vector3i(col.x, span.x, col.y)
			_links.erase(key)
			wake(key)
	for interval: Array in old:
		var left: int = interval[2]
		for span: Vector2i in spans(column):
			var overlap := mini(left,roundi(maxf(0,minf(span.y,interval[1])-maxf(span.x,interval[0]))*UNITS))
			if overlap > 0:
				var key := Vector3i(column.x, span.x, column.y)
				_set_mass(key,int(mass.get(key,0))+overlap)
				left -= overlap
		if left > 0: pending.append({"point": Vector3i(column.x, int(ceil(interval[1])), column.y), "units": left})
	_settle_displaced()

func _settle_displaced() -> void:
	var remaining: Array = []
	for entry: Dictionary in pending:
		var left: int = entry.units
		var point: Vector3i = entry.point
		var targets: Array[Vector2i] = [Vector2i(point.x, point.z)]
		for dir: Vector2i in DIRECTIONS: targets.append(Vector2i(point.x, point.z) + dir)
		for col: Vector2i in targets:
			for span: Vector2i in spans(col):
				if span.y < point.y or span.x > point.y: continue
				var key := Vector3i(col.x, span.x, col.y)
				var amount := mini(left,(span.y-key.y)*UNITS-int(mass.get(key,0)))
				if amount > 0:
					_set_mass(key,int(mass.get(key,0))+amount)
					left -= amount
		if left > 0: remaining.append({"point": point, "units": left})
	pending = remaining

func total_volume() -> float:
	var total := 0
	for value: int in mass.values(): total += value
	for entry: Dictionary in pending: total += int(entry.units)
	return float(total)/UNITS

func serialize() -> Dictionary:
	var cells: Array = []
	var keys := modified.keys()
	keys.sort_custom(func(a: Vector3i, b: Vector3i): return a.x < b.x or (a.x == b.x and (a.z < b.z or (a.z == b.z and a.y < b.y))))
	for key: Vector3i in keys:
		var value := int(mass.get(key,0))
		if value != int(initial.get(key,0)): cells.append({"cell": [key.x,key.y,key.z], "units": value})
	var active: Array = []
	for key: Vector3i in _queue.slice(_head): active.append([key.x,key.y,key.z])
	var displaced: Array = []
	for entry: Dictionary in pending:
		var p: Vector3i = entry.point
		displaced.append({"cell": [p.x,p.y,p.z], "units": entry.units})
	return {"cells": cells, "active": active, "displaced": displaced,
		"added_units":added_units,"drained_units":drained_units,"extracted_units":extracted_units}

func restore(state: Dictionary) -> void:
	surface_flux.clear()
	mass = initial.duplicate()
	modified.clear()
	changed.clear()
	_links.clear()
	_spans.clear()
	for entry: Dictionary in state.cells:
		var p: Array = entry.cell
		var key := Vector3i(int(p[0]), int(p[1]), int(p[2]))
		mass[key] = int(entry.units)
		modified[key] = true
	_queue.clear()
	_queued.clear()
	_head = 0
	for p: Array in state.active: wake(Vector3i(int(p[0]),int(p[1]),int(p[2])))
	pending.clear()
	for entry: Dictionary in state.displaced:
		var p: Array = entry.cell
		pending.append({"point": Vector3i(int(p[0]),int(p[1]),int(p[2])), "units":int(entry.units)})
	added_units = int(state.added_units)
	drained_units = int(state.drained_units)
	extracted_units = int(state.extracted_units)
