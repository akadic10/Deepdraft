extends RefCounted

## Leisure policy only. Work routes and doorway navigation remain unrestricted.
var _queue: Array[Vector3i] = []
var _parents: Dictionary = {}
var _cursor := 0
var _route: Array[Vector3i] = []
var _room_id := -1
var _revision := -1
var _retry := 0.0

static func allowed(cell: Vector3i, dwarf_id: int, sleeping := false) -> bool:
	var room := RoomManager.get_room_at(cell+Vector3i.UP)
	if room.get("room_type","")=="personal_bedroom": return int(room.owner_id)==dwarf_id
	return sleeping or room.get("room_type","")!="bedroom"

static func segment(from: Vector3i, to: Vector3i, dwarf_id: int, sleeping := false) -> bool:
	var steps := maxi(1,ceili(Vector3(to-from).length()*4.0))
	for i in range(steps+1):
		var point := Vector3(from).lerp(Vector3(to),float(i)/steps)+Vector3(.5,0,.5)
		if not allowed(Vector3i(floori(point.x),roundi(point.y),floori(point.z)),dwarf_id,sleeping): return false
	return true

func reset() -> void:
	_queue = []
	_parents.clear()
	_route = []
	_cursor = 0
	_room_id = -1
	_retry = 0.0

## Incremental search to the nearest public floor. Follow checked adjacent
## segments so string pulling cannot turn the exit into a bedroom shortcut.
func leave(agent: DwarfAgent, delta: float, sleeping := false) -> bool:
	var here := agent.current_cell()
	if agent.is_walking():
		agent._follow_path(delta)
		return true
	if allowed(here,agent.dwarf_id,sleeping) and not RoomManager._door_cells.has(here):
		reset()
		return false
	var room_id := RoomManager.get_room_id_at(here+Vector3i.UP)
	if _revision!=NavGrid.navigation_revision or (_room_id!=room_id and room_id>=0): reset()
	_revision = NavGrid.navigation_revision
	if not _route.is_empty():
		var next: Vector3i = _route.pop_front()
		if NavGrid.line_walkable_flat_from(agent.global_position,next): agent.walk_nearby(next)
		else: reset()
		return true
	_retry -= delta
	if _retry>0: return true
	if _queue.is_empty():
		_room_id = room_id
		_queue = [here]
		_parents = {here:here}
		_cursor = 0
	for n in range(64):
		if _cursor>=_queue.size() or _cursor>=4096:
			_queue = []
			_retry = 2.0
			return true
		var cell := _queue[_cursor]
		_cursor += 1
		if allowed(cell,agent.dwarf_id,sleeping) and not RoomManager._door_cells.has(cell):
			while cell!=here:
				_route.push_front(cell)
				cell = _parents[cell]
			return true
		for offset: Vector3i in [Vector3i.LEFT,Vector3i.RIGHT,Vector3i.FORWARD,Vector3i.BACK]:
			var next := cell+offset
			if _parents.has(next): continue
			var next_room := RoomManager.get_room_id_at(next+Vector3i.UP)
			if next_room>=0 and next_room!=_room_id and not allowed(next,agent.dwarf_id,sleeping): continue
			if not NavGrid.line_walkable_flat(cell,next): continue
			_parents[next] = cell
			_queue.append(next)
	return true
