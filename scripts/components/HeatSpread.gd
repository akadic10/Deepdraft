extends RefCounted

## Heat and cold spreading (doc 34 "Heat and cold spreading"; doc 282 phase 3), owned by
## RoomManager as Climate is.
## - Fires warm open air. A burning fire whose air is not in a sealed room warms the air
##   within its heat_source radius, by walking steps through air: heat units /
##   open_air_heat_per_degree at the fire, at most open_air_fire_max_c (a hearth sized for
##   a big room adds no more outdoors than a small fire), fading to nothing at the radius.
##   Walls, doors and sealed rooms stop it. In a sealed room a fire heats the room as before.
## - Doors leak. Each door pulls a sealed room door_leak of the way toward the temperature on
##   its other side: another room, or the open air beyond with any fire's warmth there. A room
##   bigger than minimum_heated_volume feels it less, by that volume over its own. Each of
##   door_leak_passes passes takes the neighbours' last values, so a chain of rooms settles at
##   once: a hearth warms the room next door, and a little the one beyond.
## Temperatures are linear forms, Vector3(base, season share, day-and-weather share), so a
## leak blends forms and the clock moving changes none of them (the Temperature view's
## shader). Derived and never saved; nothing takes time to warm up.
const NEIGHBORS: Array[Vector3i] = [Vector3i.LEFT, Vector3i.RIGHT, Vector3i.UP, Vector3i.DOWN, Vector3i.FORWARD, Vector3i.BACK]
const SIDES: Array[Vector3i] = [Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK]

var owner: Node   # RoomManager
var _warmth := {}   # air cell -> °C the open-air fires add there
var _dirty := true
var _changed := {}   # cells whose warmth changed since take_changed()
var _doors: Array[Dictionary] = []   # the last leak's door pieces: {rooms: {id: true}, open: [form]}
var _room_doors := {}   # room id -> its doors' indices in _doors


func _init(manager: Node) -> void:
	owner = manager


func clear() -> void:
	_warmth.clear()
	_changed.clear()
	_doors.clear()
	_room_doors.clear()
	_dirty = true


func mark_dirty() -> void:
	_dirty = true


func is_dirty() -> bool:
	return _dirty


## What open-air fires add to an unsealed air cell now.
func warmth_at(cell: Vector3i) -> float:
	if _dirty: rebuild()
	return float(_warmth.get(cell, 0.0))


## Walks every open-air fire's warmth again; the cells whose warmth changed wait for
## take_changed().
func rebuild() -> void:
	_dirty = false
	var old := _warmth
	_warmth = {}
	var config: Dictionary = owner.temperature_config
	var climate = owner.climate
	var doors: Dictionary = owner.get_door_boundaries()
	var sources: Dictionary = owner.heat_sources()
	for anchor: Vector3i in sources:
		var radius := int(sources[anchor].radius)
		var origin := anchor + Vector3i.UP
		if radius <= 0 or doors.has(origin) or not climate.is_air(origin) or owner.get_room_id_at(origin) >= 0: continue
		var peak := minf(float(sources[anchor].units) / float(config.open_air_heat_per_degree), float(config.open_air_fire_max_c))
		_warmth[origin] = float(_warmth.get(origin, 0.0)) + peak
		var seen := {origin: true}
		var frontier: Array[Vector3i] = [origin]
		for step in range(1, radius):
			var next: Array[Vector3i] = []
			for cell: Vector3i in frontier:
				for offset: Vector3i in NEIGHBORS:
					var neighbour := cell + offset
					if seen.has(neighbour): continue
					seen[neighbour] = true
					if doors.has(neighbour) or not climate.is_air(neighbour) or owner.get_room_id_at(neighbour) >= 0: continue
					_warmth[neighbour] = float(_warmth.get(neighbour, 0.0)) + peak * (1.0 - float(step) / float(radius))
					next.append(neighbour)
			frontier = next
	for cell: Vector3i in old:
		if not is_equal_approx(float(old[cell]), float(_warmth.get(cell, 0.0))): _changed[cell] = true
	for cell: Vector3i in _warmth:
		if not old.has(cell): _changed[cell] = true


## The cells whose warmth changed since the last call.
func take_changed() -> Array[Vector3i]:
	var cells: Array[Vector3i] = []
	cells.assign(_changed.keys())
	_changed = {}
	return cells


## Pulls each sealed room's `temp_form` toward its doors' other sides. `rooms` maps room id
## to room (each with its own `own_form`); `cells` maps air cell to room id.
func apply_door_leaks(rooms: Dictionary, cells: Dictionary) -> void:
	_doors = _door_sides(cells)
	_room_doors = {}
	for index in _doors.size():
		for id: int in _doors[index].rooms:
			if not _room_doors.has(id): _room_doors[id] = []
			_room_doors[id].append(index)
	var own := {}
	for id: int in rooms: own[id] = rooms[id].own_form
	var forms := _leak(rooms, own, true)
	for id: int in rooms: rooms[id].temp_form = forms[id]


## The share of a heat added to one room that the room keeps once its doors leak: 1 without
## doors, 0.9 with one door to the open air. The leak is linear, so its passes over that heat
## alone give it, with the open air beyond adding nothing.
func kept_share(rooms: Dictionary, id: int) -> float:
	if not _room_doors.has(id) or not rooms.has(id): return 1.0
	var own := {}
	for other: int in rooms: own[other] = Vector3.ZERO
	own[id] = Vector3.RIGHT
	var kept: Vector3 = _leak(rooms, own, false)[id]
	return kept.x


## door_leak_passes passes from each room's `own` form, each taking the neighbours' last
## values; with `open` false the open air beyond adds nothing.
func _leak(rooms: Dictionary, own: Dictionary, open: bool) -> Dictionary:
	var config: Dictionary = owner.temperature_config
	var forms := own
	for i in range(int(config.door_leak_passes)):
		var next := {}
		for id: int in rooms:
			var base: Vector3 = own[id]
			var form := base
			var pull := float(config.door_leak) * float(config.minimum_heated_volume) / maxf(float(rooms[id].volume), float(config.minimum_heated_volume))
			for index: int in _room_doors.get(id, []):
				var door: Dictionary = _doors[index]
				var total := Vector3.ZERO
				var count := 0
				for other: int in door.rooms:
					if other == id or not forms.has(other): continue
					total += forms[other]
					count += 1
				for beyond: Vector3 in door.open:
					if open: total += beyond
					count += 1
				if count > 0: form += (total / float(count) - base) * pull
			next[id] = form
		forms = next
	return forms


## Each door piece with a sealed room on a side: {rooms: {room id: true}, open: [the open
## air's form beyond, if any]}, read from the air beside its doorway.
func _door_sides(cells: Dictionary) -> Array[Dictionary]:
	var boundaries: Dictionary = owner.get_door_boundaries()
	var pieces := {}   # door origin -> its sides
	for cell: Vector3i in boundaries:
		var origin: Vector3i = boundaries[cell]
		if not pieces.has(origin): pieces[origin] = {"rooms": {}, "open": []}
		var sides: Dictionary = pieces[origin]
		for offset: Vector3i in SIDES:
			var beside := cell + offset
			if boundaries.has(beside) or not owner.climate.is_air(beside): continue
			if cells.has(beside): sides.rooms[int(cells[beside])] = true
			elif (sides.open as Array).is_empty(): sides.open.append(_open_form(beside))
	var result: Array[Dictionary] = []
	for origin: Vector3i in pieces:
		if not (pieces[origin].rooms as Dictionary).is_empty(): result.append(pieces[origin])
	return result


## The open air's form at a cell: its height's mean plus any fire's warmth, with its shares.
func _open_form(cell: Vector3i) -> Vector3:
	var place: Dictionary = owner.climate.exposure(cell)
	return Vector3(owner.climate.mean_c(float(cell.y)) + warmth_at(cell), float(place.season_share), float(place.air_share))
